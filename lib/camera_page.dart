import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'crop.dart';
import 'crop_page.dart';

/// Camera with a manual shutter. Each shot goes through the crop editor;
/// "Selesai" returns the cropped file paths (empty/null when nothing was kept).
class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _ctrl;
  final List<ScanShot> _shots = [];
  String? _error;
  bool _busy = false;
  bool _flash = false;

  /// ID card mode: two shots (front, back) become one page.
  bool _idMode = false;
  String? _idFront;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error = 'Kamera tidak ditemukan.');
        return;
      }
      final cam = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(cam, ResolutionPreset.veryHigh, enableAudio: false);
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _ctrl = c);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = e.code.contains('Denied')
            ? 'Izin kamera ditolak. Aktifkan di pengaturan.'
            : 'Kamera gagal dibuka: ${e.description ?? e.code}');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      setState(() => _ctrl = null);
    } else if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _crop(String path) async {
    final out = await Navigator.push<CropResult>(
      context,
      MaterialPageRoute(builder: (_) => CropPage(file: path)),
    );
    if (out == null || !mounted) return;
    if (!_idMode) {
      setState(() => _shots.add(ScanShot(out.path, original: path, quad: out.quad)));
      return;
    }
    final front = _idFront;
    if (front == null) {
      setState(() => _idFront = out.path);
      return;
    }
    final bytes = await compute(combineIdCard, [front, out.path]);
    final tmp = await getTemporaryDirectory();
    final f = File('${tmp.path}/id_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await f.writeAsBytes(bytes);
    if (mounted) {
      setState(() {
        _idFront = null;
        _shots.add(ScanShot(f.path));
      });
    }
  }

  Future<void> _shoot() async {
    final c = _ctrl;
    if (c == null || _busy || c.value.isTakingPicture) return;
    setState(() => _busy = true);
    try {
      final shot = await c.takePicture();
      if (!mounted) return;
      await _crop(shot.path);
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memotret: ${e.description ?? e.code}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _gallery() async {
    final picked = await ImagePicker().pickMultiImage();
    for (final x in picked) {
      if (!mounted) return;
      await _crop(x.path);
    }
  }

  Future<void> _toggleFlash() async {
    final c = _ctrl;
    if (c == null) return;
    final next = !_flash;
    try {
      await c.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _flash = next);
    } on CameraException {
      // Device has no flash; ignore.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    return PopScope(
      canPop: _shots.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Buang hasil pindaian?'),
            content: Text('${_shots.length} halaman belum disimpan.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Lanjut')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Buang')),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: c == null || !c.value.isInitialized
                                ? const Center(child: CircularProgressIndicator())
                                : Center(
                                    child: AspectRatio(
                                      aspectRatio: 1 / c.value.aspectRatio,
                                      child: CameraPreview(c),
                                    ),
                                  ),
                          ),
                          Positioned(
                            left: 12,
                            top: 12,
                            child: FilterChip(
                              avatar: const Icon(Icons.badge_outlined, size: 18),
                              label: Text(
                                !_idMode
                                    ? 'Kartu ID'
                                    : _idFront == null
                                        ? 'Kartu ID · jepret sisi depan'
                                        : 'Kartu ID · jepret sisi belakang',
                              ),
                              selected: _idMode,
                              onSelected: (v) => setState(() {
                                _idMode = v;
                                _idFront = null;
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SizedBox(
                            width: 120,
                            child: Row(
                              children: [
                                IconButton(
                                  color: Colors.white,
                                  tooltip: 'Galeri',
                                  icon: const Icon(Icons.photo_library_outlined),
                                  onPressed: _busy ? null : _gallery,
                                ),
                                IconButton(
                                  color: Colors.white,
                                  tooltip: 'Senter',
                                  icon: Icon(_flash ? Icons.flash_on : Icons.flash_off),
                                  onPressed: _toggleFlash,
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: _shoot,
                            child: Container(
                              width: 72,
                              height: 72,
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 4),
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _busy ? Colors.white38 : Colors.white,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _shots.isEmpty
                                  ? const SizedBox.shrink()
                                  : FilledButton(
                                      onPressed: _busy ? null : () => Navigator.pop(context, List<ScanShot>.of(_shots)),
                                      child: Text('Selesai (${_shots.length})', maxLines: 1, softWrap: false),
                                    ),
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
