import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/tracking/domain/runner_stats.dart';
import '../constants/app_colors.dart';
import 'auth_service.dart';
import 'profile_storage_service.dart';

class OnlineChallenge {
  final String id;
  final String title;
  final String description;
  final String badgeText;
  final double targetValue;
  final String unit;
  final int minLevel;
  final int xpReward;
  final Color accentColor;
  final IconData icon;
  final int participantsCount;
  final bool isJoined;
  final bool isRewardClaimed;

  const OnlineChallenge({
    required this.id,
    required this.title,
    required this.description,
    required this.badgeText,
    required this.targetValue,
    required this.unit,
    this.minLevel = 1,
    this.xpReward = 150,
    required this.accentColor,
    required this.icon,
    required this.participantsCount,
    required this.isJoined,
    this.isRewardClaimed = false,
  });
}

class OnlineClubMember {
  final String userId;
  final String name;
  final String city;
  final String? avatarUrl;
  final double weeklyKm;
  final int runsCount;
  final int runnerLevel;
  final bool isCurrentUser;

  const OnlineClubMember({
    required this.userId,
    required this.name,
    required this.city,
    this.avatarUrl,
    required this.weeklyKm,
    required this.runsCount,
    this.runnerLevel = 1,
    required this.isCurrentUser,
  });
}

class ClubMessage {
  final String id;
  final String clubId;
  final String userId;
  final String senderName;
  final int senderLevel;
  final String content;
  final DateTime createdAt;
  final bool isCurrentUser;

  const ClubMessage({
    required this.id,
    required this.clubId,
    required this.userId,
    required this.senderName,
    this.senderLevel = 1,
    required this.content,
    required this.createdAt,
    required this.isCurrentUser,
  });
}

class OnlineClub {
  final String id;
  final String name;
  final String location;
  final String description;
  final String schedule;
  final Color color;
  final int minLevel;
  final int membersCount;
  final bool isJoined;
  final String? createdBy;

  const OnlineClub({
    required this.id,
    required this.name,
    required this.location,
    required this.description,
    required this.schedule,
    required this.color,
    this.minLevel = 1,
    required this.membersCount,
    required this.isJoined,
    this.createdBy,
  });

  OnlineClub copyWith({
    int? membersCount,
    bool? isJoined,
  }) {
    return OnlineClub(
      id: id,
      name: name,
      location: location,
      description: description,
      schedule: schedule,
      color: color,
      minLevel: minLevel,
      membersCount: membersCount ?? this.membersCount,
      isJoined: isJoined ?? this.isJoined,
      createdBy: createdBy,
    );
  }
}

class EventAttendee {
  final String userId;
  final String name;
  final String city;
  final String? avatarUrl;
  final int runnerLevel;
  final bool isCurrentUser;

  const EventAttendee({
    required this.userId,
    required this.name,
    required this.city,
    this.avatarUrl,
    this.runnerLevel = 1,
    required this.isCurrentUser,
  });
}

class EventMessage {
  final String id;
  final String eventId;
  final String userId;
  final String senderName;
  final int senderLevel;
  final String content;
  final DateTime createdAt;
  final bool isCurrentUser;

  const EventMessage({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.senderName,
    this.senderLevel = 1,
    required this.content,
    required this.createdAt,
    required this.isCurrentUser,
  });
}

class OnlineEvent {
  final String id;
  final String title;
  final String dateStr;
  final String location;
  final String distanceTag;
  final String paceGroup;
  final String description;
  final int minLevel;
  final int maxParticipants;
  final int attendeesCount;
  final bool isAttending;
  final List<String> attendeeNames;
  final String? createdBy;

  const OnlineEvent({
    required this.id,
    required this.title,
    required this.dateStr,
    required this.location,
    required this.distanceTag,
    required this.paceGroup,
    required this.description,
    this.minLevel = 1,
    this.maxParticipants = 50,
    required this.attendeesCount,
    required this.isAttending,
    required this.attendeeNames,
    this.createdBy,
  });

  bool get isFull => attendeesCount >= maxParticipants;

