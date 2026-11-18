import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/run_storage_service.dart';
import 'record_run_screen.dart';

class ExploreRoute {
  final String id;
  final String name;
  final String location;
  final String category; // 'Popular', 'Long Run', 'Trail', 'My Route'
  final double distanceKm;
  final int elevationGainM;
  final String surface;
  final String difficulty;
  final Color color;
  final List<LatLng> points;

  const ExploreRoute({
    required this.id,
    required this.name,
    required this.location,
    required this.category,
    required this.distanceKm,
    required this.elevationGainM,
    required this.surface,
    required this.difficulty,
    required this.color,
    required this.points,
  });
}

class MapExploreScreen extends StatefulWidget {
  const MapExploreScreen({super.key});

  @override
  State<MapExploreScreen> createState() => _MapExploreScreenState();
}

class _MapExploreScreenState extends State<MapExploreScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final LocationService _locationService = LocationService();
  final RunStorageService _storageService = RunStorageService();

  String _selectedFilter = 'Semua';
  String _searchQuery = '';
  int _selectedRouteIndex = 0;
  LatLng? _currentUserLocation;
  bool _isLocating = false;

  // Rute kurasi siap pakai di kawasan Jatinangor / Bandung Timur
  final List<ExploreRoute> _curatedRoutes = const [
    ExploreRoute(
      id: 'rt_unpad_loop',
      name: 'Unpad Jatinangor Campus Loop',
      location: 'Jatinangor, Sumedang',
      category: 'Popular',
      distanceKm: 4.8,
      elevationGainM: 65,
      surface: 'Aspal & Paving',
      difficulty: 'Menengah',
      color: AppColors.primaryOrange,
      points: [
        LatLng(-6.9311, 107.7733),
        LatLng(-6.9275, 107.7748),
        LatLng(-6.9242, 107.7725),
        LatLng(-6.9260, 107.7690),
        LatLng(-6.9298, 107.7705),
        LatLng(-6.9311, 107.7733),
      ],
    ),
    ExploreRoute(
      id: 'rt_kiara_long',
      name: 'Cileunyi - Jatinangor Endurance 7K',
      location: 'Cileunyi - Jatinangor',
      category: 'Long Run',
      distanceKm: 7.4,
      elevationGainM: 110,
      surface: 'Aspal Raya',
      difficulty: 'Menantang',
      color: AppColors.accentBlue,
      points: [
        LatLng(-6.9385, 107.7520),
        LatLng(-6.9362, 107.7585),
        LatLng(-6.9340, 107.7655),
        LatLng(-6.9318, 107.7720),
        LatLng(-6.9290, 107.7775),
      ],
    ),
    ExploreRoute(
      id: 'rt_manglayang_trail',
      name: 'Kaki Gunung Manglayang Trail',
      location: 'Kaki Manglayang, Jatinangor',
      category: 'Trail',
      distanceKm: 5.6,
      elevationGainM: 245,
      surface: 'Tanah & Makadam',
      difficulty: 'Berat',
      color: AppColors.accentGreen,
      points: [
        LatLng(-6.9155, 107.7620),
        LatLng(-6.9110, 107.7645),
        LatLng(-6.9072, 107.7610),
        LatLng(-6.9095, 107.7575),
        LatLng(-6.9155, 107.7620),
      ],
    ),
    ExploreRoute(
      id: 'rt_stadion_sprint',
      name: 'Track Sprint & Tempo Interval',
      location: 'Kawasan Olahraga Jatinangor',
      category: 'Popular',
      distanceKm: 3.2,
      elevationGainM: 18,
      surface: 'Lintasan Datar',
      difficulty: 'Pemula',
      color: Color(0xFFE040FB),
      points: [
        LatLng(-6.9288, 107.7760),
        LatLng(-6.9265, 107.7785),
        LatLng(-6.9245, 107.7768),
        LatLng(-6.9270, 107.7745),
        LatLng(-6.9288, 107.7760),
      ],
    ),
  ];

  List<ExploreRoute> _mySavedAsExploreRoutes = [];

  @override
  void initState() {
    super.initState();
    _loadUserSavedRoutes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Mengambil riwayat lari user dari SharedPreferences agar bisa ditampilkan di peta Explore
  Future<void> _loadUserSavedRoutes() async {
    final runs = await _storageService.getSavedRuns();
    final mapped = runs.where((r) => r.routePoints.length >= 2).map((r) {
      return ExploreRoute(
        id: r.id,
        name: r.title,
        location: 'Rekaman Saya • ${r.date}',
        category: 'Rute Saya',
        distanceKm: r.distanceInKm,
        elevationGainM: (r.distanceInKm * 12).round(),
        surface: 'GPS Recorded',
        difficulty: 'Riwayat',
        color: Colors.amberAccent,
        points: r.routePoints,
      );
    }).toList();

    if (mounted) {
      setState(() {
        _mySavedAsExploreRoutes = mapped;
      });
    }
  }

  List<ExploreRoute> get _filteredRoutes {
    final allRoutes = [..._curatedRoutes, ..._mySavedAsExploreRoutes];
    return allRoutes.where((route) {
      final matchesSearch = _searchQuery.isEmpty ||
          route.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          route.location.toLowerCase().contains(_searchQuery.toLowerCase());

      if (!matchesSearch) return false;

      switch (_selectedFilter) {
        case 'Rute Popular':
          return route.category == 'Popular';
        case 'Panjang > 5km':
          return route.distanceKm > 5.0;
        case 'Trail / Tanjakan':
          return route.category == 'Trail' || route.elevationGainM >= 150;
        case 'Rute Saya':
          return route.category == 'Rute Saya';
        default:
          return true;
      }
    }).toList();
  }

  void _focusRouteOnMap(ExploreRoute route) {
    if (route.points.isEmpty) return;
    double sumLat = 0;
    double sumLng = 0;
    for (final p in route.points) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    final center = LatLng(sumLat / route.points.length, sumLng / route.points.length);
    _mapController.move(center, 14.8);
  }

  Future<void> _goToMyLocation() async {
    setState(() => _isLocating = true);
    final hasPermission = await _locationService.requestPermission();
    if (!hasPermission) {
      if (mounted) {
        setState(() => _isLocating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aktifkan GPS & izin lokasi terlebih dahulu.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final userLatLng = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _currentUserLocation = userLatLng;
          _isLocating = false;
        });
        _mapController.move(userLatLng, 15.5);
      }
    } catch (_) {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _showRouteDetailSheet(ExploreRoute route) {
    final estMinutes = (route.distanceKm * 6.2).round();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: route.color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    route.category.toUpperCase(),
                    style: TextStyle(color: route.color, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                Text(route.difficulty, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Text(route.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on, size: 14, color: AppColors.primaryOrange),
                const SizedBox(width: 4),
                Text(route.location, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSheetMetric('Jarak', '${route.distanceKm.toStringAsFixed(1)} km'),
                _buildSheetMetric('Elevasi', '+${route.elevationGainM} m'),
                _buildSheetMetric('Est. Waktu', '~$estMinutes mnt'),
                _buildSheetMetric('Permukaan', route.surface),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RecordRunScreen()),
                  );
                },
                icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                label: const Text(
                  'Mulai Lari di Rute Ini',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetMetric(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final routes = _filteredRoutes;
    final safeIndex = routes.isEmpty ? 0 : _selectedRouteIndex.clamp(0, routes.length - 1);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          // 1. PETA INTERAKTIF + POLYLINE RUTE + MARKER
          FlutterMap(
            mapController: _mapController,
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

              // Gambar semua jalur rute yang lolos filter
              PolylineLayer(
                polylines: List.generate(routes.length, (idx) {
                  final r = routes[idx];
                  final isSelected = idx == safeIndex;
                  return Polyline(
                    points: r.points,
                    strokeWidth: isSelected ? 6.0 : 3.5,
                    color: isSelected ? r.color : r.color.withOpacity(0.45),
                  );
                }),
              ),

              // Marker Titik Start tiap rute + Lokasi Pengguna saat ini
              MarkerLayer(
                markers: [
                  ...List.generate(routes.length, (idx) {
                    final r = routes[idx];
                    final isSelected = idx == safeIndex;
                    return Marker(
                      point: r.points.first,
                      width: isSelected ? 42 : 32,
                      height: isSelected ? 42 : 32,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedRouteIndex = idx);
                          _focusRouteOnMap(r);
                          _showRouteDetailSheet(r);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected ? r.color : AppColors.cardDark,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
                          ),
                          child: Icon(
                            Icons.directions_run,
                            color: isSelected ? Colors.white : r.color,
                            size: isSelected ? 20 : 15,
                          ),
                        ),
                      ),
                    );
                  }),
                  if (_currentUserLocation != null)
                    Marker(
                      point: _currentUserLocation!,
                      width: 26,
                      height: 26,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 2. SEARCH BAR & FILTER CHIP AKTIF
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _selectedRouteIndex = 0;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Cari rute (Unpad, Cileunyi, Manglayang...)',
                      hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      border: InputBorder.none,
                      icon: const Icon(Icons.search, color: AppColors.primaryOrange),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _selectedRouteIndex = 0;
                                });
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('Semua'),
                      _buildFilterChip('Rute Popular'),
                      _buildFilterChip('Panjang > 5km'),
                      _buildFilterChip('Trail / Tanjakan'),
                      _buildFilterChip('Rute Saya'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 3. TOMBOL GPS LOKASI SAYA (FLOATING RIGHT)
          Positioned(
            right: 16,
            bottom: 185,
            child: FloatingActionButton.small(
              heroTag: 'btn_my_location',
              backgroundColor: AppColors.cardDark,
              onPressed: _isLocating ? null : _goToMyLocation,
              child: _isLocating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryOrange),
                    )
                  : const Icon(Icons.my_location, color: AppColors.primaryOrange),
            ),
          ),

          // 4. CAROUSEL KARTU RUTE DI BAGIAN BAWAH
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            height: 155,
            child: routes.isEmpty
                ? Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Center(
                      child: Text(
                        _selectedFilter == 'Rute Saya'
                            ? 'Belum ada rute tersimpan. Rekam larimu dulu!'
                            : 'Tidak ada rute yang cocok dengan pencarian "$_searchQuery".',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: routes.length,
                    itemBuilder: (context, index) {
                      final route = routes[index];
                      final isSelected = index == safeIndex;

                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedRouteIndex = index);
                          _focusRouteOnMap(route);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 275,
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.cardDark.withOpacity(0.96),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? route.color : Colors.white12,
                              width: isSelected ? 1.8 : 1.0,
                            ),
                            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: route.color.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      route.category.toUpperCase(),
                                      style: TextStyle(
                                        color: route.color,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${route.distanceKm.toStringAsFixed(1)} km',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    route.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${route.location} • +${route.elevationGainM}m',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    route.surface,
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                  ),
                                  InkWell(
                                    onTap: () => _showRouteDetailSheet(route),
                                    child: Row(
                                      children: [
                                        Text(
                                          'Detail & Mulai',
                                          style: TextStyle(
                                            color: route.color,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Icon(Icons.arrow_forward_ios, size: 11, color: route.color),
                                      ],
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
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = label;
          _selectedRouteIndex = 0;
        });
        if (_filteredRoutes.isNotEmpty) {
          _focusRouteOnMap(_filteredRoutes.first);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryOrange : AppColors.cardDark.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primaryOrange : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}