# Dell Wyse 3040 Home Assistant Setup Guide

## 1. Initial OS Installation

Debian 12.12.0 from Balena Etcher to flash USB

## 2. Installation Mode

Install without GUI in expert mode (force GRUB)

## 3. Network Configuration

After install login as root and set network up:

```bash
# Open file
nano /etc/network/interfaces

# Add to the end:
auto enp1s0
iface enp1s0 inet dhcp

# Save and exit (Ctrl+O, Enter, Ctrl+X)
# Reboot
reboot
```

## 4. Fix CD-ROM Repository Issue

If after installation with netinst-ISO a CD-ROM reference remains, and because of this apt cannot update:

```bash
# Open sources.list
nano /etc/apt/sources.list

# Comment out the line like:
# deb cdrom:[Debian GNU/Linux 12.12.0 _Bookworm_ ...] bookworm main
```

## 5. Add Default Repository

```bash
# Run
apt edit-sources

# Add
deb http://deb.debian.org/debian bookworm main

# Save file and exit: Ctrl+O, Enter, Ctrl+X
# Update packages
apt update
```

## 6. Install SSH Server

```bash
apt install openssh-server -y
systemctl enable ssh
systemctl start ssh
```

## 7. Install Additional Packages and Temperature Sensors

```bash
# Install essential packages
apt update
apt install -y bc curl jq wireless-tools dos2unix htop git lm-sensors

# Detect and configure temperature sensors
sudo sensors-detect --auto

# Test temperature monitoring
sensors
```

### Alternative Temperature Monitoring Methods

For Intel x86 systems like Dell Wyse 3040, you can also use:

```bash
# Check thermal zones directly
cat /sys/class/thermal/thermal_zone*/temp

# Get temperature with specific thermal zone (usually zone2 for CPU)
echo "scale=1; $(cat /sys/class/thermal/thermal_zone2/temp)/1000" | bc

# Create simple temperature check function
echo 'alias temp="echo \"CPU Temperature: \$(echo \"scale=1; \$(cat /sys/class/thermal/thermal_zone2/temp)/1000\" | bc)°C\""' >> ~/.bashrc
source ~/.bashrc
```

## 8. Configure System Timezone

Set timezone to Israel (Jerusalem) for proper logging timestamps:

```bash
# Set timezone to Israel
sudo timedatectl set-timezone Asia/Jerusalem

# Verify timezone setting
timedatectl

# Check current time
date
```

Expected output:
```
               Local time: Fri 2025-10-03 21:08:54 IDT
           Universal time: Fri 2025-10-03 18:08:54 UTC
                Time zone: Asia/Jerusalem (IDT, +0300)
System clock synchronized: yes
              NTP service: active
```

## 9. Add User to Sudo and Configure Passwordless Sudo

Under root (on Wyse locally, not via SSH):

```bash
apt install sudo -y
# Replace user with your username
usermod -aG sudo user
sudo visudo
echo 'user ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/user-nopasswd
sudo chmod 440 /etc/sudoers.d/user-nopasswd
exit
```

## 10. Fix Kernel Reboot Issues

Linux kernel without additional parameters often cannot properly shutdown/reboot the device:

```bash
# Open GRUB configuration file
sudo nano /etc/default/grub

# Find line: GRUB_CMDLINE_LINUX_DEFAULT="quiet"
# Replace with: GRUB_CMDLINE_LINUX_DEFAULT="quiet reboot=efi intel_idle.max_cstate=1"

# Update GRUB
sudo update-grub

# Reboot to apply changes
reboot
```

### Alternative Boot Parameters

If it doesn't work, replace and test one by one:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet reboot=acpi intel_idle.max_cstate=1"
GRUB_CMDLINE_LINUX_DEFAULT="quiet reboot=kbd intel_idle.max_cstate=1"
GRUB_CMDLINE_LINUX_DEFAULT="quiet reboot=hard intel_idle.max_cstate=1"
```

Sometimes it helps to remove intel_idle entirely and leave only:
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet reboot=bios"
```

Additionally if all parameters don't help, there's a workaround instead of reboot use:
```bash
sudo systemctl kexec
```

## 11. SSH Key Configuration

```bash
# Create folder for keys
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Open authorized_keys file
nano ~/.ssh/authorized_keys

# Paste there (as one line):
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHNKOdVcE9EhXsjGimG00N86zo+ocaIzCx+0/KFTMiZU neoselcev@LenovoP14sgen2-Slava

# Save → Ctrl+O, Enter, Ctrl+X
# Set permissions
chmod 600 ~/.ssh/authorized_keys
```

## 12. Client SSH Configuration

On computer find SSH config folder.
Usually it's here: `C:\Users\<your_username>\.ssh\`

Create/open config file and paste:

```ssh-config
Host ha
    HostName 192.168.1.22
    Port 22
    User user
    IdentityFile C:\Users\neose\.ssh\id_ed25519
    
Host ha-vpn
    HostName 100.80.189.88
    Port 22
    User user
    IdentityFile C:\Users\neose\.ssh\id_ed25519
```

### Secure SSH Configuration

**Important Security Step**: Disable password authentication to allow only SSH key access.

```bash
# Disable password authentication for security
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Also ensure these security settings
sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# Reload SSH service to apply changes
sudo systemctl reload ssh

# Verify configuration
grep -E "PasswordAuthentication|PubkeyAuthentication|PermitRootLogin" /etc/ssh/sshd_config
```

Expected output:
```
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
```

**⚠️ Warning**: After applying these changes, you will only be able to connect via SSH keys, not passwords. Make sure your SSH key is working before applying these changes!

## 13. Tailscale Installation

```bash
sudo apt update
sudo apt install curl -y
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable tailscaled
sudo systemctl start tailscaled
sudo tailscale up
```

A link will appear. Open it and authorize in Tailscale via GitHub.

### Configure Tailscale Services for Home Assistant

After Tailscale is running, set up HTTPS access to Home Assistant:

```bash
# Enable Tailscale serve for Home Assistant (internal access)
sudo tailscale serve --bg 8443 http://localhost:8123

# Verify serve configuration
tailscale serve status
```

The serve command will create internal HTTPS access at:
`https://homeassistant.tail586076.ts.net:8443`

### Optional: Enable Tailscale Funnel (Public Access)

For public internet access (be careful with security):

```bash
# Enable funnel for public access
sudo tailscale funnel --bg 8443 on

# Verify funnel status
tailscale funnel status

# To disable public access later:
# sudo tailscale funnel --bg 8443 off
```

### Verify Tailscale Configuration

```bash
# Check Tailscale status
tailscale status

# Check all Tailscale services
systemctl list-units --type=service | grep tailscale

# Test HTTPS access
curl -k https://homeassistant.tail586076.ts.net:8443
```

## 14. Configure Firewall and DNS

```bash
sudo apt install -y ufw fail2ban
```

### Configure UFW Firewall with Network Restrictions

```bash
# Reset firewall to defaults
sudo ufw --force reset

# Set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH only from local network and Tailscale VPN
sudo ufw allow from 192.168.1.0/24 to any port 22 comment 'SSH - Local Network'
sudo ufw allow from 100.64.0.0/10 to any port 22 comment 'SSH - Tailscale VPN'

# Allow Home Assistant ports only from trusted networks
sudo ufw allow from 192.168.1.0/24 to any port 8123 comment 'Home Assistant - Local Network'
sudo ufw allow from 100.64.0.0/10 to any port 8123 comment 'Home Assistant - Tailscale VPN'

# Allow Node-RED ports only from trusted networks
sudo ufw allow from 192.168.1.0/24 to any port 1880 comment 'Node-RED - Local Network'
sudo ufw allow from 100.64.0.0/10 to any port 1880 comment 'Node-RED - Tailscale VPN'

# Enable firewall
sudo ufw --force enable

# Verify configuration
sudo ufw status numbered
```

