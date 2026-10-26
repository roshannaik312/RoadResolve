import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/hazard.dart';
import '../models/report.dart';
import 'driving_monitor.dart';
import 'location_service.dart';
import 'report_store.dart';
import 'triage_engine.dart';
import 'voice_parser.dart';
import 'voice_service.dart';

enum FlowStep { type, blockage, details, done }

/// Tap-able answers (in addition to voice).
sealed class FlowAnswer {
  const FlowAnswer();
}

class HazardAnswer extends FlowAnswer {
  const HazardAnswer(this.hazard);
  final HazardType hazard;
}

class BlockageAnswer extends FlowAnswer {
  const BlockageAnswer(this.blockage);
  final Blockage blockage;
}

class SkipAnswer extends FlowAnswer {
  const SkipAnswer();
}

class _Relisten extends FlowAnswer {
  const _Relisten();
}

class _Cancelled implements Exception {}

/// Conversational, hands-free report builder:
///
///   "What did you see?"            → hazard type
///   "Is it blocking the road?"     → lane blockage
///   "Anything else?"               → free-text details
///
/// GPS is captured the moment the flow starts (where the hazard was seen,
/// not where the driver is a minute later). A draft is created as soon as
/// the hazard type is known, so nothing is lost if the user stops talking.
class VoiceReportFlow extends ChangeNotifier {
  VoiceReportFlow({
    required this.voice,
    required this.store,
    required this.driving,
    required this.voiceEnabled,
    this.prefillHazard,
    this.prefillDetails,
    this.source = ReportSource.voice,
  });

  final VoiceService voice;
  final ReportStore store;
  final DrivingMonitor driving;
  final HazardType? prefillHazard;
  final String? prefillDetails;
  final ReportSource source;
  bool voiceEnabled;

  FlowStep step = FlowStep.type;
  String prompt = 'What did you see?';
  String hint = '';
  String? heard;
  HazardType? hazard;
  Blockage? blockage;
  final List<String> _details = [];
  Report? report;
  bool micReady = false;
  bool awaitingTap = false;

  bool _alive = true;
  Completer<FlowAnswer?>? _tap;
  Future<Position?>? _position;
  late final bool _startedWhileDriving;

  String get details => _details.join('. ');

  Future<void> start() async {
    _startedWhileDriving = driving.isDriving;
    _position = LocationService.currentPosition(recent: driving.lastPosition);
    if (voiceEnabled) {
      micReady = await voice.init();
      notifyListeners();
    }
    try {
      if (prefillDetails != null && prefillDetails!.trim().isNotEmpty) {
        _details.add(prefillDetails!.trim());
        blockage ??= VoiceParser.blockage(prefillDetails!);
      }
      if (prefillHazard != null) {
        hazard = prefillHazard;
        await _ensureDraft();
      } else {
        await _askType();
      }
      if (blockage == null) await _askBlockage();
      if (_details.isEmpty) await _askDetails();
      await _finish();
    } on _Cancelled {
      // Screen closed or user said "cancel".
    }
  }

  // ---------------------------------------------------------------- steps

  Future<void> _askType() async {
    _setStep(
      FlowStep.type,
      'What did you see?',
      'Say “dead deer”, “fallen tree”, or “snow on the road”.',
    );
    var spoken =
        'What did you see? A dead animal, a fallen tree, or snow and ice?';
    var relisten = false;
    for (var attempt = 0; hazard == null; attempt++) {
      final a = await _ask(spoken, listen: attempt < 3 || relisten);
      if (a is HazardAnswer) {
        hazard = a.hazard;
      } else if (a is _Heard) {
        if (_isCancel(a.text)) {
          await _say('Okay, cancelled.');
          throw _Cancelled();
        }
        hazard = VoiceParser.hazard(a.text);
        if (hazard != null) {
          _details.add(_capitalize(a.text));
          blockage = VoiceParser.blockage(a.text);
        }
      }
      relisten = a is _Relisten;
      spoken = switch (attempt) {
        _ when relisten => '',
        0 =>
          "Sorry, I didn't catch that. Say dead animal, fallen tree, or snow.",
        1 => "I'm still listening. What kind of hazard was it?",
        _ => '',
      };
    }
    _haptic();
    await _ensureDraft();
  }

