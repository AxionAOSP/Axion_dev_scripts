# AOSP Jank Debug Scripts

Tools for capturing and analyzing frame drops (jank) on AOSP/Android devices using Perfetto traces.

## Prerequisites

- `adb` connected to device
- `pip3 install perfetto` (installs `trace_processor_shell` for offline analysis)

## Quick Start

```bash
# 1. Capture a trace (8 seconds by default)
./capture_trace.sh

# 2. Get a human-readable diagnosis
./diagnose_jank.sh traces/<trace_file>.perfetto-trace com.android.settings

# 3. For detailed analysis
./analyze_jank.sh traces/<trace_file>.perfetto-trace com.android.settings
```

## Scripts

### `capture_trace.sh` — Capture a Perfetto trace

```bash
./capture_trace.sh                    # 8s trace, default name
./capture_trace.sh 15                 # 15s trace
./capture_trace.sh 10 settings_jank   # 10s trace, custom name
```

Gives you a 3-second countdown, then captures. Reproduce the jank during the capture window.
Traces are saved to `traces/` subfolder.

### `diagnose_jank.sh` — Human-readable jank report

```bash
./diagnose_jank.sh traces/jank.perfetto-trace
./diagnose_jank.sh traces/jank.perfetto-trace com.android.settings
```

Outputs 8 sections:
1. **Overview** — how many janky frames, worst frame duration
2. **Root causes** — jank types (App Deadline Missed, Buffer Stuffing, etc.)
3. **Main thread blockers** — what operations stalled the UI (binder calls, GC, layout, render waits)
4. **Slow binder calls** — IPC calls to system_server that took too long
5. **System_server work** — what system_server was doing during slow binder replies
6. **RenderThread** — buffer/GPU bottlenecks (dequeueBuffer waits, GPU completion)
7. **GC events** — garbage collection pauses during the trace
8. **CPU state** — frequency ranges per core (thermal throttling detection)

### `analyze_jank.sh` — Detailed technical analysis

```bash
./analyze_jank.sh traces/jank.perfetto-trace com.android.settings
```

More granular than `diagnose_jank.sh`. Shows raw frame data, per-process breakdowns, and specific operations.

### `query_trace.sh` — Run custom SQL queries

```bash
./query_trace.sh traces/jank.perfetto-trace "SELECT * FROM actual_frame_timeline_slice LIMIT 10"
```

For ad-hoc investigation. See `quick_queries.sql` for common query templates.

### `live_jank_monitor.sh` — Real-time jank monitoring

```bash
./live_jank_monitor.sh com.android.settings
```

Polls `dumpsys gfxinfo` every 2 seconds and shows frame stats. Useful for spotting jank without full trace capture.

### `quick_queries.sql` — SQL query templates

Common Perfetto SQL queries for jank debugging. Copy-paste into `query_trace.sh` or the Perfetto UI SQL tab.

### `trace_config.pbtx` — Perfetto trace configuration

Pre-configured for jank debugging with: scheduling, CPU frequency, binder, view/wm/am/gfx/hwui tracing, SurfaceFlinger frame timeline, and per-app tracing.

## Visual Analysis (Perfetto UI)

For visual inspection, open traces at https://ui.perfetto.dev

### What to look for:

1. **Find your app's process** — scroll down past CPU/GPU rows
2. **Expected Timeline** — green bars showing when frames should have been presented
3. **Actual Timeline** — colored bars showing when frames were actually presented
   - Green = on time
   - Yellow = slightly late
   - Red = significantly late (jank)
4. **Click a red frame** — see `jank_type`, `present_type`, duration in the details panel

### Key rows to inspect:

| Row | What it shows |
|-----|---------------|
| `main thread` | App's UI thread — look for long binder calls, GC, layout |
| `RenderThread` | GPU drawing — look for `dequeueBuffer` waits, long draws |
| `GPU completion` | GPU work — `waitForGpuCompletion` = GPU is the bottleneck |
| `system_server` binder threads | What system_server does during slow binder replies |

### Common jank causes:

| Jank Type | What it means | Where to look |
|-----------|---------------|---------------|
| App Deadline Missed | App's frame took too long | Main thread for binder/GC/layout |
| Buffer Stuffing | App queued frames faster than display | RenderThread for dequeueBuffer waits |
| SurfaceFlinger Stuffing | SF fell behind presenting | SF process, HWC |
| SurfaceFlinger Deadline Missed | SF missed its deadline | SF main thread |

### Common main thread blockers:

| Blocker | Typical duration | Fix |
|---------|-----------------|-----|
| `binder transaction` (to system_server) | 5-30ms | Async calls, avoid on UI thread |
| `postAndWait` | 10-30ms | Buffer stuffing (secondary symptom) |
| `inflate` | 5-50ms | ViewStub, async inflation, simpler layouts |
| GC (`concurrent copying`) | 2-10ms | Reduce allocations, suppress GC during animation |
| `SharedPreferences` commit | 5-20ms | Use `apply()` not `commit()`, or DataStore |
| `ContentProvider` query | 5-50ms | Move to background thread |
