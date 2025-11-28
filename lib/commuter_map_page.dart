import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'mqtt_service.dart';
import 'route_data_model.dart';
import 'services/directions_service.dart';
import 'services/route_search_service.dart';
import 'keys/directions_api_key.dart';

class CommuterMapPage extends StatefulWidget {
  final String? initialRouteId; // Optional: Pre-select a specific route (legacy)
  final TripSelection? tripSelection; // New: Selected trip from search
  
  const CommuterMapPage({super.key, this.initialRouteId, this.tripSelection});

  @override
  State<CommuterMapPage> createState() => _CommuterMapPageState();
}

class _CommuterMapPageState extends State<CommuterMapPage> {
  final MqttService _mqttService = MqttService();
  StreamSubscription? _sub;
  Timer? _cleanupTimer;

  GoogleMapController? _mapController;
  final LatLng _initialCameraPos = const LatLng(3.1390, 101.6869); // KL

  // routeCode -> busCode -> position
  // Keys are route codes (e.g. "750") and bus codes (e.g. "750-A"), not numeric IDs
  final Map<String, Map<String, LatLng>> _routeBusPositions = {};
  final Map<String, Map<String, DateTime>> _routeLastUpdates = {};
  final Map<String, Map<String, String>> _routeBusStatus = {}; // routeCode -> busCode -> status

  late String _selectedRouteCode; // Route code (e.g. "750"), not numeric ID
  String? _focusedBusId; // Bus code (e.g. "750-A"), not numeric ID

  // Lookup map from bus code -> bus model (for displaying bus details like plateNo)
  late final Map<String, BusInfo> _busLookup;

  // Current route polyline points from Directions API
  List<LatLng> _currentPolylinePoints = [];

  // Destination point for ETA calculation (will be dynamic based on route)
  LatLng? _destination;

  // Custom bus icons (single icon or multiple colored icons)
  BitmapDescriptor? _busIcon; // Default/green icon for "In Service"
  BitmapDescriptor? _busIconRed; // For "Breakdown"
  BitmapDescriptor? _busIconOrange; // For "Delayed"
  BitmapDescriptor? _busIconBlue; // For "Full Capacity"
  BitmapDescriptor? _busIconYellow; // For "Signal Weak"

