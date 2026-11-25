import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/tracking/domain/runner_stats.dart';
import '../constants/app_colors.dart';
import '../services/auth_service.dart';
import '../services/friends_service.dart';

class _RunnerFullProfile {
  final String userId;
  final String displayName;
  final String bio;
  final String city;
  final String? avatarUrl;
  final int runnerLevel;
  final int totalXp;
  final double weeklyDistanceKm;
  final int weeklyRunsCount;
  final double totalDistanceKm;
  final int totalRunsCount;
  final double totalCalories;
  final double longestRunKm;

  const _RunnerFullProfile({
    required this.userId,
    required this.displayName,
    required this.bio,
    required this.city,
    this.avatarUrl,
    required this.runnerLevel,
    required this.totalXp,
    required this.weeklyDistanceKm,
    required this.weeklyRunsCount,
    required this.totalDistanceKm,
    required this.totalRunsCount,
    required this.totalCalories,
    required this.longestRunKm,
  });
}

class _MiniBadge {
  final String label;
  final IconData icon;
  final Color color;

  const _MiniBadge(this.label, this.icon, this.color);
}

/// Modal Bottom Sheet untuk menampilkan Kartu Profil Mini Atlet lain
/// (Level, Gelar Rank, Progress XP, Statistik Mingguan & Sepanjang Masa, Lencana Terbuka, + Add Friend).
class RunnerProfileSheet extends StatefulWidget {
  final String userId;
  final String fallbackName;
  final String fallbackCity;
  final int fallbackLevel;

  const RunnerProfileSheet({
    super.key,
    required this.userId,
    required this.fallbackName,
    required this.fallbackCity,
    required this.fallbackLevel,
  });

  static Future<void> show(
    BuildContext context, {
    required String userId,
    String fallbackName = 'Pelari Adventure',
    String fallbackCity = 'Indonesia',
    int fallbackLevel = 1,
  }) async {
    if (userId.trim().isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => RunnerProfileSheet(
        userId: userId,
        fallbackName: fallbackName,
        fallbackCity: fallbackCity,
        fallbackLevel: fallbackLevel,
      ),
    );
  }

  @override
  State<RunnerProfileSheet> createState() => _RunnerProfileSheetState();
}

class _RunnerProfileSheetState extends State<RunnerProfileSheet> {
  final FriendsService _friendsService = FriendsService();

  _RunnerFullProfile? _profile;
  FriendItem? _friendRelation;
  bool _isLoading = true;
  bool _isBusyFriendAction = false;

  bool get _isSelf => AuthService.userId != null && AuthService.userId == widget.userId;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final supabase = AuthService.client;
    if (supabase == null) {
      if (mounted) {
        setState(() {
          _profile = _buildFallbackProfile();
          _isLoading = false;
        });
      }
      return;
    }

