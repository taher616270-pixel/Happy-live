import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'public_profile_page.dart';

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
  String _feedMode = 'daily';
  String _feedFilter = 'all';

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
          accessToken: widget.accessToken,
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

  Future<String?> _submitPost(String text, String? imageUrl) async {
    final response = await http.post(
      Uri.parse('$_api/posts'),
      headers: _headers,
      body: jsonEncode({'content': text, if (imageUrl != null) 'imageUrl': imageUrl}),
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

  Future<void> _openPostActions(Map<String, dynamic> post) async {
    final mine = post['isMine'] == true;
    await showModalBottomSheet<void>(
      context: context, backgroundColor: Colors.transparent,
      builder: (sheetContext) => Directionality(textDirection: TextDirection.rtl, child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
        decoration: const BoxDecoration(color: Color(0xFFFFFEFA), borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5DFD0), borderRadius: BorderRadius.circular(5))),
          const SizedBox(height: 14),
          if (mine) ...[
            _postActionTile(Icons.visibility_outlined, 'من يمكنهم الرؤية', () { Navigator.pop(sheetContext); _openVisibilityPicker(post); }),
            _postActionTile(Icons.delete_outline_rounded, 'حذف', () { Navigator.pop(sheetContext); _deletePost(post); }, color: const Color(0xFFD94B4B)),
          ] else ...[
            _postActionTile(Icons.visibility_off_outlined, 'إخفاء جميع منشوراته', () { Navigator.pop(sheetContext); _hideUserPosts(post); }),
            _postActionTile(Icons.flag_outlined, 'بلاغ', () { Navigator.pop(sheetContext); _reportPost(post); }, color: const Color(0xFFD94B4B)),
          ],
          _postActionTile(Icons.close_rounded, 'إلغاء', () => Navigator.pop(sheetContext)),
        ])),
      )),
    );
  }

  Widget _postActionTile(IconData icon, String label, VoidCallback onTap, {Color color = _ink}) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    leading: Icon(icon, color: color, size: 22),
    title: Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
    onTap: onTap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );

  Future<void> _openVisibilityPicker(Map<String, dynamic> post) async {
    const options = {'public': 'الجميع', 'followers': 'المتابعون', 'private': 'أنا فقط'};
    final selected = await showModalBottomSheet<String>(
      context: context, backgroundColor: Colors.transparent,
      builder: (sheetContext) => Directionality(textDirection: TextDirection.rtl, child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
        decoration: const BoxDecoration(color: Color(0xFFFFFEFA), borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5DFD0), borderRadius: BorderRadius.circular(5))),
          const SizedBox(height: 14),
          const Align(alignment: Alignment.centerRight, child: Text('من يمكنهم رؤية المنشور؟', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w900))),
          ...options.entries.map((e) => _postActionTile(e.key == 'public' ? Icons.public_rounded : e.key == 'followers' ? Icons.people_outline_rounded : Icons.lock_outline_rounded, e.value, () => Navigator.pop(sheetContext, e.key))),
        ])),
      )),
    );
    if (selected == null) return;
    try {
      final response = await http.patch(Uri.parse('$_api/posts/${post['id']}/visibility'), headers: _headers, body: jsonEncode({'visibility': selected})).timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data is! Map || data['ok'] != true) throw Exception();
      if (mounted) { setState(() => post['visibility'] = selected); _toast('تم تحديث خصوصية المنشور'); }
    } catch (_) { _toast('تعذر تحديث خصوصية المنشور'); }
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إلغاء حذف المنشور',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, animation, secondaryAnimation) => CustomConfirmDialog(
        title: 'هل تريد حذف المنشور؟',
        confirmText: 'حذف',
        onConfirm: () => _deletePostConfirmed(post),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _deletePostConfirmed(Map<String, dynamic> post) async {
    try {
      final response = await http.delete(
        Uri.parse('$_api/posts/${post['id']}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data is! Map || data['ok'] != true) throw Exception();
      if (mounted) {
        setState(() => _posts.removeWhere((e) => e['id'].toString() == post['id'].toString()));
        _toast('تم حذف المنشور');
      }
    } catch (_) {
      _toast('تعذر حذف المنشور');
    }
  }

  Future<void> _hideUserPosts(Map<String, dynamic> post) async {
    final userId = post['userId'].toString();
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إلغاء إخفاء المنشورات',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, animation, secondaryAnimation) => CustomConfirmDialog(
        title: 'تأكيد الاخفاء',
        subtitle: 'بعد الاخفاء لن تراه في منشور أصدقائك',
        confirmText: 'اخفاء',
        onConfirm: () => _hideUserPostsConfirmed(userId),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _hideUserPostsConfirmed(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$_api/users/$userId/hide'),
        headers: _headers,
      ).timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data is! Map || data['ok'] != true) throw Exception();
      if (mounted) {
        setState(() => _posts.removeWhere((e) => e['userId'].toString() == userId));
        _toast('تم إخفاء جميع منشوراته');
      }
    } catch (_) {
      _toast('تعذر إخفاء المنشورات');
    }
  }

  Future<void> _reportPost(Map<String, dynamic> post) async {
    try {
      final response = await http.post(Uri.parse('$_api/posts/${post['id']}/report'), headers: _headers, body: jsonEncode({'reason': 'general'})).timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body);
      if (response.statusCode != 201 || data is! Map || data['ok'] != true) throw Exception();
      _toast('تم إرسال البلاغ، شكرًا لمساعدتنا');
    } catch (_) { _toast('تعذر إرسال البلاغ'); }
  }
  Widget _commentActionButton(IconData icon, String label, Color background, Color foreground, VoidCallback onTap) {
    return SizedBox(
      height: 54,
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: foreground, size: 19),
            const SizedBox(height: 3),
            Text(label, maxLines: 1, style: TextStyle(color: foreground, fontSize: 11, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }

  Future<void> _openComments(Map<String, dynamic> post) async {
    final id = post['id'].toString();
    final input = TextEditingController();
    bool loading = true;
    bool sending = false;
    Map<String, dynamic>? replyingTo;
    String? error;
    List<Map<String, dynamic>> comments = [];
    final Set<String> expandedReplyThreads = {};
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
            sending = true; error = null; setSheetState(() {});
            try {
              final isReply = replyingTo != null;
              final endpoint = isReply
                  ? '$_api/posts/$id/comments/${replyingTo!.containsKey('commentId') ? replyingTo!['commentId'] : replyingTo!['id']}/replies'
                  : '$_api/posts/$id/comments';
              final response = await http.post(Uri.parse(endpoint),
                headers: _headers, body: jsonEncode({'content': text, if (isReply && replyingTo!.containsKey('commentId')) 'parentReplyId': replyingTo!['id']}));
              final data = jsonDecode(response.body);
              if (response.statusCode == 429 && data is Map) error = (data['message'] ?? 'انتظر 30 ثانية قبل التعليق مرة أخرى').toString();
              if (response.statusCode != 201 || data is! Map || data['ok'] != true) throw Exception();
              if (isReply) {
                final reply = Map<String, dynamic>.from(data['reply'] as Map);
                final commentId = (replyingTo!.containsKey('commentId') ? replyingTo!['commentId'] : replyingTo!['id']).toString();
                reply['commentId'] = commentId;
                if (replyingTo!.containsKey('commentId')) reply['parentReplyId'] = replyingTo!['id'];
                final comment = comments.firstWhere((item) => item['id'].toString() == commentId);
                bool attach(List<dynamic> nodes) {
                  for (final node in nodes) {
                    if (node is Map && node['id'].toString() == replyingTo!['id'].toString()) {
                      final children = (node['replies'] as List? ?? const []).toList();
                      children.add(reply); node['replies'] = children; return true;
                    }
                    if (node is Map && attach((node['replies'] as List? ?? const []).toList())) return true;
                  }
                  return false;
                }
                if (replyingTo!.containsKey('commentId')) {
                  attach((comment['replies'] as List? ?? const []).toList());
                } else {
                  final children = (comment['replies'] as List? ?? const []).toList();
                  children.add(reply); comment['replies'] = children;
                }
                replyingTo = null;
              } else {
                final comment = Map<String, dynamic>.from(data['comment'] as Map);
                comment['replies'] = <Map<String, dynamic>>[];
                comments.add(comment);
                post['commentsCount'] = ((post['commentsCount'] as num?)?.toInt() ?? 0) + 1;
              }
              input.clear();
              error = null;
            } catch (_) { error ??= replyingTo != null ? 'تعذر إرسال الرد' : 'تعذر إضافة التعليق'; }
            sending = false; setSheetState(() {});
          }
          Future<void> openCommentActions(Map<String, dynamic> comment) async {
            final owner = post['isMine'] == true;
            final action = await showModalBottomSheet<String>(
              context: this.context,
              backgroundColor: Colors.transparent,
              builder: (actionContext) => Directionality(
                textDirection: TextDirection.rtl,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFEFA),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5DFD0), borderRadius: BorderRadius.circular(8))),
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(child: _commentActionButton(Icons.reply_rounded, 'رد', const Color(0xFFFFF3D8), const Color(0xFF8A641D), () => Navigator.pop(actionContext, 'reply'))),
                        const SizedBox(width: 7),
                        if (owner) ...[
                          Expanded(child: _commentActionButton(Icons.delete_outline_rounded, 'حذف', const Color(0xFFFFE9E7), const Color(0xFFB64238), () => Navigator.pop(actionContext, 'delete'))),
                          const SizedBox(width: 7),
                        ],
                        Expanded(child: _commentActionButton(Icons.flag_outlined, 'بلاغ', const Color(0xFFF2EEE5), const Color(0xFF77664A), () => Navigator.pop(actionContext, 'report'))),
                        const SizedBox(width: 7),
                        Expanded(child: _commentActionButton(Icons.close_rounded, 'إلغاء', const Color(0xFFF1F1F1), const Color(0xFF777777), () => Navigator.pop(actionContext, 'cancel'))),
                      ]),
                    ]),
                  ),
                ),
              ),
            );
            if (!mounted || action == null || action == 'cancel') return;
            if (action == 'reply') {
              replyingTo = comment;
              input.clear();
              setSheetState(() {});
              return;
            }
            final commentId = (comment['id'] ?? '').toString();
            if (commentId.isEmpty) return;
            try {
              final isDelete = action == 'delete';
              final response = isDelete
                  ? await http.delete(Uri.parse('$_api/posts/$id/comments/$commentId'), headers: {'Authorization': 'Bearer ${widget.accessToken}'})
                  : await http.post(Uri.parse('$_api/posts/$id/comments/$commentId/report'), headers: _headers, body: jsonEncode({'reason': 'general'}));
              final data = jsonDecode(response.body);
              final expected = isDelete ? 200 : 201;
              if (response.statusCode != expected || data is! Map || data['ok'] != true) {
                throw Exception(data is Map ? (data['error'] ?? '').toString() : '');
              }
              if (isDelete) {
                comments.removeWhere((item) => item['id'].toString() == commentId);
                post['commentsCount'] = (((post['commentsCount'] as num?)?.toInt() ?? 1) - 1).clamp(0, 1 << 30);
              }
              setSheetState(() {});
              if (mounted) _toast(isDelete ? 'تم حذف التعليق' : 'تم إرسال البلاغ');
            } catch (_) {
              if (mounted) _toast(action == 'delete' ? 'تعذر حذف التعليق' : 'تعذر إرسال البلاغ');
            }
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
                            final commenterName = (c['name'] ?? 'مستخدم').toString();
                            final commenterAvatar =
                                (c['avatarUrl'] ?? c['avatar_url'] ?? '').toString().trim();
                            List<Map<String, dynamic>> flattenReplies(List<dynamic> roots, [String? parentName]) {
                              final result = <Map<String, dynamic>>[];
                              for (final raw in roots) {
                                if (raw is! Map) continue;
                                final item = Map<String, dynamic>.from(raw);
                                item['_replyToName'] = parentName;
                                result.add(item);
                                result.addAll(flattenReplies((item['replies'] as List? ?? const []).toList(), (item['name'] ?? 'مستخدم').toString()));
                              }
                              return result;
                            }
                            Widget buildReply(Map<String, dynamic> reply) {
                              final replyName = (reply['name'] ?? 'مستخدم').toString();
                              final avatar = (reply['avatarUrl'] ?? reply['avatar_url'] ?? '').toString().trim();
                              final replyTo = (reply['_replyToName'] ?? '').toString().trim();
                              return Padding(padding: const EdgeInsets.only(bottom: 7),
                                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  InkWell(onTap: () => _openUserProfile(reply), child: CircleAvatar(radius: 14, backgroundColor: const Color(0xFFF3F0E8),
                                    backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                                    child: avatar.isEmpty ? Text(replyName.isEmpty ? 'م' : replyName.characters.first, style: const TextStyle(color: Color(0xFF80602B), fontSize: 10, fontWeight: FontWeight.w900)) : null)),
                                  const SizedBox(width: 8),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    InkWell(onTap: () => _openUserProfile(reply), child: Text(replyName, style: const TextStyle(color: _ink, fontSize: 11, fontWeight: FontWeight.w900))),
                                    if (replyTo.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 1, bottom: 2), child: Text('رد على $replyTo', style: const TextStyle(color: _gold, fontSize: 9, fontWeight: FontWeight.w700))),
                                    Text((reply['content'] ?? '').toString(), style: const TextStyle(color: Colors.black, fontSize: 12, height: 1.45, fontWeight: FontWeight.w600)),
                                    Row(children: [
                                      Text(_timeAgo(reply['createdAt'] ?? reply['created_at']), style: const TextStyle(color: _muted, fontSize: 9)),
                                      TextButton(onPressed: () { replyingTo = {...reply, 'commentId': c['id']}; setSheetState(() {}); },
                                        style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                        child: const Text('رد', style: TextStyle(color: _gold, fontSize: 10, fontWeight: FontWeight.w800))),
                                    ]),
                                  ])),
                                ]),
                              );
                            }
                            final allReplies = flattenReplies((c['replies'] as List? ?? const []).toList());
                            final threadId = c['id'].toString();
                            final expanded = expandedReplyThreads.contains(threadId);
                            final visibleReplies = expanded || allReplies.length <= 1 ? allReplies : <Map<String, dynamic>>[allReplies.first];
                            final hiddenReplyCount = allReplies.length - visibleReplies.length;
                            Widget repliesSection() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              ...visibleReplies.map((reply) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: buildReply(reply),
                              )),
                              if (allReplies.length > 1) Align(alignment: Alignment.centerRight, child: TextButton.icon(
                                onPressed: () { if (expanded) { expandedReplyThreads.remove(threadId); } else { expandedReplyThreads.add(threadId); } setSheetState(() {}); },
                                style: TextButton.styleFrom(foregroundColor: _gold, padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), visualDensity: VisualDensity.compact, minimumSize: Size.zero),
                                icon: Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 17),
                                label: Text(expanded ? 'إخفاء الردود' : 'عرض الردود ($hiddenReplyCount)', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                              )),
                            ]);
                            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              InkWell(
                                onTap: () => _openUserProfile(c),
                                customBorder: const CircleBorder(),
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: const Color(0xFFF3F3F3),
                                  backgroundImage: commenterAvatar.isNotEmpty
                                      ? NetworkImage(commenterAvatar)
                                      : null,
                                  child: commenterAvatar.isEmpty
                                      ? Text(commenterName.isEmpty ? 'م' : commenterName.characters.first,
                                          style: const TextStyle(color: Color(0xFF80602B), fontWeight: FontWeight.w900))
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Transform.translate(
                                  offset: const Offset(0, -2),
                                  child: Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 6,
                                    children: [
                                      InkWell(
                                        onTap: () => _openUserProfile(c),
                                        child: Text(commenterName, style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 13)),
                                      ),
                                      if ((c['userId'] ?? c['user_id'] ?? '').toString().isNotEmpty &&
                                          (c['userId'] ?? c['user_id']).toString() ==
                                              (post['userId'] ?? post['user_id'] ?? '').toString())
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFE7A8),
                                            border: Border.all(color: const Color(0xFFD6A642), width: 0.8),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text('كاتب المنشور',
                                            style: TextStyle(color: Color(0xFF79520B), fontSize: 9, fontWeight: FontWeight.w900)),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                InkWell(
                                  onTap: () => openCommentActions(c),
                                  child: Text((c['content'] ?? '').toString(), style: const TextStyle(color: Color(0xFF000000), fontWeight: FontWeight.w700, fontSize: 13, height: 1.5)),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Transform.translate(
                                      offset: const Offset(4, 0),
                                      child: Text(_timeAgo(c['createdAt'] ?? c['created_at']),
                                          style: const TextStyle(color: _muted, fontSize: 10)),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        replyingTo = c;
                                        input.clear();
                                        setSheetState(() {});
                                      },
                                      style: TextButton.styleFrom(
                                        foregroundColor: _gold,
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text('رد', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                                    ),
                                  ],
                                ),
                                repliesSection(),
                              ])),
                            ]);
                          },
                        )),
                if (error != null && comments.isNotEmpty)
                  Align(alignment: Alignment.centerRight, child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 11))),
                if (replyingTo != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Expanded(child: Text('الرد على ${replyingTo!['name'] ?? 'مستخدم'}',
                          style: const TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.w800))),
                      IconButton(
                        onPressed: () { replyingTo = null; input.clear(); setSheetState(() {}); },
                        icon: const Icon(Icons.close_rounded, size: 17, color: _muted),
                        visualDensity: VisualDensity.compact,
                      ),
                    ]),
                  ),
                Row(children: [
                  Expanded(child: TextField(
                    controller: input,
                    maxLength: 500,
                    style: const TextStyle(color: _ink, fontSize: 13),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: replyingTo == null ? 'اكتب تعليقاً...' : 'رد ${(replyingTo?['name'] ?? replyingTo?['displayName'] ?? 'مستخدم').toString()}',
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
    if (diff.inHours < 1) return 'قبل ${diff.inMinutes} د';
    if (diff.inDays < 1) return 'قبل ${diff.inHours} س';
    return 'قبل ${diff.inDays} يوم';
  }

  @override
  Widget build(BuildContext context) {
    final modePosts = _feedMode == 'mine'
        ? _posts.where((post) => post['isMine'] == true).toList()
        : _posts;
    final visiblePosts = _feedFilter == 'following'
        ? modePosts.where((post) => post['followed'] == true || post['isMine'] == true).toList()
        : modePosts;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF7EBCB), Color(0xFFFAF6EA), Color(0xFFF6F7FB)],
                stops: [0.0, 0.3, 0.55],
                ),
              ),
              child: RefreshIndicator(
                color: _gold,
                onRefresh: _loadPosts,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(15, 14, 15, 100),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'المنشورات',
                                style: TextStyle(color: _ink, fontSize: 24, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'شارك لحظاتك مع مجتمع Happy Live',
                                style: TextStyle(color: _muted, fontSize: 11),
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
                            border: Border.all(color: const Color(0xFFE8D8B5)),
                          ),
                          child: const Icon(Icons.auto_awesome_rounded, color: _gold, size: 21),
                        ),
                      ],
                    ),
                    const SizedBox(height: 17),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE5D4),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        children: [
                          _feedTab('يومي', 'daily'),
                          _feedTab('خاص بي', 'mine'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _feedFilterChip('الكل', 'all'),
                        const SizedBox(width: 8),
                        _feedFilterChip('المتابعة', 'following'),
                      ],
                    ),
                    const SizedBox(height: 15),
                    if (_loading && _posts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(35),
                        child: Center(child: CircularProgressIndicator(color: _gold)),
                      )
                    else if (_error != null && _posts.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                        child: Column(
                          children: [
                            const Icon(Icons.cloud_off_rounded, color: _gold, size: 32),
                            const SizedBox(height: 9),
                            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 12)),
                            TextButton(onPressed: _loadPosts, child: const Text('إعادة المحاولة', style: TextStyle(color: _gold, fontWeight: FontWeight.w800))),
                          ],
                        ),
                      )
                    else if (visiblePosts.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(19),
                          border: Border.all(color: const Color(0xFFE9DFC9)),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _feedMode == 'mine' ? Icons.person_outline_rounded : Icons.forum_outlined,
                              color: _gold,
                              size: 38,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _feedMode == 'mine'
                                  ? 'لا توجد منشورات لك بعد'
                                  : _feedFilter == 'following'
                                      ? 'لا توجد منشورات من الحسابات التي تتابعها'
                                      : 'لا توجد منشورات بعد',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'كن أول من يشارك لحظة مع مجتمع Happy Live',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    else
                      ...List.generate(visiblePosts.length, (index) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _postCard(visiblePosts[index]),
                          if (index < visiblePosts.length - 1)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Divider(height: 1, thickness: 1, color: Color(0xFFE9DFC9)),
                            ),
                        ],
                      )),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 17,
            bottom: 19,
            child: SizedBox(
              width: 54,
              height: 54,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE8C36D), _gold],
                  ),
                  boxShadow: [
                    BoxShadow(color: _gold.withOpacity(0.28), blurRadius: 13, spreadRadius: 1),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _openCreatePost,
                    child: const Center(child: Icon(Icons.edit_rounded, color: Colors.white, size: 25)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feedTab(String label, String value) {
    final selected = _feedMode == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _feedMode = value;
          _feedFilter = 'all';
        }),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? const [BoxShadow(color: Color(0x10000000), blurRadius: 7, offset: Offset(0, 2))]
                : const [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? _ink : _muted,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _feedFilterChip(String label, String value) {
    final selected = _feedFilter == value;
    return InkWell(
      onTap: () => setState(() => _feedFilter = value),
      borderRadius: BorderRadius.circular(30),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _gold : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: selected ? _gold : const Color(0xFFE7DDC9)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _ink,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  void _openUserProfile(Map<String, dynamic> post) {
    final userId = (post['userId'] ?? '').toString();
    if (userId.isEmpty) return;
    final userPosts = _posts.where((item) => (item['userId'] ?? '').toString() == userId).toList();
    Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => PublicProfilePage(
        name: (post['name'] ?? 'مستخدم').toString(),
        userId: userId,
        accessToken: widget.accessToken,
        userCode: (post['userCode'] ?? '').toString(),
        photoUrl: (post['avatarUrl'] ?? '').toString().trim().isEmpty
            ? null
            : post['avatarUrl'].toString(),
        bio: (post['bio'] ?? '').toString(),
        posts: userPosts,
      ),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: const Offset(0, 0),
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    ));
  }

  Widget _postAuthorAvatar(Map<String, dynamic> post, String name) {
    final url = (post['avatarUrl'] ?? '').toString().trim();
    return InkWell(
      onTap: () => _openUserProfile(post),
      customBorder: const CircleBorder(),
      child: Container(
        width: 42,
        height: 42,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [Color(0xFFF6E4B9), Color(0xFFEAD09A)]),
        ),
        child: ClipOval(
          child: url.isEmpty
              ? Center(child: Text(name.isEmpty ? 'م' : name.characters.first,
                  style: const TextStyle(color: Color(0xFF80602B), fontWeight: FontWeight.w900, fontSize: 16)))
              : Image.network(url, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(child: Text(name.isEmpty ? 'م' : name.characters.first,
                    style: const TextStyle(color: Color(0xFF80602B), fontWeight: FontWeight.w900, fontSize: 16)))),
        ),
      ),
    );
  }

  Widget _postCard(Map<String, dynamic> post) {
    final name = (post['name'] ?? 'مستخدم').toString();
    final mine = post['isMine'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _postAuthorAvatar(post, name),
          const SizedBox(width: 10),
          Expanded(child: InkWell(
            onTap: () => _openUserProfile(post),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(_timeAgo(post['createdAt']), style: const TextStyle(color: _muted, fontSize: 10)),
          ]))),
          if (!mine)
            TextButton(
              onPressed: () => _toggleFollow(post),
              style: TextButton.styleFrom(foregroundColor: _gold, visualDensity: VisualDensity.compact),
              child: Text(post['followed'] == true ? 'تتابعه' : 'متابعة', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          IconButton(tooltip: 'المزيد', visualDensity: VisualDensity.compact, constraints: const BoxConstraints(minWidth: 34, minHeight: 34), padding: EdgeInsets.zero, onPressed: () => _openPostActions(post), icon: const Icon(Icons.more_horiz_rounded, color: _muted, size: 23)),
        ]),
        const SizedBox(height: 13),
        Text((post['content'] ?? '').toString(), textDirection: TextDirection.rtl, style: const TextStyle(color: _ink, fontSize: 14, height: 1.7)),
        if ((post['imageUrl'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 10),
          Center(child: _PostImage(url: post['imageUrl'].toString())),
        ],
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


class _PostImage extends StatefulWidget {
  const _PostImage({required this.url});

  final String url;

  @override
  State<_PostImage> createState() => _PostImageState();
}

class _PostImageState extends State<_PostImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _sourceWidth;
  double? _sourceHeight;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant _PostImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _sourceWidth = null;
      _sourceHeight = null;
      _failed = false;
      _resolveImage();
    }
  }

  void _resolveImage() {
    final provider = NetworkImage(widget.url);
    final nextStream = provider.resolve(createLocalImageConfiguration(context));
    if (_stream?.key == nextStream.key) return;
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = nextStream;
    _listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        if (!mounted) return;
        setState(() {
          _sourceWidth = info.image.width.toDouble();
          _sourceHeight = info.image.height.toDouble();
          _failed = false;
        });
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const SizedBox(
        width: 190,
        height: 120,
        child: Center(child: Icon(Icons.broken_image_outlined)),
      );
    }

    final sourceWidth = _sourceWidth;
    final sourceHeight = _sourceHeight;
    double boxWidth = 190;
    double boxHeight = 230;

    if (sourceWidth != null && sourceHeight != null && sourceWidth > 0) {
      final heightRatio = sourceHeight / sourceWidth;
      if (heightRatio > 1.6) {
        boxWidth = 175;
        boxHeight = (175 * heightRatio).clamp(380.0, 420.0).toDouble();
      } else if (heightRatio >= 0.9 && heightRatio <= 1.05) {
        boxWidth = 210;
        boxHeight = 210;
      } else if (heightRatio > 1.05) {
        boxWidth = 190;
        boxHeight = 230;
      } else {
        boxWidth = 210;
        boxHeight = (210 * heightRatio).clamp(100.0, 230.0).toDouble();
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: boxWidth.clamp(0.0, 240.0).toDouble(),
        height: boxHeight.clamp(0.0, 420.0).toDouble(),
        child: Image.network(
          widget.url,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    );
  }
}

