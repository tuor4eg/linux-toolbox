#!/usr/bin/env bash
# Installer invoked from linux-toolbox repository. No network access.
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
python3 - "$SRC" <<'PY'
import ast, pathlib, sys
ast.parse(pathlib.Path(sys.argv[1]).read_text())
print('Python: OK')
PY
case "$TOOL" in
  bypass) for command in ip; do command -v "$command" >/dev/null || echo "Предупреждение: отсутствует $command"; done ;;
  vpnctl|work-vpn-audit) for command in nmcli ip; do command -v "$command" >/dev/null || echo "Предупреждение: отсутствует $command"; done ;;
  tunnels) command -v ssh >/dev/null || echo 'Предупреждение: отсутствует ssh' ;;
esac

if [[ "$TOOL" == tunnels ]]; then
  DEST="${HOME}/.local/bin/tunnels"
  # User-local installation: sudo is deliberately not used.
  UNITS=()
else
  DEST="/usr/local/bin/$TOOL"
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
if [[ "$TOOL" == bypass ]]; then
  echo 'ВАЖНО: bypass v2 требует отдельной миграции старых правил; этот установщик не заменяет существующий bypass.'
fi
if [[ "$MODE" == check ]]; then
  echo 'Проверка завершена. Система не изменена.'
  exit 0
fi

if [[ "$TOOL" == bypass && -e "$DEST" ]]; then
  echo 'ОТКАЗ: установлен старый bypass. Требуется отдельная миграция маршрутов/правил.' >&2
  exit 1
fi
if [[ -e "$DEST" && "$REPLACE" != 1 ]]; then
  echo "ОТКАЗ: $DEST уже существует. Для замены укажите --replace (кроме bypass)." >&2
  exit 1
fi
for unit in "${UNITS[@]}"; do
  destunit="/etc/systemd/system/$unit"
  if [[ -e "$destunit" && "$REPLACE" != 1 ]]; then
    echo "ОТКАЗ: $destunit уже существует. Укажите --replace." >&2
    exit 1
  fi
done

if [[ "$TOOL" == tunnels ]]; then
  mkdir -p "$(dirname "$DEST")"
  if [[ -e "$DEST" ]]; then
    cp -a "$DEST" "$DEST.bak.$(date +%Y%m%d%H%M%S)"
  fi
  install -m 755 "$SRC" "$DEST"
  echo "Установлено: $DEST"
  exit 0
fi

# All checks above precede any sudo mutation.
sudo -v
BACKUP=""
if [[ -e "$DEST" ]] || ((${#UNITS[@]} > 0)); then
  BACKUP="$(sudo mktemp -d /var/backups/linux-toolbox-XXXXXXXX)"
  echo "Каталог резервных копий: $BACKUP"
fi
if [[ -e "$DEST" ]]; then
  sudo cp -a "$DEST" "$BACKUP/$(basename "$DEST")"
fi
for unit in "${UNITS[@]}"; do
  if [[ -e "/etc/systemd/system/$unit" ]]; then
    sudo cp -a "/etc/systemd/system/$unit" "$BACKUP/$unit"
  fi
done
sudo install -m 755 -o root -g root "$SRC" "$DEST"
for unit in "${UNITS[@]}"; do
  sudo install -m 644 -o root -g root "$ROOT/$TOOL/systemd/$unit" "/etc/systemd/system/$unit"
done
if ((${#UNITS[@]} > 0)); then
  sudo systemctl daemon-reload
  if [[ "$ENABLE_TIMER" == 1 ]]; then
    sudo systemctl enable --now "$TOOL.timer"
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
  echo 'Установлен bypass v2 на чистую систему. Политика и исключения не создавались.'
fi
