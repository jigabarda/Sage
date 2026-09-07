import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sage_tokens.dart';
import '../../core/sage_ui.dart';
import '../../data/models/med.dart';
import '../../providers.dart';

/// The medications the person takes, in their own words.
///
/// There is no autocomplete, no drug database and no interaction check here,
/// and that absence is the design. A field that offered completions would
/// imply the app knew what the drug was and had checked something about it —
/// see non-negotiable 6. It stores what it is told and reproduces it verbatim
/// in the export.
class MedsScreen extends ConsumerWidget {
  const MedsScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    Med? existing,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MedSheet(existing: existing),
    );
    if (saved == true) ref.invalidate(medsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meds = ref.watch(medsProvider);
    final t = context.t;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medications'),
        actions: [
          IconButton(
            tooltip: 'Add',
            onPressed: () => _edit(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: meds.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SageEmpty(message: 'Could not read these.\n$e'),
        data: (list) {
          if (list.isEmpty) {
            return const SageEmpty(
              message:
                  'Nothing added yet.\n\n'
                  'Adding what you take lets an episode record which one you '
                  'used, and puts it in the doctor export in your own words.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.surfaceAlt,
                  borderRadius: Radii.md,
                ),
                child: Text(
                  'Sage stores these exactly as you type them. It does not '
                  'suggest doses, check interactions or know what any of it '
                  'means.',
                  style: context.text.bodySmall?.copyWith(
                    color: t.inkMuted,
                    height: 1.45,
                  ),
                ),
              ),
              Gap.h16,
              for (final m in list) ...[
                _MedRow(
                  med: m,
                  onTap: () => _edit(context, ref, existing: m),
                ),
                Gap.h8,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MedRow extends StatelessWidget {
  const _MedRow({required this.med, required this.onTap});

  final Med med;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: Radii.md,
      child: InkWell(
        borderRadius: Radii.md,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: Radii.md,
            border: Border.all(color: t.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      med.name,
                      style: context.text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        // Struck through rather than hidden: a medication no
                        // longer taken still names past doses.
                        decoration: med.active
                            ? null
                            : TextDecoration.lineThrough,
                        color: med.active ? t.ink : t.inkFaint,
                      ),
                    ),
                    Gap.h4,
                    Text(
                      [
                        med.kind.label,
                        if (med.doseText.isNotEmpty) med.doseText,
                        if (!med.active) 'no longer taken',
                      ].join(' · '),
                      style: context.text.bodySmall?.copyWith(
                        color: t.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: t.inkFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedSheet extends ConsumerStatefulWidget {
  const _MedSheet({this.existing});

  final Med? existing;

  @override
  ConsumerState<_MedSheet> createState() => _MedSheetState();
}

class _MedSheetState extends ConsumerState<_MedSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _dose = TextEditingController(
    text: widget.existing?.doseText ?? '',
  );
  late MedKind _kind = widget.existing?.kind ?? MedKind.rescue;
  late bool _active = widget.existing?.active ?? true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'A name is needed.');
      return;
    }
    final repo = ref.read(medsRepositoryProvider);
    if (widget.existing == null) {
      await repo.create(name: _name.text, doseText: _dose.text, kind: _kind);
    } else {
      await repo.update(
        widget.existing!.id,
        name: _name.text,
        doseText: _dose.text,
        kind: _kind,
        active: _active,
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final med = widget.existing!;
    final doses = await ref.read(medsRepositoryProvider).doseCount(med.id);
    if (!mounted) return;

    final t = context.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${med.name}?'),
        content: Text(
          doses == 0
              ? 'It has no recorded doses, so nothing else is affected.'
              // Named, because deleting cascades the doses away and rewrites a
              // history the person may be showing a doctor. "No longer taken"
              // is almost always what they actually want.
              : 'This also deletes $doses recorded ${doses == 1 ? 'dose' : 'doses'}, '
                    'and they will no longer appear in the doctor export. If you '
                    'have simply stopped taking it, mark it "no longer taken" '
                    'instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: t.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await ref.read(medsRepositoryProvider).delete(med.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null ? 'Add a medication' : 'Edit',
              style: context.text.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap.h16,
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            Gap.h12,
            TextField(
              controller: _dose,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'How you take it',
                // Free text on purpose. People write "two at onset" and "half
                // if it's bad"; a number and a unit would lose the
                // instruction or invent precision that was never there.
                hintText: 'e.g. two at onset — in your own words',
              ),
            ),
            Gap.h16,
            Row(
              children: [
                for (final k in MedKind.values) ...[
                  Expanded(
                    child: SageChip(
                      label: k.label,
                      selected: _kind == k,
                      onTap: () => setState(() => _kind = k),
                    ),
                  ),
                  if (k != MedKind.values.last) Gap.w8,
                ],
              ],
            ),
            Gap.h4,
            Text(
              _kind.hint,
              style: context.text.bodySmall?.copyWith(color: t.inkMuted),
            ),
            if (widget.existing != null) ...[
              Gap.h16,
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Still taking this',
                      style: context.text.bodyMedium,
                    ),
                  ),
                  Switch(
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              Gap.h12,
              Text(_error!, style: TextStyle(color: t.danger)),
            ],
            Gap.h24,
            Row(
              children: [
                if (widget.existing != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _delete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: t.danger,
                      ),
                      child: const Text('Delete'),
                    ),
                  ),
                  Gap.w12,
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
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
