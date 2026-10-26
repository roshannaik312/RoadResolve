// Scripted walkthrough of every feature, used to screen-record a client demo:
//
//   tool/record_demo.sh
//
// The simulator has no microphone, so a scripted VoiceService "hears" the
// driver's answers, and captions show what the app says out loud (screen
// recordings have no audio).
import 'dart:async';
import 'dart:math' as math;

import 'package:clear_roads/app.dart';
import 'package:clear_roads/models/hazard.dart';
import 'package:clear_roads/models/report.dart';
import 'package:clear_roads/screens/voice_report_screen.dart';
import 'package:clear_roads/services/auth_service.dart';
import 'package:clear_roads/services/driving_monitor.dart';
import 'package:clear_roads/services/report_store.dart';
import 'package:clear_roads/services/settings_store.dart';
import 'package:clear_roads/services/siri_bridge.dart';
import 'package:clear_roads/services/voice_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The walkthrough skips sign-in and runs as an already signed-in driver.
class DemoAuth extends AuthService {
  @override
  bool get ready => true;
  @override
  bool get signedIn => true;
}

// ------------------------------------------------------------ demo chrome

final caption = ValueNotifier<String?>(null);
final spoken = ValueNotifier<String?>(null);
final touch = ValueNotifier<Offset?>(null);

