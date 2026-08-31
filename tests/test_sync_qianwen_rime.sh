#!/bin/bash
set -euo pipefail

SCRIPT="/Users/mac/Library/Rime/scripts/sync_qianwen_rime.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/test-qime-sync.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_contains() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || fail "$file does not contain: $text"
}

assert_not_contains() {
  local file="$1"
  local text="$2"
  if grep -Fq -- "$text" "$file"; then
    fail "$file unexpectedly contains: $text"
  fi
}

assert_equal_files() {
  cmp -s "$1" "$2" || fail "files differ: $1 <> $2"
}

APP="$TMP_ROOT/QianwenIME.app"
DATA="$APP/Contents/SharedSupport/qw_ime_data"
SCHEMAS="$DATA/schemas"
BUILD="$DATA/rime_user/build"
QIME="$TMP_ROOT/Qime"
RIME="$TMP_ROOT/Rime"
FAKE_BUILD="$TMP_ROOT/fake-build"
BACKUPS="$TMP_ROOT/backups"
STATE="$TMP_ROOT/state"
MOCK_BIN="$TMP_ROOT/bin"
COMPAT_LIBQIME="$TMP_ROOT/libqime-key-semantics.dylib"

mkdir -p "$SCHEMAS/lua/xmjd6" "$BUILD" "$QIME" \
  "$RIME/lua/xmjd6" "$RIME/opencc" "$FAKE_BUILD" "$MOCK_BIN" \
  "$APP/Contents/Frameworks"

cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleShortVersionString</key><string>1.2.3</string>
  <key>CFBundleVersion</key><string>456</string>
</dict></plist>
PLIST

printf 'vendor-default\n' >"$SCHEMAS/default.yaml"
printf 'old-qw-schema\n' >"$SCHEMAS/qw.schema.yaml"
printf 'old-qw-double-schema\n' >"$SCHEMAS/qw_double.schema.yaml"
printf 'old-qw-build-schema\n' >"$BUILD/qw.schema.yaml"
printf 'old-qw-double-build-schema\n' >"$BUILD/qw_double.schema.yaml"
printf 'old-qw-prism\n' >"$BUILD/qw.prism.bin"
printf 'old-qw-reverse\n' >"$BUILD/qw.reverse.bin"
printf 'old-qw-table\n' >"$BUILD/qw.table.bin"
printf 'old-qw-double-table\n' >"$BUILD/qw_double.table.bin"
printf 'new-engine-456\n' >"$APP/Contents/Frameworks/libqime.dylib"
printf 'engine-wrapper\n' >"$APP/Contents/Frameworks/libqianwen_engine.dylib"
printf 'key-semantics-engine\n' >"$COMPAT_LIBQIME"
printf 'runtime-order\n' >"$QIME/candidate_order.txt"
printf 'runtime-phrase\n' >"$QIME/dynamic_phrases.txt"

cat >"$RIME/default.yaml" <<'YAML'
schema_list:
  - schema: xmjd6
YAML

cat >"$RIME/xmjd6.schema.yaml" <<'YAML'
schema:
  schema_id: xmjd6
engine:
  processors:
    - ascii_composer
translator:
  dictionary: xmjd6.extended
sentence_mode:
  dictionary: xmjd6.extended
YAML

printf 'name: xmjd6.extended\n' >"$RIME/xmjd6.extended.dict.yaml"
printf 'name: xmjd6.cx\n' >"$RIME/xmjd6.cx.dict.yaml"
printf 'name: xmjd6.fuhao\n' >"$RIME/xmjd6.fuhao.dict.yaml"
printf 'return {}\n' >"$RIME/lua/xmjd6/example.lua"
printf '{"name":"test"}\n' >"$RIME/opencc/test.json"
printf 'source-order\n' >"$RIME/candidate_order.txt"
printf 'source-phrase\n' >"$RIME/dynamic_phrases.txt"
printf 'source-anniversary\n' >"$RIME/anniversaries.txt"

cp "$RIME/xmjd6.schema.yaml" "$FAKE_BUILD/xmjd6.schema.yaml"
printf 'prism-data\n' >"$FAKE_BUILD/xmjd6.extended.prism.bin"
printf 'reverse-data\n' >"$FAKE_BUILD/xmjd6.extended.reverse.bin"
printf 'table-data\n' >"$FAKE_BUILD/xmjd6.extended.table.bin"
printf 'cx-data\n' >"$FAKE_BUILD/xmjd6.cx.table.bin"

