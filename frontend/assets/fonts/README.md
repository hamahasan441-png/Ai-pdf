# Editor fonts

These SIL Open Font License 1.1 fonts are committed and bundled with the app.
`PdfUnicodeFonts` loads them by path for vector text in exported PDFs, and
`pubspec.yaml` registers `NotoSansArabic`, `Vazirmatn` and `NotoSansHebrew` as
font families so the on-screen preview uses the same faces.

| File | Family | Licence |
| --- | --- | --- |
| `NotoSans-Regular.ttf`, `NotoSans-Bold.ttf` | Noto Sans (Latin, Greek, Cyrillic) | `licenses/OFL-NotoSans.txt` |
| `NotoSansArabic-Regular.ttf`, `NotoSansArabic-Bold.ttf` | Noto Sans Arabic | `licenses/OFL-NotoSansArabic.txt` |
| `Vazirmatn-Regular.ttf`, `Vazirmatn-Bold.ttf` | Vazirmatn | `licenses/OFL-Vazirmatn.txt` |
| `NotoSansHebrew-Regular.ttf`, `NotoSansHebrew-Bold.ttf` | Noto Sans Hebrew | `licenses/OFL-NotoSansHebrew.txt` |

`SHA256SUMS` holds the checksums of the committed files. `main.dart` registers
the licences with `LicenseRegistry`, so they appear on the app's licence page.

## Verifying or restoring

```
bash frontend/assets/fonts/download_fonts.sh
```

The script downloads from `raw.githubusercontent.com` with `curl -f`, rejects
HTML/JSON error pages, non-TrueType signatures and truncated files, then runs
`sha256sum -c SHA256SUMS`. A mismatch means upstream changed a file: review it
before updating `SHA256SUMS`.

## What the tests prove

`test/editor/pdf_unicode_fonts_test.dart` parses each file's `cmap` and checks:

- Noto Sans Arabic and Vazirmatn contain the Sorani letters ڕ ڵ ێ ە ۆ ۊ, a
  Sorani paragraph, Arabic, Arabic-Indic digits, ، and ؟.
- Noto Sans contains German and Kurmanji Latin letters.

## What vector export can and cannot do

`pdf` 3.11 shapes Arabic by substituting Unicode presentation forms; it does
not run the font's GSUB table. It has no forms for ڕ ڵ ێ ە ۊ, so text with
those letters (almost every Sorani sentence) would export with broken joins.
`PdfUnicodeFonts.pick` therefore refuses such text, and text that mixes RTL and
Latin letters, and the export paints it with Flutter's shaper into the page
image instead. It looks right (see `test/golden/goldens/export_page_rtl.png`)
but it is not selectable or searchable in the exported PDF.

Plain Arabic (letters `pdf` can shape) is exported as vector text. Its text
layer holds presentation forms (for example U+FEE3 instead of U+0645): PyMuPDF
`get_text()` returns them and a reader that applies NFKC normalisation finds
the words, but PyMuPDF `search_for("مرحبا")` does not.
