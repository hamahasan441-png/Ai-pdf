import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:share_plus/share_plus.dart';

import '../../ai/presentation/ai_chat_screen.dart';
import '../../../core/services/ocr_service.dart';
import 'package:ai_pdf/features/editor/application/editor_controller.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_outline_reader.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/acro_form.dart';
import 'package:ai_pdf/features/editor/data/form_value_marks.dart';
import 'package:ai_pdf/features/editor/domain/history/form_value_command.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/acro_form_layer.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_form_field_dialogs.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_reading_mode_sheet.dart';
import 'package:ai_pdf/features/viewer/presentation/reading_mode_controller.dart';
import 'package:ai_pdf/features/editor/domain/services/document_outline_service.dart';
import 'package:ai_pdf/features/editor/data/editor_page_render_service.dart';
import 'package:ai_pdf/features/editor/data/pdf_content_text_extractor.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';
import 'package:ai_pdf/features/editor/data/text_markup_factory.dart';
import 'package:ai_pdf/features/editor/domain/services/text_selection_service.dart';
import 'package:ai_pdf/features/editor/data/annotation_persistence_service.dart';
import 'package:ai_pdf/features/editor/data/page_preloader_service.dart';
import 'package:ai_pdf/features/editor/data/page_reorder_service.dart';
import 'package:ai_pdf/features/editor/data/page_structure.dart';
import 'package:ai_pdf/features/editor/data/revision_history_service.dart';
import 'package:ai_pdf/features/editor/data/form_profile_service.dart';
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
import 'package:ai_pdf/features/editor/data/annotation_serialization.dart' show SavedPageStructure;
import 'package:ai_pdf/features/editor/data/editor_document_service.dart';
import 'package:ai_pdf/features/editor/data/editor_file_picker_service.dart';
import 'package:ai_pdf/features/editor/data/editor_page_transform_service.dart';
import 'package:ai_pdf/features/editor/data/editor_smart_fill_service.dart';
import 'package:ai_pdf/features/editor/data/editor_existing_text_service.dart';
import 'package:ai_pdf/features/editor/data/editor_annotation_apply_service.dart';
import 'package:ai_pdf/features/editor/data/editor_rich_text_service.dart';
import 'package:ai_pdf/features/editor/data/editor_text_scan_service.dart';
import 'package:ai_pdf/features/editor/data/editor_initial_fields_service.dart';
import 'package:ai_pdf/features/editor/data/editor_signature_insert_service.dart';
import 'package:ai_pdf/features/editor/data/editor_signature_flow_service.dart';
import 'package:ai_pdf/features/editor/data/ocr_field_detection_service.dart';
import 'package:ai_pdf/features/editor/data/image_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/data/stamp_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/data/signature_repository.dart';
import 'package:ai_pdf/features/editor/domain/entities/detected_field.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/image_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/stamp_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/sticky_note_annotation.dart';
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
import 'package:ai_pdf/features/editor/presentation/widgets/editor_text_selection_bar.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_toolbar.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/inline_text_editor.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_rich_text_toolbar.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_top_bar.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_page_thumbnail_strip.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_export_mode_dialogs.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_redaction_choice_dialog.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_unsaved_changes_dialog.dart';
import 'package:ai_pdf/features/editor/application/editor_search_controller.dart';
import 'package:ai_pdf/features/editor/application/editor_redaction_controller.dart';
import 'package:ai_pdf/features/editor/data/redaction_service.dart';
import 'package:ai_pdf/features/editor/domain/services/page_coordinate_transform.dart';
import 'package:ai_pdf/features/editor/domain/services/page_fit.dart';
import 'package:ai_pdf/features/editor/application/editor_outline_controller.dart';
import 'package:ai_pdf/features/editor/application/editor_compare_controller.dart';
import 'package:ai_pdf/features/editor/application/editor_layer_controller.dart';
import 'package:ai_pdf/features/editor/application/editor_form_review_controller.dart';
import 'package:ai_pdf/features/editor/application/editor_page_ops_controller.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_search_bar.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_search_highlight_painter.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_outline_panel.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_compare_view.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_layer_panel.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_form_review_panel.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_page_ops_dialog.dart';
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
  /// Shown immediately on a page turn. The sharp 2400px frame replaces it.
  static const int _previewEdge = 1280;
  static const int _maxCachedPages = 3;

  pdfx.PdfDocument? _doc;
  final Map<int, Uint8List> _pageCache = {}; // page index -> jpeg bytes
  /// Long-edge the cached JPEG was rendered at, so a preview cannot block
  /// the sharp frame and a late preview cannot overwrite it.
  final Map<int, int> _pageEdge = {};
  /// width / height of each page. Missing entries fall back to A4 portrait.
  final Map<int, double> _pageAspect = {};
  final Map<int, double> _pageHeightPt = {};
  /// Clockwise quarter-turns applied to the on-screen page this session.
  final Map<int, int> _pageQuarterTurns = {};
  List<int> _sourcePages = const [];
  final TransformationController _viewTransform = TransformationController();
  /// Positioned words from the PDF text layer, keyed by page. Empty for scans.
  final Map<int, List<PdfTextElement>> _textLayer = {};
  List<Rect> _markupPreview = const [];
  TextSelectionResult? _wordSelection;
  final TextMarkupFactory _markupFactory = const TextMarkupFactory();
  int _navTicket = 0;
  int _textGen = 0;
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
  final ImageAnnotationRenderer _imageRenderer = ImageAnnotationRenderer();
  final StampAnnotationRenderer _stampRenderer = const StampAnnotationRenderer();

  /// Bumped when an async image decode completes, to force a canvas repaint.
  int _canvasRevision = 0;
  final EditorPageRenderService _pageRender = const EditorPageRenderService();
  final AnnotationPersistenceService _persistence = const AnnotationPersistenceService();
  final PagePreloaderService _preloader = const PagePreloaderService();
  final PageReorderService _pageReorder = const PageReorderService();
  final RevisionHistoryService _revisionHistory = const RevisionHistoryService();
  final FormProfileService _formProfiles = const FormProfileService();
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
  final EditorRichTextService _richText = const EditorRichTextService();
  final Map<int, List<DetectedField>> _fields = {}; // page -> detected fields
  bool _showFields = false;

  // --- Edit existing text (OCR line -> cover + editable box) ---
  final Map<int, List<OcrLine>> _editLines = {}; // page -> recognized lines
  bool _showEditLines = false;
  bool _detecting = false;
  List<DetectedField> get _pageFields => _fields[_current] ?? const [];

  // --- Phase 27-34 controllers (wired UI features) ---
  final EditorSearchController _searchController = EditorSearchController();
  final EditorRedactionController _redactionController = EditorRedactionController();
  final EditorOutlineController _outlineController = EditorOutlineController();
  final EditorCompareController _compareController = EditorCompareController();
  final EditorLayerController _layerController = EditorLayerController();
  final EditorFormReviewController _formReviewController = EditorFormReviewController();
  final EditorPageOpsController _pageOpsController = EditorPageOpsController();

  // --- Saved signatures (persisted across sessions) ---
  static final List<List<Offset>> _savedSignatures = [];
  static bool _signaturesLoaded = false;

  @override
  void initState() {
    super.initState();
    _viewTransform.addListener(_onViewTransform);
    loadEditorReadingMode().then((m) {
      if (mounted && m != _readingMode) setState(() => _readingMode = m);
    });
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
    _viewTransform.removeListener(_onViewTransform);
    _viewTransform.dispose();
    _doc?.close();
    _ocr.dispose();
    _imageRenderer.dispose();
    _editorController.dispose();
    _searchController.dispose();
    _redactionController.dispose();
    _outlineController.dispose();
    _compareController.dispose();
    _layerController.dispose();
    _formReviewController.dispose();
    _pageOpsController.dispose();
    super.dispose();
  }

  /// Decode & cache an image annotation for painting, then repaint. Safe to
  /// call for any annotation type (no-op for non-images).
  void _prepareIfImage(EditorAnnotation? a) {
    if (a is! ImageAnnotation) return;
    _imageRenderer.prepare(a).then((_) {
      if (mounted) setState(() => _canvasRevision++);
    });
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
      setState(() {
        // Auto-select the typed signature so it can be moved/resized right away,
        // consistent with drawn/saved signatures and other annotations.
        final typed = _annotationFactory.typedSignature(val.trim());
        _pushItem(typed);
        _selected = typed;
        _tool = EditTool.pan;
      });
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

  String _openError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('password') || text.contains('encrypt')) {
      return 'This PDF is password-protected and cannot be edited until the password is removed.';
    }
    return 'Could not open file: $error';
  }

  /// Reads the PDF's bookmarks for the Outline panel, off the UI thread.
  Future<void> _loadOutline(String path, int gen) async {
    final List<OutlineHeading> headings;
    try {
      headings = await Isolate.run(
        () => const PdfOutlineReader().read(PdfObjectStore.parse(File(path).readAsBytesSync())),
      );
    } catch (e) {
      // An outline that cannot be read (encrypted file, broken structure)
      // leaves the panel showing "no outline"; the document itself still
      // opens and edits normally.
      debugPrint('Outline not loaded: $e');
      return;
    }
    if (!mounted || gen != _openGen) return;
    setState(() => _outlineController.load(headings));
  }

  /// How pages look on screen; never changes the exported file.
  ReadingMode _readingMode = ReadingMode.normal;

  Future<void> _chooseReadingMode() async {
    final picked = await showEditorReadingModeSheet(context, current: _readingMode);
    if (picked == null || !mounted) return;
    setState(() => _readingMode = picked);
    await saveEditorReadingMode(picked);
  }

  /// The PDF's own form, and the values the user changed (by field name).
  AcroFormSnapshot _form = AcroFormSnapshot.empty;
  final Map<String, Object> _formValues = {};

  /// Reads the PDF's form fields off the UI thread.
  Future<void> _loadForm(String path, int gen) async {
    final AcroFormSnapshot form;
    try {
      form = await Isolate.run(() => AcroFormSnapshot.read(File(path).readAsBytesSync()));
    } catch (e) {
      // A form that cannot be read (encrypted, broken) leaves the PDF
      // without fillable fields; it still opens and can be marked up.
      debugPrint('Form not loaded: $e');
      return;
    }
    if (!mounted || gen != _openGen) return;
    setState(() => _form = form);
  }

  /// Bumped by every [_loadFile]. An older open that finishes late must not
  /// install its document over a newer one.
  int _openGen = 0;

  /// Load a PDF/image from [path]. Optionally pre-place [fields] as editable
  /// text boxes (used by the AI form filler).
  Future<void> _loadFile(String path, String name, {List<FilledField>? fields}) async {
    final gen = ++_openGen;
    bool superseded() => !mounted || gen != _openGen;
    _editorController.beginOpenFile(fileName: name, filePath: path);
    setState(() {
      _pageCache.clear();
      _pageEdge.clear();
      _pageAspect.clear();
      _pageHeightPt.clear();
      _pageQuarterTurns.clear();
      _sourcePages = const [];
      _textLayer.clear();
      _markupPreview = const [];
      _wordSelection = null;
      _layers.clear();
      _fields.clear();
      _multi.clear();
      _selected = null;
      _outlineController.clear();
      _form = AcroFormSnapshot.empty;
      _formValues.clear();
    });

    try {
      // Detach before closing so no render picks up a closed document.
      final previous = _doc;
      _doc = null;
      _navTicket++;
      await previous?.close();
      final loaded = await _documentService.openDocument(path);
      if (superseded()) {
        await loaded.document?.close();
        return;
      }
      _doc = loaded.document;
      _pageCount = loaded.pageCount;
      _sourcePages = [for (var i = 0; i < loaded.pageCount; i++) i];
      final ticket = ++_navTicket;
      final textGen = ++_textGen;
      if (loaded.isPdf && _doc != null) {
        unawaited(_loadTextLayer(path, textGen));
        unawaited(_loadOutline(path, gen));
        // Awaited: whether the PDF has a real form decides below whether the
        // OCR field guesses run.
        await _loadForm(path, gen);
        if (superseded()) return;
        await _preloader.renderFirstPageProgressive(
          doc: _doc!,
          index: 0,
          pageCache: _pageCache,
          resolution: _pageEdge,
          aspects: _pageAspect,
          pageHeights: _pageHeightPt,
          stillCurrent: () => mounted && ticket == _navTicket,
          onLowRes: (_) {
            if (mounted && ticket == _navTicket) setState(() {});
          },
        );
        _pageRender.evictFarPages(
          pageCache: _pageCache,
          keepIndex: 0,
          maxCachedPages: _maxCachedPages,
          resolution: _pageEdge,
        );
      } else if (loaded.imageBytes != null) {
        _pageCache[0] = loaded.imageBytes!;
        _pageEdge[0] = _renderMaxEdge;
      }
      if (superseded()) return;
      _editorController.finishOpenFile(pageCount: _pageCount, currentPage: 0);

      // Restore any previously saved annotations (crash recovery).
      final saved = await _persistence.loadChecked(path);
      if (superseded()) return;
      if (saved.corrupt) {
        _showError('Saved marks could not be read. A backup was kept.');
      }
      _formValues
        ..clear()
        ..addAll(saved.formValues);
      var savedLayers = saved.layers;
      // Marks are keyed by position in the edited document. Restore them only
      // together with the page order they were placed on, and only if that
      // order fits this file; otherwise they would land on the wrong pages.
      final savedStructure = saved.structure ??
          SavedPageStructure(sources: [for (var i = 0; i < loaded.pageCount; i++) i]);
      if (!savedStructure.fits(loaded.pageCount, savedLayers.keys)) {
        await _persistence.quarantine(path);
        if (superseded()) return;
        savedLayers = const {};
        _showError('Saved marks do not match this file. A backup was kept.');
      } else if (!savedStructure.isIdentity) {
        _applySavedStructure(savedStructure);
      }
      if (savedLayers.isNotEmpty) {
        _layers.addAll(savedLayers);
        _hasUnsavedChanges = true;
        // Decode any restored image annotations so they paint on first view.
        for (final l in savedLayers.values) {
          for (final img in l.images) {
            _prepareIfImage(img);
          }
        }
      }

      _maskRedactedText();

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

      // A PDF with a real form is filled through its own fields; OCR guesses
      // would draw a second set of boxes over them.
      if (fields == null && _form.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageCache[_current] != null) _detectFields(silent: true);
        });
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (superseded()) return;
      _editorController.failOpenFile(_openError(e));
      _showError(_openError(e));
      if (mounted) setState(() {});
    }
  }

  void _onViewTransform() {
    if (_inlineEditing != null && mounted) setState(() {});
  }

  double _aspectFor(int index) {
    final stored = _pageAspect[index];
    if (stored == null || stored <= 0 || stored.isNaN) return PageFit.a4PortraitAspect;
    return stored;
  }

  void _maskRedactedText() {
    const svc = RedactionService();
    var changed = false;
    for (final entry in _layers.entries) {
      final words = _textLayer[entry.key];
      if (words == null || words.isEmpty) continue;
      final regions = [
        for (final shape in entry.value.shapes)
          if (shape.isSecureRedaction)
            RedactionRegion(shape.bounds, pageIndex: entry.key),
      ];
      if (regions.isEmpty) continue;
      final next = svc.apply(words, regions).remainingText;
      if (next.length != words.length) {
        _textLayer[entry.key] = next;
        changed = true;
      }
    }
    if (changed) _searchController.setPages(_textLayer);
  }

  void _commitRedaction() {
    final start = _shapeStart;
    final end = _shapeEnd;
    _shapeStart = null;
    _shapeEnd = null;
    if (start == null || end == null) {
      setState(() {});
      return;
    }
    final rect = Rect.fromPoints(start, end);
    if (rect.width < 0.005 || rect.height < 0.005) {
      setState(() {});
      return;
    }
    setState(() {});
    unawaited(_chooseRedaction(start, end, rect, _current));
  }

  bool _redacting = false;

  /// Redacted copies this session wrote. Only these are ever deleted.
  final Set<String> _redactedCopies = {};

  /// Ask whether to upload for secure redaction or only draw a cover.
  /// Nothing is uploaded unless the user picks the upload button.
  Future<void> _chooseRedaction(Offset start, Offset end, Rect rect, int page) async {
    if (_redacting) {
      _showError(AppLocalizations.of(context)!.redactWorking);
      return;
    }
    final sourcePath = _editorController.filePath;
    final sourcePage = _sourcePageFor(page);
    final secureAvailable = _doc != null &&
        sourcePath != null &&
        sourcePath.toLowerCase().endsWith('.pdf') &&
        sourcePage >= 0;
    final choice = await showEditorRedactionChoiceDialog(
      context,
      secureAvailable: secureAvailable,
    );
    if (!mounted || choice == null) return;
    final l10n = AppLocalizations.of(context)!;
    if (choice == RedactionChoice.visualCover) {
      final cover = ShapeAnnotation(ShapeType.rect, start, end, Colors.black, 1, true)
        ..metadata[visualCoverKey] = true;
      setState(() {
        _pushItem(cover, page: page);
        // Search still finds these words. They remain in the source PDF.
      });
      _showError(l10n.visualCoverNotice);
      return;
    }

    final mapped = RedactionService.toSourcePageRect(
      rect,
      quarterTurns: _pageQuarterTurns[page] ?? 0,
    );
    if (mapped == null || sourcePath == null) {
      _showError(l10n.redactSecureFailed(l10n.redactErrInvalidArea));
      return;
    }
    _redacting = true;
    _showError(l10n.redactWorking);
    final doc = _doc;
    final structure = List<int>.of(_sourcePages);
    final turns = Map<int, int>.of(_pageQuarterTurns);
    try {
      final result = await const RedactionService().redactViaBackend(
        filePath: sourcePath,
        regions: [RedactionRegion(mapped, pageIndex: sourcePage)],
      );
      if (!mounted) return;
      final path = result.path;
      if (path == null) {
        _showError(l10n.redactSecureFailed(_redactionFailureText(l10n, result)));
        return;
      }
      // Another file, or a page added, removed or turned while uploading,
      // would put the result on the wrong page.
      if (!identical(doc, _doc) ||
          _editorController.filePath != sourcePath ||
          !listEquals(structure, _sourcePages) ||
          !mapEquals(turns, _pageQuarterTurns)) {
        _showError(l10n.redactSecureFailed(l10n.redactErrDocumentChanged));
        return;
      }
      _redactedCopies.add(path);
      if (!await _replaceSourceDocument(path)) {
        _redactedCopies.remove(path);
        try {
          File(path).deleteSync();
        } catch (_) {}
        if (mounted) _showError(l10n.redactSecureFailed(l10n.redactErrOpenFailed));
        return;
      }
      if (!mounted) return;
      final cover = ShapeAnnotation(ShapeType.rect, start, end, Colors.black, 1, true)
        ..metadata[serverRedactedKey] = true;
      setState(() {
        _pushItem(cover, page: page);
        _hasUnsavedChanges = true;
      });
      _showError(result.occurrencesElsewhere > 0
          ? l10n.redactSecureDoneElsewhere(result.occurrencesElsewhere)
          : l10n.redactSecureDone);
    } finally {
      _redacting = false;
    }
  }

  String _redactionFailureText(AppLocalizations l10n, BackendRedactionResult result) {
    return switch (result.failure) {
      RedactionFailure.invalidArea => l10n.redactErrInvalidArea,
      RedactionFailure.missingFile => l10n.redactErrMissingFile,
      RedactionFailure.network => l10n.redactErrNetwork,
      RedactionFailure.timeout => l10n.redactErrTimeout,
      RedactionFailure.auth => l10n.redactErrAuth,
      RedactionFailure.notPdf => l10n.redactErrNotPdf,
      RedactionFailure.tooLarge => l10n.redactErrTooLarge,
      RedactionFailure.limit => l10n.redactErrLimit,
      RedactionFailure.refused => l10n.redactErrRefused(result.detail ?? ''),
      RedactionFailure.badResponse => l10n.redactErrBadResponse,
      RedactionFailure.unverified => l10n.redactErrUnverified,
      RedactionFailure.saveFailed => l10n.redactErrSaveFailed,
      RedactionFailure.server || null => l10n.redactErrServer,
    };
  }

  String _exportUnavailableText(ExportUnavailableKind kind) {
    final l10n = AppLocalizations.of(context)!;
    return switch (kind) {
      ExportUnavailableKind.unreadableFile => l10n.exportErrUnreadable,
      ExportUnavailableKind.encrypted => l10n.exportErrEncrypted,
      ExportUnavailableKind.damaged => l10n.exportErrDamaged,
      ExportUnavailableKind.writeFailed => l10n.exportErrWriteFailed,
    };
  }

  /// Swap the working PDF for [path] and keep every mark, page order and
  /// rotation. Used after a verified server redaction, so the page count must
  /// match. The original file on disk is not touched.
  Future<bool> _replaceSourceDocument(String path) async {
    final previous = _doc;
    if (previous == null) return false;
    final EditorDocumentLoadResult loaded;
    try {
      loaded = await _documentService.openDocument(path);
    } catch (_) {
      return false;
    }
    final next = loaded.document;
    if (next == null || loaded.pageCount != previous.pagesCount) {
      await next?.close();
      return false;
    }
    final oldPath = _editorController.filePath;
    _doc = next;
    _navTicket++;
    _pageCache.clear();
    _pageEdge.clear();
    _editorController.setFile(filePath: path, fileName: _fileName);
    await previous.close();
    // Recovery data follows the working file.
    if (oldPath != null && _layers.isNotEmpty) {
      _persistence.save(filePath: path, layers: _layers, structure: _pageStructure);
    }
    // An earlier redacted copy made by this app still holds what this
    // redaction removed. The user's own file is never deleted here.
    if (oldPath != null && _redactedCopies.remove(oldPath)) {
      unawaited(_persistence.delete(oldPath));
      try {
        File(oldPath).deleteSync();
      } catch (_) {
        // Already gone or locked; the OS clears the temp directory later.
      }
    }

    final gen = ++_textGen;
    try {
      final bySource = await compute(extractPdfTextLayerFromPath, path);
      if (mounted && gen == _textGen) {
        _setTextLayerFromSource(bySource);
        _searchController.setPages(_textLayer);
      }
    } catch (_) {
      // The pages still show; Find just has no words for them.
    }
    if (mounted) await _goToPage(_current);
    return true;
  }

  /// Restore a saved page order and rotations before the marks that were
  /// placed on them. Called while opening, before the marks are added.
  void _applySavedStructure(SavedPageStructure structure) {
    _sourcePages = List<int>.of(structure.sources);
    _pageCount = structure.sources.length;
    _pageQuarterTurns
      ..clear()
      ..addAll(structure.quarterTurns);
    // Page 0 was rendered for the PDF's own order; render it again.
    _navTicket++;
    _pageCache.clear();
    _pageEdge.clear();
    _pageAspect.clear();
    _pageHeightPt.clear();
    _hasUnsavedChanges = true;
    unawaited(_goToPage(0));
  }

  SavedPageStructure get _pageStructure => SavedPageStructure(
        sources: List<int>.of(_sourcePages),
        quarterTurns: Map<int, int>.of(_pageQuarterTurns),
      );

  /// Place PDF text by shown position. Text is extracted per PDF page.
  void _setTextLayerFromSource(Map<int, List<PdfTextElement>> bySource) {
    _textLayer.clear();
    for (var i = 0; i < _sourcePages.length; i++) {
      final words = bySource[_sourcePages[i]];
      if (words != null) _textLayer[i] = List<PdfTextElement>.of(words);
    }
  }

  Future<void> _loadTextLayer(String path, int gen) async {
    try {
      final map = await compute(extractPdfTextLayerFromPath, path);
      if (!mounted || gen != _textGen) return;
      setState(() => _setTextLayerFromSource(map));
      _searchController.setPages(_textLayer);
      _maskRedactedText();
      if (_searchController.state.active && _searchController.state.hasMatches) {
        _jumpToSearch();
      }
    } catch (_) {
      // A PDF this parser does not understand still edits; marks use the drag box.
    }
  }

  void _syncSearchPages() {
    _searchController.setPages(_textLayer);
  }

  void _jumpToSearch() {
    final page = _searchController.state.currentPage;
    if (page >= 0 && page != _current) _goToPage(page);
  }

  void _onSearchQuery(String query) {
    setState(() => _searchController.setQuery(query));
    _jumpToSearch();
  }

  void _onSearchStep(void Function() step) {
    setState(step);
    _jumpToSearch();
  }

  List<Rect> _findRects() {
    if (!_searchController.state.active) return const [];
    return _searchController.state.rectsForPage(_current);
  }

  int _activeFindIndex() {
    final state = _searchController.state;
    final match = state.currentMatch;
    if (match == null || match.pageIndex != _current) return -1;
    var i = 0;
    for (final m in state.matches) {
      if (m.pageIndex != _current) continue;
      if (m.elementIndex == match.elementIndex && m.start == match.start) return i;
      i++;
    }
    return -1;
  }

  Future<void> _editSelectedWords() async {
    final sel = _wordSelection;
    final words = _textLayer[_current] ?? const <PdfTextElement>[];
    if (sel == null || sel.indices.isEmpty) return;
    final picked = <PdfTextElement>[
      for (final i in sel.indices)
        if (i >= 0 && i < words.length) words[i],
    ];
    if (picked.isEmpty) return;
    final draft = _existingText.draftForWords(
      picked,
      pageHeightPt: _pageHeightPt[_current] ?? 0,
    );
    setState(() {
      _wordSelection = null;
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

  void _copyWords() {
    final text = _wordSelection?.text ?? '';
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    final l10n = AppLocalizations.of(context);
    _showError(l10n?.copied ?? 'Copied');
  }

  void _markSelection(EditTool tool) {
    final sel = _wordSelection;
    if (sel == null) return;
    final color = tool == EditTool.highlight && _color == Colors.red
        ? const Color(0xFFFFEB3B)
        : _color;
    final ann = _markupFactory.fromSelection(tool: tool, selection: sel, color: color);
    if (ann == null) return;
    setState(() {
      _pushItem(ann);
      _wordSelection = null;
    });
  }

  void _reindexTextOnDelete(int index, int oldCount) {
    final next = <int, List<PdfTextElement>>{};
    for (var i = 0; i < oldCount; i++) {
      if (i == index) continue;
      final words = _textLayer[i];
      if (words != null) next[i < index ? i : i - 1] = words;
    }
    _textLayer
      ..clear()
      ..addAll(next);
    _syncSearchPages();
  }

  void _reindexTextOnInsert(int index) {
    final next = <int, List<PdfTextElement>>{};
    for (final entry in _textLayer.entries) {
      next[entry.key >= index ? entry.key + 1 : entry.key] = entry.value;
    }
    _textLayer
      ..clear()
      ..addAll(next);
    _syncSearchPages();
  }

  /// PDF page behind the page shown at [index]; -1 for an inserted blank.
  int _sourcePageFor(int index) =>
      index >= 0 && index < _sourcePages.length ? _sourcePages[index] : index;

  Future<void> _renderPage(int index, {int? maxEdge}) async {
    if (_doc == null) return;
    final ticket = _navTicket;
    await _pageRender.renderPage(
      doc: _doc!,
      index: index,
      pageCache: _pageCache,
      renderMaxEdge: maxEdge ?? _renderMaxEdge,
      resolution: _pageEdge,
      aspects: _pageAspect,
      pageHeights: _pageHeightPt,
      stillCurrent: () => mounted && ticket == _navTicket,
      sourcePage: _sourcePageFor(index),
      quarterTurns: _pageQuarterTurns[index] ?? 0,
    );
    if (!mounted || ticket != _navTicket) return;
    _pageRender.evictFarPages(
      pageCache: _pageCache,
      keepIndex: index,
      maxCachedPages: _maxCachedPages,
      resolution: _pageEdge,
    );
  }

  Future<void> _goToPage(int index) async {
    if (index < 0 || index >= _pageCount) return;
    final ticket = ++_navTicket;
    _editorController.beginPageChange();
    final hadPreview = _pageCache.containsKey(index);
    if (hadPreview) {
      _editorController.finishPageChange(index);
      setState(() {
        _selected = null;
        _multi.clear();
        _showFields = false;
        _showEditLines = false;
        _wordSelection = null;
        _markupPreview = const [];
      });
    } else {
      setState(() {});
    }
    // Paint a lighter bitmap first so the turn is not blocked on 2400px.
    await _renderPage(index, maxEdge: _previewEdge);
    if (!mounted || ticket != _navTicket) return;
    if (!hadPreview) {
      _editorController.finishPageChange(index);
      setState(() {
        _selected = null;
        _multi.clear();
        _showFields = false;
        _showEditLines = false;
        _wordSelection = null;
        _markupPreview = const [];
      });
    }
    await _renderPage(index, maxEdge: _renderMaxEdge);
    if (!mounted || ticket != _navTicket) return;
    setState(() {});
    if (_doc == null) return;
    for (final adj in [index - 1, index + 1]) {
      if (adj < 0 || adj >= _pageCount) continue;
      _pageRender
          .renderPage(
            doc: _doc!,
            index: adj,
            pageCache: _pageCache,
            renderMaxEdge: _previewEdge,
            resolution: _pageEdge,
            aspects: _pageAspect,
            pageHeights: _pageHeightPt,
            stillCurrent: () => mounted && ticket == _navTicket,
            sourcePage: _sourcePageFor(adj),
            quarterTurns: _pageQuarterTurns[adj] ?? 0,
          )
          .then((_) {
        if (mounted && ticket == _navTicket) setState(() {});
      });
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ---- Phase 27-34 toolbar actions ----

  void _toggleSearch() {
    setState(() {
      if (_searchController.state.active) {
        _searchController.close();
      } else {
        _searchController.open();
      }
    });
  }

  void _toggleRedaction() {
    setState(() {
      if (_redactionController.state.active) {
        _redactionController.deactivate();
      } else {
        _redactionController.activate();
        _redactionController.setCurrentPage(_current);
      }
    });
  }

  void _toggleOutline() {
    setState(() => _outlineController.toggle());
  }

  /// Opens the document assistant on this file. It reads the file as saved
  /// on disk; marks not yet exported are not part of it.
  void _toggleChat() {
    final path = _editorController.filePath;
    if (path == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AiChatScreen(mode: AiChatMode.understand, initialPath: path),
    ));
  }

  void _toggleLayers() {
    setState(() => _layerController.toggle());
  }

  static String _layerKind(String layerId) => layerId.substring('layer_'.length);

  /// Applies a Layers-panel toggle to the marks of the current page as one
  /// undoable step.
  void _changeLayers(void Function(PageLayer page) change) {
    final page = _layer;
    final items = EditorLayerController.targets(page, null);
    if (items.isEmpty) return;
    setState(() {
      _editorController.beginEdit(items, label: 'Layers');
      change(page);
      _editorController.commitEdit(page);
      _canvasRevision++;
      // A hidden or locked mark cannot stay selected.
      final sel = _selected;
      if (sel != null && (!sel.visible || sel.locked)) _selected = null;
      _multi.removeWhere((a) => !a.visible || a.locked);
    });
    _schedulePersist();
  }

  void _showPageOps() {
    _pageOpsController.show(pageCount: _pageCount);
    _pageOpsController.selectCurrent(_current);
    setState(() {});
  }

  Future<void> _confirmPageOps() async {
    final op = _pageOpsController.state;
    final indices = List<int>.of(op.parsedIndices ?? const []);
    if (indices.isEmpty) return;
    _pageOpsController.hide();
    setState(() {});
    switch (op.operation) {
      case PageOperation.delete:
        final sorted = indices.toList()..sort((a, b) => b.compareTo(a));
        for (final index in sorted) {
          _deletePage(index);
        }
      case PageOperation.insertBlank:
        _insertBlankPage(indices.first);
      case PageOperation.rotateRight:
        for (final index in indices) {
          await _rotateSlot(index, clockwise: true);
        }
      case PageOperation.rotateLeft:
        for (final index in indices) {
          await _rotateSlot(index, clockwise: false);
        }
      case PageOperation.extract:
        final path = await _renderToPdfFile(onlyIndices: indices, clearRecovery: false);
        if (path != null && mounted) {
          await _offerExportedFile(path);
        }
      case PageOperation.split:
        final paths = <String>[];
        for (final index in indices) {
          final path = await _renderToPdfFile(onlyIndices: [index], clearRecovery: false);
          if (path != null) paths.add(path);
        }
        if (paths.isNotEmpty && mounted) {
          await Share.shareXFiles([for (final path in paths) XFile(path)]);
        }
    }
  }

  Future<void> _rotateSlot(int index, {required bool clockwise}) async {
    final turns = clockwise ? 1 : 3;
    final bytes = _pageCache[index];
    if (bytes != null) {
      var current = bytes;
      for (var n = 0; n < turns; n++) {
        final rotated = await _pageTransform.rotateClockwise(current);
        if (rotated == null) return;
        current = rotated;
      }
      _pageCache[index] = current;
    }
    if (!mounted) return;
    setState(() {
      var aspect = _pageAspect[index] ?? _aspectFor(index);
      for (var n = 0; n < turns; n++) {
        aspect = aspect == 0 ? aspect : 1 / aspect;
      }
      _pageAspect[index] = aspect;
      _pageQuarterTurns[index] = ((_pageQuarterTurns[index] ?? 0) + turns) % 4;
      _hasUnsavedChanges = true;
    });
    _schedulePersist();
  }

  // ---- Page management (Phase 10) ----

  void _onPageAction(int index, String action) {
    switch (action) {
      case 'delete':
        _deletePage(index);
        break;
      case 'duplicate':
        _duplicatePage(index);
        break;
      case 'insert':
        _insertBlankPage(index + 1);
        break;
      case 'moveEarlier':
        _movePage(index, index - 1);
        break;
      case 'moveLater':
        _movePage(index, index + 1);
        break;
    }
  }

  /// Moves page [from] to position [to]. Everything kept per page (bitmap,
  /// marks, undo history, rotation, text, detected fields) moves with it,
  /// and the export writes the pages in the new order.
  void _movePage(int from, int to) {
    if (from == to || from < 0 || to < 0 || from >= _pageCount || to >= _pageCount) return;
    Map<int, T> moved<T>(Map<int, T> m) => PageSourceMap.afterMove(m, from, to);
    void reKey<T>(Map<int, T> m) {
      final next = moved(m);
      m
        ..clear()
        ..addAll(next);
    }

    setState(() {
      reKey(_pageCache);
      reKey(_pageEdge);
      reKey(_pageAspect);
      reKey(_pageHeightPt);
      reKey(_pageQuarterTurns);
      reKey(_textLayer);
      reKey(_layers);
      reKey(_fields);
      reKey(_editLines);
      _editorController.shiftHistories(moved);
      if (_sourcePages.length == _pageCount) {
        final order = List<int>.of(_sourcePages);
        order.insert(to, order.removeAt(from));
        _sourcePages = order;
      }
      _current = PageSourceMap.movedIndex(_current, from, to);
      _hasUnsavedChanges = true;
      _selected = null;
      _multi.clear();
      _syncSearchPages();
    });
    _schedulePersist();
  }

  void _deletePage(int index) {
    if (_pageCount <= 1) return;
    setState(() {
      final oldCount = _pageCount;
      final newCount = _pageReorder.deletePage(
        index: index,
        pageCache: _pageCache,
        layers: _layers,
        pageCount: _pageCount,
        resolution: _pageEdge,
      );
      _reindexTextOnDelete(index, oldCount);
      if (index >= 0 && index < _sourcePages.length) {
        _sourcePages = List<int>.of(_sourcePages)..removeAt(index);
      }
      _applyShift(PageSourceMap.afterDelete, index, oldCount);
      _pageCount = newCount;
      if (_current >= _pageCount) _current = _pageCount - 1;
      _hasUnsavedChanges = true;
      _selected = null;
      _multi.clear();
    });
  }

  void _duplicatePage(int index) {
    setState(() {
      final oldCount = _pageCount;
      final newCount = _pageReorder.duplicatePage(
        index: index,
        pageCache: _pageCache,
        layers: _layers,
        pageCount: _pageCount,
        resolution: _pageEdge,
      );
      _pageCount = newCount;
      _hasUnsavedChanges = true;
      _reindexTextOnInsert(index + 1);
      final words = _textLayer[index];
      if (words != null) _textLayer[index + 1] = List<PdfTextElement>.of(words);
      if (index >= 0 && index < _sourcePages.length) {
        _sourcePages = List<int>.of(_sourcePages)..insert(index + 1, _sourcePages[index]);
      }
      _applyShift(PageSourceMap.afterInsert, index + 1, oldCount);
      final turns = _pageQuarterTurns[index];
      if (turns != null) _pageQuarterTurns[index + 1] = turns;
      final aspect = _pageAspect[index];
      if (aspect != null) _pageAspect[index + 1] = aspect;
      final height = _pageHeightPt[index];
      if (height != null) _pageHeightPt[index + 1] = height;
    });
  }

  void _insertBlankPage(int index) {
    setState(() {
      final oldCount = _pageCount;
      final newCount = _pageReorder.insertBlankPage(
        index: index,
        pageCache: _pageCache,
        layers: _layers,
        pageCount: _pageCount,
        resolution: _pageEdge,
      );
      _pageCount = newCount;
      _hasUnsavedChanges = true;
      _reindexTextOnInsert(index);
      final at = index.clamp(0, _sourcePages.length);
      _sourcePages = List<int>.of(_sourcePages)..insert(at, -1);
      _applyShift(PageSourceMap.afterInsert, index, oldCount);
    });
    _goToPage(index);
  }

  void _applyShift(
    Map<int, T> Function<T>(Map<int, T> map, int index, int oldCount) shift,
    int index,
    int oldCount,
  ) {
    _editorController.shiftHistories((h) => shift(h, index, oldCount));
    _schedulePersist();
    // Detected fields and OCR lines belong to a page too; before, they stayed
    // on the old index and showed up on the wrong page.
    final fields = shift(Map<int, List<DetectedField>>.of(_fields), index, oldCount);
    final lines = shift(Map<int, List<OcrLine>>.of(_editLines), index, oldCount);
    _fields
      ..clear()
      ..addAll(fields);
    _editLines
      ..clear()
      ..addAll(lines);
    final turns = shift(Map<int, int>.of(_pageQuarterTurns), index, oldCount);
    final aspects = shift(Map<int, double>.of(_pageAspect), index, oldCount);
    final heights = shift(Map<int, double>.of(_pageHeightPt), index, oldCount);
    _pageQuarterTurns
      ..clear()
      ..addAll(turns);
    _pageAspect
      ..clear()
      ..addAll(aspects);
    _pageHeightPt
      ..clear()
      ..addAll(heights);
  }

  // ---- Gesture handling (coordinates normalized to canvas) ----

  bool get _isFreehand => _tool == EditTool.draw;
  bool get _isMarkup => _markupFactory.isMarkupTool(_tool);
  bool get _isShape =>
      _tool == EditTool.line || _tool == EditTool.arrow || _tool == EditTool.rect ||
      _tool == EditTool.oval || _tool == EditTool.whiteout;

  void _onPanStart(Offset local, Size canvas) {
    final n = _canvasInteraction.normalize(local, canvas);
    if (n == null) return;
    if (_redactionController.state.active) {
      _shapeStart = n;
      _shapeEnd = n;
      setState(() {});
      return;
    }
    if (_tool == EditTool.eraser) {
      _eraseAt(n);
      return;
    }
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
        _wordSelection = null;
      } else if (_markupFactory.containsText(_textLayer[_current] ?? const [], n)) {
        _selMode = 'text';
        _shapeStart = n;
        _shapeEnd = n;
        _multi.clear();
        _wordSelection = _markupFactory.wordsBetween(
          start: n,
          end: n,
          elements: _textLayer[_current] ?? const [],
        );
      } else {
        _selMode = 'marquee';
        _marqueeStart = n;
        _marqueeEnd = n;
        _wordSelection = null;
      }
      if (_selMode == 'move' && _multi.isNotEmpty) {
        // Capture a single undoable step for the whole drag-move.
        _editorController.beginEdit(_multi, label: 'Move');
      }
      setState(() {});
      return;
    }
    if (_isMarkup) {
      _wordSelection = null;
      _shapeStart = n;
      _shapeEnd = n;
      _markupPreview = _markupFactory.previewRects(
        tool: _tool,
        start: n,
        end: n,
        elements: _textLayer[_current] ?? const [],
        color: _color,
      );
      setState(() {});
      return;
    }
    if (_tool == EditTool.pan && _selected != null) {
      // Start moving selected object
      _dragOffset = n;
      _editorController.beginEdit([_selected!], label: 'Move');
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
    if (n == null) return;
    if (_redactionController.state.active && _shapeStart != null) {
      _shapeEnd = n;
      setState(() {});
      return;
    }
    if (_tool == EditTool.eraser) {
      _eraseAt(n);
      return;
    }
    if (_tool == EditTool.select) {
      if (_selMode == 'text' && _shapeStart != null) {
        _shapeEnd = n;
        _wordSelection = _markupFactory.wordsBetween(
          start: _shapeStart!,
          end: n,
          elements: _textLayer[_current] ?? const [],
        );
        setState(() {});
        return;
      }
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
    if (_isMarkup && _shapeStart != null) {
      _shapeEnd = n;
      _markupPreview = _markupFactory.previewRects(
        tool: _tool,
        start: _shapeStart!,
        end: n,
        elements: _textLayer[_current] ?? const [],
        color: _color,
      );
      setState(() {});
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
    if (_tool == EditTool.eraser) return;
    if (_redactionController.state.active) {
      _commitRedaction();
      return;
    }
    if (_tool == EditTool.select) {
      if (_selMode == 'text') {
        _selMode = 'none';
        _shapeStart = null;
        _shapeEnd = null;
        setState(() {});
        return;
      }
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
      // Commit the drag-move (no-op for marquee / zero-movement selections).
      _editorController.commitEdit(_layer);
      _selMode = 'none';
      _marqueeStart = null;
      _marqueeEnd = null;
      _selDragLast = null;
      _guideX = null;
      _guideY = null;
      setState(() {});
      return;
    }
    if (_isMarkup) {
      final start = _shapeStart;
      final end = _shapeEnd;
      final ann = start != null && end != null
          ? _markupFactory.fromDrag(
              tool: _tool,
              start: start,
              end: end,
              elements: _textLayer[_current] ?? const [],
              color: _color,
            )
          : null;
      _shapeStart = null;
      _shapeEnd = null;
      _markupPreview = const [];
      if (ann != null) {
        setState(() => _pushItem(ann));
      } else {
        setState(() {});
      }
      return;
    }
    _dragOffset = null;
    _editorController.commitEdit(_layer);
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

  Future<String?> _promptNote(String initial) async {
    final controller = TextEditingController(text: initial);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(l10n.toolNote),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(hintText: l10n.toolNote),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.discard),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(l10n.saveAndExit),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return text;
  }

  Future<void> _placeNote(Offset n) async {
    final text = await _promptNote('');
    if (!mounted || text == null || text.isEmpty) return;
    setState(() => _pushItem(StickyNoteAnnotation(pos: n, text: text)));
  }

  Future<void> _editNote(StickyNoteAnnotation note) async {
    final text = await _promptNote(note.text);
    if (!mounted || text == null) return;
    if (text.isEmpty) {
      _deleteNote(note);
      return;
    }
    setState(() {
      _editorController.beginEdit([note], label: 'Edit note');
      note.text = text;
      _editorController.commitEdit(_layer, force: true);
    });
    _schedulePersist();
  }

  void _deleteNote(StickyNoteAnnotation note) {
    setState(() {
      _editorController.deleteSelected(_layer, note);
      _selected = null;
      _multi.remove(note);
    });
    _schedulePersist();
  }

  void _onTapUp(Offset local, Size canvas) {
    final n = _canvasInteraction.normalize(local, canvas);
    if (n == null) return;
    if (_tapTools.isTextTool(_tool)) {
      _editTextBox(_tapTools.buildTextDraft(n, _color, _textSize, _bold), isNew: true);
      return;
    }
    if (_tool == EditTool.note) {
      _placeNote(n);
      return;
    }
    if (_isMarkup) {
      final words = _textLayer[_current] ?? const [];
      if (words.isEmpty || _markupFactory.containsText(words, n)) {
        final ann = _markupFactory.fromDrag(
          tool: _tool,
          start: n,
          end: n,
          elements: words,
          color: _color,
        );
        if (ann != null) setState(() => _pushItem(ann));
      }
      return;
    }

    final mark = _tapTools.buildMarkAnnotation(_tool, n);
    if (mark != null) {
      setState(() => _pushItem(mark));
      return;
    }

    if (_tool == EditTool.eraser) {
      _eraseAt(n);
    } else if (_tool == EditTool.pan) {
      setState(() => _selected = _hitTest(n));
    } else if (_tool == EditTool.select) {
      final hit = _hitTest(n);
      if (hit != null) {
        setState(() {
          _wordSelection = null;
          _multi
            ..clear()
            ..add(hit);
        });
      } else {
        final words = _textLayer[_current] ?? const [];
        setState(() {
          _multi.clear();
          _wordSelection = _markupFactory.containsText(words, n)
              ? _markupFactory.wordsBetween(start: n, end: n, elements: words)
              : null;
        });
      }
    }
  }

  void _eraseAt(Offset n) {
    if (_editorController.eraseStrokeAt(_layer, n)) {
      _selected = null;
      _multi.clear();
      _hasUnsavedChanges = true;
      setState(() {});
      _schedulePersist();
    }
  }

  EditorAnnotation? _hitTest(Offset n) {
    return _hitTestService.hitTest(_layer, n);
  }

  /// Move a selected object by a normalized delta.
  void _moveSelected(Offset deltaNorm) {
    setState(() {
      final guides = _editorController.moveSelected(
        _selected,
        deltaNorm,
        _selection,
        _bounds,
        others: _layer.items,
      );
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


  /// Quick, precise font sizing for the selected value so it fits its field.
  /// [factor] > 1 enlarges, < 1 shrinks. Size is normalized to canvas height.
  void _resizeSelectedText(double factor) {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _editorController.beginEdit([sel], label: 'Resize text');
      _editorController.resizeSelectedText(sel, factor, _selection);
      _editorController.commitEdit(_layer, force: true);
    });
  }

  /// Set the rotation (radians) of the selected object during a rotate-handle
  /// drag. Bumps the canvas revision so the painter (which caches by list
  /// length) repaints the rotated image/stamp.
  void _rotateSelected(double radians) {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      if (sel is ImageAnnotation) {
        sel.rotation = radians;
      } else if (sel is StampAnnotation) {
        sel.rotation = radians;
      } else if (sel is TextAnnotation) {
        sel.rotation = radians;
      }
      _hasUnsavedChanges = true;
      _canvasRevision++;
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
    _prepareIfImage(_selected);
  }

  /// Quick colour picker for the selected text value.
  void _pickSelectedTextColor() async {
    final sel = _selected;
    if (sel is! TextAnnotation) return;
    final picked = await showEditorTextColorPickerSheet(context, selectedColor: sel.color, title: 'Text colour');
    if (picked == null) return;
    setState(() {
      _editorController.beginEdit([sel], label: 'Text colour');
      sel.color = picked;
      _editorController.commitEdit(_layer, force: true);
    });
  }

  void _duplicateSelected() {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _selected = _editorController.duplicateSelected(_layer, sel, _selection);
    });
    _prepareIfImage(_selected);
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
      _editorController.alignMulti(_multi, how, _selection, _bounds, _layer);
    });
  }

  void _distributeMulti(Axis axis) {
    if (_multi.length < 3) return;
    setState(() {
      _editorController.distributeMulti(_multi.toList(), axis, _selection, _bounds, _layer);
    });
  }

  void _deleteMulti() {
    setState(() {
      _editorController.deleteMulti(_layer, _multi);
      _multi.clear();
      _hasUnsavedChanges = true;
    });
    _schedulePersist();
  }

  void _duplicateMulti() {
    setState(() {
      final copies = _editorController.duplicateMulti(_layer, _multi, _selection);
      _multi
        ..clear()
        ..addAll(copies);
      for (final c in copies) {
        _prepareIfImage(c);
      }
      _hasUnsavedChanges = true;
    });
    _schedulePersist();
  }

  /// Add an annotation and reset the redo stack.
  void _pushItem(EditorAnnotation a, {int? page}) {
    final layer = page == null ? _layer : _layers.putIfAbsent(page, () => PageLayer());
    _editorController.pushAnnotation(layer, a, page: page);
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
    // Read the path now: the microtask can run after dispose(), when the
    // controller may no longer be read, and the last edits must still be saved.
    final path = _editorController.filePath;
    Future.microtask(() {
      _persistScheduled = false;
      final structure = _pageStructure;
      if (path != null && (_layers.isNotEmpty || !structure.isIdentity || _formValues.isNotEmpty)) {
        _persistence.save(filePath: path, layers: _layers, structure: structure, formValues: Map.of(_formValues));
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
            .showSnackBar(SnackBar(content: Text(l10n.overlayEditNotice)));
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
  /// Add a professional stamp (APPROVED, DRAFT, CONFIDENTIAL, …) to the page.
  Future<void> _addStamp() async {
    const choices = <StampKind>[
      StampKind.approved,
      StampKind.rejected,
      StampKind.confidential,
      StampKind.draft,
      StampKind.finalVersion,
      StampKind.paid,
      StampKind.voided,
      StampKind.urgent,
      StampKind.copy,
    ];
    final kind = await showModalBottomSheet<StampKind>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            for (final k in choices)
              ListTile(
                leading: const Icon(Icons.approval),
                title: Text(StampAnnotation.centered(kind: k, color: Colors.black).displayText),
                onTap: () => Navigator.pop(ctx, k),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    final color = switch (kind) {
      StampKind.approved || StampKind.paid || StampKind.finalVersion => Colors.green.shade700,
      StampKind.rejected || StampKind.voided || StampKind.urgent => Colors.red.shade700,
      _ => _color,
    };
    setState(() {
      final stamp = StampAnnotation.centered(kind: kind, color: color);
      _pushItem(stamp);
      _selected = stamp;
      _tool = EditTool.pan;
    });
  }

  /// Add an image (photo / logo / scanned signature) from device storage as a
  /// movable, resizable [ImageAnnotation].
  Future<void> _addImage() async {
    final picked = await _filePicker.pickSupportedFile();
    if (picked == null) return;
    try {
      final bytes = await File(picked.path).readAsBytes();
      // Decode once to learn the aspect ratio so the placed image isn't warped.
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final aspect = frame.image.height == 0
          ? 1.0
          : frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();

      final annotation = ImageAnnotation.centered(
        bytes: bytes,
        aspectRatio: aspect,
        label: picked.name,
      );
      // Decode + cache before it becomes visible so it paints immediately.
      await _imageRenderer.prepare(annotation);
      if (!mounted) return;
      setState(() {
        _pushItem(annotation);
        _selected = annotation;
        _tool = EditTool.pan;
      });
    } catch (e) {
      _showError('Could not add image: $e');
    }
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
  bool _inlineEditTxnOpen = false; // true when editing EXISTING text (undoable)
  TextSelection _inlineSelection = const TextSelection.collapsed(offset: 0);

  /// Whether the inline editor has a non-collapsed text selection (range).
  bool get _hasInlineSelection =>
      _inlineEditing != null && !_inlineSelection.isCollapsed;

  /// Apply bold toggle to the currently selected range in the inline editor.
  void _toggleSelectionBold() {
    final editing = _inlineEditing;
    if (editing == null || _inlineSelection.isCollapsed) return;
    setState(() {
      editing.runs = _richText.toggleBold(
          editing, _inlineSelection.start, _inlineSelection.end);
      _hasUnsavedChanges = true;
    });
  }

  void _toggleSelectionItalic() {
    final editing = _inlineEditing;
    if (editing == null || _inlineSelection.isCollapsed) return;
    setState(() {
      editing.runs = _richText.toggleItalic(
          editing, _inlineSelection.start, _inlineSelection.end);
      _hasUnsavedChanges = true;
    });
  }

  void _toggleSelectionUnderline() {
    final editing = _inlineEditing;
    if (editing == null || _inlineSelection.isCollapsed) return;
    setState(() {
      editing.runs = _richText.toggleUnderline(
          editing, _inlineSelection.start, _inlineSelection.end);
      _hasUnsavedChanges = true;
    });
  }

  Future<void> _pickSelectionColor() async {
    final editing = _inlineEditing;
    if (editing == null || _inlineSelection.isCollapsed) return;
    final picked = await showEditorTextColorPickerSheet(context, selectedColor: editing.color, title: 'Text colour');
    if (picked == null || !mounted) return;
    setState(() {
      editing.runs = _richText.applyStyle(
        editing,
        start: _inlineSelection.start,
        end: _inlineSelection.end,
        color: picked,
      );
      _hasUnsavedChanges = true;
    });
  }

  Future<void> _editTextBox(TextAnnotation box, {bool isNew = false}) async {
    // For NEW text boxes, use inline editing directly on the canvas.
    // For existing text, also use inline (replaces the modal dialog).
    if (isNew) {
      // Add the annotation first so it's in the layer. The AddCommand already
      // makes creation undoable, so no separate edit transaction is needed.
      if (!_layer.items.contains(box)) {
        _pushItem(box);
      }
      _inlineEditTxnOpen = false;
    } else {
      // Editing existing text — capture a single undoable edit step.
      _editorController.beginEdit([box], label: 'Edit text');
      _inlineEditTxnOpen = true;
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
        if (_inlineEditTxnOpen) {
          // Put the original text back, then delete that object so one undo
          // restores the box the user had before this edit.
          _editorController.revertOpenEdit();
          _editorController.deleteSelected(_layer, editing);
        } else if (_layer.items.contains(editing)) {
          // A brand-new box that was cleared should undo the add, not leave
          // an empty annotation stranded off the undo stack.
          _editorController.undo(_layer);
        }
      } else if (_inlineEditTxnOpen) {
        _editorController.commitEdit(_layer, force: true);
      }
      _inlineEditTxnOpen = false;
      _hasUnsavedChanges = true;
      _schedulePersist();
    });
  }

  void _onInlineTextChanged(String newText) {
    final editing = _inlineEditing;
    if (editing == null) return;
    if (editing.text != newText) {
      editing.runs = _richText.retarget(editing, newText);
      editing.text = newText;
    }
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
      _editorController.beginEdit([s], label: 'Shape style');
      if (_annotationEdit.applyShapeStyleResult(s, result)) {
        _editorController.commitEdit(_layer, force: true);
      } else {
        _editorController.cancelEdit();
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
        // Insert as a normal stroke annotation, then immediately select it and
        // switch to the pan tool so the user can drag it and resize it via the
        // selection handles — same behaviour as stamps / images / text boxes.
        final signature = _signatureInsert.signatureFromPadPoints(points!);
        _pushItem(signature);
        _selected = signature;
        _tool = EditTool.pan;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signature added — drag to move, use the corner handles to resize.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
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
        final aspect = _aspectFor(_current);
        _pageAspect[_current] = 1 / aspect;
        _pageQuarterTurns[_current] = ((_pageQuarterTurns[_current] ?? 0) + 1) % 4;
        // Saved with the marks, so recovery reopens the page turned.
        _hasUnsavedChanges = true;
        _schedulePersist();
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

  Future<String?> _renderToPdfFile({
    List<int>? onlyIndices,
    bool clearRecovery = true,
  }) async {
    final sourcePath = _editorController.filePath;
    final keepsSource = _doc != null && sourcePath != null && sourcePath.toLowerCase().endsWith('.pdf');
    if (keepsSource) {
      final hides = pagesThatHideContent(
        _layers,
        exportSlots(pageCount: _pageCount, only: onlyIndices),
      );
      if (hides.isNotEmpty && !await showEditorFlattenNoticeDialog(context, pages: hides)) {
        return null;
      }
      if (!mounted) return null;
    }
    _editorController.beginExport();
    setState(() {});
    try {
      String? outPath;
      if (keepsSource) {
        try {
          final result = await _exportService.renderPreservingPdfFile(
            sourcePath: sourcePath,
            doc: _doc,
            pageCache: _pageCache,
            layers: _layers,
            pageCount: _pageCount,
            quarterTurns: _pageQuarterTurns,
            sourcePages: _sourcePages,
            onlyIndices: onlyIndices,
            formValues: Map.of(_formValues),
            flattenedPageMarks: _formMarks(),
          );
          outPath = result.path;
        } on PreservingExportUnavailable catch (e) {
          // Never switch to an image-only file without asking.
          _editorController.finishExport();
          if (mounted) setState(() {});
          if (!mounted ||
              !await showEditorImageExportFallbackDialog(context, reason: _exportUnavailableText(e.kind))) {
            return null;
          }
          _editorController.beginExport();
          if (mounted) setState(() {});
          outPath = await _imageOnlyExport(onlyIndices);
        }
      } else {
        outPath = await _imageOnlyExport(onlyIndices);
      }
      if (outPath == null) {
        _editorController.finishExport(error: 'Nothing to export');
        _showError('Nothing to export');
      } else if (!File(outPath).existsSync() || File(outPath).lengthSync() < 32) {
        _editorController.finishExport(error: 'Export file was not written');
        _showError('Export file was not written');
        return null;
      } else {
        _editorController.finishExport();
        // Recovery data stays until the new file is actually on disk.
        final srcPath = _editorController.state.filePath;
        if (clearRecovery && srcPath != null) _persistence.delete(srcPath);
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

  /// Edited form values drawn as marks, for pages saved as images.
  Map<int, List<EditorAnnotation>> _formMarks() => formValueMarks(
        form: _form,
        edits: _formValues,
        sourcePages: _sourcePages,
        quarterTurns: _pageQuarterTurns,
      );

  /// An image-only file has no form: every page carries its edited values.
  Future<String?> _imageOnlyExport(List<int>? onlyIndices) {
    var layers = _layers;
    _formMarks().forEach((i, marks) => layers = withMarksBelow(layers, i, marks));
    return _exportService.renderToPdfFile(
        doc: _doc,
        pageCache: _pageCache,
        layers: layers,
        pageCount: _pageCount,
        quarterTurns: _pageQuarterTurns,
        sourcePages: _sourcePages,
        onlyIndices: onlyIndices,
      );
  }

  /// Save the edited PDF, then — right there at save time — offer to share it
  /// or continue straight into another tool (compress, convert, …). The saved
  /// file is handed off so the next tool opens it automatically (no re-picking).
  Future<void> _offerExportedFile(String outPath) async {
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

  Future<void> _export() async {
    final outPath = await _renderToPdfFile();
    if (outPath == null || !mounted) return;
    await _offerExportedFile(outPath);
  }

  /// The form fields on the shown page, or null when it has none.
  Widget? _formLayer() {
    if (_form.isEmpty || _current >= _sourcePages.length) return null;
    final source = _sourcePages[_current];
    // A duplicated page is exported without the form's widgets (they belong
    // to the first copy), so only the first copy shows the fields.
    if (source < 0 || _sourcePages.indexOf(source) != _current) return null;
    final turns = _pageQuarterTurns[_current] ?? 0;
    final placed = <PlacedAcroWidget>[
      for (final f in _form.fields)
        if (f.kind != AcroFieldKind.pushButton && f.kind != AcroFieldKind.signature)
          for (final w in f.widgets)
            if (w.pageIndex == source) (field: f, widget: w, rect: _form.rectOf(w, quarterTurns: turns)),
    ];
    if (placed.isEmpty) return null;
    return AcroFormLayer(
      widgets: placed,
      edits: _formValues,
      // Drawing tools keep drawing over fields; Move and Select fill them.
      interactive: (_tool == EditTool.pan || _tool == EditTool.select) && !_redactionController.isActive,
      onTap: _fillFormField,
    );
  }

  Future<void> _fillFormField(AcroField field, AcroWidget widget) async {
    final current = fieldValue(field, _formValues);
    final Object? next;
    switch (field.kind) {
      case AcroFieldKind.checkbox:
        next = current != 'Off' ? 'Off' : field.checkedState;
      case AcroFieldKind.radio:
        next = widget.onState ?? current;
      case AcroFieldKind.text:
        next = await showFormTextDialog(context, field: field, initial: '$current');
      case AcroFieldKind.choice:
        next = await showFormChoiceSheet(context, field: field, current: current);
      default:
        return;
    }
    if (next == null || !mounted) return;
    bool same(Object a, Object b) =>
        a is List && b is List ? a.length == b.length && a.every(b.contains) : a == b;
    if (same(next, current)) return;
    // Back to the file's value: drop the edit instead of storing a copy.
    final after = same(next, field.value) ? null : next;
    setState(() {
      _editorController.record(
        FormValueCommand(_formValues, field.name, before: _formValues[field.name], after: after),
        _layer,
      );
    });
    _schedulePersist();
  }

  ShapeType? _shapePreviewType() => _canvasInteraction.shapePreviewType(_tool);

  @override
  Widget build(BuildContext context) {
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
      // Prevent the Scaffold from shrinking when the soft keyboard opens.
      // The inline text editor uses Positioned overlays that handle their own
      // layout, so resizing the body causes the PDF viewport to collapse.
      resizeToAvoidBottomInset: false,
      appBar: EditorTopBar(
        title: _fileName ?? l10n.toolEditor,
        currentPage: _current,
        pageCount: _pageCount,
        hasDocument: bytes != null,
        canUndo: _editorController.canUndo,
        canRedo: _editorController.canRedo,
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
        searchBar: _searchController.state.active
            ? EditorSearchBar(
                searchState: _searchController.state,
                onQueryChanged: _onSearchQuery,
                onNext: () => _onSearchStep(_searchController.next),
                onPrevious: () => _onSearchStep(_searchController.previous),
                onClose: () => setState(() => _searchController.close()),
                onCaseSensitiveChanged: (v) => setState(() => _searchController.setCaseSensitive(v)),
                onWholeWordChanged: (v) => setState(() => _searchController.setWholeWord(v)),
              )
            : null,
        textSelectionBar: _wordSelection != null && _wordSelection!.isNotEmpty
            ? EditorTextSelectionBar(
                onCopy: _copyWords,
                onEdit: _editSelectedWords,
                onMarkup: _markSelection,
                onClose: () => setState(() => _wordSelection = null),
              )
            : null,
        outlinePanel: _outlineController.state.visible
            ? EditorOutlinePanel(
                outlineState: _outlineController.state,
                onJumpToPage: _goToPage,
                onToggleNode: (n) => setState(() => _outlineController.toggleNode(n)),
                onExpandAll: () => setState(() => _outlineController.expandAll()),
                onCollapseAll: () => setState(() => _outlineController.collapseAll()),
                onClose: () => setState(() => _outlineController.hide()),
              )
            : null,
        layerPanel: _layerController.state.visible
            ? EditorLayerPanel(
                // Read from the marks on every build, so the rows always
                // match the page, its undo state and page changes.
                layerState: EditorLayerState(
                  visible: true,
                  layers: EditorLayerController.layersOf(_layers[_current]),
                ),
                onToggleVisibility: (id) =>
                    _changeLayers((p) => EditorLayerController.toggleVisibility(p, _layerKind(id))),
                onToggleLock: (id) => _changeLayers((p) => EditorLayerController.toggleLock(p, _layerKind(id))),
                onShowAll: () => _changeLayers((p) => EditorLayerController.setAllVisible(p, true)),
                onHideAll: () => _changeLayers((p) => EditorLayerController.setAllVisible(p, false)),
                onClose: () => setState(() => _layerController.hide()),
              )
            : null,
        formReviewPanel: _formReviewController.state.visible
            ? EditorFormReviewPanel(
                reviewState: _formReviewController.state,
                onAccept: (id) => setState(() => _formReviewController.acceptField(id)),
                onReject: (id) => setState(() => _formReviewController.rejectField(id)),
                onAcceptAllValid: () => setState(() => _formReviewController.acceptAllValid()),
                onRejectAllPending: () => setState(() => _formReviewController.rejectAllPending()),
                onApply: () {
                  _formReviewController.beginApply();
                  setState(() => _formReviewController.finishApply());
                },
                onClose: () => setState(() => _formReviewController.hide()),
              )
            : null,
        inlineOverlay: _inlineEditing != null
            ? Positioned.fill(
                bottom: 96,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final editing = _inlineEditing!;
                    final fitted = PageFit.box(
                      maxWidth: constraints.maxWidth,
                      maxHeight: constraints.maxHeight,
                      aspect: _aspectFor(_current),
                    );
                    final origin = PageCoordinateTransform.zoomedPagePoint(
                      norm: editing.pos,
                      pageLeft: fitted.left,
                      pageTop: fitted.top,
                      pageSize: Size(fitted.width, fitted.height),
                      zoom: _viewTransform.value,
                    );
                    final scale = PageCoordinateTransform.uniformScale(_viewTransform.value);
                    final pageW = fitted.width * scale;
                    final pageH = fitted.height * scale;
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
                          left: origin.dx,
                          top: origin.dy,
                          width: (pageW * (1 - editing.pos.dx)).clamp(50.0, pageW),
                          child: InlineTextEditor(
                            annotation: editing,
                            canvasSize: Size(pageW, pageH),
                            onDone: _commitInlineEdit,
                            onTextChanged: _onInlineTextChanged,
                            onSelectionChanged: (sel) =>
                                setState(() => _inlineSelection = sel),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              )
            : null,
        documentViewport: EditorDocumentViewport(
          panEnabled: _tool == EditTool.pan && !_redactionController.state.active,
          scaleEnabled: !_redactionController.state.active,
          pageAspect: _aspectFor(_current),
          transformationController: _viewTransform,
          viewFilter: ReadingModeState(mode: _readingMode).colorFilter,
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
            highlightPreview: false,
            securePreview: _redactionController.state.active,
            markupPreview: _markupPreview,
            markupKind: _markupFactory.kindFor(_tool),
            findRects: _findRects(),
            activeFind: _activeFindIndex(),
            wordSelection: _wordSelection?.rects ?? const [],
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
            imageRenderer: _imageRenderer,
            stampRenderer: _stampRenderer,
            canvasRevision: _canvasRevision,
            formLayer: _formLayer(),
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
            onMoveTextStart: (t) {
              setState(() => _selected = t);
              _editorController.beginEdit([t], label: 'Move text');
            },
            onMoveTextEnd: () => setState(() => _editorController.commitEdit(_layer)),
            onResizeStart: () {
              final sel = _selected;
              if (sel != null) _editorController.beginEdit([sel], label: 'Resize');
            },
            onResizeEnd: () => setState(() => _editorController.commitEdit(_layer)),
            onResizeBounds: _scaleSelectedTo,
            onRotateStart: () {
              final sel = _selected;
              if (sel != null) _editorController.beginEdit([sel], label: 'Rotate');
            },
            onRotate: _rotateSelected,
            onRotateEnd: () => setState(() => _editorController.commitEdit(_layer, force: true)),
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
            onNoteTap: _editNote,
            onNoteDelete: _deleteNote,
            onAlignMulti: _alignMulti,
            onDistributeMulti: _distributeMulti,
            onDuplicateMulti: _duplicateMulti,
            onDeleteMulti: _deleteMulti,
            onDeselectMulti: () => setState(() => _multi.clear()),
            resolveTypeIcon: _typeIcon,
          ),
        ),
        richTextToolbar: EditorRichTextToolbar(
          hasFocus: _inlineEditing != null,
          hasSelection: _hasInlineSelection,
          onBold: _toggleSelectionBold,
          onItalic: _toggleSelectionItalic,
          onUnderline: _toggleSelectionUnderline,
          onColor: _pickSelectionColor,
        ),
        pageOpsDialog: _pageOpsController.state.visible
            ? EditorPageOpsDialog(
                pageOpsState: _pageOpsController.state,
                onRangeChanged: (value) => setState(() => _pageOpsController.setRangeSpec(value)),
                onOperationChanged: (op) => setState(() => _pageOpsController.setOperation(op)),
                onSelectAll: () => setState(() => _pageOpsController.selectAll()),
                onConfirm: _confirmPageOps,
                onClose: () => setState(() => _pageOpsController.hide()),
              )
            : null,
        thumbnailStrip: _pageCount > 1
            ? EditorPageThumbnailStrip(
                pageCount: _pageCount,
                currentPage: _current,
                pageCache: _pageCache,
                onPageTap: _goToPage,
                onPageAction: _onPageAction,
              )
            : null,
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
          onToolChanged: (tool) => setState(() {
            final enteringHighlight =
                tool == EditTool.highlight && _tool != EditTool.highlight;
            _tool = tool;
            _markupPreview = const [];
            _wordSelection = null;
            _shapeStart = null;
            _shapeEnd = null;
            if (enteringHighlight && _color == Colors.red) {
              _color = const Color(0xFFFFEB3B);
            }
          }),
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
          onSearch: _toggleSearch,
          onRedact: _toggleRedaction,
          onOutline: _toggleOutline,
          onChat: _toggleChat,
          onLayers: _toggleLayers,
          onPageOps: _showPageOps,
          onReadingMode: _chooseReadingMode,
          onColorChanged: (c) => setState(() => _color = c),
          recentColors: RecentColors.current,
          onPickColor: () async {
            final c = await showEditorTextColorPickerSheet(context, selectedColor: _color);
            if (c != null && mounted) setState(() => _color = c);
          },
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
