import '../config/supabase_client.dart';

// Model Classes
class Stop {
  final int id;
  final int routeId;
  final String name;
  final double latitude;
  final double longitude;
  final int sequenceIndex;
  final String? area;
  final String? routeCode;

  Stop({
    required this.id,
    required this.routeId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.sequenceIndex,
    this.area,
    this.routeCode,
  });

  factory Stop.fromJson(Map<String, dynamic> json) {
    return Stop(
      id: json['id'] as int,
      routeId: json['route_id'] as int,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      sequenceIndex: json['sequence_index'] as int,
      area: json['area'] as String?,
      routeCode: null,
    );
  }

  factory Stop.fromMap(Map<String, dynamic> map) {
    return Stop(
      id: map['id'] as int,
      routeId: map['route_id'] as int,
      name: map['name'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      sequenceIndex: map['sequence_index'] as int,
      routeCode: null, // for simple stop queries
    );
  }

  @override
  String toString() => name;
}

class RouteInfo {
  final int id;
  final String code;
  final String name;
  final double baseFare;
  final String? description;
  final bool isActive;

  RouteInfo({
    required this.id,
    required this.code,
    required this.name,
    required this.baseFare,
    this.description,
    required this.isActive,
  });

  factory RouteInfo.fromJson(Map<String, dynamic> json) {
    return RouteInfo(
      id: json['id'] as int,
      code: json['code'] as String,
      name: json['name'] as String,
      baseFare: (json['base_fare'] as num).toDouble(),
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class BusInfo {
  final int id;
  final int routeId;
  final String plateNo;
  final String code;
  final bool isActive;

  BusInfo({
    required this.id,
    required this.routeId,
    required this.plateNo,
    required this.code,
    required this.isActive,
  });

  factory BusInfo.fromJson(Map<String, dynamic> json) {
    return BusInfo(
      id: json['id'] as int,
      routeId: json['route_id'] as int,
      plateNo: json['plate_no'] as String,
      code: json['code'] as String,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class ScheduleInfo {
  final int id;
  final int busId;
  final String departureTime;
  final String arrivalTime;
  final List<String> daysOfWeek;
  final bool isActive;

  ScheduleInfo({
    required this.id,
    required this.busId,
    required this.departureTime,
    required this.arrivalTime,
    required this.daysOfWeek,
    required this.isActive,
  });

  factory ScheduleInfo.fromJson(Map<String, dynamic> json) {
    // Parse days_of_week which is stored as a PostgreSQL array
    List<String> days = [];
    if (json['days_of_week'] != null) {
      if (json['days_of_week'] is List) {
        days = (json['days_of_week'] as List).map((e) => e.toString()).toList();
      }
    }

    return ScheduleInfo(
      id: json['id'] as int,
      busId: json['bus_id'] as int,
      departureTime: json['departure_time'] as String,
      arrivalTime: json['arrival_time'] as String,
      daysOfWeek: days,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class BusWithSchedules {
  final BusInfo bus;
  final List<ScheduleInfo> schedules;

  BusWithSchedules({
    required this.bus,
    required this.schedules,
  });
}

class RouteSearchResult {
  final RouteInfo route;
  final Stop fromStop;
  final Stop toStop;
  final List<BusWithSchedules> busesWithSchedules;

  RouteSearchResult({
    required this.route,
    required this.fromStop,
    required this.toStop,
    required this.busesWithSchedules,
  });
}

class TripSelection {
  final RouteInfo route;
  final Stop fromStop;
  final Stop toStop;
  final BusInfo bus;

  TripSelection({
    required this.route,
    required this.fromStop,
    required this.toStop,
    required this.bus,
  });
}

// Service Class
class RouteSearchService {
  /// Get all stops ordered by name
  static Future<List<Stop>> getAllStops() async {
    try {
      final response = await supabase
          .from('stops')
          .select('id, route_id, name, latitude, longitude, sequence_index, routes (code)')
          .order('name');

      final rows = response as List<dynamic>;

      return rows.map((raw) {
        final map = raw as Map<String, dynamic>;
        final routeMap = map['routes'] as Map<String, dynamic>?;
        final routeCode = routeMap != null ? routeMap['code'] as String? : null;

        return Stop(
          id: map['id'] as int,
          routeId: map['route_id'] as int,
          name: map['name'] as String,
          latitude: (map['latitude'] as num).toDouble(),
          longitude: (map['longitude'] as num).toDouble(),
          sequenceIndex: map['sequence_index'] as int,
          routeCode: routeCode,
        );
      }).toList();
    } catch (e) {
      print('Error fetching stops: $e');
      rethrow;
    }
  }

  /// Search for a route between two stops
  /// Returns null if no direct route exists
  static Future<RouteSearchResult?> searchRoute({
    required int fromStopId,
    required int toStopId,
  }) async {
    try {
      // 1. Fetch both stops
      final stopsResponse = await supabase
          .from('stops')
          .select()
          .inFilter('id', [fromStopId, toStopId]);

      final stops = (stopsResponse as List)
          .map((json) => Stop.fromJson(json))
          .toList();

      if (stops.length != 2) {
        return null; // One or both stops not found
      }

      // Find which is from and which is to
      final fromStop = stops.firstWhere((s) => s.id == fromStopId);
      final toStop = stops.firstWhere((s) => s.id == toStopId);

      // 2. Check if they share the same route_id
      if (fromStop.routeId != toStop.routeId) {
        return null; // No direct route
      }

      // 3. Allow both directions on the same route
      // Do NOT reject based on sequenceIndex anymore.
      // We want to allow both directions along the same route.
      // if (fromStop.sequenceIndex >= toStop.sequenceIndex) {
      //   return null;
      // }

      // 4. Fetch the route information
      final routeResponse = await supabase
          .from('routes')
          .select()
          .eq('id', fromStop.routeId)
          .single();

      final route = RouteInfo.fromJson(routeResponse);

      // 5. Fetch all active buses for this route
      final busesResponse = await supabase
          .from('buses')
          .select()
          .eq('route_id', route.id)
          .eq('is_active', true);

      final buses = (busesResponse as List)
          .map((json) => BusInfo.fromJson(json))
          .toList();

      if (buses.isEmpty) {
        // No active buses, but route exists
        return RouteSearchResult(
          route: route,
          fromStop: fromStop,
          toStop: toStop,
          busesWithSchedules: [],
        );
      }

      // 6. Fetch all active schedules for these buses
      final busIds = buses.map((b) => b.id).toList();
      final schedulesResponse = await supabase
          .from('schedules')
          .select()
          .inFilter('bus_id', busIds)
          .eq('is_active', true)
          .order('departure_time', ascending: true);

      final schedules = (schedulesResponse as List)
          .map((json) => ScheduleInfo.fromJson(json))
          .toList();

      // 7. Group schedules by bus
      final List<BusWithSchedules> busesWithSchedules = [];
      for (final bus in buses) {
        final busSchedules = schedules
            .where((s) => s.busId == bus.id)
            .toList();
        
        busesWithSchedules.add(BusWithSchedules(
          bus: bus,
          schedules: busSchedules,
        ));
      }

      return RouteSearchResult(
        route: route,
        fromStop: fromStop,
        toStop: toStop,
        busesWithSchedules: busesWithSchedules,
      );
    } catch (e) {
      print('Error searching route: $e');
      rethrow;
    }
  }
}

