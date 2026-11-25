import 'dart:io';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/friends_service.dart';

/// Tab ke-4 di halaman Grup: Cari Pelari, Tambah Teman, Permintaan Pertemanan,
/// dan Papan Peringkat Mingguan khusus Teman.
class FriendsTabView extends StatefulWidget {
  final String currentUserName;
  final String currentUserCity;
  final String? currentUserAvatarPath;
  final int currentUserLevel;
  final double currentUserWeeklyKm;
  final int currentUserWeeklyRuns;
  final Future<bool> Function() onRequireLogin;

  const FriendsTabView({
    super.key,
    required this.currentUserName,
    required this.currentUserCity,
    required this.currentUserAvatarPath,
    required this.currentUserLevel,
    required this.currentUserWeeklyKm,
    required this.currentUserWeeklyRuns,
    required this.onRequireLogin,
  });

  @override
  State<FriendsTabView> createState() => _FriendsTabViewState();
}

class _FriendsTabViewState extends State<FriendsTabView> {
  final FriendsService _friendsService = FriendsService();
  final TextEditingController _searchCtrl = TextEditingController();

  FriendsSnapshot _snapshot = const FriendsSnapshot(isAvailable: false);
  List<RunnerProfileSummary> _discoverRunners = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String? _busyUserId;

  @override
  void initState() {
    super.initState();
    _loadFriendsAndDiscover();
    AuthService.authStateNotifier.addListener(_loadFriendsAndDiscover);
  }

