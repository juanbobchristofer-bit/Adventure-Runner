import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'run_model.dart';

class KmSplit {
  final int kmIndex;
  final double distanceKm;
  final String paceStr;
  final double speedKmh;
  final bool isActualTelemetry;

  const KmSplit({
    required this.kmIndex,
    required this.distanceKm,
    required this.paceStr,
    required this.speedKmh,
    required this.isActualTelemetry,
  });
}

class GuidedRoute {
  final String name;
  final double distanceKm;
  final Color color;
  final List<LatLng> points;

  const GuidedRoute({
    required this.name,
    required this.distanceKm,
    required this.color,
    required this.points,
  });
}

/// Controller ringan untuk meneruskan rute panduan dari tab Peta ke tab Rekam
/// tanpa menumpuk instance RecordRunScreen baru.
class GuidedRouteController {
  static final ValueNotifier<GuidedRoute?> activeRoute = ValueNotifier<GuidedRoute?>(null);
  static final ValueNotifier<int?> tabNavigationRequest = ValueNotifier<int?>(null);

  static void startGuidedRun(GuidedRoute route) {
    activeRoute.value = route;
    tabNavigationRequest.value = 2; // Pindah ke tab Rekam
  }

  static void clearGuide() {
    activeRoute.value = null;
  }
}

/// Sumber kebenaran tunggal untuk kalkulasi statistik pelari (XP, Level, Rank, Target Mingguan, Split).
class RunnerStats {
  static const Distance _geoDistance = Distance();

  static double totalDistance(List<RunModel> runs) =>
      runs.fold(0.0, (sum, item) => sum + item.distanceInKm);

  static double totalCalories(List<RunModel> runs) =>
      runs.fold(0.0, (sum, item) => sum + item.calories);

  static int totalDurationSeconds(List<RunModel> runs) =>
      runs.fold(0, (sum, item) => sum + item.durationInSeconds);

  /// Awal minggu kalender (Senin 00:00:00 waktu lokal)
  static DateTime startOfCurrentWeek([DateTime? reference]) {
    final now = reference ?? DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return todayStart.subtract(Duration(days: now.weekday - DateTime.monday));
  }

  static List<RunModel> runsInCurrentWeek(List<RunModel> runs, [DateTime? reference]) {
    final weekStart = startOfCurrentWeek(reference);
    return runs.where((r) => !r.createdAt.isBefore(weekStart)).toList();
  }

  static double weeklyDistance(List<RunModel> runs, [DateTime? reference]) =>
      totalDistance(runsInCurrentWeek(runs, reference));

  static int weeklyRunsCount(List<RunModel> runs, [DateTime? reference]) =>
      runsInCurrentWeek(runs, reference).length;

  static const int xpPerLevel = 500;

  // Sistem XP terpadu: 100 XP per km + 50 XP per sesi selesai + Bonus XP hadiah tantangan/acara
  static int totalXp(List<RunModel> runs, {int bonusXp = 0}) =>
      (totalDistance(runs) * 100).round() + (runs.length * 50) + (bonusXp < 0 ? 0 : bonusXp);

  static int runnerLevel(List<RunModel> runs, {int bonusXp = 0}) =>
      (totalXp(runs, bonusXp: bonusXp) ~/ xpPerLevel) + 1;

  static double levelProgress(List<RunModel> runs, {int bonusXp = 0}) =>
      (totalXp(runs, bonusXp: bonusXp) % xpPerLevel) / xpPerLevel;

  /// Jumlah XP tambahan yang dibutuhkan untuk mencapai [targetLevel]
  static int xpNeededForLevel(int targetLevel, int currentTotalXp) {
    if (targetLevel <= 1) return 0;
    final requiredXp = (targetLevel - 1) * xpPerLevel;
    final diff = requiredXp - currentTotalXp;
    return diff > 0 ? diff : 0;
  }

  static bool meetsLevelRequirement({required int userLevel, required int minLevel}) =>
      userLevel >= minLevel;

  /// Gelar rank pelari berdasarkan level (sumber kebenaran tunggal untuk Profil, Home, dan Profil Mini Atlet)
  static String rankTitleForLevel(int level, {bool hasActivity = true}) {
    if (level >= 10) return 'ELITE MARATHONER';
    if (level >= 6) return 'TRAIL CONQUEROR';
    if (level >= 3) return 'CITY PACER';
    if (hasActivity) return 'ACTIVE STRIDER';
    return 'ROOKIE RUNNER';
  }

  /// Rank pelari konsisten di HomeScreen, ProfileScreen, dan GroupScreen
  static String rankTitle(List<RunModel> runs, {int bonusXp = 0}) {
    final level = runnerLevel(runs, bonusXp: bonusXp);
    return rankTitleForLevel(level, hasActivity: runs.isNotEmpty || bonusXp > 0);
  }

