import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/tracking/domain/run_model.dart';
import '../../features/tracking/domain/runner_stats.dart';
import 'auth_service.dart';
import 'profile_storage_service.dart';
import 'run_storage_service.dart';

class CommunityRouteData {
  final String id;
  final String userId;
  final String authorName;
  final String name;
  final String location;
  final String category;
  final double distanceKm;
  final int elevationGainM;
  final String surface;
  final String difficulty;
  final List<LatLng> points;

  const CommunityRouteData({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.name,
    required this.location,
    required this.category,
    required this.distanceKm,
    required this.elevationGainM,
    required this.surface,
    required this.difficulty,
    required this.points,
  });
}

/// Service untuk sinkronisasi Cloud tingkat lanjut:
/// 1) Upload / hapus Avatar ke Supabase Storage (`avatars`)
/// 2) Cloud Backup & Restore penuh riwayat lari (`user_runs`)
/// 3) Berbagi & memuat Rute Komunitas Dinamis (`community_routes`)
class CloudSyncService {
  static const String _avatarBucket = 'avatars';

  static List<T> _downsampleList<T>(List<T> items, int maxItems) {
    if (items.length <= maxItems) return items;
    final step = (items.length - 1) / (maxItems - 1);
    return List<T>.generate(
      maxItems,
      (i) => items[(i * step).round().clamp(0, items.length - 1)],
    );
  }

