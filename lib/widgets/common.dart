import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/hazard.dart';
import '../models/report.dart';
import '../services/driving_detector.dart';
import '../services/driving_monitor.dart';
import '../services/triage_engine.dart';
import '../theme.dart';

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return DateFormat.MMMd().format(t);
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final Color foreground;
  final Color background;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 13 : 15, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: dense ? 12 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class HazardBadge extends StatelessWidget {
  const HazardBadge(this.hazard, {super.key, this.dense = false});
  final HazardType hazard;
  final bool dense;

  @override
  Widget build(BuildContext context) => Pill(
    label: hazard.label,
    icon: hazard.icon,
    foreground: hazard.color,
    background: hazard.color.withValues(alpha: 0.10),
    dense: dense,
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.dense = false});
  final ReportStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Pill(
      label: status.label,
      icon: status.icon,
      foreground: dark ? status.background : status.foreground,
      background: dark
          ? status.foreground.withValues(alpha: 0.35)
          : status.background,
      dense: dense,
    );
  }
}

class HazardTile extends StatelessWidget {
  const HazardTile(this.hazard, {super.key, this.size = 52});
  final HazardType hazard;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: hazard.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    child: Icon(hazard.icon, color: hazard.color, size: size * 0.5),
  );
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge(this.triage, {super.key, this.dense = true});
  final TriageResult triage;
  final bool dense;

  @override
  Widget build(BuildContext context) => Pill(
    label: '${triage.score} · ${triage.level.label}',
    icon: Icons.speed_rounded,
    foreground: triage.level.color,
    background: triage.level.color.withValues(alpha: 0.10),
    dense: dense,
  );
}

class ReportCard extends StatelessWidget {
  const ReportCard({
    super.key,
    required this.report,
    required this.onTap,
    this.footer,
  });

  final Report report;
  final VoidCallback onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final triage = TriageEngine.evaluate(report);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Thumb(report),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            StatusBadge(report.status, dense: true),
                            PriorityBadge(triage),
                            if (report.isSample)
                              Pill(
                                label: 'Sample',
                                foreground: muted,
                                background: muted.withValues(alpha: 0.08),
                                dense: true,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          triage.headline,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (report.description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            report.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.place_outlined, size: 15, color: muted),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                report.placeLabel,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              Icons.schedule_rounded,
                              size: 15,
                              color: muted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              timeAgo(report.createdAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: muted),
                ],
              ),
              if (footer != null) ...[const SizedBox(height: 12), footer!],
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb(this.report);
  final Report report;

  @override
  Widget build(BuildContext context) {
    final path = report.photoPath;
    if (path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(File(path), width: 52, height: 52, fit: BoxFit.cover),
      );
    }
    return HazardTile(report.hazard);
  }
}

/// Live "Driving / Stopped" indicator for the app bar.
class DrivingStatusPill extends StatelessWidget {
  const DrivingStatusPill({super.key});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<DrivingMonitor>();
    final (label, icon, fg, bg) = switch (m.state) {
      DrivingState.driving => (
        'Driving',
        Icons.directions_car_filled_rounded,
        AppColors.amberText,
        AppColors.amberSoft,
      ),
      DrivingState.stopped => (
        'Stopped',
        Icons.local_parking_rounded,
        const Color(0xFF065F46),
        const Color(0xFFD1FAE5),
      ),
      DrivingState.unknown => (
        'Checking',
        Icons.sensors_rounded,
        const Color(0xFF334155),
        const Color(0xFFE2E8F0),
      ),
    };
    return Semantics(
      label: 'Driving status: $label',
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Pill(
          key: ValueKey(label),
          label: label,
          icon: icon,
          foreground: fg,
          background: bg,
        ),
      ),
    );
  }
}

class SafetyBanner extends StatelessWidget {
  const SafetyBanner({
    super.key,
    required this.text,
    this.icon = Icons.shield_moon_rounded,
    this.trailing,
  });
  final String text;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.amberText, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.amberText,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        ?action,
      ],
    ),
  );
}

/// Circular priority gauge (0–100).
class PriorityGauge extends StatelessWidget {
  const PriorityGauge({
    super.key,
    required this.score,
    required this.color,
    this.size = 92,
  });
  final int score;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score / 100),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _GaugePainter(v, color, color.withValues(alpha: 0.14)),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(v * 100).round()}',
                  style: TextStyle(
                    fontSize: size * 0.32,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1,
                  ),
                ),
                Text(
                  '/ 100',
                  style: TextStyle(
                    fontSize: size * 0.12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.value, this.color, this.track);
  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.1;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(arc, start, sweep, false, base);
    canvas.drawArc(arc, start, sweep * value, false, base..color = color);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color;
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}
