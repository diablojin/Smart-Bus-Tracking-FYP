/// Model class representing an announcement from the Supabase announcements table.
class Announcement {
  final String id;
  final String title;
  final String? subtitle;
  final String category;
  final DateTime createdAt;

  Announcement({
    required this.id,
    required this.title,
    this.subtitle,
    required this.category,
    required this.createdAt,
  });

  /// Creates an Announcement instance from a Supabase row map.
  factory Announcement.fromMap(Map<String, dynamic> map) {
    return Announcement(
      id: map['id'] as String,
      title: map['title'] as String,
      subtitle: map['subtitle'] as String?,
      category: map['category'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Converts the Announcement to a map (useful for debugging or local storage).
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'category': category,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

