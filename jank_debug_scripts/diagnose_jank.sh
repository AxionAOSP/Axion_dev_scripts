#!/bin/bash
#
# Human-readable jank diagnosis — shows WHAT caused jank and WHO blocked the main thread
#
# Usage:
#   ./diagnose_jank.sh <trace_file> [package_name]
#
# Examples:
#   ./diagnose_jank.sh traces/jank_trace.perfetto-trace
#   ./diagnose_jank.sh traces/jank_trace.perfetto-trace com.android.settings

TRACE_PROCESSOR="${HOME}/.local/share/perfetto/prebuilts/trace_processor_shell"
TRACE_FILE="$1"
PACKAGE="${2:-}"

if [ -z "$TRACE_FILE" ]; then
    echo "Usage: $0 <trace_file> [package_name]"
    exit 1
fi

if [ ! -f "$TRACE_FILE" ]; then
    echo "ERROR: File not found: $TRACE_FILE"
    exit 1
fi

if [ ! -f "$TRACE_PROCESSOR" ]; then
    echo "trace_processor_shell not found. Install with: pip3 install perfetto"
    exit 1
fi

query() {
    "$TRACE_PROCESSOR" "$TRACE_FILE" -q /dev/stdin <<< "$1" 2>/dev/null | tail -n +2
}

PACKAGE_FILTER=""
if [ -n "$PACKAGE" ]; then
    PACKAGE_FILTER="AND p.name LIKE '%${PACKAGE}%'"
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║           JANK DIAGNOSIS REPORT                     ║"
echo "║  Trace: $(basename "$TRACE_FILE")"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Section 1: Quick overview ──
echo "┌─────────────────────────────────────────────────────┐"
echo "│  1. OVERVIEW — How bad is the jank?                 │"
echo "└─────────────────────────────────────────────────────┘"
echo ""
query "
SELECT
    p.name as app,
    COUNT(*) as janky_frames,
    CAST(MAX(a.dur) / 1000000 AS INT) || 'ms' as worst_frame,
    CAST(AVG(a.dur) / 1000000 AS INT) || 'ms' as avg_janky_frame,
    CAST(SUM(a.dur) / 1000000 AS INT) || 'ms' as total_jank_time
FROM actual_frame_timeline_slice a
JOIN process_track pt ON a.track_id = pt.id
JOIN process p ON pt.upid = p.upid
WHERE a.jank_type != 'None'
  AND a.jank_type != 'Buffer Stuffing'
  ${PACKAGE_FILTER}
GROUP BY p.name
ORDER BY SUM(a.dur) DESC
LIMIT 10
"

# ── Section 2: Root causes ──
echo ""
echo "┌─────────────────────────────────────────────────────┐"
echo "│  2. ROOT CAUSES — Why did frames drop?              │"
echo "└─────────────────────────────────────────────────────┘"
echo ""
echo "  Jank types explained:"
echo "    App Deadline Missed    = app took too long to draw a frame"
echo "    SurfaceFlinger Missed  = compositor couldn't present on time"
echo "    Buffer Stuffing        = app queued frames faster than display consumed"
echo "    Display HAL            = display hardware was slow"
echo ""
query "
SELECT
    a.jank_type as cause,
    COUNT(*) as occurrences,
    CAST(AVG(a.dur) / 1000000 AS INT) || 'ms' as avg_duration,
    CAST(MAX(a.dur) / 1000000 AS INT) || 'ms' as worst_duration
FROM actual_frame_timeline_slice a
JOIN process_track pt ON a.track_id = pt.id
JOIN process p ON pt.upid = p.upid
WHERE a.jank_type != 'None'
  ${PACKAGE_FILTER}
GROUP BY a.jank_type
ORDER BY COUNT(*) DESC
"

