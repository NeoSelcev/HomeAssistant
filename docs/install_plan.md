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
sudo ufw allow ssh
sudo ufw allow 8123/tcp
sudo ufw allow 1880/tcp
sudo ufw --force enable
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

## 26. Final System Verification
```

---

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