import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/profile_storage_service.dart';
import '../../../core/services/run_storage_service.dart';
import '../domain/run_model.dart';

class _ChallengeItem {
  final String id;
  final String title;
  final String description;
  final String badgeText;
  final double targetValue;
  final String unit; // 'km', 'single_km', 'runs', 'kcal'
  final int baseParticipants;
  final IconData icon;
  final Color accentColor;

  const _ChallengeItem({
    required this.id,
    required this.title,
    required this.description,
    required this.badgeText,
    required this.targetValue,
    required this.unit,
    required this.baseParticipants,
    required this.icon,
    required this.accentColor,
  });
}

class _ClubMember {
  final String name;
  final double weeklyKm;
  final int runsCount;
  final bool isCurrentUser;
  final String? avatarPath;

  const _ClubMember({
    required this.name,
    required this.weeklyKm,
    required this.runsCount,
    this.isCurrentUser = false,
    this.avatarPath,
  });
}

class _RunningClub {
  final String id;
  final String name;
  final String location;
  final String description;
  final String schedule;
  final int baseMembers;
  final IconData icon;
  final Color color;
  final List<_ClubMember> simulatedMembers;

  const _RunningClub({
    required this.id,
    required this.name,
    required this.location,
    required this.description,
    required this.schedule,
    required this.baseMembers,
    required this.icon,
    required this.color,
    required this.simulatedMembers,
  });
}

class _CommunityEvent {
  final String id;
  final String title;
  final String dateStr;
  final String location;
  final String distanceTag;
  final String paceGroup;
  final String description;
  final int baseAttendees;

