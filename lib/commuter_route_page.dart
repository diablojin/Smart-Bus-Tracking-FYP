import 'package:flutter/material.dart';

import 'commuter_map_page.dart';
import 'route_data_model.dart';
import 'pages/route_search_page.dart';

class CommuterRoutesPage extends StatefulWidget {
  const CommuterRoutesPage({super.key});

  @override
  State<CommuterRoutesPage> createState() => _CommuterRoutesPageState();
}

class _CommuterRoutesPageState extends State<CommuterRoutesPage> {
  final TextEditingController _searchController = TextEditingController();
  List<BusRouteModel> _filteredRoutes = allRoutes; // Start with all routes

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Filter routes based on search query
  /// Searches: Route Name, Origin, Destination, and Major Stops
  void _filterRoutes(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredRoutes = allRoutes;
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredRoutes = allRoutes.where((route) {
          // Search in name, origin, destination
          final matchesBasic = route.name.toLowerCase().contains(lowerQuery) ||
              route.origin.toLowerCase().contains(lowerQuery) ||
              route.destination.toLowerCase().contains(lowerQuery) ||
              route.label.toLowerCase().contains(lowerQuery);
          
          // Search in major stops
          final matchesStops = route.stops.any(
            (stop) => stop.toLowerCase().contains(lowerQuery),
          );
          
          return matchesBasic || matchesStops;
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan Your Trip'),
      ),
      body: Column(
        children: [
          // Stop-to-Stop Search Button
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RouteSearchPage(),
                  ),
                );
              },
              icon: const Icon(Icons.location_searching),
              label: const Text('Stop-to-Stop Search'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(double.infinity, 0),
              ),
            ),
          ),
          
          // Search Bar Section
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: _searchController,
              onChanged: _filterRoutes,
              decoration: InputDecoration(
                hintText: 'Where to?',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterRoutes('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
          
          // Results List (Scrollable)
          Expanded(
            child: _filteredRoutes.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    itemCount: _filteredRoutes.length,
                    itemBuilder: (context, index) {
                      final route = _filteredRoutes[index];
                      return _buildRouteTicketCard(context, route);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Empty state when no routes match
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No routes found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try searching for a different location',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// Build a "Ticket" style card for each route
  Widget _buildRouteTicketCard(BuildContext context, BusRouteModel route) {
    // Determine if fare is free
    final isFree = route.fare.toLowerCase() == 'free';
    final fareColor = isFree ? Colors.green : Theme.of(context).primaryColor;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () {
          // Navigate to map with the selected route
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CommuterMapPage(initialRouteId: route.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Route Label and Name
              Row(
                children: [
                  // Route Label Badge
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
                      route.label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Route Name
                  Expanded(
                    child: Text(
                      route.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Middle Row: Origin → Destination Flow
              Row(
                children: [
                  // Origin
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.trip_origin,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          route.origin,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  
                  // Arrow
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward,
                      size: 20,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  
                  // Destination
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          route.destination,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Bottom Row: Fare and Operating Hours
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Fare (Bold/Green or Primary)
                  Row(
                    children: [
                      Icon(
                        isFree ? Icons.star : Icons.payment,
                        size: 18,
                        color: fareColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        route.fare,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: fareColor,
                        ),
                      ),
                    ],
                  ),
                  
                  // Operating Hours (Grey)
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        route.operatingHours,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

