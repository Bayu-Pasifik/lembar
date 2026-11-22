import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'filters.dart';
import 'models.dart';
import 'store.dart';

/// One recognized line with its box as fractions of the image (0..1).
class OcrLine {
  const OcrLine(this.text, this.left, this.top, this.width, this.height);
  final String text;
  final double left, top, width, height;
}

/// Recognizes text lines in already-rendered upright JPEG [bytes] of size [w] x [h].
Future<List<OcrLine>> recognizeLines(Uint8List bytes, int w, int h, DocStore store) async {
  final tmp = await store.exportFile('ocrl_${DateTime.now().microsecondsSinceEpoch}.jpg');
  await tmp.writeAsBytes(bytes);
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(tmp.path));
    return [
      for (final b in result.blocks)
        for (final l in b.lines)
          OcrLine(
            l.text,
            l.boundingBox.left / w,
            l.boundingBox.top / h,
            l.boundingBox.width / w,
            l.boundingBox.height / h,
          ),
    ];
  } finally {
    await recognizer.close();
    try {
      await tmp.delete();
    } catch (_) {}
  }
}

/// Offline OCR (Latin script, model bundled with the app).
/// Rotation is baked in first so the recognizer sees the page upright.
Future<String> recognizePage(PageItem page, DocStore store) async {
  final upright = await compute(processPage, PageJob(page.file, page.turns, ScanFilter.original));
  final tmp = await store.exportFile('ocr_${DateTime.now().microsecondsSinceEpoch}.jpg');
  await tmp.writeAsBytes(upright.bytes);
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(tmp.path));
    return result.text.trim();
  } finally {
    await recognizer.close();
    try {
      await File(tmp.path).delete();
    } catch (_) {}
  }
}
