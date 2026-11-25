import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/tracking/domain/run_model.dart';
import 'auth_service.dart';

class SocialFeedPost {
  final String id;
  final String userId;
  final String authorName;
  final String authorCity;
  final String? authorAvatarUrl;
  final int authorLevel;
  final String title;
  final String notes;
  final String feeling;
  final double distanceKm;
  final int durationSeconds;
  final String pace;
  final double calories;
  final double elevationGainM;
  final List<LatLng> routePreview;
  final DateTime createdAt;
  final int kudosCount;
  final bool hasGivenKudos;
  final bool isMine;

  const SocialFeedPost({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.authorCity,
    this.authorAvatarUrl,
    required this.authorLevel,
    required this.title,
    required this.notes,
    required this.feeling,
    required this.distanceKm,
    required this.durationSeconds,
    required this.pace,
    required this.calories,
    required this.elevationGainM,
    required this.routePreview,
    required this.createdAt,
    required this.kudosCount,
    required this.hasGivenKudos,
    required this.isMine,
  });

  SocialFeedPost copyWith({
    int? kudosCount,
    bool? hasGivenKudos,
  }) {
    return SocialFeedPost(
      id: id,
      userId: userId,
      authorName: authorName,
      authorCity: authorCity,
      authorAvatarUrl: authorAvatarUrl,
      authorLevel: authorLevel,
      title: title,
      notes: notes,
      feeling: feeling,
      distanceKm: distanceKm,
      durationSeconds: durationSeconds,
      pace: pace,
      calories: calories,
      elevationGainM: elevationGainM,
      routePreview: routePreview,
      createdAt: createdAt,
      kudosCount: kudosCount ?? this.kudosCount,
      hasGivenKudos: hasGivenKudos ?? this.hasGivenKudos,
      isMine: isMine,
    );
  }
}

class SocialFeedSnapshot {
  final bool isAvailable;
  final bool needsSchemaSetup;
  final String? statusMessage;
  final List<SocialFeedPost> posts;

  const SocialFeedSnapshot({
    required this.isAvailable,
    this.needsSchemaSetup = false,
    this.statusMessage,
    this.posts = const [],
  });
}

/// Service untuk Feed Aktivitas Teman & Kudos (👏) berbasis Supabase.
class SocialFeedService {
  static List<Map<String, double>> _downsampleRouteForPreview(List<LatLng> points, {int maxPoints = 40}) {
    if (points.isEmpty) return const [];
    if (points.length <= maxPoints) {
      return points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
    }
    final step = (points.length - 1) / (maxPoints - 1);
    final result = <Map<String, double>>[];
    for (int i = 0; i < maxPoints; i++) {
      final p = points[(i * step).round().clamp(0, points.length - 1)];
      result.add({'lat': p.latitude, 'lng': p.longitude});
    }
    return result;
  }

  /// Mempublikasikan atau memperbarui aktivitas lari lokal ke Feed Teman online (non-blocking)
  static Future<void> publishRunToFeed(RunModel run) async {
    final supabase = AuthService.client;
    final uid = AuthService.userId;
    if (supabase == null || uid == null) return;

    try {
      await AuthService.syncLocalStatsToCloud();
      await supabase.from('activity_posts').upsert(
        {
          'local_run_id': run.id,
          'user_id': uid,
          'title': run.title,
          'notes': run.notes,
          'feeling': run.feeling,
          'distance_km': run.distanceInKm,
          'duration_seconds': run.durationInSeconds,
          'pace': run.pace,
          'calories': run.calories,
          'elevation_gain_m': run.elevationGainM,
          'route_preview': _downsampleRouteForPreview(run.routePoints),
          'created_at': run.createdAt.toUtc().toIso8601String(),
        },
        onConflict: 'user_id,local_run_id',
      );
    } catch (e) {
      debugPrint('Publikasi ke Feed Teman dilewati (offline/tabel belum aktif): $e');
    }
  }

  static Future<void> deletePublishedRun(String localRunId) async {
    final supabase = AuthService.client;
    final uid = AuthService.userId;
    if (supabase == null || uid == null) return;
    try {
      await supabase
          .from('activity_posts')
          .delete()
          .eq('user_id', uid)
          .eq('local_run_id', localRunId);
    } catch (_) {}
  }

