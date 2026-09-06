import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/sage_tokens.dart';
import '../../core/sage_ui.dart';
import '../../providers.dart';

/// Shows the export in full before any of it leaves the phone.
///
/// The preview is not decoration. This is the one screen in Sage that moves
/// health data off the device, and it does so through whatever app the person
/// picks from the share sheet — email, chat, a file manager. Handing that over
/// without showing exactly what is in it would make the app's "everything
/// stays here" promise depend on the user trusting a button.
///
/// So: read it, then decide.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  bool _busy = false;

  Future<void> _share(String report) async {
    setState(() => _busy = true);
    try {
      // Written to the cache directory rather than anywhere durable: the file
      // is a hand-off, not a second copy of the log to be looked after. The
      // system clears it.
      final dir = await getTemporaryDirectory();
      final name = ref.read(exportServiceProvider).suggestedFileName;
      final file = File('${dir.path}/$name');
      await file.writeAsString(report);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/plain')],
          subject: 'Migraine and reflux log',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not share the file. $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String report) async {
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final report = ref.watch(exportReportProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Share with a doctor')),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SageEmpty(message: 'Could not build the export.\n$e'),
        data: (text) => Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              decoration: BoxDecoration(
                color: t.surfaceAlt,
                borderRadius: Radii.md,
              ),
              child: Text(
                'This is everything that will be sent. Nothing leaves your '
                'phone until you pick something from the share sheet.',
                style: context.text.bodySmall?.copyWith(
                  color: t.inkMuted,
                  height: 1.4,
                ),
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: Radii.md,
                  border: Border.all(color: t.line),
                ),
                // Horizontally scrollable: the report is laid out in fixed
                // columns and wrapping it would destroy the alignment that
                // makes it scannable.
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      text,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _copy(text),
                      child: const Text('Copy'),
                    ),
                  ),
                  Gap.w12,
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _share(text),
                      child: Text(_busy ? 'Preparing...' : 'Share'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
