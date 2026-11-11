import 'package:flutter/material.dart';
import 'core/constants/app_colors.dart';
import 'features/tracking/presentation/main_navigation_screen.dart';

void main() {
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
      home: const MainNavigationScreen(),
    );
  }
}