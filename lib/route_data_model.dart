import 'package:google_maps_flutter/google_maps_flutter.dart'; // Add this

class BusRouteModel {
  final String id;
  final String label;
  final String name;
  final String origin;
  final String destination;
  final LatLng originCoords;      // <--- ADD THIS
  final LatLng destinationCoords; // <--- ADD THIS
  final String fare;
  final String operatingHours;
  final List<String> stops;

  const BusRouteModel({
    required this.id,
    required this.label,
    required this.name,
    required this.origin,
    required this.destination,
    required this.originCoords,      // <--- Add to constructor
    required this.destinationCoords, // <--- Add to constructor
    required this.fare,
    required this.operatingHours,
    required this.stops,
  });
}

final List<BusRouteModel> allRoutes = [
  BusRouteModel(
    id: 'route_01',
    label: '750',
    name: 'Route 750 (Shah Alam - Pasar Seni)',
    origin: 'UiTM Shah Alam',
    destination: 'Hub Pasar Seni',
    // Real Coordinates for 750 start/end
    originCoords: const LatLng(3.0665, 101.4993), 
    destinationCoords: const LatLng(3.1422, 101.6965),
    fare: 'RM 3.00',
    operatingHours: '06:00 - 23:30',
    stops: ['UiTM', 'Batu 3', 'Asia Jaya', 'KL Sentral', 'Pasar Seni'],
  ),
  BusRouteModel(
    id: 'route_02',
    label: 'GOKL-01',
    name: 'GOKL Green Line',
    origin: 'KLCC',
    destination: 'Bukit Bintang',
    // Real Coordinates for GOKL start/end
    originCoords: const LatLng(3.1579, 101.7116), 
    destinationCoords: const LatLng(3.1485, 101.7145),
    fare: 'Free',
    operatingHours: '06:00 - 23:00',
    stops: ['KLCC', 'Convention Centre', 'Pavilion'],
  ),
];