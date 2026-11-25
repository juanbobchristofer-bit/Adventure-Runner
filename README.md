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
*   **🔋 Background GPS, Current Pace, 1 KM Split Cues & Crash Recovery:** Uses Android Foreground Services, smart auto-pause, rolling 15-second Current Pace alongside Average Pace, haptic/audio + banner milestone cues every 1 km, and atomic 15-second auto-save drafts (`RunDraftService`) so active runs survive crashes or battery drain.
*   **🏃‍♂️ Strava-Like Activity Posting:** Post your runs with custom titles, personal notes/captions, mood/vibe tags (`feeling`), and photo documentation captured from your gallery or camera.
*   **👟 Step Counting & Biometric Calories:** Integrates hardware pedometer streams and user weight metrics for precise calorie expenditure and cadence calculations.
*   **📊 Post-Run Telemetry & Interactive Charts:** Elevation & Speed area charts (`TelemetryChartCard`), detailed split-per-kilometer breakdown, training intensity zones (Recovery, Aerobic, Tempo, Threshold), average speed, and one-tap summary copying for WhatsApp/Instagram.
*   **🏆 Gamification & Profile System:** Unified XP & runner leveling (from runs + claimable challenge bonus XP), 8 unlockable milestone badges, personal best records, and editable user profiles.
*   **👥 Online Community, Friends Feed + Kudos, Level Gating & Live Chat (Supabase):** Flexible authentication (Email/Password + Offline Guest Mode), Strava-style Friends Activity Feed with Kudos (👏) & mini GPS route previews, unread friend-request notification badges, level-gated Challenges with claimable XP rewards, level-gated Running Clubs with Live Weekly Leaderboards & Realtime Club Chat, level/quota-gated Community Events with Live Event Discussion, and a full Friends system with automatic offline fallback.

---

## 🛠️ Tech Stack & Architecture

*   **Framework:** Flutter (SDK `>=3.0.0 <4.0.0`)
*   **Language:** Dart
*   **Backend & Realtime:** `supabase_flutter` (Auth, PostgreSQL, Row Level Security, Realtime Chat)
*   **Geospatial & Mapping:** `flutter_map`, `latlong2`, `geolocator` + custom offline OSM tile disk cache
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
│   ├── config/
│   │   └── supabase_config.dart             # Supabase URL & publishable key (--dart-define ready)
│   ├── constants/
│   │   └── app_colors.dart                  # Custom dark athletic color palette
│   ├── services/
│   │   ├── auth_service.dart                # Flexible Email Auth + Offline Guest Mode & cloud sync
│   │   ├── community_service.dart           # Online Challenges, Clubs, Events & Realtime Chat
│   │   ├── friends_service.dart             # Search runners, Add Friend & Friends Leaderboard
│   │   ├── location_service.dart            # Background GPS & foreground config (Android/iOS)
│   │   ├── offline_tile_provider.dart       # Offline-first disk caching for OSM map tiles
│   │   ├── pedometer_service.dart           # Raw step counter stream handler
│   │   ├── profile_storage_service.dart     # User profile, biometrics & bonus XP repository
│   │   ├── run_draft_service.dart           # Atomic auto-save checkpoint & crash recovery for active runs
│   │   ├── run_storage_service.dart         # Atomic file-based run DB, migration & GPX export
│   │   └── social_feed_service.dart         # Friends Activity Feed & Kudos (Supabase)
│   ├── utils/
│   │   ├── formatters.dart                  # Shared clock & compact duration formatters
│   │   └── gpx_exporter.dart                # Standard GPX 1.1 XML serializer
│   └── widgets/
│       ├── dark_osm_tile_layer.dart         # Reusable dark-mode OSM tile layer & attribution
│       ├── mini_route_painter.dart          # Lightweight mini GPS polyline canvas painter
│       ├── runner_profile_sheet.dart        # Mini athlete profile sheet (Level, XP, stats & badges)
│       └── telemetry_chart_card.dart        # Speed & Elevation interactive area chart
└── features/
    ├── auth/
    │   └── presentation/
    │       └── login_screen.dart            # Flexible Login / Register / Guest Mode screen
    └── tracking/
        ├── data/
        │   └── community_seed_data.dart     # Offline fallback community data
        ├── domain/
        │   ├── run_model.dart               # Core workout & GPS trackpoint data model
        │   └── runner_stats.dart            # Unified XP, rank, level gating & split telemetry
        └── presentation/
            ├── main_navigation_screen.dart  # 5-tab navigation shell & guided route switcher
            ├── home_screen.dart             # Dashboard, weekly goal & activity feed
            ├── record_run_screen.dart       # Live tracking, auto-pause & guided route overlay
            ├── post_run_screen.dart         # Post-run caption, feeling, photo & save flow
            ├── map_explore_screen.dart      # Route explorer & filter view
            ├── group_screen.dart            # 4-tab Community hub (Tantangan, Klub, Acara, Teman)
            ├── club_detail_screen.dart      # Live Weekly Leaderboard & Realtime Club Chat
            ├── event_detail_screen.dart     # Event Quota, Live Discussion & Attendees
            ├── friends_tab_view.dart        # Runner search, friend requests & Friends Leaderboard
            ├── profile_screen.dart          # User stats, level, badges, cloud account & cache settings
            └── run_detail_screen.dart       # Telemetry, actual splits, edit activity & GPX export
supabase/
├── schema.sql                               # Complete PostgreSQL schema, GRANTs & RLS policies
├── migration_p1_challenges.sql              # Level gating & XP reward claim migration
├── migration_p2_clubs.sql                   # Club min_level & Realtime club_messages migration
├── migration_p3_events.sql                  # Event min_level, quota & Realtime event_messages migration
├── migration_p4_friends.sql                 # Friendships table & RLS migration
└── migration_p5_social_feed.sql             # Friends Activity Feed & Kudos tables & RLS migration
```