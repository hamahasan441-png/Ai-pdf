import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfColor, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:share_plus/share_plus.dart';

import '../../../core/services/ocr_service.dart';
import '../../../core/services/signature_store.dart';
import '../../../core/services/tool_handoff.dart';
import '../../../core/services/user_profile_service.dart';
import '../../profile/presentation/profile_screen.dart';
import '../models/filled_field.dart';
import '../services/profile_field_matcher.dart';
import '../services/smart_form_filler.dart';

/// Tools available in the pro editor.
enum EditTool { pan, select, draw, highlight, text, line, arrow, rect, oval, whiteout, signature, eraser, check, cross, dot, dash, checkbox }

/// Inferred type of a detected form field, so tapping it opens the right input.
enum FieldType { text, number, date, email, phone, name, signature, checkbox, radio }

/// A fillable field the app detected on the page via OCR. [rect] is the label
/// position (normalized 0..1); the value is placed just after it, at a font
/// size matched to the label's height.
class DetectedField {
  final Rect rect;
  final String label;
  final FieldType type;
  const DetectedField(this.rect, this.label, this.type);
}

/// Shape kinds for the vector shape tools.
enum ShapeType { line, arrow, rect, oval, whiteout }

/// Base type for anything drawn on a page (used for undo/redo ordering).
abstract class _Annotation {}

/// A freehand stroke or highlight (normalized 0..1 coordinates).
class _Stroke extends _Annotation {
  final List<Offset> points;
  final Color color;
  final double width;
  final bool highlight;
  _Stroke(this.points, this.color, this.width, this.highlight);
}

/// A straight line, arrow, or rectangle (normalized coordinates).
class _Shape extends _Annotation {
  final ShapeType type;
  Offset start;
  Offset end;
  Color color;
  double width;
  bool filled; // fill rect/oval with a translucent color
  double opacity; // 0..1
  _Shape(this.type, this.start, this.end, this.color, this.width,
      [this.filled = false, this.opacity = 1.0]);
}

/// A text box annotation (normalized position).
class _TextBox extends _Annotation {
  Offset pos; // normalized 0..1
  String text;
  Color color;
  double size; // normalized to canvas height
  bool bold;
  bool italic;
  bool underline;
  String? fontFamily; // null = default, 'serif', 'monospace'
  _TextBox(this.pos, this.text, this.color, this.size, this.bold,
      [this.italic = false, this.underline = false, this.fontFamily]);
}

/// Per-page annotation layer with undo + redo history.
class _PageLayer {
  final List<_Annotation> items = [];
  final List<_Annotation> redo = [];

  List<_Stroke> get strokes => items.whereType<_Stroke>().toList();
  List<_Shape> get shapes => items.whereType<_Shape>().toList();
  List<_TextBox> get texts => items.whereType<_TextBox>().toList();
}

/// Professional offline PDF/Image editor.
///
/// Memory-safe: pages are rendered with pdfx at a capped resolution and only
/// a few pages are cached at once. Features: multi-page nav, pinch zoom,
/// freehand draw, highlighter, straight line / arrow / rectangle shapes,
/// movable + editable text boxes (font size, bold, color), signature,
/// eraser, undo/redo, and export to a flattened PDF captured page-by-page so
/// nothing is ever loaded at huge resolution.
class PickEditScreen extends StatefulWidget {
  /// Optional: open this file immediately (skip the file picker).
  final String? initialPath;

  /// Optional: pre-place these values as editable text boxes (used by the
  /// AI form filler to drop answers onto the actual form).
  final List<FilledField>? initialFields;

  const PickEditScreen({super.key, this.initialPath, this.initialFields});
  @override
  State<PickEditScreen> createState() => _PickEditScreenState();
}

class _PickEditScreenState extends State<PickEditScreen> {
  static const int _renderMaxEdge = 1400;
  static const int _maxCachedPages = 3;

  pdfx.PdfDocument? _doc;
  final Map<int, Uint8List> _pageCache = {}; // page index -> jpeg bytes
  final Map<int, _PageLayer> _layers = {};
  int _pageCount = 0;
  int _current = 0;
  bool _loading = false;
  String? _fileName;

  EditTool _tool = EditTool.draw;
  Color _color = Colors.red;
  double _stroke = 3;
  double _textSize = 0.032; // normalized to page height
  bool _bold = false;

  List<Offset> _drawing = [];
  Offset? _shapeStart; // live shape preview (normalized)
  Offset? _shapeEnd;

  // --- Selection state ---
  _Annotation? _selected; // currently selected annotation (for move/resize)
  _Annotation? _clipboard; // copied object, pasteable onto any page
  Offset? _dragOffset; // offset during move
  bool _hasUnsavedChanges = false;

  // --- Snapping guides (E3.4) ---
  double? _guideX; // normalized x for a vertical alignment guide
  double? _guideY; // normalized y for a horizontal alignment guide

  // --- Multi-select (E2) ---
  final Set<_Annotation> _multi = {};
  Offset? _marqueeStart;
  Offset? _marqueeEnd;
  String _selMode = 'none'; // 'marquee' | 'move'
  Offset? _selDragLast;

  // --- Smart field detection (E1) ---
  final OcrService _ocr = OcrService();
  final Map<int, List<DetectedField>> _fields = {}; // page -> detected fields
  bool _showFields = false;

  // --- Edit existing text (OCR line -> cover + editable box) ---
  final Map<int, List<OcrLine>> _editLines = {}; // page -> recognized lines
  bool _showEditLines = false;
  bool _detecting = false;
  List<DetectedField> get _pageFields => _fields[_current] ?? const [];

  // --- Saved signatures (persisted across sessions) ---
  static final List<List<Offset>> _savedSignatures = [];
  static bool _signaturesLoaded = false;

