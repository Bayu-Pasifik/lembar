import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _repo = 'Bayu-Pasifik/lembar';

class UpdateInfo {
  const UpdateInfo({required this.version, required this.notes, required this.pageUrl, this.apkUrl});
  final String version;
  final String notes;
  final String pageUrl;
  final String? apkUrl;
}

/// Parses "v1.2.3+4" / "1.2.3" into comparable numeric parts (build number ignored).
List<int> parseVersion(String v) {
  final core = v.trim().replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[+-]')).first;
  return core.split('.').map((e) => int.tryParse(e) ?? 0).toList();
}

bool isNewer(String latest, String current) {
  final a = parseVersion(latest), b = parseVersion(current);
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Returns the latest release if newer than the installed version, else null.
/// Throws on network / API failure.
Future<UpdateInfo?> checkForUpdate() async {
  final current = (await PackageInfo.fromPlatform()).version;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'));
    req.headers.set('Accept', 'application/vnd.github+json');
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null; // no release published yet
    if (res.statusCode != 200) throw HttpException('GitHub HTTP ${res.statusCode}');
    final json = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String?) ?? '';
    if (!isNewer(tag, current)) return null;
    String? apk;
    for (final a in (json['assets'] as List? ?? const [])) {
      final name = (a['name'] as String?) ?? '';
      if (name.toLowerCase().endsWith('.apk')) {
        apk = a['browser_download_url'] as String?;
        break;
      }
    }
    return UpdateInfo(
      version: tag,
      notes: ((json['body'] as String?) ?? '').trim(),
      pageUrl: (json['html_url'] as String?) ?? 'https://github.com/$_repo/releases',
      apkUrl: apk,
    );
  } finally {
    client.close(force: true);
  }
}

/// [manual] true: always give feedback (up to date / error). false: silent unless update found.
Future<void> runUpdateCheck(BuildContext context, {bool manual = false}) async {
  final messenger = ScaffoldMessenger.of(context);
  UpdateInfo? info;
  try {
    info = await checkForUpdate();
  } catch (_) {
    if (manual) messenger.showSnackBar(const SnackBar(content: Text('Gagal cek update. Periksa koneksi internet.')));
    return;
  }
  if (!context.mounted) return;
  if (info == null) {
    if (manual) messenger.showSnackBar(const SnackBar(content: Text('Aplikasi sudah versi terbaru.')));
    return;
  }
  final update = info;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Update ${update.version} tersedia'),
      content: SingleChildScrollView(
        child: Text(update.notes.isEmpty ? 'Versi baru tersedia di GitHub.' : update.notes),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nanti')),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            launchUrl(Uri.parse(update.apkUrl ?? update.pageUrl), mode: LaunchMode.externalApplication);
          },
          child: Text(update.apkUrl != null ? 'Unduh APK' : 'Buka GitHub'),
        ),
      ],
    ),
  );
}
