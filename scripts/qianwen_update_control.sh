#!/bin/bash
set -euo pipefail

QW_APP="${QW_APP:-/Library/Input Methods/QianwenIME.app}"
UPDATER_REL="Contents/Helpers/QianwenIMEUpdater"
QW_RELAUNCHER="${QW_RELAUNCHER:-$QW_APP/Contents/Helpers/QianwenIMERelaunch}"
NO_RELOAD="${NO_RELOAD:-0}"

log() {
  printf '[千问更新] %s\n' "$*"
}

die() {
  printf '[千问更新] 错误：%s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
用法：qianwen_update_control.sh <status|block|unblock> [--no-reload]

  status       显示当前自动更新状态
  block        屏蔽自动更新
  unblock      取消屏蔽，允许自动更新
  --no-reload  切换后不重载千问输入法
EOF
}

validate_app() {
  [[ -d "$QW_APP" ]] || die "找不到千问输入法：$QW_APP"
  [[ -f "$QW_APP/Contents/Info.plist" ]] || die "千问 Info.plist 缺失"
}

updater_state() {
  local enabled="$QW_APP/$UPDATER_REL"
  local disabled="$enabled.disabled"
  if [[ -e "$enabled" && -e "$disabled" ]]; then
    printf 'ambiguous\n'
  elif [[ -x "$enabled" ]]; then
    printf 'enabled\n'
  elif [[ -e "$disabled" ]]; then
    printf 'blocked\n'
  elif [[ -e "$enabled" ]]; then
    printf 'broken\n'
  else
    printf 'missing\n'
  fi
}

show_status() {
  case "$(updater_state)" in
    enabled) log "自动更新：已启用" ;;
    blocked) log "自动更新：已屏蔽" ;;
    ambiguous) die "启用和禁用的更新器同时存在，请先人工检查 $QW_APP/$UPDATER_REL*" ;;
    broken) die "更新器存在但不可执行：$QW_APP/$UPDATER_REL" ;;
    missing) die "找不到千问更新器" ;;
  esac
}

reload_qianwen() {
  [[ "$NO_RELOAD" == 1 ]] && return 0
  [[ -x "$QW_RELAUNCHER" ]] || die "找不到官方重载 helper：$QW_RELAUNCHER"
  log "重载千问输入法……"
  "$QW_RELAUNCHER" --host-bundle-path "$QW_APP"
}

block_updates() {
  local updater="$QW_APP/$UPDATER_REL"
  case "$(updater_state)" in
    blocked)
      log "自动更新已经处于屏蔽状态"
      return 0
      ;;
    enabled) ;;
    *) show_status; return 1 ;;
  esac
  /bin/mv "$updater" "$updater.disabled"
  log "已屏蔽自动更新"
  reload_qianwen
}

unblock_updates() {
  local updater="$QW_APP/$UPDATER_REL"
  case "$(updater_state)" in
    enabled)
      log "自动更新已经处于启用状态"
      return 0
      ;;
    blocked) ;;
    *) show_status; return 1 ;;
  esac
  /bin/mv "$updater.disabled" "$updater"
  /bin/chmod u+x "$updater"
  log "已取消屏蔽，自动更新已启用"
  reload_qianwen
}

COMMAND="${1:-status}"
[[ $# -eq 0 ]] || shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-reload) NO_RELOAD=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
  shift
done

validate_app
case "$COMMAND" in
  status) show_status ;;
  block) block_updates ;;
  unblock) unblock_updates ;;
  -h|--help|help) usage ;;
  *) usage >&2; die "未知命令：$COMMAND" ;;
esac
