import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/sample_reports.dart';
import '../models/hazard.dart';
import '../models/report.dart';
import 'triage_engine.dart';

/// Where the store mirrors the signed-in user's reports (Firestore).
abstract class ReportSync {
  Future<void> save(Report r);
  Future<void> remove(Report r);
}

/// Local-first report storage. Everything persists on-device so drafts made
/// with no signal on a rural road are never lost; [sync] mirrors the owner's
/// reports to the cloud.
class ReportStore extends ChangeNotifier {
  static const _key = 'clear_roads.reports.v1';
  static const _uuid = Uuid();

  /// Every report on this device, including other accounts' (hidden).
  final List<Report> _reports = [];
  SharedPreferences? _prefs;
  bool _loaded = false;
  String? _owner;

  ReportSync? sync;

  bool get loaded => _loaded;
  String? get owner => _owner;

  /// Samples plus the signed-in account's reports, newest first.
  List<Report> get _visible =>
      _reports.where((r) => r.isSample || r.ownerUid == _owner).toList();

  List<Report> get all => List.unmodifiable(_visible);
  List<Report> get drafts => _visible.where((r) => r.isDraft).toList();
  List<Report> get submitted => _visible.where((r) => !r.isDraft).toList();
  List<Report> get mine => _visible.where((r) => !r.isSample).toList();

  int get openCount => _visible.where((r) => r.status.isOpen).length;
  int get resolvedCount =>
      _visible.where((r) => r.status == ReportStatus.resolved).length;

