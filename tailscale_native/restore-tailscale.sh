#!/bin/bash
# Восстановление Tailscale на Pi

[[ $EUID -ne 0 ]] && { echo "sudo $0"; exit 1; }

DIR="$(dirname "$0")"

# Установка
command -v tailscale || curl -fsSL https://tailscale.com/install.sh | sh

# Остановка
systemctl stop tailscaled tailscale-serve-ha tailscale-funnel-ha 2>/dev/null || true

# Копирование
cp "$DIR/systemd/"*.service /etc/systemd/system/
cp "$DIR/config/tailscaled.default" /etc/default/tailscaled 2>/dev/null || true

# Запуск
systemctl daemon-reload
systemctl enable --now tailscaled tailscale-serve-ha tailscale-funnel-ha

# Авторизация
tailscale status || echo "Выполните: tailscale up --hostname=rpi3-20250711"
