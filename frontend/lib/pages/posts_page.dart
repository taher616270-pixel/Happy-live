import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

  final _composer = TextEditingController();
  final List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _publishing = false;
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
    _composer.dispose();
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

  Future<void> _publish() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _publishing) return;
    setState(() => _publishing = true);
    try {
      final response = await http.post(Uri.parse('$_api/posts'),
        headers: _headers, body: jsonEncode({'content': text}))
        .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (response.statusCode != 201 || data is! Map || data['ok'] != true) {
        throw Exception(data is Map ? (data['message'] ?? 'تعذر نشر المنشور') : 'تعذر نشر المنشور');
      }
      if (!mounted) return;
      _composer.clear();
      FocusScope.of(context).unfocus();
      setState(() => _posts.insert(0, Map<String, dynamic>.from(data['post'] as Map)));
      _toast('تم نشر منشورك بنجاح');
    } catch (e) {
      if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
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
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFFF7EBCB), Color(0xFFFAF6EA), Color(0xFFF6F7FB)],
      ),
    ),
    child: RefreshIndicator(
      color: _gold,
      onRefresh: _loadPosts,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('المنشورات', style: TextStyle(color: _ink, fontSize: 25, fontWeight: FontWeight.w900)),
              SizedBox(height: 4),
              Text('لحظات وأفكار من مجتمع Happy Live', style: TextStyle(color: _muted, fontSize: 12)),
            ])),
            Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFEAD9AD))),
              child: const Icon(Icons.auto_awesome_rounded, color: _gold)),
          ]),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFEADFC7)), boxShadow: const [BoxShadow(color: Color(0x0C000000), blurRadius: 12, offset: Offset(0, 4))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _avatar(widget.name),
                const SizedBox(width: 10),
                Expanded(child: Text('مرحباً ${widget.name}، شارك لحظتك', style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _composer,
                minLines: 2, maxLines: 5, maxLength: 2000,
                textDirection: TextDirection.rtl,
                style: const TextStyle(color: _ink, fontSize: 14, height: 1.5),
                decoration: InputDecoration(
                  hintText: 'ماذا تريد أن تشارك المجتمع اليوم؟',
                  hintStyle: const TextStyle(color: _muted, fontSize: 13),
                  counterStyle: const TextStyle(color: _muted, fontSize: 10),
                  filled: true, fillColor: _cream,
                  contentPadding: const EdgeInsets.all(13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),
              Row(children: [
                const Icon(Icons.public_rounded, color: _gold, size: 17),
                const SizedBox(width: 5),
                const Expanded(child: Text('مشاركة عامة', style: TextStyle(color: _muted, fontSize: 11))),
                FilledButton.icon(
                  onPressed: _publishing ? null : _publish,
                  style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                  icon: _publishing ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, size: 16),
                  label: const Text('نشر', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 20),
          Row(children: [
            const Expanded(child: Text('أحدث المشاركات', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w900))),
            TextButton.icon(onPressed: _loadPosts, icon: const Icon(Icons.refresh_rounded, size: 17), label: const Text('تحديث'), style: TextButton.styleFrom(foregroundColor: _gold)),
          ]),
          if (_loading && _posts.isEmpty)
            const Padding(padding: EdgeInsets.all(35), child: Center(child: CircularProgressIndicator(color: _gold)))
          else if (_error != null && _posts.isEmpty)
            Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: Column(children: [
              const Icon(Icons.cloud_off_rounded, color: _gold, size: 32), const SizedBox(height: 9),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 12)),
              TextButton(onPressed: _loadPosts, child: const Text('إعادة المحاولة', style: TextStyle(color: _gold))),
            ]))
          else if (_posts.isEmpty)
            Container(padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFEADFC7))), child: const Column(children: [
              Icon(Icons.forum_outlined, color: _gold, size: 38), SizedBox(height: 10),
              Text('لا توجد منشورات بعد', style: TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 15)),
              SizedBox(height: 5), Text('كن أول من يشارك لحظة مع مجتمع Happy Live', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 12)),
            ]))
          else
            ..._posts.map(_postCard),
        ],
      ),
    ),
  );

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
