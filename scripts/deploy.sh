#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                      # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

# 1. Разбор аргумента --dry-run
DRY_RUN=0
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN=1 ;;
    *)         echo "Использование: scripts/deploy.sh [--dry-run]" >&2; exit 2 ;;
esac

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл site/index.html отсутствует, доставка не выполняется" >&2
    exit 1
fi
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения, доставка не выполняется" >&2
    exit 1
fi

# 3. Синхронизация каталога ${LOCAL_DIR} на ${REMOTE}:${REMOTE_DIR}
RSYNC_OPTS=(-avz --delete)
# Встроенный в macOS rsync (openrsync) может не поддерживать --chmod:
# проверяем и при необходимости выравниваем права по ssh после доставки.
CHMOD_VIA_RSYNC=0
CHECK_DIR="$(mktemp -d)"
if rsync -n -r --chmod=D755,F644 "$LOCAL_DIR" "$CHECK_DIR/" >/dev/null 2>&1; then
    CHMOD_VIA_RSYNC=1
    RSYNC_OPTS+=(--chmod=D755,F644)
fi
rmdir "$CHECK_DIR" 2>/dev/null || true
if [[ $DRY_RUN -eq 1 ]]; then
    RSYNC_OPTS+=(--dry-run)
fi
rsync "${RSYNC_OPTS[@]}" \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"

if [[ $DRY_RUN -eq 0 && $CHMOD_VIA_RSYNC -eq 0 ]]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE" \
        "find '${REMOTE_DIR}' -type d -exec chmod 755 {} + && find '${REMOTE_DIR}' -type f -exec chmod 644 {} +"
fi

# 4. При --dry-run — завершение с кодом 0 без проверки доступности
if [[ $DRY_RUN -eq 1 ]]; then
    echo "Пробный запуск завершён: состояние сервера не изменено"
    exit 0
fi

# 5. Проверка доступности ${SITE_URL} (с проверкой сертификата) и завершение
if ! curl -fsS --cacert "$CA_CERT" -o /dev/null "$SITE_URL"; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен или сертификат не прошёл проверку" >&2
    exit 1
fi

echo "Доставлен коммит $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
exit 0
