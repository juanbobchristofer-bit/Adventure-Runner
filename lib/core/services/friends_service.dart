import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/tracking/domain/runner_stats.dart';
import 'auth_service.dart';

enum FriendRelationStatus {
  none,
  pendingOutgoing,
  pendingIncoming,
  accepted,
}

class RunnerProfileSummary {
  final String userId;
  final String displayName;
  final String city;
  final String bio;
  final int runnerLevel;
  final double totalDistanceKm;
  final double weeklyDistanceKm;
  final int weeklyRunsCount;
  final bool isCurrentUser;

  const RunnerProfileSummary({
    required this.userId,
    required this.displayName,
    required this.city,
    required this.bio,
    required this.runnerLevel,
    required this.totalDistanceKm,
    required this.weeklyDistanceKm,
    required this.weeklyRunsCount,
    this.isCurrentUser = false,
  });
}

class FriendItem {
  final String friendshipId;
  final RunnerProfileSummary profile;
  final FriendRelationStatus status;

  const FriendItem({
    required this.friendshipId,
    required this.profile,
    required this.status,
  });
}

class FriendsSnapshot {
  final bool isAvailable;
  final bool needsSchemaSetup;
  final String? statusMessage;
  final List<FriendItem> incomingRequests;
  final List<FriendItem> outgoingRequests;
  final List<FriendItem> acceptedFriends;
  final Map<String, FriendItem> relationByUserId;

  const FriendsSnapshot({
    required this.isAvailable,
    this.needsSchemaSetup = false,
    this.statusMessage,
    this.incomingRequests = const [],
    this.outgoingRequests = const [],
    this.acceptedFriends = const [],
    this.relationByUserId = const {},
  });
}

/// Service pertemanan antar-pelari berbasis Supabase (Add Friend, Terima/Tolak, Cari Pelari, & Leaderboard Teman).
class FriendsService {
  RunnerProfileSummary _parseProfileMap(Map<String, dynamic> p, String currentWeekIso, String? currentUid) {
    final uid = p['id']?.toString() ?? '';
    final isCurrentWeek = p['week_start_iso']?.toString() == currentWeekIso;
    final level = (p['runner_level'] as num?)?.toInt() ?? 1;

    return RunnerProfileSummary(
      userId: uid,
      displayName: (p['display_name']?.toString().trim().isNotEmpty ?? false)
          ? p['display_name'].toString()
          : 'Pelari Adventure',
      city: p['city']?.toString() ?? 'Indonesia',
      bio: p['bio']?.toString() ?? '',
      runnerLevel: level < 1 ? 1 : level,
      totalDistanceKm: (p['total_distance_km'] as num?)?.toDouble() ?? 0.0,
      weeklyDistanceKm: isCurrentWeek ? ((p['weekly_distance_km'] as num?)?.toDouble() ?? 0.0) : 0.0,
      weeklyRunsCount: isCurrentWeek ? ((p['weekly_runs_count'] as num?)?.toInt() ?? 0) : 0,
      isCurrentUser: currentUid != null && uid == currentUid,
    );
  }

