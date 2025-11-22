import 'package:supabase_flutter/supabase_flutter.dart';

/// Call this once before runApp() to initialize Supabase.
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: 'https://wpiptgsloczxklodtjjm.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndwaXB0Z3Nsb2N6eGtsb2R0amptIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM1NTYwMzUsImV4cCI6MjA3OTEzMjAzNX0.2FQg14XH8GAmB1aDtr0hgfe0bNtGZg6inhBVFdyFgyI',
  );
}

/// Global Supabase client used throughout the app.
final SupabaseClient supabase = Supabase.instance.client;
