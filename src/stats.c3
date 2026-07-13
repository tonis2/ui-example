module dashboard;
import std::math;

struct SystemStats
{
	float cpu; // 0..1 — system-wide CPU busy fraction since the last sample
	float mem; // 0..1 — memory used (app + wired + compressed) / total RAM
	float disk; // 0..1 — data volume used / capacity
}

module dashboard @if(env::DARWIN);
import std::math;

alias MachPort = uint;

extern fn MachPort mach_host_self();
extern fn CInt host_statistics(MachPort host, CInt flavor, uint* info, uint* count);
extern fn CInt host_statistics64(MachPort host, CInt flavor, uint* info, uint* count);
extern fn CInt sysctlbyname(ZString name, void* oldp, usz* oldlenp, void* newp, usz newlen);
extern fn CInt statvfs(ZString path, Statvfs* buf);

const CInt HOST_CPU_LOAD_INFO = 3; // host_info.h; info = uint[4] ticks
const CInt HOST_VM_INFO64     = 4; // host_info.h; info = VmStatistics64
const uint HOST_VM_INFO64_COUNT = 38; // sizeof(vm_statistics64) / sizeof(integer_t)

// cpu_ticks indices
const usz CPU_USER   = 0;
const usz CPU_SYSTEM = 1;
const usz CPU_IDLE   = 2;
const usz CPU_NICE   = 3;

// mach/vm_statistics.h vm_statistics64 — field-for-field, so the mach call
// can fill it directly.
struct VmStatistics64
{
	uint free_count;
	uint active_count;
	uint inactive_count;
	uint wire_count;
	ulong zero_fill_count;
	ulong reactivations;
	ulong pageins;
	ulong pageouts;
	ulong faults;
	ulong cow_faults;
	ulong lookups;
	ulong hits;
	ulong purges;
	uint purgeable_count;
	uint speculative_count;
	ulong decompressions;
	ulong compressions;
	ulong swapins;
	ulong swapouts;
	uint compressor_page_count;
	uint throttled_count;
	uint external_page_count;
	uint internal_page_count;
	ulong total_uncompressed_pages_in_compressor;
}

// sys/statvfs.h — on darwin fsblkcnt_t/fsfilcnt_t are unsigned int.
struct Statvfs
{
	ulong f_bsize;
	ulong f_frsize;
	uint f_blocks;
	uint f_bfree;
	uint f_bavail;
	uint f_files;
	uint f_ffree;
	uint f_favail;
	ulong f_fsid;
	ulong f_flag;
	ulong f_namemax;
}

struct CpuTicks
{
	ulong busy;
	ulong total;
}

CpuTicks cpu_prev @private;

fn CpuTicks read_cpu_ticks() @private
{
	uint[4] ticks;
	uint count = 4;
	if (host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, &ticks[0], &count) != 0) return {};
	ulong busy = (ulong)ticks[CPU_USER] + ticks[CPU_SYSTEM] + ticks[CPU_NICE];
	return { .busy = busy, .total = busy + ticks[CPU_IDLE] };
}

<*
 Seeds the CPU tick baseline; call once before the first sample_stats.
*>
fn void stats_prime()
{
	cpu_prev = read_cpu_ticks();
}

fn float sample_cpu() @private
{
	CpuTicks now = read_cpu_ticks();
	ulong busy   = now.busy - cpu_prev.busy;
	ulong total  = now.total - cpu_prev.total;
	cpu_prev     = now;
	if (total == 0) return 0;
	return (float)busy / (float)total;
}

fn float sample_mem() @private
{
	VmStatistics64 vm;
	uint count = HOST_VM_INFO64_COUNT;
	if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (uint*)&vm, &count) != 0) return 0;

	ulong memsize;
	usz len = 8;
	if (sysctlbyname("hw.memsize", &memsize, &len, null, 0) != 0 || memsize == 0) return 0;
	ulong page = 0;
	len = 8;
	if (sysctlbyname("hw.pagesize", &page, &len, null, 0) != 0 || page == 0) return 0;

	// Activity Monitor's "Memory Used": app memory (internal minus
	// purgeable) + wired + compressed.
	ulong used = ((ulong)vm.internal_page_count - vm.purgeable_count
		+ vm.wire_count + vm.compressor_page_count) * page;
	return math::clamp((float)used / (float)memsize, 0.0f, 1.0f);
}

fn float sample_disk() @private
{
	// The data volume is where user data lives; plain "/" is the small
	// read-only system volume on modern macOS.
	Statvfs s;
	if (statvfs("/System/Volumes/Data", &s) != 0 && statvfs("/", &s) != 0) return 0;
	ulong used  = (ulong)s.f_blocks - s.f_bfree;
	ulong total = used + s.f_bavail; // like df's use%: used / (used + avail)
	if (total == 0) return 0;
	return math::clamp((float)used / (float)total, 0.0f, 1.0f);
}

fn SystemStats sample_stats()
{
	return { .cpu = sample_cpu(), .mem = sample_mem(), .disk = sample_disk() };
}

module dashboard @if(env::LINUX);
import std::io;
import std::math;

