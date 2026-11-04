class Message {
  const Message({
    required this.id,
    required this.type,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String text;
  final DateTime createdAt;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: (json['id'] ?? '').toString(),
        type: (json['type'] ?? 'text').toString(),
        senderId: (json['senderId'] ?? '').toString(),
        senderName: (json['senderName'] ?? '').toString(),
        senderAvatar: (json['senderAvatar'] ?? '').toString(),
        text: (json['text'] ?? '').toString(),
        createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'senderId': senderId,
        'senderName': senderName,
        'senderAvatar': senderAvatar,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };
}
