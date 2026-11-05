import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HappyPostsPage extends StatefulWidget {
  const HappyPostsPage({super.key, required this.accessToken, required this.name});
  final String accessToken;
  final String name;

  @override
  State<HappyPostsPage> createState() => _HappyPostsPageState();
}

class _HappyPostsPageState extends State<HappyPostsPage> {
  static const _api = 'https://happy-live-api.taher616270.workers.dev/api/v1';
  static const _ink = Color(0xFF1E2233);
  static const _gold = Color(0xFFD9A93C);
  static const _muted = Color(0xFF8B899A);
  static const _cream = Color(0xFFFAF6EA);

  final List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  String? _error;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${widget.accessToken}',
    'Content-Type': 'application/json',
  };

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadPosts() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final response = await http.get(Uri.parse('$_api/posts'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'})
        .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data is! Map || data['ok'] != true) {
        throw Exception('تعذر تحميل المنشورات');
      }
      final items = (data['posts'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (mounted) setState(() { _posts..clear()..addAll(items); _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'تعذر الاتصال الآن. اسحب للأسفل للمحاولة مرة أخرى.'; });
    }
  }

  Future<void> _openCreatePost() async {
    final content = await Navigator.of(context).push<String>(
      PageRouteBuilder<String>(
        pageBuilder: (_, __, ___) => _CreatePostPage(
          name: widget.name,
          onPublish: _submitPost,
        ),
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
    if (!mounted || content == null) return;
    _toast('تم نشر منشورك بنجاح');
  }

  Future<String?> _submitPost(String text) async {
    final response = await http.post(
      Uri.parse('$_api/posts'),
      headers: _headers,
      body: jsonEncode({'content': text}),
    ).timeout(const Duration(seconds: 15));
    final data = jsonDecode(response.body);
    if (response.statusCode != 201 || data is! Map || data['ok'] != true) {
      throw Exception(data is Map
          ? (data['message'] ?? data['error'] ?? 'تعذر نشر المنشور').toString()
          : 'تعذر نشر المنشور');
    }
    if (!mounted) return null;
    setState(() => _posts.insert(0, Map<String, dynamic>.from(data['post'] as Map)));
    return text;
  }

  Future<void> _toggleLike(Map<String, dynamic> post) async {
    final id = post['id'].toString();
    final oldLiked = post['liked'] == true;
    final oldCount = (post['likesCount'] as num?)?.toInt() ?? 0;
    setState(() {
      post['liked'] = !oldLiked;
      post['likesCount'] = oldCount + (oldLiked ? -1 : 1);
    });
    try {
      final response = await http.post(Uri.parse('$_api/posts/$id/like'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'})
        .timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data is! Map || data['ok'] != true) throw Exception();
      if (mounted) setState(() { post['liked'] = data['liked']; post['likesCount'] = data['likesCount']; });
    } catch (_) {
      if (mounted) setState(() { post['liked'] = oldLiked; post['likesCount'] = oldCount; });
      _toast('تعذر تسجيل الإعجاب');
    }
  }

  Future<void> _toggleFollow(Map<String, dynamic> post) async {
    final userId = post['userId'].toString();
    final old = post['followed'] == true;
    setState(() => post['followed'] = !old);
    try {
      final response = await http.post(Uri.parse('$_api/users/$userId/follow'),
        headers: {'Authorization': 'Bearer ${widget.accessToken}'})
        .timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data is! Map || data['ok'] != true) throw Exception();
      if (mounted) setState(() => post['followed'] = data['following'] == true);
    } catch (_) {
      if (mounted) setState(() => post['followed'] = old);
      _toast('تعذر تحديث المتابعة');
    }
  }

  Future<void> _openComments(Map<String, dynamic> post) async {
    final id = post['id'].toString();
    final input = TextEditingController();
    bool loading = true;
    bool sending = false;
    String? error;
    List<Map<String, dynamic>> comments = [];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> load() async {
            try {
              final response = await http.get(Uri.parse('$_api/posts/$id/comments'),
                headers: {'Authorization': 'Bearer ${widget.accessToken}'});
              final data = jsonDecode(response.body);
              if (response.statusCode == 200 && data is Map && data['ok'] == true) {
                comments = (data['comments'] as List? ?? const []).whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e)).toList();
                error = null;
              } else { error = 'تعذر تحميل التعليقات'; }
            } catch (_) { error = 'تحقق من اتصال الإنترنت'; }
            loading = false;
            setSheetState(() {});
          }
          Future<void> send() async {
            final text = input.text.trim();
            if (text.isEmpty || sending) return;
            sending = true; setSheetState(() {});
            try {
              final response = await http.post(Uri.parse('$_api/posts/$id/comments'),
                headers: _headers, body: jsonEncode({'content': text}));
              final data = jsonDecode(response.body);
              if (response.statusCode != 201 || data is! Map || data['ok'] != true) throw Exception();
              comments.add(Map<String, dynamic>.from(data['comment'] as Map));
              input.clear();
              post['commentsCount'] = ((post['commentsCount'] as num?)?.toInt() ?? 0) + 1;
            } catch (_) { error = 'تعذر إضافة التعليق'; }
            sending = false; setSheetState(() {});
          }
          if (loading && comments.isEmpty) load();
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              height: MediaQuery.of(context).size.height * .72,
              padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
              decoration: const BoxDecoration(
                color: Color(0xFFFFFEFA),
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Column(children: [
                Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5DFD0), borderRadius: BorderRadius.circular(5))),
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(child: Text('التعليقات', style: TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w900))),
                  Text('${comments.length}', style: const TextStyle(color: _muted, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 12),
                Expanded(child: loading
                  ? const Center(child: CircularProgressIndicator(color: _gold))
                  : error != null && comments.isEmpty
                    ? Center(child: Text(error!, style: const TextStyle(color: _muted)))
                    : comments.isEmpty
                      ? const Center(child: Text('كن أول من يعلّق على هذا المنشور', style: TextStyle(color: _muted)))
                      : ListView.separated(
                          itemCount: comments.length,
                          separatorBuilder: (_, __) => const Divider(height: 18, color: Color(0xFFF0EBDD)),
                          itemBuilder: (_, i) {
                            final c = comments[i];
                            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              _avatar((c['name'] ?? 'م').toString()),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text((c['name'] ?? 'مستخدم').toString(), style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 13)),
                                const SizedBox(height: 4),
                                Text((c['content'] ?? '').toString(), style: const TextStyle(color: _ink, fontSize: 13, height: 1.5)),
                              ])),
                            ]);
                          },
                        )),
                if (error != null && comments.isNotEmpty)
                  Align(alignment: Alignment.centerRight, child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 11))),
                Row(children: [
                  Expanded(child: TextField(
                    controller: input,
                    maxLength: 500,
                    style: const TextStyle(color: _ink, fontSize: 13),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'اكتب تعليقاً...',
                      hintStyle: const TextStyle(color: _muted),
                      filled: true, fillColor: _cream,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                    ),
                  )),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: sending ? null : send,
                    style: IconButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.white),
                    icon: sending ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
    input.dispose();
    if (mounted) setState(() {});
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, textAlign: TextAlign.right),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF393329),
    ));
  }

  Widget _avatar(String name) => Container(
    width: 42, height: 42,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(colors: [Color(0xFFF6E4B9), Color(0xFFEAD09A)]),
    ),
    child: Text(name.isEmpty ? 'م' : name.characters.first,
      style: const TextStyle(color: Color(0xFF80602B), fontWeight: FontWeight.w900, fontSize: 16)),
  );

  String _timeAgo(dynamic value) {
    final date = DateTime.tryParse((value ?? '').toString())?.toLocal();
    if (date == null) return 'الآن';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return 'منذ ${diff.inMinutes} د';
    if (diff.inDays < 1) return 'منذ ${diff.inHours} س';
    return 'منذ ${diff.inDays} يوم';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFF7EBCB),
                  Color(0xFFFAF6EA),
                  Color(0xFFF6F7FB),
                ],
              ),
            ),
            child: RefreshIndicator(
              color: _gold,
              onRefresh: _loadPosts,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'المنشورات',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'لحظات وأفكار من مجتمع Happy Live',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFEAD9AD),
                          ),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: _gold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const SizedBox(height: 20),
                  if (_loading && _posts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(35),
                      child: Center(
                        child: CircularProgressIndicator(color: _gold),
                      ),
                    )
                  else if (_error != null && _posts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            color: _gold,
                            size: 32,
                          ),
                          const SizedBox(height: 9),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_posts.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 30,
                        horizontal: 18,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFEADFC7),
                        ),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            color: _gold,
                            size: 38,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'لا توجد منشورات بعد',
                            style: TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'كن أول من يشارك لحظة مع مجتمع Happy Live',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._posts.map(_postCard),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          bottom: 20,
          child: SizedBox(
            width: 56,
            height: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFD700), Color(0xFFFFF8E1)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.5),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _openCreatePost,
                  child: const Center(
                    child: Icon(
                      Icons.edit_note,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _postCard(Map<String, dynamic> post) {
    final name = (post['name'] ?? 'مستخدم').toString();
    final mine = post['isMine'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE9E3D6)), boxShadow: const [BoxShadow(color: Color(0x09000000), blurRadius: 10, offset: Offset(0, 3))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _avatar(name),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(_timeAgo(post['createdAt']), style: const TextStyle(color: _muted, fontSize: 10)),
          ])),
          if (!mine)
            TextButton(
              onPressed: () => _toggleFollow(post),
              style: TextButton.styleFrom(foregroundColor: _gold, visualDensity: VisualDensity.compact),
              child: Text(post['followed'] == true ? 'تتابعه' : 'متابعة', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            )
          else
            const Icon(Icons.verified_user_outlined, color: _gold, size: 19),
        ]),
        const SizedBox(height: 13),
        Text((post['content'] ?? '').toString(), textDirection: TextDirection.rtl, style: const TextStyle(color: _ink, fontSize: 14, height: 1.7)),
        const SizedBox(height: 13),
        const Divider(height: 1, color: Color(0xFFF0EBDD)),
        Row(children: [
          Expanded(child: InkWell(onTap: () => _toggleLike(post), borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(post['liked'] == true ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: post['liked'] == true ? const Color(0xFFE35D67) : _muted, size: 19),
            const SizedBox(width: 6), Text('${post['likesCount'] ?? 0}', style: TextStyle(color: post['liked'] == true ? const Color(0xFFE35D67) : _muted, fontSize: 12, fontWeight: FontWeight.w700)),
          ])))),
          Container(width: 1, height: 22, color: const Color(0xFFF0EBDD)),
          Expanded(child: InkWell(onTap: () => _openComments(post), borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.mode_comment_outlined, color: _muted, size: 18), const SizedBox(width: 6),
            Text('${post['commentsCount'] ?? 0} تعليق', style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w700)),
          ])))),
        ]),
      ]),
    );
  }
}


