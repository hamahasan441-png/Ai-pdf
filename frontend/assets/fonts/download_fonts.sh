#!/bin/bash
# Downloads the open-source Unicode TrueType fonts needed for searchable RTL export.
# Run this once from the project root: bash frontend/assets/fonts/download_fonts.sh
# All fonts are SIL Open Font License 1.1.

set -euo pipefail
FONT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Downloading fonts into: $FONT_DIR"

# --- Noto Sans (Latin/Cyrillic/Greek) ---
echo "→ NotoSans-Regular.ttf"
curl -sL "https://github.com/google/fonts/raw/main/ofl/notosans/NotoSans%5Bwdth%2Cwght%5D.ttf" \
  -o "$FONT_DIR/NotoSans-Regular.ttf" 2>/dev/null || \
curl -sL "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSans/hinted/ttf/NotoSans-Regular.ttf" \
  -o "$FONT_DIR/NotoSans-Regular.ttf"

echo "→ NotoSans-Bold.ttf"
curl -sL "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSans/hinted/ttf/NotoSans-Bold.ttf" \
  -o "$FONT_DIR/NotoSans-Bold.ttf"

# --- Noto Sans Arabic (Arabic/Kurdish/Persian) ---
echo "→ NotoSansArabic-Regular.ttf"
curl -sL "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSansArabic/hinted/ttf/NotoSansArabic-Regular.ttf" \
  -o "$FONT_DIR/NotoSansArabic-Regular.ttf"

echo "→ NotoSansArabic-Bold.ttf"
curl -sL "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSansArabic/hinted/ttf/NotoSansArabic-Bold.ttf" \
  -o "$FONT_DIR/NotoSansArabic-Bold.ttf"

# --- Vazirmatn (Persian/Kurdish alternative with excellent readability) ---
echo "→ Vazirmatn-Regular.ttf"
curl -sL "https://github.com/rastikerdar/vazirmatn/raw/master/fonts/ttf/Vazirmatn-Regular.ttf" \
  -o "$FONT_DIR/Vazirmatn-Regular.ttf"

echo "→ Vazirmatn-Bold.ttf"
curl -sL "https://github.com/rastikerdar/vazirmatn/raw/master/fonts/ttf/Vazirmatn-Bold.ttf" \
  -o "$FONT_DIR/Vazirmatn-Bold.ttf"

# --- Noto Sans Hebrew ---
echo "→ NotoSansHebrew-Regular.ttf"
curl -sL "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSansHebrew/hinted/ttf/NotoSansHebrew-Regular.ttf" \
  -o "$FONT_DIR/NotoSansHebrew-Regular.ttf"

echo "→ NotoSansHebrew-Bold.ttf"
curl -sL "https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSansHebrew/hinted/ttf/NotoSansHebrew-Bold.ttf" \
  -o "$FONT_DIR/NotoSansHebrew-Bold.ttf"

echo ""
echo "Done! All fonts downloaded. Rebuild the app and RTL text will export as searchable vector PDF."
echo "These fonts are SIL Open Font License 1.1. Keep this license notice if redistributing."
