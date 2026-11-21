import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:material_ui/material_ui.dart';

import 'models.dart';
import 'store.dart';

String defaultName(DateTime t) {
  const bulan = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Dokumen ${t.day} ${bulan[t.month - 1]} ${two(t.hour)}.${two(t.minute)}';
}

/// Opens the scanner and appends results to [doc] (creating one if null).
/// Returns the document, or null if the user cancelled.
Future<Doc?> scanInto(BuildContext context, DocStore store, {Doc? doc}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await CunningDocumentScanner.scanDocuments(
      scannerSource: ScannerSource.cameraAndGallery,
    );
    if (result == null || result.images.isEmpty) return null;
    final target = doc ?? await store.create(defaultName(DateTime.now()));
    await store.addPages(target, result.images);
    await CunningDocumentScanner.cleanCache();
    return target;
  } on CunningDocumentScannerException catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(e.code == 'permission_denied'
          ? 'Izin kamera ditolak. Aktifkan di pengaturan.'
          : 'Gagal memindai: ${e.message}'),
    ));
    return null;
  }
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
