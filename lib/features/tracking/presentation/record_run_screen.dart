import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/pedometer_service.dart';
import '../../../core/services/profile_storage_service.dart';
import '../../../core/services/run_storage_service.dart';
import '../domain/run_model.dart';

class _ActivityMode {
  final String name;
  final String defaultTitle;
  final IconData icon;
  final double calorieFactor;

  const _ActivityMode({
    required this.name,
    required this.defaultTitle,
    required this.icon,
    required this.calorieFactor,
  });
}

class RecordRunScreen extends StatefulWidget {
  const RecordRunScreen({super.key});

  @override
  State<RecordRunScreen> createState() => _RecordRunScreenState();
}

class _RecordRunScreenState extends State<RecordRunScreen> {
  final LocationService _locationService = LocationService();
  final PedometerService _pedometerService = PedometerService();
  final ProfileStorageService _profileService = ProfileStorageService();
  final MapController _mapController = MapController();

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<int>? _stepSub;
  Timer? _timer;
  Timer? _countdownTimer;

  // Status Tracking & Reliabilitas
  bool _isTracking = false;
  bool _isPaused = false;
  bool _isAutoPaused = false;
  bool _autoPauseEnabled = true;
  bool _isLoadingLocation = true;
  bool _autoFollowCamera = true;
  int _countdownValue = 0; // > 0 saat overlay 3-2-1 aktif

  Position? _currentPosition;
  final List<LatLng> _routePoints = [];
  double _totalDistanceInMeters = 0.0;
  int _stepCount = 0;
  int _stepOffsetBeforePause = 0;
  int _lastRawStreamSteps = 0;
  int _elapsedSeconds = 0;
  int _stationarySeconds = 0; // Penghitung detik diam untuk Auto-Pause
  double _userWeightKg = 65.0;

  final List<_ActivityMode> _modes = const [
    _ActivityMode(name: 'Lari', defaultTitle: 'Lari Harian', icon: Icons.directions_run, calorieFactor: 1.036),
    _ActivityMode(name: 'Trail', defaultTitle: 'Trail Adventure', icon: Icons.terrain, calorieFactor: 1.18),
    _ActivityMode(name: 'Tempo', defaultTitle: 'Tempo Sprint', icon: Icons.speed, calorieFactor: 1.12),
    _ActivityMode(name: 'Jalan', defaultTitle: 'Jalan Cepat', icon: Icons.directions_walk, calorieFactor: 0.75),
  ];
  int _selectedModeIndex = 0;

  _ActivityMode get _currentMode => _modes[_selectedModeIndex];
  bool get _effectivelyPaused => _isPaused || _isAutoPaused;

  @override
  void initState() {
    super.initState();
    _loadUserWeight();
    _fetchInitialLocation();
  }

  @override
  void dispose() {
    _cancelAllStreams();
    super.dispose();
  }

