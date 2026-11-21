import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import 'models.dart';

const double _docContrast = 1.8;

/// Preview-side equivalent of [processPage]'s filter.
ColorFilter? previewFilter(ScanFilter f) {
  switch (f) {
    case ScanFilter.original:
      return null;
    case ScanFilter.grayscale:
      return const ColorFilter.matrix(<double>[
        0.299, 0.587, 0.114, 0, 0, //
        0.299, 0.587, 0.114, 0, 0,
        0.299, 0.587, 0.114, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    case ScanFilter.document:
      const c = _docContrast;
      const t = 128 * (1 - c);
      return const ColorFilter.matrix(<double>[
        0.299 * c, 0.587 * c, 0.114 * c, 0, t, //
        0.299 * c, 0.587 * c, 0.114 * c, 0, t,
        0.299 * c, 0.587 * c, 0.114 * c, 0, t,
        0, 0, 0, 1, 0,
      ]);
  }
}

class PageJob {
  const PageJob(this.file, this.turns, this.filter);
  final String file;
  final int turns;
  final ScanFilter filter;
}

class PageResult {
  const PageResult(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

/// Runs in an isolate via `compute`: decode, rotate, filter, re-encode.
Future<PageResult> processPage(PageJob job) async {
  final decoded = await img.decodeImageFile(job.file);
  if (decoded == null) throw StateError('Gagal membaca gambar: ${job.file}');
  var image = img.bakeOrientation(decoded);

  final turns = job.turns % 4;
  if (turns != 0) image = img.copyRotate(image, angle: turns * 90);

  if (job.filter != ScanFilter.original) {
    image = img.grayscale(image);
    if (job.filter == ScanFilter.document) {
      for (final p in image) {
        final v = (_docContrast * (p.r - 128) + 128).clamp(0, 255);
        p
          ..r = v
          ..g = v
          ..b = v;
      }
    }
  }
  return PageResult(
    Uint8List.fromList(img.encodeJpg(image, quality: 85)),
    image.width,
    image.height,
  );
}
