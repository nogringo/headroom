const _accented = 'àáâäãåçèéêëìíîïñòóôöõùúûüýÿ';
const _bare = 'aaaaaaceeeeiiiinooooouuuuyy';

/// Lowercase without accents, so "Études" sorts among the E.
String _plain(String theme) => [
  for (final char in theme.toLowerCase().split(''))
    switch (_accented.indexOf(char)) {
      -1 => char,
      final i => _bare[i],
    },
].join();

/// The theme of [themes] that [name] spells, whatever its case and accents.
String? themeSpelled(String name, Iterable<String> themes) {
  final plain = _plain(name.trim());
  return themes.where((theme) => _plain(theme) == plain).firstOrNull;
}

/// The [themes] in [order], then those it lacks, alphabetically whatever
/// their case and accents.
List<String> orderedThemes(Iterable<String> themes, List<String> order) {
  final present = themes.toSet();
  final unordered = present.where((theme) => !order.contains(theme)).toList()
    ..sort((a, b) => _plain(a).compareTo(_plain(b)));
  return [
    for (final theme in order)
      if (present.contains(theme)) theme,
    ...unordered,
  ];
}
