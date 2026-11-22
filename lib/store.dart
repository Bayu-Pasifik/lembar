import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class DocStore extends ChangeNotifier {
  late final Directory _root;
  late final File _index;
  late final File _settings;
  final List<Doc> docs = [];

  /// Filter given to newly scanned pages.
  ScanFilter defaultFilter = ScanFilter.document;

  Future<void> load() async {
    final base = await getApplicationDocumentsDirectory();
    _root = Directory('${base.path}/lembar');
    await _root.create(recursive: true);
    _index = File('${_root.path}/docs.json');
    _settings = File('${_root.path}/settings.json');
    if (await _settings.exists()) {
      try {
        final m = jsonDecode(await _settings.readAsString()) as Map<String, dynamic>;
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

  /// Copies scanner cache files into permanent storage and appends them as pages.
  Future<void> addPages(Doc doc, List<String> sources) async {
    final dir = Directory('${_root.path}/${doc.id}');
    await dir.create(recursive: true);
    for (final src in sources) {
      final name = '${DateTime.now().microsecondsSinceEpoch}.jpg';
      final dest = '${dir.path}/$name';
      await File(src).copy(dest);
      doc.pages.add(PageItem(file: dest, filter: defaultFilter));
    }
    await save();
  }

  Future<void> setDefaultFilter(ScanFilter f) async {
    defaultFilter = f;
    await _settings.writeAsString(jsonEncode({'defaultFilter': f.name}));
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
