import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'mqtt_service.dart';

class CommuterMapPage extends StatefulWidget {
  const CommuterMapPage({super.key});

  @override
  State<CommuterMapPage> createState() => _CommuterMapPageState();
}

class _CommuterMapPageState extends State<CommuterMapPage> {
  final MqttService _mqttService = MqttService();
  StreamSubscription? _sub;

  GoogleMapController? _mapController;
  final LatLng _initialCameraPos = const LatLng(3.1390, 101.6869); // KL

  // routeId -> busId -> position
  final Map<String, Map<String, LatLng>> _routeBusPositions = {};
  final Map<String, Map<String, DateTime>> _routeLastUpdates = {};
  final Map<String, Map<String, String>> _routeBusStatus = {}; // routeId -> busId -> status

  // Demo routes (later can come from Supabase or config)
  final List<String> _routes = ['route_01', 'route_02'];
  String _selectedRouteId = 'route_01';

  String? _focusedBusId;

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


  @override
  Widget build(BuildContext context) {
    final busesOnRoute =
        _routeBusPositions[_selectedRouteId] ?? <String, LatLng>{};

    // Build markers only for the selected route
    final markers = busesOnRoute.entries.map((entry) {
      final busId = entry.key;
      final pos = entry.value;
      
      // Read the status for this bus
      final status = _routeBusStatus[_selectedRouteId]?[busId] ?? 'In Service';
      
      print('🎨 COMMUTER: Building marker for $busId - Status: "$status"');
      
      // Determine marker color based on status
      double markerHue;
      if (status == 'Breakdown') {
        markerHue = BitmapDescriptor.hueRed;
        print('🎨 COMMUTER: Setting RED marker for $busId');
      } else if (status == 'Delayed') {
        markerHue = BitmapDescriptor.hueOrange;
        print('🎨 COMMUTER: Setting ORANGE marker for $busId');
      } else if (status == 'Full Capacity') {
        markerHue = BitmapDescriptor.hueAzure;
        print('🎨 COMMUTER: Setting BLUE marker for $busId');
      } else {
        markerHue = BitmapDescriptor.hueGreen;
        print('🎨 COMMUTER: Setting GREEN marker for $busId (status was: "$status")');
      }

      return Marker(
        markerId: MarkerId('bus_${_selectedRouteId}_$busId'),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(markerHue),
        infoWindow: InfoWindow(
          title: 'Bus $busId',
          snippet: 'Status: $status',
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
    
    // Determine badge color based on status
    Color badgeColor;
    String badgeText;
    if (focusedStatus == 'Breakdown') {
      badgeColor = Colors.red;
      badgeText = 'Breakdown';
    } else if (focusedStatus == 'Delayed') {
      badgeColor = Colors.orange;
      badgeText = 'Delayed';
    } else if (focusedStatus == 'Full Capacity') {
      badgeColor = Colors.blue;
      badgeText = 'Full Capacity';
    } else {
      badgeColor = Colors.green;
      badgeText = 'Live';
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                  const Icon(Icons.route, size: 18),
                  const SizedBox(width: 8),
                  const Text('Route:', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedRouteId,
                    underline: const SizedBox(),
                    items: _routes
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedRouteId = value;
                        _focusedBusId = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          // Bottom info card
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
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
                              ? 'Route: $_selectedRouteId | Waiting for bus...'
                              : 'Route: $_selectedRouteId | Bus: $focusedBusId',
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
                                focusedStatus == 'Breakdown' 
                                    ? Icons.warning 
                                    : focusedStatus == 'Delayed'
                                        ? Icons.schedule
                                        : focusedStatus == 'Full Capacity'
                                            ? Icons.people
                                            : Icons.wifi,
                                size: 12,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
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
                  
                  // Status line
                  Text(
                    focusedBusId != null
                        ? 'Status: $focusedStatus • ${activeBusIds.length} bus(es) on $_selectedRouteId'
                        : 'Status: Waiting for data • ${activeBusIds.length} bus(es) on $_selectedRouteId',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
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
