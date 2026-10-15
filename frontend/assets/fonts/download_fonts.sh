#!/bin/bash
# Downloads SIL OFL 1.1 TrueType fonts for searchable RTL export.
# Run once: bash frontend/assets/fonts/download_fonts.sh
# This does not run at app startup. A successful download is not glyph-coverage proof.

set -euo pipefail
FONT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Downloading fonts into: $FONT_DIR"

validate_ttf() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    echo "Rejected empty file: $file" >&2
    exit 1
  fi
  local first
  first=$(od -An -t u1 -N 1 "$file" | tr -d ' ')
  if [[ "$first" == "60" || "$first" == "123" ]]; then
    echo "Rejected non-font (HTML or JSON): $file" >&2
    rm -f "$file"
    exit 1
  fi
  local sig
  sig=$(od -An -t x1 -N 4 "$file" | tr -d ' \n')
  case "$sig" in
    00010000|74727565) ;;
    *)
      echo "Rejected bad TrueType signature $sig: $file" >&2
      rm -f "$file"
      exit 1
      ;;
  esac
  local size
  size=$(wc -c < "$file")
  if [[ "$size" -lt 10000 ]]; then
    echo "Rejected truncated font ($size bytes): $file" >&2
    rm -f "$file"
    exit 1
  fi
}

fetch() {
  local name="$1"
  local url="$2"
  echo "→ $name"
  curl -fsSL "$url" -o "$FONT_DIR/$name"
  validate_ttf "$FONT_DIR/$name"
}

fetch "NotoSans-Regular.ttf" \
  "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSans/hinted/ttf/NotoSans-Regular.ttf"
fetch "NotoSans-Bold.ttf" \
  "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSans/hinted/ttf/NotoSans-Bold.ttf"
fetch "NotoSansArabic-Regular.ttf" \
  "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSansArabic/hinted/ttf/NotoSansArabic-Regular.ttf"
fetch "NotoSansArabic-Bold.ttf" \
  "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSansArabic/hinted/ttf/NotoSansArabic-Bold.ttf"
fetch "Vazirmatn-Regular.ttf" \
  "https://github.com/rastikerdar/vazirmatn/raw/master/fonts/ttf/Vazirmatn-Regular.ttf"
fetch "Vazirmatn-Bold.ttf" \
  "https://github.com/rastikerdar/vazirmatn/raw/master/fonts/ttf/Vazirmatn-Bold.ttf"
fetch "NotoSansHebrew-Regular.ttf" \
  "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSansHebrew/hinted/ttf/NotoSansHebrew-Regular.ttf"
fetch "NotoSansHebrew-Bold.ttf" \
  "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSansHebrew/hinted/ttf/NotoSansHebrew-Bold.ttf"

echo ""
echo "Signature checks passed. Glyph coverage was not measured."
echo "These fonts are SIL Open Font License 1.1. Rebuild before export can embed them."
