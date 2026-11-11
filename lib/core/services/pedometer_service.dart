import 'dart:async';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

class PedometerService {
  StreamSubscription<StepCount>? _stepCountSubscription;
  int _initialStepCount = -1;

  /// Meminta izin akses sensor gerak (Activity Recognition)
  Future<bool> requestPermission() async {
    PermissionStatus status = await Permission.activityRecognition.request();
    return status.isGranted;
  }

  /// Memulai pendeteksian langkah kaki relatif dari saat tombol 'Mulai' ditekan
  Stream<int> getStepCountStream() async* {
    bool hasPermission = await requestPermission();
    if (!hasPermission) return;

    _initialStepCount = -1;

    yield* Pedometer.stepCountStream.map((StepCount event) {
      if (_initialStepCount == -1) {
        _initialStepCount = event.steps;
      }
      return event.steps - _initialStepCount;
    });
  }

  void stopTracking() {
    _stepCountSubscription?.cancel();
    _initialStepCount = -1;
  }
}