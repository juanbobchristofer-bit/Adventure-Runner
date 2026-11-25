import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/offline_tile_provider.dart';
import '../../../core/services/profile_storage_service.dart';
import '../../../core/services/run_storage_service.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/presentation/login_screen.dart';
import '../domain/run_model.dart';
import '../domain/runner_stats.dart';

class _AchievementBadge {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool unlocked;

  const _AchievementBadge({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.unlocked,
  });
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final RunStorageService _storageService = RunStorageService();
  final ProfileStorageService _profileService = ProfileStorageService();
  final LocationService _locationService = LocationService();
  final ImagePicker _picker = ImagePicker();

  List<RunModel> _savedRuns = [];
  OfflineCacheStats _cacheStats = const OfflineCacheStats(tileCount: 0, totalBytes: 0);
  bool _hasBackgroundGps = false;
  UserProfileData _profile = UserProfileData.defaultProfile;
  bool _isLoading = true;
  bool _isSyncingCloudRuns = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    ProfileStorageService.profileUpdateNotifier.addListener(_onExternalProfileUpdate);
    RunStorageService.runUpdateNotifier.addListener(_onExternalProfileUpdate);
    AuthService.authStateNotifier.addListener(_onExternalProfileUpdate);
  }

  @override
  void dispose() {
    ProfileStorageService.profileUpdateNotifier.removeListener(_onExternalProfileUpdate);
    RunStorageService.runUpdateNotifier.removeListener(_onExternalProfileUpdate);
    AuthService.authStateNotifier.removeListener(_onExternalProfileUpdate);
    super.dispose();
  }

  void _onExternalProfileUpdate() {
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final profile = await _profileService.getProfile();
    final runs = await _storageService.getSavedRuns();
    final cacheStats = await OfflineTileCacheService.getCacheStats();
    final hasBgGps = await _locationService.isBackgroundPermissionGranted();

    if (mounted) {
      setState(() {
        _profile = profile;
        _savedRuns = runs;
        _cacheStats = cacheStats;
        _hasBackgroundGps = hasBgGps;
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmClearMapCache() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.cardDark,
            title: const Text('Bersihkan Cache Peta?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: const Text(
              'Tile peta offline yang tersimpan akan dihapus dan akan diunduh ulang saat Anda membuka peta secara online.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Bersihkan', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    await OfflineTileCacheService.clearCache();
    await _loadUserData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cache peta offline berhasil dibersihkan.'),
          backgroundColor: AppColors.cardElevated,
        ),
      );
    }
  }

  Future<void> _enableBackgroundGps() async {
    final granted = await _locationService.requestBackgroundPermission();
    await _loadUserData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted
                ? 'Izin GPS latar belakang aktif! Pelacakan tetap stabil saat layar terkunci.'
                : 'Izin lokasi "Selalu Izinkan" belum aktif. Anda dapat mengaturnya di Pengaturan perangkat.',
          ),
          backgroundColor: AppColors.cardElevated,
        ),
      );
    }
  }

  // --- UPLOAD / GANTI FOTO PROFIL ---
  void _showAvatarPickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Foto Profil Atlet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.cardElevated,
                  child: Icon(Icons.photo_library, color: AppColors.primaryOrange),
                ),
                title: const Text('Pilih dari Galeri', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.cardElevated,
                  child: Icon(Icons.camera_alt, color: AppColors.accentBlue),
                ),
                title: const Text('Ambil Foto dengan Kamera', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              if (_profile.avatarPath != null)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.cardElevated,
                    child: Icon(Icons.delete_outline, color: Colors.redAccent),
                  ),
                  title: const Text('Hapus Foto Profil', style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _profileService.removeAvatar();
                    await CloudSyncService.removeCloudAvatar();
                    _loadUserData();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (picked != null) {
        final savedPath = await _profileService.saveAvatarImage(File(picked.path));
        String? cloudUrl;
        if (AuthService.isLoggedIn) {
          cloudUrl = await CloudSyncService.uploadAvatar(File(savedPath));
        }
        await _loadUserData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                cloudUrl != null
                    ? 'Foto profil diperbarui & disinkronkan ke Cloud!'
                    : 'Foto profil berhasil diperbarui!',
              ),
              backgroundColor: AppColors.cardElevated,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat foto: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // --- DIALOG EDIT PROFIL LENGKAP ---
  Future<void> _showEditProfileDialog() async {
    final nameCtrl = TextEditingController(text: _profile.name);
    final bioCtrl = TextEditingController(text: _profile.bio);
    final cityCtrl = TextEditingController(text: _profile.city);
    final weightCtrl = TextEditingController(text: _profile.weightKg.toStringAsFixed(0));
    final goalCtrl = TextEditingController(text: _profile.weeklyGoalKm.toStringAsFixed(0));

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Edit Profil Atlet', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogField(nameCtrl, 'Nama Lengkap', Icons.person_outline),
              const SizedBox(height: 12),
              _buildDialogField(bioCtrl, 'Bio / Motto Lari', Icons.format_quote),
              const SizedBox(height: 12),
              _buildDialogField(cityCtrl, 'Kota / Basecamp', Icons.location_on_outlined),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildDialogField(weightCtrl, 'Berat (kg)', Icons.monitor_weight_outlined, isNumber: true),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildDialogField(goalCtrl, 'Target (km)', Icons.flag_outlined, isNumber: true),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              final parsedWeight = double.tryParse(weightCtrl.text.replaceAll(',', '.').trim());
              final parsedGoal = double.tryParse(goalCtrl.text.replaceAll(',', '.').trim());

              if (newName.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nama tidak boleh kosong.'), backgroundColor: Colors.redAccent),
                  );
                }
                return;
              }

              if (parsedWeight == null || parsedWeight < 20 || parsedWeight > 300) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Berat badan harus antara 20 - 300 kg.'), backgroundColor: Colors.redAccent),
                  );
                }
                return;
              }

              if (parsedGoal == null || parsedGoal <= 0 || parsedGoal > 1000) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Target jarak harus antara 1 - 1000 km.'), backgroundColor: Colors.redAccent),
                  );
                }
                return;
              }

              await _profileService.saveProfile(
                name: newName,
                bio: bioCtrl.text.trim().isEmpty ? _profile.bio : bioCtrl.text.trim(),
                city: cityCtrl.text.trim().isEmpty ? _profile.city : cityCtrl.text.trim(),
                weightKg: parsedWeight,
                weeklyGoalKm: parsedGoal,
              );
              await _loadUserData();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    nameCtrl.dispose();
    bioCtrl.dispose();
    cityCtrl.dispose();
    weightCtrl.dispose();
    goalCtrl.dispose();
  }

  Widget _buildDialogField(TextEditingController controller, String label, IconData icon, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        prefixIcon: Icon(icon, color: AppColors.primaryOrange, size: 18),
        filled: true,
        fillColor: AppColors.backgroundDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }

  // --- KALKULASI STATISTIK & GAMIFIKASI (TERPADU VIA RunnerStats) ---
  double get _totalDistance => RunnerStats.totalDistance(_savedRuns);
  double get _totalCalories => RunnerStats.totalCalories(_savedRuns);
  int get _totalSteps => _savedRuns.fold(0, (sum, item) => sum + item.steps);

  double get _longestRunKm =>
      _savedRuns.isEmpty ? 0.0 : _savedRuns.map((r) => r.distanceInKm).reduce(math.max);

  int get _longestDurationSec =>
      _savedRuns.isEmpty ? 0 : _savedRuns.map((r) => r.durationInSeconds).reduce(math.max);

  int get _totalXp => RunnerStats.totalXp(_savedRuns, bonusXp: _profile.bonusXp);
  int get _runnerLevel => RunnerStats.runnerLevel(_savedRuns, bonusXp: _profile.bonusXp);
  double get _levelProgress => RunnerStats.levelProgress(_savedRuns, bonusXp: _profile.bonusXp);
  String get _rankTitle => RunnerStats.rankTitle(_savedRuns, bonusXp: _profile.bonusXp);

  List<_AchievementBadge> get _badges => [
        _AchievementBadge(
          title: 'First Stride',
          subtitle: 'Selesaikan 1x lari',
          icon: Icons.directions_run,
          color: AppColors.primaryOrange,
          unlocked: _savedRuns.isNotEmpty,
        ),
        _AchievementBadge(
          title: '5K Finisher',
          subtitle: 'Lari min. 5 km sekali jalan',
          icon: Icons.military_tech,
          color: AppColors.accentBlue,
          unlocked: _longestRunKm >= 5.0,
        ),
        _AchievementBadge(
          title: '10K Warrior',
          subtitle: 'Lari min. 10 km sekali jalan',
          icon: Icons.emoji_events,
          color: Colors.amber,
          unlocked: _longestRunKm >= 10.0,
        ),
        _AchievementBadge(
          title: 'Calorie Burner',
          subtitle: 'Bakar total 1.000 kcal',
          icon: Icons.local_fire_department,
          color: Colors.deepOrangeAccent,
          unlocked: _totalCalories >= 1000,
        ),
        _AchievementBadge(
          title: '10K Steps Club',
          subtitle: 'Kumpulkan 10.000 langkah',
          icon: Icons.directions_walk,
          color: AppColors.accentGreen,
          unlocked: _totalSteps >= 10000,
        ),
        _AchievementBadge(
          title: 'Endurance 30m',
          subtitle: 'Lari durasi â‰¥ 30 menit',
          icon: Icons.timer,
          color: Colors.purpleAccent,
          unlocked: _longestDurationSec >= 1800,
        ),
        _AchievementBadge(
          title: 'Consistent 5',
          subtitle: 'Selesaikan 5 sesi lari',
          icon: Icons.repeat,
          color: Colors.tealAccent,
          unlocked: _savedRuns.length >= 5,
        ),
        _AchievementBadge(
          title: 'Half Marathoner',
          subtitle: 'Total jarak tempuh 21.1 km',
          icon: Icons.workspace_premium,
          color: Colors.pinkAccent,
          unlocked: _totalDistance >= 21.1,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final badges = _badges;
    final unlockedCount = badges.where((b) => b.unlocked).length;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        title: const Text('ANDA â€¢ PROFIL', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 16)),
        backgroundColor: AppColors.backgroundDark,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Edit Profil',
            icon: const Icon(Icons.edit_note, color: AppColors.primaryOrange, size: 26),
            onPressed: _showEditProfileDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
          : RefreshIndicator(
              onRefresh: _loadUserData,
              color: AppColors.primaryOrange,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  // 1. HEADER KARTU PROFIL + UPLOAD AVATAR
                  _buildProfileHeroCard(),
                  const SizedBox(height: 16),

                  // 2. LEVEL & XP PROGRESS BAR
                  _buildLevelProgressCard(),
                  const SizedBox(height: 22),

                  // 3. PERSONAL BESTS (REKOR PRIBADI)
                  const Text(
                    'Rekor Pribadi (Personal Bests)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildRecordCard(
                          'Lari Terjauh',
                          '${_longestRunKm.toStringAsFixed(2)} km',
                          Icons.route,
                          AppColors.primaryOrange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildRecordCard(
                          'Durasi Terlama',
                          AppFormatters.formatCompactDuration(_longestDurationSec),
                          Icons.hourglass_bottom,
                          AppColors.accentBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // 4. STATISTIK SEPANJANG MASA
                  const Text(
                    'Statistik Sepanjang Masa',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.65,
                    children: [
                      _buildAllTimeStat('Total Jarak', '${_totalDistance.toStringAsFixed(2)} km', Icons.map_outlined),
                      _buildAllTimeStat('Total Aktivitas', '${_savedRuns.length} Sesi', Icons.directions_run),
                      _buildAllTimeStat('Total Kalori', '${_totalCalories.toStringAsFixed(0)} kcal', Icons.local_fire_department_outlined),
                      _buildAllTimeStat('Langkah Total', '$_totalSteps', Icons.directions_walk),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // 5. KOLEKSI LENCANA PENCAPAIAN (GAMIFICATION BADGES)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Lencana Pencapaian',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      ),
                      Text(
                        '$unlockedCount / ${badges.length} Terbuka',
                        style: const TextStyle(color: AppColors.primaryOrange, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: badges.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.45,
                    ),
                    itemBuilder: (context, index) => _buildBadgeTile(badges[index]),
                  ),
                  const SizedBox(height: 24),

                  // 6. PENGATURAN AKUN ONLINE, OFFLINE & SENSOR
                  const Text(
                    'Akun Komunitas & Pengaturan Offline',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  _buildAccountSyncCard(),
                  const SizedBox(height: 12),
                  _buildOfflineAndPermissionCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildAccountSyncCard() {
    final isLoggedIn = AuthService.isLoggedIn;
    final email = AuthService.userEmail ?? 'Belum masuk akun';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLoggedIn ? AppColors.accentGreen.withValues(alpha: 0.4) : Colors.white10,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: (isLoggedIn ? AppColors.accentGreen : AppColors.primaryOrange).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isLoggedIn ? Icons.cloud_done_outlined : Icons.login_rounded,
                  color: isLoggedIn ? AppColors.accentGreen : AppColors.primaryOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLoggedIn ? 'Akun Komunitas Aktif' : 'Mode Tamu (Offline)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isLoggedIn ? email : 'Masuk untuk ikut Klub, Acara & Leaderboard online',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isLoggedIn) ...[
                IconButton(
                  tooltip: 'Sinkron Statistik',
                  icon: const Icon(Icons.sync, color: AppColors.accentGreen, size: 20),
                  onPressed: () async {
                    final ok = await AuthService.syncLocalStatsToCloud();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok ? 'Statistik berhasil disinkronkan ke cloud!' : 'Gagal sinkron. Periksa internet atau tabel Supabase.'),
                          backgroundColor: AppColors.cardElevated,
                        ),
                      );
                    }
                  },
                ),
                TextButton(
                  onPressed: () async {
                    await AuthService.signOut();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Anda keluar ke Mode Tamu (Offline). Data lokal tetap aman.'),
                          backgroundColor: AppColors.cardElevated,
                        ),
                      );
                    }
                  },
                  child: const Text('Keluar', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ] else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                    await _loadUserData();
                  },
                  child: const Text('Masuk', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
            ],
          ),
          if (isLoggedIn) ...[
            const Divider(color: Colors.white10, height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.accentBlue),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isSyncingCloudRuns
                        ? null
                        : () async {
                            setState(() => _isSyncingCloudRuns = true);
                            final count = await CloudSyncService.backupAllLocalRuns();
                            if (mounted) {
                              setState(() => _isSyncingCloudRuns = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    count > 0
                                        ? '$count riwayat lari berhasil dicadangkan ke Cloud!'
                                        : 'Tidak ada data yang dicadangkan (pastikan migrasi P6 sudah dijalankan).',
                                  ),
                                  backgroundColor: AppColors.cardElevated,
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.cloud_upload_outlined, size: 16, color: AppColors.accentBlue),
                    label: const Text('Backup Riwayat', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.accentGreen),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isSyncingCloudRuns
                        ? null
                        : () async {
                            setState(() => _isSyncingCloudRuns = true);
                            final restored = await CloudSyncService.restoreRunsFromCloud();
                            await _loadUserData();
                            if (mounted) {
                              setState(() => _isSyncingCloudRuns = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    restored > 0
                                        ? '$restored riwayat lari berhasil dipulihkan dari Cloud!'
                                        : 'Semua riwayat cloud sudah sinkron di perangkat ini.',
                                  ),
                                  backgroundColor: AppColors.cardElevated,
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.cloud_download_outlined, size: 16, color: AppColors.accentGreen),
                    label: const Text('Pulihkan Cloud', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOfflineAndPermissionCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.accentBlue.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.offline_pin_outlined, color: AppColors.accentBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cache Peta Offline (OSM)',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_cacheStats.tileCount} tile tersimpan â€¢ ${OfflineTileCacheService.formatBytes(_cacheStats.totalBytes)}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _cacheStats.tileCount > 0 ? _confirmClearMapCache : null,
                child: Text(
                  'Bersihkan',
                  style: TextStyle(
                    color: _cacheStats.tileCount > 0 ? AppColors.primaryOrange : Colors.white24,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 22),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: (_hasBackgroundGps ? AppColors.accentGreen : Colors.amber).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.my_location,
                  color: _hasBackgroundGps ? AppColors.accentGreen : Colors.amber,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GPS Latar Belakang',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _hasBackgroundGps
                          ? 'Aktif (Always) â€¢ Stabil saat layar terkunci'
                          : 'Belum aktif penuh â€¢ Ketuk untuk mengizinkan',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              if (!_hasBackgroundGps)
                TextButton(
                  onPressed: _enableBackgroundGps,
                  child: const Text(
                    'Aktifkan',
                    style: TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                )
              else
                const Icon(Icons.check_circle, color: AppColors.accentGreen, size: 20),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeroCard() {
    final hasLocalAvatar = _profile.avatarPath != null;
    final hasCloudAvatar = !hasLocalAvatar && _profile.avatarUrl != null;
    final ImageProvider<Object>? avatarImage = hasLocalAvatar
        ? FileImage(File(_profile.avatarPath!)) as ImageProvider<Object>
        : (hasCloudAvatar ? NetworkImage(_profile.avatarUrl!) : null);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF261B17), AppColors.cardDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar + Tombol Kamera Overlay
              GestureDetector(
                onTap: _showAvatarPickerOptions,
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primaryOrange, width: 2.2),
                      ),
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: AppColors.cardElevated,
                        backgroundImage: avatarImage,
                        child: avatarImage == null
                            ? const Icon(Icons.person, size: 38, color: Colors.white70)
                            : null,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryOrange,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.cardDark, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt, size: 13, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primaryOrange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _rankTitle,
                        style: const TextStyle(
                          color: AppColors.primaryOrange,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _profile.name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            _profile.city,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
          const SizedBox(height: 12),
          Text(
            _profile.bio,
            style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildMiniChip(Icons.monitor_weight_outlined, '${_profile.weightKg.toStringAsFixed(0)} kg'),
              const SizedBox(width: 8),
              _buildMiniChip(Icons.flag_outlined, 'Target ${_profile.weeklyGoalKm.toStringAsFixed(0)} km'),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                onPressed: _showEditProfileDialog,
                icon: const Icon(Icons.edit, size: 14, color: AppColors.primaryOrange),
                label: const Text('Edit Profil', style: TextStyle(color: AppColors.primaryOrange, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildLevelProgressCard() {
    final nextLevelXp = _runnerLevel * 500;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt, color: Colors.amber, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'Level $_runnerLevel',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white),
                  ),
                ],
              ),
              Text(
                '$_totalXp / $nextLevelXp XP',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _levelProgress,
              minHeight: 8,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryOrange),
            ),
          ),
          if (_profile.bonusXp > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Termasuk +${_profile.bonusXp} XP dari klaim hadiah tantangan',
              style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecordCard(String title, String value, IconData icon, Color accent) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                const SizedBox(height: 2),
                Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllTimeStat(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryOrange, size: 18),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildBadgeTile(_AchievementBadge badge) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: badge.unlocked ? AppColors.cardDark : AppColors.cardDark.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: badge.unlocked ? badge.color.withValues(alpha: 0.5) : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: badge.unlocked ? badge.color.withValues(alpha: 0.2) : Colors.white10,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  badge.icon,
                  size: 18,
                  color: badge.unlocked ? badge.color : Colors.white24,
                ),
              ),
              Icon(
                badge.unlocked ? Icons.check_circle : Icons.lock_outline,
                size: 16,
                color: badge.unlocked ? AppColors.accentGreen : Colors.white24,
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                badge.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: badge.unlocked ? Colors.white : Colors.white38,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                badge.subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: badge.unlocked ? AppColors.textSecondary : Colors.white24,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}