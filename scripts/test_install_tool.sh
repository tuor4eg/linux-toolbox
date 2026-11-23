#!/usr/bin/env bash
# Installer regressions. Uses a temporary root and never calls real sudo.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/scripts/install-tool.sh"
BASH_BIN="$(command -v bash)"
failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

link_cmd() {
  local dir="$1" name="$2" src
  src="$(command -v "$name")"
  ln -sf "$src" "$dir/$name"
}

write_exec() {
  local path="$1"
  shift
  printf '%s\n' "$@" > "$path"
  chmod +x "$path"
}

prepare_bin() {
  local dir="$1"
  shift
  mkdir -p "$dir"
  local name
  for name in python3 grep dirname basename install cp mkdir mktemp date; do
    link_cmd "$dir" "$name"
  done
  local extra
  for extra in "$@"; do
    write_exec "$dir/$extra" '#!/bin/sh' 'exit 0'
  done
}

run_installer() {
  local path="$1"
  shift
  set +e
  output="$(PATH="$path" "$BASH_BIN" "$INSTALLER" "$@" 2>&1)"
  code=$?
  set -e
}

expect_fail() {
  local name="$1"
  shift
  if [[ "$code" -eq 0 ]]; then
    fail "$name: expected non-zero, output: $output"
  fi
}

expect_ok() {
  local name="$1"
  if [[ "$code" -ne 0 ]]; then
    fail "$name: expected 0, got $code, output: $output"
  fi
}

assert_contains() {
  local name="$1" needle="$2"
  if [[ "$output" != *"$needle"* ]]; then
    fail "$name: missing [$needle] in: $output"
  fi
}

ip_marker_stub() {
  local dir="$1" marker="$2"
  write_exec "$dir/ip" '#!/bin/sh' "echo ran >> $(printf '%q' "$marker")" 'exit 99'
}

systemctl_stub() {
  local dir="$1" log="$2"
  write_exec "$dir/systemctl" '#!/bin/sh' "printf '%s\n' \"\$*\" >> $(printf '%q' "$log")" 'exit 0'
}

fake_sudo() {
  local path="$1"
  write_exec "$path" '#!/bin/bash' 'set -euo pipefail' \
    'if [[ "${1:-}" == -v ]]; then exit 0; fi' \
    'if [[ "${1:-}" == install ]]; then' \
    '  shift' \
    '  mode=755' \
    '  args=()' \
    '  while [[ $# -gt 0 ]]; do' \
    '    case "$1" in' \
    '      -m) mode="$2"; shift 2 ;;' \
    '      -o|-g) shift 2 ;;' \
    '      *) args+=("$1"); shift ;;' \
    '    esac' \
    '  done' \
    '  exec install -m "$mode" "${args[@]}"' \
    'fi' \
    'exec "$@"'
}

refuse_sudo() {
  local path="$1"
  write_exec "$path" '#!/bin/sh' 'echo sudo-called >&2' 'exit 99'
}

backup_count() {
  find "$1" -mindepth 1 -maxdepth 1 -type d -name 'linux-toolbox-*' | wc -l
}

echo '== missing dependencies fail check =='
tmp="$(mktemp -d)"
prepare_bin "$tmp/bin"
run_installer "$tmp/bin" bypass --check
expect_fail 'bypass without ip'
assert_contains 'bypass without ip' 'отсутствует обязательная команда: ip'
rm -rf "$tmp"

tmp="$(mktemp -d)"
prepare_bin "$tmp/bin" ip
run_installer "$tmp/bin" tunnels --check
expect_fail 'tunnels without ssh'
assert_contains 'tunnels without ssh' 'отсутствует обязательная команда: ssh'
rm -rf "$tmp"

tmp="$(mktemp -d)"
prepare_bin "$tmp/bin" ip nmcli
run_installer "$tmp/bin" vpnctl --check
expect_fail 'vpnctl without ping'
assert_contains 'vpnctl without ping' 'отсутствует обязательная команда: ping'
rm -rf "$tmp"

