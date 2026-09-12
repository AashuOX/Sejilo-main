// generate_web_icons.dart — derives every icon and the social card from the one
// real brand asset, assets/branding/sejilo_logo.png.
//
// Why this exists: `flutter create` ships web/favicon.png, web/icons/Icon-192.png
// and web/icons/Icon-512.png containing the Flutter logo, and they are easy to
// forget. Shipping them means the browser tab, the PWA install prompt and every
// shared link show a framework's logo instead of the product's — the single most
// visible "nobody finished this" tell a site can have.
//
//   dart run tool/generate_web_icons.dart
//
// Regenerate after changing the logo. Output is committed, so neither the site
// build nor CI needs Chrome or this script.

import 'dart:io';

import 'package:image/image.dart';

/// Brand background, from SejiloColors.background in
/// lib/design_system/sejilo_theme.dart. Icons sit on it rather than on
/// transparency: a transparent favicon on a light tab strip shows a dark mark on
/// white, which is not what the mark was drawn for.
const int bgR = 0x07, bgG = 0x0A, bgB = 0x12;

Future<int> main() async {
  final tool = File.fromUri(Platform.script).parent;
  final app = tool.parent; // sejilo_chat/
  final site = Directory('${app.path}/../site/assets');
  final logoFile = File('${app.path}/assets/branding/sejilo_logo.png');

  if (!logoFile.existsSync()) {
    stderr.writeln('error: ${logoFile.path} is missing.');
    return 2;
  }
  final source = decodePng(logoFile.readAsBytesSync());
  if (source == null) {
    stderr.writeln('error: could not decode ${logoFile.path}.');
    return 2;
  }
  site.createSync(recursive: true);

  // The source is a small mark centred in a large dark square. Cropping to the
  // mark first is what stops every icon below from being mostly empty space.
  final mark = _transparentMark(source);
  stdout.writeln('mark cropped to ${mark.width}x${mark.height}');

  final outputs = <String, Image>{
    // The app shell. These three are the Flutter defaults being replaced.
    '${app.path}/web/favicon.png': _plate(mark, 32, 0.74),
    '${app.path}/web/icons/Icon-192.png': _plate(mark, 192, 0.76),
    '${app.path}/web/icons/Icon-512.png': _plate(mark, 512, 0.76),
    // Maskable icons are cropped to a circle or squircle by the launcher, so the
    // mark has to stay inside the middle ~60% to survive it intact.
    '${app.path}/web/icons/Icon-maskable-192.png': _plate(mark, 192, 0.54),
    '${app.path}/web/icons/Icon-maskable-512.png': _plate(mark, 512, 0.54),
    '${app.path}/web/apple-touch-icon.png': _plate(mark, 180, 0.72),
    // The static site.
    '${site.path}/favicon.png': _plate(mark, 32, 0.74),
    '${site.path}/apple-touch-icon.png': _plate(mark, 180, 0.72),
    '${site.path}/icon-192.png': _plate(mark, 192, 0.76),
    '${site.path}/icon-512.png': _plate(mark, 512, 0.76),
    // Organization.logo in the JSON-LD, and the header mark. The header one
    // keeps its transparency because it sits on the page's own surface colour.
    '${site.path}/logo-512.png': _plate(mark, 512, 0.82),
    '${site.path}/logo.png': copyResize(mark,
        width: 64, height: 64, interpolation: Interpolation.cubic),
  };

  for (final entry in outputs.entries) {
    final file = File(entry.key);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(encodePng(entry.value, level: 9));
    stdout.writeln('  wrote ${file.path} '
        '(${entry.value.width}x${entry.value.height})');
  }

  return await _socialCard(tool, site, mark);
}

