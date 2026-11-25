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
  final double weeklyKm;
  final int runsCount;
  final bool isCurrentUser;

  const OnlineClubMember({
    required this.userId,
    required this.name,
    required this.city,
    required this.weeklyKm,
    required this.runsCount,
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
    required this.membersCount,
    required this.isJoined,
    this.createdBy,
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
    required this.attendeesCount,
    required this.isAttending,
    required this.attendeeNames,
    this.createdBy,
  });
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
        return OnlineClub(
          id: id,
          name: c['name']?.toString() ?? '',
          location: c['location']?.toString() ?? '',
          description: c['description']?.toString() ?? '',
          schedule: c['schedule']?.toString() ?? '',
          color: parseHexColor(c['color_hex']?.toString()),
          membersCount: clubCounts[id] ?? 0,
          isJoined: myJoinedClubs.contains(id),
          createdBy: c['created_by']?.toString(),
        );
      }).toList();

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
        return OnlineEvent(
          id: id,
          title: e['title']?.toString() ?? '',
          dateStr: e['date_str']?.toString() ?? '',
          location: e['location']?.toString() ?? '',
          distanceTag: e['distance_tag']?.toString() ?? '5.0 KM',
          paceGroup: e['pace_group']?.toString() ?? 'All Pace',
          description: e['description']?.toString() ?? '',
          attendeesCount: evCounts[id] ?? 0,
          isAttending: myRsvps.contains(id),
          attendeeNames: evNames[id] ?? const [],
          createdBy: e['created_by']?.toString(),
        );
      }).toList();

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

  /// Mengambil leaderboard mingguan LIVE seluruh anggota klub dari Supabase
  Future<List<OnlineClubMember>> fetchClubLeaderboard(String clubId) async {
    final supabase = AuthService.client;
    if (supabase == null) return [];

    final currentUid = AuthService.userId;
    final currentWeekIso = RunnerStats.startOfCurrentWeek().toIso8601String();

    final raw = await supabase
        .from('club_members')
        .select('user_id, profiles(display_name, city, weekly_distance_km, weekly_runs_count, week_start_iso)')
        .eq('club_id', clubId);

    final members = <OnlineClubMember>[];
    for (final item in List<Map<String, dynamic>>.from(raw as List)) {
      final uid = item['user_id'].toString();
      final p = item['profiles'] is Map ? Map<String, dynamic>.from(item['profiles'] as Map) : <String, dynamic>{};
      final isCurrentWeek = p['week_start_iso']?.toString() == currentWeekIso;

      members.add(
        OnlineClubMember(
          userId: uid,
          name: (p['display_name']?.toString().trim().isNotEmpty ?? false)
              ? p['display_name'].toString()
              : 'Pelari Adventure',
          city: p['city']?.toString() ?? 'Indonesia',
          weeklyKm: isCurrentWeek ? ((p['weekly_distance_km'] as num?)?.toDouble() ?? 0.0) : 0.0,
          runsCount: isCurrentWeek ? ((p['weekly_runs_count'] as num?)?.toInt() ?? 0) : 0,
          isCurrentUser: currentUid != null && uid == currentUid,
        ),
      );
    }

    members.sort((a, b) => b.weeklyKm.compareTo(a.weeklyKm));
    return members;
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

  Future<void> toggleClub(String clubId, {required bool currentlyJoined}) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    if (currentlyJoined) {
      await supabase.from('club_members').delete().eq('club_id', clubId).eq('user_id', uid);
    } else {
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
  }) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    await AuthService.syncLocalStatsToCloud();

    final inserted = await supabase
        .from('clubs')
        .insert({
          'name': name.trim(),
          'location': location.trim(),
          'schedule': schedule.trim(),
          'description': description.trim(),
          'color_hex': colorHex,
          'created_by': uid,
        })
        .select('id')
        .single();

    await supabase.from('club_members').upsert(
      {
        'club_id': inserted['id'],
        'user_id': uid,
      },
      ignoreDuplicates: true,
    );
  }

  Future<void> toggleEventRsvp(String eventId, {required bool currentlyAttending}) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    if (currentlyAttending) {
      await supabase.from('event_rsvps').delete().eq('event_id', eventId).eq('user_id', uid);
    } else {
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
  }) async {
    final supabase = AuthService.client!;
    final uid = AuthService.userId!;
    await AuthService.syncLocalStatsToCloud();

    final inserted = await supabase
        .from('community_events')
        .insert({
          'title': title.trim(),
          'date_str': dateStr.trim(),
          'location': location.trim(),
          'distance_tag': distanceTag.trim(),
          'pace_group': paceGroup.trim(),
          'description': description.trim(),
          'created_by': uid,
        })
        .select('id')
        .single();

    await supabase.from('event_rsvps').upsert(
      {
        'event_id': inserted['id'],
        'user_id': uid,
      },
      ignoreDuplicates: true,
    );
  }
}
