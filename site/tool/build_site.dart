// build_site.dart — assembles the SejiloChat marketing site.
//
// Why a generator instead of six hand-maintained HTML files: every page needs a
// title, a description, a canonical URL, one h1, breadcrumbs and JSON-LD that
// agree with each other and with sitemap.xml. Hand-copied <head> blocks drift —
// a canonical left pointing at the page it was copied from is the classic way a
// site de-indexes itself. Here the table below is the only place a page is
// declared, and everything else is derived from it, then verified before the
// build is allowed to succeed.
//
//   dart run tool/build_site.dart --site-url=https://sejilochat.example --out=../build/site
//
// SITE_URL has no default on purpose: canonical tags, og:url and sitemap.xml are
// absolute by specification, and a guessed hostname in a shipped page is worse
// than a build that stops and asks. For a local look, pass the address you will
// serve from (http://localhost:8080).

import 'dart:convert';
import 'dart:io';

const String siteName = 'SejiloChat';
const String orgName = 'Sejilo';

/// 1200x630, generated from the real logo by
/// sejilo_chat/tool/generate_web_icons.dart — not a stock template.
const String socialCard = '/assets/social-card.png';
const String socialCardAlt =
    'The SejiloChat logo — a mint-green speech bubble drawn as the letter S — '
    'beside the words SejiloChat and the line "Chat with or without internet", '
    'on a near-black background.';

/// One page of the site. [crumbs] lists ancestor paths, nearest last, and drives
/// both the visible breadcrumb trail and its BreadcrumbList markup.
class Page {
  const Page({
    required this.path,
    required this.source,
    required this.title,
    required this.description,
    required this.h1,
    required this.crumbLabel,
    this.navLabel,
    this.crumbs = const [],
    this.jsonLd = const [],
    this.indexable = true,
    this.priority = '0.5',
  });

  final String path;
  final String source;
  final String title;
  final String description;
  final String h1;

  /// Short label for this page inside a breadcrumb trail or nav.
  final String crumbLabel;
  final String? navLabel;
  final List<String> crumbs;
  final List<String> jsonLd;
  final bool indexable;
  final String priority;
}

/// Every page on the site. Descriptions are written to fit a search result
/// (roughly 70–160 characters) and are checked against that range below.
const List<Page> pages = [
  Page(
    path: '/',
    source: 'content/home.html',
    title: 'SejiloChat — messaging that keeps working without internet',
    description:
        'A social app for Android and Windows that sends messages over the '
        'internet, and over Bluetooth mesh between nearby phones when there is '
        'no internet at all.',
    h1: 'Messaging that keeps working when the internet does not',
    crumbLabel: 'Home',
    priority: '1.0',
    jsonLd: ['organization', 'website', 'app'],
  ),
  Page(
    path: '/features/',
    source: 'content/features.html',
    title: 'Features — SejiloChat',
    description:
        'Profiles, feed, stories, direct messages and Bluetooth mesh delivery, '
        'with the limits of each one stated plainly rather than glossed over.',
    h1: 'What SejiloChat does, and what it does not',
    crumbLabel: 'Features',
    navLabel: 'Features',
    crumbs: ['/'],
    priority: '0.8',
  ),
  Page(
    path: '/features/offline-mesh/',
    source: 'content/offline-mesh.html',
    title: 'How offline Bluetooth mesh messaging works — SejiloChat',
    description:
        'Bluetooth LE reaches 10–30 m indoors. Here is how a message is relayed '
        'between phones, why it carries a hop limit, and how a relay is stopped '
        'from altering it.',
    h1: 'How offline messaging over Bluetooth mesh works',
    crumbLabel: 'Offline mesh',
    navLabel: 'Offline mesh',
    crumbs: ['/', '/features/'],
    priority: '0.8',
    jsonLd: ['faq'],
  ),
  Page(
    path: '/download/',
    source: 'content/download.html',
    title: 'Download SejiloChat for Android and Windows',
    description:
        'Install the Android build, run the Windows desktop build, or compile '
        'from source. Includes the permissions the app asks for and why each '
        'one is needed.',
    h1: 'Get SejiloChat',
    crumbLabel: 'Download',
    navLabel: 'Download',
    crumbs: ['/'],
    priority: '0.9',
    jsonLd: ['app'],
  ),
  Page(
    path: '/privacy/',
    source: 'content/privacy.html',
    title: 'Privacy — what SejiloChat stores and where',
    description:
        'Which data reaches the server, which never leaves the device, what the '
        'cryptography actually protects, and what a Bluetooth relay can see.',
    h1: 'What SejiloChat stores, and where',
    crumbLabel: 'Privacy',
    navLabel: 'Privacy',
    crumbs: ['/'],
    priority: '0.6',
  ),
  Page(
    path: '/404.html',
    source: 'content/404.html',
    title: 'Page not found — SejiloChat',
    description:
        'That address is not part of this site. Links to the features, the '
        'offline mesh explainer, the downloads and the privacy page.',
    h1: 'That page is not here',
    crumbLabel: 'Not found',
    crumbs: ['/'],
    indexable: false,
  ),
];

