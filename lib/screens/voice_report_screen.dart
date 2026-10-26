import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/hazard.dart';
import '../models/report.dart';
import '../services/driving_monitor.dart';
import '../services/report_store.dart';
import '../services/settings_store.dart';
import '../services/triage_engine.dart';
import '../services/voice_report_flow.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mic_orb.dart';
import '../widgets/photo_picker.dart';
import 'report_detail_screen.dart';

class VoiceReportScreen extends StatefulWidget {
  const VoiceReportScreen({
    super.key,
    this.prefillHazard,
    this.prefillDetails,
    this.source = ReportSource.voice,
  });

  final HazardType? prefillHazard;
  final String? prefillDetails;
  final ReportSource source;

  static Future<void> open(
    BuildContext context, {
    HazardType? hazard,
    String? details,
    ReportSource source = ReportSource.voice,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VoiceReportScreen(
          prefillHazard: hazard,
          prefillDetails: details,
          source: source,
        ),
      ),
    );
  }

  @override
  State<VoiceReportScreen> createState() => _VoiceReportScreenState();
}

class _VoiceReportScreenState extends State<VoiceReportScreen> {
  late final VoiceReportFlow flow;
  Timer? _autoClose;
  int _closeIn = 0;

  @override
  void initState() {
    super.initState();
    flow = VoiceReportFlow(
      voice: context.read<VoiceService>(),
      store: context.read<ReportStore>(),
      driving: context.read<DrivingMonitor>(),
      voiceEnabled: context.read<SettingsStore>().voicePrompts,
      prefillHazard: widget.prefillHazard,
      prefillDetails: widget.prefillDetails,
      source: widget.source,
    );
    flow.addListener(_onFlow);
    flow.start();
  }