class _CreatePostPage extends StatefulWidget {
  const _CreatePostPage({required this.name, required this.onPublish});
  final String name;
  final Future<String?> Function(String content) onPublish;
  @override
  State<_CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<_CreatePostPage> {
  static const _gold = Color(0xFFD4A017);
  static const _ink = Color(0xFF242424);
  static const _draftKey = 'happy_live_create_post_draft';
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _publishing = false;
  bool _emojiPanelOpen = false;
  String _visibility = 'عام';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleEmojiPanel() {
    if (_emojiPanelOpen) {
      setState(() => _emojiPanelOpen = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _emojiPanelOpen = true);
    }
  }

  Future<void> _publish() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _publishing) return;
    _focusNode.unfocus();
    setState(() => _publishing = true);
    try {
      final published = await widget.onPublish(content);
      if (!mounted || published == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
      if (mounted) Navigator.of(context).pop(published);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', ''), textAlign: TextAlign.right),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF393329),
        ));
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _closeComposer() async {
    if (_publishing) return;
    if (_controller.text.trim().isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    _focusNode.unfocus();
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('حفظ كمسودة', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 22),
              Row(children: [
                Expanded(child: SizedBox(height: 48, child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext, 'discard'),
                  style: TextButton.styleFrom(backgroundColor: const Color(0xFFF3F4F6), foregroundColor: _ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('تجاهل المنشور', style: TextStyle(fontWeight: FontWeight.w700)),
                ))),
                const SizedBox(width: 10),
                Expanded(child: SizedBox(height: 48, child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext, 'save'),
                  style: TextButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('حفظ', style: TextStyle(fontWeight: FontWeight.w800)),
                ))),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (choice == 'discard') {
      await prefs.remove(_draftKey);
    } else {
      await prefs.setString(_draftKey, _controller.text);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showVisibilitySheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        String current = _visibility;
        return StatefulBuilder(builder: (context, setSheetState) => Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(alignment: Alignment.center, children: [
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('من يمكنه الرؤية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink))),
                Align(alignment: AlignmentDirectional.centerEnd, child: IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded, color: _ink))),
              ]),
              const SizedBox(height: 8),
              _visibilityOption('عام', current, 'عام 🌍', 'كل المستخدمين يمكنهم رؤية منشورك', Icons.public_rounded, () => setSheetState(() => current = 'عام')),
              _visibilityOption('الأصدقاء', current, 'الأصدقاء 👥', 'فقط الأصدقاء يمكنهم الرؤية', Icons.people_alt_outlined, () => setSheetState(() => current = 'الأصدقاء')),
              _visibilityOption('خاص', current, 'خاص 🔒', 'أنا فقط من يمكنه الرؤية', Icons.lock_outline_rounded, () => setSheetState(() => current = 'خاص')),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
                onPressed: () => Navigator.pop(sheetContext, current),
                style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('تم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              )),
            ]),
          ),
        ));
      },
    );
    if (selected != null && mounted) setState(() => _visibility = selected);
  }

  Widget _visibilityOption(String value, String current, String title, String subtitle, IconData icon, VoidCallback onTap) {
    final selected = current == value;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? _gold : const Color(0xFFB8BBC1), size: 22),
          const SizedBox(width: 12),
          Icon(icon, color: const Color(0xFF777777), size: 21),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
          ])),
        ]),
      ),
    );
  }

  Widget _topicTag(String label, {bool primary = false}) => Container(
    margin: const EdgeInsetsDirectional.only(end: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: primary ? const Color(0xFFE6F2FF) : const Color(0xFFF1F2F4), borderRadius: BorderRadius.circular(18)),
    child: Text(label, maxLines: 1, style: TextStyle(color: primary ? const Color(0xFF3987D8) : const Color(0xFF666A70), fontSize: 11, fontWeight: FontWeight.w600)),
  );

  Widget _toolButton({required Widget icon, required VoidCallback onTap, String? tooltip}) => IconButton(
    tooltip: tooltip, onPressed: onTap, visualDensity: VisualDensity.compact, splashRadius: 21,
    padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 34, height: 40), icon: icon,
  );

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,
        body: SafeArea(child: Column(children: [
          SizedBox(height: 54, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              IconButton(tooltip: 'إغلاق', onPressed: _closeComposer, icon: const Icon(Icons.close_rounded, color: _ink, size: 25)),
              const Spacer(),
              TextButton(
                onPressed: _publishing || !hasText ? null : _publish,
                style: TextButton.styleFrom(foregroundColor: _gold, disabledForegroundColor: const Color(0xFF9CA3AF), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                child: _publishing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _gold)) : const Text('نشر'),
              ),
            ]),
          )),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 18, 0),
            child: Align(alignment: AlignmentDirectional.topStart, child: Container(
              width: 100, height: 130,
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(12)),
              child: Material(color: Colors.transparent, borderRadius: BorderRadius.circular(12), child: InkWell(
                borderRadius: BorderRadius.circular(12), onTap: () {},
                child: const Center(child: Icon(Icons.add_rounded, color: Color(0xFF9A9DA3), size: 34)),
              )),
            )),
          ),
          Expanded(child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(18, 12, 18, 4),
            child: TextField(
              controller: _controller, focusNode: _focusNode, autofocus: true,
              minLines: null, maxLines: null, expands: true, maxLength: 2000,
              textDirection: TextDirection.rtl, textAlign: TextAlign.right, textAlignVertical: TextAlignVertical.top,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: _ink, fontSize: 17, height: 1.7),
              decoration: const InputDecoration(
                hintText: 'قول شي... ماذا تريد أن تشارك المجتمع اليوم؟',
                hintStyle: TextStyle(color: Color(0xFFB2B2B2), fontSize: 16),
                border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                counterText: '', contentPadding: EdgeInsets.zero,
              ),
            ),
          )),
          SizedBox(height: 46, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              _toolButton(tooltip: 'وسم', onTap: () {}, icon: const Text('#', style: TextStyle(fontSize: 23, color: Color(0xFF555A61)))),
              _toolButton(
                tooltip: _emojiPanelOpen ? 'لوحة المفاتيح' : 'الإيموجي',
                onTap: _toggleEmojiPanel,
                icon: Icon(_emojiPanelOpen ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined, color: const Color(0xFF555A61), size: 22),
              ),
              const SizedBox(width: 4),
              Expanded(child: SizedBox(height: 42, child: ListView(
                scrollDirection: Axis.horizontal,
                children: [_topicTag('#إضافة موضوع', primary: true), _topicTag('#OOTD'), _topicTag('#الصحه_النفسيه')],
              ))),
              const SizedBox(width: 5),
              TextButton.icon(
                onPressed: _showVisibilitySheet,
                style: TextButton.styleFrom(foregroundColor: _gold, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                icon: const Icon(Icons.public_rounded, size: 16),
                label: const Text('عام', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
          )),
          if (_emojiPanelOpen) SizedBox(
            height: 258, width: double.infinity,
            child: EmojiPicker(
              onEmojiSelected: (category, emoji) {},
              textEditingController: _controller,
              config: Config(
                height: 258, checkPlatformCompatibility: true,
                emojiViewConfig: const EmojiViewConfig(columns: 8, emojiSizeMax: 25, backgroundColor: Color(0xFFFFFBEB)),
              ),
            ),
          ),
        ])),
      ),
    );
  }
}
