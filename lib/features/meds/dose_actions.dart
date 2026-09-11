import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/med.dart';
import '../../providers.dart';

/// Records a dose and offers to undo it.
///
/// Shared by every one-tap logger (the Medications screen, the card on Today,
/// and the calendar) so they all behave the same way. A mis-tap on a
/// one-tap control has to be reversible on the spot; a record someone cannot
/// correct is one they stop trusting.
Future<void> recordDoseWithUndo(
  BuildContext context,
  WidgetRef ref,
  Med med, {
  DateTime? at,
}) async {
  final repo = ref.read(medsRepositoryProvider);
  final doseId = await repo.recordDose(med.id, at: at);
  invalidateMedData(ref);
  if (!context.mounted) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('${med.name} recorded.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await repo.deleteDose(doseId);
            invalidateMedData(ref);
          },
        ),
      ),
    );
}

/// Removes a dose and offers to put it back exactly as it was.
///
/// Undo restores the original row, with its id, time and episode link, rather
/// than recording a new dose. A new dose would lose the link to the episode it
/// was taken for, and the episode would quietly stop saying which medication
/// was used.
Future<void> deleteDoseWithUndo(
  BuildContext context,
  WidgetRef ref,
  MedDose dose,
  String medName,
) async {
  final repo = ref.read(medsRepositoryProvider);
  await repo.deleteDose(dose.id);
  invalidateMedData(ref);
  if (!context.mounted) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('$medName dose removed.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await repo.restoreDose(dose);
            invalidateMedData(ref);
          },
        ),
      ),
    );
}
