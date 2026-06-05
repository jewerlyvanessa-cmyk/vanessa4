import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:vanessa3/widgets/qr_scan_manual_entry.dart';
import 'package:web/web.dart' hide Navigator, Text;

/// Scan berkelanjutan di browser — kumpulkan banyak kode.
Future<List<String>?> pushQrBatchScanPage(
  BuildContext context, {
  String title = 'Scan batch',
  bool showTorchActions = false,
  Color? appBarBackgroundColor,
}) {
  return Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      builder: (ctx) => _WebQrBatchScanPage(
        title: title,
        appBarBackgroundColor: appBarBackgroundColor,
      ),
    ),
  );
}

/// Scan QR di browser (HP/tablet/desktop) memakai jsQR + getUserMedia.
Future<String?> pushQrScanPage(
  BuildContext context, {
  String title = 'Scan QR Code',
  bool showTorchActions = false,
  Color? appBarBackgroundColor,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (ctx) => _WebQrScanPage(
        title: title,
        appBarBackgroundColor: appBarBackgroundColor,
      ),
    ),
  );
}

@JS('jsQR')
external JSObject? _jsQR(
  JSUint8ClampedArray data,
  int width,
  int height,
  JSObject options,
);


class _WebQrScanPage extends StatefulWidget {
  const _WebQrScanPage({
    required this.title,
    this.appBarBackgroundColor,
  });

  final String title;
  final Color? appBarBackgroundColor;

  @override
  State<_WebQrScanPage> createState() => _WebQrScanPageState();
}

class _WebQrScanPageState extends State<_WebQrScanPage> {
  static int _viewId = 0;

  late final String _viewType;
  late final HTMLVideoElement _video;
  late final HTMLCanvasElement _canvas;
  late final CanvasRenderingContext2D _ctx;

  MediaStream? _stream;
  bool _handled = false;
  bool _decoding = false;
  bool _useBackCamera = true;
  String? _error;
  Timer? _decodeTimer;

  @override
  void initState() {
    super.initState();
    _viewId += 1;
    _viewType = 'vanessa-qr-video-$_viewId';

    _video = HTMLVideoElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true');

    _canvas = HTMLCanvasElement();
    _ctx = _canvas.getContext('2d') as CanvasRenderingContext2D;

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (_) => _video,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
  }

  @override
  void dispose() {
    _decodeTimer?.cancel();
    _stopCamera();
    super.dispose();
  }

  void _completeWith(String raw) {
    if (_handled || !mounted) return;
    final value = raw.trim();
    if (value.isEmpty) return;
    _handled = true;
    _stopCamera();
    Navigator.of(context).pop(value);
  }

  Future<void> _startCamera() async {
    if (_error != null) return;
    _stopCamera();
    setState(() {
      _error = null;
    });

    final media = window.navigator.mediaDevices;

    final constraints = _useBackCamera
        ? MediaStreamConstraints(
            video: MediaTrackConstraintSet(facingMode: 'environment'.toJS),
          )
        : MediaStreamConstraints(video: true.toJS);

    try {
      final stream = await media.getUserMedia(constraints).toDart;
      _stream = stream;
      _video.srcObject = stream;
      await _video.play().toDart;
      _scheduleDecode();
    } catch (e) {
      final msg = e.toString();
      if (_useBackCamera &&
          (msg.contains('NotFoundError') || msg.contains('Overconstrained'))) {
        setState(() => _useBackCamera = false);
        await _startCamera();
        return;
      }
      setState(() {
        if (msg.contains('NotAllowedError')) {
          _error =
              'Izin kamera ditolak. Aktifkan kamera untuk situs ini di pengaturan browser.';
        } else if (msg.contains('NotSupportedError') ||
            msg.contains('SecurityError')) {
          _error =
              'Kamera tidak didukung. Buka lewat HTTPS (https://mobile.vanessa.id).';
        } else {
          _error = 'Gagal membuka kamera. Coba ganti kamera atau input manual.';
        }
      });
    }
  }

  void _stopCamera() {
    _decodeTimer?.cancel();
    _decodeTimer = null;
    _decoding = false;
    _video.pause();
    final tracks = _stream?.getTracks().toDart ?? [];
    for (final t in tracks) {
      t.stop();
    }
    _stream = null;
    _video.srcObject = null;
  }

