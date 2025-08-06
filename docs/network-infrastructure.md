# 🌐 Smart Home Network Infrastructure

## Network Topology Overview

### Primary Infrastructure

- **Main Router**: Technicolor FGA2233PTN (ISP provided)
  - Connection: Fiber optic (Point2Point)
  - External IP: 87.71.185.170
  - Provides WiFi for human devices (2.4/5GHz)
  - DHCP enabled for regular devices

- **Mesh System**: TP-Link Deco HC220-G1-IL
  - Main unit wired to primary router
  - Additional units connected via WiFi
  - Functions as network bridges (no client WiFi)
  - LAN ports used for IoT router connections

### IoT Network Segmentation

- **Secondary Routers** for Smart Home devices:
  - Technicolor TG789vac v2
  - TP-Link Archer C20  
  - D-Link DSL-256 (offline)
- **Connection**: LAN-to-WAN from Deco units
- **Purpose**: Isolated 2.4GHz networks for IoT devices
- **Security**: NAT isolation from main network

### WiFi Extenders

- **TP-Link RE305**: Extends main router coverage
- **Coverage**: Human device WiFi amplification

## Smart Home Hub Configuration

### Raspberry Pi 3B+ Network Settings

- **IP Address**: 192.168.1.100 (static)
- **Network**: Main router subnet
- **Services**:
  - Home Assistant: Port 8123
  - Node-RED: Port 1880
  - SSH: Port 22222

### Security & Access

- **VPN**: Tailscale for remote access
- **Firewall**: UFW configured
- **SSH**: Key-based authentication only
- **Network Isolation**: IoT devices separated

## Connection Types Legend

- **Black arrows**: Wired connections
- **Purple arrows**: WiFi connections  
- **Orange dots**: Main router coverage
- **Blue dots**: Mesh system nodes
- **Green dots**: IoT router coverage

---
*Network Documentation - Smart Home Infrastructure*
