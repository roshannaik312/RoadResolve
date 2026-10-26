import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/report.dart';
import '../models/hazard.dart';
import 'auth_service.dart';
import 'report_store.dart';
import 'triage_engine.dart';

/// Mirrors the signed-in user's data to Firestore, within the project's
/// security rules (firestore.rules):
///
///   users/{uid}                    profile: exactly {name, photoURL, createdAt};
///                                  later updates may only touch name/photoURL
///   users/{uid}/private/{reportId} one document per report (owner-only)
///   posts/{reportId}               public copy of each *submitted* report for
///                                  the website's incident map: no name,
///                                  email or photo; authorId is the uid and
///                                  createdAt must be the server time
///
/// Reports stay local-first: [ReportStore] saves on the device and calls
/// [save]/[remove]; Firestore queues those writes while offline. Photos stay
/// on the device (Firestore isn't for files, and the rules don't cover
/// Storage), so the cloud copy only records whether there was one.
class CloudSync implements ReportSync {
  CloudSync({
    required this.auth,
    required this.store,
    this.shareOnMap,
    this.sharingChanges,
    FirebaseFirestore? db,
  }) : _dbOverride = db;

  final AuthService auth;
  final ReportStore store;

  /// Whether submitted reports go on the public map (Settings). Null = yes.
  final bool Function()? shareOnMap;

  /// Notifies when [shareOnMap] may have changed.
  final Listenable? sharingChanges;
  bool get _sharing => shareOnMap?.call() ?? true;

  final FirebaseFirestore? _dbOverride;
  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  static const maxNameLength = 50;
  static const _type = 'report';

  String? _uid;
  String? _syncedName;
  String? _syncedPhoto;
  // Profile writes run one at a time so two quick auth events can't both
  // try to create the document (the second would be rejected as an update
  // that changes createdAt).
  Future<void> _profileQueue = Future.value();

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _privateCol(String uid) =>
      _userDoc(uid).collection('private');

  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('posts');

  bool? _lastSharing;

  void start() {
    store.sync = this;
    auth.beforeDelete = deleteUserData;
    auth.addListener(_onAuth);
    sharingChanges?.addListener(_onSharingChanged);
    _lastSharing = _sharing;
    _onAuth();
  }

  /// Turning sharing off takes the user's reports off the map; turning it
  /// back on republishes their submitted ones.
  void _onSharingChanged() {
    if (_sharing == _lastSharing) return;
    _lastSharing = _sharing;
    for (final r in store.syncable) {
      unawaited(
        _syncPost(r).catchError((Object e) {
          debugPrint('Map sync failed: $e');
        }),
      );
    }
  }

  void _onAuth() {
    final user = auth.user;
    final uid = user?.uid;
    if (uid != _uid) {
      _uid = uid;
      _syncedName = null;
      _syncedPhoto = null;
      unawaited(store.setOwner(uid));
      if (uid != null) unawaited(_pullAndPush(uid));
    }
    if (user != null) {
      _profileQueue = _profileQueue
          .then((_) => _syncProfile(user))
          .catchError((Object e) => debugPrint('Profile sync failed: $e'));
    }
  }

  // -------------------------------------------------------------- profile

  /// The profile name the rules accept: a string of at most 50 characters.
  @visibleForTesting
  static String profileName(User user) {
    var name = user.displayName?.trim() ?? '';
    if (name.isEmpty) name = user.email?.split('@').first ?? '';
    if (name.isEmpty) name = 'Clear Roads driver';
    return name.length > maxNameLength
        ? name.substring(0, maxNameLength)
        : name;
  }

