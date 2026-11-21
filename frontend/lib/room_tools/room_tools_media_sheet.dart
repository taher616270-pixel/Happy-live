import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

Future<void> showRoomToolsMediaSheet(
  BuildContext context, {
  required bool music,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RoomToolsMediaSheet(music: music),
  );
}

class _RoomToolsMediaSheet extends StatefulWidget {
  const _RoomToolsMediaSheet({required this.music});
  final bool music;

  @override
  State<_RoomToolsMediaSheet> createState() => _RoomToolsMediaSheetState();
}

class _RoomToolsMediaSheetState extends State<_RoomToolsMediaSheet> {
  final AudioPlayer _player = AudioPlayer();
  Uint8List? _bytes;
  String? _fileName;
  PlayerState _state = PlayerState.stopped;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.setReleaseMode(widget.music ? ReleaseMode.loop : ReleaseMode.stop);
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp3', 'm4a', 'wav', 'ogg'],
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('تعذر قراءة الملف المحدد');
      }
      if (bytes.length > 15 * 1024 * 1024) {
        throw Exception('الحد الأقصى لحجم الصوت 15 ميجابايت');
      }
      await _player.stop();
      _bytes = bytes;
      _fileName = file.name;
      await _player.play(BytesSource(bytes));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play() async {
    final bytes = _bytes;
    if (bytes == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _player.play(BytesSource(bytes));
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تشغيل الملف الصوتي');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePlayback() async {
    if (_busy) return;
    if (_state == PlayerState.playing && widget.music) {
      await _player.pause();
      return;
    }
    if (_bytes == null) {
      await _pickFile();
      return;
    }
    if (_state == PlayerState.paused && widget.music) {
      await _player.resume();
      return;
    }
    await _play();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.music ? 'موسيقى الغرفة' : 'مؤثر صوتي';
    final playing = _state == PlayerState.playing;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: EdgeInsets.fromLTRB(18, 14, 18, MediaQuery.paddingOf(context).bottom + 18),
        decoration: const BoxDecoration(
          color: Color(0xFF21152F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(8))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white70)),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Icon(widget.music ? Icons.music_note_rounded : Icons.graphic_eq_rounded, color: const Color(0xFFE8C477), size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _fileName ?? 'اختر ملف MP3 أو M4A أو WAV أو OGG',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pickFile,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('اختيار ملف'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _togglePlayback,
                      icon: Icon(playing && widget.music ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      label: Text(_busy ? 'جارٍ التشغيل…' : playing && widget.music ? 'إيقاف مؤقت' : 'تشغيل'),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE8C477), foregroundColor: const Color(0xFF21152F)),
                    ),
                  ),
                ],
              ),
              if (widget.music && _bytes != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : () => _player.stop(),
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('إيقاف الموسيقى'),
                  ),
                ),
              ],
              if (_error != null) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 12)),
              ),
              const SizedBox(height: 10),
              const Text(
                'تنبيه: التشغيل الحالي محلي على جهازك فقط، ولا يتم بث الملف إلى بقية مستمعي الغرفة.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFB9A9DC), fontSize: 11, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
