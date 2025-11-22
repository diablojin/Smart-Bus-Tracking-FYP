import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_page.dart';
import 'commuter_home_page.dart';
import 'driver_home_page.dart';

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
      final user = session.user;
      final metadata = user.userMetadata ?? {};
      final rawRole = metadata['role'];
      final role = (rawRole is String) ? rawRole : 'commuter';

      if (role == 'driver') {
        target = const DriverHomePage();
      } else {
        target = const CommuterHomePage();
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
