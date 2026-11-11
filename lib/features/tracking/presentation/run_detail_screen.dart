import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/run_storage_service.dart';
import '../domain/run_model.dart';

class RunDetailScreen extends StatelessWidget {
  final RunModel run;

  const RunDetailScreen({super.key, required this.run});

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    final hours = (totalSeconds ~/ 3600);

    if (hours > 0) {
      final hrs = hours.toString().padLeft(2, '0');
      return '$hrs:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Hapus Aktivitas?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Aktivitas ini akan dihapus secara permanen dari riwayat Anda.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final storageService = RunStorageService();
              await storageService.deleteRun(run.id);

              if (context.mounted) {
                Navigator.pop(ctx); // Tutup Dialog
                Navigator.pop(context, true); // Kembali ke Home & kirim trigger refresh
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Aktivitas berhasil dihapus')),
                );
              }
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LatLng initialCenter = run.routePoints.isNotEmpty
        ? run.routePoints.first
        : const LatLng(-6.9175, 107.6191);

    return Scaffold(
      appBar: AppBar(
        title: Text(run.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.cardDark,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: ListView(
        children: [
          // 1. PETA RUTE
          SizedBox(
            height: 320,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: 16.0,
              ),
              children: [
                TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.example.adventure_runner',
  tileBuilder: (context, tileWidget, tile) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -1.0,  0.0,  0.0, 0.0, 255.0,
         0.0, -1.0,  0.0, 0.0, 255.0,
         0.0,  0.0, -1.0, 0.0, 255.0,
         0.0,  0.0,  0.0, 1.0,   0.0,
      ]),
      child: tileWidget,
    );
  },
),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: run.routePoints,
                      strokeWidth: 5.0,
                      color: AppColors.primaryOrange,
                    ),
                  ],
                ),
                if (run.routePoints.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: run.routePoints.first,
                        width: 14,
                        height: 14,
                        child: Container(
                          decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                        ),
                      ),
                      Marker(
                        point: run.routePoints.last,
                        width: 14,
                        height: 14,
                        child: Container(
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // 2. STATISTIK LENGKAP
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(run.date, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 4),
                Text(run.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildDetailStat('Jarak', '${run.distanceInKm.toStringAsFixed(2)} km'),
                          _buildDetailStat('Pace Rata-rata', '${run.pace} /km'),
                        ],
                      ),
                      const Divider(height: 30, color: Colors.grey),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildDetailStat('Waktu', _formatDuration(run.durationInSeconds)),
                          _buildDetailStat('Kalori', '${run.calories.toStringAsFixed(0)} kcal'),
                        ],
                      ),
                      const Divider(height: 30, color: Colors.grey),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildDetailStat('Langkah', '${run.steps} step'),
                          _buildDetailStat('Status', 'Selesai'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}