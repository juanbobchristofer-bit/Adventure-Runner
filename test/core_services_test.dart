import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adventure_runner/core/services/offline_tile_provider.dart';
import 'package:adventure_runner/core/services/run_draft_service.dart';
import 'package:adventure_runner/core/services/run_storage_service.dart';
import 'package:adventure_runner/core/utils/formatters.dart';
import 'package:adventure_runner/core/utils/gpx_exporter.dart';
import 'package:adventure_runner/features/tracking/domain/run_model.dart';
import 'package:adventure_runner/features/tracking/domain/runner_stats.dart';

void main() {
  group('AppFormatters', () {
    test('formatCompactDuration handles minutes and hours cleanly', () {
      expect(AppFormatters.formatCompactDuration(0), '0m');
      expect(AppFormatters.formatCompactDuration(-10), '0m');
      expect(AppFormatters.formatCompactDuration(900), '15m');
      expect(AppFormatters.formatCompactDuration(4500), '1j 15m');
    });

    test('formatClockDuration formats mm:ss and hh:mm:ss', () {
      expect(AppFormatters.formatClockDuration(0), '00:00');
      expect(AppFormatters.formatClockDuration(332), '05:32');
      expect(AppFormatters.formatClockDuration(3932), '01:05:32');
    });
  });

  group('GpxExporter', () {
    test('exports valid GPX 1.1 XML with escaped metadata and trackpoints', () {
      final run = RunModel(
        id: 'gpx_1',
        title: 'Trail & Sprint <5K>',
        date: '25/11/2026',
        createdAt: DateTime.utc(2026, 11, 25, 6, 0, 0),
        distanceInKm: 1.5,
        durationInSeconds: 500,
        pace: '5:33',
        steps: 1800,
        calories: 100,
        routePoints: const [LatLng(-6.9311, 107.7733)],
        trackPoints: const [
          RunTrackPoint(latitude: -6.9311, longitude: 107.7733, altitude: 712.4, elapsedSeconds: 0),
          RunTrackPoint(latitude: -6.9250, longitude: 107.7740, altitude: 720.0, elapsedSeconds: 250),
        ],
        notes: 'Pagi "segar" & cerah',
      );

      final xml = GpxExporter.toGpxXml(run);
      expect(xml, contains('<gpx version="1.1"'));
      expect(xml, contains('<name>Trail &amp; Sprint &lt;5K&gt;</name>'));
      expect(xml, contains('<desc>Pagi &quot;segar&quot; &amp; cerah</desc>'));
      expect(xml, contains('<trkpt lat="-6.9311" lon="107.7733">'));
      expect(xml, contains('<ele>712.4</ele>'));
      expect(xml, contains('<time>2026-11-25T06:04:10.000Z</time>'));
    });
  });

  group('RunStorageService file repository & migration', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('adventure_runner_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saves, updates, exports GPX, and deletes runs while firing runUpdateNotifier', () async {
      final storage = RunStorageService(baseDir: tempDir);
      int notifications = 0;
      void listener() => notifications++;
      RunStorageService.runUpdateNotifier.addListener(listener);

      try {
        final run = RunModel(
          id: 'run_100',
          title: 'Lari Pagi',
          date: '25/11/2026',
          distanceInKm: 4.2,
          durationInSeconds: 1400,
          pace: '5:33',
          steps: 5000,
          calories: 280,
          elevationGainM: 32,
          routePoints: const [LatLng(-6.9311, 107.7733), LatLng(-6.9280, 107.7750)],
          trackPoints: const [
            RunTrackPoint(latitude: -6.9311, longitude: 107.7733, altitude: 700, elapsedSeconds: 0),
            RunTrackPoint(latitude: -6.9280, longitude: 107.7750, altitude: 732, elapsedSeconds: 1400),
          ],
        );

        await storage.saveRun(run);
        expect(notifications, 1);

        final loaded = await storage.getSavedRuns();
        expect(loaded.length, 1);
        expect(loaded.first.title, 'Lari Pagi');
        expect(loaded.first.trackPoints.length, 2);
        expect(loaded.first.elevationGainM, 32);

        // Update run
        await storage.updateRun(run.copyWith(title: 'Lari Pagi Cepat', notes: 'Mantap'));
        expect(notifications, 2);
        final afterUpdate = await storage.getSavedRuns();
        expect(afterUpdate.first.title, 'Lari Pagi Cepat');
        expect(afterUpdate.first.notes, 'Mantap');

        // Export GPX file
        final gpxFile = await storage.exportRunToGpxFile(afterUpdate.first);
        expect(await gpxFile.exists(), isTrue);
        expect(await gpxFile.readAsString(), contains('<gpx version="1.1"'));

        // Delete run
        await storage.deleteRun('run_100');
        expect(notifications, 3);
        expect(await storage.getSavedRuns(), isEmpty);
      } finally {
        RunStorageService.runUpdateNotifier.removeListener(listener);
      }
    });

    test('migrates legacy SharedPreferences runs cleanly and skips corrupted entries', () async {
      final validRun = RunModel(
        id: 'legacy_1',
        title: 'Legacy Run',
        date: '20/11/2026',
        distanceInKm: 3.0,
        durationInSeconds: 1000,
        pace: '5:33',
        steps: 3600,
        calories: 200,
        routePoints: const [LatLng(-6.93, 107.77)],
      );

      SharedPreferences.setMockInitialValues({
        'saved_runs_list': [validRun.toJson(), '{corrupted_json'],
      });

      final storage = RunStorageService(baseDir: tempDir);
      final runs = await storage.getSavedRuns();
      expect(runs.length, 1);
      expect(runs.first.id, 'legacy_1');

      // Legacy key dihapus setelah migrasi berhasil ke file repository
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('saved_runs_list'), isNull);
    });
  });

  group('OfflineTileCacheService helpers', () {
    test('formatBytes formats B, KB, and MB accurately', () {
      expect(OfflineTileCacheService.formatBytes(512), '512 B');
      expect(OfflineTileCacheService.formatBytes(2048), '2.0 KB');
      expect(OfflineTileCacheService.formatBytes(3 * 1024 * 1024), '3.0 MB');
    });

    test('isStale flags timestamps older than 30 days', () {
      expect(OfflineTileCacheService.isStale(DateTime.now().subtract(const Duration(days: 5))), isFalse);
      expect(OfflineTileCacheService.isStale(DateTime.now().subtract(const Duration(days: 35))), isTrue);
    });
  });

  group('RunDraftService anti-crash checkpointing', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('adventure_runner_draft_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saves, reloads, and clears active run draft atomically', () async {
      final service = RunDraftService(baseDir: tempDir);
      expect(await service.loadDraft(), isNull);

      final draft = ActiveRunDraft(
        modeIndex: 1,
        totalDistanceMeters: 1245.5,
        elevationGainM: 18.0,
        stepCount: 1520,
        elapsedSeconds: 410,
        completedKmCount: 1,
        lastKmSplitSeconds: 330,
        routePoints: const [LatLng(-6.9311, 107.7733), LatLng(-6.9250, 107.7750)],
        trackPoints: const [
          RunTrackPoint(latitude: -6.9311, longitude: 107.7733, altitude: 710.0, elapsedSeconds: 0),
          RunTrackPoint(latitude: -6.9250, longitude: 107.7750, altitude: 728.0, elapsedSeconds: 410),
        ],
        savedAt: DateTime.utc(2026, 11, 26, 6, 30, 0),
      );

      await service.saveDraft(draft);
      final restored = await service.loadDraft();
      expect(restored, isNotNull);
      expect(restored!.modeIndex, 1);
      expect(restored.totalDistanceMeters, closeTo(1245.5, 0.01));
      expect(restored.completedKmCount, 1);
      expect(restored.lastKmSplitSeconds, 330);
      expect(restored.trackPoints.length, 2);

      await service.clearDraft();
      expect(await service.loadDraft(), isNull);
    });
  });

  group('RunnerStats Poin 2 telemetry helpers', () {
    test('calculateRollingCurrentPace computes recent 15s window pace and falls back to live speed', () {
      // ~55.6 m dalam 15 detik => ~4:30 /km
      const pts = [
        RunTrackPoint(latitude: -6.9300, longitude: 107.7700, altitude: 700, elapsedSeconds: 0),
        RunTrackPoint(latitude: -6.9295, longitude: 107.7700, altitude: 701, elapsedSeconds: 15),
      ];
      final rolling = RunnerStats.calculateRollingCurrentPace(pts, windowSeconds: 15);
      expect(rolling, isNot('--:--'));

      // Fallback ke liveSpeedMs (3.333 m/s => 5:00 /km)
      final liveOnly = RunnerStats.calculateRollingCurrentPace(const [], liveSpeedMs: 1000 / 300);
      expect(liveOnly, '5:00');
    });

    test('rankTitleForLevel returns consistent rank tiers', () {
      expect(RunnerStats.rankTitleForLevel(1, hasActivity: false), 'ROOKIE RUNNER');
      expect(RunnerStats.rankTitleForLevel(1, hasActivity: true), 'ACTIVE STRIDER');
      expect(RunnerStats.rankTitleForLevel(3), 'CITY PACER');
      expect(RunnerStats.rankTitleForLevel(6), 'TRAIL CONQUEROR');
      expect(RunnerStats.rankTitleForLevel(10), 'ELITE MARATHONER');
    });
  });
}
