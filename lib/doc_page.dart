

import 'package:archive/archive_io.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter/foundation.dart';

import 'filters.dart';
import 'models.dart';
import 'ocr.dart';
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
    final options = await askPdfOptions(context);
    if (options == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final file = await buildPdf(doc, widget.store, options: options);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: doc.name));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareImages() async {
    setState(() => _exporting = true);
    try {
      final files = <XFile>[];
      for (var i = 0; i < doc.pages.length; i++) {
        final p = doc.pages[i];
        final r = await compute(processPage, PageJob.of(p, maxSide: 2400));
        final f = await widget.store.exportFile('${doc.id}_${i + 1}.jpg');
        await f.writeAsBytes(r.bytes);
        files.add(XFile(f.path));
      }
      await SharePlus.instance.share(ShareParams(files: files, subject: doc.name));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membagikan gambar: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareText() async {
    setState(() => _exporting = true);
    try {
      final parts = <String>[];
      for (var i = 0; i < doc.pages.length; i++) {
        final p = doc.pages[i];
        p.text ??= await recognizePage(p, widget.store);
        if (p.text!.isNotEmpty) {
          parts.add(doc.pages.length > 1 ? '--- Halaman ${i + 1} ---\n${p.text}' : p.text!);
        }
      }
      await widget.store.save();
      if (parts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Tidak ada teks terdeteksi.')));
        }
        return;
      }
      await SharePlus.instance.share(ShareParams(text: parts.join('\n\n'), subject: doc.name));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OCR gagal: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareZip() async {
    setState(() => _exporting = true);
    try {
      final tmp = await widget.store.exportFile('${doc.id}_gambar.zip');
      if (await tmp.exists()) await tmp.delete();
      final enc = ZipFileEncoder()..create(tmp.path);
      for (var i = 0; i < doc.pages.length; i++) {
        final r = await compute(processPage, PageJob.of(doc.pages[i], maxSide: 2400));
        final f = await widget.store.exportFile('${doc.id}_p${i + 1}.jpg');
        await f.writeAsBytes(r.bytes);
        await enc.addFile(f, 'halaman_${(i + 1).toString().padLeft(2, '0')}.jpg');
        await f.delete();
      }
      await enc.close();
      await SharePlus.instance.share(ShareParams(files: [XFile(tmp.path)], subject: doc.name));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membuat ZIP: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _editMeta() async {
    final note = TextEditingController(text: doc.note ?? '');
    final tags = TextEditingController(text: doc.tags.join(', '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Catatan & tag'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tags,
              decoration: const InputDecoration(labelText: 'Tag', hintText: 'pisahkan dengan koma'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Catatan'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok == true) {
      doc.note = note.text.trim();
      doc.tags
        ..clear()
        ..addAll(tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toSet());
      await widget.store.save();
      if (mounted) setState(() {});
    }
    note.dispose();
    tags.dispose();
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

Future<void> _importFiles() async {    await importInto(context, widget.store, doc: doc);    if (mounted) setState(() {});  }
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
      await widget.store.purge(doc);
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
          PopupMenuButton<String>(
            enabled: !_exporting,
            onSelected: (v) => switch (v) {
              'img' => _shareImages(),
              'import' => _importFiles(),
              'zip' => _shareZip(),
              'meta' => _editMeta(),
              _ => _shareText(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('Impor gambar/PDF ke dokumen ini')),
              PopupMenuItem(value: 'meta', child: Text('Catatan & tag')),
              PopupMenuItem(value: 'img', child: Text('Bagikan sebagai gambar')),
              PopupMenuItem(value: 'zip', child: Text('Bagikan ZIP gambar')),
              PopupMenuItem(value: 'txt', child: Text('Bagikan teks (OCR)')),
            ],
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
          if (doc.tags.isNotEmpty || (doc.note ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (doc.tags.isNotEmpty)
                      Wrap(spacing: 6, children: [for (final t in doc.tags) Chip(label: Text(t), visualDensity: VisualDensity.compact)]),
                    if ((doc.note ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(doc.note!, style: Theme.of(context).textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
            ),
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
