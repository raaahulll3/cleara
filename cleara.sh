#!/usr/bin/env bash
# Cleara v1 – Advanced & Safe Linux Cleanup Tool
# Author: raaahullls
# Date: 2025-10-30
# License: MIT

set -o errexit
set -o pipefail
set -o nounset

readonly SCRIPT_NAME=$(basename "$0")
readonly VERSION="1.0"
readonly LOGFILE="/var/log/cleara.log"

# ====== Colors ======
BOLD='\e[1m'
YELLOW_BOLD='\e[1;33m'
CYAN_BOLD='\e[1;36m'
WHITE_FAINT='\e[0;37m'
GREEN_BOLD='\e[1;32m'
RED_BOLD='\e[1;31m'
RESET='\e[0m'

# ====== Globals ======
DRY_RUN=false
NO_COLOR=false
QUIET=false
PKG_MGR=""
FREED_SPACE_BEFORE=0
FREED_SPACE_AFTER=0
declare -A SUMMARY
SUMMARY_ORDER=()  # ✅ Track order of operations

# ====== Helper Functions ======

error_exit() {
    echo -e "${RED_BOLD}Error:${RESET} $1" >&2
    exit 1
}

log() {
    local msg="$1"
    if sudo mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null; then
        echo "$(date '+%F %T') - $msg" | sudo tee -a "$LOGFILE" >/dev/null
    else
        echo "$(date '+%F %T') - $msg" >> "${HOME}/cleara.log"
    fi
}

detect_pkg_mgr() {
    if command -v apt-get >/dev/null; then PKG_MGR="apt"
    elif command -v dnf >/dev/null; then PKG_MGR="dnf"
    elif command -v pacman >/dev/null; then PKG_MGR="pacman"
    elif command -v zypper >/dev/null; then PKG_MGR="zypper"
    else PKG_MGR="unknown"
    fi
}

human_readable_size() {
    numfmt --to=iec --suffix=B "$1"
}

disk_space_before() {
    FREED_SPACE_BEFORE=$(df / --output=avail | tail -1)
}

disk_space_after() {
    FREED_SPACE_AFTER=$(df / --output=avail | tail -1)
    local diff=$((FREED_SPACE_AFTER - FREED_SPACE_BEFORE))
    if (( diff > 0 )); then
        echo -e "${GREEN_BOLD}Freed $(human_readable_size $((diff*1024))) of space.${RESET}"
    else
        echo -e "${YELLOW_BOLD}No noticeable disk space freed.${RESET}"
    fi
}

# ====== Spinner ======
spinner() {
    local msg=$1 duration=$2 cmd=$3
    local spin='|/-\' i=0 start_time=$SECONDS
    [[ $QUIET == false ]] && echo -ne "${CYAN_BOLD}${msg}${RESET} "
    tput civis
    while (( SECONDS - start_time < duration )); do
        printf "\b${spin:i++%${#spin}:1}"
        sleep 0.1
    done
    printf "\b"
    if $DRY_RUN; then
        echo -e "${YELLOW_BOLD}[DRY RUN]${RESET}"
        log "[DRY RUN] $msg"
        return
    fi
    if eval "$cmd" &>/dev/null; then
        [[ $QUIET == false ]] && echo -e "${GREEN_BOLD}✅ Done${RESET}"
        log "$msg – Success"
    else
        [[ $QUIET == false ]] && echo -e "${RED_BOLD}❌ Failed${RESET}"
        log "$msg – Failed"
    fi
    tput cnorm
}

# ====== UI ======
banner() {
    [[ $QUIET == true ]] && return
    echo -e "${YELLOW_BOLD}╭─────────────╮${RESET}"
    echo -e "${YELLOW_BOLD}│  Cleara 🚀  │${RESET}"
    echo -e "${YELLOW_BOLD}╰─────────────╯${RESET}"
    echo -e "${CYAN_BOLD}Reclaim your speed!${RESET}\n"
}

menu() {
    echo -e "${CYAN_BOLD}1)${RESET} ${WHITE_FAINT}Drop system cache${RESET}"
    echo -e "${CYAN_BOLD}2)${RESET} ${WHITE_FAINT}Clean /tmp${RESET}"
    echo -e "${CYAN_BOLD}3)${RESET} ${WHITE_FAINT}Clean package cache${RESET}"
    echo -e "${CYAN_BOLD}4)${RESET} ${WHITE_FAINT}Purge old configs${RESET}"
    echo -e "${CYAN_BOLD}5)${RESET} ${WHITE_FAINT}Clean user/global cache${RESET}"
    echo -e "${CYAN_BOLD}6)${RESET} ${WHITE_FAINT}Clean everything${RESET}"
    echo -e "${CYAN_BOLD}0)${RESET} ${WHITE_FAINT}Exit${RESET}"
}

# ====== Summary helper ======
add_summary_order() {
    local name="$1"
    for n in "${SUMMARY_ORDER[@]}"; do
        [[ "$n" == "$name" ]] && return
    done
    SUMMARY_ORDER+=("$name")
}

# ====== Core Cleaning Functions ======
drop_cache() {
    spinner "Dropping system cache..." 3 "sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null"
    SUMMARY["System Cache"]="Cleared"
    add_summary_order "System Cache"
}

