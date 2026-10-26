import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'driving_monitor.dart';
import 'report_portal.dart';

class SettingsStore extends ChangeNotifier {
  SettingsStore(this._driving);

  final DrivingMonitor _driving;
  SharedPreferences? _prefs;

  bool _voicePrompts = true;
  bool _onboarded = false;
  ThemeMode _themeMode = ThemeMode.system;
  String _portalUrl = ReportPortal.defaultBaseUrl;
  bool _shareOnMap = true;

  bool get voicePrompts => _voicePrompts;
  bool get onboarded => _onboarded;
  ThemeMode get themeMode => _themeMode;

  /// Base address of the (demo) DOT contact site drafts are submitted to.
  String get portalUrl => _portalUrl;

  /// Publish submitted reports (no name, email or photo) to the public
  /// incident map on the report website.
  bool get shareOnMap => _shareOnMap;
  DrivingOverride get drivingOverride => _driving.overrideMode;

  Future<void> load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    _voicePrompts = p.getBool('voicePrompts') ?? true;
    _onboarded = p.getBool('onboarded') ?? false;
    _themeMode = ThemeMode.values[p.getInt('themeMode') ?? 0];
    _portalUrl = p.getString('portalUrl') ?? ReportPortal.defaultBaseUrl;
    _shareOnMap = p.getBool('shareOnMap') ?? true;
    _driving.setOverride(
      DrivingOverride.values[p.getInt('drivingOverride') ?? 0],
    );
    notifyListeners();
  }

  void setVoicePrompts(bool v) {
    _voicePrompts = v;
    _prefs?.setBool('voicePrompts', v);
    notifyListeners();
  }

  void setOnboarded() {
    _onboarded = true;
    _prefs?.setBool('onboarded', true);
    notifyListeners();
  }

  void setThemeMode(ThemeMode m) {
    _themeMode = m;
    _prefs?.setInt('themeMode', m.index);
    notifyListeners();
  }

  void setPortalUrl(String url) {
    final v = url.trim();
    _portalUrl = v.isEmpty ? ReportPortal.defaultBaseUrl : v;
    _prefs?.setString('portalUrl', _portalUrl);
    notifyListeners();
  }

  void setShareOnMap(bool v) {
    _shareOnMap = v;
    _prefs?.setBool('shareOnMap', v);
    notifyListeners();
  }

  void setDrivingOverride(DrivingOverride o) {
    _driving.setOverride(o);
    _prefs?.setInt('drivingOverride', o.index);
    notifyListeners();
  }
}
