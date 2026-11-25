import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:adventure_runner/features/tracking/domain/run_model.dart';
import 'package:adventure_runner/features/tracking/domain/runner_stats.dart';

void main() {
  group('RunModel serialization & backwards compatibility', () {
    test('parses legacy JSON without createdAt, elevationGainM, or trackPoints', () {
      const legacyJson = '''
      {
        "id": "1730000000000",
        "title": "Legacy Run",
        "date": "27/10/2024",
        "distanceInKm": 3.5,
        "durationInSeconds": 1200,
        "pace": "5:43",
        "steps": 4200,
        "calories": 240.0,
        "routePoints": [{"lat": -6.9311, "lng": 107.7733}]
      }
      ''';

      final run = RunModel.fromJson(legacyJson);
      expect(run.title, 'Legacy Run');
      expect(run.elevationGainM, 0.0);
      expect(run.trackPoints, isEmpty);
      expect(run.createdAt.millisecondsSinceEpoch, 1730000000000);
    });

    test('round-trips full RunModel with trackPoints and elevationGainM', () {
      final now = DateTime(2026, 11, 25, 7, 30);
      final original = RunModel(
        id: 'run_1',
        title: 'Morning Trail',
        date: '25/11/2026',
        createdAt: now,
        distanceInKm: 2.0,
        durationInSeconds: 660,
        pace: '5:30',
        steps: 2400,
        calories: 145.0,
        elevationGainM: 42.5,
        routePoints: const [LatLng(-6.9311, 107.7733), LatLng(-6.9221, 107.7733)],
        trackPoints: const [
          RunTrackPoint(latitude: -6.9311, longitude: 107.7733, altitude: 700, elapsedSeconds: 0),
          RunTrackPoint(latitude: -6.9221, longitude: 107.7733, altitude: 742.5, elapsedSeconds: 330),
        ],
        notes: 'Cuaca cerah!',
        feeling: 'Pecah Rekor ⚡',
      );

      final decoded = RunModel.fromJson(original.toJson());
      expect(decoded.createdAt, now);
      expect(decoded.elevationGainM, 42.5);
      expect(decoded.trackPoints.length, 2);
      expect(decoded.trackPoints.last.elapsedSeconds, 330);
      expect(decoded.notes, 'Cuaca cerah!');
    });
  });

  group('RunnerStats weekly calculation & actual splits', () {
    test('weeklyDistance only counts runs from Monday of current week', () {
      // Rabu, 25 Nov 2026 -> Senin minggu ini adalah 23 Nov 2026 00:00
      final ref = DateTime(2026, 11, 25, 14, 0);
      final runs = [
        RunModel(
          id: '1',
          title: 'This Week',
          date: '24/11/2026',
          createdAt: DateTime(2026, 11, 24, 6, 30),
          distanceInKm: 5.2,
          durationInSeconds: 1800,
          pace: '5:46',
          steps: 6000,
          calories: 350,
          routePoints: const [],
        ),
        RunModel(
          id: '2',
          title: 'Last Week',
          date: '22/11/2026',
          createdAt: DateTime(2026, 11, 22, 18, 0),
          distanceInKm: 10.0,
          durationInSeconds: 3600,
          pace: '6:00',
          steps: 12000,
          calories: 650,
          routePoints: const [],
        ),
      ];

      expect(RunnerStats.weeklyDistance(runs, ref), closeTo(5.2, 0.001));
      expect(RunnerStats.weeklyRunsCount(runs, ref), 1);
      expect(RunnerStats.totalDistance(runs), closeTo(15.2, 0.001));
    });

    test('rankTitle is consistent and reflects active vs rookie states', () {
      expect(RunnerStats.rankTitle(const []), 'ROOKIE RUNNER');
      final oneShortRun = [
        RunModel(
          id: '1',
          title: 'Short',
          date: '25/11/2026',
          distanceInKm: 1.0,
          durationInSeconds: 360,
          pace: '6:00',
          steps: 1200,
          calories: 65,
          routePoints: const [],
        ),
      ];
      expect(RunnerStats.rankTitle(oneShortRun), 'ACTIVE STRIDER');
    });

    test('bonusXp increases totalXp, runnerLevel, and unlocks level gating', () {
      expect(RunnerStats.runnerLevel(const [], bonusXp: 0), 1);
      expect(RunnerStats.xpNeededForLevel(2, 0), 500);
      expect(RunnerStats.xpNeededForLevel(3, 600), 400);
      expect(RunnerStats.meetsLevelRequirement(userLevel: 1, minLevel: 2), isFalse);

      // Setelah klaim bonus 550 XP -> naik ke Level 2
      expect(RunnerStats.totalXp(const [], bonusXp: 550), 550);
      expect(RunnerStats.runnerLevel(const [], bonusXp: 550), 2);
      expect(RunnerStats.meetsLevelRequirement(userLevel: 2, minLevel: 2), isTrue);
      expect(RunnerStats.rankTitle(const [], bonusXp: 1000), 'CITY PACER');
    });

    test('calculateKmSplits uses actual trackPoints telemetry when available', () {
      // ~1.000 meter ke utara ≈ +0.009009 derajat latitude
      final run = RunModel(
        id: 'split_test',
        title: 'Negative Split Run',
        date: '25/11/2026',
        distanceInKm: 2.0,
        durationInSeconds: 660,
        pace: '5:30',
        steps: 2400,
        calories: 140,
        routePoints: const [
          LatLng(-6.9300, 107.7700),
          LatLng(-6.9210, 107.7700),
          LatLng(-6.9120, 107.7700),
        ],
        trackPoints: const [
          RunTrackPoint(latitude: -6.9300, longitude: 107.7700, elapsedSeconds: 0),
          RunTrackPoint(latitude: -6.9210, longitude: 107.7700, elapsedSeconds: 360), // ~6:00/km
          RunTrackPoint(latitude: -6.9120, longitude: 107.7700, elapsedSeconds: 660), // ~5:00/km
        ],
      );

      final splits = RunnerStats.calculateKmSplits(run);
      expect(splits.length, greaterThanOrEqualTo(2));
      expect(splits.first.isActualTelemetry, isTrue);
      // KM 2 harus lebih cepat (speedKmh lebih besar) daripada KM 1
      expect(splits[1].speedKmh, greaterThan(splits[0].speedKmh));
    });
  });
}
