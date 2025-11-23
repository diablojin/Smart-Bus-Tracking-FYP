import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_page.dart';
import 'commuter_map_page.dart';

final supabase = Supabase.instance.client;

class CommuterHomePage extends StatefulWidget {
  const CommuterHomePage({super.key});

  @override
  State<CommuterHomePage> createState() => _CommuterHomePageState();
}

class _CommuterHomePageState extends State<CommuterHomePage> {
  int _selectedIndex = 0;

  // Define the pages for each tab
  List<Widget> get _pages => [
    _HomeTab(onSwitchToMap: () => _onItemTapped(1)),
    const _MapTab(),
    const _ProfileTab(),
    const _SettingsTab(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Commuter Home'),
        centerTitle: true,
        automaticallyImplyLeading: false, // Remove default back button
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// Home Tab Content - Morning Dashboard
class _HomeTab extends StatelessWidget {
  final VoidCallback onSwitchToMap;
  
  const _HomeTab({required this.onSwitchToMap});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 
                    'July', 'August', 'September', 'October', 'November', 'December'];
    final formattedDate = '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}, ${now.year}';
    
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hello, Commuter! 👋',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formattedDate,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // System Status Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade700, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'System Status',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'All systems operational',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        
        // Favorites Section
        const Text(
          'Favorites',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildRouteChip(
              context,
              'Route 01',
              'Wangsa Maju → TARUMT',
              Icons.directions_bus,
              Colors.blue,
            ),
            _buildRouteChip(
              context,
              'Route 02',
              'Aeon Big Danau Kota → Setapak Central',
              Icons.directions_bus,
              Colors.purple,
            ),
          ],
        ),
        const SizedBox(height: 28),
        
        // Latest News Section
        const Text(
          'Latest News',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _buildAnnouncementCard(
          'Maintenance Alert',
          'Route 01 delays expected tomorrow.',
          Icons.warning_amber_rounded,
          Colors.orange,
        ),
        const SizedBox(height: 12),
        _buildAnnouncementCard(
          'App Update',
          'Real-time tracking is now faster.',
          Icons.info_outline,
          Colors.blue,
        ),
        const SizedBox(height: 12),
        _buildAnnouncementCard(
          'Public Holiday',
          'Buses running on Sunday schedule.',
          Icons.calendar_today,
          Colors.green,
        ),
        const SizedBox(height: 20),
      ],
    );
  }
  
  Widget _buildRouteChip(
    BuildContext context,
    String routeId,
    String routeName,
    IconData icon,
    Color color,
  ) {
    return InkWell(
      onTap: () => onSwitchToMap(),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  routeId,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  routeName,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAnnouncementCard(
    String title,
    String message,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Map Tab Content
class _MapTab extends StatelessWidget {
  const _MapTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 20),
          const Text(
            'Live Bus Tracking',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'See buses moving in real-time',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CommuterMapPage()),
              );
            },
            icon: const Icon(Icons.location_on),
            label: const Text('Open Live Map'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        const Text(
                          'Available Routes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildRouteItem('Route 01', 'KL City - Bangsar'),
                    const SizedBox(height: 8),
                    _buildRouteItem('Route 02', 'Aeon Big Danau Kota - Setapak Central'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteItem(String routeId, String routeName) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              routeId,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              routeName,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Profile Tab Content
class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.blue[100],
              child: const Icon(Icons.person, size: 60, color: Colors.blue),
            ),
            const SizedBox(height: 20),
            const Text(
              'Commuter Profile',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (user?.email != null) ...[
              Text(
                user!.email!,
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'ID: ${user?.id.substring(0, 8) ?? "Unknown"}',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 40),
            ListTile(
              leading: const Icon(Icons.favorite, color: Colors.blue),
              title: const Text('Favorite Routes'),
              subtitle: const Text('Route 01, Route 02'),
              tileColor: Colors.grey[100],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.history, color: Colors.blue),
              title: const Text('Recent Trips'),
              subtitle: const Text('15 trips this month'),
              tileColor: Colors.grey[100],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Settings Tab Content
class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const SizedBox(height: 20),
        const Text(
          'Settings',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.notifications, color: Colors.blue),
                title: const Text('Notifications'),
                subtitle: const Text('Get alerts for your routes'),
                trailing: Switch(
                  value: true,
                  onChanged: (value) {},
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.location_on, color: Colors.blue),
                title: const Text('Location Services'),
                subtitle: const Text('Show your location on map'),
                trailing: Switch(
                  value: true,
                  onChanged: (value) {},
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.brightness_6, color: Colors.blue),
                title: const Text('Dark Mode'),
                subtitle: const Text('Switch to dark theme'),
                trailing: Switch(
                  value: false,
                  onChanged: (value) {},
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.help, color: Colors.blue),
                title: const Text('Help & Support'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {},
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info, color: Colors.blue),
                title: const Text('About'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () async {
            await supabase.auth.signOut();
            if (!context.mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AuthPage()),
            );
          },
          icon: const Icon(Icons.logout),
          label: const Text('Log Out'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}
