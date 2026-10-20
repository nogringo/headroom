import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/thought.dart';

void main() {
  test('reads the single image written by earlier versions', () {
    final thought = Thought.fromJson({
      'id': '1',
      'text': 'Receipt',
      'image': 'receipt',
      'createdAt': '2026-10-19T09:30:00.000Z',
    });

    expect(thought.images, ['receipt']);
    expect(thought.toJson(), isNot(contains('image')));
    expect(thought.toJson()['images'], ['receipt']);
  });

  test('writes no images key for a text-only thought', () {
    final thought = Thought(id: '1', text: 'Note', createdAt: DateTime(2026));

    expect(thought.toJson(), isNot(contains('images')));
    expect(Thought.fromJson(thought.toJson()).images, isEmpty);
  });

  test('keeps its theme, and writes none until it has one', () {
    final unsorted = Thought(id: '1', text: 'Note', createdAt: DateTime(2026));
    final sorted = Thought(
      id: '2',
      text: 'Note',
      createdAt: DateTime(2026),
      theme: 'Errands',
    );

    expect(unsorted.toJson(), isNot(contains('theme')));
    expect(Thought.fromJson(unsorted.toJson()).theme, isNull);
    expect(Thought.fromJson(sorted.toJson()).theme, 'Errands');
  });

  test('remembers a theme the person chose', () {
    final byAi = Thought(
      id: '1',
      text: 'Note',
      createdAt: DateTime(2026),
      theme: 'Errands',
    );
    final chosen = Thought(
      id: '2',
      text: 'Note',
      createdAt: DateTime(2026),
      theme: 'Errands',
      themeChosen: true,
    );

    expect(byAi.toJson(), isNot(contains('themeChosen')));
    expect(Thought.fromJson(byAi.toJson()).themeChosen, isFalse);
    expect(Thought.fromJson(chosen.toJson()).themeChosen, isTrue);
  });

  test('ranks by its date, and writes a rank only once moved', () {
    final noted = DateTime.utc(2026, 10, 20, 9);
    final unmoved = Thought(id: '1', text: 'Note', createdAt: noted);
    final moved = Thought(id: '2', text: 'Note', createdAt: noted, rank: 7);

    expect(unmoved.rank, noted.microsecondsSinceEpoch);
    expect(unmoved.toJson(), isNot(contains('rank')));
    expect(Thought.fromJson(unmoved.toJson()).rank, unmoved.rank);
    expect(Thought.fromJson(moved.toJson()).rank, 7);
  });
}