// ── Entry point ───────────────────────────────────────────────────────────────

Future<int> main(List<String> args) async {
  final siteUrl = _arg(args, '--site-url') ?? Platform.environment['SITE_URL'];
  if (siteUrl == null || siteUrl.isEmpty) {
    stderr.writeln(
        'error: pass --site-url=https://your-domain (or set SITE_URL).\n'
        '       Canonical tags, og:url and sitemap.xml have to be absolute, so '
        'there is\n       nothing sensible to fall back to. For a local '
        'preview use the address you\n       will serve on, e.g. '
        '--site-url=http://localhost:8080.');
    return 2;
  }
  final site = siteUrl.endsWith('/')
      ? siteUrl.substring(0, siteUrl.length - 1)
      : siteUrl;
  final root = File.fromUri(Platform.script).parent.parent; // site/
  final out = Directory(_arg(args, '--out') ?? '${root.path}/../build/site');
  final version = _appVersion(root);

  if (out.existsSync()) out.deleteSync(recursive: true);
  out.createSync(recursive: true);

  final problems = <String>[];
  final knownPaths = pages.map((p) => p.path).toSet();
  problems.addAll(_tableProblems());

  for (final page in pages) {
    final source = File('${root.path}/${page.source}');
    if (!source.existsSync()) {
      problems.add('${page.path}: missing content file ${page.source}');
      continue;
    }
    final html = _render(page, source.readAsStringSync().trim(), site, version);
    problems.addAll(_validate(page, html, site, knownPaths));
    final target = page.path.endsWith('.html')
        ? File('${out.path}${page.path}')
        : File('${out.path}${page.path}index.html');
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(html);
  }

  _copyDir(Directory('${root.path}/assets'), Directory('${out.path}/assets'));
  _writeSitemap(out, root, site);
  _writeRobots(out, site);
  _writeLlms(out, site, version);

  // The Flutter build, if one has been made, is served at /app/. It is a single
  // canvas document with no crawlable text, which is exactly why the pages above
  // exist and why the shell asks not to be indexed.
  final app = Directory('${root.path}/../sejilo_chat/build/web');
  if (app.existsSync()) {
    _copyDir(app, Directory('${out.path}/app'));
    final stray = Directory('${out.path}/app')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.map'))
        .toList();
    for (final f in stray) {
      f.deleteSync();
    }
    if (stray.isNotEmpty) {
      stdout.writeln('  removed ${stray.length} source map(s) from /app/');
    }
  } else {
    stdout.writeln('  note: sejilo_chat/build/web is absent, so /app/ was not '
        'included.\n        Run `flutter build web --release` in sejilo_chat '
        'first if you want it.');
  }

  if (problems.isNotEmpty) {
    stderr.writeln('\n${problems.length} problem(s) — build not usable:');
    for (final p in problems) {
      stderr.writeln('  · $p');
    }
    return 1;
  }
  stdout.writeln('Built ${pages.length} pages into ${out.path} for $site');
  return 0;
}

