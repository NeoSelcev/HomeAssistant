# Cloudflare Tunnel Configuration

## 📁 Структура файлов

```
cloudflared/
├── config.yml.example          # Пример конфигурации туннеля
├── config.yml                  # Реальная конфигурация (создать после setup)
├── [TUNNEL_ID].json           # Credentials файл (создается cloudflared)
└── README.md                   # Этот файл
```

## 🚀 Первоначальная настройка

### 1. Установка cloudflared (временно)

```bash
# Скачать cloudflared для создания туннеля
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb
cloudflared --version
```

### 2. Авторизация в Cloudflare

```bash
# Авторизоваться в Cloudflare (откроется браузер)
cloudflared tunnel login
# Сертификат сохранится в /root/.cloudflared/cert.pem
```

### 3. Создание туннеля

```bash
# Создать туннель (запомните TUNNEL_ID)
cloudflared tunnel create homeassistant-tunnel

# Туннель credentials будут сохранены в:
# /root/.cloudflared/[TUNNEL_ID].json
```

### 4. Настройка DNS

```bash
# Создать DNS записи для туннеля
cloudflared tunnel route dns homeassistant-tunnel ha.[YOUR-DOMAIN]
cloudflared tunnel route dns homeassistant-tunnel test.[YOUR-DOMAIN]
```

### 5. Копирование файлов в Docker directory

```bash
# Скопировать файлы в docker directory
sudo cp /root/.cloudflared/[TUNNEL_ID].json /opt/homeassistant/cloudflared/
sudo cp /root/.cloudflared/cert.pem /opt/homeassistant/cloudflared/

# Создать config.yml на основе config.yml.example
sudo cp /opt/homeassistant/cloudflared/config.yml.example /opt/homeassistant/cloudflared/config.yml

# Заменить [TUNNEL_ID] и [YOUR-DOMAIN] на реальные значения
sudo nano /opt/homeassistant/cloudflared/config.yml
```

### 6. Удаление временной установки

```bash
# Удалить cloudflared binary (будет использоваться Docker версия)
sudo apt remove cloudflared -y
rm cloudflared.deb
```

## 🔧 Конфигурация

### config.yml

```yaml
tunnel: [TUNNEL_ID]
credentials-file: /etc/cloudflared/[TUNNEL_ID].json

ingress:
  # Home Assistant Admin Panel
  - hostname: ha.[YOUR-DOMAIN]
    service: http://ha-proxy:8080
  
  # Test web page
  - hostname: test.[YOUR-DOMAIN]
    service: http://test-web:80
  
  # Catch-all rule (required)
  - service: http_status:404
```

### Важные параметры:

- **tunnel**: ID вашего туннеля
- **credentials-file**: Путь к credentials файлу (внутри контейнера)
- **ingress**: Правила маршрутизации трафика

## 🐳 Docker Deployment

После настройки запустить туннель в Docker:

```bash
cd /opt/homeassistant
docker compose up -d cloudflared
```

## ✅ Проверка

```bash
# Проверить статус контейнера
docker ps | grep cloudflared

# Проверить логи туннеля
docker logs -f cloudflared-tunnel

# Проверить ingress rules
docker exec cloudflared-tunnel cloudflared tunnel ingress validate

# Проверить info туннеля
docker exec cloudflared-tunnel cloudflared tunnel info

# Проверить публичный доступ
curl -I https://test.[YOUR-DOMAIN]
```

## 🔒 Безопасность

- **Credentials файл**: Держите [TUNNEL_ID].json в секрете
- **cert.pem**: Сертификат для аутентификации с Cloudflare
- **config.yml**: Может содержать чувствительную информацию

### Права доступа:

```bash
chmod 600 /opt/homeassistant/cloudflared/*.json
chmod 600 /opt/homeassistant/cloudflared/cert.pem
chmod 644 /opt/homeassistant/cloudflared/config.yml
```

## 📊 Мониторинг

Tunnel мониторится следующими сервисами:

- **ha-watchdog**: Проверяет статус cloudflared контейнера
- **system-diagnostic**: Валидирует конфигурацию и connectivity
- **ha-failure-notifier**: Отправляет alerts при проблемах

## 🔗 Ссылки

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [cloudflared GitHub](https://github.com/cloudflare/cloudflared)
- [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com)

## ⚠️ Troubleshooting

### Tunnel не подключается:

```bash
# Проверить логи
docker logs cloudflared-tunnel

# Перезапустить контейнер
docker restart cloudflared-tunnel

# Проверить DNS records в Cloudflare Dashboard
```

### 502 Bad Gateway:

- Проверить, что ha-proxy контейнер запущен
- Проверить, что homeassistant доступен
- Проверить nginx конфигурацию

### 403 Forbidden:

- Проверить Cloudflare Access policies
- Проверить HTTP Basic Auth credentials
