import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// Camera entry point for creating a feed post.
/// The camera capture is delegated to the browser/device camera picker;
/// the gallery action can select either a photo or a video.
class FeedCreateCameraPage extends StatefulWidget {
  const FeedCreateCameraPage({super.key});

  @override
  State<FeedCreateCameraPage> createState() => _FeedCreateCameraPageState();
}

class _FeedCreateCameraPageState extends State<FeedCreateCameraPage> {
  final ImagePicker _picker = ImagePicker();
  bool _videoMode = true;
  bool _busy = false;
  XFile? _selected;
  Uint8List? _imageBytes;
  VideoPlayerController? _videoController;
  String? _error;

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    await _choose(source: ImageSource.camera);
  }

  Future<void> _chooseFromGallery() async {
    await _choose(source: ImageSource.gallery);
  }

  Future<void> _choose({required ImageSource source}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = _videoMode
          ? await _picker.pickVideo(source: source, maxDuration: const Duration(minutes: 3))
          : await _picker.pickImage(source: source, imageQuality: 92);
      if (file == null || !mounted) return;
      await _showPreview(file);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'تعذر فتح الكاميرا أو المعرض. تحقق من إذن الوصول ثم حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPreview(XFile file) async {
    _videoController?.dispose();
    _videoController = null;
    Uint8List? bytes;
    VideoPlayerController? video;
    if (_videoMode) {
      video = VideoPlayerController.networkUrl(Uri.parse(file.path));
      await video.initialize();
      await video.setLooping(true);
      await video.pause();
    } else {
      bytes = await file.readAsBytes();
    }
    if (!mounted) {
      video?.dispose();
      return;
    }
    setState(() {
      _selected = file;
      _imageBytes = bytes;
      _videoController = video;
    });
  }

  void _clearSelection() {
    _videoController?.dispose();
    setState(() {
      _selected = null;
      _imageBytes = null;
      _videoController = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selected != null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF080808),
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: hasSelection
                    ? (_videoMode
                        ? (_videoController?.value.isInitialized == true
                            ? Center(
                                child: AspectRatio(
                                  aspectRatio: _videoController!.value.aspectRatio,
                                  child: VideoPlayer(_videoController!),
                                ),
                              )
                            : const Center(child: CircularProgressIndicator(color: Colors.white)))
                        : (_imageBytes != null
                            ? Image.memory(_imageBytes!, fit: BoxFit.contain)
                            : const SizedBox.shrink()))
                    : const _CameraLandingPreview(),
              ),
              Positioned(
                top: 4,
                right: 8,
                child: IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 29),
                ),
              ),
              if (hasSelection)
                Positioned(
                  top: 4,
                  left: 8,
                  child: IconButton(
                    tooltip: 'إعادة الاختيار',
                    onPressed: _clearSelection,
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 27),
                  ),
                ),
              if (hasSelection)
                Positioned(
                  bottom: 28,
                  left: 20,
                  right: 20,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF0A62B),
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('تم اختيار الملف', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                )
              else
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 22,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_error != null) ...[
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _ModeButton(label: 'فيديو', selected: _videoMode, onTap: _busy ? null : () => setState(() => _videoMode = true)),
                          const SizedBox(width: 18),
                          _ModeButton(label: 'صورة', selected: !_videoMode, onTap: _busy ? null : () => setState(() => _videoMode = false)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            tooltip: 'اختيار من المعرض',
                            onPressed: _busy ? null : _chooseFromGallery,
                            icon: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 30),
                          ),
                          GestureDetector(
                            onTap: _busy ? null : _capture,
                            child: Container(
                              width: 76,
                              height: 76,
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _videoMode ? const Color(0xFFE53935) : Colors.white,
                                ),
                                child: _busy ? const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : null,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _videoMode ? 'تسجيل فيديو' : 'التقاط صورة',
                            onPressed: _busy ? null : _capture,
                            icon: Icon(_videoMode ? Icons.videocam_outlined : Icons.camera_alt_outlined, color: Colors.white, size: 30),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text('صوّر الآن أو اختر صورة أو فيديو من المعرض', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraLandingPreview extends StatelessWidget {
  const _CameraLandingPreview();

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF252525), Color(0xFF090909), Color(0xFF171717)],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 62),
              SizedBox(height: 14),
              Text('الكاميرا', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              SizedBox(height: 7),
              Text('اضغط زر التصوير لفتح كاميرا جهازك', style: TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
        ),
      );
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white60,
            fontSize: 15,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w500,
          ),
        ),
      );
}
