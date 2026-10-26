// Checks that every read and write Clear Roads makes (lib/services/cloud_sync.dart)
// is allowed by firestore.rules, and that other users are kept out.
//
//   cd tool/firestore_rules_test && npm install && npm test
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-clear-roads',
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8181,
    },
  });
});
beforeEach(() => env.clearFirestore());
after(() => env.cleanup());

const db = (uid) => env.authenticatedContext(uid).firestore();

// Same shape as CloudSync.toDoc(report).
const reportDoc = (id) => ({
  id,
  hazard: 'deadAnimal',
  blockage: 'fullLane',
  description: 'Deer in the right lane',
  latitude: 35.7796,
  longitude: -78.6382,
  road: 'US 64',
  locality: 'Raleigh',
  status: 'draft',
  source: 'voice',
  createdAt: '2026-10-24T09:15:00.000',
  submittedAt: null,
  reportedWhileDriving: true,
  updatedAt: '2026-10-24T09:15:00.000',
  timeline: [{ title: 'Draft saved', detail: 'Voice report', at: '2026-10-24T09:15:00.000', actor: 'You' }],
  type: 'report',
  hasPhoto: false,
  syncedAt: serverTimestamp(),
});

test('profile: first sign-in creates exactly name, photoURL, createdAt', async () => {
  const ref = doc(db('alice'), 'users/alice');
  await assertSucceeds(getDoc(ref)); // the app reads before creating
  await assertSucceeds(
    setDoc(ref, { name: 'Alice', photoURL: null, createdAt: serverTimestamp() }),
  );
});

test('profile: name/photo changes are allowed, createdAt is not', async () => {
  const ref = doc(db('alice'), 'users/alice');
  await setDoc(ref, { name: 'alice', photoURL: null, createdAt: serverTimestamp() });
  await assertSucceeds(updateDoc(ref, { name: 'Alice Smith' }));
  await assertSucceeds(updateDoc(ref, { photoURL: 'https://example.com/a.png' }));
  await assertFails(updateDoc(ref, { createdAt: serverTimestamp() }));
  // Why CloudSync never re-sends the full profile once it exists:
  await assertFails(
    setDoc(ref, { name: 'Alice', photoURL: null, createdAt: serverTimestamp() }),
  );
});

test('profile: rules reject what CloudSync.profileName guards against', async () => {
  const ref = doc(db('alice'), 'users/alice');
  await assertFails(setDoc(ref, { name: 'x'.repeat(51), photoURL: null, createdAt: serverTimestamp() }));
  await assertFails(setDoc(ref, { name: 'Alice', photoURL: null, createdAt: serverTimestamp(), email: 'a@b.c' }));
  await assertFails(
    setDoc(doc(db('bob'), 'users/alice'), { name: 'Bob', photoURL: null, createdAt: serverTimestamp() }),
  );
});

test('reports: owner can save, update, query and delete', async () => {
  const col = collection(db('alice'), 'users/alice/private');
  const ref = doc(col, 'r1');
  await assertSucceeds(setDoc(ref, reportDoc('r1')));
  await assertSucceeds(setDoc(ref, { ...reportDoc('r1'), status: 'submitted' }));
  const snap = await assertSucceeds(getDocs(query(col, where('type', '==', 'report'))));
  if (snap.size !== 1) throw new Error(`expected 1 report, got ${snap.size}`);
  await assertSucceeds(deleteDoc(ref));
});

test('reports: other users and signed-out visitors are kept out', async () => {
  await setDoc(doc(db('alice'), 'users/alice/private/r1'), reportDoc('r1'));
  const bob = db('bob');
  await assertFails(getDoc(doc(bob, 'users/alice/private/r1')));
  await assertFails(getDocs(collection(bob, 'users/alice/private')));
  await assertFails(setDoc(doc(bob, 'users/alice/private/r2'), reportDoc('r2')));
  await assertFails(deleteDoc(doc(bob, 'users/alice/private/r1')));
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, 'users/alice/private/r1')));
  await assertFails(getDoc(doc(anon, 'users/alice')));
});

