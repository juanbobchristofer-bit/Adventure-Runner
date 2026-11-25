import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../features/tracking/domain/run_model.dart';
import '../../features/tracking/domain/runner_stats.dart';
import '../constants/app_colors.dart';

/// Kartu visualisasi grafik Elevasi (m) dan Kecepatan (km/j) berbasis data telemetri GPS.
class TelemetryChartCard extends StatefulWidget {
  final RunModel run;
  final List<KmSplit> splits;

  const TelemetryChartCard({
    super.key,
    required this.run,
    required this.splits,
  });

  @override
  State<TelemetryChartCard> createState() => _TelemetryChartCardState();
}

class _TelemetryChartCardState extends State<TelemetryChartCard> {
  static const Distance _geoDistance = Distance();
  int _selectedChart = 0; // 0 = Kecepatan/Pace, 1 = Elevasi

  List<double> _buildSpeedSeries() {
    final pts = widget.run.trackPoints;
    if (pts.length >= 3) {
      final rawSpeeds = <double>[];
      for (int i = 1; i < pts.length; i++) {
        final dt = pts[i].elapsedSeconds - pts[i - 1].elapsedSeconds;
        if (dt <= 0) continue;
        final meters = _geoDistance.as(LengthUnit.Meter, pts[i - 1].latLng, pts[i].latLng);
        final kmh = (meters / dt) * 3.6;
        if (kmh >= 0 && kmh <= 30) {
          rawSpeeds.add(kmh);
        }
      }
      if (rawSpeeds.length >= 2) {
        return _downsample(rawSpeeds, 28);
      }
    }

    if (widget.splits.length >= 2) {
      return widget.splits.map((s) => s.speedKmh).toList();
    }
    return const [];
  }

  List<double> _buildElevationSeries() {
    final pts = widget.run.trackPoints;
    if (pts.length < 2) return const [];
    final alts = pts.map((p) => p.altitude).where((a) => a.abs() > 0.01).toList();
    if (alts.length < 2) return const [];
    return _downsample(alts, 28);
  }

  List<double> _downsample(List<double> data, int maxSamples) {
    if (data.length <= maxSamples) return data;
    final step = data.length / maxSamples;
    final out = <double>[];
    for (int i = 0; i < maxSamples; i++) {
      final start = (i * step).floor();
      final end = ((i + 1) * step).ceil().clamp(start + 1, data.length);
      double sum = 0;
      for (int j = start; j < end; j++) {
        sum += data[j];
      }
      out.add(sum / (end - start));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final speedSeries = _buildSpeedSeries();
    final elevSeries = _buildElevationSeries();

    if (speedSeries.isEmpty && elevSeries.isEmpty) {
      return const SizedBox.shrink();
    }

    final bool hasSpeed = speedSeries.length >= 2;
    final bool hasElev = elevSeries.length >= 2;
    final int activeTab = (_selectedChart == 1 && hasElev) || !hasSpeed ? 1 : 0;

    final values = activeTab == 0 ? speedSeries : elevSeries;
    final Color lineColor = activeTab == 0 ? AppColors.primaryOrange : AppColors.accentGreen;
    final String unit = activeTab == 0 ? 'km/j' : 'm';

    final double minVal = values.reduce(math.min);
    final double maxVal = values.reduce(math.max);
    final double avgVal = values.reduce((a, b) => a + b) / values.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Grafik Telemetri',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              if (hasSpeed && hasElev)
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildToggleChip('Kecepatan', activeTab == 0, AppColors.primaryOrange, () {
                        setState(() => _selectedChart = 0);
                      }),
                      _buildToggleChip('Elevasi', activeTab == 1, AppColors.accentGreen, () {
                        setState(() => _selectedChart = 1);
                      }),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLegendStat('MIN', '${minVal.toStringAsFixed(1)} $unit', AppColors.textSecondary),
              _buildLegendStat('RATA-RATA', '${avgVal.toStringAsFixed(1)} $unit', Colors.white),
              _buildLegendStat('MAKS', '${maxVal.toStringAsFixed(1)} $unit', lineColor),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 135,
            width: double.infinity,
            child: CustomPaint(
              painter: _AreaLineChartPainter(
                values: values,
                lineColor: lineColor,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('0.0 km', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
              Text(
                '${(widget.run.distanceInKm / 2).toStringAsFixed(1)} km',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
              ),
              Text(
                '${widget.run.distanceInKm.toStringAsFixed(2)} km',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip(String label, bool selected, Color accent, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendStat(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 9.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: valueColor, fontSize: 12.5, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _AreaLineChartPainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;

  const _AreaLineChartPainter({
    required this.values,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    // Garis grid horizontal tipis
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (int i = 0; i <= 3; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = (maxV - minV).abs() < 0.001 ? 1.0 : (maxV - minV);
    final padY = size.height * 0.12;
    final usableH = size.height - (padY * 2);

    final offsets = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final norm = (values[i] - minV) / span;
      final y = size.height - padY - (norm * usableH);
      offsets.add(Offset(x, y));
    }

    final linePath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (int i = 1; i < offsets.length; i++) {
      final prev = offsets[i - 1];
      final curr = offsets[i];
      final midX = (prev.dx + curr.dx) / 2;
      linePath.cubicTo(midX, prev.dy, midX, curr.dy, curr.dx, curr.dy);
    }

    final areaPath = Path.from(linePath)
      ..lineTo(offsets.last.dx, size.height)
      ..lineTo(offsets.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.38),
          lineColor.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(areaPath, fillPaint);

    final strokePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(linePath, strokePaint);

    // Titik puncak
    int peakIdx = 0;
    for (int i = 1; i < values.length; i++) {
      if (values[i] > values[peakIdx]) peakIdx = i;
    }
    canvas.drawCircle(offsets[peakIdx], 4.5, Paint()..color = lineColor);
    canvas.drawCircle(offsets[peakIdx], 2.2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _AreaLineChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.lineColor != lineColor;
}
