import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/route_search_service.dart';
import '../models/stop_model.dart';
import '../models/route_stop_model.dart';
import '../commuter_map_page.dart';
import '../config/supabase_client.dart';
import 'commuter/report_page.dart';

/// Reusable widget containing the Stop-to-Stop search form and results.
/// Uses the new route_stops junction table schema for proper journey planning.
class StopToStopSearchBody extends StatefulWidget {
  const StopToStopSearchBody({super.key});

  @override
  State<StopToStopSearchBody> createState() => _StopToStopSearchBodyState();
}

class _StopToStopSearchBodyState extends State<StopToStopSearchBody> {
  RouteDataBundle? _bundle;
  bool _isLoadingBundle = true;
  bool _isSearching = false;
  bool _detectingLocation = false;

  // Unique stops by name (first occurrence kept)
  List<StopModel> _uniqueStops = [];
  
  String? _fromStopName;
  String? _toStopName;
  List<RouteSearchResult> _results = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRouteDataBundle();
  }

  Future<void> _loadRouteDataBundle() async {
    try {
      if (!mounted) return;
      setState(() {
        _isLoadingBundle = true;
        _errorMessage = null;
      });

      final bundle = await RouteSearchService.loadRouteDataBundle();

      if (!mounted) return;
      
      // Build unique stops list keyed by name (keep first occurrence)
      final Map<String, StopModel> uniqueStopsMap = {};
      for (final stop in bundle.stops) {
        if (!uniqueStopsMap.containsKey(stop.name)) {
          uniqueStopsMap[stop.name] = stop;
        }
      }
      final uniqueStops = uniqueStopsMap.values.toList();
      // Sort alphabetically by name for better UX
      uniqueStops.sort((a, b) => a.name.compareTo(b.name));

      setState(() {
        _bundle = bundle;
        _uniqueStops = uniqueStops;
        _isLoadingBundle = false;
      });
    } catch (e, stackTrace) {
      print('❌ Error in _loadRouteDataBundle: $e');
      print('Stack trace: $stackTrace');
      if (!mounted) return;
      setState(() {
        _isLoadingBundle = false;
        // Show a more user-friendly error message
        final errorMsg = e.toString();
        if (errorMsg.contains('Null') && errorMsg.contains('String')) {
          _errorMessage = 'Database error: Some route data is missing. Please check your Supabase tables have all required fields (route_code, route_name, stop_code, stop_name).';
        } else {
          _errorMessage = 'Failed to load route data: ${e.toString()}';
        }
      });
    }
  }

  void _searchRoutes() {
    if (_fromStopName == null || _toStopName == null || _bundle == null) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Please select both From and To stops';
      });
      return;
    }

    if (_fromStopName == _toStopName) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'From and To stops must be different';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final matches = RouteSearchService.searchRoutes(
        bundle: _bundle!,
        fromStopName: _fromStopName!,
        toStopName: _toStopName!,
      );

      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _results = matches;

        if (matches.isEmpty) {
          _errorMessage = 'No direct routes found between these stops.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _errorMessage = 'Error searching routes: $e';
      });
    }
  }

  /// Get current GPS position with permission handling
  Future<Position?> _getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Location request timed out');
        },
      );
    } catch (e) {
      return null;
    }
  }

  /// Find the nearest stop from current position (by name)
  String? _findNearestStopName(Position position) {
    if (_bundle == null || _bundle!.stops.isEmpty) return null;

    try {
      StopModel? nearest;
      double? nearestDistance;

      for (final stop in _bundle!.stops) {
        if (stop.latitude == null || stop.longitude == null) continue;

        try {
          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            stop.latitude!,
            stop.longitude!,
          );

          if (nearest == null || distance < nearestDistance!) {
            nearest = stop;
            nearestDistance = distance;
          }
        } catch (e) {
          continue;
        }
      }

      return nearest?.name;
    } catch (e) {
      return null;
    }
  }

  /// Use current location to auto-select the From stop
  Future<void> _useCurrentLocationAsFrom() async {
    if (!mounted) return;
    setState(() {
      _detectingLocation = true;
      _errorMessage = null;
    });

    try {
      final position = await _getCurrentPosition();
      if (position == null) {
        if (!mounted) return;
        setState(() {
          _detectingLocation = false;
          _errorMessage = 'Unable to get current location. Please enable GPS or check location permissions.';
        });
        return;
      }

      final nearestStopName = _findNearestStopName(position);
      if (nearestStopName == null) {
        if (!mounted) return;
        setState(() {
          _detectingLocation = false;
          _errorMessage = 'No stops available in the system.';
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _fromStopName = nearestStopName;
        _detectingLocation = false;
        _results = [];
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _detectingLocation = false;
        _errorMessage = 'Location request timed out.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _detectingLocation = false;
        _errorMessage = 'Failed to detect location: ${e.toString()}';
      });
    }
  }

  Future<void> _navigateToReport(RouteSearchResult result) async {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportIssuePage(
          routeId: result.route.id.toString(),
          routeName: result.route.name,
          busId: null, // Bus is not selected at this point
          busName: null,
        ),
      ),
    );
  }

  Future<void> _navigateToMap(RouteSearchResult result) async {
    try {
      // Fetch route info from Supabase to create RouteInfo
      final routeResponse = await supabase
          .from('routes')
          .select()
          .eq('id', result.route.id)
          .maybeSingle();

      if (routeResponse == null) {
        // Fallback: navigate with just route code
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CommuterMapPage(
              initialRouteId: result.route.code,
            ),
          ),
        );
        return;
      }

      final routeInfo = RouteInfo.fromJson(Map<String, dynamic>.from(routeResponse));

      // Fetch first active bus for this route
      final busesResponse = await supabase
          .from('buses')
          .select()
          .eq('route_id', result.route.id)
          .eq('is_active', true)
          .limit(1);

      BusInfo bus;
      if (busesResponse.isNotEmpty) {
        bus = BusInfo.fromJson(Map<String, dynamic>.from(busesResponse[0] as Map));
      } else {
        // Create a default bus if none found (will be updated when MQTT data arrives)
        bus = BusInfo(
          id: 0,
          routeId: result.route.id,
          plateNo: 'N/A',
          code: '${result.route.code}-A',
          isActive: true,
        );
      }

      // Convert StopModel to Stop
      // We need to find the actual stop records from Supabase that match the names and route
      final fromStopResponse = await supabase
          .from('stops')
          .select()
          .eq('stop_name', result.fromStop.name)
          .limit(1)
          .maybeSingle();

      final toStopResponse = await supabase
          .from('stops')
          .select()
          .eq('stop_name', result.toStop.name)
          .limit(1)
          .maybeSingle();

      // Get route_stops to find sequence_index for these stops on this route
      final routeStopsResponse = await supabase
          .from('route_stops')
          .select()
          .eq('route_id', result.route.id);

      final routeStops = (routeStopsResponse as List)
          .map((rs) => RouteStopModel.fromMap(rs as Map<String, dynamic>))
          .toList();

      // Find sequence_index for from and to stops
      int? fromSeq;
      int? toSeq;
      int? fromStopId;
      int? toStopId;

      for (final rs in routeStops) {
        final stop = _bundle?.stopsById[rs.stopId];
        if (stop != null) {
          if (stop.name == result.fromStop.name) {
            fromSeq = rs.seq;
            fromStopId = rs.stopId;
          }
          if (stop.name == result.toStop.name) {
            toSeq = rs.seq;
            toStopId = rs.stopId;
          }
        }
      }

      // Create Stop objects (legacy format)
      final fromStopData = fromStopResponse != null ? Map<String, dynamic>.from(fromStopResponse) : null;
      final toStopData = toStopResponse != null ? Map<String, dynamic>.from(toStopResponse) : null;

      final fromStop = Stop(
        id: fromStopId ?? result.fromStop.id,
        routeId: result.route.id,
        name: result.fromStop.name,
        latitude: result.fromStop.latitude ?? (fromStopData != null ? (fromStopData['latitude'] as num?)?.toDouble() ?? 0.0 : 0.0),
        longitude: result.fromStop.longitude ?? (fromStopData != null ? (fromStopData['longitude'] as num?)?.toDouble() ?? 0.0 : 0.0),
        sequenceIndex: fromSeq ?? 0,
      );

      final toStop = Stop(
        id: toStopId ?? result.toStop.id,
        routeId: result.route.id,
        name: result.toStop.name,
        latitude: result.toStop.latitude ?? (toStopData != null ? (toStopData['latitude'] as num?)?.toDouble() ?? 0.0 : 0.0),
        longitude: result.toStop.longitude ?? (toStopData != null ? (toStopData['longitude'] as num?)?.toDouble() ?? 0.0 : 0.0),
        sequenceIndex: toSeq ?? 0,
      );

      // Create TripSelection with all required data
      final tripSelection = TripSelection(
        route: routeInfo,
        fromStop: fromStop,
        toStop: toStop,
        bus: bus,
      );

      // Navigate with TripSelection to enable live tracking and bottom card
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CommuterMapPage(
            tripSelection: tripSelection,
            // Also pass route code as fallback
            initialRouteId: result.route.code,
            // Pass override stops for header display
            overrideFromStop: result.fromStop,
            overrideToStop: result.toStop,
          ),
        ),
      );
    } catch (e) {
      print('❌ Error creating trip selection: $e');
      // Fallback: navigate with just route code
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CommuterMapPage(
            initialRouteId: result.route.code,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoadingBundle) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading route data...'),
          ],
        ),
      );
    }

    if (_bundle == null || _uniqueStops.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'No route data available',
              style: textTheme.bodyLarge?.copyWith(color: colorScheme.error),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadRouteDataBundle,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Select your starting stop and destination to find routes',
                    style: textTheme.bodyMedium,
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
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              InkWell(
                onTap: _detectingLocation ? null : _useCurrentLocationAsFrom,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_detectingLocation)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        )
                      else
                        Icon(
                          Icons.my_location,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                      const SizedBox(width: 4),
                      Text(
                        _detectingLocation ? 'Detecting...' : 'Use Current Location',
                        style: textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _fromStopName,
            hint: Text('Select starting stop', style: textTheme.bodyMedium),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.trip_origin),
              filled: true,
              fillColor: colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            isExpanded: true,
            items: _uniqueStops.map((stop) {
              return DropdownMenuItem<String>(
                value: stop.name,
                child: Text(
                  stop.name,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (String? value) {
              setState(() {
                _fromStopName = value;
                _errorMessage = null;
                _results = [];
              });
            },
          ),
          const SizedBox(height: 20),

          // To Stop Dropdown
          Text(
            'To Stop',
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _toStopName,
            hint: Text('Select destination stop', style: textTheme.bodyMedium),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.location_on),
              filled: true,
              fillColor: colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            isExpanded: true,
            items: _uniqueStops.map((stop) {
              return DropdownMenuItem<String>(
                value: stop.name,
                child: Text(
                  stop.name,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (String? value) {
              setState(() {
                _toStopName = value;
                _errorMessage = null;
                _results = [];
              });
            },
          ),
          const SizedBox(height: 24),

          // Search Button
          ElevatedButton(
            onPressed: _isSearching ? null : _searchRoutes,
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
                    'Search Routes',
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
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.error.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: colorScheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Search Results
          if (_results.isNotEmpty) ...[
            Text(
              'Found ${_results.length} route(s)',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ..._results.map((result) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: RouteResultCard(
                    result: result,
                    onTap: () => _navigateToMap(result),
                    onReportIssue: () => _navigateToReport(result),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

/// Card widget for displaying a route search result.
/// Theme-aware and supports both light and dark modes.
class RouteResultCard extends StatelessWidget {
  final RouteSearchResult result;
  final VoidCallback onTap;
  final VoidCallback? onReportIssue;

  const RouteResultCard({
    super.key,
    required this.result,
    required this.onTap,
    this.onReportIssue,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Get intermediate stops (excluding from and to)
    final intermediateOnly = result.intermediateStops.length > 2
        ? result.intermediateStops.sublist(1, result.intermediateStops.length - 1)
        : <StopModel>[];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Route Header: Code chip + Main title (From → To)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    result.route.code,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${result.fromStop.name} → ${result.toStop.name}',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Route name as subtitle (muted)
            Text(
              result.route.name,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            // Intermediate stops (if any)
            if (intermediateOnly.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Via: ${intermediateOnly.map((s) => s.name).join(', ')}',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 16),
            // Action buttons row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Report Issue button
                if (onReportIssue != null)
                  TextButton.icon(
                    onPressed: onReportIssue,
                    icon: Icon(
                      Icons.report_problem,
                      size: 16,
                      color: colorScheme.error,
                    ),
                    label: Text(
                      'Report Issue',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                // Tap to view on map
                TextButton.icon(
                  onPressed: onTap,
                  icon: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  label: Text(
                    'View on map',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
