import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class GlobalGiftEvents {
  GlobalGiftEvents._();

  static final GlobalGiftEvents instance = GlobalGiftEvents._();
  static const String _apiBase = 'https://happy-live-api.taher616270.workers.dev/api/v1';

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  String? _token;
  bool _disposed = false;

  Stream<Map<String, dynamic>> get events => _events.stream;

  void connect(String accessToken) {
    final token = accessToken.trim();
    if (token.isEmpty || _disposed) return;
    if (_token == token && _channel != null) return;
    disconnect();
    _token = token;
    _open();
  }

  void _open() {
    final token = _token;
    if (token == null || token.isEmpty || _disposed) return;
    try {
      final base = Uri.parse(_apiBase);
      final uri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '${base.path}/gifts/global-stream',
        query: null,
        fragment: null,
      );
      final channel = WebSocketChannel.connect(
        uri,
        protocols: <String>['happy-live-gifts', token],
      );
      _channel = channel;
      _subscription = channel.stream.listen(
        (raw) {
          try {
            final decoded = jsonDecode(raw.toString());
            if (decoded is Map<String, dynamic> &&
                decoded['type'] == 'global_gift_banner') {
              _events.add(decoded);
            }
          } catch (error) {
            debugPrint('[GlobalGiftEvents] invalid event: $error');
          }
        },
        onError: (Object error) {
          debugPrint('[GlobalGiftEvents] socket error: $error');
          _scheduleReconnect();
        },
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (error) {
      debugPrint('[GlobalGiftEvents] connect failed: $error');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _channel = null;
    _subscription = null;
    if (_token == null || _disposed || _reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _reconnectTimer = null;
      _open();
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _token = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(channel.sink.close());
  }
}