  void _cancelAllStreams() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    _positionSub?.cancel();
    _stepSub?.cancel();
    _locationService.stopTracking();
    _pedometerService.stopTracking();
  }

  Future<void> _loadUserWeight() async {
    final profile = await _profileService.getProfile();
    if (mounted) {
      setState(() => _userWeightKg = profile.weightKg);
    }
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
    setState(() => _autoFollowCamera = true);
    if (_currentPosition != null) {
      _mapController.move(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        17.0,
      );
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      if (_isTracking && !_isPaused && _autoPauseEnabled) {
        final currentSpeedMs = _currentPosition?.speed ?? 0.0;
        if (currentSpeedMs < 0.5) {
          _stationarySeconds++;
          if (_stationarySeconds >= 5 && !_isAutoPaused) {
            HapticFeedback.lightImpact();
            setState(() => _isAutoPaused = true);
          }
        } else {
          _stationarySeconds = 0;
          if (_isAutoPaused) {
            HapticFeedback.mediumImpact();
            setState(() => _isAutoPaused = false);
          }
        }
      }

      if (!_effectivelyPaused) {
        setState(() => _elapsedSeconds++);
      }
    });
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
    if (_totalDistanceInMeters < 15 || _elapsedSeconds == 0) return "--:--";
    final double distanceInKm = _totalDistanceInMeters / 1000;
    final double paceInSecondsPerKm = _elapsedSeconds / distanceInKm;

    final int minutes = paceInSecondsPerKm ~/ 60;
    final int seconds = (paceInSecondsPerKm % 60).toInt();

    if (minutes > 99) return "--:--";
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  double get _estimatedCalories {
    final double distanceKm = _totalDistanceInMeters / 1000;
    return distanceKm * _userWeightKg * _currentMode.calorieFactor;
  }

  void _startStreams() {
    _positionSub?.cancel();
    _positionSub = _locationService.getPositionStream().listen((Position position) {
      if (!mounted) return;
      if (position.accuracy > 25.0) return;

      if (_isAutoPaused && position.speed >= 0.7) {
        _stationarySeconds = 0;
        HapticFeedback.mediumImpact();
        setState(() => _isAutoPaused = false);
      }

      if (_effectivelyPaused) {
        setState(() => _currentPosition = position);
        return;
      }

      final newLatLng = LatLng(position.latitude, position.longitude);

      if (_routePoints.isNotEmpty) {
        final lastLatLng = _routePoints.last;
        final distance = Geolocator.distanceBetween(
          lastLatLng.latitude,
          lastLatLng.longitude,
          newLatLng.latitude,
          newLatLng.longitude,
        );

        if (distance >= 3.0) {
          _stationarySeconds = 0;
          _totalDistanceInMeters += distance;
          setState(() {
            _currentPosition = position;
            _routePoints.add(newLatLng);
          });
        } else {
          setState(() => _currentPosition = position);
        }
      } else {
        setState(() {
          _currentPosition = position;
          _routePoints.add(newLatLng);
        });
      }

      if (_autoFollowCamera) {
        _mapController.move(newLatLng, 17.0);
      }
    });

    _stepSub?.cancel();
    _lastRawStreamSteps = 0;
    _stepSub = _pedometerService.getStepCountStream().listen((int steps) {
      if (!mounted || _effectivelyPaused) return;
      _lastRawStreamSteps = steps;
      setState(() => _stepCount = _stepOffsetBeforePause + steps);
    });
  }

  Future<void> _initiateCountdownAndStart() async {
    bool hasPermission = await _locationService.requestPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Izin lokasi/GPS wajib diaktifkan untuk merekam rute.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _countdownValue = 3);

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_countdownValue > 1) {
        HapticFeedback.selectionClick();
        setState(() => _countdownValue--);
      } else {
        timer.cancel();
        HapticFeedback.heavyImpact();
        setState(() => _countdownValue = 0);
        _beginActualRecording();
      }
    });
  }

  void _beginActualRecording() {
    setState(() {
      _isTracking = true;
      _isPaused = false;
      _isAutoPaused = false;
      _stationarySeconds = 0;
      _autoFollowCamera = true;
      _routePoints.clear();
      _totalDistanceInMeters = 0.0;
      _stepCount = 0;
      _stepOffsetBeforePause = 0;
      _elapsedSeconds = 0;
      if (_currentPosition != null) {
        _routePoints.add(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
      }
    });

    _startTimer();
    _startStreams();
  }

  void _resumeFromPause() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isPaused = false;
      _isAutoPaused = false;
      _stationarySeconds = 0;
      _autoFollowCamera = true;
    });
    _startStreams();
  }

  void _pauseTracking() {
    HapticFeedback.mediumImpact();
    _positionSub?.cancel();
    _stepSub?.cancel();
    _stepOffsetBeforePause += _lastRawStreamSteps;
    _lastRawStreamSteps = 0;
    setState(() {
      _isPaused = true;
      _isAutoPaused = false;
    });
  }

  Future<void> _finishTracking() async {
    HapticFeedback.heavyImpact();
    _cancelAllStreams();
    setState(() {
      _isTracking = false;
      _isPaused = false;
      _isAutoPaused = false;
    });

    final bool? didSave = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _PostRunActivityScreen(
          defaultTitle: _currentMode.defaultTitle,
          distanceInKm: _totalDistanceInMeters / 1000,
          durationInSeconds: _elapsedSeconds,
          pace: _calculatePace(),
          steps: _stepCount,
          calories: _estimatedCalories,
          routePoints: List.from(_routePoints),
        ),
      ),
    );

    if (didSave == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aktivitas berhasil diposting ke feed Home!'),
          backgroundColor: AppColors.cardElevated,
        ),
      );
    }
    _resetStats();
  }

  void _showModeSelectorSheet() {
    if (_isTracking) return;
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
            const Text(
              'Pilih Jenis Aktivitas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 14),
            ...List.generate(_modes.length, (idx) {
              final mode = _modes[idx];
              final isSelected = idx == _selectedModeIndex;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSelected ? AppColors.primaryOrange : AppColors.cardElevated,
                  child: Icon(mode.icon, color: Colors.white, size: 20),
                ),
                title: Text(mode.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(mode.defaultTitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                trailing: isSelected ? const Icon(Icons.check_circle, color: AppColors.primaryOrange) : null,
                onTap: () {
                  setState(() => _selectedModeIndex = idx);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _resetStats() {
    setState(() {
      _routePoints.clear();
      _totalDistanceInMeters = 0.0;
      _stepCount = 0;
      _stepOffsetBeforePause = 0;
      _lastRawStreamSteps = 0;
      _elapsedSeconds = 0;
      _stationarySeconds = 0;
      _isTracking = false;
      _isPaused = false;
      _isAutoPaused = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentLatLng = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(-6.9311, 107.7733);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentLatLng,
              initialZoom: 17.0,
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && _autoFollowCamera) {
                  setState(() => _autoFollowCamera = false);
                }
              },
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
                    points: _routePoints,
                    strokeWidth: 5.5,
                    color: AppColors.primaryOrange,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (_routePoints.isNotEmpty)
                    Marker(
                      point: _routePoints.first,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.accentGreen,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                      ),
                    ),
                  if (_currentPosition != null)
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

          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.signal_cellular_alt,
                        size: 14,
                        color: _currentPosition != null ? AppColors.accentGreen : Colors.orangeAccent,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _currentPosition != null
                            ? 'GPS ±${_currentPosition!.accuracy.toStringAsFixed(0)}m'
                            : 'Mencari GPS...',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _currentPosition != null ? AppColors.accentGreen : Colors.orangeAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _autoPauseEnabled = !_autoPauseEnabled;
                      if (!_autoPauseEnabled) _isAutoPaused = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _autoPauseEnabled ? AppColors.accentBlue.withOpacity(0.6) : Colors.white12,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.motion_photos_paused,
                          size: 14,
                          color: _autoPauseEnabled ? AppColors.accentBlue : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _autoPauseEnabled ? 'Auto-Pause ON' : 'Auto-Pause OFF',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _autoPauseEnabled ? AppColors.accentBlue : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_fire_department, size: 14, color: AppColors.primaryOrange),
                      const SizedBox(width: 4),
                      Text(
                        '${_estimatedCalories.toStringAsFixed(0)} kcal',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            right: 16,
            bottom: 265,
            child: FloatingActionButton.small(
              heroTag: 'btn_record_recenter',
              backgroundColor: _autoFollowCamera ? AppColors.primaryOrange : AppColors.cardDark,
              onPressed: _recenterMap,
              child: Icon(
                _autoFollowCamera ? Icons.gps_fixed : Icons.gps_not_fixed,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF161618),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black54, blurRadius: 12, spreadRadius: 2),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 10),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade700,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  if (_isPaused || _isAutoPaused)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: (_isAutoPaused ? AppColors.accentBlue : Colors.amber).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _isAutoPaused
                            ? 'AUTO-PAUSED (DIAM TERDETEKSI • LANJUT OTOMATIS)'
                            : 'SESI DIJEDA (PAUSED)',
                        style: TextStyle(
                          color: _isAutoPaused ? AppColors.accentBlue : Colors.amber,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStravaMetric('WAKTU', _formatDuration(_elapsedSeconds)),
                        Container(height: 32, width: 1, color: Colors.white12),
                        _buildStravaMetric('PACE (/KM)', _calculatePace()),
                        Container(height: 32, width: 1, color: Colors.white12),
                        _buildStravaMetric('JARAK (KM)', (_totalDistanceInMeters / 1000).toStringAsFixed(2)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 26, left: 24, right: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        GestureDetector(
                          onTap: _isTracking ? null : _showModeSelectorSheet,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: AppColors.cardElevated,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _isTracking ? Colors.transparent : AppColors.primaryOrange.withOpacity(0.5),
                                  ),
                                ),
                                child: Icon(_currentMode.icon, color: AppColors.primaryOrange),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _isTracking ? _currentMode.name : '${_currentMode.name} ▾',
                                style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        if (!_isTracking)
                          _buildCircleActionButton(
                            icon: Icons.play_arrow_rounded,
                            color: AppColors.primaryOrange,
                            size: 74,
                            iconSize: 42,
                            onTap: _initiateCountdownAndStart,
                          )
                        else if (!_isPaused)
                          _buildCircleActionButton(
                            icon: Icons.pause_rounded,
                            color: Colors.amber.shade700,
                            size: 74,
                            iconSize: 38,
                            onTap: _pauseTracking,
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildCircleActionButton(
                                icon: Icons.play_arrow_rounded,
                                color: AppColors.accentGreen,
                                size: 66,
                                iconSize: 36,
                                onTap: _resumeFromPause,
                              ),
                              const SizedBox(width: 16),
                              _buildCircleActionButton(
                                icon: Icons.stop_rounded,
                                color: Colors.redAccent,
                                size: 66,
                                iconSize: 34,
                                onTap: _finishTracking,
                              ),
                            ],
                          ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(
                                color: AppColors.cardElevated,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '$_stepCount',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text('Langkah', style: TextStyle(fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_countdownValue > 0)
            Container(
              color: Colors.black.withOpacity(0.88),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'BERSIAP LARI',
                      style: TextStyle(
                        color: AppColors.primaryOrange,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TweenAnimationBuilder<double>(
                      key: ValueKey(_countdownValue),
                      tween: Tween(begin: 1.4, end: 1.0),
                      duration: const Duration(milliseconds: 400),
                      builder: (context, scale, child) {
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primaryOrange, width: 4),
                          color: AppColors.primaryOrange.withOpacity(0.15),
                        ),
                        child: Center(
                          child: Text(
                            '$_countdownValue',
                            style: const TextStyle(
                              fontSize: 68,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () {
                        _countdownTimer?.cancel();
                        setState(() => _countdownValue = 0);
                      },
                      child: const Text('Batalkan', style: TextStyle(color: Colors.white54, fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCircleActionButton({
    required IconData icon,
    required Color color,
    required double size,
    required double iconSize,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(icon, size: iconSize, color: Colors.white),
      ),
    );
  }

  Widget _buildStravaMetric(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      ],
    );
  }
}

class _PostRunActivityScreen extends StatefulWidget {
  final String defaultTitle;
  final double distanceInKm;
  final int durationInSeconds;
  final String pace;
  final int steps;
  final double calories;
  final List<LatLng> routePoints;

  const _PostRunActivityScreen({
    required this.defaultTitle,
    required this.distanceInKm,
    required this.durationInSeconds,
    required this.pace,
    required this.steps,
    required this.calories,
    required this.routePoints,
  });

  @override
  State<_PostRunActivityScreen> createState() => _PostRunActivityScreenState();
}

class _PostRunActivityScreenState extends State<_PostRunActivityScreen> {
  final RunStorageService _storageService = RunStorageService();
  final ImagePicker _picker = ImagePicker();
  final MapController _previewMapController = MapController();

  late TextEditingController _titleController;
  final TextEditingController _notesController = TextEditingController();

  File? _selectedPhoto;
  bool _isSaving = false;

  final List<String> _feelings = const [
    'Luar Biasa 🔥',
    'Santai & Segar 🌿',
    'Kuat & Stabil 💪',
    'Tanjakan Berat ⛰️',
    'Pecah Rekor ⚡',
  ];
  String _selectedFeeling = 'Luar Biasa 🔥';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.defaultTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _fitPreviewMap() {
    if (widget.routePoints.length >= 2) {
      final bounds = LatLngBounds.fromPoints(widget.routePoints);
      _previewMapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(28)),
      );
    } else if (widget.routePoints.isNotEmpty) {
      _previewMapController.move(widget.routePoints.first, 16.0);
    }
  }

  Future<void> _pickActivityPhoto(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() => _selectedPhoto = File(picked.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat foto: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _saveAndPost() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    String? savedPhotoPath;
    if (_selectedPhoto != null) {
      savedPhotoPath = await _storageService.saveRunPhoto(_selectedPhoto!);
    }

    final now = DateTime.now();
    final newRun = RunModel(
      id: now.millisecondsSinceEpoch.toString(),
      title: _titleController.text.trim().isEmpty ? widget.defaultTitle : _titleController.text.trim(),
      date: "${now.day}/${now.month}/${now.year}",
      distanceInKm: widget.distanceInKm,
      durationInSeconds: widget.durationInSeconds,
      pace: widget.pace,
      steps: widget.steps,
      calories: widget.calories,
      routePoints: widget.routePoints,
      notes: _notesController.text.trim(),
      photoPath: savedPhotoPath,
      feeling: _selectedFeeling,
    );

    await _storageService.saveRun(newRun);

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  void _confirmDiscard() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Buang Rekaman Lari?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Data GPS dan statistik sesi ini tidak akan disimpan.', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kembali', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context, false);
            },
            child: const Text('Buang', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    final h = totalSeconds ~/ 3600;
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = widget.routePoints.isNotEmpty
        ? widget.routePoints.first
        : const LatLng(-6.9311, 107.7733);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: _confirmDiscard,
        ),
        title: const Text(
          'Post Aktivitas',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Colors.white),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isSaving ? null : _saveAndPost,
              child: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Simpan & Post', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                  decoration: const InputDecoration(
                    hintText: 'Judul lari (misal: Lari Pagi Keliling Unpad)',
                    hintStyle: TextStyle(color: Colors.white38, fontWeight: FontWeight.normal),
                    border: InputBorder.none,
                  ),
                ),
                const Divider(color: Colors.white10),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Ceritakan pengalaman larimu hari ini... Cuaca, rute, atau target berikutnya?',
                    hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Bagaimana Rasanya Lari Ini?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _feelings.map((feeling) {
                final isSelected = _selectedFeeling == feeling;
                return GestureDetector(
                  onTap: () => setState(() => _selectedFeeling = feeling),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primaryOrange : AppColors.cardDark,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? AppColors.primaryOrange : Colors.white12),
                    ),
                    child: Text(
                      feeling,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Foto Momen Lari (Opsional)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (_selectedPhoto != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    _selectedPhoto!,
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedPhoto = null),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _buildPhotoButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Pilih dari Galeri',
                    onTap: () => _pickActivityPhoto(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildPhotoButton(
                    icon: Icons.camera_alt_outlined,
                    label: 'Ambil Foto',
                    onTap: () => _pickActivityPhoto(ImageSource.camera),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 18),
          const Text(
            'Trek Rute GPS & Statistik',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: SizedBox(
                    height: 180,
                    child: FlutterMap(
                      mapController: _previewMapController,
                      options: MapOptions(
                        initialCenter: initialCenter,
                        initialZoom: 15.5,
                        onMapReady: _fitPreviewMap,
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
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
                        if (widget.routePoints.length >= 2)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: widget.routePoints,
                                strokeWidth: 4.5,
                                color: AppColors.primaryOrange,
                              ),
                            ],
                          ),
                        if (widget.routePoints.isNotEmpty)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: widget.routePoints.first,
                                width: 16,
                                height: 16,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.accentGreen,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                              if (widget.routePoints.length >= 2)
                                Marker(
                                  point: widget.routePoints.last,
                                  width: 16,
                                  height: 16,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatCol('JARAK', '${widget.distanceInKm.toStringAsFixed(2)} km'),
                      _buildStatCol('WAKTU', _formatDuration(widget.durationInSeconds)),
                      _buildStatCol('PACE', '${widget.pace} /km'),
                      _buildStatCol('KALORI', '${widget.calories.toStringAsFixed(0)} kcal'),
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

  Widget _buildPhotoButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primaryOrange.withOpacity(0.45)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primaryOrange, size: 26),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCol(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
      ],
    );
  }
}