import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/domain/entities/editor_mode.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_design.dart';

/// An entry of the top bar's menu.
class EditorMenuAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const EditorMenuAction(this.icon, this.label, this.onTap);
}

/// The editor's top bar: back, the document (or workspace) name, and only
/// the actions the current workspace needs. Reading shows search, share and
/// a menu; the editing workspaces show undo, redo and Done.
class EditorTopBar extends StatelessWidget {
  static const double height = 56;

  final EditorMode mode;
  final String title;

  /// A quiet second line: the page, the file or what to do.
  final String? subtitle;
  final bool hasDocument;
  final bool canUndo;
  final bool canRedo;
  final bool canPaste;
  final bool loading;

  /// Shows a quiet dot so the user always knows whether the work is saved.
  final bool unsavedChanges;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onPaste;
  final VoidCallback? onExport;
  final VoidCallback? onSearch;

  /// Leaves an editing workspace (back to reading).
  final VoidCallback? onDone;
  final List<EditorMenuAction> menu;

  const EditorTopBar({
    super.key,
    required this.mode,
    required this.title,
    this.subtitle,
    required this.hasDocument,
    required this.canUndo,
    required this.canRedo,
    required this.canPaste,
    required this.loading,
    this.unsavedChanges = false,
    this.onUndo,
    this.onRedo,
    this.onPaste,
    this.onExport,
    this.onSearch,
    this.onDone,
    this.menu = const [],
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = EditorPalette.of(context);
    final reading = mode == EditorMode.view;
    final fg = palette.barForeground;
    return Material(
      color: palette.barSurface,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.hairline))),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: height,
            child: IconTheme(
              data: IconThemeData(color: fg, size: 22),
              child: Row(
                children: [
                  BackButton(color: fg),
                  Expanded(child: _title(context, palette)),
                  if (hasDocument) ...[
                    if (canPaste)
                      IconButton(
                        icon: const Icon(Icons.content_paste_outlined),
                        tooltip: l10n.shortcutPaste,
                        onPressed: onPaste,
                      ),
                    if (reading) ...[
                      if (onSearch != null)
                        IconButton(icon: const Icon(Icons.search), tooltip: l10n.toolFind, onPressed: onSearch),
                      if (canUndo) IconButton(icon: const Icon(Icons.undo), tooltip: l10n.undo, onPressed: onUndo),
                    IconButton(
                        icon: const Icon(Icons.ios_share),
                        tooltip: l10n.export,
                        onPressed: loading ? null : onExport,
                      ),
                      if (menu.isNotEmpty) _menu(l10n, palette),
                    ] else ...[
                      IconButton(
                        icon: const Icon(Icons.undo),
                        tooltip: l10n.undo,
                        onPressed: canUndo ? onUndo : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.redo),
                        tooltip: l10n.redo,
                        onPressed: canRedo ? onRedo : null,
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 2, end: 10),
                        child: FilledButton(
                          onPressed: onDone,
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.accent,
                            foregroundColor: palette.onAccent,
                            minimumSize: const Size(72, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          child: Text(l10n.done),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(BuildContext context, EditorPalette palette) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: palette.barForeground),
              ),
            ),
            if (unsavedChanges) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: l10n.unsavedChangesDot,
                child: Container(
                  width: 12,
                  height: 12,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColorsDot.of(context).withValues(alpha: 0.45), width: 2),
                  ),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: AppColorsDot.of(context), shape: BoxShape.circle),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: palette.barMuted),
          ),
      ],
    );
  }

  Widget _menu(AppLocalizations l10n, EditorPalette palette) {
    return PopupMenuButton<int>(
      tooltip: l10n.moreActions,
      icon: Icon(Icons.more_vert, color: palette.barForeground),
      shape: EditorChrome.menuShape,
      onSelected: (i) => menu[i].onTap(),
      itemBuilder: (_) => [
        for (var i = 0; i < menu.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Row(children: [
              Icon(menu[i].icon, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(menu[i].label)),
            ]),
          ),
      ],
    );
  }
}

/// The unsaved-changes dot colour: the calm accent in both themes.
class AppColorsDot {
  static Color of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF63CFC2) : const Color(0xFF2BB5A6);
}