  /// Mengunggah foto profil lokal ke Supabase Storage dan memperbarui kolom `profiles.avatar_url`
  static Future<String?> uploadAvatar(File file) async {
    final supabase = AuthService.client;
    final uid = AuthService.userId;
    if (supabase == null || uid == null) return null;

    try {
      final bytes = await file.readAsBytes();
      final storagePath = '$uid/avatar.jpg';

      await supabase.storage.from(_avatarBucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
              cacheControl: '3600',
            ),
          );

      final publicUrl = supabase.storage.from(_avatarBucket).getPublicUrl(storagePath);
      final versionedUrl = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';

      await ProfileStorageService().saveAvatarUrl(versionedUrl);
      try {
        await supabase.from('profiles').update({
          'avatar_url': versionedUrl,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', uid);
      } catch (_) {}

      return versionedUrl;
    } catch (e) {
      debugPrint('Upload avatar ke Supabase Storage dilewati: $e');
      return null;
    }
  }

  static Future<void> removeCloudAvatar() async {
    final supabase = AuthService.client;
    final uid = AuthService.userId;
    await ProfileStorageService().saveAvatarUrl(null);
    if (supabase == null || uid == null) return;

    try {
      await supabase.storage.from(_avatarBucket).remove(['$uid/avatar.jpg']);
    } catch (_) {}

    try {
      await supabase.from('profiles').update({
        'avatar_url': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    } catch (_) {}
  }

  /// Mencadangkan satu aktivitas lari ke tabel `user_runs` Supabase (non-blocking)
  static Future<bool> backupSingleRun(RunModel run) async {
    final supabase = AuthService.client;
    final uid = AuthService.userId;
    if (supabase == null || uid == null) return false;

    try {
      final compactRoute = _downsampleList(run.routePoints, 250)
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList();
      final compactTrack = _downsampleList(run.trackPoints, 250).map((tp) => tp.toMap()).toList();

      await supabase.from('user_runs').upsert(
        {
          'local_run_id': run.id,
          'user_id': uid,
          'title': run.title,
          'date_label': run.date,
          'created_at': run.createdAt.toUtc().toIso8601String(),
          'distance_km': run.distanceInKm,
          'duration_seconds': run.durationInSeconds,
          'pace': run.pace,
          'steps': run.steps,
          'calories': run.calories,
          'elevation_gain_m': run.elevationGainM,
          'notes': run.notes,
          'feeling': run.feeling,
          'route_points': compactRoute,
          'track_points': compactTrack,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,local_run_id',
      );
      return true;
    } catch (e) {
      debugPrint('Backup lari ke cloud dilewati (offline/tabel user_runs belum dibuat): $e');
      return false;
    }
  }

  static Future<void> deleteCloudRun(String localRunId) async {
    final supabase = AuthService.client;
    final uid = AuthService.userId;
    if (supabase == null || uid == null) return;
    try {
      await supabase.from('user_runs').delete().eq('user_id', uid).eq('local_run_id', localRunId);
    } catch (_) {}
  }

  /// Mencadangkan seluruh riwayat lari lokal ke cloud dan mengembalikan jumlah sesi yang berhasil dicadangkan.
  static Future<int> backupAllLocalRuns() async {
    if (!AuthService.isLoggedIn) return 0;
    await AuthService.syncLocalStatsToCloud();
    final runs = await RunStorageService().getSavedRuns();
    int success = 0;
    for (final run in runs) {
      if (await backupSingleRun(run)) {
        success++;
      }
    }
    return success;
  }

  /// Memulihkan riwayat lari dari tabel `user_runs` Supabase ke perangkat ini (tanpa duplikasi).
  static Future<int> restoreRunsFromCloud({bool onlyIfLocalEmpty = false}) async {
    final supabase = AuthService.client;
    final uid = AuthService.userId;
    if (supabase == null || uid == null) return 0;

    try {
      final storage = RunStorageService();
      if (onlyIfLocalEmpty) {
        final existing = await storage.getSavedRuns();
        if (existing.isNotEmpty) return 0;
      }

      final raw = List<Map<String, dynamic>>.from(
        await supabase
            .from('user_runs')
            .select()
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(200) as List,
      );

      if (raw.isEmpty) return 0;

      final parsedRuns = raw.map((row) {
        final rawRoute = row['route_points'] as List<dynamic>? ?? const [];
        final rawTrack = row['track_points'] as List<dynamic>? ?? const [];

        return RunModel(
          id: row['local_run_id']?.toString() ?? row['id'].toString(),
          title: row['title']?.toString() ?? 'Aktivitas Lari',
          date: row['date_label']?.toString() ?? '',
          createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
          distanceInKm: (row['distance_km'] as num?)?.toDouble() ?? 0.0,
          durationInSeconds: (row['duration_seconds'] as num?)?.toInt() ?? 0,
          pace: row['pace']?.toString() ?? '--:--',
          steps: (row['steps'] as num?)?.toInt() ?? 0,
          calories: (row['calories'] as num?)?.toDouble() ?? 0.0,
          elevationGainM: (row['elevation_gain_m'] as num?)?.toDouble() ?? 0.0,
          notes: row['notes']?.toString() ?? '',
          feeling: row['feeling']?.toString() ?? 'Luar Biasa 🔥',
          routePoints: rawRoute
              .whereType<Map>()
              .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
              .toList(),
          trackPoints: rawTrack
              .whereType<Map>()
              .map((tp) => RunTrackPoint.fromMap(Map<String, dynamic>.from(tp)))
              .toList(),
        );
      }).toList();

      return await storage.importRunsFromCloud(parsedRuns);
    } catch (e) {
      debugPrint('Pulihkan riwayat dari cloud dilewati: $e');
      return 0;
    }
  }

  /// Membagikan rute lari nyata ke Peta Jelajah Komunitas (`community_routes`)
  static Future<void> shareRunAsCommunityRoute({
    required RunModel run,
    required String location,
    String category = 'Komunitas',
    String surface = 'GPS Komunitas',
  }) async {
    final supabase = AuthService.client;
    final uid = AuthService.userId;
    if (supabase == null || uid == null) {
      throw Exception('Masuk akun terlebih dahulu untuk membagikan rute ke komunitas.');
    }
    if (run.routePoints.length < 2) {
      throw Exception('Rute ini belum memiliki titik GPS yang cukup untuk dibagikan.');
    }
    if (!RunnerStats.isValidRunningActivity(run)) {
      throw Exception('Aktivitas terdeteksi melebihi batas kecepatan lari (> 22 km/j) dan tidak dapat dibagikan.');
    }

    await AuthService.syncLocalStatsToCloud();

    final difficulty = run.elevationGainM >= 150 || run.distanceInKm >= 10
        ? 'Menantang'
        : run.distanceInKm >= 5
            ? 'Menengah'
            : 'Pemula';

    final compactPoints = _downsampleList(run.routePoints, 80)
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList();

    await supabase.from('community_routes').upsert(
      {
        'user_id': uid,
        'local_run_id': run.id,
        'name': run.title,
        'location': location.trim().isEmpty ? 'Indonesia' : location.trim(),
        'category': category,
        'distance_km': run.distanceInKm,
        'elevation_gain_m': run.elevationGainM.round(),
        'surface': surface,
        'difficulty': difficulty,
        'points': compactPoints,
      },
      onConflict: 'user_id,local_run_id',
    );
  }

  /// Mengambil daftar rute komunitas terbaru untuk ditampilkan di Peta Jelajah
  static Future<List<CommunityRouteData>> fetchCommunityRoutes() async {
    final supabase = AuthService.client;
    if (supabase == null) return const [];

    try {
      final raw = List<Map<String, dynamic>>.from(
        await supabase
            .from('community_routes')
            .select('id, user_id, name, location, category, distance_km, elevation_gain_m, surface, difficulty, points, profiles(display_name)')
            .order('created_at', ascending: false)
            .limit(40) as List,
      );

      return raw
          .map((row) {
            final rawPts = row['points'] as List<dynamic>? ?? const [];
            final pts = rawPts
                .whereType<Map>()
                .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
                .toList();
            final profile = row['profiles'] is Map
                ? Map<String, dynamic>.from(row['profiles'] as Map)
                : <String, dynamic>{};

            return CommunityRouteData(
              id: row['id'].toString(),
              userId: row['user_id'].toString(),
              authorName: (profile['display_name']?.toString().trim().isNotEmpty ?? false)
                  ? profile['display_name'].toString()
                  : 'Pelari Adventure',
              name: row['name']?.toString() ?? 'Rute Komunitas',
              location: row['location']?.toString() ?? 'Indonesia',
              category: row['category']?.toString() ?? 'Komunitas',
              distanceKm: (row['distance_km'] as num?)?.toDouble() ?? 0.0,
              elevationGainM: (row['elevation_gain_m'] as num?)?.toInt() ?? 0,
              surface: row['surface']?.toString() ?? 'GPS Komunitas',
              difficulty: row['difficulty']?.toString() ?? 'Menengah',
              points: pts,
            );
          })
          .where((r) => r.points.length >= 2)
          .toList();
    } catch (e) {
      debugPrint('Memuat rute komunitas dilewati: $e');
      return const [];
    }
  }
}