  /// Menghitung Current Pace (rolling window 15 detik terakhir) dari trackPoints GPS,
  /// dengan fallback halus ke kecepatan GPS aktual saat titik masih sedikit.
  static String calculateRollingCurrentPace(
    List<RunTrackPoint> trackPoints, {
    int windowSeconds = 15,
    double? liveSpeedMs,
  }) {
    if (trackPoints.length >= 2) {
      final latest = trackPoints.last;
      final minElapsed = latest.elapsedSeconds - windowSeconds;
      double windowMeters = 0.0;
      int? earliestElapsed;

      for (int i = trackPoints.length - 1; i >= 1; i--) {
        final curr = trackPoints[i];
        final prev = trackPoints[i - 1];
        if (curr.elapsedSeconds < minElapsed) break;
        final seg = _geoDistance.as(LengthUnit.Meter, prev.latLng, curr.latLng);
        if (seg > 0) {
          windowMeters += seg;
          earliestElapsed = prev.elapsedSeconds;
        }
        if (prev.elapsedSeconds <= minElapsed) break;
      }

      if (earliestElapsed != null) {
        final dt = latest.elapsedSeconds - earliestElapsed;
        if (dt >= 3 && windowMeters >= 12.0) {
          final paceSecPerKm = dt / (windowMeters / 1000.0);
          if (paceSecPerKm >= 90 && paceSecPerKm <= 1800) {
            return formatPaceFromSeconds(paceSecPerKm);
          }
        }
      }
    }

    if (liveSpeedMs != null && liveSpeedMs >= 0.7 && liveSpeedMs <= 12.5) {
      return formatPaceFromSeconds(1000.0 / liveSpeedMs);
    }

    return '--:--';
  }

  static String formatPaceFromSeconds(double paceSecondsPerKm) {
    if (paceSecondsPerKm <= 0 || paceSecondsPerKm.isNaN || paceSecondsPerKm.isInfinite) {
      return '--:--';
    }
    final int totalSec = paceSecondsPerKm.round();
    final int min = totalSec ~/ 60;
    final int sec = totalSec % 60;
    if (min > 99) return '--:--';
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  /// Menghitung split per kilometer AKTUAL dari trackPoints (jika tersedia timestamp),
  /// atau menampilkan rata-rata pace jujur untuk rekaman lama tanpa timestamp per titik.
  static List<KmSplit> calculateKmSplits(RunModel run) {
    if (run.distanceInKm < 0.2 || run.durationInSeconds <= 0) return [];

    // 1. Jika rekaman memiliki telemetri trackPoints dengan waktu aktual
    if (run.trackPoints.length >= 2 &&
        run.trackPoints.last.elapsedSeconds > run.trackPoints.first.elapsedSeconds) {
      final List<KmSplit> splits = [];
      double accumulatedMeters = 0.0;
      double lastSplitEndMeters = 0.0;
      double lastSplitEndSec = run.trackPoints.first.elapsedSeconds.toDouble();
      double nextTargetMeters = 1000.0;
      int splitIdx = 1;

      for (int i = 1; i < run.trackPoints.length; i++) {
        final prev = run.trackPoints[i - 1];
        final curr = run.trackPoints[i];
        final segMeters = _geoDistance.as(LengthUnit.Meter, prev.latLng, curr.latLng);
        if (segMeters <= 0) continue;

        accumulatedMeters += segMeters;
        final segSec = (curr.elapsedSeconds - prev.elapsedSeconds).toDouble();

        while (accumulatedMeters >= nextTargetMeters) {
          final overshoot = accumulatedMeters - nextTargetMeters;
          final fraction = ((segMeters - overshoot) / segMeters).clamp(0.0, 1.0);
          final crossingSec = prev.elapsedSeconds + (segSec * fraction);
          final splitDurationSec = (crossingSec - lastSplitEndSec).clamp(1.0, 36000.0);

          final paceSecPerKm = splitDurationSec; // segmen tepat 1.0 km
          splits.add(KmSplit(
            kmIndex: splitIdx,
            distanceKm: 1.0,
            paceStr: formatPaceFromSeconds(paceSecPerKm),
            speedKmh: 3600.0 / paceSecPerKm,
            isActualTelemetry: true,
          ));

          splitIdx++;
          lastSplitEndMeters = nextTargetMeters;
          lastSplitEndSec = crossingSec;
          nextTargetMeters += 1000.0;
        }
      }

      // Tambahkan sisa segmen terakhir jika >= 100 meter
      final remainingMeters = accumulatedMeters - lastSplitEndMeters;
      if (remainingMeters >= 100.0) {
        final remainingKm = remainingMeters / 1000.0;
        final remainingSec =
            (run.trackPoints.last.elapsedSeconds - lastSplitEndSec).clamp(1.0, 36000.0);
        final paceSecPerKm = remainingSec / remainingKm;
        splits.add(KmSplit(
          kmIndex: splitIdx,
          distanceKm: remainingKm,
          paceStr: formatPaceFromSeconds(paceSecPerKm),
          speedKmh: 3600.0 / paceSecPerKm,
          isActualTelemetry: true,
        ));
      }

      if (splits.isNotEmpty) return splits;
    }

    // 2. Fallback jujur untuk data lama (tanpa trackPoints): tampilkan pace rata-rata aktual tanpa manipulasi acak
    final double avgPaceSec = run.durationInSeconds / run.distanceInKm;
    final double avgSpeedKmh = 3600.0 / avgPaceSec;
    final String paceStr = formatPaceFromSeconds(avgPaceSec);

    final int fullKms = run.distanceInKm.floor();
    final double remainderKm = run.distanceInKm - fullKms;
    final int totalSplits = fullKms + (remainderKm >= 0.1 ? 1 : 0);

    return List.generate(totalSplits, (i) {
      final isLastPartial = (i == fullKms && remainderKm >= 0.1);
      return KmSplit(
        kmIndex: i + 1,
        distanceKm: isLastPartial ? remainderKm : 1.0,
        paceStr: paceStr,
        speedKmh: avgSpeedKmh,
        isActualTelemetry: false,
      );
    });
  }
}
