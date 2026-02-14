# protonatpmpc
Automated NAT-PMP port forwarding manager for ProtonVPN .config with integrated firewall management. For Fedora.

This script automatically:

Detects your ProtonVPN connection using POINTOPOINT interface detection
Requests and maintains port forwarding via NAT-PMP protocol
Renews port mappings before they expire (60s lease, 45s renewal)
Opens firewall ports automatically when ports are assigned
Closes old firewall ports when ports rotate
Gracefully releases ports and closes firewall rules on shutdown

Features

Automatic Interface Detection - No need to hardcode interface names; detects any active P2P tunnel
Firewall Integration - Automatically manages firewalld rules as ports change
Graceful Shutdown - Properly releases port mappings and closes firewall ports on exit
Smart Port Management - Only closes ports in the ProtonVPN range (40000-65535) to avoid system ports
Error Recovery - Handles connection drops and gateway errors with automatic retry logic
Clean Terminal UI - Real-time status display with clear formatting
Logging - Activity logged to /tmp/proton-portforward.log for debugging

Requirements
System Requirements

Linux (tested on Fedora/RHEL/CentOS)
Bash 4.0+
Root/sudo access for firewall management

Dependencies
# Fedora/RHEL/CentOS
sudo dnf install libnatpmp iproute firewalld

# Debian/Ubuntu
sudo apt install natpmpc iproute2 firewalld

How It Works

1-VPN Detection - Monitors for active POINTOPOINT interfaces (VPN tunnels)
2-Port Request - Sends NAT-PMP requests to gateway (10.2.0.1) for TCP and UDP mappings
3-Firewall Update - Opens the assigned port in firewalld (both TCP and UDP)
4-Renewal Loop - Renews mapping every 45 seconds (before the 60s lease expires)
5-Port Rotation Handling - If ProtonVPN assigns a new port, closes the old one and opens the new one
6-Cleanup - On exit, releases port mapping and closes firewall rules

Status Display
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ProtonVPN Port Forwarding Manager v2
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Status: ✅ ACTIVE
Time:   2026-02-15 14:30:45
Interface: proton0

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  FORWARDED PORT (TCP+UDP): 51234      ┃
┃                                        ┃
┃  Firewall: ✅ OPEN                     ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Next renewal: 14:31:30

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


Development Note
This script was developed partly with AI assistance (Claude). This is a simple script that i found useful and igured it might be useful to others dealing with the same annoyance. I'm not a pro dev, just someone who wanted to set-and-forget their own VPN port forwarding. Use at your own risk, and feel free to improve it!
