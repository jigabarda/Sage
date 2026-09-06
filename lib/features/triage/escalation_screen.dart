import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/sage_tokens.dart';
import '../../core/sage_ui.dart';
import '../../data/triage/red_flag.dart';
import '../../data/triage/triage_rules.dart';

/// Where Tier 0 sends someone, and the end of the road for this app.
///
/// **No self-care advice appears on this screen, in any form.** Not below the
/// fold, not as a "meanwhile you could" aside. The entire purpose of the
/// triage gate is to stop Sage from suggesting a dark room to someone who
/// needs a CT scan, and a helpful-looking suggestion underneath the warning
/// undoes that completely.
///
/// It is also deliberately a dead end: there is no "continue anyway" and no
/// path from here to the guidance screen. Someone can leave with the back
/// gesture, which is theirs to do, but the app will not offer them a door.
class EscalationScreen extends StatelessWidget {
  const EscalationScreen({super.key, required this.flagCode});

  final String flagCode;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final flag = TriageRules.byCode(flagCode);

    if (flag == null) {
      // Should be unreachable. If a code ever goes missing between builds,
      // failing towards "get help" is the only acceptable direction.
      return Scaffold(
        appBar: AppBar(),
        body: const SageEmpty(
          message:
              'Something you reported needs a person to look at it. '
              'Please contact a doctor or your local emergency number.',
        ),
      );
    }

    final isEmergency = flag.urgency == RedFlagUrgency.emergency;

    return Scaffold(
      backgroundColor: isEmergency ? t.alertSoft : t.canvas,
      appBar: AppBar(
        backgroundColor: isEmergency ? t.alertSoft : t.canvas,
        title: const Text('Get this looked at'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Icon(
            isEmergency
                ? Icons.emergency_outlined
                : Icons.medical_services_outlined,
            size: 44,
            color: isEmergency ? t.alert : t.severityMid,
          ),
          Gap.h16,
          Text(
            isEmergency
                ? 'Call your local emergency number now, or get to an '
                      'emergency department.'
                : 'See a doctor about this in the next few days.',
            style: context.text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: isEmergency ? t.alert : t.ink,
            ),
          ),
          Gap.h24,
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: Radii.md,
              border: Border.all(color: t.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You said:',
                  style: context.text.labelSmall?.copyWith(color: t.inkMuted),
                ),
                Gap.h4,
                Text(
                  flag.question,
                  style: context.text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                Gap.h16,
                Text(
                  flag.because,
                  style: context.text.bodyMedium?.copyWith(
                    color: t.inkMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          Gap.h24,
          if (isEmergency) ...[
            Text(
              'If you are on your own, tell someone where you are before you '
              'do anything else.',
              style: context.text.bodyMedium?.copyWith(height: 1.45),
            ),
            Gap.h12,
          ],
          Text(
            'Sage does not give advice on this, and it cannot tell you '
            'whether it is serious. That is what the checklist is for — it '
            'points at things worth a person looking at, and stops there.',
            style: context.text.bodySmall?.copyWith(
              color: t.inkMuted,
              height: 1.45,
            ),
          ),
          Gap.h32,
          OutlinedButton(
            onPressed: () => context.go('/today'),
            child: const Text('Back to Today'),
          ),
        ],
      ),
    );
  }
}