/// Crops [source] to the mark and lifts it off its background.
///
/// The brand file is a small mint mark centred in a large near-black square.
/// Alpha is taken from luminance and the colour is then un-premultiplied — the
/// mark was composited over near-black, so dividing by the alpha recovers the
/// original mint and its gradient instead of leaving a dark fringe around every
/// curve.
Image _transparentMark(Image source) {
  final src = source.convert(numChannels: 4);
  const int floor = 18, ceiling = 170, edge = 40;

  var minX = src.width, minY = src.height, maxX = -1, maxY = -1;
  for (final p in src) {
    final luma = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
    if (luma <= edge) continue;
    if (p.x < minX) minX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.x > maxX) maxX = p.x;
    if (p.y > maxY) maxY = p.y;
  }
  if (maxX < 0) throw StateError('the logo appears to be a blank image');

  // A little air around the mark, and a square crop so no later resize squashes
  // it.
  final pad = ((maxX - minX + maxY - minY) / 2 * 0.04).round();
  final side = [maxX - minX + 1, maxY - minY + 1].reduce((a, b) => a > b ? a : b)
      + pad * 2;
  final cx = (minX + maxX) ~/ 2, cy = (minY + maxY) ~/ 2;
  final cropped = copyCrop(
    src,
    x: cx - side ~/ 2,
    y: cy - side ~/ 2,
    width: side,
    height: side,
  );

  final out = Image(width: side, height: side, numChannels: 4);
  for (final p in cropped) {
    final luma = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
    final alpha =
        ((luma - floor) / (ceiling - floor) * 255).clamp(0, 255).round();
    if (alpha == 0) {
      out.setPixelRgba(p.x, p.y, 0, 0, 0, 0);
      continue;
    }
    final scale = 255 / alpha;
    out.setPixelRgba(
      p.x,
      p.y,
      (p.r * scale).clamp(0, 255).round(),
      (p.g * scale).clamp(0, 255).round(),
      (p.b * scale).clamp(0, 255).round(),
      alpha,
    );
  }
  return out;
}

/// The mark centred on a brand-coloured square of [size] px, occupying
/// [fraction] of the width.
Image _plate(Image mark, int size, double fraction) {
  final plate = Image(width: size, height: size, numChannels: 4);
  fill(plate, color: ColorRgba8(bgR, bgG, bgB, 255));
  final inner = (size * fraction).round();
  final scaled = copyResize(mark,
      width: inner, height: inner, interpolation: Interpolation.cubic);
  compositeImage(plate, scaled,
      dstX: (size - inner) ~/ 2, dstY: (size - inner) ~/ 2);
  return plate;
}

/// Renders tool/social_card.html at exactly 1200x630 with headless Chrome.
///
/// Chrome rather than a drawing loop because the card is mostly type, and the
/// bitmap fonts bundled with the `image` package look like what they are. The
/// result is committed, so this only has to run when the wording or the logo
/// changes.
Future<int> _socialCard(Directory tool, Directory site, Image mark) async {
  final chrome = _chrome();
  if (chrome == null) {
    stderr.writeln('\nerror: no Chrome or Edge found for rendering the social '
        'card.\n       Set CHROME_PATH=/path/to/chrome and run this again. The '
        'icons above\n       were written; only assets/social-card.png was '
        'skipped.');
    return 1;
  }

  final work = Directory.systemTemp.createTempSync('sejilo-card');
  try {
    final template = File('${tool.path}/social_card.html');
    if (!template.existsSync()) {
      stderr.writeln('error: ${template.path} is missing.');
      return 2;
    }
    File('${work.path}/card.html').writeAsStringSync(template.readAsStringSync());
    File('${work.path}/mark.png').writeAsBytesSync(encodePng(
        copyResize(mark,
            width: 320, height: 320, interpolation: Interpolation.cubic),
        level: 9));

    final target = '${site.path}/social-card.png';
    final result = await Process.run(chrome, [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      '--window-size=1200,630',
      '--screenshot=$target',
      'file:///${work.path.replaceAll(r'\', '/')}/card.html',
    ]);
    final png = File(target);
    if (!png.existsSync()) {
      stderr.writeln('error: Chrome did not produce $target\n'
          '${result.stderr}');
      return 1;
    }
    final card = decodePng(png.readAsBytesSync())!;
    if (card.width != 1200 || card.height != 630) {
      stderr.writeln('error: the card came out ${card.width}x${card.height}; '
          'og:image is declared as 1200x630');
      return 1;
    }
    stdout.writeln('  wrote $target (1200x630)');
    return 0;
  } finally {
    work.deleteSync(recursive: true);
  }
}

String? _chrome() {
  final candidates = [
    Platform.environment['CHROME_PATH'],
    r'C:\Program Files\Google\Chrome\Application\chrome.exe',
    r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ];
  for (final c in candidates) {
    if (c != null && c.isNotEmpty && File(c).existsSync()) return c;
  }
  return null;
}
