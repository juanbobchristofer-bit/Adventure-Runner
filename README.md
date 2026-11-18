# 🏃‍♂️ Adventure Runner

<div align="center">

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%230175C2.svg?style=for-the-badge&logo=Dart&logoColor=white)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-orange?style=for-the-badge)](https://flutter.dev)

A modern, gamified, offline-first running tracking mobile application inspired by Strava's sleek aesthetic. Built with Flutter and OpenStreetMap.

</div>

---

## 📱 About The Project

**Adventure Runner** is an endurance and fitness tracking application designed for runners who prefer complete data privacy and 100% offline functionality. It leverages device sensors (GPS and pedometer) to record workouts, calculate accurate paces, estimate calorie burn based on user biometrics, and sync everything locally using `SharedPreferences`.

Featuring a dark-themed athletic UI, gamification elements (XP leveling, achievements, personal records), and simulated offline social clubs, Adventure Runner brings the full community workout experience directly to your device without requiring cloud servers.

---

## ✨ Key Features

*   **📍 Real-Time GPS Tracking & Mapping:** Interactive dark-mode map powered by `flutter_map` and OpenStreetMap, complete with polyline rendering, start/finish markers, and custom auto-fit bounds.
*   **🔋 Background GPS & Smart Auto-Pause:** Uses Android Foreground Services and wake-locks to ensure uninterrupted tracking even when the phone is locked in your pocket. Features smart auto-pause that pauses telemetry when stationary.
*   **🏃‍♂️ Strava-Like Activity Posting:** Post your runs with custom titles, personal notes/captions, mood/vibe tags (`feeling`), and photo documentation captured from your gallery or camera.
*   **👟 Step Counting & Biometric Calories:** Integrates hardware pedometer streams and user weight metrics for precise calorie expenditure and cadence calculations.
*   **📊 Post-Run Telemetry & Analysis:** Detailed split-per-kilometer breakdown, training intensity zones (Recovery, Aerobic, Tempo, Threshold), average speed, and one-tap summary copying for WhatsApp/Instagram.
*   **🏆 Gamification & Profile System:** XP and runner leveling, 8 unlockable milestone badges, personal best records (longest run & duration), and editable user profiles.
*   **👥 Offline Clubs & Challenges:** Simulated local running groups with dynamic leaderboards that sync with your actual running history, plus monthly endurance challenges and event RSVPs.

---

## 🛠️ Tech Stack & Architecture

*   **Framework:** Flutter (SDK `>=3.0.0 <4.0.0`)
*   **Language:** Dart
*   **Geospatial & Mapping:** `flutter_map`, `latlong2`, `geolocator`
*   **Sensors:** `pedometer`, `permission_handler`
*   **Local Storage:** `shared_preferences`, `path_provider`
*   **Media Handling:** `image_picker`
*   **State Management:** Stateful Architecture with Service-Locator patterns and reactive `ValueNotifier` hooks.

---

## 📂 Project Structure

```text
lib/
├── core/
│   ├── constants/
│   │   └── app_colors.dart          # Custom dark athletic color palette
│   └── services/
│       ├── location_service.dart    # Background GPS & foreground config
│       ├── pedometer_service.dart   # Step counter stream handler
│       ├── profile_storage.dart     # User profile & biometrics repository
│       └── run_storage_service.dart # JSON serialization & local run persistence
└── features/
    └── tracking/
        ├── domain/
        │   └── run_model.dart       # Core data model for workouts
        └── presentation/
            ├── home_screen.dart         # Dashboard, stats & activity feed
            ├── record_run_screen.dart   # Live tracking, countdown & post screen
            ├── map_screen.dart          # Route explorer & filter view
            ├── group_screen.dart        # Offline clubs, leaderboards & events
            ├── profile_screen.dart      # User stats, level, badges & settings
            └── run_detail_screen.dart   # Deep telemetry, splits & share summary