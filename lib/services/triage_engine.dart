import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/hazard.dart';
import '../models/report.dart';

enum PriorityLevel {
  low('Low', Color(0xFF15803D)),
  medium('Medium', Color(0xFFCA8A04)),
  high('High', Color(0xFFEA580C)),
  critical('Critical', Color(0xFFDC2626));

  const PriorityLevel(this.label, this.color);
  final String label;
  final Color color;

  static PriorityLevel fromScore(int score) {
    if (score >= 80) return critical;
    if (score >= 60) return high;
    if (score >= 40) return medium;
    return low;
  }
}

enum RoadClass {
  stateHighway('State highway', 'State DOT', 55),
  countyRoad('County road', 'County Highway Department', 45),
  localStreet('Local street', 'Town Public Works', 30);

  const RoadClass(this.label, this.agency, this.typicalSpeedMph);
  final String label;
  final String agency;
  final int typicalSpeedMph;
}

class ScoreFactor {
  const ScoreFactor(this.points, this.reason);
  final int points;
  final String reason;
}

class TriageResult {
  const TriageResult({
    required this.score,
    required this.level,
    required this.headline,
    required this.factors,
    required this.roadClass,
    required this.crew,
    required this.equipment,
    required this.targetResponse,
    this.advisories = const [],
  });

  final int score;
  final PriorityLevel level;
  final String headline;
  final List<ScoreFactor> factors;
  final RoadClass roadClass;
  final String crew;
  final List<String> equipment;
  final String targetResponse;
  final List<String> advisories;

  String get jurisdiction => roadClass.agency;
}

/// Deterministic rules engine: severity score, jurisdiction and crew
/// recommendation. Every point is explained so dispatchers (and judges)
/// can see why a report ranked where it did.
class TriageEngine {
  const TriageEngine._();

  static RoadClass classifyRoad(String? road) {
    final r = (road ?? '').toLowerCase();
    if (RegExp(
      r'\b(i-?\d+|interstate|us-?\s?\d+|us route|state route|sr-?\s?\d+|route \d+|rte|highway|hwy|expressway|freeway|turnpike|parkway|thruway|nc-?\d+|ny-?\d+)\b',
    ).hasMatch(r)) {
      return RoadClass.stateHighway;
    }
    if (RegExp(r'\b(county|cr-?\s?\d+|co rd|co\. rd)\b').hasMatch(r)) {
      return RoadClass.countyRoad;
    }
    return RoadClass.localStreet;
  }

  static TriageResult evaluate(Report report) {
    final factors = <ScoreFactor>[];
    final text = report.description.toLowerCase();
    final h = report.hazard;
    final road = classifyRoad(report.road);

    factors.add(ScoreFactor(h.baseScore, '${h.label} base risk'));
    if (report.blockage.score > 0) {
      factors.add(
        ScoreFactor(
          report.blockage.score,
          'Hazard is ${report.blockage.spoken}',
        ),
      );
    } else if (report.blockage == Blockage.unknown) {
      factors.add(
        const ScoreFactor(
          5,
          'Lane position unknown — assumed near travel lane',
        ),
      );
    }

    switch (road) {
      case RoadClass.stateHighway:
        factors.add(const ScoreFactor(15, 'High-speed road (≈55 mph)'));
      case RoadClass.countyRoad:
        factors.add(const ScoreFactor(8, 'Rural county road (≈45 mph)'));
      case RoadClass.localStreet:
        break;
    }

    void bump(List<String> words, int pts, String why) {
      if (words.any(text.contains)) factors.add(ScoreFactor(pts, why));
    }

    bump(
      ['power line', 'powerline', 'wire', 'wires', 'utility pole'],
      18,
      'Possible downed power lines',
    );
    bump(
      ['school', 'bus stop', 'bus route', 'kids'],
      8,
      'Near school / bus route',
    );
    bump(
      ['curve', 'blind', 'hill', 'bridge', 'overpass'],
      6,
      'Low-visibility location',
    );
    bump(['night', 'dark', 'fog', 'foggy'], 4, 'Poor visibility conditions');
    bump(
      ['deer', 'moose', 'elk', 'bear', 'large', 'big', 'huge'],
      5,
      'Large object',
    );
    bump(
      ['accident', 'crash', 'swerv', 'almost hit', 'near miss'],
      10,
      'Drivers swerving / near misses',
    );
    if (h == HazardType.snowIce) {
      bump(
        ['black ice', 'unplowed', 'not plowed', 'inches', 'deep'],
        8,
        'Unplowed or icy surface',
      );
    }

    final score = math.min(100, factors.fold<int>(0, (s, f) => s + f.points));
    final level = PriorityLevel.fromScore(score);

    final (crew, equipment, advisories) = _response(report, road);

    return TriageResult(
      score: score,
      level: level,
      headline: headline(report),
      factors: factors,
      roadClass: road,
      crew: crew,
      equipment: equipment,
      targetResponse: switch (level) {
        PriorityLevel.critical => 'Dispatch within 30 min',
        PriorityLevel.high => 'Dispatch within 2 hours',
        PriorityLevel.medium => 'Same day',
        PriorityLevel.low => 'Next scheduled route (1–3 days)',
      },
      advisories: advisories,
    );
  }

