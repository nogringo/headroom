class Thought {
  const Thought({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  factory Thought.fromJson(Map<String, dynamic> json) => Thought(
    id: json['id'] as String,
    text: json['text'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
  );

  final String id;
  final String text;
  final DateTime createdAt;

  Thought copyWith({String? text}) =>
      Thought(id: id, text: text ?? this.text, createdAt: createdAt);

  Map<String, Object> toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}
