class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    this.createdAt,
  });

  final String id;
  final String displayName;
  final DateTime? createdAt;

  factory Profile.fromMap(Map<String, dynamic> map) {
    final rawName = map['display_name'] as String?;
    final displayName =
        rawName != null && rawName.trim().isNotEmpty ? rawName.trim() : 'Guest';
    return Profile(
      id: map['id'].toString(),
      displayName: displayName,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.parse(map['created_at'] as String),
    );
  }
}