  const _CommunityEvent({
    required this.id,
    required this.title,
    required this.dateStr,
    required this.location,
    required this.distanceTag,
    required this.paceGroup,
    required this.description,
    required this.baseAttendees,
  });
}

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final RunStorageService _runService = RunStorageService();
  final ProfileStorageService _profileService = ProfileStorageService();

  static const String _prefJoinedChallenges = 'joined_challenges_ids';
  static const String _prefJoinedClubs = 'joined_clubs_ids';
  static const String _prefRsvpEvents = 'rsvp_events_ids';

  List<RunModel> _savedRuns = [];
  UserProfileData _profile = const UserProfileData(
    name: 'Pelari Adventure',
    bio: '',
    city: 'Jatinangor, Indonesia',
    weightKg: 65.0,
    weeklyGoalKm: 15.0,
  );

  Set<String> _joinedChallengeIds = {};
  Set<String> _joinedClubIds = {};
  Set<String> _rsvpEventIds = {};
  bool _isLoading = true;

  final List<_ChallengeItem> _challenges = const [
    _ChallengeItem(
      id: 'ch_monthly_25k',
      title: 'Jatinangor 25K Endurance',
      description: 'Kumpulkan total jarak lari 25 km dari seluruh sesi rekamanmu.',
      badgeText: 'ENDURANCE 25K',
      targetValue: 25.0,
      unit: 'km',
      baseParticipants: 1240,
      icon: Icons.military_tech,
      accentColor: AppColors.primaryOrange,
    ),
    _ChallengeItem(
      id: 'ch_single_5k',
      title: '5K Finisher Challenge',
      description: 'Selesaikan minimal 5 km dalam satu kali sesi lari tanpa henti.',
      badgeText: '5K MILESTONE',
      targetValue: 5.0,
      unit: 'single_km',
      baseParticipants: 2180,
      icon: Icons.bolt,
      accentColor: AppColors.accentBlue,
    ),
    _ChallengeItem(
      id: 'ch_consistency_5',
      title: '5x Active Runner Streak',
      description: 'Selesaikan minimal 5 sesi lari yang tercatat di riwayat aktivitas.',
      badgeText: 'CONSISTENCY',
      targetValue: 5.0,
      unit: 'runs',
      baseParticipants: 945,
      icon: Icons.local_fire_department,
      accentColor: AppColors.accentGreen,
    ),
    _ChallengeItem(
      id: 'ch_calorie_1500',
      title: '1,500 kcal Burn Target',
      description: 'Bakar total 1.500 kalori dari aktivitas lari maupun trail.',
      badgeText: 'CALORIE BURN',
      targetValue: 1500.0,
      unit: 'kcal',
      baseParticipants: 780,
      icon: Icons.whatshot,
      accentColor: Colors.amber,
    ),
  ];

  final List<_RunningClub> _clubs = const [
    _RunningClub(
      id: 'club_sumedang',
      name: 'Runner Club Sumedang',
      location: 'Jatinangor & Sumedang',
      description: 'Komunitas lari terbuka untuk mahasiswa dan warga kawasan Jatinangor–Sumedang.',
      schedule: 'Rabu 19:30 & Minggu 06:00',
      baseMembers: 117,
      icon: Icons.directions_run,
      color: AppColors.primaryOrange,
      simulatedMembers: [
        _ClubMember(name: 'Raka Pratama', weeklyKm: 24.5, runsCount: 5),
        _ClubMember(name: 'Nadia Putri', weeklyKm: 18.2, runsCount: 4),
        _ClubMember(name: 'Dimas Saputra', weeklyKm: 12.0, runsCount: 3),
        _ClubMember(name: 'Fajar Nugroho', weeklyKm: 6.4, runsCount: 2),
        _ClubMember(name: 'Salsa Maharani', weeklyKm: 3.1, runsCount: 1),
      ],
    ),
    _RunningClub(
      id: 'club_manglayang',
      name: 'Bandung Timur Trail Runners',
      location: 'Cileunyi & Kaki Manglayang',
      description: 'Fokus latihan elevasi, lari lintas alam, dan persiapan trail run Jawa Barat.',
      schedule: 'Sabtu 06:15 • Basecamp Manglayang',
      baseMembers: 430,
      icon: Icons.terrain,
      color: AppColors.accentGreen,
      simulatedMembers: [
        _ClubMember(name: 'Bagas Wicaksono', weeklyKm: 34.8, runsCount: 6),
        _ClubMember(name: 'Tari Anggraini', weeklyKm: 21.0, runsCount: 4),
        _ClubMember(name: 'Reza Kurniawan', weeklyKm: 14.5, runsCount: 3),
        _ClubMember(name: 'Kevin Wijaya', weeklyKm: 7.5, runsCount: 2),
      ],
    ),
    _RunningClub(
      id: 'club_campus_pacer',
      name: 'Unpad Morning Pacer',
      location: 'Kawasan Kampus Jatinangor',
      description: 'Grup lari pagi santai sebelum kuliah dengan berbagai kelompok pace (5:30 – 7:30/km).',
      schedule: 'Selasa & Jumat • 05:45 WIB',
      baseMembers: 264,
      icon: Icons.speed,
      color: AppColors.accentBlue,
      simulatedMembers: [
        _ClubMember(name: 'Alvin Hendrawan', weeklyKm: 19.6, runsCount: 5),
        _ClubMember(name: 'Citra Lestari', weeklyKm: 15.1, runsCount: 4),
        _ClubMember(name: 'Gilang Ramadhan', weeklyKm: 9.8, runsCount: 2),
        _ClubMember(name: 'Hana Pertiwi', weeklyKm: 4.2, runsCount: 1),
      ],
    ),
  ];

  final List<_CommunityEvent> _events = const [
    _CommunityEvent(
      id: 'ev_jatinangor_night',
      title: 'Jatinangor Loop Night Run 5K',
      dateStr: 'Sabtu, 21 Nov 2026 • 19:30 WIB',
      location: 'Gerbang Utama Unpad, Jatinangor',
      distanceTag: '5.0 KM',
      paceGroup: 'All Pace (6:00 - 7:30 /km)',
      description: 'Lari malam santai bersama komunitas lokal mengelilingi rute utama Jatinangor. Gratis hidrasi di titik finish.',
      baseAttendees: 84,
    ),
    _CommunityEvent(
      id: 'ev_siliwangi_sunday',
      title: 'Siliwangi Sunday Morning 10K',
      dateStr: 'Minggu, 29 Nov 2026 • 06:00 WIB',
      location: 'Stadion Siliwangi, Bandung',
      distanceTag: '10.0 KM',
      paceGroup: 'Tempo & Endurance',
      description: 'Latihan long run akhir pekan bersama pacer berpengalaman untuk persiapan lomba 10K.',
      baseAttendees: 142,
    ),
    _CommunityEvent(
      id: 'ev_manglayang_funtrail',
      title: 'Manglayang Sunrise Fun Trail',
      dateStr: 'Minggu, 6 Des 2026 • 06:15 WIB',
      location: 'Pos Pendakian Barubereum, Cileunyi',
      distanceTag: '6.5 KM',
      paceGroup: 'Trail / Elevasi +240m',
      description: 'Eksplorasi jalur tanah dan kebun pinus kaki Gunung Manglayang dengan pemandangan matahari terbit.',
      baseAttendees: 59,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadAllData();
    ProfileStorageService.profileUpdateNotifier.addListener(_loadAllData);
  }

  @override
  void dispose() {
    ProfileStorageService.profileUpdateNotifier.removeListener(_loadAllData);
    super.dispose();
  }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final runs = await _runService.getSavedRuns();
    final profile = await _profileService.getProfile();

    if (mounted) {
      setState(() {
        _savedRuns = runs;
        _profile = profile;
        _joinedChallengeIds = (prefs.getStringList(_prefJoinedChallenges) ?? ['ch_monthly_25k']).toSet();
        _joinedClubIds = (prefs.getStringList(_prefJoinedClubs) ?? ['club_sumedang']).toSet();
        _rsvpEventIds = (prefs.getStringList(_prefRsvpEvents) ?? []).toSet();
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleChallenge(String id) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_joinedChallengeIds.contains(id)) {
        _joinedChallengeIds.remove(id);
      } else {
        _joinedChallengeIds.add(id);
      }
    });
    await prefs.setStringList(_prefJoinedChallenges, _joinedChallengeIds.toList());
  }

  Future<void> _toggleClub(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final joining = !_joinedClubIds.contains(id);
    setState(() {
      if (joining) {
        _joinedClubIds.add(id);
      } else {
        _joinedClubIds.remove(id);
      }
    });
    await prefs.setStringList(_prefJoinedClubs, _joinedClubIds.toList());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(joining ? 'Berhasil bergabung dengan klub!' : 'Keluar dari klub'),
          backgroundColor: AppColors.cardElevated,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleEventRsvp(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final attending = !_rsvpEventIds.contains(id);
    setState(() {
      if (attending) {
        _rsvpEventIds.add(id);
      } else {
        _rsvpEventIds.remove(id);
      }
    });
    await prefs.setStringList(_prefRsvpEvents, _rsvpEventIds.toList());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(attending ? 'Kehadiran dikonfirmasi! Sampai jumpa di garis start.' : 'RSVP acara dibatalkan'),
          backgroundColor: AppColors.cardElevated,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // --- HITUNG PROGRES NYATA USER UNTUK SETIAP TANTANGAN ---
  double get _totalDistance => _savedRuns.fold(0.0, (s, r) => s + r.distanceInKm);
  double get _longestSingleKm => _savedRuns.isEmpty ? 0.0 : _savedRuns.map((r) => r.distanceInKm).reduce(math.max);
  double get _totalCalories => _savedRuns.fold(0.0, (s, r) => s + r.calories);

  double _getCurrentProgressValue(_ChallengeItem item) {
    switch (item.unit) {
      case 'km':
        return _totalDistance;
      case 'single_km':
        return _longestSingleKm;
      case 'runs':
        return _savedRuns.length.toDouble();
      case 'kcal':
        return _totalCalories;
      default:
        return 0.0;
    }
  }

  String _formatProgressText(_ChallengeItem item, double currentVal) {
    if (item.unit == 'runs') {
      return '${currentVal.toInt()} / ${item.targetValue.toInt()} sesi';
    }
    if (item.unit == 'kcal') {
      return '${currentVal.toStringAsFixed(0)} / ${item.targetValue.toStringAsFixed(0)} kcal';
    }
    return '${currentVal.toStringAsFixed(1)} / ${item.targetValue.toStringAsFixed(0)} km';
  }

  // --- BOTTOM SHEET LEADERBOARD KLUB (MENGGABUNGKAN USER ASLI + ANGGOTA KLUB) ---
  void _showClubLeaderboardSheet(_RunningClub club) {
    final isJoined = _joinedClubIds.contains(club.id);

    // Gabungkan data asli user ke dalam leaderboard klub
    final List<_ClubMember> allMembers = [
      ...club.simulatedMembers,
      _ClubMember(
        name: '${_profile.name} (Anda)',
        weeklyKm: _totalDistance,
        runsCount: _savedRuns.length,
        isCurrentUser: true,
        avatarPath: _profile.avatarPath,
      ),
    ];

    allMembers.sort((a, b) => b.weeklyKm.compareTo(a.weeklyKm));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
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
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: club.color.withOpacity(0.2),
                    child: Icon(club.icon, color: club.color, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(club.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text(club.schedule, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(club.description, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Papan Peringkat Jarak Klub', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                  Text('Live Sync', style: TextStyle(color: AppColors.accentGreen, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: allMembers.length,
                  itemBuilder: (_, idx) {
                    final member = allMembers[idx];
                    final rank = idx + 1;
                    final hasAvatar = member.avatarPath != null;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: member.isCurrentUser
                            ? AppColors.primaryOrange.withOpacity(0.18)
                            : AppColors.backgroundDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: member.isCurrentUser ? AppColors.primaryOrange : Colors.white10,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 26,
                            child: Text(
                              '#$rank',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                color: rank == 1
                                    ? Colors.amber
                                    : rank == 2
                                        ? Colors.grey.shade300
                                        : rank == 3
                                            ? Colors.orange.shade300
                                            : AppColors.textSecondary,
                              ),
                            ),
                          ),
                          CircleAvatar(
                            radius: 17,
                            backgroundColor: AppColors.cardElevated,
                            backgroundImage: hasAvatar ? FileImage(File(member.avatarPath!)) : null,
                            child: !hasAvatar
                                ? Text(
                                    member.name[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.name,
                                  style: TextStyle(
                                    fontWeight: member.isCurrentUser ? FontWeight.bold : FontWeight.w600,
                                    color: Colors.white,
                                    fontSize: 13.5,
                                  ),
                                ),
                                Text(
                                  '${member.runsCount} sesi aktivitas',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${member.weeklyKm.toStringAsFixed(1)} km',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: member.isCurrentUser ? AppColors.primaryOrange : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isJoined ? AppColors.cardElevated : club.color,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _toggleClub(club.id);
                  },
                  child: Text(
                    isJoined ? 'Keluar dari Klub' : 'Gabung Klub Sekarang',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: AppBar(
          title: const Text('GRUP & KOMUNITAS', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 16)),
          backgroundColor: AppColors.backgroundDark,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: 'Sinkronisasi Progres',
              icon: const Icon(Icons.sync, color: Colors.white70),
              onPressed: _loadAllData,
            ),
          ],
          bottom: const TabBar(
            indicatorColor: AppColors.primaryOrange,
            indicatorWeight: 3,
            labelColor: AppColors.primaryOrange,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              Tab(text: 'Tantangan'),
              Tab(text: 'Klub'),
              Tab(text: 'Acara'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
            : TabBarView(
                children: [
                  _buildChallengesTab(),
                  _buildClubsTab(),
                  _buildEventsTab(),
                ],
              ),
      ),
    );
  }

  // --- TAB 1: TANTANGAN DENGAN PROGRES ASLI ---
  Widget _buildChallengesTab() {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: AppColors.primaryOrange,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _challenges.length,
        itemBuilder: (context, index) {
          final ch = _challenges[index];
          final isJoined = _joinedChallengeIds.contains(ch.id);
          final currentVal = _getCurrentProgressValue(ch);
          final ratio = (currentVal / ch.targetValue).clamp(0.0, 1.0);
          final isCompleted = ratio >= 1.0;

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCompleted
                    ? AppColors.accentGreen.withOpacity(0.6)
                    : isJoined
                        ? ch.accentColor.withOpacity(0.4)
                        : Colors.white10,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: ch.accentColor.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(ch.icon, color: ch.accentColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ch.badgeText,
                            style: TextStyle(
                              color: ch.accentColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ch.title,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    if (isCompleted)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accentGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'SELESAI',
                          style: TextStyle(color: AppColors.accentGreen, fontSize: 10, fontWeight: FontWeight.w900),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(ch.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 14),

                // Progress bar progres nyata user
                if (isJoined) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progres Anda: ${_formatProgressText(ch, currentVal)}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${(ratio * 100).toInt()}%',
                        style: TextStyle(color: ch.accentColor, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 7,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isCompleted ? AppColors.accentGreen : ch.accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.people_outline, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 5),
                        Text(
                          '${ch.baseParticipants + (isJoined ? 1 : 0)} Peserta',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: isJoined ? Colors.transparent : ch.accentColor,
                        side: BorderSide(color: isJoined ? Colors.white24 : ch.accentColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      ),
                      onPressed: () => _toggleChallenge(ch.id),
                      child: Text(
                        isJoined ? 'Diikuti ✓' : 'Gabung Tantangan',
                        style: TextStyle(
                          color: isJoined ? Colors.white70 : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- TAB 2: KLUB + LEADERBOARD ---
  Widget _buildClubsTab() {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: AppColors.primaryOrange,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _clubs.length,
        itemBuilder: (context, index) {
          final club = _clubs[index];
          final isJoined = _joinedClubIds.contains(club.id);

          return GestureDetector(
            onTap: () => _showClubLeaderboardSheet(club),
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isJoined ? club.color.withOpacity(0.45) : Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: club.color.withOpacity(0.18),
                        child: Icon(club.icon, color: club.color, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              club.name,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${club.location} • ${club.baseMembers + (isJoined ? 1 : 0)} Anggota',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.leaderboard, color: club.color, size: 20),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(club.description, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.schedule, size: 14, color: AppColors.primaryOrange),
                          const SizedBox(width: 5),
                          Text(club.schedule, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                        ],
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isJoined ? AppColors.cardElevated : club.color,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _toggleClub(club.id),
                        child: Text(
                          isJoined ? 'Anggota ✓' : 'Gabung',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- TAB 3: ACARA KOMUNITAS + RSVP ---
  Widget _buildEventsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _events.length,
      itemBuilder: (context, index) {
        final ev = _events[index];
        final isAttending = _rsvpEventIds.contains(ev.id);

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isAttending ? AppColors.accentGreen.withOpacity(0.5) : Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryOrange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ev.distanceTag,
                      style: const TextStyle(color: AppColors.primaryOrange, fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    ev.paceGroup,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(ev.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 13, color: AppColors.primaryOrange),
                  const SizedBox(width: 6),
                  Text(ev.dateStr, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 13, color: AppColors.accentBlue),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(ev.location, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(ev.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 14),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people, size: 16, color: AppColors.primaryOrange),
                      const SizedBox(width: 6),
                      Text(
                        '${ev.baseAttendees + (isAttending ? 1 : 0)} Pelari Hadir',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isAttending ? AppColors.accentGreen.withOpacity(0.2) : AppColors.primaryOrange,
                      side: isAttending ? const BorderSide(color: AppColors.accentGreen) : BorderSide.none,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    onPressed: () => _toggleEventRsvp(ev.id),
                    icon: Icon(
                      isAttending ? Icons.check_circle : Icons.event_available,
                      size: 16,
                      color: isAttending ? AppColors.accentGreen : Colors.white,
                    ),
                    label: Text(
                      isAttending ? 'Terdaftar' : 'Ikut Acara',
                      style: TextStyle(
                        color: isAttending ? AppColors.accentGreen : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}