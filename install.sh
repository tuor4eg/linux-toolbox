#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() {
  cat <<'HELP'
Использование:
  ./install.sh list
  ./install.sh check [all|bypass|tunnels|vpnctl|work-vpn-audit]
  ./install.sh install <tool> [--replace] [--enable-timer]
По умолчанию только проверка; установка выполняется явно.
Для bypass --replace обновляет только v2 (в файле есть managed-routes.json).
Старую версию без реестра установщик не заменяет и маршруты не меняет.
HELP
}
cmd="${1:-}"; shift || true
case "$cmd" in
  list)
    printf '%s\n' bypass tunnels vpnctl work-vpn-audit ;;
  check)
    tool="${1:-all}"
    if [[ "$tool" == all ]]; then
      for t in bypass tunnels vpnctl work-vpn-audit; do
        echo "========== $t =========="
        "$ROOT/scripts/install-tool.sh" "$t" --check
      done
    else
      "$ROOT/scripts/install-tool.sh" "$tool" --check
    fi ;;
  install)
    tool="${1:-}"; [[ -n "$tool" ]] || { usage; exit 2; }; shift
    "$ROOT/scripts/install-tool.sh" "$tool" --install "$@" ;;
  *) usage; [[ -z "$cmd" ]] || exit 2 ;;
esac
