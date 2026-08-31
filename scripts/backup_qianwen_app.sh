#!/bin/bash
set -euo pipefail

QW_APP="${QW_APP:-/Library/Input Methods/QianwenIME.app}"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/Library/Application Support/QianwenIME/Backups/AppSnapshots}"
RESTORE_POINTER="${RESTORE_POINTER:-$BACKUP_ROOT/latest-app-snapshot.txt}"

log() {
  printf '[千问备份] %s\n' "$*"
}

die() {
  printf '[千问备份] 错误：%s\n' "$*" >&2
  exit 1
}

plist_value() {
  /usr/bin/plutil -extract "$1" raw "$2" 2>/dev/null || true
}

clone_tree() {
  local source="$1" target="$2"
  if /bin/cp -cR "$source" "$target" 2>/dev/null; then
    return 0
  fi
  /usr/bin/ditto --norsrc --noextattr "$source" "$target"
}

write_manifest() {
  local app="$1" manifest="$2"
  (
    cd "$app"
    find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
      /usr/bin/shasum -a 256 "$file"
    done
  ) >"$manifest"
}

verify_manifest() {
  local app="$1" manifest="$2"
  (cd "$app" && /usr/bin/shasum -a 256 -c "$manifest" >/dev/null)
}

[[ -d "$QW_APP" ]] || die "找不到千问输入法：$QW_APP"
[[ -f "$QW_APP/Contents/Info.plist" ]] || die "千问 Info.plist 缺失"

version="$(plist_value CFBundleShortVersionString "$QW_APP/Contents/Info.plist")"
build="$(plist_value CFBundleVersion "$QW_APP/Contents/Info.plist")"
stamp="$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$BACKUP_ROOT"

snapshot="$BACKUP_ROOT/QianwenIME-current-${version:-unknown}-${build:-unknown}-$stamp.app"
[[ ! -e "$snapshot" ]] || snapshot="${snapshot%.app}-$$.app"
partial="$snapshot.partial"
manifest="$snapshot.sha256"
pointer_tmp="$RESTORE_POINTER.tmp.$$"

cleanup() {
  [[ ! -e "$partial" ]] || /bin/rm -rf "$partial"
  [[ ! -e "$pointer_tmp" ]] || /bin/rm -f "$pointer_tmp"
}
trap cleanup EXIT

log "备份当前千问 ${version:-unknown} (${build:-unknown})……"
clone_tree "$QW_APP" "$partial"
/bin/mv "$partial" "$snapshot"
write_manifest "$snapshot" "$manifest"
verify_manifest "$snapshot" "$manifest" || die "备份校验失败：$snapshot"

mkdir -p "$(dirname "$RESTORE_POINTER")"
printf '%s\n' "$snapshot" >"$pointer_tmp"
/bin/mv "$pointer_tmp" "$RESTORE_POINTER"

log "App 备份完成：$snapshot"
log "校验清单：$manifest"
log "默认恢复点：$RESTORE_POINTER"
log "未备份 Qime 用户数据"
