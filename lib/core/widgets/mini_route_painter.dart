import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../constants/app_colors.dart';

/// Painter ringan untuk menggambar pratinjau jalur GPS mini pada kartu aktivitas.
class MiniRoutePainter extends CustomPainter {
  final List<LatLng> points;

  const MiniRoutePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      final paint = Paint()
        ..color = Colors.white24
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(size.width * 0.2, size.height * 0.8)
        ..quadraticBezierTo(size.width * 0.2, size.height * 0.2, size.width * 0.5, size.height * 0.5)
        ..quadraticBezierTo(size.width * 0.8, size.height * 0.8, size.width * 0.8, size.height * 0.2);
      canvas.drawPath(path, paint);
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final double latSpan = (maxLat - minLat) == 0 ? 0.0001 : (maxLat - minLat);
    final double lngSpan = (maxLng - minLng) == 0 ? 0.0001 : (maxLng - minLng);

    final path = Path();
    Offset? startOffset;
    Offset? endOffset;

    for (int i = 0; i < points.length; i++) {
      final normX = (points[i].longitude - minLng) / lngSpan;
      final normY = 1.0 - ((points[i].latitude - minLat) / latSpan);
      final offset = Offset(normX * size.width, normY * size.height);

      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
        startOffset = offset;
      } else {
        path.lineTo(offset.dx, offset.dy);
        endOffset = offset;
      }
    }

    final routePaint = Paint()
      ..color = AppColors.primaryOrange
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, routePaint);

    if (startOffset != null) {
      canvas.drawCircle(startOffset, 2.8, Paint()..color = AppColors.accentGreen);
    }
    if (endOffset != null) {
      canvas.drawCircle(endOffset, 2.8, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant MiniRoutePainter oldDelegate) => oldDelegate.points != points;
}
