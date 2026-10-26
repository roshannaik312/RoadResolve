import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/report.dart';
import '../services/driving_detector.dart';
import '../services/driving_monitor.dart';
import '../services/auth_service.dart';
import '../services/report_portal.dart';
import '../services/settings_store.dart';
import '../theme.dart';

/// The Submit button, locked while the user is driving.
class SubmitGate extends StatelessWidget {
  const SubmitGate({super.key, required this.report, this.compact = false});

  final Report report;
  final bool compact;

  /// Opens the state DOT form pre-filled with [report]. The draft is marked
  /// submitted when the site sends the driver back (see AppShell).
  static Future<void> submit(BuildContext context, Report report) async {
    final driving = context.read<DrivingMonitor>();
    final settings = context.read<SettingsStore>();
    final auth = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);
    if (!driving.canSubmit) return;
    final user = auth.user;
    try {
      final uri = await ReportPortal.buildUri(
        report,
        baseUrl: settings.portalUrl,
        name: user?.displayName,
        email: user?.email,
      );
      final ok = await ReportPortal.open(uri);
      if (!ok) throw StateError('launch failed');
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Couldn’t open the report website at ${settings.portalUrl}. '
            'Check the address in Settings.',
          ),
        ),
      );
    }
  }

  /// The website takes one report at a time, so start with the oldest draft.
  static Future<void> submitNext(BuildContext context, List<Report> drafts) {
    final oldest = drafts.reduce(
      (a, b) => a.createdAt.isBefore(b.createdAt) ? a : b,
    );
    return submit(context, oldest);
  }

  @override
  Widget build(BuildContext context) {
    final driving = context.watch<DrivingMonitor>();
    if (driving.canSubmit) {
      return FilledButton.icon(
        style: compact
            ? FilledButton.styleFrom(minimumSize: const Size(0, 44))
            : null,
        onPressed: () => submit(context, report),
        icon: const Icon(Icons.open_in_new_rounded),
        label: Text(compact ? 'Submit' : 'Submit on DOT website'),
      );
    }

    final secs = driving.secondsUntilStopped;
    final String reason = switch (driving.state) {
      DrivingState.driving when secs != null =>
        'Unlocks after you stay stopped · ${secs}s',
      DrivingState.driving => 'You appear to be driving',
      _ => 'Checking whether you are driving…',
    };

    return Semantics(
      label: 'Submit locked. $reason',
      child: Container(
        height: compact ? 44 : 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.amberSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_clock_rounded, color: AppColors.amberText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Submit when stopped',
                    style: TextStyle(
                      color: AppColors.amberText,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  if (!compact)
                    Text(
                      reason,
                      style: const TextStyle(
                        color: AppColors.amberText,
                        fontSize: 12.5,
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
