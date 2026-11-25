import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// Full-screen TikTok-style camera for creating a feed item.
/// Gallery selection supports both photos and videos.
class FeedCreateCameraPage extends StatefulWidget {
  const FeedCreateCameraPage({super.key});

  @override
  State<FeedCreateCameraPage> createState() => _FeedCreateCameraPageState();
}

class _FeedCreateCameraPageState extends State<FeedCreateCameraPage>
    with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  CameraController? _camera;
  VideoPlayerController? _video;
  XFile? _selected;
  Uint8List? _imageBytes;
  bool _videoMode = true;
  bool _recording = false;
  bool _busy = false;
  bool _cameraDenied = false;
  bool _selectedIsVideo = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _camera?.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed && _selected == null) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (_busy || _camera?.value.isInitialized == true) return;
    setState(() {
      _busy = true;
      _error = null;
      _cameraDenied = false;
    });
    try {
      final devices = await availableCameras();
      if (devices.isEmpty) {
        throw CameraException('NoCamera', 'No camera device is available');
      }
      final backCameras = devices.where((c) => c.lensDirection == CameraLensDirection.back);
      final device = backCameras.isNotEmpty ? backCameras.first : devices.first;
      final controller = CameraController(
        device,
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraDenied = true;
        _error = 'اسمح للمتصفح باستخدام الكاميرا والميكروفون لبدء التصوير.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      if (_videoMode) {
        if (_recording) {
          final file = await camera.stopVideoRecording();
          setState(() => _recording = false);
          await _showPreview(file, isVideo: true);
        } else {
          await camera.startVideoRecording();
          if (mounted) setState(() => _recording = true);
        }
      } else {
        final file = await camera.takePicture();
        await _showPreview(file, isVideo: false);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'تعذر التصوير. تحقق من أذونات الكاميرا ثم حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseFromGallery() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await _picker.pickMedia();
      if (file == null || !mounted) return;
      final mime = (file.mimeType ?? '').toLowerCase();
      final path = file.path.toLowerCase();
      final isVideo = mime.startsWith('video/') ||
          path.endsWith('.mp4') ||
          path.endsWith('.mov') ||
          path.endsWith('.webm') ||
          path.endsWith('.m4v');
      await _showPreview(file, isVideo: isVideo);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'تعذر فتح المعرض. حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPreview(XFile file, {required bool isVideo}) async {
    final oldCamera = _camera;
    _camera = null;
    await oldCamera?.dispose();
    _video?.dispose();
    _video = null;
    Uint8List? bytes;
    VideoPlayerController? video;
    if (isVideo) {
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
      _selectedIsVideo = isVideo;
      _imageBytes = bytes;
      _video = video;
      _recording = false;
    });
  }

  Future<void> _retake() async {
    _video?.dispose();
    setState(() {
      _video = null;
      _selected = null;
      _imageBytes = null;
      _selectedIsVideo = false;
      _error = null;
    });
    await _initializeCamera();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected != null;
    final cameraReady = _camera?.value.isInitialized == true;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (selected)
                _selectedIsVideo
                    ? (_video?.value.isInitialized == true
                        ? Center(
                            child: AspectRatio(
                              aspectRatio: _video!.value.aspectRatio,
                              child: VideoPlayer(_video!),
                            ),
                          )
                        : const Center(child: CircularProgressIndicator(color: Colors.white)))
                    : (_imageBytes != null
                        ? Image.memory(_imageBytes!, fit: BoxFit.contain)
                        : const SizedBox.shrink())
              else if (cameraReady)
                Center(child: CameraPreview(_camera!))
              else
                const _CameraLoadingPreview(),
              Positioned(
                top: 4,
                right: 8,
                child: IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 29),
                ),
              ),
              if (selected)
                Positioned(
                  top: 4,
                  left: 8,
                  child: IconButton(
                    tooltip: 'إعادة التصوير',
                    onPressed: _busy ? null : _retake,
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 27),
                  ),
                ),
              if (selected)
                Positioned(
                  bottom: 24,
                  left: 20,
                  right: 20,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF0A62B),
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('استخدام هذا الملف', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                )
              else
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 20,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_error != null) ...[
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12)),
                        if (_cameraDenied) ...[
                          const SizedBox(height: 8),
                          TextButton(onPressed: _initializeCamera, child: const Text('إعادة المحاولة')),
                        ],
                        const SizedBox(height: 8),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _ModeButton(label: 'فيديو', selected: _videoMode, onTap: _busy || _recording ? null : () => setState(() => _videoMode = true)),
                          const SizedBox(width: 22),
                          _ModeButton(label: 'صورة', selected: !_videoMode, onTap: _busy || _recording ? null : () => setState(() => _videoMode = false)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            tooltip: 'اختيار من المعرض',
                            onPressed: _busy || _recording ? null : _chooseFromGallery,
                            icon: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 30),
                          ),
                          GestureDetector(
                            onTap: _busy ? null : _capture,
                            child: Container(
                              width: 78,
                              height: 78,
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 4),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _recording ? Colors.white : (_videoMode ? const Color(0xFFE53935) : Colors.white),
                                ),
                                child: _busy
                                    ? const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                    : null,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _videoMode ? (_recording ? 'إيقاف التسجيل' : 'بدء التسجيل') : 'التقاط صورة',
                            onPressed: _busy ? null : _capture,
                            icon: Icon(_videoMode ? Icons.videocam_outlined : Icons.camera_alt_outlined, color: Colors.white, size: 30),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _recording ? 'جارٍ تسجيل الفيديو — اضغط لإيقافه' : 'صوّر الآن أو اختر صورة أو فيديو من المعرض',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
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

class _CameraLoadingPreview extends StatelessWidget {
  const _CameraLoadingPreview();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0xFF101010),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white70),
              SizedBox(height: 14),
              Text('جارٍ تشغيل الكاميرا...', style: TextStyle(color: Colors.white70, fontSize: 13)),
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
