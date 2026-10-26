import 'package:flutter/material.dart';

/// Hazard categories. `id` values are shared with the iOS Siri intent
/// (ios/Runner/HazardIntents.swift) — keep them in sync.
enum HazardType {
  deadAnimal(
    id: 'deadAnimal',
    label: 'Dead animal',
    spoken: 'dead animal',
    icon: Icons.pets_rounded,
    color: Color(0xFFB45309),
    baseScore: 40,
    keywords: [
      'dead animal',
      'carcass',
      'deer',
      'roadkill',
      'road kill',
      'animal',
      'raccoon',
      'possum',
      'opossum',
      'skunk',
      'moose',
      'coyote',
      'fox',
      'dog',
      'cat',
      'bear',
      'elk',
      'turkey',
      'dead',
    ],
  ),
  fallenTree(
    id: 'fallenTree',
    label: 'Fallen tree',
    spoken: 'fallen tree',
    icon: Icons.park_rounded,
    color: Color(0xFF15803D),
    baseScore: 55,
    keywords: [
      'fallen tree',
      'tree',
      'trees',
      'branch',
      'branches',
      'limb',
      'log',
      'trunk',
      'timber',
      'downed',
    ],
  ),
  snowIce(
    id: 'snowIce',
    label: 'Snow or ice',
    spoken: 'snow or ice',
    icon: Icons.ac_unit_rounded,
    color: Color(0xFF0369A1),
    baseScore: 50,
    keywords: [
      'snow',
      'ice',
      'icy',
      'black ice',
      'slush',
      'unplowed',
      'not plowed',
      'plow',
      'frozen',
      'sleet',
      'slippery',
      'drift',
      'snowdrift',
    ],
  ),
  pothole(
    id: 'pothole',
    label: 'Pothole',
    spoken: 'pothole',
    icon: Icons.radio_button_checked_rounded,
    color: Color(0xFF7C3AED),
    baseScore: 30,
    keywords: ['pothole', 'pot hole', 'hole', 'crater', 'sinkhole', 'crack'],
  ),
  debris(
    id: 'debris',
    label: 'Debris',
    spoken: 'debris',
    icon: Icons.inventory_2_rounded,
    color: Color(0xFFB91C1C),
    baseScore: 40,
    keywords: [
      'debris',
      'rock',
      'rocks',
      'boulder',
      'trash',
      'tire',
      'ladder',
      'mattress',
      'box',
      'garbage',
      'junk',
      'object',
      'gravel',
      'mud',
    ],
  ),
  other(
    id: 'other',
    label: 'Other',
    spoken: 'road hazard',
    icon: Icons.report_rounded,
    color: Color(0xFF475569),
    baseScore: 30,
    keywords: ['other', 'something else', 'hazard'],
  );

  const HazardType({
    required this.id,
    required this.label,
    required this.spoken,
    required this.icon,
    required this.color,
    required this.baseScore,
    required this.keywords,
  });

  final String id;
  final String label;
  final String spoken;
  final IconData icon;
  final Color color;
  final int baseScore;
  final List<String> keywords;

  /// The three hazards this app is built around; shown first everywhere.
  static const primary = [deadAnimal, fallenTree, snowIce];

  static HazardType? fromId(String? id) {
    for (final h in values) {
      if (h.id == id) return h;
    }
    return null;
  }
}

/// How much of the road the hazard occupies.
enum Blockage {
  unknown('Not specified', 'not specified', Icons.help_outline_rounded, 0),
  shoulder(
    'Shoulder / roadside',
    'on the shoulder',
    Icons.turn_slight_right_rounded,
    0,
  ),
  partialLane(
    'Partly in a lane',
    'partly blocking a lane',
    Icons.vertical_split_rounded,
    18,
  ),
  fullLane('Blocking a lane', 'blocking a lane', Icons.block_rounded, 28),
  allLanes(
    'Blocking all lanes',
    'blocking all lanes',
    Icons.do_not_disturb_on_total_silence_rounded,
    40,
  );

  const Blockage(this.label, this.spoken, this.icon, this.score);

  final String label;
  final String spoken;
  final IconData icon;
  final int score;

  static Blockage fromName(String? name) =>
      values.firstWhere((b) => b.name == name, orElse: () => unknown);
}
