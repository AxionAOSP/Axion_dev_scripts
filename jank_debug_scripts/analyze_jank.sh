#!/bin/bash
#
# Analyze a Perfetto trace for jank — outputs a summary report
#
# Usage:
#   ./analyze_jank.sh <trace_file> [package_name]
#
# Examples:
#   ./analyze_jank.sh traces/jank_trace.perfetto-trace
#   ./analyze_jank.sh traces/jank_trace.perfetto-trace com.android.settings

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

echo ""
echo "============================================"
echo "  Jank Analysis Report"
echo "  Trace: $(basename "$TRACE_FILE")"
echo "============================================"
echo ""

# 1. List all janky frames
echo "--- JANKY FRAMES (sorted by duration) ---"
echo ""
JANK_QUERY="
SELECT
    a.name as frame_id,
    a.dur / 1000000 as dur_ms,
    a.jank_type,
    a.jank_tag,
    p.name as process
FROM actual_frame_timeline_slice a
JOIN process_track pt ON a.track_id = pt.id
JOIN process p ON pt.upid = p.upid
WHERE a.jank_type != 'None'
  AND a.jank_type != 'Buffer Stuffing'
"
if [ -n "$PACKAGE" ]; then
    JANK_QUERY="$JANK_QUERY AND p.name LIKE '%${PACKAGE}%'"
fi
JANK_QUERY="$JANK_QUERY ORDER BY a.dur DESC LIMIT 30"
query "$JANK_QUERY"

echo ""
echo "--- JANK SUMMARY BY TYPE ---"
echo ""
SUMMARY_QUERY="
SELECT
    jank_type,
    COUNT(*) as count,
    SUM(dur) / 1000000 as total_ms,
    AVG(dur) / 1000000 as avg_ms,
    MAX(dur) / 1000000 as max_ms
FROM actual_frame_timeline_slice
WHERE jank_type != 'None'
GROUP BY jank_type
ORDER BY total_ms DESC
"
query "$SUMMARY_QUERY"

echo ""
echo "--- JANK SUMMARY BY PROCESS ---"
echo ""
PROC_QUERY="
SELECT
    p.name as process,
    COUNT(*) as janky_frames,
    SUM(a.dur) / 1000000 as total_jank_ms,
    MAX(a.dur) / 1000000 as worst_frame_ms
FROM actual_frame_timeline_slice a
JOIN process_track pt ON a.track_id = pt.id
JOIN process p ON pt.upid = p.upid
WHERE a.jank_type != 'None'
  AND a.jank_type != 'Buffer Stuffing'
GROUP BY p.name
ORDER BY total_jank_ms DESC
LIMIT 15
"
query "$PROC_QUERY"

# 2. Long slices on main threads
echo ""
echo "--- LONG MAIN THREAD OPERATIONS (>5ms) ---"
echo ""
LONG_QUERY="
SELECT
    p.name as process,
    s.dur / 1000000 as dur_ms,
    REPLACE(s.name, CHAR(10), ' ') as operation
FROM slice s
JOIN thread_track tt ON s.track_id = tt.id
JOIN thread t ON tt.utid = t.utid
JOIN process p ON t.upid = p.upid
WHERE t.is_main_thread = 1
  AND s.dur > 5000000
  AND s.depth = 0
  AND s.name NOT IN ('VSYNC-app', 'VSYNC-sf')
"
if [ -n "$PACKAGE" ]; then
    LONG_QUERY="$LONG_QUERY AND p.name LIKE '%${PACKAGE}%'"
fi
LONG_QUERY="$LONG_QUERY ORDER BY s.dur DESC LIMIT 25"
query "$LONG_QUERY"

# 3. Binder transactions > 3ms
echo ""
echo "--- SLOW BINDER TRANSACTIONS (>3ms) ---"
echo ""
BINDER_QUERY="
SELECT
    p.name as caller_process,
    s.dur / 1000000 as dur_ms,
    s.name
FROM slice s
JOIN thread_track tt ON s.track_id = tt.id
JOIN thread t ON tt.utid = t.utid
JOIN process p ON t.upid = p.upid
WHERE t.is_main_thread = 1
  AND s.name = 'binder transaction'
  AND s.dur > 3000000
"
if [ -n "$PACKAGE" ]; then
    BINDER_QUERY="$BINDER_QUERY AND p.name LIKE '%${PACKAGE}%'"
fi
BINDER_QUERY="$BINDER_QUERY ORDER BY s.dur DESC LIMIT 20"
query "$BINDER_QUERY"

# 4. RenderThread waits
echo ""
echo "--- RENDERTHREAD BUFFER WAITS (>2ms) ---"
echo ""
RT_QUERY="
SELECT
    p.name as process,
    s.dur / 1000000.0 as dur_ms,
    s.name as operation
FROM slice s
JOIN thread_track tt ON s.track_id = tt.id
JOIN thread t ON tt.utid = t.utid
JOIN process p ON t.upid = p.upid
WHERE t.name LIKE 'RenderThread%'
  AND s.dur > 2000000
  AND (s.name LIKE '%dequeue%' OR s.name LIKE '%waitFor%' OR s.name LIKE '%queueBuffer%'
       OR s.name LIKE '%postAndWait%' OR s.name LIKE '%Vulkan%' OR s.name LIKE '%flush%')
"
if [ -n "$PACKAGE" ]; then
    RT_QUERY="$RT_QUERY AND p.name LIKE '%${PACKAGE}%'"
fi
RT_QUERY="$RT_QUERY ORDER BY s.dur DESC LIMIT 20"
query "$RT_QUERY"

# 5. GC events during trace
echo ""
echo "--- GC EVENTS ---"
echo ""
GC_QUERY="
SELECT
    p.name as process,
    COUNT(*) as gc_count,
    SUM(s.dur) / 1000000 as total_gc_ms,
    MAX(s.dur) / 1000000 as worst_gc_ms
FROM slice s
JOIN thread_track tt ON s.track_id = tt.id
JOIN thread t ON tt.utid = t.utid
JOIN process p ON t.upid = p.upid
WHERE (s.name LIKE '%GC%' OR s.name LIKE '%concurrent copying%' OR s.name LIKE '%young%')
  AND s.dur > 100000
GROUP BY p.name
ORDER BY total_gc_ms DESC
LIMIT 10
"
query "$GC_QUERY"

echo ""
echo "============================================"
echo "  Analysis complete"
echo "============================================"
echo ""
echo "Next steps:"
echo "  - Open trace in https://ui.perfetto.dev for visual inspection"
echo "  - Look at the Expected/Actual Timeline rows for the janky process"
echo "  - Click red/yellow frames to see jank_type details"
echo "  - Check main thread for binder calls, GC, or layout inflation during animation"
echo "  - Check RenderThread for dequeueBuffer/waitForBuffer (buffer stuffing)"
echo ""