### Configure Fail2ban for SSH Protection

**⚠️ Dell Wyse specific**: Use systemd backend instead of pyinotify

```bash
# Create Fail2ban configuration for SSH protection
sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[DEFAULT]
bantime = 10m
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
backend = systemd
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
maxretry = 3
bantime = 1h
EOF

# Enable and start Fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Verify Fail2ban status
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

Expected output:
```
Status
|- Number of jail:      1
`- Jail list:   sshd

Status for the jail: sshd
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     0
|  `- Journal matches:  _SYSTEMD_UNIT=ssh.service + _COMM=sshd
`- Actions
   |- Currently banned: 0
   |- Total banned:     0
   `- Banned IP list:
```

### Configure Fail2ban Telegram Security Alerts

**⚠️ Advanced Security**: Real-time Telegram notifications for security events

```bash
# Copy fail2ban Telegram notification files
ssh ha "sudo cp /tmp/homeassistant-setup/services/security/fail2ban-telegram-notify/telegram-notify.conf /etc/fail2ban/action.d/"
ssh ha "sudo cp /tmp/homeassistant-setup/services/security/fail2ban-telegram-notify/telegram-fail2ban-notify.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/telegram-fail2ban-notify.sh"

# Setup logrotate for security logs
ssh ha "sudo cp /tmp/homeassistant-setup/services/security/fail2ban-telegram-notify/fail2ban-telegram-notify.logrotate /etc/logrotate.d/fail2ban-telegram-notify"

# Create log file with correct permissions
ssh ha "sudo touch /var/log/fail2ban-telegram-notify.log && sudo chown user:user /var/log/fail2ban-telegram-notify.log"

# Update fail2ban configuration to include Telegram notifications
ssh ha "sudo cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.backup"
ssh ha "sudo cp /tmp/homeassistant-setup/services/security/fail2ban-telegram-notify/jail.local /etc/fail2ban/jail.local"

# Clear any existing fail2ban state to avoid conflicts
ssh ha "sudo systemctl stop fail2ban"
ssh ha "sudo rm -f /var/lib/fail2ban/fail2ban.sqlite3*"

# Restart fail2ban to apply Telegram integration
ssh ha "sudo systemctl start fail2ban"

# Verify Telegram integration
ssh ha "sudo fail2ban-client status sshd"

# Test notification system
ssh ha "/usr/local/bin/telegram-fail2ban-notify.sh start"
```

### Configure DNS Backup Servers

```bash
# Check current DNS configuration
ssh ha "cat /etc/resolv.conf"

# Add multiple backup DNS servers for redundancy
ssh ha "echo 'nameserver 8.8.8.8' | sudo tee -a /etc/resolv.conf"
ssh ha "echo 'nameserver 1.1.1.1' | sudo tee -a /etc/resolv.conf"

# Verify final DNS configuration
ssh ha "cat /etc/resolv.conf"
```

Expected output:
```
domain lan
search lan
nameserver 192.168.1.1    # Local router (primary)
nameserver 8.8.8.8        # Google DNS (backup)
nameserver 1.1.1.1        # Cloudflare DNS (backup)
```

```bash
# Test DNS resolution with multiple methods
ssh ha "getent hosts google.com"
ssh ha "ping -c 2 google.com"
ssh ha "ping -c 2 1.1.1.1"
```

## 15. Updates

```bash
# Update sources.list for complete repositories
sudo nano /etc/apt/sources.list
```

Add these lines:
```bash
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
```

Save → Ctrl+O, Enter, Ctrl+X.

```bash
sudo apt update
sudo apt upgrade -y
sudo apt full-upgrade -y
sudo apt autoremove -y
```

## 16. SWAP Configuration

```bash
# Create 2GB SWAP file
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Verify SWAP is active
sudo swapon --show
free -h
```

### Make SWAP Automatic at Boot

```bash
sudo nano /etc/fstab
```

Add line to the end:
```bash
/swapfile none swap sw 0 0
```

Save (Ctrl+O, Enter, Ctrl+X).

## 17. Install HTOP

```bash
sudo apt update
sudo apt install htop -y

# Run to monitor system resources
htop
```

## 18. Transfer Project Files and Configure Logging

### Copy Project Files
```bash
# Create directory and copy services
ssh ha "mkdir -p /tmp/homeassistant-setup"
scp -r ./services/ ha:/tmp/homeassistant-setup/
scp -r ./docker/ ha:/tmp/homeassistant-setup/
```

### Setup Logging Service
```bash
# Create configuration directories
ssh ha "sudo mkdir -p /etc/logging-service /var/log/homeassistant /var/log/monitoring /var/log/system-diagnostic"

# Copy logging configuration
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/logging-service/logging-service.conf /etc/logging-service/config"
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/logging-service/logging-service.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/logging-service.sh"

# Setup logrotate configurations
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/logging-service/logging-service.logrotate /etc/logrotate.d/logging-service"
ssh ha "sudo cp /tmp/homeassistant-setup/services/logrotate/* /etc/logrotate.d/"
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/ha-general-logs.logrotate /etc/logrotate.d/ha-general-logs"

# Fix log file permissions for Dell Wyse (x86_64 specific issue)
# IMPORTANT: Centralized logging requires user:user ownership for all managed logs
ssh ha "sudo touch /var/log/ha-system-diagnostic.log /var/log/ha-watchdog.log /var/log/ha-failure-notifier.log /var/log/ha-failures.log /var/log/ha-reboot.log"
ssh ha "sudo chown user:user /var/log/ha-system-diagnostic.log /var/log/ha-watchdog.log /var/log/ha-failure-notifier.log /var/log/ha-failures.log /var/log/ha-reboot.log"

# Optimize journald
ssh ha "sudo mkdir -p /etc/systemd/journald.conf.d"
ssh ha "sudo cp /tmp/homeassistant-setup/services/logrotate/journald.conf /etc/systemd/journald.conf.d/00-custom.conf"
ssh ha "sudo systemctl restart systemd-journald"

# Create log files with correct permissions
ssh ha "sudo touch /var/log/logging-service.log && sudo chown user:user /var/log/logging-service.log"
ssh ha "sudo chown user:user /var/log/homeassistant /var/log/monitoring /var/log/system-diagnostic"

# Fix critical log permissions for monitoring services (Dell Wyse specific)
ssh ha "sudo chown user:user /var/log/ha-watchdog.log /var/log/ha-failures.log /var/log/ha-failure-notifier.log"
ssh ha "sudo mkdir -p /var/lib/ha-failure-notifier && sudo chown -R user:user /var/lib/ha-failure-notifier"
ssh ha "sudo chown -R user:user /var/log/ha-*.log"
```

## 19. Configure Telegram Notifications

### Setup Telegram Service
```bash
# Create Telegram configuration directory
ssh ha "sudo mkdir -p /etc/telegram-sender"

# Copy Telegram configuration and script
ssh ha "sudo cp /tmp/homeassistant-setup/services/communication/telegram-sender/telegram-sender.conf /etc/telegram-sender/config"
ssh ha "sudo cp /tmp/homeassistant-setup/services/communication/telegram-sender/telegram-sender.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/telegram-sender.sh"

# Setup Telegram logrotate
ssh ha "sudo cp /tmp/homeassistant-setup/services/communication/telegram-sender/telegram-sender.logrotate /etc/logrotate.d/telegram-sender"

# Create Telegram log file with correct permissions
ssh ha "sudo touch /var/log/telegram-sender.log && sudo chmod 644 /var/log/telegram-sender.log && sudo chown user:user /var/log/telegram-sender.log"

