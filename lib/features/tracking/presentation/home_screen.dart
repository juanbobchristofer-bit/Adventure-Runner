import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/profile_storage_service.dart';
import '../../../core/services/run_storage_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/mini_route_painter.dart';
import '../domain/run_model.dart';
import '../domain/runner_stats.dart';
import 'run_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final RunStorageService _storageService = RunStorageService();
  final ProfileStorageService _profileService = ProfileStorageService();

  List<RunModel> _savedRuns = [];
  Set<String> _validPhotoRunIds = {};
  UserProfileData _profile = UserProfileData.defaultProfile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRunsAndProfile();
    ProfileStorageService.profileUpdateNotifier.addListener(_loadRunsAndProfile);
    RunStorageService.runUpdateNotifier.addListener(_loadRunsAndProfile);
  }

  @override
  void dispose() {
    ProfileStorageService.profileUpdateNotifier.removeListener(_loadRunsAndProfile);
    RunStorageService.runUpdateNotifier.removeListener(_loadRunsAndProfile);
    super.dispose();
  }

  Future<void> _loadRunsAndProfile() async {
    final runs = await _storageService.getSavedRuns();
    final profile = await _profileService.getProfile();
    final validPhotos = <String>{};
    for (final run in runs) {
      if (run.photoPath != null && await File(run.photoPath!).exists()) {
        validPhotos.add(run.id);
      }
    }
    if (mounted) {
      setState(() {
        _savedRuns = runs;
        _validPhotoRunIds = validPhotos;
        _profile = profile;
        _isLoading = false;
      });
    }
  }

  double get _totalDistance => RunnerStats.totalDistance(_savedRuns);
  double get _weeklyDistance => RunnerStats.weeklyDistance(_savedRuns);
  int get _totalSeconds => RunnerStats.totalDurationSeconds(_savedRuns);
  double get _totalCalories => RunnerStats.totalCalories(_savedRuns);

  String get _runnerRank => RunnerStats.rankTitle(_savedRuns, bonusXp: _profile.bonusXp);

  List<double> get _recentBarValues {
    if (_savedRuns.isEmpty) return List.filled(7, 0.0);
    final recent = _savedRuns.take(7).toList().reversed.toList();
    final padded = List<double>.filled(7, 0.0);
    for (int i = 0; i < recent.length; i++) {
      padded[7 - recent.length + i] = recent[i].distanceInKm;
    }
    return padded;
  }

  Future<void> _showEditGoalDialog() async {
    final controller = TextEditingController(text: _profile.weeklyGoalKm.toStringAsFixed(0));
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Target Jarak Lari (km)', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Contoh: 20',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primaryOrange)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primaryOrange, width: 2)),
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
              final val = double.tryParse(controller.text.replaceAll(',', '.').trim());
              if (val == null || val <= 0 || val > 1000) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Masukkan target jarak antara 1 - 1000 km.'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
                return;
              }
              await _profileService.saveWeeklyGoal(val);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double safeGoalKm = _profile.weeklyGoalKm > 0 ? _profile.weeklyGoalKm : 15.0;
    final double goalProgress = (_weeklyDistance / safeGoalKm).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
          : RefreshIndicator(
              onRefresh: _loadRunsAndProfile,
              color: AppColors.primaryOrange,
              child: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 105,
                    floating: true,
                    pinned: true,
                    backgroundColor: AppColors.backgroundDark,
                    elevation: 0,
                    flexibleSpace: FlexibleSpaceBar(
                      titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.primaryOrange,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.bolt, color: Colors.white, size: 16),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'ADVENTURE RUNNER',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 1.2,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      IconButton(
                        tooltip: 'Refresh Data',
                        onPressed: _loadRunsAndProfile,
                        icon: const Icon(Icons.sync, color: Colors.white70),
                      ),
                    ],
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildHeroPerformanceCard(goalProgress),
                        const SizedBox(height: 16),
                        _buildPerformanceChartCard(),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Riwayat Aktivitas',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.cardDark,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Text(
                                '${_savedRuns.length} Sesi',
                                style: const TextStyle(color: AppColors.primaryOrange, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_savedRuns.isEmpty)
                          _buildEmptyState()
                        else
                          ..._savedRuns.map((run) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Dismissible(
                                  key: Key(run.id),
                                  direction: DismissDirection.endToStart,
                                  confirmDismiss: (_) async {
                                    return await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: AppColors.cardDark,
                                            title: const Text('Hapus Aktivitas?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            content: Text(
                                              'Hapus "${run.title}" secara permanen dari riwayat?',
                                              style: const TextStyle(color: AppColors.textSecondary),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx, false),
                                                child: const Text('Batal', style: TextStyle(color: Colors.grey)),
                                              ),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                onPressed: () => Navigator.pop(ctx, true),
                                                child: const Text('Hapus', style: TextStyle(color: Colors.white)),
                                              ),
                                            ],
                                          ),
                                        ) ??
                                        false;
                                  },
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 22),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.delete_outline, color: Colors.white, size: 28),
                                        SizedBox(height: 4),
                                        Text('Hapus', style: TextStyle(color: Colors.white, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  onDismissed: (direction) async {
                                    await _storageService.deleteRun(run.id);
                                    _loadRunsAndProfile();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Aktivitas lari dihapus'),
                                          backgroundColor: AppColors.cardElevated,
                                        ),
                                      );
                                    }
                                  },
                                  child: _buildModernActivityCard(context, run),
                                ),
                              )),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroPerformanceCard(double goalProgress) {
    final hasAvatar = _profile.avatarPath != null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF251A16), AppColors.cardDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.35), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      value: goalProgress,
                      strokeWidth: 4.5,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryOrange),
                    ),
                  ),
                  CircleAvatar(
                    radius: 29,
                    backgroundColor: AppColors.cardElevated,
                    backgroundImage: hasAvatar ? FileImage(File(_profile.avatarPath!)) : null,
                    child: !hasAvatar ? const Icon(Icons.person, color: Colors.white70, size: 28) : null,
                  ),
                ],
              ),
              const SizedBox(width: 14),
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
                        _runnerRank,
                        style: const TextStyle(
                          color: AppColors.primaryOrange,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _profile.name,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    GestureDetector(
                      onTap: _showEditGoalDialog,
                      child: Row(
                        children: [
                          Text(
                            'Target Minggu Ini: ${_weeklyDistance.toStringAsFixed(1)} / ${_profile.weeklyGoalKm.toStringAsFixed(0)} km (${(goalProgress * 100).toInt()}%)',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit, size: 12, color: AppColors.primaryOrange),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetricPill(Icons.straighten, 'Total Jarak', '${_totalDistance.toStringAsFixed(2)} km', AppColors.primaryOrange),
              _buildMetricPill(Icons.timer_outlined, 'Total Waktu', AppFormatters.formatCompactDuration(_totalSeconds), AppColors.accentBlue),
              _buildMetricPill(Icons.local_fire_department_outlined, 'Kalori', '${_totalCalories.toStringAsFixed(0)} kcal', AppColors.accentGreen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricPill(IconData icon, String label, String value, Color accentColor) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: accentColor, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceChartCard() {
    final values = _recentBarValues;
    final double maxVal = values.reduce(math.max);
    final double chartMax = maxVal > 0 ? maxVal : 5.0;

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
              const Text(
                'Tren Jarak (7 Sesi Terakhir)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
              Text(
                'Maks: ${maxVal.toStringAsFixed(1)} km',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 95,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (index) {
                final val = values[index];
                final double ratio = (val / chartMax).clamp(0.08, 1.0);
                final bool isLatest = index == 6 && val > 0;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      val > 0 ? val.toStringAsFixed(1) : '-',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isLatest ? FontWeight.bold : FontWeight.normal,
                        color: isLatest ? AppColors.primaryOrange : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      width: 24,
                      height: 62 * ratio,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: isLatest
                              ? [AppColors.primaryOrange, AppColors.primaryOrangeLight]
                              : val > 0
                                  ? [AppColors.primaryOrange.withValues(alpha: 0.45), AppColors.primaryOrange.withValues(alpha: 0.75)]
                                  : [Colors.white10, Colors.white10],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('S${index + 1}', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernActivityCard(BuildContext context, RunModel run) {
    final String badgeLabel = run.distanceInKm >= 10
        ? '10K PRO'
        : run.distanceInKm >= 5
            ? '5K RUN'
            : 'DAILY RUN';
    final bool hasPhoto = run.photoPath != null && _validPhotoRunIds.contains(run.id);
    final bool hasUserAvatar = _profile.avatarPath != null;

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => RunDetailScreen(run: run)),
        );
        if (result == true) _loadRunsAndProfile();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Post ala Strava (Avatar + Nama + Tanggal + Badge)
            Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: AppColors.cardElevated,
                  backgroundImage: hasUserAvatar ? FileImage(File(_profile.avatarPath!)) : null,
                  child: !hasUserAvatar ? const Icon(Icons.person, size: 18, color: Colors.white70) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _profile.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white),
                      ),
                      Text(
                        '${run.date} â€¢ ${_profile.city}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badgeLabel,
                    style: const TextStyle(color: AppColors.primaryOrange, fontSize: 10, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Judul, Feeling & Caption Pengalaman Lari
            Text(
              run.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            if (run.feeling.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                run.feeling,
                style: const TextStyle(color: AppColors.primaryOrangeLight, fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ],
            if (run.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                run.notes,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),

            // Media Showcase: Foto Momen Lari + Mini Trek Rute GPS
            if (hasPhoto)
              SizedBox(
                height: 165,
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(run.photoPath!),
                          height: 165,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 165,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: SizedBox.expand(
                                child: CustomPaint(painter: MiniRoutePainter(run.routePoints)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text('GPS TRACK', style: TextStyle(color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                height: 85,
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.backgroundDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: CustomPaint(
                        size: const Size(double.infinity, 60),
                        painter: MiniRoutePainter(run.routePoints),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${run.calories.toStringAsFixed(0)} kcal\n${run.steps} langkah',
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 14),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 12),

            // Baris Statistik Bawah
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCardStat('JARAK', '${run.distanceInKm.toStringAsFixed(2)} km'),
                _buildCardStat('AVG PACE', '${run.pace} /km'),
                _buildCardStat('DURASI', AppFormatters.formatCompactDuration(run.durationInSeconds)),
                const Icon(Icons.chevron_right, color: AppColors.primaryOrange),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, letterSpacing: 0.5)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: const Column(
        children: [
          Icon(Icons.directions_run, size: 48, color: AppColors.primaryOrange),
          SizedBox(height: 12),
          Text('Siap Memulai Petualangan?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
          SizedBox(height: 6),
          Text(
            'Belum ada rekaman lari. Buka tab Rekam di bawah untuk mulai melacak rute GPS pertamamu!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}