import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/tracking/domain/runner_stats.dart';
import '../config/supabase_config.dart';
import 'profile_storage_service.dart';
import 'run_storage_service.dart';

class AuthActionResult {
  final bool success;
  final bool requiresEmailConfirmation;
  final String message;

  const AuthActionResult({
    required this.success,
    this.requiresEmailConfirmation = false,
    required this.message,
  });
}

/// Mengelola autentikasi fleksibel (Email/Password + Mode Offline/Tamu) dan sinkronisasi
/// otomatis statistik pelari ke tabel `profiles` Supabase.
class AuthService {
  static const String _prefGuestModeChosen = 'auth_guest_mode_chosen';

  static final ValueNotifier<int> authStateNotifier = ValueNotifier<int>(0);
  static bool _isInitialized = false;
  static StreamSubscription<AuthState>? _authSub;
  static bool _listenersBound = false;

  static SupabaseClient? get client => _isInitialized ? Supabase.instance.client : null;
  static User? get currentUser => client?.auth.currentUser;
  static bool get isLoggedIn => currentUser != null;
  static String? get userId => currentUser?.id;
  static String? get userEmail => currentUser?.email;

  /// Menginisialisasi Supabase secara aman (tidak crash bila perangkat offline atau di lingkungan test).
  static Future<void> initialize() async {
    if (_isInitialized || !SupabaseConfig.isConfigured) return;

    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
      _isInitialized = true;

      _authSub?.cancel();
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        authStateNotifier.value++;
        if (data.event == AuthChangeEvent.signedIn) {
          unawaited(syncLocalStatsToCloud());
        }
      });

      if (!_listenersBound) {
        _listenersBound = true;
        RunStorageService.runUpdateNotifier.addListener(_onLocalDataChanged);
        ProfileStorageService.profileUpdateNotifier.addListener(_onLocalDataChanged);
      }

      if (isLoggedIn) {
        unawaited(syncLocalStatsToCloud());
      }
    } catch (e) {
      debugPrint('Supabase initialization dilewati (mode offline): $e');
    }
  }

  static void _onLocalDataChanged() {
    if (isLoggedIn) {
      unawaited(syncLocalStatsToCloud());
    }
  }

  /// Mengecek apakah pengguna sudah login ATAU sudah pernah memilih Mode Tamu (Offline)
  static Future<bool> hasEnteredApp() async {
    if (isLoggedIn) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefGuestModeChosen) ?? false;
  }

  static Future<void> continueAsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefGuestModeChosen, true);
    authStateNotifier.value++;
  }

  static Future<AuthActionResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final supabase = client;
    if (supabase == null) {
      return const AuthActionResult(
        success: false,
        message: 'Layanan online belum siap. Periksa koneksi internet Anda.',
      );
    }

    try {
      await supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      await _hydrateProfileFromCloudIfDefault();
      await syncLocalStatsToCloud();
      authStateNotifier.value++;
      return const AuthActionResult(
        success: true,
        message: 'Berhasil masuk! Statistik Anda tersinkron dengan komunitas.',
      );
    } on AuthException catch (e) {
      return AuthActionResult(success: false, message: _translateAuthError(e.message));
    } catch (_) {
      return const AuthActionResult(
        success: false,
        message: 'Gagal terhubung ke server. Pastikan koneksi internet aktif.',
      );
    }
  }

  static Future<AuthActionResult> signUpWithEmail({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final supabase = client;
    if (supabase == null) {
      return const AuthActionResult(
        success: false,
        message: 'Layanan online belum siap. Periksa koneksi internet Anda.',
      );
    }

    try {
      final cleanName = displayName.trim();
      final response = await supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': cleanName},
      );

      // Perbarui nama profil lokal agar selaras dengan akun baru
      final profileService = ProfileStorageService();
      final localProfile = await profileService.getProfile();
      if (cleanName.isNotEmpty) {
        await profileService.saveProfile(
          name: cleanName,
          bio: localProfile.bio,
          city: localProfile.city,
          weightKg: localProfile.weightKg,
          weeklyGoalKm: localProfile.weeklyGoalKm,
        );
      }

      if (response.session != null) {
        await syncLocalStatsToCloud();
        authStateNotifier.value++;
        return const AuthActionResult(
          success: true,
          message: 'Akun berhasil dibuat! Selamat bergabung di komunitas Adventure Runner.',
        );
      }

      return const AuthActionResult(
        success: true,
        requiresEmailConfirmation: true,
        message: 'Pendaftaran berhasil! Cek kotak masuk/spam email Anda untuk konfirmasi, lalu silakan Masuk.',
      );
    } on AuthException catch (e) {
      return AuthActionResult(success: false, message: _translateAuthError(e.message));
    } catch (_) {
      return const AuthActionResult(
        success: false,
        message: 'Gagal mendaftar. Pastikan koneksi internet aktif.',
      );
    }
  }

  static Future<AuthActionResult> sendPasswordReset(String email) async {
    final supabase = client;
    if (supabase == null) {
      return const AuthActionResult(
        success: false,
        message: 'Layanan online belum siap. Periksa koneksi internet Anda.',
      );
    }

    try {
      await supabase.auth.resetPasswordForEmail(email.trim());
      return const AuthActionResult(
        success: true,
        message: 'Tautan reset password telah dikirim ke email Anda.',
      );
    } on AuthException catch (e) {
      return AuthActionResult(success: false, message: _translateAuthError(e.message));
    } catch (_) {
      return const AuthActionResult(
        success: false,
        message: 'Gagal mengirim email reset password.',
      );
    }
  }

  static Future<void> signOut() async {
    try {
      await client?.auth.signOut();
    } catch (_) {}
    authStateNotifier.value++;
  }

  /// Jika profil lokal masih bawaan, tarik nama/bio/kota dari cloud saat login di perangkat baru.
  static Future<void> _hydrateProfileFromCloudIfDefault() async {
    final supabase = client;
    final uid = userId;
    if (supabase == null || uid == null) return;

    try {
      final row = await supabase.from('profiles').select().eq('id', uid).maybeSingle();
      if (row == null) return;

      final profileService = ProfileStorageService();
      final local = await profileService.getProfile();
      final isLocalDefaultName = local.name == UserProfileData.defaultProfile.name;

      final cloudBonusXp = (row['bonus_xp'] as num?)?.toInt() ?? 0;
      await profileService.mergeBonusXpFromCloud(cloudBonusXp);

      if (isLocalDefaultName && row['display_name'] != null) {
        await profileService.saveProfile(
          name: row['display_name'].toString(),
          bio: row['bio']?.toString() ?? local.bio,
          city: row['city']?.toString() ?? local.city,
          weightKg: (row['weight_kg'] as num?)?.toDouble() ?? local.weightKg,
          weeklyGoalKm: (row['weekly_goal_km'] as num?)?.toDouble() ?? local.weeklyGoalKm,
        );
      }
    } catch (e) {
      debugPrint('Hydrate profil cloud dilewati: $e');
    }
  }

  /// Menyinkronkan profil dan statistik lari lokal ke tabel `profiles` Supabase untuk leaderboard live.
  static Future<bool> syncLocalStatsToCloud() async {
    final supabase = client;
    final uid = userId;
    if (supabase == null || uid == null) return false;

    try {
      final profile = await ProfileStorageService().getProfile();
      final runs = await RunStorageService().getSavedRuns();
      final weekStartIso = RunnerStats.startOfCurrentWeek().toIso8601String();
      final longestKm = runs.isEmpty ? 0.0 : runs.map((r) => r.distanceInKm).reduce(math.max);
      final totalXp = RunnerStats.totalXp(runs, bonusXp: profile.bonusXp);
      final runnerLevel = RunnerStats.runnerLevel(runs, bonusXp: profile.bonusXp);

      final basePayload = <String, dynamic>{
        'id': uid,
        'display_name': profile.name,
        'bio': profile.bio,
        'city': profile.city,
        'weight_kg': profile.weightKg,
        'weekly_goal_km': profile.weeklyGoalKm,
        'weekly_distance_km': RunnerStats.weeklyDistance(runs),
        'weekly_runs_count': RunnerStats.weeklyRunsCount(runs),
        'total_distance_km': RunnerStats.totalDistance(runs),
        'total_runs_count': runs.length,
        'total_calories': RunnerStats.totalCalories(runs),
        'longest_run_km': longestKm,
        'week_start_iso': weekStartIso,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      try {
        await supabase.from('profiles').upsert(
          {
            ...basePayload,
            'bonus_xp': profile.bonusXp,
            'total_xp': totalXp,
            'runner_level': runnerLevel,
          },
          onConflict: 'id',
        );
      } on PostgrestException {
        // Fallback aman jika migrasi kolom bonus_xp/runner_level belum dijalankan di Supabase
        await supabase.from('profiles').upsert(basePayload, onConflict: 'id');
      }
      return true;
    } catch (e) {
      debugPrint('Sync statistik ke cloud gagal (offline / tabel belum dibuat): $e');
      return false;
    }
  }

  static String _translateAuthError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return 'Email atau password tidak sesuai.';
    }
    if (lower.contains('user already registered')) {
      return 'Email ini sudah terdaftar. Silakan pindah ke tab Masuk.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Email belum dikonfirmasi. Cek inbox atau folder spam Anda.';
    }
    if (lower.contains('password should be at least')) {
      return 'Password minimal terdiri dari 6 karakter.';
    }
    if (lower.contains('invalid email') || lower.contains('unable to validate email')) {
      return 'Format alamat email tidak valid.';
    }
    if (lower.contains('rate limit')) {
      return 'Terlalu banyak percobaan. Tunggu beberapa saat lalu coba lagi.';
    }
    return raw;
  }
}
