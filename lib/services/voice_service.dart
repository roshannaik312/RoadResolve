import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Thin wrapper around on-device speech recognition + text-to-speech that
/// exposes a simple "say something, then listen for an answer" API.
class VoiceService extends ChangeNotifier {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _sttReady = false;
  bool _ttsReady = false;
  bool _listening = false;
  bool _speaking = false;
  double _level = 0;
  String _partial = '';
  Completer<String?>? _pending;

  bool get available => _sttReady;
  bool get isListening => _listening;
  bool get isSpeaking => _speaking;
  String get partial => _partial;

  /// Normalised 0..1 microphone level for the animated orb.
  double get level => _level;

  Future<bool> init() async {
    if (!_ttsReady) {
      try {
        await _tts.setSharedInstance(true);
        await _configureAudio();
        await _tts.awaitSpeakCompletion(true);
        await _tts.setSpeechRate(0.5);
        await _tts.setVolume(1.0);
        await _tts.setLanguage('en-US');
        _tts.setStartHandler(() => _setSpeaking(true));
        _tts.setCompletionHandler(() => _setSpeaking(false));
        _tts.setCancelHandler(() => _setSpeaking(false));
        _tts.setErrorHandler((_) => _setSpeaking(false));
        _ttsReady = true;
      } catch (_) {
        _ttsReady = false;
      }
    }
    if (!_sttReady) {
      try {
        _sttReady = await _stt.initialize(
          onStatus: _onStatus,
          onError: (_) => _finish(_partial.isEmpty ? null : _partial),
        );
      } catch (_) {
        _sttReady = false;
      }
    }
    notifyListeners();
    return _sttReady;
  }

  // Speak as ordinary media playback so prompts follow the phone's media
  // volume (a playAndRecord session has its own, quieter volume level).
  // Playback still routes to Bluetooth / CarPlay and ducks music. The
  // recogniser switches to playAndRecord itself while listening, then
  // restores this category.
  Future<void> _configureAudio() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      const [IosTextToSpeechAudioCategoryOptions.duckOthers],
      IosTextToSpeechAudioMode.defaultMode,
    );
  }

  void _setSpeaking(bool v) {
    _speaking = v;
    notifyListeners();
  }

  Future<void> speak(String text) async {
    if (!_ttsReady) return;
    await stopListening();
    try {
      // The recogniser may have switched the audio session; restore ours.
      await _configureAudio();
      _setSpeaking(true);
      await _tts.speak(text);
    } catch (_) {
      // Speech is a convenience; never block the flow on it.
    } finally {
      _setSpeaking(false);
    }
  }

  /// Listen for one utterance. Resolves with the final transcript, or null
  /// on silence / error / cancel.
  Future<String?> listen({
    Duration listenFor = const Duration(seconds: 12),
    Duration pauseFor = const Duration(seconds: 2, milliseconds: 500),
  }) async {
    if (!_sttReady) return null;
    await stopListening();
    _partial = '';
    _level = 0;
    final completer = _pending = Completer<String?>();
    try {
      await _stt.listen(
        onResult: _onResult,
        onSoundLevelChange: (db) {
          // iOS reports roughly -50..10 dB.
          _level = ((db + 50) / 60).clamp(0.0, 1.0);
          notifyListeners();
        },
        listenOptions: SpeechListenOptions(
          listenFor: listenFor,
          pauseFor: pauseFor,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.confirmation,
          onDevice: false,
          autoPunctuation: true,
        ),
      );
      _listening = true;
      notifyListeners();
    } catch (_) {
      _finish(null);
    }
    return completer.future.timeout(
      listenFor + const Duration(seconds: 3),
      onTimeout: () {
        final text = _partial.isEmpty ? null : _partial;
        _finish(text);
        return text;
      },
    );
  }

  void _onResult(SpeechRecognitionResult r) {
    _partial = r.recognizedWords;
    notifyListeners();
    if (r.finalResult) _finish(_partial.isEmpty ? null : _partial);
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      // Give the final result callback a moment to arrive first.
      Future.delayed(const Duration(milliseconds: 400), () {
        _finish(_partial.isEmpty ? null : _partial);
      });
    }
  }

  void _finish(String? text) {
    _listening = false;
    _level = 0;
    final p = _pending;
    _pending = null;
    if (p != null && !p.isCompleted) p.complete(text);
    notifyListeners();
  }

  /// Stop listening; any pending [listen] resolves with null.
  Future<void> stopListening() async {
    if (_pending != null) _finish(null);
    if (_stt.isListening) {
      try {
        await _stt.cancel();
      } catch (_) {}
    }
  }

  Future<void> stopAll() async {
    await stopListening();
    try {
      await _tts.stop();
    } catch (_) {}
    _setSpeaking(false);
  }

  @override
  void dispose() {
    stopAll();
    super.dispose();
  }
}
