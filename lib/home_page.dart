import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'doc_page.dart';
import 'models.dart';
import 'page_image.dart';
import 'scan_actions.dart';
import 'store.dart';
import 'update_check.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});
  final DocStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DocStore get store => widget.store;
  bool _searching = false;
  String _query = '';
  String? _folder;
  final Set<Doc> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(Doc d) => setState(() {
        if (!_selected.remove(d)) _selected.add(d);
      });

  Future<void> _deleteSelected() async {
    final list = _selected.toList();
    setState(_selected.clear);
    for (final d in list) {
      await store.delete(d);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${list.length} dokumen dipindah ke sampah'),
      action: SnackBarAction(
        label: 'Urungkan',
        onPressed: () async {
          for (final d in list) {
            await store.restore(d);
          }
        },
      ),
    ));
  }

  Future<void> _backup() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Membuat cadangan…')));
    try {
      final f = await store.createBackup();
      messenger.hideCurrentSnackBar();
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], subject: 'Cadangan Lembar'));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal mencadangkan: $e')));
    }
  }

  Future<void> _restore() async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['zip']);
    if (picked.isEmpty || !mounted) return;
    final path = picked.first.path;
    if (path == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pulihkan cadangan?'),
        content: const Text('Semua dokumen saat ini diganti dengan isi cadangan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pulihkan')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await store.restoreBackup(path);
      messenger.showSnackBar(SnackBar(content: Text('$n dokumen dipulihkan')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal memulihkan: $e')));
    }
  }

  Future<void> _moveSelected() async {
    final f = await askFolder(context, store, null);
    if (f == null) return;
    await store.setFolderAll(_selected, f);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _mergeSelected() async {
    // Oldest first, so pages keep their natural order.
    final list = _selected.toList()..sort((a, b) => a.created.compareTo(b.created));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gabungkan dokumen?'),
        content: Text('${list.length} dokumen digabung ke "${list.first.name}". Sisanya masuk sampah.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gabungkan')),
        ],
      ),
    );
    if (ok != true) return;
    setState(_selected.clear);
    final doc = await store.merge(list);
    if (mounted) _open(context, doc);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) runUpdateCheck(context);
    });
  }

  bool _matches(Doc d) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (d.name.toLowerCase().contains(q)) return true;
    if ((d.note ?? '').toLowerCase().contains(q)) return true;
    if (d.tags.any((t) => t.toLowerCase().contains(q))) return true;
    return d.pages.any((p) => (p.text ?? '').toLowerCase().contains(q));
  }

  Future<void> _scan(BuildContext context) async {
    final doc = await scanInto(context, store);
    if (doc != null && context.mounted) _open(context, doc);
  }

  Future<void> _import(BuildContext context) async {
    final doc = await importInto(context, store);
    if (doc != null && context.mounted) _open(context, doc);
  }

  void _open(BuildContext context, Doc doc) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DocPage(store: store, doc: doc)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        // A folder that no longer exists (renamed or emptied) falls back to "Semua".
        final folder = store.folders.contains(_folder) ? _folder : null;
        final docs = store.visibleDocs(folder: folder).where(_matches).toList();
        _selected.removeWhere((d) => d.deleted != null || !store.docs.contains(d));
        return Scaffold(
          appBar: _selecting
              ? AppBar(
                  leading: IconButton(
                    tooltip: 'Batal pilih',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_selected.clear),
                  ),
                  title: Text('${_selected.length} dipilih'),
                  actions: [
                    IconButton(
                      tooltip: 'Pilih semua',
                      icon: const Icon(Icons.select_all),
                      onPressed: () => setState(() => _selected.addAll(docs)),
                    ),
                    IconButton(
                      tooltip: 'Pindahkan ke folder',
                      icon: const Icon(Icons.folder_outlined),
                      onPressed: _moveSelected,
                    ),
                    if (_selected.length > 1)
                      IconButton(
                        tooltip: 'Gabungkan',
                        icon: const Icon(Icons.merge_type),
                        onPressed: _mergeSelected,
                      ),
                    IconButton(
                      tooltip: 'Hapus',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _deleteSelected,
                    ),
                  ],
                )
              : AppBar(
            title: _searching
                ? TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Cari nama atau isi dokumen',
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  )
                : const Text('Lembar'),
            actions: [
              IconButton(
                tooltip: _searching ? 'Tutup pencarian' : 'Cari',
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _query = '';
                }),
              ),
              PopupMenuButton<DocSort>(
                tooltip: 'Urutkan: ${store.sort.label}',
                icon: const Icon(Icons.sort),
                initialValue: store.sort,
                onSelected: store.setSort,
                itemBuilder: (_) => [
                  for (final s in DocSort.values) PopupMenuItem(value: s, child: Text(s.label)),
                ],
              ),
              PopupMenuButton<String>(
                tooltip: 'Lainnya',
                onSelected: (v) {
                  switch (v) {
                    case 'trash':
                      Navigator.push(context, MaterialPageRoute(builder: (_) => TrashPage(store: store)));
                    case 'grid':
                      store.setGrid(!store.grid);
                    case 'backup':
                      _backup();
                    case 'restore':
                      _restore();
                    default:
                      runUpdateCheck(context, manual: true);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'grid', child: Text(store.grid ? 'Tampilan daftar' : 'Tampilan kisi')),
                  const PopupMenuItem(value: 'backup', child: Text('Cadangkan semua dokumen')),
                  const PopupMenuItem(value: 'restore', child: Text('Pulihkan dari cadangan')),
                  PopupMenuItem(
                    value: 'trash',
                    child: Text(store.trash.isEmpty ? 'Sampah' : 'Sampah (${store.trash.length})'),
                  ),
                  const PopupMenuItem(value: 'update', child: Text('Cek update')),
                ],
              ),
              IconButton(
                tooltip: 'Filter bawaan: ${store.defaultFilter.label}',
                icon: const Icon(Icons.tune),
                onPressed: () async {
                  final f = await pickFilter(
                    context,
                    title: 'Filter bawaan halaman baru',
                    current: store.defaultFilter,
                  );
                  if (f != null) await store.setDefaultFilter(f);
                },
              ),
            ],
          ),
          body: Column(
            children: [
              if (store.folders.isNotEmpty)
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('Semua'),
                          selected: folder == null,
                          onSelected: (_) => setState(() => _folder = null),
                        ),
                      ),
                      for (final f in store.folders)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: const Icon(Icons.folder_outlined, size: 18),
                            label: Text(f),
                            selected: folder == f,
                            onSelected: (_) => setState(() => _folder = f),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: docs.isEmpty
                    ? (_query.trim().isEmpty && folder == null
                        ? const _Empty()
                        : const Center(child: Text('Tidak ada dokumen cocok')))
                    : store.grid
                    ? GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: docs.length,
                        itemBuilder: (context, i) => _DocGridTile(
                          doc: docs[i],
                          selected: _selected.contains(docs[i]),
                          onLongPress: () => _toggle(docs[i]),
                          onTap: () => _selecting ? _toggle(docs[i]) : _open(context, docs[i]),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
                        itemCount: docs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _DocTile(
                          doc: docs[i],
                          selecting: _selecting,
                          selected: _selected.contains(docs[i]),
                          onLongPress: () => _toggle(docs[i]),
                          onTap: () => _selecting ? _toggle(docs[i]) : _open(context, docs[i]),
                          onRename: () async {
                            final n = await askName(context, docs[i].name);
                            if (n != null) {
                              docs[i].name = n;
                              await store.save();
                            }
                          },
                          onFolder: () async {
                            final f = await askFolder(context, store, docs[i].folder);
                            if (f != null) await store.setFolder(docs[i], f);
                          },
                          onDelete: () => _confirmDelete(context, docs[i]),
                        ),
                      ),
              ),
            ],
          ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'import',
                tooltip: 'Impor gambar atau PDF',
                onPressed: () => _import(context),
                child: const Icon(Icons.file_open_outlined),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                heroTag: 'scan',
                onPressed: () => _scan(context),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Pindai'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, Doc doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus dokumen?'),
        content: Text('"${doc.name}" dan ${doc.pages.length} halamannya akan dihapus permanen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) await store.delete(doc);
  }
}