# Secure Telegram configuration file (contains bot token)
ssh ha "sudo chmod 600 /etc/telegram-sender/config"
```

### Verify Logging Setup
```bash
# Check log directories
ssh ha "ls -la /var/log/ | grep -E '(telegram|logging|homeassistant)'"

# Check logrotate status
ssh ha "sudo logrotate -d /etc/logrotate.d/ha-general-logs"

# Check journald configuration
ssh ha "sudo systemctl status systemd-journald"
```

## 20. Configure System Monitoring Services

### Setup Backup Service
```bash
# Install backup service
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/ha-backup/ha-backup.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/ha-backup.sh"
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/ha-backup/ha-backup.service /etc/systemd/system/"
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/ha-backup/ha-backup.timer /etc/systemd/system/"
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/ha-backup/ha-backup.logrotate /etc/logrotate.d/ha-backup"
```

### Setup Update Checker
```bash
# Install update checker
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/update-checker/update-checker.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/update-checker.sh"
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/update-checker/update-checker.service /etc/systemd/system/"
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/update-checker/update-checker.timer /etc/systemd/system/"
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/update-checker/update-checker.logrotate /etc/logrotate.d/update-checker"
```

### Setup Nightly Reboot
```bash
# Install nightly reboot service
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/nightly-reboot/nightly-reboot.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/nightly-reboot.sh"
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/nightly-reboot/nightly-reboot.service /etc/systemd/system/"
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/nightly-reboot/nightly-reboot.timer /etc/systemd/system/"
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/nightly-reboot/nightly-reboot.logrotate /etc/logrotate.d/nightly-reboot"
```

## 21. Configure System Diagnostics

### Setup Diagnostic Services
```bash
# Install system diagnostic scripts
ssh ha "sudo cp /tmp/homeassistant-setup/services/diagnostics/system-diagnostic.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/system-diagnostic.sh"
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/system-diagnostic-startup/system-diagnostic-startup.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/system-diagnostic-startup.sh"

# Install systemd services for daily diagnostics
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/system-diagnostic-startup/system-diagnostic-startup.service /etc/systemd/system/"
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/system-diagnostic-startup/system-diagnostic-startup.timer /etc/systemd/system/"

# Setup logrotate for diagnostics
ssh ha "sudo cp /tmp/homeassistant-setup/services/diagnostics/system-diagnostic.logrotate /etc/logrotate.d/system-diagnostic"
ssh ha "sudo cp /tmp/homeassistant-setup/services/system/system-diagnostic-startup/system-diagnostic-startup.logrotate /etc/logrotate.d/system-diagnostic-startup"

# Create sysdiag command alias
ssh ha "sudo ln -sf /usr/local/bin/system-diagnostic.sh /usr/local/bin/sysdiag"
```

### Test System Diagnostics
```bash
# Run quick diagnostic test
ssh ha "sysdiag --quick"

# Run full system diagnostic
ssh ha "sysdiag --full"
```

## 22. Configure Home Assistant Monitoring

### Setup HA Watchdog
```bash
# Install HA watchdog service
ssh ha "sudo cp /tmp/homeassistant-setup/services/monitoring/ha-watchdog/ha-watchdog.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/ha-watchdog.sh"
ssh ha "sudo cp /tmp/homeassistant-setup/services/monitoring/ha-watchdog/ha-watchdog.service /etc/systemd/system/"
ssh ha "sudo cp /tmp/homeassistant-setup/services/monitoring/ha-watchdog/ha-watchdog.timer /etc/systemd/system/"
ssh ha "sudo cp /tmp/homeassistant-setup/services/monitoring/ha-watchdog/ha-watchdog.conf /etc/"
ssh ha "sudo cp /tmp/homeassistant-setup/services/monitoring/ha-watchdog/ha-watchdog.logrotate /etc/logrotate.d/ha-watchdog"
```

### Setup Failure Notifier
```bash
# Install failure notification service
ssh ha "sudo cp /tmp/homeassistant-setup/services/monitoring/ha-failure-notifier/ha-failure-notifier.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/ha-failure-notifier.sh"
ssh ha "sudo cp /tmp/homeassistant-setup/services/monitoring/ha-failure-notifier/ha-failure-notifier.service /etc/systemd/system/"
ssh ha "sudo cp /tmp/homeassistant-setup/services/monitoring/ha-failure-notifier/ha-failure-notifier.timer /etc/systemd/system/"
ssh ha "sudo cp /tmp/homeassistant-setup/services/monitoring/ha-failure-notifier/ha-failure-notifier.logrotate /etc/logrotate.d/ha-failure-notifier"
```

### Start All Monitoring Services

#### Enable and Start All Timers
```bash
# Reload systemd and enable all services
ssh ha "sudo systemctl daemon-reload"
ssh ha "sudo systemctl enable ha-backup.timer ha-watchdog.timer ha-failure-notifier.timer nightly-reboot.timer update-checker.timer system-diagnostic-startup.timer"
ssh ha "sudo systemctl start ha-backup.timer ha-watchdog.timer ha-failure-notifier.timer nightly-reboot.timer update-checker.timer system-diagnostic-startup.timer"
```

#### Dell Wyse Compatibility Fixes
```bash
# Create compatibility symlinks for monitoring services
ssh ha "sudo mkdir -p /etc/ha-watchdog && sudo ln -sf /etc/ha-watchdog.conf /etc/ha-watchdog/config"
ssh ha "sudo systemctl daemon-reload"
```

#### Verify All Services
```bash
# Check timer status
ssh ha "systemctl list-timers | grep -E '(ha-|nightly|update|system-diagnostic)'"

# Test Telegram notifications
ssh ha "/usr/local/bin/telegram-sender.sh 'Monitoring setup completed on Dell Wyse 3040' 2"

# Run quick system diagnostic
ssh ha "sysdiag --quick"
```

## 23. Docker Installation

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker user
sudo apt install -y docker-compose-plugin
```

## 24. Configure Docker Logging

```bash
sudo mkdir -p /etc/docker
sudo nano /etc/docker/daemon.json
```