String? _arg(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('$name=')) return a.substring(name.length + 1);
  }
  return null;
}

/// Reads `version:` out of the Flutter package so the site cannot advertise a
/// release that was never built.
String _appVersion(Directory root) {
  final pubspec = File('${root.path}/../sejilo_chat/pubspec.yaml');
  if (!pubspec.existsSync()) return '';
  final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', multiLine: true)
      .firstMatch(pubspec.readAsStringSync());
  return m == null ? '' : m.group(1)!;
}

// ── Rendering ─────────────────────────────────────────────────────────────────

String _render(Page p, String body, String site, String version) {
  final url = '$site${p.path}';
  final head = StringBuffer()
    ..writeln('<!DOCTYPE html>')
    ..writeln('<html lang="en">')
    ..writeln('<head>')
    ..writeln('<meta charset="utf-8">')
    ..writeln(
        '<meta name="viewport" content="width=device-width, initial-scale=1">')
    ..writeln('<title>${_esc(p.title)}</title>')
    ..writeln('<meta name="description" content="${_esc(p.description)}">');
  if (p.indexable) {
    head
      ..writeln('<link rel="canonical" href="$url">')
      ..writeln('<meta property="og:url" content="$url">');
  } else {
    // A 404 that can be indexed is a 404 that turns up in search results.
    head.writeln('<meta name="robots" content="noindex, follow">');
  }
  head
    ..writeln('<meta name="theme-color" content="#070A12">')
    ..writeln('<meta name="color-scheme" content="dark">')
    ..writeln('<meta property="og:type" content="website">')
    ..writeln('<meta property="og:site_name" content="$siteName">')
    ..writeln('<meta property="og:title" content="${_esc(p.title)}">')
    ..writeln(
        '<meta property="og:description" content="${_esc(p.description)}">')
    ..writeln('<meta property="og:image" content="$site$socialCard">')
    ..writeln('<meta property="og:image:width" content="1200">')
    ..writeln('<meta property="og:image:height" content="630">')
    ..writeln('<meta property="og:image:alt" content="${_esc(socialCardAlt)}">')
    ..writeln('<meta name="twitter:card" content="summary_large_image">')
    ..writeln('<meta name="twitter:title" content="${_esc(p.title)}">')
    ..writeln(
        '<meta name="twitter:description" content="${_esc(p.description)}">')
    ..writeln('<meta name="twitter:image" content="$site$socialCard">')
    ..writeln(
        '<meta name="twitter:image:alt" content="${_esc(socialCardAlt)}">')
    ..writeln('<link rel="icon" href="/assets/favicon.png" sizes="32x32" '
        'type="image/png">')
    ..writeln('<link rel="apple-touch-icon" '
        'href="/assets/apple-touch-icon.png">')
    ..writeln('<link rel="manifest" href="/assets/site.webmanifest">')
    ..writeln('<link rel="stylesheet" href="/assets/styles.css">');
  for (final block in _jsonLd(p, body, site, version)) {
    head.writeln('<script type="application/ld+json">$block</script>');
  }
  head.writeln('</head>');
  return '$head${_body(p, body, version)}';
}

/// The visible page. The skip link, the landmarks and `aria-current` are here
/// because a keyboard user hitting the same nav on every page needs a way past
/// it, and because "one clear heading" only means anything if the heading is in
/// a `<main>` a screen reader can jump to.
String _body(Page p, String body, String version) {
  final b = StringBuffer()
    ..writeln('<body>')
    ..writeln('<a class="skip" href="#main">Skip to content</a>')
    ..write(_nav(p))
    ..writeln('<main id="main">');
  if (p.crumbs.isNotEmpty) b.write(_crumbs(p));
  b
    ..writeln('<h1>${_esc(p.h1)}</h1>')
    ..writeln(body)
    ..writeln('</main>')
    ..write(_footer(version))
    ..writeln('</body>')
    ..writeln('</html>');
  return b.toString();
}