  Future<SocialFeedSnapshot> fetchFriendsFeed() async {
    final supabase = AuthService.client;
    final uid = AuthService.userId;
    if (supabase == null || uid == null) {
      return const SocialFeedSnapshot(
        isAvailable: false,
        statusMessage: 'Masuk akun untuk melihat Feed Aktivitas Teman & memberikan Kudos.',
      );
    }

    try {
      dynamic rawPosts;
      try {
        rawPosts = await supabase
            .from('activity_posts')
            .select(
              'id, user_id, title, notes, feeling, distance_km, duration_seconds, pace, calories, elevation_gain_m, route_preview, created_at, profiles(display_name, city, avatar_url, runner_level)',
            )
            .order('created_at', ascending: false)
            .limit(40);
      } on PostgrestException catch (e) {
        final msg = e.message.toLowerCase();
        if (msg.contains('avatar_url') || msg.contains('runner_level')) {
          rawPosts = await supabase
              .from('activity_posts')
              .select(
                'id, user_id, title, notes, feeling, distance_km, duration_seconds, pace, calories, elevation_gain_m, route_preview, created_at, profiles(display_name, city)',
              )
              .order('created_at', ascending: false)
              .limit(40);
        } else {
          rethrow;
        }
      }

      final postRows = List<Map<String, dynamic>>.from(rawPosts as List);
      if (postRows.isEmpty) {
        return const SocialFeedSnapshot(isAvailable: true, posts: []);
      }

      final postIds = postRows.map((e) => e['id'].toString()).toList();
      final rawKudos = List<Map<String, dynamic>>.from(
        await supabase.from('activity_kudos').select('post_id, user_id').inFilter('post_id', postIds) as List,
      );

      final kudosCountMap = <String, int>{};
      final myKudosSet = <String>{};
      for (final row in rawKudos) {
        final pid = row['post_id'].toString();
        final kuid = row['user_id'].toString();
        kudosCountMap[pid] = (kudosCountMap[pid] ?? 0) + 1;
        if (kuid == uid) myKudosSet.add(pid);
      }

      final posts = postRows.map((row) {
        final pid = row['id'].toString();
        final authorId = row['user_id'].toString();
        final profile = row['profiles'] is Map
            ? Map<String, dynamic>.from(row['profiles'] as Map)
            : <String, dynamic>{};
        final rawPreview = row['route_preview'] as List<dynamic>? ?? const [];
        final previewPoints = rawPreview
            .whereType<Map>()
            .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
            .toList();

        final rawAvatar = profile['avatar_url']?.toString().trim();
        return SocialFeedPost(
          id: pid,
          userId: authorId,
          authorName: (profile['display_name']?.toString().trim().isNotEmpty ?? false)
              ? profile['display_name'].toString()
              : 'Pelari Adventure',
          authorCity: profile['city']?.toString() ?? 'Indonesia',
          authorAvatarUrl: (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
          authorLevel: ((profile['runner_level'] as num?)?.toInt() ?? 1).clamp(1, 999),
          title: row['title']?.toString() ?? 'Aktivitas Lari',
          notes: row['notes']?.toString() ?? '',
          feeling: row['feeling']?.toString() ?? '',
          distanceKm: (row['distance_km'] as num?)?.toDouble() ?? 0.0,
          durationSeconds: (row['duration_seconds'] as num?)?.toInt() ?? 0,
          pace: row['pace']?.toString() ?? '--:--',
          calories: (row['calories'] as num?)?.toDouble() ?? 0.0,
          elevationGainM: (row['elevation_gain_m'] as num?)?.toDouble() ?? 0.0,
          routePreview: previewPoints,
          createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
          kudosCount: kudosCountMap[pid] ?? 0,
          hasGivenKudos: myKudosSet.contains(pid),
          isMine: authorId == uid,
        );
      }).toList();

      return SocialFeedSnapshot(isAvailable: true, posts: posts);
    } on PostgrestException catch (e) {
      final isMissing = e.code == 'PGRST205' ||
          e.code == '42P01' ||
          e.message.toLowerCase().contains('activity_posts');
      return SocialFeedSnapshot(
        isAvailable: false,
        needsSchemaSetup: isMissing,
        statusMessage: isMissing
            ? 'Tabel Feed Teman belum aktif. Jalankan supabase/migration_p5_social_feed.sql di SQL Editor Supabase.'
            : e.message,
      );
    } catch (_) {
      return const SocialFeedSnapshot(
        isAvailable: false,
        statusMessage: 'Tidak dapat memuat Feed Teman (periksa koneksi internet).',
      );
    }
  }

  Future<void> toggleKudos({
    required String postId,
    required bool currentlyGiven,
  }) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    if (currentlyGiven) {
      await supabase.from('activity_kudos').delete().eq('post_id', postId).eq('user_id', uid);
    } else {
      await supabase.from('activity_kudos').upsert(
        {'post_id': postId, 'user_id': uid},
        ignoreDuplicates: true,
      );
    }
  }
}
