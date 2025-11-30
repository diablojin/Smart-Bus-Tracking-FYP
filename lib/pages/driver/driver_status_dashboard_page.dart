// driver_status_dashboard_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../mqtt_service.dart';

final supabase = Supabase.instance.client;

class DriverStatusDashboardPage extends StatefulWidget {
  const DriverStatusDashboardPage({super.key});

  @override
  State<DriverStatusDashboardPage> createState() => _DriverStatusDashboardPageState();
}

class _DriverStatusDashboardPageState extends State<DriverStatusDashboardPage> {
  final MqttService _mqttService = MqttService();

  String? _busCode;
  String? _busPlate;
  String? _routeCode;

  bool _isLoadingAssignment = true;
  bool _isTripActive = false;

  Position? _lastPosition;
  StreamSubscription<Position>? _positionSub;
  Timer? _updateTimer;

  String _status = 'Inactive';
  DateTime? _lastUpdateTime;

  @override
  void initState() {
    super.initState();
    _loadDriverAssignment();
    
    // Timer to update GPS status text every second
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _updateTimer?.cancel();
    _mqttService.dispose();
    WakelockPlus.disable(); // Disable wakelock when leaving page
    super.dispose();
  }

  Future<void> _loadDriverAssignment() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => _isLoadingAssignment = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No logged-in driver.')),
        );
        return;
      }

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
        setState(() => _isLoadingAssignment = false);
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
        _isLoadingAssignment = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading assignment: $e')),
      );
      setState(() => _isLoadingAssignment = false);
    }
  }

  Future<void> _startTrip() async {
    if (_busCode == null || _routeCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bus/route assigned to this driver.')),
      );
      return;
    }

    // Set status to "In Service" when starting trip
    setState(() {
      _status = 'In Service';
    });

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

    // Connect MQTT
    try {
      await _mqttService.connect();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('MQTT connection failed: $e')),
      );
      return;
    }

    // Enable wakelock to keep screen on
    await WakelockPlus.enable();

    // Start streaming GPS → MQTT
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // only when moved ≥ 10m
      ),
    ).listen((pos) {
      setState(() {
        _lastPosition = pos;
        _lastUpdateTime = DateTime.now();
      });

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
    await WakelockPlus.disable();

    setState(() {
      _isTripActive = false;
      _status = 'Inactive';
    });
    
    // Optionally pop back to Home after confirmation
    if (!mounted) return;
    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Trip?'),
        content: const Text('Are you sure you want to end this trip?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('End Trip'),
          ),
        ],
      ),
    );
    
    if (shouldPop == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _updateStatus(String status) async {
    setState(() => _status = status);

    // Immediately push a status update if trip is active and we know where we are
    if (_isTripActive &&
        _lastPosition != null &&
        _busCode != null &&
        _routeCode != null) {
      await _mqttService.publishBusLocation(
        routeId: _routeCode!,
        busId: _busCode!,
        lat: _lastPosition!.latitude,
        lng: _lastPosition!.longitude,
        status: _status,
      );
    }
  }

  String _getGpsStatusText() {
    if (!_isTripActive) {
      return 'GPS inactive';
    }
    if (_lastUpdateTime == null) {
      return 'GPS connecting...';
    }
    final seconds = DateTime.now().difference(_lastUpdateTime!).inSeconds;
    return 'GPS active (last update: ${seconds}s ago)';
  }

  Color _getStatusColor() {
    switch (_status) {
      case 'In Service':
        return Colors.green;
      case 'Delayed':
        return Colors.orange;
      case 'Full Capacity':
        return Colors.blue;
      case 'Breakdown':
        return Colors.red;
      case 'Inactive':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    if (_isLoadingAssignment) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Driver Tracking'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Tracking'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bus & Route Info Card
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.directions_bus, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        'Bus: ${_busCode ?? '-'}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Plate: ${_busPlate ?? 'N/A'}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Route: ${_routeCode ?? '-'}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // GPS Status Row
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _isTripActive && _lastUpdateTime != null
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getGpsStatusText(),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Current Status Badge
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: _getStatusColor().withOpacity(0.15),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _getStatusColor(),
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Current Status: ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      _status,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _getStatusColor(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Status Buttons Grid (2x2) - Only show when trip is active
            if (_isTripActive) ...[
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.1,
                children: [
                  _StatusButton(
                    title: 'In Service',
                    subtitle: 'Bus operating normally',
                    icon: Icons.check_circle,
                    color: Colors.green,
                    isSelected: _status == 'In Service',
                    onTap: () => _updateStatus('In Service'),
                  ),
                  _StatusButton(
                    title: 'Delayed',
                    subtitle: 'Traffic or schedule delay',
                    icon: Icons.access_time_filled,
                    color: Colors.orange,
                    isSelected: _status == 'Delayed',
                    onTap: () => _updateStatus('Delayed'),
                  ),
                  _StatusButton(
                    title: 'Full Capacity',
                    subtitle: 'No more passengers allowed',
                    icon: Icons.groups_rounded,
                    color: Colors.blue,
                    isSelected: _status == 'Full Capacity',
                    onTap: () => _updateStatus('Full Capacity'),
                  ),
                  _StatusButton(
                    title: 'Breakdown',
                    subtitle: 'Unable to continue service',
                    icon: Icons.warning_rounded,
                    color: Colors.red,
                    isSelected: _status == 'Breakdown',
                    onTap: () => _updateStatus('Breakdown'),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ] else
              const SizedBox(height: 32),

            // Trip Control Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: (_busCode == null || _routeCode == null)
                    ? null
                    : (_isTripActive ? _stopTrip : _startTrip),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isTripActive ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _isTripActive ? 'End Trip' : 'Start Trip',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// Status Button Widget
class _StatusButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatusButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white70 : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

