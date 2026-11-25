import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// Gallery-only composer for photos and videos in the short-video feed.
class FeedCreateCameraPage extends StatefulWidget {
  const FeedCreateCameraPage({
    super.key,
    required this.initialFile,
    required this.accessToken,
  });

  final XFile initialFile;
  final String accessToken;

  @override
  State<FeedCreateCameraPage> createState() => _FeedCreateCameraPageState();
}

class _FeedCreateCameraPageState extends State<FeedCreateCameraPage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _caption = TextEditingController();
  XFile? _selected;
  Uint8List? _mediaBytes;
  VideoPlayerController? _video;
  bool _selectedIsVideo = false;
  bool _busy = false;
  String? _error;

  static const _api = 'https://happy-live-api.taher616270.workers.dev';

  @override
  void initState() {
    super.initState();
    _loadFile(widget.initialFile);
  }

  @override
  void dispose() {
    _caption.dispose();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _chooseFromGallery() async {
    if (_busy) return;
    try {
      final file = await _picker.pickMedia();
      if (!mounted || file == null) return;
      await _loadFile(file);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر فتح المعرض. حاول مرة أخرى.');
    }
  }

  String _sniffVideoExtension(Uint8List bytes) {
    // Some iOS/Safari pickers report a generic or incorrect MIME type.
    // Inspect container signatures as a final reliable video check.
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
      final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
      return brand.startsWith('qt') ? 'mov' : 'mp4';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x1A && bytes[1] == 0x45 &&
        bytes[2] == 0xDF && bytes[3] == 0xA3) {
      return 'webm';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x4F && bytes[1] == 0x67 &&
        bytes[2] == 0x67 && bytes[3] == 0x53) {
      return 'ogg';
    }
    if (bytes.length >= 4 && bytes[0] == 0 && bytes[1] == 0 &&
        bytes[2] == 1 && (bytes[3] == 0xB3 || bytes[3] == 0xBA)) {
      return 'mpeg';
    }
    return '';
  }

  Future<void> _loadFile(XFile file) async {
    if (!mounted) return;
    setState(() { _busy = true; _error = null; });
    VideoPlayerController? video;
    try {
      final mime = (file.mimeType ?? '').toLowerCase();
      final path = file.path.toLowerCase();
      final fileName = file.name.toLowerCase();
      // Safari/iOS may return a blob: path without the original extension.
      // Always inspect XFile.name as well as MIME type and path, otherwise
      // selected MOV/MP4 videos can be mistaken for still images.
      const videoExtensions = [
        '.mp4', '.mov', '.m4v', '.webm', '.mpeg', '.mpg', '.3gp', '.ogv', '.ogg'
      ];
      final bytes = await file.readAsBytes();
      final sniffedExtension = _sniffVideoExtension(bytes);
      final isVideo = mime.startsWith('video/') ||
          sniffedExtension.isNotEmpty ||
          videoExtensions.any(fileName.endsWith) ||
          videoExtensions.any(path.endsWith);
      if (bytes.isEmpty) throw Exception('الملف فارغ.');
      if (bytes.length > 100 * 1024 * 1024) {
        throw Exception('حجم الملف يتجاوز الحد المسموح (100 ميجابايت).');
      }
      if (isVideo) {
        // Preview decoding is optional: iPhone videos may be HEVC/MOV and are
        // converted to browser-safe H.264 after upload by ImageKit.
        video = VideoPlayerController.networkUrl(Uri.parse(file.path));
        try {
          await video.initialize().timeout(const Duration(seconds: 12));
          await video.setLooping(true);
          await video.pause();
        } catch (_) {
          video.dispose();
          video = null;
        }
      }
      if (!mounted) { await video?.dispose(); return; }
      await _video?.dispose();
      setState(() {
        _selected = file;
        _selectedIsVideo = isVideo;
        _mediaBytes = bytes;
        _video = video;
      });
      video = null;
    } catch (error) {
      await video?.dispose();
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', 'تعذر تجهيز الملف: '));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      return value is Map<String, dynamic> ? value : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<String> _uploadMedia() async {
    final file = _selected;
    final bytes = _mediaBytes;
    if (file == null || bytes == null) throw Exception('اختر صورة أو فيديو أولاً.');
    if (widget.accessToken.isEmpty) throw Exception('انتهت جلسة الدخول. سجّل الدخول ثم حاول مجدداً.');

    final authResponse = await http.get(
      Uri.parse('$_api/api/v1/imagekit/auth'),
      headers: {'Authorization': 'Bearer ${widget.accessToken}', 'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 20));
    final auth = _decode(authResponse);
    if (authResponse.statusCode != 200 || auth['token'] == null ||
        auth['signature'] == null || auth['expire'] == null || auth['publicKey'] == null) {
      throw Exception((auth['message'] ?? auth['error'] ?? 'تعذر تجهيز خدمة رفع الملفات.').toString());
    }

    String extensionOf(String value) {
      final clean = value.split('?').first;
      final dot = clean.lastIndexOf('.');
      return dot < 0 ? '' : clean.substring(dot + 1).toLowerCase();
    }
    final nameExtension = extensionOf(file.name);
    final pathExtension = extensionOf(file.path);
    final declaredMime = (file.mimeType ?? '').toLowerCase();
    final sniffedExtension = _sniffVideoExtension(bytes);
    final mimeExtension = switch (declaredMime) {
      'video/mp4' => 'mp4',
      'video/quicktime' => 'mov',
      'video/x-m4v' => 'm4v',
      'video/webm' => 'webm',
      'video/3gpp' => '3gp',
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => '',
    };
    const videoExtensions = {'mp4', 'mov', 'm4v', 'webm', 'mpeg', 'mpg', '3gp', 'ogv', 'ogg'};
    const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'avif', 'bmp'};
    final extension = _selectedIsVideo
        ? (videoExtensions.contains(mimeExtension)
            ? mimeExtension
            : videoExtensions.contains(sniffedExtension)
                ? sniffedExtension
                : videoExtensions.contains(nameExtension)
                    ? nameExtension
                    : videoExtensions.contains(pathExtension)
                        ? pathExtension
                        : 'mp4')
        : (imageExtensions.contains(mimeExtension)
            ? mimeExtension
            : imageExtensions.contains(nameExtension)
                ? nameExtension
                : imageExtensions.contains(pathExtension)
                    ? pathExtension
                    : 'jpg');
    final uploadFileName = 'happy-live-feed-${DateTime.now().millisecondsSinceEpoch}.$extension';
    final request = http.MultipartRequest('POST', Uri.parse('https://upload.imagekit.io/api/v1/files/upload'));
    request.fields.addAll({
      'publicKey': auth['publicKey'].toString(),
      'token': auth['token'].toString(),
      'expire': auth['expire'].toString(),
      'signature': auth['signature'].toString(),
      'fileName': uploadFileName,
      'useUniqueFileName': 'true',
      'folder': '/happy-live/feed',
    });
    // Start generating the browser-safe H.264/AAC MP4 as soon as the
    // video is uploaded, rather than making the first viewer wait for encoding.
    if (_selectedIsVideo) {
      request.fields['transformation'] = jsonEncode({
        'post': [
          {'type': 'transformation', 'value': 'f-mp4,vc-h264,ac-aac'}
        ],
      });
    }
    final mediaMime = _selectedIsVideo
        ? switch (extension) {
            'mp4' || 'm4v' => 'video/mp4',
            'mov' => 'video/quicktime',
            'webm' => 'video/webm',
            '3gp' => 'video/3gpp',
            'mpeg' || 'mpg' => 'video/mpeg',
            'ogv' || 'ogg' => 'video/ogg',
            _ => 'video/mp4',
          }
        : (declaredMime.startsWith('image/')
            ? declaredMime
            : switch (extension) {
                'jpg' || 'jpeg' => 'image/jpeg',
                'png' => 'image/png',
                'gif' => 'image/gif',
                'webp' => 'image/webp',
                _ => 'application/octet-stream',
              });
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: uploadFileName,
      contentType: MediaType.parse(mediaMime),
    ));
    final streamed = await request.send().timeout(const Duration(minutes: 3));
    final response = await http.Response.fromStream(streamed);
    final uploaded = _decode(response);
    final mediaUrl = uploaded['url'];
    if (response.statusCode < 200 || response.statusCode >= 300 ||
        mediaUrl is! String || mediaUrl.isEmpty) {
      throw Exception((uploaded['message'] ?? uploaded['error'] ?? 'فشل رفع الملف إلى التخزين.').toString());
    }
    if (_selectedIsVideo) {
      final uploadedPath = Uri.tryParse(mediaUrl)?.path.toLowerCase() ?? mediaUrl.toLowerCase();
      if (!videoExtensions.any(uploadedPath.endsWith)) {
        throw Exception('تعذر تأكيد رفع الفيديو كفيديو. أعد اختيار ملف MP4 أو MOV.');
      }
    }
    return mediaUrl;
  }

  Future<void> _publish() async {
    if (_busy || _selected == null || _mediaBytes == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final mediaUrl = await _uploadMedia();
      final response = await http.post(
        Uri.parse('$_api/api/feed'),
        headers: {
          'Authorization': 'Bearer ${widget.accessToken}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'url': mediaUrl, 'caption': _caption.text.trim()}),
      ).timeout(const Duration(seconds: 30));
      final result = _decode(response);
      if (response.statusCode != 201 || result['ok'] != true) {
        throw Exception((result['message'] ?? result['error'] ?? 'تعذر نشر المنشور.').toString());
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected != null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('إنشاء منشور'),
          actions: [
            if (selected)
              IconButton(
                tooltip: 'اختيار ملف آخر',
                onPressed: _busy ? null : _chooseFromGallery,
                icon: const Icon(Icons.photo_library_outlined),
              ),
          ],
        ),
        body: SafeArea(
          child: selected
              ? Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: _selectedIsVideo
                            ? (_video?.value.isInitialized == true
                                ? AspectRatio(
                                    aspectRatio: _video!.value.aspectRatio,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        VideoPlayer(_video!),
                                        IconButton.filled(
                                          onPressed: _busy ? null : () {
                                            final controller = _video!;
                                            setState(() {
                                              controller.value.isPlaying
                                                  ? controller.pause()
                                                  : controller.play();
                                            });
                                          },
                                          icon: Icon(_video!.value.isPlaying ? Icons.pause : Icons.play_arrow),
                                        ),
                                      ],
                                    ),
                                  )
                                : const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.video_file_outlined, color: Colors.white70, size: 54),
                                      SizedBox(height: 10),
                                      Text(
                                        'سيتم تجهيز الفيديو للتشغيل عند النشر',
                                        style: TextStyle(color: Colors.white70),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ))
                            : (_mediaBytes != null
                                ? Image.memory(_mediaBytes!, fit: BoxFit.contain)
                                : const SizedBox.shrink()),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                      child: TextField(
                        controller: _caption,
                        maxLength: 2000,
                        maxLines: 2,
                        minLines: 1,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'اكتب وصفاً لمنشورك...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          counterStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF202020),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                        child: Text(_error!, textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent)),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _publish,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF3158),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _busy
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('نشر', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_library_outlined, color: Colors.white, size: 58),
                        const SizedBox(height: 16),
                        const Text('اختر صورة أو فيديو من معرض جهازك',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 16)),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent)),
                        ],
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _busy ? null : _chooseFromGallery,
                          icon: _busy
                              ? const SizedBox(width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.folder_open),
                          label: Text(_busy ? 'جارٍ تجهيز الملف...' : 'فتح المعرض'),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