    try {
      Map<String, dynamic>? row;
      try {
        row = await supabase
            .from('profiles')
            .select(
              'id, display_name, bio, city, avatar_url, runner_level, total_xp, weekly_distance_km, weekly_runs_count, total_distance_km, total_runs_count, total_calories, longest_run_km',
            )
            .eq('id', widget.userId)
            .maybeSingle();
      } on PostgrestException catch (e) {
        final msg = e.message.toLowerCase();
        if (msg.contains('avatar_url') || msg.contains('runner_level') || msg.contains('total_xp')) {
          row = await supabase
              .from('profiles')
              .select(
                'id, display_name, bio, city, weekly_distance_km, weekly_runs_count, total_distance_km, total_runs_count, total_calories, longest_run_km',
              )
              .eq('id', widget.userId)
              .maybeSingle();
        } else {
          rethrow;
        }
      }

      FriendItem? relation;
      if (AuthService.isLoggedIn && !_isSelf) {
        final snap = await _friendsService.fetchFriendsSnapshot();
        relation = snap.relationByUserId[widget.userId];
      }

      if (mounted) {
        setState(() {
          if (row != null) {
            final totalDist = (row['total_distance_km'] as num?)?.toDouble() ?? 0.0;
            final totalRuns = (row['total_runs_count'] as num?)?.toInt() ?? 0;
            final computedXp = (totalDist * 100).round() + (totalRuns * 50);
            final xp = (row['total_xp'] as num?)?.toInt() ?? computedXp;
            final level = ((row['runner_level'] as num?)?.toInt() ?? ((xp ~/ RunnerStats.xpPerLevel) + 1)).clamp(1, 999);

            final rawAvatar = row['avatar_url']?.toString().trim();

            _profile = _RunnerFullProfile(
              userId: widget.userId,
              displayName: (row['display_name']?.toString().trim().isNotEmpty ?? false)
                  ? row['display_name'].toString()
                  : widget.fallbackName,
              bio: row['bio']?.toString().trim() ?? '',
              city: (row['city']?.toString().trim().isNotEmpty ?? false)
                  ? row['city'].toString()
                  : widget.fallbackCity,
              avatarUrl: (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null,
              runnerLevel: level,
              totalXp: xp,
              weeklyDistanceKm: (row['weekly_distance_km'] as num?)?.toDouble() ?? 0.0,
              weeklyRunsCount: (row['weekly_runs_count'] as num?)?.toInt() ?? 0,
              totalDistanceKm: totalDist,
              totalRunsCount: totalRuns,
              totalCalories: (row['total_calories'] as num?)?.toDouble() ?? 0.0,
              longestRunKm: (row['longest_run_km'] as num?)?.toDouble() ?? 0.0,
            );
          } else {
            _profile = _buildFallbackProfile();
          }
          _friendRelation = relation;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _profile = _buildFallbackProfile();
          _isLoading = false;
        });
      }
    }
  }

  _RunnerFullProfile _buildFallbackProfile() {
    final lvl = widget.fallbackLevel.clamp(1, 999);
    return _RunnerFullProfile(
      userId: widget.userId,
      displayName: widget.fallbackName,
      bio: '',
      city: widget.fallbackCity,
      runnerLevel: lvl,
      totalXp: (lvl - 1) * RunnerStats.xpPerLevel,
      weeklyDistanceKm: 0,
      weeklyRunsCount: 0,
      totalDistanceKm: 0,
      totalRunsCount: 0,
      totalCalories: 0,
      longestRunKm: 0,
    );
  }

  List<_MiniBadge> _unlockedBadges(_RunnerFullProfile p) {
    return [
      if (p.totalRunsCount >= 1) const _MiniBadge('First Stride', Icons.directions_run, AppColors.primaryOrange),
      if (p.longestRunKm >= 5.0) const _MiniBadge('5K Finisher', Icons.military_tech, AppColors.accentBlue),
      if (p.longestRunKm >= 10.0) const _MiniBadge('10K Warrior', Icons.emoji_events, Colors.amber),
      if (p.totalCalories >= 1000) const _MiniBadge('Calorie Burner', Icons.local_fire_department, Colors.deepOrangeAccent),
      if (p.totalRunsCount >= 5) const _MiniBadge('Consistent 5', Icons.repeat, Colors.tealAccent),
      if (p.totalDistanceKm >= 21.1) const _MiniBadge('Half Marathoner', Icons.workspace_premium, Colors.pinkAccent),
    ];
  }

