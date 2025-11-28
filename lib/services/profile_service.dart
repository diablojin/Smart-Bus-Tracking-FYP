import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ProfileService {
  /// Returns the app role for the current user: 'driver', 'commuter', or null if no profile.
  static Future<String?> getCurrentUserRole() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    final response = await supabase
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();

    if (response == null) return null;
    final role = response['role'] as String?;
    return role;
  }
}

