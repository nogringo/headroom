/// A step of a thought, which the person ticks off.
typedef Subtask = ({String text, bool done});

class Thought {
  Thought({
    required this.id,
    required this.text,
    this.delta = const [],
    this.images = const [],
    required this.createdAt,
    this.themes = const [],
    this.themesChosen = false,
    this.title,
    this.subtasks = const [],
    this.ranks = const {},
  });

  factory Thought.fromJson(Map<String, dynamic> json) {
    // Written while a thought had a single theme, and a single rank in it.
    final theme = json['theme'] as String?;
    return Thought(
      id: json['id'] as String,
      text: json['text'] as String,
      delta: [
        ...?(json['delta'] as List<dynamic>?)?.cast<Map<String, dynamic>>(),
      ],
      images: [
        ...?(json['images'] as List<dynamic>?)?.cast<String>(),
        // Written before a thought could hold several images.
        if (json['image'] case final String image) image,
      ],
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      themes: [...?(json['themes'] as List<dynamic>?)?.cast<String>(), ?theme],
      themesChosen: json['themesChosen'] == true || json['themeChosen'] == true,
      title: json['title'] as String?,
      subtasks: [
        if (json['subtasks'] case final List<dynamic> subtasks)
          for (final subtask in subtasks.cast<Map<String, dynamic>>())
            (text: subtask['text'] as String, done: subtask['done'] == true),
      ],
      ranks: {
        ...?(json['ranks'] as Map<String, dynamic>?)?.cast<String, int>(),
        if (json['rank'] case final int rank) theme ?? '': rank,
      },
    );
  }

  final String id;

  /// Empty when the thought is only images. Kept as written, whatever the AI
  /// makes of it.
  final String text;

  /// The [text] with its formatting, as Quill Delta operations. Empty when it
  /// has none.
  final List<Map<String, dynamic>> delta;

  /// Names of the images in the storage, in the order they were added.
  final List<String> images;
  final DateTime createdAt;

  /// Given by the AI, or chosen by the person. Empty until either has.
  final List<String> themes;

  /// Whether the person chose [themes], which the AI then leaves alone.
  final bool themesChosen;

  /// The AI's few words for a long thought, listed in place of its text.
  final String? title;

  /// The steps the AI found in it.
  final List<Subtask> subtasks;

  /// Its place in the themes the person moved it in, '' for the thoughts
  /// without one. See [rankIn].
  final Map<String, int> ranks;

  /// Its place in [theme], which lists the highest first. The time it was
  /// noted, in microseconds, until the person moves it.
  int rankIn(String theme) => ranks[theme] ?? createdAt.microsecondsSinceEpoch;

  /// Null keeps what this thought has.
  Thought copyWith({
    String? text,
    List<Map<String, dynamic>>? delta,
    List<String>? images,
    List<String>? themes,
    bool? themesChosen,
    String? title,
    List<Subtask>? subtasks,
    Map<String, int>? ranks,
  }) => Thought(
    id: id,
    text: text ?? this.text,
    delta: delta ?? this.delta,
    images: images ?? this.images,
    createdAt: createdAt,
    themes: themes ?? this.themes,
    themesChosen: themesChosen ?? this.themesChosen,
    title: title ?? this.title,
    subtasks: subtasks ?? this.subtasks,
    ranks: ranks ?? this.ranks,
  );

  Map<String, Object> toJson() {
    final moved = {
      for (final theme in themes.isEmpty ? const [''] : themes)
        if (ranks[theme] case final rank?
            when rank != createdAt.microsecondsSinceEpoch)
          theme: rank,
    };
    return {
      'id': id,
      'text': text,
      if (delta.isNotEmpty) 'delta': delta,
      if (images.isNotEmpty) 'images': images,
      'createdAt': createdAt.toUtc().toIso8601String(),
      if (themes.isNotEmpty) 'themes': themes,
      if (themesChosen) 'themesChosen': true,
      'title': ?title,
      if (subtasks.isNotEmpty)
        'subtasks': [
          for (final subtask in subtasks)
            {'text': subtask.text, if (subtask.done) 'done': true},
        ],
      if (moved.isNotEmpty) 'ranks': moved,
    };
  }
}
