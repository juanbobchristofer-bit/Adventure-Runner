import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  /// Memeriksa & meminta izin akses lokasi (serta notifikasi foreground di Android 13+)
  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    // Minta izin notifikasi di Android 13+ agar Foreground Service berjalan mulus saat layar mati
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final notifStatus = await Permission.notification.status;
        if (notifStatus.isDenied) {
          await Permission.notification.request();
        }
      } catch (_) {}
    }

    return true;
  }

  /// Mengecek apakah izin lokasi latar belakang ("Always") sudah diberikan
  Future<bool> isBackgroundPermissionGranted() async {
    try {
      return await Permission.locationAlways.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Meminta izin lokasi latar belakang secara eksplisit (Android 10+ & iOS Always)
  /// setelah izin lokasi foreground aktif.
  Future<bool> requestBackgroundPermission() async {
    final hasForeground = await requestPermission();
    if (!hasForeground) return false;

    try {
      final status = await Permission.locationAlways.status;
      if (status.isGranted) return true;
      final requested = await Permission.locationAlways.request();
      return requested.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Memulai aliran data GPS real-time dengan dukungan Background / Screen-Off Android & iOS
  Stream<Position> getPositionStream() {
    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        // distanceFilter 0 agar kecepatan (speed = 0) tetap terkirim saat berhenti untuk Auto-Pause
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Adventure Runner • Merekam Rute',
          notificationText: 'Pelacakan GPS aktif di latar belakang',
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    }

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}