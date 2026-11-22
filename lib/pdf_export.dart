import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'filters.dart';
import 'models.dart';
import 'ocr.dart';
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
  const PdfOptions({this.paper = PdfPaper.fit, this.quality = PdfQuality.high, this.searchable = false});
  final PdfPaper paper;

  /// Adds an invisible OCR text layer so the PDF can be searched and selected.
  final bool searchable;
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
    if (base == null) {
      const width = 595.28; // A4 width in points
      format = PdfPageFormat(width, width * r.height / r.width);
    } else {
      // Pick the orientation that matches the photo, then fit it inside the sheet.
      format = r.width > r.height ? base.landscape : base;
    }
    // Where the photo lands on the sheet (points): filled, or contained and centred.
    final scale = base == null
        ? format.width / r.width
        : (format.width / r.width < format.height / r.height ? format.width / r.width : format.height / r.height);
    final iw = r.width * scale;
    final ih = r.height * scale;
    final ox = (format.width - iw) / 2;
    final oy = (format.height - ih) / 2;

    var lines = const <OcrLine>[];
    if (options.searchable) {
      try {
        lines = await recognizeLines(r.bytes, r.width, r.height, store);
      } catch (_) {
        // A page whose OCR fails is still exported, just not searchable.
      }
    }
    final pw.Widget child = pw.Container(
      width: format.width,
      height: format.height,
      color: PdfColors.white,
      child: pw.Stack(
        children: [
          pw.Positioned(left: ox, top: oy, child: pw.Image(image, width: iw, height: ih, fit: pw.BoxFit.fill)),
          for (final l in lines)
            if (_latin(l.text).trim().isNotEmpty)
              pw.Positioned(
                left: ox + l.left * iw,
                top: oy + l.top * ih,
                child: pw.Text(
                  _latin(l.text),
                  style: pw.TextStyle(fontSize: (l.height * ih * 0.8).clamp(4.0, 72.0), renderingMode: PdfTextRenderingMode.invisible),
                ),
              ),
        ],
      ),
    );
    pdf.addPage(pw.Page(pageFormat: format, margin: pw.EdgeInsets.zero, build: (_) => child));
    onProgress?.call((i + 1) / doc.pages.length);
  }
  final safe = doc.name.replaceAll(RegExp(r'[\/:*?"<>|]'), '_').trim();
  final file = await store.exportFile('${safe.isEmpty ? 'dokumen' : safe}.pdf');
  await file.writeAsBytes(await pdf.save());
  return file;
}

/// The built-in PDF font only covers Latin-1; drop anything else so it does not throw.
String _latin(String s) => String.fromCharCodes(s.runes.where((c) => c >= 32 && c < 256));
