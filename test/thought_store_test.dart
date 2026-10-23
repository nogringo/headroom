import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/thought.dart';
import 'package:headroom/thought_store.dart';

import 'in_memory_storage.dart';

void main() {
  group('ThoughtStore', () {
    late InMemoryStorage storage;
    late ThoughtStore store;

    setUp(() {
      storage = InMemoryStorage();
      store = ThoughtStore(storage);
    });

    test('adds trimmed thoughts, newest first, and persists them', () async {
      store.add('  first ');
      store.add('second');
      await store.flush();

      expect(store.thoughts.map((t) => t.text), ['second', 'first']);
      expect(storage.saved.map((t) => t.text), ['second', 'first']);
    });

    test('ignores blank input without an image', () {
      expect(store.add('   \n '), isNull);
      expect(store.thoughts, isEmpty);
    });

    test('accepts images without text', () async {
      final first = await store.saveImage(Uint8List.fromList([1]));
      final second = await store.saveImage(Uint8List.fromList([2]));
      store.add(' ', images: [first, second]);
      await store.flush();

      expect(storage.saved.single.text, isEmpty);
      expect(storage.saved.single.images, [first, second]);
    });

    test('refuses an update that would leave neither text nor image', () {
      final withImage = store.add('caption', images: ['photo'])!;
      final textOnly = store.add('note')!;

      store
        ..update(withImage.id, text: '', images: ['photo'])
        ..update(textOnly.id, text: '', images: []);

      expect(store.thoughts.map((t) => t.text), ['note', '']);
    });

    test('update adds and removes images', () {
      final thought = store.add('note')!;

      store.update(thought.id, text: 'note', images: ['first', 'second']);
      expect(store.thoughts.single.images, ['first', 'second']);

      store.update(thought.id, text: 'note', images: ['second']);
      expect(store.thoughts.single.images, ['second']);

      store.update(thought.id, text: 'note', images: []);
      expect(store.thoughts.single.images, isEmpty);
    });

    test('load drops images that no thought uses', () async {
      final used = await storage.saveImage(Uint8List.fromList([1]));
      await storage.saveImage(Uint8List.fromList([2]));
      storage.saved = [
        Thought(id: '1', text: '', images: [used], createdAt: DateTime(2026)),
      ];

      await store.load();

      expect(storage.images.keys, [used]);
    });

    test('restores a removed thought at its old position', () async {
      store
        ..add('a')
        ..add('b')
        ..add('c');
      final b = store.thoughts[1];

      final index = store.remove(b.id);
      expect(store.thoughts.map((t) => t.text), ['c', 'a']);

      store.restore(b, index);
      await store.flush();
      expect(storage.saved.map((t) => t.text), ['c', 'b', 'a']);
    });

    test('keeps what the AI gave through an edit', () {
      final thought = store.add('Buy bread and milk')!;
      store.annotate(
        thought.id,
        themes: ['Errands'],
        title: 'Groceries',
        subtasks: ['Bread', 'Milk'],
      );
      store.annotate('gone', themes: ['Nowhere']);

      store.update(thought.id, text: 'Bake bread', images: ['receipt']);

      final edited = store.thoughts.single;
      expect(edited.text, 'Bake bread');
      expect(edited.themes, ['Errands']);
      expect(edited.title, 'Groceries');
      expect(edited.subtasks.map((s) => s.text), ['Bread', 'Milk']);
    });

    test('keeps the themes the person chose from the AI', () {
      final thought = store.add('Buy bread')!;
      store.chooseThemes(thought.id, ['Bakery', 'Errands']);

      store.annotate(thought.id, themes: ['Food'], title: 'Bread');
      expect(store.thoughts.single.themes, ['Bakery', 'Errands']);
      expect(store.thoughts.single.themesChosen, isTrue);
      expect(store.thoughts.single.title, 'Bread');

      store.chooseThemes(thought.id, []);
      expect(store.thoughts.single.themes, isEmpty);
      expect(store.thoughts.single.themesChosen, isTrue);
    });

    test('ticks a subtask off and back on', () async {
      final thought = store.add('Bread, milk')!;
      store.annotate(thought.id, themes: [], subtasks: ['Bread', 'Milk']);

      store.toggleSubtask(thought.id, 1);
      await store.flush();
      expect(storage.saved.single.subtasks, [
        (text: 'Bread', done: false),
        (text: 'Milk', done: true),
      ]);

      store
        ..toggleSubtask(thought.id, 1)
        ..toggleSubtask(thought.id, 7);
      expect(store.thoughts.single.subtasks.last.done, isFalse);
    });

    test('renames a theme, which may join another', () async {
      store
        ..add('Fix the build')
        ..add('Buy milk')
        ..add('Buy bread');
      final [bread, milk, build] = store.thoughts;
      store
        ..annotate(bread.id, themes: ['Errands', 'Food'])
        ..annotate(build.id, themes: ['Work'])
        ..chooseThemes(milk.id, ['Errands']);

      store.renameTheme('Errands', 'Shopping');
      expect(store.thoughts.map((t) => t.themes), [
        ['Shopping', 'Food'],
        ['Shopping'],
        ['Work'],
      ]);
      expect(store.thoughts.map((t) => t.themesChosen), [false, true, false]);

      store.renameTheme('Food', 'Shopping');
      await store.flush();
      expect(storage.saved.first.themes, ['Shopping']);
    });

    test('takes a theme off its thoughts, and gives it back', () async {
      store
        ..add('Buy milk')
        ..add('Buy bread');
      final [bread, milk] = store.thoughts;
      store
        ..chooseThemes(bread.id, ['Errands', 'Food'])
        ..chooseThemes(milk.id, ['Errands'])
        ..reorder('Errands', [milk.id, bread.id]);
      final rank = store.thoughts.last.rankIn('Errands');

      final originals = store.removeTheme('Errands');
      expect(store.thoughts.map((t) => t.themes), [
        ['Food'],
        <String>[],
      ]);
      expect(store.thoughts.last.ranks, isEmpty);

      store.restoreTheme('Errands', originals);
      await store.flush();
      expect(storage.saved.map((t) => t.themes), [
        ['Errands', 'Food'],
        ['Errands'],
      ]);
      expect(store.thoughts.last.rankIn('Errands'), rank);
    });

    test('keeps a theme once its last thought is gone', () async {
      final thought = store.add('Buy milk')!;
      store
        ..chooseThemes(thought.id, ['Errands'])
        ..remove(thought.id);
      expect(store.themes, {'Errands'});

      await store.flush();
      final reopened = ThoughtStore(storage);
      await reopened.load();
      expect(reopened.themes, {'Errands'});
    });

    test('adds, renames and deletes a theme with no thought', () async {
      store.addThemes(['Errands']);
      store.renameTheme('Errands', 'Shopping');
      expect(store.themes, {'Shopping'});

      expect(store.removeTheme('Shopping'), isEmpty);
      expect(store.themes, isEmpty);
      store.restoreTheme('Shopping', []);
      expect(store.themes, {'Shopping'});

      store.removeTheme('Shopping');
      await store.flush();
      final reopened = ThoughtStore(storage);
      await reopened.load();
      expect(reopened.themes, isEmpty);
    });

    test('keeps the themes of thoughts saved before themes were', () async {
      final now = DateTime.now();
      storage.saved = [
        Thought(id: '1', text: 'Buy milk', createdAt: now, themes: ['Food']),
      ];
      await store.load();
      store.remove('1');
      await store.flush();

      final reopened = ThoughtStore(storage);
      await reopened.load();
      expect(reopened.themes, {'Food'});
    });

    test('merges thoughts into the newest and unmerges them', () async {
      store
        ..add('milk', images: ['carton'])
        ..add('Call the garage')
        ..add('Buy milk', images: ['list', 'carton']);
      final [newest, middle, oldest] = store.thoughts;
      store
        ..annotate(newest.id, themes: ['Errands'], title: 'Milk')
        ..chooseThemes(oldest.id, ['Food', 'Errands']);

      final merged = store.merge([oldest.id, newest.id], ' Buy milk ')!;
      await store.flush();

      expect(storage.saved.map((t) => t.text), ['Buy milk', 'Call the garage']);
      final kept = store.thoughts.first;
      expect(kept.id, newest.id);
      expect(kept.createdAt, newest.createdAt);
      expect(kept.themes, ['Errands', 'Food']);
      expect(kept.themesChosen, isTrue);
      expect(kept.title, isNull);
      expect(kept.images, ['list', 'carton']);

      store.unmerge(merged);
      await store.flush();
      expect(storage.saved.map((t) => t.id), [newest.id, middle.id, oldest.id]);
      expect(storage.saved.first.text, 'Buy milk');
      expect(storage.saved.last.images, ['carton']);
    });

    test('a new thought ranks above every other', () {
      final first = store.add('first')!;
      store.reorder('', [first.id]);
      final second = store.add('second')!;

      expect(second.rankIn(''), greaterThan(first.rankIn('')));
    });

    test('reorders thoughts with the ranks they hold', () async {
      store
        ..add('Fix the build')
        ..add('Buy milk')
        ..add('Post the letter')
        ..add('Buy bread');
      final [bread, letter, milk, build] = store.thoughts;

      store.reorder('', [milk.id, bread.id, 'deleted', letter.id]);
      await store.flush();

      final ranks = {for (final t in storage.saved) t.text: t.rankIn('')};
      expect(ranks['Buy milk'], bread.rankIn(''));
      expect(ranks['Buy bread'], letter.rankIn(''));
      expect(ranks['Post the letter'], milk.rankIn(''));
      expect(ranks['Fix the build'], build.rankIn(''));
      expect(storage.saved.map((t) => t.text), [
        'Buy bread',
        'Post the letter',
        'Buy milk',
        'Fix the build',
      ]);
    });

    test('a move in one theme leaves the others as they were', () {
      store
        ..add('Buy milk')
        ..add('Buy bread');
      final [bread, milk] = store.thoughts;
      store
        ..chooseThemes(milk.id, ['Errands', 'Food'])
        ..chooseThemes(bread.id, ['Errands', 'Food']);

      store.reorder('Errands', [milk.id, bread.id]);

      final [movedBread, movedMilk] = store.thoughts;
      expect(movedMilk.rankIn('Errands'), bread.rankIn('Errands'));
      expect(movedBread.rankIn('Errands'), milk.rankIn('Errands'));
      expect(movedMilk.rankIn('Food'), milk.rankIn('Food'));
      expect(movedBread.rankIn('Food'), bread.rankIn('Food'));
    });

    test('a merge takes the highest rank of the thoughts it joins', () {
      store
        ..add('milk')
        ..add('Buy milk');
      final [newest, oldest] = store.thoughts;
      store.reorder('', [oldest.id, newest.id]);

      store.merge([oldest.id, newest.id], 'Buy milk');

      expect(store.thoughts.single.id, newest.id);
      expect(store.thoughts.single.rankIn(''), newest.rankIn(''));
    });

    test('keeps the rank through edits, and a renamed theme', () {
      store
        ..add('first')
        ..add('second');
      final [second, first] = store.thoughts;
      store
        ..chooseThemes(first.id, ['Work'])
        ..chooseThemes(second.id, ['Work'])
        ..reorder('Work', [first.id, second.id]);
      final rank = store.thoughts.last.rankIn('Work');

      store
        ..update(first.id, text: 'edited', images: [])
        ..renameTheme('Work', 'Jobs');

      expect(store.thoughts.last.rankIn('Jobs'), rank);
    });

    test('merges nothing when fewer than two thoughts are left', () {
      final thought = store.add('milk')!;

      expect(store.merge([thought.id, 'deleted'], 'Buy milk'), isNull);
      expect(store.thoughts.single.text, 'milk');
    });

    test('updates text but keeps the original date', () async {
      final thought = store.add('draft')!;
      store.update(thought.id, text: ' final ', images: []);
      await store.flush();

      expect(storage.saved.single.text, 'final');
      expect(storage.saved.single.createdAt, thought.createdAt);
    });

    test(
      'flags a failed write and clears the flag once a write succeeds',
      () async {
        final reported = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = reported.add;
        addTearDown(() => FlutterError.onError = previous);

        storage.failWrites = true;
        store.add('lost?');
        await store.flush();
        expect(store.saveFailed, isTrue);
        expect(reported, hasLength(1));

        storage.failWrites = false;
        store.add('retry');
        await store.flush();
        expect(store.saveFailed, isFalse);
        expect(storage.saved.map((t) => t.text), ['retry', 'lost?']);
      },
    );
  });
}
