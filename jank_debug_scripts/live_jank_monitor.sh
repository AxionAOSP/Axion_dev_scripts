#!/bin/bash
#
# Live jank monitoring — watches for frame drops in real-time via dumpsys
#
# Usage:
#   ./live_jank_monitor.sh [package_name]
#
# Examples:
#   ./live_jank_monitor.sh com.android.settings
#   ./live_jank_monitor.sh   # monitors all gfx info

PACKAGE="${1:-}"

if ! adb devices 2>/dev/null | grep -q "device$"; then
    echo "ERROR: No device connected"
    exit 1
fi

echo ""
echo "Live Jank Monitor"
echo "=================="
if [ -n "$PACKAGE" ]; then
    echo "Monitoring: $PACKAGE"
else
    echo "Monitoring: all apps (specify package for focused view)"
fi
echo "Press Ctrl+C to stop"
echo ""

if [ -n "$PACKAGE" ]; then
    adb shell dumpsys gfxinfo "$PACKAGE" reset > /dev/null 2>&1
fi

while true; do
    sleep 2

    if [ -n "$PACKAGE" ]; then
        OUTPUT=$(adb shell dumpsys gfxinfo "$PACKAGE" 2>/dev/null)
    else
        OUTPUT=$(adb shell dumpsys gfxinfo 2>/dev/null)
    fi

    JANKY=$(echo "$OUTPUT" | grep "Janky frames:" | head -1)
    TOTAL=$(echo "$OUTPUT" | grep "Total frames rendered:" | head -1)
    PERCENTILE=$(echo "$OUTPUT" | grep "50th percentile:" | head -1)
    P90=$(echo "$OUTPUT" | grep "90th percentile:" | head -1)
    P95=$(echo "$OUTPUT" | grep "95th percentile:" | head -1)
    P99=$(echo "$OUTPUT" | grep "99th percentile:" | head -1)
    MISSED=$(echo "$OUTPUT" | grep "Number Missed Vsync:" | head -1)
    SLOW_UI=$(echo "$OUTPUT" | grep "Number Slow UI thread:" | head -1)
    SLOW_BMP=$(echo "$OUTPUT" | grep "Number Slow bitmap uploads:" | head -1)
    SLOW_ISSUE=$(echo "$OUTPUT" | grep "Number Slow issue draw commands:" | head -1)

    TIMESTAMP=$(date +%H:%M:%S)

    if [ -n "$JANKY" ]; then
        echo "[$TIMESTAMP] $TOTAL | $JANKY"
        echo "           $PERCENTILE | $P90 | $P95 | $P99"
        echo "           $MISSED | $SLOW_UI"
        [ -n "$SLOW_BMP" ] && echo "           $SLOW_BMP | $SLOW_ISSUE"
        echo ""
    fi
done
