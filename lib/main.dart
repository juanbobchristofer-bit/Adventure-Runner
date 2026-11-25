import 'package:flutter/material.dart';
import 'core/constants/app_colors.dart';
import 'core/services/auth_service.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/tracking/presentation/main_navigation_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.initialize();
  runApp(const AdventureRunnerApp());
}

class AdventureRunnerApp extends StatelessWidget {
  const AdventureRunnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Adventure Runner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.backgroundDark,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primaryOrange,
          surface: AppColors.cardDark,
        ),
        useMaterial3: true,
      ),
      home: const _FlexibleEntryGate(),
    );
  }
}

/// Gerbang masuk fleksibel: menampilkan halaman Login/Daftar pada kunjungan pertama
/// (dengan tombol lewati ke Mode Offline), lalu langsung membuka aplikasi utama setelahnya.
class _FlexibleEntryGate extends StatefulWidget {
  const _FlexibleEntryGate();

  @override
  State<_FlexibleEntryGate> createState() => _FlexibleEntryGateState();
}

class _FlexibleEntryGateState extends State<_FlexibleEntryGate> {
  bool _checking = true;
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    _checkEntryStatus();
  }

  Future<void> _checkEntryStatus() async {
    final entered = await AuthService.hasEnteredApp();
    if (mounted) {
      setState(() {
        _entered = entered;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryOrange),
        ),
      );
    }

    if (!_entered) {
      return LoginScreen(
        isInitialGate: true,
        onAuthComplete: () {
          if (mounted) setState(() => _entered = true);
        },
      );
    }

    return const MainNavigationScreen();
  }
}
