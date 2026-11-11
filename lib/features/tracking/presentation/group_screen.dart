import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Grup & Komunitas', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.cardDark,
          bottom: const TabBar(
            indicatorColor: AppColors.primaryOrange,
            labelColor: AppColors.primaryOrange,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'Tantangan'),
              Tab(text: 'Klub'),
              Tab(text: 'Acara'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab Tantangan
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildCard('Tantangan September 50K', 'Berlari total 50km bulan ini', '1,240 Peserta'),
                _buildCard('Weekend 10K Run', 'Selesaikan 10km dalam 1 sesi di akhir pekan', '850 Peserta'),
              ],
            ),
            // Tab Klub
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildCard('Runner Club Sumedang', 'Komunitas lari area Sumedang & Jatinangor', '117 Anggota'),
                _buildCard('Bandung Trail Runners', 'Klub lari lintas alam', '430 Anggota'),
              ],
            ),
            // Tab Acara
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildCard('Siliwangi Night Run', 'Stadion Siliwangi, Bandung • 30 Sep', '117 Anggota Hadir'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(String title, String subtitle, String info) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.people, size: 16, color: AppColors.primaryOrange),
              const SizedBox(width: 6),
              Text(info, style: const TextStyle(color: AppColors.primaryOrange, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}