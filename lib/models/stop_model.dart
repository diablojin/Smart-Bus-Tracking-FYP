/// Model class representing a stop from the Supabase stops table.
class StopModel {
  final int id;
  final String code;
  final String name;
  final double? latitude;
  final double? longitude;

  StopModel({
    required this.id,
    required this.code,
    required this.name,
    this.latitude,
    this.longitude,
  });

  /// Creates a StopModel instance from a Supabase row map.
  factory StopModel.fromMap(Map<String, dynamic> map) {
    return StopModel(
      id: map['id'] as int,
      code: (map['stop_code'] as String?) ?? (map['code'] as String?) ?? '',
      name: (map['stop_name'] as String?) ?? (map['name'] as String?) ?? '',
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'stop_code': code,
      'stop_name': name,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}

