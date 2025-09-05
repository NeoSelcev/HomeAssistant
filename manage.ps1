# 🏠 Raspberry Pi Home Assistant Project Management Script
# Smart home project management on Raspberry Pi

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("connect", "status", "deploy", "backup", "logs", "restart", "update", "install", "check")]
    [string]$Action,
    
    [string]$RpiIP = "192.168.1.21",   # IP of your Raspberry Pi
    [int]$RpiPort = 22,                # SSH port
    [string]$RpiUser = "root",         # User
    [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519"  # Path to SSH key
)

# Colors for output
function Write-Success { param($Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Error { param($Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-Info { param($Message) Write-Host "ℹ️  $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "⚠️  $Message" -ForegroundColor Yellow }

# SSH key check
function Test-SSHKey {
    if (-not (Test-Path $KeyPath)) {
        Write-Error "SSH key not found: $KeyPath"
        Write-Info "Create key with command: ssh-keygen -t ed25519 -f `"$KeyPath`""
        return $false
    }
    return $true
}

# Execute SSH command
function Invoke-SSHCommand {
    param([string]$Command, [string]$Description = "")
    
    if ($Description) { Write-Info $Description }
    
    $sshArgs = @(
        "-i", $KeyPath
        "-p", $RpiPort
        "-o", "StrictHostKeyChecking=no"
        "-o", "UserKnownHostsFile=NUL"
        "$RpiUser@$RpiIP"
        $Command
    )
    
    & ssh $sshArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Command failed with error: $Command"
        return $false
    }
    return $true
}

# Copy files to RPi
function Copy-ToRPi {
    param([string]$LocalPath, [string]$RemotePath, [string]$Description = "")
    
    if ($Description) { Write-Info $Description }
    
    $scpArgs = @(
        "-i", $KeyPath
        "-P", $RpiPort
        "-o", "StrictHostKeyChecking=no"
        "-o", "UserKnownHostsFile=NUL"
        "-r"
        $LocalPath
        "$RpiUser@$RpiIP`:$RemotePath"
    )
    
    & scp $scpArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Copy error: $LocalPath -> $RemotePath"
        return $false
    }
    return $true
}

# Copy files from RPi
function Copy-FromRPi {
    param([string]$RemotePath, [string]$LocalPath, [string]$Description = "")
    
    if ($Description) { Write-Info $Description }
    
    $scpArgs = @(
        "-i", $KeyPath
        "-P", $RpiPort
        "-o", "StrictHostKeyChecking=no"
        "-o", "UserKnownHostsFile=NUL"
        "-r"
        "$RpiUser@$RpiIP`:$RemotePath"
        $LocalPath
    )
    
    & scp $scpArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Copy error: $RemotePath -> $LocalPath"
        return $false
    }
    return $true
}

# Action: Connect and check
function Connect-ToRPi {
    Write-Info "🔌 Connecting to Raspberry Pi: $RpiUser@$RpiIP`:$RpiPort"
    
    if (-not (Test-SSHKey)) { return }
    
    $commands = @(
        @{ cmd = "hostname"; desc = "Checking hostname" }
        @{ cmd = "uptime"; desc = "System uptime" }
        @{ cmd = "free -h"; desc = "Memory usage" }
        @{ cmd = "df -h /"; desc = "Disk usage" }
        @{ cmd = "docker --version 2>/dev/null || echo 'Docker not installed'"; desc = "Docker version" }
    )
    
    foreach ($cmd in $commands) {
        Invoke-SSHCommand -Command $cmd.cmd -Description $cmd.desc
        Write-Host ""
    }
}

# Action: System status
function Get-SystemStatus {
    Write-Info "📊 Getting system status..."
    
    if (-not (Test-SSHKey)) { return }
    
    $statusScript = @"
#!/bin/bash
echo "=== 🖥️  SYSTEM INFORMATION ==="
echo "Host: `$(hostname)"
echo "Uptime: `$(uptime -p)"
echo "Load: `$(uptime | awk -F'load average:' '{print `$2}')"
echo "CPU Temperature: `$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print `$1/1000"°C"}' || echo 'Unavailable')"
echo ""

echo "=== 💾 MEMORY AND DISK ==="
free -h
echo ""
df -h / /boot
echo ""

echo "=== 🐳 DOCKER ==="
if command -v docker >/dev/null 2>&1; then
    echo "Docker version: `$(docker --version)"
    echo "Docker status: `$(systemctl is-active docker)"
    echo ""
    echo "Containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
else
    echo "Docker not installed"
fi
echo ""

echo "=== 🔍 MONITORING ==="
if systemctl list-timers | grep -q ha-watchdog; then
    echo "HA Watchdog: `$(systemctl is-active ha-watchdog.timer)"
    echo "HA Failure Notifier: `$(systemctl is-active ha-failure-notifier.timer)"
    echo "Telegram Sender: `$([ -f /usr/local/bin/telegram-sender.sh ] && echo 'Installed' || echo 'Not installed')"
    echo ""
    echo "Recent checks:"
    tail -5 /var/log/ha-watchdog.log 2>/dev/null || echo "Log not found"
else
    echo "Monitoring system not installed"
fi
echo ""

echo "=== 🌐 NETWORK ==="
ip addr show | grep -E "inet.*global" | awk '{print `$2, `$NF}'
echo ""
ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo "Internet: ✅ Available" || echo "Internet: ❌ Unavailable"
"@

    $statusScript | Invoke-SSHCommand -Command "cat > /tmp/status.sh && chmod +x /tmp/status.sh && /tmp/status.sh && rm /tmp/status.sh"
}

# Action: Deploy monitoring
function Deploy-Monitoring {
    Write-Info "🚀 Deploying monitoring system..."
    
    if (-not (Test-SSHKey)) { return }
    
    # Create temporary directory
    $tempDir = "/tmp/ha-monitoring-deploy"
    Invoke-SSHCommand -Command "mkdir -p $tempDir" -Description "Creating temporary directory"
    
    # Copy monitoring files
    $monitoringPath = ".\project\monitoring"
    Copy-ToRPi -LocalPath "$monitoringPath\*" -RemotePath $tempDir -Description "Copying monitoring files"
    
    # Run installation
    $installScript = @"
#!/bin/bash
cd $tempDir
chmod +x install.sh scripts/*.sh
./install.sh
"@

    $installScript | Invoke-SSHCommand -Command "cat > /tmp/install_monitoring.sh && chmod +x /tmp/install_monitoring.sh && /tmp/install_monitoring.sh"
    
    Write-Success "Deployment completed! Don't forget to configure Telegram in /etc/telegram-sender/config"
}

# Action: System backup
function Backup-System {
    Write-Info "💾 Creating configuration backup..."
    
    if (-not (Test-SSHKey)) { return }
    
    $backupDir = ".\backups\$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    
    # Copy important configurations
    $backupPaths = @(
        "/srv/home",
        "/etc/telegram-sender",
        "/etc/ha-watchdog",
        "/var/log/ha-*.log",
        "/var/log/telegram-sender.log",
        "/var/lib/ha-failure-notifier"
    )
    
    foreach ($path in $backupPaths) {
        $safePath = $path -replace "/", "_"
        Copy-FromRPi -RemotePath $path -LocalPath "$backupDir\$safePath" -Description "Backup: $path"
    }
    
    Write-Success "Backup created: $backupDir"
}

# Action: View logs
function Get-Logs {
    Write-Info "📋 Getting system logs..."
    
    if (-not (Test-SSHKey)) { return }
    
    $logScript = @"
#!/bin/bash
echo "=== 🔍 WATCHDOG LOGS ==="
tail -20 /var/log/ha-watchdog.log 2>/dev/null || echo "Log not found"
echo ""

echo "=== 🔧 FAILURE NOTIFIER LOGS ==="
tail -20 /var/log/ha-failure-notifier.log 2>/dev/null || echo "Log not found"
echo ""

echo "=== 📢 TELEGRAM SENDER LOGS ==="
tail -20 /var/log/telegram-sender.log 2>/dev/null || echo "Log not found"
echo ""

echo "=== 🚨 FAILURE LOGS ==="
tail -20 /var/log/ha-failures.log 2>/dev/null || echo "Log not found"
echo ""

echo "=== 🐳 DOCKER LOGS ==="
journalctl -u docker --no-pager -l --lines=10
echo ""

echo "=== ⚙️  SYSTEMD MONITORING LOGS ==="
journalctl -u ha-watchdog.service --no-pager -l --lines=5
journalctl -u ha-failure-notifier.service --no-pager -l --lines=5
"@

    $logScript | Invoke-SSHCommand
}

# Action: Restart services
function Restart-Services {
    Write-Info "🔄 Restarting services..."
    
    if (-not (Test-SSHKey)) { return }
    
    $restartScript = @"
#!/bin/bash
echo "🔄 Restarting Home Assistant services..."

# Restart containers
docker restart homeassistant nodered
echo "✅ Containers restarted"

# Restart monitoring services
sudo systemctl restart ha-watchdog.timer ha-failure-notifier.timer
echo "✅ Monitoring services restarted"

echo "✅ All services restarted successfully"
"@

    $restartScript | Invoke-SSHCommand
}

# Action: System update
function Update-System {
    Write-Info "📦 Updating system..."
    
    if (-not (Test-SSHKey)) { return }
    
    $updateScript = @"
#!/bin/bash
echo "Updating packages..."
apt update && apt upgrade -y

echo "Updating Docker images..."
cd /srv/home
docker compose pull
docker compose up -d

echo "Cleaning old images..."
docker image prune -f

echo "Update completed!"
"@

    $updateScript | Invoke-SSHCommand -Description "Running system update"
}

# Action: Install base system
function Install-BaseSystem {
    Write-Info "🔧 Installing base system..."
    
    if (-not (Test-SSHKey)) { return }
    
    # Copy setup scripts
    Copy-ToRPi -LocalPath ".\project\setup\*" -RemotePath "/tmp/" -Description "Copying installation scripts"
    
    Invoke-SSHCommand -Command "chmod +x /tmp/*.sh && /tmp/rpi_auto_update_script.sh" -Description "Running base system installation"
}

# Action: Comprehensive check
function Check-Everything {
    Write-Info "🔍 Comprehensive system check..."
    
    if (-not (Test-SSHKey)) { return }
    
    $checkScript = @"
#!/bin/bash
echo "=== 🏥 SYSTEM DIAGNOSTICS ==="
echo ""

# Network connectivity check
echo "🌐 NETWORK:"
ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo "  ✅ Internet available" || echo "  ❌ No internet"
ping -c 1 \$(ip route | awk '/default/ {print \$3}') >/dev/null 2>&1 && echo "  ✅ Gateway accessible" || echo "  ❌ Gateway inaccessible"
ip link show wlan0 | grep -q "state UP" && echo "  ✅ WiFi active" || echo "  ❌ WiFi inactive"
echo ""

# Resource check
echo "💻 RESOURCES:"
mem_free=\$(free -m | awk '/Mem:/ {print \$7}')
[ \$mem_free -gt 100 ] && echo "  ✅ Memory sufficient (\${mem_free}MB)" || echo "  ❌ Low memory (\${mem_free}MB)"

disk_free=\$(df / | awk 'NR==2 {print \$4}')
[ \$disk_free -gt 500000 ] && echo "  ✅ Disk space sufficient (\$((disk_free/1024))MB)" || echo "  ❌ Low disk space (\$((disk_free/1024))MB)"

temp=\$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print \$1/1000}')
if [ ! -z "\$temp" ]; then
    [ \$(echo "\$temp < 70" | bc) -eq 1 ] && echo "  ✅ Temperature normal (\${temp}°C)" || echo "  ❌ High temperature (\${temp}°C)"
fi
echo ""

# Docker check
echo "🐳 DOCKER:"
if command -v docker >/dev/null 2>&1; then
    systemctl is-active docker >/dev/null 2>&1 && echo "  ✅ Docker active" || echo "  ❌ Docker inactive"
    
    containers=("homeassistant" "nodered")
    for container in "\${containers[@]}"; do
        if docker inspect -f '{{.State.Running}}' "\$container" 2>/dev/null | grep -q true; then
            echo "  ✅ \$container running"
        else
            echo "  ❌ \$container not running"
        fi
    done
else
    echo "  ❌ Docker not installed"
fi
echo ""

# Port check
echo "🚪 PORTS:"
timeout 2 bash -c '</dev/tcp/localhost/8123' 2>/dev/null && echo "  ✅ Home Assistant (8123) accessible" || echo "  ❌ Home Assistant inaccessible"
timeout 2 bash -c '</dev/tcp/localhost/1880' 2>/dev/null && echo "  ✅ Node-RED (1880) accessible" || echo "  ❌ Node-RED inaccessible"
echo ""

# Monitoring check
echo "🔍 MONITORING:"
systemctl is-active ha-watchdog.timer >/dev/null 2>&1 && echo "  ✅ Watchdog active" || echo "  ❌ Watchdog inactive"
systemctl is-active ha-failure-notifier.timer >/dev/null 2>&1 && echo "  ✅ Failure Notifier active" || echo "  ❌ Failure Notifier inactive"

# Check new centralized Telegram service
if [ -f /etc/telegram-sender/config ]; then
    source /etc/telegram-sender/config
    [ ! -z "\$TELEGRAM_BOT_TOKEN" ] && echo "  ✅ Telegram Sender configured" || echo "  ⚠️  Telegram Sender not configured"
    [ -f /usr/local/bin/telegram-sender.sh ] && echo "  ✅ Telegram Sender script installed" || echo "  ❌ Telegram Sender script missing"
else
    echo "  ❌ Telegram Sender configuration not found"
fi
echo ""

echo "=== 📊 FINAL STATUS ==="
echo "Check time: \$(date)"
"@

    $checkScript | Invoke-SSHCommand
}

# Main menu
function Show-Menu {
    Write-Host @"
🏠 Raspberry Pi Home Assistant Project Manager
══════════════════════════════════════════════

Available actions:
  connect   - Connect and check basic information
  status    - Get detailed system status
  deploy    - Deploy monitoring system
  backup    - Create configuration backups
  logs      - View system logs
  restart   - Restart services
  update    - Update system and Docker images
  install   - Install base system
  check     - Comprehensive check of all components

Parameters:
  -RpiIP     Raspberry Pi IP address (default: $RpiIP)
  -RpiPort   SSH port (default: $RpiPort)
  -RpiUser   SSH user (default: $RpiUser)
  -KeyPath   SSH key path (default: $KeyPath)

Example: .\manage.ps1 -Action connect -RpiIP 192.168.1.150
"@ -ForegroundColor Yellow
}

# Main logic
switch ($Action) {
    "connect" { Connect-ToRPi }
    "status" { Get-SystemStatus }
    "deploy" { Deploy-Monitoring }
    "backup" { Backup-System }
    "logs" { Get-Logs }
    "restart" { Restart-Services }
    "update" { Update-System }
    "install" { Install-BaseSystem }
    "check" { Check-Everything }
    default { Show-Menu }
}