  OnlineEvent copyWith({
    int? attendeesCount,
    bool? isAttending,
  }) {
    return OnlineEvent(
      id: id,
      title: title,
      dateStr: dateStr,
      location: location,
      distanceTag: distanceTag,
      paceGroup: paceGroup,
      description: description,
      minLevel: minLevel,
      maxParticipants: maxParticipants,
      attendeesCount: attendeesCount ?? this.attendeesCount,
      isAttending: isAttending ?? this.isAttending,
      attendeeNames: attendeeNames,
      createdBy: createdBy,
    );
  }
}

class CommunitySnapshot {
  final bool isOnline;
  final bool needsSchemaSetup;
  final String? statusMessage;
  final List<OnlineChallenge> challenges;
  final List<OnlineClub> clubs;
  final List<OnlineEvent> events;

  const CommunitySnapshot({
    required this.isOnline,
    this.needsSchemaSetup = false,
    this.statusMessage,
    required this.challenges,
    required this.clubs,
    required this.events,
  });
}

/// Service komunitas online berbasis Supabase (Tantangan, Klub, Leaderboard Mingguan Live, & Acara).
class CommunityService {
  static Color parseHexColor(String? hex, {Color fallback = AppColors.primaryOrange}) {
    if (hex == null || hex.isEmpty) return fallback;
    final clean = hex.replaceFirst('#', '').trim();
    if (clean.length == 6) {
      final parsed = int.tryParse('FF$clean', radix: 16);
      if (parsed != null) return Color(parsed);
    }
    return fallback;
  }

  static IconData iconForChallengeUnit(String unit) {
    switch (unit) {
      case 'single_km':
        return Icons.bolt;
      case 'runs':
        return Icons.local_fire_department;
      case 'kcal':
        return Icons.whatshot;
      default:
        return Icons.military_tech;
    }
  }

