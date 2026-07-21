import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:share_plus/share_plus.dart';

import '../../../core/services/ocr_service.dart';
import 'package:ai_pdf/features/editor/application/editor_controller.dart';
import 'package:ai_pdf/features/editor/data/editor_page_render_service.dart';
import 'package:ai_pdf/features/editor/data/annotation_persistence_service.dart';
import 'package:ai_pdf/features/editor/data/page_preloader_service.dart';
import 'package:ai_pdf/features/editor/data/revision_history_service.dart';
import 'package:ai_pdf/features/editor/data/form_profile_service.dart';
import 'package:ai_pdf/features/editor/data/export_settings_service.dart';
import 'package:ai_pdf/features/editor/data/cross_field_logic_service.dart';
import 'package:ai_pdf/features/editor/data/editor_export_service.dart';
import 'package:ai_pdf/features/editor/data/editor_field_input_service.dart';
import 'package:ai_pdf/features/editor/data/editor_annotation_factory_service.dart';
import 'package:ai_pdf/features/editor/data/editor_canvas_interaction_service.dart';
import 'package:ai_pdf/features/editor/data/editor_hit_test_service.dart';
import 'package:ai_pdf/features/editor/data/editor_annotation_edit_service.dart';
import 'package:ai_pdf/features/editor/data/editor_profile_auto_fill_service.dart';
import 'package:ai_pdf/features/editor/data/editor_profile_insert_service.dart';
import 'package:ai_pdf/features/editor/data/editor_tap_tool_service.dart';
import 'package:ai_pdf/features/editor/data/editor_document_service.dart';
import 'package:ai_pdf/features/editor/data/editor_file_picker_service.dart';
import 'package:ai_pdf/features/editor/data/editor_page_transform_service.dart';
import 'package:ai_pdf/features/editor/data/editor_smart_fill_service.dart';
import 'package:ai_pdf/features/editor/data/editor_existing_text_service.dart';
import 'package:ai_pdf/features/editor/data/editor_annotation_apply_service.dart';
import 'package:ai_pdf/features/editor/data/editor_text_scan_service.dart';
import 'package:ai_pdf/features/editor/data/editor_initial_fields_service.dart';
import 'package:ai_pdf/features/editor/data/editor_signature_insert_service.dart';
import 'package:ai_pdf/features/editor/data/editor_signature_flow_service.dart';
import 'package:ai_pdf/features/editor/data/ocr_field_detection_service.dart';
import 'package:ai_pdf/features/editor/data/signature_repository.dart';
import 'package:ai_pdf/features/editor/domain/entities/detected_field.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/services/annotation_bounds_service.dart';
import 'package:ai_pdf/features/editor/domain/services/selection_service.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/signature_pad_sheet.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_screen_body.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_document_viewport.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_profile_field_picker_sheet.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_text_color_picker_sheet.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_export_actions_sheet.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_smart_fill_source_sheet.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_mark_choice_sheet.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_guided_fill_dialog.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_signature_picker_sheet.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_smart_fill_review_sheet.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_value_prompt_dialog.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_shape_style_dialog.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_text_dialog.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_toolbar.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/inline_text_editor.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_top_bar.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_unsaved_changes_dialog.dart';
import '../../../core/services/tool_handoff.dart';
import '../../../core/services/user_profile_service.dart';
import '../../profile/presentation/profile_screen.dart';
import '../models/filled_field.dart';

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
  static const int _renderMaxEdge = 2400;
  static const int _maxCachedPages = 3;

  pdfx.PdfDocument? _doc;
  final Map<int, Uint8List> _pageCache = {}; // page index -> jpeg bytes
  final Map<int, PageLayer> _layers = {};
  final EditorController _editorController = EditorController();

  int get _pageCount => _editorController.state.pageCount;
  set _pageCount(int value) => _editorController.setPageCount(value);

  int get _current => _editorController.state.currentPage;
  set _current(int value) => _editorController.setCurrentPage(value);

  bool get _loading => _editorController.state.loading;
  set _loading(bool value) => _editorController.setLoading(value);

  String? get _fileName => _editorController.state.fileName;
  set _fileName(String? value) =>
      _editorController.setFile(filePath: _editorController.state.filePath, fileName: value);

  bool get _hasUnsavedChanges => _editorController.state.hasUnsavedChanges;
  set _hasUnsavedChanges(bool value) => _editorController.setUnsavedChanges(value);

  EditTool _tool = EditTool.draw;
  Color _color = Colors.red;
  double _stroke = 3;
  double _textSize = 0.032; // normalized to page height
  bool _bold = false;

  List<Offset> _drawing = [];
  Offset? _shapeStart; // live shape preview (normalized)
  Offset? _shapeEnd;

  // --- Selection state ---
  EditorAnnotation? _selected; // currently selected annotation (for move/resize)
  EditorAnnotation? _clipboard; // copied object, pasteable onto any page
  Offset? _dragOffset; // offset during move

  // --- Snapping guides (E3.4) ---
  double? _guideX; // normalized x for a vertical alignment guide
  double? _guideY; // normalized y for a horizontal alignment guide

  // --- Multi-select (E2) ---
  final Set<EditorAnnotation> _multi = {};
  Offset? _marqueeStart;
  Offset? _marqueeEnd;
  String _selMode = 'none'; // 'marquee' | 'move'
  Offset? _selDragLast;

  // --- Smart field detection (E1) ---
  final OcrService _ocr = OcrService();
  final SignatureRepository _signatureRepo = const SignatureRepository();
  final OcrFieldDetectionService _fieldDetection = const OcrFieldDetectionService();
  final EditorPageRenderService _pageRender = const EditorPageRenderService();
  final AnnotationPersistenceService _persistence = const AnnotationPersistenceService();
  final PagePreloaderService _preloader = const PagePreloaderService();
  final RevisionHistoryService _revisionHistory = const RevisionHistoryService();
  final FormProfileService _formProfiles = const FormProfileService();
  final ExportSettingsService _exportSettings = const ExportSettingsService();
  final CrossFieldLogicService _crossField = const CrossFieldLogicService();
  final EditorFieldInputService _fieldInput = const EditorFieldInputService();
  final EditorAnnotationFactoryService _annotationFactory = const EditorAnnotationFactoryService();
  final EditorCanvasInteractionService _canvasInteraction = const EditorCanvasInteractionService();
  final EditorHitTestService _hitTestService = const EditorHitTestService();
  final EditorProfileAutoFillService _profileAutoFill = const EditorProfileAutoFillService();
  final EditorProfileInsertService _profileInsert = const EditorProfileInsertService();
  final EditorTapToolService _tapTools = const EditorTapToolService();
  final EditorAnnotationEditService _annotationEdit = const EditorAnnotationEditService();
  final EditorSignatureFlowService _signatureFlow = const EditorSignatureFlowService();
  final EditorExportService _exportService = const EditorExportService();
  final AnnotationBoundsService _bounds = const AnnotationBoundsService();
  final SelectionService _selection = const SelectionService();
  final EditorDocumentService _documentService = const EditorDocumentService();
  final EditorInitialFieldsService _initialFields = const EditorInitialFieldsService();
  final EditorSignatureInsertService _signatureInsert = const EditorSignatureInsertService();
  final EditorFilePickerService _filePicker = const EditorFilePickerService();
  final EditorPageTransformService _pageTransform = const EditorPageTransformService();
  final EditorTextScanService _textScan = const EditorTextScanService();
  final EditorSmartFillService _smartFill = const EditorSmartFillService();
  final EditorExistingTextService _existingText = const EditorExistingTextService();
  final EditorAnnotationApplyService _annotationApply = const EditorAnnotationApplyService();
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
      _signatureRepo.loadSavedSignatures().then((sigs) {
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
    _editorController.dispose();
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
      final detected = await _fieldDetection.detectFieldsFromPageBytes(
        bytes: bytes,
        ocr: _ocr,
      );
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
  Future<void> _openFieldInput(DetectedField field) async {
    if (field.type == FieldType.checkbox) {
      final mark = await _chooseCheckMark();
      if (mark == null) return;
      final annotation = _fieldInput.buildCheckboxAnnotation(field, mark);
      setState(() {
        _pushItem(annotation);
        _selected = annotation;
        _tool = EditTool.pan;
      });
      return;
    }

    if (field.type == FieldType.radio) {
      final annotation = _fieldInput.buildRadioAnnotation(field);
      setState(() {
        _pushItem(annotation);
        _selected = annotation;
        _tool = EditTool.pan;
      });
      return;
    }

    if (field.type == FieldType.signature) {
      await _addSignature();
      return;
    }

    final placement = _fieldInput.buildTextPlacement(field);

    if (field.type == FieldType.date) {
      final d = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
        helpText: placement.title.isEmpty ? 'Select date' : placement.title,
      );
      if (d != null) {
        _placeValue(placement.pos, placement.size, _fieldInput.formatDate(d));
      }
      return;
    }

    final val = await _promptValue(
      placement.title.isEmpty ? 'Enter value' : placement.title,
      _fieldInput.keyboardTypeFor(field.type),
      field.type,
    );
    if (val != null && val.trim().isNotEmpty) {
      final v = val.trim();
      final fitted = _fieldInput.fitTextSize(
        v,
        placement.size,
        (0.98 - placement.pos.dx).clamp(0.05, 1.0).toDouble(),
      );
      _placeValue(placement.pos, fitted, v);
      _offerReplicate(field, v);
    }
  }

  void _placeValue(Offset pos, double size, String text) {
    final tb = _annotationFactory.textAt(pos, size, text, color: Colors.black);
    setState(() {
      _editorController.pushAnnotation(_layer, tb);
      _selected = tb;
      _tool = EditTool.pan;
    });
  }

  /// Quick chooser shown when a checkbox field is tapped: check (correct) or
  /// cross (wrong). Returns the chosen glyph, or null if dismissed.
  Future<String?> _chooseCheckMark() {
    return showEditorMarkChoiceSheet(context);
  }

  /// After filling a labelled field, offer to fill any other fields on the page
  /// that share the same label (e.g. a name/date that repeats) with one tap.
  void _offerReplicate(DetectedField source, String value) {
    final similar = _fieldInput.findReplicateTargets(source, _pageFields);
    if (similar.isEmpty) return;

    final label = _fieldInput.cleanLabel(source.label);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Fill ${similar.length} more "$label" field(s) with the same value?'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Fill all',
          onPressed: () {
            for (final f in similar) {
              final placement = _fieldInput.buildTextPlacement(f);
              final fitted = _fieldInput.fitTextSize(
                value,
                placement.size,
                (0.98 - placement.pos.dx).clamp(0.05, 1.0).toDouble(),
              );
              _placeValue(placement.pos, fitted, value);
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
    if (_pageFields.isEmpty) {
      await _detectFields();
    }
    final fields = _pageFields;
    if (fields.isEmpty) return;

    await UserProfileService.instance.load();
    final profile = UserProfileService.instance.data;

    // Compute dependent fields (full name, age, net/gross) before auto-fill.
    final enrichedProfile = Map<String, String>.from(profile);
    final computed = _crossField.computeDependents(enrichedProfile);
    enrichedProfile.addAll(computed);

    final result = _profileAutoFill.autoFill(fields: fields, profile: enrichedProfile);

    if (!mounted) return;
    if (result.annotations.isNotEmpty) {
      setState(() {
        _layer.items.addAll(result.annotations);
        _hasUnsavedChanges = true;
      });
    }

    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.autoCount > 0 ? l10n.autoFilledCount(result.autoCount) : l10n.noProfileMatches),
    ));

    if (result.remaining.isNotEmpty) {
      await _guidedFill(result.remaining);
    }
  }

  /// Step through [fields] one-by-one, opening the right input for each so the
  /// user can quickly complete anything the profile couldn't fill.
  Future<void> _guidedFill(List<DetectedField> fields) async {
    if (!mounted || fields.isEmpty) return;
    final go = await showEditorGuidedFillDialog(context, fieldCount: fields.length);
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
      FieldType.name,
    );
    if (val != null && val.trim().isNotEmpty) {
      setState(() => _pushItem(_annotationFactory.typedSignature(val.trim())));
    }
  }

  Future<String?> _promptValue(String label, TextInputType kb, FieldType type) {
    return showEditorValuePromptDialog(
      context,
      label: label,
      keyboardType: kb,
      leading: Icon(_typeIcon(type), size: 18),
    );
  }

  PageLayer get _layer => _layers.putIfAbsent(_current, () => PageLayer());

  Future<void> _pick() async {
    final picked = await _filePicker.pickSupportedFile();
    if (picked == null) return;
    await _loadFile(picked.path, picked.name);
  }

  /// Load a PDF/image from [path]. Optionally pre-place [fields] as editable
  /// text boxes (used by the AI form filler).
  Future<void> _loadFile(String path, String name, {List<FilledField>? fields}) async {
    _editorController.beginOpenFile(fileName: name, filePath: path);
    setState(() {
      _pageCache.clear();
      _layers.clear();
      _fields.clear();
      _multi.clear();
      _selected = null;
    });

    try {
      await _doc?.close();
      final loaded = await _documentService.openDocument(path);
      _doc = loaded.document;
      _pageCount = loaded.pageCount;
      if (loaded.isPdf) {
        await _renderPage(0);
      } else if (loaded.imageBytes != null) {
        _pageCache[0] = loaded.imageBytes!;
      }
      _editorController.finishOpenFile(pageCount: _pageCount, currentPage: 0);

      // Restore any previously saved annotations (crash recovery).
      final savedLayers = await _persistence.load(path);
      if (savedLayers.isNotEmpty) {
        _layers.addAll(savedLayers);
        _hasUnsavedChanges = true;
      }

      if (fields != null && fields.isNotEmpty) {
        _initialFields.applyInitialFields(
          fields: fields,
          pageCount: _pageCount,
          layers: _layers,
          savedSignatures: _savedSignatures,
        );
        _hasUnsavedChanges = true;
        _tool = EditTool.pan;
      }

      if (fields == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageCache[_current] != null) _detectFields(silent: true);
        });
      }
      if (mounted) setState(() {});
    } catch (e) {
      _editorController.failOpenFile('Could not open file: $e');
      _showError('Could not open file: $e');
      if (mounted) setState(() {});
    }
  }

  Future<void> _renderPage(int index) async {
    if (_pageCache.containsKey(index) || _doc == null) return;
    await _pageRender.renderPage(
      doc: _doc!,
      index: index,
      pageCache: _pageCache,
      renderMaxEdge: _renderMaxEdge,
    );
    _pageRender.evictFarPages(
      pageCache: _pageCache,
      keepIndex: index,
      maxCachedPages: _maxCachedPages,
    );
  }

  Future<void> _goToPage(int index) async {
    if (index < 0 || index >= _pageCount) return;
    _editorController.beginPageChange();
    setState(() {});
    await _renderPage(index);
    _editorController.finishPageChange(index);
    setState(() {
      _selected = null;
      _multi.clear();
      _showFields = false;
      _showEditLines = false;
    });
    // Pre-render adjacent pages for instant page-switching.
    if (_doc != null) {
      _preloader.preloadAdjacent(
        doc: _doc!,
        currentPage: index,
        pageCount: _pageCount,
        pageCache: _pageCache,
        renderMaxEdge: _renderMaxEdge,
      );
    }
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
    final n = _canvasInteraction.normalize(local, canvas);
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
    final n = _canvasInteraction.normalize(local, canvas);
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
        _multi
          ..clear()
          ..addAll(_canvasInteraction.marqueeSelection(
            items: _layer.items,
            marqueeStart: _marqueeStart,
            marqueeEnd: _marqueeEnd,
            bounds: _bounds,
          ));
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
    final stroke = _isFreehand
        ? _canvasInteraction.completeStroke(
            drawing: _drawing,
            tool: _tool,
            color: _color,
            stroke: _stroke,
          )
        : null;
    final shape = _isShape
        ? _canvasInteraction.completeShape(
            shapeStart: _shapeStart,
            shapeEnd: _shapeEnd,
            tool: _tool,
            color: _color,
            stroke: _stroke,
          )
        : null;
    if (stroke != null) {
      _pushItem(stroke);
    } else if (shape != null) {
      _pushItem(shape);
    }
    _drawing = [];
    _shapeStart = null;
    _shapeEnd = null;
    setState(() {});
  }

  void _onTapUp(Offset local, Size canvas) {
    final n = _canvasInteraction.normalize(local, canvas);
    if (_tapTools.isTextTool(_tool)) {
      _editTextBox(_tapTools.buildTextDraft(n, _color, _textSize, _bold), isNew: true);
      return;
    }

    final mark = _tapTools.buildMarkAnnotation(_tool, n);
    if (mark != null) {
      setState(() => _pushItem(mark));
      return;
    }

    if (_tool == EditTool.eraser) {
      setState(() {
        if (_editorController.eraseLast(_layer)) {
          _selected = null;
          _multi.clear();
        }
      });
    } else if (_tool == EditTool.pan) {
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
  EditorAnnotation? _hitTest(Offset n) {
    return _hitTestService.hitTest(_layer, n);
  }

  /// Move a selected object by a normalized delta.
  void _moveSelected(Offset deltaNorm) {
    setState(() {
      final guides = _editorController.moveSelected(_selected, deltaNorm, _selection, _bounds);
      if (guides != null) {
        _guideX = guides.guideX;
        _guideY = guides.guideY;
      }
    });
    _schedulePersist();
  }

  /// Resize the selected object so its bounding box becomes [nb] (normalized).
  /// Works uniformly for every annotation type: stroke points are remapped,
  /// shape endpoints are remapped, and text scales its font size by the height
  /// ratio. Used by the corner resize handles.
  void _scaleSelectedTo(Rect nb) {
    setState(() {
      final guides = _editorController.scaleSelectedTo(_selected, nb, _selection, _bounds);
      if (guides != null) {
        _guideX = guides.guideX;
        _guideY = guides.guideY;
      }
    });
  }


  /// Resize a selected shape by adjusting its end point.
  void _resizeSelected(Offset newEndNorm) {
    setState(() {
      _editorController.resizeSelectedShape(_selected, newEndNorm, _selection);
    });
  }

  /// Quick, precise font sizing for the selected value so it fits its field.
  /// [factor] > 1 enlarges, < 1 shrinks. Size is normalized to canvas height.
  void _resizeSelectedText(double factor) {
    setState(() {
      _editorController.resizeSelectedText(_selected, factor, _selection);
    });
  }

  void _deleteSelected() {
    if (_selected != null) {
      setState(() {
        _selected = _editorController.deleteSelected(_layer, _selected);
      });
      _schedulePersist();
    }
  }

  /// Copy the selected object to an in-editor clipboard (works across pages).
  void _copySelected() {
    final sel = _selected;
    if (sel == null) return;
    _clipboard = _editorController.copySelected(sel, _selection);
    setState(() {}); // refresh so the Paste action becomes enabled
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(milliseconds: 900)),
    );
  }

  /// Paste the clipboard object onto the CURRENT page, selected & ready to move.
  void _pasteClipboard() {
    setState(() {
      _selected = _editorController.pasteClipboard(_layer, _clipboard, _selection);
      if (_selected != null) {
        _tool = EditTool.pan;
      }
    });
  }

  /// Quick colour picker for the selected text value.
  void _pickSelectedTextColor() async {
    final sel = _selected;
    if (sel is! TextAnnotation) return;
    final picked = await showEditorTextColorPickerSheet(context, selectedColor: sel.color);
    if (picked == null) return;
    setState(() {
      sel.color = picked;
      _hasUnsavedChanges = true;
    });
  }

  void _duplicateSelected() {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _selected = _editorController.duplicateSelected(_layer, sel, _selection);
    });
  }

  void _bringToFront() {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _editorController.bringToFront(_layer, sel, _selection);
    });
  }

  void _sendToBack() {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _editorController.sendToBack(_layer, sel, _selection);
    });
  }

  // ---- Multi-select helpers (E2) ----

  void _moveAnnotation(EditorAnnotation a, Offset d) {
    _editorController.moveAnnotation(a, d, _selection);
  }

  /// Normalized bounding box of any annotation.
  Rect _boundsOf(EditorAnnotation a) => _bounds.boundsOf(a);

  void _alignMulti(String how) {
    if (_multi.length < 2) return;
    setState(() {
      _editorController.alignMulti(_multi, how, _selection, _bounds);
    });
  }

  void _distributeMulti(Axis axis) {
    if (_multi.length < 3) return;
    setState(() {
      _editorController.distributeMulti(_multi.toList(), axis, _selection, _bounds);
    });
  }

  void _deleteMulti() {
    setState(() {
      _editorController.deleteMulti(_layer, _multi);
      _multi.clear();
    });
  }

  void _duplicateMulti() {
    setState(() {
      final copies = _editorController.duplicateMulti(_layer, _multi, _selection);
      _multi
        ..clear()
        ..addAll(copies);
    });
  }

  /// Add an annotation and reset the redo stack.
  void _pushItem(EditorAnnotation a) {
    _editorController.pushAnnotation(_layer, a);
    _schedulePersist();
    // Log to revision history for cross-session undo / version tracking.
    final path = _editorController.state.filePath;
    if (path != null) {
      _revisionHistory.appendEntry(
        filePath: path,
        commandType: 'add',
        description: 'Add ${a.runtimeType.toString().replaceAll("Annotation", "")}',
      );
    }
  }

  /// Save layers to disk (debounced: only the last call in a frame executes).
  bool _persistScheduled = false;
  void _schedulePersist() {
    if (_persistScheduled) return;
    _persistScheduled = true;
    Future.microtask(() {
      _persistScheduled = false;
      final path = _editorController.state.filePath;
      if (path != null && _layers.isNotEmpty) {
        _persistence.save(filePath: path, layers: _layers);
      }
    });
  }


  /// Fill & Sign: place today's date (dd.MM.yyyy) as a movable text box.
  void _placeSignatureDate() {
    final d = DateTime.now();
    final s = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    setState(() => _pushItem(_annotationFactory.signatureDateAt(const Offset(0.5, 0.5), s, _color, _textSize, _bold)));
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

    final source = await showEditorSmartFillSourceSheet(context);
    if (source == null || !mounted) return;

    String? infoPath;
    if (source == 'doc') {
      final picked = await _filePicker.pickSupportedFile();
      if (picked == null) return;
      infoPath = picked.path;
    }

    setState(() => _detecting = true);
    try {
      await UserProfileService.instance.load();
      final profile = UserProfileService.instance.data;
      final fields = await _smartFill.smartFillPage(
        pageBytes: bytes,
        pageOcr: _ocr,
        source: source,
        profile: profile,
        infoDocumentPath: infoPath,
      );

      if (!mounted) return;
      setState(() => _detecting = false);

      if (fields.isEmpty) {
        _showError(AppLocalizations.of(context)!.smartFillNoMatch);
        return;
      }

      final confirmed = await showEditorSmartFillReviewSheet(context, fields: fields);
      if (confirmed == null || confirmed.isEmpty || !mounted) return;

      setState(() {
        _annotationApply.applyFilledFieldsToLayer(_layer, confirmed);
        _tool = EditTool.pan;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.smartFillPlaced(confirmed.length))),
      );
      // Save filled values as a form profile for next time.
      if (_editorController.state.fileName != null) {
        final values = <String, String>{};
        for (final f in confirmed) {
          values[f.label] = f.value;
        }
        _formProfiles.saveProfile(
          formType: _editorController.state.fileName!,
          fieldValues: values,
        );
      }
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
      final lines = await _textScan.scanEditableLines(bytes: bytes, ocr: _ocr);
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
    final draft = _existingText.draftForLine(line);
    setState(() {
      _showEditLines = false;
      _pushItem(draft.whiteout);
    });
    final before = _layer.items.length;
    await _editTextBox(draft.textBox, isNew: true);
    if (_layer.items.length == before &&
        _layer.items.isNotEmpty &&
        _layer.items.last is ShapeAnnotation &&
        (_layer.items.last as ShapeAnnotation).type == ShapeType.whiteout) {
      setState(() => _layer.items.removeLast());
    }
  }


  /// Fill & Sign: pick a saved profile value (name, address, ID…) and drop it
  /// as a movable text box. Prompts to set up the profile if none is saved.
  /// Add a predefined stamp to the page.
  Future<void> _addStamp() async {
    // Show a simple stamp chooser (for now, use DRAFT as default).
    // TODO: show a stamp picker sheet with all StampKind options.
    setState(() {
      _pushItem(_annotationFactory.textAt(
        const Offset(0.35, 0.45),
        0.04,
        'DRAFT',
        color: Colors.red,
        bold: true,
      ));
    });
  }

  /// Add an image from the device gallery to the page.
  Future<void> _addImage() async {
    final picked = await _filePicker.pickSupportedFile();
    if (picked == null) return;
    // For now, add as a text placeholder showing the filename.
    // Full ImageAnnotation rendering requires the image_annotation_renderer
    // to be wired into the canvas painter (P1 service exists, wiring is next).
    setState(() {
      _pushItem(_annotationFactory.textAt(
        const Offset(0.3, 0.4),
        0.02,
        '[Image: ${picked.name}]',
        color: Colors.blueGrey,
      ));
    });
  }

  Future<void> _insertProfileField() async {
    await UserProfileService.instance.load();
    final data = UserProfileService.instance.data;
    final entries = _profileInsert.buildOptions(data);
    if (!mounted) return;
    final picked = await showEditorProfileFieldPickerSheet(
      context,
      entries: entries,
      onSetUpProfile: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
      },
    );
    if (picked == null) return;
    setState(() => _pushItem(
          _profileInsert.buildAnnotation(picked.value, _color, _textSize, _bold),
        ));
  }

  // --- Inline text editing (P1) ---
  TextAnnotation? _inlineEditing; // annotation currently being edited inline

  Future<void> _editTextBox(TextAnnotation box, {bool isNew = false}) async {
    // For NEW text boxes, use inline editing directly on the canvas.
    // For existing text, also use inline (replaces the modal dialog).
    if (isNew) {
      // Add the annotation first so it's in the layer.
      if (!_layer.items.contains(box)) {
        _pushItem(box);
      }
    }
    setState(() {
      _inlineEditing = box;
      _selected = box;
      _tool = EditTool.pan;
    });
  }

  void _commitInlineEdit() {
    final editing = _inlineEditing;
    if (editing == null) return;
    setState(() {
      _inlineEditing = null;
      if (editing.text.isEmpty) {
        // Empty text → remove the annotation (user cleared it).
        _layer.items.remove(editing);
      }
      _hasUnsavedChanges = true;
      _schedulePersist();
    });
  }

  void _onInlineTextChanged(String newText) {
    final editing = _inlineEditing;
    if (editing == null) return;
    editing.text = newText;
    _hasUnsavedChanges = true;
  }

  /// Properties editor for a selected shape (E3): stroke width, color,
  /// fill (rect/oval), and opacity.
  Future<void> _editShapeStyle(ShapeAnnotation s) async {
    final canFill = s.type == ShapeType.rect || s.type == ShapeType.oval;
    final result = await showEditorShapeStyleDialog(
      context,
      canFill: canFill,
      filled: s.filled,
      opacity: s.opacity,
      width: s.width,
      color: s.color,
    );
    setState(() {
      if (_annotationEdit.applyShapeStyleResult(s, result)) {
        _hasUnsavedChanges = true;
      }
    });
  }

  void _undo() {
    setState(() {
      _editorController.undo(_layer);
      _selected = null;
      _multi.clear();
    });
    _schedulePersist();
  }

  void _redoAction() {
    setState(() {
      _editorController.redo(_layer);
      _selected = null;
      _multi.clear();
    });
    _schedulePersist();
  }

  Future<void> _addSignature() async {
    List<Offset>? points;
    final choice = await showEditorSignaturePickerSheet(
      context,
      savedSignatureCount: _savedSignatures.length,
    );
    if (choice == null) return;
    if (choice.isDelete) {
      await _signatureFlow.deleteSavedSignature(_savedSignatures, choice.deleteIndex!);
      return;
    }
    if (choice.action == 'type') {
      await _typeSignature();
      return;
    } else if (choice.action == 'new') {
      points = await _drawSignature();
    } else {
      points = _signatureFlow.resolveSavedSignature(choice, _savedSignatures);
    }

    if (points != null && points.length > 1) {
      setState(() {
        _pushItem(_signatureInsert.signatureFromPadPoints(points!));
      });
    }
  }

  Future<List<Offset>?> _drawSignature() async {
    final points = await Navigator.of(context).push<List<Offset>>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const SignaturePadSheet()),
    );
    final save = await showEditorSaveSignatureDialog(context);
    await _signatureFlow.persistDrawnSignatureIfRequested(_savedSignatures, points, save);
    return points;
  }

  /// Rotate the current page image 90° clockwise. The rotation is applied to
  /// the cached bytes (re-encoded) so it appears immediately and exports correctly.
  Future<void> _rotatePage() async {
    final bytes = _pageCache[_current];
    if (bytes == null) return;
    _editorController.beginPageChange();
    setState(() {});
    try {
      final rotated = await _pageTransform.rotateClockwise(bytes);
      if (rotated != null) {
        _pageCache[_current] = rotated;
      }
    } catch (e) {
      _editorController.setError('Rotate failed: $e');
      _showError('Rotate failed: $e');
    } finally {
      _editorController.finishPageChange(_current);
      if (mounted) setState(() {});
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

  Future<String?> _renderToPdfFile() async {
    _editorController.beginExport();
    setState(() {});
    try {
      final outPath = await _exportService.renderToPdfFile(
        doc: _doc,
        pageCache: _pageCache,
        layers: _layers,
        pageCount: _pageCount,
      );
      if (outPath == null) {
        _editorController.finishExport(error: 'Nothing to export');
        _showError('Nothing to export');
      } else {
        _editorController.finishExport();
        // Clear the saved annotations — work is now in the exported PDF.
        final srcPath = _editorController.state.filePath;
        if (srcPath != null) _persistence.delete(srcPath);
      }
      return outPath;
    } catch (e) {
      _editorController.finishExport(error: 'Export failed: $e');
      _showError('Export failed: $e');
      return null;
    } finally {
      if (mounted) setState(() {});
    }
  }

  /// Save the edited PDF, then — right there at save time — offer to share it
  /// or continue straight into another tool (compress, convert, …). The saved
  /// file is handed off so the next tool opens it automatically (no re-picking).
  Future<void> _export() async {
    final outPath = await _renderToPdfFile();
    if (outPath == null || !mounted) return;
    final action = await showEditorExportActionsSheet(context, outPath: outPath);
    if (action == null || !mounted) return;
    if (action.kind == 'share') {
      await Share.shareXFiles([XFile(outPath)]);
      return;
    }
    if (action.kind == 'route' && action.route != null) {
      if (action.handoffPath != null) ToolHandoff.instance.set(action.handoffPath!);
      context.push(action.route!);
    }
  }

  ShapeType? _shapePreviewType() => _canvasInteraction.shapePreviewType(_tool);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final bytes = _pageCache[_current];

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final action = await showEditorUnsavedChangesDialog(context);
        if (action == 'discard' && mounted) {
          setState(() {
            _editorController.clearDirty();
          });
          Navigator.of(context).pop();
        } else if (action == 'save' && mounted) {
          await _export();
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF2B2B2B),
      appBar: EditorTopBar(
        title: _fileName ?? l10n.toolEditor,
        currentPage: _current,
        pageCount: _pageCount,
        hasDocument: bytes != null,
        canUndo: _layer.items.isNotEmpty,
        canRedo: _layer.redo.isNotEmpty,
        canPaste: _clipboard != null,
        loading: _loading,
        onUndo: _undo,
        onRedo: _redoAction,
        onPaste: _pasteClipboard,
        onExport: _export,
      ),
      body: EditorScreenBody(
        bytes: bytes,
        loading: _loading,
        detecting: _detecting,
        detectingLabel: l10n.readingTheForm,
        onPick: _pick,
        inlineOverlay: _inlineEditing != null
            ? Positioned.fill(
                bottom: 96,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final editing = _inlineEditing!;
                    final canvasW = constraints.maxWidth;
                    final canvasH = constraints.maxHeight;
                    const aspect = 1 / 1.414;
                    double pageW, pageH;
                    if (canvasW / canvasH > aspect) {
                      pageH = canvasH;
                      pageW = canvasH * aspect;
                    } else {
                      pageW = canvasW;
                      pageH = canvasW / aspect;
                    }
                    final offsetX = (canvasW - pageW) / 2;
                    final offsetY = (canvasH - pageH) / 2;
                    final left = offsetX + editing.pos.dx * pageW;
                    final top = offsetY + editing.pos.dy * pageH;
                    return Stack(
                      children: [
                        // Tap outside to dismiss inline editor.
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: _commitInlineEdit,
                            behavior: HitTestBehavior.translucent,
                          ),
                        ),
                        Positioned(
                          left: left,
                          top: top,
                          width: (pageW * (1 - editing.pos.dx)).clamp(50.0, pageW),
                          child: InlineTextEditor(
                            annotation: editing,
                            canvasSize: Size(pageW, pageH),
                            onDone: _commitInlineEdit,
                            onTextChanged: _onInlineTextChanged,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              )
            : null,
        documentViewport: EditorDocumentViewport(
          panEnabled: _tool == EditTool.pan,
          scaleEnabled: _tool == EditTool.pan,
          child: EditorCanvas(
            bytes: bytes ?? Uint8List(0),
            tool: _tool,
            layer: _layer,
            drawing: _drawing,
            shapeStart: _shapeStart,
            shapeEnd: _shapeEnd,
            previewShapeType: _shapePreviewType(),
            color: _color,
            stroke: _stroke,
            highlightPreview: _tool == EditTool.highlight,
            showFields: _showFields,
            pageFields: _pageFields,
            showEditLines: _showEditLines,
            editLines: _editLines[_current] ?? const <OcrLine>[],
            guideX: _guideX,
            guideY: _guideY,
            multi: _multi,
            selMode: _selMode,
            marqueeStart: _marqueeStart,
            marqueeEnd: _marqueeEnd,
            selected: _selected,
            boundsOf: _boundsOf,
            onTapUp: _onTapUp,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onFieldTap: _openFieldInput,
            onEditLineTap: _editExistingLine,
            onEditText: _editTextBox,
            onSelectText: (t) => setState(() => _selected = t),
            onMoveText: (t, d, size) => setState(() {
              t.pos = Offset(
                (t.pos.dx + d.delta.dx / size.width).clamp(0.0, 0.98),
                (t.pos.dy + d.delta.dy / size.height).clamp(0.0, 0.98),
              );
              _hasUnsavedChanges = true;
            }),
            onResizeBounds: _scaleSelectedTo,
            onTextDecrease: () => _resizeSelectedText(0.9),
            onTextIncrease: () => _resizeSelectedText(1.1),
            onPickTextColor: _pickSelectedTextColor,
            onEditShapeStyle: () => _editShapeStyle(_selected as ShapeAnnotation),
            onCopySelected: _copySelected,
            onDuplicateSelected: _duplicateSelected,
            onBringToFront: _bringToFront,
            onSendToBack: _sendToBack,
            onDeleteSelected: _deleteSelected,
            onDeselectSelected: () => setState(() => _selected = null),
            onAlignMulti: _alignMulti,
            onDistributeMulti: _distributeMulti,
            onDuplicateMulti: _duplicateMulti,
            onDeleteMulti: _deleteMulti,
            onDeselectMulti: () => setState(() => _multi.clear()),
            resolveTypeIcon: _typeIcon,
          ),
        ),
        toolbar: EditorToolbar(
          tool: _tool,
          detecting: _detecting,
          showFields: _showFields,
          showEditLines: _showEditLines,
          hasPageFields: _pageFields.isNotEmpty,
          isShape: _isShape,
          color: _color,
          stroke: _stroke,
          textSize: _textSize,
          bold: _bold,
          onToolChanged: (tool) => setState(() => _tool = tool),
          onAutoFill: _autoFill,
          onAiFill: _smartFillPage,
          onEditTextTool: _scanForEdit,
          onToggleFields: () => setState(() => _showFields = !_showFields),
          onAddSignature: _addSignature,
          onPlaceSignatureDate: _placeSignatureDate,
          onInsertProfileField: _insertProfileField,
          onAddStamp: _addStamp,
          onAddImage: _addImage,
          onRotatePage: _rotatePage,
          onOpen: _pick,
          onColorChanged: (c) => setState(() => _color = c),
          onStrokeChanged: (v) => setState(() => _stroke = v),
          onTextSizeChanged: (v) => setState(() => _textSize = v),
          onToggleBold: () => setState(() => _bold = !_bold),
        ),
      ),
      floatingActionButton: bytes == null
          ? null
          : EditorPageNavigation(
              currentPage: _current,
              pageCount: _pageCount,
              onPrev: _current > 0 ? () => _goToPage(_current - 1) : null,
              onNext: _current < _pageCount - 1 ? () => _goToPage(_current + 1) : null,
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    ),
    );
  }

}
