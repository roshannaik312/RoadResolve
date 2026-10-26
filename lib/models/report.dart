import 'package:flutter/material.dart';

import 'hazard.dart';

enum ReportStatus {
  draft('Draft', Icons.edit_note_rounded, Color(0xFF92400E), Color(0xFFFEF3C7)),
  submitted(
    'Submitted',
    Icons.send_rounded,
    Color(0xFF334155),
    Color(0xFFE2E8F0),
  ),
  underReview(
    'Under review',
    Icons.fact_check_rounded,
    Color(0xFF1D4ED8),
    Color(0xFFDBEAFE),
  ),
  acknowledged(
    'Acknowledged',
    Icons.thumb_up_alt_rounded,
    Color(0xFF6D28D9),
    Color(0xFFEDE9FE),
  ),
  inProgress(
    'Crew on the way',
    Icons.local_shipping_rounded,
    Color(0xFFC2410C),
    Color(0xFFFFEDD5),
  ),
  resolved(
    'Resolved',
    Icons.check_circle_rounded,
    Color(0xFF047857),
    Color(0xFFD1FAE5),
  );

  const ReportStatus(this.label, this.icon, this.foreground, this.background);

  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;

  bool get isOpen => this != draft && this != resolved;

  ReportStatus? get next {
    final i = index + 1;
    return i < values.length ? values[i] : null;
  }

  static ReportStatus fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => draft);
}

enum ReportSource {
  voice('Voice'),
  siri('Siri'),
  tap('Quick tap'),
  manual('Manual'),
  sample('Sample');

  const ReportSource(this.label);
  final String label;

  static ReportSource fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => manual);
}

class TimelineEvent {
  const TimelineEvent({
    required this.title,
    required this.at,
    this.detail,
    this.actor = 'You',
  });

  final String title;
  final String? detail;
  final DateTime at;
  final String actor;

  Map<String, dynamic> toJson() => {
    'title': title,
    'detail': detail,
    'at': at.toIso8601String(),
    'actor': actor,
  };

  factory TimelineEvent.fromJson(Map<String, dynamic> j) => TimelineEvent(
    title: j['title'] as String,
    detail: j['detail'] as String?,
    at: DateTime.parse(j['at'] as String),
    actor: j['actor'] as String? ?? 'You',
  );
}

class Report {
  Report({
    required this.id,
    required this.hazard,
    required this.createdAt,
    this.blockage = Blockage.unknown,
    this.description = '',
    this.latitude,
    this.longitude,
    this.road,
    this.locality,
    this.status = ReportStatus.draft,
    this.source = ReportSource.manual,
    this.photoPath,
    this.submittedAt,
    this.reportedWhileDriving = false,
    this.ownerUid,
    DateTime? updatedAt,
    List<TimelineEvent>? timeline,
  }) : updatedAt = updatedAt ?? createdAt,
       timeline = timeline ?? [];

  final String id;
  HazardType hazard;
  Blockage blockage;
  String description;
  double? latitude;
  double? longitude;
  String? road;
  String? locality;
  ReportStatus status;
  final ReportSource source;
  String? photoPath;
  final DateTime createdAt;
  DateTime? submittedAt;
  final bool reportedWhileDriving;
  final List<TimelineEvent> timeline;

  /// Firebase uid of the account that made the report; null for samples and
  /// for drafts made before accounts existed.
  String? ownerUid;

  /// Last local change; the newer copy wins when syncing with Firestore.
  DateTime updatedAt;

  bool get isDraft => status == ReportStatus.draft;
  bool get isSample => source == ReportSource.sample;
  bool get hasLocation => latitude != null && longitude != null;

  String get placeLabel {
    if (road != null && road!.isNotEmpty) return road!;
    if (hasLocation) {
      return '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}';
    }
    return 'Locating…';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'hazard': hazard.id,
    'blockage': blockage.name,
    'description': description,
    'latitude': latitude,
    'longitude': longitude,
    'road': road,
    'locality': locality,
    'status': status.name,
    'source': source.name,
    'photoPath': photoPath,
    'createdAt': createdAt.toIso8601String(),
    'submittedAt': submittedAt?.toIso8601String(),
    'reportedWhileDriving': reportedWhileDriving,
    'ownerUid': ownerUid,
    'updatedAt': updatedAt.toIso8601String(),
    'timeline': timeline.map((e) => e.toJson()).toList(),
  };

  factory Report.fromJson(Map<String, dynamic> j) => Report(
    id: j['id'] as String,
    hazard: HazardType.fromId(j['hazard'] as String?) ?? HazardType.other,
    blockage: Blockage.fromName(j['blockage'] as String?),
    description: j['description'] as String? ?? '',
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    road: j['road'] as String?,
    locality: j['locality'] as String?,
    status: ReportStatus.fromName(j['status'] as String?),
    source: ReportSource.fromName(j['source'] as String?),
    photoPath: j['photoPath'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String),
    submittedAt: j['submittedAt'] == null
        ? null
        : DateTime.parse(j['submittedAt'] as String),
    reportedWhileDriving: j['reportedWhileDriving'] as bool? ?? false,
    ownerUid: j['ownerUid'] as String?,
    updatedAt: j['updatedAt'] == null
        ? null
        : DateTime.tryParse(j['updatedAt'] as String),
    timeline: (j['timeline'] as List<dynamic>? ?? [])
        .map((e) => TimelineEvent.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
