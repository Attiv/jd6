#!/bin/bash
set -euo pipefail

# 用指定的千问 App 副本替换当前安装的千问，并可选禁用自动更新。
#
# 背景：千问 1.2.x 起不再把字母键交给 librime 的 processor 链（只转发控制键
# 和标点），因此星猫键道的顶功、= 引导键、0 调频等所有 lua_processor 功能都
# 失效，且无法在 Lua 或 schema 层修复。1.1.5.23 是已知最后一个逐键处理版本。
#
# 替换通过千问自带的、厂商签名的 QianwenIMEAtomicSwap helper 完成，由 launchd
# 直接拉起，使 macOS App Management 把这次改动归因给千问自身。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

original_user="${SUDO_USER:-${USER:-mac}}"
default_home="${HOME:-/Users/$original_user}"
if [[ -n "${SUDO_USER:-}" ]] && command -v dscl >/dev/null 2>&1; then
  detected_home="$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}' || true)"
  [[ -n "$detected_home" ]] && default_home="$detected_home"
fi

QW_APP="${QW_APP:-/Library/Input Methods/QianwenIME.app}"
BACKUP_ROOT="${BACKUP_ROOT:-$default_home/Library/Application Support/QianwenIME/Backups}"
STATE_DIR="${STATE_DIR:-$default_home/Library/Application Support/QianwenIME/RimeSync}"
QW_USER_DIR="${QW_USER_DIR:-$default_home/Library/Application Support/QianwenIME/Qime}"
DEFAULT_SOURCE="${DEFAULT_SOURCE:-$BACKUP_ROOT/QianwenIME-stock-20260724-191833.app}"
QW_ATOMIC_SWAPPER="${QW_ATOMIC_SWAPPER:-$QW_APP/Contents/Helpers/QianwenIMEAtomicSwap}"
QW_RELAUNCHER="${QW_RELAUNCHER:-$QW_APP/Contents/Helpers/QianwenIMERelaunch}"
QW_LAUNCHCTL="${QW_LAUNCHCTL:-$(command -v launchctl || true)}"
PYTHON3="${PYTHON3:-$(command -v python3 || true)}"

UPDATER_REL="Contents/Helpers/QianwenIMEUpdater"
DISABLE_UPDATER=1
SKIP_USER_BACKUP=0
ALLOW_MODIFIED_SOURCE=0
NO_RELOAD=0
STAGE_ROOT=""

log() {
  printf '[千问回退] %s\n' "$*"
}

die() {
  printf '[千问回退] 错误：%s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
用法：
  rollback_qianwen.sh install [<App 路径>] [--keep-updater] [--skip-user-backup] [--allow-modified-source] [--no-reload]
  rollback_qianwen.sh status

命令：
  install          用指定 App 副本替换当前千问；不给路径则用默认的 1.1.5.23 备份
  status           显示当前千问版本、可用备份和自动更新状态

选项：
  --keep-updater   保留 QianwenIMEUpdater（默认禁用，避免被自动升级覆盖）
  --skip-user-backup
                   不备份或改动 Qime 用户数据；用于只恢复 App 的固定快照
  --allow-modified-source
                   允许安装已由外部校验过的修改版 App 快照（默认要求厂商签名有效）
  --no-reload      替换后不重启千问

替换前会自动把当前版本整包克隆到 Backups/，随时可以用 install 装回去。
EOF
}

