enum ScanFilter {
  original('Asli', 'Tanpa pemrosesan'),
  color('Warna', 'Hapus bayangan, warna tetap'),
  document('Dokumen', 'Hapus bayangan, hitam putih bersih'),
  grayscale('Abu-abu', 'Hanya diubah ke abu-abu');

  const ScanFilter(this.label, this.description);
  final String label;
  final String description;
}

/// Where a signature sits on a page: centre (x, y) and width, all as fractions
/// of the page size.
class SignaturePlacement {
  const SignaturePlacement(this.file, this.x, this.y, this.width);

  /// PNG of the signature (transparent background).
  final String file;
  final double x;
  final double y;
  final double width;

  Map<String, dynamic> toJson() => {'file': file, 'x': x, 'y': y, 'w': width};

  factory SignaturePlacement.fromJson(Map<String, dynamic> j) => SignaturePlacement(
        j['file'] as String,
        (j['x'] as num).toDouble(),
        (j['y'] as num).toDouble(),
        (j['w'] as num).toDouble(),
      );
}

class PageItem {
  PageItem({
    required this.file,
    this.turns = 0,
    this.filter = ScanFilter.document,
    this.text,
    this.original,
    this.quad,
    this.brightness = 0,
    this.contrast = 1,
    this.signature,
  });

  /// The cropped page image that everything else renders from.
  String file;
  int turns;
  ScanFilter filter;

  /// Cached OCR result. Null means not recognized yet (or invalidated by rotation).
  String? text;

  /// Full photo the crop was taken from, kept so the crop can be edited later.
  String? original;

  /// Crop corners on [original]: tl, tr, br, bl as x,y pairs (0..1).
  List<double>? quad;

  /// -0.5..0.5, added after the filter.
  double brightness;

  /// 0.5..2.0, 1 = unchanged.
  double contrast;

  SignaturePlacement? signature;

  bool get adjusted => brightness != 0 || contrast != 1;

  /// Everything that changes how the page looks; used as a cache key.
  String get renderKey =>
      '$file|$turns|${filter.name}|$brightness|$contrast|${signature?.file}|${signature?.x}|${signature?.y}|${signature?.width}';

  Map<String, dynamic> toJson() => {
        'file': file,
        'turns': turns,
        'filter': filter.name,
        if (text != null) 'text': text,
        if (original != null) 'original': original,
        if (quad != null) 'quad': quad,
        if (brightness != 0) 'brightness': brightness,
        if (contrast != 1) 'contrast': contrast,
        if (signature != null) 'signature': signature!.toJson(),
      };

  factory PageItem.fromJson(Map<String, dynamic> j) => PageItem(
        file: j['file'] as String,
        text: j['text'] as String?,
        turns: j['turns'] as int? ?? 0,
        filter: ScanFilter.values.firstWhere(
          (f) => f.name == j['filter'],
          orElse: () => ScanFilter.document,
        ),
        original: j['original'] as String?,
        quad: (j['quad'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        brightness: (j['brightness'] as num?)?.toDouble() ?? 0,
        contrast: (j['contrast'] as num?)?.toDouble() ?? 1,
        signature: j['signature'] == null
            ? null
            : SignaturePlacement.fromJson(j['signature'] as Map<String, dynamic>),
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