  /// Mengambil seluruh data Tantangan, Klub, dan Acara dari Supabase secara paralel.
  Future<CommunitySnapshot> fetchCommunitySnapshot() async {
    final supabase = AuthService.client;
    if (supabase == null) {
      return const CommunitySnapshot(
        isOnline: false,
        statusMessage: 'Mode Offline',
        challenges: [],
        clubs: [],
        events: [],
      );
    }

    final currentUid = AuthService.userId;

    try {
      final results = await Future.wait<dynamic>([
        supabase.from('challenges').select().order('created_at'),
        supabase.from('challenge_participants').select(),
        supabase.from('clubs').select().order('created_at', ascending: false),
        supabase.from('club_members').select('club_id, user_id'),
        supabase.from('community_events').select().order('created_at', ascending: false),
        supabase.from('event_rsvps').select('event_id, user_id, profiles(display_name)'),
      ]);

      final rawChallenges = List<Map<String, dynamic>>.from(results[0] as List);
      final rawChParts = List<Map<String, dynamic>>.from(results[1] as List);
      final rawClubs = List<Map<String, dynamic>>.from(results[2] as List);
      final rawClubMembers = List<Map<String, dynamic>>.from(results[3] as List);
      final rawEvents = List<Map<String, dynamic>>.from(results[4] as List);
      final rawEventRsvps = List<Map<String, dynamic>>.from(results[5] as List);

      // Hitung peserta & status klaim hadiah per tantangan
      final chCounts = <String, int>{};
      final myJoinedChallenges = <String>{};
      final myClaimedChallenges = <String>{};
      for (final row in rawChParts) {
        final cid = row['challenge_id'].toString();
        final uid = row['user_id'].toString();
        chCounts[cid] = (chCounts[cid] ?? 0) + 1;
        if (currentUid != null && uid == currentUid) {
          myJoinedChallenges.add(cid);
          if (row['reward_claimed'] == true) {
            myClaimedChallenges.add(cid);
          }
        }
      }

      final challenges = rawChallenges.map((c) {
        final id = c['id'].toString();
        final unit = c['unit']?.toString() ?? 'km';
        final minLevel = (c['min_level'] as num?)?.toInt() ?? 1;
        final xpReward = (c['xp_reward'] as num?)?.toInt() ?? 150;
        return OnlineChallenge(
          id: id,
          title: c['title']?.toString() ?? '',
          description: c['description']?.toString() ?? '',
          badgeText: c['badge_text']?.toString() ?? 'CHALLENGE',
          targetValue: (c['target_value'] as num?)?.toDouble() ?? 10.0,
          unit: unit,
          minLevel: minLevel < 1 ? 1 : minLevel,
          xpReward: xpReward < 0 ? 0 : xpReward,
          accentColor: parseHexColor(c['accent_hex']?.toString()),
          icon: iconForChallengeUnit(unit),
          participantsCount: chCounts[id] ?? 0,
          isJoined: myJoinedChallenges.contains(id),
          isRewardClaimed: myClaimedChallenges.contains(id),
        );
      }).toList()
        ..sort((a, b) {
          final byLevel = a.minLevel.compareTo(b.minLevel);
          if (byLevel != 0) return byLevel;
          return a.targetValue.compareTo(b.targetValue);
        });

      // Hitung anggota per klub
      final clubCounts = <String, int>{};
      final myJoinedClubs = <String>{};
      for (final row in rawClubMembers) {
        final cid = row['club_id'].toString();
        final uid = row['user_id'].toString();
        clubCounts[cid] = (clubCounts[cid] ?? 0) + 1;
        if (currentUid != null && uid == currentUid) myJoinedClubs.add(cid);
      }

      final clubs = rawClubs.map((c) {
        final id = c['id'].toString();
        final minLevel = (c['min_level'] as num?)?.toInt() ?? 1;
        return OnlineClub(
          id: id,
          name: c['name']?.toString() ?? '',
          location: c['location']?.toString() ?? '',
          description: c['description']?.toString() ?? '',
          schedule: c['schedule']?.toString() ?? '',
          color: parseHexColor(c['color_hex']?.toString()),
          minLevel: minLevel < 1 ? 1 : minLevel,
          membersCount: clubCounts[id] ?? 0,
          isJoined: myJoinedClubs.contains(id),
          createdBy: c['created_by']?.toString(),
        );
      }).toList()
        ..sort((a, b) {
          final byLevel = a.minLevel.compareTo(b.minLevel);
          if (byLevel != 0) return byLevel;
          return b.membersCount.compareTo(a.membersCount);
        });

      // Hitung RSVP & nama hadirin per acara
      final evCounts = <String, int>{};
      final evNames = <String, List<String>>{};
      final myRsvps = <String>{};
      for (final row in rawEventRsvps) {
        final eid = row['event_id'].toString();
        final uid = row['user_id'].toString();
        evCounts[eid] = (evCounts[eid] ?? 0) + 1;
        if (currentUid != null && uid == currentUid) myRsvps.add(eid);

        final profileObj = row['profiles'];
        if (profileObj is Map && profileObj['display_name'] != null) {
          evNames.putIfAbsent(eid, () => []).add(profileObj['display_name'].toString());
        }
      }

      final events = rawEvents.map((e) {
        final id = e['id'].toString();
        final minLevel = (e['min_level'] as num?)?.toInt() ?? 1;
        final maxParticipants = (e['max_participants'] as num?)?.toInt() ?? 50;
        return OnlineEvent(
          id: id,
          title: e['title']?.toString() ?? '',
          dateStr: e['date_str']?.toString() ?? '',
          location: e['location']?.toString() ?? '',
          distanceTag: e['distance_tag']?.toString() ?? '5.0 KM',
          paceGroup: e['pace_group']?.toString() ?? 'All Pace',
          description: e['description']?.toString() ?? '',
          minLevel: minLevel < 1 ? 1 : minLevel,
          maxParticipants: maxParticipants < 2 ? 2 : maxParticipants,
          attendeesCount: evCounts[id] ?? 0,
          isAttending: myRsvps.contains(id),
          attendeeNames: evNames[id] ?? const [],
          createdBy: e['created_by']?.toString(),
        );
      }).toList()
        ..sort((a, b) => a.minLevel.compareTo(b.minLevel));

      return CommunitySnapshot(
        isOnline: true,
        challenges: challenges,
        clubs: clubs,
        events: events,
      );
    } on PostgrestException catch (e) {
      final isMissingTable = e.code == 'PGRST205' ||
          e.code == '42P01' ||
          e.message.toLowerCase().contains('could not find the table') ||
          e.message.toLowerCase().contains('does not exist');
      return CommunitySnapshot(
        isOnline: false,
        needsSchemaSetup: isMissingTable,
        statusMessage: isMissingTable
            ? 'Tabel Supabase belum dibuat. Jalankan file supabase/schema.sql di SQL Editor Supabase.'
            : e.message,
        challenges: const [],
        clubs: const [],
        events: const [],
      );
    } catch (_) {
      return const CommunitySnapshot(
        isOnline: false,
        statusMessage: 'Tidak ada koneksi internet. Menampilkan mode offline.',
        challenges: [],
        clubs: [],
        events: [],
      );
    }
  }

