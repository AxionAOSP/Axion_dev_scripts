#!/bin/bash

echo -e "\033[1;33mWaiting for device...\033[0m"
adb wait-for-device
adb shell getprop sys.boot_completed | grep -q 1 || {
    echo -e "\033[1;33mWaiting for boot to complete...\033[0m"
    while ! adb shell getprop sys.boot_completed 2>/dev/null | grep -q 1; do
        sleep 2
    done
}
echo -e "\033[0;32mDevice ready.\033[0m"

declare -A DEVICES=(
    ["Pixel Fold Outer"]="1080x2092 420"
    ["Pixel Fold Inner"]="1840x2208 420"
    ["Pixel 9 Pro"]="1280x2856 490"
    ["Pixel 9"]="1080x2424 420"
    ["Pixel 8a"]="1080x2400 430"
    ["POCO X6 Pro (duchamp)"]="1220x2712 446"
    ["Samsung S24 Ultra"]="1440x3120 510"
    ["Samsung S24"]="1080x2340 420"
    ["Samsung A52s 5G"]="1080x2400 405"
    ["Samsung A55"]="1080x2340 390"
    ["OnePlus Ace 5"]="1264x2780 450"
    ["OnePlus Nord CE2 Lite"]="1080x2412 401"
    ["OnePlus 12"]="1440x3168 510"
    ["OnePlus 13R"]="1264x2780 450"
    ["Nothing Phone 2"]="1080x2412 420"
    ["Nothing Phone 2a"]="1080x2412 390"
    ["Xiaomi Pad 6"]="1800×2880 400"
    ["Xiaomi 11x Pro"]="1080x2400 440"
    ["Xiaomi 14"]="1200x2670 440"
    ["Redmi Note 12 Pro/Plus/Discovery 5G (rubyx)"]="1080x2400 440"
    ["Redmi Note 13 Pro"]="1220x2712 446"
    ["Tecno Pova LG7n"]="1080x2400 356"
    ["Small Phone (720p)"]="720x1600 320"
    ["Compact (360sw)"]="1080x2400 480"
    ["Tablet 10in"]="1600x2560 320"
    ["Low DPI"]="1080x2400 300"
    ["High DPI"]="1080x2400 560"
)

