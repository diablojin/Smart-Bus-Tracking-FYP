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

  // Demo routes (later can come from Supabase or config)
  final List<String> _routes = ['route_01', 'route_02'];
  String _selectedRouteId = 'route_01';

  String? _focusedBusId;

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

        setState(() {
          _routeBusPositions.putIfAbsent(routeId, () => {});
          _routeLastUpdates.putIfAbsent(routeId, () => {});

          _routeBusPositions[routeId]![busId] = pos;
          _routeLastUpdates[routeId]![busId] = location.timestamp;

          _focusedBusId ??= busId; // first bus on any route
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

      return Marker(
        markerId: MarkerId('bus_${_selectedRouteId}_$busId'),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Bus $busId',
          snippet: 'Route: $_selectedRouteId',
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

    final activeBusIds = busesOnRoute.keys.toList();

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
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.wifi, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Live',
                                style: TextStyle(
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
                    'Status: Live tracking: ${activeBusIds.length} bus(es) on $_selectedRouteId',
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
