import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class RoomSeatSocket {
  RoomSeatSocket({
    required this.apiBase,
    required this.roomId,
    required this.accessToken,
    required this.onEvent,
    this.onConnectionChanged,
  });

  final String apiBase;
  final String roomId;
  final String accessToken;
  final void Function(Map<String, dynamic>) onEvent;
  final void Function(bool connected)? onConnectionChanged;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _reconnect;
  bool _disposed = false;
  bool _connecting = false;
  bool _connected = false;
  int _reconnectAttempt = 0;

  bool get isConnected => _connected;

  Uri get _uri {
    final base = Uri.parse(apiBase);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path}/rooms/${Uri.encodeComponent(roomId)}/seat-stream',
      query: null,
      fragment: null,
    );
  }

  Future<void> connect() async {
    if (_disposed || _connecting || _connected || roomId.isEmpty || accessToken.isEmpty) return;
    _connecting = true;
    WebSocketChannel? candidate;
    try {
      candidate = WebSocketChannel.connect(
        _uri,
        protocols: <String>['happy-live-seats', accessToken],
      );
      _channel = candidate;
      _subscription = candidate.stream.listen(
        _onData,
        onError: (_) => _onClosed(candidate!),
        onDone: () => _onClosed(candidate!),
        cancelOnError: true,
      );
      await candidate.ready.timeout(const Duration(seconds: 8));
      if (_disposed || !identical(_channel, candidate)) return;
      _connected = true;
      _reconnectAttempt = 0;
      _reconnect?.cancel();
      _reconnect = null;
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
        send(<String, dynamic>{'type': 'seat_heartbeat'});
      });
      onConnectionChanged?.call(true);
    } catch (_) {
      if (candidate != null && identical(_channel, candidate)) {
        _channel = null;
        await _subscription?.cancel();
        _subscription = null;
        try { await candidate.sink.close(); } catch (_) {}
      }
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void sendMove({required int? from, required int to, required int version}) {
    send(<String, dynamic>{
      'type': 'move_seat',
      'from': from,
      'to': to,
      'version': version,
    });
  }

  void send(Map<String, dynamic> message) {
    if (!_connected || _channel == null) {
      onEvent(<String, dynamic>{'type': 'socket_unavailable'});
      return;
    }
    try {
      _channel!.sink.add(jsonEncode(message));
    } catch (_) {
      _handleClosed();
    }
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) onEvent(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // Ignore malformed frames; the next snapshot reconciles the client.
    }
  }

  void _onClosed(WebSocketChannel channel) {
    if (!identical(_channel, channel)) return;
    _handleClosed();
  }

  void _handleClosed() {
    if (_disposed) return;
    _connected = false;
    _channel = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    onConnectionChanged?.call(false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || (_reconnect?.isActive ?? false)) return;
    const delays = <int>[1, 2, 3, 5, 8, 13, 20];
    final index = _reconnectAttempt.clamp(0, delays.length - 1) as int;
    final seconds = delays[index];
    _reconnectAttempt++;
    _reconnect = Timer(Duration(seconds: seconds), () {
      _reconnect = null;
      connect();
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnect?.cancel();
    _heartbeat?.cancel();
    await _subscription?.cancel();
    try { await _channel?.sink.close(); } catch (_) {}
    _channel = null;
    _connected = false;
    onConnectionChanged?.call(false);
  }
}