SORTED_KEYS=(
    "Small Phone (720p)"
    "Low DPI"
    "Compact (360sw)"
    "Samsung A52s 5G"
    "Samsung A55"
    "Nothing Phone 2a"
    "Samsung S24"
    "Pixel Fold Outer"
    "Nothing Phone 2"
    "Pixel 9"
    "Pixel 8a"
    "Xiaomi Pad 6"
    "Xiaomi 14"
    "Xiaomi 11x Pro"
    "POCO X6 Pro (duchamp)"
    "Redmi Note 12 Pro/Plus/Discovery 5G (rubyx)"
    "Redmi Note 13 Pro"
    "Pixel Fold Inner"
    "Pixel 9 Pro"
    "OnePlus Ace 5"
    "OnePlus Nord CE 2 Lite (oscaro)"
    "OnePlus 12"
    "OnePlus 13R"
    "Samsung S24 Ultra"
    "Tecno Pova LG7n"
    "Tablet 10in"
    "High DPI"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCREENSHOT_DIR="${SCRIPT_DIR}/../ui_tests/screenshots"
DEVICE_SCREENSHOT_DIR="/sdcard/ui_tests"
DEVICE_SCREENSHOT_PATH="${DEVICE_SCREENSHOT_DIR}/screenshot.png"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

take_screenshot() {
    local name="$1"
    local res="$2"
    local dpi="$3"
    local w=$(echo "$res" | cut -dx -f1)
    local density=$(echo "scale=4; $dpi / 160" | bc)
    local sw=$(echo "scale=0; $w / $density" | bc)

    mkdir -p "$SCREENSHOT_DIR"

    local safe_name=$(echo "$name" | tr ' ()/' '_' | tr -d "'\"")
    local filename="${safe_name}_${res}_${dpi}dpi_${sw}sw.png"
    local filepath="${SCREENSHOT_DIR}/${filename}"

    adb shell mkdir -p "$DEVICE_SCREENSHOT_DIR"
    adb shell screencap -p "$DEVICE_SCREENSHOT_PATH"
    if adb pull "$DEVICE_SCREENSHOT_PATH" "$filepath" >/dev/null 2>&1; then
        adb shell rm "$DEVICE_SCREENSHOT_PATH"
        echo -e "  ${GREEN}Screenshot saved:${NC} $filename"
    else
        echo -e "  ${RED}Screenshot failed${NC}"
    fi

    echo -e "  ${GREEN}Screenshot:${NC} $filename"
}

show_menu() {
    echo ""
    echo -e "${BOLD}=== Display Emulation Tool ===${NC}"
    echo ""
    printf "  ${CYAN}%-4s${NC} %-25s %-15s %5s  %5s\n" "#" "Device" "Resolution" "DPI" "SW"
    echo "  ----------------------------------------------------------------"

    local i=1
    for key in "${SORTED_KEYS[@]}"; do
        local spec="${DEVICES[$key]}"
        local res=$(echo "$spec" | cut -d' ' -f1)
        local dpi=$(echo "$spec" | cut -d' ' -f2)
        local w=$(echo "$res" | cut -dx -f1)
        local h=$(echo "$res" | cut -dx -f2)
        local density=$(echo "scale=4; $dpi / 160" | bc)
        local sw=$(echo "scale=0; $w / $density" | bc)
        printf "  ${GREEN}%-4s${NC} %-25s %-15s %5s  %3sdp\n" "$i)" "$key" "$res" "$dpi" "$sw"
        i=$((i + 1))
    done

    echo ""
    echo -e "  ${YELLOW}r)${NC}  Reset to device defaults"
    echo -e "  ${YELLOW}c)${NC}  Custom resolution & density"
    echo -e "  ${YELLOW}s)${NC}  Show current display info"
    echo -e "  ${YELLOW}p)${NC}  Screenshot current state"
    echo -e "  ${YELLOW}q)${NC}  Quit"
    echo ""
}

apply_display() {
    local name="$1"
    local res="$2"
    local dpi="$3"
    local w=$(echo "$res" | cut -dx -f1)
    local h=$(echo "$res" | cut -dx -f2)
    local density=$(echo "scale=4; $dpi / 160" | bc)
    local sw=$(echo "scale=0; $w / $density" | bc)

    echo ""
    echo -e "${CYAN}Applying: ${BOLD}$name${NC}"
    echo -e "  Resolution: ${res}"
    echo -e "  DPI: ${dpi}"
    echo -e "  SW: ~${sw}dp"
    echo -e "  Density: ${density}"

    adb shell wm size "$res" 2>/dev/null
    adb shell wm density "$dpi" 2>/dev/null

    echo -e "${GREEN}Applied.${NC} Pull down shade to check."

    if [[ "$AUTO_SCREENSHOT" == "1" ]]; then
        echo -e "  ${YELLOW}Waiting 3s for UI to settle...${NC}"
        sleep 3
        take_screenshot "$name" "$res" "$dpi"
    fi
    echo ""
}

reset_display() {
    echo ""
    echo -e "${YELLOW}Resetting to device defaults...${NC}"
    adb shell wm size reset 2>/dev/null
    adb shell wm density reset 2>/dev/null
    echo -e "${GREEN}Reset complete.${NC}"
    echo ""
}

show_current() {
    echo ""
    echo -e "${CYAN}Current display state:${NC}"
    echo -n "  Size: "
    adb shell wm size 2>/dev/null
    echo -n "  Density: "
    adb shell wm density 2>/dev/null
    echo ""
}

custom_display() {
    echo ""
    read -p "  Width (px): " cw
    read -p "  Height (px): " ch
    read -p "  DPI: " cdpi

    if [[ -n "$cw" && -n "$ch" && -n "$cdpi" ]]; then
        apply_display "Custom (${cw}x${ch} @ ${cdpi}dpi)" "${cw}x${ch}" "$cdpi"
    else
        echo -e "${RED}Invalid input.${NC}"
    fi
}

cycle_all() {
    local delay="${1:-5}"
    echo ""
    echo -e "${BOLD}Cycling through all devices (${delay}s each)...${NC}"
    echo -e "${CYAN}Screenshots enabled → ${SCREENSHOT_DIR}/${NC}"
    echo -e "Press Ctrl+C to stop."
    echo ""

    AUTO_SCREENSHOT="1"
    for key in "${SORTED_KEYS[@]}"; do
        local spec="${DEVICES[$key]}"
        local res=$(echo "$spec" | cut -d' ' -f1)
        local dpi=$(echo "$spec" | cut -d' ' -f2)
        apply_display "$key" "$res" "$dpi"
    done
    AUTO_SCREENSHOT="0"

    echo -e "${YELLOW}Cycle complete. Resetting...${NC}"
    reset_display
}

if [[ "$1" == "--cycle" ]]; then
    cycle_all "${2:-5}"
    exit 0
fi

if [[ "$1" == "--reset" ]]; then
    reset_display
    exit 0
fi

if [[ -n "$1" && -n "$2" && -n "$3" ]]; then
    apply_display "$1" "$2" "$3"
    exit 0
fi

while true; do
    show_menu
    read -p "  Select: " choice

    case "$choice" in
        r|R) reset_display ;;
        c|C) custom_display ;;
        s|S) show_current ;;
        p|P)
            cur_size=$(adb shell wm size 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | tail -1)
            cur_dpi=$(adb shell wm density 2>/dev/null | grep -oE '[0-9]+' | tail -1)
            [[ -z "$cur_size" ]] && cur_size="unknown"
            [[ -z "$cur_dpi" ]] && cur_dpi="unknown"
            take_screenshot "manual" "$cur_size" "$cur_dpi"
            ;;
        q|Q) echo ""; exit 0 ;;
        [0-9]*)
            idx=$((choice - 1))
            if [[ $idx -ge 0 && $idx -lt ${#SORTED_KEYS[@]} ]]; then
                key="${SORTED_KEYS[$idx]}"
                spec="${DEVICES[$key]}"
                res=$(echo "$spec" | cut -d' ' -f1)
                dpi=$(echo "$spec" | cut -d' ' -f2)
                apply_display "$key" "$res" "$dpi"
            else
                echo -e "${RED}Invalid selection.${NC}"
            fi
            ;;
        *) echo -e "${RED}Invalid input.${NC}" ;;
    esac
done
