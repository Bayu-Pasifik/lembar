import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'filters.dart';
import 'models.dart';

/// Shows a page with rotation and filter applied, using the same pipeline as the
/// PDF export so the preview matches the result. Results are cached in memory.
class PageImage extends StatefulWidget {
  const PageImage({
    super.key,
    required this.page,
    this.maxSide = 1600,
    this.fit = BoxFit.contain,
    this.thumbnail = false,
  });
  final PageItem page;
  final int maxSide;
  final BoxFit fit;

  /// Thumbnails stay quiet: no spinner, no error text.
  final bool thumbnail;

  @override
  State<PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<PageImage> {
  static final Map<String, Uint8List> _cache = {};
  static const _cacheLimit = 64;

  Uint8List? _bytes;
  Object? _error;
  bool _loading = false;
  String _key = '';

  String _keyFor(PageItem p) => '${p.renderKey}|${widget.maxSide}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PageImage old) {
    super.didUpdateWidget(old);
    if (_keyFor(widget.page) != _key) _load();
  }

  Future<void> _load() async {
    final p = widget.page;
    final key = _keyFor(p);
    _key = key;
    final cached = _cache[key];
    if (cached != null) {
      setState(() {
        _bytes = cached;
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await compute(processPage, PageJob.of(p, maxSide: widget.maxSide));
      _cache[key] = r.bytes;
      if (_cache.length > _cacheLimit) _cache.remove(_cache.keys.first);
      if (!mounted || _key != key) return;
      setState(() {
        _bytes = r.bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || _key != key) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.thumbnail
          ? const Center(child: Icon(Icons.broken_image_outlined))
          : Center(child: Text('Gagal memuat: $_error', style: const TextStyle(color: Colors.white70)));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_bytes != null) Image.memory(_bytes!, fit: widget.fit, gaplessPlayback: true),
        if (_loading && !widget.thumbnail)
          const Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.only(top: 12),
              child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            ),
          ),
      ],
    );
  }
}