Add:
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "7"
  }
}
```

```bash
sudo systemctl restart docker
```

## 25. Setup Home Assistant

```bash
sudo mkdir -p /opt/homeassistant
sudo cp -r /tmp/homeassistant-setup/docker/* /opt/homeassistant/
cd /opt/homeassistant
sudo chown -R user:user /opt/homeassistant
docker compose up -d
```

### Fix Backup and Telegram Services

After Home Assistant is running, fix critical service issues:

```bash
# Fix Home Assistant config permissions for backup service
ssh ha "sudo chmod -R a+r /opt/homeassistant/homeassistant"

# Fix backup directory permissions  
ssh ha "sudo chown -R user:user /opt/backups"

# Test backup functionality
ssh ha "/usr/local/bin/ha-backup.sh"

# Test Telegram with hostname (should show [HomeAssistant] prefix)
ssh ha "/usr/local/bin/telegram-sender.sh 'System setup completed successfully!' 2"
```

## 26. Final System Verification

```bash
# Check all monitoring timers
ssh ha "systemctl list-timers | grep -E '(ha-|nightly|update|system-diagnostic)'"

# Run comprehensive system diagnostic
ssh ha "sysdiag --full"

# Test temperature monitoring
ssh ha "temp"

# Check Docker containers
ssh ha "docker ps"

# Verify log rotation
ssh ha "sudo logrotate -d /etc/logrotate.d/ha-general-logs"

# Test all Telegram notifications
ssh ha "/usr/local/bin/telegram-sender.sh 'Final system test - all services operational' 2"
```

### Important Notes About System Logs

**Normal "Errors" You Can Ignore:**

```bash
# These SSH kex errors are NORMAL - they're from ha-watchdog monitoring SSH every 2 minutes
# Check logs: sudo journalctl -u ssh.service | grep kex_exchange_identification
# Pattern: "Connection closed by ::1" (localhost IPv6) every ~2 minutes
# This is ha-watchdog testing SSH connectivity - completely normal behavior
```

Expected log entries:
```
Oct 03 20:27:01 HomeAssistant sshd[151899]: error: kex_exchange_identification: Connection closed by remote host
Oct 03 20:27:01 HomeAssistant sshd[151899]: Connection closed by ::1 port 37060
```

These are **monitoring checks, not security threats**.

HomeAssistant
192.168.1.22	
A4:bb:6d:20:67:77	

id_ed25519
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBzSjnVXBPRIV7IxophtNDfOs6PqHGiMwsftPyhUzImVAAAAKjNropLza6K
SwAAAAtzc2gtZWQyNTUxOQAAACBzSjnVXBPRIV7IxophtNDfOs6PqHGiMwsftPyhUzImVA
AAAEBwxp6MW7O9+NzY2hv/rg6blSU5BRwUkJPIXLrmr4Jwn3NKOdVcE9EhXsjGimG00N86
zo+ocaIzCx+0/KFTMiZUAAAAHm5lb3NlbGNldkBMZW5vdm9QMTRzZ2VuMi1TbGF2YQECAw
QFBgc=
-----END OPENSSH PRIVATE KEY-----

id_ed25519.pub
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHNKOdVcE9EhXsjGimG00N86zo+ocaIzCx+0/KFTMiZU neoselcev@LenovoP14sgen2-Slava
## 27. Setup Cloudflare Tunnel (Optional)

### Prerequisites

- Domain registered and added to Cloudflare
- Access to Cloudflare Dashboard
- Docker and Docker Compose already installed

### Temporary Setup for Tunnel Creation

```bash
# Download and install cloudflared temporarily (for tunnel creation only)
ssh ha "curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
ssh ha "sudo dpkg -i cloudflared.deb"
ssh ha "cloudflared --version"
```

### Authenticate with Cloudflare

```bash
# Login to Cloudflare (will provide URL to open in browser)
ssh ha "cloudflared tunnel login"
# Follow the URL provided and authenticate in browser
# Certificate will be saved to /root/.cloudflared/cert.pem
```

### Create Tunnel

```bash
# Create tunnel
ssh ha "cloudflared tunnel create homeassistant-tunnel"
# Save the tunnel ID that is displayed (e.g., a1b2c3d4-e5f6-7890-abcd-ef1234567890)

# Setup DNS routing
ssh ha "cloudflared tunnel route dns homeassistant-tunnel ha.[YOUR-DOMAIN]"
ssh ha "cloudflared tunnel route dns homeassistant-tunnel test.[YOUR-DOMAIN]"
```

### Configure Docker Setup

```bash
# Create Docker configuration directory
ssh ha "sudo mkdir -p /opt/homeassistant/cloudflared"
ssh ha "sudo mkdir -p /opt/homeassistant/nginx-auth/html"
ssh ha "sudo mkdir -p /opt/homeassistant/html"

# Copy tunnel credentials to Docker directory
ssh ha "sudo cp /root/.cloudflared/*.json /opt/homeassistant/cloudflared/"
ssh ha "sudo cp /root/.cloudflared/cert.pem /opt/homeassistant/cloudflared/"

# Create Docker tunnel configuration
ssh ha "sudo tee /opt/homeassistant/cloudflared/config.yml << 'CFEOF'
tunnel: TUNNEL_ID_HERE
credentials-file: /etc/cloudflared/TUNNEL_ID_HERE.json

ingress:
  # Home Assistant Admin Panel (with Basic Auth + Cloudflare Access)
  - hostname: ha.[YOUR-DOMAIN]
    service: http://ha-proxy:8080
  # Test web page (Docker service name)
  - hostname: test.[YOUR-DOMAIN]
    service: http://test-web:80
  # Catch-all rule (required)
  - service: http_status:404
CFEOF"

# Replace TUNNEL_ID_HERE with your actual tunnel ID
# Replace [YOUR-DOMAIN] with your actual domain

# Create nginx-auth directory for Basic Authentication
ssh ha "sudo mkdir -p /opt/homeassistant/nginx-auth"

# Create nginx configuration with Basic Auth
ssh ha "sudo tee /opt/homeassistant/nginx-auth/nginx.conf << 'NGINXEOF'
events {
    worker_connections 1024;
}

http {
    server {
        listen 8080;
        server_name _;
        
        # Serve login page for root path when not authenticated
        location = / {
            auth_basic off;
            root /usr/share/nginx/html;
            try_files /login.html =404;
        }
        
        # Admin path requires authentication
        location /admin {
            auth_basic \"Home Assistant Admin Access\";
            auth_basic_user_file /etc/nginx/.htpasswd;
            
            rewrite ^/admin(.*)\$ /\$1 break;
            
            proxy_pass http://homeassistant:8123;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \"upgrade\";
        }
        
        # All other paths require authentication
        location / {
            auth_basic \"Home Assistant Admin Access\";
            auth_basic_user_file /etc/nginx/.htpasswd;
            
            proxy_pass http://homeassistant:8123;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \"upgrade\";
        }
    }
}
NGINXEOF"

# Install htpasswd utility for creating password file
ssh ha "sudo apt-get install -y apache2-utils"

# Create .htpasswd file with admin user
# Default password: HA2024SecurePass (change this!)
ssh ha "sudo htpasswd -cb /opt/homeassistant/nginx-auth/.htpasswd admin HA2024SecurePass"

# Set appropriate permissions
ssh ha "sudo chmod 644 /opt/homeassistant/nginx-auth/.htpasswd"

# Create custom login page (workaround for Chrome Basic Auth issue)
ssh ha "sudo mkdir -p /opt/homeassistant/nginx-auth/html"
ssh ha "sudo tee /opt/homeassistant/nginx-auth/html/login.html > /dev/null << 'HTMLEOF'
<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Home Assistant Login</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #41b883 0%, #35495e 100%);
        }
        .login-box {
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 10px 25px rgba(0,0,0,0.2);
            max-width: 400px;
            width: 100%;
        }
        h2 {
            margin-top: 0;
            color: #333;
            text-align: center;
            font-size: 24px;
        }
        .icon {
            text-align: center;
            font-size: 48px;
            margin-bottom: 10px;
        }
        .form-group {
            margin-bottom: 20px;
        }
        label {
            display: block;
            margin-bottom: 5px;
            color: #555;
            font-weight: 600;
        }
        input {
            width: 100%;
            padding: 12px;
            border: 2px solid #e0e0e0;
            border-radius: 6px;
            box-sizing: border-box;
            font-size: 14px;
            transition: border-color 0.3s;
        }
        input:focus {
            outline: none;
            border-color: #41b883;
        }
        button {
            width: 100%;
            padding: 14px;
            background: #41b883;
            color: white;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-size: 16px;
            font-weight: 600;
            transition: background 0.3s;
        }
        button:hover {
            background: #35a06f;
        }
        button:active {
            transform: translateY(1px);
        }
    </style>
</head>
<body>
    <div class=\"login-box\">
        <div class=\"icon\">🏠</div>
        <h2>Home Assistant Admin</h2>
        <form id=\"loginForm\">
            <div class=\"form-group\">
                <label for=\"username\">Username:</label>
                <input type=\"text\" id=\"username\" name=\"username\" required autocomplete=\"username\" autofocus>
            </div>
            <div class=\"form-group\">
                <label for=\"password\">Password:</label>
                <input type=\"password\" id=\"password\" name=\"password\" required autocomplete=\"current-password\">
            </div>
            <button type=\"submit\">Login</button>
        </form>
    </div>
    <script>
        document.getElementById('loginForm').addEventListener('submit', function(e) {
            e.preventDefault();
            const username = document.getElementById('username').value;
            const password = document.getElementById('password').value;
            const protocol = window.location.protocol;
            const host = window.location.host;
            const url = protocol + '//' + encodeURIComponent(username) + ':' + encodeURIComponent(password) + '@' + host + '/admin';
            window.location.href = url;
        });
    </script>
</body>
</html>
HTMLEOF"

# Create test web page
ssh ha "sudo tee /opt/homeassistant/html/index.html > /dev/null << 'TESTEOF'
<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Home Assistant Test Page</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #41b883 0%, #35495e 100%);
            color: white;
        }
        .container {
            text-align: center;
            padding: 40px;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 15px;
            backdrop-filter: blur(10px);
        }
        h1 {
            font-size: 3em;
            margin: 0 0 20px 0;
        }
        p {
            font-size: 1.2em;
            margin: 10px 0;
        }
        .status {
            display: inline-block;
            padding: 10px 20px;
            background: #41b883;
            border-radius: 25px;
            margin-top: 20px;
            font-weight: bold;
        }
        .info {
            margin-top: 30px;
            padding-top: 30px;
            border-top: 1px solid rgba(255, 255, 255, 0.3);
        }
        .icon {
            font-size: 5em;
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class=\"container\">
        <div class=\"icon\">🏠</div>
        <h1>Home Assistant Test Page</h1>
        <p>Cloudflare Tunnel is <span class=\"status\">✅ ACTIVE</span></p>
        <div class=\"info\">
            <p><strong>System:</strong> Home Assistant Monitoring</p>
            <p><strong>Location:</strong> Dell Wyse 3040</p>
            <p><strong>Network:</strong> 192.168.1.22</p>
            <p><strong>Tunnel:</strong> Cloudflare Edge Network</p>
        </div>
    </div>
</body>
</html>
TESTEOF"
```

### Setup DNS Routes

```bash
# Create DNS route for admin panel
ssh ha "cloudflared tunnel route dns [TUNNEL_ID] ha.[YOUR-DOMAIN]"

# Create DNS route for test page
ssh ha "cloudflared tunnel route dns [TUNNEL_ID] test.[YOUR-DOMAIN]"
```

### Deploy with Docker Compose

```bash
# Update docker-compose.yml to include cloudflared, ha-proxy, and test-web services
# Copy the docker-compose-with-tunnel.yml from the project to /opt/homeassistant/

ssh ha "cd /opt/homeassistant && sudo docker compose -f docker-compose-with-tunnel.yml up -d"

# Verify containers are running
ssh ha "sudo docker ps | grep -E 'homeassistant|ha-proxy|cloudflared|test-web'"
```

### Remove Temporary Installation

```bash
# Remove temporary binary installation
ssh ha "sudo apt remove cloudflared -y"
ssh ha "rm cloudflared.deb"
ssh ha "sudo rm -rf /etc/cloudflared"
```

### Test Docker Configuration

```bash
# Check container logs
ssh ha "sudo docker logs cloudflared-tunnel"

# Verify tunnel status
ssh ha "sudo docker exec cloudflared-tunnel cloudflared tunnel info"

# Validate ingress configuration
ssh ha "sudo docker exec cloudflared-tunnel cloudflared tunnel ingress validate"
```

### Verify Public Access

```bash
# Test public test page
curl -I https://test.[YOUR-DOMAIN]

# Should return HTTP/2 200 with Cloudflare headers:
# cf-ray: xxxxx-YYY
# server: cloudflare

# Test Home Assistant admin panel (should show login page)
curl -I https://ha.[YOUR-DOMAIN]

# Should return HTTP/2 200 with login page HTML
```

**Access Instructions**:

1. **Open in Browser**: Navigate to `https://ha.[YOUR-DOMAIN]`
2. **Enter HTTP Basic Auth**: Enter credentials in the web form:
   - Username: `admin`
   - Password: `HA2024SecurePass` (or your custom password)
3. Click "Login" button
4. **Enter Home Assistant Login**: Use your Home Assistant credentials

**Alternative Methods** (if needed):
- Firefox/Safari may show standard Basic Auth dialog
- Direct URL with credentials: `https://admin:HA2024SecurePass@ha.[YOUR-DOMAIN]/admin`

**Note**: Chrome/Chromium browsers don't display Basic Auth dialogs for HTTPS through Cloudflare tunnels. The custom login page solves this limitation.

### Monitor Docker Tunnel

```bash
# Check container status
ssh ha "sudo docker ps | grep cloudflared"

# View real-time logs
ssh ha "sudo docker logs -f cloudflared-tunnel"

# Check tunnel health
ssh ha "sudo docker exec cloudflared-tunnel cloudflared tunnel info"
```

### Security Configuration (Optional)

**Dual Authentication Setup**:

For maximum security, add Cloudflare Access (Zero Trust) with OAuth before Basic Auth.

See AdGuard install_plan Section 26 "Security Configuration" for detailed OAuth setup with GitHub and Google.

### Cloudflare Tunnel Benefits

- ✅ **Zero Port Forwarding**: No open ports on router/firewall
- ✅ **Automatic SSL**: Cloudflare handles certificates
- ✅ **DDoS Protection**: Edge-level protection
- ✅ **Hidden Origin IP**: Real server IP not exposed
- ✅ **Geographic Distribution**: Multiple edge locations
- ✅ **Zero Trust Ready**: Can add authentication layers

## 28. Create Management Control Script

### Create ha-monitoring-control

```bash
# Create comprehensive monitoring control script
ssh ha "sudo tee /usr/local/bin/ha-monitoring-control > /dev/null << 'EOF'
#!/bin/bash

case \"\$1\" in
    start)
        systemctl start ha-watchdog.timer
        systemctl start ha-failure-notifier.timer
        systemctl start boot-notifier.timer
        systemctl start nightly-reboot.timer
        [[ -f /etc/systemd/system/logging-service.service ]] && systemctl start logging-service.service
        [[ -f /etc/systemd/system/update-checker.timer ]] && systemctl start update-checker.timer
        [[ -f /etc/systemd/system/ha-backup.timer ]] && systemctl start ha-backup.timer
        [[ -f /etc/systemd/system/system-diagnostic-startup.timer ]] && systemctl start system-diagnostic-startup.timer
        [[ -f /etc/systemd/system/tailscaled.service ]] && systemctl start tailscaled
        echo \"✅ All Home Assistant monitoring services started\"
        ;;
    stop)
        systemctl stop ha-watchdog.timer
        systemctl stop ha-failure-notifier.timer
        systemctl stop boot-notifier.timer
        systemctl stop nightly-reboot.timer
        [[ -f /etc/systemd/system/logging-service.service ]] && systemctl stop logging-service.service
        [[ -f /etc/systemd/system/update-checker.timer ]] && systemctl stop update-checker.timer
        [[ -f /etc/systemd/system/ha-backup.timer ]] && systemctl stop ha-backup.timer
        [[ -f /etc/systemd/system/system-diagnostic-startup.timer ]] && systemctl stop system-diagnostic-startup.timer
        echo \"⏹️ All Home Assistant monitoring services stopped\"
        ;;
    restart)
        systemctl restart ha-watchdog.timer
        systemctl restart ha-failure-notifier.timer
        systemctl restart boot-notifier.timer
        systemctl restart nightly-reboot.timer
        [[ -f /etc/systemd/system/logging-service.service ]] && systemctl restart logging-service.service
        [[ -f /etc/systemd/system/update-checker.timer ]] && systemctl restart update-checker.timer
        [[ -f /etc/systemd/system/tailscaled.service ]] && systemctl restart tailscaled
        echo \"🔄 All Home Assistant monitoring services restarted\"
        ;;
    status)
        echo \"📊 Home Assistant Monitoring Services Status:\"
        echo \"--- Core Monitoring ---\"
        systemctl status ha-watchdog.timer --no-pager -l
        systemctl status ha-failure-notifier.timer --no-pager -l
        systemctl status boot-notifier.timer --no-pager -l
        echo \"--- System Maintenance ---\"
        systemctl status nightly-reboot.timer --no-pager -l
        [[ -f /etc/systemd/system/update-checker.timer ]] && systemctl status update-checker.timer --no-pager -l
        echo \"--- VPN Access ---\"
        [[ -f /etc/systemd/system/tailscaled.service ]] && systemctl status tailscaled --no-pager -l
        ;;
    logs)
        echo \"📋 System Watchdog logs:\"
        tail -20 /var/log/ha-watchdog.log 2>/dev/null || echo \"Log file not found\"
        echo \"\"
        echo \"📋 Failure notifier logs:\"
        tail -20 /var/log/ha-failure-notifier.log 2>/dev/null || echo \"Log file not found\"
        echo \"\"
        echo \"📋 Backup logs:\"
        tail -10 /var/log/ha-backup.log 2>/dev/null || echo \"Log file not found\"
        ;;
    log-sizes)
        echo \"�� Log file sizes:\"
        du -sh /var/log/ha-*.log /var/log/telegram-sender.log /var/log/boot-notifier.log 2>/dev/null | sort -h
        echo \"\"
        echo \"📊 Journal size:\"
        journalctl --disk-usage
        ;;
    rotate-logs)
        echo \"🔄 Forcing log rotation...\"
        sudo logrotate -f /etc/logrotate.d/ha-general-logs
        echo \"✅ Log rotation completed\"
        ;;
    clean-journal)
        echo \"🧹 Cleaning systemd journal...\"
        BEFORE=\$(journalctl --disk-usage | grep -oP '\d+\.\d+[A-Z]+')
        echo \"Size before: \$BEFORE\"
        sudo journalctl --vacuum-size=500M
        AFTER=\$(journalctl --disk-usage | grep -oP '\d+\.\d+[A-Z]+')
        echo \"Size after: \$AFTER\"
        ;;
    test-telegram)
        echo \"🧪 Testing Telegram notifications...\"
        if [[ -x \"/usr/local/bin/telegram-sender.sh\" ]] && [[ -f \"/etc/telegram-sender/config\" ]]; then
            /usr/local/bin/telegram-sender.sh \"Home Assistant monitoring system test - \$(date)\" 2
        else
            echo \"❌ Telegram sender not configured\"
            echo \"📝 Configure /etc/telegram-sender/config\"
        fi
        ;;
    diagnostic)
        if [[ -f /usr/local/bin/system-diagnostic.sh ]]; then
            /usr/local/bin/system-diagnostic.sh
        else
            echo \"❌ Diagnostic script not found\"
        fi
        ;;
    *)
        echo \"Usage: \$0 {start|stop|restart|status|logs|log-sizes|rotate-logs|clean-journal|test-telegram|diagnostic}\"
        exit 1
        ;;
esac
EOF'"

# Make script executable
ssh ha "sudo chmod +x /usr/local/bin/ha-monitoring-control"

# Create convenient aliases
ssh ha "echo 'alias ha-start=\"ha-monitoring-control start\"' >> ~/.bashrc"
ssh ha "echo 'alias ha-stop=\"ha-monitoring-control stop\"' >> ~/.bashrc"
ssh ha "echo 'alias ha-status=\"ha-monitoring-control status\"' >> ~/.bashrc"
ssh ha "echo 'alias ha-logs=\"ha-monitoring-control logs\"' >> ~/.bashrc"
ssh ha "source ~/.bashrc"
```

### Test Management Script

```bash
# Test status command
ssh ha "ha-monitoring-control status"

# Test logs command
ssh ha "ha-monitoring-control logs"

# Test Telegram
ssh ha "ha-monitoring-control test-telegram"
```

## 29. Setup Docker Audit Logging

### Install auditd

```bash
# Install audit daemon
ssh ha "sudo apt-get update && sudo apt-get install -y auditd audispd-plugins"

# Enable and start auditd
ssh ha "sudo systemctl enable auditd"
ssh ha "sudo systemctl start auditd"

# Verify installation
ssh ha "sudo auditctl -v"
ssh ha "sudo systemctl status auditd"
```

### Create Docker Audit Rules

```bash
# Create Docker audit rules file
ssh ha "sudo tee /etc/audit/rules.d/docker.rules > /dev/null << 'DOCKEREOF'
# Docker Audit Rules for Home Assistant System
# Monitor all Docker daemon and container operations

# Docker daemon execution
-w /usr/bin/dockerd -p x -k docker_daemon

# Docker socket access (all container operations go through this)
-w /var/run/docker.sock -p rwxa -k docker_socket

# Container runtime binaries
-w /usr/bin/containerd -p x -k container_runtime
-w /usr/bin/runc -p x -k container_runtime
-w /usr/bin/docker-containerd -p x -k container_runtime
-w /usr/bin/docker-runc -p x -k container_runtime

# Docker configuration changes
-w /etc/docker/ -p wa -k docker_config
-w /etc/default/docker -p wa -k docker_config
-w /opt/homeassistant/docker-compose.yml -p wa -k docker_compose
-w /opt/homeassistant/docker-compose-with-tunnel.yml -p wa -k docker_compose

# Docker systemd service changes
-w /etc/systemd/system/docker.service -p wa -k docker_systemd
-w /etc/systemd/system/docker.service.d/ -p wa -k docker_systemd
-w /lib/systemd/system/docker.service -p wa -k docker_systemd

# Container data directories (optional, can generate many events)
# -w /var/lib/docker/ -p wa -k docker_data

# Docker CLI commands
-a always,exit -F path=/usr/bin/docker -F perm=x -k docker_command
DOCKEREOF"

# Reload audit rules
ssh ha "sudo augenrules --load"

# Verify rules are loaded
ssh ha "sudo auditctl -l | grep docker"
```

### Configure journald for Docker Logs

```bash
# Backup original journald config
ssh ha "sudo cp /etc/systemd/journald.conf /etc/systemd/journald.conf.bak"

# Configure journald retention
ssh ha "sudo tee /etc/systemd/journald.conf > /dev/null << 'JOURNALEOF'
[Journal]
# Persistent storage
Storage=persistent

# Maximum disk usage
SystemMaxUse=500M
SystemKeepFree=1G

# Retention policies
MaxRetentionSec=1month
MaxFileSec=1week

# Rate limiting
RateLimitIntervalSec=30s
RateLimitBurst=10000

# Forward to syslog (optional)
ForwardToSyslog=no
ForwardToWall=no
JOURNALEOF"

# Restart journald to apply changes
ssh ha "sudo systemctl restart systemd-journald"

# Verify configuration
ssh ha "journalctl --disk-usage"
```

### Test Docker Audit Logging

```bash
# Generate some Docker events
ssh ha "sudo docker ps"
ssh ha "sudo docker images"

# Wait a few seconds for audit to write
sleep 3

# Check audit logs for Docker events
ssh ha "sudo ausearch -k docker_socket -ts recent | head -20"
ssh ha "sudo ausearch -k docker_daemon -ts recent"

# Check Docker daemon journal
ssh ha "sudo journalctl -u docker -n 50 --no-pager"
```

### View Docker Audit Reports

```bash
# Recent Docker socket access
ssh ha "sudo ausearch -k docker_socket -ts today"

# Docker configuration changes
ssh ha "sudo ausearch -k docker_config -k docker_compose -ts this-week"

# Docker command execution
ssh ha "sudo ausearch -k docker_command -ts today"

# Generate Docker audit summary
ssh ha "sudo aureport -f | grep docker"
```

### Integrate with System Diagnostic

Audit logs are automatically checked by `system-diagnostic.sh`:

```bash
# Run full diagnostic (includes Docker audit check)
ssh ha "sysdiag"

# Manual check of Docker audit events
ssh ha "sudo ausearch -k docker_daemon -k docker_socket --start recent"
```

### Create Docker Audit Monitoring Script (Optional)

```bash
# Create monitoring script for Docker audit alerts
ssh ha "sudo tee /usr/local/bin/docker-audit-monitor.sh > /dev/null << 'MONITOREOF'
#!/bin/bash
# Docker Audit Event Monitor
# Sends Telegram alerts for suspicious Docker operations

TELEGRAM_SENDER=\"/usr/local/bin/telegram-sender.sh\"
LAST_CHECK_FILE=\"/var/run/docker-audit-last-check\"

# Get timestamp of last check (or 1 hour ago if first run)
if [[ -f \"\$LAST_CHECK_FILE\" ]]; then
    LAST_CHECK=\$(cat \"\$LAST_CHECK_FILE\")
else
    LAST_CHECK=\$(date -d '1 hour ago' '+%m/%d/%Y %H:%M:%S')
fi

# Check for suspicious Docker events
SUSPICIOUS_EVENTS=\$(ausearch -k docker_socket -k docker_config -ts \"\$LAST_CHECK\" --success yes 2>/dev/null | grep -E \"SYSCALL|type=PATH\" | wc -l)

if [[ \"\$SUSPICIOUS_EVENTS\" -gt 10 ]]; then
    MESSAGE=\"🚨 Docker Audit Alert: \$SUSPICIOUS_EVENTS events detected since \$LAST_CHECK\"
    \"\$TELEGRAM_SENDER\" \"\$MESSAGE\" 2
fi

# Update last check timestamp
date '+%m/%d/%Y %H:%M:%S' > \"\$LAST_CHECK_FILE\"
MONITOREOF"

# Make executable
ssh ha "sudo chmod +x /usr/local/bin/docker-audit-monitor.sh"

# Test the script
ssh ha "sudo /usr/local/bin/docker-audit-monitor.sh"
```

### Docker Audit Best Practices

- ✅ **Monitor socket access** - All container operations go through `/var/run/docker.sock`
- ✅ **Track configuration changes** - Audit `/etc/docker/` and compose files
- ✅ **Limit log size** - Configure journald retention to prevent disk fill
- ✅ **Regular review** - Check audit logs weekly for anomalies
- ✅ **Integrate monitoring** - Include Docker audit in system diagnostics

**Note:** Docker audit logging can generate significant log volume. Monitor disk usage with `journalctl --disk-usage` and adjust retention settings if needed.

## 30. Setup System Auditing (auditd)

### Install auditd (if not already installed)

```bash
# Check if auditd is installed
ssh ha "dpkg -l | grep auditd"

# If not installed:
ssh ha "sudo apt-get update && sudo apt-get install -y auditd audispd-plugins"

# Enable and start auditd
ssh ha "sudo systemctl enable auditd"
ssh ha "sudo systemctl start auditd"
```

### Configure auditd

```bash
# Backup original configuration
ssh ha "sudo cp /etc/audit/auditd.conf /etc/audit/auditd.conf.bak"

# Configure audit log retention
ssh ha "sudo sed -i 's/^max_log_file = .*/max_log_file = 10/' /etc/audit/auditd.conf"
ssh ha "sudo sed -i 's/^num_logs = .*/num_logs = 10/' /etc/audit/auditd.conf"
ssh ha "sudo sed -i 's/^max_log_file_action = .*/max_log_file_action = ROTATE/' /etc/audit/auditd.conf"