class _DocGridTile extends StatelessWidget {
  const _DocGridTile({required this.doc, required this.selected, required this.onTap, required this.onLongPress});
  final Doc doc;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final first = doc.pages.isEmpty ? null : doc.pages.first;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: selected ? t.colorScheme.secondaryContainer : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  first == null
                      ? ColoredBox(color: t.colorScheme.surfaceContainerHighest)
                      : PageImage(page: first, maxSide: 480, fit: BoxFit.cover, thumbnail: true),
                  if (selected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(Icons.check_circle, color: t.colorScheme.primary),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                  Text('${doc.pages.length} halaman',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TrashPage extends StatelessWidget {
  const TrashPage({super.key, required this.store});
  final DocStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = store.trash;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Sampah'),
            actions: [
              if (items.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Kosongkan sampah?'),
                        content: Text('${items.length} dokumen dihapus permanen.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kosongkan')),
                        ],
                      ),
                    );
                    if (ok == true) await store.emptyTrash();
                  },
                  child: const Text('Kosongkan'),
                ),
            ],
          ),
          body: items.isEmpty
              ? const Center(child: Text('Sampah kosong. Dokumen terhapus disimpan 30 hari.'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final d = items[i];
                    return ListTile(
                      title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${d.pages.length} halaman'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Pulihkan',
                            icon: const Icon(Icons.restore),
                            onPressed: () => store.restore(d),
                          ),
                          IconButton(
                            tooltip: 'Hapus permanen',
                            icon: const Icon(Icons.delete_forever_outlined),
                            onPressed: () => store.purge(d),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 72, color: t.colorScheme.outline),
            const SizedBox(height: 16),
            Text('Belum ada dokumen', style: t.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Ketuk Pindai untuk memotret kertas atau mengimpor dari galeri.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.doc,
    required this.selecting,
    required this.selected,
    required this.onLongPress,
    required this.onTap,
    required this.onRename,
    required this.onFolder,
    required this.onDelete,
  });
  final Doc doc;
  final bool selecting;
  final bool selected;
  final VoidCallback onLongPress;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onFolder;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final first = doc.pages.isEmpty ? null : doc.pages.first;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: selected ? t.colorScheme.secondaryContainer : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: selected ? t.colorScheme.primary : t.colorScheme.outline),
                ),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 56,
                  height: 72,
                  child: first == null
                      ? ColoredBox(color: t.colorScheme.surfaceContainerHighest)
                      : PageImage(page: first, maxSide: 240, fit: BoxFit.cover, thumbnail: true),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(doc.folder == null ? '${doc.pages.length} halaman' : '${doc.folder} · ${doc.pages.length} halaman',
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (!selecting)
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'rename' => onRename(),
                  'folder' => onFolder(),
                  _ => onDelete(),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Ubah nama')),
                  PopupMenuItem(value: 'folder', child: Text('Pindahkan ke folder')),
                  PopupMenuItem(value: 'delete', child: Text('Hapus')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
