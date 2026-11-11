import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/run_storage_service.dart';
import '../domain/run_model.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final RunStorageService _storageService = RunStorageService();
  List<RunModel> _savedRuns = [];
  bool _isLoading = true;
  String _userName = 'Pelari Adventure';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('user_profile_name') ?? 'Pelari Adventure';
    final runs = await _storageService.getSavedRuns();

    if (mounted) {
      setState(() {
        _userName = savedName;
        _savedRuns = runs;
        _isLoading = false;
      });
    }
  }

  Future<void> _showEditProfileDialog() async {
    final controller = TextEditingController(text: _userName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Edit Profil', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nama Lengkap',
            labelStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primaryOrange),
            ),
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
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('user_profile_name', newName);
                setState(() => _userName = newName);
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  double get _totalDistance => _savedRuns.fold(0.0, (sum, item) => sum + item.distanceInKm);
  int get _totalSeconds => _savedRuns.fold(0, (sum, item) => sum + item.durationInSeconds);

  String _formatHours(int seconds) {
    final double hours = seconds / 3600;
    return hours.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PROFIL', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        backgroundColor: AppColors.cardDark,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUserData),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
          : RefreshIndicator(
              onRefresh: _loadUserData,
              color: AppColors.primaryOrange,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Profile Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 32,
                              backgroundColor: AppColors.primaryOrange,
                              child: Icon(Icons.person, size: 36, color: Colors.white),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _userName,
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_savedRuns.length} aktivitas lari',
                                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.primaryOrange),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            minimumSize: const Size(double.infinity, 40),
                          ),
                          onPressed: _showEditProfileDialog,
                          icon: const Icon(Icons.edit, size: 16, color: AppColors.primaryOrange),
                          label: const Text('Edit Profil', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text('Statistik Sepanjang Masa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard('Total Jarak', '${_totalDistance.toStringAsFixed(2)} km', Icons.map),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard('Total Aktivitas', '${_savedRuns.length}', Icons.directions_run),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard('Total Waktu', '${_formatHours(_totalSeconds)} Jam', Icons.timer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard('Langkah Total', '${_savedRuns.fold(0, (s, i) => s + i.steps)}', Icons.directions_walk),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryOrange, size: 24),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}