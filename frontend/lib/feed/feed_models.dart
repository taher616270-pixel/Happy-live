class FeedVideo {
  final String id, url, authorName, authorAvatar, caption, sound;
  final String? template, repostLabel;
  int likes, comments, saves, shares;
  bool liked, saved, following;

  /// Images are stored in the same media URL field as videos. Detect their
  /// actual file extension from the URL path (ignoring query parameters).
  bool get isImage {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return const {
      '.jpg', '.jpeg', '.png', '.webp', '.gif', '.avif', '.bmp'
    }.any(path.endsWith);
  }

  FeedVideo({
    required this.id,
    required this.url,
    this.authorName = '',
    this.authorAvatar = '',
    this.caption = '',
    this.sound = '',
    this.template,
    this.repostLabel,
    this.likes = 0,
    this.comments = 0,
    this.saves = 0,
    this.shares = 0,
    this.liked = false,
    this.saved = false,
    this.following = false,
  });
}

class FeedComment {
  final String id, user, avatar, text, time;
  int likes;
  bool liked;
  FeedComment({
    required this.id,
    required this.user,
    this.avatar = '',
    required this.text,
    this.time = 'الآن',
    this.likes = 0,
    this.liked = false,
  });
}

class FeedFriend {
  final String id, name, avatar;
  final int streak;
  const FeedFriend({
    required this.id,
    required this.name,
    this.avatar = '',
    this.streak = 0,
  });
}

String fmtCount(int n) {
  String trim(double v) =>
      v.toStringAsFixed(1).replaceFirst(RegExp(r'\\.0$'), '');
  if (n < 10000) return '$n';
  if (n < 1000000) return '${trim(n / 1000)} ألف';
  return '${trim(n / 1000000)} مليون';
}
