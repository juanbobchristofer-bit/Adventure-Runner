import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/pedometer_service.dart';
import '../../../core/services/run_storage_service.dart';
import '../domain/run_model.dart';

class RecordRunScreen extends StatefulWidget {
  const RecordRunScreen({super.key});

  @override
  State<RecordRunScreen> createState() => _RecordRunScreenState();
}

class _RecordRunScreenState extends State<RecordRunScreen> {
  final LocationService _locationService = LocationService();
  final PedometerService _pedometerService = PedometerService();
  final RunStorageService _storageService = RunStorageService();
  final MapController _mapController = MapController();

  bool _isTracking = false;
  bool _isLoadingLocation = true;
  Position? _currentPosition;

  final List<LatLng> _routePoints = [];
  double _totalDistanceInMeters = 0.0;
  int _stepCount = 0;

  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _fetchInitialLocation();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchInitialLocation() async {
    bool hasPermission = await _locationService.requestPermission();
    if (!hasPermission) {
      if (mounted) setState(() => _isLoadingLocation = false);
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        final initialLatLng = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentPosition = position;
          _isLoadingLocation = false;
        });
        _mapController.move(initialLatLng, 17.0);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  void _recenterMap() {
    if (_currentPosition != null) {
      _mapController.move(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        17.0,
      );
    }
  }

  void _startTimer() {
    _elapsedSeconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

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

  String _calculatePace() {
    if (_totalDistanceInMeters < 10 || _elapsedSeconds == 0) return "--:--";
    final double distanceInKm = _totalDistanceInMeters / 1000;
    final double paceInSecondsPerKm = _elapsedSeconds / distanceInKm;

    final int minutes = paceInSecondsPerKm ~/ 60;
    final int seconds = (paceInSecondsPerKm % 60).toInt();

    if (minutes > 99) return "--:--";
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _toggleTracking() async {
    if (!_isTracking) {
      bool hasPermission = await _locationService.requestPermission();
      if (!hasPermission) return;

      setState(() {
        _isTracking = true;
        _routePoints.clear();
        _totalDistanceInMeters = 0.0;
        _stepCount = 0;
      });

      _startTimer();

      _locationService.getPositionStream().listen((Position position) {
        if (!mounted) return;
        final newLatLng = LatLng(position.latitude, position.longitude);

        if (_routePoints.isNotEmpty) {
          final lastLatLng = _routePoints.last;
          final distance = Geolocator.distanceBetween(
            lastLatLng.latitude,
            lastLatLng.longitude,
            newLatLng.latitude,
            newLatLng.longitude,
          );
          _totalDistanceInMeters += distance;
        }

        setState(() {
          _currentPosition = position;
          _routePoints.add(newLatLng);
        });

        _mapController.move(newLatLng, 17.0);
      });

      _pedometerService.getStepCountStream().listen((int steps) {
        if (!mounted) return;
        setState(() => _stepCount = steps);
      });
    } else {
      _stopTimer();
      _locationService.stopTracking();
      _pedometerService.stopTracking();
      setState(() => _isTracking = false);

      _showSaveRunDialog();
    }
  }

  void _showSaveRunDialog() {
    final titleController = TextEditingController(text: "Lari Sore");
    final double distanceKm = _totalDistanceInMeters / 1000;
    final double calories = distanceKm * 60;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Simpan Aktivitas Lari', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Judul Aktivitas',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primaryOrange),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Jarak: ${distanceKm.toStringAsFixed(2)} KM'),
            Text('Waktu: ${_formatDuration(_elapsedSeconds)}'),
            Text('Pace: ${_calculatePace()} /km'),
            Text('Langkah: $_stepCount step'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetStats();
            },
            child: const Text('Buang', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
            onPressed: () async {
              final newRun = RunModel(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                title: titleController.text.isEmpty ? "Lari Sore" : titleController.text,
                date: "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}",
                distanceInKm: distanceKm,
                durationInSeconds: _elapsedSeconds,
                pace: _calculatePace(),
                steps: _stepCount,
                calories: calories,
                routePoints: List.from(_routePoints),
              );

              await _storageService.saveRun(newRun);

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Aktivitas berhasil disimpan ke Home!')),
                );
                _resetStats();
              }
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _resetStats() {
    setState(() {
      _routePoints.clear();
      _totalDistanceInMeters = 0.0;
      _stepCount = 0;
      _elapsedSeconds = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentLatLng = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(-6.9175, 107.6191);

    return Scaffold(
      body: Stack(
        children: [
          // 1. ESRI DARK GRAY CANVAS MAP (STABIL & TANPA WATERMARK)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentLatLng,
              initialZoom: 17.0,
            ),
            children: [
              TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.example.adventure_runner',
  tileBuilder: (context, tileWidget, tile) {
    // Memberikan filter Invert + Darken agar OSM menjadi Dark Mode
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
                    points: _routePoints,
                    strokeWidth: 5.0,
                    color: AppColors.primaryOrange,
                  ),
                ],
              ),
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: currentLatLng,
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primaryOrange.withOpacity(0.25),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Center(
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: const BoxDecoration(
                              color: AppColors.primaryOrange,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          if (_isLoadingLocation)
            Container(
              color: Colors.black87,
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.primaryOrange),
              ),
            ),

          // 2. TOMBOL AKSI SAMPING MAP
          Positioned(
            right: 16,
            bottom: 250,
            child: Column(
              children: [
                _buildSideIconButton(
                  icon: Icons.my_location,
                  onTap: _recenterMap,
                ),
              ],
            ),
          ),

          // 3. FLOATING STATS PANEL & CONTROL SHEET
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF161616),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 10,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 12),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade700,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.signal_cellular_alt,
                          size: 14,
                          color: _currentPosition != null ? Colors.greenAccent : Colors.orangeAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _currentPosition != null ? 'GPS Didapat' : 'Mencari Signal GPS...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _currentPosition != null ? Colors.greenAccent : Colors.orangeAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStravaMetric('Waktu', _formatDuration(_elapsedSeconds)),
                        Container(height: 30, width: 1, color: Colors.grey.shade800),
                        _buildStravaMetric('Rata2 split (/km)', _calculatePace()),
                        Container(height: 30, width: 1, color: Colors.grey.shade800),
                        _buildStravaMetric('Jarak (km)', (_totalDistanceInMeters / 1000).toStringAsFixed(2)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.only(bottom: 28, left: 32, right: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2C2C2C),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.directions_run, color: AppColors.primaryOrange),
                            ),
                            const SizedBox(height: 6),
                            const Text('Berlari', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),

                        GestureDetector(
                          onTap: _toggleTracking,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: _isTracking ? Colors.redAccent : AppColors.primaryOrange,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (_isTracking ? Colors.redAccent : AppColors.primaryOrange).withOpacity(0.4),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                )
                              ],
                            ),
                            child: Icon(
                              _isTracking ? Icons.stop : Icons.play_arrow,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                        ),

                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2C2C2C),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '$_stepCount',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text('Langkah', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStravaMetric(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildSideIconButton({required IconData icon, required VoidCallback onTap}) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 6)],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onTap,
      ),
    );
  }
}