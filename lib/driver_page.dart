import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'mqtt_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class DriverPage extends StatefulWidget {
  const DriverPage({super.key});

  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  final MqttService _mqttService = MqttService();

  // Assigned driver details (pre-assigned by admin or fetched from Supabase)
  String _assignedRouteId = 'route_01';
  String _assignedBusId = 'bus_001';

  bool _isTracking = false;
  String _status = 'Not tracking';
  Position? _lastPosition;
  
  // Bus status for commuters
  String _currentStatus = 'In Service';

  StreamSubscription<Position>? _positionSub;

  @override
  void initState() {
    super.initState();
    _initMqtt();
  }

  Future<void> _initMqtt() async {
    setState(() {
      _status = 'Connecting to MQTT...';
    });

    try {
      await _mqttService.connect();
      setState(() {
        _status = 'Connected to MQTT. Ready to track.';
      });
    } catch (e) {
      setState(() {
        _status = 'MQTT connection failed: $e';
      });
    }
  }

  Future<bool> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _status = 'Location services are disabled. Please enable GPS.';
      });
      await Geolocator.openLocationSettings();
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _status = 'Location permission denied.';
        });
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _status =
            'Location permission permanently denied. Please enable in app settings.';
      });
      return false;
    }

    // Permission granted
    return true;
  }

  Future<void> _startTracking() async {
    if (_isTracking) return;

    final routeId = _assignedRouteId;
    final busId = _assignedBusId;

    if (routeId.isEmpty || busId.isEmpty) {
      setState(() {
        _status = 'No route or bus assigned.';
      });
      return;
    }

    if (!_mqttService.isConnected) {
      await _initMqtt();
      if (!_mqttService.isConnected) {
        return;
      }
    }

    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) return;

    setState(() {
      _isTracking = true;
      _status = 'Tracking started for $busId on $routeId';
    });
    WakelockPlus.enable();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {

      print('LatLng(${position.latitude}, ${position.longitude}),');
      _lastPosition = position;

      await _mqttService.publishLocation(
        routeId: routeId,
        busId: busId,
        lat: position.latitude,
        lng: position.longitude,
        status: _currentStatus,
      );

      if (mounted) {
        setState(() {
          _status =
              'Tracking $busId ($routeId) | Lat: ${position.latitude.toStringAsFixed(5)}, '
              'Lng: ${position.longitude.toStringAsFixed(5)}';
        });
      }
    });
  }

  Future<void> _stopTracking() async {
    if (!_isTracking) return;

    await _positionSub?.cancel();
    _positionSub = null;

    setState(() {
      _isTracking = false;
      _status = 'Tracking stopped';
    });
    WakelockPlus.disable();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pos = _lastPosition;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Live Status Card
              _buildStatusCard(),
              const SizedBox(height: 24),

              // Trip Configuration Card
              _buildTripConfigCard(),
              const SizedBox(height: 24),

              // Action Button (Start or Stop based on tracking state)
              if (!_isTracking) _buildStartButton() else _buildStopButton(),
              const SizedBox(height: 24),

              // Status Update Section
              _buildStatusUpdateSection(),
              const SizedBox(height: 24),

              // Debug Info (collapsed by default)
              if (pos != null) _buildDebugInfo(pos),
            ],
          ),
        ),
      ),
    );
  }

  // Status Indicator Card
  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Pulsing indicator when tracking
            if (_isTracking)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 1500),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: 0.5 + (value * 0.5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.wifi_tethering, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Broadcasting Live',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                onEnd: () {
                  if (mounted && _isTracking) {
                    setState(() {}); // Trigger rebuild to restart animation
                  }
                },
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.schedule, color: Colors.black54, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Ready to Start',
                      style: TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Current Assignment Card (Read-Only)
  Widget _buildTripConfigCard() {
    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Assignment',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.map, color: Colors.blue, size: 32),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Route',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _assignedRouteId,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.directions_bus, color: Colors.orange, size: 32),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bus',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _assignedBusId,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Large Start Button
  Widget _buildStartButton() {
    return InkWell(
      onTap: _startTracking,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.play_arrow, color: Colors.white, size: 40),
            SizedBox(width: 12),
            Text(
              'Start Tracking',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Large Stop Button
  Widget _buildStopButton() {
    return InkWell(
      onTap: _stopTracking,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF44336), Color(0xFFE57373)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.stop, color: Colors.white, size: 40),
            SizedBox(width: 12),
            Text(
              'Stop Tracking',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Status Update Section
  Widget _buildStatusUpdateSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bus Status',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _buildStatusButton(
                  label: 'In Service',
                  color: Colors.green,
                  icon: Icons.check_circle,
                  statusValue: 'In Service',
                ),
                _buildStatusButton(
                  label: 'Delayed',
                  color: Colors.orange,
                  icon: Icons.access_time,
                  statusValue: 'Delayed',
                ),
                _buildStatusButton(
                  label: 'Full Capacity',
                  color: Colors.blue,
                  icon: Icons.people,
                  statusValue: 'Full Capacity',
                ),
                _buildStatusButton(
                  label: 'Breakdown',
                  color: Colors.red,
                  icon: Icons.warning,
                  statusValue: 'Breakdown',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusButton({
    required String label,
    required Color color,
    required IconData icon,
    required String statusValue,
  }) {
    final isSelected = _currentStatus == statusValue;

    return InkWell(
      onTap: () => _updateStatus(statusValue),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? color : Colors.grey.shade600,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? color : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() {
      _currentStatus = newStatus;
    });

    // If tracking is active, publish immediate update with new status
    if (_isTracking && _lastPosition != null) {
      await _mqttService.publishLocation(
        routeId: _assignedRouteId,
        busId: _assignedBusId,
        lat: _lastPosition!.latitude,
        lng: _lastPosition!.longitude,
        status: _currentStatus,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to: $_currentStatus'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Debug Info (always visible)
  Widget _buildDebugInfo(Position pos) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Developer Debug Info',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          _buildDebugRow('Latitude', pos.latitude.toString()),
          const SizedBox(height: 8),
          _buildDebugRow('Longitude', pos.longitude.toString()),
          const SizedBox(height: 8),
          _buildDebugRow('Accuracy', '${pos.accuracy.toStringAsFixed(2)} m'),
        ],
      ),
    );
  }

  Widget _buildDebugRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