# Verify configuration
ssh ha "sudo grep -E 'max_log_file|num_logs|max_log_file_action' /etc/audit/auditd.conf"
```

### Create Comprehensive Audit Rules

```bash
# Create system audit rules file
ssh ha "sudo tee /etc/audit/rules.d/audit.rules > /dev/null << 'AUDITEOF'
# System Audit Rules for Home Assistant Server
# Monitors security-critical system operations

# ===== SSH Access Monitoring =====
# SSH daemon
-w /usr/sbin/sshd -p x -k ssh_daemon

# SSH configuration
-w /etc/ssh/sshd_config -p wa -k ssh_config
-w /etc/ssh/ssh_config -p wa -k ssh_config

# SSH keys
-w /home/macbookpro12-1/.ssh/ -p wa -k ssh_keys
-w /root/.ssh/ -p wa -k ssh_keys

# PAM authentication
-w /etc/pam.d/ -p wa -k pam_config
-w /var/log/auth.log -p wa -k auth_log

# ===== systemd Service Changes =====
# systemd unit files
-w /etc/systemd/system/ -p wa -k systemd_units
-w /usr/lib/systemd/system/ -p wa -k systemd_units
-w /lib/systemd/system/ -p wa -k systemd_units

# systemd control commands
-a always,exit -F arch=b64 -S execve -F path=/bin/systemctl -k systemd_control
-a always,exit -F arch=b64 -S execve -F path=/usr/bin/systemctl -k systemd_control

