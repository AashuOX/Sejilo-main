// data_storage_settings_page.dart — upload size, mesh attachments, disk use.
//
// The previous version was four inert switches ("Data Saver", "Autoplay",
// "Download over mobile data"), a "Calculating..." row that never finished, and
// a Clear cache button whose only effect was a "Cache cleared" SnackBar. There
// is no video anywhere in the app and no autoplay to gate, so those rows are
// gone. What remains is measured or read from a preference something consumes.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_preferences.dart';
import '../core/image_utils.dart';
import 'settings_section.dart';

class DataStorageSettingsPage extends StatefulWidget {
  const DataStorageSettingsPage({required this.preferences, super.key});

  final AppPreferences preferences;

  @override
  State<DataStorageSettingsPage> createState() =>
      _DataStorageSettingsPageState();
}

class _DataStorageSettingsPageState extends State<DataStorageSettingsPage> {
  int? _cacheBytes;
  int? _attachmentBytes;
  int? _attachmentCount;
  bool _measuring = true;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  /// Adds up what is actually on disk, in two buckets that are different in
  /// kind: throwaway cache, and received mesh attachments (real content).
  Future<void> _measure() async {
    if (!mounted) return;
    setState(() => _measuring = true);
    int cache = 0;
    int attachments = 0;
    int files = 0;
    try {
      final temporary = await getTemporaryDirectory();
      cache = await _directorySize(temporary);
      final documents = await getApplicationDocumentsDirectory();
      final meshDirectory = Directory(
        '${documents.path}${Platform.pathSeparator}mesh_attachments',
      );
      if (meshDirectory.existsSync()) {
        await for (final entity in meshDirectory.list(recursive: true)) {
          if (entity is File) {
            attachments += await entity.length();
            files++;
          }
        }
      }
    } on Object {
      // A platform that refuses the directory listing leaves the numbers null
      // rather than showing a guess.
      if (!mounted) return;
      setState(() {
        _measuring = false;
        _cacheBytes = null;
        _attachmentBytes = null;
        _attachmentCount = null;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _measuring = false;
      _cacheBytes = cache;
      _attachmentBytes = attachments;
      _attachmentCount = files;
    });
  }

  static Future<int> _directorySize(Directory directory) async {
    if (!directory.existsSync()) return 0;
    var total = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // Vanished between listing and measuring; skip it.
        }
      }
    }
    return total;
  }

  /// Deletes the OS temporary directory's contents only. Mesh attachments live
  /// in the documents directory and are deliberately left alone — they are the
  /// only copy of a photo somebody sent you.
  Future<void> _clearCache() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _clearing = true);
    var removed = 0;
    var failed = 0;
    try {
      final temporary = await getTemporaryDirectory();
      if (temporary.existsSync()) {
        for (final entity in temporary.listSync()) {
          try {
            if (entity is File) {
              removed += await entity.length();
              await entity.delete();
            } else if (entity is Directory) {
              removed += await _directorySize(entity);
              await entity.delete(recursive: true);
            }
          } on FileSystemException {
            failed++;
          }
        }
      }
    } on Object {
      if (mounted) setState(() => _clearing = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('The cache directory could not be opened.')),
      );
      return;
    }
    if (mounted) setState(() => _clearing = false);
    await _measure();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'Freed ${_formatBytes(removed)}.'
              : 'Freed ${_formatBytes(removed)}. $failed item(s) were in use and stayed.',
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final preferences = widget.preferences;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Data and storage',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ListenableBuilder(
        listenable: preferences,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SettingsSection(
              title: 'Uploads',
              icon: Icons.high_quality_rounded,
              children: [
                SwitchListTile(
                  value: preferences.highQualityUploads,
                  onChanged: preferences.setHighQualityUploads,
                  title: const Text('Upload photos at full size'),
                  subtitle: Text(
                    preferences.highQualityUploads
                        ? 'Posts and stories are sent with a longest edge of '
                            '${ImageUtils.maxPostDimension} px.'
                        : 'Posts and stories are shrunk to '
                            '${ImageUtils.dataSaverPostDimension} px on the '
                            'longest edge to save data.',
                  ),
                  secondary: const Icon(Icons.image_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SettingsSection(
              title: 'Mesh attachments',
              icon: Icons.download_outlined,
              children: [
                RadioGroup<AutoDownloadPolicy>(
                  groupValue: preferences.autoDownloadPolicy,
                  onChanged: (value) {
                    if (value != null) {
                      preferences.setAutoDownloadPolicy(value);
                    }
                  },
                  child: const Column(
                    children: [
                      RadioListTile<AutoDownloadPolicy>(
                        value: AutoDownloadPolicy.trustedPeers,
                        title: Text('From verified contacts'),
                        subtitle: Text(
                          'Photos are kept only when the sender is someone whose '
                          'key you have verified',
                        ),
                      ),
                      RadioListTile<AutoDownloadPolicy>(
                        value: AutoDownloadPolicy.everyone,
                        title: Text('From anyone nearby'),
                        subtitle: Text('Any photo that arrives over mesh is saved'),
                      ),
                      RadioListTile<AutoDownloadPolicy>(
                        value: AutoDownloadPolicy.never,
                        title: Text('Never'),
                        subtitle: Text(
                          'The message still arrives; the attached photo is '
                          'discarded',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SettingsSection(
              title: 'Storage',
              icon: Icons.storage_outlined,
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Cached files'),
                  subtitle: Text(
                    _measuring
                        ? 'Measuring…'
                        : _cacheBytes == null
                            ? 'This platform does not expose a cache directory.'
                            : '${_formatBytes(_cacheBytes!)} of temporary files',
                  ),
                  trailing: _measuring
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: 'Recalculate',
                          onPressed: _measure,
                        ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Clear cache'),
                  subtitle: const Text(
                    'Received photos and your messages are not touched',
                  ),
                  trailing: _clearing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  enabled: !_clearing && (_cacheBytes ?? 0) > 0,
                  onTap: _clearCache,
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Received mesh photos'),
                  subtitle: Text(
                    _measuring
                        ? 'Measuring…'
                        : _attachmentBytes == null
                            ? 'Could not be measured.'
                            : '${_formatBytes(_attachmentBytes!)} in '
                                '${_attachmentCount ?? 0} file(s) — deleted with '
                                'their message',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
