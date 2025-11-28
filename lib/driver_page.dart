// driver_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mqtt_service.dart';

final supabase = Supabase.instance.client;

class DriverPage extends StatefulWidget {
  const DriverPage({super.key});

  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  final MqttService _mqttService = MqttService();

  String? _busCode;
  String? _busPlate;
  String? _routeCode;

  bool _isLoadingAssignment = true;
  bool _isTripActive = false;

  Position? _lastPosition;
  StreamSubscription<Position>? _positionSub;

  String _status = 'In Service';

  @override
  void initState() {
    super.initState();
    _loadDriverAssignment();
  }

  // ---------------------------------------------------------------------------
  // 1. Get bus code, plate number, and route code for this driver from Supabase
  // ---------------------------------------------------------------------------
  Future<void> _loadDriverAssignment() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => _isLoadingAssignment = false);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No logged-in driver.')));
        return;
      }

      // drivers.bus_id -> buses.id
      // buses.route_id -> routes.id
      //
      // We pull:
      // - buses.code      (bus code shown in UI + MQTT busId)
      // - buses.plate_no  (for display)
      // - routes.code     (route code, e.g. 801)
      final data = await supabase
          .from('drivers')
          .select('bus_id, buses(code, plate_no, routes(code))')
          .eq('auth_user_id', user.id)
          .maybeSingle();

      if (data == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No bus assignment found for this driver.'),
          ),
        );
        return;
      }

      final busRow = data['buses'] as Map<String, dynamic>?;
      final busCode = busRow?['code'] as String?;
      final busPlate = busRow?['plate_no'] as String?;

      final routesRow = busRow?['routes'] as Map<String, dynamic>?;
      final routeCode = routesRow?['code'] as String?;

      setState(() {
        _busCode = busCode;
        _busPlate = busPlate;
        _routeCode = routeCode;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading assignment: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoadingAssignment = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 2. Start / stop trip (GPS + MQTT)
  // ---------------------------------------------------------------------------

  Future<void> _toggleTrip() async {
    if (_isTripActive) {
      await _stopTrip();
    } else {
      await _startTrip();
    }
  }

  Future<void> _startTrip() async {
    if (_busCode == null || _routeCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bus/route assigned to this driver.')),
      );
      return;
    }

    // Location permission
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      final newPerm = await Geolocator.requestPermission();
      if (newPerm == LocationPermission.denied ||
          newPerm == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required.')),
        );
        return;
      }
    }

    // Turn on GPS service if off
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable location services (GPS).')),
      );
      return;
    }

    // Connect MQTT once
    try {
      await _mqttService.connect();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('MQTT connection failed: $e')));
      return;
    }

    // Start streaming GPS → MQTT
    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10, // only when moved ≥ 10m
          ),
        ).listen((pos) {
          setState(() => _lastPosition = pos);

          _mqttService.publishBusLocation(
            routeId: _routeCode!,
            busId: _busCode!,
            lat: pos.latitude,
            lng: pos.longitude,
            status: _status,
          );
        });

    setState(() => _isTripActive = true);
  }

  Future<void> _stopTrip() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _mqttService.disconnect();

    setState(() => _isTripActive = false);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mqttService.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Widget _buildStatusTile(String label, IconData icon, Color color) {
    final isSelected = _status == label;
    return InkWell(
      onTap: () async {
        setState(() {
          _status = label;
        });

        // Immediately push a status update if trip is active and we know where we are
        if (_isTripActive &&
            _lastPosition != null &&
            _busCode != null &&
            _routeCode != null) {
          await _mqttService.publishBusLocation(
            routeId: _routeCode!, // e.g. "801"
            busId: _busCode!, // e.g. "801-B"
            lat: _lastPosition!.latitude,
            lng: _lastPosition!.longitude,
            status: _status, // <- the new status
          );
        }
      },

      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingAssignment) {
      return Scaffold(
        appBar: AppBar(title: const Text('Driver Tracking')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Driver Tracking')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Bus assignment card
            Card(
              child: ListTile(
                leading: const Icon(Icons.directions_bus),
                title: Text('Bus: ${_busCode ?? '-'}'),
                subtitle: Text(
                  _busPlate != null ? 'Plate: $_busPlate' : 'Not assigned',
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Route assignment card
            Card(
              child: ListTile(
                leading: const Icon(Icons.route),
                title: Text('Route: ${_routeCode ?? '-'}'),
              ),
            ),

            const SizedBox(height: 16),

            // Status selector grid
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.2,
              children: [
                _buildStatusTile(
                  'In Service',
                  Icons.check_circle,
                  Colors.green,
                ),
                _buildStatusTile('Delayed', Icons.access_time, Colors.orange),
                _buildStatusTile('Breakdown', Icons.warning, Colors.red),
                _buildStatusTile('Full Capacity', Icons.people, Colors.blue),
              ],
            ),

            const SizedBox(height: 16),

            // Last GPS info
            if (_lastPosition != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.gps_fixed),
                  title: const Text('Last position'),
                  subtitle: Text(
                    'Lat: ${_lastPosition!.latitude.toStringAsFixed(6)}, '
                    'Lng: ${_lastPosition!.longitude.toStringAsFixed(6)}',
                  ),
                ),
              )
            else
              Card(
                child: ListTile(
                  leading: const Icon(Icons.gps_not_fixed),
                  title: const Text('No GPS data yet'),
                  subtitle: const Text(
                    'Tap "Start Trip" to begin sending location.',
                  ),
                ),
              ),

            const Spacer(),

            // Start / Stop button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(
                  _isTripActive
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_fill,
                ),
                label: Text(_isTripActive ? 'Stop Trip' : 'Start Trip'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  backgroundColor: _isTripActive ? Colors.red : Colors.green,
                ),
                onPressed: (_busCode == null || _routeCode == null)
                    ? null
                    : _toggleTrip,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
