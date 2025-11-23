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
    'route_01': 'Jln Dataran → Jln Tun Sambanthan',
    'route_02': 'KLCC → Pavilion KL',
  };

  String? _focusedBusId;

  // Destination point (KL Sentral) for ETA calculation
  final LatLng _destination = const LatLng(3.1335, 101.6868);

  // Route 01 polyline coordinates (High-resolution GPS tracking - 9 points)
  final List<LatLng> _route01Points = const [
    LatLng(3.14587, 101.69319),      // Start point (northernmost)
    LatLng(3.1448103, 101.6934007),  
    LatLng(3.1437189, 101.6931108),  
    LatLng(3.1426396, 101.6929596),  
    LatLng(3.1415967, 101.6931696),  
    LatLng(3.1407582, 101.6939083),  
    LatLng(3.1406888, 101.6943517),  
    LatLng(3.1406393, 101.6945889),  
    LatLng(3.14064, 101.69458),      // End point (southernmost)
  ];

  // Route 02 polyline coordinates (KLCC to Pavilion)
  final List<LatLng> _route02Points = const [
    LatLng(3.1579, 101.7116), // KLCC
    LatLng(3.1550, 101.7130),
    LatLng(3.1520, 101.7140),
    LatLng(3.1485, 101.7145), // Pavilion
  ];

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
