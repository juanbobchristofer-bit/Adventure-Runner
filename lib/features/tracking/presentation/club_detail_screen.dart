import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/community_service.dart';
import '../../../core/services/friends_service.dart';
import '../../../core/widgets/runner_profile_sheet.dart';
import '../../auth/presentation/login_screen.dart';
import '../domain/runner_stats.dart';

/// Halaman Detail Klub Online dengan 2 sub-tab:
/// 1) Leaderboard Mingguan Live (dengan badge Level tiap anggota)
/// 2) Ruang Obrolan Klub (Live Chat Supabase Realtime khusus anggota klub)
class ClubDetailScreen extends StatefulWidget {
  final OnlineClub club;
  final int userLevel;
  final int userTotalXp;
  final String? userAvatarPath;

  const ClubDetailScreen({
    super.key,
    required this.club,
    required this.userLevel,
    required this.userTotalXp,
    this.userAvatarPath,
  });

  @override
  State<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends State<ClubDetailScreen> {
  final CommunityService _communityService = CommunityService();
  final FriendsService _friendsService = FriendsService();
  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _chatScrollCtrl = ScrollController();

  late OnlineClub _club;
  List<OnlineClubMember> _members = [];
  Map<String, FriendItem> _friendRelations = {};
  List<ClubMessage> _messages = [];
  bool _loadingLeaderboard = true;
  bool _loadingChat = true;
  String? _chatError;
  bool _isSending = false;
  bool _isTogglingMembership = false;
  bool _didChange = false;
  RealtimeChannel? _realtimeChannel;

  bool get _meetsLevel =>
      RunnerStats.meetsLevelRequirement(userLevel: widget.userLevel, minLevel: _club.minLevel);

  @override
  void initState() {
    super.initState();
    _club = widget.club;
    _loadLeaderboard();
    _loadMessages();
    _realtimeChannel = _communityService.subscribeToClubMessages(
      clubId: _club.id,
      onChange: () => _loadMessages(scrollToBottom: true),
    );
  }

  @override
  void dispose() {
    _communityService.unsubscribeChannel(_realtimeChannel);
    _chatCtrl.dispose();
    _chatScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLeaderboard() async {
    try {
      final list = await _communityService.fetchClubLeaderboard(_club.id);
      final friendSnap = AuthService.isLoggedIn
          ? await _friendsService.fetchFriendsSnapshot()
          : const FriendsSnapshot(isAvailable: false);
      if (mounted) {
        setState(() {
          _members = list;
          _friendRelations = friendSnap.relationByUserId;
          _loadingLeaderboard = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingLeaderboard = false);
    }
  }

  Future<void> _addFriendFromLeaderboard(OnlineClubMember member) async {
    if (!await _ensureLoggedIn()) return;
    try {
      await _friendsService.sendFriendRequest(member.userId);
      await _loadLeaderboard();
      _showSnack('Permintaan pertemanan dikirim ke ${member.name}!');
    } catch (e) {
      _showSnack('Gagal menambah teman: $e', isError: true);
    }
  }

  Future<void> _loadMessages({bool scrollToBottom = false}) async {
    try {
      final list = await _communityService.fetchClubMessages(_club.id);
      if (mounted) {
        setState(() {
          _messages = list;
          _loadingChat = false;
          _chatError = null;
        });
        if (scrollToBottom) {
          _scrollToLatestMessage();
        }
      }
    } on PostgrestException catch (e) {
      final missingTable = e.code == 'PGRST205' ||
          e.code == '42P01' ||
          e.message.toLowerCase().contains('club_messages');
      if (mounted) {
        setState(() {
          _loadingChat = false;
          _chatError = missingTable
              ? 'Tabel obrolan klub belum aktif. Jalankan supabase/migration_p2_clubs.sql di SQL Editor Supabase.'
              : 'Gagal memuat obrolan: ${e.message}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingChat = false;
          _chatError = 'Tidak dapat memuat obrolan klub saat ini.';
        });
      }
    }
  }

  void _scrollToLatestMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.animateTo(
          _chatScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<bool> _ensureLoggedIn() async {
    if (AuthService.isLoggedIn) return true;
    final didLogin = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    return didLogin == true && AuthService.isLoggedIn;
  }

  Future<void> _toggleMembership() async {
    if (_isTogglingMembership) return;

    if (!_club.isJoined && !_meetsLevel) {
      final xpMissing = RunnerStats.xpNeededForLevel(_club.minLevel, widget.userTotalXp);
      _showSnack(
        'Klub ini membutuhkan minimal Level ${_club.minLevel} (kurang $xpMissing XP lagi).',
        isError: true,
      );
      return;
    }

    if (!await _ensureLoggedIn()) return;

    setState(() => _isTogglingMembership = true);
    try {
      final joining = !_club.isJoined;
      await _communityService.toggleClub(
        _club.id,
        currentlyJoined: _club.isJoined,
        userLevel: widget.userLevel,
        minLevel: _club.minLevel,
      );

      if (mounted) {
        setState(() {
          _club = _club.copyWith(
            isJoined: joining,
            membersCount: (_club.membersCount + (joining ? 1 : -1)).clamp(0, 999999),
          );
          _didChange = true;
        });
        _showSnack(joining ? 'Berhasil bergabung! Ruang obrolan klub kini terbuka.' : 'Keluar dari ${_club.name}.');
      }
      await _loadLeaderboard();
    } catch (e) {
      _showSnack('Gagal memperbarui keanggotaan: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isTogglingMembership = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    if (!await _ensureLoggedIn()) return;

    setState(() => _isSending = true);
    try {
      await _communityService.sendClubMessage(clubId: _club.id, content: text);
      _chatCtrl.clear();
      await _loadMessages(scrollToBottom: true);
    } catch (e) {
      _showSnack('Gagal mengirim pesan: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _confirmDeleteMessage(ClubMessage msg) async {
    if (!msg.isCurrentUser) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.cardDark,
            title: const Text('Hapus Pesan?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: const Text('Pesan ini akan dihapus dari obrolan klub.', style: TextStyle(color: AppColors.textSecondary)),
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
    try {
      await _communityService.deleteClubMessage(msg.id);
      await _loadMessages();
    } catch (e) {
      _showSnack('Gagal menghapus pesan: $e', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : AppColors.cardElevated,
      ),
    );
  }

  String _formatMsgTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.pop(context, _didChange);
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: AppColors.backgroundDark,
          appBar: AppBar(
            backgroundColor: AppColors.backgroundDark,
            elevation: 0,
            title: Text(
              _club.name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.5),
            ),
            actions: [
              IconButton(
                tooltip: 'Segarkan Data Klub',
                icon: const Icon(Icons.sync, color: Colors.white70),
                onPressed: () {
                  _loadLeaderboard();
                  _loadMessages();
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // Header Info Klub
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _club.color.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: _club.color.withValues(alpha: 0.2),
                          child: Icon(Icons.directions_run, color: _club.color, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (_meetsLevel ? AppColors.accentGreen : Colors.white24).withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'MIN LV. ${_club.minLevel}',
                                      style: TextStyle(
                                        color: _meetsLevel ? AppColors.accentGreen : Colors.white60,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${_club.membersCount} Anggota',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_club.location} • ${_club.schedule}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _club.isJoined
                                ? AppColors.cardElevated
                                : (_meetsLevel ? _club.color : Colors.white12),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _isTogglingMembership ? null : _toggleMembership,
                          child: _isTogglingMembership
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(
                                  _club.isJoined
                                      ? 'Keluar'
                                      : (_meetsLevel ? 'Gabung' : 'Lv. ${_club.minLevel}'),
                                  style: TextStyle(
                                    color: _meetsLevel || _club.isJoined ? Colors.white : Colors.white54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    if (_club.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_club.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ],
                ),
              ),

              // 2 Sub-Tab: Leaderboard & Obrolan Klub
              const TabBar(
                indicatorColor: AppColors.primaryOrange,
                indicatorWeight: 3,
                labelColor: AppColors.primaryOrange,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: [
                  Tab(icon: Icon(Icons.leaderboard_outlined, size: 18), text: 'Leaderboard'),
                  Tab(icon: Icon(Icons.forum_outlined, size: 18), text: 'Obrolan Klub'),
                ],
              ),

              Expanded(
                child: TabBarView(
                  children: [
                    _buildLeaderboardTab(),
                    _buildClubChatTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboardTab() {
    if (_loadingLeaderboard) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
    }
    if (_members.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada anggota di klub ini.\nJadilah pelari pertama yang bergabung!',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLeaderboard,
      color: AppColors.primaryOrange,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _members.length,
        itemBuilder: (context, idx) {
          final m = _members[idx];
          final rank = idx + 1;
          final hasAvatar = m.isCurrentUser && widget.userAvatarPath != null;

          return GestureDetector(
            onTap: () async {
              await RunnerProfileSheet.show(
                context,
                userId: m.userId,
                fallbackName: m.name,
                fallbackCity: m.city,
                fallbackLevel: m.runnerLevel,
              );
              if (mounted) await _loadLeaderboard();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: m.isCurrentUser ? AppColors.primaryOrange.withValues(alpha: 0.16) : AppColors.cardDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: m.isCurrentUser ? AppColors.primaryOrange : Colors.white10),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
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
                    radius: 18,
                    backgroundColor: AppColors.cardElevated,
                    backgroundImage: hasAvatar ? FileImage(File(widget.userAvatarPath!)) : null,
                    child: !hasAvatar
                        ? Text(
                            m.name.trim().isNotEmpty ? m.name.trim()[0].toUpperCase() : '?',
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
                                m.isCurrentUser ? '${m.name} (Anda)' : m.name,
                                style: TextStyle(
                                  fontWeight: m.isCurrentUser ? FontWeight.bold : FontWeight.w600,
                                  color: Colors.white,
                                  fontSize: 13.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Lv.${m.runnerLevel}',
                                style: const TextStyle(color: Colors.amber, fontSize: 9.5, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${m.runsCount} sesi minggu ini • ${m.city}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${m.weeklyKm.toStringAsFixed(1)} km',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: m.isCurrentUser ? AppColors.primaryOrange : Colors.white,
                    ),
                  ),
                  if (!m.isCurrentUser) ...[
                    const SizedBox(width: 6),
                    _buildQuickFriendAction(m),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickFriendAction(OnlineClubMember member) {
    final relation = _friendRelations[member.userId];
    final status = relation?.status ?? FriendRelationStatus.none;

    if (status == FriendRelationStatus.accepted) {
      return const Tooltip(
        message: 'Sudah Berteman',
        child: Icon(Icons.how_to_reg, color: AppColors.accentGreen, size: 19),
      );
    }
    if (status == FriendRelationStatus.pendingOutgoing) {
      return const Tooltip(
        message: 'Menunggu Konfirmasi',
        child: Icon(Icons.hourglass_top_rounded, color: Colors.amber, size: 18),
      );
    }
    return IconButton(
      tooltip: status == FriendRelationStatus.pendingIncoming ? 'Terima Teman' : 'Tambah Teman',
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(4),
      icon: Icon(
        Icons.person_add_alt_1_outlined,
        color: status == FriendRelationStatus.pendingIncoming ? AppColors.accentGreen : AppColors.primaryOrange,
        size: 19,
      ),
      onPressed: () => _addFriendFromLeaderboard(member),
    );
  }

  Widget _buildClubChatTab() {
    return Column(
      children: [
        Expanded(
          child: _loadingChat
              ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
              : _chatError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _chatError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.amber, fontSize: 12.5),
                        ),
                      ),
                    )
                  : _messages.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.forum_outlined, size: 42, color: Colors.white24),
                              SizedBox(height: 10),
                              Text(
                                'Belum ada obrolan di klub ini.\nMulai sapa sesama pelari atau ajak lari bareng!',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadMessages,
                          color: AppColors.primaryOrange,
                          child: ListView.builder(
                            controller: _chatScrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            itemCount: _messages.length,
                            itemBuilder: (context, idx) {
                              final msg = _messages[idx];
                              return _buildChatBubble(msg);
                            },
                          ),
                        ),
        ),
        _buildChatComposer(),
      ],
    );
  }

  Widget _buildChatBubble(ClubMessage msg) {
    final isMe = msg.isCurrentUser;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: isMe ? () => _confirmDeleteMessage(msg) : null,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: isMe ? AppColors.primaryOrange.withValues(alpha: 0.24) : AppColors.cardDark,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isMe ? 14 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 14),
            ),
            border: Border.all(
              color: isMe ? AppColors.primaryOrange.withValues(alpha: 0.55) : Colors.white10,
            ),
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isMe ? 'Anda' : msg.senderName,
                    style: TextStyle(
                      color: isMe ? AppColors.primaryOrangeLight : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      'Lv.${msg.senderLevel}',
                      style: const TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatMsgTime(msg.createdAt),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                msg.content,
                style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatComposer() {
    if (!_club.isJoined || !AuthService.isLoggedIn) {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.cardDark,
            border: Border(top: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Icon(
                _meetsLevel ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                size: 18,
                color: _meetsLevel ? AppColors.primaryOrange : Colors.amber,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  !_meetsLevel
                      ? 'Capai Level ${_club.minLevel} lalu gabung klub untuk ikut mengobrol.'
                      : 'Gabung klub ini untuk ikut mengirim pesan di ruang obrolan.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _meetsLevel ? AppColors.primaryOrange : Colors.white12,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _toggleMembership,
                child: Text(
                  _meetsLevel ? 'Gabung' : 'Lv. ${_club.minLevel}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: const BoxDecoration(
          color: AppColors.cardDark,
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatCtrl,
                maxLength: 500,
                maxLines: 3,
                minLines: 1,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Tulis pesan untuk anggota klub...',
                  hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.backgroundDark,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 21,
              backgroundColor: AppColors.primaryOrange,
              child: IconButton(
                onPressed: _isSending ? null : _sendMessage,
                icon: _isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 19),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
