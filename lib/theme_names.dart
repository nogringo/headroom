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

/// Alphabetically, whatever their case and accents.
List<String> sortedThemes(Iterable<String> themes) =>
    [...themes]..sort((a, b) => _plain(a).compareTo(_plain(b)));

/// The theme of [themes] that [name] spells, whatever its case and accents.
String? themeSpelled(String name, Iterable<String> themes) {
  final plain = _plain(name.trim());
  return themes.where((theme) => _plain(theme) == plain).firstOrNull;
}
