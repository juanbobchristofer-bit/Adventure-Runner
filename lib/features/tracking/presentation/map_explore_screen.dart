import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';

class MapExploreScreen extends StatelessWidget {
  const MapExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(-6.9311, 107.7733), // Kawasan Jatinangor / Sumedang
              initialZoom: 14.0,
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
            ],
          ),

          // Search Bar & Filter Chip (Gaya Strava)
          Positioned(
            top: 50,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const TextField(
                    decoration: InputDecoration(
                      hintText: 'Cari Rute & Popular Heatmaps...',
                      border: InputBorder.none,
                      icon: Icon(Icons.search, color: AppColors.primaryOrange),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildChip('Rute Popular', true),
                      _buildChip('Panjang > 5km', false),
                      _buildChip('Elevasi', false),
                      _buildChip('Permukaan', false),
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

  Widget _buildChip(String label, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primaryOrange : AppColors.cardDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}