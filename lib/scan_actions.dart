import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'camera_page.dart';
import 'crop.dart';
import 'models.dart';
import 'pdf_export.dart';
import 'store.dart';

String defaultName(DateTime t) {
  const bulan = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Dokumen ${t.day} ${bulan[t.month - 1]} ${two(t.hour)}.${two(t.minute)}';
}

/// Opens the camera and appends results to [doc] (creating one if null).
/// Returns the document, or null if the user cancelled.
Future<Doc?> scanInto(BuildContext context, DocStore store, {Doc? doc}) async {
  final images = await Navigator.push<List<ScanShot>>(
    context,
    MaterialPageRoute(builder: (_) => const CameraPage()),
  );
  if (images == null || images.isEmpty) return null;
  final target = doc ?? await store.create(defaultName(DateTime.now()));
  await store.addPages(target, images);
  for (final s in images) {
    try {
      await File(s.cropped).delete();
    } catch (_) {}
  }
  return target;
}

/// Bottom sheet listing the filters; resolves to the chosen one (null if dismissed).
Future<ScanFilter?> pickFilter(BuildContext context, {required String title, ScanFilter? current}) {
  return showModalBottomSheet<ScanFilter>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
          ),
          for (final f in ScanFilter.values)
            ListTile(
              title: Text(f.label),
              subtitle: Text(f.description),
              trailing: f == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, f),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<String?> askName(BuildContext context, String initial) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Ubah nama'),
      content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim().isEmpty ? null : c.text.trim()),
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
}

/// Asks for paper size and quality before exporting a PDF (null if dismissed).
Future<PdfOptions?> askPdfOptions(BuildContext context) {
  var paper = PdfPaper.fit;
  var quality = PdfQuality.high;
  return showModalBottomSheet<PdfOptions>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Opsi PDF', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              const Text('Ukuran kertas'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in PdfPaper.values)
                    ChoiceChip(
                      label: Text(p.label),
                      selected: paper == p,
                      onSelected: (_) => setSheet(() => paper = p),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Kualitas'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final q in PdfQuality.values)
                    ChoiceChip(
                      label: Text(q.label),
                      selected: quality == q,
                      onSelected: (_) => setSheet(() => quality = q),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(quality.description, style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, PdfOptions(paper: paper, quality: quality)),
                  child: const Text('Buat PDF'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
