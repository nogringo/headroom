import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/theme_names.dart';

void main() {
  test('lists themes in the order given, then the others alphabetically', () {
    expect(
      orderedThemes(
        {'Work', 'Études', 'bills', 'Errands', 'Home'},
        ['Home', 'Gone', 'Work'],
      ),
      ['Home', 'Work', 'bills', 'Errands', 'Études'],
    );
  });

  test('finds a theme whatever its case and accents', () {
    expect(themeSpelled(' etudes ', ['Work', 'Études']), 'Études');
    expect(themeSpelled('Garden', ['Work', 'Études']), isNull);
  });
}