  void _onFlow() {
    // While driving, close the finished screen automatically so the driver
    // never has to look at or touch the phone again.
    if (flow.step == FlowStep.done &&
        _autoClose == null &&
        flow.driving.isDriving) {
      _closeIn = 8;
      _autoClose = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _closeIn--);
        if (_closeIn <= 0) {
          t.cancel();
          Navigator.of(context).maybePop();
        }
      });
    }
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    flow.removeListener(_onFlow);
    flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: flow,
      child: Consumer2<VoiceReportFlow, VoiceService>(
        builder: (context, flow, voice, _) {
          final theme = Theme.of(context);
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: Text(
                widget.source == ReportSource.siri
                    ? 'Siri report'
                    : 'Report a hazard',
              ),
              actions: [
                const DrivingStatusPill(),
                IconButton(
                  tooltip: flow.voiceEnabled
                      ? 'Mute voice prompts'
                      : 'Turn on voice prompts',
                  icon: Icon(
                    flow.voiceEnabled
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                  ),
                  onPressed: () => flow.setVoiceEnabled(!flow.voiceEnabled),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: flow.step == FlowStep.done
                    ? _DoneView(
                        key: const ValueKey('done'),
                        flow: flow,
                        closeIn: _closeIn,
                      )
                    : ListView(
                        key: const ValueKey('ask'),
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                        children: [
                          const SafetyBanner(
                            text: 'Eyes on the road — just answer out loud.',
                            icon: Icons.record_voice_over_rounded,
                          ),
                          const SizedBox(height: 18),
                          _StepDots(step: flow.step),
                          const SizedBox(height: 20),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Text(
                              flow.prompt,
                              key: ValueKey(flow.prompt),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            flow.hint,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: MicOrb(
                              listening: voice.isListening,
                              speaking: voice.isSpeaking,
                              level: voice.level,
                              enabled: flow.voiceEnabled && flow.micReady,
                              onTap: flow.relisten,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _VoiceStatus(flow: flow, voice: voice),
                          const SizedBox(height: 22),
                          _Options(flow: flow),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step});
  final FlowStep step;

  @override
  Widget build(BuildContext context) {
    const labels = ['Hazard', 'Lane', 'Details'];
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(3, (i) {
        final active = i == step.index;
        final done = i < step.index;
        final color = done || active ? scheme.primary : scheme.outlineVariant;
        return Expanded(
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: color.withValues(
                    alpha: active ? 1 : (done ? 0.7 : 0.4),
                  ),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _VoiceStatus extends StatelessWidget {
  const _VoiceStatus({required this.flow, required this.voice});
  final VoiceReportFlow flow;
  final VoiceService voice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String status;
    if (!flow.voiceEnabled) {
      status = 'Voice prompts off — tap an option';
    } else if (!flow.micReady) {
      status = 'Microphone unavailable — tap an option';
    } else if (voice.isSpeaking) {
      status = 'Speaking…';
    } else if (voice.isListening) {
      status = 'Listening…';
    } else {
      status = 'Tap the mic to talk';
    }
    final transcript = voice.isListening && voice.partial.isNotEmpty
        ? voice.partial
        : flow.heard;
    return Column(
      children: [
        Text(
          status,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (transcript != null && transcript.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '“$transcript”',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Options extends StatelessWidget {
  const _Options({required this.flow});
  final VoiceReportFlow flow;

  @override
  Widget build(BuildContext context) {
    switch (flow.step) {
      case FlowStep.type:
        final others = HazardType.values.where(
          (h) => !HazardType.primary.contains(h),
        );
        return Column(
          children: [
            for (final h in HazardType.primary)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BigOption(
                  icon: h.icon,
                  color: h.color,
                  label: h.label,
                  onTap: () => flow.choose(HazardAnswer(h)),
                ),
              ),
            Row(
              children: [
                for (final h in others)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _SmallOption(
                        icon: h.icon,
                        color: h.color,
                        label: h.label,
                        onTap: () => flow.choose(HazardAnswer(h)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      case FlowStep.blockage:
        return Column(
          children: [
            for (final b in [
              Blockage.shoulder,
              Blockage.partialLane,
              Blockage.fullLane,
              Blockage.allLanes,
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BigOption(
                  icon: b.icon,
                  color: b.score >= 28
                      ? AppColors.danger
                      : Theme.of(context).colorScheme.primary,
                  label: b.label,
                  onTap: () => flow.choose(BlockageAnswer(b)),
                ),
              ),
            TextButton(
              onPressed: () => flow.choose(const SkipAnswer()),
              child: const Text('Not sure — skip'),
            ),
          ],
        );
      case FlowStep.details:
        return FilledButton.icon(
          onPressed: () => flow.choose(const SkipAnswer()),
          icon: const Icon(Icons.check_rounded),
          label: const Text('Done — save draft'),
        );
      case FlowStep.done:
        return const SizedBox.shrink();
    }
  }
}

class _BigOption extends StatelessWidget {
  const _BigOption({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallOption extends StatelessWidget {
  const _SmallOption({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({super.key, required this.flow, required this.closeIn});
  final VoiceReportFlow flow;
  final int closeIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final driving = context.watch<DrivingMonitor>();
    final store = context.watch<ReportStore>();
    final report = flow.report == null ? null : store.byId(flow.report!.id);
    if (report == null) return const SizedBox.shrink();
    final triage = TriageEngine.evaluate(report);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        const SizedBox(height: 12),
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.4, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 56,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Draft saved',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          driving.isDriving
              ? "Keep driving safely. Submit it from My Reports once you've stopped."
              : "You're stopped — review it and submit when ready.",
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                HazardTile(report.hazard, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        triage.headline,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        report.placeLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      PriorityBadge(triage),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (report.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '“${report.description}”',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _PhotoStep(report: report, locked: !driving.canSubmit),
        const SizedBox(height: 24),
        if (driving.canSubmit)
          FilledButton.icon(
            icon: const Icon(Icons.rate_review_rounded),
            label: const Text('Review & submit'),
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => ReportDetailScreen(reportId: report.id),
              ),
            ),
          )
        else
          const SafetyBanner(
            icon: Icons.lock_clock_rounded,
            text: 'Submitting unlocks automatically when you stop driving.',
          ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(closeIn > 0 ? 'Done (closing in $closeIn s)' : 'Done'),
        ),
      ],
    );
  }
}

/// Offers a photo right after the draft is saved, instead of only on the
/// review screen. Locked while driving, like the rest of the editing.
class _PhotoStep extends StatelessWidget {
  const _PhotoStep({required this.report, required this.locked});
  final Report report;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final path = report.photoPath;
    final hasPhoto = path != null && File(path).existsSync();

    if (locked) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.no_photography_outlined, color: muted),
          title: const Text('Add a photo when stopped'),
          subtitle: const Text(
            'Photos unlock once you\u2019ve safely stopped.',
          ),
        ),
      );
    }

    if (hasPhoto) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Image.file(File(path), width: 84, height: 84, fit: BoxFit.cover),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Photo added',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () => choosePhotoSource(context, report),
              child: const Text('Replace'),
            ),
            const SizedBox(width: 8),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.add_a_photo_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Add a photo',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  'Optional',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'A photo helps crews judge the hazard before they arrive.',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.photo_camera_rounded),
                    label: const Text('Take photo'),
                    onPressed: () =>
                        attachPhoto(context, report, ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Library'),
                    onPressed: () =>
                        attachPhoto(context, report, ImageSource.gallery),
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
