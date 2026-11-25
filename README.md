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

**Adventure Runner** is an endurance and fitness tracking application designed for runners who prioritize data privacy and offline-first reliability. It leverages device sensors (GPS and pedometer) to record workouts, calculate accurate paces and per-kilometer splits, estimate calorie burn based on user biometrics, cache visited OpenStreetMap tiles locally on disk for offline map viewing, and persist all activity history locally using `SharedPreferences`.

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
*   **Local Storage:** Atomic file-based JSON repository (`path_provider` + per-run GPS track files + GPX 1.1 export) & `shared_preferences`
*   **Media Handling:** `image_picker`
*   **State Management:** Lightweight reactive `ValueNotifier` architecture across tabs & services.

---

## 📂 Project Structure

```text
lib/
├── main.dart
├── core/
│   ├── constants/
│   │   └── app_colors.dart                  # Custom dark athletic color palette
│   ├── services/
│   │   ├── location_service.dart            # Background GPS & foreground config (Android/iOS)
│   │   ├── offline_tile_provider.dart       # Offline-first disk caching for OSM map tiles
│   │   ├── pedometer_service.dart           # Raw step counter stream handler
│   │   ├── profile_storage_service.dart     # User profile & biometrics repository
│   │   └── run_storage_service.dart         # Atomic file-based run DB, migration & GPX export
│   ├── utils/
│   │   ├── formatters.dart                  # Shared clock & compact duration formatters
│   │   └── gpx_exporter.dart                # Standard GPX 1.1 XML serializer
│   └── widgets/
│       ├── dark_osm_tile_layer.dart         # Reusable dark-mode OSM tile layer & attribution
│       └── mini_route_painter.dart          # Lightweight mini GPS polyline canvas painter
└── features/
    └── tracking/
        ├── data/
        │   └── community_seed_data.dart     # Curated local challenges, clubs & events data
        ├── domain/
        │   ├── run_model.dart               # Core workout & GPS trackpoint data model
        │   └── runner_stats.dart            # Unified XP, rank, weekly distance & split telemetry
        └── presentation/
            ├── main_navigation_screen.dart  # 5-tab navigation shell & guided route switcher
            ├── home_screen.dart             # Dashboard, weekly goal & activity feed
            ├── record_run_screen.dart       # Live tracking, auto-pause & guided route overlay
            ├── post_run_screen.dart         # Post-run caption, feeling, photo & save flow
            ├── map_explore_screen.dart      # Route explorer & filter view
            ├── group_screen.dart            # Offline clubs, weekly leaderboards & events
            ├── profile_screen.dart          # User stats, level, badges & offline cache settings
            └── run_detail_screen.dart       # Telemetry, actual splits, edit activity & GPX export
```