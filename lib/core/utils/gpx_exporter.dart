import '../../features/tracking/domain/run_model.dart';

/// Menghasilkan dokumen standar GPX 1.1 dari data [RunModel] untuk backup atau impor ke Strava/Garmin.
class GpxExporter {
  static String escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String toGpxXml(RunModel run) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="Adventure Runner" '
        'xmlns="http://www.topografix.com/GPX/1/1">',
      )
      ..writeln('  <metadata>')
      ..writeln('    <name>${escapeXml(run.title)}</name>')
      ..writeln('    <time>${run.createdAt.toUtc().toIso8601String()}</time>')
      ..writeln('  </metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>${escapeXml(run.title)}</name>')
      ..writeln('    <type>running</type>');

    if (run.notes.isNotEmpty) {
      buffer.writeln('    <desc>${escapeXml(run.notes)}</desc>');
    }

    buffer.writeln('    <trkseg>');

    if (run.trackPoints.isNotEmpty) {
      for (final tp in run.trackPoints) {
        final pointTime = run.createdAt.add(Duration(seconds: tp.elapsedSeconds)).toUtc();
        buffer
          ..writeln('      <trkpt lat="${tp.latitude}" lon="${tp.longitude}">')
          ..writeln('        <ele>${tp.altitude.toStringAsFixed(1)}</ele>')
          ..writeln('        <time>${pointTime.toIso8601String()}</time>')
          ..writeln('      </trkpt>');
      }
    } else {
      for (final pt in run.routePoints) {
        buffer.writeln('      <trkpt lat="${pt.latitude}" lon="${pt.longitude}" />');
      }
    }

    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');

    return buffer.toString();
  }
}
