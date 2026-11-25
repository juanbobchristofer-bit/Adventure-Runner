import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/pedometer_service.dart';
import '../../../core/services/profile_storage_service.dart';
import '../../../core/services/run_draft_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dark_osm_tile_layer.dart';
import '../domain/run_model.dart';
import '../domain/runner_stats.dart';
import 'post_run_screen.dart';

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

class _RecordRunScreenState extends State<RecordRunScreen> with WidgetsBindingObserver {
  final LocationService _locationService = LocationService();
  final PedometerService _pedometerService = PedometerService();
  final ProfileStorageService _profileService = ProfileStorageService();
  final RunDraftService _draftService = RunDraftService();
  final MapController _mapController = MapController();

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<int>? _stepSub;
  Timer? _timer;
  Timer? _countdownTimer;
  Timer? _kmBannerTimer;

  // Status Tracking & Reliabilitas
  bool _isTracking = false;
  bool _isPaused = false;
  bool _isAutoPaused = false;
  bool _autoPauseEnabled = true;
  bool _kmCueEnabled = true;
  bool _isLoadingLocation = true;
  bool _autoFollowCamera = true;
  int _countdownValue = 0; // > 0 saat overlay 3-2-1 aktif

  // Kilometer Milestone Cue
  int _completedKmCount = 0;
  int _lastKmSplitSeconds = 0;
  String? _kmMilestoneBanner;

  Position? _currentPosition;
  final List<LatLng> _routePoints = [];
  final List<RunTrackPoint> _trackPoints = [];
  double _totalDistanceInMeters = 0.0;
  double _elevationGainM = 0.0;
  double? _lastAltitudeAnchor;
  int _stepCount = 0;
  int? _lastSensorSteps;
  int _elapsedSeconds = 0;
  int _stationarySeconds = 0; // Penghitung detik diam untuk Auto-Pause
  double _userWeightKg = 65.0;
  GuidedRoute? _guidedRoute;

