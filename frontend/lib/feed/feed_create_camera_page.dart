import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// Select a photo or video from the device gallery. No camera access is used.
class FeedCreateCameraPage extends StatefulWidget {
  const FeedCreateCameraPage({super.key, required this.initialFile});

  final XFile initialFile;

  @override
  State<FeedCreateCameraPage> createState() => _FeedCreateCameraPageState();
}

class _FeedCreateCameraPageState extends State<FeedCreateCameraPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selected;
  Uint8List? _imageBytes;
  VideoPlayerController? _video;
  bool _selectedIsVideo = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFile(initialFile);
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _chooseFromGallery() async {
    if (_busy) return;
    try {
      // This method is called directly by a user tapping the gallery button.
      final file = await _picker.pickMedia();
      if (!mounted || file == null) return;
      await _loadFile(file);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر فتح المعرض. حاول مرة أخرى.');
      }
    }
  }

  Future<void> _loadFile(XFile file) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    VideoPlayerController? video;
    try {
      final mime = (file.mimeType ?? '').toLowerCase();
      final path = file.path.toLowerCase();
      final isVideo = mime.startsWith('video/') ||
          path.endsWith('.mp4') ||
          path.endsWith('.mov') ||
          path.endsWith('.webm') ||
          path.endsWith('.m4v');

      Uint8List? imageBytes;
      if (isVideo) {
        // image_picker exposes a browser-readable blob URL on web.
        video = VideoPlayerController.networkUrl(Uri.parse(file.path));
        await video.initialize();
        await video.setLooping(true);
        await video.pause();
      } else {
        imageBytes = await file.readAsBytes();
      }

      if (!mounted) {
        await video?.dispose();
        return;
      }
      await _video?.dispose();
      setState(() {
        _selected = file;
        _selectedIsVideo = isVideo;
        _imageBytes = imageBytes;
        _video = video;
      });
      video = null; // Ownership transferred to the State.
    } catch (_) {
      await video?.dispose();
      if (mounted) {
        setState(() => _error = 'تعذر فتح الملف أو معاينته. اختر صورة أو فيديو آخر.');
      }
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
          title: const Text('اختيار منشور'),
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
                                          onPressed: () {
                                            final controller = _video!;
                                            setState(() {
                                              controller.value.isPlaying
                                                  ? controller.pause()
                                                  : controller.play();
                                            });
                                          },
                                          icon: Icon(
                                            _video!.value.isPlaying
                                                ? Icons.pause
                                                : Icons.play_arrow,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : const CircularProgressIndicator(color: Colors.white))
                            : (_imageBytes != null
                                ? Image.memory(_imageBytes!, fit: BoxFit.contain)
                                : const SizedBox.shrink()),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(_selected),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF3158),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'التالي',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
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
                        const Icon(Icons.photo_library_outlined,
                            color: Colors.white, size: 58),
                        const SizedBox(height: 16),
                        const Text(
                          'اختر صورة أو فيديو من معرض جهازك',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent)),
                        ],
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _busy ? null : _chooseFromGallery,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.folder_open),
                          label: Text(_busy ? 'جارٍ فتح المعرض...' : 'فتح المعرض'),
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
