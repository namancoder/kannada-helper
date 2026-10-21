import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../engines/engines.dart';
import '../services/from_kannada.dart';
import '../services/scan_frame.dart';
import 'kannada_result.dart';

/// Point the camera at Kannada text; read it in English and Hindi.
///
/// Live: about one frame a second is cropped to the box, read with OCR and
/// translated, but only when the Kannada text actually changed.
/// Freeze: takes one still photo for a steadier read and holds the result.
class ScanView extends StatefulWidget {
  const ScanView({
    super.key,
    required this.ocr,
    required this.fromKannada,
    required this.tts,
    required this.romanizer,
    required this.voiceInstalled,
    required this.active,
  });

  final Ocr ocr;
  final FromKannada fromKannada;
  final TextToSpeech tts;
  final Romanizer romanizer;
  final bool? voiceInstalled;

  /// The camera only runs while this is true (Scan mode on screen).
  final bool active;

  @override
  State<ScanView> createState() => _ScanViewState();
}

enum _Stage { checking, needsData, downloading, starting, live, error }

class _ScanViewState extends State<ScanView> with WidgetsBindingObserver {
  /// What's read (slightly larger than the box drawn on screen, because the
  /// analysed frame and the preview can be framed a little differently).
  static const _readBox = ScanBox(widthFraction: 0.9, heightFraction: 0.3);
  static const _drawBox = ScanBox(widthFraction: 0.84, heightFraction: 0.24);
  static const _interval = Duration(milliseconds: 1000);

  /// Tesseract mean confidence (0-100) needed to trust a read. Random shapes
  /// forced into Kannada letters usually score well below these.
  static const _minLiveConfidence = 60;
  static const _minFrozenConfidence = 45;

  _Stage _stage = _Stage.checking;
  CameraController? _camera;
  String? _error;
  double? _downloadProgress;

  bool _busy = false; // a frame is being processed
  bool _frozen = false;
  bool _torch = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  int _generation = 0; // bumps on every start/stop so stale work is ignored

  String _lastText = '';

  /// Live reads must match twice in a row before they count; OCR noise
  /// changes every frame, real text doesn't.
  String _candidate = '';

  // Debug builds only: what Tesseract actually saw and said.
  Uint8List? _debugPng;
  String _debugRaw = '';
  int _debugConfidence = 0;
  String? _kannada;
  ({String en, String hi})? _meaning;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(ScanView old) {
    super.didUpdateWidget(old);
    if (!old.active && widget.active) _start();
    if (old.active && !widget.active) _stopCamera(afterFrame: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.active) return;
    // Release the camera in the background; take it back on return.
    // ('inactive' also fires during permission dialogs, so it's ignored.)
    if (state == AppLifecycleState.paused) {
      setState(_stopCamera);
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _camera?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- setup --

  /// Safe to call from initState/didUpdateWidget: the synchronous part only
  /// sets fields (a build follows anyway); setState comes after awaits.
  Future<void> _start() async {
    final gen = ++_generation;
    _stage = _Stage.checking;
    _error = null;
    bool ready;
    try {
      ready = await widget.ocr.isReady();
    } catch (e) {
      ready = false;
    }
    if (!mounted || gen != _generation) return;
    if (!ready) {
      setState(() => _stage = _Stage.needsData);
      return;
    }
    await _startCamera(gen);
  }

  Future<void> _download() async {
    setState(() {
      _stage = _Stage.downloading;
      _downloadProgress = null;
      _error = null;
    });
    try {
      await widget.ocr.prepare(onProgress: (got, total) {
        if (!mounted || total == null) return;
        setState(() => _downloadProgress = got / total);
      });
      if (mounted && widget.active) await _start();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.needsData;
        _error = 'Download failed. Check your internet and try again.\n($e)';
      });
    }
  }

