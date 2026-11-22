import 'package:material_ui/material_ui.dart';

import 'doc_page.dart';
import 'models.dart';
import 'page_image.dart';
import 'scan_actions.dart';
import 'store.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.store});
  final DocStore store;

  Future<void> _scan(BuildContext context) async {
    final doc = await scanInto(context, store);
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
        final docs = store.docs;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Lembar'),
            actions: [
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
          body: docs.isEmpty
              ? const _Empty()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _DocTile(
                    doc: docs[i],
                    onTap: () => _open(context, docs[i]),
                    onRename: () async {
                      final n = await askName(context, docs[i].name);
                      if (n != null) {
                        docs[i].name = n;
                        await store.save();
                      }
                    },
                    onDelete: () => _confirmDelete(context, docs[i]),
                  ),
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _scan(context),
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Pindai'),
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
  const _DocTile({required this.doc, required this.onTap, required this.onRename, required this.onDelete});
  final Doc doc;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final first = doc.pages.isEmpty ? null : doc.pages.first;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
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
                    Text('${doc.pages.length} halaman',
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Ubah nama')),
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
