import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/sage_tokens.dart';
import '../../core/sage_ui.dart';
import '../../data/backup/backup_service.dart';
import '../../providers.dart';

/// Save a copy of everything, or put one back.
///
/// The two halves are deliberately unequal in weight. Saving is one tap.
/// Restoring is a file picker, then a summary of what is in the file, then a
/// dialog that names what is about to be destroyed — because it replaces the
/// log rather than merging into it.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  String? _message;

  BackupService get _service => ref.read(backupServiceProvider);

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final json = await _service.export();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_service.suggestedFileName}');
      await file.writeAsString(json);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'Sage backup',
        ),
      );
      if (mounted) {
        setState(
          () => _message =
              'Saved. Keep it somewhere that is not this phone — a backup that '
              'only exists on the device it backs up is not a backup.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not save the backup. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _message = null);

    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Sage backup', extensions: ['json']),
      ],
    );
    if (file == null) return;

    setState(() => _busy = true);
    try {
      final json = await file.readAsString();
      // Parsed and validated before anything is destroyed, so a bad file
      // fails harmlessly and an unreadable one never gets as far as a
      // confirmation dialog.
      final summary = _service.inspect(json);
      if (!mounted) return;

      final confirmed = await _confirm(summary);
      if (confirmed != true || !mounted) {
        setState(() => _busy = false);
        return;
      }

      await _service.restore(json);
      if (!mounted) return;

      // Everything downstream reads the tables that were just replaced.
      invalidateEpisodeData(ref);
      invalidateDailyData(ref);
      // Meds and doses were replaced too.
      invalidateMedData(ref);

      setState(
        () => _message =
            'Restored ${summary.episodes} episodes and ${summary.loggedDays} '
            'days of context.',
      );
    } on BackupError catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not restore that file. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(BackupSummary summary) {
    final t = context.t;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace everything?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This backup holds ${summary.episodes} episodes and '
              '${summary.loggedDays} days of context.',
            ),
            Gap.h12,
            // Named plainly. A restore is the one action in Sage that can
            // destroy data the user cannot get back.
            Text(
              'Everything currently in the app will be deleted and replaced. '
              'Anything logged since this backup was made will be lost.',
              style: TextStyle(color: t.danger),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: t.danger),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.surfaceAlt,
              borderRadius: Radii.md,
            ),
            child: Text(
              'Sage keeps everything on this phone and nowhere else. That is '
              'the point of it — and it means losing the phone loses the log '
              'unless you have a copy.',
              style: context.text.bodySmall?.copyWith(
                color: t.inkMuted,
                height: 1.45,
              ),
            ),
          ),
          Gap.h24,
          SageSection(
            title: 'Save a copy',
            hint:
                'A complete file you can put back later. Not the same as '
                'the doctor export, which is written to be read rather than '
                'restored.',
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save a backup'),
            ),
          ),
          Gap.h32,
          SageSection(
            title: 'Put one back',
            hint:
                'Replaces everything in the app with the contents of a '
                'backup file. It does not merge.',
            child: OutlinedButton(
              onPressed: _busy ? null : _restore,
              child: const Text('Restore from a file'),
            ),
          ),
          if (_message != null) ...[
            Gap.h24,
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.accentSoft,
                borderRadius: Radii.md,
              ),
              child: Text(
                _message!,
                style: context.text.bodySmall?.copyWith(height: 1.45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
