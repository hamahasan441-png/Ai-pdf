/// A document in the user's library (Phase: Document Library).
///
/// Represents a PDF, image, or scan stored on-device. Carries metadata for
/// display, search, sorting, and organization (folders, tags, favorites).
/// Immutable value type — mutations produce a new instance.
class LibraryItem {
  final String id;
  final String name;
  final String path;
  final LibraryItemType type;
  final int sizeBytes;
  final int pageCount;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final DateTime? lastOpenedAt;
  final String? folderId;
  final Set<String> tags;
  final bool isFavorite;
  final bool isPinned;
  final String? thumbnailPath;

  const LibraryItem({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.sizeBytes,
    this.pageCount = 1,
    required this.createdAt,
    required this.modifiedAt,
    this.lastOpenedAt,
    this.folderId,
    this.tags = const {},
    this.isFavorite = false,
    this.isPinned = false,
    this.thumbnailPath,
  });

  String get extension => name.contains('.') ? name.split('.').last.toLowerCase() : '';
  bool get isPdf => type == LibraryItemType.pdf;
  bool get isImage => type == LibraryItemType.image;
  bool get isScan => type == LibraryItemType.scan;

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  LibraryItem copyWith({
    String? name,
    String? path,
    int? sizeBytes,
    int? pageCount,
    DateTime? modifiedAt,
    DateTime? lastOpenedAt,
    String? folderId,
    Set<String>? tags,
    bool? isFavorite,
    bool? isPinned,
    String? thumbnailPath,
    bool clearFolder = false,
  }) =>
      LibraryItem(
        id: id,
        name: name ?? this.name,
        path: path ?? this.path,
        type: type,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        pageCount: pageCount ?? this.pageCount,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
        folderId: clearFolder ? null : (folderId ?? this.folderId),
        tags: tags ?? this.tags,
        isFavorite: isFavorite ?? this.isFavorite,
        isPinned: isPinned ?? this.isPinned,
        thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      );

  /// Serialization for SQLite/SharedPreferences persistence.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'type': type.index,
        'sizeBytes': sizeBytes,
        'pageCount': pageCount,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'modifiedAt': modifiedAt.millisecondsSinceEpoch,
        'lastOpenedAt': lastOpenedAt?.millisecondsSinceEpoch,
        'folderId': folderId,
        'tags': tags.toList(),
        'isFavorite': isFavorite,
        'isPinned': isPinned,
        'thumbnailPath': thumbnailPath,
      };

  factory LibraryItem.fromJson(Map<String, dynamic> j) => LibraryItem(
        id: j['id'] as String,
        name: j['name'] as String,
        path: j['path'] as String,
        type: LibraryItemType.values[j['type'] as int],
        sizeBytes: j['sizeBytes'] as int,
        pageCount: j['pageCount'] as int? ?? 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int),
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(j['modifiedAt'] as int),
        lastOpenedAt: j['lastOpenedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['lastOpenedAt'] as int)
            : null,
        folderId: j['folderId'] as String?,
        tags: (j['tags'] as List?)?.cast<String>().toSet() ?? const {},
        isFavorite: j['isFavorite'] as bool? ?? false,
        isPinned: j['isPinned'] as bool? ?? false,
        thumbnailPath: j['thumbnailPath'] as String?,
      );
}

enum LibraryItemType { pdf, image, scan }
