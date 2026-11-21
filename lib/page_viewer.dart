import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'ocr.dart';
import 'page_image.dart';
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

  Future<void> _setFilter(ScanFilter f) async {
    setState(() => page.filter = f);
    await widget.store.save();
  }

  Future<void> _delete() async {
    await widget.store.removePage(doc, _index);
    if (!mounted) return;
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Wrap(
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
        ),
      ),
    );
  }
}