String _nav(Page p) {
  final links = StringBuffer();
  for (final n in pages.where((x) => x.navLabel != null)) {
    final current = n.path == p.path;
    links.writeln('<a href="${n.path}"'
        '${current ? ' aria-current="page"' : ''}>${_esc(n.navLabel!)}</a>');
  }
  return '''
<header class="topbar">
<a class="brand" href="/">
<img src="/assets/logo.png" width="32" height="32" alt="">
<span>$siteName</span>
</a>
<nav aria-label="Main">
$links</nav>
</header>
''';
}

/// Visible trail. Its machine-readable twin is the BreadcrumbList in
/// [_jsonLd], built from the same [Page.crumbs] list, so the two cannot
/// disagree.
String _crumbs(Page p) {
  final items = StringBuffer();
  for (final path in p.crumbs) {
    final label = pages.firstWhere((x) => x.path == path).crumbLabel;
    items.writeln('<li><a href="$path">${_esc(label)}</a></li>');
  }
  items.writeln('<li><span aria-current="page">${_esc(p.crumbLabel)}'
      '</span></li>');
  return '<nav class="crumbs" aria-label="Breadcrumb">\n<ol>\n$items</ol>\n'
      '</nav>\n';
}

String _footer(String version) => '''
<footer class="foot">
<nav aria-label="Footer">
<a href="/">Home</a>
<a href="/features/">Features</a>
<a href="/features/offline-mesh/">Offline mesh</a>
<a href="/download/">Download</a>
<a href="/privacy/">Privacy</a>
<a href="/app/">Web app</a>
</nav>
<p>$siteName is built by $orgName.${version.isEmpty ? '' : ' Current app '
        'version $version.'} No advertising, no analytics, no third-party
tracking scripts on this site.</p>
</footer>
''';

/// Escapes text that is interpolated into an attribute or into markup. Page
/// titles and descriptions contain apostrophes and dashes, and a stray `&` in
/// an attribute is an HTML validity error even when browsers forgive it.
String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

// ── Structured data ───────────────────────────────────────────────────────────

/// JSON-LD for one page.
///
/// Two rules hold everything here honest. Nothing is asserted that the site
/// cannot show: there is no `aggregateRating` because no ratings exist, no
/// `SearchAction` because the site has no search, and no `LocalBusiness` or
/// `PostalAddress` because there is no premises to describe — invented
/// LocalBusiness markup is the fastest route to a manual action. And the FAQ
/// block is read out of the rendered Q&A markup, so the answers Google is shown
/// are literally the answers on the page.
List<String> _jsonLd(Page p, String body, String site, String version) {
  final blocks = <String>[];

  if (p.jsonLd.contains('organization')) {
    blocks.add(_ld({
      '@context': 'https://schema.org',
      '@type': 'Organization',
      '@id': '$site/#organization',
      'name': orgName,
      'url': '$site/',
      'logo': {
        '@type': 'ImageObject',
        'url': '$site/assets/logo-512.png',
        'width': 512,
        'height': 512,
      },
    }));
  }

  if (p.jsonLd.contains('website')) {
    blocks.add(_ld({
      '@context': 'https://schema.org',
      '@type': 'WebSite',
      '@id': '$site/#website',
      'name': siteName,
      'url': '$site/',
      'inLanguage': 'en',
      'publisher': {'@id': '$site/#organization'},
    }));
  }

  if (p.jsonLd.contains('app')) {
    blocks.add(_ld({
      '@context': 'https://schema.org',
      '@type': 'SoftwareApplication',
      '@id': '$site/#app',
      'name': siteName,
      'applicationCategory': 'SocialNetworkingApplication',
      // Only the platforms that are actually built. There is no iOS target in
      // the repository, so claiming one here would be a lie a reviewer could
      // check in thirty seconds.
      'operatingSystem': 'Android 8.0+, Windows 10+',
      'url': '$site/',
      'installUrl': '$site/download/',
      'description': p.description,
      if (version.isNotEmpty) 'softwareVersion': version,
      'offers': {
        '@type': 'Offer',
        'price': '0',
        'priceCurrency': 'USD',
      },
      'featureList': const [
        'Direct and group messaging over the internet',
        'Bluetooth LE mesh delivery between nearby devices with no internet',
        'End-to-end encrypted message payloads signed per device',
        'Profiles, a following feed and 24-hour stories',
      ],
      'publisher': {'@id': '$site/#organization'},
      'screenshot': '$site$socialCard',
    }));
  }

  if (p.jsonLd.contains('faq')) {
    final qa = _faqPairs(body);
    if (qa.isNotEmpty) {
      blocks.add(_ld({
        '@context': 'https://schema.org',
        '@type': 'FAQPage',
        'mainEntity': [
          for (final pair in qa)
            {
              '@type': 'Question',
              'name': pair.key,
              'acceptedAnswer': {'@type': 'Answer', 'text': pair.value},
            },
        ],
      }));
    }
  }

  if (p.indexable && p.crumbs.isNotEmpty) {
    final trail = [...p.crumbs, p.path];
    blocks.add(_ld({
      '@context': 'https://schema.org',
      '@type': 'BreadcrumbList',
      'itemListElement': [
        for (var i = 0; i < trail.length; i++)
          {
            '@type': 'ListItem',
            'position': i + 1,
            'name': pages.firstWhere((x) => x.path == trail[i]).crumbLabel,
            'item': '$site${trail[i]}',
          },
      ],
    }));
  }

  return blocks;
}

