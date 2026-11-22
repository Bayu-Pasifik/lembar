import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'filters.dart';
import 'models.dart';
import 'store.dart';

enum PdfPaper {
  fit('Sesuai foto', null),
  a4('A4', PdfPageFormat.a4),
  letter('Letter', PdfPageFormat.letter);

  const PdfPaper(this.label, this.format);
  final String label;
  final PdfPageFormat? format;
}

enum PdfQuality {
  high('Tinggi', 'Paling tajam, file besar', 2400, 85),
  medium('Sedang', 'Seimbang untuk dikirim lewat chat', 1600, 70),
  low('Kecil', 'File paling ringan', 1100, 55);

  const PdfQuality(this.label, this.description, this.maxSide, this.jpegQuality);
  final String label;
  final String description;

  /// Longest side of each page image in pixels.
  final int maxSide;
  final int jpegQuality;
}

class PdfOptions {
  const PdfOptions({this.paper = PdfPaper.fit, this.quality = PdfQuality.high});
  final PdfPaper paper;
  final PdfQuality quality;
}

Future<File> buildPdf(
  Doc doc,
  DocStore store, {
  PdfOptions options = const PdfOptions(),
  ValueChanged<double>? onProgress,
}) async {
  final pdf = pw.Document(title: doc.name);
  for (var i = 0; i < doc.pages.length; i++) {
    final p = doc.pages[i];
    final r = await compute(
      processPage,
      PageJob.of(p, maxSide: options.quality.maxSide, quality: options.quality.jpegQuality),
    );
    final image = pw.MemoryImage(r.bytes);
    final base = options.paper.format;
    final PdfPageFormat format;
    final pw.Widget child;
    if (base == null) {
      const width = 595.28; // A4 width in points
      format = PdfPageFormat(width, width * r.height / r.width);
      child = pw.Image(image, fit: pw.BoxFit.fill);
    } else {
      // Pick the orientation that matches the photo, then fit it inside the sheet.
      format = r.width > r.height ? base.landscape : base;
      child = pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
    }
    pdf.addPage(pw.Page(pageFormat: format, margin: pw.EdgeInsets.zero, build: (_) => child));
    onProgress?.call((i + 1) / doc.pages.length);
  }
  final safe = doc.name.replaceAll(RegExp(r'[\/:*?"<>|]'), '_').trim();
  final file = await store.exportFile('${safe.isEmpty ? 'dokumen' : safe}.pdf');
  await file.writeAsBytes(await pdf.save());
  return file;
}
