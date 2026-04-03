#!/data/data/com.termux/files/usr/bin/env bash

## Troubleshooting
# set -e -u -x

#
# Psiphon Labs 
# https://github.com/Psiphon-Labs/psiphon-labs.github.io
#
#
# Script auto install Psiphon Tunnel VPN for Termux (Android)
# Adapted from Linux version by MisterTowelie
#
# System Required: Termux (F-Droid version recommended)
#
# https://github.com/MisterTowelie/Psiphon-Tunnel-VPN
#
# Author original: MisterTowelie
# Termux adaptation: AI Assistant

############################################################################
#   VERSION HISTORY   ######################################################
############################################################################

# v2.0 (Termux)
# - Adapted for Termux environment
# - Added ARM64/ARMv7 support
# - Removed sudo dependencies
# - Changed paths for Termux (/data/data/com.termux/files/usr/)
# - Added termux-wake-lock support
# - Fixed binary download URLs for Android
# - Added notification support via termux-notification

readonly script_version="2.0-termux"

readonly RED="\033[0;31m"
readonly GREEN="\033[0;32m"
readonly YELLOW="\033[0;33m"
readonly BOLD="\033[1m"
readonly NORM="\033[0m"
readonly INFO="${BOLD}${GREEN}[INFO]: $NORM"
readonly ERROR="${BOLD}${RED}[ERROR]: $NORM"
readonly WARNING="${BOLD}${YELLOW}[WARNING]: $NORM"
readonly HELP="${BOLD}${GREEN}[HELP]: $NORM"

readonly os="$(uname)"
readonly arch="$(uname -m)"

# Detect Android architecture
case "$arch" in
    aarch64|arm64)
        readonly psiphon_arch="arm64"
        readonly psiphon_name_file="psiphon-tunnel-core-arm64"
        ;;
    armv7l|armv7|arm)
        readonly psiphon_arch="armv7"
        readonly psiphon_name_file="psiphon-tunnel-core-armv7"
        ;;
    x86_64|amd64)
        readonly psiphon_arch="x86_64"
        readonly psiphon_name_file="psiphon-tunnel-core-x86_64"
        ;;
    i386|i686|x86)
        readonly psiphon_arch="x86"
        readonly psiphon_name_file="psiphon-tunnel-core-x86"
        ;;
    *)
        echo -e "${ERROR}Unsupported architecture: $arch" >&2
        echo -e "${INFO}Supported: arm64, armv7, x86_64, x86" >&2
        exit 1
        ;;
esac

readonly supported_os=("Linux")
readonly psiphon_name="Psiphon Tunnel VPN"
readonly psiphon_dir="$HOME/psiphon"
readonly psiphon_path="$psiphon_dir/$psiphon_name_file"
readonly psiphon_config="$psiphon_dir/config.json"
readonly psiphon_log="$psiphon_dir/psiphon-tunnel.log"
readonly psiphon_pid_file="$psiphon_dir/psiphon.pid"

# GitHub raw URLs for Android binaries
readonly psiphon_url="https://github.com/Psiphon-Labs/psiphon-tunnel-core-binaries/raw/master/android/$psiphon_name_file"
readonly psiphon_url_commit="https://api.github.com/repos/Psiphon-Labs/psiphon-tunnel-core-binaries/commits"

readonly level_msg=("$ERROR" "$WARNING" "$INFO" "$HELP")
readonly msg_DB=("The file $psiphon_name or its configuration file was not found."
        "Usage: ${0##*/} install | uninstall | update | start | stop | port | status | help")

psiphon_local_commit=''
psiphon_remote_commit=''
action=''
pid=''

# Check if running in Termux
if [[ -z "${TERMUX_VERSION}" ]] && [[ ! "$PREFIX" == *"com.termux"* ]]; then
    echo -e "${WARNING}This script is designed for Termux (Android)" >&2
    echo -e "${INFO}Detected environment: ${PREFIX:-unknown}" >&2
    echo -e "${INFO}Continue anyway? (y/n)" >&2
    read -n1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

if [[ ! " ${supported_os[*]} " =~ $os ]]; then
    echo -e "${level_msg[0]}This ($os) operating system is not supported." >&2
    exit 1
fi

