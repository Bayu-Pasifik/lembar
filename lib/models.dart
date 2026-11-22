enum ScanFilter {
  original('Asli', 'Tanpa pemrosesan'),
  color('Warna', 'Hapus bayangan, warna tetap'),
  document('Dokumen', 'Hapus bayangan, hitam putih bersih'),
  grayscale('Abu-abu', 'Hanya diubah ke abu-abu');

  const ScanFilter(this.label, this.description);
  final String label;
  final String description;
}

class PageItem {
  PageItem({required this.file, this.turns = 0, this.filter = ScanFilter.document, this.text});

  String file;
  int turns;
  ScanFilter filter;

  /// Cached OCR result. Null means not recognized yet (or invalidated by rotation).
  String? text;

  Map<String, dynamic> toJson() =>
      {'file': file, 'turns': turns, 'filter': filter.name, if (text != null) 'text': text};

  factory PageItem.fromJson(Map<String, dynamic> j) => PageItem(
        file: j['file'] as String,
        text: j['text'] as String?,
        turns: j['turns'] as int? ?? 0,
        filter: ScanFilter.values.firstWhere(
          (f) => f.name == j['filter'],
          orElse: () => ScanFilter.document,
        ),
      );
}

class Doc {
  Doc({required this.id, required this.name, required this.created, List<PageItem>? pages})
      : pages = pages ?? [];

  final String id;
  String name;
  final DateTime created;
  final List<PageItem> pages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created': created.toIso8601String(),
        'pages': pages.map((p) => p.toJson()).toList(),
      };

  factory Doc.fromJson(Map<String, dynamic> j) => Doc(
        id: j['id'] as String,
        name: j['name'] as String,
        created: DateTime.parse(j['created'] as String),
        pages: (j['pages'] as List)
            .map((p) => PageItem.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}
