/// String extensions for profile and dietary display.
extension StringExtension on String {
  /// Converts hyphenated or space-separated words to Title Case.
  /// e.g. 'gluten-free' → 'Gluten Free', 'high-protein' → 'High Protein'
  String toTitleCase() {
    if (isEmpty) return this;
    return replaceAll('-', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : w)
        .join(' ');
  }
}