  Future<void> _handleFriendAction() async {
    if (_isBusyFriendAction || !AuthService.isLoggedIn || _isSelf) return;
    final relation = _friendRelation;
    final status = relation?.status ?? FriendRelationStatus.none;

    setState(() => _isBusyFriendAction = true);
    try {
      if (status == FriendRelationStatus.none) {
        await _friendsService.sendFriendRequest(widget.userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Permintaan pertemanan dikirim ke ${_profile?.displayName ?? widget.fallbackName}!'),
              backgroundColor: AppColors.cardElevated,
            ),
          );
        }
      } else if (status == FriendRelationStatus.pendingIncoming && relation != null) {
        await _friendsService.acceptFriendRequest(relation.friendshipId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sekarang Anda berteman dengan ${_profile?.displayName ?? widget.fallbackName}!'),
              backgroundColor: AppColors.cardElevated,
            ),
          );
        }
      }
      await _loadProfile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memproses pertemanan: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusyFriendAction = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
        child: _isLoading || _profile == null
            ? const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator(color: AppColors.primaryOrange)),
              )
            : _buildContent(_profile!),
      ),
    );
  }

  Widget _buildContent(_RunnerFullProfile p) {
    final rankTitle = RunnerStats.rankTitleForLevel(
      p.runnerLevel,
      hasActivity: p.totalRunsCount > 0 || p.totalXp > 0,
    );
    final levelProgress = (p.totalXp % RunnerStats.xpPerLevel) / RunnerStats.xpPerLevel;
    final unlocked = _unlockedBadges(p);
    final status = _friendRelation?.status ?? FriendRelationStatus.none;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),

          // Header Profil
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primaryOrange, width: 2),
                ),
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.cardElevated,
                  backgroundImage: p.avatarUrl != null ? NetworkImage(p.avatarUrl!) : null,
                  child: p.avatarUrl == null
                      ? Text(
                          p.displayName.trim().isNotEmpty ? p.displayName.trim()[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _isSelf ? '${p.displayName} (Anda)' : p.displayName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Lv.${p.runnerLevel}',
                            style: const TextStyle(color: Colors.amber, fontSize: 10.5, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      rankTitle,
                      style: const TextStyle(
                        color: AppColors.primaryOrange,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 12.5, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            p.city,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (p.bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.backgroundDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                '"${p.bio}"',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontStyle: FontStyle.italic),
              ),
            ),
          ],

          const SizedBox(height: 14),
          // Progress Level & XP
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Level ${p.runnerLevel} Progress', style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
              Text('${p.totalXp} XP', style: const TextStyle(color: AppColors.primaryOrange, fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: levelProgress,
              minHeight: 7,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryOrange),
            ),
          ),

          const SizedBox(height: 16),
          // Grid Statistik 2x2
          Row(
            children: [
              _buildStatBox('Minggu Ini', '${p.weeklyDistanceKm.toStringAsFixed(1)} km', '${p.weeklyRunsCount} sesi', AppColors.primaryOrange),
              const SizedBox(width: 10),
              _buildStatBox('Total Jarak', '${p.totalDistanceKm.toStringAsFixed(1)} km', '${p.totalRunsCount} sesi', AppColors.accentBlue),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildStatBox('Lari Terjauh', '${p.longestRunKm.toStringAsFixed(2)} km', 'Personal Best', AppColors.accentGreen),
              const SizedBox(width: 10),
              _buildStatBox('Kalori Total', '${p.totalCalories.toStringAsFixed(0)} kcal', 'Sepanjang masa', Colors.amber),
            ],
          ),

          const SizedBox(height: 16),
          // Lencana Pencapaian Terbuka
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Lencana Terbuka', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
              Text('${unlocked.length} / 6', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 8),
          if (unlocked.isEmpty)
            const Text(
              'Pelari ini baru memulai perjalanannya dan belum membuka lencana.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: unlocked.map((b) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: b.color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: b.color.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(b.icon, size: 14, color: b.color),
                      const SizedBox(width: 5),
                      Text(
                        b.label,
                        style: TextStyle(color: b.color, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),

          if (!_isSelf && AuthService.isLoggedIn) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: _buildFriendActionButton(status),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, String value, String sub, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.backgroundDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: accent, fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendActionButton(FriendRelationStatus status) {
    if (status == FriendRelationStatus.accepted) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.accentGreen),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: null,
        icon: const Icon(Icons.how_to_reg, color: AppColors.accentGreen, size: 18),
        label: const Text('Sudah Berteman ✓', style: TextStyle(color: AppColors.accentGreen, fontWeight: FontWeight.bold)),
      );
    }

    if (status == FriendRelationStatus.pendingOutgoing) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.amber),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: null,
        icon: const Icon(Icons.hourglass_top_rounded, color: Colors.amber, size: 17),
        label: const Text('Permintaan Terkirim (Menunggu)', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
      );
    }

    final isIncoming = status == FriendRelationStatus.pendingIncoming;
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: isIncoming ? AppColors.accentGreen : AppColors.primaryOrange,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: _isBusyFriendAction ? null : _handleFriendAction,
      icon: _isBusyFriendAction
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(isIncoming ? Icons.check_circle_outline : Icons.person_add_alt_1, color: isIncoming ? Colors.black : Colors.white, size: 18),
      label: Text(
        isIncoming ? 'Terima Permintaan Pertemanan' : 'Tambah sebagai Teman',
        style: TextStyle(color: isIncoming ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}
