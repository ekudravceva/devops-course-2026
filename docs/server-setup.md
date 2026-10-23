# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины
- Гипервизор: Oracle VirtualBox 7.x на macOS (Apple Silicon)
- ОС: Ubuntu Server 26.10 (arm64)
- Оперативная память: 2048 МБ
- Ядра процессора: 2
- Диск: 25 ГБ, динамически расширяемый

## 2. Сетевые интерфейсы
| Адаптер | Тип | Адрес | Назначение |
|---|---|---|---|
| 1 | NAT (enp0s8) | 10.0.2.15 | выход в Интернет (репозитории пакетов), проброс порта SSH |
| 2 | Host-only (enp0s9) | 192.168.56.2 | доступ с хоста (SSH по имени, веб-сервер в ПР № 6) |

Имя узла: `devops-vm`, полное имя: `devops-vm.devops.local`. На хосте в `/etc/hosts`: `192.168.56.2 devops.local`.

## 3. Правило проброса портов
Адаптер 1 (NAT), правило `ssh`: TCP, хост 127.0.0.1:2222 → гость :2222 (до смены порта SSH — :22).

## 4. Учётные записи
| Имя | Группы | Аутентификация |
|---|---|---|
| student | student, sudo | пароль (только консоль ВМ; по SSH вход запрещён) |
| devops | devops, sudo | SSH по ключу ed25519 (`~/.ssh/devops_vm` на хосте); пароль нужен только для `sudo` |

Права: `~/.ssh` — 700, `~/.ssh/authorized_keys` — 600. Вход root по SSH запрещён.

## 5. Служба SSH
- Порт: 2222 (служба запущена как `ssh.service`, `ssh.socket` отключён: `sudo systemctl disable --now ssh.socket`)
- Файл конфигурации: `/etc/ssh/sshd_config.d/99-hardening.conf` (резервная копия основного: `/etc/ssh/sshd_config.backup`)
- Директивы: `Port 2222`, `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`, `PermitEmptyPasswords no`, `MaxAuthTries 3`, `LoginGraceTime 30`, `AllowUsers devops`, `X11Forwarding no`, `ClientAliveInterval 300`, `ClientAliveCountMax 2`
- Конфликтующая строка `PasswordAuthentication yes` в `/etc/ssh/sshd_config.d/50-cloud-init.conf` закомментирована (если файл есть)
- Проверка: `sudo sshd -t`, действующие значения — `sudo sshd -T`
- Клиент (хост), `~/.ssh/config`: `Host devops`, `HostName 127.0.0.1`, `Port 2222`, `User devops`, `IdentityFile ~/.ssh/devops_vm`, `IdentitiesOnly yes`

## 6. Правила межсетевого экрана
- Политики: `default deny incoming`, `default allow outgoing`; журналирование: `logging medium`
- Правила:
  - `ufw limit 2222/tcp` (SSH, с ограничением частоты)
  - `ufw allow 80/tcp` (HTTP)
  - `ufw allow 443/tcp` (HTTPS)
- Порядок: сначала разрешающие правила, затем `sudo ufw enable`

## 7. Снимки состояния
| Наименование | Момент создания |
|---|---|
| 01-clean-install | после установки ОС и обновления, ВМ выключена |
| 02-keys-configured | после настройки ключа и `~/.ssh/config` (задание 1) |
| 03-ssh-hardened | после усиления защиты SSH (задание 2) |
| 04-nginx-https | после установки Nginx и перевода ресурса на HTTPS (ПР № 6, задание 2) |
| 05-docker-compose | после запуска проекта «приложение + СУБД» (ПР № 7, задание 2) |