# ===== Firewall Changes =====
# UFW configuration
-w /etc/ufw/ -p wa -k firewall_config
-w /usr/sbin/ufw -p x -k firewall_cmd
-w /etc/default/ufw -p wa -k firewall_config

# iptables direct access
-w /usr/sbin/iptables -p x -k firewall_iptables
-w /usr/sbin/ip6tables -p x -k firewall_iptables
-w /sbin/iptables -p x -k firewall_iptables
-w /sbin/ip6tables -p x -k firewall_iptables

# Netfilter configuration (socket options)
-a always,exit -F arch=b64 -S setsockopt -F a0=41 -k netfilter_config

# ===== Privilege Escalation =====
# sudo usage
-w /usr/bin/sudo -p x -k sudo_usage
-w /etc/sudoers -p wa -k sudo_config
-w /etc/sudoers.d/ -p wa -k sudo_config

# su command
-w /usr/bin/su -p x -k privilege_escalation
-w /bin/su -p x -k privilege_escalation

# ===== User and Group Changes =====
# Password files
-w /etc/passwd -p wa -k user_modification
-w /etc/shadow -p wa -k user_modification
-w /etc/group -p wa -k group_modification
-w /etc/gshadow -p wa -k group_modification

# User management commands
-w /usr/sbin/useradd -p x -k user_management
-w /usr/sbin/userdel -p x -k user_management
-w /usr/sbin/usermod -p x -k user_management
-w /usr/sbin/groupadd -p x -k group_management
-w /usr/sbin/groupdel -p x -k group_management
-w /usr/sbin/groupmod -p x -k group_management

