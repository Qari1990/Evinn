import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../app_config.dart';

/// In-app auto-update for the sideloaded Android build.
///
/// On launch it asks GitHub for the latest Release of the configured repo. The
/// release tag is "build-<N>" where N is the Android versionCode of that build.
/// If N is greater than the installed versionCode, it offers to download the
/// attached APK and launch the system installer.
class UpdateService {
  static Future<void> checkAndPrompt(BuildContext context, {bool silent = true}) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final installed = int.tryParse(info.buildNumber) ?? 0;

      final uri = Uri.parse(
          'https://api.github.com/repos/${AppConfig.githubOwner}/${AppConfig.githubRepo}/releases/latest');
      final r = await http.get(uri, headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return;

      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '').toString(); // e.g. build-7
      final latest = int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final assets = (j['assets'] as List?) ?? [];
      final apk = assets.cast<Map<String, dynamic>>().firstWhere(
            (a) => (a['name'] ?? '').toString().toLowerCase().endsWith('.apk'),
            orElse: () => {},
          );
      final apkUrl = (apk['browser_download_url'] ?? '').toString();

      if (latest <= installed || apkUrl.isEmpty) return; // up to date
      if (!context.mounted) return;

      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Update available'),
          content: Text('A newer version of ${AppConfig.appName} is available '
              '(build $latest, you have ${installed == 0 ? '—' : installed}). Update now?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
          ],
        ),
      );
      if (go == true && context.mounted) await _downloadAndInstall(context, apkUrl, latest);
    } catch (_) {
      // Update check is best-effort; never block the app.
    }
  }

  static Future<void> _downloadAndInstall(BuildContext context, String url, int build) async {
    final progress = ValueNotifier<double>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Downloading update…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, p, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: p > 0 ? p : null),
            const SizedBox(height: 10),
            Text(p > 0 ? '${(p * 100).round()}%' : 'Starting…'),
          ]),
        ),
      ),
    );

    try {
      final req = http.Request('GET', Uri.parse(url));
      final resp = await req.send();
      final total = resp.contentLength ?? 0;
      final dir = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      final file = File('${dir.path}/evinn-build-$build.apk');
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) progress.value = received / total;
      }
      await sink.close();

      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      await OpenFilex.open(file.path); // launches the system package installer
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    }
  }
}