  /// Mengambil leaderboard mingguan LIVE seluruh anggota klub dari Supabase (termasuk badge Level)
  Future<List<OnlineClubMember>> fetchClubLeaderboard(String clubId) async {
    final supabase = AuthService.client;
    if (supabase == null) return [];

    final currentUid = AuthService.userId;
    final currentWeekIso = RunnerStats.startOfCurrentWeek().toIso8601String();

    dynamic raw;
    try {
      raw = await supabase
          .from('club_members')
          .select('user_id, profiles(display_name, city, avatar_url, weekly_distance_km, weekly_runs_count, week_start_iso, runner_level)')
          .eq('club_id', clubId);
    } on PostgrestException {
      try {
        raw = await supabase
            .from('club_members')
            .select('user_id, profiles(display_name, city, weekly_distance_km, weekly_runs_count, week_start_iso, runner_level)')
            .eq('club_id', clubId);
      } on PostgrestException {
        raw = await supabase
            .from('club_members')
            .select('user_id, profiles(display_name, city, weekly_distance_km, weekly_runs_count, week_start_iso)')
            .eq('club_id', clubId);
      }
    }

    final members = <OnlineClubMember>[];
    for (final item in List<Map<String, dynamic>>.from(raw as List)) {
      final uid = item['user_id'].toString();
      final p = item['profiles'] is Map ? Map<String, dynamic>.from(item['profiles'] as Map) : <String, dynamic>{};
      final isCurrentWeek = p['week_start_iso']?.toString() == currentWeekIso;
      final level = (p['runner_level'] as num?)?.toInt() ?? 1;
      final rawAvatar = p['avatar_url']?.toString().trim();

      members.add(
        OnlineClubMember(
          userId: uid,
          name: (p['display_name']?.toString().trim().isNotEmpty ?? false)
              ? p['display_name'].toString()
              : 'Pelari Adventure',
          city: p['city']?.toString() ?? 'Indonesia',
          avatarUrl: (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
          weeklyKm: isCurrentWeek ? ((p['weekly_distance_km'] as num?)?.toDouble() ?? 0.0) : 0.0,
          runsCount: isCurrentWeek ? ((p['weekly_runs_count'] as num?)?.toInt() ?? 0) : 0,
          runnerLevel: level < 1 ? 1 : level,
          isCurrentUser: currentUid != null && uid == currentUid,
        ),
      );
    }

    members.sort((a, b) => b.weeklyKm.compareTo(a.weeklyKm));
    return members;
  }

  /// Mengambil riwayat pesan ruang obrolan klub (60 pesan terbaru)
  Future<List<ClubMessage>> fetchClubMessages(String clubId) async {
    final supabase = AuthService.client;
    if (supabase == null) return [];

    final currentUid = AuthService.userId;

    dynamic raw;
    try {
      raw = await supabase
          .from('club_messages')
          .select('id, club_id, user_id, content, created_at, profiles(display_name, runner_level)')
          .eq('club_id', clubId)
          .order('created_at', ascending: true)
          .limit(60);
    } on PostgrestException {
      raw = await supabase
          .from('club_messages')
          .select('id, club_id, user_id, content, created_at, profiles(display_name)')
          .eq('club_id', clubId)
          .order('created_at', ascending: true)
          .limit(60);
    }

    final messages = <ClubMessage>[];
    for (final row in List<Map<String, dynamic>>.from(raw as List)) {
      final uid = row['user_id'].toString();
      final p = row['profiles'] is Map ? Map<String, dynamic>.from(row['profiles'] as Map) : <String, dynamic>{};
      final level = (p['runner_level'] as num?)?.toInt() ?? 1;
      messages.add(
        ClubMessage(
          id: row['id'].toString(),
          clubId: row['club_id'].toString(),
          userId: uid,
          senderName: (p['display_name']?.toString().trim().isNotEmpty ?? false)
              ? p['display_name'].toString()
              : 'Pelari Adventure',
          senderLevel: level < 1 ? 1 : level,
          content: row['content']?.toString() ?? '',
          createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
          isCurrentUser: currentUid != null && uid == currentUid,
        ),
      );
    }
    return messages;
  }

  Future<void> sendClubMessage({
    required String clubId,
    required String content,
  }) async {
    final clean = content.trim();
    if (clean.isEmpty) {
      throw Exception('Pesan tidak boleh kosong.');
    }
    if (clean.length > 500) {
      throw Exception('Pesan maksimal 500 karakter.');
    }

    final supabase = AuthService.client!;
    final uid = AuthService.userId!;

    await supabase.from('club_messages').insert({
      'club_id': clubId,
      'user_id': uid,
      'content': clean,
    });
  }

  Future<void> deleteClubMessage(String messageId) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    await supabase.from('club_messages').delete().eq('id', messageId).eq('user_id', uid);
  }

