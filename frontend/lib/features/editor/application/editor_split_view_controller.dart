import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Layout mode for the split view (Phase 47).
enum SplitViewMode {
  /// Single page (default editor mode).
  single,

  /// Two pages side by side (landscape reading / comparison).
  sideBySide,

  /// One page above the other (portrait tablet).
  stacked,
}

/// UI state for the split-view dual-page feature (Phase 47).
class EditorSplitViewState {
  final SplitViewMode mode;
  final int leftPage;
  final int rightPage;
  final bool syncScroll;
  final int pageCount;

  const EditorSplitViewState({
    this.mode = SplitViewMode.single,
    this.leftPage = 0,
    this.rightPage = 1,
    this.syncScroll = true,
    this.pageCount = 1,
  });

  bool get isSplit => mode != SplitViewMode.single;
  bool get canSplit => pageCount >= 2;

  /// The two visible pages as a list (single mode returns just the left page).
  List<int> get visiblePages =>
      isSplit ? [leftPage, rightPage] : [leftPage];

  EditorSplitViewState copyWith({
    SplitViewMode? mode,
    int? leftPage,
    int? rightPage,
    bool? syncScroll,
    int? pageCount,
  }) =>
      EditorSplitViewState(
        mode: mode ?? this.mode,
        leftPage: leftPage ?? this.leftPage,
        rightPage: rightPage ?? this.rightPage,
        syncScroll: syncScroll ?? this.syncScroll,
        pageCount: pageCount ?? this.pageCount,
      );
}

/// Controller for the split-view dual-page feature (Phase 47).
///
/// Allows the user to view two pages simultaneously: side-by-side (landscape
/// tablets / desktop) or stacked (portrait). Each pane is independently
/// navigable, but optionally scroll-synced. The primary use case is comparing
/// two pages of the same document or reading a two-page spread.
final editorSplitViewProvider =
    StateNotifierProvider<EditorSplitViewController, EditorSplitViewState>(
        (ref) => EditorSplitViewController());

class EditorSplitViewController extends StateNotifier<EditorSplitViewState> {
  EditorSplitViewController() : super(const EditorSplitViewState());

  void setPageCount(int count) {
    state = state.copyWith(pageCount: count);
    _clampPages();
  }

  void setMode(SplitViewMode mode) {
    if (mode != SplitViewMode.single && state.pageCount < 2) return;
    state = state.copyWith(mode: mode);
    if (mode != SplitViewMode.single && state.leftPage == state.rightPage) {
      // Ensure different pages when entering split.
      final right = (state.leftPage + 1).clamp(0, state.pageCount - 1);
      state = state.copyWith(rightPage: right);
    }
  }

  void toggleSplit() {
    if (state.isSplit) {
      setMode(SplitViewMode.single);
    } else {
      setMode(SplitViewMode.sideBySide);
    }
  }

  void toggleSyncScroll() =>
      state = state.copyWith(syncScroll: !state.syncScroll);

  void setLeftPage(int page) {
    state = state.copyWith(leftPage: page.clamp(0, state.pageCount - 1));
  }

  void setRightPage(int page) {
    state = state.copyWith(rightPage: page.clamp(0, state.pageCount - 1));
  }

  /// Navigate both panes as a spread (left=N, right=N+1).
  void goToSpread(int leftPage) {
    final left = leftPage.clamp(0, state.pageCount - 1);
    final right = (left + 1).clamp(0, state.pageCount - 1);
    state = state.copyWith(leftPage: left, rightPage: right);
  }

  /// Move the spread forward by 2 pages.
  void nextSpread() => goToSpread(state.leftPage + 2);

  /// Move the spread backward by 2 pages.
  void previousSpread() => goToSpread(state.leftPage - 2);

  void _clampPages() {
    final max = (state.pageCount - 1).clamp(0, state.pageCount);
    state = state.copyWith(
      leftPage: state.leftPage.clamp(0, max),
      rightPage: state.rightPage.clamp(0, max),
    );
  }
}
