import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/announcement.dart';

final supabase = Supabase.instance.client;

/// Service for fetching announcements from Supabase.
class AnnouncementService {
  /// Fetches published announcements for commuters.
  /// Returns announcements where target_role is 'commuter' or 'all', ordered by creation date (newest first).
  /// Limits results to 5 most recent announcements.
  static Future<List<Announcement>> fetchAnnouncementsForCommuter() async {
    try {
      final data = await supabase
          .from('announcements')
          .select()
          .or('target_role.eq.commuter,target_role.eq.all')
          .eq('is_published', true)
          .order('created_at', ascending: false)
          .limit(5);

      return (data as List)
          .map((row) {
            if (row is Map<String, dynamic>) {
              return Announcement.fromMap(row);
            }
            return null;
          })
          .whereType<Announcement>()
          .toList();
    } catch (e) {
      // Log error and return empty list on failure
      print('Error fetching announcements: $e');
      return [];
    }
  }

  /// Real-time stream of published announcements for commuters.
  /// Automatically updates when announcements are added, modified, or deleted in Supabase.
  /// Returns announcements where target_role is 'commuter' or 'all', ordered by creation date (newest first).
  /// Limits results to 5 most recent announcements.
  static Stream<List<Announcement>> commuterAnnouncementsStream() {
    try {
      return supabase
          .from('announcements')
          .stream(primaryKey: ['id'])
          .eq('is_published', true)
          .order('created_at', ascending: false)
          .limit(5)
          .map((data) {
            // Filter by target_role and convert rows to Announcement objects
            return (data as List)
                .map((row) {
                  if (row is Map<String, dynamic>) {
                    // Apply target_role filter (commuter or all)
                    final targetRole = row['target_role'] as String?;
                    
                    if (targetRole == 'commuter' || targetRole == 'all') {
                      return Announcement.fromMap(row);
                    }
                  }
                  return null;
                })
                .whereType<Announcement>()
                .toList();
          });
    } catch (e) {
      // Return an empty stream on error
      print('Error creating announcements stream: $e');
      return Stream.value([]);
    }
  }
}

