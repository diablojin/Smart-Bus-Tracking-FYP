/// Model class representing a route-stop relationship from the Supabase route_stops table.
class RouteStopModel {
  final int id;
  final int routeId;
  final int stopId;
  final int seq;

  RouteStopModel({
    required this.id,
    required this.routeId,
    required this.stopId,
    required this.seq,
  });

  /// Creates a RouteStopModel instance from a Supabase row map.
  factory RouteStopModel.fromMap(Map<String, dynamic> map) {
    return RouteStopModel(
      id: map['id'] as int,
      routeId: (map['route_id'] as int?) ?? 0,
      stopId: (map['stop_id'] as int?) ?? 0,
      seq: (map['seq'] as int?) ?? (map['sequence'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'route_id': routeId,
      'stop_id': stopId,
      'seq': seq,
    };
  }
}

