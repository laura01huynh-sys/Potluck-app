// Formatting and conversion helpers for recipes and ingredients.

String formatCookTime(int minutes) {
  final roundedMinutes = ((minutes + 2) ~/ 5) * 5;
  if (roundedMinutes < 60) return '${roundedMinutes}m';
  final hours = roundedMinutes ~/ 60;
  final remainingMins = roundedMinutes % 60;
  if (remainingMins == 0) return '${hours}h';
  return '${hours}h ${remainingMins}m';
}

double amountAsDouble(dynamic amount) {
  if (amount is num) return amount.toDouble();
  return double.tryParse(amount?.toString() ?? '') ?? 0.0;
}

int amountAsInt(dynamic amount) {
  if (amount is int) return amount;
  if (amount is num) return amount.round();
  return int.tryParse(amount?.toString() ?? '') ?? 0;
}

String decimalToFraction(double value) {
  final fractions = {
    0.125: '1/8',
    0.25: '1/4',
    0.333: '1/3',
    0.375: '3/8',
    0.5: '1/2',
    0.625: '5/8',
    0.667: '2/3',
    0.75: '3/4',
    0.875: '7/8',
  };
  if (value == value.round()) return value.round().toString();
  final wholePart = value.floor();
  final decimalPart = value - wholePart;
  String? fraction;
  double minDiff = 1.0;
  for (final entry in fractions.entries) {
    final diff = (decimalPart - entry.key).abs();
    if (diff < minDiff && diff < 0.05) {
      minDiff = diff;
      fraction = entry.value;
    }
  }
  if (fraction != null) {
    if (wholePart == 0) return fraction;
    return '$wholePart $fraction';
  }
  return value.toStringAsFixed(1).replaceAll(RegExp(r'\.?0+$'), '');
}

(double, String) convertToMetric(double value, String unit) {
  final u = unit.toLowerCase().trim();
  if (u == 'cup' || u == 'cups') return (value * 240, 'ml');
  if (u == 'tbsp' || u == 'tablespoon' || u == 'tablespoons') return (value * 15, 'ml');
  if (u == 'tsp' || u == 'teaspoon' || u == 'teaspoons') return (value * 5, 'ml');
  if (u == 'fl oz' || u == 'fluid ounce' || u == 'fluid ounces') return (value * 30, 'ml');
  if (u == 'quart' || u == 'quarts' || u == 'qt') return (value * 946, 'ml');
  if (u == 'pint' || u == 'pints' || u == 'pt') return (value * 473, 'ml');
  if (u == 'gallon' || u == 'gallons' || u == 'gal') return (value * 3785, 'ml');
  if (u == 'oz' || u == 'ounce' || u == 'ounces') return (value * 28.35, 'g');
  if (u == 'lb' || u == 'lbs' || u == 'pound' || u == 'pounds') return (value * 453.6, 'g');
  if (u == '°f' || u == 'f') return ((value - 32) * 5 / 9, '°C');
  return (value, unit);
}

String abbreviateUnit(String unit) {
  final unitMap = {
    'tablespoons': 'tbsp', 'tablespoon': 'tbsp', 'tbsp': 'tbsp',
    'teaspoons': 'tsp', 'teaspoon': 'tsp', 'tsp': 'tsp',
    'cups': 'cup', 'cup': 'cup',
    'ounces': 'oz', 'ounce': 'oz', 'oz': 'oz',
    'pounds': 'lb', 'pound': 'lb', 'lb': 'lb', 'lbs': 'lb',
    'grams': 'g', 'gram': 'g', 'g': 'g',
    'kilograms': 'kg', 'kilogram': 'kg', 'kg': 'kg',
    'liters': 'L', 'liter': 'L', 'L': 'L',
    'milliliters': 'mL', 'milliliter': 'mL', 'ml': 'mL', 'mL': 'mL',
    'fluid ounces': 'fl oz', 'fluid ounce': 'fl oz', 'fl oz': 'fl oz', 'floz': 'fl oz',
    'quarts': 'qt', 'quart': 'qt', 'qt': 'qt',
    'gallons': 'gal', 'gallon': 'gal', 'gal': 'gal',
    'pints': 'pt', 'pint': 'pt', 'pt': 'pt',
    'dozens': 'doz', 'dozen': 'doz', 'doz': 'doz',
    'pieces': 'pc', 'piece': 'pc', 'pc': 'pc',
    'cans': 'can', 'can': 'can', 'jars': 'jar', 'jar': 'jar',
    'bags': 'bag', 'bag': 'bag', 'boxes': 'box', 'box': 'box',
    'bunches': 'bunch', 'bunch': 'bunch', 'packages': 'pkg', 'package': 'pkg', 'pkg': 'pkg',
    'pinches': 'pinch', 'pinch': 'pinch', 'dashes': 'dash', 'dash': 'dash',
    'drops': 'drop', 'drop': 'drop', 'cloves': 'clove', 'clove': 'clove',
    'heads': 'head', 'head': 'head', 'stalks': 'stalk', 'stalk': 'stalk',
    'leaves': 'leaf', 'leaf': 'leaf', 'sprigs': 'sprig', 'sprig': 'sprig',
    'sticks': 'stick', 'stick': 'stick', 'slices': 'slice', 'slice': 'slice',
    'cubes': 'cube', 'cube': 'cube', 'dices': 'dice', 'dice': 'dice',
    'chops': 'chop', 'chop': 'chop', 'crumbs': 'crumb', 'crumb': 'crumb',
    'shreds': 'shred', 'shred': 'shred', 'sheets': 'sheet', 'sheet': 'sheet',
    'layers': 'layer', 'layer': 'layer', 'rounds': 'round', 'round': 'round',
    'wedges': 'wedge', 'wedge': 'wedge', 'quarters': 'quarter', 'quarter': 'quarter',
    'halves': 'half', 'half': 'half', 'thirds': 'third', 'third': 'third',
    'fourths': 'fourth', 'fourth': 'fourth', 'fifths': 'fifth', 'fifth': 'fifth',
    'sixths': 'sixth', 'sixth': 'sixth', 'eighths': 'eighth', 'eighth': 'eighth',
    'tenths': 'tenth', 'tenth': 'tenth', 'twelfths': 'twelfth', 'twelfth': 'twelfth',
  };
  final lowerUnit = unit.toLowerCase().trim();
  if (unitMap.containsKey(lowerUnit)) return unitMap[lowerUnit]!;
  return unit.isEmpty ? '' : unit;
}
