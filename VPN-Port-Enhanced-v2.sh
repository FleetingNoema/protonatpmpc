#!/bin/bash
# =============================================================================
# ProtonVPN Port Forwarding Manager (Enhanced Edition v2 with Firewall Integration)
# Automatically maintains NAT-PMP port forwarding using POINTOPOINT detection
# Automatically opens/closes firewall ports as they change
# =============================================================================

# Enable safer bash execution
set -o pipefail

# --- CONFIGURATION ---
GATEWAY="10.2.0.1"
LEASE_TIME=60
SLEEP_TIME=45
LOG_FILE="/tmp/proton-portforward.log"
FIREWALL_ZONE="public"  # Change this if you use a different zone

# --- TRAP FOR GRACEFUL SHUTDOWN ---
cleanup() {
    local exit_code=$?
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⏹  Shutting down gracefully..."
    
    if [ -n "$CURRENT_PORT" ] && [ -n "$INTERFACE" ]; then
        echo "   Releasing port $CURRENT_PORT..."
        # Send lease time of 0 to release the port
        natpmpc -a 1 0 tcp 0 -g "$GATEWAY" &>/dev/null
        natpmpc -a 1 0 udp 0 -g "$GATEWAY" &>/dev/null
        echo "   Port released successfully"
        
        # Close the firewall port
        echo "   Closing firewall port $CURRENT_PORT..."
        close_firewall_port "$CURRENT_PORT"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit "$exit_code"
}

trap cleanup SIGINT SIGTERM EXIT

# --- FUNCTION: Check if firewalld is running ---
check_firewalld() {
    systemctl is-active --quiet firewalld 2>/dev/null
}

# --- FUNCTION: Open firewall port ---
open_firewall_port() {
    local port=$1
    local success=0
    
    if ! check_firewalld; then
        echo "⚠️  firewalld is not running - skipping firewall configuration"
        return 1
    fi
    
    # Add port for TCP (runtime - immediate effect)
    if sudo firewall-cmd --zone="$FIREWALL_ZONE" --add-port="${port}/tcp" &>/dev/null; then
        echo "   ✓ Opened TCP port $port in firewall (runtime)"
    else
        echo "   ⚠️  Failed to open TCP port $port"
        success=1
    fi
    
    # Add port for UDP (runtime - immediate effect)
    if sudo firewall-cmd --zone="$FIREWALL_ZONE" --add-port="${port}/udp" &>/dev/null; then
        echo "   ✓ Opened UDP port $port in firewall (runtime)"
    else
        echo "   ⚠️  Failed to open UDP port $port"
        success=1
    fi
    
    return "$success"
}

# --- FUNCTION: Close firewall port ---
close_firewall_port() {
    local port=$1
    
    if ! check_firewalld; then
        return 1
    fi
    
    # Remove TCP port
    sudo firewall-cmd --zone="$FIREWALL_ZONE" --remove-port="${port}/tcp" &>/dev/null && \
        echo "   ✓ Closed TCP port $port in firewall"
    
    # Remove UDP port
    sudo firewall-cmd --zone="$FIREWALL_ZONE" --remove-port="${port}/udp" &>/dev/null && \
        echo "   ✓ Closed UDP port $port in firewall"
    
    return 0
}

# --- FUNCTION: Get currently open ProtonVPN ports from firewall ---
# Returns a list of ports that look like they were opened by this script
get_open_proton_ports() {
    if ! check_firewalld; then
        return 1
    fi
    
    # Get list of open ports in the zone
    sudo firewall-cmd --zone="$FIREWALL_ZONE" --list-ports 2>/dev/null | \
        tr ' ' '\n' | grep -oP '^\d+(?=/tcp)' | sort -un
}

# --- FUNCTION: Close old ProtonVPN ports ---
# This removes any previously opened ports that are no longer the current port
close_old_ports() {
    local current_port=$1
    local old_ports
    
    old_ports=$(get_open_proton_ports)
    
    if [ -z "$old_ports" ]; then
        return 0
    fi
    
    # Close each old port that's not the current one
    while IFS= read -r port; do
        # Skip if it's the current port
        if [ "$port" = "$current_port" ]; then
            continue
        fi
        
        # Only close ports in typical ProtonVPN forwarding range (usually 40000-65535)
        # This prevents accidentally closing other important ports
        if [ "$port" -ge 40000 ] && [ "$port" -le 65535 ]; then
            echo "   Closing old forwarded port: $port"
            close_firewall_port "$port"
        fi
    done <<< "$old_ports"
}

# --- FUNCTION: Detect VPN Interface ---
# Instead of matching names, we look for Point-to-Point tunnels that are UP
get_vpn_interface() {
    ip -o link show 2>/dev/null | grep "POINTOPOINT" | grep "UP" | awk -F': ' '{print $2}' | head -n 1
}

# --- FUNCTION: Request port mapping ---
request_port_mapping() {
    local result_udp result_tcp port_udp port_tcp
    
    # Request UDP mapping
    if ! result_udp=$(natpmpc -a 1 0 udp "$LEASE_TIME" -g "$GATEWAY" 2>&1); then
        return 1
    fi
    
    # Request TCP mapping
    if ! result_tcp=$(natpmpc -a 1 0 tcp "$LEASE_TIME" -g "$GATEWAY" 2>&1); then
        return 1
    fi
    
    port_udp=$(echo "$result_udp" | grep -oP 'Mapped public port \K\d+')
    port_tcp=$(echo "$result_tcp" | grep -oP 'Mapped public port \K\d+')
    
    if [ -z "$port_udp" ] || [ -z "$port_tcp" ]; then
        return 1
    fi
    
    if [ "$port_udp" = "$port_tcp" ]; then
        CURRENT_PORT=$port_tcp
        return 0
    else
        echo "⚠️  Warning: Port mismatch! UDP: $port_udp vs TCP: $port_tcp"
        CURRENT_PORT=$port_tcp
        return 0
    fi
}

