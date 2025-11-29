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
import 'config/supabase_client.dart';

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
  BusInfo? _selectedBus; // Selected bus for tracking (dynamic, not locked to initial)

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
      // Set initial selected bus from trip selection (but allow it to change)
      _selectedBus = widget.tripSelection!.bus;
      // Add the tripSelection bus to lookup map
      _busLookup[widget.tripSelection!.bus.code] = widget.tripSelection!.bus;
    } else if (widget.initialRouteId != null) {
      // Treat initialRouteId as route code (string)
      _selectedRouteCode = widget.initialRouteId!;
      _selectedBus = null; // No initial bus selection
    } else {
      // Fallback to first route's code
      _selectedRouteCode = allRoutes.first.code;
      _selectedBus = null; // No initial bus selection
    }
    
    // Load custom bus icon
    _loadBusIcon();
    
    // Fetch route polyline immediately
    _fetchRoutePolyline();
    
    // Initialize MQTT connection
    _initMqtt();
    
    // Pre-fetch all buses for the selected route to populate lookup
    _prefetchBusesForRoute();
    
    // Start periodic timer to refresh UI and check for stale buses
    _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        setState(() {
          // This forces a rebuild to check timestamps
          // Clean up selected bus if it's stale (but don't force reset - let user choose)
          if (_selectedBus != null) {
            final busCode = _selectedBus!.code;
            final lastUpdate = _routeLastUpdates[_selectedRouteCode]?[busCode];
            if (lastUpdate != null) {
              final staleness = DateTime.now().difference(lastUpdate).inSeconds;
              if (staleness > 300) {
                // Very stale bus (5+ minutes), but don't auto-reset - let user see it's stale
                // The UI will show "Signal Weak" or similar status
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

        // Auto-follow if this bus is on the selected route & selected
        if (_selectedRouteCode == routeId && _selectedBus?.code == busId) {
          _mapController?.animateCamera(CameraUpdate.newLatLng(pos));
        }
        
        // Update bus lookup when we receive MQTT updates
        // Create a basic entry if we don't have full bus info yet
        if (!_busLookup.containsKey(busId)) {
          // Create a temporary bus info entry for buses that appear via MQTT
          // This allows users to select buses even if they weren't in the initial trip selection
          final tempBus = BusInfo(
            id: 0, // Temporary - will be updated if real data arrives
            routeId: 0, // Temporary
            plateNo: 'N/A',
            code: busId,
            isActive: true,
          );
          _busLookup[busId] = tempBus;
          
          // Fetch real bus data from Supabase in the background
          _fetchBusInfoByCode(busId);
        } else {
          // Check if we have temporary data and fetch real data if needed
          final existingBus = _busLookup[busId];
          if (existingBus != null && (existingBus.plateNo == 'N/A' || existingBus.id == 0)) {
            _fetchBusInfoByCode(busId);
          }
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

  void _onRecenterPressed() {
    if (_selectedBus == null || _mapController == null) return;

    final busesOnRoute = _routeBusPositions[_selectedRouteCode];
    if (busesOnRoute == null) return;

    final pos = busesOnRoute[_selectedBus!.code];
    if (pos == null) return;

    _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(
        pos,
        15.0,
      ),
    );
  }
  
  void _recenterOnSelectedBus() {
    if (_selectedBus == null || _mapController == null) return;

    final busesOnRoute = _routeBusPositions[_selectedRouteCode];
    if (busesOnRoute == null) return;

    final pos = busesOnRoute[_selectedBus!.code];
    if (pos == null) return;

    _mapController!.animateCamera(CameraUpdate.newLatLng(pos));
  }
  
  void _moveCameraToBus(BusInfo bus) {
    if (_mapController == null) return;
    
    final busesOnRoute = _routeBusPositions[_selectedRouteCode];
    if (busesOnRoute == null) return;
    
    final pos = busesOnRoute[bus.code];
    if (pos == null) return;
    
    _mapController!.animateCamera(CameraUpdate.newLatLng(pos));
  }

  /// Pre-fetch all buses for the selected route to populate lookup map
  Future<void> _prefetchBusesForRoute() async {
    try {
      // First, get the route ID from the route code
      final routeResponse = await supabase
          .from('routes')
          .select('id')
          .eq('code', _selectedRouteCode)
          .maybeSingle();

      if (routeResponse == null) {
        print('⚠️ Route with code $_selectedRouteCode not found');
        return;
      }

      final routeId = routeResponse['id'] as int;

      // Fetch all active buses for this route
      final busesResponse = await supabase
          .from('buses')
          .select()
          .eq('route_id', routeId)
          .eq('is_active', true);

      final buses = (busesResponse as List)
          .map((json) => BusInfo.fromJson(json))
          .toList();

      // Update lookup map
      setState(() {
        for (final bus in buses) {
          _busLookup[bus.code] = bus;
        }
        
        // If we have a selected bus, make sure it's updated with real data
        if (_selectedBus != null) {
          final updatedBus = _busLookup[_selectedBus!.code];
          if (updatedBus != null) {
            _selectedBus = updatedBus;
          }
        }
      });

      print('✅ Pre-fetched ${buses.length} buses for route $_selectedRouteCode');
    } catch (e) {
      print('❌ Error pre-fetching buses for route: $e');
      // Don't throw - allow the app to continue
    }
  }

  /// Fetch bus information from Supabase by bus code
  /// Updates the bus lookup map with real data
  Future<void> _fetchBusInfoByCode(String busCode) async {
    try {
      // Skip if we already have this bus in lookup with real data (not temporary)
      if (_busLookup.containsKey(busCode)) {
        final existingBus = _busLookup[busCode];
        if (existingBus != null && existingBus.plateNo != 'N/A' && existingBus.id != 0) {
          return; // Already have real data
        }
      }

      // Query Supabase for bus by code
      final response = await supabase
          .from('buses')
          .select()
          .eq('code', busCode)
          .maybeSingle();

      if (response != null) {
        final busInfo = BusInfo.fromJson(response);
        
        // Update the lookup map
        setState(() {
          _busLookup[busCode] = busInfo;
          
          // If this is the currently selected bus, update it
          if (_selectedBus?.code == busCode) {
            _selectedBus = busInfo;
          }
        });
        
        print('✅ Fetched bus info for $busCode: ${busInfo.plateNo}');
      } else {
        print('⚠️ Bus with code $busCode not found in database');
      }
    } catch (e) {
      print('❌ Error fetching bus info for $busCode: $e');
      // Don't throw - allow the app to continue with temporary data
    }
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

  /// Format last update timestamp for display
  String _formatLastUpdate(DateTime lastUpdate) {
    final now = DateTime.now();
    final difference = now.difference(lastUpdate);
    
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      // Format as date and time
      return '${lastUpdate.day}/${lastUpdate.month} ${lastUpdate.hour}:${lastUpdate.minute.toString().padLeft(2, '0')}';
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
    String? routeFare;
    
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
    }

    final busesOnRoute =
        _routeBusPositions[_selectedRouteCode] ?? <String, LatLng>{};

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
          // Find or create bus info for this bus
          BusInfo? busInfo = _busLookup[busId];
          if (busInfo == null) {
            // Create a basic bus info entry if we don't have it
            // This can happen if bus appears via MQTT before being in lookup
            // We'll use the bus code as a temporary identifier
            busInfo = BusInfo(
              id: 0, // Temporary - will be updated when real data arrives
              routeId: 0, // Temporary
              plateNo: 'N/A',
              code: busId,
              isActive: true,
            );
            _busLookup[busId] = busInfo;
            
            // Fetch real bus data from Supabase in the background
            _fetchBusInfoByCode(busId);
          } else if (busInfo.plateNo == 'N/A' || busInfo.id == 0) {
            // We have temporary data, fetch real data
            _fetchBusInfoByCode(busId);
          }
          
          setState(() {
            _selectedBus = busInfo;
          });
          
          // Move camera to selected bus
          _moveCameraToBus(busInfo);
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

    // Get data for selected bus
    final selectedBusCode = _selectedBus?.code; // Bus code (e.g. "750-A")
    final selectedPos = selectedBusCode != null ? busesOnRoute[selectedBusCode] : null;
    final selectedLastUpdate = (selectedBusCode != null)
        ? (_routeLastUpdates[_selectedRouteCode]?[selectedBusCode])
        : null;
    
    // Get the status of the selected bus
    final selectedStatus = (selectedBusCode != null)
        ? (_routeBusStatus[_selectedRouteCode]?[selectedBusCode] ?? 'In Service')
        : 'In Service';

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
      appBar: AppBar(
        title: const Text('Commuter View'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: Stack(
        children: [
          // 1) Map fills the screen
          Positioned.fill(
            child: GoogleMap(
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
          ),

          // 2) Top route summary card
          Positioned(
            top: kToolbarHeight + 12, // below AppBar
            left: 16,
            right: 16,
            child: _RouteSummaryCard(
              routeCode: routeLabel,
              routeName: routeName,
              origin: routeOrigin,
              destination: routeDestination,
            ),
          ),

          // 3) Floating recenter button (bottom-right above bottom card)
          if (selectedPos != null && _selectedBus != null)
            Positioned(
              right: 16,
              bottom: 200, // adjust so it sits above bottom card
              child: FloatingActionButton.small(
                heroTag: 'recenter_fab',
                onPressed: _onRecenterPressed,
                child: const Icon(Icons.my_location),
              ),
            ),

          // 4) Bottom card anchored to bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _AnimatedBusBottomCard(
              selectedBus: _selectedBus,
              activeBusCount: activeBusIds.length,
              routeFare: routeFare,
              selectedStatus: selectedStatus,
              selectedLastUpdate: selectedLastUpdate,
              etaText: selectedPos != null && _destination != null
                  ? (selectedStatus == 'Breakdown'
                      ? 'ETA: Unavailable'
                      : 'ETA: ${_calculateETA(selectedPos)}')
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// Route Summary Card Widget
class _RouteSummaryCard extends StatelessWidget {
  final String routeCode;
  final String routeName;
  final String origin;
  final String destination;

  const _RouteSummaryCard({
    required this.routeCode,
    required this.routeName,
    required this.origin,
    required this.destination,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF00695C),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              routeCode,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  routeName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.circle, size: 8, color: Colors.blue),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        origin,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 14),
                    const SizedBox(width: 8),
                    const Icon(Icons.circle, size: 8, color: Colors.red),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        destination,
                        style: const TextStyle(fontSize: 12),
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
    );
  }
}

// Animated Bottom Card Widget
class _AnimatedBusBottomCard extends StatelessWidget {
  final BusInfo? selectedBus;
  final int activeBusCount;
  final String? routeFare;
  final String? selectedStatus;
  final DateTime? selectedLastUpdate;
  final String? etaText;

  const _AnimatedBusBottomCard({
    required this.selectedBus,
    required this.activeBusCount,
    this.routeFare,
    this.selectedStatus,
    this.selectedLastUpdate,
    this.etaText,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.2),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: selectedBus == null
          ? const SizedBox.shrink()
          : _BusBottomCard(
              key: ValueKey(selectedBus!.code),
              bus: selectedBus!,
              activeBusCount: activeBusCount,
              routeFare: routeFare,
              selectedStatus: selectedStatus,
              selectedLastUpdate: selectedLastUpdate,
              etaText: etaText,
            ),
    );
  }
}

// Bottom Card Content Widget
class _BusBottomCard extends StatelessWidget {
  final BusInfo bus;
  final int activeBusCount;
  final String? routeFare;
  final String? selectedStatus;
  final DateTime? selectedLastUpdate;
  final String? etaText;

  const _BusBottomCard({
    super.key,
    required this.bus,
    required this.activeBusCount,
    this.routeFare,
    this.selectedStatus,
    this.selectedLastUpdate,
    this.etaText,
  });

  @override
  Widget build(BuildContext context) {
    final String busCode = bus.code;
    final String plate = bus.plateNo;
    final String status = selectedStatus ?? 'In Service';

    final bool isActive = status.toLowerCase() == 'in service';

    final Color statusColor;
    if (status.toLowerCase().contains('delay')) {
      statusColor = const Color(0xFFFFA726); // orange
    } else if (status.toLowerCase().contains('break')) {
      statusColor = const Color(0xFFE53935); // red
    } else if (status.toLowerCase().contains('full')) {
      statusColor = const Color(0xFF42A5F5); // blue
    } else {
      statusColor = const Color(0xFF43A047); // green
    }

    final String activeLabel = activeBusCount <= 0
        ? 'No buses active'
        : '$activeBusCount bus${activeBusCount > 1 ? 'es' : ''} active';

    String? lastUpdatedFormatted;
    if (selectedLastUpdate != null) {
      final now = DateTime.now();
      final difference = now.difference(selectedLastUpdate!);
      
      if (difference.inSeconds < 60) {
        lastUpdatedFormatted = '${difference.inSeconds}s ago';
      } else if (difference.inMinutes < 60) {
        lastUpdatedFormatted = '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        lastUpdatedFormatted = '${difference.inHours}h ago';
      } else {
        lastUpdatedFormatted = '${selectedLastUpdate!.day}/${selectedLastUpdate!.month} ${selectedLastUpdate!.hour}:${selectedLastUpdate!.minute.toString().padLeft(2, '0')}';
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Small drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Row 1: Bus + Fare
          Row(
            children: [
              const Icon(Icons.directions_bus, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bus $busCode ($plate)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (routeFare != null)
                Text(
                  routeFare!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Active count + Status pill
          Row(
            children: [
              const Icon(Icons.people_alt_outlined, size: 18),
              const SizedBox(width: 6),
              Text(
                activeLabel,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade800,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isActive ? Icons.check_circle : Icons.error_outline,
                      size: 16,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (etaText != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  etaText!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
          if (lastUpdatedFormatted != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.update, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  'Last updated: $lastUpdatedFormatted',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
