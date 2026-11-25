import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/login_screen.dart';
import 'features/tracking/presentation/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://wcfbibmafwtrgozvucio.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndjZmJpYm1hZnd0cmdvenZ1Y2lvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU0MzIxMjgsImV4cCI6MjExMTAwODEyOH0.6b073RBsyUhMEdA7Do6GPo0DANtMq7Zb31dLZAUCn9s',
  );

  runApp(const AdventureRunnerApp());
}

class AdventureRunnerApp extends StatelessWidget {
  const AdventureRunnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      title: 'Adventure Runner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        primaryColor: const Color(0xFFFF5722),
      ),
      home: session != null
          ? const MainNavigationScreen()
          : const LoginScreen(),
    );
  }
}