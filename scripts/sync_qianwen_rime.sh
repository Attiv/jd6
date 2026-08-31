#!/bin/bash
set -euo pipefail

# 将 ~/Library/Rime 中的星猫键道部署并覆盖千问双拼（保留千问全拼）。
# 默认不覆盖千问自己的 candidate_order.txt / dynamic_phrases.txt。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

original_user="${SUDO_USER:-${USER:-mac}}"
default_home="${HOME:-/Users/$original_user}"
if [[ -n "${SUDO_USER:-}" ]] && command -v dscl >/dev/null 2>&1; then
  detected_home="$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}' || true)"
  [[ -n "$detected_home" ]] && default_home="$detected_home"
fi

QW_APP="${QW_APP:-/Library/Input Methods/QianwenIME.app}"
RIME_DIR="${RIME_DIR:-$default_home/Library/Rime}"
QW_USER_DIR="${QW_USER_DIR:-$default_home/Library/Application Support/QianwenIME/Qime}"
BACKUP_ROOT="${BACKUP_ROOT:-$default_home/Library/Application Support/QianwenIME/Backups/RimeSync}"
STATE_DIR="${STATE_DIR:-$default_home/Library/Application Support/QianwenIME/RimeSync}"
RIME_DEPLOYER="${RIME_DEPLOYER:-/Library/Input Methods/Squirrel.app/Contents/MacOS/rime_deployer}"
QW_RELAUNCHER="${QW_RELAUNCHER:-$QW_APP/Contents/Helpers/QianwenIMERelaunch}"
QW_ATOMIC_SWAPPER="${QW_ATOMIC_SWAPPER:-$QW_APP/Contents/Helpers/QianwenIMEAtomicSwap}"
QW_LAUNCHCTL="${QW_LAUNCHCTL:-$(command -v launchctl || true)}"
COMPAT_FILE="${QIME_COMPAT_FILE:-$SCRIPT_DIR/qianwen_overlay/qime_trigger_compat.lua}"
PYTHON3="${PYTHON3:-$(command -v python3 || true)}"
QW_COMPAT_LIBQIME="${QW_COMPAT_LIBQIME:-$STATE_DIR/compat/libqime-key-semantics.dylib}"
QW_SKIP_ENGINE_ABI_CHECK="${QW_SKIP_ENGINE_ABI_CHECK:-0}"
QW_DISABLE_ENGINE_COMPAT="${QW_DISABLE_ENGINE_COMPAT:-0}"
QW_ENGINE_COMPAT_STRICT="${QW_ENGINE_COMPAT_STRICT:-0}"
QW_ENGINE_COMPAT_ANNOUNCED="${QW_ENGINE_COMPAT_ANNOUNCED:-0}"
QW_IN_ATOMIC_STAGE="${QW_IN_ATOMIC_STAGE:-0}"
QW_FORCE_ATOMIC_STAGE="${QW_FORCE_ATOMIC_STAGE:-0}"

# 按键语义兼容引擎的处置结果：install / skip。
ENGINE_COMPAT_DECISION="skip"
ENGINE_COMPAT_STATUS="unknown"
ENGINE_COMPAT_REASON=""
ENGINE_COMPAT_MISSING_FILE=""
ENGINE_COMPAT_HASH=""

QW_DATA="$QW_APP/Contents/SharedSupport/qw_ime_data"
QW_SCHEMAS="$QW_DATA/schemas"
QW_BUILD="$QW_DATA/rime_user/build"
QW_LIBQIME="$QW_APP/Contents/Frameworks/libqime.dylib"
QW_ENGINE_WRAPPER="$QW_APP/Contents/Frameworks/libqianwen_engine.dylib"
PLIST="$QW_APP/Contents/Info.plist"

WITH_RUNTIME=0
NO_RELOAD=0
WORK_DIR=""

log() {
  printf '[千问 Rime] %s\n' "$*"
}

die() {
  printf '[千问 Rime] 错误：%s\n' "$*" >&2
  exit 1
}

warn() {
  printf '[千问 Rime] 警告：%s\n' "$*" >&2
}

usage() {
  cat <<'EOF'
用法：
  sync_qianwen_rime.sh sync [--with-runtime] [--no-reload]
  sync_qianwen_rime.sh status

命令：
  sync             部署 ~/Library/Rime，备份并同步到千问，然后用官方 helper 重载
  status           检查千问更新后是否需要重新同步

选项：
  --with-runtime   同时用 Rime 目录里的 candidate_order.txt 和
                   dynamic_phrases.txt 覆盖千问运行数据；默认保留千问自己的数据
  --no-reload      只安装文件，不重载千问

可用环境变量：
  QW_APP, RIME_DIR, QW_USER_DIR, BACKUP_ROOT, STATE_DIR,
  RIME_DEPLOYER, QW_RELAUNCHER, QW_COMPAT_LIBQIME
  QW_DISABLE_ENGINE_COMPAT=1   完全不使用按键语义兼容引擎，也不再提示
  QW_ENGINE_COMPAT_STRICT=1    兼容引擎不可用时直接中止（默认降级继续同步）
EOF
}

