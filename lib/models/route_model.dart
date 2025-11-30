/// Model class representing a route from the Supabase routes table.
class RouteModel {
  final int id;
  final String code;
  final String name;

  RouteModel({
    required this.id,
    required this.code,
    required this.name,
  });

  /// Creates a RouteModel instance from a Supabase row map.
  factory RouteModel.fromMap(Map<String, dynamic> map) {
    return RouteModel(
      id: map['id'] as int,
      code: (map['route_code'] as String?) ?? (map['code'] as String?) ?? '',
      name: (map['route_name'] as String?) ?? (map['name'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'route_code': code,
      'route_name': name,
    };
  }
}

