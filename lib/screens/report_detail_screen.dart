import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/hazard.dart';
import '../models/report.dart';
import '../services/driving_monitor.dart';
import '../services/report_store.dart';
import '../services/triage_engine.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/hazard_pin.dart';
import '../widgets/photo_picker.dart';
import '../widgets/submit_gate.dart';

class ReportDetailScreen extends StatelessWidget {
  const ReportDetailScreen({super.key, required this.reportId});
  final String reportId;

  static Future<void> open(BuildContext context, Report r) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => ReportDetailScreen(reportId: r.id)));

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ReportStore>();
    final driving = context.watch<DrivingMonitor>();
    final report = store.byId(reportId);
    if (report == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.delete_outline_rounded,
          title: 'Report removed',
          message: 'This report no longer exists.',
        ),
      );
    }
    final triage = TriageEngine.evaluate(report);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: Text(report.isDraft ? 'Review draft' : 'Report details'),
        actions: [
          if (report.isDraft || !report.isSample)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _confirmDelete(context, store, report),
            ),
        ],
      ),
      bottomNavigationBar: _BottomAction(report: report, triage: triage),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _Header(report: report, canEdit: driving.canSubmit && report.isDraft),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              HazardBadge(report.hazard),
              StatusBadge(report.status),
              if (report.source == ReportSource.siri)
                const Pill(
                  label: 'via Siri',
                  icon: Icons.mic_rounded,
                  foreground: Color(0xFF7C3AED),
                  background: Color(0xFFEDE9FE),
                ),
              if (report.isSample)
                Pill(
                  label: 'Sample data',
                  foreground: muted,
                  background: muted.withValues(alpha: 0.08),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            triage.headline,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.place_outlined, size: 16, color: muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  [
                    report.placeLabel,
                    if (report.locality != null) report.locality,
                  ].join(', '),
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 16, color: muted),
              const SizedBox(width: 4),
              Text(
                DateFormat('MMM d, h:mm a').format(report.createdAt),
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (report.isDraft) ...[
            _DraftEditor(report: report, locked: !driving.canSubmit),
            const SizedBox(height: 12),
          ] else if (report.description.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  report.description,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _TriageCard(triage: triage),
          const SizedBox(height: 12),
          _ResponseCard(triage: triage),
          if (report.hasLocation) ...[
            const SizedBox(height: 12),
            _MiniMap(report: report),
          ],
          const SizedBox(height: 12),
          _Timeline(report: report),
          const SizedBox(height: 12),
          Text(
            'Prototype: triage, routing and crew suggestions are rule-based simulations. '
            'Reports are not sent to a real agency.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ReportStore store,
    Report r,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this report?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.of(context).pop();
      await store.delete(r);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.report, required this.canEdit});
  final Report report;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final path = report.photoPath;
    final hasPhoto = path != null && File(path).existsSync();
    final h = report.hazard;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 190,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasPhoto)
              Image.file(File(path), fit: BoxFit.cover)
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      h.color.withValues(alpha: 0.18),
                      h.color.withValues(alpha: 0.05),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: report.isDraft
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    if (report.isDraft) const SizedBox(height: 36),
                    Icon(h.icon, size: 64, color: h.color),
                    const SizedBox(height: 8),
                    Text(
                      report.isDraft ? 'No photo yet' : 'Illustration',
                      style: TextStyle(
                        color: h.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            if (report.isDraft)
              Positioned(
                right: 12,
                bottom: 12,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                  onPressed: canEdit
                      ? () => choosePhotoSource(context, report)
                      : null,
                  icon: Icon(
                    canEdit ? Icons.add_a_photo_rounded : Icons.lock_rounded,
                    size: 18,
                  ),
                  label: Text(
                    canEdit
                        ? (hasPhoto ? 'Replace photo' : 'Add photo')
                        : 'Photo when stopped',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DraftEditor extends StatefulWidget {
  const _DraftEditor({required this.report, required this.locked});
  final Report report;
  final bool locked;

  @override
  State<_DraftEditor> createState() => _DraftEditorState();
}

class _DraftEditorState extends State<_DraftEditor> {
  late final TextEditingController _desc = TextEditingController(
    text: widget.report.description,
  );

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  void _save() => context.read<ReportStore>().update(widget.report);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.report;
    final locked = widget.locked;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Edit before submitting',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (locked)
                  const Pill(
                    label: 'Locked while driving',
                    icon: Icons.lock_rounded,
                    foreground: AppColors.amberText,
                    background: AppColors.amberSoft,
                    dense: true,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Hazard', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in HazardType.values)
                  ChoiceChip(
                    avatar: Icon(h.icon, size: 18, color: h.color),
                    label: Text(h.label),
                    selected: r.hazard == h,
                    onSelected: locked
                        ? null
                        : (_) {
                            setState(() => r.hazard = h);
                            _save();
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Lane blockage', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in Blockage.values)
                  ChoiceChip(
                    label: Text(b.label),
                    selected: r.blockage == b,
                    onSelected: locked
                        ? null
                        : (_) {
                            setState(() => r.blockage = b);
                            _save();
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _desc,
              enabled: !locked,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'What should the crew know?',
              ),
              onChanged: (v) {
                r.description = v;
                _save();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TriageCard extends StatefulWidget {
  const _TriageCard({required this.triage});
  final TriageResult triage;

  @override
  State<_TriageCard> createState() => _TriageCardState();
}

class _TriageCardState extends State<_TriageCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.triage;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PriorityGauge(score: t.score, color: t.level.color),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PRIORITY',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        t.level.label,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: t.level.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              t.targetResponse,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Why this score',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Column(
                children: [
                  for (final f in t.factors)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Text(
                              '+${f.points}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: t.level.color,
                              ),
                            ),
                          ),
                          Expanded(child: Text(f.reason)),
                        ],
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

class _ResponseCard extends StatelessWidget {
  const _ResponseCard({required this.triage});
  final TriageResult triage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recommended response',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            row(
              Icons.account_balance_rounded,
              'Jurisdiction',
              '${triage.jurisdiction} · ${triage.roadClass.label}',
            ),
            row(Icons.engineering_rounded, 'Crew', triage.crew),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in triage.equipment)
                  Chip(
                    avatar: const Icon(Icons.construction_rounded, size: 16),
                    label: Text(e),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            for (final a in triage.advisories) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        a,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.report});
  final Report report;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(report.latitude!, report.longitude!);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 170,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 15,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.clearroads.clear_roads',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 44,
                      height: 44,
                      child: HazardMapPin(hazard: report.hazard),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${report.latitude!.toStringAsFixed(5)}, ${report.longitude!.toStringAsFixed(5)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.report});
  final Report report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = report.timeline;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Timeline',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < events.length; i++)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: i == events.length - 1
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primary.withValues(
                                    alpha: 0.4,
                                  ),
                            shape: BoxShape.circle,
                          ),
                        ),
                        if (i < events.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: theme.dividerColor,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              events[i].title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (events[i].detail != null)
                              Text(
                                events[i].detail!,
                                style: theme.textTheme.bodyMedium,
                              ),
                            Text(
                              '${DateFormat('MMM d, h:mm a').format(events[i].at)} · ${events[i].actor}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
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

class _BottomAction extends StatelessWidget {
  const _BottomAction({required this.report, required this.triage});
  final Report report;
  final TriageResult triage;

  @override
  Widget build(BuildContext context) {
    final store = context.read<ReportStore>();
    Widget? child;
    if (report.isDraft) {
      child = SubmitGate(report: report);
    } else if (report.status.next != null) {
      child = OutlinedButton.icon(
        onPressed: () => store.advanceStatus(report),
        icon: const Icon(Icons.fast_forward_rounded),
        label: Text('Simulate agency update → ${report.status.next!.label}'),
      );
    }
    if (child == null) return const SizedBox.shrink();
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: child,
      ),
    );
  }
}
