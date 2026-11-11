import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import 'home_screen.dart';
import 'map_explore_screen.dart';
import 'record_run_screen.dart';
import 'group_screen.dart';
import 'profile_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 2; // Default tab Rekam

  final List<Widget> _screens = const [
    HomeScreen(),
    MapExploreScreen(), // Tab Peta Jelajah
    RecordRunScreen(),
    GroupScreen(),     // Tab Komunitas & Grup
    ProfileScreen(),   // Tab Profil / Anda
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.cardDark,
        selectedItemColor: AppColors.primaryOrange,
        unselectedItemColor: Colors.grey,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: 'Peta'),
          BottomNavigationBarItem(icon: Icon(Icons.radio_button_checked, size: 28), label: 'Rekam'),
          BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: 'Grup'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Anda'),
        ],
      ),
    );
  }
}