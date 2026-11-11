import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationService {
  StreamSubscription<Position>? _positionSubscription;

  /// Memeriksa & meminta izin akses lokasi di Android/iOS
  Future<bool> requestPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Cek apakah layanan GPS di HP aktif
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    // Cek status izin lokasi dari pengguna
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Memulai aliran data GPS (Stream) secara real-time saat pengguna lari
  Stream<Position> getPositionStream() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high, // Presisi tinggi untuk pelacakan rute lari
      distanceFilter: 5,               // Mengirim update posisi setiap berpindah 5 meter
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  /// Menghentikan pelacakan GPS saat sesi lari selesai
  void stopTracking() {
    _positionSubscription?.cancel();
  }
}