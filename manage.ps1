# 🏠 Raspberry Pi Home Assistant Project Management Script
# Управление проектом "умного дома" на Raspberry Pi

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("connect", "status", "deploy", "backup", "logs", "restart", "update", "install", "check")]
    [string]$Action,
    
    [string]$RpiIP = "192.168.1.21",   # IP вашей малинки
    [int]$RpiPort = 22,                # SSH порт
    [string]$RpiUser = "root",         # Пользователь
    [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519"  # Путь к SSH ключу
)

# Цвета для вывода
function Write-Success { param($Message) Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Error { param($Message) Write-Host "❌ $Message" -ForegroundColor Red }
function Write-Info { param($Message) Write-Host "ℹ️  $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "⚠️  $Message" -ForegroundColor Yellow }

# Проверка SSH ключа
function Test-SSHKey {
    if (-not (Test-Path $KeyPath)) {
        Write-Error "SSH ключ не найден: $KeyPath"
        Write-Info "Создайте ключ командой: ssh-keygen -t ed25519 -f `"$KeyPath`""
        return $false
    }
    return $true
}

# Выполнение SSH команды
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
        Write-Error "Команда завершилась с ошибкой: $Command"
        return $false
    }
    return $true
}

# Копирование файлов на RPi
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
        Write-Error "Ошибка копирования: $LocalPath -> $RemotePath"
        return $false
    }
    return $true
}

# Копирование файлов с RPi
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
        Write-Error "Ошибка копирования: $RemotePath -> $LocalPath"
        return $false
    }
    return $true
}

# Действие: Подключение и проверка
function Connect-ToRPi {
    Write-Info "🔌 Подключение к Raspberry Pi: $RpiUser@$RpiIP`:$RpiPort"
    
    if (-not (Test-SSHKey)) { return }
    
    $commands = @(
        @{ cmd = "hostname"; desc = "Проверка имени хоста" }
        @{ cmd = "uptime"; desc = "Время работы системы" }
        @{ cmd = "free -h"; desc = "Использование памяти" }
        @{ cmd = "df -h /"; desc = "Использование диска" }
        @{ cmd = "docker --version 2>/dev/null || echo 'Docker не установлен'"; desc = "Версия Docker" }
    )
    
    foreach ($cmd in $commands) {
        Invoke-SSHCommand -Command $cmd.cmd -Description $cmd.desc
        Write-Host ""
    }
}

# Действие: Статус системы
function Get-SystemStatus {
    Write-Info "📊 Получение статуса системы..."
    
    if (-not (Test-SSHKey)) { return }
    
    $statusScript = @"
#!/bin/bash
echo "=== 🖥️  ИНФОРМАЦИЯ О СИСТЕМЕ ==="
echo "Хост: `$(hostname)"
echo "Время работы: `$(uptime -p)"
echo "Нагрузка: `$(uptime | awk -F'load average:' '{print `$2}')"
echo "Температура CPU: `$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print `$1/1000"°C"}' || echo 'Недоступно')"
echo ""

echo "=== 💾 ПАМЯТЬ И ДИСК ==="
free -h
echo ""
df -h / /boot
echo ""

echo "=== 🐳 DOCKER ==="
if command -v docker >/dev/null 2>&1; then
    echo "Docker версия: `$(docker --version)"
    echo "Статус Docker: `$(systemctl is-active docker)"
    echo ""
    echo "Контейнеры:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
else
    echo "Docker не установлен"
fi
echo ""

echo "=== 🔍 МОНИТОРИНГ ==="
if systemctl list-timers | grep -q ha-watchdog; then
    echo "HA Watchdog: `$(systemctl is-active ha-watchdog.timer)"
    echo "HA Failure Notifier: `$(systemctl is-active ha-failure-notifier.timer)"
    echo "Telegram Sender: `$([ -f /usr/local/bin/telegram-sender.sh ] && echo 'Установлен' || echo 'Не установлен')"
    echo ""
    echo "Последние проверки:"
    tail -5 /var/log/ha-watchdog.log 2>/dev/null || echo "Лог не найден"
else
    echo "Система мониторинга не установлена"
fi
echo ""

echo "=== 🌐 СЕТЬ ==="
ip addr show | grep -E "inet.*global" | awk '{print `$2, `$NF}'
echo ""
ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo "Интернет: ✅ Доступен" || echo "Интернет: ❌ Недоступен"
"@

    $statusScript | Invoke-SSHCommand -Command "cat > /tmp/status.sh && chmod +x /tmp/status.sh && /tmp/status.sh && rm /tmp/status.sh"
}

# Действие: Развертывание мониторинга
function Deploy-Monitoring {
    Write-Info "🚀 Развертывание системы мониторинга..."
    
    if (-not (Test-SSHKey)) { return }
    
    # Создаем временную директорию
    $tempDir = "/tmp/ha-monitoring-deploy"
    Invoke-SSHCommand -Command "mkdir -p $tempDir" -Description "Создание временной директории"
    
    # Копируем файлы мониторинга
    $monitoringPath = ".\project\monitoring"
    Copy-ToRPi -LocalPath "$monitoringPath\*" -RemotePath $tempDir -Description "Копирование файлов мониторинга"
    
    # Запускаем установку
    $installScript = @"
#!/bin/bash
cd $tempDir
chmod +x install.sh scripts/*.sh
./install.sh
"@

    $installScript | Invoke-SSHCommand -Command "cat > /tmp/install_monitoring.sh && chmod +x /tmp/install_monitoring.sh && /tmp/install_monitoring.sh"
    
    Write-Success "Развертывание завершено! Не забудьте настроить Telegram в /etc/telegram-sender/config"
}

# Действие: Резервное копирование
function Backup-System {
    Write-Info "💾 Создание резервной копии конфигурации..."
    
    if (-not (Test-SSHKey)) { return }
    
    $backupDir = ".\backups\$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    
    # Копируем важные конфигурации
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
    
    Write-Success "Резервная копия создана: $backupDir"
}

# Действие: Просмотр логов
function Get-Logs {
    Write-Info "📋 Получение логов системы..."
    
    if (-not (Test-SSHKey)) { return }
    
    $logScript = @"
#!/bin/bash
echo "=== 🔍 ЛОГИ WATCHDOG ==="
tail -20 /var/log/ha-watchdog.log 2>/dev/null || echo "Лог не найден"
echo ""

echo "=== 🔧 ЛОГИ FAILURE NOTIFIER ==="
tail -20 /var/log/ha-failure-notifier.log 2>/dev/null || echo "Лог не найден"
echo ""

echo "=== 📢 ЛОГИ TELEGRAM SENDER ==="
tail -20 /var/log/telegram-sender.log 2>/dev/null || echo "Лог не найден"
echo ""

echo "=== 🚨 ЛОГИ СБОЕВ ==="
tail -20 /var/log/ha-failures.log 2>/dev/null || echo "Лог не найден"
echo ""

echo "=== 🐳 ЛОГИ DOCKER ==="
journalctl -u docker --no-pager -l --lines=10
echo ""

echo "=== ⚙️  ЛОГИ SYSTEMD МОНИТОРИНГА ==="
journalctl -u ha-watchdog.service --no-pager -l --lines=5
journalctl -u ha-failure-notifier.service --no-pager -l --lines=5
"@

    $logScript | Invoke-SSHCommand
}

# Действие: Перезапуск сервисов
function Restart-Services {
    Write-Info "🔄 Перезапуск сервисов..."
    
    if (-not (Test-SSHKey)) { return }
    
    $commands = @(
        @{ cmd = "systemctl restart ha-watchdog.timer"; desc = "Перезапуск HA Watchdog" }
        @{ cmd = "systemctl restart ha-failure-notifier.timer"; desc = "Перезапуск HA Failure Notifier" }
        @{ cmd = "cd /srv/home && docker compose restart"; desc = "Перезапуск Docker контейнеров" }
    )
    
    foreach ($cmd in $commands) {
        if (Invoke-SSHCommand -Command $cmd.cmd -Description $cmd.desc) {
            Write-Success $cmd.desc
        }
    }
}

# Действие: Обновление системы
function Update-System {
    Write-Info "📦 Обновление системы..."
    
    if (-not (Test-SSHKey)) { return }
    
    $updateScript = @"
#!/bin/bash
echo "Обновление пакетов..."
apt update && apt upgrade -y

echo "Обновление Docker образов..."
cd /srv/home
docker compose pull
docker compose up -d

echo "Очистка старых образов..."
docker image prune -f

echo "Обновление завершено!"
"@

    $updateScript | Invoke-SSHCommand -Description "Выполнение обновления системы"
}

# Действие: Установка базовой системы
function Install-BaseSystem {
    Write-Info "🔧 Установка базовой системы..."
    
    if (-not (Test-SSHKey)) { return }
    
    # Копируем setup скрипты
    Copy-ToRPi -LocalPath ".\project\setup\*" -RemotePath "/tmp/" -Description "Копирование установочных скриптов"
    
    Invoke-SSHCommand -Command "chmod +x /tmp/*.sh && /tmp/rpi_auto_update_script.sh" -Description "Запуск установки базовой системы"
}

# Действие: Комплексная проверка
function Check-Everything {
    Write-Info "🔍 Комплексная проверка системы..."
    
    if (-not (Test-SSHKey)) { return }
    
    $checkScript = @"
#!/bin/bash
echo "=== 🏥 ДИАГНОСТИКА СИСТЕМЫ ==="
echo ""

# Проверка сетевой связности
echo "🌐 СЕТЬ:"
ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo "  ✅ Интернет доступен" || echo "  ❌ Нет интернета"
ping -c 1 \$(ip route | awk '/default/ {print \$3}') >/dev/null 2>&1 && echo "  ✅ Шлюз доступен" || echo "  ❌ Шлюз недоступен"
ip link show wlan0 | grep -q "state UP" && echo "  ✅ WiFi активен" || echo "  ❌ WiFi неактивен"
echo ""

# Проверка ресурсов
echo "💻 РЕСУРСЫ:"
mem_free=\$(free -m | awk '/Mem:/ {print \$7}')
[ \$mem_free -gt 100 ] && echo "  ✅ Памяти достаточно (\${mem_free}MB)" || echo "  ❌ Мало памяти (\${mem_free}MB)"

disk_free=\$(df / | awk 'NR==2 {print \$4}')
[ \$disk_free -gt 500000 ] && echo "  ✅ Места достаточно (\$((disk_free/1024))MB)" || echo "  ❌ Мало места (\$((disk_free/1024))MB)"

temp=\$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print \$1/1000}')
if [ ! -z "\$temp" ]; then
    [ \$(echo "\$temp < 70" | bc) -eq 1 ] && echo "  ✅ Температура нормальная (\${temp}°C)" || echo "  ❌ Высокая температура (\${temp}°C)"
fi
echo ""

# Проверка Docker
echo "🐳 DOCKER:"
if command -v docker >/dev/null 2>&1; then
    systemctl is-active docker >/dev/null 2>&1 && echo "  ✅ Docker активен" || echo "  ❌ Docker неактивен"
    
    containers=("homeassistant" "nodered")
    for container in "\${containers[@]}"; do
        if docker inspect -f '{{.State.Running}}' "\$container" 2>/dev/null | grep -q true; then
            echo "  ✅ \$container работает"
        else
            echo "  ❌ \$container не работает"
        fi
    done
else
    echo "  ❌ Docker не установлен"
fi
echo ""

# Проверка портов
echo "🚪 ПОРТЫ:"
timeout 2 bash -c '</dev/tcp/localhost/8123' 2>/dev/null && echo "  ✅ Home Assistant (8123) доступен" || echo "  ❌ Home Assistant недоступен"
timeout 2 bash -c '</dev/tcp/localhost/1880' 2>/dev/null && echo "  ✅ Node-RED (1880) доступен" || echo "  ❌ Node-RED недоступен"
echo ""

# Проверка мониторинга
echo "🔍 МОНИТОРИНГ:"
systemctl is-active ha-watchdog.timer >/dev/null 2>&1 && echo "  ✅ Watchdog активен" || echo "  ❌ Watchdog неактивен"
systemctl is-active ha-failure-notifier.timer >/dev/null 2>&1 && echo "  ✅ Failure Notifier активен" || echo "  ❌ Failure Notifier неактивен"

# Проверка нового централизованного Telegram сервиса
if [ -f /etc/telegram-sender/config ]; then
    source /etc/telegram-sender/config
    [ ! -z "\$TELEGRAM_BOT_TOKEN" ] && echo "  ✅ Telegram Sender настроен" || echo "  ⚠️  Telegram Sender не настроен"
    [ -f /usr/local/bin/telegram-sender.sh ] && echo "  ✅ Telegram Sender скрипт установлен" || echo "  ❌ Telegram Sender скрипт отсутствует"
else
    echo "  ❌ Конфигурация Telegram Sender не найдена"
fi
echo ""

echo "=== 📊 ИТОГОВЫЙ СТАТУС ==="
echo "Время проверки: \$(date)"
"@

    $checkScript | Invoke-SSHCommand
}

# Главное меню
function Show-Menu {
    Write-Host @"
🏠 Raspberry Pi Home Assistant Project Manager
══════════════════════════════════════════════

Доступные действия:
  connect   - Подключиться и проверить базовую информацию
  status    - Получить детальный статус системы
  deploy    - Развернуть систему мониторинга
  backup    - Создать резервную копию конфигураций
  logs      - Просмотреть логи системы
  restart   - Перезапустить сервисы
  update    - Обновить систему и Docker образы
  install   - Установить базовую систему
  check     - Комплексная проверка всех компонентов

Параметры:
  -RpiIP     IP адрес Raspberry Pi (по умолчанию: $RpiIP)
  -RpiPort   SSH порт (по умолчанию: $RpiPort)
  -RpiUser   SSH пользователь (по умолчанию: $RpiUser)
  -KeyPath   Путь к SSH ключу (по умолчанию: $KeyPath)

Пример: .\manage.ps1 -Action connect -RpiIP 192.168.1.150
"@ -ForegroundColor Yellow
}

# Основная логика
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