  Future<void> _askBlockage() async {
    _setStep(
      FlowStep.blockage,
      'Is it blocking the road?',
      'Say “on the shoulder”, “blocking a lane”, or “both lanes”.',
    );
    var spoken =
        'Got it, ${hazard!.spoken}. Is it on the shoulder, blocking a lane, or blocking all lanes?';
    for (var attempt = 0; blockage == null; attempt++) {
      final a = await _ask(spoken, listen: true);
      if (a is BlockageAnswer) {
        blockage = a.blockage;
      } else if (a is SkipAnswer) {
        blockage = Blockage.unknown;
      } else if (a is _Heard) {
        if (_isCancel(a.text)) break;
        blockage =
            VoiceParser.blockage(a.text) ??
            (VoiceParser.isSkip(a.text) ? Blockage.unknown : null);
        if (blockage == null && a.text.split(' ').length > 3) {
          // Treat a longer answer as a description rather than asking again.
          _details.add(_capitalize(a.text));
          blockage = Blockage.unknown;
        }
      } else if (a == null && attempt >= 1) {
        blockage = Blockage.unknown;
      }
      spoken = a is _Relisten ? '' : 'Shoulder, one lane, or all lanes?';
    }
    blockage ??= Blockage.unknown;
    _haptic();
    await _updateDraft();
  }

  Future<void> _askDetails() async {
    _setStep(
      FlowStep.details,
      'Anything else?',
      'e.g. “near the school bus stop” or “cars are swerving”. Say “done” to save.',
    );
    var spoken = 'Anything else to add? Or say done.';
    for (var attempt = 0; attempt < 3; attempt++) {
      final a = await _ask(spoken, listen: true);
      if (a is _Heard) {
        if (!VoiceParser.isSkip(a.text) && !_isCancel(a.text)) {
          _details.add(_capitalize(a.text));
          blockage =
              (blockage == Blockage.unknown
                  ? VoiceParser.blockage(a.text)
                  : null) ??
              blockage;
        }
        break;
      }
      if (a is _Relisten) {
        spoken = '';
        continue;
      }
      break; // Skip, silence, or tap.
    }
    await _updateDraft();
  }

  Future<void> _finish() async {
    _setStep(FlowStep.done, 'Draft saved', '');
    _haptic();
    final r = report!;
    final triage = TriageEngine.evaluate(r);
    final where = r.road != null ? ' near ${r.road}' : '';
    final tail = driving.isDriving
        ? "Submit it once you've safely stopped."
        : 'You can add a photo, then review and submit it.';
    await _say('Saved. ${triage.headline}$where. $tail');
  }

  // --------------------------------------------------------------- drafts

  Future<void> _ensureDraft() async {
    if (report != null) return;
    final pos = await _position?.timeout(
      const Duration(seconds: 6),
      onTimeout: () => null,
    );
    report = await store.createDraft(
      hazard: hazard!,
      blockage: blockage ?? Blockage.unknown,
      description: details,
      latitude: pos?.latitude,
      longitude: pos?.longitude,
      source: source,
      whileDriving: _startedWhileDriving,
    );
    notifyListeners();
    if (pos != null) {
      // Reverse-geocode in the background; don't hold up the conversation.
      unawaited(
        LocationService.describe(pos.latitude, pos.longitude).then((place) {
          final r = report;
          if (r == null) return;
          r.road = place.road;
          r.locality = place.locality;
          store.update(r);
          if (_alive) notifyListeners();
        }),
      );
    }
  }

  Future<void> _updateDraft() async {
    final r = report;
    if (r == null) return;
    r.hazard = hazard ?? r.hazard;
    r.blockage = blockage ?? r.blockage;
    r.description = details;
    await store.update(r);
    notifyListeners();
  }

  // ------------------------------------------------------------ plumbing

