import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/community_service.dart';
import '../../../core/services/profile_storage_service.dart';
import '../../../core/services/run_storage_service.dart';
import '../../auth/presentation/login_screen.dart';
import '../data/community_seed_data.dart';
import '../domain/run_model.dart';
import '../domain/runner_stats.dart';
import 'club_detail_screen.dart';
import 'event_detail_screen.dart';
import 'friends_tab_view.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final RunStorageService _runService = RunStorageService();
  final ProfileStorageService _profileService = ProfileStorageService();
  final CommunityService _communityService = CommunityService();

  static const String _prefJoinedChallenges = 'joined_challenges_ids';
  static const String _prefClaimedChallenges = 'claimed_challenges_ids';
  static const String _prefJoinedClubs = 'joined_clubs_ids';
  static const String _prefRsvpEvents = 'rsvp_events_ids';

  List<RunModel> _savedRuns = [];
  UserProfileData _profile = UserProfileData.defaultProfile;

  // Data online (Supabase)
  bool _isOnlineMode = false;
  bool _needsSchemaSetup = false;
  String? _statusMessage;
  List<OnlineChallenge> _onlineChallenges = [];
  List<OnlineClub> _onlineClubs = [];
  List<OnlineEvent> _onlineEvents = [];

  // Fallback offline lokal
  Set<String> _localJoinedChallengeIds = {};
  Set<String> _localClaimedChallengeIds = {};
  Set<String> _localJoinedClubIds = {};
  Set<String> _localRsvpEventIds = {};

  bool _isLoading = true;
  String? _claimingChallengeId;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    ProfileStorageService.profileUpdateNotifier.addListener(_loadAllData);
    RunStorageService.runUpdateNotifier.addListener(_loadAllData);
    AuthService.authStateNotifier.addListener(_loadAllData);
  }

  @override
  void dispose() {
    ProfileStorageService.profileUpdateNotifier.removeListener(_loadAllData);
    RunStorageService.runUpdateNotifier.removeListener(_loadAllData);
    AuthService.authStateNotifier.removeListener(_loadAllData);
    super.dispose();
  }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final runs = await _runService.getSavedRuns();
    final profile = await _profileService.getProfile();
    final snapshot = await _communityService.fetchCommunitySnapshot();

    if (!mounted) return;
    setState(() {
      _savedRuns = runs;
      _profile = profile;
      _isOnlineMode = snapshot.isOnline;
      _needsSchemaSetup = snapshot.needsSchemaSetup;
      _statusMessage = snapshot.statusMessage;
      _onlineChallenges = snapshot.challenges;
      _onlineClubs = snapshot.clubs;
      _onlineEvents = snapshot.events;
      _localJoinedChallengeIds =
          (prefs.getStringList(_prefJoinedChallenges) ?? ['ch_starter_1k']).toSet();
      _localClaimedChallengeIds = (prefs.getStringList(_prefClaimedChallenges) ?? []).toSet();
      _localJoinedClubIds = (prefs.getStringList(_prefJoinedClubs) ?? ['club_sumedang']).toSet();
      _localRsvpEventIds = (prefs.getStringList(_prefRsvpEvents) ?? []).toSet();
      _isLoading = false;
    });
  }

  Future<bool> _ensureLoggedInForOnlineAction() async {
    if (AuthService.isLoggedIn) return true;
    final didLogin = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (didLogin == true) {
      await _loadAllData();
      return AuthService.isLoggedIn;
    }
    return false;
  }

  // --- HITUNG PROGRES NYATA & LEVEL GAMIFIKASI USER ---
  double get _totalDistance => RunnerStats.totalDistance(_savedRuns);
  double get _longestSingleKm =>
      _savedRuns.isEmpty ? 0.0 : _savedRuns.map((r) => r.distanceInKm).reduce(math.max);
  double get _totalCalories => RunnerStats.totalCalories(_savedRuns);
  int get _userTotalXp => RunnerStats.totalXp(_savedRuns, bonusXp: _profile.bonusXp);
  int get _userLevel => RunnerStats.runnerLevel(_savedRuns, bonusXp: _profile.bonusXp);
  double get _userLevelProgress => RunnerStats.levelProgress(_savedRuns, bonusXp: _profile.bonusXp);
  String get _userRank => RunnerStats.rankTitle(_savedRuns, bonusXp: _profile.bonusXp);

  double _getCurrentProgressValue(String unit) {
    switch (unit) {
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

  String _formatProgressText(String unit, double targetValue, double currentVal) {
    if (unit == 'runs') {
      return '${currentVal.toInt()} / ${targetValue.toInt()} sesi';
    }
    if (unit == 'kcal') {
      return '${currentVal.toStringAsFixed(0)} / ${targetValue.toStringAsFixed(0)} kcal';
    }
    return '${currentVal.toStringAsFixed(1)} / ${targetValue.toStringAsFixed(0)} km';
  }

  // --- AKSI TANTANGAN (LEVEL GATING + KLAIM BONUS XP) ---
  Future<void> _handleToggleOnlineChallenge(OnlineChallenge ch) async {
    if (!ch.isJoined && !RunnerStats.meetsLevelRequirement(userLevel: _userLevel, minLevel: ch.minLevel)) {
      final xpMissing = RunnerStats.xpNeededForLevel(ch.minLevel, _userTotalXp);
      _showSnack('Terkunci! Capai Level ${ch.minLevel} (kurang $xpMissing XP) untuk ikut tantangan ini.', isError: true);
      return;
    }
    if (!await _ensureLoggedInForOnlineAction()) return;
    try {
      await _communityService.toggleChallenge(
        ch.id,
        currentlyJoined: ch.isJoined,
        userLevel: _userLevel,
        minLevel: ch.minLevel,
      );
      await _loadAllData();
    } catch (e) {
      _showSnack('Gagal memperbarui tantangan: $e', isError: true);
    }
  }

  Future<void> _handleClaimOnlineChallengeReward(OnlineChallenge ch) async {
    if (_claimingChallengeId != null) return;
    if (!await _ensureLoggedInForOnlineAction()) return;

    final oldLevel = _userLevel;
    setState(() => _claimingChallengeId = ch.id);
    try {
      await _communityService.claimChallengeReward(
        challengeId: ch.id,
        xpReward: ch.xpReward,
      );
      await _loadAllData();
      if (mounted) {
        _showRewardClaimedDialog(
          challengeTitle: ch.title,
          xpReward: ch.xpReward,
          leveledUp: _userLevel > oldLevel,
          newLevel: _userLevel,
        );
      }
    } catch (e) {
      _showSnack('Gagal klaim hadiah XP: $e', isError: true);
    } finally {
      if (mounted) setState(() => _claimingChallengeId = null);
    }
  }

  Future<void> _handleToggleOfflineChallenge(ChallengeItem ch) async {
    final isJoined = _localJoinedChallengeIds.contains(ch.id);
    if (!isJoined && !RunnerStats.meetsLevelRequirement(userLevel: _userLevel, minLevel: ch.minLevel)) {
      final xpMissing = RunnerStats.xpNeededForLevel(ch.minLevel, _userTotalXp);
      _showSnack('Terkunci! Capai Level ${ch.minLevel} (kurang $xpMissing XP) untuk ikut tantangan ini.', isError: true);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (isJoined) {
        _localJoinedChallengeIds.remove(ch.id);
      } else {
        _localJoinedChallengeIds.add(ch.id);
      }
    });
    await prefs.setStringList(_prefJoinedChallenges, _localJoinedChallengeIds.toList());
  }

  Future<void> _handleClaimOfflineChallengeReward(ChallengeItem ch) async {
    if (_localClaimedChallengeIds.contains(ch.id)) return;
    final oldLevel = _userLevel;
    final prefs = await SharedPreferences.getInstance();
    _localClaimedChallengeIds.add(ch.id);
    await prefs.setStringList(_prefClaimedChallenges, _localClaimedChallengeIds.toList());
    await _profileService.addBonusXp(ch.xpReward);
    await _loadAllData();
    if (mounted) {
      _showRewardClaimedDialog(
        challengeTitle: ch.title,
        xpReward: ch.xpReward,
        leveledUp: _userLevel > oldLevel,
        newLevel: _userLevel,
      );
    }
  }

  void _showRewardClaimedDialog({
    required String challengeTitle,
    required int xpReward,
    required bool leveledUp,
    required int newLevel,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (leveledUp ? AppColors.primaryOrange : Colors.amber).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                leveledUp ? Icons.emoji_events : Icons.bolt,
                color: leveledUp ? AppColors.primaryOrange : Colors.amber,
                size: 38,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              leveledUp ? 'LEVEL UP • LEVEL $newLevel!' : 'HADIAH XP DIKLAIM!',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              '+$xpReward XP dari "$challengeTitle"',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(height: 6),
            Text(
              leveledUp
                  ? 'Selamat! Rank Anda sekarang $_userRank. Tantangan & akses tier baru kini terbuka!'
                  : 'Total XP Anda sekarang $_userTotalXp XP (Level $_userLevel). Terus berlari!',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mantap!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // --- AKSI KLUB (LEVEL GATING) ---
  Future<void> _handleToggleOnlineClub(OnlineClub club) async {
    if (!club.isJoined && !RunnerStats.meetsLevelRequirement(userLevel: _userLevel, minLevel: club.minLevel)) {
      final xpMissing = RunnerStats.xpNeededForLevel(club.minLevel, _userTotalXp);
      _showSnack('Terkunci! Capai Level ${club.minLevel} (kurang $xpMissing XP) untuk bergabung dengan klub ini.', isError: true);
      return;
    }
    if (!await _ensureLoggedInForOnlineAction()) return;
    try {
      final joining = !club.isJoined;
      await _communityService.toggleClub(
        club.id,
        currentlyJoined: club.isJoined,
        userLevel: _userLevel,
        minLevel: club.minLevel,
      );
      await _loadAllData();
      _showSnack(joining ? 'Berhasil bergabung dengan ${club.name}! Obrolan klub kini terbuka.' : 'Keluar dari ${club.name}');
    } catch (e) {
      _showSnack('Gagal memperbarui keanggotaan klub: $e', isError: true);
    }
  }

  Future<void> _handleToggleOfflineClub(RunningClub club) async {
    final isJoined = _localJoinedClubIds.contains(club.id);
    if (!isJoined && !RunnerStats.meetsLevelRequirement(userLevel: _userLevel, minLevel: club.minLevel)) {
      final xpMissing = RunnerStats.xpNeededForLevel(club.minLevel, _userTotalXp);
      _showSnack('Terkunci! Capai Level ${club.minLevel} (kurang $xpMissing XP) untuk bergabung.', isError: true);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final joining = !isJoined;
    setState(() {
      if (joining) {
        _localJoinedClubIds.add(club.id);
      } else {
        _localJoinedClubIds.remove(club.id);
      }
    });
    await prefs.setStringList(_prefJoinedClubs, _localJoinedClubIds.toList());
    _showSnack(joining ? 'Berhasil bergabung dengan klub (offline).' : 'Keluar dari klub.');
  }

  // --- AKSI ACARA (SYARAT LEVEL + KUOTA PESERTA) ---
  Future<void> _handleToggleOnlineEvent(OnlineEvent ev) async {
    if (!ev.isAttending) {
      if (!RunnerStats.meetsLevelRequirement(userLevel: _userLevel, minLevel: ev.minLevel)) {
        final xpMissing = RunnerStats.xpNeededForLevel(ev.minLevel, _userTotalXp);
        _showSnack('Terkunci! Capai Level ${ev.minLevel} (kurang $xpMissing XP) untuk mengikuti acara ini.', isError: true);
        return;
      }
      if (ev.isFull) {
        _showSnack('Maaf, kuota peserta acara ini sudah penuh (${ev.maxParticipants}/${ev.maxParticipants}).', isError: true);
        return;
      }
    }
    if (!await _ensureLoggedInForOnlineAction()) return;
    try {
      final attending = !ev.isAttending;
      await _communityService.toggleEventRsvp(
        ev.id,
        currentlyAttending: ev.isAttending,
        userLevel: _userLevel,
        minLevel: ev.minLevel,
        currentAttendeesCount: ev.attendeesCount,
        maxParticipants: ev.maxParticipants,
      );
      await _loadAllData();
      _showSnack(attending ? 'Kehadiran dikonfirmasi! Ruang diskusi acara kini terbuka.' : 'RSVP acara dibatalkan.');
    } catch (e) {
      _showSnack('Gagal memperbarui RSVP: $e', isError: true);
    }
  }

  Future<void> _handleToggleOfflineEvent(CommunityEvent ev) async {
    final isAttending = _localRsvpEventIds.contains(ev.id);
    if (!isAttending) {
      if (!RunnerStats.meetsLevelRequirement(userLevel: _userLevel, minLevel: ev.minLevel)) {
        final xpMissing = RunnerStats.xpNeededForLevel(ev.minLevel, _userTotalXp);
        _showSnack('Terkunci! Capai Level ${ev.minLevel} (kurang $xpMissing XP) untuk mengikuti acara ini.', isError: true);
        return;
      }
      if (ev.baseAttendees >= ev.maxParticipants) {
        _showSnack('Maaf, kuota acara ini sudah penuh.', isError: true);
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final attending = !isAttending;
    setState(() {
      if (attending) {
        _localRsvpEventIds.add(ev.id);
      } else {
        _localRsvpEventIds.remove(ev.id);
      }
    });
    await prefs.setStringList(_prefRsvpEvents, _localRsvpEventIds.toList());
    _showSnack(attending ? 'Kehadiran dicatat secara lokal.' : 'RSVP dibatalkan.');
  }

  Future<void> _openOnlineEventDetail(OnlineEvent ev) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          event: ev,
          userLevel: _userLevel,
          userTotalXp: _userTotalXp,
          userAvatarPath: _profile.avatarPath,
        ),
      ),
    );
    if (changed == true) {
      await _loadAllData();
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : AppColors.cardElevated,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // --- BUAT KLUB ONLINE BARU ---
  Future<void> _showCreateClubSheet() async {
    if (!_isOnlineMode) {
      _showSnack('Hubungkan ke internet untuk membuat klub online.', isError: true);
      return;
    }
    if (!await _ensureLoggedInForOnlineAction()) return;
    if (!mounted) return;

    final nameCtrl = TextEditingController();
    final locCtrl = TextEditingController(text: _profile.city);
    final scheduleCtrl = TextEditingController(text: 'Minggu • 06:00 WIB');
    final descCtrl = TextEditingController();
    String selectedHex = '#FC4C02';
    int selectedMinLevel = 1;
    bool isSubmitting = false;

    const palette = ['#FC4C02', '#00E676', '#29B6F6', '#E040FB', '#FFC107'];
    const levelOptions = [1, 2, 3, 5, 8];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
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
                const Text('Buat Klub Lari Baru', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 14),
                _buildSheetField(nameCtrl, 'Nama Klub (contoh: Bandung Sub-50)', Icons.groups_outlined),
                const SizedBox(height: 10),
                _buildSheetField(locCtrl, 'Kota / Wilayah', Icons.location_on_outlined),
                const SizedBox(height: 10),
                _buildSheetField(scheduleCtrl, 'Jadwal Latihan', Icons.schedule_outlined),
                const SizedBox(height: 10),
                _buildSheetField(descCtrl, 'Deskripsi singkat klub', Icons.notes, maxLines: 2),
                const SizedBox(height: 12),
                Text(
                  'Syarat Level Minimal (Maks. Lv. $_userLevel sesuai level Anda)',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: levelOptions.map((lvl) {
                    final canSelect = lvl <= _userLevel;
                    final isSelected = selectedMinLevel == lvl;
                    return ChoiceChip(
                      label: Text(lvl == 1 ? 'Lv. 1 (Terbuka)' : 'Min. Lv. $lvl'),
                      selected: isSelected,
                      onSelected: canSelect ? (_) => setSheetState(() => selectedMinLevel = lvl) : null,
                      selectedColor: AppColors.primaryOrange,
                      backgroundColor: AppColors.backgroundDark,
                      disabledColor: Colors.white10,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : (canSelect ? Colors.white70 : Colors.white30),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                const Text('Warna Klub', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: palette.map((hex) {
                    final color = CommunityService.parseHexColor(hex);
                    final isSelected = selectedHex == hex;
                    return GestureDetector(
                      onTap: () => setSheetState(() => selectedHex = hex),
                      child: Container(
                        width: 32,
                        height: 32,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: isSelected ? Colors.white : Colors.transparent, width: 2.5),
                        ),
                        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryOrange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            if (nameCtrl.text.trim().isEmpty) return;
                            setSheetState(() => isSubmitting = true);
                            try {
                              await _communityService.createClub(
                                name: nameCtrl.text,
                                location: locCtrl.text.trim().isEmpty ? 'Indonesia' : locCtrl.text,
                                schedule: scheduleCtrl.text.trim().isEmpty ? 'Fleksibel' : scheduleCtrl.text,
                                description: descCtrl.text.trim().isEmpty
                                    ? 'Komunitas pelari Adventure Runner.'
                                    : descCtrl.text,
                                colorHex: selectedHex,
                                minLevel: selectedMinLevel,
                              );
                              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              await _loadAllData();
                              _showSnack('Klub "${nameCtrl.text.trim()}" berhasil dibuat!');
                            } catch (e) {
                              setSheetState(() => isSubmitting = false);
                              _showSnack('Gagal membuat klub: $e', isError: true);
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Buat Klub Sekarang', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    nameCtrl.dispose();
    locCtrl.dispose();
    scheduleCtrl.dispose();
    descCtrl.dispose();
  }

  // --- BUAT ACARA KOMUNITAS ONLINE BARU ---
  Future<void> _showCreateEventSheet() async {
    if (!_isOnlineMode) {
      _showSnack('Hubungkan ke internet untuk membuat acara komunitas online.', isError: true);
      return;
    }
    if (!await _ensureLoggedInForOnlineAction()) return;
    if (!mounted) return;

    final titleCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: 'Minggu • 06:00 WIB');
    final locCtrl = TextEditingController(text: _profile.city);
    final distCtrl = TextEditingController(text: '5.0 KM');
    final paceCtrl = TextEditingController(text: 'All Pace');
    final quotaCtrl = TextEditingController(text: '50');
    final descCtrl = TextEditingController();
    int selectedMinLevel = 1;
    bool isSubmitting = false;
    const levelOptions = [1, 2, 3, 5];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
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
                const Text('Buat Acara Lari Bersama', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 14),
                _buildSheetField(titleCtrl, 'Judul Acara (contoh: Sunday Fun Run 5K)', Icons.event_outlined),
                const SizedBox(height: 10),
                _buildSheetField(dateCtrl, 'Hari, Tanggal & Jam', Icons.calendar_today_outlined),
                const SizedBox(height: 10),
                _buildSheetField(locCtrl, 'Lokasi Titik Kumpul', Icons.location_on_outlined),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildSheetField(distCtrl, 'Jarak (5.0 KM)', Icons.straighten)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildSheetField(paceCtrl, 'Pace Group', Icons.speed)),
                  ],
                ),
                const SizedBox(height: 10),
                _buildSheetField(quotaCtrl, 'Kuota Maksimal Peserta (contoh: 50)', Icons.people_outline, isNumber: true),
                const SizedBox(height: 12),
                Text(
                  'Syarat Level Minimal (Maks. Lv. $_userLevel)',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: levelOptions.map((lvl) {
                    final canSelect = lvl <= _userLevel;
                    final isSelected = selectedMinLevel == lvl;
                    return ChoiceChip(
                      label: Text(lvl == 1 ? 'Lv. 1 (Terbuka)' : 'Min. Lv. $lvl'),
                      selected: isSelected,
                      onSelected: canSelect ? (_) => setSheetState(() => selectedMinLevel = lvl) : null,
                      selectedColor: AppColors.primaryOrange,
                      backgroundColor: AppColors.backgroundDark,
                      disabledColor: Colors.white10,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : (canSelect ? Colors.white70 : Colors.white30),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                _buildSheetField(descCtrl, 'Deskripsi / info tambahan', Icons.notes, maxLines: 2),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryOrange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            if (titleCtrl.text.trim().isEmpty) return;
                            final parsedQuota = int.tryParse(quotaCtrl.text.trim()) ?? 50;
                            setSheetState(() => isSubmitting = true);
                            try {
                              await _communityService.createEvent(
                                title: titleCtrl.text,
                                dateStr: dateCtrl.text.trim().isEmpty ? 'Segera diumumkan' : dateCtrl.text,
                                location: locCtrl.text.trim().isEmpty ? 'Indonesia' : locCtrl.text,
                                distanceTag: distCtrl.text.trim().isEmpty ? '5.0 KM' : distCtrl.text,
                                paceGroup: paceCtrl.text.trim().isEmpty ? 'All Pace' : paceCtrl.text,
                                description: descCtrl.text.trim().isEmpty
                                    ? 'Lari santai bersama komunitas Adventure Runner.'
                                    : descCtrl.text,
                                minLevel: selectedMinLevel,
                                maxParticipants: parsedQuota.clamp(2, 500),
                              );
                              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              await _loadAllData();
                              _showSnack('Acara "${titleCtrl.text.trim()}" dipublikasikan!');
                            } catch (e) {
                              setSheetState(() => isSubmitting = false);
                              _showSnack('Gagal membuat acara: $e', isError: true);
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Publikasikan Acara', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    titleCtrl.dispose();
    dateCtrl.dispose();
    locCtrl.dispose();
    distCtrl.dispose();
    paceCtrl.dispose();
    quotaCtrl.dispose();
    descCtrl.dispose();
  }

  Widget _buildSheetField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    bool isNumber = false,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 13.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        prefixIcon: Icon(icon, color: AppColors.primaryOrange, size: 18),
        filled: true,
        fillColor: AppColors.backgroundDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  // --- BUKA HALAMAN DETAIL KLUB ONLINE (LEADERBOARD + LIVE CHAT) ---
  Future<void> _openOnlineClubDetail(OnlineClub club) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClubDetailScreen(
          club: club,
          userLevel: _userLevel,
          userTotalXp: _userTotalXp,
          userAvatarPath: _profile.avatarPath,
        ),
      ),
    );
    if (changed == true) {
      await _loadAllData();
    }
  }

  // --- LEADERBOARD KLUB FALLBACK OFFLINE ---
  void _showOfflineClubLeaderboardSheet(RunningClub club) {
    final isJoined = _localJoinedClubIds.contains(club.id);
    final meetsLevel = RunnerStats.meetsLevelRequirement(userLevel: _userLevel, minLevel: club.minLevel);
    final double userWeeklyKm = RunnerStats.weeklyDistance(_savedRuns);
    final int userWeeklyRuns = RunnerStats.weeklyRunsCount(_savedRuns);
    final List<ClubMember> allMembers = [
      ...club.simulatedMembers,
      ClubMember(
        name: '${_profile.name} (Anda)',
        weeklyKm: userWeeklyKm,
        runsCount: userWeeklyRuns,
        runnerLevel: _userLevel,
        isCurrentUser: true,
        avatarPath: _profile.avatarPath,
      ),
    ]..sort((a, b) => b.weeklyKm.compareTo(a.weeklyKm));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
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
              Text(club.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('${club.schedule} • Min. Lv. ${club.minLevel}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 12),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Papan Peringkat Mingguan (Offline)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                  Text('Mode Offline', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: allMembers.length,
                  itemBuilder: (_, idx) {
                    final m = allMembers[idx];
                    return _buildLeaderboardRow(
                      rank: idx + 1,
                      name: m.name,
                      runnerLevel: m.runnerLevel,
                      subtitle: '${m.runsCount} sesi aktivitas',
                      weeklyKm: m.weeklyKm,
                      isCurrentUser: m.isCurrentUser,
                      avatarPath: m.avatarPath,
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
                    backgroundColor: isJoined
                        ? AppColors.cardElevated
                        : (meetsLevel ? club.color : Colors.white12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _handleToggleOfflineClub(club);
                  },
                  child: Text(
                    isJoined
                        ? 'Keluar dari Klub'
                        : (meetsLevel ? 'Gabung Klub' : 'Butuh Level ${club.minLevel}'),
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

  Widget _buildLeaderboardRow({
    required int rank,
    required String name,
    required int runnerLevel,
    required String subtitle,
    required double weeklyKm,
    required bool isCurrentUser,
    String? avatarPath,
  }) {
    final hasAvatar = avatarPath != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrentUser ? AppColors.primaryOrange.withValues(alpha: 0.18) : AppColors.backgroundDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isCurrentUser ? AppColors.primaryOrange : Colors.white10),
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
            backgroundImage: hasAvatar ? FileImage(File(avatarPath)) : null,
            child: !hasAvatar
                ? Text(
                    name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.w600,
                          color: Colors.white,
                          fontSize: 13.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'Lv.$runnerLevel',
                        style: const TextStyle(color: Colors.amber, fontSize: 9.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Text(
            '${weeklyKm.toStringAsFixed(1)} km',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: isCurrentUser ? AppColors.primaryOrange : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: AppBar(
          title: Row(
            children: [
              const Text(
                'GRUP & KOMUNITAS',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 15.5),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: (_isOnlineMode ? AppColors.accentGreen : Colors.amber).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 3.5,
                      backgroundColor: _isOnlineMode ? AppColors.accentGreen : Colors.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isOnlineMode ? 'ONLINE' : 'OFFLINE',
                      style: TextStyle(
                        color: _isOnlineMode ? AppColors.accentGreen : Colors.amber,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.backgroundDark,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: 'Sinkronisasi Komunitas',
              icon: const Icon(Icons.sync, color: Colors.white70),
              onPressed: () async {
                if (AuthService.isLoggedIn) {
                  await AuthService.syncLocalStatsToCloud();
                }
                await _loadAllData();
              },
            ),
          ],
          bottom: const TabBar(
            indicatorColor: AppColors.primaryOrange,
            indicatorWeight: 3,
            labelColor: AppColors.primaryOrange,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            tabs: [
              Tab(text: 'Tantangan'),
              Tab(text: 'Klub'),
              Tab(text: 'Acara'),
              Tab(text: 'Teman'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (!AuthService.isLoggedIn) _buildGuestLoginBanner(),
            if (_needsSchemaSetup && _statusMessage != null) _buildSchemaWarningBanner(_statusMessage!),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
                  : TabBarView(
                      children: [
                        _buildChallengesTab(),
                        _buildClubsTab(),
                        _buildEventsTab(),
                        FriendsTabView(
                          currentUserName: _profile.name,
                          currentUserCity: _profile.city,
                          currentUserAvatarPath: _profile.avatarPath,
                          currentUserLevel: _userLevel,
                          currentUserWeeklyKm: RunnerStats.weeklyDistance(_savedRuns),
                          currentUserWeeklyRuns: RunnerStats.weeklyRunsCount(_savedRuns),
                          onRequireLogin: _ensureLoggedInForOnlineAction,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuestLoginBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryOrange.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.public, color: AppColors.primaryOrange, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Masuk akun untuk gabung klub, buat acara & bersaing di leaderboard online.',
              style: TextStyle(color: Colors.white, fontSize: 11.5),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryOrange,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _ensureLoggedInForOnlineAction,
            child: const Text('Masuk', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSchemaWarningBanner(String message) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.amber, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  // --- TAB 1: TANTANGAN (LEVEL GATING + KLAIM BONUS XP) ---
  Widget _buildChallengesTab() {
    if (_isOnlineMode) {
      return RefreshIndicator(
        onRefresh: _loadAllData,
        color: AppColors.primaryOrange,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildRunnerLevelBanner(),
            const SizedBox(height: 14),
            ..._onlineChallenges.map((ch) => _buildChallengeCard(
                  id: ch.id,
                  title: ch.title,
                  description: ch.description,
                  badgeText: ch.badgeText,
                  unit: ch.unit,
                  targetValue: ch.targetValue,
                  minLevel: ch.minLevel,
                  xpReward: ch.xpReward,
                  accentColor: ch.accentColor,
                  icon: ch.icon,
                  participantsCount: ch.participantsCount,
                  isJoined: ch.isJoined,
                  isRewardClaimed: ch.isRewardClaimed,
                  onToggle: () => _handleToggleOnlineChallenge(ch),
                  onClaimReward: () => _handleClaimOnlineChallengeReward(ch),
                )),
          ],
        ),
      );
    }

    const offlineList = CommunitySeedData.challenges;
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: AppColors.primaryOrange,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildRunnerLevelBanner(),
          const SizedBox(height: 14),
          ...offlineList.map((ch) {
            final isJoined = _localJoinedChallengeIds.contains(ch.id);
            final isClaimed = _localClaimedChallengeIds.contains(ch.id);
            return _buildChallengeCard(
              id: ch.id,
              title: ch.title,
              description: ch.description,
              badgeText: ch.badgeText,
              unit: ch.unit,
              targetValue: ch.targetValue,
              minLevel: ch.minLevel,
              xpReward: ch.xpReward,
              accentColor: ch.accentColor,
              icon: ch.icon,
              participantsCount: ch.baseParticipants + (isJoined ? 1 : 0),
              isJoined: isJoined,
              isRewardClaimed: isClaimed,
              onToggle: () => _handleToggleOfflineChallenge(ch),
              onClaimReward: () => _handleClaimOfflineChallengeReward(ch),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRunnerLevelBanner() {
    final nextLevelXp = _userLevel * RunnerStats.xpPerLevel;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF251A16), AppColors.cardDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryOrange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'LV. $_userLevel',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _userRank,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              Text(
                '$_userTotalXp / $nextLevelXp XP',
                style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _userLevelProgress,
              minHeight: 7,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryOrange),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _profile.bonusXp > 0
                ? 'Selesaikan tantangan untuk klaim Bonus XP (sudah terkumpul +${_profile.bonusXp} XP) & buka tier level tinggi!'
                : 'Naikkan Level dari lari & klaim Bonus XP tantangan untuk membuka tantangan tier lebih tinggi.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengeCard({
    required String id,
    required String title,
    required String description,
    required String badgeText,
    required String unit,
    required double targetValue,
    required int minLevel,
    required int xpReward,
    required Color accentColor,
    required IconData icon,
    required int participantsCount,
    required bool isJoined,
    required bool isRewardClaimed,
    required VoidCallback onToggle,
    required VoidCallback onClaimReward,
  }) {
    final bool isUnlocked = RunnerStats.meetsLevelRequirement(userLevel: _userLevel, minLevel: minLevel);
    final int xpMissing = RunnerStats.xpNeededForLevel(minLevel, _userTotalXp);
    final currentVal = _getCurrentProgressValue(unit);
    final ratio = (currentVal / targetValue).clamp(0.0, 1.0);
    final isCompleted = ratio >= 1.0;
    final bool canClaim = isUnlocked && isJoined && isCompleted && !isRewardClaimed;
    final bool isClaiming = _claimingChallengeId == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUnlocked ? AppColors.cardDark : AppColors.cardDark.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: !isUnlocked
              ? Colors.white12
              : canClaim
                  ? Colors.amber.withValues(alpha: 0.85)
                  : isRewardClaimed
                      ? AppColors.accentGreen.withValues(alpha: 0.6)
                      : isJoined
                          ? accentColor.withValues(alpha: 0.45)
                          : Colors.white10,
          width: canClaim ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Baris Badge Level Requirement & Hadiah XP
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isUnlocked ? AppColors.accentGreen : Colors.white24).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isUnlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                      size: 11,
                      color: isUnlocked ? AppColors.accentGreen : Colors.white54,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'MIN LV. $minLevel',
                      style: TextStyle(
                        color: isUnlocked ? AppColors.accentGreen : Colors.white60,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt, size: 12, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text(
                      '+$xpReward XP',
                      style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (isRewardClaimed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentGreen.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('DIKLAIM ✓', style: TextStyle(color: AppColors.accentGreen, fontSize: 10, fontWeight: FontWeight.w900)),
                )
              else if (isUnlocked && isJoined && isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('SIAP KLAIM', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isUnlocked ? accentColor : Colors.white24).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isUnlocked ? icon : Icons.lock,
                  color: isUnlocked ? accentColor : Colors.white38,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      badgeText,
                      style: TextStyle(
                        color: isUnlocked ? accentColor : Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isUnlocked ? Colors.white : Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 14),

          // Banner Terkunci jika Level belum cukup
          if (!isUnlocked) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_clock, size: 16, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Capai Level $minLevel (kurang $xpMissing XP lagi) untuk membuka tantangan ini.',
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else if (isJoined) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Progres Anda: ${_formatProgressText(unit, targetValue, currentVal)}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text('${(ratio * 100).toInt()}%', style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(isCompleted ? AppColors.accentGreen : accentColor),
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
                  Text('$participantsCount Peserta', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
              if (!isUnlocked)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  onPressed: onToggle,
                  icon: const Icon(Icons.lock_outline, size: 14, color: Colors.white38),
                  label: Text(
                    'Butuh Lv. $minLevel',
                    style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                )
              else if (canClaim)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: isClaiming ? null : onClaimReward,
                  icon: isClaiming
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.card_giftcard, size: 16, color: Colors.white),
                  label: Text(
                    isClaiming ? 'Mengklaim...' : 'Klaim +$xpReward XP',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                )
              else if (isRewardClaimed)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.accentGreen.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  onPressed: null,
                  icon: const Icon(Icons.check_circle, size: 15, color: AppColors.accentGreen),
                  label: const Text(
                    'Selesai & Diklaim',
                    style: TextStyle(color: AppColors.accentGreen, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                )
              else
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: isJoined ? Colors.transparent : accentColor,
                    side: BorderSide(color: isJoined ? Colors.white24 : accentColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  ),
                  onPressed: onToggle,
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
  }

  // --- TAB 2: KLUB + BUAT KLUB ONLINE ---
  Widget _buildClubsTab() {
    if (_isOnlineMode) {
      return RefreshIndicator(
        onRefresh: _loadAllData,
        color: AppColors.primaryOrange,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primaryOrange),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _showCreateClubSheet,
                icon: const Icon(Icons.add_circle_outline, color: AppColors.primaryOrange, size: 19),
                label: const Text('Buat Klub Lari Baru', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
            const SizedBox(height: 14),
            ..._onlineClubs.map((club) => _buildClubCard(
                  name: club.name,
                  location: club.location,
                  description: club.description,
                  schedule: club.schedule,
                  minLevel: club.minLevel,
                  color: club.color,
                  icon: Icons.directions_run,
                  membersCount: club.membersCount,
                  isJoined: club.isJoined,
                  hasLiveChat: true,
                  onOpenDetail: () => _openOnlineClubDetail(club),
                  onToggle: () => _handleToggleOnlineClub(club),
                )),
          ],
        ),
      );
    }

    const offlineClubs = CommunitySeedData.clubs;
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: AppColors.primaryOrange,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: offlineClubs.length,
        itemBuilder: (context, index) {
          final club = offlineClubs[index];
          final isJoined = _localJoinedClubIds.contains(club.id);
          return _buildClubCard(
            name: club.name,
            location: club.location,
            description: club.description,
            schedule: club.schedule,
            minLevel: club.minLevel,
            color: club.color,
            icon: club.icon,
            membersCount: club.baseMembers + (isJoined ? 1 : 0),
            isJoined: isJoined,
            hasLiveChat: false,
            onOpenDetail: () => _showOfflineClubLeaderboardSheet(club),
            onToggle: () => _handleToggleOfflineClub(club),
          );
        },
      ),
    );
  }

  Widget _buildClubCard({
    required String name,
    required String location,
    required String description,
    required String schedule,
    required int minLevel,
    required Color color,
    required IconData icon,
    required int membersCount,
    required bool isJoined,
    required bool hasLiveChat,
    required VoidCallback onOpenDetail,
    required VoidCallback onToggle,
  }) {
    final bool isUnlocked = RunnerStats.meetsLevelRequirement(userLevel: _userLevel, minLevel: minLevel);
    final int xpMissing = RunnerStats.xpNeededForLevel(minLevel, _userTotalXp);

    return GestureDetector(
      onTap: onOpenDetail,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isUnlocked ? AppColors.cardDark : AppColors.cardDark.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: !isUnlocked
                ? Colors.white12
                : isJoined
                    ? color.withValues(alpha: 0.45)
                    : Colors.white10,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge syarat level & fitur obrolan
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isUnlocked ? AppColors.accentGreen : Colors.white24).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUnlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                        size: 11,
                        color: isUnlocked ? AppColors.accentGreen : Colors.white54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        minLevel == 1 ? 'TERBUKA • LV. 1+' : 'MIN LV. $minLevel',
                        style: TextStyle(
                          color: isUnlocked ? AppColors.accentGreen : Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (hasLiveChat) ...[
                  const Icon(Icons.forum_outlined, color: AppColors.textSecondary, size: 15),
                  const SizedBox(width: 6),
                ],
                Icon(Icons.leaderboard, color: isUnlocked ? color : Colors.white30, size: 18),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: (isUnlocked ? color : Colors.white24).withValues(alpha: 0.18),
                  child: Icon(isUnlocked ? icon : Icons.lock, color: isUnlocked ? color : Colors.white38, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isUnlocked ? Colors.white : Colors.white60,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text('$location • $membersCount Anggota', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(description, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            if (!isUnlocked) ...[
              const SizedBox(height: 10),
              Text(
                '🔒 Capai Level $minLevel (kurang $xpMissing XP lagi) untuk bergabung & ikut obrolan klub.',
                style: const TextStyle(color: Colors.amber, fontSize: 11.5),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, size: 14, color: AppColors.primaryOrange),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          schedule,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !isUnlocked
                        ? Colors.white12
                        : (isJoined ? AppColors.cardElevated : color),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: onToggle,
                  child: Text(
                    !isUnlocked
                        ? 'Butuh Lv. $minLevel'
                        : (isJoined ? 'Anggota ✓' : 'Gabung'),
                    style: TextStyle(
                      color: isUnlocked ? Colors.white : Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 3: ACARA + BUAT ACARA ONLINE ---
  Widget _buildEventsTab() {
    if (_isOnlineMode) {
      return RefreshIndicator(
        onRefresh: _loadAllData,
        color: AppColors.primaryOrange,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accentBlue),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _showCreateEventSheet,
                icon: const Icon(Icons.add_circle_outline, color: AppColors.accentBlue, size: 19),
                label: const Text('Buat Acara Lari Bersama', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
            const SizedBox(height: 14),
            ..._onlineEvents.map((ev) => _buildEventCard(
                  title: ev.title,
                  dateStr: ev.dateStr,
                  location: ev.location,
                  distanceTag: ev.distanceTag,
                  paceGroup: ev.paceGroup,
                  description: ev.description,
                  minLevel: ev.minLevel,
                  maxParticipants: ev.maxParticipants,
                  attendeesCount: ev.attendeesCount,
                  attendeeNames: ev.attendeeNames,
                  isAttending: ev.isAttending,
                  hasDiscussion: true,
                  onOpenDetail: () => _openOnlineEventDetail(ev),
                  onToggle: () => _handleToggleOnlineEvent(ev),
                )),
          ],
        ),
      );
    }

    const offlineEvents = CommunitySeedData.events;
    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: AppColors.primaryOrange,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: offlineEvents.length,
        itemBuilder: (context, index) {
          final ev = offlineEvents[index];
          final isAttending = _localRsvpEventIds.contains(ev.id);
          return _buildEventCard(
            title: ev.title,
            dateStr: ev.dateStr,
            location: ev.location,
            distanceTag: ev.distanceTag,
            paceGroup: ev.paceGroup,
            description: ev.description,
            minLevel: ev.minLevel,
            maxParticipants: ev.maxParticipants,
            attendeesCount: ev.baseAttendees + (isAttending ? 1 : 0),
            attendeeNames: const [],
            isAttending: isAttending,
            hasDiscussion: false,
            onOpenDetail: null,
            onToggle: () => _handleToggleOfflineEvent(ev),
          );
        },
      ),
    );
  }

  Widget _buildEventCard({
    required String title,
    required String dateStr,
    required String location,
    required String distanceTag,
    required String paceGroup,
    required String description,
    required int minLevel,
    required int maxParticipants,
    required int attendeesCount,
    required List<String> attendeeNames,
    required bool isAttending,
    required bool hasDiscussion,
    required VoidCallback? onOpenDetail,
    required VoidCallback onToggle,
  }) {
    final bool isUnlocked = RunnerStats.meetsLevelRequirement(userLevel: _userLevel, minLevel: minLevel);
    final int xpMissing = RunnerStats.xpNeededForLevel(minLevel, _userTotalXp);
    final bool isFull = attendeesCount >= maxParticipants;
    final bool blockedByQuota = !isAttending && isFull;
    final double quotaRatio = (attendeesCount / maxParticipants).clamp(0.0, 1.0);
    final attendeesPreview = attendeeNames.isEmpty
        ? null
        : attendeeNames.take(3).join(', ') +
            (attendeeNames.length > 3 ? ' +${attendeeNames.length - 3} lainnya' : '');

    return GestureDetector(
      onTap: onOpenDetail,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isUnlocked ? AppColors.cardDark : AppColors.cardDark.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: !isUnlocked
                ? Colors.white12
                : isAttending
                    ? AppColors.accentGreen.withValues(alpha: 0.5)
                    : Colors.white10,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(distanceTag, style: const TextStyle(color: AppColors.primaryOrange, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isUnlocked ? AppColors.accentGreen : Colors.white24).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUnlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                        size: 11,
                        color: isUnlocked ? AppColors.accentGreen : Colors.white54,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        minLevel == 1 ? 'LV. 1+' : 'MIN LV. $minLevel',
                        style: TextStyle(
                          color: isUnlocked ? AppColors.accentGreen : Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (hasDiscussion) ...[
                  const Icon(Icons.forum_outlined, size: 15, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                ],
                Text(paceGroup, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isUnlocked ? Colors.white : Colors.white60,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 13, color: AppColors.primaryOrange),
                const SizedBox(width: 6),
                Text(dateStr, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on, size: 13, color: AppColors.accentBlue),
                const SizedBox(width: 6),
                Expanded(child: Text(location, style: const TextStyle(color: Colors.white70, fontSize: 12))),
              ],
            ),
            const SizedBox(height: 10),
            Text(description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
            if (!isUnlocked) ...[
              const SizedBox(height: 8),
              Text(
                '🔒 Capai Level $minLevel (kurang $xpMissing XP lagi) untuk mendaftar & ikut diskusi acara.',
                style: const TextStyle(color: Colors.amber, fontSize: 11.5),
              ),
            ],
            if (attendeesPreview != null) ...[
              const SizedBox(height: 8),
              Text(
                'Ikut hadir: $attendeesPreview',
                style: const TextStyle(color: AppColors.accentGreen, fontSize: 11.5, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            // Bar Kuota Peserta
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Kuota: $attendeesCount / $maxParticipants Pelari',
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  isFull ? 'KUOTA PENUH' : 'Sisa ${maxParticipants - attendeesCount} slot',
                  style: TextStyle(
                    color: isFull ? Colors.redAccent : AppColors.accentBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: quotaRatio,
                minHeight: 5.5,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(isFull ? Colors.redAccent : AppColors.accentBlue),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  hasDiscussion ? 'Ketuk kartu untuk diskusi & daftar peserta' : 'Mode Offline',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAttending
                        ? AppColors.accentGreen.withValues(alpha: 0.2)
                        : (!isUnlocked || blockedByQuota ? Colors.white12 : AppColors.primaryOrange),
                    side: isAttending ? const BorderSide(color: AppColors.accentGreen) : BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: onToggle,
                  icon: Icon(
                    isAttending
                        ? Icons.check_circle
                        : (!isUnlocked ? Icons.lock_outline : Icons.event_available),
                    size: 16,
                    color: isAttending
                        ? AppColors.accentGreen
                        : (isUnlocked && !blockedByQuota ? Colors.white : Colors.white54),
                  ),
                  label: Text(
                    isAttending
                        ? 'Terdaftar'
                        : (!isUnlocked
                            ? 'Butuh Lv. $minLevel'
                            : (blockedByQuota ? 'Penuh' : 'Ikut Acara')),
                    style: TextStyle(
                      color: isAttending
                          ? AppColors.accentGreen
                          : (isUnlocked && !blockedByQuota ? Colors.white : Colors.white54),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
