import 'package:flutter/material.dart';
import 'bootstrap.dart';
import 'config/supabase_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase before running the app
  await initSupabase();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Bus Tracking',
      debugShowCheckedModeBanner: false,
      home: const Bootstrap(),
    );
  }
}
