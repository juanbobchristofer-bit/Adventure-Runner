import 'dart:async';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

class PedometerService {
  /// Meminta izin akses sensor gerak (Activity Recognition)
  Future<bool> requestPermission() async {
    try {
      final status = await Permission.activityRecognition.status;
      if (status.isGranted) return true;
      final requested = await Permission.activityRecognition.request();
      return requested.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Aliran nilai kumulatif mentah dari sensor langkah perangkat.
  /// Pemanggil menghitung delta antar-event agar aman terhadap Pause & Auto-Pause.
  Stream<int> getRawStepCountStream() async* {
    final bool hasPermission = await requestPermission();
    if (!hasPermission) return;

    yield* Pedometer.stepCountStream.map((StepCount event) => event.steps);
  }
}