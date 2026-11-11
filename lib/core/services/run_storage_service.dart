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

  Future<List<RunModel>> getSavedRuns() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? jsonStringList = prefs.getStringList(_storageKey);

    if (jsonStringList == null) return [];

    return jsonStringList.map((e) => RunModel.fromJson(e)).toList();
  }

  // FITUR BARU: Hapus aktivitas lari berdasarkan ID
  Future<void> deleteRun(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final List<RunModel> currentRuns = await getSavedRuns();

    currentRuns.removeWhere((run) => run.id == id);

    final List<String> jsonStringList = currentRuns.map((e) => e.toJson()).toList();
    await prefs.setStringList(_storageKey, jsonStringList);
  }
}