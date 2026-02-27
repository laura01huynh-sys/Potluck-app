/// String and measurement formatting helpers used across the app.

extension StringExtension on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
  String capitalizeWords() => split(' ').map((w) => w.capitalize()).join(' ');
}

String formatCookTime(int minutes) {
  final m = ((minutes + 2) ~/ 5) * 5;
  if (m < 60) return '${m}m';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '${h}h' : '${h}h ${r}m';
}

double amountAsDouble(dynamic a) => a is num ? a.toDouble() : double.tryParse(a?.toString() ?? '') ?? 0.0;
int amountAsInt(dynamic a) => a is int ? a : a is num ? a.round() : int.tryParse(a?.toString() ?? '') ?? 0;

String decimalToFraction(double value) {
  const f = {0.125: '1/8', 0.25: '1/4', 0.333: '1/3', 0.375: '3/8', 0.5: '1/2', 0.625: '5/8', 0.667: '2/3', 0.75: '3/4', 0.875: '7/8'};
  if (value == value.round()) return value.round().toString();
  final w = value.floor(), d = value - w;
  String? frac;
  double min = 1.0;
  for (final e in f.entries) {
    final diff = (d - e.key).abs();
    if (diff < min && diff < 0.05) {
      min = diff;
      frac = e.value;
    }
  }
  if (frac != null) return w == 0 ? frac : '$w $frac';
  return value.toStringAsFixed(1).replaceAll(RegExp(r'\.?0+$'), '');
}

(double, String) convertToMetric(double value, String unit) {
  const c = {
    'cup': (240.0, 'ml'), 'cups': (240.0, 'ml'), 'tbsp': (15.0, 'ml'), 'tablespoon': (15.0, 'ml'), 'tablespoons': (15.0, 'ml'),
    'tsp': (5.0, 'ml'), 'teaspoon': (5.0, 'ml'), 'teaspoons': (5.0, 'ml'), 'fl oz': (30.0, 'ml'), 'fluid ounce': (30.0, 'ml'),
    'fluid ounces': (30.0, 'ml'), 'quart': (946.0, 'ml'), 'quarts': (946.0, 'ml'), 'qt': (946.0, 'ml'), 'pint': (473.0, 'ml'),
    'pints': (473.0, 'ml'), 'pt': (473.0, 'ml'), 'gallon': (3785.0, 'ml'), 'gallons': (3785.0, 'ml'), 'gal': (3785.0, 'ml'),
    'oz': (28.35, 'g'), 'ounce': (28.35, 'g'), 'ounces': (28.35, 'g'), 'lb': (453.6, 'g'), 'lbs': (453.6, 'g'),
    'pound': (453.6, 'g'), 'pounds': (453.6, 'g'),
  };
  final u = unit.toLowerCase().trim();
  if (u == '°f' || u == 'f') return ((value - 32) * 5 / 9, '°C');
  if (c.containsKey(u)) {
    final (mul, newUnit) = c[u]!;
    return (value * mul, newUnit);
  }
  return (value, unit);
}

String abbreviateUnit(String unit) {
  const m = {
    'tablespoons': 'tbsp', 'tablespoon': 'tbsp', 'tbsp': 'tbsp', 'teaspoons': 'tsp', 'teaspoon': 'tsp', 'tsp': 'tsp',
    'cups': 'cup', 'cup': 'cup', 'fl oz': 'fl oz', 'floz': 'fl oz', 'quarts': 'qt', 'quart': 'qt', 'qt': 'qt',
    'pints': 'pt', 'pint': 'pt', 'pt': 'pt', 'gallons': 'gal', 'gallon': 'gal', 'gal': 'gal', 'liters': 'L',
    'liter': 'L', 'l': 'L', 'milliliters': 'mL', 'milliliter': 'mL', 'ml': 'mL', 'mL': 'mL', 'ounces': 'oz',
    'ounce': 'oz', 'oz': 'oz', 'pounds': 'lb', 'pound': 'lb', 'lb': 'lb', 'lbs': 'lb', 'grams': 'g', 'gram': 'g',
    'g': 'g', 'kilograms': 'kg', 'kilogram': 'kg', 'kg': 'kg',
  };
  final l = unit.toLowerCase().trim();
  return m[l] ?? (unit.isEmpty ? '' : unit);
}

class RecipeUtils {
  static const _desc = {'large', 'medium', 'small', 'extra-large', 'xl', 'whole', 'each', 'ea', 'fresh', 'ripe', 'raw',
    'cooked', 'dried', 'frozen', 'chopped', 'diced', 'sliced', 'minced', 'grated', 'shredded', 'peeled', 'pitted',
    'halved', 'quartered', 'crushed', 'ground', 'packed', 'heaping', 'level'};
  static const _units = {'tbsp', 'tsp', 'cup', 'fl oz', 'qt', 'pt', 'gal', 'l', 'ml', 'oz', 'lb', 'g', 'kg',
    'pinch', 'dash', 'drop', 'clove', 'slice', 'stick', 'serving', 'pc'};

  static String cleanMeasurement(String m) {
    final t = m.trim();
    if (t.isEmpty) return '';
    final p = t.split(RegExp(r'\s+'));
    if (p.isEmpty) return '';
    var q = p[0], s = 1;
    if (p.length >= 2 && RegExp(r'^\d+$').hasMatch(p[0]) && RegExp(r'^[\d./]+$').hasMatch(p[1])) {
      q = '${p[0]} ${p[1]}';
      s = 2;
    }
    if (!RegExp(r'^[\d./]+(?:\s+[\d./]+)?$').hasMatch(q)) return '';
    final u = p.length > s ? p.sublist(s).join(' ') : '';
    if (u.isEmpty) return q;
    final l = u.toLowerCase().trim();
    if (_desc.contains(l) || l == '<unit>' || l.startsWith('<')) return q;
    final c = abbreviateUnit(l).toLowerCase();
    return _units.contains(c) ? '$q ${abbreviateUnit(l)}' : q;
  }
}