# --- FUNCTION: Display status ---
display_status() {
    local status=$1
    local interface=$2
    local port=$3
    local firewall_status=$4
    
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ProtonVPN Port Forwarding Manager v2"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    case $status in
        "WAITING")
            echo "Status: 🔍 WAITING FOR VPN"
            echo "Time:   $(date '+%Y-%m-%d %H:%M:%S')"
            echo ""
            echo "No active POINTOPOINT VPN tunnel detected."
            echo "Check your connection to ProtonVPN."
            ;;
        "GATEWAY_ERROR")
            echo "Status: ❌ GATEWAY NOT RESPONDING"
            echo "Time:   $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Interface: $interface"
            echo ""
            echo "VPN is connected but the gateway ($GATEWAY) rejected the request."
            echo "Ensure '+pmp' is in your username or NAT-PMP is enabled."
            ;;
        "ACTIVE")
            echo "Status: ✅ ACTIVE"
            echo "Time:   $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Interface: $interface"
            echo ""
            echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
            printf "┃  FORWARDED PORT (TCP+UDP): %-11s┃\n" "$port"
            printf "┃  %-38s┃\n" " "
            if [ "$firewall_status" = "open" ]; then
                echo "┃  Firewall: ✅ OPEN                     ┃"
            elif [ "$firewall_status" = "disabled" ]; then
                echo "┃  Firewall: ⚠️  FIREWALLD NOT RUNNING   ┃"
            else
                echo "┃  Firewall: ❌ CHECK MANUALLY           ┃"
            fi
            echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
            echo ""
            echo "Next renewal: $(date -d "+$SLEEP_TIME seconds" '+%H:%M:%S')"
            ;;
    esac
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# --- FUNCTION: Check dependencies ---
check_dependencies() {
    local missing_deps=()
    
    if ! command -v natpmpc &>/dev/null; then
        missing_deps+=("natpmpc")
    fi
    
    if ! command -v ip &>/dev/null; then
        missing_deps+=("ip (iproute2)")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "ERROR: Missing required dependencies:"
        printf '  - %s\n' "${missing_deps[@]}"
        echo ""
        echo "Install them with: sudo apt install natpmpc iproute2"
        exit 1
    fi
}

# --- MAIN LOOP ---
echo "Starting ProtonVPN Port Forwarding Manager v2..."
echo "Logging to: $LOG_FILE"

# Check dependencies
check_dependencies

# Check if firewalld is available
if check_firewalld; then
    echo "✓ firewalld detected and running"
    echo "  Using zone: $FIREWALL_ZONE"
else
    echo "⚠️  firewalld is not running - firewall ports will not be managed"
    echo "  Port forwarding will still work, but you'll need to manually open ports"
fi

sleep 2

CURRENT_PORT=""
PREVIOUS_PORT=""
FAILURE_COUNT=0
MAX_FAILURES=3

while true; do
    INTERFACE=$(get_vpn_interface)
    
    if [ -z "$INTERFACE" ]; then
        # If VPN is down and we had a port open, close it
        if [ -n "$CURRENT_PORT" ]; then
            echo "VPN disconnected, closing port $CURRENT_PORT in firewall..." | tee -a "$LOG_FILE"
            close_firewall_port "$CURRENT_PORT"
            PREVIOUS_PORT=""
        fi
        
        display_status "WAITING"
        CURRENT_PORT=""
        FAILURE_COUNT=0
        sleep 5
        continue
    fi
    
    if request_port_mapping; then
        # Port mapping successful
        FIREWALL_STATUS="unknown"
        
        # If port changed, update firewall
        if [ "$CURRENT_PORT" != "$PREVIOUS_PORT" ]; then
            echo ""
            echo "Port assignment: $CURRENT_PORT"
            
            # Close old ports that are no longer needed
            if [ -n "$PREVIOUS_PORT" ] && [ "$PREVIOUS_PORT" != "$CURRENT_PORT" ]; then
                echo "Port changed from $PREVIOUS_PORT to $CURRENT_PORT"
                close_old_ports "$CURRENT_PORT"
            fi
            
            # Open the new port
            if open_firewall_port "$CURRENT_PORT"; then
                FIREWALL_STATUS="open"
            else
                FIREWALL_STATUS="disabled"
            fi
            
            PREVIOUS_PORT="$CURRENT_PORT"
            echo ""
        else
            # Port hasn't changed, just check if firewall is still configured
            if check_firewalld; then
                FIREWALL_STATUS="open"
            else
                FIREWALL_STATUS="disabled"
            fi
        fi
        
        display_status "ACTIVE" "$INTERFACE" "$CURRENT_PORT" "$FIREWALL_STATUS"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Port $CURRENT_PORT active on $INTERFACE" >> "$LOG_FILE"
        FAILURE_COUNT=0
    else
        display_status "GATEWAY_ERROR" "$INTERFACE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Gateway error on $INTERFACE" >> "$LOG_FILE"
        
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        if [ "$FAILURE_COUNT" -ge "$MAX_FAILURES" ]; then
            echo "⚠️  Multiple failures. Waiting 30s..."
            sleep 30
            FAILURE_COUNT=0
        fi
        sleep 5
        continue
    fi
    
    sleep "$SLEEP_TIME"
done
