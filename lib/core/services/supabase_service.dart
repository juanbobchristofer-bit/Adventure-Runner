import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseClient client = Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;

  static Future<AuthResponse> signUp(String email, String password) async {
    return await client.auth.signUp(
      email: email.trim(),
      password: password.trim(),
    );
  }

  static Future<AuthResponse> signIn(String email, String password) async {
    return await client.auth.signInWithPassword(
      email: email.trim(),
      password: password.trim(),
    );
  }

  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  static Future<void> saveActivity({
    required String title,
    required double distanceKm,
    required int durationSeconds,
    int steps = 0,
    List? routeCoordinates,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) throw Exception('Pengguna belum login.');

    await client.from('activities').insert({
      'user_id': userId,
      'title': title,
      'distance_km': distanceKm,
      'duration_seconds': durationSeconds,
      'steps': steps,
      'route_json': routeCoordinates,
    });
  }

  static Future<List> getUserActivities() async {
    final response = await client
        .from('activities')
        .select()
        .order('created_at', ascending: false);
    return List.from(response);
  }
}