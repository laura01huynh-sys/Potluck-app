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
    'cup': (240.0, 'ml'), 'cups': (240.0, 'ml'),
    'tbsp': (15.0, 'ml'), 'tablespoon': (15.0, 'ml'), 'tablespoons': (15.0, 'ml'),
    'tsp': (5.0, 'ml'), 'teaspoon': (5.0, 'ml'), 'teaspoons': (5.0, 'ml'),
    'oz': (28.35, 'g'), 'ounce': (28.35, 'g'), 'ounces': (28.35, 'g'),
    'lb': (453.6, 'g'), 'lbs': (453.6, 'g'), 'pound': (453.6, 'g'), 'pounds': (453.6, 'g'),
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
    'tablespoon': 'tbsp', 'tablespoons': 'tbsp',
    'teaspoon': 'tsp', 'teaspoons': 'tsp',
    'ounce': 'oz', 'ounces': 'oz',
    'pound': 'lb', 'pounds': 'lb', 'lbs': 'lb',
    'cloves': 'clove',
    'pieces': 'pc', 'piece': 'pc',
  };
  final l = unit.toLowerCase().trim();
  return m[l] ?? unit;
}

class RecipeUtils {
  static const _desc = {
    'large', 'medium', 'small', 'whole', 'each', 'ea',
    'chopped', 'diced', 'sliced', 'minced',
  };

  static const _units = {
    'tbsp', 'tsp', 'cup', 'oz', 'lb', 'g', 'kg', 'ml', 'l',
    'clove', 'pinch', 'pc',
  };

  /// Unified measurement normalizer
  static String normalizeAndClean(String ingredient, String measurement) {
    final ing = ingredient.toLowerCase().trim();
    final meas = measurement.trim();
    if (meas.isEmpty) return '';

    // Garlic → ensure "clove/cloves"
    if (ing.contains('garlic')) {
      final numMatch = RegExp(r'^([\d./]+(?:\s+[\d./]+)?)').firstMatch(meas);
      if (numMatch != null) {
        final num = numMatch.group(1)!.trim();
        if (meas.toLowerCase().contains('clove')) return meas;
        final numVal = double.tryParse(num.replaceAll('/', '.')) ?? 1;
        return numVal == 1 ? '1 clove' : '$num cloves';
      }
      return meas;
    }

    // Generic cleaning
    final p = meas.split(RegExp(r'\s+'));
    if (p.isEmpty) return '';

    var q = p[0];
    var s = 1;

    // Support mixed numbers "2 1/2"
    if (p.length >= 2 && RegExp(r'^\d+$').hasMatch(p[0]) && RegExp(r'^[\d./]+$').hasMatch(p[1])) {
      q = '${p[0]} ${p[1]}';
      s = 2;
    }

    if (!RegExp(r'^[\d./]+(?:\s+[\d./]+)?$').hasMatch(q)) return '';
    if (p.length <= s) return q;

    // Strip descriptors from unit
    final unitTokens = <String>[];
    for (var i = s; i < p.length; i++) {
      final tok = p[i].toLowerCase();
      if (tok.isEmpty || _desc.contains(tok)) continue;
      unitTokens.add(p[i]);
    }

    if (unitTokens.isEmpty) return q;

    final canon = abbreviateUnit(unitTokens.join(' '));
    if (!_units.contains(canon.toLowerCase())) return q;

    return '$q $canon';
  }

  /// Backwards-compatible wrapper
  static String cleanMeasurement(String m) => normalizeAndClean('', m);
}