/// Serialises JSON-LD, with every `<` written as its escape. Still valid JSON,
/// and it means no value can close the script element it sits inside — the
/// standard way a block like this turns into an injection point.
String _ld(Map<String, Object?> data) => const JsonEncoder.withIndent('  ')
    .convert(data)
    .replaceAll('<', '\\u003c');

/// Pulls question/answer pairs out of the rendered markup, so the FAQ rich
/// result can only ever contain text that is visible on the page. The contract
/// with the content files is one `<article class="qa">` per question, holding an
/// `<h3>` and one or more paragraphs.
List<MapEntry<String, String>> _faqPairs(String body) {
  final out = <MapEntry<String, String>>[];
  final blocks =
      RegExp(r'<article class="qa">(.*?)</article>', dotAll: true).allMatches(
    body,
  );
  for (final block in blocks) {
    final inner = block.group(1)!;
    final q = RegExp(r'<h3[^>]*>(.*?)</h3>', dotAll: true).firstMatch(inner);
    if (q == null) continue;
    final answer = _text(inner.replaceRange(q.start, q.end, ''));
    if (answer.isEmpty) continue;
    out.add(MapEntry(_text(q.group(1)!), answer));
  }
  return out;
}

/// Markup to plain text: entities back to characters, tags dropped, runs of
/// whitespace collapsed.
String _text(String html) => html
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&nbsp;', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

// ── Sitemap, robots, llms.txt ─────────────────────────────────────────────────

/// Only indexable pages are listed: a sitemap that advertises a `noindex` URL
/// is a contradiction Search Console reports back as an error. `lastmod` is the
/// content file's own modification date, so it stays truthful without anyone
/// remembering to bump it.
void _writeSitemap(Directory out, Directory root, String site) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
  for (final p in pages.where((p) => p.indexable)) {
    final source = File('${root.path}/${p.source}');
    final stamp = source.existsSync()
        ? source.lastModifiedSync().toUtc().toIso8601String().substring(0, 10)
        : null;
    b
      ..writeln('  <url>')
      ..writeln('    <loc>$site${p.path}</loc>');
    if (stamp != null) b.writeln('    <lastmod>$stamp</lastmod>');
    b
      ..writeln('    <priority>${p.priority}</priority>')
      ..writeln('  </url>');
  }
  b.writeln('</urlset>');
  File('${out.path}/sitemap.xml').writeAsStringSync(b.toString());
}

