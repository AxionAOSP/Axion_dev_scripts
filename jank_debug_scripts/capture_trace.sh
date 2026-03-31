#!/bin/bash
#
# Capture a Perfetto trace for jank debugging
#
# Usage:
#   ./capture_trace.sh [duration_seconds] [output_name]
#
# Examples:
#   ./capture_trace.sh              # 8s trace, default name
#   ./capture_trace.sh 15           # 15s trace
#   ./capture_trace.sh 10 settings  # 10s trace named "settings"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DURATION=${1:-8}
NAME=${2:-jank_trace}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${SCRIPT_DIR}/traces/${NAME}_${TIMESTAMP}.perfetto-trace"
DEVICE_CONFIG="/data/local/tmp/trace_config.pbtx"
DEVICE_TRACE="/data/misc/perfetto-traces/${NAME}_${TIMESTAMP}.perfetto-trace"

mkdir -p "${SCRIPT_DIR}/traces"

if ! adb devices 2>/dev/null | grep -q "device$"; then
    echo "ERROR: No device connected"
    exit 1
fi

sed "s/duration_ms: 8000/duration_ms: $((DURATION * 1000))/" \
    "${SCRIPT_DIR}/trace_config.pbtx" > /tmp/_trace_config_tmp.pbtx

adb push /tmp/_trace_config_tmp.pbtx "$DEVICE_CONFIG" 2>/dev/null

echo ""
echo "====================================="
echo "  Perfetto Trace Capture"
echo "====================================="
echo "  Duration : ${DURATION}s"
echo "  Output   : ${OUTPUT_FILE}"
echo "====================================="
echo ""
echo ">>> Starting in 3 seconds — reproduce the jank now! <<<"
echo ""
sleep 3

adb shell "cat ${DEVICE_CONFIG} | perfetto --txt -c - -o ${DEVICE_TRACE}" 2>&1 | \
    grep -v "Warning: No PTY"

echo ""
echo "Pulling trace..."
adb pull "$DEVICE_TRACE" "$OUTPUT_FILE" 2>&1 | tail -1

echo ""
echo "Trace saved to: ${OUTPUT_FILE}"
echo ""
echo "To analyze:"
echo "  1. Open https://ui.perfetto.dev and load the trace file"
echo "  2. Or run: ./analyze_jank.sh ${OUTPUT_FILE}"
echo ""
