import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'filters.dart';
import 'models.dart';
import 'store.dart';

const _noFilter = ColorFilter.mode(Colors.transparent, BlendMode.dst);

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

  Future<void> _rotate() async {
    setState(() => page.turns = (page.turns + 1) % 4);
    await widget.store.save();
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
            child: Center(
              child: ColorFiltered(
                colorFilter: previewFilter(p.filter) ?? _noFilter,
                child: RotatedBox(
                  quarterTurns: p.turns,
                  child: Image.file(File(p.file), fit: BoxFit.contain),
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final f in ScanFilter.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(f.label),
                    selected: page.filter == f,
                    onSelected: (_) => _setFilter(f),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
