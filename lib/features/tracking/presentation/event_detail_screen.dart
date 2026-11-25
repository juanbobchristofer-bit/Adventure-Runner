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

/// Halaman Detail Acara Online dengan 2 sub-tab:
/// 1) Diskusi Acara (Live Chat koordinasi titik kumpul & pace)
/// 2) Peserta Hadir (daftar peserta RSVP beserta badge Level)
class EventDetailScreen extends StatefulWidget {
  final OnlineEvent event;
  final int userLevel;
  final int userTotalXp;
  final String? userAvatarPath;

  const EventDetailScreen({
    super.key,
    required this.event,
    required this.userLevel,
    required this.userTotalXp,
    this.userAvatarPath,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final CommunityService _communityService = CommunityService();
  final FriendsService _friendsService = FriendsService();
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _chatScrollCtrl = ScrollController();

  late OnlineEvent _event;
  List<EventAttendee> _attendees = [];
  Map<String, FriendItem> _friendRelations = {};
  List<EventMessage> _messages = [];
  bool _loadingAttendees = true;
  bool _loadingChat = true;
  String? _chatError;
  bool _isSending = false;
  bool _isTogglingRsvp = false;
  bool _didChange = false;
  RealtimeChannel? _realtimeChannel;

  bool get _meetsLevel =>
      RunnerStats.meetsLevelRequirement(userLevel: widget.userLevel, minLevel: _event.minLevel);

  bool get _canSendMessage =>
      AuthService.isLoggedIn &&
      (_event.isAttending || (_event.createdBy != null && _event.createdBy == AuthService.userId));

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _loadAttendees();
    _loadMessages();
    _realtimeChannel = _communityService.subscribeToEventMessages(
      eventId: _event.id,
      onChange: () => _loadMessages(scrollToBottom: true),
    );
  }

  @override
  void dispose() {
    _communityService.unsubscribeChannel(_realtimeChannel);
    _msgCtrl.dispose();
    _chatScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAttendees() async {
    try {
      final list = await _communityService.fetchEventAttendees(_event.id);
      final friendSnap = AuthService.isLoggedIn
          ? await _friendsService.fetchFriendsSnapshot()
          : const FriendsSnapshot(isAvailable: false);
      if (mounted) {
        setState(() {
          _attendees = list;
          _friendRelations = friendSnap.relationByUserId;
          _event = _event.copyWith(attendeesCount: list.length);
          _loadingAttendees = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAttendees = false);
    }
  }

  Future<void> _addFriendFromEvent(EventAttendee attendee) async {
    if (!await _ensureLoggedIn()) return;
    try {
      await _friendsService.sendFriendRequest(attendee.userId);
      await _loadAttendees();
      _showSnack('Permintaan pertemanan dikirim ke ${attendee.name}!');
    } catch (e) {
      _showSnack('Gagal menambah teman: $e', isError: true);
    }
  }

  Future<void> _loadMessages({bool scrollToBottom = false}) async {
    try {
      final list = await _communityService.fetchEventMessages(_event.id);
      if (mounted) {
        setState(() {
          _messages = list;
          _loadingChat = false;
          _chatError = null;
        });
        if (scrollToBottom) _scrollToBottom();
      }
    } on PostgrestException catch (e) {
      final missingTable = e.code == 'PGRST205' ||
          e.code == '42P01' ||
          e.message.toLowerCase().contains('event_messages');
      if (mounted) {
        setState(() {
          _loadingChat = false;
          _chatError = missingTable
              ? 'Tabel diskusi acara belum aktif. Jalankan supabase/migration_p3_events.sql di SQL Editor Supabase.'
              : 'Gagal memuat diskusi: ${e.message}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingChat = false;
          _chatError = 'Tidak dapat memuat diskusi acara saat ini.';
        });
      }
    }
  }

  void _scrollToBottom() {
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

  Future<void> _toggleRsvp() async {
    if (_isTogglingRsvp) return;

    if (!_event.isAttending) {
      if (!_meetsLevel) {
        final xpMissing = RunnerStats.xpNeededForLevel(_event.minLevel, widget.userTotalXp);
        _showSnack('Acara ini membutuhkan minimal Level ${_event.minLevel} (kurang $xpMissing XP).', isError: true);
        return;
      }
      if (_event.isFull) {
        _showSnack('Maaf, kuota peserta acara ini sudah penuh (${_event.maxParticipants}/${_event.maxParticipants}).', isError: true);
        return;
      }
    }

    if (!await _ensureLoggedIn()) return;

    setState(() => _isTogglingRsvp = true);
    try {
      final attending = !_event.isAttending;
      await _communityService.toggleEventRsvp(
        _event.id,
        currentlyAttending: _event.isAttending,
        userLevel: widget.userLevel,
        minLevel: _event.minLevel,
        currentAttendeesCount: _event.attendeesCount,
        maxParticipants: _event.maxParticipants,
      );

      if (mounted) {
        setState(() {
          _event = _event.copyWith(
            isAttending: attending,
            attendeesCount: (_event.attendeesCount + (attending ? 1 : -1)).clamp(0, _event.maxParticipants),
          );
          _didChange = true;
        });
        _showSnack(attending ? 'Kehadiran dikonfirmasi! Ruang diskusi acara kini terbuka.' : 'RSVP acara dibatalkan.');
      }
      await _loadAttendees();
    } catch (e) {
      _showSnack('Gagal memperbarui RSVP: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isTogglingRsvp = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    if (!await _ensureLoggedIn()) return;

    setState(() => _isSending = true);
    try {
      await _communityService.sendEventMessage(eventId: _event.id, content: text);
      _msgCtrl.clear();
      await _loadMessages(scrollToBottom: true);
    } catch (e) {
      _showSnack('Gagal mengirim pesan: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _confirmDeleteMessage(EventMessage msg) async {
    if (!msg.isCurrentUser) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.cardDark,
            title: const Text('Hapus Pesan?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: const Text('Pesan ini akan dihapus dari ruang diskusi acara.', style: TextStyle(color: AppColors.textSecondary)),
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
      await _communityService.deleteEventMessage(msg.id);
      await _loadMessages();
    } catch (e) {
      _showSnack('Gagal menghapus pesan: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.redAccent : AppColors.cardElevated),
    );
  }

  String _formatTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final quotaRatio = (_event.attendeesCount / _event.maxParticipants).clamp(0.0, 1.0);
    final blockedByQuota = !_event.isAttending && _event.isFull;

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
              _event.title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            actions: [
              IconButton(
                tooltip: 'Segarkan Acara',
                icon: const Icon(Icons.sync, color: Colors.white70),
                onPressed: () {
                  _loadAttendees();
                  _loadMessages();
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // Kartu Ringkasan Acara
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _event.isAttending ? AppColors.accentGreen.withValues(alpha: 0.5) : Colors.white10,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primaryOrange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _event.distanceTag,
                            style: const TextStyle(color: AppColors.primaryOrange, fontSize: 10.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (_meetsLevel ? AppColors.accentGreen : Colors.white24).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'MIN LV. ${_event.minLevel}',
                            style: TextStyle(
                              color: _meetsLevel ? AppColors.accentGreen : Colors.white60,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(_event.paceGroup, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 13, color: AppColors.primaryOrange),
                        const SizedBox(width: 6),
                        Text(_event.dateStr, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 13, color: AppColors.accentBlue),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _event.location,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (_event.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_event.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                    const SizedBox(height: 10),
                    // Progress Kuota + Tombol RSVP
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Kuota: ${_event.attendeesCount} / ${_event.maxParticipants} Pelari',
                                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                                  ),
                                  if (_event.isFull)
                                    const Text('PENUH', style: TextStyle(color: Colors.redAccent, fontSize: 10.5, fontWeight: FontWeight.w900)),
                                ],
                              ),
                              const SizedBox(height: 5),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: LinearProgressIndicator(
                                  value: quotaRatio,
                                  minHeight: 6,
                                  backgroundColor: Colors.white10,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _event.isFull ? Colors.redAccent : AppColors.accentBlue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _event.isAttending
                                ? AppColors.accentGreen.withValues(alpha: 0.2)
                                : (!_meetsLevel || blockedByQuota ? Colors.white12 : AppColors.primaryOrange),
                            side: _event.isAttending ? const BorderSide(color: AppColors.accentGreen) : BorderSide.none,
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _isTogglingRsvp ? null : _toggleRsvp,
                          child: _isTogglingRsvp
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(
                                  _event.isAttending
                                      ? 'Terdaftar ✓'
                                      : (!_meetsLevel
                                          ? 'Lv. ${_event.minLevel}'
                                          : (blockedByQuota ? 'Penuh' : 'Ikut Acara')),
                                  style: TextStyle(
                                    color: _event.isAttending
                                        ? AppColors.accentGreen
                                        : (_meetsLevel && !blockedByQuota ? Colors.white : Colors.white54),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const TabBar(
                indicatorColor: AppColors.primaryOrange,
                indicatorWeight: 3,
                labelColor: AppColors.primaryOrange,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: [
                  Tab(icon: Icon(Icons.forum_outlined, size: 18), text: 'Diskusi Acara'),
                  Tab(icon: Icon(Icons.people_outline, size: 18), text: 'Peserta Hadir'),
                ],
              ),

              Expanded(
                child: TabBarView(
                  children: [
                    _buildDiscussionTab(),
                    _buildAttendeesTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiscussionTab() {
    return Column(
      children: [
        Expanded(
          child: _loadingChat
              ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
              : _chatError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_chatError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.amber, fontSize: 12.5)),
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
                                'Belum ada diskusi acara.\nKoordinasikan titik kumpul, pace, atau info cuaca di sini!',
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
                            itemBuilder: (_, idx) => _buildMessageBubble(_messages[idx]),
                          ),
                        ),
        ),
        _buildComposer(),
      ],
    );
  }

  Widget _buildMessageBubble(EventMessage msg) {
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
            color: isMe ? AppColors.accentBlue.withValues(alpha: 0.22) : AppColors.cardDark,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isMe ? 14 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 14),
            ),
            border: Border.all(
              color: isMe ? AppColors.accentBlue.withValues(alpha: 0.55) : Colors.white10,
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
                      color: isMe ? AppColors.accentBlue : Colors.white,
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
                  Text(_formatTime(msg.createdAt), style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ],
              ),
              const SizedBox(height: 5),
              Text(msg.content, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    if (!_canSendMessage) {
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
                _meetsLevel && !_event.isFull ? Icons.event_available : Icons.lock_outline,
                size: 18,
                color: _meetsLevel && !_event.isFull ? AppColors.primaryOrange : Colors.amber,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  !_meetsLevel
                      ? 'Capai Level ${_event.minLevel} lalu daftar acara untuk ikut diskusi.'
                      : _event.isFull
                          ? 'Kuota acara penuh. Hanya peserta terdaftar yang dapat berdiskusi.'
                          : 'Konfirmasi kehadiran (RSVP) untuk ikut berdiskusi di acara ini.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              if (_meetsLevel && !_event.isFull)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _toggleRsvp,
                  child: const Text('Ikut', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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
                controller: _msgCtrl,
                maxLength: 500,
                maxLines: 3,
                minLines: 1,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Tanya titik kumpul, pace, atau info acara...',
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
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 19),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendeesTab() {
    if (_loadingAttendees) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
    }
    if (_attendees.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada pelari yang mendaftar.\nJadilah peserta pertama di acara ini!',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAttendees,
      color: AppColors.primaryOrange,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _attendees.length,
        itemBuilder: (_, idx) {
          final a = _attendees[idx];
          final hasAvatar = a.isCurrentUser && widget.userAvatarPath != null;

          return GestureDetector(
            onTap: () async {
              await RunnerProfileSheet.show(
                context,
                userId: a.userId,
                fallbackName: a.name,
                fallbackCity: a.city,
                fallbackLevel: a.runnerLevel,
              );
              if (mounted) await _loadAttendees();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: a.isCurrentUser ? AppColors.accentGreen.withValues(alpha: 0.14) : AppColors.cardDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: a.isCurrentUser ? AppColors.accentGreen : Colors.white10),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: AppColors.cardElevated,
                    backgroundImage: hasAvatar ? FileImage(File(widget.userAvatarPath!)) : null,
                    child: !hasAvatar
                        ? Text(
                            a.name.trim().isNotEmpty ? a.name.trim()[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                a.isCurrentUser ? '${a.name} (Anda)' : a.name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
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
                                'Lv.${a.runnerLevel}',
                                style: const TextStyle(color: Colors.amber, fontSize: 9.5, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(a.city, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  if (a.isCurrentUser)
                    const Icon(Icons.check_circle, color: AppColors.accentGreen, size: 18)
                  else
                    _buildQuickFriendAction(a),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickFriendAction(EventAttendee attendee) {
    final relation = _friendRelations[attendee.userId];
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
      onPressed: () => _addFriendFromEvent(attendee),
    );
  }
}
