import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'mqtt_service.dart';
import 'route_data_model.dart';
import 'services/directions_service.dart';
import 'keys/directions_api_key.dart';

class CommuterMapPage extends StatefulWidget {
  final String? initialRouteId; // Optional: Pre-select a specific route
  
  const CommuterMapPage({super.key, this.initialRouteId});

  @override
  State<CommuterMapPage> createState() => _CommuterMapPageState();
}

class _CommuterMapPageState extends State<CommuterMapPage> {
  final MqttService _mqttService = MqttService();
  StreamSubscription? _sub;
  Timer? _cleanupTimer;

  GoogleMapController? _mapController;
  final LatLng _initialCameraPos = const LatLng(3.1390, 101.6869); // KL

  // routeId -> busId -> position
  final Map<String, Map<String, LatLng>> _routeBusPositions = {};
  final Map<String, Map<String, DateTime>> _routeLastUpdates = {};
  final Map<String, Map<String, String>> _routeBusStatus = {}; // routeId -> busId -> status

  late String _selectedRouteId;
  String? _focusedBusId;

  // Current route polyline points from Directions API
  List<LatLng> _currentPolylinePoints = [];

  // Destination point for ETA calculation (will be dynamic based on route)
  LatLng? _destination;

  @override
  void initState() {
    super.initState();
    // Initialize selected route from widget parameter or default to route_01
    _selectedRouteId = widget.initialRouteId ?? 'route_01';
    
    // Fetch route polyline immediately
    _fetchRoutePolyline();
    
    // Initialize MQTT connection
    _initMqtt();
    
    // Start periodic timer to refresh UI and check for stale buses
    _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        setState(() {
          // This forces a rebuild to check timestamps
          // Clean up focused bus if it's stale
          if (_focusedBusId != null) {
            final lastUpdate = _routeLastUpdates[_selectedRouteId]?[_focusedBusId];
            if (lastUpdate != null) {
              final staleness = DateTime.now().difference(lastUpdate).inSeconds;
              if (staleness > 60) {
                // Ghost bus detected, reset focus
                _focusedBusId = null;
              }
            }
          }
        });
      }
    });
  }

  /// Debug function to test Directions API via raw HTTP
  Future<void> testDirectionsFromApp() async {
    debugPrint('Using Directions key prefix: ${directionsApiKey.substring(0, 8)}');
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=3.0738,101.5183'
      '&destination=3.1390,101.6869'
      '&mode=driving'
      '&key=$directionsApiKey',
    );
    try {
      final response = await http.get(url);
      debugPrint('Status code: ${response.statusCode}');
      debugPrint('Body: ${response.body}');
    } catch (e) {
      debugPrint('HTTP error: $e');
    }
  }

  /// Fetch route polyline from Directions API
  Future<void> _fetchRoutePolyline() async {
    print('📍 Starting to fetch route for: $_selectedRouteId');
    
    // Find the route model
    final routeModel = allRoutes.firstWhere(
      (route) => route.id == _selectedRouteId,
      orElse: () => allRoutes.first,
    );

    print('📍 Route Model Found: ${routeModel.label} - ${routeModel.name}');
    print('📍 Origin: ${routeModel.originCoords}');
    print('📍 Destination: ${routeModel.destinationCoords}');

    // Set destination for ETA calculation
    _destination = routeModel.destinationCoords;

    try {
      // Fetch route from Directions API
      final directionsService = DirectionsService();
      final points = await directionsService.getRoute(
        routeModel.originCoords,
        routeModel.destinationCoords,
      );

      print('📍 API returned ${points.length} points');

      if (points.isNotEmpty) {
        setState(() {
          _currentPolylinePoints = points;
        });
        print('✅ Successfully loaded ${points.length} polyline points for $_selectedRouteId');
        
        // Center camera on the route after a short delay
        Future.delayed(const Duration(milliseconds: 500), () {
          _fitRouteBounds(routeModel.originCoords, routeModel.destinationCoords);
        });
      } else {
        // FALLBACK: Draw a simple straight line if API fails
        setState(() {
          _currentPolylinePoints = [
            routeModel.originCoords,
            routeModel.destinationCoords,
          ];
        });
        print('⚠️ No route points from API - using fallback straight line for $_selectedRouteId');
        print('⚠️ Fallback points: Origin ${routeModel.originCoords}, Destination ${routeModel.destinationCoords}');
        print('⚠️ _currentPolylinePoints now has ${_currentPolylinePoints.length} points');
        
        // Still center camera on origin/destination
        Future.delayed(const Duration(milliseconds: 500), () {
          _fitRouteBounds(routeModel.originCoords, routeModel.destinationCoords);
        });
      }
    } catch (e) {
      print('❌ Error fetching route from API: $e');
      
      // FALLBACK: Draw a simple straight line on error
      setState(() {
        _currentPolylinePoints = [
          routeModel.originCoords,
          routeModel.destinationCoords,
        ];
      });
      print('⚠️ Using fallback straight line due to API error');
      print('⚠️ Fallback points: Origin ${routeModel.originCoords}, Destination ${routeModel.destinationCoords}');
      print('⚠️ _currentPolylinePoints now has ${_currentPolylinePoints.length} points');
      
      // Still center camera on origin/destination
      Future.delayed(const Duration(milliseconds: 500), () {
        _fitRouteBounds(routeModel.originCoords, routeModel.destinationCoords);
      });
    }
  }

  /// Fit camera to show the entire route
  void _fitRouteBounds(LatLng origin, LatLng destination) {
    if (_mapController == null) return;

    // Calculate bounds
    final double minLat = origin.latitude < destination.latitude
        ? origin.latitude
        : destination.latitude;
    final double maxLat = origin.latitude > destination.latitude
        ? origin.latitude
        : destination.latitude;
    final double minLng = origin.longitude < destination.longitude
        ? origin.longitude
        : destination.longitude;
    final double maxLng = origin.longitude > destination.longitude
        ? origin.longitude
        : destination.longitude;

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80), // 80px padding
    );
    
    print('📍 Camera positioned to show route bounds');
  }

  Future<void> _initMqtt() async {
    try {
      await _mqttService.connect();

      await _mqttService.subscribeToAllRoutes();

      _sub = _mqttService.busLocationStream.listen((location) {
        final routeId = location.routeId;
        final busId = location.busId;
        final pos = LatLng(location.lat, location.lng);
        final status = location.status; // Capture status

        print('🚌 COMMUTER: Received update for $busId on $routeId - Status: $status');

        setState(() {
          _routeBusPositions.putIfAbsent(routeId, () => {});
          _routeLastUpdates.putIfAbsent(routeId, () => {});
          _routeBusStatus.putIfAbsent(routeId, () => {}); // Initialize status map

          _routeBusPositions[routeId]![busId] = pos;
          _routeLastUpdates[routeId]![busId] = location.timestamp;
          _routeBusStatus[routeId]![busId] = status; // Save status

          print('🚌 COMMUTER: Saved status for $busId: ${_routeBusStatus[routeId]![busId]}');

          // Fix: Auto-select first bus
          if (_focusedBusId == null) _focusedBusId = busId;
        });

        // Auto-follow if this bus is on the selected route & focused
        if (_selectedRouteId == routeId && _focusedBusId == busId) {
          _mapController?.animateCamera(CameraUpdate.newLatLng(pos));
        }
      });
    } catch (e) {
      print('MQTT connection error: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _cleanupTimer?.cancel();
    super.dispose();
  }

  void _recenterOnFocusedBus() {
    if (_focusedBusId == null || _mapController == null) return;

    final busesOnRoute = _routeBusPositions[_selectedRouteId];
    if (busesOnRoute == null) return;

    final pos = busesOnRoute[_focusedBusId!];
    if (pos == null) return;

    _mapController!.animateCamera(CameraUpdate.newLatLng(pos));
  }

  /// Calculate ETA from bus position to destination
  /// Assumes average speed of 40 km/h (approx 666 meters/minute)
  String _calculateETA(LatLng busPos) {
    if (_destination == null) return 'N/A';
    
    final distanceInMeters = Geolocator.distanceBetween(
      busPos.latitude,
      busPos.longitude,
      _destination!.latitude,
      _destination!.longitude,
    );

    // Average speed: 40 km/h = 40000 m/h = 666.67 m/min
    const speedInMetersPerMinute = 666.67;
    final minutes = distanceInMeters / speedInMetersPerMinute;

    if (minutes < 1) {
      return 'Arriving now';
    } else if (minutes < 60) {
      return '~${minutes.round()} mins';
    } else {
      final hours = (minutes / 60).floor();
      final remainingMins = (minutes % 60).round();
      return '~${hours}h ${remainingMins}m';
    }
  }


  @override
  Widget build(BuildContext context) {
    // Get current route model
    final currentRoute = allRoutes.firstWhere(
      (route) => route.id == _selectedRouteId,
      orElse: () => allRoutes.first,
    );

    final busesOnRoute =
        _routeBusPositions[_selectedRouteId] ?? <String, LatLng>{};

    // Build markers only for the selected route with staleness check
    final markers = busesOnRoute.entries.where((entry) {
      final busId = entry.key;
      final lastUpdate = _routeLastUpdates[_selectedRouteId]?[busId];
      
      // Filter out ghost buses (>60 seconds stale)
      if (lastUpdate != null) {
        final staleness = DateTime.now().difference(lastUpdate).inSeconds;
        if (staleness > 60) {
          return false; // Skip this bus marker
        }
      }
      return true;
    }).map((entry) {
      final busId = entry.key;
      final pos = entry.value;
      final lastUpdate = _routeLastUpdates[_selectedRouteId]?[busId];
      
      // Check staleness for signal warning
      int staleness = 0;
      if (lastUpdate != null) {
        staleness = DateTime.now().difference(lastUpdate).inSeconds;
      }
      
      // Read the status for this bus
      final status = _routeBusStatus[_selectedRouteId]?[busId] ?? 'In Service';
      
      // Determine marker color: Priority 1 = Signal Health, Priority 2 = Bus Status
      double markerHue;
      String displayStatus;
      
      // First Check: Stale signal (>30 seconds)
      if (staleness > 30) {
        markerHue = BitmapDescriptor.hueYellow;
        displayStatus = 'Signal Weak';
      } 
      // Second Check: Good signal, check bus status
      else {
        displayStatus = status;
        if (status == 'Breakdown') {
          markerHue = BitmapDescriptor.hueRed;
        } else if (status == 'Delayed') {
          markerHue = BitmapDescriptor.hueOrange;
        } else if (status == 'Full Capacity') {
          markerHue = BitmapDescriptor.hueAzure;
        } else {
          markerHue = BitmapDescriptor.hueGreen;
        }
      }

      return Marker(
        markerId: MarkerId('bus_${_selectedRouteId}_$busId'),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(markerHue),
        infoWindow: InfoWindow(
          title: 'Bus $busId',
          snippet: 'Status: $displayStatus',
        ),
        onTap: () {
          setState(() {
            _focusedBusId = busId;
          });
        },
      );
    }).toSet();

    // Add origin and destination markers
    if (_currentPolylinePoints.isNotEmpty) {
      print('🗺️ Adding origin marker at: ${currentRoute.originCoords}');
      print('🗺️ Adding destination marker at: ${currentRoute.destinationCoords}');
      
      markers.add(
        Marker(
          markerId: const MarkerId('route_origin'),
          position: currentRoute.originCoords,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: InfoWindow(
            title: '🚏 ${currentRoute.origin}',
            snippet: 'Origin',
          ),
        ),
      );
      markers.add(
        Marker(
          markerId: const MarkerId('route_destination'),
          position: currentRoute.destinationCoords,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: InfoWindow(
            title: '🚏 ${currentRoute.destination}',
            snippet: 'Destination',
          ),
        ),
      );
      print('🗺️ Total markers on map: ${markers.length}');
    } else {
      print('🗺️ NO MARKERS - _currentPolylinePoints is empty, skipping origin/destination markers');
    }

    final focusedBusId = _focusedBusId;
    final focusedPos = focusedBusId != null ? busesOnRoute[focusedBusId] : null;
    final focusedLastUpdate = (focusedBusId != null)
        ? (_routeLastUpdates[_selectedRouteId]?[focusedBusId])
        : null;
    
    // Get the status of the focused bus
    final focusedStatus = (focusedBusId != null)
        ? (_routeBusStatus[_selectedRouteId]?[focusedBusId] ?? 'In Service')
        : 'In Service';
    
    // Determine badge color, text, and icon based on status
    Color badgeColor;
    String badgeText;
    IconData badgeIcon;
    
    if (focusedStatus == 'Breakdown') {
      badgeColor = Colors.red;
      badgeText = 'Breakdown';
      badgeIcon = Icons.warning;
    } else if (focusedStatus == 'Delayed') {
      badgeColor = Colors.orange;
      badgeText = 'Delayed';
      badgeIcon = Icons.access_time;
    } else if (focusedStatus == 'Full Capacity') {
      badgeColor = Colors.blue;
      badgeText = 'Full Capacity';
      badgeIcon = Icons.people;
    } else if (focusedStatus == 'Signal Weak') {
      badgeColor = Colors.yellow.shade700;
      badgeText = 'Signal Weak';
      badgeIcon = Icons.signal_wifi_statusbar_connected_no_internet_4;
    } else {
      // 'In Service' or default
      badgeColor = Colors.green;
      badgeText = focusedStatus;
      badgeIcon = Icons.check_circle;
    }

    final activeBusIds = busesOnRoute.keys.toList();

    // Build polyline from current route points
    final Set<Polyline> polylines = {};
    if (_currentPolylinePoints.isNotEmpty) {
      print('🗺️ Building polyline with ${_currentPolylinePoints.length} points');
      print('🗺️ First point: ${_currentPolylinePoints.first}');
      print('🗺️ Last point: ${_currentPolylinePoints.last}');
      
      polylines.add(
        Polyline(
          polylineId: PolylineId('${_selectedRouteId}_path'),
          points: _currentPolylinePoints,
          color: Colors.blue, // Changed from teal to blue
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
      print('🗺️ Polyline added to map');
    } else {
      print('🗺️ NO POLYLINE POINTS - _currentPolylinePoints is empty!');
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Commuter View')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialCameraPos,
              zoom: 14,
            ),
            markers: markers,
            polylines: polylines,
            onMapCreated: (controller) {
              _mapController = controller;
            },
          ),

          // Top Route Header Card
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Route Label Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      currentRoute.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Origin → Destination
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentRoute.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                currentRoute.origin,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                Icons.arrow_forward,
                                size: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            Flexible(
                              child: Text(
                                currentRoute.destination,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Info Sheet
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Static Route Data (Always visible)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Fare
                      Row(
                        children: [
                          Icon(
                            currentRoute.fare.toLowerCase() == 'free'
                                ? Icons.star
                                : Icons.payment,
                            size: 18,
                            color: currentRoute.fare.toLowerCase() == 'free'
                                ? Colors.green
                                : Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            currentRoute.fare,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: currentRoute.fare.toLowerCase() == 'free'
                                  ? Colors.green
                                  : Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                      // Operating Hours
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            currentRoute.operatingHours,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  
                  // Live Bus Data (Conditional)
                  if (focusedBusId != null) ...[
                    // Bus header with status badge
                    Row(
                      children: [
                        const Icon(Icons.directions_bus, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Bus $focusedBusId',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                badgeIcon,
                                size: 12,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                badgeText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // ETA and Active buses
                    Row(
                      children: [
                        if (focusedPos != null && _destination != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.green.shade300,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Colors.green.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'ETA: ${_calculateETA(focusedPos)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          '${activeBusIds.length} bus(es) active',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    if (focusedLastUpdate != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Last update: $focusedLastUpdate',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ] else ...[
                    // No bus tracking - show waiting message
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Waiting for bus departure...',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Debug button for testing Directions API
          Positioned(
            top: 100,
            right: 12,
            child: ElevatedButton(
              onPressed: testDirectionsFromApp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('Test Directions API'),
            ),
          ),
        ],
      ),
      floatingActionButton: focusedPos != null
          ? FloatingActionButton(
              onPressed: _recenterOnFocusedBus,
              tooltip: 'Recenter on bus',
              child: const Icon(Icons.my_location),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
