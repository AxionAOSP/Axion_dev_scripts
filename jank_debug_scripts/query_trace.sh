#!/bin/bash
#
# Run a custom SQL query against a Perfetto trace
#
# Usage:
#   ./query_trace.sh <trace_file> "<sql_query>"
#
# Examples:
#   ./query_trace.sh traces/jank.perfetto-trace "SELECT * FROM actual_frame_timeline_slice LIMIT 10"
#   ./query_trace.sh traces/jank.perfetto-trace "$(cat my_query.sql)"

TRACE_PROCESSOR="${HOME}/.local/share/perfetto/prebuilts/trace_processor_shell"
TRACE_FILE="$1"
SQL_QUERY="$2"

if [ -z "$TRACE_FILE" ] || [ -z "$SQL_QUERY" ]; then
    echo "Usage: $0 <trace_file> \"<sql_query>\""
    echo ""
    echo "Common queries:"
    echo ""
    echo "  # All janky frames for a process"
    echo "  \"SELECT a.name, a.dur/1000000 as ms, a.jank_type FROM actual_frame_timeline_slice a"
    echo "   JOIN process_track pt ON a.track_id=pt.id JOIN process p ON pt.upid=p.upid"
    echo "   WHERE p.name LIKE '%settings%' AND a.jank_type!='None' ORDER BY a.dur DESC\""
    echo ""
    echo "  # Main thread slices during a time window"
    echo "  \"SELECT s.ts, s.dur/1000000.0 as ms, s.name, s.depth FROM slice s"
    echo "   JOIN thread_track tt ON s.track_id=tt.id JOIN thread t ON tt.utid=t.utid"
    echo "   WHERE t.tid=<PID> AND s.ts>=<START_NS> AND s.ts<=<END_NS> ORDER BY s.ts\""
    echo ""
    echo "  # Thread scheduling state (running/sleeping/blocked)"
    echo "  \"SELECT ts, dur/1000.0 as us, state, blocked_function FROM thread_state"
    echo "   WHERE utid=(SELECT utid FROM thread WHERE tid=<TID> LIMIT 1)"
    echo "   AND ts>=<START> AND ts<=<END> ORDER BY ts\""
    exit 1
fi

if [ ! -f "$TRACE_PROCESSOR" ]; then
    echo "trace_processor_shell not found. Install with: pip3 install perfetto"
    exit 1
fi

"$TRACE_PROCESSOR" "$TRACE_FILE" -q /dev/stdin <<< "$SQL_QUERY" 2>/dev/null