/// The app shell at /app/ is deliberately *not* disallowed. It carries
/// `noindex`, and a crawler that is blocked from fetching a URL never reads the
/// directive telling it to drop that URL — so a `Disallow` here would keep the
/// bare shell in the index instead of removing it.
void _writeRobots(Directory out, String site) {
  File('${out.path}/robots.txt').writeAsStringSync('''
User-agent: *
Allow: /

Sitemap: $site/sitemap.xml
''');
}

/// llms.txt, in the llmstxt.org shape: an H1, one blockquote summary, then
/// linked sections. The point of the file is that an assistant reading it does
/// not have to guess, so the limits are stated here as plainly as the features —
/// a model that repeats "unlimited Bluetooth range" to a user has been failed by
/// this file, not by the user.
void _writeLlms(Directory out, String site, String version) {
  final v = version.isEmpty ? 'in development' : version;
  final buf = StringBuffer()
    ..writeln('# $siteName')
    ..writeln()
    ..writeln('> A social messaging app for Android and Windows. Messages go '
        'over the internet when there is internet, and hop directly between '
        'nearby devices over Bluetooth Low Energy when there is none. Current '
        'app version: $v.')
    ..writeln()
    ..writeln('## Pages')
    ..writeln();
  for (final p in pages.where((p) => p.indexable)) {
    buf.writeln('- [${p.crumbLabel}]($site${p.path}): ${p.description}');
  }
  buf
    ..writeln()
    ..writeln('## Facts worth getting right')
    ..writeln()
    ..writeln('- Bluetooth LE carries roughly 10-30 m indoors through one hop. '
        'Range is extended only by relaying through other devices running the '
        'app, each hop adding its own 10-30 m. It is not unlimited, it does not '
        'reach a device with nobody in between, and it is not a replacement for '
        'a mobile network.')
    ..writeln('- Platforms built today: Android and Windows. There is no iOS '
        'build.')
    ..writeln('- Mesh frames are signed with Ed25519 per device and relays '
        'cannot alter them; direct sessions derive an X25519 shared secret and '
        'encrypt with ChaCha20-Poly1305.')
    ..writeln('- The app is free and has no advertising. The source is not '
        'published under an open-source licence.')
    ..writeln('- $site/app/ is the browser build of the app itself. It has no '
        'Bluetooth access, because browsers do not expose BLE advertising, so '
        'offline mesh is Android and Windows only.')
    ..writeln();
  File('${out.path}/llms.txt').writeAsStringSync(buf.toString());
}

// ── Validation ────────────────────────────────────────────────────────────────

/// Everything a hand-maintained site gets wrong, checked before the build is
/// allowed to succeed. Each rule exists because breaking it has a specific
/// consequence, named in the message.
List<String> _validate(
  Page p,
  String html,
  String site,
  Set<String> knownPaths,
) {
  final problems = <String>[];
  void check(bool ok, String message) {
    if (!ok) problems.add('${p.path}: $message');
  }

  final h1s = RegExp(r'<h1[\s>]').allMatches(html).length;
  check(h1s == 1, 'has $h1s <h1> elements; exactly one is the whole point of '
      '"one clear heading per page"');

  check(p.title.length >= 15 && p.title.length <= 65,
      'title is ${p.title.length} characters; outside 15-65 it is truncated or '
      'too thin to describe the page');
  check(p.description.length >= 70 && p.description.length <= 160,
      'description is ${p.description.length} characters; outside 70-160 a '
      'search result either cuts it off or ignores it');

  if (p.indexable) {
    check(html.contains('<link rel="canonical" href="$site${p.path}">'),
        'canonical is missing or does not point at this exact URL');
    check(!html.contains('name="robots" content="noindex'),
        'is meant to be indexed but carries noindex');
  } else {
    check(html.contains('name="robots" content="noindex'),
        'must carry noindex or it can appear in search results');
    check(!html.contains('rel="canonical"'),
        'is a noindex page and should not claim a canonical');
  }

  check(html.contains('<html lang="en">'), 'is missing a lang attribute');
  check(!RegExp(r'<script(?![^>]*application/ld\+json)').hasMatch(html),
      'contains executable JavaScript; these pages are meant to ship none');
  for (final key in p.jsonLd) {
    final type = const {
      'organization': 'Organization',
      'website': 'WebSite',
      'app': 'SoftwareApplication',
      'faq': 'FAQPage',
    }[key];
    check(type != null, 'declares unknown structured-data block "$key"');
    if (type != null) {
      check(html.contains('"@type": "$type"'),
          'declares $key but no $type block was emitted — for the FAQ that '
          'means the page has no <article class="qa"> markup to read');
    }
  }
  if (p.indexable && p.crumbs.isNotEmpty) {
    check(html.contains('"@type": "BreadcrumbList"'),
        'has a breadcrumb trail but no BreadcrumbList markup');
  }

  return problems..addAll(_contentProblems(p, html, knownPaths));
}

