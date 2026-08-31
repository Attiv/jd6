#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/Library/Application Support/QianwenIME/Backups/AppSnapshots}"
RESTORE_POINTER="${RESTORE_POINTER:-$BACKUP_ROOT/latest-app-snapshot.txt}"
ROLLBACK_SCRIPT="${ROLLBACK_SCRIPT:-$SCRIPT_DIR/rollback_qianwen.sh}"
NO_RELOAD=0
SNAPSHOT=""

log() {
  printf '[千问恢复] %s\n' "$*"
}

die() {
  printf '[千问恢复] 错误：%s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
用法：restore_qianwen_app.sh [<App 备份路径>] [--no-reload]

不给路径时恢复 backup_qianwen_app.sh 最近记录的 App 快照。
只恢复千问 App，不恢复或覆盖 Qime 用户数据。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-reload) NO_RELOAD=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "未知参数：$1" ;;
    *)
      [[ -z "$SNAPSHOT" ]] || die "只能指定一个 App 备份路径"
      SNAPSHOT="$1"
      ;;
  esac
  shift
done

if [[ -z "$SNAPSHOT" ]]; then
  [[ -f "$RESTORE_POINTER" ]] || die "找不到默认恢复点：$RESTORE_POINTER"
  IFS= read -r SNAPSHOT <"$RESTORE_POINTER"
fi

[[ -d "$SNAPSHOT" ]] || die "找不到 App 备份：$SNAPSHOT"
[[ -f "$SNAPSHOT/Contents/Info.plist" ]] || die "备份不是有效的千问 App：$SNAPSHOT"
MANIFEST="$SNAPSHOT.sha256"
[[ -f "$MANIFEST" ]] || die "找不到备份校验清单：$MANIFEST"
(cd "$SNAPSHOT" && /usr/bin/shasum -a 256 -c "$MANIFEST" >/dev/null) \
  || die "App 备份校验失败，拒绝恢复：$SNAPSHOT"
[[ -x "$ROLLBACK_SCRIPT" ]] || die "找不到恢复实现：$ROLLBACK_SCRIPT"

args=(install "$SNAPSHOT" --keep-updater --skip-user-backup --allow-modified-source)
[[ "$NO_RELOAD" -eq 0 ]] || args+=(--no-reload)

log "校验通过，开始恢复 App；不会恢复 Qime 用户数据"
"$ROLLBACK_SCRIPT" "${args[@]}"