  static String headline(Report r) {
    final text = r.description.toLowerCase();
    final subject = switch (r.hazard) {
      HazardType.deadAnimal =>
        text.contains('deer') ? 'Deer carcass' : 'Animal carcass',
      HazardType.fallenTree =>
        text.contains('branch') || text.contains('limb')
            ? 'Fallen branch'
            : 'Fallen tree',
      HazardType.snowIce =>
        text.contains('ice') ? 'Icy road surface' : 'Snow-covered road',
      HazardType.pothole => 'Pothole',
      HazardType.debris => 'Debris in roadway',
      HazardType.other => 'Road hazard',
    };
    if (r.blockage == Blockage.unknown) return subject;
    return '$subject, ${r.blockage.spoken}';
  }

  static (String, List<String>, List<String>) _response(
    Report r,
    RoadClass road,
  ) {
    final inLane =
        r.blockage == Blockage.partialLane ||
        r.blockage == Blockage.fullLane ||
        r.blockage == Blockage.allLanes;
    final traffic = <String>[
      if (inLane) 'Traffic cones + arrow board',
      if (inLane && road == RoadClass.stateHighway) 'Truck-mounted attenuator',
      if (r.blockage == Blockage.allLanes) 'Flaggers / road-closed signage',
    ];
    final text = r.description.toLowerCase();
    final advisories = <String>[];

    switch (r.hazard) {
      case HazardType.deadAnimal:
        final large = ['deer', 'moose', 'elk', 'bear'].any(text.contains);
        return (
          'Roadside carcass-removal crew (2)',
          [
            large ? 'Pickup with winch / lift gate' : 'Pickup truck',
            'PPE + disposal bags',
            ...traffic,
          ],
          advisories,
        );
      case HazardType.fallenTree:
        if (['wire', 'power', 'utility'].any(text.contains)) {
          advisories.add(
            'Notify electric utility before clearing — possible live wires.',
          );
        }
        return (
          r.blockage == Blockage.allLanes
              ? 'Tree crew (3) + loader operator'
              : 'Tree crew (2)',
          [
            'Chainsaws',
            if (r.blockage == Blockage.allLanes)
              'Front loader / grapple'
            else
              'Brush chipper',
            ...traffic,
          ],
          advisories,
        );
      case HazardType.snowIce:
        if (['school', 'bus'].any(text.contains)) {
          advisories.add(
            'School/bus route — prioritize before morning pickup.',
          );
        }
        return (
          'Plow route operator',
          [
            text.contains('ice')
                ? 'Salt / brine spreader'
                : 'Plow truck with spreader',
            if (road == RoadClass.stateHighway) 'Tandem plow (multi-lane)',
          ],
          advisories,
        );
      case HazardType.pothole:
        return (
          'Patch crew (2)',
          ['Cold-patch asphalt', 'Tamper', ...traffic],
          advisories,
        );
      case HazardType.debris:
        return (
          'Roadside clean-up crew',
          ['Pickup truck', 'Broom / sweeper', ...traffic],
          advisories,
        );
      case HazardType.other:
        return (
          'Field inspector',
          ['Inspection vehicle', ...traffic],
          advisories,
        );
    }
  }

  /// Open report of the same type within [radiusMeters] in the last day.
  static Report? findDuplicate(
    Report candidate,
    Iterable<Report> others, {
    double radiusMeters = 200,
  }) {
    if (!candidate.hasLocation) return null;
    for (final o in others) {
      if (o.id == candidate.id || o.isDraft || !o.status.isOpen) continue;
      if (o.hazard != candidate.hazard || !o.hasLocation) continue;
      final hoursApart = candidate.createdAt.difference(o.createdAt).inHours;
      if (hoursApart.abs() > 24) continue;
      final d = distanceMeters(
        candidate.latitude!,
        candidate.longitude!,
        o.latitude!,
        o.longitude!,
      );
      if (d <= radiusMeters) return o;
    }
    return null;
  }

  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }
}
