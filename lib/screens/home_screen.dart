import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/hazard.dart';
import '../services/driving_monitor.dart';
import '../services/report_store.dart';
import '../services/settings_store.dart';
import '../services/voice_report_flow.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'report_detail_screen.dart';
import 'voice_report_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenTab});

  /// Switch the shell's tab (1 = map, 3 = my reports, 4 = settings).
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final driving = context.watch<DrivingMonitor>();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: driving.isDriving
          ? DrivingHome(key: const ValueKey('driving'), onOpenTab: onOpenTab)
          : _StoppedHome(key: const ValueKey('stopped'), onOpenTab: onOpenTab),
    );
  }
}

class _StoppedHome extends StatelessWidget {
  const _StoppedHome({super.key, required this.onOpenTab});
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ReportStore>();
    final drafts = store.drafts;
    final recent = store.submitted.take(4).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _Hero(onMap: () => onOpenTab(1)),
        if (drafts.isNotEmpty) ...[
          const SizedBox(height: 14),
          _DraftsReady(count: drafts.length, onReview: () => onOpenTab(3)),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            _Stat(
              value: store.all.length,
              label: 'Reports',
              color: Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(width: 10),
            _Stat(
              value: store.openCount,
              label: 'Open',
              color: const Color(0xFFD97706),
            ),
            const SizedBox(width: 10),
            _Stat(
              value: store.resolvedCount,
              label: 'Resolved',
              color: AppColors.success,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SiriTip(onMore: () => onOpenTab(4)),
        const SizedBox(height: 10),
        SectionHeader(
          'Recent reports',
          action: TextButton(
            onPressed: () => onOpenTab(1),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('See map'),
                SizedBox(width: 2),
                Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ),
        for (final r in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ReportCard(
              report: r,
              onTap: () => ReportDetailScreen.open(context, r),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          'Emergency? Call 911. Only report when it is safe. '
          'This prototype does not contact real agencies.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onMap});
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  color: Colors.white,
                  size: 15,
                ),
                SizedBox(width: 5),
                Text(
                  'Hands-free reporting',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Spot a hazard?\nJust say it.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Report dead animals, fallen trees and snow by voice while you drive. '
            "It's saved as a draft — submit once you've stopped.",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 15,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.brandDark,
                minimumSize: const Size.fromHeight(58),
              ),
              onPressed: () => VoiceReportScreen.open(context),
              icon: const Icon(Icons.mic_rounded, size: 26),
              label: const Text('Report by voice'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
              ),
              onPressed: onMap,
              icon: const Icon(Icons.map_outlined),
              label: const Text('View community map'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftsReady extends StatelessWidget {
  const _DraftsReady({required this.count, required this.onReview});
  final int count;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.amberSoft,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onReview,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.drafts_rounded,
                  color: AppColors.amberText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count draft${count == 1 ? '' : 's'} ready to submit',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.amberText,
                        fontSize: 16,
                      ),
                    ),
                    const Text(
                      "You're stopped — review and send them now.",
                      style: TextStyle(color: AppColors.amberText),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.amberText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SiriTip extends StatelessWidget {
  const _SiriTip({required this.onMore});
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onMore,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF6366F1),
                      Color(0xFFEC4899),
                      Color(0xFFF59E0B),
                    ],
                  ),
                ),
                child: const Icon(Icons.mic_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Works with Siri',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '“Hey Siri, report a fallen tree in Clear Roads”',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
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

/// Minimal, glanceable home shown automatically while driving:
/// one giant voice button and three one-tap hazard buttons.
class DrivingHome extends StatelessWidget {
  const DrivingHome({super.key, required this.onOpenTab});
  final ValueChanged<int> onOpenTab;

  Future<void> _quick(BuildContext context, HazardType h) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await quickReport(
      hazard: h,
      store: context.read<ReportStore>(),
      driving: context.read<DrivingMonitor>(),
      voice: context.read<VoiceService>(),
      speak: context.read<SettingsStore>().voicePrompts,
    );
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text('${r.hazard.label} saved as a draft'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final driving = context.watch<DrivingMonitor>();
    final drafts = context.select<ReportStore, int>((s) => s.drafts.length);
    final speed = driving.speedMps;
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.drivingGradient),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, c) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.directions_car_filled_rounded,
                            color: AppColors.amber,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Driving mode',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const Spacer(),
                          if (speed != null)
                            Text(
                              '${(speed * 2.23694).round()} mph',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Semantics(
                        button: true,
                        label: 'Report a hazard by voice',
                        child: GestureDetector(
                          onTap: () => VoiceReportScreen.open(context),
                          child: Container(
                            width: 210,
                            height: 210,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.heroGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.brand.withValues(
                                    alpha: 0.55,
                                  ),
                                  blurRadius: 50,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.mic_rounded,
                                  color: Colors.white,
                                  size: 84,
                                ),
                                Text(
                                  'Tap & speak',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'or say “Hey Siri, report a hazard in Clear Roads”',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                      const SizedBox(height: 28),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ONE-TAP DRAFT',
                          style: TextStyle(
                            color: Colors.white54,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (final h in HazardType.primary)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                child: _DriveButton(
                                  hazard: h,
                                  onTap: () => _quick(context, h),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Material(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => onOpenTab(3),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.lock_clock_rounded,
                                  color: AppColors.amber,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    drafts == 0
                                        ? "Drafts are saved here — submit them once you've stopped."
                                        : '$drafts draft${drafts == 1 ? '' : 's'} saved · submit when stopped',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DriveButton extends StatelessWidget {
  const _DriveButton({required this.hazard, required this.onTap});
  final HazardType hazard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: SizedBox(
          height: 118,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: hazard.color,
                  shape: BoxShape.circle,
                ),
                child: Icon(hazard.icon, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 10),
              Text(
                hazard.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
