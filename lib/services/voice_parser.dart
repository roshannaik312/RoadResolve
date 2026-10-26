import '../models/hazard.dart';

/// Turns free-form speech ("there's a dead deer in the right lane") into
/// structured fields. Deterministic keyword matching: it runs on-device,
/// works offline and is predictable while driving.
class VoiceParser {
  const VoiceParser._();

  static String _norm(String text) =>
      ' ${text.toLowerCase().replaceAll(RegExp(r"['\u2019]"), '').replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';

  static bool _has(String norm, String phrase) => norm.contains(' $phrase ');

  /// Best hazard match, preferring the longest (most specific) keyword.
  static HazardType? hazard(String text) {
    final n = _norm(text);
    HazardType? best;
    var bestLen = 0;
    for (final h in HazardType.values) {
      for (final k in h.keywords) {
        if (_has(n, k) && k.length > bestLen) {
          best = h;
          bestLen = k.length;
        }
      }
    }
    // "dead" alone is weak; "dead tree" is a tree.
    if (best == HazardType.deadAnimal && bestLen <= 4) {
      for (final k in HazardType.fallenTree.keywords) {
        if (_has(n, k)) return HazardType.fallenTree;
      }
    }
    return best;
  }

  static const _allLanes = [
    'all lanes',
    'both lanes',
    'whole road',
    'entire road',
    'both directions',
    'road is blocked',
    'road blocked',
    'completely blocked',
    'across the road',
    'across both',
    'all of it',
    'road closed',
    'impassable',
    'cant get through',
    'everything',
  ];
  static const _fullLane = [
    'blocking the lane',
    'blocking a lane',
    'blocking one lane',
    'blocks the lane',
    'in the lane',
    'in my lane',
    'middle of the lane',
    'middle of the road',
    'in the road',
    'one lane',
    'the lane',
    'right lane',
    'left lane',
    'center lane',
    'travel lane',
    'blocking traffic',
    'a lane',
    'lane',
    'blocking',
    'in the way',
  ];
  static const _partial = [
    'partially',
    'partly',
    'part of',
    'half',
    'edge of the lane',
    'sticking out',
    'a little',
    'some of',
    'into the lane',
    'a bit',
  ];
  static const _shoulder = [
    'shoulder',
    'side of the road',
    'roadside',
    'off the road',
    'ditch',
    'not blocking',
    'isnt blocking',
    'no',
    'nope',
    'curb',
    'sidewalk',
    'median',
    'grass',
  ];

  /// Lane blockage, or null if nothing recognisable was said.
  static Blockage? blockage(String text) {
    final n = _norm(text);
    bool any(List<String> words) => words.any((w) => _has(n, w));
    if (any(_allLanes)) return Blockage.allLanes;
    if (any(_partial)) return Blockage.partialLane;
    if (any(const [
      'not blocking',
      'isnt blocking',
      'shoulder',
      'side of the road',
      'ditch',
    ])) {
      return Blockage.shoulder;
    }
    if (any(_fullLane)) return Blockage.fullLane;
    if (any(_shoulder)) return Blockage.shoulder;
    if (any(const ['yes', 'yeah', 'yep'])) return Blockage.fullLane;
    return null;
  }

  static bool isSkip(String text) {
    final n = _norm(text);
    return const [
          'skip',
          'no',
          'nope',
          'nothing',
          'none',
          'done',
          'thats it',
          'thats all',
          'no thanks',
          'nothing else',
          'all good',
          'finish',
          'save',
          'save it',
        ].any((w) => _has(n, w)) &&
        n.trim().split(' ').length <= 4;
  }

  static bool isCancel(String text) {
    final n = _norm(text);
    return const [
      'cancel',
      'never mind',
      'nevermind',
      'stop',
      'forget it',
    ].any((w) => _has(n, w));
  }
}
