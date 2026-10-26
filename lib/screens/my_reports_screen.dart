import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/driving_monitor.dart';
import '../services/report_store.dart';
import '../widgets/common.dart';
import '../widgets/submit_gate.dart';
import 'report_detail_screen.dart';
import 'voice_report_screen.dart';

enum ReportsTab { drafts, submitted }

class MyReportsScreen extends StatelessWidget {
  const MyReportsScreen({super.key, required this.tab, required this.onTab});

  final ReportsTab tab;
  final ValueChanged<ReportsTab> onTab;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ReportStore>();
    final driving = context.watch<DrivingMonitor>();
    final drafts = store.drafts;
    final submitted = store.mine.where((r) => !r.isDraft).toList();
    final list = tab == ReportsTab.drafts ? drafts : submitted;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SegmentedButton<ReportsTab>(
          style: SegmentedButton.styleFrom(minimumSize: const Size(0, 46)),
          segments: [
            ButtonSegment(
              value: ReportsTab.drafts,
              icon: const Icon(Icons.edit_note_rounded),
              label: Text('Drafts (${drafts.length})'),
            ),
            ButtonSegment(
              value: ReportsTab.submitted,
              icon: const Icon(Icons.send_rounded),
              label: Text('Submitted (${submitted.length})'),
            ),
          ],
          selected: {tab},
          onSelectionChanged: (s) => onTab(s.first),
        ),
        const SizedBox(height: 14),
        if (tab == ReportsTab.drafts && drafts.isNotEmpty) ...[
          if (!driving.canSubmit)
            const SafetyBanner(
              icon: Icons.lock_clock_rounded,
              text:
                  "Drafts are safe here. Submitting unlocks once you've stopped driving.",
            )
          else if (drafts.length > 1)
            FilledButton.icon(
              onPressed: () => SubmitGate.submitNext(context, drafts),
              icon: const Icon(Icons.send_rounded),
              label: Text('Submit drafts one by one (${drafts.length})'),
            ),
          const SizedBox(height: 12),
        ],
        if (list.isEmpty)
          EmptyState(
            icon: tab == ReportsTab.drafts
                ? Icons.inbox_rounded
                : Icons.outbox_rounded,
            title: tab == ReportsTab.drafts
                ? 'No drafts'
                : 'Nothing submitted yet',
            message: tab == ReportsTab.drafts
                ? 'Reports you make by voice or Siri are saved here until you submit them.'
                : 'Submitted reports and their status updates appear here.',
            action: FilledButton.icon(
              onPressed: () => VoiceReportScreen.open(context),
              icon: const Icon(Icons.mic_rounded),
              label: const Text('Report a hazard'),
            ),
          )
        else
          for (final r in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ReportCard(
                report: r,
                onTap: () => ReportDetailScreen.open(context, r),
                footer: r.isDraft ? SubmitGate(report: r, compact: true) : null,
              ),
            ),
      ],
    );
  }
}
