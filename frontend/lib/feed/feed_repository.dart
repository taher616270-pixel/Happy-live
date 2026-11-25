import 'dart:convert';
import 'package:http/http.dart' as http;
import 'feed_models.dart';

enum FeedTab { forYou, following, community }

class FeedConfig {
  static const String apiBase = 'https://happy-live-api.taher616270.workers.dev';
  static const String shareBase = 'https://happy-live.pages.dev';
  static String Function() userId = () => '';
  static String Function() authToken = () => '';
  static String Function() myAvatar = () => '';
}

abstract class FeedRepository {
  Future<List<FeedVideo>> feed(FeedTab tab, {int page = 0});
  Future<void> setLike(String id, bool value);
  Future<void> setSave(String id, bool value);
  Future<void> follow(String id);
  Future<void> addShare(String id);
  Future<List<FeedComment>> comments(String videoId);
  Future<FeedComment> addComment(String videoId, String text);
  Future<void> likeComment(String id, bool value);
  Future<List<FeedFriend>> friends();
  Future<void> sendToFriend(String videoId, String friendId);
  Future<List<FeedVideo>> search(String query);
}

class HttpFeedRepository implements FeedRepository {
  final http.Client _client;
  HttpFeedRepository({http.Client? client}) : _client = client ?? http.Client();

  Map<String,String> get _headers => {
    'Authorization': 'Bearer ${FeedConfig.authToken()}',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
  Uri _uri(String path, [Map<String,String>? query]) =>
      Uri.parse('${FeedConfig.apiBase}/api/feed$path').replace(queryParameters: query);
  Future<Map<String,dynamic>> _get(String path, [Map<String,String>? query]) async {
    final r = await _client.get(_uri(path, query), headers: _headers).timeout(const Duration(seconds: 20));
    return _decode(r);
  }
  Future<Map<String,dynamic>> _post(String path, Map<String,dynamic> body) async {
    final r = await _client.post(_uri(path), headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
    return _decode(r);
  }
  Map<String,dynamic> _decode(http.Response r) {
    dynamic value;
    try { value = jsonDecode(r.body); } catch (_) { throw Exception('استجابة غير صالحة من الخادم'); }
    if (r.statusCode < 200 || r.statusCode >= 300 || value is! Map) {
      final message = value is Map ? (value['error'] ?? value['message'] ?? 'feed_request_failed') : 'feed_request_failed';
      throw Exception(message.toString());
    }
    final map = Map<String,dynamic>.from(value);
    if (map['ok'] == false) throw Exception((map['error'] ?? 'feed_request_failed').toString());
    return map;
  }
  List<dynamic> _list(Map<String,dynamic> m, String key) => m[key] is List ? m[key] as List : const [];
  FeedVideo _video(dynamic raw) {
    final m = Map<String,dynamic>.from(raw as Map);
    return FeedVideo(
      id: (m['id'] ?? '').toString(), url: (m['url'] ?? m['video_url'] ?? '').toString(),
      authorName: (m['authorName'] ?? m['author_name'] ?? '').toString(),
      authorAvatar: (m['authorAvatar'] ?? m['author_avatar'] ?? '').toString(),
      caption: (m['caption'] ?? '').toString(), sound: (m['sound'] ?? '').toString(),
      template: m['template']?.toString(), repostLabel: m['repostLabel']?.toString(),
      likes: (m['likes'] as num?)?.toInt() ?? 0, comments: (m['comments'] as num?)?.toInt() ?? 0,
      saves: (m['saves'] as num?)?.toInt() ?? 0, shares: (m['shares'] as num?)?.toInt() ?? 0,
      liked: m['liked'] == true, saved: m['saved'] == true, following: m['following'] == true,
    );
  }
  @override Future<List<FeedVideo>> feed(FeedTab tab, {int page = 0}) async {
    final m = await _get('', {'tab': tab.name, 'page': '$page'});
    return _list(m, 'videos').map(_video).toList();
  }
  @override Future<void> setLike(String id, bool value) async { await _post('/like', {'video_id':id,'liked':value}); }
  @override Future<void> setSave(String id, bool value) async { await _post('/save', {'video_id':id,'saved':value}); }
  @override Future<void> follow(String id) async { await _post('/follow', {'video_id':id}); }
  @override Future<void> addShare(String id) async { await _post('/share', {'video_id':id}); }
  @override Future<List<FeedComment>> comments(String id) async {
    final m = await _get('/comments', {'video_id':id});
    return _list(m,'comments').map((x) {
      final v = Map<String,dynamic>.from(x as Map);
      return FeedComment(id:'${v['id']}', user:'${v['user'] ?? ''}', avatar:'${v['avatar'] ?? ''}',
        text:'${v['text'] ?? ''}', time:'${v['time'] ?? 'الآن'}',
        likes:(v['likes'] as num?)?.toInt() ?? 0, liked:v['liked'] == true);
    }).toList();
  }
  @override Future<FeedComment> addComment(String id, String text) async {
    final m = await _post('/comments', {'video_id':id,'text':text});
    final v = Map<String,dynamic>.from(m['comment'] as Map);
    return FeedComment(id:'${v['id']}', user:'${v['user'] ?? ''}', avatar:'${v['avatar'] ?? ''}',
      text:'${v['text'] ?? text}', time:'الآن', likes:0, liked:false);
  }
  @override Future<void> likeComment(String id, bool value) async { await _post('/comment-like', {'comment_id':id,'liked':value}); }
  @override Future<List<FeedFriend>> friends() async {
    final m = await _get('/friends');
    return _list(m,'friends').map((x) {
      final v = Map<String,dynamic>.from(x as Map);
      return FeedFriend(id:'${v['id']}',name:'${v['name'] ?? ''}',avatar:'${v['avatar'] ?? ''}',streak:(v['streak'] as num?)?.toInt() ?? 0);
    }).toList();
  }
  @override Future<void> sendToFriend(String videoId, String friendId) async { await _post('/send', {'video_id':videoId,'friend_id':friendId}); }
  @override Future<List<FeedVideo>> search(String q) async {
    final m = await _get('/search', {'q':q});
    return _list(m,'videos').map(_video).toList();
  }
}