  /// Berlangganan pembaruan live chat klub melalui Supabase Realtime
  RealtimeChannel? subscribeToClubMessages({
    required String clubId,
    required VoidCallback onChange,
  }) {
    final supabase = AuthService.client;
    if (supabase == null) return null;

    final channel = supabase.channel('club_chat_$clubId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'club_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'club_id',
            value: clubId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }

  Future<void> unsubscribeChannel(RealtimeChannel? channel) async {
    final supabase = AuthService.client;
    if (supabase != null && channel != null) {
      try {
        await supabase.removeChannel(channel);
      } catch (_) {}
    }
  }

  Future<void> toggleChallenge(
    String challengeId, {
    required bool currentlyJoined,
    required int userLevel,
    required int minLevel,
  }) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    if (currentlyJoined) {
      await supabase
          .from('challenge_participants')
          .delete()
          .eq('challenge_id', challengeId)
          .eq('user_id', uid);
    } else {
      if (!RunnerStats.meetsLevelRequirement(userLevel: userLevel, minLevel: minLevel)) {
        throw Exception('Level belum mencukupi. Tantangan ini membutuhkan minimal Level $minLevel.');
      }
      await AuthService.syncLocalStatsToCloud();
      await supabase.from('challenge_participants').upsert(
        {
          'challenge_id': challengeId,
          'user_id': uid,
        },
        ignoreDuplicates: true,
      );
    }
  }

  /// Mengklaim hadiah Bonus XP sekali saja setelah tantangan mencapai 100%
  Future<int> claimChallengeReward({
    required String challengeId,
    required int xpReward,
  }) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;

    // Pastikan belum pernah diklaim sebelumnya di server
    final existing = await supabase
        .from('challenge_participants')
        .select('reward_claimed')
        .eq('challenge_id', challengeId)
        .eq('user_id', uid)
        .maybeSingle();

    if (existing == null) {
      throw Exception('Anda belum terdaftar pada tantangan ini.');
    }
    if (existing['reward_claimed'] == true) {
      throw Exception('Hadiah XP tantangan ini sudah pernah diklaim.');
    }

    await supabase
        .from('challenge_participants')
        .update({
          'reward_claimed': true,
          'claimed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('challenge_id', challengeId)
        .eq('user_id', uid);

    final updatedBonusXp = await ProfileStorageService().addBonusXp(xpReward);
    await AuthService.syncLocalStatsToCloud();
    return updatedBonusXp;
  }

  Future<void> toggleClub(
    String clubId, {
    required bool currentlyJoined,
    required int userLevel,
    required int minLevel,
  }) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    if (currentlyJoined) {
      await supabase.from('club_members').delete().eq('club_id', clubId).eq('user_id', uid);
    } else {
      if (!RunnerStats.meetsLevelRequirement(userLevel: userLevel, minLevel: minLevel)) {
        throw Exception('Level belum mencukupi. Klub ini membutuhkan minimal Level $minLevel.');
      }
      await AuthService.syncLocalStatsToCloud();
      await supabase.from('club_members').upsert(
        {
          'club_id': clubId,
          'user_id': uid,
        },
        ignoreDuplicates: true,
      );
    }
  }

