import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'mqtt_service.dart';

class CommuterMapPage extends StatefulWidget {
  const CommuterMapPage({super.key});

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

  // Demo routes (later can come from Supabase or config)
  final List<String> _routes = ['route_01', 'route_02'];
  String _selectedRouteId = 'route_01';

  // Route name mapping for display
  final Map<String, String> _routeNames = {
    'route_01': 'Wangsa Maju → TARUMT',
    'route_02': 'Aeon Big Danau Kota → Setapak Central',
  };

  String? _focusedBusId;

  // Destination point (KL Sentral) for ETA calculation
  final LatLng _destination = const LatLng(3.1335, 101.6868);

  // Route 01 polyline coordinates (Actual GPS tracking - 60 points)
  final List<LatLng> _route01Points = const [
    LatLng(3.2052117, 101.7319433),
    LatLng(3.2056799, 101.7313395),
    LatLng(3.2061699, 101.7307299),
    LatLng(3.2065508, 101.7302284),
    LatLng(3.206924, 101.7298496),
    LatLng(3.2071134, 101.7296231),
    LatLng(3.2072935, 101.7293998),
    LatLng(3.2074943, 101.7291421),
    LatLng(3.2076798, 101.728934),
    LatLng(3.2078702, 101.7287295),
    LatLng(3.2080998, 101.7285106),
    LatLng(3.208305, 101.7282949),
    LatLng(3.20851, 101.7280799),
    LatLng(3.2087103, 101.7278603),
    LatLng(3.2089051, 101.7278338),
    LatLng(3.2090451, 101.7279732),
    LatLng(3.2092199, 101.7281496),
    LatLng(3.2094001, 101.7283033),
    LatLng(3.2095817, 101.7284567),
    LatLng(3.2097666, 101.7286083),
    LatLng(3.209955, 101.7287532),
    LatLng(3.2101305, 101.7288902),
    LatLng(3.2103376, 101.7290545),
    LatLng(3.2105399, 101.7291833),
    LatLng(3.2106194, 101.7290925),
    LatLng(3.2107403, 101.72888),
    LatLng(3.2108817, 101.7286733),
    LatLng(3.2110395, 101.7284506),
    LatLng(3.2112076, 101.7285302),
    LatLng(3.2113918, 101.72863),
    LatLng(3.2116089, 101.7287511),
    LatLng(3.211795, 101.728855),
    LatLng(3.2119687, 101.728947),
    LatLng(3.2121569, 101.7290399),
    LatLng(3.2123401, 101.7291466),
    LatLng(3.2125202, 101.72925),
    LatLng(3.2127084, 101.7293433),
    LatLng(3.212908, 101.7294513),
    LatLng(3.2130933, 101.729555),
    LatLng(3.2132687, 101.7296519),
    LatLng(3.2134341, 101.7297371),
    LatLng(3.2136491, 101.7298527),
    LatLng(3.2138236, 101.7299519),
    LatLng(3.2140067, 101.7300583),
    LatLng(3.2141804, 101.7301601),
    LatLng(3.2143798, 101.7302499),
    LatLng(3.2145456, 101.7303826),
    LatLng(3.2146674, 101.7303222),
    LatLng(3.2147903, 101.7302199),
    LatLng(3.21489, 101.7300849),
    LatLng(3.2149932, 101.7299306),
    LatLng(3.2150702, 101.7297784),
    LatLng(3.2151208, 101.7296394),
    LatLng(3.2151569, 101.7294589),
    LatLng(3.2151559, 101.7292948),
    LatLng(3.2151431, 101.729141),
    LatLng(3.2151122, 101.7289796),
    LatLng(3.2150553, 101.7288022),
    LatLng(3.2149951, 101.7286384),
    LatLng(3.2149492, 101.7285282),
  ];