  Report? byId(String id) {
    for (final r in _visible) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Switch to [uid]'s reports. Drafts made before accounts existed (no
  /// owner) are adopted by the first account that signs in.
  Future<void> setOwner(String? uid) async {
    _owner = uid;
    if (uid != null) {
      for (final r in _reports) {
        if (!r.isSample && r.ownerUid == null) r.ownerUid = uid;
      }
    }
    notifyListeners();
    await _save();
  }

  /// The owner's reports that should be uploaded.
  List<Report> get syncable =>
      _reports.where((r) => !r.isSample && r.ownerUid == _owner).toList();

  /// Merge the owner's reports downloaded from the cloud: new ones are added
  /// and the newer copy of each report wins. Returns the local reports that
  /// are newer than (or missing from) the cloud, so they can be uploaded.
  Future<List<Report>> mergeRemote(List<Report> remote) async {
    final owner = _owner;
    if (owner == null) return const [];
    final remoteById = {for (final r in remote) r.id: r};
    for (final rr in remote) {
      rr.ownerUid = owner;
      final i = _reports.indexWhere((x) => x.id == rr.id);
      if (i < 0) {
        _reports.add(rr);
      } else if (rr.updatedAt.isAfter(_reports[i].updatedAt)) {
        // Keep this device's photo; the cloud copy has no file.
        rr.photoPath ??= _reports[i].photoPath;
        _reports[i] = rr;
      }
    }
    _sort();
    notifyListeners();
    await _save();
    return syncable.where((l) {
      final rr = remoteById[l.id];
      return rr == null || l.updatedAt.isAfter(rr.updatedAt);
    }).toList();
  }

  /// Forget [uid]'s reports on this device (account deleted).
  Future<void> purgeOwner(String uid) async {
    _reports.removeWhere((r) => r.ownerUid == uid);
    notifyListeners();
    await _save();
  }

  /// Persist locally and mirror to the cloud.
  Future<void> _commit(Report r) async {
    r.updatedAt = DateTime.now();
    notifyListeners();
    await _save();
    _push(r);
  }

  void _push(Report r) {
    final s = sync;
    if (s == null || r.isSample || r.ownerUid == null) return;
    // Firestore queues writes while offline; never block the UI on them.
    s.save(r).catchError((Object e) {
      debugPrint('Report sync failed: $e');
    });
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key);
    _reports.clear();
    if (raw == null) {
      _reports.addAll(buildSampleReports(DateTime.now()));
    } else {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _reports.addAll(
          list.map((e) => Report.fromJson(e as Map<String, dynamic>)),
        );
      } catch (_) {
        _reports.addAll(buildSampleReports(DateTime.now()));
      }
    }
    _sort();
    _loaded = true;
    notifyListeners();
    await _save();
  }

  void _sort() => _reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> _save() async {
    await _prefs?.setString(
      _key,
      jsonEncode(_reports.map((r) => r.toJson()).toList()),
    );
  }

  Future<Report> createDraft({
    required HazardType hazard,
    Blockage blockage = Blockage.unknown,
    String description = '',
    double? latitude,
    double? longitude,
    String? road,
    String? locality,
    ReportSource source = ReportSource.voice,
    bool whileDriving = false,
  }) async {
    final now = DateTime.now();
    final r = Report(
      id: _uuid.v4(),
      hazard: hazard,
      blockage: blockage,
      description: description,
      latitude: latitude,
      longitude: longitude,
      road: road,
      locality: locality,
      createdAt: now,
      source: source,
      reportedWhileDriving: whileDriving,
      ownerUid: _owner,
      timeline: [
        TimelineEvent(
          title: 'Draft saved',
          detail:
              '${source.label} report${whileDriving ? ' while driving' : ''}',
          at: now,
        ),
      ],
    );
    _reports.insert(0, r);
    await _commit(r);
    return r;
  }

  Future<void> update(Report r) => _commit(r);

  /// Submit a draft. Callers must check [DrivingMonitor.canSubmit] first;
  /// this is enforced again here as a last line of defence.
  Future<void> submit(
    Report r, {
    required bool canSubmit,
    String? reference,
  }) async {
    if (!canSubmit) {
      throw StateError(
        'Reports can only be submitted when you are not driving.',
      );
    }
    if (!r.isDraft) return;
    final now = DateTime.now();
    final triage = TriageEngine.evaluate(r);
    final dup = TriageEngine.findDuplicate(r, _visible);
    r.status = ReportStatus.submitted;
    r.submittedAt = now;
    r.timeline.addAll([
      TimelineEvent(
        title: reference == null
            ? 'Submitted'
            : 'Submitted on the state DOT website',
        detail: reference == null ? null : 'Reference $reference',
        at: now,
      ),
      TimelineEvent(
        title:
            'Auto-triaged · Priority ${triage.score}/100 (${triage.level.label})',
        detail: triage.headline,
        at: now,
        actor: 'Clear Roads',
      ),
      TimelineEvent(
        title: 'Routed to ${triage.jurisdiction}',
        detail: '${triage.roadClass.label} · Recommended: ${triage.crew}',
        at: now,
        actor: 'Clear Roads',
      ),
      if (dup != null)
        TimelineEvent(
          title: 'Linked to a nearby report',
          detail:
              'Same hazard reported near ${dup.placeLabel} — merged as a confirmation.',
          at: now,
          actor: 'Clear Roads',
        ),
    ]);
    await _commit(r);
  }

  /// Demo only: simulate the agency moving the report forward.
  Future<void> advanceStatus(Report r) async {
    final next = r.status.next;
    if (next == null || r.isDraft) return;
    final triage = TriageEngine.evaluate(r);
    r.status = next;
    r.timeline.add(
      TimelineEvent(
        title: next.label,
        detail: switch (next) {
          ReportStatus.underReview => 'Dispatcher reviewing the report',
          ReportStatus.acknowledged =>
            '${triage.jurisdiction} accepted the work order',
          ReportStatus.inProgress => '${triage.crew} dispatched',
          ReportStatus.resolved =>
            'Crew cleared the hazard. Thanks for reporting!',
          _ => null,
        },
        at: DateTime.now(),
        actor: triage.jurisdiction,
      ),
    );
    await _commit(r);
  }

  Future<void> delete(Report r) async {
    _reports.removeWhere((x) => x.id == r.id);
    notifyListeners();
    await _save();
    _remove(r);
  }

  void _remove(Report r) {
    final s = sync;
    if (s == null || r.isSample || r.ownerUid == null) return;
    s.remove(r).catchError((Object e) {
      debugPrint('Report delete sync failed: $e');
    });
  }

  /// Removes the signed-in account's reports (here and in the cloud) and
  /// restores the samples. Other accounts' reports on this device are kept.
  Future<void> resetDemo() async {
    final mineNow = syncable;
    _reports.removeWhere((r) => r.isSample || r.ownerUid == _owner);
    _reports.addAll(buildSampleReports(DateTime.now()));
    _sort();
    notifyListeners();
    await _save();
    mineNow.forEach(_remove);
  }
}
