#!/bin/bash
# 文件职责：把 website/media/ 下的媒体文件逐个上传到 cdn.gearmac.dev 背后的 R2 bucket。
# 分层：脚本（发布资源）；内容类型必须在此显式登记，未登记的扩展名直接失败。
#
# 用法：./Scripts/upload-website-media.sh
set -euo pipefail

BUCKET="gearmac-cdn"
WEBSITE="$(cd "$(dirname "$0")/../website" && pwd)"

# 目录为空时让通配符展开为空列表，而不是保留字面量。
shopt -s nullglob
FILES=("$WEBSITE"/media/*)
if [ ${#FILES[@]} -eq 0 ]; then
    echo "No media in $WEBSITE/media — nothing to upload."
    exit 0
fi

# 切到 website 目录后再上传，保证 wrangler 以正确的工作目录解析配置。
cd "$WEBSITE"
# 逐个上传：把扩展名映射为 Content-Type，并打印文件名、类型与体积。
for FILE in "${FILES[@]}"; do
    NAME="$(basename "$FILE")"
    # 未知扩展名直接终止：R2 会以 octet-stream 提供它，页面上的媒体标签就会失效。
    case "$NAME" in
        *.mp4) TYPE="video/mp4" ;;
        *.webm) TYPE="video/webm" ;;
        *.mov) TYPE="video/quicktime" ;;
        *.png) TYPE="image/png" ;;
        *.jpg | *.jpeg) TYPE="image/jpeg" ;;
        *) echo "::error::$NAME: add its content type to Scripts/upload-website-media.sh first."; exit 1 ;;
    esac
    printf '▸ %s (%s, %s)\n' "$NAME" "$TYPE" "$(du -h "$FILE" | cut -f1)"
    npx wrangler r2 object put "${BUCKET}/${NAME}" --file "$FILE" --content-type "$TYPE" --remote
done

echo "✓ ${#FILES[@]} file(s) on https://cdn.gearmac.dev/"
