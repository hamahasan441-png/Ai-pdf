/// A folder in the document library (Phase: Document Library).
///
/// Flat hierarchy (no nesting) for simplicity — like iOS Files "Recents" / Tags
/// approach rather than deep file-system trees.
class LibraryFolder {
  final String id;
  final String name;
  final String? color;
  final String? icon;
  final DateTime createdAt;
  final int itemCount;

  const LibraryFolder({
    required this.id,
    required this.name,
    this.color,
    this.icon,
    required this.createdAt,
    this.itemCount = 0,
  });

  LibraryFolder copyWith({
    String? name,
    String? color,
    String? icon,
    int? itemCount,
  }) =>
      LibraryFolder(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        icon: icon ?? this.icon,
        createdAt: createdAt,
        itemCount: itemCount ?? this.itemCount,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'icon': icon,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory LibraryFolder.fromJson(Map<String, dynamic> j) => LibraryFolder(
        id: j['id'] as String,
        name: j['name'] as String,
        color: j['color'] as String?,
        icon: j['icon'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int),
      );
}
