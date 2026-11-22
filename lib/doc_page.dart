import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'page_image.dart';
import 'page_viewer.dart';
import 'pdf_export.dart';
import 'scan_actions.dart';
import 'store.dart';

class DocPage extends StatefulWidget {
  const DocPage({super.key, required this.store, required this.doc});
  final DocStore store;
  final Doc doc;

  @override
  State<DocPage> createState() => _DocPageState();
}

class _DocPageState extends State<DocPage> {
  bool _exporting = false;

  Doc get doc => widget.doc;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final file = await buildPdf(doc, widget.store);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: doc.name));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _filterAll() async {
    final f = await pickFilter(context, title: 'Terapkan ke semua halaman');
    if (f == null) return;
    await widget.store.applyFilterToAll(doc, f);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Filter ${f.label} diterapkan ke ${doc.pages.length} halaman')),
    );
  }

  Future<void> _addPages() async {
    await scanInto(context, widget.store, doc: doc);
    if (mounted) setState(() {});
  }

  Future<void> _open(int index) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PageViewer(store: widget.store, doc: doc, initial: index)),
    );
    if (!mounted) return;
    if (doc.pages.isEmpty) {
      await widget.store.delete(doc);
      if (mounted) Navigator.pop(context);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(doc.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Filter semua halaman',
            icon: const Icon(Icons.auto_fix_high),
            onPressed: doc.pages.isEmpty ? null : _filterAll,
          ),
          IconButton(
            tooltip: 'Ubah nama',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final n = await askName(context, doc.name);
              if (n != null) {
                doc.name = n;
                await widget.store.save();
                if (mounted) setState(() {});
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_exporting) const LinearProgressIndicator(),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
              itemCount: doc.pages.length,
              onReorderItem: (from, to) async {
                setState(() => doc.pages.insert(to, doc.pages.removeAt(from)));
                await widget.store.save();
              },
              itemBuilder: (context, i) {
                final p = doc.pages[i];
                return Card(
                  key: ValueKey(p.file),
                  clipBehavior: Clip.antiAlias,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: InkWell(
                    onTap: () => _open(i),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 64,
                            height: 84,
                            child: PageImage(page: p, maxSide: 240, thumbnail: true),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Halaman ${i + 1}', style: Theme.of(context).textTheme.titleSmall),
                                Text(p.filter.label, style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'add',
            onPressed: _exporting ? null : _addPages,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Tambah'),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'pdf',
            onPressed: _exporting ? null : _export,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Bagikan PDF'),
          ),
        ],
      ),
    );
  }
}
