# Linux Toolbox

Personal collection of Linux administration utilities.

## Utilities

| Utility | Description |
|---------|-------------|
| bypass | Manage routing exceptions for VPN traffic |
| tunnels | Manage named SSH port forwarding tunnels |
| vpnctl | Maintain work OpenVPN routing through Hiddify/Outline |
| work-vpn-audit | Log work VPN connections and observed public IPs |

## Platform

Developed and tested on Ubuntu Linux.

Python utilities use Python 3.

Some tools require:
- NetworkManager
- systemd
- iproute2
- OpenVPN

## Installation

Independent installers will be added for each utility.

Current files are snapshots of working local installations.

## Security

Do not commit:
- VPN credentials or private keys
- Authentication tokens
- Real environment files
- Personal configuration files
- SQLite history databases

Review source files before the first commit.