cleanup() {
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

plist_value() {
  local key="$1"
  if [[ -f "$PLIST" ]]; then
    /usr/bin/plutil -extract "$key" raw "$PLIST" 2>/dev/null || true
  fi
}

sha256_file() {
  /usr/bin/shasum -a 256 "$1" | awk '{print $1}'
}

app_cdhash() {
  local value=""
  if command -v codesign >/dev/null 2>&1 && [[ -d "$QW_APP" ]]; then
    value="$(codesign -dv --verbose=4 "$QW_APP" 2>&1 \
      | awk -F= '/^CDHash=/{print $2; exit}' || true)"
  fi
  if [[ -z "$value" && -f "$PLIST" ]]; then
    value="$(sha256_file "$PLIST")"
  fi
  printf '%s\n' "${value:-unknown}"
}

safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

current_app_metadata() {
  APP_VERSION="$(plist_value CFBundleShortVersionString)"
  APP_BUILD="$(plist_value CFBundleVersion)"
  APP_VERSION="${APP_VERSION:-unknown}"
  APP_BUILD="${APP_BUILD:-unknown}"
  APP_IDENTITY="$(app_cdhash)"
}

state_value() {
  local key="$1"
  local file="$STATE_DIR/last-sync.env"
  [[ -f "$file" ]] || return 0
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "$file"
}

validate_common() {
  [[ -d "$QW_APP" ]] || die "找不到千问输入法：$QW_APP"
  [[ -f "$PLIST" ]] || die "找不到千问 Info.plist：$PLIST"
  [[ -d "$QW_DATA" ]] || die "找不到千问 Rime 数据目录：$QW_DATA"
  [[ -d "$QW_SCHEMAS" ]] || die "找不到千问 schemas：$QW_SCHEMAS"
  [[ -d "$QW_BUILD" ]] || die "找不到千问 build：$QW_BUILD"
}

validate_source_inputs() {
  validate_common
  [[ -d "$RIME_DIR" ]] || die "找不到 Rime 目录：$RIME_DIR"
  [[ -f "$RIME_DIR/xmjd6.schema.yaml" ]] \
    || die "缺少 $RIME_DIR/xmjd6.schema.yaml"
  [[ -x "$RIME_DEPLOYER" ]] || die "找不到可执行的 rime_deployer：$RIME_DEPLOYER"
  [[ -f "$COMPAT_FILE" ]] || die "缺少千问兼容层：$COMPAT_FILE"
  [[ -n "$PYTHON3" && -x "$PYTHON3" ]] || die "需要 python3 来安全生成 qw_double.schema.yaml"
}

validate_sync_inputs() {
  validate_source_inputs
  [[ -w "$QW_DATA" ]] \
    || die "千问目录不可写，且原子暂存部署未生效：$QW_DATA"
  if [[ "$ENGINE_COMPAT_DECISION" == "install" ]]; then
    [[ -w "$QW_LIBQIME" ]] \
      || die "千问 libqime 不可写，且原子暂存部署未生效：$QW_LIBQIME"
  fi
}

probe_writable_dir() {
  local directory="$1"
  local probe="$directory/.qime-write-probe.$$.$RANDOM"
  if ( umask 077; : >"$probe" ) 2>/dev/null; then
    /bin/rm -f "$probe"
    return 0
  fi
  return 1
}

app_can_be_modified_directly() {
  probe_writable_dir "$QW_DATA" || return 1
  if [[ "$ENGINE_COMPAT_DECISION" == "install" ]]; then
    probe_writable_dir "$(dirname "$QW_LIBQIME")" || return 1
  fi
}

copy_file_atomic() {
  local source="$1"
  local target="$2"
  local temporary
  mkdir -p "$(dirname "$target")"
  temporary="${target}.qime-sync.$$"
  /bin/cp -p "$source" "$temporary"
  /bin/mv -f "$temporary" "$target"
}

clone_tree() {
  local source="$1"
  local target="$2"
  mkdir -p "$(dirname "$target")"
  if /bin/cp -cR "$source" "$target" 2>/dev/null; then
    return 0
  fi
  /usr/bin/rsync -a "$source/" "$target/"
}

copy_source_for_deploy() {
  local target="$1"
  local file pattern
  mkdir -p "$target"
  shopt -s nullglob

  if [[ -f "$RIME_DIR/default.yaml" ]]; then
    /bin/cp -p "$RIME_DIR/default.yaml" "$target/default.yaml"
  elif [[ -f "$RIME_DIR/trash/default.yaml" ]]; then
    /bin/cp -p "$RIME_DIR/trash/default.yaml" "$target/default.yaml"
  else
    cat >"$target/default.yaml" <<'YAML'
schema_list:
  - schema: xmjd6
YAML
  fi

  for pattern in \
    'xmjd6*.yaml' 'xkjd6*.yaml' \
    'pinyin_simp*.yaml' 'liangfen*.yaml' 'english*.yaml' \
    'symbols.yaml' 'default.custom.yaml'
  do
    for file in "$RIME_DIR"/$pattern; do
      [[ -f "$file" ]] && /bin/cp -p "$file" "$target/"
    done
  done

  [[ -d "$RIME_DIR/opencc" ]] \
    && /usr/bin/rsync -a --exclude='.DS_Store' "$RIME_DIR/opencc/" "$target/opencc/"
  [[ -d "$RIME_DIR/lua" ]] \
    && /usr/bin/rsync -a --exclude='.DS_Store' "$RIME_DIR/lua/" "$target/lua/"
  shopt -u nullglob
}

deploy_to_staging() {
  local user_stage="$WORK_DIR/user"
  local build_stage="$WORK_DIR/build"
  local deploy_log="$WORK_DIR/rime-deployer.log"

  copy_source_for_deploy "$user_stage"
  mkdir -p "$build_stage"
  log "部署星猫键道到临时目录（不会改动原 Rime/build）……"
  # shared_data_dir 也指向隔离后的星猫目录，避免 Squirrel 自带的
  # default/key_bindings/punctuation 预设悄悄改变部署结果。
  if ! "$RIME_DEPLOYER" --build "$user_stage" "$user_stage" "$build_stage" \
      >"$deploy_log" 2>&1; then
    cat "$deploy_log" >&2
    die "Rime 部署失败；尚未修改千问文件"
  fi

  local required
  for required in \
    xmjd6.schema.yaml \
    xmjd6.extended.prism.bin \
    xmjd6.extended.reverse.bin \
    xmjd6.extended.table.bin
  do
    [[ -f "$build_stage/$required" ]] \
      || die "部署结果缺少 ${required}；尚未修改千问文件"
  done

  mkdir -p "$STATE_DIR/logs"
  /bin/cp -p "$deploy_log" "$STATE_DIR/logs/rime-deployer-latest.log"
}

make_qw_double_schema() {
  local source="$1"
  local target="$2"
  local temporary="$WORK_DIR/$(basename "$target").$RANDOM"

  "$PYTHON3" - "$source" "$temporary" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_bytes().decode("utf-8-sig")

text, schema_count = re.subn(
    r"^(\s*schema_id:\s*)xmjd6(\s*(?:#.*)?)$",
    r"\1qw_double\2",
    text,
    count=1,
    flags=re.MULTILINE,
)
if schema_count != 1 and not re.search(r"^\s*schema_id:\s*qw_double\s*$", text, re.MULTILINE):
    raise SystemExit("cannot locate schema_id: xmjd6")

text = re.sub(
    r"^(\s*dictionary:\s*)xmjd6\.extended(\s*(?:#.*)?)$",
    r"\1qw_double\2",
    text,
    flags=re.MULTILINE,
)
if len(re.findall(r"^\s*dictionary:\s*qw_double(?:\s*(?:#.*)?)?$", text, re.MULTILINE)) < 2:
    raise SystemExit("expected translator and sentence_mode dictionaries")

compat = "    - lua_processor@*xmjd6/qime_trigger_compat"
lines = [line for line in text.splitlines() if "lua_processor@*xmjd6/qime_trigger_compat" not in line]
insert_at = None
inside_engine = False
for index, line in enumerate(lines):
    if re.match(r"^engine:\s*(?:#.*)?$", line):
        inside_engine = True
        continue
    if inside_engine and re.match(r"^\S", line):
        inside_engine = False
    if inside_engine and re.match(r"^\s{2}processors:\s*(?:#.*)?$", line):
        insert_at = index + 1
        break
if insert_at is None:
    raise SystemExit("cannot locate engine/processors")
lines.insert(insert_at, compat)

result = "\n".join(lines) + ("\n" if text.endswith("\n") else "")
if result.count("lua_processor@*xmjd6/qime_trigger_compat") != 1:
    raise SystemExit("compat processor insertion is not idempotent")
target.write_text(result, encoding="utf-8")
PY
  copy_file_atomic "$temporary" "$target"
}

create_versioned_backup() {
  local version_safe build_safe identity_short backup_dir partial
  version_safe="$(safe_name "$APP_VERSION")"
  build_safe="$(safe_name "$APP_BUILD")"
  identity_short="$(safe_name "${APP_IDENTITY:0:12}")"
  backup_dir="$BACKUP_ROOT/qime-pre-sync-${version_safe}-${build_safe}-${identity_short}"

  if [[ -d "$backup_dir" ]]; then
    if [[ -f "$QW_LIBQIME" && ! -f "$backup_dir/Frameworks/libqime.dylib" ]]; then
      mkdir -p "$backup_dir/Frameworks"
      copy_file_atomic "$QW_LIBQIME" "$backup_dir/Frameworks/libqime.dylib"
    fi
    log "本版本已有同步前备份：$backup_dir"
    LAST_BACKUP="$backup_dir"
    return 0
  fi

  mkdir -p "$BACKUP_ROOT"
  partial="${backup_dir}.partial.$$"
  log "备份当前千问数据：$backup_dir"
  mkdir -p "$partial"
  clone_tree "$QW_DATA" "$partial/qw_ime_data"
  if [[ -f "$QW_LIBQIME" ]]; then
    mkdir -p "$partial/Frameworks"
    copy_file_atomic "$QW_LIBQIME" "$partial/Frameworks/libqime.dylib"
  fi
  if [[ -d "$QW_USER_DIR" ]]; then
    clone_tree "$QW_USER_DIR" "$partial/Qime"
  fi
  {
    printf 'app_version=%s\n' "$APP_VERSION"
    printf 'app_build=%s\n' "$APP_BUILD"
    printf 'app_identity=%s\n' "$APP_IDENTITY"
    printf 'created_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
  } >"$partial/metadata.env"
  /bin/mv "$partial" "$backup_dir"
  LAST_BACKUP="$backup_dir"
}

codesign_team_id() {
  local target="$1"
  if command -v codesign >/dev/null 2>&1; then
    codesign -dv --verbose=4 "$target" 2>&1 \
      | awk -F= '/^TeamIdentifier=/{print $2; exit}' || true
  fi
}

engine_compat_is_usable() {
  ENGINE_COMPAT_REASON=""
  ENGINE_COMPAT_MISSING_FILE=""
  [[ "$QW_SKIP_ENGINE_ABI_CHECK" -eq 1 ]] && return 0

  if command -v codesign >/dev/null 2>&1; then
    if ! codesign --verify --strict "$QW_COMPAT_LIBQIME" 2>/dev/null; then
      ENGINE_COMPAT_REASON="兼容 libqime 自身签名无效：$QW_COMPAT_LIBQIME"
      return 1
    fi
    local app_team compat_team
    app_team="$(codesign_team_id "$QW_APP")"
    compat_team="$(codesign_team_id "$QW_COMPAT_LIBQIME")"
    if [[ -n "$app_team" && -n "$compat_team" && "$app_team" != "$compat_team" ]]; then
      ENGINE_COMPAT_REASON="兼容 libqime 与千问 Team ID 不一致：$compat_team != $app_team"
      return 1
    fi
  fi

  if command -v lipo >/dev/null 2>&1; then
    if ! lipo "$QW_COMPAT_LIBQIME" -verify_arch "$(uname -m)" >/dev/null 2>&1; then
      ENGINE_COMPAT_REASON="兼容 libqime 不包含当前架构：$(uname -m)"
      return 1
    fi
  fi

  if command -v nm >/dev/null 2>&1; then
    local imports="$WORK_DIR/libqime.imports"
    local exports="$WORK_DIR/libqime.exports"
    local missing="$WORK_DIR/libqime.missing"
    nm -u "$QW_ENGINE_WRAPPER" 2>/dev/null \
      | grep -E '^__Z.*4qime' | LC_ALL=C sort -u >"$imports" || true
    nm -gU "$QW_COMPAT_LIBQIME" 2>/dev/null \
      | awk '{print $3}' | LC_ALL=C sort -u >"$exports"
    LC_ALL=C comm -23 "$imports" "$exports" >"$missing"
    if [[ -s "$missing" ]]; then
      ENGINE_COMPAT_MISSING_FILE="$missing"
      ENGINE_COMPAT_REASON="千问新版引擎包装层需要 $(wc -l <"$missing" | tr -d ' ') 个兼容 libqime 中不存在的 ABI 符号"
      return 1
    fi
  fi
}

# 在改动任何千问文件之前决定兼容引擎的去留：可用就装，不可用则默认降级，
# 只跳过 libqime 替换，星猫键道数据照常同步（QW_ENGINE_COMPAT_STRICT=1 时中止）。
decide_engine_compat() {
  ENGINE_COMPAT_DECISION="skip"
  ENGINE_COMPAT_REASON=""
  local announce=1
  [[ "$QW_ENGINE_COMPAT_ANNOUNCED" -eq 1 ]] && announce=0

  if [[ "$QW_DISABLE_ENGINE_COMPAT" -eq 1 ]]; then
    ENGINE_COMPAT_STATUS="disabled"
    [[ "$announce" -eq 1 ]] \
      && log "已通过 QW_DISABLE_ENGINE_COMPAT 跳过按键语义兼容引擎"
    return 0
  fi
  if [[ ! -f "$QW_COMPAT_LIBQIME" ]]; then
    ENGINE_COMPAT_STATUS="absent"
    [[ "$announce" -eq 1 ]] \
      && log "未找到按键语义兼容引擎，跳过：$QW_COMPAT_LIBQIME"
    return 0
  fi
  [[ -f "$QW_LIBQIME" ]] || die "找不到千问 libqime：$QW_LIBQIME"
  [[ -f "$QW_ENGINE_WRAPPER" ]] || die "找不到千问引擎包装层：$QW_ENGINE_WRAPPER"

  if engine_compat_is_usable; then
    ENGINE_COMPAT_DECISION="install"
    ENGINE_COMPAT_STATUS="installed"
    return 0
  fi

  ENGINE_COMPAT_STATUS="skipped"
  if [[ "$QW_ENGINE_COMPAT_STRICT" -eq 1 ]]; then
    if [[ -n "$ENGINE_COMPAT_MISSING_FILE" && -s "$ENGINE_COMPAT_MISSING_FILE" ]]; then
      cat "$ENGINE_COMPAT_MISSING_FILE" >&2
    fi
    die "${ENGINE_COMPAT_REASON}；已按 QW_ENGINE_COMPAT_STRICT=1 停止，未修改千问文件"
  fi
  if [[ "$announce" -eq 1 ]]; then
    if [[ -n "$ENGINE_COMPAT_MISSING_FILE" && -s "$ENGINE_COMPAT_MISSING_FILE" ]]; then
      cat "$ENGINE_COMPAT_MISSING_FILE" >&2
    fi
    warn "$ENGINE_COMPAT_REASON"
    warn "兼容 libqime 是旧版千问的厂商签名原件，无法为新版重建，本次保留千问自带引擎"
    warn "星猫键道方案、词库、Lua 与 OpenCC 仍会照常同步"
    warn "若顶功或 Lua 引导键因此失效，请回退到可用的旧版千问；确认不再需要可设 QW_DISABLE_ENGINE_COMPAT=1 消除此提示"
  fi
  return 0
}

install_engine_compat() {
  ENGINE_COMPAT_HASH=""
  [[ "$ENGINE_COMPAT_DECISION" == "install" ]] || return 0

  ENGINE_COMPAT_HASH="$(sha256_file "$QW_COMPAT_LIBQIME")"
  if [[ "$(sha256_file "$QW_LIBQIME")" == "$ENGINE_COMPAT_HASH" ]]; then
    log "按键语义兼容引擎已经安装"
    return 0
  fi

  log "安装兼容 libqime，恢复逐键处理、顶功和 Lua 引导键……"
  copy_file_atomic "$QW_COMPAT_LIBQIME" "$QW_LIBQIME"
  if [[ "$QW_SKIP_ENGINE_ABI_CHECK" -ne 1 ]] && command -v codesign >/dev/null 2>&1; then
    codesign --verify --strict "$QW_LIBQIME" 2>/dev/null \
      || die "安装后的兼容 libqime 签名验证失败"
  fi
}

copy_source_overlay() {
  local file pattern base
  shopt -s nullglob
  mkdir -p "$QW_SCHEMAS/lua" "$QW_SCHEMAS/opencc"

  for pattern in \
    'xmjd6*.yaml' 'xkjd6*.yaml' \
    'pinyin_simp*.yaml' 'liangfen*.yaml' 'english*.yaml' \
    'symbols.yaml' 'anniversaries.txt'
  do
    for file in "$RIME_DIR"/$pattern; do
      [[ -f "$file" ]] || continue
      base="$(basename "$file")"
      copy_file_atomic "$file" "$QW_SCHEMAS/$base"
    done
  done

  if [[ -d "$RIME_DIR/lua/xmjd6" ]]; then
    mkdir -p "$QW_SCHEMAS/lua/xmjd6"
    # App Management may allow file writes while denying directory mode/time
    # changes. Copy content only; -a would fail on those protected directories.
    /usr/bin/rsync -r --delete --exclude='.DS_Store' \
      "$RIME_DIR/lua/xmjd6/" "$QW_SCHEMAS/lua/xmjd6/"
  fi
  if [[ -d "$RIME_DIR/lua/eng" ]]; then
    mkdir -p "$QW_SCHEMAS/lua/eng"
    /usr/bin/rsync -r --delete --exclude='.DS_Store' \
      "$RIME_DIR/lua/eng/" "$QW_SCHEMAS/lua/eng/"
  fi
  if [[ -d "$RIME_DIR/opencc" ]]; then
    /usr/bin/rsync -r --exclude='.DS_Store' \
      "$RIME_DIR/opencc/" "$QW_SCHEMAS/opencc/"
  fi

  copy_file_atomic "$COMPAT_FILE" "$QW_SCHEMAS/lua/xmjd6/qime_trigger_compat.lua"
  shopt -u nullglob
}

copy_build_overlay() {
  local file base
  shopt -s nullglob
  for file in \
    "$WORK_DIR/build"/xmjd6*.bin \
    "$WORK_DIR/build"/xmjd6*.schema.yaml \
    "$WORK_DIR/build"/pinyin_simp*.bin \
    "$WORK_DIR/build"/pinyin_simp*.schema.yaml \
    "$WORK_DIR/build"/liangfen*.bin \
    "$WORK_DIR/build"/liangfen*.schema.yaml \
    "$WORK_DIR/build"/english*.bin \
    "$WORK_DIR/build"/english*.schema.yaml
  do
    [[ -f "$file" ]] || continue
    base="$(basename "$file")"
    copy_file_atomic "$file" "$QW_BUILD/$base"
  done

  for base in prism.bin reverse.bin table.bin; do
    copy_file_atomic \
      "$WORK_DIR/build/xmjd6.extended.$base" \
      "$QW_BUILD/qw_double.$base"
  done
  shopt -u nullglob
}

copy_qime_support_files() {
  local file
  mkdir -p "$QW_USER_DIR"
  for file in xmjd6.cx.dict.yaml xmjd6.fuhao.dict.yaml anniversaries.txt; do
    if [[ -f "$RIME_DIR/$file" ]]; then
      copy_file_atomic "$RIME_DIR/$file" "$QW_USER_DIR/$file"
    fi
  done

  if [[ "$WITH_RUNTIME" -eq 1 ]]; then
    for file in candidate_order.txt dynamic_phrases.txt; do
      if [[ -f "$RIME_DIR/$file" ]]; then
        copy_file_atomic "$RIME_DIR/$file" "$QW_USER_DIR/$file"
      fi
    done
  fi
}

write_state() {
  local state_tmp source_hash
  mkdir -p "$STATE_DIR"
  state_tmp="$STATE_DIR/last-sync.env.tmp.$$"
  source_hash="$(sha256_file "$RIME_DIR/xmjd6.schema.yaml")"
  {
    printf 'app_version=%s\n' "$APP_VERSION"
    printf 'app_build=%s\n' "$APP_BUILD"
    printf 'app_identity=%s\n' "$APP_IDENTITY"
    printf 'source_schema_sha256=%s\n' "$source_hash"
    printf 'engine_compat_sha256=%s\n' "${ENGINE_COMPAT_HASH:-}"
    printf 'engine_compat_status=%s\n' "${ENGINE_COMPAT_STATUS:-unknown}"
    printf 'backup=%s\n' "$LAST_BACKUP"
    printf 'synced_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
  } >"$state_tmp"
  /bin/mv -f "$state_tmp" "$STATE_DIR/last-sync.env"
}

run_status() {
  validate_common
  current_app_metadata
  local old_version old_build old_identity schema="$QW_SCHEMAS/qw_double.schema.yaml"
  old_version="$(state_value app_version)"
  old_build="$(state_value app_build)"
  old_identity="$(state_value app_identity)"

  if [[ -z "$old_version" ]]; then
    log "尚未记录同步状态，请运行：\"$0\" sync"
    return 10
  fi

  if [[ "$old_version" != "$APP_VERSION" || "$old_build" != "$APP_BUILD" \
        || "$old_identity" != "$APP_IDENTITY" ]]; then
    log "检测到千问更新：已同步 $old_version ($old_build)，当前 $APP_VERSION ($APP_BUILD)"
    log "请重新运行：\"$0\" sync"
    return 10
  fi

  if [[ ! -f "$schema" ]] \
      || ! grep -Fq 'schema_id: qw_double' "$schema" \
      || ! grep -Fq 'lua_processor@*xmjd6/qime_trigger_compat' "$schema" \
      || [[ ! -f "$QW_SCHEMAS/lua/xmjd6/qime_trigger_compat.lua" ]] \
      || ! grep -Fq 'utf8.char(0x200B)' \
          "$QW_SCHEMAS/lua/xmjd6/qime_trigger_compat.lua"; then
    log "千问中的星猫键道覆盖层缺失或已被替换，请重新运行 sync"
    return 10
  fi

  local engine_status engine_note=""
  engine_status="$(state_value engine_compat_status)"
  if [[ -z "$engine_status" ]]; then
    # 旧状态文件没有该字段：有哈希即代表当时装过兼容引擎。
    if [[ -n "$(state_value engine_compat_sha256)" ]]; then
      engine_status="installed"
    else
      engine_status="skipped"
    fi
  fi

  if [[ "$engine_status" == "installed" ]]; then
    local wanted_engine current_engine
    wanted_engine="$(state_value engine_compat_sha256)"
    current_engine="$(sha256_file "$QW_LIBQIME")"
    if [[ -n "$wanted_engine" && "$wanted_engine" != "$current_engine" ]]; then
      log "千问更新覆盖了逐键兼容引擎，顶功和 Lua 引导键会失效，请重新运行 sync"
      return 10
    fi
    engine_note="逐键兼容层存在"
  else
    engine_note="按键语义兼容引擎未启用（${engine_status}），使用千问自带引擎"
  fi

  log "已同步：千问 $APP_VERSION ($APP_BUILD)，星猫键道就绪；$engine_note"
}

atomic_exchange_contents() {
  local current_contents="$1"
  local next_contents="$2"
  local stage_root="$3"
  local uid domain label plist stdout_file stderr_file success=0

  [[ -x "$QW_ATOMIC_SWAPPER" ]] \
    || die "找不到千问官方原子替换 helper：$QW_ATOMIC_SWAPPER"
  [[ -n "$QW_LAUNCHCTL" && -x "$QW_LAUNCHCTL" ]] \
    || die "找不到 launchctl，无法通过 App Management 保护"

  uid="$(id -u "$original_user")"
  domain="gui/$uid"
  label="com.local.qime-sync.$(date +%s).$$.$RANDOM"
  plist="$stage_root/$label.plist"
  stdout_file="$stage_root/$label.out"
  stderr_file="$stage_root/$label.err"

  "$PYTHON3" - "$plist" "$label" "$QW_ATOMIC_SWAPPER" \
      "$current_contents" "$next_contents" "$stdout_file" "$stderr_file" <<'PY'
import plistlib
import sys

plist, label, helper, current, next_path, stdout_path, stderr_path = sys.argv[1:]
payload = {
    "Label": label,
    "ProgramArguments": [
        helper, "--current", current, "--next", next_path,
    ],
    "RunAtLoad": True,
    "KeepAlive": False,
    "StandardOutPath": stdout_path,
    "StandardErrorPath": stderr_path,
}
with open(plist, "wb") as stream:
    plistlib.dump(payload, stream)
PY

  # 由 launchd 直接启动厂商签名 helper，使 macOS App Management 将替换
  # 归因给千问自身；KeepAlive=false 保证 Contents 只交换一次。
  "$QW_LAUNCHCTL" bootstrap "$domain" "$plist" \
    || die "无法加载一次性原子替换任务"

  local attempt
  for attempt in $(seq 1 100); do
    if [[ -f "$stdout_file" ]] \
        && grep -Fq 'atomic swap succeeded' "$stdout_file"; then
      success=1
      break
    fi
    if [[ -f "$stderr_file" ]] \
        && grep -Fq 'atomic swap failed' "$stderr_file"; then
      break
    fi
    sleep 0.1
  done

  "$QW_LAUNCHCTL" bootout "$domain/$label" 2>/dev/null \
    || "$QW_LAUNCHCTL" bootout "$domain" "$plist" 2>/dev/null \
    || true

  if [[ "$success" -ne 1 ]]; then
    [[ -f "$stdout_file" ]] && cat "$stdout_file" >&2
    [[ -f "$stderr_file" ]] && cat "$stderr_file" >&2
    die "千问 Contents 原子替换失败"
  fi

  local success_count
  success_count="$(grep -Fc 'atomic swap succeeded' "$stdout_file" || true)"
  [[ "$success_count" -eq 1 ]] \
    || die "原子替换任务执行次数异常：$success_count"
}

run_sync_via_atomic_stage() {
  local stage_root stage_app expected_engine expected_compat recursive_args

  [[ "$QW_IN_ATOMIC_STAGE" -ne 1 ]] \
    || die "原子暂存目录仍不可写，已停止以避免递归"
  [[ -x "$QW_ATOMIC_SWAPPER" ]] \
    || die "当前版本缺少官方原子替换 helper：$QW_ATOMIC_SWAPPER"

  mkdir -p "$STATE_DIR"
  stage_root="$(mktemp -d "$STATE_DIR/AtomicStage-$(date +%Y%m%d-%H%M%S).XXXXXX")"
  stage_app="$stage_root/QianwenIME.app"
  log "macOS App Management 阻止直接修改，改用完整 App 暂存与一次性原子替换……"

  if ! /bin/cp -cR "$QW_APP" "$stage_app" 2>/dev/null; then
    /usr/bin/ditto --norsrc --noextattr "$QW_APP" "$stage_app"
  fi
  /usr/bin/xattr -d com.apple.macl "$stage_app" 2>/dev/null || true
  /bin/chmod -R u+rwX "$stage_app"

  recursive_args=(sync --no-reload)
  [[ "$WITH_RUNTIME" -eq 1 ]] && recursive_args+=(--with-runtime)

  QW_IN_ATOMIC_STAGE=1 \
  QW_FORCE_ATOMIC_STAGE=0 \
  QW_APP="$stage_app" \
  RIME_DIR="$RIME_DIR" \
  QW_USER_DIR="$QW_USER_DIR" \
  BACKUP_ROOT="$BACKUP_ROOT" \
  STATE_DIR="$STATE_DIR" \
  RIME_DEPLOYER="$RIME_DEPLOYER" \
  QW_RELAUNCHER="$QW_RELAUNCHER" \
  QW_ATOMIC_SWAPPER="$QW_ATOMIC_SWAPPER" \
  QW_LAUNCHCTL="$QW_LAUNCHCTL" \
  QIME_COMPAT_FILE="$COMPAT_FILE" \
  QW_COMPAT_LIBQIME="$QW_COMPAT_LIBQIME" \
  QW_SKIP_ENGINE_ABI_CHECK="$QW_SKIP_ENGINE_ABI_CHECK" \
  QW_DISABLE_ENGINE_COMPAT="$QW_DISABLE_ENGINE_COMPAT" \
  QW_ENGINE_COMPAT_STRICT="$QW_ENGINE_COMPAT_STRICT" \
  QW_ENGINE_COMPAT_ANNOUNCED=1 \
  PYTHON3="$PYTHON3" \
    "$SCRIPT_DIR/$(basename "$0")" "${recursive_args[@]}"

  expected_compat="$(sha256_file \
    "$stage_app/Contents/SharedSupport/qw_ime_data/schemas/lua/xmjd6/qime_trigger_compat.lua")"
  expected_engine=""
  if [[ -f "$stage_app/Contents/Frameworks/libqime.dylib" ]]; then
    expected_engine="$(sha256_file "$stage_app/Contents/Frameworks/libqime.dylib")"
  fi

  atomic_exchange_contents \
    "$QW_APP/Contents" "$stage_app/Contents" "$stage_root"

  [[ "$(sha256_file \
      "$QW_APP/Contents/SharedSupport/qw_ime_data/schemas/lua/xmjd6/qime_trigger_compat.lua")" \
      == "$expected_compat" ]] \
    || die "原子替换后 Lua 兼容层校验失败"
  if [[ -n "$expected_engine" ]]; then
    [[ "$(sha256_file "$QW_APP/Contents/Frameworks/libqime.dylib")" \
        == "$expected_engine" ]] \
      || die "原子替换后 libqime 校验失败"
  fi

  if [[ "$NO_RELOAD" -eq 0 ]]; then
    [[ -x "$QW_RELAUNCHER" ]] || die "找不到官方重载 helper：$QW_RELAUNCHER"
    log "使用千问官方 helper 重载输入法……"
    "$QW_RELAUNCHER" --host-bundle-path "$QW_APP"
  else
    log "已跳过重载（--no-reload）"
  fi

  if [[ "$ENGINE_COMPAT_DECISION" == "install" ]]; then
    log "原子暂存同步完成；更新后的顶功、Lua 引导键和单符号显示已恢复"
  else
    log "原子暂存同步完成；本次未替换 libqime，使用千问自带引擎"
  fi
  log "完整回退副本：$stage_app"
}

run_sync() {
  validate_source_inputs
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/qime-sync.XXXXXX")"

  # 先判定兼容引擎，再决定是否需要原子暂存：跳过引擎替换时不必为了
  # libqime 的写权限而整包暂存。
  decide_engine_compat

  # 千问 1.2.x 的双拼层会先接管字母，再通过 InputText 整串送入 Rime。
  # 没有逐键兼容引擎时，键道拿不到原始编码，覆盖 qw_double 会导致无候选。
  # 必须在备份或修改 App 之前中止，避免再次把输入法部署成不可输入状态。
  if [[ "$ENGINE_COMPAT_DECISION" != "install" ]]; then
    die "双拼覆盖需要逐键兼容引擎；当前千问版本不兼容，已停止且未修改 App"
  fi

  if [[ "$QW_IN_ATOMIC_STAGE" -ne 1 ]] \
      && { [[ "$QW_FORCE_ATOMIC_STAGE" -eq 1 ]] \
           || ! app_can_be_modified_directly; }; then
    run_sync_via_atomic_stage
    return
  fi

  validate_sync_inputs
  current_app_metadata

  deploy_to_staging

  # 在确认部署产物完整后才备份和修改 App。
  create_versioned_backup

  log "同步星猫键道源码、Lua 与 OpenCC……"
  copy_source_overlay
  copy_build_overlay

  # 只覆盖千问双拼；千问全拼的 qw schema 和编译产物保持厂商原样。
  make_qw_double_schema "$RIME_DIR/xmjd6.schema.yaml" "$QW_SCHEMAS/qw_double.schema.yaml"
  make_qw_double_schema "$WORK_DIR/build/xmjd6.schema.yaml" "$QW_BUILD/qw_double.schema.yaml"
  copy_qime_support_files
  install_engine_compat

  if [[ "$NO_RELOAD" -eq 0 ]]; then
    [[ -x "$QW_RELAUNCHER" ]] || die "找不到官方重载 helper：$QW_RELAUNCHER"
    log "使用千问官方 helper 重载输入法……"
    "$QW_RELAUNCHER" --host-bundle-path "$QW_APP"
  else
    log "已跳过重载（--no-reload）"
  fi

  write_state
  log "同步完成：千问 $APP_VERSION ($APP_BUILD)"
  log "备份：$LAST_BACKUP"
  if [[ "$WITH_RUNTIME" -eq 0 ]]; then
    log "已保留千问自己的 candidate_order.txt 和 dynamic_phrases.txt"
  fi
}

COMMAND="${1:-sync}"
if [[ $# -gt 0 ]]; then shift; fi

case "$COMMAND" in
  sync)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --with-runtime) WITH_RUNTIME=1 ;;
        --no-reload) NO_RELOAD=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "未知参数：$1" ;;
      esac
      shift
    done
    run_sync
    ;;
  status)
    [[ $# -eq 0 ]] || die "status 不接受额外参数"
    run_status
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    die "未知命令：$COMMAND"
    ;;
esac
