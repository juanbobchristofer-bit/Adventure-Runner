import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/tracking/domain/run_model.dart';

/// Snapshot sementara dari sesi lari yang sedang berjalan untuk pemulihan jika aplikasi
/// tertutup paksa / crash / baterai habis.
class ActiveRunDraft {
  final int modeIndex;
  final double totalDistanceMeters;
  final double elevationGainM;
  final int stepCount;
  final int elapsedSeconds;
  final int completedKmCount;
  final int lastKmSplitSeconds;
  final List<LatLng> routePoints;
  final List<RunTrackPoint> trackPoints;
  final DateTime savedAt;

  const ActiveRunDraft({
    required this.modeIndex,
    required this.totalDistanceMeters,
    required this.elevationGainM,
    required this.stepCount,
    required this.elapsedSeconds,
    required this.completedKmCount,
    required this.lastKmSplitSeconds,
    required this.routePoints,
    required this.trackPoints,
    required this.savedAt,
  });

  bool get hasMeaningfulProgress => elapsedSeconds >= 10 || totalDistanceMeters >= 20.0;

  Map<String, dynamic> toMap() {
    return {
      'modeIndex': modeIndex,
      'totalDistanceMeters': totalDistanceMeters,
      'elevationGainM': elevationGainM,
      'stepCount': stepCount,
      'elapsedSeconds': elapsedSeconds,
      'completedKmCount': completedKmCount,
      'lastKmSplitSeconds': lastKmSplitSeconds,
      'routePoints': routePoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      'trackPoints': trackPoints.map((p) => p.toMap()).toList(),
      'savedAt': savedAt.toIso8601String(),
    };
  }

  factory ActiveRunDraft.fromMap(Map<String, dynamic> map) {
    final rawRoute = map['routePoints'] as List<dynamic>? ?? const [];
    final rawTrack = map['trackPoints'] as List<dynamic>? ?? const [];

    return ActiveRunDraft(
      modeIndex: (map['modeIndex'] as num?)?.toInt() ?? 0,
      totalDistanceMeters: (map['totalDistanceMeters'] as num?)?.toDouble() ?? 0.0,
      elevationGainM: (map['elevationGainM'] as num?)?.toDouble() ?? 0.0,
      stepCount: (map['stepCount'] as num?)?.toInt() ?? 0,
      elapsedSeconds: (map['elapsedSeconds'] as num?)?.toInt() ?? 0,
      completedKmCount: (map['completedKmCount'] as num?)?.toInt() ?? 0,
      lastKmSplitSeconds: (map['lastKmSplitSeconds'] as num?)?.toInt() ?? 0,
      routePoints: rawRoute
          .whereType<Map>()
          .map((e) => LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble()))
          .toList(),
      trackPoints: rawTrack
          .whereType<Map>()
          .map((e) => RunTrackPoint.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      savedAt: DateTime.tryParse(map['savedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// Menyimpan dan memulihkan checkpoint sesi lari secara atomik ke disk.
class RunDraftService {
  static const String _dbFolderName = 'runs_db';
  static const String _draftFileName = 'active_run_draft.json';

  final Directory? _overrideBaseDir;

  RunDraftService({Directory? baseDir}) : _overrideBaseDir = baseDir;

  Future<File> _getDraftFile() async {
    final baseDir = _overrideBaseDir ?? await getApplicationDocumentsDirectory();
    final dbDir = Directory('${baseDir.path}/$_dbFolderName');
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }
    return File('${dbDir.path}/$_draftFileName');
  }

  Future<void> saveDraft(ActiveRunDraft draft) async {
    try {
      final file = await _getDraftFile();
      final tmpFile = File('${file.path}.tmp');
      await tmpFile.writeAsString(jsonEncode(draft.toMap()), flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tmpFile.rename(file.path);
    } catch (e) {
      debugPrint('Gagal menyimpan checkpoint draft lari: $e');
    }
  }

  Future<ActiveRunDraft?> loadDraft() async {
    try {
      final file = await _getDraftFile();
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return null;
      final draft = ActiveRunDraft.fromMap(decoded);
      if (!draft.hasMeaningfulProgress) return null;
      return draft;
    } catch (e) {
      debugPrint('Draft lari korup dilewati: $e');
      return null;
    }
  }

  Future<void> clearDraft() async {
    try {
      final file = await _getDraftFile();
      if (await file.exists()) {
        await file.delete();
      }
      final tmpFile = File('${file.path}.tmp');
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
    } catch (e) {
      debugPrint('Gagal menghapus draft lari: $e');
    }
  }
}
