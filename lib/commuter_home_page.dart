import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_page.dart';
import 'commuter_route_page.dart';
import 'pages/commuter/report_page.dart';

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
    const _HomeTab(),              // Index 0: Dashboard
    const CommuterRoutesPage(),    // Index 1: Routes Search
    const _ProfileTab(),           // Index 2: Profile
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Only show AppBar when NOT on Routes tab (index 1)
      // Routes tab has its own AppBar in CommuterRoutesPage
      appBar: _selectedIndex == 1
          ? null
          : AppBar(
              centerTitle: true,
              title: Text(
                _selectedIndex == 2 ? 'Profile' : 'Commuter Home',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              elevation: 0,
              automaticallyImplyLeading: false, // Remove default back button
            ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.alt_route),
            label: 'Routes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// Home Tab Content - New implementation with greeting + Plan Trip + Latest Updates
class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  String? _displayName;

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  String _formatName(String raw) {
    // If an email sneaks in, strip the domain.
    if (raw.contains('@')) {
      raw = raw.split('@').first;
    }

    // Replace underscores with spaces.
    raw = raw.replaceAll('_', ' ');

    // Optionally remove digits.
    raw = raw.replaceAll(RegExp(r'[0-9]'), '');

    raw = raw.trim();
    if (raw.isEmpty) return 'Commuter';

    // Capitalize first letter.
    return raw[0].toUpperCase() + raw.substring(1);
  }

  void _loadUserName() {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _displayName = 'Commuter';
      });
      return;
    }

    // Try to use user metadata or email prefix as a fallback
    final fullName = user.userMetadata?['name'] as String?;
    final email = user.email ?? '';
    final emailName = email.contains('@') ? email.split('@').first : email;

    setState(() {
      if (fullName != null && fullName.trim().isNotEmpty) {
        _displayName = fullName.trim();
      } else if (emailName.isNotEmpty) {
        _displayName = _formatName(emailName);
      } else {
        _displayName = 'Commuter';
      }
    });
  }

  String _greetingForNow() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _formattedDate() {
    final now = DateTime.now();
    // Simple, readable date without extra dependencies
    final weekdays = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final dayName = weekdays[now.weekday % 7];
    final monthName = months[now.month - 1];

    return '$dayName, $monthName ${now.day}, ${now.year}';
  }

  void _onPlanTripPressed() {
    // Navigate to Routes tab (which shows Stop-to-Stop Search)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CommuterRoutesPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _displayName ?? 'Commuter';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Greeting
            Text(
              '${_greetingForNow()}, $name! 👋',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formattedDate(),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 24),

            // Primary CTA: Plan Trip (replaces the old "Service Normal" card)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _onPlanTripPressed,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.directions_bus),
                    SizedBox(width: 8),
                    Text(
                      'Plan My Trip',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Latest updates header
            const Text(
              'Latest Updates 🔔',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            // Example update cards (static for now; you can bind to real data later)
            const _UpdateCard(
              icon: Icons.notifications_active,
              iconBgColor: Color(0xFFE3F2FD),
              iconColor: Color(0xFF1565C0),
              title: 'Service Alert',
              subtitle: 'Route 750 frequency increased for peak hours.',
            ),
            const SizedBox(height: 10),
            const _UpdateCard(
              icon: Icons.build,
              iconBgColor: Color(0xFFFFF3E0),
              iconColor: Color(0xFFEF6C00),
              title: 'Maintenance',
              subtitle: 'MRT feeder bus TB15 temporarily rerouted.',
            ),
            const SizedBox(height: 10),
            const _UpdateCard(
              icon: Icons.system_update_alt,
              iconBgColor: Color(0xFFF3E5F5),
              iconColor: Color(0xFF6A1B9A),
              title: 'App Update',
              subtitle: 'New Dark Mode available for night travellers.',
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// Simple reusable card for "Latest Updates"
class _UpdateCard extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _UpdateCard({
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Profile Tab Content
class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 20),
        // Profile Header
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                child: Icon(
                  Icons.person,
                  size: 60,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Commuter Profile',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (user?.email != null) ...[
                Text(
                  user!.email!,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                'ID: ${user?.id.substring(0, 8) ?? "Unknown"}',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        
        // Account Section
        const Text(
          'Account',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.favorite, color: Colors.blue),
                title: const Text('Favorite Routes'),
                subtitle: const Text('Route 01, Route 02'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {},
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.history, color: Colors.blue),
                title: const Text('Recent Trips'),
                subtitle: const Text('15 trips this month'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        
        // Support Section
        const Text(
          'Support',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.report_problem, color: Colors.orange),
                title: const Text('Report an Issue'),
                subtitle: const Text('Let us know about any problems'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ReportIssuePage(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.help, color: Colors.blue),
                title: const Text('Help & Support'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        
        // Settings Section
        const Text(
          'Settings',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 32),
        
        // Logout Button
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
        const SizedBox(height: 20),
      ],
    );
  }
}
