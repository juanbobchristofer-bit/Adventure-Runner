import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/friends_service.dart';
import '../domain/runner_stats.dart';
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
  void initState() {
    super.initState();
    GuidedRouteController.tabNavigationRequest.addListener(_handleTabRequest);
    AuthService.authStateNotifier.addListener(_refreshNotificationBadges);
    _refreshNotificationBadges();
  }

  @override
  void dispose() {
    GuidedRouteController.tabNavigationRequest.removeListener(_handleTabRequest);
    AuthService.authStateNotifier.removeListener(_refreshNotificationBadges);
    super.dispose();
  }

  void _refreshNotificationBadges() {
    FriendsService.refreshPendingBadge();
  }

  void _handleTabRequest() {
    final targetTab = GuidedRouteController.tabNavigationRequest.value;
    if (targetTab != null && targetTab >= 0 && targetTab < _screens.length) {
      setState(() => _currentIndex = targetTab);
      GuidedRouteController.tabNavigationRequest.value = null;
    }
  }

  Widget _buildGroupIconWithBadge(int count) {
    if (count <= 0) {
      return const Icon(Icons.people_outline);
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.people_outline),
        Positioned(
          right: -7,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardDark, width: 1.2),
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text(
              count > 9 ? '9+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: FriendsService.pendingRequestsCount,
        builder: (context, pendingCount, _) => BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() => _currentIndex = index);
            if (index == 3) _refreshNotificationBadges();
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.cardDark,
          selectedItemColor: AppColors.primaryOrange,
          unselectedItemColor: Colors.grey,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: [
            const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            const BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: 'Peta'),
            const BottomNavigationBarItem(icon: Icon(Icons.radio_button_checked, size: 28), label: 'Rekam'),
            BottomNavigationBarItem(icon: _buildGroupIconWithBadge(pendingCount), label: 'Grup'),
            const BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Anda'),
          ],
        ),
      ),
    );
  }
}