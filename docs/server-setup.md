# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины
- Гипервизор: Oracle VirtualBox 7.x на macOS (Apple Silicon)
- ОС: Ubuntu Server 24.04 LTS (arm64)
- Оперативная память: 2048 МБ
- Ядра процессора: 2
- Диск: 25 ГБ, динамически расширяемый

## 2. Сетевые интерфейсы
| Адаптер | Тип | Адрес | Назначение |
|---|---|---|---|
| 1 | NAT | 10.0.2.15 | выход в Интернет (репозитории пакетов), проброс порта SSH |
| 2 | Host-only | 192.168.56.101 | доступ с хоста (SSH по имени, веб-сервер в ПР № 6) |

Имя узла: `devops-vm`, полное имя: `devops-vm.devops.local`. На хосте в `/etc/hosts`: `192.168.56.101 devops.local`.

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
