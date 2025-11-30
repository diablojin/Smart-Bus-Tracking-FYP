import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/route_search_service.dart';
import '../commuter_map_page.dart';

/// Reusable widget containing the Stop-to-Stop search form and results
/// Can be used in Routes tab or as a standalone page
class StopToStopSearchBody extends StatefulWidget {
  const StopToStopSearchBody({super.key});

  @override
  State<StopToStopSearchBody> createState() => _StopToStopSearchBodyState();
}

class _StopToStopSearchBodyState extends State<StopToStopSearchBody> {
  List<Stop> _allStops = [];
  bool _isLoadingStops = true;
  bool _isSearching = false;
  bool _detectingLocation = false;
  
  Stop? _selectedFromStop;
  Stop? _selectedToStop;
  
  RouteSearchResult? _searchResult;
  String? _errorMessage;
  
  // Selection state for tracking
  BusInfo? _selectedBusForTracking;
  RouteSearchResult? _selectedRouteResult; // Store the route result for the selected bus

  @override
  void initState() {
    super.initState();
    _loadStops();
  }

  Future<void> _loadStops() async {
    try {
      setState(() {
        _isLoadingStops = true;
        _errorMessage = null;
      });
      
      final stops = await RouteSearchService.getAllStops();
      
      setState(() {
        _allStops = stops;
        _isLoadingStops = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingStops = false;
        _errorMessage = 'Failed to load stops: $e';
      });
    }
  }

  Future<void> _searchRoute() async {
    if (_selectedFromStop == null || _selectedToStop == null) {
      setState(() {
        _errorMessage = 'Please select both From and To stops';
      });
      return;
    }

    if (_selectedFromStop!.id == _selectedToStop!.id) {
      setState(() {
        _errorMessage = 'From and To stops must be different';
      });
      return;
    }

    try {
      setState(() {
        _isSearching = true;
        _errorMessage = null;
        _searchResult = null;
      });

      final result = await RouteSearchService.searchRoute(
        fromStopId: _selectedFromStop!.id,
        toStopId: _selectedToStop!.id,
      );

      setState(() {
        _isSearching = false;
        if (result == null) {
          _errorMessage = 'No direct route found between these stops. '
              'Please check if they are on the same route.';
          _selectedBusForTracking = null; // Clear selection on new search
          _selectedRouteResult = null;
        } else {
          _searchResult = result;
          _selectedBusForTracking = null; // Clear selection on new search
          _selectedRouteResult = null;
        }
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _errorMessage = 'Error searching route: $e';
      });
    }
  }

