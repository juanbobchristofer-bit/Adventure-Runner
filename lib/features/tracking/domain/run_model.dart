import 'dart:convert';
import 'package:latlong2/latlong.dart';

class RunTrackPoint {
  final double latitude;
  final double longitude;
  final double altitude;
  final int elapsedSeconds;

  const RunTrackPoint({
    required this.latitude,
    required this.longitude,
    this.altitude = 0.0,
    this.elapsedSeconds = 0,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  Map<String, dynamic> toMap() {
    return {
      'lat': latitude,
      'lng': longitude,
      'alt': altitude,
      'sec': elapsedSeconds,
    };
  }

  factory RunTrackPoint.fromMap(Map<String, dynamic> map) {
    return RunTrackPoint(
      latitude: (map['lat'] as num).toDouble(),
      longitude: (map['lng'] as num).toDouble(),
      altitude: (map['alt'] as num?)?.toDouble() ?? 0.0,
      elapsedSeconds: (map['sec'] as num?)?.toInt() ?? 0,
    );
  }
}

class RunModel {
  final String id;
  final String title;
  final String date;
  final DateTime createdAt;
  final double distanceInKm;
  final int durationInSeconds;
  final String pace;
  final int steps;
  final double calories;
  final double elevationGainM;
  final List<LatLng> routePoints;
  final List<RunTrackPoint> trackPoints;
  final String notes;
  final String? photoPath;
  final String feeling;

  RunModel({
    required this.id,
    required this.title,
    required this.date,
    DateTime? createdAt,
    required this.distanceInKm,
    required this.durationInSeconds,
    required this.pace,
    required this.steps,
    required this.calories,
    this.elevationGainM = 0.0,
    required this.routePoints,
    this.trackPoints = const [],
    this.notes = '',
    this.photoPath,
    this.feeling = 'Luar Biasa 🔥',
  }) : createdAt = createdAt ?? _inferCreatedAt(id, date);

  static DateTime _inferCreatedAt(String id, String dateStr) {
    final millis = int.tryParse(id);
    if (millis != null && millis > 946684800000) {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    final parts = dateStr.split('/');
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d);
      }
    }
    return DateTime.now();
  }

  RunModel copyWith({
    String? title,
    String? notes,
    String? photoPath,
    bool clearPhoto = false,
    String? feeling,
  }) {
    return RunModel(
      id: id,
      title: title ?? this.title,
      date: date,
      createdAt: createdAt,
      distanceInKm: distanceInKm,
      durationInSeconds: durationInSeconds,
      pace: pace,
      steps: steps,
      calories: calories,
      elevationGainM: elevationGainM,
      routePoints: routePoints,
      trackPoints: trackPoints,
      notes: notes ?? this.notes,
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      feeling: feeling ?? this.feeling,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'date': date,
      'createdAt': createdAt.toIso8601String(),
      'distanceInKm': distanceInKm,
      'durationInSeconds': durationInSeconds,
      'pace': pace,
      'steps': steps,
      'calories': calories,
      'elevationGainM': elevationGainM,
      'routePoints': routePoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      'trackPoints': trackPoints.map((tp) => tp.toMap()).toList(),
      'notes': notes,
      'photoPath': photoPath,
      'feeling': feeling,
    };
  }

  factory RunModel.fromMap(Map<String, dynamic> map) {
    final rawRoute = map['routePoints'] as List<dynamic>? ?? [];
    final List<LatLng> points = rawRoute
        .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
        .toList();

    final rawTrack = map['trackPoints'] as List<dynamic>? ?? [];
    final List<RunTrackPoint> tracks = rawTrack
        .map((tp) => RunTrackPoint.fromMap(Map<String, dynamic>.from(tp as Map)))
        .toList();

    final String id = map['id']?.toString() ?? '';
    final String date = map['date']?.toString() ?? '';
    final DateTime parsedCreatedAt = map['createdAt'] != null
        ? (DateTime.tryParse(map['createdAt'].toString()) ?? _inferCreatedAt(id, date))
        : _inferCreatedAt(id, date);

    return RunModel(
      id: id,
      title: map['title'] ?? 'Run Activity',
      date: date,
      createdAt: parsedCreatedAt,
      distanceInKm: (map['distanceInKm'] as num?)?.toDouble() ?? 0.0,
      durationInSeconds: (map['durationInSeconds'] as num?)?.toInt() ?? 0,
      pace: map['pace'] ?? '0:00',
      steps: (map['steps'] as num?)?.toInt() ?? 0,
      calories: (map['calories'] as num?)?.toDouble() ?? 0.0,
      elevationGainM: (map['elevationGainM'] as num?)?.toDouble() ?? 0.0,
      routePoints: points,
      trackPoints: tracks,
      notes: map['notes'] ?? '',
      photoPath: map['photoPath'],
      feeling: map['feeling'] ?? 'Luar Biasa 🔥',
    );
  }

  String toJson() => json.encode(toMap());

  factory RunModel.fromJson(String source) => RunModel.fromMap(json.decode(source));
}