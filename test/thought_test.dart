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
}
