#!/usr/bin/env bash
# 卡面不进仓库（原站写明仅限非商业使用），本地和 CI 都靠这个脚本现拉。
# 想换成自己的美术，把下面两张表改掉再跑一次即可。
set -euo pipefail

BASE="https://tianqi-public-media-1516434243.cos.ap-guangzhou.myqcloud.com/assets"
DEST="$(cd "$(dirname "$0")/.." && pwd)/Cresto/Resources/Cards"
mkdir -p "$DEST"

# 目标文件名:源文件名
CARDS=(
  "00-fool:00-fool"
  "01-magician:01-magician"
  "02-high-priestess:02-high_priestess"
  "03-empress:03-empress"
  "04-emperor:04-gpt-dark"
  "05-hierophant:05-hierophant"
  "06-lovers:06-lovers"
  "07-chariot:07-chariot"
  "08-strength:08-strength"
  "09-hermit:09-hermit"
  "10-wheel-of-fortune:10-wheel_of_fortune"
  "11-justice:11-justice"
  "12-hanged-man:12-hanged_man"
  "13-death:13-death"
  "14-temperance:14-temperance"
  "15-devil:15-gpt-light"
  "16-tower:16-tower"
  "17-star:17-star"
  "18-moon:18-moon"
  "19-sun:19-sun"
  "20-judgement:20-judgement"
  "21-world:21-world"
)

for pair in "${CARDS[@]}"; do
  out="${pair%%:*}"
  src="${pair##*:}"
  curl -fsSL "$BASE/cards/$src.webp" -o "$DEST/$out.webp"
  echo "  $out.webp"
done

curl -fsSL "$BASE/back.webp" -o "$DEST/card-back.webp"
echo "  card-back.webp"

echo "✅ 卡面已就位：$DEST"
