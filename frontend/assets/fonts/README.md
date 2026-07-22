# Editor fonts (searchable RTL export)

Drop Unicode TrueType (`.ttf`) fonts into this folder to make exported Arabic,
Kurdish (Sorani/Kurmanji), Persian, and Hebrew text **real, selectable, and
searchable** vector text in the PDF instead of a rasterized image.

The export pipeline (`EditorExportService` + `PdfUnicodeFonts`) loads these
files **by name at runtime**. Because this whole directory is declared in
`pubspec.yaml`, simply adding the files below and rebuilding activates the
feature — no code or pubspec changes required.

## Expected file names

| Purpose | Regular | Bold |
| --- | --- | --- |
| Latin / Cyrillic / Greek | `NotoSans-Regular.ttf` | `NotoSans-Bold.ttf` |
| Arabic / Kurdish (Arabic script) | `NotoSansArabic-Regular.ttf` | `NotoSansArabic-Bold.ttf` |
| Kurdish / Persian (alt.) | `Vazirmatn-Regular.ttf` | `Vazirmatn-Bold.ttf` |
| Hebrew | `NotoSansHebrew-Regular.ttf` | `NotoSansHebrew-Bold.ttf` |

These names match `FontRegistry` and `PdfUnicodeFonts`. Missing files are simply
skipped (that script falls back to the rasterized export path).

## Where to get them (all SIL Open Font License 1.1)

- Noto Sans / Noto Sans Arabic / Noto Sans Hebrew — Google Noto Fonts.
- Vazirmatn — an open Persian/Arabic-script family.

Fetch them once and place the `.ttf` files here. Keep the OFL license text
alongside them if you redistribute the app, per the license terms.

## Behaviour when this folder has no fonts

Everything still works: RTL text is rasterized into the page image (correct
visual order via `RtlTextRenderer`), it just isn't selectable/searchable in the
exported PDF. Adding the fonts upgrades that to vector text automatically.
