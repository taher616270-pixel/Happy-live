import 'dart:async';
import '../widgets/centered_notification.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Direct private conversation opened from a public profile.
class PrivateChatPage extends StatefulWidget {
  const PrivateChatPage({
    super.key,
    required this.accessToken,
    required this.conversationId,
    required this.title,
    this.avatarUrl = '',
  });

  final String accessToken;
  final String conversationId;
  final String title;
  final String avatarUrl;

  static const String apiBase =
      'https://happy-live-api.taher616270.workers.dev/api/v1';

  @override
  State<PrivateChatPage> createState() => _PrivateChatPageState();
}

class _PrivateChatPageState extends State<PrivateChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _refreshTimer;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String _currentUserId = '';
  List<Map<String, dynamic>> _messages = [];

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${widget.accessToken}',
        'Content-Type': 'application/json',
      };

  String get _conversationPath =>
      '/messages/conversations/${Uri.encodeComponent(widget.conversationId)}';

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _loadMessages(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await http
          .get(
            Uri.parse('${PrivateChatPage.apiBase}$_conversationPath/messages?limit=100'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map ||
          response.statusCode != 200 ||
          decoded['ok'] != true) {
        throw Exception(decoded is Map
            ? (decoded['message'] ?? decoded['error'] ?? 'تعذر تحميل الرسائل')
                .toString()
            : 'تعذر تحميل الرسائل');
      }
      final rows = (decoded['messages'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      // Keep the timeline chronological even if the API changes its sort order.
      rows.sort((a, b) {
        final aDate = _dateForMessage(a);
        final bDate = _dateForMessage(b);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      });
      if (!mounted) return;
      setState(() {
        _messages = rows;
        _currentUserId = (decoded['currentUserId'] ?? '').toString();
        _loading = false;
        _error = null;
      });
      await http.patch(
        Uri.parse('${PrivateChatPage.apiBase}$_conversationPath/read'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (!silent) _scrollToLatest();
    } catch (error) {
      if (mounted && !silent) {
        setState(() {
          _loading = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final response = await http
          .post(
            Uri.parse('${PrivateChatPage.apiBase}$_conversationPath/messages'),
            headers: _headers,
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map ||
          response.statusCode != 201 ||
          decoded['ok'] != true) {
        throw Exception(decoded is Map
            ? (decoded['message'] ?? decoded['error'] ?? 'تعذر إرسال الرسالة')
                .toString()
            : 'تعذر إرسال الرسالة');
      }
      final sent = decoded['message'] is Map
          ? Map<String, dynamic>.from(decoded['message'] as Map)
          : <String, dynamic>{
              'senderId': _currentUserId,
              'text': text,
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            };
      _input.clear();
      if (!mounted) return;
      setState(() {
        _messages.add(sent);
        _error = null;
      });
      _scrollToLatest();
    } catch (error) {
      if (mounted) {
        showCenteredNotification(context, 
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _messageText(Map<String, dynamic> message) =>
      (message['text'] ?? message['body'] ?? '').toString();

  String _senderId(Map<String, dynamic> message) =>
      (message['senderId'] ?? message['sender_id'] ?? '').toString();

  DateTime? _dateForMessage(Map<String, dynamic> message) {
    final raw = message['createdAt'] ??
        message['created_at'] ??
        message['timestamp'] ??
        message['sentAt'];
    if (raw == null) return null;
    if (raw is num) {
      final value = raw.toInt();
      final milliseconds = value.abs() < 1000000000000
          ? value * 1000
          : value;
      return DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      ).toLocal();
    }
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  DateTime? _messageDate(Map<String, dynamic> message) =>
      _dateForMessage(message);

  bool _startsTimeGroup(int index) {
    // Keep timestamps on their own centered line between messages.
    return index > 0;
  }

  String _timeGroupLabel(int index) {
    final current = _messageDate(_messages[index]);
    if (current == null) return '';

    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${current.year}-${twoDigits(current.month)}-${twoDigits(current.day)} '
        '${twoDigits(current.hour)}:${twoDigits(current.minute)}:${twoDigits(current.second)}';
  }

  Widget _timeSeparator(int index) {
    final label = _timeGroupLabel(index);
    if (label.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 9, bottom: 9),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFB0B0B0),
            fontSize: 10,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F5EC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1E2233),
          elevation: 0.5,
          title: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _loadMessages,
                                  child: const Text('إعادة المحاولة'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _messages.isEmpty
                          ? const Center(
                              child: Text(
                                'ابدأ المحادثة بإرسال أول رسالة',
                                style: TextStyle(color: Color(0xFF888888)),
                              ),
                            )
                          : ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message = _messages[index];
                                final mine = _senderId(message) == _currentUserId;
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_startsTimeGroup(index))
                                      _timeSeparator(index),
                                    Align(
                                      alignment: mine
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: Container(
                                        constraints: BoxConstraints(
                                          maxWidth:
                                              MediaQuery.of(context).size.width * .78,
                                        ),
                                        margin: const EdgeInsets.only(bottom: 9),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: mine
                                              ? const Color(0xFFFFE8B2)
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(17),
                                        ),
                                        child: Text(
                                          _messageText(message),
                                          style: const TextStyle(
                                            color: Color(0xFF292929),
                                            fontSize: 14,
                                            height: 1.45,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                color: Colors.white,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: 'اكتب رسالتك...',
                          filled: true,
                          fillColor: const Color(0xFFF5F3EE),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: Material(
                        color: const Color(0xFFD9A93C),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _sending ? null : _send,
                          child: Center(
                            child: _sending
                                ? const SizedBox(
                                    width: 19,
                                    height: 19,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded,
                                    color: Colors.white, size: 21),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