# ===== Monitoring Service Files =====
# Monitoring scripts
-w /usr/local/bin/ha-watchdog.sh -p wa -k monitoring_scripts
-w /usr/local/bin/ha-failure-notifier.sh -p wa -k monitoring_scripts
-w /usr/local/bin/system-diagnostic.sh -p wa -k monitoring_scripts
-w /usr/local/bin/telegram-sender.sh -p wa -k monitoring_scripts
-w /usr/local/bin/boot-notifier.sh -p wa -k monitoring_scripts
-w /usr/local/bin/ha-monitoring-control -p wa -k monitoring_scripts

# Configuration files
-w /etc/ha-watchdog.conf -p wa -k monitoring_config
-w /etc/telegram-sender/ -p wa -k telegram_config

# ===== System Configuration =====
# Kernel modules
-w /sbin/insmod -p x -k kernel_modules
-w /sbin/rmmod -p x -k kernel_modules
-w /sbin/modprobe -p x -k kernel_modules
-a always,exit -F arch=b64 -S init_module,delete_module -k kernel_modules

# System time changes
-a always,exit -F arch=b64 -S adjtimex,settimeofday -k time_change
-a always,exit -F arch=b64 -S clock_settime -F a0=0 -k time_change
-w /etc/localtime -p wa -k time_change

