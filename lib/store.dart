import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'crop.dart';
import 'models.dart';

class DocStore extends ChangeNotifier {
  late final Directory _root;
  late final File _index;
  late final File _settings;
  final List<Doc> docs = [];

  /// Filter given to newly scanned pages.
  ScanFilter defaultFilter = ScanFilter.document;

  /// Saved signature PNG, or null when the user has not drawn one.
  String? signatureFile;

  Future<void> load() async {
    final base = await getApplicationDocumentsDirectory();
    _root = Directory('${base.path}/lembar');
    await _root.create(recursive: true);
    _index = File('${_root.path}/docs.json');
    _settings = File('${_root.path}/settings.json');
    if (await _settings.exists()) {
      try {
        final m = jsonDecode(await _settings.readAsString()) as Map<String, dynamic>;
        final sig = m['signatureFile'] as String?;
        if (sig != null && await File(sig).exists()) signatureFile = sig;
        defaultFilter = ScanFilter.values.firstWhere(
          (f) => f.name == m['defaultFilter'],
          orElse: () => ScanFilter.document,
        );
      } catch (_) {
        // Keep the built-in default.
      }
    }
    if (await _index.exists()) {
      try {
        final list = jsonDecode(await _index.readAsString()) as List;
        docs
          ..clear()
          ..addAll(list.map((e) => Doc.fromJson(e as Map<String, dynamic>)));
      } catch (_) {
        // Corrupt index: start empty rather than crash.
      }
    }
    docs.sort((a, b) => b.created.compareTo(a.created));
  }

  Future<void> save() async {
    await _index.writeAsString(jsonEncode(docs.map((d) => d.toJson()).toList()));
    notifyListeners();
  }

  Future<Doc> create(String name) async {
    final doc = Doc(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      created: DateTime.now(),
    );
    docs.insert(0, doc);
    await save();
    return doc;
  }

  Directory _docDir(Doc doc) => Directory('${_root.path}/${doc.id}');

  Future<String> _copyIn(Doc doc, String src, [String ext = 'jpg']) async {
    final dir = _docDir(doc);
    await dir.create(recursive: true);
    final dest = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await File(src).copy(dest);
    return dest;
  }

  /// Copies cropped shots (and the photos they came from) into permanent
  /// storage and appends them as pages.
  Future<void> addPages(Doc doc, List<ScanShot> shots) async {
    for (final s in shots) {
      final file = await _copyIn(doc, s.cropped);
      final original = s.original == null ? null : await _copyIn(doc, s.original!);
      doc.pages.add(PageItem(
        file: file,
        filter: defaultFilter,
        original: original,
        quad: s.quad?.toList(),
      ));
    }
    await save();
  }

  /// Replaces a page's crop. The first re-crop of an old page keeps its current
  /// image as the source so the crop can be widened again later.
  Future<void> recrop(Doc doc, PageItem page, String cropped, Quad quad) async {
    final old = page.file;
    page.file = await _copyIn(doc, cropped);
    if (page.original == null) {
      page.original = old;
    } else {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    page.quad = quad.toList();
    page.text = null; // OCR no longer matches the new crop
    await save();
  }

  Future<void> _saveSettings() => _settings.writeAsString(jsonEncode({
        'defaultFilter': defaultFilter.name,
        if (signatureFile != null) 'signatureFile': signatureFile,
      }));

  /// Saves a newly drawn signature (transparent PNG) and makes it the current one.
  Future<String> setSignature(Uint8List png) async {
    final file = File('${_root.path}/signature_${DateTime.now().microsecondsSinceEpoch}.png');
    await file.writeAsBytes(png);
    signatureFile = file.path;
    await _saveSettings();
    notifyListeners();
    return file.path;
  }

  Future<void> setDefaultFilter(ScanFilter f) async {
    defaultFilter = f;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> applyFilterToAll(Doc doc, ScanFilter f) async {
    for (final p in doc.pages) {
      p.filter = f;
    }
    await save();
  }

  Future<void> removePage(Doc doc, int index) async {
    final page = doc.pages.removeAt(index);
    try {
      await File(page.file).delete();
      if (page.original != null) await File(page.original!).delete();
    } catch (_) {}
    await save();
  }

  Future<void> delete(Doc doc) async {
    docs.remove(doc);
    try {
      await Directory('${_root.path}/${doc.id}').delete(recursive: true);
    } catch (_) {}
    await save();
  }

  Future<File> exportFile(String fileName) async {
    final tmp = await getTemporaryDirectory();
    return File('${tmp.path}/$fileName');
  }
}
