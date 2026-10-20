class Thought {
  Thought({
    required this.id,
    required this.text,
    this.images = const [],
    required this.createdAt,
    this.theme,
    this.themeChosen = false,
    int? rank,
  }) : rank = rank ?? createdAt.microsecondsSinceEpoch;

  factory Thought.fromJson(Map<String, dynamic> json) => Thought(
    id: json['id'] as String,
    text: json['text'] as String,
    images: [
      ...?(json['images'] as List<dynamic>?)?.cast<String>(),
      // Written before a thought could hold several images.
      if (json['image'] case final String image) image,
    ],
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    theme: json['theme'] as String?,
    themeChosen: json['themeChosen'] == true,
    rank: json['rank'] as int?,
  );

  final String id;

  /// Empty when the thought is only images.
  final String text;

  /// Names of the images in the storage, in the order they were added.
  final List<String> images;
  final DateTime createdAt;

  /// Given by the AI, or chosen by the person. Null until either has.
  final String? theme;

  /// Whether the person chose [theme], which the AI then leaves alone.
  final bool themeChosen;

  /// Its place in its theme, which lists the highest first. The time it was
  /// noted, in microseconds, until the person moves it.
  final int rank;

  Map<String, Object> toJson() => {
    'id': id,
    'text': text,
    if (images.isNotEmpty) 'images': images,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (theme case final String theme) 'theme': theme,
    if (themeChosen) 'themeChosen': true,
    if (rank != createdAt.microsecondsSinceEpoch) 'rank': rank,
  };
}
