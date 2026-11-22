import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'crop.dart';
import 'crop_page.dart';
import 'models.dart';
import 'ocr.dart';
import 'page_image.dart';
import 'signature_page.dart';
import 'store.dart';

class PageViewer extends StatefulWidget {
  const PageViewer({super.key, required this.store, required this.doc, required this.initial});
  final DocStore store;
  final Doc doc;
  final int initial;

  @override
  State<PageViewer> createState() => _PageViewerState();
}

class _PageViewerState extends State<PageViewer> {
  late final PageController _ctrl = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  Doc get doc => widget.doc;
  PageItem get page => doc.pages[_index];

  bool _ocrBusy = false;

  Future<void> _rotate() async {
    setState(() {
      page.turns = (page.turns + 1) % 4;
      page.text = null; // OCR result no longer matches the orientation
    });
    await widget.store.save();
  }

  Future<void> _ocr() async {
    if (_ocrBusy) return;
    final target = page;
    if (target.text == null) {
      setState(() => _ocrBusy = true);
      try {
        target.text = await recognizePage(target, widget.store);
        await widget.store.save();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OCR gagal: $e')));
        }
        return;
      } finally {
        if (mounted) setState(() => _ocrBusy = false);
      }
    }
    if (!mounted) return;
    final text = target.text ?? '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Teks halaman ${_index + 1}', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  child: SelectableText(
                    text.isEmpty ? 'Tidak ada teks terdeteksi.' : text,
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: text.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(ClipboardData(text: text));
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('Teks disalin')),
                                );
                              }
                            },
                      icon: const Icon(Icons.copy),
                      label: const Text('Salin'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: text.isEmpty
                          ? null
                          : () => SharePlus.instance.share(ShareParams(text: text)),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Bagikan'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _recrop() async {
    final p = page;
    final source = p.original ?? p.file;
    final initial = p.original != null && p.quad != null ? Quad.fromList(p.quad!) : null;
    final out = await Navigator.push<CropResult>(
      context,
      MaterialPageRoute(builder: (_) => CropPage(file: source, initial: initial)),
    );
    if (out == null) return;
    await widget.store.recrop(doc, p, out.path, out.quad);
    try {
      await File(out.path).delete();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _adjust() async {
    final p = page;
    var b = p.brightness, c = p.contrast;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kecerahan & kontras', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('Kecerahan'),
                Slider(
                  value: b,
                  min: -0.4,
                  max: 0.4,
                  onChanged: (v) => setSheet(() => b = v),
                  onChangeEnd: (v) async {
                    setState(() => p.brightness = v);
                    await widget.store.save();
                  },
                ),
                const Text('Kontras'),
                Slider(
                  value: c,
                  min: 0.5,
                  max: 2,
                  onChanged: (v) => setSheet(() => c = v),
                  onChangeEnd: (v) async {
                    setState(() => p.contrast = v);
                    await widget.store.save();
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      setSheet(() {
                        b = 0;
                        c = 1;
                      });
                      setState(() {
                        p.brightness = 0;
                        p.contrast = 1;
                      });
                      await widget.store.save();
                    },
                    child: const Text('Setel ulang'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sign() async {
    final p = page;
    var file = widget.store.signatureFile;
    if (file == null) {
      file = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => SignaturePadPage(store: widget.store)),
      );
      if (file == null || !mounted) return;
    } else {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.draw_outlined),
                title: const Text('Tempel tanda tangan'),
                onTap: () => Navigator.pop(ctx, 'place'),
              ),
              ListTile(
                leading: const Icon(Icons.brush_outlined),
                title: const Text('Buat tanda tangan baru'),
                onTap: () => Navigator.pop(ctx, 'new'),
              ),
              if (p.signature != null)
                ListTile(
                  leading: const Icon(Icons.layers_clear_outlined),
                  title: const Text('Lepas dari halaman ini'),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
            ],
          ),
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'remove') {
        setState(() => p.signature = null);
        await widget.store.save();
        return;
      }
      if (choice == 'new') {
        file = await Navigator.push<String>(
          context,
          MaterialPageRoute(builder: (_) => SignaturePadPage(store: widget.store)),
        );
        if (file == null || !mounted) return;
      }
    }
    final result = await Navigator.push<SignResult>(
      context,
      MaterialPageRoute(
        builder: (_) => SignPlacePage(page: p, signatureFile: file!, pageCount: doc.pages.length),
      ),
    );
    if (result == null) return;
    setState(() {
      for (final q in result.all ? doc.pages : [p]) {
        q.signature = result.placement;
      }
    });
    await widget.store.save();
  }

  Future<void> _setFilter(ScanFilter f) async {
    setState(() => page.filter = f);
    await widget.store.save();
  }

  Future<void> _delete() async {
    final at = _index;
    final store = widget.store;
    final removed = await store.removePage(doc, at);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    var undone = false;
    messenger
        .showSnackBar(SnackBar(
          content: const Text('Halaman dihapus'),
          action: SnackBarAction(
            label: 'Urungkan',
            onPressed: () async {
              undone = true;
              await store.restorePage(doc, at, removed);
              if (mounted) setState(() => _index = at);
            },
          ),
        ))
        .closed
        .then((_) {
      if (!undone) store.discardPage(removed);
    });
    if (doc.pages.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _index = _index.clamp(0, doc.pages.length - 1));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (doc.pages.isEmpty) return const Scaffold();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${doc.pages.length}'),
        actions: [
          _ocrBusy
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(tooltip: 'Ambil teks (OCR)', icon: const Icon(Icons.text_snippet_outlined), onPressed: _ocr),
          IconButton(tooltip: 'Putar', icon: const Icon(Icons.rotate_right), onPressed: _rotate),
          IconButton(tooltip: 'Hapus halaman', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: doc.pages.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final p = doc.pages[i];
          return InteractiveViewer(
            maxScale: 5,
            child: PageImage(page: p),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  for (final f in ScanFilter.values)
                    ChoiceChip(
                      label: Text(f.label),
                      selected: page.filter == f,
                      onSelected: (_) => _setFilter(f),
                    ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: _recrop,
                    icon: const Icon(Icons.crop),
                    label: const Text('Potong'),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: page.adjusted ? Colors.tealAccent : Colors.white),
                    onPressed: _adjust,
                    icon: const Icon(Icons.tune),
                    label: const Text('Sesuaikan'),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: page.signature != null ? Colors.tealAccent : Colors.white,
                    ),
                    onPressed: _sign,
                    icon: const Icon(Icons.draw_outlined),
                    label: const Text('Tanda tangan'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