function check_update_psiphon(){
    if [[ ! -f "$psiphon_path" ]]; then
        echo -e "$INFO Psiphon not installed yet. Run 'install' first." >&2
        return 1
    fi
    
    psiphon_local_commit="$("${psiphon_path}" --version 2>/dev/null | grep "Revision:" | head -1 | cut -d : -f 2 | tr -d " ")"
    
    if [[ -z "$psiphon_local_commit" ]]; then
        echo -e "${WARNING}Could not determine local version" >&2
        return 1
    fi
    
    # Get latest commit for Android directory
    psiphon_remote_commit="$(curl -sL "$psiphon_url_commit" | grep -o '"path":"android/[^"]*"' | head -1 | grep -o 'android/[^"]*' | head -1)"
    
    echo -e "$INFO Local version: $psiphon_local_commit" >&2
    echo -e "$INFO Checking for updates..." >&2

    # For Android binaries, we check if binary exists and is recent
    # Since commit hashes differ between platforms, we use file modification time as fallback
    if command -v md5sum >/dev/null 2>&1; then
        echo -e "$INFO Checking binary hash..." >&2
        # Re-download and compare if needed
        local temp_file="${psiphon_path}.tmp"
        if curl -sL "$psiphon_url" -o "$temp_file" 2>/dev/null; then
            if [[ -f "$psiphon_path" ]]; then
                local old_hash=$(md5sum "$psiphon_path" 2>/dev/null | cut -d' ' -f1)
                local new_hash=$(md5sum "$temp_file" 2>/dev/null | cut -d' ' -f1)
                if [[ "$old_hash" != "$new_hash" ]]; then
                    echo -e "$INFO New version available!" >&2
                    mv "$temp_file" "$psiphon_path"
                    chmod +x "$psiphon_path"
                    echo -e "$INFO Updated successfully" >&2
                else
                    rm -f "$temp_file"
                    echo -e "$INFO Already up to date" >&2
                fi
            else
                mv "$temp_file" "$psiphon_path"
                chmod +x "$psiphon_path"
            fi
        fi
    else
        echo -e "${WARNING}Cannot check for updates (md5sum not available)" >&2
    fi
}

function check_psiphon(){
    if [ -f "${psiphon_path}" ] && [ -f "${psiphon_config}" ]; then
        return 0
    else
        return 1
    fi
}

function check_free_port(){
    local port="$1"

    if command -v netstat >/dev/null 2>&1; then
        if netstat -tln 2>/dev/null | grep -q ":$port "; then
            echo -e "${level_msg[1]}Port [$port] is already busy, try another one." >&2
            return 1
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tln 2>/dev/null | grep -q ":$port "; then
            echo -e "${level_msg[1]}Port [$port] is already busy, try another one." >&2
            return 1
        fi
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -i :"$port" >/dev/null 2>&1; then
            echo -e "${level_msg[1]}Port [$port] is already busy, try another one." >&2
            return 1
        fi
    fi
    
    echo -e "${level_msg[2]}Port [$port] is available." >&2
    return 0
}

function check_dependencies(){
    local deps=("curl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo
        echo -e "${level_msg[0]}Missing required packages: ${missing[*]}" >&2
        echo -e "${INFO}Install with: pkg install ${missing[*]}" >&2
        echo
        read -n1 -rp "Press any key to install automatically..."
        echo
        pkg install -y "${missing[@]}" || {
            echo -e "${level_msg[0]}Failed to install packages" >&2
            exit 1
        }
    fi
    
    # Optional: termux-api for notifications
    if command -v termux-notification >/dev/null 2>&1; then
        readonly HAS_TERMUX_API=1
    else
        readonly HAS_TERMUX_API=0
        echo -e "${INFO}Tip: Install termux-api for notifications (pkg install termux-api)" >&2
    fi
}

function is_running_psiphon(){
    if [[ -f "$psiphon_pid_file" ]]; then
        pid=$(cat "$psiphon_pid_file" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            rm -f "$psiphon_pid_file"
            pid=''
            return 1
        fi
    fi
    
    # Fallback: search by process name
    pid=$(pgrep -f -- "$psiphon_name_file" 2>/dev/null | head -1)
    if [[ -n "$pid" ]]; then
        echo "$pid" > "$psiphon_pid_file"
        return 0
    fi
    
    return 1
}

function stop_pid_psiphon(){
    is_running_psiphon

    if [[ -z "$pid" ]]; then
        echo -e "${level_msg[2]}[$psiphon_name] is not running." >&2
        return 1
    fi

    echo -e "${level_msg[2]}Stopping [$psiphon_name] (PID: $pid)..." >&2
    
    # Remove wake lock if exists
    if [[ -f "$psiphon_dir/.wakelock" ]]; then
        if command -v termux-wake-unlock >/dev/null 2>&1; then
            termux-wake-unlock 2>/dev/null || true
        fi
        rm -f "$psiphon_dir/.wakelock"
    fi
    
    kill "$pid" 2>/dev/null
    sleep 2

    if is_running_psiphon; then
        echo -e "${level_msg[1]}$psiphon_name did not stop gracefully, forcing..." >&2
        kill -9 "$pid" 2>/dev/null
        sleep 1
    fi

    rm -f "$psiphon_pid_file"
    echo -e "${level_msg[2]}[$psiphon_name] stopped." >&2
    
    # Notification
    if [[ "$HAS_TERMUX_API" == "1" ]]; then
        termux-notification --title "Psiphon" --content "VPN stopped" --priority low 2>/dev/null || true
    fi
    
    return 0
}

function set_port_psiphon(){
    local message="$1"
    local default_port="$2"
    local httpport="$3"
    local port

    while true; do
        IFS= read -rp "$message [$default_port]: " port
        [[ -z "$port" ]] && port="$default_port"

        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
            echo -e "${level_msg[1]}$port: invalid port (must be 1-65535)." >&2
            continue
        fi

        if [[ -n "$httpport" && "$port" == "$httpport" ]]; then
            echo -e "${level_msg[1]}$port: cannot be the same as previous port ($httpport)." >&2
            continue
        fi

        if ! check_free_port "$port"; then
            continue
        fi

        echo "$port"
        return
    done
}

function download_files(){
    echo -e "$INFO Downloading $psiphon_name for $psiphon_arch..." >&2
    
    if ! curl --progress-bar -fSL --retry 3 --retry-delay 5 --connect-timeout 30 \
         -o "${psiphon_path}" "${psiphon_url}"; then
        echo -e "${level_msg[0]}Download failed. Check internet connection." >&2
        echo -e "${INFO}URL: $psiphon_url" >&2
        rm -f "${psiphon_path}"
        exit 1
    fi

    chmod +x "${psiphon_path}"
    echo -e "$INFO Download complete" >&2
}

function download_psiphon(){
    [[ ! -d "$psiphon_dir" ]] && mkdir -p "$psiphon_dir"
    download_files
}

function conf_psiphon(){
    echo
    echo -e "${level_msg[2]}Configure HTTP Proxy port:" >&2
    httpport=$(set_port_psiphon "Port (default:" 8080)
    echo
    echo -e "${level_msg[2]}Configure SOCKS Proxy port:" >&2
    socksport=$(set_port_psiphon "Port (default:" 1080 "$httpport")
    echo
    echo -e "${level_msg[2]}Selected ports:" >&2
    echo -e "${level_msg[2]}  HTTP Proxy:  $httpport" >&2
    echo -e "${level_msg[2]}  SOCKS Proxy: $socksport" >&2
    
    cat > "${psiphon_config}"<<-EOF
{
 "LocalHttpProxyPort":$httpport,
 "LocalSocksProxyPort":$socksport,
 "PropagationChannelId":"FFFFFFFFFFFFFFFF",
 "RemoteServerListDownloadFilename":"remote_server_list",
 "RemoteServerListSignaturePublicKey":"MIICIDANBgkqhkiG9w0BAQEFAAOCAg0AMIICCAKCAgEAt7Ls+/39r+T6zNW7GiVpJfzq/xvL9SBH5rIFnk0RXYEYavax3WS6HOD35eTAqn8AniOwiH+DOkvgSKF2caqk/y1dfq47Pdymtwzp9ikpB1C5OfAysXzBiwVJlCdajBKvBZDerV1cMvRzCKvKwRmvDmHgphQQ7WfXIGbRbmmk6opMBh3roE42KcotLFtqp0RRwLtcBRNtCdsrVsjiI1Lqz/lH+T61sGjSjQ3CHMuZYSQJZo/KrvzgQXpkaCTdbObxHqb6/+i1qaVOfEsvjoiyzTxJADvSytVtcTjijhPEV6XskJVHE1Zgl+7rATr/pDQkw6DPCNBS1+Y6fy7GstZALQXwEDN/qhQI9kWkHijT8ns+i1vGg00Mk/6J75arLhqcodWsdeG/M/moWgqQAnlZAGVtJI1OgeF5fsPpXu4kctOfuZlGjVZXQNW34aOzm8r8S0eVZitPlbhcPiR4gT/aSMz/wd8lZlzZYsje/Jr8u/YtlwjjreZrGRmG8KMOzukV3lLmMppXFMvl4bxv6YFEmIuTsOhbLTwFgh7KYNjodLj/LsqRVfwz31PgWQFTEPICV7GCvgVlPRxnofqKSjgTWI4mxDhBpVcATvaoBl1L/6WLbFvBsoAUBItWwctO2xalKxF5szhGm8lccoc5MZr8kfE0uxMgsxz4er68iCID+rsCAQM=",
 "RemoteServerListUrl":"https://s3.amazonaws.com/psiphon/web/mjr4-p23r-puwl/server_list_compressed",
 "SponsorId":"FFFFFFFFFFFFFFFF",
 "UseIndistinguishableTLS":true,
 "DisableLocalHTTPProxy":false,
 "DisableLocalSocksProxy":false
}
EOF
    echo -e "$INFO Configuration saved" >&2
}

function run_psiphon(){
    echo
    echo -e "${level_msg[2]}Starting $psiphon_name..." >&2
    
    # Prevent device sleep while running
    if command -v termux-wake-lock >/dev/null 2>&1; then
        termux-wake-lock
        touch "$psiphon_dir/.wakelock"
        echo -e "$INFO Wake lock acquired (preventing sleep)" >&2
    fi
    
    # Clear old log
    > "$psiphon_log"
    
    nohup "$psiphon_path" -formatNotices -obfs4-distBias \
        -dataRootDirectory "$psiphon_dir" \
        -config "$psiphon_config" >>"$psiphon_log" 2>&1 &
    
    psiphon_pid=$!
    echo "$psiphon_pid" > "$psiphon_pid_file"
    
    sleep 2
    
    if kill -0 "$psiphon_pid" 2>/dev/null; then
        echo -e "${level_msg[2]}Started successfully (PID: $psiphon_pid)" >&2
        echo -e "${level_msg[2]}Log: $psiphon_log" >&2
        
        # Show proxy settings
        if [[ -f "$psiphon_config" ]]; then
            local http_port=$(grep "LocalHttpProxyPort" "$psiphon_config" | grep -o '[0-9]*')
            local socks_port=$(grep "LocalSocksProxyPort" "$psiphon_config" | grep -o '[0-9]*')
            echo -e "${level_msg[2]}HTTP Proxy:  127.0.0.1:$http_port" >&2
            echo -e "${level_msg[2]}SOCKS Proxy: 127.0.0.1:$socks_port" >&2
        fi
        
        # Notification
        if [[ "$HAS_TERMUX_API" == "1" ]]; then
            termux-notification --title "Psiphon VPN" --content "Running (PID: $psiphon_pid)" \
                --ongoing --priority high --button1 "Stop" --button1-action "termux-open-url psiphon://stop" 2>/dev/null || true
        fi
    else
        echo -e "${level_msg[0]}Failed to start! Check log:" >&2
        tail -20 "$psiphon_log" >&2
        rm -f "$psiphon_pid_file"
        return 1
    fi
}

function install_psiphon(){
    if check_psiphon; then
        echo
        echo -e "${level_msg[2]}Psiphon already installed. Checking for updates..." >&2
        check_update_psiphon
    else
        echo
        echo -e "${level_msg[2]}Installing $psiphon_name ($psiphon_arch)..." >&2
        echo
        check_dependencies
        download_psiphon
        conf_psiphon
        echo
        echo -e "${level_msg[2]}Installation complete!" >&2
        echo -e "${level_msg[2]}Directory: $psiphon_dir" >&2
        echo
        echo -e "$INFO Usage: ${0##*/} start" >&2
    fi
}

function uninstall_psiphon(){
    if check_psiphon; then
        stop_pid_psiphon
        echo
        echo -e "${level_msg[2]}Removing $psiphon_name..." >&2
        rm -Rf "${psiphon_dir}"
        echo -e "${level_msg[2]}Uninstalled successfully" >&2
    else
        echo
        echo -e "${level_msg[1]}${msg_DB[0]}" >&2
    fi
}

function update_psiphon(){
    if check_psiphon; then
        echo -e "$INFO Stopping Psiphon before update..." >&2
        local was_running=0
        if is_running_psiphon; then
            was_running=1
            stop_pid_psiphon
        fi
        
        check_update_psiphon
        
        if [[ "$was_running" == "1" ]]; then
            echo -e "$INFO Restarting..." >&2
            run_psiphon
        fi
    else
        echo
        echo -e "${level_msg[1]}${msg_DB[0]}" >&2
        echo -e "${INFO}Run: ${0##*/} install" >&2
    fi
}

function start_psiphon(){
    if is_running_psiphon; then
        echo -e "${level_msg[1]}[$psiphon_name] already running (PID $pid)" >&2
        return 0
    fi
    
    if ! check_psiphon; then
        echo
        echo -e "${level_msg[1]}${msg_DB[0]}" >&2
        echo -e "${INFO}Run: ${0##*/} install" >&2
        return 1
    fi
    
    # Validate config
    if [[ ! -s "$psiphon_config" ]] || [[ $(wc -l < "$psiphon_config") -lt 5 ]]; then
        echo -e "${WARNING}Invalid config, reconfiguring..." >&2
        conf_psiphon
    fi
    
    run_psiphon
}

function stop_psiphon(){
    stop_pid_psiphon
}

function status_psiphon(){
    if is_running_psiphon; then
        echo -e "${level_msg[2]}[$psiphon_name] is RUNNING (PID: $pid)" >&2
        echo -e "$INFO Recent log entries:" >&2
        tail -5 "$psiphon_log" 2>/dev/null || echo "No log available"
        
        if [[ -f "$psiphon_config" ]]; then
            echo
            echo -e "$INFO Proxy settings:" >&2
            grep -E "LocalHttpProxyPort|LocalSocksProxyPort" "$psiphon_config" 2>/dev/null || true
        fi
    else
        echo -e "${level_msg[1]}[$psiphon_name] is NOT running" >&2
        if [[ -f "$psiphon_log" ]]; then
            echo -e "$INFO Last log entries:" >&2
            tail -5 "$psiphon_log" 2>/dev/null || true
        fi
    fi
}

function port_psiphon(){
    if ! check_psiphon; then
        echo -e "${level_msg[1]}${msg_DB[0]}" >&2
        return 1
    fi
    
    conf_psiphon
    
    if is_running_psiphon; then
        echo
        echo -e "${level_msg[2]}Restarting $psiphon_name with new ports..." >&2
        stop_pid_psiphon
        sleep 1
        run_psiphon
    fi
}

function help_psiphon(){
    echo
    echo -e "${level_msg[3]}Psiphon Tunnel VPN for Termux v$script_version" >&2
    echo -e "${level_msg[3]}Architecture: $psiphon_arch" >&2
    echo
    echo "Commands:"
    echo "  install    - Install Psiphon and configure ports"
    echo "  uninstall  - Remove Psiphon completely"
    echo "  update     - Check and install updates"
    echo "  start      - Start Psiphon VPN"
    echo "  stop       - Stop Psiphon VPN"
    echo "  status     - Check if running and show info"
    echo "  port       - Change proxy ports"
    echo "  help       - Show this help"
    echo
    echo "Tips:"
    echo "  • Use 'termux-wake-lock' to prevent sleep while connected"
    echo "  • HTTP proxy works with curl: curl -x http://127.0.0.1:PORT ..."
    echo "  • SOCKS5 proxy works with many apps"
    echo "  • Install termux-api for notifications"
    echo
}

# Main
action="$1"
[ -z "$1" ] && action="help"

case "$action" in
    install|uninstall|update|start|stop|status|port|help)
        "${action}"_psiphon
        ;;
    *)
        echo
        echo -e "${level_msg[0]}Invalid command: [$action]" >&2
        help_psiphon
        ;;
esac
