import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'auth_page.dart';
import 'commuter_route_page.dart';
import 'models/announcement.dart';
import 'services/announcement_service.dart';

final supabase = Supabase.instance.client;

class CommuterHomePage extends StatefulWidget {
  final bool isGuest;
  
  const CommuterHomePage({
    super.key,
    this.isGuest = false,
  });

  @override
  State<CommuterHomePage> createState() => _CommuterHomePageState();
}

class _CommuterHomePageState extends State<CommuterHomePage> {
  int _selectedIndex = 0;

  // Define the pages for each tab
  List<Widget> get _pages => [
    const _HomeTab(),              // Index 0: Dashboard
    const CommuterRoutesPage(),    // Index 1: Routes Search
    _ProfileTab(isGuest: widget.isGuest), // Index 2: Profile
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Greeting
            Text(
              '${_greetingForNow()}, $name! 👋',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formattedDate(),
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.75),
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
                  children: [
                    Icon(
                      Icons.directions_bus,
                      color: colorScheme.onPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Plan My Trip',
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: colorScheme.onPrimary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Latest updates header
            Text(
              'Latest Updates 🔔',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),

            // Dynamic announcements from Supabase
            const LatestUpdatesSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Widget that fetches and displays announcements from Supabase in real-time.
/// Uses StreamBuilder to automatically update when announcements change.
class LatestUpdatesSection extends StatelessWidget {
  const LatestUpdatesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Announcement>>(
      stream: AnnouncementService.commuterAnnouncementsStream(),
      builder: (context, snapshot) {
        // Show loading indicator while waiting for initial data
        if (snapshot.hasData == false) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final announcements = snapshot.data ?? [];

        // Show empty state if no announcements
        if (announcements.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No updates at the moment.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
            ),
          );
        }

        // Display announcement cards
        return Column(
          children: [
            for (int i = 0; i < announcements.length; i++) ...[
              _AnnouncementCard(announcement: announcements[i]),
              if (i < announcements.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

/// Card widget for displaying a single announcement.
/// Theme-aware and supports both light and dark modes.
class _AnnouncementCard extends StatelessWidget {
  final Announcement announcement;

  const _AnnouncementCard({
    required this.announcement,
  });

  /// Maps announcement category to an appropriate icon.
  IconData _getIconForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'service alert':
        return Icons.directions_bus;
      case 'maintenance':
        return Icons.build;
      case 'app update':
        return Icons.smartphone;
      default:
        return Icons.info;
    }
  }

  /// Gets theme-aware icon colors based on category.
  /// Returns a tuple of (backgroundColor, iconColor) that adapts to light/dark mode.
  (Color, Color) _getColorsForCategory(BuildContext context, String category) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    switch (category.toLowerCase()) {
      case 'service alert':
        return isDark
            ? (const Color(0xFF1E3A5F).withOpacity(0.3), const Color(0xFF64B5F6))
            : (const Color(0xFFE3F2FD), const Color(0xFF1565C0));
      case 'maintenance':
        return isDark
            ? (const Color(0xFF5D4037).withOpacity(0.3), const Color(0xFFFFB74D))
            : (const Color(0xFFFFF3E0), const Color(0xFFEF6C00));
      case 'app update':
        return isDark
            ? (const Color(0xFF4A148C).withOpacity(0.3), const Color(0xFFBA68C8))
            : (const Color(0xFFF3E5F5), const Color(0xFF6A1B9A));
      default:
        return isDark
            ? (colorScheme.primary.withOpacity(0.2), colorScheme.primary)
            : (colorScheme.primary.withOpacity(0.1), colorScheme.primary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final icon = _getIconForCategory(announcement.category);
    final (iconBgColor, iconColor) = _getColorsForCategory(context, announcement.category);

    return Container(
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
                  announcement.category,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  announcement.title,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.75),
                  ),
                ),
                if (announcement.subtitle != null && announcement.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    announcement.subtitle!,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Profile Tab Content
class _ProfileTab extends StatefulWidget {
  final bool isGuest;
  
  const _ProfileTab({
    this.isGuest = false,
  });

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  String? _email;

  bool _darkModeEnabled = AppTheme.isDarkMode;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    // Listen to theme changes to keep switch in sync
    AppTheme.themeModeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    AppTheme.themeModeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {
        _darkModeEnabled = AppTheme.isDarkMode;
      });
    }
  }

  void _loadUserInfo() {
    final user = supabase.auth.currentUser;
    setState(() {
      _email = user?.email ?? 'unknown@example.com';
    });
  }

  void _onTapFavoriteRoutes() {
    // TODO: Navigate to favorite routes page if implemented
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Favorite Routes (coming soon)')),
    );
  }

  void _onTapRecentTrips() {
    // TODO: Navigate to recent trips page if implemented
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recent Trips (coming soon)')),
    );
  }


  void _onTapHelpSupport() {
    // TODO: Navigate to help & support page
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Help & Support (coming soon)')),
    );
  }


  void _onToggleDarkMode(bool value) {
    setState(() {
      _darkModeEnabled = value;
    });
    AppTheme.setDarkMode(value);
    // Optional: persist this preference later (e.g. SharedPreferences or Supabase)
  }

  Future<void> _onLogoutPressed() async {
    await supabase.auth.signOut();

    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHeader(),
            const SizedBox(height: 24),

            // Only show Account section if not guest
            if (!widget.isGuest) ...[
              Text(
                'Account',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              _ProfileTile(
                icon: Icons.favorite_outline,
                iconColor: colorScheme.primary,
                title: 'Favorite Routes',
                subtitle: 'Quick access to your saved routes.',
                onTap: _onTapFavoriteRoutes,
              ),
              const SizedBox(height: 8),
              _ProfileTile(
                icon: Icons.history,
                iconColor: colorScheme.primary,
                title: 'Recent Trips',
                subtitle: 'View your recent journeys.',
                onTap: _onTapRecentTrips,
              ),
              const SizedBox(height: 24),
              Text(
                'Support',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              _ProfileTile(
                icon: Icons.help_outline,
                iconColor: colorScheme.primary,
                title: 'Help & Support',
                subtitle: 'FAQs and contact information.',
                onTap: _onTapHelpSupport,
              ),
              const SizedBox(height: 24),
            ],

            const SizedBox(height: 24),
            Text(
              'Settings',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            _SwitchTile(
              icon: Icons.dark_mode_outlined,
              iconColor: colorScheme.primary,
              title: 'Dark Mode',
              subtitle: 'Switch to dark theme.',
              value: _darkModeEnabled,
              onChanged: _onToggleDarkMode,
            ),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _onLogoutPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Log Out',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    final titleColor = Theme.of(context).colorScheme.onSurface;
    final subtitleColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.8);
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2F1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person,
              size: 34,
              color: Color(0xFF00695C),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Commuter Profile',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 4),
          // Show "Guest" for guest users, otherwise show email
          Text(
            widget.isGuest ? 'Guest' : (_email ?? 'unknown@example.com'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: subtitleColor,
            ),
          ),
          // Show guest mode banner if applicable
          if (widget.isGuest) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Limited access (Guest Mode)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Reusable profile option tile with arrow
class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
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
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.75),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Tile with a switch on the right
class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.75),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
