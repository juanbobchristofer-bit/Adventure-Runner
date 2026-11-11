import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/run_storage_service.dart';
import '../domain/run_model.dart';
import 'run_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final RunStorageService _storageService = RunStorageService();
  List<RunModel> _savedRuns = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRuns();
  }

  Future<void> _loadRuns() async {
    final runs = await _storageService.getSavedRuns();
    if (mounted) {
      setState(() {
        _savedRuns = runs;
        _isLoading = false;
      });
    }
  }

  double get _totalDistance => _savedRuns.fold(0.0, (sum, item) => sum + item.distanceInKm);
  int get _totalSeconds => _savedRuns.fold(0, (sum, item) => sum + item.durationInSeconds);

  String _formatTotalTime(int seconds) {
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    return '${hours}j ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ADVENTURE RUNNER', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        backgroundColor: AppColors.cardDark,
        elevation: 0,
        actions: [
          IconButton(onPressed: _loadRuns, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
          : RefreshIndicator(
              onRefresh: _loadRuns,
              color: AppColors.primaryOrange,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Cuplikan Aktivitas Anda', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildSummaryColumn('Aktivitas', '${_savedRuns.length}'),
                            _buildSummaryColumn('Waktu', _formatTotalTime(_totalSeconds)),
                            _buildSummaryColumn('Jarak', '${_totalDistance.toStringAsFixed(2)} km'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Aktivitas Terbaru', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),

                  if (_savedRuns.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(30),
                      alignment: Alignment.center,
                      child: const Text('Belum ada aktivitas lari. Klik tab Rekam untuk mulai!', style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ..._savedRuns.map((run) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Dismissible(
                            key: Key(run.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (direction) async {
                              await _storageService.deleteRun(run.id);
                              _loadRuns();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Aktivitas dihapus')),
                                );
                              }
                            },
                            child: _buildActivityCard(context, run),
                          ),
                        )),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryColumn(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ],
    );
  }

  Widget _buildActivityCard(BuildContext context, RunModel run) {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RunDetailScreen(run: run),
          ),
        );

        if (result == true) {
          _loadRuns(); // Reload jika aktivitas dihapus dari halaman detail
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.primaryOrange,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Juan Haloho', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(run.date, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(run.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Jarak', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    Text('${run.distanceInKm.toStringAsFixed(2)} km', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pace', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    Text('${run.pace} /km', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Langkah', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    Text('${run.steps} step', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}