  /// Speak [spoken] (if non-empty), then listen; a tap at any point wins.
  Future<FlowAnswer?> _ask(String spoken, {required bool listen}) async {
    _check();
    heard = null;
    final tap = _tap = Completer<FlowAnswer?>();
    final useVoice = voiceEnabled && micReady;
    awaitingTap = !useVoice || !listen;
    notifyListeners();

    if (useVoice && spoken.isNotEmpty) {
      await Future.any<void>([voice.speak(spoken), tap.future]);
      if (tap.isCompleted) {
        await voice.stopAll();
        return _result(await tap.future);
      }
    }
    _check();
    if (useVoice && listen) {
      final listening = voice.listen().then<FlowAnswer?>(
        (t) => t == null ? null : _Heard(t),
      );
      final first = await Future.any<FlowAnswer?>([listening, tap.future]);
      if (tap.isCompleted) {
        await voice.stopListening();
        return _result(await tap.future);
      }
      if (first is _Heard) {
        heard = first.text;
        notifyListeners();
      }
      if (first != null || !useVoice) return _result(first);
      // Silence: fall through to wait for a tap or relisten.
      awaitingTap = true;
      notifyListeners();
      return _result(
        await tap.future.timeout(
          const Duration(seconds: 1),
          onTimeout: () => null,
        ),
      );
    }
    awaitingTap = true;
    notifyListeners();
    return _result(await tap.future);
  }

  FlowAnswer? _result(FlowAnswer? a) {
    _check();
    return a;
  }

  /// Tap answer from the UI.
  void choose(FlowAnswer answer) {
    final t = _tap;
    if (t != null && !t.isCompleted) t.complete(answer);
  }

  /// Mic button: listen again without repeating the question.
  void relisten() => choose(const _Relisten());

  void setVoiceEnabled(bool v) {
    voiceEnabled = v;
    if (!v) {
      voice.stopAll();
    } else if (!micReady) {
      voice.init().then((ok) {
        micReady = ok;
        if (_alive) notifyListeners();
      });
    }
    notifyListeners();
  }

  Future<void> _say(String text) async {
    if (voiceEnabled && _alive) await voice.speak(text);
  }

  void _setStep(FlowStep s, String p, String h) {
    step = s;
    prompt = p;
    hint = h;
    heard = null;
    notifyListeners();
  }

  void _check() {
    if (!_alive) throw _Cancelled();
  }

  bool _isCancel(String text) =>
      text.split(' ').length <= 4 && VoiceParser.isCancel(text);

  static String _capitalize(String s) {
    final t = s.trim();
    return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
  }

  void _haptic() => HapticFeedback.mediumImpact();

  @override
  void dispose() {
    _alive = false;
    final t = _tap;
    if (t != null && !t.isCompleted) t.complete(null);
    voice.stopAll();
    super.dispose();
  }
}

class _Heard extends FlowAnswer {
  const _Heard(this.text);
  final String text;
}

/// One-tap report from the driving-mode home screen: no questions asked.
Future<Report> quickReport({
  required HazardType hazard,
  required ReportStore store,
  required DrivingMonitor driving,
  required VoiceService voice,
  required bool speak,
}) async {
  HapticFeedback.heavyImpact();
  final pos = await LocationService.currentPosition(
    recent: driving.lastPosition,
  ).timeout(const Duration(seconds: 6), onTimeout: () => null);
  final r = await store.createDraft(
    hazard: hazard,
    latitude: pos?.latitude,
    longitude: pos?.longitude,
    source: ReportSource.tap,
    whileDriving: driving.isDriving,
  );
  if (pos != null) {
    unawaited(
      LocationService.describe(pos.latitude, pos.longitude).then((p) {
        r.road = p.road;
        r.locality = p.locality;
        store.update(r);
      }),
    );
  }
  if (speak) {
    unawaited(
      voice.init().then(
        (_) => voice.speak(
          '${hazard.label} saved as a draft. Submit it when you have stopped.',
        ),
      ),
    );
  }
  return r;
}