  @override
  void dispose() {
    AuthService.authStateNotifier.removeListener(_loadFriendsAndDiscover);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFriendsAndDiscover() async {
    if (!AuthService.isLoggedIn) {
      if (mounted) {
        setState(() {
          _snapshot = const FriendsSnapshot(
            isAvailable: false,
            statusMessage: 'Masuk akun untuk mencari pelari, tambah teman, dan melihat leaderboard teman.',
          );
          _discoverRunners = [];
          _isLoading = false;
        });
      }
      return;
    }

    final snapshot = await _friendsService.fetchFriendsSnapshot();
    final runners = snapshot.isAvailable
        ? await _friendsService.searchRunners(_searchCtrl.text)
        : <RunnerProfileSummary>[];

    if (mounted) {
      setState(() {
        _snapshot = snapshot;
        _discoverRunners = runners;
        _isLoading = false;
      });
    }
  }

  Future<void> _onSearchChanged(String query) async {
    if (!AuthService.isLoggedIn || !_snapshot.isAvailable) return;
    setState(() => _isSearching = true);
    try {
      final list = await _friendsService.searchRunners(query);
      if (mounted) {
        setState(() {
          _discoverRunners = list;
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _sendRequest(RunnerProfileSummary runner) async {
    if (_busyUserId != null) return;
    setState(() => _busyUserId = runner.userId);
    try {
      await _friendsService.sendFriendRequest(runner.userId);
      await _loadFriendsAndDiscover();
      _showSnack('Permintaan pertemanan dikirim ke ${runner.displayName}!');
    } catch (e) {
      _showSnack('Gagal mengirim permintaan: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  Future<void> _acceptRequest(FriendItem item) async {
    if (_busyUserId != null) return;
    setState(() => _busyUserId = item.profile.userId);
    try {
      await _friendsService.acceptFriendRequest(item.friendshipId);
      await _loadFriendsAndDiscover();
      _showSnack('Sekarang Anda berteman dengan ${item.profile.displayName}!');
    } catch (e) {
      _showSnack('Gagal menerima permintaan: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  Future<void> _removeRelation(FriendItem item, {required String successMessage}) async {
    if (_busyUserId != null) return;
    setState(() => _busyUserId = item.profile.userId);
    try {
      await _friendsService.removeFriendship(item.friendshipId);
      await _loadFriendsAndDiscover();
      _showSnack(successMessage);
    } catch (e) {
      _showSnack('Gagal memperbarui pertemanan: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  Future<void> _confirmUnfriend(FriendItem item) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.cardDark,
            title: const Text('Hapus Teman?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Text(
              'Hapus ${item.profile.displayName} dari daftar teman Anda?',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Hapus', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _removeRelation(item, successMessage: '${item.profile.displayName} dihapus dari daftar teman.');
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.redAccent : AppColors.cardElevated),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_add_alt_1_outlined, size: 52, color: AppColors.primaryOrange),
              const SizedBox(height: 14),
              const Text(
                'Berteman dengan Sesama Pelari',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
              ),
              const SizedBox(height: 8),
              const Text(
                'Masuk akun untuk mencari pelari lain, saling Add Friend, dan bersaing di papan peringkat mingguan bersama teman!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final ok = await widget.onRequireLogin();
                  if (ok) await _loadFriendsAndDiscover();
                },
                icon: const Icon(Icons.login_rounded, color: Colors.white, size: 18),
                label: const Text('Masuk / Daftar Sekarang', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
    }

    if (!_snapshot.isAvailable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _snapshot.needsSchemaSetup ? Icons.storage_outlined : Icons.wifi_off_rounded,
                size: 46,
                color: Colors.amber,
              ),
              const SizedBox(height: 12),
              Text(
                _snapshot.statusMessage ?? 'Fitur teman belum tersedia saat ini.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.amber, fontSize: 13),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.primaryOrange)),
                onPressed: _loadFriendsAndDiscover,
                icon: const Icon(Icons.refresh, color: AppColors.primaryOrange, size: 18),
                label: const Text('Coba Lagi', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final leaderboard = <RunnerProfileSummary>[
      RunnerProfileSummary(
        userId: AuthService.userId ?? 'me',
        displayName: '${widget.currentUserName} (Anda)',
        city: widget.currentUserCity,
        bio: '',
        runnerLevel: widget.currentUserLevel,
        totalDistanceKm: 0,
        weeklyDistanceKm: widget.currentUserWeeklyKm,
        weeklyRunsCount: widget.currentUserWeeklyRuns,
        isCurrentUser: true,
      ),
      ..._snapshot.acceptedFriends.map((f) => f.profile),
    ]..sort((a, b) => b.weeklyDistanceKm.compareTo(a.weeklyDistanceKm));

    return RefreshIndicator(
      onRefresh: _loadFriendsAndDiscover,
      color: AppColors.primaryOrange,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. SEARCH BAR CARI PELARI
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Cari nama pelari untuk Add Friend...',
                hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                border: InputBorder.none,
                icon: const Icon(Icons.search, color: AppColors.primaryOrange),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryOrange)),
                      )
                    : (_searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null),
              ),
            ),
          ),

          // 2. PERMINTAAN PERTEMANAN MASUK
          if (_snapshot.incomingRequests.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                const Text(
                  'Permintaan Pertemanan',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_snapshot.incomingRequests.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._snapshot.incomingRequests.map((item) => _buildIncomingRequestCard(item)),
          ],

          // 3. PAPAN PERINGKAT MINGGUAN TEMAN
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Papan Peringkat Teman (Minggu Ini)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(
                '${_snapshot.acceptedFriends.length} Teman',
                style: const TextStyle(color: AppColors.primaryOrange, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_snapshot.acceptedFriends.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: const Text(
                'Belum ada teman yang terhubung. Cari pelari di bawah atau tambahkan teman langsung dari Leaderboard Klub!',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
            )
          else
            ...List.generate(leaderboard.length, (idx) {
              final runner = leaderboard[idx];
              final friendItem = _snapshot.relationByUserId[runner.userId];
              return _buildFriendLeaderboardRow(
                rank: idx + 1,
                runner: runner,
                friendItem: friendItem,
              );
            }),

          // 4. TEMUKAN / HASIL PENCARIAN PELARI
          const SizedBox(height: 20),
          Text(
            _searchCtrl.text.trim().isEmpty ? 'Temukan Pelari Lainnya' : 'Hasil Pencarian Pelari',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 10),
          if (_discoverRunners.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                _searchCtrl.text.trim().isEmpty
                    ? 'Belum ada pelari lain yang terdaftar di server.'
                    : 'Tidak ditemukan pelari dengan nama "${_searchCtrl.text.trim()}".',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
            )
          else
            ..._discoverRunners.map((runner) => _buildDiscoverRunnerCard(runner)),
        ],
      ),
    );
  }

  Widget _buildIncomingRequestCard(FriendItem item) {
    final isBusy = _busyUserId == item.profile.userId;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: AppColors.cardElevated,
            child: Text(
              item.profile.displayName[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.profile.displayName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildLevelPill(item.profile.runnerLevel),
                  ],
                ),
                Text(item.profile.city, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Tolak',
            onPressed: isBusy ? null : () => _removeRelation(item, successMessage: 'Permintaan pertemanan ditolak.'),
            icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentGreen,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: isBusy ? null : () => _acceptRequest(item),
            child: const Text('Terima', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendLeaderboardRow({
    required int rank,
    required RunnerProfileSummary runner,
    FriendItem? friendItem,
  }) {
    final hasAvatar = runner.isCurrentUser && widget.currentUserAvatarPath != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: runner.isCurrentUser ? AppColors.primaryOrange.withValues(alpha: 0.16) : AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: runner.isCurrentUser ? AppColors.primaryOrange : Colors.white10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '#$rank',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: rank == 1
                    ? Colors.amber
                    : rank == 2
                        ? Colors.grey.shade300
                        : rank == 3
                            ? Colors.orange.shade300
                            : AppColors.textSecondary,
              ),
            ),
          ),
          CircleAvatar(
            radius: 17,
            backgroundColor: AppColors.cardElevated,
            backgroundImage: hasAvatar ? FileImage(File(widget.currentUserAvatarPath!)) : null,
            child: !hasAvatar
                ? Text(
                    runner.displayName.trim().isNotEmpty ? runner.displayName.trim()[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        runner.displayName,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: runner.isCurrentUser ? FontWeight.bold : FontWeight.w600,
                          fontSize: 13.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildLevelPill(runner.runnerLevel),
                  ],
                ),
                Text(
                  '${runner.weeklyRunsCount} sesi minggu ini • ${runner.city}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            '${runner.weeklyDistanceKm.toStringAsFixed(1)} km',
            style: TextStyle(
              color: runner.isCurrentUser ? AppColors.primaryOrange : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          if (!runner.isCurrentUser && friendItem != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Hapus Teman',
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
              icon: const Icon(Icons.person_remove_outlined, color: Colors.white38, size: 17),
              onPressed: () => _confirmUnfriend(friendItem),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiscoverRunnerCard(RunnerProfileSummary runner) {
    final relation = _snapshot.relationByUserId[runner.userId];
    final status = relation?.status ?? FriendRelationStatus.none;
    final isBusy = _busyUserId == runner.userId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: AppColors.cardElevated,
            child: Text(
              runner.displayName.trim().isNotEmpty ? runner.displayName.trim()[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        runner.displayName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildLevelPill(runner.runnerLevel),
                  ],
                ),
                Text(
                  '${runner.city} • Total ${runner.totalDistanceKm.toStringAsFixed(1)} km',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (status == FriendRelationStatus.accepted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accentGreen.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Teman ✓', style: TextStyle(color: AppColors.accentGreen, fontSize: 11.5, fontWeight: FontWeight.bold)),
            )
          else if (status == FriendRelationStatus.pendingOutgoing && relation != null)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: isBusy ? null : () => _removeRelation(relation, successMessage: 'Permintaan pertemanan dibatalkan.'),
              child: const Text('Menunggu', style: TextStyle(color: Colors.white70, fontSize: 11.5)),
            )
          else if (status == FriendRelationStatus.pendingIncoming && relation != null)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentGreen,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: isBusy ? null : () => _acceptRequest(relation),
              child: const Text('Terima', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11.5)),
            )
          else
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: isBusy ? null : () => _sendRequest(runner),
              icon: isBusy
                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.person_add_alt_1, size: 14, color: Colors.white),
              label: const Text('Tambah', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
            ),
        ],
      ),
    );
  }

  Widget _buildLevelPill(int level) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'Lv.$level',
        style: const TextStyle(color: Colors.amber, fontSize: 9.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}
