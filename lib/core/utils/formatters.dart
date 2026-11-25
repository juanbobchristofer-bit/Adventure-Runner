/// Utility pemformatan waktu & angka yang digunakan konsisten di seluruh aplikasi.
class AppFormatters {
  /// Format ringkas untuk ringkasan total waktu, contoh: "45m" atau "1j 20m".
  static String formatCompactDuration(int totalSeconds) {
    final safeSec = totalSeconds < 0 ? 0 : totalSeconds;
    final int hours = safeSec ~/ 3600;
    final int minutes = (safeSec % 3600) ~/ 60;
    if (hours == 0) return '${minutes}m';
    return '${hours}j ${minutes}m';
  }

  /// Format stopwatch untuk layar rekam & detail, contoh: "05:32" atau "01:05:32".
  static String formatClockDuration(int totalSeconds) {
    final safeSec = totalSeconds < 0 ? 0 : totalSeconds;
    final minutes = ((safeSec % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (safeSec % 60).toString().padLeft(2, '0');
    final hours = safeSec ~/ 3600;

    if (hours > 0) {
      final hrs = hours.toString().padLeft(2, '0');
      return '$hrs:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