# ── Section 3: What blocked the main thread ──
echo ""
echo "┌─────────────────────────────────────────────────────┐"
echo "│  3. MAIN THREAD BLOCKERS — What stalled the UI?     │"
echo "└─────────────────────────────────────────────────────┘"
echo ""
echo "  These operations ran on the main thread and took >5ms:"
echo "  (The main thread must be free to measure/layout/draw every frame)"
echo ""
query "
SELECT
    p.name as app,
    CAST(s.dur / 1000000 AS INT) || 'ms' as duration,
    CASE
        WHEN s.name = 'binder transaction' THEN 'BINDER CALL — main thread blocked waiting on system_server'
        WHEN s.name = 'postAndWait' THEN 'RENDER WAIT — main thread blocked waiting for RenderThread (buffer full)'
        WHEN s.name LIKE 'dispatchInputEvent%' THEN 'INPUT HANDLING — ' || s.name
        WHEN s.name LIKE 'inflation%' OR s.name LIKE 'inflate%' THEN 'LAYOUT INFLATE — ' || s.name
        WHEN s.name LIKE '%GC%' OR s.name LIKE '%concurrent%' THEN 'GARBAGE COLLECTION — ' || s.name
        WHEN s.name LIKE 'measure%' OR s.name LIKE 'layout%' THEN 'MEASURE/LAYOUT — ' || s.name
        WHEN s.name LIKE 'draw%' OR s.name LIKE 'Draw%' THEN 'DRAWING — ' || s.name
        WHEN s.name LIKE '%ContentProvider%' OR s.name LIKE '%query%' THEN 'DATABASE/PROVIDER QUERY — ' || s.name
        WHEN s.name LIKE '%lock%' OR s.name LIKE '%contention%' THEN 'LOCK CONTENTION — ' || s.name
        WHEN s.name LIKE 'Choreographer%' THEN 'CHOREOGRAPHER — ' || s.name
        WHEN s.name LIKE '%SharedPreferences%' THEN 'DISK I/O (SharedPrefs) — ' || s.name
        ELSE s.name
    END as what_blocked
FROM slice s
JOIN thread_track tt ON s.track_id = tt.id
JOIN thread t ON tt.utid = t.utid
JOIN process p ON t.upid = p.upid
WHERE t.is_main_thread = 1
  AND s.dur > 5000000
  AND s.depth <= 1
  AND s.name NOT IN ('VSYNC-app', 'VSYNC-sf', 'Looper.dispatch: Handler (android.app.ActivityThread\$H) {', 'activityStart', 'activityResume')
  ${PACKAGE_FILTER}
ORDER BY s.dur DESC
LIMIT 30
"

# ── Section 4: Binder call details ──
echo ""
echo "┌─────────────────────────────────────────────────────┐"
echo "│  4. SLOW BINDER CALLS — Who is system_server slow   │"
echo "│     responding to?                                  │"
echo "└─────────────────────────────────────────────────────┘"
echo ""
echo "  Binder calls are IPC to system_server. When slow, they block the UI."
echo "  Common culprits: WM lock contention, surface creation, activity start."
echo ""
query "
SELECT
    p.name as caller_app,
    CAST(s.dur / 1000000.0 AS TEXT) || 'ms' as blocked_for,
    CASE
        WHEN s.dur > 15000000 THEN '*** CRITICAL — likely WM lock or activity start ***'
        WHEN s.dur > 8000000 THEN '** HIGH — may cause visible jank **'
        WHEN s.dur > 3000000 THEN '* MODERATE — contributes to frame drops *'
        ELSE 'low'
    END as severity
FROM slice s
JOIN thread_track tt ON s.track_id = tt.id
JOIN thread t ON tt.utid = t.utid
JOIN process p ON t.upid = p.upid
WHERE t.is_main_thread = 1
  AND s.name = 'binder transaction'
  AND s.dur > 3000000
  ${PACKAGE_FILTER}
ORDER BY s.dur DESC
LIMIT 20
"

# ── Section 5: System_server work during binder calls ──
echo ""
echo "┌─────────────────────────────────────────────────────┐"
echo "│  5. SYSTEM_SERVER — What was it doing when slow?    │"
echo "└─────────────────────────────────────────────────────┘"
echo ""
echo "  This shows what system_server binder threads were working on"
echo "  when they took >3ms to reply. Helps identify WM/AM bottlenecks."
echo ""
query "
SELECT
    CAST(s.dur / 1000000.0 AS TEXT) || 'ms' as reply_dur,
    t.name as server_thread,
    CASE
        WHEN child.name LIKE '%createSurface%' THEN 'Creating window surface (WM transition)'
        WHEN child.name LIKE '%setMode%' OR child.name LIKE '%IPower%' THEN 'Power HAL mode change'
        WHEN child.name LIKE '%WindowInfos%' THEN 'Window info update to input/accessibility'
        WHEN child.name LIKE '%relayoutWindow%' THEN 'Window relayout'
        WHEN child.name LIKE '%addWindow%' THEN 'Adding new window'
        WHEN child.name LIKE '%removeWindow%' THEN 'Removing window'
        WHEN child.name LIKE '%Transition%' THEN 'WM Shell transition'
        WHEN child.name LIKE '%startActivity%' THEN 'Starting activity'
        WHEN child.name LIKE '%resolveIntent%' OR child.name LIKE '%resolveActivity%' THEN 'Resolving intent/activity'
        WHEN child.name IS NOT NULL THEN child.name
        ELSE '(untraced CPU work — likely WM lock held or ActivityStarter)'
    END as server_work
FROM slice s
JOIN thread_track tt ON s.track_id = tt.id
JOIN thread t ON tt.utid = t.utid
JOIN process p ON t.upid = p.upid
LEFT JOIN slice child ON child.track_id = s.track_id
    AND child.ts > s.ts AND child.ts < s.ts + s.dur
    AND child.depth = s.depth + 1
    AND child.dur > 50000
