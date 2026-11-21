import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'filters.dart';
import 'models.dart';
import 'store.dart';

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