  // Guard untuk mencegah lonjakan GPS (spike) & penambahan jarak saat sesi dijeda
  bool _isResumingSegment = false;
  DateTime? _lastValidPointTime;
  DateTime? _lastMovementTime;
  static const double _maxValidRunningSpeedMs = 12.5; // ~45 km/jam

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
    WidgetsBinding.instance.addObserver(this);
    _guidedRoute = GuidedRouteController.activeRoute.value;
    _loadUserWeight();
    _fetchInitialLocation();
    ProfileStorageService.profileUpdateNotifier.addListener(_loadUserWeight);
    GuidedRouteController.activeRoute.addListener(_onGuidedRouteChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingDraft());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ProfileStorageService.profileUpdateNotifier.removeListener(_loadUserWeight);
    GuidedRouteController.activeRoute.removeListener(_onGuidedRouteChanged);
    _kmBannerTimer?.cancel();
    _cancelAllStreams();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isTracking &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached)) {
      unawaited(_persistDraftCheckpoint());
    }
  }

  Future<void> _persistDraftCheckpoint() async {
    if (!_isTracking) return;
    final draft = ActiveRunDraft(
      modeIndex: _selectedModeIndex,
      totalDistanceMeters: _totalDistanceInMeters,
      elevationGainM: _elevationGainM,
      stepCount: _stepCount,
      elapsedSeconds: _elapsedSeconds,
      completedKmCount: _completedKmCount,
      lastKmSplitSeconds: _lastKmSplitSeconds,
      routePoints: List<LatLng>.from(_routePoints),
      trackPoints: List<RunTrackPoint>.from(_trackPoints),
      savedAt: DateTime.now(),
    );
    if (draft.hasMeaningfulProgress) {
      await _draftService.saveDraft(draft);
    }
  }

  Future<void> _checkPendingDraft() async {
    if (_isTracking || !mounted) return;
    final draft = await _draftService.loadDraft();
    if (draft == null || !mounted) return;

    final distKm = (draft.totalDistanceMeters / 1000).toStringAsFixed(2);
    final duration = AppFormatters.formatClockDuration(draft.elapsedSeconds);
    final savedTime =
        '${draft.savedAt.hour.toString().padLeft(2, '0')}:${draft.savedAt.minute.toString().padLeft(2, '0')}';

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.restore_rounded, color: AppColors.primaryOrange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sesi Lari Belum Tersimpan',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.5),
              ),
            ),
          ],
        ),
        content: Text(
          'Ditemukan rekaman otomatis terakhir pukul $savedTime:\n\n'
          '• Jarak: $distKm km\n'
          '• Durasi: $duration\n'
          '• Langkah: ${draft.stepCount} step\n\n'
          'Ingin melanjutkan rekaman ini atau langsung menyimpannya?',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Buang', style: TextStyle(color: Colors.redAccent)),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.accentBlue)),
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Simpan Sekarang', style: TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
            onPressed: () => Navigator.pop(ctx, 'resume'),
            child: const Text('Lanjutkan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (action == 'discard') {
      await _draftService.clearDraft();
    } else if (action == 'resume') {
      _restoreDraftForResume(draft);
    } else if (action == 'save') {
      await _saveRecoveredDraftDirectly(draft);
    }
  }

  void _restoreDraftForResume(ActiveRunDraft draft) {
    final safeMode = draft.modeIndex.clamp(0, _modes.length - 1);
    setState(() {
      _selectedModeIndex = safeMode;
      _totalDistanceInMeters = draft.totalDistanceMeters;
      _elevationGainM = draft.elevationGainM;
      _stepCount = draft.stepCount;
      _elapsedSeconds = draft.elapsedSeconds;
      _completedKmCount = draft.completedKmCount;
      _lastKmSplitSeconds = draft.lastKmSplitSeconds;
      _routePoints
        ..clear()
        ..addAll(draft.routePoints);
      _trackPoints
        ..clear()
        ..addAll(draft.trackPoints);
      _lastAltitudeAnchor = draft.trackPoints.isNotEmpty && draft.trackPoints.last.altitude.abs() > 0.01
          ? draft.trackPoints.last.altitude
          : null;
      _isTracking = true;
      _isPaused = true;
      _isAutoPaused = false;
      _isResumingSegment = true;
    });
    _startTimer();

    if (_routePoints.isNotEmpty) {
      try {
        _mapController.move(_routePoints.last, 17.0);
      } catch (_) {}
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sesi dipulihkan dalam status Jeda. Tekan Play hijau untuk lanjut berlari!'),
        backgroundColor: AppColors.cardElevated,
      ),
    );
  }

  Future<void> _saveRecoveredDraftDirectly(ActiveRunDraft draft) async {
    final safeMode = _modes[draft.modeIndex.clamp(0, _modes.length - 1)];
    final distKm = draft.totalDistanceMeters / 1000.0;
    final paceStr = (draft.totalDistanceMeters >= 15 && draft.elapsedSeconds > 0)
        ? RunnerStats.formatPaceFromSeconds(draft.elapsedSeconds / distKm)
        : '--:--';
    final calories = distKm * _userWeightKg * safeMode.calorieFactor;

    final bool? didSave = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PostRunActivityScreen(
          defaultTitle: safeMode.defaultTitle,
          distanceInKm: distKm,
          durationInSeconds: draft.elapsedSeconds,
          pace: paceStr,
          steps: draft.stepCount,
          calories: calories,
          elevationGainM: draft.elevationGainM,
          routePoints: List<LatLng>.from(draft.routePoints),
          trackPoints: List<RunTrackPoint>.from(draft.trackPoints),
        ),
      ),
    );

    await _draftService.clearDraft();
    if (didSave == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesi yang dipulihkan berhasil disimpan ke Home!'),
          backgroundColor: AppColors.cardElevated,
        ),
      );
    }
  }

  void _onGuidedRouteChanged() {
    final route = GuidedRouteController.activeRoute.value;
    if (!mounted) return;
    setState(() => _guidedRoute = route);
    if (route != null && route.points.length >= 2 && !_isTracking) {
      try {
        final bounds = LatLngBounds.fromPoints(route.points);
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.fromLTRB(40, 120, 40, 290)),
        );
        setState(() => _autoFollowCamera = false);
      } catch (_) {}
    }
  }

  void _recordTrackPoint(Position position, LatLng latLng) {
    _routePoints.add(latLng);
    _trackPoints.add(
      RunTrackPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        elapsedSeconds: _elapsedSeconds,
      ),
    );
    // Hitung elevation gain aktual dengan ambang 2m untuk menyaring noise vertikal GPS
    if (position.altitude.abs() > 0.01) {
      if (_lastAltitudeAnchor == null) {
        _lastAltitudeAnchor = position.altitude;
      } else {
        final diff = position.altitude - _lastAltitudeAnchor!;
        if (diff >= 2.0) {
          _elevationGainM += diff;
          _lastAltitudeAnchor = position.altitude;
        } else if (diff <= -2.0) {
          _lastAltitudeAnchor = position.altitude;
        }
      }
    }
  }

  void _cancelAllStreams() {
    _timer?.cancel();
    _timer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _positionSub?.cancel();
    _positionSub = null;
    _stepSub?.cancel();
    _stepSub = null;
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
        final now = DateTime.now();
        final currentSpeedMs = _currentPosition?.speed ?? 0.0;
        final secondsSinceMovement = _lastMovementTime == null
            ? _stationarySeconds
            : now.difference(_lastMovementTime!).inSeconds;

        // Anggap diam jika kecepatan GPS rendah ATAU tidak ada perpindahan valid selama >= 5 detik
        final isStationary = currentSpeedMs < 0.5 || secondsSinceMovement >= 5;
        if (isStationary) {
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
        if (_elapsedSeconds > 0 && _elapsedSeconds % 15 == 0) {
          unawaited(_persistDraftCheckpoint());
        }
      }
    });
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

  String _calculateCurrentPace() {
    if (!_isTracking || _effectivelyPaused) return '--:--';
    return RunnerStats.calculateRollingCurrentPace(
      _trackPoints,
      windowSeconds: 15,
      liveSpeedMs: _currentPosition?.speed,
    );
  }

  void _checkKmMilestone() {
    final completedKm = _totalDistanceInMeters ~/ 1000;
    if (completedKm > _completedKmCount) {
      final splitSeconds = (_elapsedSeconds - _lastKmSplitSeconds).clamp(1, 36000);
      final splitPace = RunnerStats.formatPaceFromSeconds(splitSeconds.toDouble());
      _completedKmCount = completedKm;
      _lastKmSplitSeconds = _elapsedSeconds;
      _triggerKmMilestoneCue(km: completedKm, splitPace: splitPace);
    }
  }

  void _triggerKmMilestoneCue({required int km, required String splitPace}) {
    if (_kmCueEnabled) {
      HapticFeedback.heavyImpact();
      Future<void>.delayed(const Duration(milliseconds: 220), () {
        HapticFeedback.heavyImpact();
      });
      unawaited(SystemSound.play(SystemSoundType.alert));
    }

    _kmBannerTimer?.cancel();
    if (mounted) {
      setState(() {
        _kmMilestoneBanner =
            'KM $km Selesai! • Split $splitPace /km • Total ${AppFormatters.formatClockDuration(_elapsedSeconds)}';
      });
    }
    _kmBannerTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) {
        setState(() => _kmMilestoneBanner = null);
      }
    });
  }

  double get _estimatedCalories {
    final double distanceKm = _totalDistanceInMeters / 1000;
    return distanceKm * _userWeightKg * _currentMode.calorieFactor;
  }

  void _startStreams() {
    _positionSub?.cancel();
    _positionSub = _locationService.getPositionStream().listen(
      (Position position) {
        if (!mounted) return;
        if (position.accuracy > 25.0) return;

        final now = DateTime.now();
        final newLatLng = LatLng(position.latitude, position.longitude);

        // Deteksi lanjut otomatis dari Auto-Pause saat kecepatan atau perpindahan nyata kembali terdeteksi
        if (_isAutoPaused) {
          final movedFromLast = _routePoints.isEmpty
              ? 0.0
              : Geolocator.distanceBetween(
                  _routePoints.last.latitude,
                  _routePoints.last.longitude,
                  newLatLng.latitude,
                  newLatLng.longitude,
                );
          if (position.speed >= 0.7 || (movedFromLast >= 5.0 && movedFromLast <= 40.0)) {
            _stationarySeconds = 0;
            _lastMovementTime = now;
            HapticFeedback.mediumImpact();
            setState(() => _isAutoPaused = false);
          }
        }

        if (_effectivelyPaused) {
          setState(() => _currentPosition = position);
          return;
        }

        // Jika baru saja melanjutkan dari Pause manual, jadikan titik ini anchor baru tanpa menghitung jarak selama jeda
        if (_isResumingSegment) {
          _isResumingSegment = false;
          _lastValidPointTime = now;
          _lastMovementTime = now;
          _lastAltitudeAnchor = position.altitude.abs() > 0.01 ? position.altitude : null;
          setState(() {
            _currentPosition = position;
            _recordTrackPoint(position, newLatLng);
          });
          if (_autoFollowCamera) {
            _mapController.move(newLatLng, 17.0);
          }
          return;
        }

        if (_routePoints.isNotEmpty) {
          final lastLatLng = _routePoints.last;
          final distance = Geolocator.distanceBetween(
            lastLatLng.latitude,
            lastLatLng.longitude,
            newLatLng.latitude,
            newLatLng.longitude,
          );

          final elapsedSinceLastSec = _lastValidPointTime == null
              ? 2.0
              : (now.difference(_lastValidPointTime!).inMilliseconds / 1000.0).clamp(1.0, 3600.0);
          final impliedSpeedMs = distance / elapsedSinceLastSec;

          // Filter jitter (< 3m) dan filter GPS teleport/spike (> 12.5 m/s atau ~45 km/jam)
          if (distance >= 3.0 && impliedSpeedMs <= _maxValidRunningSpeedMs) {
            _stationarySeconds = 0;
            _lastValidPointTime = now;
            _lastMovementTime = now;
            _totalDistanceInMeters += distance;
            setState(() {
              _currentPosition = position;
              _recordTrackPoint(position, newLatLng);
            });
            _checkKmMilestone();
          } else {
            setState(() => _currentPosition = position);
          }
        } else {
          _lastValidPointTime = now;
          _lastMovementTime = now;
          setState(() {
            _currentPosition = position;
            _recordTrackPoint(position, newLatLng);
          });
        }

        if (_autoFollowCamera) {
          _mapController.move(newLatLng, 17.0);
        }
      },
      onError: (Object error) {
        debugPrint('GPS stream error: $error');
      },
    );

    _stepSub?.cancel();
    _lastSensorSteps = null;
    _stepSub = _pedometerService.getRawStepCountStream().listen(
      (int rawSteps) {
        if (!mounted) return;
        if (_lastSensorSteps == null) {
          _lastSensorSteps = rawSteps;
          return;
        }

        final int delta = rawSteps - _lastSensorSteps!;
        _lastSensorSteps = rawSteps;

        // Hanya tambahkan delta langkah saat tidak dijeda (Pause maupun Auto-Pause)
        if (delta > 0 && !_effectivelyPaused) {
          setState(() => _stepCount += delta);
        }
      },
      onError: (Object error) {
        debugPrint('Pedometer stream error: $error');
      },
    );
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
    final now = DateTime.now();
    setState(() {
      _isTracking = true;
      _isPaused = false;
      _isAutoPaused = false;
      _isResumingSegment = false;
      _stationarySeconds = 0;
      _lastValidPointTime = now;
      _lastMovementTime = now;
      _autoFollowCamera = true;
      _routePoints.clear();
      _trackPoints.clear();
      _totalDistanceInMeters = 0.0;
      _elevationGainM = 0.0;
      _lastAltitudeAnchor = null;
      _stepCount = 0;
      _lastSensorSteps = null;
      _elapsedSeconds = 0;
      _completedKmCount = 0;
      _lastKmSplitSeconds = 0;
      _kmMilestoneBanner = null;
      if (_currentPosition != null) {
        _recordTrackPoint(
          _currentPosition!,
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        );
      }
    });

    unawaited(_draftService.clearDraft());
    _startTimer();
    _startStreams();
  }

  void _resumeFromPause() {
    HapticFeedback.mediumImpact();
    final now = DateTime.now();
    setState(() {
      _isPaused = false;
      _isAutoPaused = false;
      _isResumingSegment = true;
      _stationarySeconds = 0;
      _lastMovementTime = now;
      _autoFollowCamera = true;
    });
    _startStreams();
  }

  void _pauseTracking() {
    HapticFeedback.mediumImpact();
    _positionSub?.cancel();
    _positionSub = null;
    _stepSub?.cancel();
    _stepSub = null;
    _lastSensorSteps = null;
    setState(() {
      _isPaused = true;
      _isAutoPaused = false;
    });
    unawaited(_persistDraftCheckpoint());
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
        builder: (_) => PostRunActivityScreen(
          defaultTitle: _guidedRoute?.name ?? _currentMode.defaultTitle,
          distanceInKm: _totalDistanceInMeters / 1000,
          durationInSeconds: _elapsedSeconds,
          pace: _calculatePace(),
          steps: _stepCount,
          calories: _estimatedCalories,
          elevationGainM: _elevationGainM,
          routePoints: List.from(_routePoints),
          trackPoints: List.from(_trackPoints),
        ),
      ),
    );

    await _draftService.clearDraft();
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
      _trackPoints.clear();
      _totalDistanceInMeters = 0.0;
      _elevationGainM = 0.0;
      _lastAltitudeAnchor = null;
      _stepCount = 0;
      _lastSensorSteps = null;
      _elapsedSeconds = 0;
      _stationarySeconds = 0;
      _completedKmCount = 0;
      _lastKmSplitSeconds = 0;
      _kmMilestoneBanner = null;
      _isResumingSegment = false;
      _lastValidPointTime = null;
      _lastMovementTime = null;
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
              backgroundColor: AppColors.backgroundDark,
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && _autoFollowCamera) {
                  setState(() => _autoFollowCamera = false);
                }
              },
            ),
            children: [
              const DarkOsmTileLayer(),
              PolylineLayer(
                polylines: [
                  if (_guidedRoute != null && _guidedRoute!.points.length >= 2)
                    Polyline(
                      points: _guidedRoute!.points,
                      strokeWidth: 4.5,
                      color: _guidedRoute!.color.withValues(alpha: 0.65),
                    ),
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
                          color: AppColors.primaryOrange.withValues(alpha: 0.25),
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
            left: 14,
            right: 14,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark.withValues(alpha: 0.92),
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
                  const SizedBox(width: 6),
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
                        color: AppColors.cardDark.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _autoPauseEnabled ? AppColors.accentBlue.withValues(alpha: 0.6) : Colors.white12,
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
                            _autoPauseEnabled ? 'Auto-Pause' : 'AP OFF',
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
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _kmCueEnabled = !_kmCueEnabled);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _kmCueEnabled ? AppColors.primaryOrange.withValues(alpha: 0.65) : Colors.white12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _kmCueEnabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                            size: 14,
                            color: _kmCueEnabled ? AppColors.primaryOrange : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _kmCueEnabled ? '1KM Cue' : 'Cue OFF',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _kmCueEnabled ? AppColors.primaryOrange : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark.withValues(alpha: 0.92),
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
          ),

          if (_kmMilestoneBanner != null)
            Positioned(
              top: 94,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryOrange, Color(0xFFFF7A3D)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryOrange.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.flag_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _kmMilestoneBanner!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_guidedRoute != null && _kmMilestoneBanner == null)
            Positioned(
              top: 94,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.cardDark.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _guidedRoute!.color.withValues(alpha: 0.7)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.alt_route, size: 16, color: _guidedRoute!.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Panduan: ${_guidedRoute!.name} (${_guidedRoute!.distanceKm.toStringAsFixed(1)} km)',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: GuidedRouteController.clearGuide,
                      child: const Icon(Icons.close, size: 16, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),

          const Positioned(
            left: 16,
            bottom: 318,
            child: OsmAttributionBadge(),
          ),

          Positioned(
            right: 16,
            bottom: 318,
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
                        color: (_isAutoPaused ? AppColors.accentBlue : Colors.amber).withValues(alpha: 0.2),
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
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStravaMetric('WAKTU', AppFormatters.formatClockDuration(_elapsedSeconds)),
                            Container(height: 30, width: 1, color: Colors.white12),
                            _buildStravaMetric(
                              'JARAK (KM)',
                              (_totalDistanceInMeters / 1000).toStringAsFixed(2),
                              valueColor: AppColors.primaryOrange,
                            ),
                          ],
                        ),
                        const Divider(height: 16, color: Colors.white10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStravaMetric(
                              'CURRENT PACE',
                              _calculateCurrentPace(),
                              fontSize: 18,
                              valueColor: _isTracking && !_effectivelyPaused ? AppColors.accentGreen : Colors.white70,
                            ),
                            Container(height: 24, width: 1, color: Colors.white12),
                            _buildStravaMetric(
                              'AVG PACE (/KM)',
                              _calculatePace(),
                              fontSize: 18,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
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
                                    color: _isTracking ? Colors.transparent : AppColors.primaryOrange.withValues(alpha: 0.5),
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
              color: Colors.black.withValues(alpha: 0.88),
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
                          color: AppColors.primaryOrange.withValues(alpha: 0.15),
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
              color: color.withValues(alpha: 0.4),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(icon, size: iconSize, color: Colors.white),
      ),
    );
  }

  Widget _buildStravaMetric(
    String label,
    String value, {
    double fontSize = 22,
    Color valueColor = Colors.white,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: valueColor),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      ],
    );
  }
}
