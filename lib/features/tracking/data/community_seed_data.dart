import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class ChallengeItem {
  final String id;
  final String title;
  final String description;
  final String badgeText;
  final double targetValue;
  final String unit; // 'km', 'single_km', 'runs', 'kcal'
  final int minLevel;
  final int xpReward;
  final int baseParticipants;
  final IconData icon;
  final Color accentColor;

  const ChallengeItem({
    required this.id,
    required this.title,
    required this.description,
    required this.badgeText,
    required this.targetValue,
    required this.unit,
    this.minLevel = 1,
    this.xpReward = 150,
    required this.baseParticipants,
    required this.icon,
    required this.accentColor,
  });
}

class ClubMember {
  final String name;
  final double weeklyKm;
  final int runsCount;
  final bool isCurrentUser;
  final String? avatarPath;

  const ClubMember({
    required this.name,
    required this.weeklyKm,
    required this.runsCount,
    this.isCurrentUser = false,
    this.avatarPath,
  });
}

class RunningClub {
  final String id;
  final String name;
  final String location;
  final String description;
  final String schedule;
  final int baseMembers;
  final IconData icon;
  final Color color;
  final List<ClubMember> simulatedMembers;

  const RunningClub({
    required this.id,
    required this.name,
    required this.location,
    required this.description,
    required this.schedule,
    required this.baseMembers,
    required this.icon,
    required this.color,
    required this.simulatedMembers,
  });
}

class CommunityEvent {
  final String id;
  final String title;
  final String dateStr;
  final String location;
  final String distanceTag;
  final String paceGroup;
  final String description;
  final int baseAttendees;

  const CommunityEvent({
    required this.id,
    required this.title,
    required this.dateStr,
    required this.location,
    required this.distanceTag,
    required this.paceGroup,
    required this.description,
    required this.baseAttendees,
  });
}

/// Data kurasi komunitas lokal (tantangan, klub, acara) yang dipisahkan dari UI GroupScreen.
class CommunitySeedData {
  static const List<ChallengeItem> challenges = [
    ChallengeItem(
      id: 'ch_starter_1k',
      title: 'First Stride 1K Starter',
      description: 'Tantangan pembuka untuk pelari baru: kumpulkan total jarak 1 km pertama.',
      badgeText: 'STARTER 1K',
      targetValue: 1.0,
      unit: 'km',
      minLevel: 1,
      xpReward: 100,
      baseParticipants: 3120,
      icon: Icons.flag_circle_outlined,
      accentColor: AppColors.accentGreen,
    ),
    ChallengeItem(
      id: 'ch_single_5k',
      title: '5K Finisher Challenge',
      description: 'Selesaikan minimal 5 km dalam satu kali sesi lari tanpa henti.',
      badgeText: '5K MILESTONE',
      targetValue: 5.0,
      unit: 'single_km',
      minLevel: 1,
      xpReward: 150,
      baseParticipants: 2180,
      icon: Icons.bolt,
      accentColor: AppColors.accentBlue,
    ),
    ChallengeItem(
      id: 'ch_consistency_5',
      title: '5x Active Runner Streak',
      description: 'Selesaikan minimal 5 sesi lari yang tercatat di riwayat aktivitas.',
      badgeText: 'CONSISTENCY',
      targetValue: 5.0,
      unit: 'runs',
      minLevel: 2,
      xpReward: 250,
      baseParticipants: 945,
      icon: Icons.local_fire_department,
      accentColor: AppColors.accentGreen,
    ),
    ChallengeItem(
      id: 'ch_monthly_25k',
      title: 'Adventure 25K Endurance',
      description: 'Kumpulkan total jarak lari 25 km dari seluruh sesi rekamanmu.',
      badgeText: 'ENDURANCE 25K',
      targetValue: 25.0,
      unit: 'km',
      minLevel: 3,
      xpReward: 400,
      baseParticipants: 1240,
      icon: Icons.military_tech,
      accentColor: AppColors.primaryOrange,
    ),
    ChallengeItem(
      id: 'ch_calorie_1500',
      title: '1,500 kcal Burn Target',
      description: 'Bakar total 1.500 kalori dari aktivitas lari maupun trail.',
      badgeText: 'CALORIE BURN',
      targetValue: 1500.0,
      unit: 'kcal',
      minLevel: 4,
      xpReward: 500,
      baseParticipants: 780,
      icon: Icons.whatshot,
      accentColor: Colors.amber,
    ),
  ];

