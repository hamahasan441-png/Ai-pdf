import 'dart:ui' show Offset, Rect;

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/services/annotation_bounds_service.dart';

/// Service for grouping and ungrouping annotations.
///
/// Grouping means treating multiple annotations as a single unit for:
/// - Move (drag one → all move together)
/// - Delete (delete group → deletes all members)
/// - Duplicate (duplicates the whole group)
/// - Bring to front / send to back
///
/// Groups are stored as a Map<String, Set<String>> (groupId → member annotation ids).
/// This is separate from the annotation model itself (no base class change needed).
class AnnotationGroupService {
  const AnnotationGroupService();

  /// Create a new group from the selected annotations.
  /// Returns the group ID.
  String createGroup(
    Set<EditorAnnotation> annotations,
    Map<String, Set<String>> groups,
  ) {
    if (annotations.length < 2) return '';
    final groupId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    groups[groupId] = annotations.map((a) => a.id).toSet();
    return groupId;
  }

  /// Ungroup: remove the group, annotations become independent.
  void ungroup(String groupId, Map<String, Set<String>> groups) {
    groups.remove(groupId);
  }

  /// Find which group an annotation belongs to (if any).
  String? findGroup(String annotationId, Map<String, Set<String>> groups) {
    for (final entry in groups.entries) {
      if (entry.value.contains(annotationId)) return entry.key;
    }
    return null;
  }

  /// Get all annotation IDs in the same group as [annotationId].
  Set<String> groupMembers(String annotationId, Map<String, Set<String>> groups) {
    final groupId = findGroup(annotationId, groups);
    if (groupId == null) return {annotationId};
    return groups[groupId] ?? {annotationId};
  }

  /// Compute the bounding box of a group (union of all member bounds).
  Rect groupBounds(
    Set<String> memberIds,
    List<EditorAnnotation> allAnnotations,
    AnnotationBoundsService bounds,
  ) {
    Rect? result;
    for (final a in allAnnotations) {
      if (!memberIds.contains(a.id)) continue;
      final b = bounds.boundsOf(a);
      result = result == null ? b : result.expandToInclude(b);
    }
    return result ?? Rect.zero;
  }

  /// Move all members of a group by a normalised delta.
  void moveGroup(
    Set<String> memberIds,
    Offset delta,
    List<EditorAnnotation> allAnnotations,
  ) {
    for (final a in allAnnotations) {
      if (!memberIds.contains(a.id)) continue;
      if (a is TextAnnotation) {
        a.pos = Offset(a.pos.dx + delta.dx, a.pos.dy + delta.dy);
      } else if (a is ShapeAnnotation) {
        a.start = Offset(a.start.dx + delta.dx, a.start.dy + delta.dy);
        a.end = Offset(a.end.dx + delta.dx, a.end.dy + delta.dy);
      }
    }
  }

  /// Remove a group and clean up references when members are deleted.
  void cleanupDeletedMembers(
    Set<String> deletedIds,
    Map<String, Set<String>> groups,
  ) {
    final emptyGroups = <String>[];
    for (final entry in groups.entries) {
      entry.value.removeAll(deletedIds);
      if (entry.value.length < 2) emptyGroups.add(entry.key);
    }
    for (final id in emptyGroups) {
      groups.remove(id);
    }
  }
}