## 8. Веб-сервер
- Устанавливаемый пакет: `nginx` (`sudo apt install -y nginx`); стандартный ресурс отключён удалением ссылки `/etc/nginx/sites-enabled/default`
- Конфигурация ресурса: `/etc/nginx/sites-available/devops-site`, активируется ссылкой в `/etc/nginx/sites-enabled/` (`sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/`)
- Блоки `server`: порт 80 (`server_name devops.local`) — перенаправление `return 301 https://$host$request_uri;`; порт 443 (`ssl`) — раздача ресурса, `ssl_protocols TLSv1.2 TLSv1.3`
- Каталог ресурса: `/var/www/devops-site`, владелец `devops:devops`, права каталогов 755, файлов 644 (доставка: `scripts/deploy.sh`; права D755/F644 задаются `rsync --chmod` либо командой `chmod` по ssh, если встроенный rsync macOS не поддерживает `--chmod`)
- Сертификат: `/etc/ssl/certs/devops.crt`, права 644, владелец root; закрытый ключ: `/etc/ssl/private/devops.key`, права 600, владелец root
- Команда формирования сертификата:
  `sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt -subj "/CN=devops.local" -addext "subjectAltName=DNS:devops.local"`
- Срок действия: 365 дней, истекает 23.10.2027 (`sudo openssl x509 -enddate -noout -in /etc/ssl/certs/devops.crt`)
- Применение конфигурации: `sudo nginx -t && sudo systemctl reload nginx` (не `restart`)
- Порты 80 и 443 разрешены правилами UFW из раздела 6 (правила `Nginx Full` не добавлялись)

## 9. Контейнеризация
- Docker Engine: установлен из официального репозитория Docker (`/etc/apt/sources.list.d/docker.sources`, ключ `/etc/apt/keyrings/docker.asc`), пакеты `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`; версия: 29.9.2 (`docker version`), Compose: v5.6.1 (`docker compose version`); пакет `docker.io` из репозитория дистрибутива не используется
- Участники группы `docker`: `devops` (добавлен командой `sudo usermod -aG docker devops`; вступает в силу в новой SSH-сессии). Членство в группе равносильно правам root: пользователь может смонтировать каталог `/` в контейнер на запись, поэтому в группу включаются только учётные записи с правом sudo
- Расположение проекта на сервере: `~/app` (`/home/devops/app`); имя проекта Compose — `app` (по имени каталога), контейнеры `app-app-1` и `app-db-1`; исходный код доставляется с хоста командой `rsync -avz --delete --exclude=.env app/ devops:app/`
- Файл переменных окружения: `~/app/.env`, права 600, владелец `devops`; создаётся на сервере из шаблона `.env.example` (пароль СУБД генерируется командой `openssl rand -hex 16`), в репозиторий не включается (`.gitignore`) и исключён из образа (`.dockerignore`) и из синхронизации (`--exclude=.env`)
- Образ приложения: `devops-app:1.0` (основа `python:3.12-slim`, процесс работает от пользователя `app`, не от root); СУБД: `postgres:16-alpine` (основная версия закреплена)
- Публикуемые порты: приложение — `127.0.0.1:5000:5000` (только локальный адрес сервера); порт СУБД 5432 не публикуется, приложение обращается к СУБД по имени сервиса `db` в сети проекта. Публикация порта на `0.0.0.0` недопустима: правила Docker обрабатываются раньше правил UFW, и порт оказывается доступен из сети
- Сеть проекта: `app_backend` (пользовательская сеть типа bridge, встроенный DNS разрешает имена сервисов)
- Именованные тома: `app_db_data` (каталог данных СУБД `/var/lib/postgresql/data`); `docker compose down` том сохраняет, `docker compose down -v` удаляет данные безвозвратно
- Обратный прокси-сервер: в блок HTTPS файла `/etc/nginx/sites-available/devops-site` добавлено расположение `location /app/` с `proxy_pass http://127.0.0.1:5000/;` и заголовками `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`; статический ресурс (`location /`) сохранён; применение: `sudo nginx -t && sudo systemctl reload nginx`
- Запуск и остановка: `cd ~/app && docker compose up -d --build` / `docker compose down`; службы имеют политику `restart: unless-stopped` и поднимаются после перезагрузки
- Проверка: `docker compose ps` (у `db` состояние `healthy`), `curl --cacert ~/devops.crt https://devops.local/app/`, `scripts/audit.sh` (раздел [5])