  static const List<RunningClub> clubs = [
    RunningClub(
      id: 'club_sumedang',
      name: 'Runner Club Sumedang',
      location: 'Jatinangor & Sumedang',
      description: 'Komunitas lari terbuka untuk mahasiswa dan warga kawasan Jatinangor–Sumedang.',
      schedule: 'Rabu 19:30 & Minggu 06:00',
      baseMembers: 117,
      icon: Icons.directions_run,
      color: AppColors.primaryOrange,
      simulatedMembers: [
        ClubMember(name: 'Raka Pratama', weeklyKm: 24.5, runsCount: 5),
        ClubMember(name: 'Nadia Putri', weeklyKm: 18.2, runsCount: 4),
        ClubMember(name: 'Dimas Saputra', weeklyKm: 12.0, runsCount: 3),
        ClubMember(name: 'Fajar Nugroho', weeklyKm: 6.4, runsCount: 2),
        ClubMember(name: 'Salsa Maharani', weeklyKm: 3.1, runsCount: 1),
      ],
    ),
    RunningClub(
      id: 'club_manglayang',
      name: 'Bandung Timur Trail Runners',
      location: 'Cileunyi & Kaki Manglayang',
      description: 'Fokus latihan elevasi, lari lintas alam, dan persiapan trail run Jawa Barat.',
      schedule: 'Sabtu 06:15 • Basecamp Manglayang',
      baseMembers: 430,
      icon: Icons.terrain,
      color: AppColors.accentGreen,
      simulatedMembers: [
        ClubMember(name: 'Bagas Wicaksono', weeklyKm: 34.8, runsCount: 6),
        ClubMember(name: 'Tari Anggraini', weeklyKm: 21.0, runsCount: 4),
        ClubMember(name: 'Reza Kurniawan', weeklyKm: 14.5, runsCount: 3),
        ClubMember(name: 'Kevin Wijaya', weeklyKm: 7.5, runsCount: 2),
      ],
    ),
    RunningClub(
      id: 'club_campus_pacer',
      name: 'Unpad Morning Pacer',
      location: 'Kawasan Kampus Jatinangor',
      description: 'Grup lari pagi santai sebelum kuliah dengan berbagai kelompok pace (5:30 – 7:30/km).',
      schedule: 'Selasa & Jumat • 05:45 WIB',
      baseMembers: 264,
      icon: Icons.speed,
      color: AppColors.accentBlue,
      simulatedMembers: [
        ClubMember(name: 'Alvin Hendrawan', weeklyKm: 19.6, runsCount: 5),
        ClubMember(name: 'Citra Lestari', weeklyKm: 15.1, runsCount: 4),
        ClubMember(name: 'Gilang Ramadhan', weeklyKm: 9.8, runsCount: 2),
        ClubMember(name: 'Hana Pertiwi', weeklyKm: 4.2, runsCount: 1),
      ],
    ),
  ];

  static const List<CommunityEvent> events = [
    CommunityEvent(
      id: 'ev_jatinangor_night',
      title: 'Jatinangor Loop Night Run 5K',
      dateStr: 'Sabtu, 21 Nov 2026 • 19:30 WIB',
      location: 'Gerbang Utama Unpad, Jatinangor',
      distanceTag: '5.0 KM',
      paceGroup: 'All Pace (6:00 - 7:30 /km)',
      description: 'Lari malam santai bersama komunitas lokal mengelilingi rute utama Jatinangor. Gratis hidrasi di titik finish.',
      baseAttendees: 84,
    ),
    CommunityEvent(
      id: 'ev_siliwangi_sunday',
      title: 'Siliwangi Sunday Morning 10K',
      dateStr: 'Minggu, 29 Nov 2026 • 06:00 WIB',
      location: 'Stadion Siliwangi, Bandung',
      distanceTag: '10.0 KM',
      paceGroup: 'Tempo & Endurance',
      description: 'Latihan long run akhir pekan bersama pacer berpengalaman untuk persiapan lomba 10K.',
      baseAttendees: 142,
    ),
    CommunityEvent(
      id: 'ev_manglayang_funtrail',
      title: 'Manglayang Sunrise Fun Trail',
      dateStr: 'Minggu, 6 Des 2026 • 06:15 WIB',
      location: 'Pos Pendakian Barubereum, Cileunyi',
      distanceTag: '6.5 KM',
      paceGroup: 'Trail / Elevasi +240m',
      description: 'Eksplorasi jalur tanah dan kebun pinus kaki Gunung Manglayang dengan pemandangan matahari terbit.',
      baseAttendees: 59,
    ),
  ];
}
