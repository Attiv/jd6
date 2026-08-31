#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/qianwen-update-tests.XXXXXX")"
trap '/bin/rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_absent() {
  [[ ! -e "$1" ]] || fail "expected path to be absent: $1"
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "expected '$2' in $1"
}

make_fake_app() {
  local app="$1"
  mkdir -p "$app/Contents/Helpers" "$app/Contents/MacOS"
  cat >"$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>1.1.5</string>
<key>CFBundleVersion</key><string>1.1.5.23</string>
</dict></plist>
PLIST
  printf '#!/bin/sh\nexit 0\n' >"$app/Contents/Helpers/QianwenIMEUpdater"
  chmod +x "$app/Contents/Helpers/QianwenIMEUpdater"
  printf 'current app payload\n' >"$app/Contents/MacOS/QianwenIME"
}

APP="$TMP_ROOT/QianwenIME.app"
BACKUPS="$TMP_ROOT/Backups"
POINTER="$BACKUPS/latest-app-snapshot.txt"
QIME="$TMP_ROOT/Qime"
mkdir -p "$QIME"
printf 'do not restore me\n' >"$QIME/user-data-sentinel"
make_fake_app "$APP"

QW_APP="$APP" NO_RELOAD=1 \
  "$ROOT_DIR/scripts/qianwen_update_control.sh" block
assert_file "$APP/Contents/Helpers/QianwenIMEUpdater.disabled"
assert_absent "$APP/Contents/Helpers/QianwenIMEUpdater"

QW_APP="$APP" NO_RELOAD=1 \
  "$ROOT_DIR/scripts/qianwen_update_control.sh" status >"$TMP_ROOT/blocked.status"
assert_contains "$TMP_ROOT/blocked.status" '自动更新：已屏蔽'

QW_APP="$APP" NO_RELOAD=1 \
  "$ROOT_DIR/scripts/qianwen_update_control.sh" unblock
assert_file "$APP/Contents/Helpers/QianwenIMEUpdater"
assert_absent "$APP/Contents/Helpers/QianwenIMEUpdater.disabled"

QW_APP="$APP" NO_RELOAD=1 \
  "$ROOT_DIR/scripts/qianwen_update_control.sh" status >"$TMP_ROOT/enabled.status"
assert_contains "$TMP_ROOT/enabled.status" '自动更新：已启用'

QW_APP="$APP" BACKUP_ROOT="$BACKUPS" RESTORE_POINTER="$POINTER" \
  "$ROOT_DIR/scripts/backup_qianwen_app.sh" >"$TMP_ROOT/backup.log"
assert_file "$POINTER"
SNAPSHOT="$(cat "$POINTER")"
assert_file "$SNAPSHOT/Contents/Info.plist"
assert_file "$SNAPSHOT.sha256"
assert_absent "$BACKUPS/Qime"
assert_contains "$QIME/user-data-sentinel" 'do not restore me'

printf 'changed after snapshot\n' >"$APP/Contents/MacOS/QianwenIME"

cat >"$TMP_ROOT/fake-rollback.sh" <<'FAKE'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$@" >"$ROLLBACK_ARGS_FILE"
[[ "$1" == install ]]
source_app="$2"
/bin/rm -rf "$QW_APP"
/usr/bin/ditto "$source_app" "$QW_APP"
FAKE
chmod +x "$TMP_ROOT/fake-rollback.sh"

QW_APP="$APP" RESTORE_POINTER="$POINTER" \
ROLLBACK_SCRIPT="$TMP_ROOT/fake-rollback.sh" \
ROLLBACK_ARGS_FILE="$TMP_ROOT/rollback.args" \
  "$ROOT_DIR/scripts/restore_qianwen_app.sh" --no-reload

assert_contains "$APP/Contents/MacOS/QianwenIME" 'current app payload'
assert_contains "$TMP_ROOT/rollback.args" '--skip-user-backup'
assert_contains "$TMP_ROOT/rollback.args" '--keep-updater'
assert_contains "$TMP_ROOT/rollback.args" '--allow-modified-source'
assert_contains "$TMP_ROOT/rollback.args" '--no-reload'
assert_contains "$QIME/user-data-sentinel" 'do not restore me'

"$ROOT_DIR/scripts/rollback_qianwen.sh" --help >"$TMP_ROOT/rollback.help"
assert_contains "$TMP_ROOT/rollback.help" '--skip-user-backup'
assert_contains "$TMP_ROOT/rollback.help" '--allow-modified-source'

printf 'PASS: Qianwen update-control, App snapshot, and App-only restore tests\n'