  Future<void> createClub({
    required String name,
    required String location,
    required String schedule,
    required String description,
    required String colorHex,
    int minLevel = 1,
  }) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    await AuthService.syncLocalStatsToCloud();

    final basePayload = <String, dynamic>{
      'name': name.trim(),
      'location': location.trim(),
      'schedule': schedule.trim(),
      'description': description.trim(),
      'color_hex': colorHex,
      'created_by': uid,
    };

    Map<String, dynamic> inserted;
    try {
      inserted = await supabase
          .from('clubs')
          .insert({...basePayload, 'min_level': minLevel < 1 ? 1 : minLevel})
          .select('id')
          .single();
    } on PostgrestException {
      inserted = await supabase.from('clubs').insert(basePayload).select('id').single();
    }

    await supabase.from('club_members').upsert(
      {
        'club_id': inserted['id'],
        'user_id': uid,
      },
      ignoreDuplicates: true,
    );
  }

  Future<void> toggleEventRsvp(
    String eventId, {
    required bool currentlyAttending,
    required int userLevel,
    required int minLevel,
    required int currentAttendeesCount,
    required int maxParticipants,
  }) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    if (currentlyAttending) {
      await supabase.from('event_rsvps').delete().eq('event_id', eventId).eq('user_id', uid);
    } else {
      if (!RunnerStats.meetsLevelRequirement(userLevel: userLevel, minLevel: minLevel)) {
        throw Exception('Level belum mencukupi. Acara ini membutuhkan minimal Level $minLevel.');
      }
      if (currentAttendeesCount >= maxParticipants) {
        throw Exception('Maaf, kuota peserta acara ini sudah penuh ($maxParticipants/$maxParticipants).');
      }
      await AuthService.syncLocalStatsToCloud();
      await supabase.from('event_rsvps').upsert(
        {
          'event_id': eventId,
          'user_id': uid,
        },
        ignoreDuplicates: true,
      );
    }
  }

  Future<void> createEvent({
    required String title,
    required String dateStr,
    required String location,
    required String distanceTag,
    required String paceGroup,
    required String description,
    int minLevel = 1,
    int maxParticipants = 50,
  }) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    await AuthService.syncLocalStatsToCloud();

    final basePayload = <String, dynamic>{
      'title': title.trim(),
      'date_str': dateStr.trim(),
      'location': location.trim(),
      'distance_tag': distanceTag.trim(),
      'pace_group': paceGroup.trim(),
      'description': description.trim(),
      'created_by': uid,
    };

    Map<String, dynamic> inserted;
    try {
      inserted = await supabase
          .from('community_events')
          .insert({
            ...basePayload,
            'min_level': minLevel < 1 ? 1 : minLevel,
            'max_participants': maxParticipants.clamp(2, 500),
          })
          .select('id')
          .single();
    } on PostgrestException {
      inserted = await supabase.from('community_events').insert(basePayload).select('id').single();
    }

    await supabase.from('event_rsvps').upsert(
      {
        'event_id': inserted['id'],
        'user_id': uid,
      },
      ignoreDuplicates: true,
    );
  }

  /// Mengambil daftar lengkap peserta acara beserta level & kotanya
  Future<List<EventAttendee>> fetchEventAttendees(String eventId) async {
    final supabase = AuthService.client;
    if (supabase == null) return [];

    final currentUid = AuthService.userId;

    dynamic raw;
    try {
      raw = await supabase
          .from('event_rsvps')
          .select('user_id, profiles(display_name, city, avatar_url, runner_level)')
          .eq('event_id', eventId)
          .order('rsvped_at', ascending: true);
    } on PostgrestException {
      try {
        raw = await supabase
            .from('event_rsvps')
            .select('user_id, profiles(display_name, city, runner_level)')
            .eq('event_id', eventId)
            .order('rsvped_at', ascending: true);
      } on PostgrestException {
        raw = await supabase
            .from('event_rsvps')
            .select('user_id, profiles(display_name, city)')
            .eq('event_id', eventId)
            .order('rsvped_at', ascending: true);
      }
    }

    final list = <EventAttendee>[];
    for (final row in List<Map<String, dynamic>>.from(raw as List)) {
      final uid = row['user_id'].toString();
      final p = row['profiles'] is Map ? Map<String, dynamic>.from(row['profiles'] as Map) : <String, dynamic>{};
      final level = (p['runner_level'] as num?)?.toInt() ?? 1;
      final rawAvatar = p['avatar_url']?.toString().trim();
      list.add(
        EventAttendee(
          userId: uid,
          name: (p['display_name']?.toString().trim().isNotEmpty ?? false)
              ? p['display_name'].toString()
              : 'Pelari Adventure',
          city: p['city']?.toString() ?? 'Indonesia',
          avatarUrl: (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
          runnerLevel: level < 1 ? 1 : level,
          isCurrentUser: currentUid != null && uid == currentUid,
        ),
      );
    }
    return list;
  }

  /// Menghapus klub milik sendiri (dijaga oleh kebijakan RLS `created_by = auth.uid()`)
  Future<void> deleteClub(String clubId) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    await supabase.from('clubs').delete().eq('id', clubId).eq('created_by', uid);
  }

  /// Menghapus acara milik sendiri (dijaga oleh kebijakan RLS `created_by = auth.uid()`)
  Future<void> deleteEvent(String eventId) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    await supabase.from('community_events').delete().eq('id', eventId).eq('created_by', uid);
  }

  /// Mengambil riwayat pesan ruang diskusi acara (60 pesan terbaru)
  Future<List<EventMessage>> fetchEventMessages(String eventId) async {
    final supabase = AuthService.client;
    if (supabase == null) return [];

    final currentUid = AuthService.userId;

    dynamic raw;
    try {
      raw = await supabase
          .from('event_messages')
          .select('id, event_id, user_id, content, created_at, profiles(display_name, runner_level)')
          .eq('event_id', eventId)
          .order('created_at', ascending: true)
          .limit(60);
    } on PostgrestException {
      raw = await supabase
          .from('event_messages')
          .select('id, event_id, user_id, content, created_at, profiles(display_name)')
          .eq('event_id', eventId)
          .order('created_at', ascending: true)
          .limit(60);
    }

    final list = <EventMessage>[];
    for (final row in List<Map<String, dynamic>>.from(raw as List)) {
      final uid = row['user_id'].toString();
      final p = row['profiles'] is Map ? Map<String, dynamic>.from(row['profiles'] as Map) : <String, dynamic>{};
      final level = (p['runner_level'] as num?)?.toInt() ?? 1;
      list.add(
        EventMessage(
          id: row['id'].toString(),
          eventId: row['event_id'].toString(),
          userId: uid,
          senderName: (p['display_name']?.toString().trim().isNotEmpty ?? false)
              ? p['display_name'].toString()
              : 'Pelari Adventure',
          senderLevel: level < 1 ? 1 : level,
          content: row['content']?.toString() ?? '',
          createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
          isCurrentUser: currentUid != null && uid == currentUid,
        ),
      );
    }
    return list;
  }

  Future<void> sendEventMessage({
    required String eventId,
    required String content,
  }) async {
    final clean = content.trim();
    if (clean.isEmpty) {
      throw Exception('Pesan tidak boleh kosong.');
    }
    if (clean.length > 500) {
      throw Exception('Pesan maksimal 500 karakter.');
    }
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    await supabase.from('event_messages').insert({
      'event_id': eventId,
      'user_id': uid,
      'content': clean,
    });
  }

  Future<void> deleteEventMessage(String messageId) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    await supabase.from('event_messages').delete().eq('id', messageId).eq('user_id', uid);
  }

  RealtimeChannel? subscribeToEventMessages({
    required String eventId,
    required VoidCallback onChange,
  }) {
    final supabase = AuthService.client;
    if (supabase == null) return null;

    final channel = supabase.channel('event_chat_$eventId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'event_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: eventId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }
}
