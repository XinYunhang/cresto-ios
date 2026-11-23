#!/usr/bin/env bash
# 生成本地个人信息文件（不进仓库）。
# 用法：bash scripts/make_profile.sh 2008-06-17 秦耀扬
set -euo pipefail

BIRTHDAY="${1:-${BIRTHDAY:-}}"
NAME="${2:-${PROFILE_NAME:-}}"
WEREAD_KEY="${WEREAD_API_KEY:-}"
WEREAD_ENDPOINT="${WEREAD_ENDPOINT:-}"

if [ -z "$BIRTHDAY" ]; then
  echo "usage: bash scripts/make_profile.sh YYYY-MM-DD [称呼]" >&2
  exit 1
fi

DEST="$(cd "$(dirname "$0")/.." && pwd)/Cresto/Resources"
mkdir -p "$DEST"

WEREAD_EXTRA=""
if [ -n "$WEREAD_KEY" ]; then
  WEREAD_EXTRA="${WEREAD_EXTRA}  <key>weread_api_key</key>
  <string>$WEREAD_KEY</string>
"
fi
if [ -n "$WEREAD_ENDPOINT" ]; then
  WEREAD_EXTRA="${WEREAD_EXTRA}  <key>weread_endpoint</key>
  <string>$WEREAD_ENDPOINT</string>
"
fi

cat > "$DEST/profile.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>birthday</key>
  <string>$BIRTHDAY</string>
  <key>name</key>
  <string>$NAME</string>
${WEREAD_EXTRA}</dict>
</plist>
PLIST

echo "✅ profile.plist -> $DEST"
echo "   birthday: $BIRTHDAY   name: ${NAME:-（空）}"