cat >"$MOCK_BIN/rime_deployer" <<'SH'
#!/bin/bash
set -euo pipefail
[[ "$1" == "--build" ]]
mkdir -p "$4"
cp "$FAKE_BUILD_DIR"/* "$4/"
printf '%s\n' "$*" >>"$DEPLOY_LOG"
SH
chmod +x "$MOCK_BIN/rime_deployer"

cat >"$MOCK_BIN/relaunch" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$RELAUNCH_LOG"
SH
chmod +x "$MOCK_BIN/relaunch"

cat >"$MOCK_BIN/atomic_swap" <<'SH'
#!/bin/bash
set -euo pipefail
[[ "$1" == "--current" && "$3" == "--next" ]]
current="$2"
next="$4"
temporary="${current}.test-swap.$$"
mv "$current" "$temporary"
mv "$next" "$current"
mv "$temporary" "$next"
printf 'atomic swap succeeded current=%s next=%s\n' "$current" "$next"
printf 'run\n' >>"$ATOMIC_SWAP_LOG"
SH
chmod +x "$MOCK_BIN/atomic_swap"

cat >"$MOCK_BIN/launchctl" <<'SH'
#!/bin/bash
set -euo pipefail
case "$1" in
  bootstrap)
    plist="$3"
    /usr/bin/python3 - "$plist" <<'PY'
import plistlib
import subprocess
import sys

with open(sys.argv[1], "rb") as stream:
    job = plistlib.load(stream)
with open(job["StandardOutPath"], "wb") as stdout, \
     open(job["StandardErrorPath"], "wb") as stderr:
    result = subprocess.run(job["ProgramArguments"], stdout=stdout, stderr=stderr)
raise SystemExit(result.returncode)
PY
    ;;
  bootout)
    exit 0
    ;;
  print)
    exit 1
    ;;
  *)
    exit 2
    ;;
esac
SH
chmod +x "$MOCK_BIN/launchctl"

cat >"$MOCK_BIN/codesign" <<'SH'
#!/bin/bash
set -euo pipefail
if [[ " $* " == *" -dv "* ]]; then
  printf 'CDHash=fixture-cdhash\nTeamIdentifier=FIXTURETEAM\n' >&2
fi
exit 0
SH
chmod +x "$MOCK_BIN/codesign"

cat >"$MOCK_BIN/lipo" <<'SH'
#!/bin/bash
set -euo pipefail
[[ "$1" == "$QW_COMPAT_LIBQIME" ]]
[[ "$2" == "-verify_arch" ]]
[[ "$3" == "$(uname -m)" ]]
SH
chmod +x "$MOCK_BIN/lipo"

cat >"$MOCK_BIN/nm" <<'SH'
#!/bin/bash
set -euo pipefail
symbol='__ZN4qime11QimeSession9InputTextENSt3__117basic_string_viewIcNS1_11char_traitsIcEEEE'
missing='__ZN4qime10QimeEngine17QueryQuickPhrasesEv'
case "$1" in
  -u)
    printf '%s\n' "$symbol"
    if [[ "${NM_MISSING_ABI:-0}" == "1" ]]; then
      printf '%s\n' "$missing"
    fi
    ;;
  -gU)
    printf '0000000000000000 T _RimeFindModule\n'
    printf '0000000000000000 T %s\n' "$symbol"
    ;;
esac
SH
chmod +x "$MOCK_BIN/nm"

run_sync() {
  PATH="$MOCK_BIN:$PATH" \
  QW_APP="$APP" \
  QW_USER_DIR="$QIME" \
  RIME_DIR="$RIME" \
  BACKUP_ROOT="$BACKUPS" \
  STATE_DIR="$STATE" \
  RIME_DEPLOYER="$MOCK_BIN/rime_deployer" \
  SQUIRREL_SHARED="$TMP_ROOT/squirrel-shared" \
  QW_RELAUNCHER="$MOCK_BIN/relaunch" \
  QW_ATOMIC_SWAPPER="$MOCK_BIN/atomic_swap" \
  QW_LAUNCHCTL="$MOCK_BIN/launchctl" \
  QW_COMPAT_LIBQIME="$COMPAT_LIBQIME" \
  QW_SKIP_ENGINE_ABI_CHECK=0 \
  FAKE_BUILD_DIR="$FAKE_BUILD" \
  DEPLOY_LOG="$TMP_ROOT/deploy.log" \
  RELAUNCH_LOG="$TMP_ROOT/relaunch.log" \
  ATOMIC_SWAP_LOG="$TMP_ROOT/atomic-swap.log" \
  "$SCRIPT" "$@"
}

mkdir -p "$TMP_ROOT/squirrel-shared"

run_sync sync

BACKUP_DIR="$(find "$BACKUPS" -maxdepth 1 -type d -name 'qime-pre-sync-1.2.3-456-*' | head -1)"
[[ -n "$BACKUP_DIR" ]] || fail "versioned pre-sync backup was not created"
assert_contains "$BACKUP_DIR/qw_ime_data/schemas/qw.schema.yaml" "old-qw-schema"
assert_contains "$BACKUP_DIR/qw_ime_data/schemas/qw_double.schema.yaml" "old-qw-double-schema"
assert_contains "$BACKUP_DIR/Frameworks/libqime.dylib" "new-engine-456"

assert_contains "$SCHEMAS/qw.schema.yaml" "old-qw-schema"
assert_contains "$BUILD/qw.schema.yaml" "old-qw-build-schema"
assert_contains "$BUILD/qw.prism.bin" "old-qw-prism"
assert_contains "$BUILD/qw.reverse.bin" "old-qw-reverse"
assert_contains "$BUILD/qw.table.bin" "old-qw-table"
assert_contains "$SCHEMAS/qw_double.schema.yaml" "schema_id: qw_double"
assert_contains "$SCHEMAS/qw_double.schema.yaml" "dictionary: qw_double"
assert_contains "$SCHEMAS/qw_double.schema.yaml" "lua_processor@*xmjd6/qime_trigger_compat"
[[ "$(grep -Fc 'lua_processor@*xmjd6/qime_trigger_compat' "$SCHEMAS/qw_double.schema.yaml")" -eq 1 ]] \
  || fail "compat processor was inserted more than once"
assert_not_contains "$SCHEMAS/qw_double.schema.yaml" "dictionary: xmjd6.extended"
assert_contains "$SCHEMAS/default.yaml" "vendor-default"

assert_file "$SCHEMAS/lua/xmjd6/qime_trigger_compat.lua"
assert_contains "$SCHEMAS/lua/xmjd6/qime_trigger_compat.lua" "utf8.char(0x200B)"
assert_contains "$SCHEMAS/lua/xmjd6/qime_trigger_compat.lua" "context:pop_input(3)"
assert_not_contains "$SCHEMAS/lua/xmjd6/qime_trigger_compat.lua" "ch .. ch"
assert_equal_files "$RIME/lua/xmjd6/example.lua" "$SCHEMAS/lua/xmjd6/example.lua"
assert_equal_files "$RIME/opencc/test.json" "$SCHEMAS/opencc/test.json"
assert_equal_files "$FAKE_BUILD/xmjd6.extended.table.bin" "$BUILD/qw_double.table.bin"
assert_equal_files "$FAKE_BUILD/xmjd6.extended.prism.bin" "$BUILD/qw_double.prism.bin"
assert_equal_files "$FAKE_BUILD/xmjd6.extended.reverse.bin" "$BUILD/qw_double.reverse.bin"
assert_equal_files "$COMPAT_LIBQIME" "$APP/Contents/Frameworks/libqime.dylib"
assert_equal_files "$RIME/xmjd6.cx.dict.yaml" "$QIME/xmjd6.cx.dict.yaml"
assert_equal_files "$RIME/xmjd6.fuhao.dict.yaml" "$QIME/xmjd6.fuhao.dict.yaml"

# Runtime learning/state is deliberately preserved unless explicitly requested.
assert_contains "$QIME/candidate_order.txt" "runtime-order"
assert_contains "$QIME/dynamic_phrases.txt" "runtime-phrase"

assert_file "$STATE/last-sync.env"
assert_contains "$STATE/last-sync.env" "app_version=1.2.3"
assert_contains "$STATE/last-sync.env" "app_build=456"
assert_contains "$STATE/last-sync.env" "engine_compat_sha256="
assert_file "$TMP_ROOT/deploy.log"
awk '$1 == "--build" && $2 == $3 {found=1} END {exit !found}' "$TMP_ROOT/deploy.log" \
  || fail "deployer must use the staged Rime source as shared data, not Squirrel presets"
assert_file "$TMP_ROOT/relaunch.log"

run_sync status >"$TMP_ROOT/status-current.log"
assert_contains "$TMP_ROOT/status-current.log" "已同步"

# A new app build must be reported as needing a re-sync.
plutil -replace CFBundleVersion -string 457 "$APP/Contents/Info.plist"
set +e
run_sync status >"$TMP_ROOT/status-updated.log" 2>&1
STATUS_RC=$?
set -e
[[ "$STATUS_RC" -eq 10 ]] || fail "updated app status exit code: $STATUS_RC (expected 10)"
assert_contains "$TMP_ROOT/status-updated.log" "检测到千问更新"

# Explicit runtime synchronization is opt-in.
printf 'new-engine-457\n' >"$APP/Contents/Frameworks/libqime.dylib"
run_sync sync --with-runtime
assert_contains "$QIME/candidate_order.txt" "source-order"
assert_contains "$QIME/dynamic_phrases.txt" "source-phrase"
assert_equal_files "$COMPAT_LIBQIME" "$APP/Contents/Frameworks/libqime.dylib"

BACKUP_457="$(find "$BACKUPS" -maxdepth 1 -type d -name 'qime-pre-sync-1.2.3-457-*' | head -1)"
assert_contains "$BACKUP_457/Frameworks/libqime.dylib" "new-engine-457"

# App Management-protected updates are installed through one non-restarting
# launchd job and an atomic Contents exchange.
plutil -replace CFBundleVersion -string 458 "$APP/Contents/Info.plist"
printf 'new-engine-458\n' >"$APP/Contents/Frameworks/libqime.dylib"
printf 'return {atomic=true}\n' >"$RIME/lua/xmjd6/example.lua"
QW_FORCE_ATOMIC_STAGE=1 run_sync sync
assert_contains "$SCHEMAS/lua/xmjd6/example.lua" "atomic=true"
assert_equal_files "$COMPAT_LIBQIME" "$APP/Contents/Frameworks/libqime.dylib"
[[ "$(wc -l <"$TMP_ROOT/atomic-swap.log" | tr -d ' ')" -eq 1 ]] \
  || fail "atomic Contents exchange did not run exactly once"
assert_contains "$STATE/last-sync.env" "app_build=458"
assert_contains "$STATE/last-sync.env" "engine_compat_status=installed"

# 千问新版引擎包装层要求兼容 libqime 没有的 ABI 时：严格模式必须在改动任何
# 千问文件之前中止。
plutil -replace CFBundleVersion -string 459 "$APP/Contents/Info.plist"
printf 'new-engine-459\n' >"$APP/Contents/Frameworks/libqime.dylib"
printf 'return {abi=true}\n' >"$RIME/lua/xmjd6/example.lua"
export NM_MISSING_ABI=1

set +e
export QW_ENGINE_COMPAT_STRICT=1
run_sync sync >"$TMP_ROOT/strict.log" 2>&1
STRICT_RC=$?
unset QW_ENGINE_COMPAT_STRICT
set -e
[[ "$STRICT_RC" -ne 0 ]] || fail "strict mode must abort on missing engine ABI"
assert_contains "$TMP_ROOT/strict.log" "QW_ENGINE_COMPAT_STRICT=1"
assert_contains "$APP/Contents/Frameworks/libqime.dylib" "new-engine-459"
assert_not_contains "$SCHEMAS/lua/xmjd6/example.lua" "abi=true"
[[ -z "$(find "$BACKUPS" -maxdepth 1 -type d -name 'qime-pre-sync-1.2.3-459-*')" ]] \
  || fail "strict abort must happen before any backup or app modification"

# 双拼入口依赖千问把原始字母逐键交给 Rime；兼容引擎不可用时必须在
# 备份和修改文件前中止，不能部署一个完全无法输入的 qw_double。
set +e
run_sync sync >"$TMP_ROOT/degraded.log" 2>&1
DEGRADED_RC=$?
set -e
[[ "$DEGRADED_RC" -ne 0 ]] || fail "double-pinyin overlay must abort without key-event compatibility"
assert_contains "$TMP_ROOT/degraded.log" "双拼覆盖需要逐键兼容引擎"
assert_contains "$APP/Contents/Frameworks/libqime.dylib" "new-engine-459"
assert_not_contains "$SCHEMAS/lua/xmjd6/example.lua" "abi=true"
[[ -z "$(find "$BACKUPS" -maxdepth 1 -type d -name 'qime-pre-sync-1.2.3-459-*')" ]] \
  || fail "unsupported double-pinyin overlay must abort before backup"
assert_contains "$STATE/last-sync.env" "app_build=458"

unset NM_MISSING_ABI

printf 'PASS: qianwen rime sync\n'