  // Route 02 polyline coordinates (Actual GPS tracking - 33 points)
  final List<LatLng> _route02Points = const [
    LatLng(3.204415, 101.7157183),
    LatLng(3.2043605, 101.7157135),
    LatLng(3.2042001, 101.71583),
    LatLng(3.2040417, 101.7159483),
    LatLng(3.2038801, 101.7160699),
    LatLng(3.2037362, 101.7161592),
    LatLng(3.2035602, 101.7162583),
    LatLng(3.2033803, 101.7163599),
    LatLng(3.2031982, 101.7164316),
    LatLng(3.2030103, 101.7165199),
    LatLng(3.2028563, 101.716622),
    LatLng(3.2027064, 101.716732),
    LatLng(3.2025338, 101.716858),
    LatLng(3.2023831, 101.7169686),
    LatLng(3.2022378, 101.7170785),
    LatLng(3.2020706, 101.7172098),
    LatLng(3.2019049, 101.7173166),
    LatLng(3.2017467, 101.7174334),
    LatLng(3.2015653, 101.7175715),
    LatLng(3.2014099, 101.7176918),
    LatLng(3.201255, 101.7178118),
    LatLng(3.2010933, 101.7179351),
    LatLng(3.2009623, 101.7180342),
    LatLng(3.200805, 101.7181517),
    LatLng(3.2007096, 101.7183105),
    LatLng(3.2009437, 101.7186073),
    LatLng(3.2011325, 101.7188609),
    LatLng(3.2013401, 101.7191617),
    LatLng(3.2015483, 101.7194633),
    LatLng(3.2017404, 101.7197553),
    LatLng(3.2019794, 101.7200535),
    LatLng(3.2022119, 101.7203284),
    LatLng(3.2023424, 101.720483),
  ];

  /// Build Route 01 bus stop markers
  Set<Marker> _getRoute01Stops() {
    return {
      Marker(
        markerId: const MarkerId('stop_route01_start'),
        position: _route01Points.first, // Wangsa Maju
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: const InfoWindow(
          title: '🚏 Wangsa Maju',
          snippet: 'Route 01 Start',
        ),
      ),
      Marker(
        markerId: const MarkerId('stop_route01_middle'),
        position: _route01Points[30], // Middle point (~Taman Bunga Raya)
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: const InfoWindow(
          title: '🚏 Taman Bunga Raya',
          snippet: 'Route 01 Stop',
        ),
      ),
      Marker(
        markerId: const MarkerId('stop_route01_end'),
        position: _route01Points.last, // TARUMT Main Gate
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: const InfoWindow(
          title: '🚏 TARUMT Main Gate',
          snippet: 'Route 01 End',
        ),
      ),
    };
  }

  /// Build Route 02 bus stop markers
  Set<Marker> _getRoute02Stops() {
    return {
      Marker(
        markerId: const MarkerId('stop_route02_start'),
        position: _route02Points.first, // Aeon Big Danau Kota
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: const InfoWindow(
          title: '🚏 Aeon Big Danau Kota',
          snippet: 'Route 02 Start',
        ),
      ),
      Marker(
        markerId: const MarkerId('stop_route02_end'),
        position: _route02Points.last, // Setapak Central
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: const InfoWindow(
          title: '🚏 Setapak Central',
          snippet: 'Route 02 End',
        ),
      ),
    };
  }

