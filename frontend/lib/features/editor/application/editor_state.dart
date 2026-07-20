import 'package:flutter/material.dart';
import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Immutable application state for the editor screen.
///
/// Everything the UI needs to render is here. The editor controller mutates
/// this via [copyWith]; widgets rebuild only when the fields they read change.
///
/// ### What lives here vs elsewhere
/// - Annotation data → [PageLayer] objects (owned by the controller, NOT here)
/// - Undo/redo stack → [HistoryStack] (owned by the controller, NOT here)
/// - This class holds: loading flags, current page, tool selection,
///   style properties, selection state, snap guides, UI mode flags.
class EditorState {
  // ── Document ─────────────────────────────────────────────────────────────
  final bool loading;
  final bool exporting;
  final int currentPage;
  final int pageCount;
  final bool hasUnsavedChanges;
  final String? filePath;
  final String? fileName;
  final String? error;

  // ── Undo / redo availability (mirrors HistoryStack, for UI buttons) ──────
  final bool canUndo;
  final bool canRedo;
  final String? undoDescription;
  final String? redoDescription;

  // ── Active tool + style ──────────────────────────────────────────────────
  final EditTool tool;
  final Color penColor;
  final double penStroke;
  final double textSize; // pt
  final bool textBold;
  final bool textItalic;
  final bool textUnderline;
  final String? textFontFamily;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final double textLineHeight;
  final Color? textBackgroundColor;

  // ── Selection ────────────────────────────────────────────────────────────
  final String? selectedId;   // single selection — stable annotation id
  final Set<String> multiIds; // multi-selection — set of ids

  // ── Snap guides ──────────────────────────────────────────────────────────
  final double? guideX;
  final double? guideY;

  // ── UI mode flags ────────────────────────────────────────────────────────
  final bool showFieldOverlay;    // OCR-detected field badges
  final bool showEditLineOverlay; // OCR edit-line highlights
  final bool detectingFields;     // OCR/AI field detection in progress
  final String? detectingLabel;

  // ── Zoom / pan ───────────────────────────────────────────────────────────
  final double zoom;

  const EditorState({
    this.loading = false,
    this.exporting = false,
    this.currentPage = 0,
    this.pageCount = 0,
    this.hasUnsavedChanges = false,
    this.filePath,
    this.fileName,
    this.error,
    this.canUndo = false,
    this.canRedo = false,
    this.undoDescription,
    this.redoDescription,
    this.tool = EditTool.pan,
    this.penColor = const Color(0xFF1E293B),
    this.penStroke = 3.0,
    this.textSize = 14.0,
    this.textBold = false,
    this.textItalic = false,
    this.textUnderline = false,
    this.textFontFamily,
    this.textAlign = TextAlign.left,
    this.textDirection,
    this.textLineHeight = 1.2,
    this.textBackgroundColor,
    this.selectedId,
    this.multiIds = const {},
    this.guideX,
    this.guideY,
    this.showFieldOverlay = false,
    this.showEditLineOverlay = false,
    this.detectingFields = false,
    this.detectingLabel,
    this.zoom = 1.0,
  });

  bool get hasSelection => selectedId != null;
  bool get hasMultiSelection => multiIds.isNotEmpty;
  bool get isIdle => !loading && !exporting && !detectingFields;

  EditorState copyWith({
    bool? loading,
    bool? exporting,
    int? currentPage,
    int? pageCount,
    bool? hasUnsavedChanges,
    String? filePath,
    String? fileName,
    String? error,
    bool clearError = false,
    bool? canUndo,
    bool? canRedo,
    String? undoDescription,
    String? redoDescription,
    EditTool? tool,
    Color? penColor,
    double? penStroke,
    double? textSize,
    bool? textBold,
    bool? textItalic,
    bool? textUnderline,
    String? textFontFamily,
    bool clearTextFont = false,
    TextAlign? textAlign,
    TextDirection? textDirection,
    bool clearTextDirection = false,
    double? textLineHeight,
    Color? textBackgroundColor,
    bool clearTextBackground = false,
    String? selectedId,
    bool clearSelection = false,
    Set<String>? multiIds,
    double? guideX,
    bool clearGuideX = false,
    double? guideY,
    bool clearGuideY = false,
    bool? showFieldOverlay,
    bool? showEditLineOverlay,
    bool? detectingFields,
    String? detectingLabel,
    bool clearDetectingLabel = false,
    double? zoom,
  }) {
    return EditorState(
      loading: loading ?? this.loading,
      exporting: exporting ?? this.exporting,
      currentPage: currentPage ?? this.currentPage,
      pageCount: pageCount ?? this.pageCount,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      error: clearError ? null : (error ?? this.error),
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      undoDescription: undoDescription ?? this.undoDescription,
      redoDescription: redoDescription ?? this.redoDescription,
      tool: tool ?? this.tool,
      penColor: penColor ?? this.penColor,
      penStroke: penStroke ?? this.penStroke,
      textSize: textSize ?? this.textSize,
      textBold: textBold ?? this.textBold,
      textItalic: textItalic ?? this.textItalic,
      textUnderline: textUnderline ?? this.textUnderline,
      textFontFamily: clearTextFont ? null : (textFontFamily ?? this.textFontFamily),
      textAlign: textAlign ?? this.textAlign,
      textDirection:
          clearTextDirection ? null : (textDirection ?? this.textDirection),
      textLineHeight: textLineHeight ?? this.textLineHeight,
      textBackgroundColor:
          clearTextBackground ? null : (textBackgroundColor ?? this.textBackgroundColor),
      selectedId: clearSelection ? null : (selectedId ?? this.selectedId),
      multiIds: multiIds ?? this.multiIds,
      guideX: clearGuideX ? null : (guideX ?? this.guideX),
      guideY: clearGuideY ? null : (guideY ?? this.guideY),
      showFieldOverlay: showFieldOverlay ?? this.showFieldOverlay,
      showEditLineOverlay: showEditLineOverlay ?? this.showEditLineOverlay,
      detectingFields: detectingFields ?? this.detectingFields,
      detectingLabel:
          clearDetectingLabel ? null : (detectingLabel ?? this.detectingLabel),
      zoom: zoom ?? this.zoom,
    );
  }
}
