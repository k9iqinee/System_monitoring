#!/bin/bash

# System Monitor Script
# Version 3.0 - With clean display after dependency check

# Text Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Error handling function
error_exit() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    cleanup
    exit 1
}

# Cleanup function to reset terminal
cleanup() {
    stty echo icanon &>/dev/null
    printf "\033[?25h"  # Show cursor
    printf "\033[0m"    # Reset colors
    clear
}

# Trap interrupts
trap cleanup EXIT INT TERM

# Detect package manager
detect_pkg_manager() {
    if command -v apt &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v zypper &>/dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# Check and install dependencies
check_dependencies() {
    local pkg_manager=$(detect_pkg_manager)
    local packages=()
    local install_cmd=""
    
    case "$pkg_manager" in
        apt)
            packages=("procps" "util-linux" "iproute2")
            install_cmd="sudo apt update && sudo apt install -y"
            ;;
        dnf|yum)
            packages=("procps-ng" "util-linux" "iproute")
            install_cmd="sudo $pkg_manager install -y"
            ;;
        pacman)
            packages=("procps-ng" "util-linux" "iproute2")
            install_cmd="sudo pacman -Sy --noconfirm"
            ;;
        zypper)
            packages=("procps" "util-linux" "iproute2")
            install_cmd="sudo zypper install -y"
            ;;
        *)
            error_exit "Unsupported package manager. Please install manually: procps, util-linux, iproute2"
            ;;
    esac

    # Check if packages are already installed
    local missing=()
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  ${pkg%% *} " 2>/dev/null && \
           ! rpm -q "${pkg%% *}" &>/dev/null && \
           ! pacman -Q "${pkg%% *}" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}Installing missing packages: ${missing[*]}${NC}"
        if ! eval "$install_cmd ${missing[*]}"; then
            error_exit "Failed to install required packages"
        fi
    fi
}

# Get CPU temperature safely
get_cpu_temp() {
    local temp=""
    # Try sysfs first
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1)
        [ -n "$temp" ] && temp=$((temp/1000))"°C"
    fi
    
    # Try sensors command if available
    if [ -z "$temp" ] && command -v sensors &>/dev/null; then
        temp=$(sensors 2>/dev/null | awk '/Package|Tdie|Core 0/ {print $2}' | head -1 | tr -d '+°C')
        [ -n "$temp" ] && temp="${temp}°C"
    fi

    echo "${temp:-N/A}"
}

# Main display function
display_system_info() {
    # Get system information
    local ram_total=$(free -m | awk '/Mem:/ {print $2}')
    local ram_used=$(free -m | awk '/Mem:/ {print $3}')
    local ram_percent=$(awk "BEGIN {printf \"%.0f\", $ram_used*100/$ram_total}")
    
    local disk_used=$(df -h / | awk 'NR==2 {print $3}')
    local disk_total=$(df -h / | awk 'NR==2 {print $2}')
    local disk_percent=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    
    local cpu_usage=$(top -bn1 | awk '/Cpu\(s\):/ {printf "%.1f%%", 100-$8}')
    local cpu_temp=$(get_cpu_temp)
    local uptime=$(uptime -p | sed 's/up //')
    local load_avg=$(uptime | awk -F'average: ' '{print $2}')
    local network=$(ip -o link show | awk -F': ' '!/lo/ {print $2}' | tr '\n' ' ')

    # Display information
    echo -e "${BLUE}=============================================="
    echo -e "            ${GREEN}SYSTEM MONITOR${BLUE}"
    echo -e "=============================================="
    echo -e "${YELLOW} Uptime:    ${GREEN}$uptime"
    echo -e "${YELLOW} Load Avg:  ${GREEN}$load_avg"
    echo -e "${YELLOW} CPU Usage: ${GREEN}$cpu_usage"
    echo -e "${YELLOW} CPU Temp:  ${GREEN}$cpu_temp"
    echo -e "${YELLOW} Memory:    ${GREEN}${ram_used}MB/${ram_total}MB (${ram_percent}%)"
    echo -e "${YELLOW} Disk:      ${GREEN}${disk_used}/${disk_total} (${disk_percent}%)"
    echo -e "${YELLOW} Network:   ${GREEN}${network}"
    echo -e "${BLUE}=============================================="
    echo -e " Press ${RED}q${BLUE} to quit"
    echo -e "==============================================${NC}"
}

# Main execution
main() {
    # Check dependencies first
    check_dependencies

    # Configure terminal
    stty -echo -icanon &>/dev/null
    printf "\033[?25l"  # Hide cursor
    
    # Clear screen completely before showing monitor
    clear

    # Main loop
    while true; do
        # Move cursor to top-left and display info
        printf "\033[H"
        display_system_info
        
        # Check for quit key
        if read -t 1 -n 1 key; then
            [[ "$key" == "q" ]] && break
        fi
    done

    cleanup
}

# Start the script
main