  @override
  void initState() {
    super.initState();
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
    final distanceInMeters = Geolocator.distanceBetween(
      busPos.latitude,
      busPos.longitude,
      _destination.latitude,
      _destination.longitude,
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
          print('👻 COMMUTER: Ghost bus detected - $busId (stale for ${staleness}s)');
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
      
      print('🎨 COMMUTER: Building marker for $busId - Status: "$status", Staleness: ${staleness}s');
      
      // Determine marker color: Priority 1 = Signal Health, Priority 2 = Bus Status
      double markerHue;
      String displayStatus;
      
      // First Check: Stale signal (>30 seconds)
      if (staleness > 30) {
        markerHue = BitmapDescriptor.hueYellow;
        displayStatus = 'Signal Weak';
        print('⚠️ COMMUTER: Setting YELLOW marker for $busId (weak signal)');
      } 
      // Second Check: Good signal, check bus status
      else {
        displayStatus = status;
        if (status == 'Breakdown') {
          markerHue = BitmapDescriptor.hueRed;
          print('🎨 COMMUTER: Setting RED marker for $busId (Breakdown)');
        } else if (status == 'Delayed') {
          markerHue = BitmapDescriptor.hueOrange;
          print('🎨 COMMUTER: Setting ORANGE marker for $busId (Delayed)');
        } else if (status == 'Full Capacity') {
          markerHue = BitmapDescriptor.hueAzure;
          print('🎨 COMMUTER: Setting BLUE marker for $busId (Full Capacity)');
        } else {
          markerHue = BitmapDescriptor.hueGreen;
          print('🎨 COMMUTER: Setting GREEN marker for $busId (In Service)');
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

    // Add bus stop markers based on selected route
    if (_selectedRouteId == 'route_01') {
      markers.addAll(_getRoute01Stops());
    } else if (_selectedRouteId == 'route_02') {
      markers.addAll(_getRoute02Stops());
    }

    // Build polylines for the selected route
    final Set<Polyline> polylines = {};
    if (_selectedRouteId == 'route_01') {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route_01_path'),
          points: _route01Points,
          color: Colors.blueAccent,
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    } else if (_selectedRouteId == 'route_02') {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route_02_path'),
          points: _route02Points,
          color: Colors.deepPurpleAccent,
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
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

          // Top route selector
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.route, size: 18, color: Colors.black87),
                  const SizedBox(width: 8),
                  const Text(
                    'Route:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: DropdownButton<String>(
                      value: _selectedRouteId,
                      underline: const SizedBox(),
                      elevation: 4,
                      borderRadius: BorderRadius.circular(20),
                      dropdownColor: Colors.white.withOpacity(0.95),
                      isExpanded: true,
                      icon: Icon(
                        Icons.keyboard_arrow_down,
                        size: 18,
                        color: Colors.grey[700],
                      ),
                      items: _routes
                          .map((r) => DropdownMenuItem(
                                value: r,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _selectedRouteId == r 
                                        ? Colors.blue.withOpacity(0.1)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.directions_bus,
                                        size: 16,
                                        color: _selectedRouteId == r 
                                            ? Colors.blue 
                                            : Colors.grey[600],
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _routeNames[r] ?? r,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: _selectedRouteId == r 
                                                ? FontWeight.bold 
                                                : FontWeight.w500,
                                            color: _selectedRouteId == r 
                                                ? Colors.blue 
                                                : Colors.black87,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedRouteId = value;
                          _focusedBusId = null;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom info card
          Positioned(
            left: 8,
            right: 8,
            bottom: 76, // Moved up to avoid FAB overlap
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with bus icon and route/bus info
                  Row(
                    children: [
                      const Icon(Icons.directions_bus, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          focusedBusId == null
                              ? '${_routeNames[_selectedRouteId] ?? _selectedRouteId} | Waiting for bus...'
                              : '${_routeNames[_selectedRouteId] ?? _selectedRouteId} | Bus: $focusedBusId',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (focusedBusId != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                badgeIcon,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                badgeText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Status line with ETA
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          focusedBusId != null
                              ? 'Status: $focusedStatus • ${activeBusIds.length} bus(es) active'
                              : 'Status: Waiting for data • ${activeBusIds.length} bus(es) active',
                          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        ),
                      ),
                      // ETA Badge
                      if (focusedPos != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
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
                                _calculateETA(focusedPos),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Last update timestamp
                  if (focusedLastUpdate != null)
                    Text(
                      'Last update: $focusedLastUpdate',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  
                  // Coordinates
                  if (focusedPos != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Lat: ${focusedPos.latitude.toStringAsFixed(5)}, '
                      'Lng: ${focusedPos.longitude.toStringAsFixed(5)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _recenterOnFocusedBus,
        tooltip: 'Recenter on focused bus',
        child: const Icon(Icons.my_location),
      ),
    );
  }
}