  @override
  void initState() {
    super.initState();
    // Restore signatures saved in previous sessions (once per app run).
    if (!_signaturesLoaded) {
      _signaturesLoaded = true;
      SignatureStore.instance.load().then((sigs) {
        if (sigs.isNotEmpty && _savedSignatures.isEmpty) {
          _savedSignatures.addAll(sigs);
          if (mounted) setState(() {});
        }
      });
    }
    if (widget.initialPath != null) {
      // Open the provided file after first frame (so context/state is ready).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadFile(widget.initialPath!, widget.initialPath!.split('/').last,
            fields: widget.initialFields);
      });
    }
  }

  @override
  void dispose() {
    _doc?.close();
    _ocr.dispose();
    super.dispose();
  }

  // ---- Smart field detection (E1) --------------------------------------

  /// OCR the current page, find label-like fields, infer each type, and show
  /// them as tappable targets. Fully offline (ML Kit bundled model).
  Future<void> _detectFields({bool silent = false}) async {
    final bytes = _pageCache[_current];
    if (bytes == null) return;
    setState(() => _detecting = true);
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/detect_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await f.writeAsBytes(bytes);
      final result = await _ocr.recognize(f.path);
      try {
        await f.delete();
      } catch (_) {}

      final detected = <DetectedField>[];
      for (final line in result.lines) {
        if (!_isFieldLabel(line.text)) continue;
        detected.add(DetectedField(
          Rect.fromLTWH(line.x, line.y, line.w, line.h),
          line.text.trim(),
          _inferType(line.text),
        ));
      }

      // Shape-based detection: small, roughly-square OCR boxes with very short
      // text (1-3 chars) that aren't already a label are likely checkbox/radio
      // form elements. Catches drawn squares/circles that OCR reads as a random
      // character rather than a known glyph.
      for (final line in result.lines) {
        final t = line.text.trim();
        if (t.isEmpty || t.length > 3) continue;
        if (_isFieldLabel(t)) continue; // already handled above
        final aspect = line.w > 0 ? (line.h / line.w) : 1.0;
        final isSmall = line.w < 0.06 && line.h < 0.04;
        if (!isSmall) continue;
        if (aspect >= 0.6 && aspect <= 1.6) {
          final type = (t == 'O' || t == 'o' || t == '0')
              ? FieldType.radio
              : FieldType.checkbox;
          detected.add(DetectedField(
            Rect.fromLTWH(line.x, line.y, line.w, line.h),
            t,
            type,
          ));
        }
      }
      setState(() {
        _fields[_current] = detected;
        _showFields = true;
        _tool = EditTool.pan; // so taps select/fill, not draw
      });
      if (detected.isEmpty && !silent) {
        _showError('No obvious fields found on this page. You can still tap Text to add anywhere.');
      }
    } catch (e) {
      if (!silent) _showError('Field detection failed: $e');
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  bool _isFieldLabel(String t) {
    final s = t.trim();
    if (s.isEmpty || s.length > 60) return false;
    if (s.endsWith(':')) return true;
    if (RegExp(r'_{2,}').hasMatch(s)) return true; // underscore blanks
    if (_isCheckboxGlyph(s)) return true;
    if (_isRadioGlyph(s)) return true;
    return _inferType(s) != FieldType.text; // matched a typed keyword
  }

  /// Detect visual checkbox glyphs that OCR recognizes as characters.
  bool _isCheckboxGlyph(String s) {
    final t = s.trim();
    if (t.length <= 3) {
      if (RegExp(r'^[\[\]()\u25A1\u2610\u2611\u2612\u25A0\u25FB\u25FC\u2B1C□☐☑☒■◻◼⬜]+$')
          .hasMatch(t)) return true;
      if (RegExp(r'^[xX]$').hasMatch(t)) return true;
    }
    return false;
  }

  /// Detect visual radio button glyphs (circles).
  bool _isRadioGlyph(String s) {
    final t = s.trim();
    if (t.length <= 2) {
      if (RegExp(r'^[\u25CB\u25CE\u25C9\u25EF\u26AA\u26AB○◎◉◯⚪⚫]+$')
          .hasMatch(t)) return true;
      if (t == 'O' || t == 'o' || t == '()') return true;
    }
    return false;
  }

  FieldType _inferType(String label) {
    final s = label.toLowerCase();
    bool has(List<String> ks) => ks.any((k) => s.contains(k));
    if (has(['signature', 'unterschrift', 'sign here', 'signed'])) return FieldType.signature;
    if (_isCheckboxGlyph(label.trim())) return FieldType.checkbox;
    if (_isRadioGlyph(label.trim())) return FieldType.radio;
    // Short option words that typically have a checkbox next to them.
    if (s.trim().length <= 12 && has(['ja', 'nein', 'yes', 'no', 'männlich',
        'weiblich', 'divers', 'ledig', 'verheiratet'])) return FieldType.checkbox;
    if (has(['e-mail', 'email', 'e mail'])) return FieldType.email;
    if (has(['date', 'datum', 'birth', 'geburt', 'geboren', 'dob', 'valid', 'expiry'])) {
      return FieldType.date;
    }
    if (has(['phone', 'tel', 'telefon', 'mobile', 'handy', 'fax'])) return FieldType.phone;
    if (has(['amount', 'betrag', 'iban', 'zip', 'postal', 'plz', 'number', 'nummer',
        'no.', 'nr', 'sum', 'total', 'konto', 'account', 'salary', 'income', 'einkommen'])) {
      return FieldType.number;
    }
    if (has(['name', 'vorname', 'nachname', 'first name', 'last name', 'surname', 'familienname'])) {
      return FieldType.name;
    }
    return FieldType.text;
  }

  IconData _typeIcon(FieldType t) => switch (t) {
        FieldType.date => Icons.event,
        FieldType.number || FieldType.phone => Icons.pin,
        FieldType.email => Icons.alternate_email,
        FieldType.signature => Icons.gesture,
        FieldType.checkbox => Icons.check_box_outlined,
        FieldType.radio => Icons.radio_button_checked,
        _ => Icons.text_fields,
      };

  /// Tapping a detected field opens the right interaction for its type.
  ///
  /// SMART BEHAVIOR (marks are auto-sized from [field.rect] so they never
  /// overflow the box):
  /// - Checkbox/square: instantly places a ✓ sized to ~80% of the box, centered.
  /// - Radio/circle: instantly places a ● dot sized to ~70% of the diameter.
  /// - Text/name/email/phone/number: opens keyboard with the right type; places
  ///   the value at a font size ~75% of the field height.
  /// - Date: date picker → TT.MM.JJJJ, sized to fit.
  /// - Signature: opens the signature pad.
  Future<void> _openFieldInput(DetectedField field) async {
    // --- Checkbox: instant check mark, fitted inside the square ---
    if (field.type == FieldType.checkbox) {
      // Let the user choose a check (correct) or a cross (wrong).
      final mark = await _chooseCheckMark();
      if (mark == null) return;
      final markSize = (field.rect.height * 0.80).clamp(0.012, 0.06).toDouble();
      final cx = (field.rect.left + (field.rect.width - markSize * 0.5) * 0.5)
          .clamp(0.0, 0.97)
          .toDouble();
      final cy = (field.rect.top + (field.rect.height - markSize) * 0.3)
          .clamp(0.0, 0.97)
          .toDouble();
      final color =
          mark == '✓' ? const Color(0xFF16A34A) : const Color(0xFFD9636B);
      final tb = _TextBox(Offset(cx, cy), mark, color, markSize, true);
      setState(() {
        _pushItem(tb);
        _selected = tb; // auto-select so the whole mark can be dragged at once
        _tool = EditTool.pan;
      });
      return;
    }

    // --- Radio button / circle: instant filled dot, fitted inside ---
    if (field.type == FieldType.radio) {
      final dotSize = (field.rect.height * 0.70).clamp(0.010, 0.05).toDouble();
      final cx = (field.rect.left + (field.rect.width - dotSize * 0.4) * 0.5)
          .clamp(0.0, 0.97)
          .toDouble();
      final cy = (field.rect.top + (field.rect.height - dotSize) * 0.35)
          .clamp(0.0, 0.97)
          .toDouble();
      final tb = _TextBox(Offset(cx, cy), '●', Colors.black, dotSize, false);
      setState(() {
        _pushItem(tb);
        _selected = tb; // auto-select so the whole dot can be dragged at once
        _tool = EditTool.pan;
      });
      return;
    }

    // --- Signature: open the signature pad ---
    if (field.type == FieldType.signature) {
      await _addSignature();
      return;
    }

    // Text/date placement: just after the label, sized to ~75% of line height
    // so it fits inside the field's writing area.
    final size = (field.rect.height * 0.75).clamp(0.014, 0.05).toDouble();
    final pos = Offset(
      (field.rect.left + field.rect.width + 0.008).clamp(0.0, 0.90).toDouble(),
      (field.rect.top + field.rect.height * 0.1).clamp(0.0, 0.97).toDouble(),
    );
    final title = field.label.replaceAll(':', '').trim();

    if (field.type == FieldType.date) {
      final d = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
        helpText: title.isEmpty ? 'Select date' : title,
      );
      if (d != null) {
        final v = '${d.day.toString().padLeft(2, '0')}.'
            '${d.month.toString().padLeft(2, '0')}.${d.year}';
        _placeValue(pos, size, v);
      }
      return;
    }
    final kb = switch (field.type) {
      FieldType.number || FieldType.phone => TextInputType.number,
      FieldType.email => TextInputType.emailAddress,
      _ => TextInputType.text,
    };
    final val = await _promptValue(title.isEmpty ? 'Enter value' : title, kb, field.type);
    if (val != null && val.trim().isNotEmpty) {
      final v = val.trim();
      // Auto-fit: shrink long values so they don't overflow the field's width.
      final fitted = _fitTextSize(v, size, (0.98 - pos.dx).clamp(0.05, 1.0).toDouble());
      _placeValue(pos, fitted, v);
      _offerReplicate(field, v);
    }
  }

  void _placeValue(Offset pos, double size, String text) {
    final tb = _TextBox(pos, text, Colors.black, size, false);
    setState(() {
      _pushItem(tb);
      // Auto-select + switch to move mode so the user can immediately drag the
      // whole value into place with one finger — simple, no extra taps.
      _selected = tb;
      _tool = EditTool.pan;
    });
  }

  /// Quick chooser shown when a checkbox field is tapped: check (correct) or
  /// cross (wrong). Returns the chosen glyph, or null if dismissed.
  Future<String?> _chooseCheckMark() {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _markChoice(ctx, '✓', 'Correct', const Color(0xFF16A34A)),
              _markChoice(ctx, '✗', 'Wrong', const Color(0xFFD9636B)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _markChoice(BuildContext ctx, String mark, String label, Color color) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.pop(ctx, mark),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(mark,
                    style: TextStyle(
                        fontSize: 36, color: color, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            Text(label),
          ],
        ),
      ),
    );
  }

  /// Rough auto-fit: reduce font [baseSize] so a value of [text] fits within
  /// [availWidthNorm] (normalized page width). Heuristic (no pixel measuring)
  /// but reliably keeps long values from spilling past the field.
  double _fitTextSize(String text, double baseSize, double availWidthNorm) {
    if (text.isEmpty) return baseSize;
    const advance = 0.55; // avg glyph width as a fraction of the font size
    const pageWH = 1.41; // A4 portrait height/width ratio
    final neededH = text.length * advance * baseSize; // in height-normalized units
    final availH = availWidthNorm * pageWH; // convert width budget to height units
    if (neededH <= availH) return baseSize;
    return (baseSize * (availH / neededH)).clamp(0.010, baseSize).toDouble();
  }

  String _normLabel(String s) =>
      s.toLowerCase().replaceAll(':', '').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// After filling a labelled field, offer to fill any other fields on the page
  /// that share the same label (e.g. a name/date that repeats) with one tap.
  void _offerReplicate(DetectedField source, String value) {
    final key = _normLabel(source.label);
    if (key.isEmpty) return;
    const textLike = {
      FieldType.text, FieldType.name, FieldType.email,
      FieldType.phone, FieldType.number, FieldType.date,
    };
    final similar = _pageFields
        .where((f) =>
            !identical(f, source) &&
            textLike.contains(f.type) &&
            _normLabel(f.label) == key)
        .toList();
    if (similar.isEmpty) return;

    final label = source.label.replaceAll(':', '').trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Fill ${similar.length} more "$label" field(s) with the same value?'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Fill all',
          onPressed: () {
            for (final f in similar) {
              final size = (f.rect.height * 0.75).clamp(0.014, 0.05).toDouble();
              final pos = Offset(
                (f.rect.left + f.rect.width + 0.008).clamp(0.0, 0.90).toDouble(),
                (f.rect.top + f.rect.height * 0.1).clamp(0.0, 0.97).toDouble(),
              );
              final fitted = _fitTextSize(
                  value, size, (0.98 - pos.dx).clamp(0.05, 1.0).toDouble());
              _placeValue(pos, fitted, value);
            }
          },
        ),
      ),
    );
  }

  // ---- Offline Smart Auto-Fill (form filler) --------------------------
  //
  // Uses the on-device profile + OCR-detected labels to fill known fields
  // instantly and privately — no network, no AI call. Whatever can't be
  // matched from the profile is offered as a quick guided pass, so the user
  // taps through the rest with the correct keyboard / date picker per field.

  Future<void> _autoFill() async {
    if (_pageCache[_current] == null) return;
    // Make sure we have fields to work with on this page.
    if (_pageFields.isEmpty) {
      await _detectFields();
    }
    final fields = _pageFields;
    if (fields.isEmpty) return; // _detectFields already messaged the user.

    await UserProfileService.instance.load();
    final profile = UserProfileService.instance.data;

    var autoCount = 0;
    final remaining = <DetectedField>[];
    for (final f in fields) {
      // Signatures always need an explicit gesture/typed entry.
      if (f.type == FieldType.signature) {
        remaining.add(f);
        continue;
      }
      final key = ProfileFieldMatcher.match(f.label);
      final value = key == null ? null : profile[key];
      if (value != null && value.trim().isNotEmpty) {
        // Place the value just after the label, at the label's line height.
        final pos = Offset(
          (f.rect.left + f.rect.width + 0.012).clamp(0.0, 0.9),
          f.rect.top,
        );
        final size = (f.rect.height * 0.85).clamp(0.014, 0.06);
        _placeValue(pos, size, value.trim());
        autoCount++;
      } else {
        remaining.add(f);
      }
    }

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(autoCount > 0
          ? l10n.autoFilledCount(autoCount)
          : l10n.noProfileMatches),
    ));

    if (remaining.isNotEmpty) {
      await _guidedFill(remaining);
    }
  }

  /// Step through [fields] one-by-one, opening the right input for each so the
  /// user can quickly complete anything the profile couldn't fill.
  Future<void> _guidedFill(List<DetectedField> fields) async {
    if (!mounted || fields.isEmpty) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.fillRemainingFields),
        content: Text(AppLocalizations.of(ctx)!.fillRemainingBody(fields.length)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(ctx)!.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(ctx)!.ok)),
        ],
      ),
    );
    if (go != true) return;
    for (final f in fields) {
      if (!mounted) break;
      await _openFieldInput(f);
    }
  }

  /// Fill & Sign: add a typed signature rendered in a script-like style. A fast
  /// alternative to drawing when the user just wants their name on the line.
  Future<void> _typeSignature() async {
    final val = await _promptValue(
        AppLocalizations.of(context)!.typeYourSignature,
        TextInputType.text,
        FieldType.name);
    if (val != null && val.trim().isNotEmpty) {
      setState(() => _pushItem(_TextBox(
            const Offset(0.4, 0.68),
            val.trim(),
            Colors.black,
            0.045,
            false, // bold
            true, // italic (script-like)
            false, // underline
            'serif',
          )));
    }
  }

  Future<String?> _promptValue(String label, TextInputType kb, FieldType type) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(_typeIcon(type), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: kb,
          decoration: InputDecoration(hintText: AppLocalizations.of(ctx)!.typeHere, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(ctx)!.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(AppLocalizations.of(ctx)!.add)),
        ],
      ),
    );
  }

  _PageLayer get _layer => _layers.putIfAbsent(_current, () => _PageLayer());

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    await _loadFile(path, result.files.first.name);
  }

  /// Load a PDF/image from [path]. Optionally pre-place [fields] as editable
  /// text boxes (used by the AI form filler).
  Future<void> _loadFile(String path, String name, {List<FilledField>? fields}) async {
    setState(() {
      _loading = true;
      _pageCache.clear();
      _layers.clear();
      _fields.clear();
      _multi.clear();
      _current = 0;
      _fileName = name;
      _selected = null;
    });

    try {
      await _doc?.close();
      _doc = null;
      if (path.toLowerCase().endsWith('.pdf')) {
        _doc = await pdfx.PdfDocument.openFile(path);
        _pageCount = _doc!.pagesCount;
        await _renderPage(0);
      } else {
        _pageCount = 1;
        _pageCache[0] = await File(path).readAsBytes();
      }

      // Drop AI-filled values onto their pages as editable text boxes.
      if (fields != null && fields.isNotEmpty) {
        for (final f in fields) {
          final pageIndex = (f.page - 1).clamp(0, (_pageCount - 1).clamp(0, 1 << 30));
          final layer = _layers.putIfAbsent(pageIndex, () => _PageLayer());
          // If the AI found a signature line and the user has a saved drawn
          // signature, stamp the real signature there instead of the name.
          if (f.isSignature && _savedSignatures.isNotEmpty) {
            final s = _signatureStrokeAt(_savedSignatures.first, f.x, f.y);
            if (s != null) {
              layer.items.add(s);
              continue;
            }
          }
          // Style by field kind: checks are a bold mark, signatures use an
          // italic serif (script-like) look, everything else is plain text.
          final double boxSize = f.isCheck ? 0.03 : (f.isSignature ? 0.032 : 0.024);
          layer.items.add(_TextBox(
            Offset(f.x, f.y),
            f.text,
            Colors.black,
            boxSize,
            f.isCheck, // bold
            f.isSignature, // italic
            false,
            f.isSignature ? 'serif' : null,
          ));
        }
        _hasUnsavedChanges = true;
        _tool = EditTool.pan; // start in move/select mode so user can adjust
      }

      // Smart tap: detect fields immediately so tapping any box gives the right
      // action (keyboard / check / dot) without pressing Auto-fill first.
      if (fields == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageCache[_current] != null) _detectFields(silent: true);
        });
      }
    } catch (e) {
      _showError('Could not open file: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _renderPage(int index) async {
    if (_pageCache.containsKey(index) || _doc == null) return;
    final page = await _doc!.getPage(index + 1);
    try {
      final longEdge = page.width > page.height ? page.width : page.height;
      final scale = longEdge > _renderMaxEdge ? _renderMaxEdge / longEdge : 1.0;
      final rendered = await page.render(
        width: (page.width * scale),
        height: (page.height * scale),
        format: pdfx.PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
      );
      if (rendered != null) {
        _pageCache[index] = rendered.bytes;
      }
    } finally {
      await page.close();
    }
    _evictFarPages(index);
  }

  /// Bound memory: drop rendered bytes for pages far from [keep].
  /// Annotation layers (tiny) are always retained so edits are never lost.
  void _evictFarPages(int keep) {
    if (_pageCache.length <= _maxCachedPages) return;
    final toRemove = _pageCache.keys
        .where((k) => (k - keep).abs() > 1)
        .toList()
      ..sort((a, b) => (b - keep).abs().compareTo((a - keep).abs()));
    for (final k in toRemove) {
      if (_pageCache.length <= _maxCachedPages) break;
      _pageCache.remove(k);
    }
  }

  Future<void> _goToPage(int index) async {
    if (index < 0 || index >= _pageCount) return;
    setState(() => _loading = true);
    await _renderPage(index);
    setState(() {
      _current = index;
      _selected = null;
      _multi.clear();
      _showFields = false;
      _showEditLines = false;
      _loading = false;
    });
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ---- Gesture handling (coordinates normalized to canvas) ----

  bool get _isFreehand => _tool == EditTool.draw || _tool == EditTool.highlight;
  bool get _isShape =>
      _tool == EditTool.line || _tool == EditTool.arrow || _tool == EditTool.rect ||
      _tool == EditTool.oval || _tool == EditTool.whiteout;

  void _onPanStart(Offset local, Size canvas) {
    final n = _norm(local, canvas);
    if (_tool == EditTool.select) {
      final hit = _hitTest(n);
      if (hit != null && _multi.contains(hit)) {
        _selMode = 'move';
        _selDragLast = n;
      } else if (hit != null) {
        _multi
          ..clear()
          ..add(hit);
        _selMode = 'move';
        _selDragLast = n;
      } else {
        _selMode = 'marquee';
        _marqueeStart = n;
        _marqueeEnd = n;
      }
      setState(() {});
      return;
    }
    if (_tool == EditTool.pan && _selected != null) {
      // Start moving selected object
      _dragOffset = n;
      return;
    }
    if (_isFreehand) {
      _drawing = [n];
      setState(() {});
    } else if (_isShape) {
      _shapeStart = n;
      _shapeEnd = n;
      setState(() {});
    }
  }

  void _onPanUpdate(Offset local, Size canvas) {
    final n = _norm(local, canvas);
    if (_tool == EditTool.select) {
      if (_selMode == 'marquee') {
        _marqueeEnd = n;
        setState(() {});
      } else if (_selMode == 'move' && _selDragLast != null) {
        final d = Offset(n.dx - _selDragLast!.dx, n.dy - _selDragLast!.dy);
        for (final a in _multi) {
          _moveAnnotation(a, d);
        }
        _selDragLast = n;
        _hasUnsavedChanges = true;
        setState(() {});
      }
      return;
    }
    if (_tool == EditTool.pan && _selected != null && _dragOffset != null) {
      final delta = Offset(n.dx - _dragOffset!.dx, n.dy - _dragOffset!.dy);
      _moveSelected(delta);
      _dragOffset = n;
      return;
    }
    if (_isFreehand) {
      _drawing = [..._drawing, n];
      setState(() {});
    } else if (_isShape && _shapeStart != null) {
      _shapeEnd = n;
      setState(() {});
    }
  }

  void _onPanEnd() {
    if (_tool == EditTool.select) {
      if (_selMode == 'marquee' && _marqueeStart != null && _marqueeEnd != null) {
        final r = Rect.fromPoints(_marqueeStart!, _marqueeEnd!);
        _multi.clear();
        if (r.width > 0.01 || r.height > 0.01) {
          for (final a in _layer.items) {
            if (_boundsOf(a).overlaps(r)) _multi.add(a);
          }
        }
      }
      _selMode = 'none';
      _marqueeStart = null;
      _marqueeEnd = null;
      _selDragLast = null;
      _guideX = null;
      _guideY = null;
      setState(() {});
      return;
    }
    _dragOffset = null;
    _guideX = null;
    _guideY = null;
    if (_isFreehand && _drawing.length > 1) {
      _pushItem(_Stroke(
        List.from(_drawing),
        _tool == EditTool.highlight ? _color.withOpacity(0.35) : _color,
        _tool == EditTool.highlight ? 16 : _stroke,
        _tool == EditTool.highlight,
      ));
    } else if (_isShape && _shapeStart != null && _shapeEnd != null) {
      final type = switch (_tool) {
        EditTool.line => ShapeType.line,
        EditTool.arrow => ShapeType.arrow,
        EditTool.oval => ShapeType.oval,
        EditTool.whiteout => ShapeType.whiteout,
        _ => ShapeType.rect,
      };
      if ((_shapeStart! - _shapeEnd!).distance > 0.01) {
        _pushItem(_Shape(type, _shapeStart!, _shapeEnd!, _color, _stroke));
      }
    }
    _drawing = [];
    _shapeStart = null;
    _shapeEnd = null;
    setState(() {});
  }

  void _onTapUp(Offset local, Size canvas) {
    final n = _norm(local, canvas);
    if (_tool == EditTool.text) {
      _editTextBox(_TextBox(n, '', _color, _textSize, _bold), isNew: true);
    } else if (_tool == EditTool.check) {
      _placeMark(n, '✓', const Color(0xFF16A34A));
    } else if (_tool == EditTool.cross) {
      _placeMark(n, '✕', const Color(0xFFDC2626));
    } else if (_tool == EditTool.dot) {
      _placeMark(n, '●', Colors.black);
    } else if (_tool == EditTool.dash) {
      _placeMark(n, '—', Colors.black);
    } else if (_tool == EditTool.checkbox) {
      _placeMark(n, '☑', Colors.black);
    } else if (_tool == EditTool.eraser) {
      setState(() {
        if (_layer.items.isNotEmpty) {
          _layer.redo.add(_layer.items.removeLast());
          _selected = null;
          _multi.clear();
          _hasUnsavedChanges = true;
        }
      });
    } else if (_tool == EditTool.pan) {
      // Tap in pan mode = try to select an object
      setState(() => _selected = _hitTest(n));
    } else if (_tool == EditTool.select) {
      final hit = _hitTest(n);
      setState(() {
        _multi.clear();
        if (hit != null) _multi.add(hit);
      });
    }
  }

  /// Hit-test in reverse draw order (topmost first): text, shapes, strokes.
  _Annotation? _hitTest(Offset n) {
    for (final item in _layer.items.reversed) {
      if (item is _TextBox) {
        if ((item.pos - n).distance < 0.07) return item;
      } else if (item is _Shape) {
        final r = Rect.fromPoints(item.start, item.end).inflate(0.03);
        if (r.contains(n)) return item;
      } else if (item is _Stroke) {
        // Bounding box of the stroke (works for signatures/drawings).
        var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
        for (final p in item.points) {
          minX = math.min(minX, p.dx);
          minY = math.min(minY, p.dy);
          maxX = math.max(maxX, p.dx);
          maxY = math.max(maxY, p.dy);
        }
        final r = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(0.02);
        if (r.contains(n)) return item;
      }
    }
    return null;
  }

  /// Move a selected object by a normalized delta.
  void _moveSelected(Offset deltaNorm) {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      if (sel is _Shape) {
        sel.start = Offset(
          (sel.start.dx + deltaNorm.dx).clamp(0.0, 1.0),
          (sel.start.dy + deltaNorm.dy).clamp(0.0, 1.0),
        );
        sel.end = Offset(
          (sel.end.dx + deltaNorm.dx).clamp(0.0, 1.0),
          (sel.end.dy + deltaNorm.dy).clamp(0.0, 1.0),
        );
      } else if (sel is _TextBox) {
        sel.pos = Offset(
          (sel.pos.dx + deltaNorm.dx).clamp(0.0, 0.98),
          (sel.pos.dy + deltaNorm.dy).clamp(0.0, 0.98),
        );
      } else if (sel is _Stroke) {
        for (var i = 0; i < sel.points.length; i++) {
          sel.points[i] = Offset(
            (sel.points[i].dx + deltaNorm.dx).clamp(0.0, 1.0),
            (sel.points[i].dy + deltaNorm.dy).clamp(0.0, 1.0),
          );
        }
      }
      _snapSelected();
      _hasUnsavedChanges = true;
    });
  }

  /// Resize the selected object so its bounding box becomes [nb] (normalized).
  /// Works uniformly for every annotation type: stroke points are remapped,
  /// shape endpoints are remapped, and text scales its font size by the height
  /// ratio. Used by the corner resize handles.
  void _scaleSelectedTo(Rect nb) {
    final sel = _selected;
    if (sel == null) return;
    final ob = _boundsOf(sel);
    final ow = ob.width.abs() < 1e-6 ? 1e-6 : ob.width;
    final oh = ob.height.abs() < 1e-6 ? 1e-6 : ob.height;
    double mapX(double x) => nb.left + (x - ob.left) / ow * nb.width;
    double mapY(double y) => nb.top + (y - ob.top) / oh * nb.height;
    setState(() {
      if (sel is _Stroke) {
        for (var i = 0; i < sel.points.length; i++) {
          sel.points[i] = Offset(
            mapX(sel.points[i].dx).clamp(0.0, 1.0),
            mapY(sel.points[i].dy).clamp(0.0, 1.0),
          );
        }
      } else if (sel is _Shape) {
        sel.start = Offset(
          mapX(sel.start.dx).clamp(0.0, 1.0),
          mapY(sel.start.dy).clamp(0.0, 1.0),
        );
        sel.end = Offset(
          mapX(sel.end.dx).clamp(0.0, 1.0),
          mapY(sel.end.dy).clamp(0.0, 1.0),
        );
      } else if (sel is _TextBox) {
        sel.pos = Offset(nb.left.clamp(0.0, 0.98), nb.top.clamp(0.0, 0.98));
        sel.size = (sel.size * (nb.height / oh)).clamp(0.01, 0.2);
      }
      _hasUnsavedChanges = true;
    });
  }

  /// Magnetically snap the selected object's center to the page center (0.5)
  /// when close, and record guide lines to draw. Call inside setState.
  void _snapSelected() {
    final sel = _selected;
    if (sel == null) return;
    const th = 0.014; // snap threshold (normalized)
    double? gx, gy;
    // Vertical guides: page quarters + center (via the object's center)...
    final b = _boundsOf(sel);
    for (final line in const [0.25, 0.5, 0.75]) {
      if ((b.center.dx - line).abs() < th) {
        _moveAnnotation(sel, Offset(line - b.center.dx, 0));
        gx = line;
        break;
      }
    }
    // ...else snap the object's left/right edge to the page margins.
    if (gx == null) {
      final b1 = _boundsOf(sel);
      if (b1.left.abs() < th) {
        _moveAnnotation(sel, Offset(-b1.left, 0));
        gx = 0;
      } else if ((b1.right - 1).abs() < th) {
        _moveAnnotation(sel, Offset(1 - b1.right, 0));
        gx = 1;
      }
    }
    // Horizontal guides: page quarters + center...
    final b2 = _boundsOf(sel);
    for (final line in const [0.25, 0.5, 0.75]) {
      if ((b2.center.dy - line).abs() < th) {
        _moveAnnotation(sel, Offset(0, line - b2.center.dy));
        gy = line;
        break;
      }
    }
    // ...else snap top/bottom edge to the page margins.
    if (gy == null) {
      final b3 = _boundsOf(sel);
      if (b3.top.abs() < th) {
        _moveAnnotation(sel, Offset(0, -b3.top));
        gy = 0;
      } else if ((b3.bottom - 1).abs() < th) {
        _moveAnnotation(sel, Offset(0, 1 - b3.bottom));
        gy = 1;
      }
    }
    _guideX = gx;
    _guideY = gy;
  }

  /// Resize a selected shape by adjusting its end point.
  void _resizeSelected(Offset newEndNorm) {
    final sel = _selected;
    if (sel is _Shape) {
      setState(() {
        sel.end = Offset(newEndNorm.dx.clamp(0.0, 1.0), newEndNorm.dy.clamp(0.0, 1.0));
        _hasUnsavedChanges = true;
      });
    }
  }

  /// Quick, precise font sizing for the selected value so it fits its field.
  /// [factor] > 1 enlarges, < 1 shrinks. Size is normalized to canvas height.
  void _resizeSelectedText(double factor) {
    final sel = _selected;
    if (sel is _TextBox) {
      setState(() {
        sel.size = (sel.size * factor).clamp(0.008, 0.2);
        _hasUnsavedChanges = true;
      });
    }
  }

  void _deleteSelected() {
    if (_selected != null) {
      setState(() {
        _layer.items.remove(_selected);
        _layer.redo.add(_selected!);
        _selected = null;
        _hasUnsavedChanges = true;
      });
    }
  }

  /// Clone an annotation, offset by [d] (normalized). Preserves text styling so
  /// duplicates/pastes look identical to the original.
  _Annotation? _cloneAnnotation(_Annotation sel, double d) {
    if (sel is _Shape) {
      return _Shape(sel.type, Offset(sel.start.dx + d, sel.start.dy + d),
          Offset(sel.end.dx + d, sel.end.dy + d), sel.color, sel.width);
    } else if (sel is _TextBox) {
      return _TextBox(Offset(sel.pos.dx + d, sel.pos.dy + d), sel.text, sel.color,
          sel.size, sel.bold, sel.italic, sel.underline, sel.fontFamily);
    } else if (sel is _Stroke) {
      return _Stroke(sel.points.map((p) => Offset(p.dx + d, p.dy + d)).toList(),
          sel.color, sel.width, sel.highlight);
    }
    return null;
  }

  /// Copy the selected object to an in-editor clipboard (works across pages).
  void _copySelected() {
    final sel = _selected;
    if (sel == null) return;
    _clipboard = _cloneAnnotation(sel, 0);
    setState(() {}); // refresh so the Paste action becomes enabled
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(milliseconds: 900)),
    );
  }

  /// Paste the clipboard object onto the CURRENT page, selected & ready to move.
  void _pasteClipboard() {
    final c = _clipboard;
    if (c == null) return;
    final copy = _cloneAnnotation(c, 0.03);
    if (copy == null) return;
    setState(() {
      _layer.items.add(copy);
      _selected = copy;
      _tool = EditTool.pan;
      _hasUnsavedChanges = true;
    });
  }

  /// Quick colour picker for the selected text value.
  void _pickSelectedTextColor() {
    final sel = _selected;
    if (sel is! _TextBox) return;
    const swatches = <Color>[
      Color(0xFF1B2130), Colors.black, Color(0xFF4C63D2), Color(0xFF2E9E7B),
      Color(0xFFD9636B), Color(0xFFCF9A4E), Color(0xFF7E7BD4), Colors.white,
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Text colour', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final c in swatches)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() {
                          sel.color = c;
                          _hasUnsavedChanges = true;
                        });
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black26),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _duplicateSelected() {
    final sel = _selected;
    if (sel == null) return;
    const d = 0.03; // small offset so the copy is visible
    _Annotation? copy;
    if (sel is _Shape) {
      copy = _Shape(sel.type, Offset(sel.start.dx + d, sel.start.dy + d),
          Offset(sel.end.dx + d, sel.end.dy + d), sel.color, sel.width);
    } else if (sel is _TextBox) {
      copy = _TextBox(Offset(sel.pos.dx + d, sel.pos.dy + d), sel.text, sel.color, sel.size, sel.bold);
    } else if (sel is _Stroke) {
      copy = _Stroke(sel.points.map((p) => Offset(p.dx + d, p.dy + d)).toList(),
          sel.color, sel.width, sel.highlight);
    }
    if (copy != null) {
      setState(() {
        _layer.items.add(copy!);
        _selected = copy;
        _hasUnsavedChanges = true;
      });
    }
  }

  void _bringToFront() {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _layer.items.remove(sel);
      _layer.items.add(sel);
      _hasUnsavedChanges = true;
    });
  }

  void _sendToBack() {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _layer.items.remove(sel);
      _layer.items.insert(0, sel);
      _hasUnsavedChanges = true;
    });
  }

  // ---- Multi-select helpers (E2) ----

  Offset _clampOff(Offset o, [double m = 1.0]) =>
      Offset(o.dx.clamp(0.0, m), o.dy.clamp(0.0, m));

  void _moveAnnotation(_Annotation a, Offset d) {
    if (a is _Shape) {
      a.start = _clampOff(a.start + d);
      a.end = _clampOff(a.end + d);
    } else if (a is _TextBox) {
      a.pos = _clampOff(a.pos + d, 0.98);
    } else if (a is _Stroke) {
      for (var i = 0; i < a.points.length; i++) {
        a.points[i] = _clampOff(a.points[i] + d);
      }
    }
  }

  /// Normalized bounding box of any annotation.
  Rect _boundsOf(_Annotation a) {
    if (a is _Shape) return Rect.fromPoints(a.start, a.end);
    if (a is _TextBox) {
      final w = (a.text.length * a.size * 0.55).clamp(0.02, 1.0);
      return Rect.fromLTWH(a.pos.dx, a.pos.dy, w.toDouble(), a.size * 1.3);
    }
    if (a is _Stroke) {
      var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
      for (final p in a.points) {
        minX = math.min(minX, p.dx);
        minY = math.min(minY, p.dy);
        maxX = math.max(maxX, p.dx);
        maxY = math.max(maxY, p.dy);
      }
      return Rect.fromLTRB(minX, minY, maxX, maxY);
    }
    return Rect.zero;
  }

  _Annotation? _copyAnnotation(_Annotation a, double d) {
    if (a is _Shape) {
      return _Shape(a.type, Offset(a.start.dx + d, a.start.dy + d),
          Offset(a.end.dx + d, a.end.dy + d), a.color, a.width);
    } else if (a is _TextBox) {
      return _TextBox(Offset(a.pos.dx + d, a.pos.dy + d), a.text, a.color, a.size, a.bold);
    } else if (a is _Stroke) {
      return _Stroke(a.points.map((p) => Offset(p.dx + d, p.dy + d)).toList(),
          a.color, a.width, a.highlight);
    }
    return null;
  }

  void _alignMulti(String how) {
    if (_multi.length < 2) return;
    final rects = {for (final a in _multi) a: _boundsOf(a)};
    Rect group = rects.values.first;
    for (final r in rects.values) {
      group = group.expandToInclude(r);
    }
    setState(() {
      for (final a in _multi) {
        final r = rects[a]!;
        double dx = 0, dy = 0;
        switch (how) {
          case 'left':
            dx = group.left - r.left;
            break;
          case 'hcenter':
            dx = group.center.dx - r.center.dx;
            break;
          case 'right':
            dx = group.right - r.right;
            break;
          case 'top':
            dy = group.top - r.top;
            break;
          case 'vcenter':
            dy = group.center.dy - r.center.dy;
            break;
          case 'bottom':
            dy = group.bottom - r.bottom;
            break;
        }
        _moveAnnotation(a, Offset(dx, dy));
      }
      _hasUnsavedChanges = true;
    });
  }

  void _distributeMulti(Axis axis) {
    if (_multi.length < 3) return;
    final list = _multi.toList();
    final rects = {for (final a in list) a: _boundsOf(a)};
    list.sort((p, q) => axis == Axis.horizontal
        ? rects[p]!.center.dx.compareTo(rects[q]!.center.dx)
        : rects[p]!.center.dy.compareTo(rects[q]!.center.dy));
    final first = rects[list.first]!.center;
    final last = rects[list.last]!.center;
    final step = (axis == Axis.horizontal ? (last.dx - first.dx) : (last.dy - first.dy)) /
        (list.length - 1);
    setState(() {
      for (var i = 1; i < list.length - 1; i++) {
        final a = list[i];
        final c = rects[a]!.center;
        if (axis == Axis.horizontal) {
          _moveAnnotation(a, Offset(first.dx + step * i - c.dx, 0));
        } else {
          _moveAnnotation(a, Offset(0, first.dy + step * i - c.dy));
        }
      }
      _hasUnsavedChanges = true;
    });
  }

  void _deleteMulti() {
    setState(() {
      for (final a in _multi) {
        _layer.items.remove(a);
        _layer.redo.add(a);
      }
      _multi.clear();
      _hasUnsavedChanges = true;
    });
  }

  void _duplicateMulti() {
    const d = 0.03;
    final copies = <_Annotation>[];
    for (final a in _multi) {
      final c = _copyAnnotation(a, d);
      if (c != null) copies.add(c);
    }
    setState(() {
      _layer.items.addAll(copies);
      _multi
        ..clear()
        ..addAll(copies);
      _hasUnsavedChanges = true;
    });
  }

  Offset _norm(Offset local, Size canvas) =>
      Offset(local.dx / canvas.width, local.dy / canvas.height);

  /// Add an annotation and reset the redo stack.
  void _pushItem(_Annotation a) {
    _layer.items.add(a);
    _layer.redo.clear();
    _hasUnsavedChanges = true;
  }

  /// Fill & Sign: drop a single glyph (check / cross / dot / dash / checkbox)
  /// as a movable text box at the tapped position. Great for forms.
  void _placeMark(Offset n, String glyph, Color color) {
    setState(() => _pushItem(_TextBox(n, glyph, color, 0.04, false)));
  }

  /// Fill & Sign: place today's date (dd.MM.yyyy) as a movable text box.
  void _placeSignatureDate() {
    final d = DateTime.now();
    final s = '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}.${d.year}';
    setState(() => _pushItem(_TextBox(const Offset(0.5, 0.5), s, _color, _textSize, _bold)));
  }

  // ---- Integrated Smart AI Fill (standalone, no API) ----------------------
  //
  // The full SmartFormFiller engine running directly inside the editor: OCR the
  // current page, detect fields via FormOntology (fuzzy, umlaut-tolerant),
  // resolve values from Profile using multi-signal scoring + checkbox options +
  // date normalization, show review sheet, and place confirmed values. One tap,
  // fully on-device, no second upload or separate screen needed.

  Future<void> _smartFillPage() async {
    final bytes = _pageCache[_current];
    if (bytes == null) return;

    // Offer a choice: fill from saved Profile or upload an info document.
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(l10n.aiFillFromProfile),
                subtitle: Text(l10n.aiFillFromProfileDesc),
                onTap: () => Navigator.pop(ctx, 'profile'),
              ),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: Text(l10n.aiFillFromDoc),
                subtitle: Text(l10n.aiFillFromDocDesc),
                onTap: () => Navigator.pop(ctx, 'doc'),
              ),
            ],
          ),
        );
      },
    );
    if (source == null || !mounted) return;

    setState(() => _detecting = true);
    try {
      // 1) OCR the current page
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final tmpPath = '${dir.path}/smartfill_$stamp.jpg';
      await File(tmpPath).writeAsBytes(bytes);
      final ocrResult = await _ocr.recognize(tmpPath);
      try { await File(tmpPath).delete(); } catch (_) {}

      // 2) Get info: either from an uploaded doc or empty (profile-only)
      List<OcrResult> infoPages = const [];
      if (source == 'doc') {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        );
        final path = picked?.files.first.path;
        if (path != null && mounted) {
          // OCR the info document
          final infoOcr = OcrService();
          try {
            if (path.toLowerCase().endsWith('.pdf')) {
              final infoDoc = await pdfx.PdfDocument.openFile(path);
              try {
                final count = infoDoc.pagesCount < 10 ? infoDoc.pagesCount : 10;
                for (var i = 1; i <= count; i++) {
                  final pg = await infoDoc.getPage(i);
                  try {
                    final le = pg.width > pg.height ? pg.width : pg.height;
                    final sc = le > 1400 ? 1400 / le : 1.0;
                    final img = await pg.render(
                      width: pg.width * sc, height: pg.height * sc,
                      format: pdfx.PdfPageImageFormat.jpeg, backgroundColor: '#FFFFFF',
                    );
                    if (img?.bytes != null) {
                      final p = '${dir.path}/info_${stamp}_$i.jpg';
                      await File(p).writeAsBytes(img!.bytes);
                      infoPages = [...infoPages, await infoOcr.recognize(p)];
                      try { await File(p).delete(); } catch (_) {}
                    }
                  } finally { await pg.close(); }
                }
              } finally { await infoDoc.close(); }
            } else {
              infoPages = [await infoOcr.recognize(path)];
            }
          } finally { await infoOcr.dispose(); }
        }
      }

      // 3) Load profile and run the engine
      await UserProfileService.instance.load();
      final profile = UserProfileService.instance.data;
      final info = SmartFormFiller.extractInfo(infoPages);
      final fields = SmartFormFiller.fillForm([ocrResult], info, profile);

      if (!mounted) return;
      setState(() => _detecting = false);

      if (fields.isEmpty) {
        _showError(AppLocalizations.of(context)!.smartFillNoMatch);
        return;
      }

      // 4) Show review sheet
      final confirmed = await showModalBottomSheet<List<FilledField>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => _EditorReviewSheet(fields: fields),
      );
      if (confirmed == null || confirmed.isEmpty || !mounted) return;

      // 5) Place confirmed values as editable text boxes
      setState(() {
        for (final f in confirmed) {
          if (f.isCheck) {
            _pushItem(_TextBox(
              Offset(f.x, f.y), f.text, Colors.black, 0.03, true));
          } else if (f.isSignature) {
            _pushItem(_TextBox(
              Offset(f.x, f.y), f.text, Colors.black, 0.032, false, true, false, 'serif'));
          } else {
            _pushItem(_TextBox(
              Offset(f.x, f.y), f.text, Colors.black, 0.024, false));
          }
        }
        _tool = EditTool.pan;
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.smartFillPlaced(confirmed.length)),
      ));
    } catch (e) {
      _showError('Smart Fill failed: $e');
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  /// Edit existing text: OCR the current page and show every text line as a
  /// tappable box. Tapping a line covers the original and opens a pre-filled,
  /// editable text box on top — a practical, on-device "edit text" for both
  /// scanned and flat PDFs. (Overlay-based, not glyph-level reflow.)
  Future<void> _scanForEdit() async {
    if (_showEditLines) {
      setState(() => _showEditLines = false);
      return;
    }
    final bytes = _pageCache[_current];
    if (bytes == null) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _detecting = true);
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/edit_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await f.writeAsBytes(bytes);
      final result = await _ocr.recognize(f.path);
      try {
        await f.delete();
      } catch (_) {}
      final lines = result.lines
          .where((l) => l.text.trim().isNotEmpty && l.w > 0.02 && l.h > 0.004)
          .toList();
      setState(() {
        _editLines[_current] = lines;
        _showEditLines = lines.isNotEmpty;
        _tool = EditTool.pan;
      });
      if (!mounted) return;
      if (lines.isEmpty) {
        _showError(l10n.noTextFound);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.tapLineToEdit)));
      }
    } catch (e) {
      _showError(l10n.operationFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  /// Cover an existing OCR line with white and open a pre-filled editable box.
  Future<void> _editExistingLine(OcrLine line) async {
    final double size = (line.h * 0.72).clamp(0.012, 0.08).toDouble();
    setState(() {
      _showEditLines = false;
      _pushItem(_Shape(ShapeType.whiteout, Offset(line.x, line.y),
          Offset(line.x + line.w, line.y + line.h), Colors.white, 1));
    });
    final before = _layer.items.length;
    await _editTextBox(
      _TextBox(Offset(line.x, line.y + line.h * 0.1), line.text.trim(),
          Colors.black, size, false),
      isNew: true,
    );
    // User cancelled -> remove the stray whiteout we added underneath.
    if (_layer.items.length == before &&
        _layer.items.isNotEmpty &&
        _layer.items.last is _Shape &&
        (_layer.items.last as _Shape).type == ShapeType.whiteout) {
      setState(() => _layer.items.removeLast());
    }
  }

  /// Fill & Sign: pick a saved profile value (name, address, ID…) and drop it
  /// as a movable text box. Prompts to set up the profile if none is saved.
  Future<void> _insertProfileField() async {
    final l10n = AppLocalizations.of(context)!;
    await UserProfileService.instance.load();
    final data = UserProfileService.instance.data;
    final entries = UserProfileService.fields
        .where((f) => (data[f.$1] ?? '').trim().isNotEmpty)
        .toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        if (entries.isEmpty) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.badge_outlined, size: 48, color: Theme.of(ctx).colorScheme.outline),
                const SizedBox(height: 12),
                Text(l10n.noProfileData, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                  icon: const Icon(Icons.badge_outlined),
                  label: Text(l10n.setUpProfile),
                ),
              ]),
            ),
          );
        }
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final f in entries)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(data[f.$1]!),
                  subtitle: Text(f.$2),
                  onTap: () {
                    final value = data[f.$1]!;
                    Navigator.pop(ctx);
                    setState(() => _pushItem(
                        _TextBox(const Offset(0.5, 0.5), value, _color, _textSize, _bold)));
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editTextBox(_TextBox box, {bool isNew = false}) async {
    final ctrl = TextEditingController(text: box.text);
    double size = box.size;
    bool bold = box.bold;
    bool italic = box.italic;
    bool underline = box.underline;
    String? font = box.fontFamily;
    Color color = box.color;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isNew ? 'Add Text' : 'Edit Text'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(ctx)!.typeText,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Text(AppLocalizations.of(ctx)!.sizeLabel),
                Expanded(
                  child: Slider(
                    value: size,
                    min: 0.015,
                    max: 0.08,
                    onChanged: (v) => setLocal(() => size = v),
                  ),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(ctx)!.bold,
                  isSelected: bold,
                  icon: const Icon(Icons.format_bold),
                  onPressed: () => setLocal(() => bold = !bold),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(ctx)!.italic,
                  isSelected: italic,
                  icon: const Icon(Icons.format_italic),
                  onPressed: () => setLocal(() => italic = !italic),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(ctx)!.underline,
                  isSelected: underline,
                  icon: const Icon(Icons.format_underlined),
                  onPressed: () => setLocal(() => underline = !underline),
                ),
              ]),
              Row(children: [
                Text(AppLocalizations.of(ctx)!.font),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButton<String?>(
                    value: font,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(value: null, child: Text(AppLocalizations.of(ctx)!.fontDefault)),
                      const DropdownMenuItem(value: 'serif', child: Text('Serif', style: TextStyle(fontFamily: 'serif'))),
                      const DropdownMenuItem(value: 'monospace', child: Text('Mono', style: TextStyle(fontFamily: 'monospace'))),
                    ],
                    onChanged: (v) => setLocal(() => font = v),
                  ),
                ),
              ]),
              Row(
                children: [Colors.red, Colors.blue, Colors.black, Colors.green, Colors.orange, Colors.purple]
                    .map((c) => GestureDetector(
                          onTap: () => setLocal(() => color = c),
                          child: Container(
                            width: 28,
                            height: 28,
                            margin: const EdgeInsets.only(right: 8, top: 4),
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: color == c ? Colors.blueAccent : Colors.grey.shade400,
                                width: color == c ? 3 : 1,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
          actions: [
            if (!isNew)
              TextButton(
                onPressed: () => Navigator.pop(ctx, '__delete__'),
                child: Text(AppLocalizations.of(ctx)!.delete, style: const TextStyle(color: Colors.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(ctx)!.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(AppLocalizations.of(ctx)!.ok)),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      if (result == '__delete__') {
        _layer.items.remove(box);
      } else if (result.isNotEmpty) {
        box.text = result;
        box.color = color;
        box.size = size;
        box.bold = bold;
        box.italic = italic;
        box.underline = underline;
        box.fontFamily = font;
        // Remember last-used style for the next text box.
        _textSize = size;
        _bold = bold;
        _color = color;
        if (isNew) _pushItem(box);
      }
    });
  }

  /// Properties editor for a selected shape (E3): stroke width, color,
  /// fill (rect/oval), and opacity.
  Future<void> _editShapeStyle(_Shape s) async {
    bool filled = s.filled;
    double opacity = s.opacity;
    double width = s.width;
    Color color = s.color;
    final canFill = s.type == ShapeType.rect || s.type == ShapeType.oval;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(AppLocalizations.of(ctx)!.shapeStyle),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              SizedBox(width: 56, child: Text(AppLocalizations.of(ctx)!.width)),
              Expanded(
                child: Slider(value: width, min: 1, max: 14, onChanged: (v) => setLocal(() => width = v)),
              ),
            ]),
            Row(children: [
              SizedBox(width: 56, child: Text(AppLocalizations.of(ctx)!.opacity)),
              Expanded(
                child: Slider(value: opacity, min: 0.1, max: 1, onChanged: (v) => setLocal(() => opacity = v)),
              ),
            ]),
            if (canFill)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(AppLocalizations.of(ctx)!.fill),
                value: filled,
                onChanged: (v) => setLocal(() => filled = v),
              ),
            Row(
              children: [Colors.red, Colors.blue, Colors.black, Colors.green, Colors.orange, Colors.purple]
                  .map((c) => GestureDetector(
                        onTap: () => setLocal(() => color = c),
                        child: Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.only(right: 8, top: 4),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: color == c ? Colors.blueAccent : Colors.grey.shade400,
                              width: color == c ? 3 : 1,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(ctx)!.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.of(ctx)!.ok)),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        s.filled = filled;
        s.opacity = opacity;
        s.width = width;
        s.color = color;
        _hasUnsavedChanges = true;
      });
    }
  }

  void _undo() {
    setState(() {
      if (_layer.items.isNotEmpty) {
        _layer.redo.add(_layer.items.removeLast());
        _selected = null;
        _multi.clear();
        _hasUnsavedChanges = true;
      }
    });
  }

  void _redoAction() {
    setState(() {
      if (_layer.redo.isNotEmpty) {
        _layer.items.add(_layer.redo.removeLast());
        _selected = null;
        _multi.clear();
        _hasUnsavedChanges = true;
      }
    });
  }

  /// Map raw signature-pad points into a normalized [_Stroke] positioned with
  /// its top-left near (x, y) on the page, preserving aspect ratio. Returns
  /// null if the points have no meaningful extent.
  _Stroke? _signatureStrokeAt(List<Offset> pts, double x, double y,
      {double targetW = 0.26}) {
    if (pts.length < 2) return null;
    double minX = pts.first.dx, maxX = minX, minY = pts.first.dy, maxY = minY;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final w = (maxX - minX).abs();
    final h = (maxY - minY).abs();
    if (w < 1e-3 && h < 1e-3) return null;
    final aspect = w == 0 ? 0.4 : (h / w);
    final targetH = (targetW * aspect).clamp(0.02, 0.14).toDouble();
    // Sit the signature slightly above the label baseline so it rests on the line.
    final top = (y - targetH * 0.6).clamp(0.0, 0.97).toDouble();
    final norm = pts.map((p) {
      final nx = w == 0 ? 0.0 : (p.dx - minX) / w;
      final ny = h == 0 ? 0.0 : (p.dy - minY) / h;
      return Offset(
        (x + nx * targetW).clamp(0.0, 1.0).toDouble(),
        (top + ny * targetH).clamp(0.0, 1.0).toDouble(),
      );
    }).toList();
    return _Stroke(norm, Colors.black, 2.5, false);
  }

  Future<void> _addSignature() async {
    // Chooser: draw a new signature, type one, or reuse a saved drawing.
    List<Offset>? points;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.draw),
              title: Text(AppLocalizations.of(ctx)!.drawNewSignature),
              onTap: () => Navigator.pop(ctx, 'new'),
            ),
            ListTile(
              leading: const Icon(Icons.keyboard),
              title: Text(AppLocalizations.of(ctx)!.typeSignature),
              onTap: () => Navigator.pop(ctx, 'type'),
            ),
            if (_savedSignatures.isNotEmpty) const Divider(height: 1),
            ...List.generate(_savedSignatures.length, (i) => ListTile(
                  leading: const Icon(Icons.gesture),
                  title: Text(AppLocalizations.of(ctx)!.savedSignatureN(i + 1)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () {
                      _savedSignatures.removeAt(i);
                      SignatureStore.instance.save(_savedSignatures);
                      Navigator.pop(ctx);
                    },
                  ),
                  onTap: () => Navigator.pop(ctx, 'saved_$i'),
                )),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'type') {
      await _typeSignature();
      return;
    } else if (choice == 'new') {
      points = await _drawSignature();
    } else if (choice.startsWith('saved_')) {
      final idx = int.tryParse(choice.replaceFirst('saved_', ''));
      if (idx != null && idx < _savedSignatures.length) {
        points = _savedSignatures[idx];
      }
    }

    if (points != null && points.length > 1) {
      setState(() {
        _pushItem(_Stroke(
          points!.map((p) => Offset(0.1 + p.dx / 900, 0.7 + p.dy / 900)).toList(),
          Colors.black,
          2.5,
          false,
        ));
      });
    }
  }

  Future<List<Offset>?> _drawSignature() async {
    final points = await Navigator.of(context).push<List<Offset>>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _SignaturePad()),
    );
    if (points != null && points.length > 1) {
      // Ask to save for reuse
      final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(ctx)!.saveThisSignature),
          content: Text(AppLocalizations.of(ctx)!.savedSignaturesReused),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(ctx)!.no)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.of(ctx)!.save)),
          ],
        ),
      );
      if (save == true) {
        _savedSignatures.add(List.from(points));
        SignatureStore.instance.save(_savedSignatures);
      }
    }
    return points;
  }

  /// Rotate the current page image 90° clockwise. The rotation is applied to
  /// the cached bytes (re-encoded) so it appears immediately and exports correctly.
  Future<void> _rotatePage() async {
    final bytes = _pageCache[_current];
    if (bytes == null) return;
    setState(() => _loading = true);
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final original = frame.image;
      final w = original.height;
      final h = original.width;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
      canvas.translate(w.toDouble(), 0);
      canvas.rotate(math.pi / 2);
      canvas.drawImage(original, Offset.zero, Paint());
      original.dispose();
      final picture = recorder.endRecording();
      final rotated = await picture.toImage(w, h);
      final data = await rotated.toByteData(format: ui.ImageByteFormat.png);
      rotated.dispose();
      picture.dispose();
      if (data != null) {
        _pageCache[_current] = data.buffer.asUint8List();
      }
    } catch (e) {
      _showError('Rotate failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---- Export: compose each page off-screen at high resolution ----
  //
  // Pro approach (used by big PDF apps): instead of screenshotting the visible
  // widget (limited to screen resolution and fragile), we re-render each page
  // at a high pixel cap and paint the annotations directly onto an off-screen
  // Canvas. This gives crisp output, is much faster (no per-frame waits), works
  // for pages that aren't on screen, and keeps memory bounded (one page image
  // in flight at a time, disposed immediately).

  static const double _exportMaxEdge = 1800;

  /// True if [s] can be represented with the PDF standard (Latin-1) fonts, so
  /// it can be exported as real, selectable/searchable text rather than pixels.
  /// Other scripts (e.g. Arabic) and special glyphs (✓ ☑ ●) are rasterized
  /// into the page image instead, so they always render correctly.
  bool _isLatin1(String s) {
    for (final c in s.codeUnits) {
      if (c > 0xFF) return false;
    }
    return true;
  }

  /// Convert a Flutter [Color] to a [PdfColor], applying [opacity] as alpha.
  /// Uses bit extraction (no per-channel getters) to keep it version-stable.
  PdfColor _pdfColor(Color c, [double opacity = 1.0]) {
    final v = c.value;
    return PdfColor(
      ((v >> 16) & 0xFF) / 255.0,
      ((v >> 8) & 0xFF) / 255.0,
      (v & 0xFF) / 255.0,
      opacity.clamp(0.0, 1.0).toDouble(),
    );
  }

  /// Build a crisp VECTOR rectangle / whiteout box for export (resolution
  /// independent). Only axis-aligned box shapes are vectorized this way; other
  /// shapes are rasterized in [_composePagePng]. Coordinates are top-left,
  /// matching the on-screen model, so mapping is a direct scale by page size.
  pw.Widget _buildPdfShape(_Shape s, double pageW, double pageH) {
    final left = math.min(s.start.dx, s.end.dx) * pageW;
    final top = math.min(s.start.dy, s.end.dy) * pageH;
    final w = (s.start.dx - s.end.dx).abs() * pageW;
    final h = (s.start.dy - s.end.dy).abs() * pageH;
    // Scale stroke width to the export page like the on-screen renderer does
    // (reference height 1000px).
    final k = pageH / 1000.0;
    if (s.type == ShapeType.whiteout) {
      return pw.Positioned(
        left: left,
        top: top,
        child: pw.Container(
          width: w,
          height: h,
          decoration: pw.BoxDecoration(
            color: const PdfColor(1, 1, 1),
            border: pw.Border.all(
              color: const PdfColor(0.62, 0.62, 0.62),
              width: (k).clamp(0.3, 2.0).toDouble(),
            ),
          ),
        ),
      );
    }
    return pw.Positioned(
      left: left,
      top: top,
      child: pw.Container(
        width: w,
        height: h,
        decoration: pw.BoxDecoration(
          color: s.filled ? _pdfColor(s.color, s.opacity * 0.25) : null,
          border: pw.Border.all(
            color: _pdfColor(s.color, s.opacity),
            width: (s.width * k).clamp(0.3, 40.0).toDouble(),
          ),
        ),
      ),
    );
  }

  Future<String?> _renderToPdfFile() async {
    setState(() => _loading = true);
    try {
      final doc = pw.Document();
      // Standard PDF fonts, built once and reused across pages.
      final fonts = _PdfFonts();
      var rendered = 0;
      for (var i = 0; i < _pageCount; i++) {
        final composed = await _composePagePng(i);
        if (composed == null) {
          // Yield to the event loop so the UI stays responsive on big files.
          await Future<void>.delayed(Duration.zero);
          continue;
        }

        // Page size in points, matching the raster's aspect ratio so the image
        // fills the page exactly (no letterboxing) and normalized annotation
        // coordinates map straight onto the page.
        const longPts = 842.0; // A4 long edge
        final double pageW, pageH;
        if (composed.width >= composed.height) {
          pageW = longPts;
          pageH = longPts * composed.height / composed.width;
        } else {
          pageH = longPts;
          pageW = longPts * composed.width / composed.height;
        }

        final image = pw.MemoryImage(composed.bytes);
        // Axis-aligned box shapes (rectangles + whiteout) are drawn as crisp
        // vectors over the page image, under the text layer.
        final shapes = (_layers[i]?.shapes ?? const <_Shape>[])
            .where((s) =>
                s.type == ShapeType.rect || s.type == ShapeType.whiteout)
            .toList();
        // Latin text is overlaid as REAL, selectable vector text; other scripts
        // and glyphs were already rasterized into the composed page image.
        final texts = (_layers[i]?.texts ?? const <_TextBox>[])
            .where((t) => t.text.isNotEmpty && _isLatin1(t.text))
            .toList();

        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat(pageW, pageH, marginAll: 0),
          build: (_) => pw.SizedBox(
            width: pageW,
            height: pageH,
            child: pw.Stack(
              children: [
                pw.SizedBox(
                  width: pageW,
                  height: pageH,
                  child: pw.Image(image, fit: pw.BoxFit.fill),
                ),
                for (final s in shapes) _buildPdfShape(s, pageW, pageH),
                for (final t in texts)
                  pw.Positioned(
                    left: t.pos.dx * pageW,
                    top: t.pos.dy * pageH,
                    child: pw.SizedBox(
                      width: (pageW * (1 - t.pos.dx)).clamp(1.0, pageW),
                      child: pw.Text(
                        t.text,
                        style: pw.TextStyle(
                          font: fonts.pick(t.fontFamily, t.bold, t.italic),
                          fontSize: t.size * pageH,
                          color: PdfColor.fromInt(t.color.value),
                          decoration: t.underline
                              ? pw.TextDecoration.underline
                              : pw.TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ));
        rendered++;
        // Yield to the event loop so the UI stays responsive on big files.
        await Future<void>.delayed(Duration.zero);
      }

      if (rendered == 0) {
        _showError('Nothing to export');
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final outPath = '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(outPath).writeAsBytes(await doc.save());
      return outPath;
    } catch (e) {
      _showError('Export failed: $e');
      return null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Save the edited PDF, then — right there at save time — offer to share it
  /// or continue straight into another tool (compress, convert, …). The saved
  /// file is handed off so the next tool opens it automatically (no re-picking).
  Future<void> _export() async {
    final outPath = await _renderToPdfFile();
    if (outPath == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
                child: Row(children: [
                  Icon(Icons.check_circle, color: cs.secondary, size: 22),
                  const SizedBox(width: 8),
                  Text('Saved', style: Theme.of(ctx).textTheme.titleMedium),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Do more with your file',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              ),
              ListTile(
                leading: Icon(Icons.ios_share, color: cs.primary),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(ctx);
                  Share.shareXFiles([XFile(outPath)]);
                },
              ),
              _toolTile(ctx, Icons.compress, l10n.toolCompress, outPath, '/tools/compress'),
              _toolTile(ctx, Icons.sync_alt, l10n.convert, outPath, '/tools/convert'),
              _toolTile(ctx, Icons.collections, l10n.toolPdfToImages, outPath, '/tools/pdf-to-images'),
              _toolTile(ctx, Icons.text_snippet, l10n.toolPdfToText, outPath, '/tools/pdf-to-text'),
              const Divider(height: 1),
              _toolTile(ctx, Icons.grid_view, l10n.tools, null, '/tools'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _toolTile(BuildContext ctx, IconData icon, String label,
      String? handoffPath, String route) {
    final cs = Theme.of(ctx).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.primary),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () {
        if (handoffPath != null) ToolHandoff.instance.set(handoffPath);
        Navigator.pop(ctx);
        context.push(route);
      },
    );
  }

  /// Render page [index] at high resolution and paint the strokes, shapes and
  /// non-Latin text of its annotation layer on top, returning the PNG bytes
  /// plus pixel dimensions. Latin text is intentionally NOT drawn here — it is
  /// overlaid as real vector text during export. Everything is disposed before
  /// returning.
  Future<({Uint8List bytes, int width, int height})?> _composePagePng(
      int index) async {
    // 1) Obtain the base image bytes for this page (high-res for PDFs).
    Uint8List? baseBytes;
    if (_doc != null) {
      final page = await _doc!.getPage(index + 1);
      try {
        final longEdge = page.width > page.height ? page.width : page.height;
        final scale = longEdge > _exportMaxEdge ? _exportMaxEdge / longEdge : 1.0;
        final img = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: pdfx.PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        );
        baseBytes = img?.bytes;
      } finally {
        await page.close();
      }
    } else {
      baseBytes = _pageCache[index]; // image file case
    }
    if (baseBytes == null) return null;

    // 2) Decode to a ui.Image so we know the exact pixel dimensions.
    final codec = await ui.instantiateImageCodec(baseBytes);
    final frame = await codec.getNextFrame();
    final base = frame.image;

    try {
      final size = Size(base.width.toDouble(), base.height.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawImage(base, Offset.zero, Paint());
      // Composite strokes + shapes, and any text that can't be a standard PDF
      // font (non-Latin scripts, mark glyphs). Latin text stays vector on export.
      final layer = _layers[index];
      if (layer != null) {
        for (final s in layer.strokes) {
          _AnnDraw.stroke(canvas, size, s.points, s.color, s.width);
        }
        for (final s in layer.shapes) {
          // Axis-aligned boxes are exported as crisp vectors; skip them here.
          if (s.type == ShapeType.rect || s.type == ShapeType.whiteout) {
            continue;
          }
          _AnnDraw.shape(canvas, size, s.type, s.start, s.end, s.color,
              s.width, s.filled, s.opacity);
        }
        for (final t in layer.texts) {
          if (!_isLatin1(t.text)) _AnnDraw.text(canvas, size, t);
        }
      }
      final picture = recorder.endRecording();
      final composed = await picture.toImage(base.width, base.height);
      try {
        final data = await composed.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) return null;
        return (
          bytes: data.buffer.asUint8List(),
          width: base.width,
          height: base.height,
        );
      } finally {
        composed.dispose();
        picture.dispose();
      }
    } finally {
      base.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final bytes = _pageCache[_current];

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final action = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(ctx)!.unsavedChanges),
            content: Text(AppLocalizations.of(ctx)!.unsavedEditsBody),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text(AppLocalizations.of(ctx)!.discard)),
              FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(AppLocalizations.of(ctx)!.saveAndExit)),
            ],
          ),
        );
        if (action == 'discard' && mounted) {
          setState(() => _hasUnsavedChanges = false);
          Navigator.of(context).pop();
        } else if (action == 'save' && mounted) {
          await _export();
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF2B2B2B),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_fileName ?? l10n.toolEditor,
                style: const TextStyle(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_pageCount > 0)
              Text(l10n.pageOfPages(_current + 1, _pageCount),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
        actions: [
          if (bytes != null) ...[
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: l10n.undo,
              onPressed: _layer.items.isEmpty ? null : _undo,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              tooltip: l10n.redo,
              onPressed: _layer.redo.isEmpty ? null : _redoAction,
            ),
            IconButton(
              icon: const Icon(Icons.content_paste),
              tooltip: 'Paste',
              onPressed: _clipboard == null ? null : _pasteClipboard,
            ),
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: l10n.export,
              onPressed: _loading ? null : _export,
            ),
          ],
        ],
      ),
      body: bytes == null
          ? _emptyState(cs)
          : Stack(
              children: [
                Positioned.fill(
                  bottom: 96,
                  child: InteractiveViewer(
                    maxScale: 5,
                    panEnabled: _tool == EditTool.pan,
                    scaleEnabled: _tool == EditTool.pan,
                    child: Center(
                      child: LayoutBuilder(builder: (context, constraints) {
                        return AspectRatio(
                          aspectRatio: 1 / 1.414, // A4-ish
                          child: RepaintBoundary(
                            child: _buildCanvas(bytes),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                if (_loading || _detecting)
                  Positioned.fill(
                    child: ColoredBox(
                      color: const Color(0x66000000),
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const CircularProgressIndicator(),
                          if (_detecting) ...[
                            const SizedBox(height: 12),
                            Text(l10n.readingTheForm, style: const TextStyle(color: Colors.white)),
                          ],
                        ]),
                      ),
                    ),
                  ),
                Positioned(left: 0, right: 0, bottom: 0, child: _toolbar(cs)),
              ],
            ),
      floatingActionButton: bytes == null
          ? null
          : (_pageCount > 1
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 100),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'prev',
                        onPressed: _current > 0 ? () => _goToPage(_current - 1) : null,
                        child: const Icon(Icons.chevron_left),
                      ),
                      const SizedBox(width: 12),
                      FloatingActionButton.small(
                        heroTag: 'next',
                        onPressed: _current < _pageCount - 1 ? () => _goToPage(_current + 1) : null,
                        child: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                )
              : null),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    ),
    );
  }

  Widget _buildCanvas(Uint8List bytes) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final canDragText = _tool == EditTool.pan || _tool == EditTool.text;
      return GestureDetector(
        onTapUp: (d) => _onTapUp(d.localPosition, size),
        onPanStart: (d) => _onPanStart(d.localPosition, size),
        onPanUpdate: (d) => _onPanUpdate(d.localPosition, size),
        onPanEnd: (_) => _onPanEnd(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(bytes, fit: BoxFit.fill),
            CustomPaint(
              painter: _AnnPainter(
                _layer.strokes,
                _layer.shapes,
                _drawing,
                _shapeStart,
                _shapeEnd,
                _shapePreviewType(),
                _color,
                _stroke,
                _tool == EditTool.highlight,
              ),
            ),
            // Detected fields (tap to fill with the right typed input)
            if (_showFields)
              ..._pageFields.map((f) {
                // Color/shape code by type: green square = checkbox, blue circle
                // = radio, amber rounded-rect = text/date/signature.
                final isCheckbox = f.type == FieldType.checkbox;
                final isRadio = f.type == FieldType.radio;
                final base = isCheckbox
                    ? Colors.green
                    : isRadio
                        ? Colors.blue
                        : Colors.amber;
                return Positioned(
                  left: f.rect.left * size.width,
                  top: f.rect.top * size.height,
                  child: GestureDetector(
                    onTap: () => _openFieldInput(f),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 18),
                      width: isCheckbox || isRadio
                          ? (f.rect.width * size.width).clamp(18.0, 40.0)
                          : null,
                      height: (f.rect.height * size.height).clamp(18.0, 60.0),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: base.withOpacity(0.18),
                        border: Border.all(color: base.shade700, width: 1.5),
                        borderRadius: isRadio
                            ? BorderRadius.circular(100)
                            : BorderRadius.circular(4),
                      ),
                      child: Icon(_typeIcon(f.type), size: 14, color: base.shade900),
                    ),
                  ),
                );
              }),
            // Editable text lines (tap a line to replace its text)
            if (_showEditLines)
              ...(_editLines[_current] ?? const <OcrLine>[]).map((line) => Positioned(
                    left: line.x * size.width,
                    top: line.y * size.height,
                    width: (line.w * size.width).clamp(10.0, size.width),
                    height: (line.h * size.height).clamp(12.0, 80.0),
                    child: GestureDetector(
                      onTap: () => _editExistingLine(line),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.14),
                          border: Border.all(color: Colors.blueAccent, width: 1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  )),
            // Snapping guides (E3.4)
            if (_guideX != null)
              Positioned(
                left: _guideX! * size.width,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(width: 1, color: Colors.pinkAccent),
                ),
              ),
            if (_guideY != null)
              Positioned(
                top: _guideY! * size.height,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(height: 1, color: Colors.pinkAccent),
                ),
              ),
            // Multi-select highlights (E2)
            ..._multi.map((a) {
              final r = _boundsOf(a);
              return Positioned(
                left: r.left * size.width,
                top: r.top * size.height,
                width: (r.width * size.width).clamp(6.0, size.width),
                height: (r.height * size.height).clamp(6.0, size.height),
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue, width: 1.5),
                      color: Colors.blue.withOpacity(0.08),
                    ),
                  ),
                ),
              );
            }),
            // Marquee rectangle while dragging in Select mode
            if (_selMode == 'marquee' && _marqueeStart != null && _marqueeEnd != null)
              Positioned.fromRect(
                rect: Rect.fromPoints(
                  Offset(_marqueeStart!.dx * size.width, _marqueeStart!.dy * size.height),
                  Offset(_marqueeEnd!.dx * size.width, _marqueeEnd!.dy * size.height),
                ),
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blueAccent),
                      color: Colors.blue.withOpacity(0.12),
                    ),
                  ),
                ),
              ),
            // Text boxes
            ..._layer.texts.map((t) => Positioned(
                  left: t.pos.dx * size.width,
                  top: t.pos.dy * size.height,
                  child: GestureDetector(
                    onTap: () {
                      if (_tool == EditTool.pan) {
                        setState(() => _selected = t);
                      } else {
                        _editTextBox(t);
                      }
                    },
                    onPanUpdate: canDragText
                        ? (d) => setState(() {
                              t.pos = Offset(
                                (t.pos.dx + d.delta.dx / size.width).clamp(0.0, 0.98),
                                (t.pos.dy + d.delta.dy / size.height).clamp(0.0, 0.98),
                              );
                              _hasUnsavedChanges = true;
                            })
                        : null,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        border: _selected == t
                            ? Border.all(color: Colors.blue, width: 2)
                            : null,
                      ),
                      child: Text(
                        t.text,
                        style: TextStyle(
                          color: t.color,
                          fontSize: t.size * size.height,
                          fontWeight: t.bold ? FontWeight.w800 : FontWeight.w500,
                          fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
                          decoration: t.underline ? TextDecoration.underline : TextDecoration.none,
                          decorationColor: t.color,
                          fontFamily: t.fontFamily,
                        ),
                      ),
                    ),
                  ),
                )),
            // Unified selection: bounding box + corner resize handles that work
            // for ANY object (signature/stroke, text, rectangle, line, arrow,
            // oval). Drag the object body to move; drag a handle to resize.
            if (_selected != null) ...[
              _selectionBox(size, _boundsOf(_selected!)),
              _scaleHandle(size, bottomRight: false),
              _scaleHandle(size, bottomRight: true),
            ],
            // Selection action bar (appears when something is selected)
            if (_selected != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_selected is _TextBox) ...[
                      _miniBtn(Icons.edit, AppLocalizations.of(context)!.editText, () => _editTextBox(_selected as _TextBox)),
                      const SizedBox(width: 10),
                      _miniBtn(Icons.text_decrease, 'A−', () => _resizeSelectedText(0.9)),
                      const SizedBox(width: 10),
                      _miniBtn(Icons.text_increase, 'A+', () => _resizeSelectedText(1.1)),
                      const SizedBox(width: 10),
                      _miniBtn(Icons.palette_outlined, 'Colour', _pickSelectedTextColor),
                      const SizedBox(width: 10),
                    ],
                    if (_selected is _Shape) ...[
                      _miniBtn(Icons.tune, AppLocalizations.of(context)!.style, () => _editShapeStyle(_selected as _Shape)),
                      const SizedBox(width: 10),
                    ],
                    _miniBtn(Icons.content_copy, 'Copy', _copySelected),
                    const SizedBox(width: 10),
                    _miniBtn(Icons.copy_all, AppLocalizations.of(context)!.duplicate, _duplicateSelected),
                    const SizedBox(width: 10),
                    _miniBtn(Icons.flip_to_front, AppLocalizations.of(context)!.bringToFront, _bringToFront),
                    const SizedBox(width: 10),
                    _miniBtn(Icons.flip_to_back, AppLocalizations.of(context)!.sendToBack, _sendToBack),
                    const SizedBox(width: 10),
                    _miniBtn(Icons.delete_outline, AppLocalizations.of(context)!.delete, _deleteSelected),
                    const SizedBox(width: 10),
                    _miniBtn(Icons.close, AppLocalizations.of(context)!.deselect, () => setState(() => _selected = null)),
                  ]),
                ),
              ),
            // Multi-select action bar (E2): align / distribute / bulk actions
            if (_multi.isNotEmpty)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      Text(AppLocalizations.of(context)!.nSelected(_multi.length),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      _miniBtn(Icons.align_horizontal_left, AppLocalizations.of(context)!.alignLeft, () => _alignMulti('left')),
                      const SizedBox(width: 12),
                      _miniBtn(Icons.align_horizontal_center, AppLocalizations.of(context)!.alignCenter, () => _alignMulti('hcenter')),
                      const SizedBox(width: 12),
                      _miniBtn(Icons.align_horizontal_right, AppLocalizations.of(context)!.alignRight, () => _alignMulti('right')),
                      const SizedBox(width: 12),
                      _miniBtn(Icons.align_vertical_top, AppLocalizations.of(context)!.alignTop, () => _alignMulti('top')),
                      const SizedBox(width: 12),
                      _miniBtn(Icons.align_vertical_center, AppLocalizations.of(context)!.alignMiddle, () => _alignMulti('vcenter')),
                      const SizedBox(width: 12),
                      _miniBtn(Icons.align_vertical_bottom, AppLocalizations.of(context)!.alignBottom, () => _alignMulti('bottom')),
                      const SizedBox(width: 12),
                      _miniBtn(Icons.horizontal_distribute, AppLocalizations.of(context)!.distributeH, () => _distributeMulti(Axis.horizontal)),
                      const SizedBox(width: 12),
                      _miniBtn(Icons.vertical_distribute, AppLocalizations.of(context)!.distributeV, () => _distributeMulti(Axis.vertical)),
                      const SizedBox(width: 12),
                      _miniBtn(Icons.copy_all, AppLocalizations.of(context)!.duplicate, _duplicateMulti),
                      const SizedBox(width: 12),
                      _miniBtn(Icons.delete_outline, AppLocalizations.of(context)!.delete, _deleteMulti),
                      const SizedBox(width: 12),
                      _miniBtn(Icons.close, AppLocalizations.of(context)!.deselect, () => setState(() => _multi.clear())),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _miniBtn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      );

  /// The blue selection outline drawn around the currently selected object of
  /// any type. [b] is the object's normalized bounding box.
  Widget _selectionBox(Size size, Rect b) {
    return Positioned(
      left: b.left * size.width - 3,
      top: b.top * size.height - 3,
      width: (b.width * size.width + 6).clamp(8.0, size.width),
      height: (b.height * size.height + 6).clamp(8.0, size.height),
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blueAccent, width: 1.5),
          ),
        ),
      ),
    );
  }

  /// A draggable corner handle that resizes the selected object (any type) by
  /// its bounding box. [bottomRight] chooses which corner; the opposite corner
  /// stays anchored. Recomputes from the live bounds each frame so scaling is
  /// stable as the object changes size.
  Widget _scaleHandle(Size size, {required bool bottomRight}) {
    final sel = _selected;
    if (sel == null) return const SizedBox.shrink();
    final b = _boundsOf(sel);
    final hx = (bottomRight ? b.right : b.left) * size.width;
    final hy = (bottomRight ? b.bottom : b.top) * size.height;
    return Positioned(
      left: hx - 15,
      top: hy - 15,
      child: GestureDetector(
        onPanUpdate: (d) {
          final cur = _boundsOf(sel);
          final dxN = d.delta.dx / size.width;
          final dyN = d.delta.dy / size.height;
          final Rect nb = bottomRight
              ? Rect.fromLTRB(cur.left, cur.top, cur.right + dxN, cur.bottom + dyN)
              : Rect.fromLTRB(cur.left + dxN, cur.top + dyN, cur.right, cur.bottom);
          // Keep a sane minimum so the object never collapses to nothing.
          if (nb.width < 0.02 || nb.height < 0.01) return;
          _scaleSelectedTo(nb);
        },
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.blueAccent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
          ),
          child: Icon(
            bottomRight ? Icons.open_in_full : Icons.close_fullscreen,
            size: 12,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  ShapeType? _shapePreviewType() {
    switch (_tool) {
      case EditTool.line:
        return ShapeType.line;
      case EditTool.arrow:
        return ShapeType.arrow;
      case EditTool.rect:
        return ShapeType.rect;
      case EditTool.oval:
        return ShapeType.oval;
      case EditTool.whiteout:
        return ShapeType.whiteout;
      default:
        return null;
    }
  }

  Widget _emptyState(ColorScheme cs) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.draw_outlined, size: 72, color: Colors.white38),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.openPdfOrImageToEdit,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white70)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loading ? null : _pick,
              icon: const Icon(Icons.folder_open),
              label: Text(AppLocalizations.of(context)!.chooseFile),
            ),
          ],
        ),
      );

  Widget _toolbar(ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    final showStyle = _tool == EditTool.draw ||
        _tool == EditTool.highlight ||
        _tool == EditTool.text ||
        _isShape;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(children: [
                _actionBtn(Icons.auto_fix_high, l10n.autoFill,
                    _detecting ? () {} : _autoFill, cs),
                _actionBtn(Icons.psychology, l10n.aiFill,
                    _detecting ? () {} : _smartFillPage, cs),
                _actionBtn(_showEditLines ? Icons.text_fields : Icons.text_format,
                    l10n.editTextTool, _detecting ? () {} : _scanForEdit, cs),
                if (_pageFields.isNotEmpty)
                  _actionBtn(_showFields ? Icons.visibility_off : Icons.visibility,
                      _showFields ? l10n.toolHide : l10n.toolFields,
                      () => setState(() => _showFields = !_showFields), cs),
                _toolBtn(Icons.pan_tool_alt, l10n.toolMove, EditTool.pan, cs),
                // --- Fill & Sign (form marks) ---
                _actionBtn(Icons.gesture, l10n.toolSign, _addSignature, cs),
                _actionBtn(Icons.event_available, l10n.signatureDate, _placeSignatureDate, cs),
                _actionBtn(Icons.badge_outlined, l10n.myProfile, _insertProfileField, cs),
                _toolBtn(Icons.check, l10n.markCheck, EditTool.check, cs),
                _toolBtn(Icons.close, l10n.markCross, EditTool.cross, cs),
                _toolBtn(Icons.check_box_outlined, l10n.markCheckbox, EditTool.checkbox, cs),
                _toolBtn(Icons.fiber_manual_record, l10n.markDot, EditTool.dot, cs),
                _toolBtn(Icons.remove, l10n.markDash, EditTool.dash, cs),
                // --- Text & drawing ---
                _toolBtn(Icons.title, l10n.toolText, EditTool.text, cs),
                _toolBtn(Icons.edit, l10n.toolDraw, EditTool.draw, cs),
                _toolBtn(Icons.highlight, l10n.toolHighlight, EditTool.highlight, cs),
                _toolBtn(Icons.horizontal_rule, l10n.toolLine, EditTool.line, cs),
                _toolBtn(Icons.north_east, l10n.toolArrow, EditTool.arrow, cs),
                _toolBtn(Icons.crop_square, l10n.toolBox, EditTool.rect, cs),
                _toolBtn(Icons.circle_outlined, l10n.toolOval, EditTool.oval, cs),
                _toolBtn(Icons.format_color_fill, l10n.toolWhiteout, EditTool.whiteout, cs),
                _toolBtn(Icons.cleaning_services, l10n.toolEraser, EditTool.eraser, cs),
                _actionBtn(Icons.rotate_right, l10n.rotate, _rotatePage, cs),
                _actionBtn(Icons.folder_open, l10n.toolOpen, _pick, cs),
              ]),
            ),
            if (showStyle)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 10, right: 10),
                child: Row(children: [
                  ...[Colors.red, Colors.blue, Colors.black, Colors.green, Colors.orange, Colors.purple]
                      .map((c) => GestureDetector(
                            onTap: () => setState(() => _color = c),
                            child: Container(
                              width: 26,
                              height: 26,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: _color == c ? cs.primary : Colors.grey.shade400,
                                    width: _color == c ? 3 : 1),
                              ),
                            ),
                          )),
                  if (_tool == EditTool.draw || _isShape)
                    Expanded(
                      child: Slider(
                        value: _stroke,
                        min: 1,
                        max: 12,
                        onChanged: (v) => setState(() => _stroke = v),
                      ),
                    ),
                  if (_tool == EditTool.text) ...[
                    Expanded(
                      child: Slider(
                        value: _textSize,
                        min: 0.015,
                        max: 0.08,
                        onChanged: (v) => setState(() => _textSize = v),
                      ),
                    ),
                    IconButton(
                      tooltip: AppLocalizations.of(context)!.bold,
                      isSelected: _bold,
                      icon: const Icon(Icons.format_bold),
                      onPressed: () => setState(() => _bold = !_bold),
                    ),
                  ],
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _toolBtn(IconData icon, String label, EditTool tool, ColorScheme cs) {
    final active = _tool == tool;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => setState(() => _tool = tool),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? cs.primaryContainer : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 22, color: active ? cs.primary : cs.onSurface),
            Text(label, style: TextStyle(fontSize: 10, color: active ? cs.primary : cs.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 22, color: cs.onSurface),
            Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

/// A lightweight review sheet for the editor's integrated Smart Fill.
/// Shows matched fields with checkboxes and edit, returns confirmed list.
class _EditorReviewSheet extends StatefulWidget {
  final List<FilledField> fields;
  const _EditorReviewSheet({required this.fields});

  @override
  State<_EditorReviewSheet> createState() => _EditorReviewSheetState();
}

class _EditorReviewSheetState extends State<_EditorReviewSheet> {
  late List<bool> _checked;
  late List<FilledField> _fields;

  @override
  void initState() {
    super.initState();
    _fields = List.of(widget.fields);
    _checked = List.filled(_fields.length, true);
  }

  void _editField(int i) async {
    final ctrl = TextEditingController(text: _fields[i].text);
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_fields[i].field.isNotEmpty ? _fields[i].field : l10n.editText),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: l10n.typeHere,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(l10n.ok)),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      setState(() => _fields[i] = _fields[i].withText(result.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final count = _checked.where((c) => c).length;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Icon(Icons.psychology, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.reviewBeforePlacing,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(l10n.editAnyValue,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _fields.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final f = _fields[i];
                  return ListTile(
                    leading: Checkbox(
                      value: _checked[i],
                      onChanged: (v) =>
                          setState(() => _checked[i] = v ?? false),
                    ),
                    title: Text(
                      f.field.isNotEmpty ? f.field : f.anchor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _checked[i] ? cs.onSurface : cs.outline,
                      ),
                    ),
                    subtitle: Text(
                      f.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: _checked[i] ? cs.primary : cs.outline,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (f.uncertain)
                          Tooltip(
                            message: l10n.smartFillUncertain,
                            child: Icon(Icons.warning_amber_rounded,
                                size: 18, color: cs.error),
                          ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: l10n.editText,
                          onPressed: _checked[i] ? () => _editField(i) : null,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: count > 0
                    ? () {
                        final result = <FilledField>[];
                        for (var i = 0; i < _fields.length; i++) {
                          if (_checked[i]) result.add(_fields[i]);
                        }
                        Navigator.pop(context, result);
                      }
                    : null,
                icon: const Icon(Icons.check),
                label: Text(l10n.placeNValues(count)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 14 built-in PDF standard fonts, created once and reused across pages
/// during export. Standard fonts keep the exported text selectable/searchable
/// without bundling any TTF assets (Latin-1 coverage only — non-Latin text is
/// rasterized into the page image instead).
class _PdfFonts {
  final pw.Font helv = pw.Font.helvetica();
  final pw.Font helvB = pw.Font.helveticaBold();
  final pw.Font helvO = pw.Font.helveticaOblique();
  final pw.Font helvBO = pw.Font.helveticaBoldOblique();
  final pw.Font times = pw.Font.times();
  final pw.Font timesB = pw.Font.timesBold();
  final pw.Font timesI = pw.Font.timesItalic();
  final pw.Font timesBI = pw.Font.timesBoldItalic();
  final pw.Font cour = pw.Font.courier();
  final pw.Font courB = pw.Font.courierBold();
  final pw.Font courO = pw.Font.courierOblique();
  final pw.Font courBO = pw.Font.courierBoldOblique();

  /// Pick the standard font matching the editor's [family] ('serif' -> Times,
  /// 'monospace' -> Courier, else Helvetica) and bold/italic style.
  pw.Font pick(String? family, bool bold, bool italic) {
    switch (family) {
      case 'serif':
        return bold ? (italic ? timesBI : timesB) : (italic ? timesI : times);
      case 'monospace':
        return bold ? (italic ? courBO : courB) : (italic ? courO : cour);
      default:
        return bold ? (italic ? helvBO : helvB) : (italic ? helvO : helv);
    }
  }
}

/// Shared, resolution-independent drawing used by BOTH the on-screen painter
/// and the off-screen export compositor, so the exported PDF looks exactly
/// like what the user sees. Line/arrow/text sizes scale with the canvas height
/// (normalized to a 1000px reference) so a stroke keeps the same relative
/// thickness whether drawn on a phone screen or a 1800px export page.
class _AnnDraw {
  static const double _refHeight = 1000.0;

  static void stroke(Canvas canvas, Size size, List<Offset> pts, Color color, double width) {
    if (pts.length < 2) return;
    final k = size.height / _refHeight;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(pts[0].dx * size.width, pts[0].dy * size.height);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx * size.width, pts[i].dy * size.height);
    }
    canvas.drawPath(path, paint);
  }

  static void shape(Canvas canvas, Size size, ShapeType type, Offset a, Offset b, Color color, double width,
      [bool filled = false, double opacity = 1.0]) {
    final k = size.height / _refHeight;
    final p1 = Offset(a.dx * size.width, a.dy * size.height);
    final p2 = Offset(b.dx * size.width, b.dy * size.height);
    final effColor = color.withOpacity((color.opacity * opacity).clamp(0.0, 1.0));
    final paint = Paint()
      ..color = effColor
      ..strokeWidth = width * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = effColor.withOpacity((effColor.opacity * 0.25).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;

    switch (type) {
      case ShapeType.rect:
        if (filled) canvas.drawRect(Rect.fromPoints(p1, p2), fillPaint);
        canvas.drawRect(Rect.fromPoints(p1, p2), paint);
        break;
      case ShapeType.line:
        canvas.drawLine(p1, p2, paint);
        break;
      case ShapeType.arrow:
        canvas.drawLine(p1, p2, paint);
        _arrowHead(canvas, p1, p2, paint, k);
        break;
      case ShapeType.oval:
        if (filled) canvas.drawOval(Rect.fromPoints(p1, p2), fillPaint);
        canvas.drawOval(Rect.fromPoints(p1, p2), paint);
        break;
      case ShapeType.whiteout:
        // Filled white rectangle — covers/redacts content underneath.
        final fill = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawRect(Rect.fromPoints(p1, p2), fill);
        // Thin border so you can see it while editing.
        final border = Paint()
          ..color = Colors.grey.shade400
          ..strokeWidth = 1 * k
          ..style = PaintingStyle.stroke;
        canvas.drawRect(Rect.fromPoints(p1, p2), border);
        break;
    }
  }

  static void _arrowHead(Canvas canvas, Offset from, Offset to, Paint paint, double k) {
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    final headLen = 18.0 * k;
    const headAngle = math.pi / 7;
    final p1 = Offset(
      to.dx - headLen * math.cos(angle - headAngle),
      to.dy - headLen * math.sin(angle - headAngle),
    );
    final p2 = Offset(
      to.dx - headLen * math.cos(angle + headAngle),
      to.dy - headLen * math.sin(angle + headAngle),
    );
    canvas.drawLine(to, p1, paint);
    canvas.drawLine(to, p2, paint);
  }

  static void text(Canvas canvas, Size size, _TextBox t) {
    if (t.text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: t.text,
        style: TextStyle(
          color: t.color,
          fontSize: t.size * size.height,
          fontWeight: t.bold ? FontWeight.w800 : FontWeight.w500,
          fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
          decoration: t.underline ? TextDecoration.underline : TextDecoration.none,
          decorationColor: t.color,
          fontFamily: t.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * (1 - t.pos.dx));
    tp.paint(canvas, Offset(t.pos.dx * size.width, t.pos.dy * size.height));
  }

  /// Paint an entire page layer (strokes, shapes, text) onto [canvas].
  static void layer(Canvas canvas, Size size, _PageLayer? layer) {
    if (layer == null) return;
    for (final s in layer.strokes) {
      stroke(canvas, size, s.points, s.color, s.width);
    }
    for (final s in layer.shapes) {
      shape(canvas, size, s.type, s.start, s.end, s.color, s.width, s.filled, s.opacity);
    }
    for (final t in layer.texts) {
      text(canvas, size, t);
    }
  }
}

/// On-screen painter for freehand strokes, shapes, and live previews.
/// Text boxes are drawn as draggable widgets, so they are not painted here.
class _AnnPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final List<_Shape> shapes;
  final List<Offset> current;
  final Offset? shapeStart;
  final Offset? shapeEnd;
  final ShapeType? shapeType;
  final Color curColor;
  final double curWidth;
  final bool curHighlight;

  _AnnPainter(
    this.strokes,
    this.shapes,
    this.current,
    this.shapeStart,
    this.shapeEnd,
    this.shapeType,
    this.curColor,
    this.curWidth,
    this.curHighlight,
  );

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _AnnDraw.stroke(canvas, size, s.points, s.color, s.width);
    }
    for (final s in shapes) {
      _AnnDraw.shape(canvas, size, s.type, s.start, s.end, s.color, s.width, s.filled, s.opacity);
    }
    if (current.length > 1) {
      _AnnDraw.stroke(canvas, size, current,
          curHighlight ? curColor.withOpacity(0.35) : curColor, curHighlight ? 16 : curWidth);
    }
    if (shapeType != null && shapeStart != null && shapeEnd != null) {
      _AnnDraw.shape(canvas, size, shapeType!, shapeStart!, shapeEnd!, curColor, curWidth);
    }
  }

  @override
  bool shouldRepaint(covariant _AnnPainter old) => true;
}

/// Full-screen signature capture pad.
class _SignaturePad extends StatefulWidget {
  const _SignaturePad();
  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final List<Offset> _points = [];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.signHere),
        actions: [
          TextButton(onPressed: () => setState(() => _points.clear()), child: Text(AppLocalizations.of(context)!.clear)),
          FilledButton(
              onPressed: () => Navigator.pop(
                  context, _points.where((p) => p.isFinite).toList()),
              child: Text(AppLocalizations.of(context)!.done)),
          const SizedBox(width: 8),
        ],
      ),
      body: GestureDetector(
        onPanUpdate: (d) => setState(() => _points.add(d.localPosition)),
        onPanEnd: (_) => _points.add(Offset.infinite),
        child: CustomPaint(painter: _SigPainter(_points), size: Size.infinite),
      ),
    );
  }
}

class _SigPainter extends CustomPainter {
  final List<Offset> points;
  _SigPainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < points.length - 1; i++) {
      if (points[i] != Offset.infinite && points[i + 1] != Offset.infinite) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SigPainter old) => true;
}
