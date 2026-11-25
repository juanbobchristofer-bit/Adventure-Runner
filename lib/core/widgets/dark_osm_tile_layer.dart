import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../constants/app_colors.dart';
import '../services/offline_tile_provider.dart';

/// TileLayer OpenStreetMap dark-mode yang dapat dipakai ulang, dilengkapi disk caching offline
/// dan header User-Agent yang patuh terhadap OSM Tile Usage Policy.
class DarkOsmTileLayer extends StatefulWidget {
  const DarkOsmTileLayer({super.key});

  @override
  State<DarkOsmTileLayer> createState() => _DarkOsmTileLayerState();
}

class _DarkOsmTileLayerState extends State<DarkOsmTileLayer> {
  static const List<double> _darkInvertMatrix = [
    -1.0,  0.0,  0.0, 0.0, 255.0,
     0.0, -1.0,  0.0, 0.0, 255.0,
     0.0,  0.0, -1.0, 0.0, 255.0,
     0.0,  0.0,  0.0, 1.0,   0.0,
  ];

  late final OfflineCachedTileProvider _tileProvider;

  @override
  void initState() {
    super.initState();
    _tileProvider = OfflineCachedTileProvider();
  }

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.adventurerunner.app',
      tileProvider: _tileProvider,
      tileBuilder: (context, tileWidget, tile) {
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix(_darkInvertMatrix),
          child: tileWidget,
        );
      },
    );
  }
}

/// Badge atribusi resmi OpenStreetMap (wajib sesuai lisensi ODbL & OSM Tile Usage Policy).
class OsmAttributionBadge extends StatelessWidget {
  const OsmAttributionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.cardDark.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          '© OpenStreetMap',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
