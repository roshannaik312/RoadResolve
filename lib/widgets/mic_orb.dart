import 'package:flutter/material.dart';

import '../theme.dart';

/// Large animated microphone. Pulses while speaking, reacts to the mic
/// level while listening, and is tappable to listen again.
class MicOrb extends StatefulWidget {
  const MicOrb({
    super.key,
    required this.listening,
    required this.speaking,
    required this.level,
    required this.enabled,
    required this.onTap,
    this.size = 128,
  });

  final bool listening;
  final bool speaking;
  final double level;
  final bool enabled;
  final VoidCallback onTap;
  final double size;

  @override
  State<MicOrb> createState() => _MicOrbState();
}

class _MicOrbState extends State<MicOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.listening || widget.speaking;
    final color = !widget.enabled
        ? Theme.of(context).colorScheme.outline
        : widget.listening
        ? const Color(0xFFE11D48)
        : AppColors.brand;
    final s = widget.size;

    return Semantics(
      button: true,
      label: widget.listening ? 'Listening' : 'Tap to speak',
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: SizedBox(
          width: s * 1.6,
          height: s * 1.6,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = _pulse.value;
              final levelBoost = widget.listening ? widget.level * 0.35 : 0.0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (active)
                    for (final offset in [0.0, 0.5])
                      _Ring(
                        size: s * (1 + 0.55 * ((t + offset) % 1)),
                        opacity: (1 - ((t + offset) % 1)) * 0.35,
                        color: color,
                      ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: s * (1 + levelBoost),
                    height: s * (1 + levelBoost),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [color.withValues(alpha: 0.95), color],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.speaking
                          ? Icons.graphic_eq_rounded
                          : Icons.mic_rounded,
                      color: Colors.white,
                      size: s * 0.42,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.opacity, required this.color});
  final double size;
  final double opacity;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: opacity),
    ),
  );
}
