class Warehouse {
  const Warehouse({
    this.id,
    required this.name,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Warehouse.fromMap(Map<String, Object?> m) => Warehouse(
        id: m['id'] as int,
        name: m['name'] as String,
        isActive: (m['is_active'] as int) == 1,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );

  @override
  bool operator ==(Object other) => other is Warehouse && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