  Future<void> _startCamera(int gen) async {
    if (mounted) setState(() => _stage = _Stage.starting);
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('NoCamera', 'No camera found');
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        back,
        ResolutionPreset.veryHigh, // 1080p: enough detail for small print
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted || gen != _generation) {
        await controller.dispose();
        return;
      }
      _camera = controller;
      _frozen = false;
      _torch = false;
      setState(() => _stage = _Stage.live);
      await controller.startImageStream(_onFrame);
    } on CameraException catch (e) {
      await controller?.dispose();
      if (!mounted || gen != _generation) return;
      _camera = null;
      setState(() {
        _stage = _Stage.error;
        _error = cameraErrorMessage(e.code);
      });
    }
  }

  /// [afterFrame]: wait until the preview is off screen before releasing the
  /// camera (used when switching modes). In the background no frames are
  /// drawn, so there it's released at once.
  void _stopCamera({bool afterFrame = false}) {
    _generation++;
    final camera = _camera;
    _camera = null;
    _busy = false;
    if (camera != null) {
      if (afterFrame) {
        WidgetsBinding.instance.addPostFrameCallback((_) => camera.dispose());
      } else {
        camera.dispose();
      }
    }
    // No setState: may run inside didUpdateWidget, and the preview must not
    // touch the disposed controller. The next build shows the spinner.
    if (_stage == _Stage.live) _stage = _Stage.checking;
  }

  // ------------------------------------------------------------- reading --

  void _onFrame(CameraImage frame) {
    final now = DateTime.now();
    if (_busy || _frozen || now.difference(_lastFrame) < _interval) return;
    final camera = _camera;
    if (camera == null) return;
    _busy = true;
    _lastFrame = now;

    final plane = frame.planes.first; // Y = brightness, all OCR needs
    final request = FrameRequest(
      // Copy: the camera reuses this buffer as soon as we return.
      luma: Uint8List.fromList(plane.bytes),
      width: frame.width,
      height: frame.height,
      rowStride: plane.bytesPerRow,
      rotation: camera.description.sensorOrientation,
      box: _readBox,
    );
    _process(_generation, () => compute(frameToPng, request), live: true);
  }

  Future<void> _process(
    int gen,
    Future<Uint8List?> Function() makePng, {
    required bool live,
  }) async {
    try {
      final png = await makePng();
      if (png == null || gen != _generation) return;
      final ocr = await widget.ocr.read(png);
      if (!mounted || gen != _generation) return;
      if (kDebugMode) {
        setState(() {
          _debugPng = png;
          _debugRaw = ocr.text.trim().replaceAll('\n', ' ⏎ ');
          _debugConfidence = ocr.confidence;
        });
      }
      if (live && _frozen) return; // a freeze started meanwhile

      final text = cleanKannada(ocr.text);
      final minConfidence = live ? _minLiveConfidence : _minFrozenConfidence;
      if (kannadaLetterCount(text) < 3 || ocr.confidence < minConfidence) {
        // Nothing trustworthy. Keep the last good result on screen (no flicker).
        _candidate = '';
        if (!live) {
          setState(() => _error = "Couldn't read that clearly. Fill the box "
              'with the text, hold steady and try Freeze again.');
        }
        return;
      }
      if (live) {
        if (text != _candidate) {
          _candidate = text; // wait for the next frame to confirm
          return;
        }
        if (text == _lastText) return;
      }

      final meaning = await widget.fromKannada(text);
      if (!mounted || gen != _generation) return;
      if (live && _frozen) return;
      _lastText = text;
      setState(() {
        _kannada = text;
        _meaning = meaning;
        _error = null;
      });
    } catch (e) {
      if (mounted && gen == _generation && !live) {
        setState(() => _error = 'Could not read that: $e');
      }
    } finally {
      if (gen == _generation) _busy = false;
    }
  }

  Future<void> _toggleFreeze() async {
    final camera = _camera;
    if (camera == null) return;

    if (_frozen) {
      setState(() {
        _frozen = false;
        _error = null;
        _candidate = '';
      });
      await camera.resumePreview();
      if (!camera.value.isStreamingImages) {
        await camera.startImageStream(_onFrame);
      }
      return;
    }

    setState(() => _frozen = true);
    final gen = _generation;
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
      final photo = await camera.takePicture();
      await camera.pausePreview();
      final jpeg = await photo.readAsBytes();
      if (!mounted || gen != _generation) return;
      _busy = true;
      setState(() => _error = null);
      await _process(
        gen,
        () => compute(photoToPng, PhotoRequest(jpeg, box: _readBox)),
        live: false,
      );
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = 'Camera error: ${e.description}');
    }
  }

  Future<void> _toggleTorch() async {
    final camera = _camera;
    if (camera == null) return;
    try {
      await camera.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } on CameraException {
      // No flash on this device; ignore.
    }
  }

  // ------------------------------------------------------------------ UI --

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      _Stage.checking ||
      _Stage.starting =>
        const Center(child: CircularProgressIndicator()),
      _Stage.needsData || _Stage.downloading => _buildNeedsData(context),
      _Stage.error => _buildError(context),
      _Stage.live => _buildLive(context),
    };
  }

  Widget _buildNeedsData(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final downloading = _stage == _Stage.downloading;
    return ListView(
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.document_scanner_outlined, size: 56),
        const SizedBox(height: 16),
        Text('One-time setup for Scan',
            textAlign: TextAlign.center, style: text.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Scan needs the Kannada reading model (a few MB). '
          'After this download it works offline.',
          textAlign: TextAlign.center,
          style: text.bodyLarge,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: downloading ? null : _download,
          icon: const Icon(Icons.download),
          label: Text(downloading ? 'Downloading…' : 'Download Kannada model'),
        ),
        if (downloading) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _downloadProgress),
        ],
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.no_photography_outlined,
              size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(_error ?? 'Camera unavailable.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _start, child: const Text('Try again')),
        ],
      ),
    );
  }

  Widget _buildLive(BuildContext context) {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final kannada = _kannada;
    final meaning = _meaning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  CameraPreview(camera),
                  const Positioned.fill(child: _ScanBoxOverlay(box: _drawBox)),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton.filledTonal(
                      tooltip: _torch ? 'Torch off' : 'Torch on',
                      icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
                      onPressed: _toggleTorch,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _frozen
                    ? 'Frozen. Tap Resume to scan again.'
                    : 'Fit Kannada text inside the box',
                style:
                    textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
            FilledButton.icon(
              key: const Key('freeze'),
              onPressed: _toggleFreeze,
              icon: Icon(_frozen ? Icons.play_arrow : Icons.pause),
              label: Text(_frozen ? 'Resume' : 'Freeze'),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: TextStyle(color: colors.error)),
        ],
        if (kDebugMode && _debugPng != null) ...[
          const SizedBox(height: 6),
          _DebugStrip(
            png: _debugPng!,
            raw: _debugRaw,
            confidence: _debugConfidence,
            threshold: _frozen ? _minFrozenConfidence : _minLiveConfidence,
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          flex: 4,
          child: kannada == null || meaning == null
              ? Center(
                  child: Text('The meaning will show here.',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant)),
                )
              : ListView(
                  children: [
                    _Meaning(label: 'English', text: meaning.en, big: true),
                    _Meaning(label: 'हिंदी', text: meaning.hi),
                    const SizedBox(height: 4),
                    KannadaResult(
                      kannada: kannada,
                      romanizer: widget.romanizer,
                      tts: widget.tts,
                      voiceInstalled: widget.voiceInstalled,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Darkens everything outside the scan box and outlines the box.
class _ScanBoxOverlay extends StatelessWidget {
  const _ScanBoxOverlay({required this.box});

  final ScanBox box;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScanBoxPainter(box, Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _ScanBoxPainter extends CustomPainter {
  _ScanBoxPainter(this.box, this.color);

  final ScanBox box;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * box.widthFraction;
    final h = size.height * box.heightFraction;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h),
      const Radius.circular(12),
    );
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rect);
    canvas.drawPath(shade, Paint()..color = const Color(0x88000000));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_ScanBoxPainter old) =>
      old.box != box || old.color != color;
}

class _Meaning extends StatelessWidget {
  const _Meaning({required this.label, required this.text, this.big = false});

  final String label;
  final String text;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          SelectableText(
            text,
            style: big
                ? theme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)
                : theme.titleMedium,
          ),
        ],
      ),
    );
  }
}

/// Debug builds only: the exact image sent to OCR, its raw output and score.
/// If the picture looks sideways, mirrored or blurry, that's the problem.
class _DebugStrip extends StatelessWidget {
  const _DebugStrip({
    required this.png,
    required this.raw,
    required this.confidence,
    required this.threshold,
  });

  final Uint8List png;
  final String raw;
  final int confidence;
  final int threshold;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ok = confidence >= threshold;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.memory(png, height: 56, gaplessPlayback: true),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'DEBUG  confidence $confidence/$threshold ${ok ? '✓' : '✗'}\n'
                '${raw.isEmpty ? '(no text)' : raw}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ok ? colors.onSurface : colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Turns camera plugin error codes into something a human can act on.
String cameraErrorMessage(String code) {
  if (code.contains('AccessDenied') || code.contains('Permission')) {
    return "Camera access is off. Allow the camera for Kannada Helper in "
        "your phone's app settings, then tap Try again.";
  }
  if (code == 'NoCamera') return 'No camera found on this device.';
  return 'Could not start the camera ($code).';
}
