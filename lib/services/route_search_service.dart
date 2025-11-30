import '../config/supabase_client.dart';
import '../models/route_model.dart';
import '../models/stop_model.dart';
import '../models/route_stop_model.dart';

/// Bundle containing all route data loaded from Supabase.
/// Provides efficient lookup maps for route search operations.
class RouteDataBundle {
  final List<RouteModel> routes;
  final List<StopModel> stops;
  final Map<int, List<RouteStopModel>> routeStopsByRouteId;
  final Map<int, RouteModel> routesById;
  final Map<int, StopModel> stopsById;
  // Stops grouped by route_id, ordered by sequence_index (from route_stops.seq)
  final Map<int, List<StopModel>> stopsByRouteId;

  RouteDataBundle({
    required this.routes,
    required this.stops,
    required this.routeStopsByRouteId,
    required this.routesById,
    required this.stopsById,
    required this.stopsByRouteId,
  });
}

/// Result of a route search between two stops.
class RouteSearchResult {
  final RouteModel route;
  final StopModel fromStop;
  final StopModel toStop;
  final List<StopModel> intermediateStops;

  RouteSearchResult({
    required this.route,
    required this.fromStop,
    required this.toStop,
    required this.intermediateStops,
  });
}

/// Bus information model (used by CommuterMapPage for tracking).
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

/// Trip selection model (used by CommuterMapPage for navigation).
/// Note: This uses the old Stop model structure for compatibility with CommuterMapPage.
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

/// Route information model (legacy compatibility).
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
      baseFare: (json['base_fare'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

/// Stop model (legacy compatibility for CommuterMapPage).
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
      routeCode: null,
    );
  }

  @override
  String toString() => name;
}

/// Service for loading route data and searching routes.
class RouteSearchService {
  /// Loads all route data from Supabase into a bundle.
  /// 
  /// Fetches:
  /// - Active routes (is_active = true)
  /// - All stops
  /// - All route_stops relationships
  /// 
  /// Returns a RouteDataBundle with organized data and lookup maps.
  static Future<RouteDataBundle> loadRouteDataBundle() async {
    try {
      // 1. Fetch active routes
      final routesResponse = await supabase
          .from('routes')
          .select()
          .eq('is_active', true);

      if (routesResponse.isNotEmpty) {
        final sampleRow = Map<String, dynamic>.from(routesResponse[0] as Map);
        print('📊 Sample route row keys: ${sampleRow.keys.toList()}');
      }

      final routes = (routesResponse as List)
          .map((row) {
            try {
              return RouteModel.fromMap(row as Map<String, dynamic>);
            } catch (e) {
              print('❌ Error parsing route: $e');
              print('   Row data: $row');
              print('   Row keys: ${(row as Map<String, dynamic>).keys.toList()}');
              return null;
            }
          })
          .whereType<RouteModel>()
          .toList();

      // 2. Fetch all stops
      final stopsResponse = await supabase
          .from('stops')
          .select();

      if (stopsResponse.isNotEmpty) {
        final sampleRow = Map<String, dynamic>.from(stopsResponse[0] as Map);
        print('📊 Sample stop row keys: ${sampleRow.keys.toList()}');
      }

      final stops = (stopsResponse as List)
          .map((row) {
            try {
              return StopModel.fromMap(row as Map<String, dynamic>);
            } catch (e) {
              print('❌ Error parsing stop: $e');
              print('   Row data: $row');
              print('   Row keys: ${(row as Map<String, dynamic>).keys.toList()}');
              return null;
            }
          })
          .whereType<StopModel>()
          .toList();

      // 3. Fetch all route_stops
      final routeStopsResponse = await supabase
          .from('route_stops')
          .select()
          .order('route_id')
          .order('seq');

      final routeStops = (routeStopsResponse as List)
          .map((row) {
            try {
              return RouteStopModel.fromMap(row as Map<String, dynamic>);
            } catch (e) {
              print('Error parsing route_stop: $e, row: $row');
              return null;
            }
          })
          .whereType<RouteStopModel>()
          .toList();

      // 4. Group route_stops by route_id
      final Map<int, List<RouteStopModel>> routeStopsByRouteId = {};
      for (final routeStop in routeStops) {
        routeStopsByRouteId.putIfAbsent(routeStop.routeId, () => []).add(routeStop);
      }

      // Ensure each route's stops are sorted by seq
      for (final entry in routeStopsByRouteId.entries) {
        entry.value.sort((a, b) => a.seq.compareTo(b.seq));
      }

      // 5. Build lookup maps
      final Map<int, RouteModel> routesById = {};
      for (final route in routes) {
        routesById[route.id] = route;
      }

      final Map<int, StopModel> stopsById = {};
      for (final stop in stops) {
        stopsById[stop.id] = stop;
      }

      // 6. Build stopsByRouteId: group stops by route_id, ordered by sequence_index (seq)
      final Map<int, List<StopModel>> stopsByRouteId = {};
      for (final entry in routeStopsByRouteId.entries) {
        final routeId = entry.key;
        final routeStopList = entry.value; // Already sorted by seq
        final stopList = routeStopList
            .map((rs) => stopsById[rs.stopId])
            .whereType<StopModel>()
            .toList();
        stopsByRouteId[routeId] = stopList;
      }

      print('✅ Loaded ${routes.length} routes, ${stops.length} stops, ${routeStops.length} route_stops');
      
      return RouteDataBundle(
        routes: routes,
        stops: stops,
        routeStopsByRouteId: routeStopsByRouteId,
        routesById: routesById,
        stopsById: stopsById,
        stopsByRouteId: stopsByRouteId,
      );
    } catch (e, stackTrace) {
      print('❌ Error loading route data bundle: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Searches for all direct routes that include both stops by name (two-way routes).
  /// 
  /// Returns a list of RouteSearchResult objects, one for each matching route.
  static List<RouteSearchResult> searchRoutes({
    required RouteDataBundle bundle,
    required String fromStopName,
    required String toStopName,
  }) {
    if (fromStopName == toStopName) {
      return [];
    }

    final List<RouteSearchResult> matches = [];

    bundle.stopsByRouteId.forEach((routeId, stopList) {
      // stopList is already ordered by sequence_index (from route_stops.seq)
      // Find indices where stop names match
      final fromIndex = stopList.indexWhere((s) => s.name == fromStopName);
      final toIndex = stopList.indexWhere((s) => s.name == toStopName);

      // Check if both stops exist on this route (direction doesn't matter - two-way routes)
      if (fromIndex != -1 && toIndex != -1 && fromIndex != toIndex) {
        final route = bundle.routesById[routeId];
        if (route == null) return; // Skip if route not found

        // Get intermediate stops (including from and to)
        // Handle both directions by using min/max for sublist bounds
        final startIndex = fromIndex < toIndex ? fromIndex : toIndex;
        final endIndex = fromIndex < toIndex ? toIndex : fromIndex;
        final intermediate = stopList.sublist(startIndex, endIndex + 1);

        // Get the actual from/to stop models (preserve user's selection order)
        final fromStopModel = stopList[fromIndex];
        final toStopModel = stopList[toIndex];

        if (intermediate.length >= 2) {
          matches.add(RouteSearchResult(
            route: route,
            fromStop: fromStopModel,
            toStop: toStopModel,
            intermediateStops: intermediate,
          ));
        }
      }
    });

    return matches;
  }
}
