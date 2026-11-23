#!/usr/bin/env bash
# Installer invoked from linux-toolbox repository. No network access.
# Test overrides, unset in normal use: LINUX_TOOLBOX_BIN_DIR,
# LINUX_TOOLBOX_UNIT_DIR, LINUX_TOOLBOX_VPNCTL_CONFIG,
# LINUX_TOOLBOX_BACKUP_PARENT, LINUX_TOOLBOX_SUDO.
set -euo pipefail
TOOL="${1:-}"; shift || true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=check
REPLACE=0
ENABLE_TIMER=0
for opt in "$@"; do
  case "$opt" in
    --check) MODE=check ;;
    --install) MODE=install ;;
    --replace) REPLACE=1 ;;
    --enable-timer) ENABLE_TIMER=1 ;;
    *) echo "Неизвестная опция: $opt" >&2; exit 2 ;;
  esac
done
case "$TOOL" in
  bypass|tunnels|vpnctl|work-vpn-audit) ;;
  *) echo "Неизвестная утилита: $TOOL" >&2; exit 2 ;;
esac
if [[ "$ENABLE_TIMER" == 1 && "$TOOL" != vpnctl && "$TOOL" != work-vpn-audit ]]; then
  echo "У $TOOL нет таймера" >&2; exit 2
fi
SRC="$ROOT/$TOOL/$TOOL"
[[ -f "$SRC" ]] || { echo "Нет исходника: $SRC" >&2; exit 1; }

missing=0
require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Ошибка: отсутствует обязательная команда: $1" >&2
    missing=1
  fi
}
require_cmd python3
case "$TOOL" in
  bypass)
    require_cmd ip
    ;;
  tunnels)
    require_cmd ssh
    ;;
  vpnctl)
    require_cmd nmcli
    require_cmd ip
    require_cmd ping
    ;;
  work-vpn-audit)
    require_cmd nmcli
    require_cmd ip
    require_cmd curl
    ;;
esac
if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

python3 - "$SRC" <<'PY'
import ast, pathlib, sys
ast.parse(pathlib.Path(sys.argv[1]).read_text())
print('Python: OK')
PY

BIN_DIR="${LINUX_TOOLBOX_BIN_DIR:-/usr/local/bin}"
UNIT_DIR="${LINUX_TOOLBOX_UNIT_DIR:-/etc/systemd/system}"
VPNCTL_CONFIG="${LINUX_TOOLBOX_VPNCTL_CONFIG:-/etc/vpnctl.json}"
BACKUP_PARENT="${LINUX_TOOLBOX_BACKUP_PARENT:-/var/backups}"

# LINUX_TOOLBOX_SUDO unset: real sudo. Empty: run as the current user.
# A path: that program is the sudo prefix (tests).
root() {
  if [[ -n "${LINUX_TOOLBOX_SUDO+x}" ]]; then
    if [[ -z "$LINUX_TOOLBOX_SUDO" ]]; then
      if [[ "${1:-}" == -v ]]; then
        return 0
      fi
      "$@"
      return
    fi
    "$LINUX_TOOLBOX_SUDO" "$@"
    return
  fi
  sudo "$@"
}

if [[ "$TOOL" == tunnels ]]; then
  DEST="${HOME}/.local/bin/tunnels"
  # User-local installation: sudo is deliberately not used.
  UNITS=()
else
  DEST="$BIN_DIR/$TOOL"
  UNITS=()
  if [[ "$TOOL" == vpnctl || "$TOOL" == work-vpn-audit ]]; then
    UNITS=("$TOOL.service" "$TOOL.timer")
  fi
fi

printf 'Утилита: %s\nИсходник: %s\nНазначение: %s\nРежим: %s\n' "$TOOL" "$SRC" "$DEST" "$MODE"
[[ -e "$DEST" ]] && echo "Уже существует: $DEST"
for unit in "${UNITS[@]}"; do
  f="$ROOT/$TOOL/systemd/$unit"
  [[ -f "$f" ]] || { echo "Отсутствует $f" >&2; exit 1; }
  [[ "$unit" == *.service ]] && grep -Fq "/usr/local/bin/$TOOL" "$f" || true
  echo "Unit: $unit"
done
if [[ "$TOOL" == vpnctl || "$TOOL" == work-vpn-audit ]]; then
  if [[ -f "$VPNCTL_CONFIG" ]]; then
    echo "Конфиг на месте: $VPNCTL_CONFIG"
  else
    echo "Конфиг отсутствует: $VPNCTL_CONFIG"
  fi
