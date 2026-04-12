class Cast {
  const Cast({
    required this.name,
    required this.characterName,
    required this.avatarUrl,
  });

  final String name;
  final String characterName;
  final String avatarUrl;

  factory Cast.fromJson(Map<String, dynamic> json) {
    return Cast(
      name: (json['name'] ?? '').toString(),
      characterName:
          (json['characterName'] ?? json['character_name'] ?? '').toString(),
      avatarUrl: (json['avatarUrl'] ?? json['avatar_url'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'characterName': characterName,
      'avatarUrl': avatarUrl,
    };
  }
}
