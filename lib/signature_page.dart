import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'filters.dart';
import 'models.dart';
import 'store.dart';

const _ink = Color(0xFF1A237E);

/// Draw a signature with a finger. Saves it as a transparent PNG and pops the
/// file path (null when cancelled).
class SignaturePadPage extends StatefulWidget {
  const SignaturePadPage({super.key, required this.store});
  final DocStore store;

  @override
  State<SignaturePadPage> createState() => _SignaturePadPageState();
}

class _SignaturePadPageState extends State<SignaturePadPage> {
  final List<List<Offset>> _strokes = [];
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final png = await renderSignaturePng(_strokes);
    if (png == null) {
      setState(() => _saving = false);
      return;
    }
    final path = await widget.store.setSignature(png);
    if (mounted) Navigator.pop(context, path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buat tanda tangan')),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GestureDetector(
                    onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
                    onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
                    child: CustomPaint(
                      painter: _PadPainter(_strokes),
                      child: _strokes.isEmpty
                          ? const Center(
                              child: Text('Goreskan tanda tangan di sini', style: TextStyle(color: Colors.black38)),
                            )
                          : const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear),
                      child: const Text('Hapus'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _strokes.isEmpty || _saving ? null : _save,
                      child: const Text('Simpan'),
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

class _PadPainter extends CustomPainter {
  _PadPainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) => paintStrokes(canvas, strokes, 3.5);

  @override
  bool shouldRepaint(_PadPainter old) => true;
}

void paintStrokes(Canvas canvas, List<List<Offset>> strokes, double width) {
  final paint = Paint()
    ..color = _ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  for (final s in strokes) {
    if (s.length == 1) {
      canvas.drawCircle(s.first, width / 2, Paint()..color = _ink);
      continue;
    }
    final path = Path()..moveTo(s.first.dx, s.first.dy);
    for (final p in s.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }
}

/// Renders strokes tightly cropped to their bounds on a transparent background.
Future<Uint8List?> renderSignaturePng(List<List<Offset>> strokes) async {
  final points = [for (final s in strokes) ...s];
  if (points.isEmpty) return null;
  var minX = points.first.dx, maxX = minX, minY = points.first.dy, maxY = minY;
  for (final p in points) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  const pad = 8.0, scale = 3.0;
  final w = ((maxX - minX) + pad * 2) * scale;
  final h = ((maxY - minY) + pad * 2) * scale;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)
    ..scale(scale)
    ..translate(pad - minX, pad - minY);
  paintStrokes(canvas, strokes, 3.5);
  final image = await rec.endRecording().toImage(w.ceil(), h.ceil());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

/// Lets the user drag and resize the saved signature over a page. Pops the
/// chosen placement (null when cancelled).
class SignPlacePage extends StatefulWidget {
  const SignPlacePage({super.key, required this.page, required this.signatureFile, this.pageCount = 1});
  final PageItem page;

  /// Pages in the document; the "all pages" option only shows when more than one.
  final int pageCount;
  final String signatureFile;

  @override
  State<SignPlacePage> createState() => _SignPlacePageState();
}

class _SignPlacePageState extends State<SignPlacePage> {
  PageResult? _base;
  double _aspect = 0.4; // signature height / width
  late double _x = widget.page.signature?.x ?? 0.7;
  late double _y = widget.page.signature?.y ?? 0.85;
  late double _w = widget.page.signature?.width ?? 0.3;
  bool _all = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = widget.page;
    // The page as it looks without any signature on it.
    final bare = PageItem(
      file: p.file,
      turns: p.turns,
      filter: p.filter,
      brightness: p.brightness,
      contrast: p.contrast,
    );
    final base = await compute(processPage, PageJob.of(bare, maxSide: 1400));
    final bytes = await File(widget.signatureFile).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _base = base;
      _aspect = frame.image.height / frame.image.width;
    });
  }

  @override
  Widget build(BuildContext context) {
    final base = _base;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Tempel tanda tangan'),
      ),
      body: base == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: base.width / base.height,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final sw = _w * box.maxWidth;
                          final sh = sw * _aspect;
                          return Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              Positioned.fill(child: Image.memory(base.bytes, fit: BoxFit.fill)),
                              Positioned(
                                left: _x * box.maxWidth - sw / 2,
                                top: _y * box.maxHeight - sh / 2,
                                width: sw,
                                height: sh,
                                child: GestureDetector(
                                  onPanUpdate: (d) => setState(() {
                                    _x = (_x + d.delta.dx / box.maxWidth).clamp(0.0, 1.0);
                                    _y = (_y + d.delta.dy / box.maxHeight).clamp(0.0, 1.0);
                                  }),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.tealAccent, width: 1.5),
                                    ),
                                    child: Image.file(File(widget.signatureFile), fit: BoxFit.fill),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.photo_size_select_small, color: Colors.white70),
                      Expanded(
                        child: Slider(
                          value: _w,
                          min: 0.1,
                          max: 0.7,
                          onChanged: (v) => setState(() => _w = v),
                        ),
                      ),
                      const Icon(Icons.photo_size_select_large, color: Colors.white70),
                    ],
                  ),
                ),
                if (widget.pageCount > 1)
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      'Terapkan ke semua ${widget.pageCount} halaman',
                      style: const TextStyle(color: Colors.white),
                    ),
                    value: _all,
                    onChanged: (v) => setState(() => _all = v ?? false),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Batal'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                Navigator.pop(
                              context,
                              SignResult(SignaturePlacement(widget.signatureFile, _x, _y, _w), all: _all),
                            ),
                            child: const Text('Terapkan'),
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

/// What the user chose in [SignPlacePage].
class SignResult {
  const SignResult(this.placement, {required this.all});
  final SignaturePlacement placement;

  /// Apply the same placement to every page of the document.
  final bool all;
}