tmp="$(mktemp -d)"
prepare_bin "$tmp/bin" ip ping
run_installer "$tmp/bin" vpnctl --check
expect_fail 'vpnctl without nmcli'
assert_contains 'vpnctl without nmcli' 'отсутствует обязательная команда: nmcli'
rm -rf "$tmp"

tmp="$(mktemp -d)"
prepare_bin "$tmp/bin" ip nmcli
run_installer "$tmp/bin" work-vpn-audit --check
expect_fail 'audit without curl'
assert_contains 'audit without curl' 'отсутствует обязательная команда: curl'
rm -rf "$tmp"

tmp="$(mktemp -d)"
prepare_bin "$tmp/bin"
run_installer "$tmp/bin" vpnctl --check
expect_fail 'vpnctl lists every missing command'
assert_contains 'vpnctl nmcli' 'nmcli'
assert_contains 'vpnctl ip' 'ip'
assert_contains 'vpnctl ping' 'ping'
rm -rf "$tmp"

echo '== check succeeds when commands exist =='
tmp="$(mktemp -d)"
prepare_bin "$tmp/bin" ip
run_installer "$tmp/bin" bypass --check
expect_ok 'bypass check'
assert_contains 'bypass check' 'Система не изменена.'
rm -rf "$tmp"

tmp="$(mktemp -d)"
prepare_bin "$tmp/bin" ssh
run_installer "$tmp/bin" tunnels --check
expect_ok 'tunnels check'
rm -rf "$tmp"

tmp="$(mktemp -d)"
prepare_bin "$tmp/bin" nmcli ip ping
export LINUX_TOOLBOX_VPNCTL_CONFIG="$tmp/missing.json"
run_installer "$tmp/bin" vpnctl --check
unset LINUX_TOOLBOX_VPNCTL_CONFIG
expect_ok 'vpnctl check without config'
assert_contains 'vpnctl check config note' 'Конфиг отсутствует:'
rm -rf "$tmp"

tmp="$(mktemp -d)"
prepare_bin "$tmp/bin" nmcli ip curl
export LINUX_TOOLBOX_VPNCTL_CONFIG="$tmp/missing.json"
run_installer "$tmp/bin" work-vpn-audit --check
unset LINUX_TOOLBOX_VPNCTL_CONFIG
expect_ok 'audit check without config'
assert_contains 'audit check config note' 'Конфиг отсутствует:'
rm -rf "$tmp"

use_root() {
  export LINUX_TOOLBOX_BIN_DIR="$1"
  export LINUX_TOOLBOX_BACKUP_PARENT="$2"
  export LINUX_TOOLBOX_SUDO="$3"
  if [[ -n "${4:-}" ]]; then
    export LINUX_TOOLBOX_UNIT_DIR="$4"
  else
    unset LINUX_TOOLBOX_UNIT_DIR
  fi
  if [[ -n "${5:-}" ]]; then
    export LINUX_TOOLBOX_VPNCTL_CONFIG="$5"
  else
    unset LINUX_TOOLBOX_VPNCTL_CONFIG
  fi
}

clear_root() {
  unset LINUX_TOOLBOX_BIN_DIR LINUX_TOOLBOX_UNIT_DIR LINUX_TOOLBOX_VPNCTL_CONFIG
  unset LINUX_TOOLBOX_BACKUP_PARENT LINUX_TOOLBOX_SUDO
}

echo '== bypass v1 is not replaced and routes are not touched =='
tmp="$(mktemp -d)"
prepare_bin "$tmp/bin"
ip_marker_stub "$tmp/bin" "$tmp/ip-ran"
refuse_sudo "$tmp/sudo"
mkdir -p "$tmp/bin-dest" "$tmp/backups"
printf '#!/bin/sh\necho legacy-bypass\n' > "$tmp/bin-dest/bypass"
chmod 755 "$tmp/bin-dest/bypass"
printf 'routes-sentinel\n' > "$tmp/routes"
before="$(cat "$tmp/bin-dest/bypass")"
use_root "$tmp/bin-dest" "$tmp/backups" "$tmp/sudo"
run_installer "$tmp/bin" bypass --install --replace
clear_root
expect_fail 'v1 replace refused'
assert_contains 'v1 message' 'установлен старый bypass'
[[ "$(cat "$tmp/bin-dest/bypass")" == "$before" ]] || fail 'v1 binary was modified'
[[ "$(cat "$tmp/routes")" == 'routes-sentinel' ]] || fail 'sentinel routes changed'
[[ ! -e "$tmp/ip-ran" ]] || fail 'ip was executed during v1 refusal'
[[ "$(backup_count "$tmp/backups")" -eq 0 ]] || fail 'backup dir created for refused v1'
rm -rf "$tmp"