cleanup() {
  if [[ -n "$STAGE_ROOT" && -d "$STAGE_ROOT" ]]; then
    /bin/rm -rf "$STAGE_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT

plist_value() {
  local key="$1" plist="$2"
  [[ -f "$plist" ]] || return 0
  /usr/bin/plutil -extract "$key" raw "$plist" 2>/dev/null || true
}

app_version_string() {
  local app="$1" version build
  version="$(plist_value CFBundleShortVersionString "$app/Contents/Info.plist")"
  build="$(plist_value CFBundleVersion "$app/Contents/Info.plist")"
  printf '%s (%s)' "${version:-unknown}" "${build:-unknown}"
}

clone_tree() {
  local source="$1" target="$2"
  mkdir -p "$(dirname "$target")"
  if /bin/cp -cR "$source" "$target" 2>/dev/null; then
    return 0
  fi
  /usr/bin/ditto --norsrc --noextattr "$source" "$target"
}

validate_common() {
  [[ -d "$QW_APP" ]] || die "找不到千问输入法：$QW_APP"
  [[ -f "$QW_APP/Contents/Info.plist" ]] || die "千问 Info.plist 缺失"
}

run_status() {
  validate_common
  log "当前千问：$(app_version_string "$QW_APP")"
  if [[ -x "$QW_APP/$UPDATER_REL" ]]; then
    log "自动更新：启用（$UPDATER_REL 存在且可执行）"
  elif [[ -e "$QW_APP/$UPDATER_REL.disabled" ]]; then
    log "自动更新：已禁用（更新器已改名为 QianwenIMEUpdater.disabled）"
  else
    log "自动更新：更新器不存在"
  fi
  log "可用的整包备份："
  local app found=0
  shopt -s nullglob
  for app in "$BACKUP_ROOT"/*.app; do
    printf '  - %-22s %s\n' "$(app_version_string "$app")" "$app"
    found=1
  done
  shopt -u nullglob
  [[ "$found" -eq 1 ]] || printf '  （无）\n'
}

# 由 launchd 直接启动厂商签名 helper，使 macOS App Management 将替换归因给
# 千问自身；KeepAlive=false 保证 Contents 只交换一次。
atomic_exchange_contents() {
  local current_contents="$1" next_contents="$2" stage_root="$3"
  local uid domain label plist stdout_file stderr_file success=0 attempt

  [[ -x "$QW_ATOMIC_SWAPPER" ]] \
    || die "找不到千问官方原子替换 helper：$QW_ATOMIC_SWAPPER"
  [[ -n "$QW_LAUNCHCTL" && -x "$QW_LAUNCHCTL" ]] \
    || die "找不到 launchctl，无法通过 App Management 保护"
  [[ -n "$PYTHON3" && -x "$PYTHON3" ]] || die "需要 python3 生成 launchd 任务"

  uid="$(id -u "$original_user")"
  domain="gui/$uid"
  label="com.local.qime-rollback.$(date +%s).$$.$RANDOM"
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

  "$QW_LAUNCHCTL" bootstrap "$domain" "$plist" \
    || die "无法加载一次性原子替换任务"

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

backup_current_app() {
  local version build stamp target
  version="$(plist_value CFBundleShortVersionString "$QW_APP/Contents/Info.plist")"
  build="$(plist_value CFBundleVersion "$QW_APP/Contents/Info.plist")"
  stamp="$(date '+%Y%m%d-%H%M%S')"
  target="$BACKUP_ROOT/QianwenIME-stock-${version:-unknown}-${build:-unknown}.app"

  if [[ -d "$target" ]]; then
    log "本版本已有整包备份：$target"
    CURRENT_BACKUP="$target"
    return 0
  fi

  mkdir -p "$BACKUP_ROOT"
  local partial="$target.partial.$stamp"
  log "整包备份当前千问 $(app_version_string "$QW_APP")……"
  clone_tree "$QW_APP" "$partial"
  /bin/mv "$partial" "$target"
  CURRENT_BACKUP="$target"
  log "备份完成：$target"
}

backup_user_dir() {
  local stamp target
  [[ -d "$QW_USER_DIR" ]] || return 0
  stamp="$(date '+%Y%m%d-%H%M%S')"
  target="$BACKUP_ROOT/Qime-user-before-rollback-$stamp"
  log "备份千问用户目录……"
  clone_tree "$QW_USER_DIR" "$target"
  log "用户目录备份：$target"
}

run_install() {
  local source="$1"
  validate_common
  [[ -d "$source" ]] || die "找不到要安装的 App：$source"
  [[ -f "$source/Contents/Info.plist" ]] || die "不是有效的 App 包：$source"

  if [[ "$ALLOW_MODIFIED_SOURCE" -eq 1 ]]; then
    log "允许恢复已通过外部清单校验的修改版 App"
  elif command -v codesign >/dev/null 2>&1; then
    codesign --verify --strict "$source" 2>/dev/null \
      || die "待安装 App 签名校验失败，已停止：$source"
  fi

  local source_desc current_desc
  source_desc="$(app_version_string "$source")"
  current_desc="$(app_version_string "$QW_APP")"
  log "当前版本：$current_desc"
  log "将安装：  $source_desc"
  if [[ "$source_desc" == "$current_desc" ]]; then
    log "版本相同，仍会继续（可用于恢复被改动的 App 内容）"
  fi

  backup_current_app
  if [[ "$SKIP_USER_BACKUP" -eq 0 ]]; then
    backup_user_dir
  else
    log "已按要求跳过 Qime 用户数据备份"
  fi

  mkdir -p "$STATE_DIR"
  STAGE_ROOT="$(mktemp -d "$STATE_DIR/Rollback-$(date '+%Y%m%d-%H%M%S').XXXXXX")"
  local stage_app="$STAGE_ROOT/QianwenIME.app"

  log "准备暂存副本……"
  clone_tree "$source" "$stage_app"
  /usr/bin/xattr -d com.apple.macl "$stage_app" 2>/dev/null || true
  /bin/chmod -R u+rwX "$stage_app"

  if [[ "$DISABLE_UPDATER" -eq 1 ]]; then
    if [[ -e "$stage_app/$UPDATER_REL" ]]; then
      /bin/mv "$stage_app/$UPDATER_REL" "$stage_app/$UPDATER_REL.disabled"
      log "已禁用自动更新器（保留为 QianwenIMEUpdater.disabled，可随时改回）"
    else
      log "暂存副本中没有更新器，无需禁用"
    fi
  fi

  local expected_identity
  expected_identity="$(plist_value CFBundleVersion "$stage_app/Contents/Info.plist")"

  log "通过千问官方 helper 原子替换 Contents……"
  atomic_exchange_contents "$QW_APP/Contents" "$stage_app/Contents" "$STAGE_ROOT"

  local installed
  installed="$(plist_value CFBundleVersion "$QW_APP/Contents/Info.plist")"
  [[ "$installed" == "$expected_identity" ]] \
    || die "替换后版本校验失败：期望 ${expected_identity}，实际 $installed"

  if [[ "$NO_RELOAD" -eq 0 ]]; then
    local relauncher="$QW_APP/Contents/Helpers/QianwenIMERelaunch"
    [[ -x "$relauncher" ]] || die "找不到官方重载 helper：$relauncher"
    log "重启千问输入法……"
    "$relauncher" --host-bundle-path "$QW_APP"
  else
    log "已跳过重启（--no-reload）"
  fi

  log "安装完成：$(app_version_string "$QW_APP")"
  log "替换前的版本已保存：$CURRENT_BACKUP"
  log "被换下的 Contents 暂存于：${stage_app}（本次运行结束后清理）"
  log ""
  log "下一步：运行 scripts/sync_qianwen_rime.sh sync 重新覆盖星猫键道"
}

COMMAND="${1:-status}"
if [[ $# -gt 0 ]]; then shift; fi

case "$COMMAND" in
  install)
    SOURCE_APP=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --keep-updater) DISABLE_UPDATER=0 ;;
        --skip-user-backup) SKIP_USER_BACKUP=1 ;;
        --allow-modified-source) ALLOW_MODIFIED_SOURCE=1 ;;
        --no-reload) NO_RELOAD=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) die "未知参数：$1" ;;
        *) SOURCE_APP="$1" ;;
      esac
      shift
    done
    run_install "${SOURCE_APP:-$DEFAULT_SOURCE}"
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
