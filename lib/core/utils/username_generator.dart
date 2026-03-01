import 'dart:math';

/// Potluck-themed adjective list for random username generation.
const List<String> potluckAdjectives = [
  'Spicy',
  'Golden',
  'Crispy',
  'Savory',
  'Smoky',
  'Zesty',
  'Tangy',
  'Sweet',
  'Toasty',
  'Sizzling',
  'Fresh',
  'Rustic',
  'Velvet',
  'Herby',
  'Mellow',
  'Peppered',
  'Roasted',
  'Honeyed',
  'Buttery',
  'Wild',
];

/// Potluck-themed noun list for random username generation.
const List<String> potluckNouns = [
  'Basil',
  'Gnocchi',
  'Sage',
  'Thyme',
  'Mango',
  'Truffle',
  'Paprika',
  'Saffron',
  'Olive',
  'Fennel',
  'Clove',
  'Nutmeg',
  'Rosemary',
  'Cinnamon',
  'Maple',
  'Pecan',
  'Walnut',
  'Fig',
  'Cardamom',
  'Lavender',
];

/// Generates a random Potluck-style username (adjective + noun, no separator).
/// Pass [Random] for tests; omit to use a new [Random()] each call.
String generatePotluckUsername([Random? rng]) {
  final random = rng ?? Random();
  final adj = potluckAdjectives[random.nextInt(potluckAdjectives.length)];
  final noun = potluckNouns[random.nextInt(potluckNouns.length)];
  return '$adj$noun';
}