class CustomConfirmDialog extends StatelessWidget {
  const CustomConfirmDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.confirmText,
    required this.onConfirm,
  });

  final String title;
  final String? subtitle;
  final String confirmText;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 20,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  textDirection: TextDirection.ltr,
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onConfirm();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00D1C1),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                          child: Text(
                            confirmText,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF5F5F7),
                            foregroundColor: const Color(0xFF8E8E93),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                          child: const Text(
                            'الغاء',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreatePostPage extends StatefulWidget {
  const _CreatePostPage({required this.name, required this.accessToken, required this.onPublish});
  final String name;
  final String accessToken;
  final Future<String?> Function(String content, String? imageUrl) onPublish;
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
  final ImagePicker _imagePicker = ImagePicker();
  Uint8List? _selectedImageBytes;

  Future<String> _uploadPostImage() async {
    final bytes = _selectedImageBytes;
    if (bytes == null) throw Exception('اختر صورة أولاً');
    final authResponse = await http.get(
      Uri.parse('https://happy-live-api.taher616270.workers.dev/api/v1/imagekit/auth'),
      headers: {'Authorization': 'Bearer ${widget.accessToken}'},
    );
    if (authResponse.statusCode != 200) {
      throw Exception('خدمة رفع الصور غير مكتملة الإعداد. تحقق من مفاتيح ImageKit.');
    }
    final auth = jsonDecode(authResponse.body) as Map<String, dynamic>;
    final request = http.MultipartRequest('POST', Uri.parse('https://upload.imagekit.io/api/v1/files/upload'));
    request.fields.addAll({
      'publicKey': auth['publicKey'].toString(),
      'token': auth['token'].toString(),
      'expire': auth['expire'].toString(),
      'signature': auth['signature'].toString(),
      'fileName': 'happy-live-post-${DateTime.now().millisecondsSinceEpoch}.jpg',
      'useUniqueFileName': 'true',
      'folder': '/happy-live/posts',
    });
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'happy-live-post.jpg'));
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || data is! Map || data['url'] is! String) {
      throw Exception('تعذر رفع الصورة إلى مساحة التخزين');
    }
    return data['url'] as String;
  }

  Future<void> _pickPostImage() async {
    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _selectedImageBytes = bytes);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الصور. تحقق من صلاحية الوصول ثم حاول مرة أخرى.')),
      );
    }
  }

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
    if ((content.isEmpty && _selectedImageBytes == null) || _publishing) return;
    _focusNode.unfocus();
    setState(() => _publishing = true);
    try {
      final imageUrl = _selectedImageBytes == null ? null : await _uploadPostImage();
      final published = await widget.onPublish(content, imageUrl);
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

  Widget _toolButton({required Widget icon, required VoidCallback onTap, String? tooltip}) => IconButton(
    tooltip: tooltip, onPressed: onTap, visualDensity: VisualDensity.compact, splashRadius: 21,
    padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 34, height: 40), icon: icon,
  );

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
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
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 18, 0),
            child: Align(alignment: AlignmentDirectional.topStart, child: Container(
              width: 100, height: 130,
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: [
                Positioned.fill(
                  child: _selectedImageBytes == null
                      ? const Center(child: Icon(Icons.add_rounded, color: Color(0xFF9A9DA3), size: 34))
                      : Image.memory(_selectedImageBytes!, fit: BoxFit.cover),
                ),
                Positioned.fill(
                  child: Material(color: Colors.transparent, child: InkWell(
                    onTap: _pickPostImage,
                    child: _selectedImageBytes == null
                        ? const SizedBox.expand()
                        : Align(alignment: AlignmentDirectional.topEnd, child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: Container(
                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.edit_rounded, color: Colors.white, size: 19),
                            ),
                          )),
                  )),
                ),
                if (_selectedImageBytes != null)
                  PositionedDirectional(
                    top: 5, start: 5,
                    child: InkWell(
                      onTap: () => setState(() => _selectedImageBytes = null),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 17),
                      ),
                    ),
                  ),
              ]),
            )),
          ),
          SizedBox(height: 46, child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEDEDED), width: 1),
            ),
            child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              _toolButton(tooltip: 'وسم', onTap: () {}, icon: const Text('#', style: TextStyle(fontSize: 23, color: Color(0xFF555A61)))),
              _toolButton(
                tooltip: _emojiPanelOpen ? 'لوحة المفاتيح' : 'الإيموجي',
                onTap: _toggleEmojiPanel,
                icon: Icon(_emojiPanelOpen ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined, color: const Color(0xFF555A61), size: 22),
              ),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _showVisibilitySheet,
                  borderRadius: BorderRadius.circular(100),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5E6C8),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: const Color(0xFFD4A017), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_outline_rounded, size: 18, color: Color(0xFFD4A017)),
                          const SizedBox(width: 6),
                          Text(_visibility, style: const TextStyle(fontSize: 14, color: Color(0xFF3B3428), fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_back_ios_rounded, size: 14, color: Color(0xFFD4A017)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          )),
          ),
          if (_emojiPanelOpen) SizedBox(
            height: 258,
            width: double.infinity,
            child: EmojiPicker(
              onEmojiSelected: (category, emoji) {},
              textEditingController: _controller,
              config: Config(
                height: 258,
                checkPlatformCompatibility: true,
                emojiViewConfig: const EmojiViewConfig(
                  columns: 8,
                  emojiSizeMax: 25,
                  backgroundColor: Color(0xFFFFFBEB),
                ),
              ),
            ),
          ),
        ])),
      ),
    );
  }
}
