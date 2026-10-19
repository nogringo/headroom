class Thought {
  const Thought({
    required this.id,
    required this.text,
    this.image,
    required this.createdAt,
  });

  factory Thought.fromJson(Map<String, dynamic> json) => Thought(
    id: json['id'] as String,
    text: json['text'] as String,
    image: json['image'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
  );

  final String id;

  /// Empty when the thought is only an image.
  final String text;

  /// Name of the image in the storage, if any.
  final String? image;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
    'id': id,
    'text': text,
    'image': ?image,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}