  @override
  void initState() {
    super.initState();
    // Initialize bus lookup map
    _busLookup = {};
    
    // Initialize selected route code from widget parameters
    if (widget.tripSelection != null) {
      _selectedRouteCode = widget.tripSelection!.route.code.toString();
      // Set focused bus from trip selection
      _focusedBusId = widget.tripSelection!.bus.code;
      // Add the tripSelection bus to lookup map
      _busLookup[widget.tripSelection!.bus.code] = widget.tripSelection!.bus;
    } else if (widget.initialRouteId != null) {
      // Treat initialRouteId as route code (string)
      _selectedRouteCode = widget.initialRouteId!;
    } else {
      // Fallback to first route's code
      _selectedRouteCode = allRoutes.first.code;
    }
    
    // Load custom bus icon
    _loadBusIcon();
    
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
            final lastUpdate = _routeLastUpdates[_selectedRouteCode]?[_focusedBusId];
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

  /// Load custom bus icon(s) from assets
  Future<void> _loadBusIcon() async {
    // Icon size: 32x32 pixels for better map visibility
    const config = ImageConfiguration(size: Size(32, 32));
    
    print('🔧 Loading colored bus icons (bus_icon_{color}.png)...');
    
    // Load status-specific colored bus icons following naming scheme: bus_icon_{color}.png
    try {
      final iconRed = await BitmapDescriptor.asset(config, 'assets/icons/bus_icon_red.png');
      if (mounted) setState(() => _busIconRed = iconRed);
      print('✅ bus_icon_red.png loaded (32x32) - Breakdown');
    } catch (e) {
      print('❌ bus_icon_red.png not found: $e');
    }
    
    try {
      final iconOrange = await BitmapDescriptor.asset(config, 'assets/icons/bus_icon_orange.png');
      if (mounted) setState(() => _busIconOrange = iconOrange);
      print('✅ bus_icon_orange.png loaded (32x32) - Delayed');
    } catch (e) {
      print('❌ bus_icon_orange.png not found: $e');
    }
    
    try {
      final iconBlue = await BitmapDescriptor.asset(config, 'assets/icons/bus_icon_blue.png');
      if (mounted) setState(() => _busIconBlue = iconBlue);
      print('✅ bus_icon_blue.png loaded (32x32) - Full Capacity');
    } catch (e) {
      print('❌ bus_icon_blue.png not found: $e');
    }
    
    try {
      final iconGreen = await BitmapDescriptor.asset(config, 'assets/icons/bus_icon_green.png');
      if (mounted) setState(() => _busIcon = iconGreen);
      print('✅ bus_icon_green.png loaded (32x32) - In Service');
    } catch (e) {
      print('❌ bus_icon_green.png not found: $e');
    }
    
    // Try to load yellow icon for Signal Weak (optional, to be added later)
    try {
      final iconYellow = await BitmapDescriptor.asset(config, 'assets/icons/bus_icon_yellow.png');
      if (mounted) setState(() => _busIconYellow = iconYellow);
      print('✅ bus_icon_yellow.png loaded (32x32) - Signal Weak');
    } catch (e) {
      print('ℹ️ bus_icon_yellow.png not found yet (will use default yellow marker for Signal Weak)');
    }
    
    print('🚌 Bus icon loading complete!');
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
    print('📍 Starting to fetch route');
    
    LatLng origin;
    LatLng destination;
    
    // Use TripSelection if available, otherwise fall back to hardcoded route model
    if (widget.tripSelection != null) {
      // Use dynamic coordinates from selected trip
      origin = LatLng(
        widget.tripSelection!.fromStop.latitude,
        widget.tripSelection!.fromStop.longitude,
      );
      destination = LatLng(
        widget.tripSelection!.toStop.latitude,
        widget.tripSelection!.toStop.longitude,
      );
      
      print('📍 Using trip selection: ${widget.tripSelection!.fromStop.name} → ${widget.tripSelection!.toStop.name}');
      print('📍 Origin: $origin');
      print('📍 Destination: $destination');
    } else {
      // Legacy behavior: use hardcoded route model
      // Match by route code instead of numeric ID
      final routeModel = allRoutes.firstWhere(
        (route) => route.code == _selectedRouteCode,
        orElse: () => allRoutes.first,
      );
      
      origin = routeModel.originCoords;
      destination = routeModel.destinationCoords;
      
      print('📍 Using legacy route model: ${routeModel.code} - ${routeModel.name}');
      print('📍 Origin: $origin');
      print('📍 Destination: $destination');
    }

    // Set destination for ETA calculation
    _destination = destination;

    try {
      // Fetch route from Directions API
      final directionsService = DirectionsService();
      final points = await directionsService.getRoute(origin, destination);

      print('📍 API returned ${points.length} points');

      if (points.isNotEmpty) {
        setState(() {
          _currentPolylinePoints = points;
        });
        print('✅ Successfully loaded ${points.length} polyline points');
        
        // Center camera on the route after a short delay
        Future.delayed(const Duration(milliseconds: 500), () {
          _fitRouteBounds(origin, destination);
        });
      } else {
        // FALLBACK: Draw a simple straight line if API fails
        setState(() {
          _currentPolylinePoints = [origin, destination];
        });
        print('⚠️ No route points from API - using fallback straight line');
        print('⚠️ Fallback points: Origin $origin, Destination $destination');
        
        // Still center camera on origin/destination
        Future.delayed(const Duration(milliseconds: 500), () {
          _fitRouteBounds(origin, destination);
        });
      }
    } catch (e) {
      print('❌ Error fetching route from API: $e');
      
      // FALLBACK: Draw a simple straight line on error
      setState(() {
        _currentPolylinePoints = [origin, destination];
      });
      print('⚠️ Using fallback straight line due to API error');
      
      // Still center camera on origin/destination
      Future.delayed(const Duration(milliseconds: 500), () {
        _fitRouteBounds(origin, destination);
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

      // Subscribe to all bus location topics
      // Topic pattern: rapidkl/bus/+/location (where + matches any bus code)
      // We filter buses by route code in the listener
      await _mqttService.subscribeToAllRoutes();

      _sub = _mqttService.busLocationStream.listen((location) {
        // Debug logging for incoming MQTT updates
        debugPrint(
          '🚌 MQTT UPDATE route=${location.routeId}, '
          'bus=${location.busId}, '
          'lat=${location.lat}, lng=${location.lng}, '
          'status=${location.status}, '
          'ts=${location.timestamp.toIso8601String()}',
        );

        // routeId and busId are already strings (route code and bus code)
        final routeId = location.routeId;
        final busId = location.busId;
        final pos = LatLng(location.lat, location.lng);
        final status = location.status;

        setState(() {
          _routeBusPositions.putIfAbsent(routeId, () => {});
          _routeLastUpdates.putIfAbsent(routeId, () => {});
          _routeBusStatus.putIfAbsent(routeId, () => {});

          _routeBusPositions[routeId]![busId] = pos;
          _routeLastUpdates[routeId]![busId] = location.timestamp;
          _routeBusStatus[routeId]![busId] = status;
        });

        // Auto-follow if this bus is on the selected route & focused
        if (_selectedRouteCode == routeId && _focusedBusId == busId) {
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

    final busesOnRoute = _routeBusPositions[_selectedRouteCode];
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
    // Determine route label, name, origin, destination based on trip selection
    String routeLabel;
    String routeName;
    String routeOrigin;
    String routeDestination;
    LatLng routeOriginCoords;
    LatLng routeDestinationCoords;
    String routeFare;
    String routeOperatingHours = '6:00 AM - 11:00 PM'; // Default
    
    if (widget.tripSelection != null) {
      // Use trip selection data
      routeLabel = widget.tripSelection!.route.code;
      routeName = widget.tripSelection!.route.name;
      routeOrigin = widget.tripSelection!.fromStop.name;
      routeDestination = widget.tripSelection!.toStop.name;
      routeOriginCoords = LatLng(
        widget.tripSelection!.fromStop.latitude,
        widget.tripSelection!.fromStop.longitude,
      );
      routeDestinationCoords = LatLng(
        widget.tripSelection!.toStop.latitude,
        widget.tripSelection!.toStop.longitude,
      );
      routeFare = 'RM ${widget.tripSelection!.route.baseFare.toStringAsFixed(2)}';
    } else {
      // Legacy: Use hardcoded route model
      // Match by route code instead of numeric ID
      final currentRoute = allRoutes.firstWhere(
        (route) => route.code == _selectedRouteCode,
        orElse: () => allRoutes.first,
      );
      routeLabel = currentRoute.code; // Use code as the route label
      routeName = currentRoute.name;
      routeOrigin = currentRoute.origin;
      routeDestination = currentRoute.destination;
      routeOriginCoords = currentRoute.originCoords;
      routeDestinationCoords = currentRoute.destinationCoords;
      routeFare = currentRoute.fare;
      routeOperatingHours = currentRoute.operatingHours;
    }

    final busesOnRoute =
        _routeBusPositions[_selectedRouteCode] ?? <String, LatLng>{};

    // Derive the "current bus" from focusedBusId
    final currentBusCode =
        _focusedBusId ?? widget.tripSelection?.bus.code;
    final currentBus =
        currentBusCode != null ? _busLookup[currentBusCode] : null;

    // Build markers for ALL buses on the selected route
    final markers = busesOnRoute.entries.where((entry) {
      final busId = entry.key;
      final lastUpdate = _routeLastUpdates[_selectedRouteCode]?[busId];

      if (lastUpdate != null) {
        final staleness = DateTime.now().difference(lastUpdate).inSeconds;
        // Hide only ghost buses that haven't updated for a long time
        if (staleness > 300) return false; // 5 minutes is fine
      }

      return true;
    }).map((entry) {
      final busId = entry.key;
      final pos = entry.value;
      final lastUpdate = _routeLastUpdates[_selectedRouteCode]?[busId];
      final status = _routeBusStatus[_selectedRouteCode]?[busId] ?? 'In Service';

      int staleness = 0;
      if (lastUpdate != null) {
        staleness = DateTime.now().difference(lastUpdate).inSeconds;
      }

      // Status priority: Breakdown > Delayed > Full Capacity > Signal Weak (only if staleness > 120 and status is "In Service") > Normal In Service
      String displayStatus;
      BitmapDescriptor markerIcon;

      if (status == 'Breakdown') {
        displayStatus = 'Breakdown';
        markerIcon = _busIconRed ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      } else if (status == 'Delayed') {
        displayStatus = 'Delayed';
        markerIcon = _busIconOrange ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      } else if (status == 'Full Capacity') {
        displayStatus = 'Full Capacity';
        markerIcon = _busIconBlue ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
      } else if (staleness > 120) {
        // Only show Signal Weak when there's no special status AND the last update is old (2+ minutes)
        displayStatus = 'Signal Weak';
        markerIcon = _busIconYellow ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
      } else {
        // Normal "In Service"
        displayStatus = status;
        markerIcon = _busIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      }

      return Marker(
        markerId: MarkerId('bus_${_selectedRouteCode}_$busId'),
        position: pos,
        icon: markerIcon,
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

    // Extra debug info
    debugPrint(
      '🗺️ Markers on route $_selectedRouteCode: ${markers.length} '
      '(busesOnRoute: ${busesOnRoute.keys.toList()})',
    );

    // Add From and To stop markers with distinct colors
    if (_currentPolylinePoints.isNotEmpty) {
      print('🗺️ Adding From marker (blue) at: $routeOriginCoords');
      print('🗺️ Adding To marker (red) at: $routeDestinationCoords');
      
      // From Stop - Blue Marker
      markers.add(
        Marker(
          markerId: const MarkerId('from_stop'),
          position: routeOriginCoords,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: 'From: $routeOrigin',
            snippet: 'Starting point',
          ),
        ),
      );
      
      // To Stop - Red Marker
      markers.add(
        Marker(
          markerId: const MarkerId('to_stop'),
          position: routeDestinationCoords,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: 'To: $routeDestination',
            snippet: 'Destination',
          ),
        ),
      );
      
      print('🗺️ Total markers on map: ${markers.length}');
    } else {
      print('🗺️ NO MARKERS - _currentPolylinePoints is empty, skipping origin/destination markers');
    }

    final focusedBusCode = _focusedBusId; // Bus code (e.g. "750-A")
    final focusedPos = focusedBusCode != null ? busesOnRoute[focusedBusCode] : null;
    final focusedLastUpdate = (focusedBusCode != null)
        ? (_routeLastUpdates[_selectedRouteCode]?[focusedBusCode])
        : null;
    
    // Get the status of the focused bus
    final focusedStatus = (focusedBusCode != null)
        ? (_routeBusStatus[_selectedRouteCode]?[focusedBusCode] ?? 'In Service')
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
          polylineId: PolylineId('${_selectedRouteCode}_path'),
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
                      routeLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Route Name and Direction
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          routeName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        
                        // Show specific trip direction if tripSelection is available
                        if (widget.tripSelection != null) ...[
                          Row(
                            children: [
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: Colors.blue.shade600,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  widget.tripSelection!.fromStop.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(
                                  Icons.arrow_forward,
                                  size: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  widget.tripSelection!.toStop.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: Colors.red.shade600,
                              ),
                            ],
                          ),
                        ] else ...[
                          // Legacy: Show generic origin → destination
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  routeOrigin,
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
                                  routeDestination,
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
                            routeFare.toLowerCase() == 'free'
                                ? Icons.star
                                : Icons.payment,
                            size: 18,
                            color: routeFare.toLowerCase() == 'free'
                                ? Colors.green
                                : Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            routeFare,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: routeFare.toLowerCase() == 'free'
                                  ? Colors.green
                                  : Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                      // Operating Hours (if not using trip selection)
                      if (widget.tripSelection == null)
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              routeOperatingHours,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      // Selected bus info (if current bus is available)
                      if (currentBus != null)
                        Row(
                          children: [
                            const Icon(
                              Icons.directions_bus,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Bus ${currentBus.code} (${currentBus.plateNo})',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w600,
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
                  if (focusedBusCode != null) ...[
                    // Bus header with status badge
                    Row(
                      children: [
                        const Icon(Icons.directions_bus, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Bus $focusedBusCode', // Display bus code (e.g. "750-A")
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
                    
                    // ETA and Active buses (Status-aware styling)
                    Row(
                      children: [
                        if (focusedPos != null && _destination != null) ...[
                          // Determine ETA styling based on bus status
                          Builder(
                            builder: (context) {
                              Color etaBgColor;
                              Color etaBorderColor;
                              Color etaTextColor;
                              IconData etaIcon;
                              String etaText;
                              
                              if (focusedStatus == 'Breakdown') {
                                // 🔴 Breakdown - Show unavailable with red/grey styling
                                etaBgColor = Colors.red.shade50;
                                etaBorderColor = Colors.red.shade300;
                                etaTextColor = Colors.red.shade700;
                                etaIcon = Icons.warning;
                                etaText = 'ETA: Unavailable';
                              } else if (focusedStatus == 'Delayed') {
                                // 🟠 Delayed - Show ETA with orange styling
                                etaBgColor = Colors.orange.shade50;
                                etaBorderColor = Colors.orange.shade300;
                                etaTextColor = Colors.orange.shade700;
                                etaIcon = Icons.access_time;
                                etaText = 'ETA: ${_calculateETA(focusedPos)}';
                              } else if (focusedStatus == 'Full Capacity') {
                                // 🔵 Full Capacity - Show ETA with blue styling
                                etaBgColor = Colors.blue.shade50;
                                etaBorderColor = Colors.blue.shade300;
                                etaTextColor = Colors.blue.shade700;
                                etaIcon = Icons.access_time;
                                etaText = 'ETA: ${_calculateETA(focusedPos)}';
                              } else {
                                // 🟢 Normal/In Service - Show ETA with green styling
                                etaBgColor = Colors.green.shade50;
                                etaBorderColor = Colors.green.shade300;
                                etaTextColor = Colors.green.shade700;
                                etaIcon = Icons.access_time;
                                etaText = 'ETA: ${_calculateETA(focusedPos)}';
                              }
                              
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: etaBgColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: etaBorderColor,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      etaIcon,
                                      size: 14,
                                      color: etaTextColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      etaText,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: etaTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
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