echo '== bypass v2 replace keeps routes and writes a non-empty backup =='
tmp="$(mktemp -d)"
prepare_bin "$tmp/bin"
ip_marker_stub "$tmp/bin" "$tmp/ip-ran"
fake_sudo "$tmp/sudo"
mkdir -p "$tmp/bin-dest" "$tmp/backups"
cp "$ROOT/bypass/bypass" "$tmp/bin-dest/bypass"
printf '\n# installed-copy\n' >> "$tmp/bin-dest/bypass"
printf 'routes-sentinel\n' > "$tmp/routes"
printf 'policy-sentinel\n' > "$tmp/policy"
use_root "$tmp/bin-dest" "$tmp/backups" "$tmp/sudo"
run_installer "$tmp/bin" bypass --install --replace
clear_root
expect_ok 'v2 replace'
assert_contains 'v2 replace message' 'Обновлён bypass v2'
cmp -s "$ROOT/bypass/bypass" "$tmp/bin-dest/bypass" || fail 'v2 binary was not replaced from the repo'
[[ "$(cat "$tmp/routes")" == 'routes-sentinel' ]] || fail 'routes sentinel changed on v2 replace'
[[ "$(cat "$tmp/policy")" == 'policy-sentinel' ]] || fail 'policy sentinel changed on v2 replace'
[[ ! -e "$tmp/ip-ran" ]] || fail 'ip was executed during v2 replace'
mapfile -t backups < <(find "$tmp/backups" -mindepth 1 -maxdepth 1 -type d -name 'linux-toolbox-*')
if [[ "${#backups[@]}" -ne 1 ]]; then
  fail "expected one backup dir, got ${#backups[@]}"
elif [[ ! -s "${backups[0]}/bypass" ]]; then
  fail 'backup of previous bypass is empty'
elif ! grep -Fq 'installed-copy' "${backups[0]}/bypass"; then
  fail 'backup does not contain the previous file'
fi
rm -rf "$tmp"

echo '== bypass v2 without --replace is refused =='
tmp="$(mktemp -d)"
prepare_bin "$tmp/bin" ip
refuse_sudo "$tmp/sudo"
mkdir -p "$tmp/bin-dest" "$tmp/backups"
cp "$ROOT/bypass/bypass" "$tmp/bin-dest/bypass"
use_root "$tmp/bin-dest" "$tmp/backups" "$tmp/sudo"
run_installer "$tmp/bin" bypass --install
clear_root
expect_fail 'v2 without replace'
assert_contains 'v2 needs flag' '--replace'
[[ "$(backup_count "$tmp/backups")" -eq 0 ]] || fail 'backup created without --replace'
rm -rf "$tmp"

