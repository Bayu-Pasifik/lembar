import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'crop.dart';

/// Result of the crop editor: the corrected image plus the corners used.
class CropResult {
  const CropResult(this.path, this.quad);
  final String path;
  final Quad quad;
}

/// Lets the user drag four corners over a photo, then returns the perspective-corrected JPEG
/// and corners (null when cancelled). [initial] pre-places the corners (e.g. a previous crop).
class CropPage extends StatefulWidget {
  const CropPage({super.key, required this.file, this.initial});
  final String file;
  final Quad? initial;

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  CropInput? _input;
  List<(double, double)> _c = Quad.inset.points;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await compute(prepareForCrop, widget.file);
      if (!mounted) return;
      setState(() {
        _input = r;
        _c = (widget.initial ?? r.guess).points;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Quad get _quad => Quad(_c[0], _c[1], _c[2], _c[3]);

  Future<void> _done() async {
    setState(() => _busy = true);
    try {
      final bytes = await compute(cropQuad, CropJob(widget.file, _quad));
      final tmp = await getTemporaryDirectory();
      final f = File('${tmp.path}/crop_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await f.writeAsBytes(bytes);
      if (mounted) Navigator.pop(context, CropResult(f.path, _quad));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memotong: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final input = _input;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Atur potongan'),
        actions: [
          TextButton(
            onPressed: input == null || _busy ? null : () => setState(() => _c = Quad.full.points),
            child: const Text('Seluruh foto'),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
          : input == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          // Fit the image inside the available area.
                          final scale = (box.maxWidth - 40) / input.width < (box.maxHeight - 40) / input.height
                              ? (box.maxWidth - 40) / input.width
                              : (box.maxHeight - 40) / input.height;
                          final w = input.width * scale, h = input.height * scale;
                          final left = (box.maxWidth - w) / 2, top = (box.maxHeight - h) / 2;
                          Offset toPx((double, double) p) => Offset(left + p.$1 * w, top + p.$2 * h);
                          return Stack(
                            children: [
                              Positioned(
                                left: left,
                                top: top,
                                width: w,
                                height: h,
                                child: Image.memory(input.bytes, fit: BoxFit.fill, gaplessPlayback: true),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(painter: _QuadPainter(_c.map(toPx).toList())),
                                ),
                              ),
                              for (var i = 0; i < 4; i++)
                                Positioned(
                                  left: toPx(_c[i]).dx - 28,
                                  top: toPx(_c[i]).dy - 28,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onPanUpdate: _busy
                                        ? null
                                        : (d) => setState(() {
                                              final p = _c[i];
                                              _c = [..._c]..[i] = (
                                                  (p.$1 + d.delta.dx / w).clamp(0.0, 1.0),
                                                  (p.$2 + d.delta.dy / h).clamp(0.0, 1.0),
                                                );
                                            }),
                                    child: const SizedBox(
                                      width: 56,
                                      height: 56,
                                      child: Center(child: _Handle()),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                                onPressed: _busy ? null : () => Navigator.pop(context),
                                child: const Text('Ulangi'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _busy ? null : _done,
                                child: const Text('Pakai'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.35),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
      );
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.pts);
  final List<Offset> pts;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(path, Paint()..color = const Color(0x2200BFA5));
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_QuadPainter old) => true;
}
