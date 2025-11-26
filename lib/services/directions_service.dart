import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DirectionsService {
  // TODO: SECURITY WARNING - Move this to environment variables or secure config
  // NEVER commit API keys to version control
  // For now, replace with your own key
  static const String _apiKey = 'AIzaSyDXwkPTUGqpfQJO6YnztAuYOzAw7pvcQeo'; 

  Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    // Initialize with API key
    PolylinePoints polylinePoints = PolylinePoints(apiKey: _apiKey);

    try {
      print('🗺️ Fetching route from (${start.latitude}, ${start.longitude}) to (${end.latitude}, ${end.longitude})');
      
      // VERSION 2.0+ SYNTAX (Current package version)
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        request: PolylineRequest(
          origin: PointLatLng(start.latitude, start.longitude),
          destination: PointLatLng(end.latitude, end.longitude),
          mode: TravelMode.driving,
        ),
      );

      if (result.points.isNotEmpty) {
        print('✅ Successfully fetched ${result.points.length} route points');
        return result.points
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList();
      } else {
        print('⚠️ No route points returned from API. Status: ${result.status}');
        if (result.errorMessage != null) {
          print('❌ Error message: ${result.errorMessage}');
        }
      }
    } catch (e) {
      print("❌ Error fetching route: $e");
      print("💡 Check: 1) API key valid, 2) Billing enabled, 3) Directions API enabled");
    }
    return [];
  }
}