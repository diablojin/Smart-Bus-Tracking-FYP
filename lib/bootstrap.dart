import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_page.dart';
import 'commuter_home_page.dart';
import 'driver_home_page.dart';
import 'services/profile_service.dart';

final supabase = Supabase.instance.client;

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  @override
  void initState() {
    super.initState();
    _checkSessionAndNavigate();
  }

  Future<void> _checkSessionAndNavigate() async {
    final session = supabase.auth.currentSession;

    Widget target;

    if (session == null) {
      target = const AuthPage();
    } else {
      // Check if current user is guest
      final user = supabase.auth.currentUser;
      final isGuest = user?.email == 'guest@smartbus.com';
      
      final role = await ProfileService.getCurrentUserRole();
      if (role == 'driver') {
        target = const DriverHomePage();
      } else {
        target = CommuterHomePage(isGuest: isGuest);
      }
    }

    Future.microtask(() {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => target),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
