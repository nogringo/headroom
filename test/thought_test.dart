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

  test('keeps its themes, and writes none until it has some', () {
    final unsorted = Thought(id: '1', text: 'Note', createdAt: DateTime(2026));
    final sorted = Thought(
      id: '2',
      text: 'Note',
      createdAt: DateTime(2026),
      themes: ['Errands', 'Home'],
    );

    expect(unsorted.toJson(), isNot(contains('themes')));
    expect(Thought.fromJson(unsorted.toJson()).themes, isEmpty);
    expect(Thought.fromJson(sorted.toJson()).themes, ['Errands', 'Home']);
  });

  test('remembers themes the person chose', () {
    final byAi = Thought(
      id: '1',
      text: 'Note',
      createdAt: DateTime(2026),
      themes: ['Errands'],
    );
    final chosen = Thought(
      id: '2',
      text: 'Note',
      createdAt: DateTime(2026),
      themes: ['Errands'],
      themesChosen: true,
    );

    expect(byAi.toJson(), isNot(contains('themesChosen')));
    expect(Thought.fromJson(byAi.toJson()).themesChosen, isFalse);
    expect(Thought.fromJson(chosen.toJson()).themesChosen, isTrue);
  });

  test('keeps its title and subtasks, ticked or not', () {
    final plain = Thought(id: '1', text: 'Note', createdAt: DateTime(2026));
    final described = Thought(
      id: '2',
      text: 'Bread, milk',
      createdAt: DateTime(2026),
      title: 'Groceries',
      subtasks: [(text: 'Bread', done: true), (text: 'Milk', done: false)],
    );

    expect(plain.toJson(), isNot(contains('title')));
    expect(plain.toJson(), isNot(contains('subtasks')));
    final read = Thought.fromJson(described.toJson());
    expect(read.title, 'Groceries');
    expect(read.subtasks, described.subtasks);
    expect(described.toJson()['subtasks'], [
      {'text': 'Bread', 'done': true},
      {'text': 'Milk'},
    ]);
  });

  test('ranks by its date in each theme, and writes a rank once moved', () {
    final noted = DateTime.utc(2026, 10, 20, 9);
    final unmoved = Thought(id: '1', text: 'Note', createdAt: noted);
    final moved = Thought(
      id: '2',
      text: 'Note',
      createdAt: noted,
      themes: ['Work', 'Home'],
      ranks: {'Work': 7, 'Gone': 3},
    );

    expect(unmoved.rankIn(''), noted.microsecondsSinceEpoch);
    expect(unmoved.toJson(), isNot(contains('ranks')));
    expect(moved.toJson()['ranks'], {'Work': 7});
    final read = Thought.fromJson(moved.toJson());
    expect(read.rankIn('Work'), 7);
    expect(read.rankIn('Home'), noted.microsecondsSinceEpoch);
  });

  test('reads the single theme and rank written by earlier versions', () {
    final sorted = Thought.fromJson({
      'id': '1',
      'text': 'Note',
      'createdAt': '2026-10-19T09:30:00.000Z',
      'theme': 'Errands',
      'themeChosen': true,
      'rank': 7,
    });
    final unsorted = Thought.fromJson({
      'id': '2',
      'text': 'Note',
      'createdAt': '2026-10-19T09:30:00.000Z',
      'rank': 5,
    });

    expect(sorted.themes, ['Errands']);
    expect(sorted.themesChosen, isTrue);
    expect(sorted.rankIn('Errands'), 7);
    expect(unsorted.themes, isEmpty);
    expect(unsorted.rankIn(''), 5);
  });
}
