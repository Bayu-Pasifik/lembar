// Generates the Lembar launcher icons. Run: dart run tool/make_icon.dart
import 'dart:io';

import 'package:image/image.dart' as img;

const _bg = 0xFF1D4ED8; // blue
const _paper = 0xFFFFFFFF;
const _fold = 0xFFBFD3FF;
const _line = 0xFF93B0F5;
const _accent = 0xFFFBBF24; // amber scan corners

img.ColorUint8 _c(int argb) =>
    img.ColorUint8.rgba((argb >> 16) & 255, (argb >> 8) & 255, argb & 255, (argb >> 24) & 255);

/// Draws the glyph (paper + scan brackets) on a [size] canvas. Everything sits
/// inside the central 66% so adaptive-icon masks never clip it.
img.Image glyph(int size, {int? background, bool rounded = false}) {
  final im = img.Image(width: size, height: size, numChannels: 4);
  if (background != null) {
    if (rounded) {
      img.fillRect(im, x1: 0, y1: 0, x2: size, y2: size, color: _c(0x00000000));
      img.fillRect(im,
          x1: 0, y1: 0, x2: size, y2: size, color: _c(background), radius: size * 0.22);
    } else {
      img.fill(im, color: _c(background));
    }
  }
  final s = size / 108; // work in the 108dp adaptive grid
  int p(num v) => (v * s).round();

  // Paper
  final x1 = p(35), y1 = p(28), x2 = p(73), y2 = p(80);
  img.fillRect(im, x1: x1, y1: y1, x2: x2, y2: y2, color: _c(_paper), radius: p(3));
  // Folded corner
  img.fillPolygon(im,
      vertices: [img.Point(p(63), p(28)), img.Point(p(73), p(38)), img.Point(p(63), p(38))],
      color: _c(_fold));
  // Text lines
  for (var i = 0; i < 4; i++) {
    final y = p(47 + i * 8);
    final w = i == 3 ? p(14) : p(26);
    img.fillRect(im, x1: p(41), y1: y, x2: p(41) + w, y2: y + p(3), color: _c(_line), radius: p(1.5));
  }
  // Scan brackets around the paper
  final t = p(3.2);
  final l = p(11);
  final bx1 = p(28), by1 = p(21), bx2 = p(80), by2 = p(87);
  void bar(int ax, int ay, int bx, int by) =>
      img.fillRect(im, x1: ax, y1: ay, x2: bx, y2: by, color: _c(_accent), radius: t ~/ 2);
  // top-left
  bar(bx1, by1, bx1 + l, by1 + t);
  bar(bx1, by1, bx1 + t, by1 + l);
  // top-right
  bar(bx2 - l, by1, bx2, by1 + t);
  bar(bx2 - t, by1, bx2, by1 + l);
  // bottom-left
  bar(bx1, by2 - t, bx1 + l, by2);
  bar(bx1, by2 - l, bx1 + t, by2);
  // bottom-right
  bar(bx2 - l, by2 - t, bx2, by2);
  bar(bx2 - t, by2 - l, bx2, by2);
  return im;
}

void save(String path, img.Image im) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(im));
}

void main() {
  const res = 'android/app/src/main/res';
  const legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
  const adaptive = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432};
  legacy.forEach((d, px) {
    save('$res/mipmap-$d/ic_launcher.png', glyph(px * 4, background: _bg, rounded: true).let((i) => img.copyResize(i, width: px, interpolation: img.Interpolation.cubic)));
  });
  adaptive.forEach((d, px) {
    // Shrink so the corner brackets stay inside the circular mask (66dp safe zone).
    final big = glyph(px * 3);
    final inner = img.copyResize(big, width: (px * 3 * 0.72).round(), interpolation: img.Interpolation.cubic);
    final canvas = img.Image(width: px * 3, height: px * 3, numChannels: 4);
    img.compositeImage(canvas, inner,
        dstX: (canvas.width - inner.width) ~/ 2, dstY: (canvas.height - inner.height) ~/ 2);
    save('$res/mipmap-$d/ic_launcher_foreground.png',
        img.copyResize(canvas, width: px, interpolation: img.Interpolation.cubic));
  });
  Directory('$res/mipmap-anydpi-v26').createSync(recursive: true);
  File('$res/mipmap-anydpi-v26/ic_launcher.xml').writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''');
  File('$res/values/ic_launcher_background.xml').writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#1D4ED8</color>
</resources>
''');
  // 1024px preview / store logo
  save('assets/logo.png', glyph(1024, background: _bg, rounded: true));
  stdout.writeln('icons written');
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