fi
if [[ "$TOOL" == bypass ]]; then
  if [[ -e "$DEST" ]] && ! grep -Fq 'managed-routes.json' "$DEST"; then
    echo 'ВАЖНО: установлен bypass без реестра. --replace его не заменит; нужна отдельная миграция. Маршруты не изменяются.'
  else
    echo 'ВАЖНО: --replace обновляет только bypass v2 (в программе есть managed-routes.json). Версию без реестра установщик не мигрирует и маршруты не трогает.'
  fi
fi
if [[ "$MODE" == check ]]; then
  echo 'Проверка завершена. Система не изменена.'
  exit 0
fi

if [[ "$TOOL" == bypass && -e "$DEST" ]]; then
  if [[ "$REPLACE" != 1 ]] || ! grep -Fq 'managed-routes.json' "$DEST"; then
    if ! grep -Fq 'managed-routes.json' "$DEST"; then
      echo 'ОТКАЗ: установлен старый bypass. Требуется отдельная миграция маршрутов/правил.' >&2
    else
      echo "ОТКАЗ: $DEST уже существует. Для обновления bypass v2 укажите --replace." >&2
    fi
    exit 1
  fi
fi
if [[ -e "$DEST" && "$REPLACE" != 1 ]]; then
  echo "ОТКАЗ: $DEST уже существует. Для замены укажите --replace." >&2
  exit 1
fi
for unit in "${UNITS[@]}"; do
  destunit="$UNIT_DIR/$unit"
  if [[ -e "$destunit" && "$REPLACE" != 1 ]]; then
    echo "ОТКАЗ: $destunit уже существует. Укажите --replace." >&2
    exit 1
  fi
done
if [[ "$TOOL" == vpnctl || "$TOOL" == work-vpn-audit ]]; then
  if [[ ! -f "$VPNCTL_CONFIG" ]]; then
    echo "ОТКАЗ: нет $VPNCTL_CONFIG. Создайте его вручную до установки. Установщик этот файл не создаёт и не изменяет." >&2
    exit 1
  fi
fi

if [[ "$TOOL" == tunnels ]]; then
  mkdir -p "$(dirname "$DEST")"
  if [[ -e "$DEST" ]]; then
    cp -a "$DEST" "$DEST.bak.$(date +%Y%m%d%H%M%S)"
  fi
  install -m 755 "$SRC" "$DEST"
  echo "Установлено: $DEST"
  exit 0
fi

# Routing, policy and /etc/vpnctl.json are intentionally left untouched.
had_dest=0
[[ -e "$DEST" ]] && had_dest=1
root -v
backup_needed=0
[[ -e "$DEST" ]] && backup_needed=1
for unit in "${UNITS[@]}"; do
  [[ -e "$UNIT_DIR/$unit" ]] && backup_needed=1
done
if [[ "$backup_needed" == 1 ]]; then
  BACKUP="$(root mktemp -d "$BACKUP_PARENT/linux-toolbox-XXXXXXXX")"
  echo "Каталог резервных копий: $BACKUP"
  if [[ -e "$DEST" ]]; then
    root cp -a "$DEST" "$BACKUP/$(basename "$DEST")"
  fi
  for unit in "${UNITS[@]}"; do
    if [[ -e "$UNIT_DIR/$unit" ]]; then
      root cp -a "$UNIT_DIR/$unit" "$BACKUP/$unit"
    fi
  done
fi
root install -m 755 -o root -g root "$SRC" "$DEST"
for unit in "${UNITS[@]}"; do
  root install -m 644 -o root -g root "$ROOT/$TOOL/systemd/$unit" "$UNIT_DIR/$unit"
done
if ((${#UNITS[@]} > 0)); then
  root systemctl daemon-reload
  if [[ "$ENABLE_TIMER" == 1 ]]; then
    root systemctl enable --now "$TOOL.timer"
  else
    echo "Таймер не включался. Для запуска: sudo systemctl enable --now $TOOL.timer"
  fi
fi
if [[ "$TOOL" == vpnctl ]]; then
  echo 'Конфиг /etc/vpnctl.json не создавался и не изменялся.'
  echo 'ВНИМАНИЕ: до включения таймера проверьте корректность профилей и маршрутов.'
elif [[ "$TOOL" == work-vpn-audit ]]; then
  echo 'Аудит использует существующий /etc/vpnctl.json; база SQLite не тронута.'
elif [[ "$TOOL" == bypass ]]; then
  if [[ "$had_dest" == 1 ]]; then
    echo 'Обновлён bypass v2. Маршруты, политика и исключения не изменялись.'
  else
    echo 'Установлен bypass v2 на чистую систему. Политика и исключения не создавались.'
  fi
fi