# Network configuration
-w /etc/network/ -p wa -k network_config
-w /etc/hosts -p wa -k network_config
-w /etc/hostname -p wa -k network_config
-w /etc/resolv.conf -p wa -k network_config

# Cron jobs
-w /etc/cron.allow -p wa -k cron_config
-w /etc/cron.deny -p wa -k cron_config
-w /etc/cron.d/ -p wa -k cron_config
-w /etc/cron.daily/ -p wa -k cron_config
-w /etc/cron.hourly/ -p wa -k cron_config
-w /etc/cron.monthly/ -p wa -k cron_config
-w /etc/cron.weekly/ -p wa -k cron_config
-w /etc/crontab -p wa -k cron_config
-w /var/spool/cron/ -p wa -k cron_config

# Package management
-w /usr/bin/apt -p x -k package_management
-w /usr/bin/apt-get -p x -k package_management
-w /usr/bin/dpkg -p x -k package_management

# Make rules immutable (must be last rule)
# -e 2
AUDITEOF"

# Reload audit rules
ssh ha "sudo augenrules --load"

# List loaded rules
ssh ha "sudo auditctl -l | wc -l"
```

### Test System Auditing

```bash
# Generate test events
ssh ha "sudo systemctl status docker"  # systemd event
ssh ha "sudo cat /etc/ssh/sshd_config > /dev/null"  # SSH config access

# Wait for audit to write
sleep 2

# Check SSH monitoring
ssh ha "sudo ausearch -k ssh_daemon -ts recent"

# Check systemd monitoring
ssh ha "sudo ausearch -k systemd_control -ts recent"

# Check SSH config access
ssh ha "sudo ausearch -k ssh_config -ts recent"
```

### View Audit Reports

```bash
# Summary of all audit events
ssh ha "sudo aureport --summary"

# Authentication attempts (successful and failed)
ssh ha "sudo aureport --auth"

# Failed authentication attempts
ssh ha "sudo aureport --auth --failed"

# Command executions
ssh ha "sudo aureport -x --summary"

# File access events
ssh ha "sudo aureport -f --summary"

# User events
ssh ha "sudo aureport -u --summary"
```

### Common Audit Queries

```bash
# ===== SSH Monitoring =====
# All SSH daemon events today
ssh ha "sudo ausearch -k ssh_daemon -ts today -i"

# Failed SSH login attempts
ssh ha "sudo ausearch -k ssh_daemon --success no -ts this-week -i"

# SSH configuration changes
ssh ha "sudo ausearch -k ssh_config -ts this-month -i"

# ===== System Changes =====
# systemd service modifications
ssh ha "sudo ausearch -k systemd_units -ts today -i"

# systemctl command executions
ssh ha "sudo ausearch -k systemd_control -ts today -i"

# Firewall rule changes
ssh ha "sudo ausearch -k firewall_config -k firewall_cmd -ts today -i"

# ===== Security Events =====
# All sudo usage today
ssh ha "sudo ausearch -k sudo_usage -ts today -i"

# Failed sudo attempts
ssh ha "sudo ausearch -k sudo_usage --success no -ts this-week -i"

# User/group modifications
ssh ha "sudo ausearch -k user_modification -k group_modification -ts this-month -i"

# ===== Monitoring System =====
# Changes to monitoring scripts
ssh ha "sudo ausearch -k monitoring_scripts -ts this-week -i"

# Changes to monitoring configuration
ssh ha "sudo ausearch -k monitoring_config -ts this-week -i"
```

### Integrate with System Diagnostic

Add audit checks to system diagnostic script:

```bash
# System diagnostic automatically checks audit status
ssh ha "sysdiag"

# Manual audit health check
ssh ha "sudo auditctl -s"  # Audit status
ssh ha "sudo auditctl -l | wc -l"  # Number of rules loaded
```

### Create Audit Monitoring Script (Optional)

```bash
# Create script for monitoring critical audit events
ssh ha "sudo tee /usr/local/bin/audit-monitor.sh > /dev/null << 'MONEOF'
#!/bin/bash
# System Audit Event Monitor
# Alerts on security-critical events

TELEGRAM_SENDER=\"/usr/local/bin/telegram-sender.sh\"
LAST_CHECK_FILE=\"/var/run/audit-last-check\"

# Get timestamp of last check
if [[ -f \"\$LAST_CHECK_FILE\" ]]; then
    LAST_CHECK=\$(cat \"\$LAST_CHECK_FILE\")
else
    LAST_CHECK=\$(date -d '1 hour ago' '+%m/%d/%Y %H:%M:%S')
fi

# Check for failed SSH attempts
FAILED_SSH=\$(ausearch -k ssh_daemon --success no -ts \"\$LAST_CHECK\" 2>/dev/null | grep -c \"type=USER_AUTH\")

# Check for failed sudo attempts
FAILED_SUDO=\$(ausearch -k sudo_usage --success no -ts \"\$LAST_CHECK\" 2>/dev/null | grep -c \"type=USER_CMD\")

# Check for firewall changes
FIREWALL_CHANGES=\$(ausearch -k firewall_config -k firewall_cmd -ts \"\$LAST_CHECK\" 2>/dev/null | grep -c \"type=SYSCALL\")

# Send alerts if needed
if [[ \"\$FAILED_SSH\" -gt 5 ]]; then
    \"\$TELEGRAM_SENDER\" \"🚨 Security Alert: \$FAILED_SSH failed SSH attempts since \$LAST_CHECK\" 2
fi

if [[ \"\$FAILED_SUDO\" -gt 3 ]]; then
    \"\$TELEGRAM_SENDER\" \"⚠️ Security Alert: \$FAILED_SUDO failed sudo attempts since \$LAST_CHECK\" 2
fi

if [[ \"\$FIREWALL_CHANGES\" -gt 0 ]]; then
    \"\$TELEGRAM_SENDER\" \"🔒 Firewall Alert: \$FIREWALL_CHANGES firewall changes detected since \$LAST_CHECK\" 2
fi

# Update last check timestamp
date '+%m/%d/%Y %H:%M:%S' > \"\$LAST_CHECK_FILE\"
MONEOF"

# Make executable
ssh ha "sudo chmod +x /usr/local/bin/audit-monitor.sh"

# Test the script
ssh ha "sudo /usr/local/bin/audit-monitor.sh"
```

### Audit Best Practices

- ✅ **Regular Review** - Check audit logs weekly for anomalies
- ✅ **Storage Management** - Monitor audit log size (configured for ~100MB total)
- ✅ **Performance** - auditd is lightweight but monitor system performance
- ✅ **Rule Optimization** - Only audit security-relevant events
- ✅ **Alert Integration** - Integrate with Telegram for critical events
- ✅ **Backup** - Include `/var/log/audit/` in backup strategy

**Note:** Audit rules become active after system reboot or `augenrules --load`. Some rules may require kernel capabilities.