// Linux samplers, mirroring the macOS ones above: CPU and memory are parsed
// straight out of procfs, the disk from a statvfs() call.

extern fn CInt statvfs(ZString path, StatvfsLinux* buf);

// sys/statvfs.h (glibc, 64-bit). Only the first five fields are read; the
// trailing layout varies across glibc versions, so the generous padding
// guarantees the real struct always fits and statvfs never writes past us.
struct StatvfsLinux
{
	ulong f_bsize;
	ulong f_frsize;
	ulong f_blocks; // total data blocks, in f_frsize units
	ulong f_bfree; // free blocks
	ulong f_bavail; // free blocks available to unprivileged users
	ulong[16] _tail;
}

struct CpuTicks @private
{
	ulong busy;
	ulong total;
}

CpuTicks cpu_prev @private;

// Reads a small procfs file into `buffer`, returning the filled slice (empty
// on error). procfs reports size 0, so file::load_buffer is useless here; a
// single read is enough — the fields we need sit in the first few lines.
fn char[] read_proc(String path, char[] buffer) @private
{
	File? f = file::open(path, "rb");
	if (catch f) return {};
	defer (void)f.close();
	sz n = f.read(buffer) ?? 0;
	return buffer[:n];
}

fn CpuTicks read_cpu_ticks() @private
{
	char[512] buf;
	// The aggregate "cpu" line: label then user nice system idle iowait irq
	// softirq steal (guest/guest_nice follow but are already folded into
	// user/nice, so we stop at the first eight to avoid double-counting).
	Splitter it = ((String)read_proc("/proc/stat", &buf)).tokenize("\n");
	String? first = it.next();
	if (catch first) return {};
	Splitter fields = first.tokenize(" ");
	if (catch fields.next()) return {}; // skip the "cpu" label
	ulong total = 0;
	ulong idle  = 0;
	usz idx = 0;
	while (try tok = fields.next())
	{
		if (idx >= 8) break;
		ulong v = tok.to_ulong() ?? 0;
		total += v;
		if (idx == 3 || idx == 4) idle += v; // idle + iowait
		idx++;
	}
	return { .busy = total - idle, .total = total };
}

<*
 Seeds the CPU tick baseline; call once before the first sample_stats.
*>
fn void stats_prime()
{
	cpu_prev = read_cpu_ticks();
}

fn float sample_cpu() @private
{
	CpuTicks now = read_cpu_ticks();
	ulong busy  = now.busy - cpu_prev.busy;
	ulong total = now.total - cpu_prev.total;
	cpu_prev    = now;
	if (total == 0) return 0;
	return (float)busy / (float)total;
}

fn ulong parse_meminfo_kb(String line) @private
{
	// e.g. "MemTotal:       16333764 kB" — the value is the second token.
	Splitter it = line.tokenize(" ");
	if (catch it.next()) return 0; // skip the label
	String? num = it.next();
	if (catch num) return 0;
	return num.to_ulong() ?? 0;
}

fn float sample_mem() @private
{
	char[2048] buf;
	String info = (String)read_proc("/proc/meminfo", &buf);
	ulong total = 0;
	ulong avail = 0;
	Splitter lines = info.tokenize("\n");
	while (try line = lines.next())
	{
		if (line.starts_with("MemTotal:"))
		{
			total = parse_meminfo_kb(line);
		}
		else if (line.starts_with("MemAvailable:"))
		{
			avail = parse_meminfo_kb(line);
		}
	}
	if (total == 0) return 0;
	// MemAvailable is the kernel's estimate of memory free for new work; the
	// remainder is "used" the way a user perceives it (reclaimable cache aside).
	ulong used = total > avail ? total - avail : 0;
	return math::clamp((float)used / (float)total, 0.0f, 1.0f);
}

fn float sample_disk() @private
{
	// Prefer /var: it always exists and holds user data. On a normal distro
	// it lives on the root filesystem (so this equals /); on atomic/immutable
	// systems (ostree, bootc) "/" is a tiny read-only composefs and /var is
	// the real writable partition. Fall back to / if /var is unavailable.
	// Block size cancels out of the ratio, like df's use%.
	StatvfsLinux s;
	if (statvfs("/var", &s) != 0 && statvfs("/", &s) != 0) return 0;
	ulong used  = (ulong)s.f_blocks - s.f_bfree;
	ulong total = used + s.f_bavail;
	if (total == 0) return 0;
	return math::clamp((float)used / (float)total, 0.0f, 1.0f);
}

fn SystemStats sample_stats()
{
	return { .cpu = sample_cpu(), .mem = sample_mem(), .disk = sample_disk() };
}

module dashboard @if(!env::DARWIN && !env::LINUX);
import std::math;

// Simulated fallback where the samplers aren't ported: values drift so the
// dashboard still moves.

float sim_t @private = 0.37f;

fn void stats_prime()
{
}

fn SystemStats sample_stats()
{
	sim_t += 0.13f;
	return {
		.cpu = 0.5f + 0.45f * math::sin(sim_t),
		.mem = 0.6f + 0.30f * math::sin(sim_t * 0.6f + 1.7f),
		.disk = 0.55f,
	};
}