test('account deletion: owner can wipe private docs and profile in one batch', async () => {
  const alice = db('alice');
  await setDoc(doc(alice, 'users/alice'), { name: 'Alice', photoURL: null, createdAt: serverTimestamp() });
  await setDoc(doc(alice, 'users/alice/private/r1'), reportDoc('r1'));
  await setDoc(doc(alice, 'users/alice/private/r2'), reportDoc('r2'));

  const docs = await getDocs(collection(alice, 'users/alice/private'));
  const batch = writeBatch(alice);
  docs.forEach((d) => batch.delete(d.ref));
  batch.delete(doc(alice, 'users/alice'));
  await assertSucceeds(batch.commit());
});

// Same shape as CloudSync.toPost(report, uid).
const postDoc = (uid, extra = {}) => ({
  authorId: uid,
  title: 'Dead animal blocking a lane',
  createdAt: serverTimestamp(),
  kind: 'hazard',
  hazard: 'deadAnimal',
  hazardLabel: 'Dead animal',
  blockage: 'fullLane',
  blockageLabel: 'Blocking a lane',
  status: 'submitted',
  statusLabel: 'Submitted',
  priority: 72,
  priorityLabel: 'High',
  description: 'Deer in the right lane',
  road: 'US 64',
  locality: 'Raleigh',
  lat: 35.7796,
  lng: -78.6382,
  reportedAt: '2026-10-24T13:15:00.000Z',
  submittedAt: '2026-10-24T13:20:00.000Z',
  updatedAt: '2026-10-24T13:20:00.000Z',
  ...extra,
});

test('map posts: the author can publish, update and remove', async () => {
  const ref = doc(db('alice'), 'posts/r1');
  await assertSucceeds(setDoc(ref, postDoc('alice')));
  // Status updates re-send the whole post (createdAt = server time again).
  await assertSucceeds(setDoc(ref, postDoc('alice', { status: 'inProgress', statusLabel: 'In progress' })));
  await assertSucceeds(deleteDoc(ref));
});

test('map posts: anyone, even signed out, can read them (the website)', async () => {
  await setDoc(doc(db('alice'), 'posts/r1'), postDoc('alice'));
  const anon = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(anon, 'posts/r1')));
  await assertSucceeds(getDocs(query(collection(anon, 'posts'), where('kind', '==', 'hazard'))));
});

test('map posts: no impersonation, no tampering by others', async () => {
  await assertFails(setDoc(doc(db('bob'), 'posts/x'), postDoc('alice')));
  await assertFails(setDoc(doc(db('alice'), 'posts/x'), postDoc('alice', { title: '' })));
  await assertFails(setDoc(doc(db('alice'), 'posts/x'), postDoc('alice', { createdAt: '2020-01-01' })));
  await setDoc(doc(db('alice'), 'posts/r1'), postDoc('alice'));
  await assertFails(setDoc(doc(db('bob'), 'posts/r1'), postDoc('bob')));
  await assertFails(deleteDoc(doc(db('bob'), 'posts/r1')));
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(setDoc(doc(anon, 'posts/y'), postDoc('anon')));
});

test('map posts: deleting a post that was never published is denied', async () => {
  // Why CloudSync only deletes posts for submitted reports.
  await assertFails(deleteDoc(doc(db('alice'), 'posts/never')));
});

test('account deletion also removes the author\'s map posts', async () => {
  const alice = db('alice');
  await setDoc(doc(alice, 'posts/r1'), postDoc('alice'));
  await setDoc(doc(alice, 'posts/r2'), postDoc('alice'));
  const mine = await getDocs(query(collection(alice, 'posts'), where('authorId', '==', 'alice')));
  const batch = writeBatch(alice);
  mine.forEach((d) => batch.delete(d.ref));
  await assertSucceeds(batch.commit());
});

test('nothing outside users/ and posts/ is writable', async () => {
  await assertFails(setDoc(doc(db('alice'), 'reports/r1'), reportDoc('r1')));
});
