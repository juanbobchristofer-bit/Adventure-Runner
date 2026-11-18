import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfileData {
  final String name;
  final String bio;
  final String city;
  final double weightKg;
  final double weeklyGoalKm;
  final String? avatarPath;

  const UserProfileData({
    required this.name,
    required this.bio,
    required this.city,
    required this.weightKg,
    required this.weeklyGoalKm,
    this.avatarPath,
  });
}

class ProfileStorageService {
  static const String _keyName = 'user_profile_name';
  static const String _keyBio = 'user_profile_bio';
  static const String _keyCity = 'user_profile_city';
  static const String _keyWeight = 'user_profile_weight';
  static const String _keyGoal = 'user_weekly_goal_km';
  static const String _keyAvatarPath = 'user_profile_avatar_path';

  /// Notifier global agar perubahan di halaman Profil langsung memperbarui HomeScreen
  static final ValueNotifier<int> profileUpdateNotifier = ValueNotifier<int>(0);

  Future<UserProfileData> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final savedAvatar = prefs.getString(_keyAvatarPath);
    final validAvatar = (savedAvatar != null && File(savedAvatar).existsSync()) ? savedAvatar : null;

    return UserProfileData(
      name: prefs.getString(_keyName) ?? 'Pelari Adventure',
      bio: prefs.getString(_keyBio) ?? 'Chasing new personal records every mile.',
      city: prefs.getString(_keyCity) ?? 'Jatinangor, Indonesia',
      weightKg: prefs.getDouble(_keyWeight) ?? 65.0,
      weeklyGoalKm: prefs.getDouble(_keyGoal) ?? 15.0,
      avatarPath: validAvatar,
    );
  }

  Future<void> saveProfile({
    required String name,
    required String bio,
    required String city,
    required double weightKg,
    required double weeklyGoalKm,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, name.trim());
    await prefs.setString(_keyBio, bio.trim());
    await prefs.setString(_keyCity, city.trim());
    await prefs.setDouble(_keyWeight, weightKg);
    await prefs.setDouble(_keyGoal, weeklyGoalKm);
    profileUpdateNotifier.value++;
  }

  Future<void> saveWeeklyGoal(double goalKm) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyGoal, goalKm);
    profileUpdateNotifier.value++;
  }

  /// Menyalin foto pilihan user ke direktori permanen aplikasi agar tidak hilang saat cache HP dibersihkan
  Future<String> saveAvatarImage(File sourceFile) async {
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedFile = await sourceFile.copy('${appDir.path}/$fileName');

    final prefs = await SharedPreferences.getInstance();
    final oldPath = prefs.getString(_keyAvatarPath);
    if (oldPath != null && File(oldPath).existsSync()) {
      try {
        await File(oldPath).delete();
      } catch (_) {}
    }

    await prefs.setString(_keyAvatarPath, savedFile.path);
    profileUpdateNotifier.value++;
    return savedFile.path;
  }

  Future<void> removeAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final oldPath = prefs.getString(_keyAvatarPath);
    if (oldPath != null && File(oldPath).existsSync()) {
      try {
        await File(oldPath).delete();
      } catch (_) {}
    }
    await prefs.remove(_keyAvatarPath);
    profileUpdateNotifier.value++;
  }
}