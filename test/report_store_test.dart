import 'package:clear_roads/models/hazard.dart';
import 'package:clear_roads/models/report.dart';
import 'package:clear_roads/services/cloud_sync.dart';
import 'package:clear_roads/services/report_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingSync implements ReportSync {
  final saved = <String>[];
  final removed = <String>[];

  @override
  Future<void> save(Report r) async => saved.add(r.id);

  @override
  Future<void> remove(Report r) async => removed.add(r.id);
}

Future<ReportStore> freshStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = ReportStore();
  await store.load();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each account only sees its own reports plus the samples', () async {
    final store = await freshStore();
    final samples = store.all.length;

    await store.setOwner('alice');
    final a = await store.createDraft(hazard: HazardType.pothole);
    expect(a.ownerUid, 'alice');
    expect(store.mine.map((r) => r.id), [a.id]);

    await store.setOwner('bob');
    expect(store.mine, isEmpty);
    expect(store.byId(a.id), isNull);
    expect(store.all.length, samples);

    await store.setOwner('alice');
    expect(store.byId(a.id), isNotNull);
  });

  test(
    'drafts made before signing in are adopted by the first account',
    () async {
      final store = await freshStore();
      final early = await store.createDraft(hazard: HazardType.debris);
      expect(early.ownerUid, isNull);

      await store.setOwner('alice');
      expect(early.ownerUid, 'alice');
      expect(store.syncable.map((r) => r.id), [early.id]);
    },
  );

  test('changes are pushed for owned reports, never for samples', () async {
    final store = await freshStore();
    final sync = RecordingSync();
    store.sync = sync;
    await store.setOwner('alice');

    final r = await store.createDraft(hazard: HazardType.fallenTree);
    await store.submit(r, canSubmit: true, reference: 'DEMO-1');
    final sample = store.all.firstWhere((x) => x.isSample);
    await store.update(sample);
    await store.delete(r);

    expect(sync.saved, [r.id, r.id]);
    expect(sync.removed, [r.id]);
  });

  test('merge keeps the newer copy and reports what to upload', () async {
    final store = await freshStore();
    await store.setOwner('alice');
    final local = await store.createDraft(
      hazard: HazardType.snowIce,
      description: 'local',
    );
    local.photoPath = '/device/photo.jpg';

    final newer = Report.fromJson({
      ...local.toJson(),
      'description': 'edited on another phone',
      'updatedAt': local.updatedAt
          .add(const Duration(minutes: 5))
          .toIso8601String(),
    })..photoPath = null;
    final remoteOnly = Report(
      id: 'remote-only',
      hazard: HazardType.pothole,
      createdAt: DateTime(2026, 10, 1),
    );

    final upload = await store.mergeRemote([newer, remoteOnly]);
    expect(store.byId(local.id)!.description, 'edited on another phone');
    // The cloud copy has no photo file, so this device's photo is kept.
    expect(store.byId(local.id)!.photoPath, '/device/photo.jpg');
    expect(store.byId('remote-only')!.ownerUid, 'alice');
    expect(upload, isEmpty);

    final offline = await store.createDraft(hazard: HazardType.debris);
    final again = await store.mergeRemote([newer, remoteOnly]);
    expect(again.map((r) => r.id), [offline.id]);
  });

  test('Firestore documents drop the device photo path but round-trip', () {
    final r = Report(
      id: 'x',
      hazard: HazardType.deadAnimal,
      blockage: Blockage.fullLane,
      createdAt: DateTime(2026, 10, 24, 9),
      description: 'Deer',
      latitude: 35.78,
      longitude: -78.64,
      photoPath: '/private/var/photo.jpg',
      ownerUid: 'alice',
    );
    final doc = CloudSync.toDoc(r);
    expect(doc.containsKey('photoPath'), isFalse);
    expect(doc.containsKey('ownerUid'), isFalse);
    expect(doc['hasPhoto'], isTrue);
    expect(doc['type'], 'report');

    final back = CloudSync.fromDoc({...doc}..remove('syncedAt'));
    expect(back.id, 'x');
    expect(back.blockage, Blockage.fullLane);
    expect(back.latitude, 35.78);
    expect(back.photoPath, isNull);
  });

  test('public map post has the rule-required fields and no personal data', () {
    final r =
        Report(
            id: 'x',
            hazard: HazardType.fallenTree,
            blockage: Blockage.allLanes,
            createdAt: DateTime.utc(2026, 10, 24, 9),
            description: 'Oak across both lanes',
            latitude: 35.78,
            longitude: -78.64,
            road: 'US 64',
            photoPath: '/private/var/photo.jpg',
            ownerUid: 'alice',
          )
          ..status = ReportStatus.submitted
          ..submittedAt = DateTime.utc(2026, 10, 24, 9, 5);

    final post = CloudSync.toPost(r, 'alice');
    expect(post['authorId'], 'alice');
    expect((post['title'] as String).isNotEmpty, isTrue);
    expect((post['title'] as String).length <= 200, isTrue);
    expect(post.containsKey('createdAt'), isTrue);
    expect(post['lat'], 35.78);
    expect(post['hazard'], 'fallenTree');
    for (final k in ['photoPath', 'photoURL', 'email', 'name', 'ownerUid']) {
      expect(post.containsKey(k), isFalse, reason: k);
    }

    expect(CloudSync.isPublic(r), isTrue);
    r.status = ReportStatus.draft;
    expect(CloudSync.isPublic(r), isFalse);
  });
}
