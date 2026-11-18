import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/tracking/domain/run_model.dart';

class RunStorageService {
  static const String _storageKey = 'saved_runs_list';

  Future<void> saveRun(RunModel run) async {
    final prefs = await SharedPreferences.getInstance();
    final List<RunModel> currentRuns = await getSavedRuns();

    currentRuns.insert(0, run);

    final List<String> jsonStringList = currentRuns.map((e) => e.toJson()).toList();
    await prefs.setStringList(_storageKey, jsonStringList);
  }

  Future<void> updateRun(RunModel updatedRun) async {
    final prefs = await SharedPreferences.getInstance();
    final List<RunModel> currentRuns = await getSavedRuns();

    final index = currentRuns.indexWhere((r) => r.id == updatedRun.id);
    if (index != -1) {
      currentRuns[index] = updatedRun;
      final List<String> jsonStringList = currentRuns.map((e) => e.toJson()).toList();
      await prefs.setStringList(_storageKey, jsonStringList);
    }
  }

  Future<List<RunModel>> getSavedRuns() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? jsonStringList = prefs.getStringList(_storageKey);

    if (jsonStringList == null) return [];

    return jsonStringList.map((e) => RunModel.fromJson(e)).toList();
  }

  Future<void> deleteRun(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final List<RunModel> currentRuns = await getSavedRuns();

    final target = currentRuns.where((r) => r.id == id).toList();
    if (target.isNotEmpty && target.first.photoPath != null) {
      final f = File(target.first.photoPath!);
      if (f.existsSync()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    currentRuns.removeWhere((run) => run.id == id);

    final List<String> jsonStringList = currentRuns.map((e) => e.toJson()).toList();
    await prefs.setStringList(_storageKey, jsonStringList);
  }

  /// Menyalin foto aktivitas lari ke penyimpanan permanen aplikasi
  Future<String> saveRunPhoto(File sourceFile) async {
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = 'run_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedFile = await sourceFile.copy('${appDir.path}/$fileName');
    return savedFile.path;
  }
}