  /// Get current GPS position with permission handling
  Future<Position?> _getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('⚠️ Location services are disabled');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('⚠️ Location permission denied by user');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('⚠️ Location permission permanently denied');
        return null;
      }

      // Add timeout to prevent hanging on emulator
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, // Changed from high to medium for emulator compatibility
        timeLimit: const Duration(seconds: 10), // 10 second timeout
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('⚠️ Location request timed out (emulator may not have GPS)');
          throw TimeoutException('Location request timed out');
        },
      );
    } catch (e) {
      print('❌ Error getting current position: $e');
      return null;
    }
  }

  /// Find the nearest stop from current position
  Stop? _findNearestStop(Position position) {
    if (_allStops.isEmpty) return null;

    try {
      Stop? nearest;
      double? nearestDistance;

      for (final stop in _allStops) {
        try {
          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            stop.latitude,
            stop.longitude,
          );

          if (nearest == null || distance < nearestDistance!) {
            nearest = stop;
            nearestDistance = distance;
          }
        } catch (e) {
          print('⚠️ Error calculating distance to stop ${stop.name}: $e');
          continue; // Skip this stop and continue with next
        }
      }

      return nearest;
    } catch (e) {
      print('❌ Error in _findNearestStop: $e');
      return null;
    }
  }

  /// Use current location to auto-select the From stop
  Future<void> _useCurrentLocationAsFrom() async {
    setState(() {
      _detectingLocation = true;
      _errorMessage = null;
    });

    try {
      final position = await _getCurrentPosition();
      if (position == null) {
        setState(() {
          _detectingLocation = false;
          _errorMessage = 'Unable to get current location. '
              'Please enable GPS in emulator settings or check location permissions.';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Tip: In Android Emulator, go to Settings > Location to enable GPS',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      final nearest = _findNearestStop(position);
      if (nearest == null) {
        setState(() {
          _detectingLocation = false;
          _errorMessage = 'No stops available in the system.';
        });
        return;
      }

      // Calculate distance in km for display
      final distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        nearest.latitude,
        nearest.longitude,
      );
      final distanceInKm = (distanceInMeters / 1000).toStringAsFixed(2);

      setState(() {
        _selectedFromStop = nearest;
        _detectingLocation = false;
        _searchResult = null; // Clear previous results
      });

      // Show confirmation to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Nearest stop: ${nearest.name} (${distanceInKm} km away)',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on TimeoutException {
      setState(() {
        _detectingLocation = false;
        _errorMessage = 'Location request timed out. '
            'Emulator may not have GPS enabled. Please enable location in emulator settings.';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location timeout. Enable GPS in Emulator: Settings > Location',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('❌ Error in _useCurrentLocationAsFrom: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _detectingLocation = false;
        _errorMessage = 'Failed to detect location: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final labelColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white70 : Colors.grey.shade600;

    return _isLoadingStops
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading stops...'),
              ],
            ),
          )
        : _allStops.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No stops available',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loadStops,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Instructions
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Select your starting stop and destination to find routes',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // From Stop Label with "Use Current Location" button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'From Stop',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: labelColor,
                          ),
                        ),
                        InkWell(
                          onTap: _detectingLocation ? null : _useCurrentLocationAsFrom,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9), // soft green background
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_detectingLocation)
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF2E7D32),
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.my_location,
                                    size: 16,
                                    color: Color(0xFF2E7D32),
                                  ),
                                const SizedBox(width: 4),
                                Text(
                                  _detectingLocation ? 'Detecting...' : 'Use Current Location',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF2E7D32),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<Stop>(
                      value: _selectedFromStop,
                      hint: Text(
                        'Select starting stop',
                        style: TextStyle(color: hintColor),
                      ),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.trip_origin),
                        filled: true,
                        fillColor: cardColor,
                        hintText: 'Select starting stop',
                        hintStyle: TextStyle(color: hintColor),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade600),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      isExpanded: true,
                      items: _allStops.map((stop) {
                        return DropdownMenuItem<Stop>(
                          value: stop,
                          child: Text(
                            stop.routeCode != null && stop.routeCode!.isNotEmpty
                                ? '${stop.name} (${stop.routeCode})'
                                : stop.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (Stop? value) {
                        setState(() {
                          _selectedFromStop = value;
                          _errorMessage = null;
                          _searchResult = null;
                          _selectedBusForTracking = null; // Clear selection when route changes
                          _selectedRouteResult = null;
                        });
                      },
                    ),
                    const SizedBox(height: 20),

                    // To Stop Dropdown
                    Text(
                      'To Stop',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<Stop>(
                      value: _selectedToStop,
                      hint: Text(
                        'Select destination stop',
                        style: TextStyle(color: hintColor),
                      ),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.location_on),
                        filled: true,
                        fillColor: cardColor,
                        hintText: 'Select destination stop',
                        hintStyle: TextStyle(color: hintColor),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade600),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      isExpanded: true,
                      items: _allStops.map((stop) {
                        return DropdownMenuItem<Stop>(
                          value: stop,
                          child: Text(
                            stop.routeCode != null && stop.routeCode!.isNotEmpty
                                ? '${stop.name} (${stop.routeCode})'
                                : stop.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (Stop? value) {
                        setState(() {
                          _selectedToStop = value;
                          _errorMessage = null;
                          _searchResult = null;
                          _selectedBusForTracking = null; // Clear selection when route changes
                          _selectedRouteResult = null;
                        });
                      },
                    ),
                    const SizedBox(height: 24),

                    // Search Button
                    ElevatedButton(
                      onPressed: _isSearching ? null : _searchRoute,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSearching
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Search Route',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(height: 24),

                    // Error Message
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Search Results
                    if (_searchResult != null) ...[
                      _buildSearchResult(_searchResult!),
                    ],
                    
                    // Start Tracking Button (only shown when search result exists and bus is selected)
                    if (_searchResult != null && _selectedBusForTracking != null && _selectedRouteResult != null) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            // Create trip selection
                            final trip = TripSelection(
                              route: _selectedRouteResult!.route,
                              fromStop: _selectedRouteResult!.fromStop,
                              toStop: _selectedRouteResult!.toStop,
                              bus: _selectedBusForTracking!,
                            );

                            // Navigate to commuter map with trip selection
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CommuterMapPage(tripSelection: trip),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Start Tracking',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24), // Extra padding at bottom
                    ],
                  ],
                ),
              );
  }

  Widget _buildSearchResult(RouteSearchResult result) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white70 : Colors.grey.shade700;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Route Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    result.route.code,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    result.route.name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // From/To Stop Info
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.trip_origin, size: 16, color: textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            'From',
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.fromStop.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward,
                  color: Theme.of(context).primaryColor,
                  size: 24,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'To',
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.location_on, size: 16, color: textSecondary),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.toStop.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Fare
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.payment, size: 20, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Fare: RM ${result.route.baseFare.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Buses and Schedules
            if (result.busesWithSchedules.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No active buses or schedules available for this route.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                'Available Buses',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...result.busesWithSchedules.map((busWithSchedules) {
                return _buildBusScheduleCard(result, busWithSchedules);
              }).toList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBusScheduleCard(RouteSearchResult result, BusWithSchedules busWithSchedules) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white70 : Colors.grey.shade700;

    // Get departure times as a comma-separated string
    final departureTimes = busWithSchedules.schedules
        .map((schedule) => schedule.departureTime)
        .join(', ');
    
    // Check if this bus is selected
    final isSelected = _selectedBusForTracking?.id == busWithSchedules.bus.id;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedBusForTracking = busWithSchedules.bus;
          _selectedRouteResult = result;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected 
              ? Theme.of(context).primaryColor.withOpacity(0.1)
              : cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? Theme.of(context).primaryColor
                : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.directions_bus,
                  color: Theme.of(context).primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bus ${busWithSchedules.bus.code}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        busWithSchedules.bus.plateNo,
                        style: TextStyle(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: textSecondary,
                  size: 24,
                ),
              ],
            ),
            if (busWithSchedules.schedules.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.access_time, size: 16, color: textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Departure Times',
                          style: TextStyle(
                            fontSize: 12,
                            color: textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          departureTimes.isNotEmpty
                              ? departureTimes
                              : 'No schedules available',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'No schedules available',
                style: TextStyle(
                  fontSize: 12,
                  color: textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (isSelected) ...[
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Theme.of(context).primaryColor,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Selected',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Tap to select',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

