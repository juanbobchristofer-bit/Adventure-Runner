import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/tracking/domain/run_model.dart';
import '../utils/gpx_exporter.dart';
import 'social_feed_service.dart';

/// Repositori lokal untuk riwayat lari.
/// Menyimpan indeks metadata & file trek GPS secara terpisah di disk (`runs_db/`) dengan penulisan atomik,
/// serta otomatis memigrasikan data lama dari SharedPreferences agar tidak membebani memori startup.
class RunStorageService {
  static const String _legacyStorageKey = 'saved_runs_list';
  static const String _dbFolderName = 'runs_db';
  static const String _tracksFolderName = 'tracks';
  static const String _indexFileName = 'runs_index.json';

  /// Notifier global agar seluruh tab (Home, Peta, Grup, Profil) otomatis sinkron saat data lari berubah
  static final ValueNotifier<int> runUpdateNotifier = ValueNotifier<int>(0);

  final Directory? _overrideBaseDir;

  RunStorageService({Directory? baseDir}) : _overrideBaseDir = baseDir;

  Future<Directory?> _resolveDbDir() async {
    final overrideDir = _overrideBaseDir;
    if (overrideDir != null) {
      final dir = Directory('${overrideDir.path}/$_dbFolderName');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    if (kIsWeb) return null;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/$_dbFolderName');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  String _safeFileId(String id) => id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  Future<void> _atomicWriteString(File target, String content) async {
    final parent = target.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final tempFile = File('${target.path}.tmp');
    await tempFile.writeAsString(content, flush: true);
    await tempFile.rename(target.path);
  }

  Future<void> _writeTrackFile(Directory dbDir, RunModel run) async {
    final trackFile = File('${dbDir.path}/$_tracksFolderName/${_safeFileId(run.id)}.json');
    final payload = json.encode({
      'routePoints': run.routePoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      'trackPoints': run.trackPoints.map((tp) => tp.toMap()).toList(),
    });
    await _atomicWriteString(trackFile, payload);
  }

  Future<Map<String, dynamic>?> _readTrackFile(Directory dbDir, String runId) async {
    final trackFile = File('${dbDir.path}/$_tracksFolderName/${_safeFileId(runId)}.json');
    if (!await trackFile.exists()) return null;
    try {
      final raw = await trackFile.readAsString();
      return Map<String, dynamic>.from(json.decode(raw) as Map);
    } catch (e) {
      debugPrint('Gagal membaca file trek $runId: $e');
      return null;
    }
  }

  Future<void> _deleteTrackFile(Directory dbDir, String runId) async {
    final trackFile = File('${dbDir.path}/$_tracksFolderName/${_safeFileId(runId)}.json');
    if (await trackFile.exists()) {
      try {
        await trackFile.delete();
      } catch (_) {}
    }
  }

  /// Simpan indeks metadata ringan (tanpa array koordinat besar) ke `runs_index.json`
  Future<void> _writeIndexFile(Directory dbDir, List<RunModel> runs) async {
    final indexFile = File('${dbDir.path}/$_indexFileName');
    final metadataList = runs.map((run) {
      final map = run.toMap();
      map['routePoints'] = const <dynamic>[];
      map['trackPoints'] = const <dynamic>[];
      return map;
    }).toList();
    await _atomicWriteString(indexFile, json.encode(metadataList));
  }

  Future<void> _migrateLegacyPrefsIfNeeded(Directory dbDir) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacyList = prefs.getStringList(_legacyStorageKey);
      if (legacyList == null || legacyList.isEmpty) return;

      final List<RunModel> migrated = [];
      for (final raw in legacyList) {
        try {
          migrated.add(RunModel.fromJson(raw));
        } catch (e) {
          debugPrint('Melewati data legacy korup saat migrasi: $e');
        }
      }

      if (migrated.isNotEmpty) {
        for (final run in migrated) {
          await _writeTrackFile(dbDir, run);
        }
        await _writeIndexFile(dbDir, migrated);
      }
      await prefs.remove(_legacyStorageKey);
    } catch (e) {
      debugPrint('Migrasi legacy SharedPreferences dilewati: $e');
    }
  }

  Future<List<RunModel>> _getFromSharedPrefsFallback() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? jsonStringList = prefs.getStringList(_legacyStorageKey);
    if (jsonStringList == null) return [];

    final List<RunModel> runs = [];
    for (final rawJson in jsonStringList) {
      try {
        runs.add(RunModel.fromJson(rawJson));
      } catch (e) {
        debugPrint('Melewati data lari korup saat parsing: $e');
      }
    }
    return runs;
  }

  Future<void> _saveToSharedPrefsFallback(List<RunModel> runs) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> jsonStringList = runs.map((e) => e.toJson()).toList();
    await prefs.setStringList(_legacyStorageKey, jsonStringList);
  }

  Future<List<RunModel>> getSavedRuns() async {
    final dbDir = await _resolveDbDir();
    if (dbDir == null) {
      return _getFromSharedPrefsFallback();
    }

    final indexFile = File('${dbDir.path}/$_indexFileName');
    if (!await indexFile.exists()) {
      await _migrateLegacyPrefsIfNeeded(dbDir);
    }

    if (!await indexFile.exists()) return [];

    try {
      final rawIndex = await indexFile.readAsString();
      final decoded = json.decode(rawIndex) as List<dynamic>;
      final List<RunModel> runs = [];

      for (final item in decoded) {
        try {
          final map = Map<String, dynamic>.from(item as Map);
          final id = map['id']?.toString() ?? '';
          final trackData = await _readTrackFile(dbDir, id);
          if (trackData != null) {
            map['routePoints'] = trackData['routePoints'] ?? const <dynamic>[];
            map['trackPoints'] = trackData['trackPoints'] ?? const <dynamic>[];
          }
          runs.add(RunModel.fromMap(map));
        } catch (e) {
          debugPrint('Melewati entri lari korup: $e');
        }
      }
      return runs;
    } catch (e) {
      debugPrint('Gagal membaca indeks riwayat lari: $e');
      return [];
    }
  }

  Future<void> saveRun(RunModel run) async {
    final dbDir = await _resolveDbDir();
    final List<RunModel> currentRuns = await getSavedRuns();
    currentRuns.insert(0, run);

    if (dbDir == null) {
      await _saveToSharedPrefsFallback(currentRuns);
    } else {
      await _writeTrackFile(dbDir, run);
      await _writeIndexFile(dbDir, currentRuns);
    }
    runUpdateNotifier.value++;
    unawaited(SocialFeedService.publishRunToFeed(run));
  }

  Future<void> updateRun(RunModel updatedRun) async {
    final dbDir = await _resolveDbDir();
    final List<RunModel> currentRuns = await getSavedRuns();

    final index = currentRuns.indexWhere((r) => r.id == updatedRun.id);
    if (index != -1) {
      currentRuns[index] = updatedRun;
      if (dbDir == null) {
        await _saveToSharedPrefsFallback(currentRuns);
      } else {
        await _writeTrackFile(dbDir, updatedRun);
        await _writeIndexFile(dbDir, currentRuns);
      }
      runUpdateNotifier.value++;
      unawaited(SocialFeedService.publishRunToFeed(updatedRun));
    }
  }

  Future<void> deleteRun(String id) async {
    final dbDir = await _resolveDbDir();
    final List<RunModel> currentRuns = await getSavedRuns();

    final target = currentRuns.where((r) => r.id == id).toList();
    if (target.isNotEmpty && target.first.photoPath != null) {
      final f = File(target.first.photoPath!);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    currentRuns.removeWhere((run) => run.id == id);

    if (dbDir == null) {
      await _saveToSharedPrefsFallback(currentRuns);
    } else {
      await _deleteTrackFile(dbDir, id);
      await _writeIndexFile(dbDir, currentRuns);
    }
    runUpdateNotifier.value++;
    unawaited(SocialFeedService.deletePublishedRun(id));
  }

  /// Menyalin foto aktivitas lari ke penyimpanan permanen aplikasi
  Future<String> saveRunPhoto(File sourceFile) async {
    final appDir = _overrideBaseDir ?? await getApplicationDocumentsDirectory();
    final fileName = 'run_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedFile = await sourceFile.copy('${appDir.path}/$fileName');
    return savedFile.path;
  }

  /// Mengekspor aktivitas ke file standar GPX 1.1 di direktori dokumen aplikasi
  Future<File> exportRunToGpxFile(RunModel run) async {
    final baseDir = _overrideBaseDir ?? await getApplicationDocumentsDirectory();
    final exportDir = Directory('${baseDir.path}/gpx_exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    final file = File('${exportDir.path}/adventure_run_${_safeFileId(run.id)}.gpx');
    final gpxContent = GpxExporter.toGpxXml(run);
    await _atomicWriteString(file, gpxContent);
    return file;
  }
}