WHERE p.pid = (SELECT pid FROM process WHERE name = 'system_server' LIMIT 1)
  AND s.name = 'binder reply'
  AND s.dur > 3000000
GROUP BY s.ts
ORDER BY s.dur DESC
LIMIT 20
"

# ── Section 6: RenderThread issues ──
echo ""
echo "┌─────────────────────────────────────────────────────┐"
echo "│  6. RENDERTHREAD — Buffer/GPU bottlenecks           │"
echo "└─────────────────────────────────────────────────────┘"
echo ""
echo "  RenderThread handles GPU drawing. When it's slow, postAndWait blocks."
echo "  dequeueBuffer wait = buffer queue full (buffer stuffing)"
echo "  GPU completion wait = GPU is behind"
echo ""
query "
SELECT
    p.name as app,
    CAST(s.dur / 1000000.0 AS TEXT) || 'ms' as duration,
    s.name as operation,
    CASE
        WHEN s.name LIKE '%dequeue%' OR s.name LIKE '%waitForBuffer%' THEN 'BUFFER FULL — all buffer slots queued, waiting for SF to consume'
        WHEN s.name LIKE '%GPU%' OR s.name LIKE '%waiting for GPU%' THEN 'GPU BEHIND — GPU hasn''t finished previous frame'
        WHEN s.name LIKE '%flush%' THEN 'GPU COMMAND FLUSH — sending draw commands to GPU'
        WHEN s.name LIKE '%Vulkan%' THEN 'VULKAN SUBMIT — submitting work to GPU'
        WHEN s.name LIKE '%queueBuffer%' THEN 'QUEUE BUFFER — handing buffer to SurfaceFlinger'
        ELSE ''
    END as explanation
FROM slice s
JOIN thread_track tt ON s.track_id = tt.id
JOIN thread t ON tt.utid = t.utid
JOIN process p ON t.upid = p.upid
WHERE t.name LIKE 'RenderThread%'
  AND s.dur > 2000000
  AND (s.name LIKE '%dequeue%' OR s.name LIKE '%waitFor%' OR s.name LIKE '%queueBuffer%'
       OR s.name LIKE '%GPU%' OR s.name LIKE '%flush%' OR s.name LIKE '%Vulkan%')
  ${PACKAGE_FILTER}
ORDER BY s.dur DESC
LIMIT 15
"

# ── Section 7: GC during animation ──
echo ""
echo "┌─────────────────────────────────────────────────────┐"
echo "│  7. GARBAGE COLLECTION — GC pauses during animation │"
echo "└─────────────────────────────────────────────────────┘"
echo ""
query "
SELECT
    p.name as app,
    t.name as thread,
    CAST(s.dur / 1000000.0 AS TEXT) || 'ms' as gc_pause,
    s.name as gc_type
FROM slice s
JOIN thread_track tt ON s.track_id = tt.id
JOIN thread t ON tt.utid = t.utid
JOIN process p ON t.upid = p.upid
WHERE (s.name LIKE '%GC%' OR s.name LIKE '%concurrent copying%')
  AND s.dur > 500000
  ${PACKAGE_FILTER}
ORDER BY s.dur DESC
LIMIT 15
"

# ── Section 8: CPU frequency during jank ──
echo ""
echo "┌─────────────────────────────────────────────────────┐"
echo "│  8. CPU STATE — Was the CPU throttled?              │"
echo "└─────────────────────────────────────────────────────┘"
echo ""
echo "  If max frequencies are low, thermal throttling may cause jank."
echo ""
query "
SELECT
    cpu,
    CAST(MIN(value) / 1000 AS INT) || ' MHz' as min_freq,
    CAST(MAX(value) / 1000 AS INT) || ' MHz' as max_freq,
    CAST(AVG(value) / 1000 AS INT) || ' MHz' as avg_freq
FROM counter c
JOIN cpu_counter_track ct ON c.track_id = ct.id
WHERE ct.name = 'cpufreq'
GROUP BY cpu
ORDER BY cpu
"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  DIAGNOSIS COMPLETE                                 ║"
echo "║                                                     ║"
echo "║  Quick interpretation:                              ║"
echo "║  - Section 3 shows WHAT blocked the UI thread       ║"
echo "║  - Section 4 shows slow IPC calls                   ║"
echo "║  - Section 5 shows WHY system_server was slow       ║"
echo "║  - Section 6 shows GPU/buffer bottlenecks           ║"
echo "║  - Section 8 shows if CPU was thermal-throttled     ║"
echo "║                                                     ║"
echo "║  For visual analysis: https://ui.perfetto.dev       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