  Future<void> _syncProfile(User user) async {
    if (user.uid != _uid) return;
    final name = profileName(user);
    final photo = user.photoURL;
    if (name == _syncedName && photo == _syncedPhoto) return;

    final ref = _userDoc(user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      // Create: exactly the three keys the rules allow.
      await ref.set({
        'name': name,
        'photoURL': photo,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      final data = snap.data() ?? const {};
      final changes = <String, Object?>{
        if (data['name'] != name) 'name': name,
        if (data['photoURL'] != photo) 'photoURL': photo,
      };
      // Update: only name/photoURL may change.
      if (changes.isNotEmpty) await ref.update(changes);
    }
    _syncedName = name;
    _syncedPhoto = photo;
  }

  // -------------------------------------------------------------- reports

  /// Firestore form of a report. The device-only photo path is replaced by
  /// a flag, and the owner is implied by the document path.
  @visibleForTesting
  static Map<String, dynamic> toDoc(Report r) {
    final json = r.toJson()
      ..remove('photoPath')
      ..remove('ownerUid');
    return {
      ...json,
      'type': _type,
      'hasPhoto': r.photoPath != null,
      'syncedAt': FieldValue.serverTimestamp(),
    };
  }

  @visibleForTesting
  static Report fromDoc(Map<String, dynamic> data) {
    final json = Map<String, dynamic>.of(data)
      ..remove('type')
      ..remove('hasPhoto')
      ..remove('syncedAt');
    return Report.fromJson(json);
  }

  Future<void> _pullAndPush(String uid) async {
    try {
      final snap = await _privateCol(uid).where('type', isEqualTo: _type).get();
      if (uid != _uid) return;
      final remote = <Report>[];
      for (final d in snap.docs) {
        try {
          remote.add(fromDoc(d.data()));
        } catch (e) {
          debugPrint('Skipping unreadable report ${d.id}: $e');
        }
      }
      final toUpload = await store.mergeRemote(remote);
      for (final r in toUpload) {
        await save(r);
      }
    } catch (e) {
      debugPrint('Report download failed: $e');
    }
  }

  @override
  Future<void> save(Report r) async {
    final uid = r.ownerUid;
    if (uid == null || uid != _uid || r.isSample) return;
    await _privateCol(uid).doc(r.id).set(toDoc(r));
    await _syncPost(r);
  }

  @override
  Future<void> remove(Report r) async {
    final uid = r.ownerUid;
    if (uid == null || uid != _uid) return;
    await _privateCol(uid).doc(r.id).delete();
    // Drafts were never published.
    if (!r.isDraft) await _deletePost(r.id);
  }

  // ------------------------------------------------------- public map

  /// Only submitted reports with a location, and only while sharing is on.
  static bool isPublic(Report r) => !r.isDraft && !r.isSample && r.hasLocation;

  Future<void> _syncPost(Report r) async {
    final uid = r.ownerUid;
    if (uid == null || uid != _uid) return;
    if (_sharing && isPublic(r)) {
      await _posts.doc(r.id).set(toPost(r, uid));
    } else if (!r.isDraft) {
      await _deletePost(r.id);
    }
  }

  Future<void> _deletePost(String id) async {
    try {
      await _posts.doc(id).delete();
    } on FirebaseException catch (e) {
      // Never published (or already gone): the delete rule reads
      // resource.data.authorId, which doesn't exist for a missing doc.
      if (e.code != 'permission-denied' && e.code != 'not-found') rethrow;
    }
  }

  /// The public map entry. Matches the `posts` create rule: authorId is the
  /// signed-in uid, title is 1–200 characters, createdAt is server time.
  /// Personal details (name, email, photo) are never included.
  @visibleForTesting
  static Map<String, dynamic> toPost(Report r, String uid) {
    final triage = TriageEngine.evaluate(r);
    var title = triage.headline.trim();
    if (title.isEmpty) title = r.hazard.label;
    if (title.length > 200) title = title.substring(0, 200);
    return {
      'authorId': uid,
      'title': title,
      'createdAt': FieldValue.serverTimestamp(),
      'kind': 'hazard',
      'hazard': r.hazard.id,
      'hazardLabel': r.hazard.label,
      'blockage': r.blockage.name,
      'blockageLabel': r.blockage == Blockage.unknown ? null : r.blockage.label,
      'status': r.status.name,
      'statusLabel': r.status.label,
      'priority': triage.score,
      'priorityLabel': triage.level.label,
      'description': r.description,
      'road': r.road,
      'locality': r.locality,
      'lat': r.latitude,
      'lng': r.longitude,
      'reportedAt': r.createdAt.toUtc().toIso8601String(),
      'submittedAt': r.submittedAt?.toUtc().toIso8601String(),
      'updatedAt': r.updatedAt.toUtc().toIso8601String(),
    };
  }

  // -------------------------------------------------------------- account

  /// Deletes everything stored for [uid] (all private documents, then the
  /// profile). Runs while the user is still signed in, before the account
  /// itself is deleted, because the rules only let the owner delete.
  Future<void> deleteUserData(String uid) async {
    final refs = [
      for (final d in (await _privateCol(uid).get()).docs) d.reference,
      for (final d
          in (await _posts.where('authorId', isEqualTo: uid).get()).docs)
        d.reference,
      _userDoc(uid),
    ];
    // A batch holds at most 500 writes.
    for (var i = 0; i < refs.length; i += 450) {
      final batch = _db.batch();
      for (final ref in refs.skip(i).take(450)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
    await store.purgeOwner(uid);
  }
}
