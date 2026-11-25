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
          if (mounted) setState(() => _recording = false);
          await _showPreview(file, isVideo: true);
        } else {
          await camera.prepareForVideoRecording();
          await camera.startVideoRecording();
          if (mounted) setState(() => _recording = true);
        }
      } else {
        final file = await camera.takePicture();
        await _showPreview(file, isVideo: false);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _videoMode
            ? 'تعذر تسجيل الفيديو: ${error.toString()}'
            : 'تعذر التقاط الصورة: ${error.toString()}');
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
              // Portrait-first camera canvas, like a short-video creator.
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
                        ? Center(child: Image.memory(_imageBytes!, fit: BoxFit.contain))
                        : const SizedBox.shrink())
              else if (cameraReady)
                Positioned.fill(child: CameraPreview(_camera!))
              else
                const _CameraLoadingPreview(),

              // Top navigation and sound entry.
              Positioned(
                top: 2,
                left: 4,
                right: 4,
                child: Row(
                  children: [
                    _CreatorIconButton(
                      icon: Icons.close_rounded,
                      label: 'إغلاق',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    if (!selected)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(.42),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.music_note_rounded, color: Colors.white, size: 17),
                            SizedBox(width: 6),
                            Text('إضافة صوت', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    const Spacer(),
                    if (selected)
                      _CreatorIconButton(
                        icon: Icons.refresh_rounded,
                        label: 'إعادة',
                        onTap: _busy ? null : _retake,
                      )
                    else
                      const SizedBox(width: 44),
                  ],
                ),
              ),

              if (!selected) ...[
                // Editing tools on the right, kept visually light over the camera.
                Positioned(
                  right: 10,
                  top: MediaQuery.of(context).size.height * .22,
                  child: Column(
                    children: const [
                      _CreatorTool(icon: Icons.flip_camera_android_rounded, label: 'قلب'),
                      SizedBox(height: 22),
                      _CreatorTool(icon: Icons.speed_rounded, label: 'السرعة'),
                      SizedBox(height: 22),
                      _CreatorTool(icon: Icons.auto_awesome_outlined, label: 'تجميل'),
                      SizedBox(height: 22),
                      _CreatorTool(icon: Icons.filter_vintage_outlined, label: 'فلاتر'),
                      SizedBox(height: 22),
                      _CreatorTool(icon: Icons.timer_outlined, label: 'المؤقت'),
                      SizedBox(height: 22),
                      _CreatorTool(icon: Icons.flash_on_rounded, label: 'فلاش'),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withOpacity(.68), Colors.black.withOpacity(.94)],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_error != null) ...[
                          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12)),
                          if (_cameraDenied)
                            TextButton(
                              onPressed: _initializeCamera,
                              child: const Text('إعادة المحاولة', style: TextStyle(color: Colors.white)),
                            ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ModeButton(label: 'قصة', selected: false, onTap: null),
                            const SizedBox(width: 18),
                            _ModeButton(label: 'فيديو', selected: _videoMode, onTap: _busy || _recording ? null : () => setState(() => _videoMode = true)),
                            const SizedBox(width: 18),
                            _ModeButton(label: 'صورة', selected: !_videoMode, onTap: _busy || _recording ? null : () => setState(() => _videoMode = false)),
                          ],
                        ),
                        const SizedBox(height: 23),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: _busy || _recording ? null : _chooseFromGallery,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.photo_library_outlined, color: Colors.white, size: 27),
                                  SizedBox(height: 5),
                                  Text('تحميل', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: _busy ? null : _capture,
                              child: Container(
                                width: 82,
                                height: 82,
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 4),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _recording ? const Color(0xFFFF3158) : Colors.white,
                                  ),
                                  child: _busy
                                      ? const Padding(
                                          padding: EdgeInsets.all(19),
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                        )
                                      : _recording
                                          ? const Icon(Icons.stop_rounded, color: Colors.white, size: 34)
                                          : null,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _busy || _recording ? null : () {
                                setState(() => _error = 'يمكنك استخدام الكاميرا الأمامية من إعدادات التصوير.');
                              },
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.cameraswitch_outlined, color: Colors.white, size: 27),
                                  SizedBox(height: 5),
                                  Text('قلب', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _recording ? 'جارٍ تسجيل الفيديو • اضغط لإيقاف التسجيل' : 'اضغط للتصوير أو ارفع ملفاً من جهازك',
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ] else
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 22,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                        child: const Text('معاينة المنشور', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(_selected),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF3158),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('التالي', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
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

class _CreatorIconButton extends StatelessWidget {
  const _CreatorIconButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 27),
      );
}

class _CreatorTool extends StatelessWidget {
  const _CreatorTool({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 25),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      );
}

class _CameraLoadingPreview extends StatelessWidget {
  const _CameraLoadingPreview();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF7EBCB), Color(0xFFFAF6EA), Color(0xFFF6F7FB)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFFD9A93C)),
              SizedBox(height: 14),
              Text(
                'جارٍ تشغيل الكاميرا...',
                style: TextStyle(color: Color(0xFF1E2233), fontSize: 13, fontWeight: FontWeight.w600),
              ),
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
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAD09A) : const Color(0xFFFFFEFA),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? const Color(0xFFD9A93C) : const Color(0xFFE8D8B5),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFF1E2233) : const Color(0xFF8B899A),
              fontSize: 15,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w500,
            ),
          ),
        ),
      );
}