clean_tmp() {
    if [[ -d /tmp && $(ls -A /tmp) ]]; then
        spinner "Cleaning /tmp..." 3 "sudo find /tmp -mindepth 1 -maxdepth 1 ! -path '/tmp/.X11-unix*' -exec rm -rf {} +"
        SUMMARY["/tmp"]="Cleared"
        add_summary_order "/tmp"
    else
        SUMMARY["/tmp"]="Already Clean"
        add_summary_order "/tmp"
        [[ $QUIET == false ]] && echo -e "${YELLOW_BOLD}/tmp is already clean.${RESET}"
    fi
}

clean_pkg_cache() {
    case $PKG_MGR in
        apt)   spinner "Cleaning apt cache..." 4 "sudo apt-get autoremove -y && sudo apt-get autoclean -y && sudo apt-get clean -y" ;;
        dnf)   spinner "Cleaning dnf cache..." 4 "sudo dnf clean all -y" ;;
        pacman) spinner "Cleaning pacman cache..." 4 "sudo pacman -Scc --noconfirm" ;;
        zypper) spinner "Cleaning zypper cache..." 4 "sudo zypper clean -a" ;;
        *) echo -e "${RED_BOLD}Unsupported package manager.${RESET}" ;;
    esac
    SUMMARY["Package Cache"]="Cleared"
    add_summary_order "Package Cache"
}

purge_old_configs() {
    local oldcfgs
    oldcfgs=$(dpkg -l 2>/dev/null | awk '/^rc/ {print $2}') || true
    if [[ -n "$oldcfgs" ]]; then
        spinner "Purging old configs..." 4 "sudo apt purge -y $oldcfgs"
        SUMMARY["Old Configs"]="Cleared"
        add_summary_order "Old Configs"
    else
        SUMMARY["Old Configs"]="None"
        add_summary_order "Old Configs"
        [[ $QUIET == false ]] && echo -e "${YELLOW_BOLD}No old configs to purge.${RESET}"
    fi
}

clean_caches() {
    spinner "Cleaning user/system cache..." 3 "rm -rf ~/.cache/* && sudo rm -rf /var/cache/apt/* /var/cache/man/*"
    SUMMARY["User Cache"]="Cleared"
    add_summary_order "User Cache"
}

clean_all() {
    disk_space_before
    SUMMARY_ORDER=()   # ✅ Reset summary order to avoid duplicates
    drop_cache
    clean_tmp
    clean_pkg_cache
    purge_old_configs
    clean_caches
    wait
    disk_space_after
}

# ====== Summary Display ======
show_summary() {
    [[ $QUIET == true ]] && return
    echo -e "\n${CYAN_BOLD}Summary:${RESET}"
    echo "┌───────────────────────┬──────────────┐"
    echo "│ Operation             │ Status!      │"
    echo "├───────────────────────┼──────────────┤"
    for key in "${SUMMARY_ORDER[@]}"; do
        printf "│ %-21s │ %-12s │\n" "$key" "${SUMMARY[$key]}"
    done
    echo "└───────────────────────┴──────────────┘"
}

# ====== CLI Flags ======
usage() {
    cat <<EOF
Cleara v${VERSION} – Advanced Linux Cleanup Tool

Usage:
  $SCRIPT_NAME [OPTIONS]

Options:
  --all           Perform full cleanup
  --tmp           Clean /tmp directory
  --cache         Clean user/system cache
  --pkg           Clean package cache
  --purge         Purge old configs
  --dry-run       Preview actions without deleting
  --quiet         Minimal output (for cron jobs)
  --no-color      Disable color output
  -v, --version   Show version info
  -h, --help      Show this help
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all) ACTION="all"; shift ;;
            --tmp) ACTION="tmp"; shift ;;
            --cache) ACTION="cache"; shift ;;
            --pkg) ACTION="pkg"; shift ;;
            --purge) ACTION="purge"; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            --quiet) QUIET=true; shift ;;
            --no-color) NO_COLOR=true; shift ;;
            -v|--version) echo "Cleara v${VERSION} by raaahulllls"; exit 0 ;;
            -h|--help) usage; exit 0 ;;
            *) echo "Unknown option: $1"; usage; exit 1 ;;
        esac
    done
}

# ====== Main ======
main() {
    detect_pkg_mgr
    [[ $EUID -ne 0 ]] && sudo -v || true
    banner
    disk_space_before

    if [[ -n "${ACTION:-}" ]]; then
        case "$ACTION" in
            all) clean_all ;;
            tmp) clean_tmp ;;
            cache) clean_caches ;;
            pkg) clean_pkg_cache ;;
            purge) purge_old_configs ;;
        esac
        show_summary
        exit 0
    fi

    # Interactive mode
    while true; do
        menu
        echo
        read -rp "Select option ⌨ : " opt
        echo
        case "$opt" in
            1) drop_cache ;;
            2) clean_tmp ;;
            3) clean_pkg_cache ;;
            4) purge_old_configs ;;
            5) clean_caches ;;
            6) clean_all ;;
            0)
                echo -e "${GREEN_BOLD}Cleaning done, speed gained! 🚀${RESET}"
                echo -e "${GREEN_BOLD}Thanks for using Cleara!${RESET}"
                exit 0
                ;;
            *) echo -e "${RED_BOLD}Invalid choice.${RESET}" ;;
        esac
        show_summary
        echo
    done
}

parse_args "$@"
main