class DemoChrome extends StatelessWidget {
  const DemoChrome({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          child,
          IgnorePointer(
            child: ValueListenableBuilder<Offset?>(
              valueListenable: touch,
              builder: (_, p, _) => p == null
                  ? const SizedBox.shrink()
                  : Stack(
                      children: [
                        Positioned(
                          left: p.dx - 24,
                          top: p.dy - 24,
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey(p),
                            tween: Tween(begin: 0.6, end: 1),
                            duration: const Duration(milliseconds: 250),
                            builder: (_, v, _) => Transform.scale(
                              scale: v,
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.45),
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 118,
            child: IgnorePointer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _bubble(
                    spoken,
                    const Color(0xEE4C1D95),
                    Icons.volume_up_rounded,
                  ),
                  const SizedBox(height: 8),
                  _bubble(caption, const Color(0xE6111827), null),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ValueNotifier<String?> text, Color bg, IconData? icon) {
    return ValueListenableBuilder<String?>(
      valueListenable: text,
      builder: (_, t, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: t == null
            ? const SizedBox.shrink()
            : Container(
                key: ValueKey(t),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        t,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          fontStyle: icon != null
                              ? FontStyle.italic
                              : FontStyle.normal,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ------------------------------------------------------------ scripted voice

class DemoVoice extends VoiceService {
  final answers = <String>[];
  bool _listening = false;
  bool _speaking = false;
  String _partial = '';
  double _level = 0;
  final _rand = math.Random(7);

  @override
  bool get available => true;
  @override
  bool get isListening => _listening;
  @override
  bool get isSpeaking => _speaking;
  @override
  String get partial => _partial;
  @override
  double get level => _level;

  @override
  Future<bool> init() async => true;

  @override
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    _speaking = true;
    spoken.value = 'App says: “$text”';
    notifyListeners();
    await Future<void>.delayed(
      Duration(milliseconds: (text.length * 55).clamp(1400, 4200)),
    );
    _speaking = false;
    notifyListeners();
  }

  @override
  Future<String?> listen({
    Duration listenFor = const Duration(seconds: 12),
    Duration pauseFor = const Duration(seconds: 2, milliseconds: 500),
  }) async {
    _listening = true;
    _partial = '';
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (answers.isEmpty) {
      _listening = false;
      notifyListeners();
      return null;
    }
    final text = answers.removeAt(0);
    spoken.value = null;
    final words = text.split(' ');
    for (var i = 0; i < words.length; i++) {
      _partial = words.take(i + 1).join(' ');
      _level = 0.35 + _rand.nextDouble() * 0.6;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 230));
    }
    _level = 0;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    _listening = false;
    notifyListeners();
    return text;
  }

  @override
  Future<void> stopListening() async {
    _listening = false;
    _level = 0;
    notifyListeners();
  }

  @override
  Future<void> stopAll() async {
    // Like the real service, never notify synchronously (it's called from
    // dispose while the widget tree is locked).
    await Future<void>.delayed(Duration.zero);
    _listening = false;
    _speaking = false;
    notifyListeners();
  }
}

// ------------------------------------------------------------ fixed GPS

/// A car on NY-50 near Saratoga Springs, without iOS permission prompts.
/// The demo override drives the Driving/Stopped state.
class DemoDriving extends DrivingMonitor {
  @override
  Future<void> start() async {}

  @override
  Position? get lastPosition => Position(
    latitude: 43.1450149,
    longitude: -73.6929013,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 90,
    altitudeAccuracy: 3,
    heading: 20,
    headingAccuracy: 5,
    speed: isDriving ? 24.6 : 0,
    speedAccuracy: 1,
  );

  @override
  double? get speedMps => isDriving ? 24.6 : 0;
}

// ------------------------------------------------------------ the demo

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'Clear Roads client demo',
    timeout: const Timeout(Duration(minutes: 10)),
    (tester) async {
      Future<void> wait(int ms) async {
        await tester.runAsync(
          () => Future<void>.delayed(Duration(milliseconds: ms)),
        );
        await tester.pump();
      }

      Future<void> say(String text, {int hold = 2600}) async {
        caption.value = text;
        await wait(hold);
      }

      Future<void> waitFor(Finder f, {int timeoutMs = 20000}) async {
        for (var t = 0; t < timeoutMs; t += 200) {
          if (f.evaluate().isNotEmpty) return;
          await wait(200);
        }
        final visible = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .join(' | ');
      throw StateError('Timed out waiting for $f. On screen: $visible');
      }

      Future<void> tap(Finder f, {int after = 900}) async {
        await waitFor(f);
        final target = f.first;
        await tester.ensureVisible(target);
        await wait(250);
        final p = tester.getCenter(target);
        touch.value = p;
        await wait(280);
        await tester.tapAt(p);
        await wait(180);
        touch.value = null;
        await wait(after);
      }

      Future<void> scroll(double dy, {double y = 480, int ms = 900}) async {
        await tester.timedDragFrom(
          Offset(200, y),
          Offset(0, -dy),
          Duration(milliseconds: ms),
        );
        await wait(700);
      }

      // The simulator has no motion coprocessor; the app already falls back
      // to GPS, so don't fail the walkthrough on that platform error.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if ('${details.exception}'.contains('unavailable')) return;
        originalOnError?.call(details);
      };

      // Fresh state: onboarding + sample data.
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final voice = DemoVoice();
      final driving = DemoDriving();
      final settings = SettingsStore(driving);
      final reports = ReportStore();
      await Future.wait([settings.load(), reports.load()]);
      settings.setThemeMode(ThemeMode.light);
      settings.setDrivingOverride(DrivingOverride.forceStopped);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>(create: (_) => DemoAuth()),
            ChangeNotifierProvider<DrivingMonitor>.value(value: driving),
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: reports),
            ChangeNotifierProvider<VoiceService>.value(value: voice),
            Provider(
              create: (_) => SiriBridge(),
              dispose: (_, s) => s.dispose(),
            ),
          ],
          child: const DemoChrome(child: ClearRoadsApp()),
        ),
      );
      await wait(1500);

      // ignore: avoid_print
      print('DEMO_START');
      await wait(2500);

      // 1. Onboarding
      await say(
        'Clear Roads: report road hazards hands-free, by voice or Siri.',
        hold: 3800,
      );
      await tap(find.text('Get started'), after: 1500);

      // 2. Home while stopped
      await say(
        'Home: one tap to report by voice, plus live stats for the area.',
        hold: 3500,
      );
      await scroll(330);
      await say(
        'Recent community reports, each with an automatic priority.',
        hold: 3000,
      );
      await scroll(-330);

      // 3. Community map
      await tap(find.text('Map'), after: 2500);
      await say(
        'Community map: every open hazard, filterable by type.',
        hold: 3000,
      );
      await tap(find.text('Dead animal'), after: 1500);
      await tap(find.text('Dead animal'), after: 1200);
      await say('Tap a pin to preview the report.', hold: 1500);
      final pinBox = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'HazardMapPin',
      );
      if (pinBox.evaluate().isNotEmpty) await tap(pinBox.first, after: 2500);
      await tap(find.text('Home'), after: 1200);

      // 4. Driving mode
      await say(
        'The app detects driving from GPS speed and the motion sensor…',
        hold: 2200,
      );
      settings.setDrivingOverride(DrivingOverride.forceDriving);
      await wait(1200);
      await say(
        '…and switches to a dark, glanceable Driving mode.',
        hold: 3500,
      );

      // 5. Voice report, all in one sentence
      await say('Tap once and just talk. No typing, no looking.', hold: 2200);
      voice.answers.add(
        'Dead deer partly in the right lane, cars swerving near the curve',
      );
      await tap(find.text('Tap & speak'), after: 500);
      await waitFor(find.text('Draft saved'), timeoutMs: 40000);
      caption.value =
          'One sentence fills in the hazard, lane and details. Saved as a draft with GPS.';
      await wait(3800);
      spoken.value = null;
      await say('While driving, the screen closes by itself.', hold: 1600);
      await tap(find.textContaining('Done'), after: 1500);

      // 6. One-tap draft
      await say(
        'Or one tap on a big button saves a draft instantly.',
        hold: 2200,
      );
      await tap(find.text('Fallen tree'), after: 2800);
      spoken.value = null;

      // 7. Siri
      caption.value = 'Siri: “Hey Siri, report snow or ice in Clear Roads”';
      await wait(3000);
      unawaited(
        VoiceReportScreen.open(
          navigatorKey.currentContext!,
          hazard: HazardType.snowIce,
          source: ReportSource.siri,
        ),
      );
      voice.answers.addAll([
        'It covers both lanes',
        'Near the school bus stop on the hill',
      ]);
      caption.value =
          'Siri opens the app, saves a draft right away, then asks two quick follow-ups.';
      await waitFor(find.text('Draft saved'), timeoutMs: 40000);
      await wait(4000);
      spoken.value = null;
      await tap(find.textContaining('Done'), after: 1500);

      // 8. Safety gate while driving
      await tap(find.text('Reports'), after: 1500);
      await say(
        'Drafts are safe here, but submitting is locked while driving.',
        hold: 3500,
      );
      await tap(
        find.text(
          'Dead deer partly in the right lane, cars swerving near the curve',
        ),
        after: 1500,
      );
      await say(
        'Editing and photos are locked too, so nobody types at 55 mph.',
        hold: 3500,
      );
      await tester.pageBack();
      await wait(1200);

      // 9. Stopped → unlock
      await say(
        'Once the car has been still for 45 s (a red light doesn’t count)…',
        hold: 2500,
      );
      settings.setDrivingOverride(DrivingOverride.forceStopped);
      await wait(1200);
      await say('…review and submit unlock.', hold: 2500);
      await tap(find.text('Home'), after: 1500);
      await say('Home reminds you that drafts are ready.', hold: 2500);
      await tap(find.textContaining('ready to submit'), after: 1500);

      // 10. Review + smart triage
      await tap(
        find.text(
          'Dead deer partly in the right lane, cars swerving near the curve',
        ),
        after: 1800,
      );
      await say(
        'Review the draft: change the hazard or lane, add a photo or a note.',
        hold: 3500,
      );
      await scroll(420);
      await say('Smart triage scores priority from 0 to 100…', hold: 1800);
      await tap(find.text('Why this score'), after: 1200);
      await say('…and explains every point.', hold: 3000);
      await scroll(330);
      await say(
        'It routes the report to the right agency, with the crew and equipment it needs.',
        hold: 4000,
      );
      await scroll(380);
      await wait(1500);
      await tap(find.text('Submit report'), after: 2500);
      await say('Submitted: auto-triaged and routed to State DOT.', hold: 2500);

      // 11. Status timeline
      await scroll(1400);
      await say(
        'Status timeline. Here we simulate the agency working the report:',
        hold: 2800,
      );
      for (var i = 0; i < 4; i++) {
        final next = find.textContaining('Simulate agency update');
        if (next.evaluate().isEmpty) break;
        await tap(next, after: 900);
        await scroll(260);
      }
      await say(
        'Under review, acknowledged, crew dispatched, resolved.',
        hold: 3500,
      );
      await tester.pageBack();
      await wait(1200);

      // 12. Submit the rest
      final all = find.textContaining('Submit all');
      if (all.evaluate().isNotEmpty) {
        await say('Remaining drafts can be sent in one tap.', hold: 1800);
        await tap(all, after: 2200);
      } else {
        final one = find.text('Submit report');
        if (one.evaluate().isNotEmpty) await tap(one, after: 2200);
      }
      await tap(find.textContaining('Submitted ('), after: 2500);
      await say('Everything you sent, with live status.', hold: 2500);

      // 13. Settings
      await tap(find.text('Settings'), after: 1500);
      await say('Siri phrases work right after install. No setup.', hold: 3200);
      await scroll(420);
      await say(
        'Driving detection settings, plus a demo override for showing it without a car.',
        hold: 3500,
      );
      await scroll(300);
      await tap(find.text('Dark'), after: 800);
      await say('Light and dark themes.', hold: 1500);
      await tap(find.text('Home'), after: 2500);
      await tap(find.text('Settings'), after: 800);
      await scroll(720, ms: 700);
      await tap(find.text('Light'), after: 800);
      await tap(find.text('Home'), after: 1200);

      await say('Clear Roads: spot a hazard? Just say it.', hold: 4000);
      caption.value = null;
      await wait(1000);
      // ignore: avoid_print
      print('DEMO_END');
      await wait(1500);
      FlutterError.onError = originalOnError;
    },
  );
}
