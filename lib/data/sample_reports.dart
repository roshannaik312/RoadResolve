import '../models/hazard.dart';
import '../models/report.dart';

/// Pilot area used for the demo map and sample data (Saratoga County, NY).
const pilotCenterLat = 43.0831;
const pilotCenterLng = -73.7846;

/// Clearly-labelled sample reports so the map and dashboard aren't empty.
List<Report> buildSampleReports(DateTime now) {
  Report sample(
    String id,
    HazardType h,
    Blockage b,
    String desc,
    String road,
    double lat,
    double lng,
    Duration ago,
    ReportStatus status,
  ) {
    final created = now.subtract(ago);
    final timeline = <TimelineEvent>[
      TimelineEvent(
        title: 'Submitted',
        detail: 'Sample report',
        at: created,
        actor: 'Resident',
      ),
    ];
    var s = ReportStatus.submitted;
    var t = created;
    while (s != status && s.next != null) {
      s = s.next!;
      t = t.add(Duration(minutes: 20 + s.index * 7));
      timeline.add(TimelineEvent(title: s.label, at: t, actor: 'Demo agency'));
    }
    return Report(
      id: id,
      hazard: h,
      blockage: b,
      description: desc,
      road: road,
      locality: 'Saratoga Springs',
      latitude: lat,
      longitude: lng,
      createdAt: created,
      submittedAt: created,
      status: status,
      source: ReportSource.sample,
      timeline: timeline,
    );
  }

  return [
    sample(
      'seed-1',
      HazardType.deadAnimal,
      Blockage.partialLane,
      'Dead deer partially in the northbound lane, cars swerving around it.',
      'NY-50',
      43.0962,
      -73.7712,
      const Duration(minutes: 40),
      ReportStatus.underReview,
    ),
    sample(
      'seed-2',
      HazardType.fallenTree,
      Blockage.allLanes,
      'Large tree down across both lanes after the storm. Wires look tangled.',
      'Lake Avenue',
      43.0858,
      -73.7738,
      const Duration(hours: 2),
      ReportStatus.inProgress,
    ),
    sample(
      'seed-3',
      HazardType.snowIce,
      Blockage.allLanes,
      'Road not plowed, about 4 inches of snow on the school bus route.',
      'County Route 9P',
      43.0612,
      -73.7470,
      const Duration(hours: 3),
      ReportStatus.acknowledged,
    ),
    sample(
      'seed-4',
      HazardType.fallenTree,
      Blockage.shoulder,
      'Branch leaning over the shoulder.',
      'Union Avenue',
      43.0779,
      -73.7653,
      const Duration(hours: 6),
      ReportStatus.submitted,
    ),
    sample(
      'seed-5',
      HazardType.deadAnimal,
      Blockage.shoulder,
      'Raccoon on the shoulder near the creek bridge.',
      'Crescent Avenue',
      43.0718,
      -73.7605,
      const Duration(hours: 9),
      ReportStatus.resolved,
    ),
    sample(
      'seed-6',
      HazardType.snowIce,
      Blockage.fullLane,
      'Black ice on the curve, a car slid off earlier.',
      'Church Street',
      43.0849,
      -73.8010,
      const Duration(hours: 12),
      ReportStatus.inProgress,
    ),
    sample(
      'seed-7',
      HazardType.pothole,
      Blockage.partialLane,
      'Deep pothole near the intersection, damaging tires.',
      'Broadway',
      43.0804,
      -73.7861,
      const Duration(days: 1),
      ReportStatus.acknowledged,
    ),
    sample(
      'seed-8',
      HazardType.debris,
      Blockage.fullLane,
      'Ladder in the right lane.',
      'I-87',
      43.1101,
      -73.7372,
      const Duration(days: 2),
      ReportStatus.resolved,
    ),
  ];
}