echo '== vpnctl and work-vpn-audit require an existing config and skip empty backups =='
for tool in vpnctl work-vpn-audit; do
  tmp="$(mktemp -d)"
  if [[ "$tool" == vpnctl ]]; then
    prepare_bin "$tmp/bin" nmcli ip ping
  else
    prepare_bin "$tmp/bin" nmcli ip curl
  fi
  refuse_sudo "$tmp/sudo"
  mkdir -p "$tmp/bin-dest" "$tmp/units" "$tmp/backups"
  use_root "$tmp/bin-dest" "$tmp/backups" "$tmp/sudo" "$tmp/units" "$tmp/vpnctl.json"
  run_installer "$tmp/bin" "$tool" --install
  clear_root
  expect_fail "$tool missing config"
  assert_contains "$tool missing config" 'не создаёт и не изменяет'
  [[ ! -e "$tmp/vpnctl.json" ]] || fail "$tool created vpnctl.json"
  [[ ! -e "$tmp/bin-dest/$tool" ]] || fail "$tool installed despite missing config"
  [[ "$(backup_count "$tmp/backups")" -eq 0 ]] || fail "$tool created a backup without a config"
  rm -rf "$tmp"

  tmp="$(mktemp -d)"
  if [[ "$tool" == vpnctl ]]; then
    prepare_bin "$tmp/bin" nmcli ip ping
  else
    prepare_bin "$tmp/bin" nmcli ip curl
  fi
  systemctl_stub "$tmp/bin" "$tmp/systemctl.log"
  fake_sudo "$tmp/sudo"
  mkdir -p "$tmp/bin-dest" "$tmp/units" "$tmp/backups"
  printf '%s\n' '{"profiles":{"work":{"uuid":"00000000-0000-0000-0000-000000000000","endpoint":"auto","expected_networks":["10.0.0.0/24"]}}}' > "$tmp/vpnctl.json"
  before="$(cat "$tmp/vpnctl.json")"
  use_root "$tmp/bin-dest" "$tmp/backups" "$tmp/sudo" "$tmp/units" "$tmp/vpnctl.json"
  run_installer "$tmp/bin" "$tool" --install
  clear_root
  expect_ok "$tool fresh install"
  [[ -x "$tmp/bin-dest/$tool" ]] || fail "$tool binary missing"
  [[ -f "$tmp/units/$tool.service" && -f "$tmp/units/$tool.timer" ]] || fail "$tool units missing"
  [[ "$(cat "$tmp/vpnctl.json")" == "$before" ]] || fail "$tool rewrote vpnctl.json"
  [[ "$(backup_count "$tmp/backups")" -eq 0 ]] || fail "$tool created an empty backup dir"
  grep -qx 'daemon-reload' "$tmp/systemctl.log" || fail "$tool did not reload systemd"
  if grep -q 'enable' "$tmp/systemctl.log"; then
    fail "$tool enabled a timer without --enable-timer"
  fi
  rm -rf "$tmp"
done

echo '== replace backup is created only when there is something to copy =='
tmp="$(mktemp -d)"
prepare_bin "$tmp/bin" nmcli ip ping
systemctl_stub "$tmp/bin" "$tmp/systemctl.log"
fake_sudo "$tmp/sudo"
mkdir -p "$tmp/bin-dest" "$tmp/units" "$tmp/backups"
printf 'previous-binary\n' > "$tmp/bin-dest/vpnctl"
chmod 755 "$tmp/bin-dest/vpnctl"
printf 'previous-unit\n' > "$tmp/units/vpnctl.service"
printf '%s\n' '{"profiles":{}}' > "$tmp/vpnctl.json"
use_root "$tmp/bin-dest" "$tmp/backups" "$tmp/sudo" "$tmp/units" "$tmp/vpnctl.json"
run_installer "$tmp/bin" vpnctl --install --replace
clear_root
expect_ok 'vpnctl replace'
mapfile -t backups < <(find "$tmp/backups" -mindepth 1 -maxdepth 1 -type d -name 'linux-toolbox-*')
if [[ "${#backups[@]}" -ne 1 ]]; then
  fail "expected one vpnctl backup, got ${#backups[@]}"
elif [[ "$(cat "${backups[0]}/vpnctl")" != 'previous-binary' ]]; then
  fail 'backup missed the previous binary'
elif [[ "$(cat "${backups[0]}/vpnctl.service")" != 'previous-unit' ]]; then
  fail 'backup missed the previous unit'
fi
[[ "$(cat "$tmp/vpnctl.json")" == '{"profiles":{}}' ]] || fail 'replace rewrote vpnctl.json'
rm -rf "$tmp"

if [[ "$failures" -ne 0 ]]; then
  echo "FAILED: $failures" >&2
  exit 1
fi
echo 'installer tests: OK'