  void _scheduleDecode() {
    _decodeTimer?.cancel();
    _decodeTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_decoding && mounted && !_handled) {
        _decodeFrame();
      }
    });
  }

  void _decodeFrame() {
    if (_handled || _error != null) return;
    if (_video.readyState < 2) return; // HAVE_CURRENT_DATA

    final w = _video.videoWidth;
    final h = _video.videoHeight;
    if (w <= 0 || h <= 0) return;

    _decoding = true;
    try {
      _canvas.width = w;
      _canvas.height = h;
      _ctx.drawImage(_video, 0, 0);
      final imageData = _ctx.getImageData(0, 0, w, h);
      final options = JSObject()
        ..setProperty('inversionAttempts'.toJS, 'dontInvert'.toJS);
      final result = _jsQR(
        imageData.data,
        w,
        h,
        options,
      );
      if (result != null) {
        final dataProp = result.getProperty('data'.toJS);
        final data = dataProp.isA<JSString>() ? (dataProp as JSString).toDart : '';
        if (data.isNotEmpty) {
          _completeWith(data);
        }
      }
    } catch (_) {
      // jsQR belum dimuat — abaikan frame ini
    } finally {
      _decoding = false;
    }
  }

  Future<void> _switchCamera() async {
    setState(() => _useBackCamera = !_useBackCamera);
    await _startCamera();
  }

  Future<void> _manualEntry() async {
    final value = await showQrManualEntryDialog(context);
    if (value != null && value.isNotEmpty) {
      _completeWith(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: widget.appBarBackgroundColor,
        actions: [
          IconButton(
            tooltip: 'Ganti kamera',
            icon: const Icon(Icons.cameraswitch),
            onPressed: _switchCamera,
          ),
          IconButton(
            tooltip: 'Input manual',
            icon: const Icon(Icons.keyboard),
            onPressed: _manualEntry,
          ),
        ],
      ),
      body: _error != null
          ? _buildError()
          : Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Colors.black,
                  child: HtmlElementView(viewType: _viewType),
                ),
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      child: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(
                          'Arahkan QR ke kamera. Izinkan akses kamera jika diminta.',
                          style:
                              TextStyle(color: Colors.white, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off, size: 48),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _startCamera,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _manualEntry,
              icon: const Icon(Icons.keyboard),
              label: const Text('Input kode manual'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebQrBatchScanPage extends StatefulWidget {
  const _WebQrBatchScanPage({
    required this.title,
    this.appBarBackgroundColor,
  });

  final String title;
  final Color? appBarBackgroundColor;

  @override
  State<_WebQrBatchScanPage> createState() => _WebQrBatchScanPageState();
}

class _WebQrBatchScanPageState extends State<_WebQrBatchScanPage> {
  static const _debounce = Duration(seconds: 2);
  static int _viewId = 0;

  late final String _viewType;
  late final HTMLVideoElement _video;
  late final HTMLCanvasElement _canvas;
  late final CanvasRenderingContext2D _ctx;

  MediaStream? _stream;
  bool _decoding = false;
  bool _useBackCamera = true;
  String? _error;
  Timer? _decodeTimer;

  final List<String> _codes = [];
  final Set<String> _seenKeys = {};
  final Map<String, DateTime> _lastDetect = {};

  @override
  void initState() {
    super.initState();
    _viewId += 1;
    _viewType = 'vanessa-qr-batch-video-$_viewId';

    _video = HTMLVideoElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true');

    _canvas = HTMLCanvasElement();
    _ctx = _canvas.getContext('2d') as CanvasRenderingContext2D;

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (_) => _video,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
  }

  @override
  void dispose() {
    _decodeTimer?.cancel();
    _stopCamera();
    super.dispose();
  }

  String _dedupeKey(String raw) => raw.trim().toLowerCase();

  void _tryAdd(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final key = _dedupeKey(trimmed);
    final now = DateTime.now();
    final last = _lastDetect[key];
    if (last != null && now.difference(last) < _debounce) return;
    _lastDetect[key] = now;
    if (_seenKeys.contains(key)) return;
    setState(() {
      _seenKeys.add(key);
      _codes.add(trimmed);
    });
  }

  void _finish() {
    if (!mounted) return;
    _stopCamera();
    Navigator.of(context).pop(_codes);
  }

  Future<void> _startCamera() async {
    if (_error != null) return;
    _stopCamera();
    setState(() {
      _error = null;
    });

    final media = window.navigator.mediaDevices;
    final constraints = _useBackCamera
        ? MediaStreamConstraints(
            video: MediaTrackConstraintSet(facingMode: 'environment'.toJS),
          )
        : MediaStreamConstraints(video: true.toJS);

    try {
      final stream = await media.getUserMedia(constraints).toDart;
      _stream = stream;
      _video.srcObject = stream;
      await _video.play().toDart;
      _scheduleDecode();
    } catch (e) {
      final msg = e.toString();
      if (_useBackCamera &&
          (msg.contains('NotFoundError') || msg.contains('Overconstrained'))) {
        setState(() => _useBackCamera = false);
        await _startCamera();
        return;
      }
      setState(() {
        if (msg.contains('NotAllowedError')) {
          _error =
              'Izin kamera ditolak. Aktifkan kamera untuk situs ini di pengaturan browser.';
        } else if (msg.contains('NotSupportedError') ||
            msg.contains('SecurityError')) {
          _error =
              'Kamera tidak didukung. Buka lewat HTTPS (https://mobile.vanessa.id).';
        } else {
          _error = 'Gagal membuka kamera. Coba ganti kamera atau input manual.';
        }
      });
    }
  }

  void _stopCamera() {
    _decodeTimer?.cancel();
    _decodeTimer = null;
    _decoding = false;
    _video.pause();
    final tracks = _stream?.getTracks().toDart ?? [];
    for (final t in tracks) {
      t.stop();
    }
    _stream = null;
    _video.srcObject = null;
  }

  void _scheduleDecode() {
    _decodeTimer?.cancel();
    _decodeTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_decoding && mounted) {
        _decodeFrame();
      }
    });
  }

  void _decodeFrame() {
    if (_error != null) return;
    if (_video.readyState < 2) return;

    final w = _video.videoWidth;
    final h = _video.videoHeight;
    if (w <= 0 || h <= 0) return;

    _decoding = true;
    try {
      _canvas.width = w;
      _canvas.height = h;
      _ctx.drawImage(_video, 0, 0);
      final imageData = _ctx.getImageData(0, 0, w, h);
      final options = JSObject()
        ..setProperty('inversionAttempts'.toJS, 'dontInvert'.toJS);
      final result = _jsQR(
        imageData.data,
        w,
        h,
        options,
      );
      if (result != null) {
        final dataProp = result.getProperty('data'.toJS);
        final data =
            dataProp.isA<JSString>() ? (dataProp as JSString).toDart : '';
        if (data.isNotEmpty) _tryAdd(data);
      }
    } catch (_) {
      // jsQR belum dimuat
    } finally {
      _decoding = false;
    }
  }

  Future<void> _switchCamera() async {
    setState(() => _useBackCamera = !_useBackCamera);
    await _startCamera();
  }

  Future<void> _manualEntry() async {
    final value = await showQrManualEntryDialog(context);
    if (value != null && value.isNotEmpty) _tryAdd(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: widget.appBarBackgroundColor,
        actions: [
          TextButton(
            onPressed: _codes.isEmpty ? null : _finish,
            child: Text('Selesai (${_codes.length})'),
          ),
          IconButton(
            tooltip: 'Ganti kamera',
            icon: const Icon(Icons.cameraswitch),
            onPressed: _switchCamera,
          ),
          IconButton(
            tooltip: 'Input manual',
            icon: const Icon(Icons.keyboard),
            onPressed: _manualEntry,
          ),
        ],
      ),
      body: _error != null
          ? _buildError()
          : Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Colors.black,
                  child: HtmlElementView(viewType: _viewType),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Material(
                      color: Colors.black54,
                      borderRadius:
                          const BorderRadius.all(Radius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _codes.isEmpty
                                  ? 'Arahkan QR ke kamera. Scan berulang tanpa tutup kamera.'
                                  : '${_codes.length} kode terkumpul — scan lagi atau ketuk Selesai.',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (_codes.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: _finish,
                                child: Text(
                                  'Selesai — proses ${_codes.length} kode',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off, size: 48),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _startCamera,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _manualEntry,
              icon: const Icon(Icons.keyboard),
              label: const Text('Input kode manual'),
            ),
          ],
        ),
      ),
    );
  }
}
