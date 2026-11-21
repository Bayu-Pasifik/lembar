import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'filters.dart';
import 'models.dart';
import 'store.dart';

Future<File> buildPdf(Doc doc, DocStore store, {ValueChanged<double>? onProgress}) async {
  final pdf = pw.Document(title: doc.name);
  for (var i = 0; i < doc.pages.length; i++) {
    final p = doc.pages[i];
    final r = await compute(processPage, PageJob(p.file, p.turns, p.filter, maxSide: 2400));
    const width = 595.28; // A4 width in points
    final height = width * r.height / r.width;
    final image = pw.MemoryImage(r.bytes);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(width, height),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
      ),
    );
    onProgress?.call((i + 1) / doc.pages.length);
  }
  final safe = doc.name.replaceAll(RegExp(r'[\/:*?"<>|]'), '_').trim();
  final file = await store.exportFile('${safe.isEmpty ? 'dokumen' : safe}.pdf');
  await file.writeAsBytes(await pdf.save());
  return file;
}
