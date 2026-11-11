import 'dart:convert';
import 'package:latlong2/latlong.dart';

class RunModel {
  final String id;
  final String title;
  final String date;
  final double distanceInKm;
  final int durationInSeconds;
  final String pace;
  final int steps;
  final double calories;
  final List<LatLng> routePoints;

  RunModel({
    required this.id,
    required this.title,
    required this.date,
    required this.distanceInKm,
    required this.durationInSeconds,
    required this.pace,
    required this.steps,
    required this.calories,
    required this.routePoints,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'date': date,
      'distanceInKm': distanceInKm,
      'durationInSeconds': durationInSeconds,
      'pace': pace,
      'steps': steps,
      'calories': calories,
      'routePoints': routePoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
    };
  }

  factory RunModel.fromMap(Map<String, dynamic> map) {
    var rawRoute = map['routePoints'] as List<dynamic>? ?? [];
    List<LatLng> points = rawRoute
        .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
        .toList();

    return RunModel(
      id: map['id'] ?? '',
      title: map['title'] ?? 'Run Activity',
      date: map['date'] ?? '',
      distanceInKm: (map['distanceInKm'] as num).toDouble(),
      durationInSeconds: map['durationInSeconds'] ?? 0,
      pace: map['pace'] ?? '0:00',
      steps: map['steps'] ?? 0,
      calories: (map['calories'] as num).toDouble(),
      routePoints: points,
    );
  }

  String toJson() => json.encode(toMap());

  factory RunModel.fromJson(String source) => RunModel.fromMap(json.decode(source));
}