module dashboard;
import std::math;

// Real system statistics. On macOS these are plain libSystem calls (Mach
// host statistics + sysctl + statvfs) declared as externs — no extra
// libraries to link. Other platforms get a simulated fallback below, so
// the example still builds and runs everywhere the library does.

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

module dashboard @if(!env::DARWIN);
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