  /// Mengambil daftar teman, permintaan masuk, dan permintaan keluar milik user yang sedang login.
  Future<FriendsSnapshot> fetchFriendsSnapshot() async {
    final supabase = AuthService.client;
    final uid = AuthService.userId;
    if (supabase == null || uid == null) {
      return const FriendsSnapshot(
        isAvailable: false,
        statusMessage: 'Masuk akun untuk menambah teman & melihat leaderboard teman.',
      );
    }

    final currentWeekIso = RunnerStats.startOfCurrentWeek().toIso8601String();

    try {
      final rawRows = List<Map<String, dynamic>>.from(
        await supabase
            .from('friendships')
            .select('id, requester_id, addressee_id, status')
            .or('requester_id.eq.$uid,addressee_id.eq.$uid')
            .order('updated_at', ascending: false) as List,
      );

      if (rawRows.isEmpty) {
        return const FriendsSnapshot(isAvailable: true);
      }

      final otherUserIds = <String>{};
      for (final row in rawRows) {
        final req = row['requester_id'].toString();
        final addr = row['addressee_id'].toString();
        otherUserIds.add(req == uid ? addr : req);
      }

      dynamic rawProfiles;
      try {
        rawProfiles = await supabase
            .from('profiles')
            .select('id, display_name, city, bio, runner_level, total_distance_km, weekly_distance_km, weekly_runs_count, week_start_iso')
            .inFilter('id', otherUserIds.toList());
      } on PostgrestException {
        rawProfiles = await supabase
            .from('profiles')
            .select('id, display_name, city, bio, total_distance_km, weekly_distance_km, weekly_runs_count, week_start_iso')
            .inFilter('id', otherUserIds.toList());
      }

      final profileMap = <String, RunnerProfileSummary>{};
      for (final p in List<Map<String, dynamic>>.from(rawProfiles as List)) {
        final summary = _parseProfileMap(p, currentWeekIso, uid);
        profileMap[summary.userId] = summary;
      }

      final incoming = <FriendItem>[];
      final outgoing = <FriendItem>[];
      final accepted = <FriendItem>[];
      final relationByUser = <String, FriendItem>{};

      for (final row in rawRows) {
        final friendshipId = row['id'].toString();
        final req = row['requester_id'].toString();
        final addr = row['addressee_id'].toString();
        final statusStr = row['status']?.toString() ?? 'pending';
        final otherId = req == uid ? addr : req;

        final profile = profileMap[otherId] ??
            RunnerProfileSummary(
              userId: otherId,
              displayName: 'Pelari Adventure',
              city: 'Indonesia',
              bio: '',
              runnerLevel: 1,
              totalDistanceKm: 0,
              weeklyDistanceKm: 0,
              weeklyRunsCount: 0,
            );

        late final FriendRelationStatus relationStatus;
        if (statusStr == 'accepted') {
          relationStatus = FriendRelationStatus.accepted;
        } else if (addr == uid) {
          relationStatus = FriendRelationStatus.pendingIncoming;
        } else {
          relationStatus = FriendRelationStatus.pendingOutgoing;
        }

        final item = FriendItem(
          friendshipId: friendshipId,
          profile: profile,
          status: relationStatus,
        );

        relationByUser[otherId] = item;
        if (relationStatus == FriendRelationStatus.accepted) {
          accepted.add(item);
        } else if (relationStatus == FriendRelationStatus.pendingIncoming) {
          incoming.add(item);
        } else {
          outgoing.add(item);
        }
      }

      accepted.sort((a, b) => b.profile.weeklyDistanceKm.compareTo(a.profile.weeklyDistanceKm));

      return FriendsSnapshot(
        isAvailable: true,
        incomingRequests: incoming,
        outgoingRequests: outgoing,
        acceptedFriends: accepted,
        relationByUserId: relationByUser,
      );
    } on PostgrestException catch (e) {
      final isMissingTable = e.code == 'PGRST205' ||
          e.code == '42P01' ||
          e.message.toLowerCase().contains('friendships');
      return FriendsSnapshot(
        isAvailable: false,
        needsSchemaSetup: isMissingTable,
        statusMessage: isMissingTable
            ? 'Tabel pertemanan belum aktif. Jalankan supabase/migration_p4_friends.sql di SQL Editor Supabase.'
            : e.message,
      );
    } catch (_) {
      return const FriendsSnapshot(
        isAvailable: false,
        statusMessage: 'Tidak dapat memuat daftar teman (mode offline).',
      );
    }
  }

  /// Mencari pelari lain berdasarkan nama (jika kosong, menampilkan daftar pelari terbaru untuk ditemukan).
  Future<List<RunnerProfileSummary>> searchRunners(String query) async {
    final supabase = AuthService.client;
    final uid = AuthService.userId;
    if (supabase == null) return [];

    final currentWeekIso = RunnerStats.startOfCurrentWeek().toIso8601String();
    final cleanQuery = query.trim();

    dynamic raw;
    try {
      var req = supabase
          .from('profiles')
          .select('id, display_name, city, bio, runner_level, total_distance_km, weekly_distance_km, weekly_runs_count, week_start_iso');
      if (cleanQuery.isNotEmpty) {
        req = req.ilike('display_name', '%$cleanQuery%');
      }
      raw = await req.order('updated_at', ascending: false).limit(25);
    } on PostgrestException {
      var req = supabase
          .from('profiles')
          .select('id, display_name, city, bio, total_distance_km, weekly_distance_km, weekly_runs_count, week_start_iso');
      if (cleanQuery.isNotEmpty) {
        req = req.ilike('display_name', '%$cleanQuery%');
      }
      raw = await req.order('updated_at', ascending: false).limit(25);
    }

    final list = <RunnerProfileSummary>[];
    for (final p in List<Map<String, dynamic>>.from(raw as List)) {
      final summary = _parseProfileMap(p, currentWeekIso, uid);
      if (!summary.isCurrentUser) {
        list.add(summary);
      }
    }
    return list;
  }

  Future<void> sendFriendRequest(String targetUserId) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    if (targetUserId == uid) {
      throw Exception('Tidak dapat menambahkan diri sendiri sebagai teman.');
    }

    await AuthService.syncLocalStatsToCloud();

    // Cek jika pelari target sudah lebih dulu mengirim permintaan ke kita -> langsung terima!
    final reverse = await supabase
        .from('friendships')
        .select('id, status')
        .eq('requester_id', targetUserId)
        .eq('addressee_id', uid)
        .maybeSingle();

    if (reverse != null) {
      if (reverse['status'] != 'accepted') {
        await acceptFriendRequest(reverse['id'].toString());
      }
      return;
    }

    await supabase.from('friendships').upsert(
      {
        'requester_id': uid,
        'addressee_id': targetUserId,
        'status': 'pending',
      },
      ignoreDuplicates: true,
    );
  }

  Future<void> acceptFriendRequest(String friendshipId) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    await supabase
        .from('friendships')
        .update({
          'status': 'accepted',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', friendshipId)
        .eq('addressee_id', uid);
  }

  Future<void> removeFriendship(String friendshipId) async {
    final supabase = AuthService.client!;
    await supabase.from('friendships').delete().eq('id', friendshipId);
  }
}
