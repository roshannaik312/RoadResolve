import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/hazard.dart';
import '../models/report.dart';
import 'location_service.dart';

/// Hands a draft to the (demo) state DOT contact form, pre-filled, so the
/// driver only has to review and press Submit. The site sends the driver back
/// with `clearroads://portal/submitted?id=…&ref=…` (see [parseReturn]).
class ReportPortal {
  const ReportPortal._();

  static const scheme = 'clearroads';

  /// Default site address; change it in Settings (e.g. your Mac's LAN IP when
  /// testing on a phone) or with `--dart-define=PORTAL_URL=…`.
  static const defaultBaseUrl = String.fromEnvironment(
    'PORTAL_URL',
    defaultValue: 'https://roadresolve-ddedf.web.app',
  );

  /// Form sections (`UnitName`) matched by words in the driver's description,
  /// checked in order. Used when the hazard type alone doesn't pick a section.
  static final _sectionKeywords = <(String, RegExp)>[
    ('culvert', RegExp(r'\bculverts?\b')),
    (
      'drainage',
      RegExp(
        r'\b(drain|drains|drainage|flood|flooded|flooding|standing water|'
        r'ponding|puddles?|clogged|storm ?water|ditch)\b',
      ),
    ),
    ('guardrail', RegExp(r'\b(guard ?rails?|barrier|cable rail)\b')),
    (
      'signal',
      RegExp(r'\b(traffic (light|signal)s?|stop ?lights?|signals?)\b'),
    ),
    ('signs', RegExp(r'\b(signs?|signage|stop sign|yield sign)\b')),
    ('pothole', RegExp(r'\b(pot ?holes?|sinkholes?)\b')),
    (
      'shoulder',
      RegExp(
        r'\bshoulder\b.*\b(damage[d]?|drop ?off|rut|ruts|erod\w*|washed|'
        r'crumbl\w*|broken|soft|missing|cracked)\b|'
        r'\b(damage[d]?|drop ?off|rut|ruts|erod\w*|washed|crumbl\w*|broken|'
        r'soft|missing|cracked)\b.*\bshoulder\b',
      ),
    ),
  ];

  /// The road-problem section of the form (`UnitName`) for a draft.
  ///
  /// Something lying in the road always goes to Highway Debris/Dead Animals;
  /// potholes to Potholes. Otherwise the description picks the section
  /// (e.g. "stop sign knocked down" → Missing or Damaged Signage), falling
  /// back to Other. Snow and ice have no section of their own.
  static String unitFor(Report r) {
    switch (r.hazard) {
      case HazardType.deadAnimal:
      case HazardType.fallenTree:
      case HazardType.debris:
        return 'debris';
      case HazardType.pothole:
        return 'pothole';
      case HazardType.snowIce:
      case HazardType.other:
        break;
    }
    final text = r.description.toLowerCase();
    for (final (unit, pattern) in _sectionKeywords) {
      if (pattern.hasMatch(text)) return unit;
    }
    if (r.hazard == HazardType.other && r.blockage == Blockage.shoulder) {
      return 'shoulder';
    }
    return 'other';
  }

  static Future<Uri> buildUri(
    Report r, {
    required String baseUrl,
    String? name,
    String? email,
  }) async {
    var road = r.road;
    var city = r.locality;
    String? county;
    if (r.hasLocation) {
      final place = await LocationService.describe(r.latitude!, r.longitude!);
      road ??= place.road;
      city ??= place.locality;
      county = place.county;
    }

    final parts = (name ?? '').trim().split(RegExp(r'\s+'));
    final first = parts.isEmpty ? '' : parts.first;
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    final description = [
      r.hazard.label,
      if (r.blockage != Blockage.unknown) r.blockage.label.toLowerCase(),
      if (r.description.trim().isNotEmpty) r.description.trim(),
    ].join(' — ');

    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final base = Uri.parse(trimmed.isEmpty ? defaultBaseUrl : trimmed);
    return base.replace(
      path: '${base.path}/form.html',
      queryParameters: {
        'UnitName': unitFor(r),
        'sourceUrl': '/contact/',
        'hazard': r.hazard.id,
        'lane': r.blockage.name,
        'observed': r.createdAt.toIso8601String(),
        'description': description,
        if (road != null && road.isNotEmpty) 'road': road,
        if (city != null && city.isNotEmpty) 'city': city,
        if (county != null && county.isNotEmpty) 'county': county,
        if (r.hasLocation) 'lat': r.latitude!.toStringAsFixed(6),
        if (r.hasLocation) 'lng': r.longitude!.toStringAsFixed(6),
        if (first.isNotEmpty) 'firstName': first,
        if (last.isNotEmpty) 'lastName': last,
        if (email != null && email.isNotEmpty) 'email': email,
        if (r.photoPath != null) 'hasPhoto': '1',
        'reportId': r.id,
        'returnUrl': '$scheme://portal/submitted?id=${r.id}',
      },
    );
  }

  /// Opens the pre-filled form in an in-app Safari sheet.
  static Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.inAppBrowserView);

  static Future<void> close() => closeInAppWebView();

  /// Parses the link the site opens after Submit or Cancel. Depending on the
  /// iOS engine path, Flutter hands over either the full URL or only its
  /// path and query, so accept both.
  static PortalReturn? parseReturn(Uri uri) {
    final isOurs = uri.scheme == scheme || uri.scheme.isEmpty;
    if (!isOurs || !uri.path.endsWith('/submitted')) return null;
    final id = uri.queryParameters['id'];
    if (id == null || id.isEmpty) return null;
    return PortalReturn(
      reportId: id,
      submitted: uri.queryParameters['status'] != 'cancelled',
      reference: uri.queryParameters['ref'],
    );
  }
}

class PortalReturn {
  const PortalReturn({
    required this.reportId,
    required this.submitted,
    this.reference,
  });
  final String reportId;
  final bool submitted;
  final String? reference;
}

/// Catches the website's return links. It must be registered before runApp
/// so it sees links ahead of MaterialApp, which would otherwise try to push
/// them as named routes.
class PortalLinks with WidgetsBindingObserver {
  PortalLinks._();
  static final instance = PortalLinks._();

  final _returns = StreamController<PortalReturn>.broadcast();
  PortalReturn? _pending;

  Stream<PortalReturn> get returns => _returns.stream;

  void attach() => WidgetsBinding.instance.addObserver(this);

  /// A return that arrived while nothing was listening (e.g. signed out).
  PortalReturn? takePending() {
    final p = _pending;
    _pending = null;
    return p;
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final ret = ReportPortal.parseReturn(routeInformation.uri);
    if (ret == null) return false;
    if (_returns.hasListener) {
      _returns.add(ret);
    } else {
      _pending = ret;
    }
    return true;
  }
}
