import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
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

  DocSort sort = DocSort.newest;

  /// Home screen shows thumbnails in a grid instead of a list.
  bool grid = false;

  /// Documents in the chosen order. Pass [folder] to keep only that folder.
  List<Doc> visibleDocs({String? folder}) =>
      docs.where((d) => d.deleted == null && (folder == null || d.folder == folder)).toList()..sort(sort.compare);

  /// Documents in the trash, most recently deleted first.
  List<Doc> get trash => docs.where((d) => d.deleted != null).toList()..sort((a, b) => b.deleted!.compareTo(a.deleted!));

  /// Folder names in use, sorted.
  List<String> get folders =>
      (docs.where((d) => d.deleted == null).map((d) => d.folder).whereType<String>().toSet().toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));

  Future<void> setSort(DocSort s) async {
    sort = s;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setFolder(Doc doc, String? folder) async {
    final f = folder?.trim();
    doc.folder = (f == null || f.isEmpty) ? null : f;
    await save();
  }

  Future<void> load() async {
    final base = await getApplicationDocumentsDirectory();
    _root = Directory('${base.path}/lembar');
    await _root.create(recursive: true);
    _index = File('${_root.path}/docs.json');
    _settings = File('${_root.path}/settings.json');
    await _readFiles();
  }

  Future<void> _readFiles() async {
    if (await _settings.exists()) {
      try {
        final m = jsonDecode(await _settings.readAsString()) as Map<String, dynamic>;
        sort = DocSort.values.firstWhere((s) => s.name == m['sort'], orElse: () => DocSort.newest);
        grid = m['grid'] == true;
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
    // Trash is emptied after 30 days.
    final old = docs.where((d) => d.deleted != null && DateTime.now().difference(d.deleted!).inDays >= 30).toList();
    for (final d in old) {
      await purge(d);
    }
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

  Future<String> _copyIn(Doc doc, String src) async {
    final dir = _docDir(doc);
    await dir.create(recursive: true);
    // Keep the real extension: the image decoder picks its format from it.
    final dot = src.lastIndexOf('.');
    var ext = dot > src.lastIndexOf('/') ? src.substring(dot + 1).toLowerCase() : 'jpg';
    if (ext != 'png' && ext != 'jpg' && ext != 'jpeg') ext = 'jpg';
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
        'sort': sort.name,
        'grid': grid,
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

  /// Takes a page out of the document but keeps its files, so it can be
  /// restored with [restorePage]; call [discardPage] to free the files.
  Future<PageItem> removePage(Doc doc, int index) async {
    final page = doc.pages.removeAt(index);
    await save();
    return page;
  }

  Future<void> restorePage(Doc doc, int index, PageItem page) async {
    doc.pages.insert(index.clamp(0, doc.pages.length), page);
    await save();
  }

  Future<void> discardPage(PageItem page) async {
    try {
      await File(page.file).delete();
      if (page.original != null) await File(page.original!).delete();
    } catch (_) {}
  }

  /// Moves a document to the trash.
  Future<void> delete(Doc doc) async {
    doc.deleted = DateTime.now();
    await save();
  }

  Future<void> restore(Doc doc) async {
    doc.deleted = null;
    await save();
  }

  /// Deletes a document and its files for good.
  Future<void> purge(Doc doc) async {
    docs.remove(doc);
    try {
      await _docDir(doc).delete(recursive: true);
    } catch (_) {}
    await save();
  }

  Future<void> emptyTrash() async {
    for (final d in trash) {
      docs.remove(d);
      try {
        await _docDir(d).delete(recursive: true);
      } catch (_) {}
    }
    await save();
  }

  Future<void> setFolderAll(Iterable<Doc> list, String? folder) async {
    final f = folder?.trim();
    for (final d in list) {
      d.folder = (f == null || f.isEmpty) ? null : f;
    }
    await save();
  }

  /// Appends the pages of the other documents to the first one, copying their
  /// files, and moves the sources to the trash. Returns the merged document.
  Future<Doc> merge(List<Doc> list) async {
    final target = list.first;
    for (final d in list.skip(1)) {
      for (final p in d.pages) {
        target.pages.add(PageItem(
          file: await _copyIn(target, p.file),
          original: p.original == null ? null : await _copyIn(target, p.original!),
          quad: p.quad?.toList(),
          turns: p.turns,
          filter: p.filter,
          text: p.text,
          brightness: p.brightness,
          contrast: p.contrast,
          signature: p.signature,
        ));
      }
      for (final t in d.tags) {
        if (!target.tags.contains(t)) target.tags.add(t);
      }
      if ((d.note ?? '').isNotEmpty) {
        target.note = [if ((target.note ?? '').isNotEmpty) target.note!, d.note!].join('\n');
      }
      d.deleted = DateTime.now();
    }
    await save();
    return target;
  }

  Future<void> setGrid(bool v) async {
    grid = v;
    await _saveSettings();
    notifyListeners();
  }

  /// Zips the whole library (documents, images, signature, settings).
  Future<File> createBackup() async {
    await File('${_root.path}/root.txt').writeAsString(_root.path);
    final tmp = await getTemporaryDirectory();
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final out = '${tmp.path}/lembar-backup-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}.zip';
    final enc = ZipFileEncoder()..create(out);
    await enc.addDirectory(_root, includeDirName: false);
    await enc.close();
    return File(out);
  }

  /// Replaces the library with the contents of a backup zip. Absolute paths
  /// inside the backup are rewritten to this device's storage location.
  /// Returns the number of documents restored.
  Future<int> restoreBackup(String zipPath) async {
    final tmp = await getTemporaryDirectory();
    final work = Directory('${tmp.path}/restore_${DateTime.now().microsecondsSinceEpoch}');
    await work.create(recursive: true);
    try {
      await extractFileToDisk(zipPath, work.path);
      final idx = File('${work.path}/docs.json');
      if (!await idx.exists()) throw const FormatException('Bukan berkas cadangan Lembar.');
      jsonDecode(await idx.readAsString()); // must parse before we touch anything

      final marker = File('${work.path}/root.txt');
      final oldRoot = await marker.exists() ? (await marker.readAsString()).trim() : null;

      // Clear the current library, then move the backup in.
      await for (final e in _root.list()) {
        await e.delete(recursive: true);
      }
      await for (final e in work.list()) {
        final name = e.path.split(RegExp(r'[\\/]')).last;
        if (name == 'root.txt') continue;
        await e.rename('${_root.path}/$name');
      }
      if (oldRoot != null && oldRoot != _root.path) {
        for (final f in [_index, _settings]) {
          if (await f.exists()) {
            await f.writeAsString((await f.readAsString()).replaceAll(oldRoot, _root.path));
          }
        }
      }
      signatureFile = null;
      await _readFiles();
      notifyListeners();
      return docs.where((d) => d.deleted == null).length;
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<File> exportFile(String fileName) async {
    final tmp = await getTemporaryDirectory();
    return File('${tmp.path}/$fileName');
  }
}