/// Images, links and leftover boilerplate.
List<String> _contentProblems(Page p, String html, Set<String> knownPaths) {
  final problems = <String>[];
  void check(bool ok, String message) {
    if (!ok) problems.add('${p.path}: $message');
  }

  // An <img> with no alt attribute at all is unusable; alt="" is the correct
  // marking for an image that repeats adjacent text, which is exactly the case
  // for the mark beside the wordmark in the header. Inside <main>, though, an
  // image is carrying information, so its alt has to say something.
  final main = RegExp(r'<main[^>]*>(.*)</main>', dotAll: true).firstMatch(html);
  for (final img in RegExp(r'<img\b[^>]*>').allMatches(html)) {
    final tag = img.group(0)!;
    check(RegExp(r'\salt=').hasMatch(tag), 'has an <img> with no alt '
        'attribute: $tag');
    final inMain = main != null && img.start > main.start && img.end < main.end;
    if (inMain) {
      check(!tag.contains('alt=""'),
          'has a content image with an empty alt: $tag');
    }
  }

  for (final link in RegExp(r'href="(/[^"#?]*)').allMatches(html)) {
    final href = link.group(1)!;
    if (href.startsWith('/assets/') || href == '/app/') continue;
    check(knownPaths.contains(href),
        'links to $href, which no page in this build produces');
  }
  check(!html.contains('href="http://'),
      'has an insecure http:// link, which browsers flag as mixed content');

  for (final token in const [
    '{{',
    'TODO',
    'Lorem ipsum',
    'lorem ipsum',
    'YOUR_',
    'example.com',
    'Vite',
    'Create React App',
  ]) {
    check(!html.contains(token),
        'still contains the placeholder text "$token"');
  }
  return problems;
}

/// Cross-page invariants — the ones that only exist between pages, so they
/// cannot be checked while rendering a single one.
List<String> _tableProblems() {
  final problems = <String>[];
  for (final field in const ['path', 'title', 'description', 'h1']) {
    final seen = <String, String>{};
    for (final p in pages) {
      final value = switch (field) {
        'path' => p.path,
        'title' => p.title,
        'description' => p.description,
        _ => p.h1,
      };
      final first = seen[value];
      if (first != null) {
        problems.add('$first and ${p.path} share the same $field — duplicate '
            '${field}s are the classic way two pages compete for one result');
      }
      seen[value] = p.path;
    }
  }
  final known = pages.map((p) => p.path).toSet();
  for (final p in pages) {
    for (final c in p.crumbs) {
      if (!known.contains(c)) {
        problems.add('${p.path}: breadcrumb ancestor $c is not a page');
      }
    }
  }
  return problems;
}

// ── Files ─────────────────────────────────────────────────────────────────────

void _copyDir(Directory from, Directory to) {
  if (!from.existsSync()) return;
  to.createSync(recursive: true);
  for (final entity in from.listSync(recursive: true)) {
    final rel = entity.path
        .substring(from.path.length)
        .replaceAll(r'\', '/')
        .replaceFirst(RegExp('^/'), '');
    if (entity is Directory) {
      Directory('${to.path}/$rel').createSync(recursive: true);
    } else if (entity is File) {
      final target = File('${to.path}/$rel');
      target.parent.createSync(recursive: true);
      entity.copySync(target.path);
    }
  }
}

