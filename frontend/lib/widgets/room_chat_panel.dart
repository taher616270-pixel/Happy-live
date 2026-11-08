import 'package:flutter/material.dart';

enum MsgType { system, join, user }

class ChatMessage {
  final MsgType type;
  final String sender;
  final String text;
  final String? avatarUrl;
  final int? loveLevel;
  final int? moonLevel;
  final String? vipLabel;
  const ChatMessage({
    required this.type,
    required this.sender,
    required this.text,
    this.avatarUrl,
    this.loveLevel,
    this.moonLevel,
    this.vipLabel,
  });
}

/// قسم الرسايل: نفس الودجت يظهر صغير داخل الغرفة، ولما expanded=true
/// يرتفع ويغطي الشاشة كلها مع شريط الكتابة فوق الكيبورد.
class RoomChatPanel extends StatefulWidget {
  final bool expanded;
  final VoidCallback onCollapse;
  final List<ChatMessage> messages;
  final void Function(String text) onSend;

  const RoomChatPanel({
    super.key,
    required this.expanded,
    required this.onCollapse,
    required this.messages,
    required this.onSend,
  });

  @override
  State<RoomChatPanel> createState() => _RoomChatPanelState();
}

class _RoomChatPanelState extends State<RoomChatPanel> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText && mounted) setState(() => _hasText = has);
    });
  }

  @override
  void didUpdateWidget(covariant RoomChatPanel old) {
    super.didUpdateWidget(old);
    // الكيبورد ما يطلع تلقائي، يطلع لما تضغط على حقل الكتابة
    if (!widget.expanded && old.expanded) {
      _focus.unfocus();
    }
    if (widget.messages.length != old.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    widget.onSend(t);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final topSafe = MediaQuery.of(context).padding.top;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.expanded ? widget.onCollapse : null,
              child: ListView.separated(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                    12, widget.expanded ? topSafe + 16 : 4, 12, 8),
                itemCount: widget.messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _bubble(widget.messages[i]),
                ),
              ),
            ),
          ),
          if (widget.expanded) _inputBar(),
        ],
      ),
    );
  }

  // ---------- الفقاعات ----------
  Widget _bubble(ChatMessage m) {
    switch (m.type) {
      case MsgType.system:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: _bg(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${m.sender}:',
                  style:
                      const TextStyle(color: Color(0xFF4CAF50), fontSize: 18)),
              const SizedBox(height: 8),
              Text(m.text,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 17, height: 1.5)),
            ],
          ),
        );
      case MsgType.join:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: _bg(),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              _badge(const [Color(0xFFB03CFF), Color(0xFF7A2CFF)],
                  Icons.person_add_alt_1),
              if (m.moonLevel != null)
                _badge(const [Color(0xFF4DA3FF), Color(0xFF3B7BEB)],
                    Icons.nightlight_round,
                    text: '${m.moonLevel}'),
              if (m.loveLevel != null)
                _badge(const [Color(0xFFFF9A3C), Color(0xFFE5732A)],
                    Icons.favorite,
                    text: '${m.loveLevel}'),
              Text(m.sender,
                  style: const TextStyle(
                      color: Color(0xFF4FD1C5), fontSize: 16)),
              Text(m.text,
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        );
      case MsgType.user:
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              backgroundImage:
                  m.avatarUrl != null ? NetworkImage(m.avatarUrl!) : null,
              child: m.avatarUrl == null
                  ? const Icon(Icons.person, color: Colors.white70, size: 20)
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(m.sender,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14)),
                      if (m.vipLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: const Color(0xFF8BC34A)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(m.vipLabel!,
                              style: const TextStyle(
                                  color: Color(0xFF8BC34A),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      if (m.moonLevel != null)
                        _badge(const [Color(0xFF4DA3FF), Color(0xFF3B7BEB)],
                            Icons.nightlight_round,
                            text: '${m.moonLevel}'),
                      if (m.loveLevel != null)
                        _badge(const [Color(0xFFFF9A3C), Color(0xFFE5732A)],
                            Icons.favorite,
                            text: '${m.loveLevel}'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // فقاعة ذهبية مثل الفيديو
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2B2A12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFC9B24A), width: 1.5),
                    ),
                    child: Text(m.text,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15)),
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }

  BoxDecoration _bg() => BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(18),
      );

  Widget _badge(List<Color> gradient, IconData icon, {String? text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (text != null)
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        if (text != null) const SizedBox(width: 3),
        Icon(icon, color: Colors.white, size: 14),
      ]),
    );
  }

  // ---------- شريط الكتابة ----------
  Widget _inputBar() {
    return Container(
      color: const Color(0xFF1B1A22),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () {/* TODO: رفع صورة عبر ImageKit */},
            icon: const Icon(Icons.image_outlined,
                color: Colors.white70, size: 30),
          ),
          Expanded(
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.07),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.text_fields,
                        color: Colors.white70, size: 28),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      cursorColor: const Color(0xFFE040FB),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 17),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'قل شيئًا',
                        hintStyle:
                            TextStyle(color: Colors.white38, fontSize: 17),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.face_retouching_natural,
                        color: Colors.white70, size: 28),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 64,
              height: 50,
              decoration: BoxDecoration(
                color: _hasText
                    ? const Color(0xFF8E2DE2)
                    : Colors.white.withOpacity(.07),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Icon(Icons.send_outlined,
                  color: _hasText ? Colors.white : Colors.white30, size: 26),
            ),
          ),
        ],
      ),
    );
  }
}
