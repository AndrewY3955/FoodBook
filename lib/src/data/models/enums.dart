/// Dart mirrors of the PostgreSQL enums in migration 0001.
///
/// The wire value is the Postgres label, kept separate from the display
/// label so that renaming UI copy never changes what is stored. Unknown
/// values decode to a sensible default instead of throwing, so that a
/// server-side enum addition does not crash an older client.
library;

enum MealType {
  breakfast('breakfast', 'Breakfast'),
  lunch('lunch', 'Lunch'),
  dinner('dinner', 'Dinner'),
  snack('snack', 'Snack'),
  dessert('dessert', 'Dessert');

  const MealType(this.wire, this.label);
  final String wire;
  final String label;

  static MealType fromWire(String? value) => MealType.values.firstWhere(
        (MealType e) => e.wire == value,
        orElse: () => MealType.dinner,
      );
}

enum Season {
  spring('spring', 'Spring'),
  summer('summer', 'Summer'),
  autumn('autumn', 'Autumn'),
  winter('winter', 'Winter'),
  allYear('all_year', 'All year');

  const Season(this.wire, this.label);
  final String wire;
  final String label;

  static Season fromWire(String? value) => Season.values.firstWhere(
        (Season e) => e.wire == value,
        orElse: () => Season.allYear,
      );
}

/// Order matters: this is the order the shopping list renders its
/// headers in, chosen to roughly match how a supermarket is walked.
enum GroceryCategory {
  veggies('veggies', 'Veggies'),
  fruits('fruits', 'Fruits'),
  bakery('bakery', 'Bakery'),
  meat('meat', 'Meat'),
  seafood('seafood', 'Seafood'),
  dairy('dairy', 'Dairy'),
  frozen('frozen', 'Frozen'),
  pantryStaples('pantry_staples', 'Pantry staples'),
  spices('spices', 'Spices'),
  beverages('beverages', 'Beverages'),
  other('other', 'Other');

  const GroceryCategory(this.wire, this.label);
  final String wire;
  final String label;

  static GroceryCategory fromWire(String? value) =>
      GroceryCategory.values.firstWhere(
        (GroceryCategory e) => e.wire == value,
        orElse: () => GroceryCategory.other,
      );
}

enum MeasureUnit {
  unit('unit', ''),
  piece('piece', ''),
  pinch('pinch', 'pinch'),
  clove('clove', 'clove'),
  slice('slice', 'slice'),
  g('g', 'g'),
  kg('kg', 'kg'),
  oz('oz', 'oz'),
  lb('lb', 'lb'),
  ml('ml', 'ml'),
  l('l', 'l'),
  tsp('tsp', 'tsp'),
  tbsp('tbsp', 'tbsp'),
  cup('cup', 'cup'),
  flOz('fl_oz', 'fl oz'),
  bunch('bunch', 'bunch'),
  can('can', 'can'),
  package('package', 'pack'),
  toTaste('to_taste', 'to taste');

  const MeasureUnit(this.wire, this.label);
  final String wire;
  final String label;

  /// Units that take a plural form when the quantity is not 1.
  bool get pluralises => const <MeasureUnit>{
        MeasureUnit.pinch,
        MeasureUnit.clove,
        MeasureUnit.slice,
        MeasureUnit.bunch,
        MeasureUnit.can,
        MeasureUnit.package,
      }.contains(this);

  /// "to taste" must never be multiplied by a serving scale.
  bool get isScalable => this != MeasureUnit.toTaste;

  static MeasureUnit fromWire(String? value) => MeasureUnit.values.firstWhere(
        (MeasureUnit e) => e.wire == value,
        orElse: () => MeasureUnit.unit,
      );
}

enum MemberRole {
  owner('owner', 'Owner'),
  admin('admin', 'Admin'),
  member('member', 'Member');

  const MemberRole(this.wire, this.label);
  final String wire;
  final String label;

  bool get canManageMembers => this != MemberRole.member;

  static MemberRole fromWire(String? value) => MemberRole.values.firstWhere(
        (MemberRole e) => e.wire == value,
        orElse: () => MemberRole.member,
      );
}

enum ImportSource {
  manual('manual', 'Written here'),
  web('web', 'From the web'),
  instagram('instagram', 'From Instagram'),
  tiktok('tiktok', 'From TikTok'),
  fork('fork', 'Forked');

  const ImportSource(this.wire, this.label);
  final String wire;
  final String label;

  static ImportSource fromWire(String? value) => ImportSource.values.firstWhere(
        (ImportSource e) => e.wire == value,
        orElse: () => ImportSource.manual,
      );

  static ImportSource forHost(String host) {
    final String h = host.toLowerCase();
    if (h.contains('instagram')) return ImportSource.instagram;
    if (h.contains('tiktok')) return ImportSource.tiktok;
    return ImportSource.web;
  }
}
