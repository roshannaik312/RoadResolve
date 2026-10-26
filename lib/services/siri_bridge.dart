import 'dart:async';

import 'package:flutter/services.dart';

import '../models/hazard.dart';

enum SiriAction { draft, showDrafts }

class SiriRequest {
  const SiriRequest({
    required this.action,
    this.hazard,
    this.details,
    required this.createdAt,
  });

  factory SiriRequest.fromMap(Map<dynamic, dynamic> m) => SiriRequest(
    action: m['action'] == 'showDrafts'
        ? SiriAction.showDrafts
        : SiriAction.draft,
    hazard: HazardType.fromId(m['hazard'] as String?),
    details: m['details'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['createdAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    ),
  );

  final SiriAction action;
  final HazardType? hazard;
  final String? details;
  final DateTime createdAt;
}

/// Receives "Hey Siri, report a fallen tree in Clear Roads" requests from
/// the App Intents defined in ios/Runner/HazardIntents.swift.
class SiriBridge {
  SiriBridge() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pendingAvailable') await drain();
    });
  }

  static const _channel = MethodChannel('clear_roads/siri');
  final _controller = StreamController<SiriRequest>.broadcast();

  Stream<SiriRequest> get requests => _controller.stream;

  /// Pull any requests queued while Flutter wasn't running.
  Future<void> drain() async {
    try {
      final list =
          await _channel.invokeListMethod<dynamic>('takePending') ?? const [];
      for (final item in list) {
        _controller.add(SiriRequest.fromMap(item as Map));
      }
    } on MissingPluginException {
      // Not on iOS (tests / other platforms).
    } on PlatformException {
      // Ignore — nothing to drain.
    }
  }

  void dispose() => _controller.close();
}
