import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../data/sample_reports.dart';
import '../models/hazard.dart';
import '../models/report.dart';
import '../services/driving_monitor.dart';
import '../services/report_store.dart';
import '../widgets/common.dart';
import '../widgets/hazard_pin.dart';
import 'report_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  HazardType? _filter;
  bool _openOnly = false;
  String? _selectedId;

  List<Report> _visible(ReportStore store) => store.all
      .where((r) => r.hasLocation)
      .where((r) => _filter == null || r.hazard == _filter)
      .where((r) => !_openOnly || r.status.isOpen || r.isDraft)
      .toList();

  void _focus(Report r) {
    setState(() => _selectedId = r.id);
    _map.move(LatLng(r.latitude!, r.longitude!), 15);
  }

  void _recenter(DrivingMonitor driving) {
    final p = driving.lastPosition;
    _map.move(
      p == null
          ? const LatLng(pilotCenterLat, pilotCenterLng)
          : LatLng(p.latitude, p.longitude),
      13.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ReportStore>();
    final driving = context.watch<DrivingMonitor>();
    final reports = _visible(store);
    final me = driving.lastPosition;
    final theme = Theme.of(context);
    Report? selected;
    for (final r in reports) {
      if (r.id == _selectedId) selected = r;
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: const LatLng(pilotCenterLat, pilotCenterLng),
            initialZoom: 12.5,
            onTap: (_, _) => setState(() => _selectedId = null),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.clearroads.clear_roads',
            ),
            if (me != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(me.latitude, me.longitude),
                    width: 26,
                    height: 26,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final r in reports)
                  Marker(
                    point: LatLng(r.latitude!, r.longitude!),
                    width: 44,
                    height: 44,
                    child: GestureDetector(
                      onTap: () => _focus(r),
                      child: Opacity(
                        opacity: r.status == ReportStatus.resolved ? 0.55 : 1,
                        child: HazardMapPin(
                          hazard: r.hazard,
                          selected: r.id == _selectedId,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        // Filters
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _FilterChip(
                  label: 'Open only',
                  icon: Icons.filter_alt_rounded,
                  selected: _openOnly,
                  onTap: () => setState(() => _openOnly = !_openOnly),
                ),
                _FilterChip(
                  label: 'All hazards',
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                for (final h in HazardType.values)
                  _FilterChip(
                    label: h.label,
                    icon: h.icon,
                    color: h.color,
                    selected: _filter == h,
                    onTap: () =>
                        setState(() => _filter = _filter == h ? null : h),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 14,
          bottom: selected != null ? 196 : 110,
          child: FloatingActionButton.small(
            heroTag: 'recenter',
            tooltip: 'Recenter',
            onPressed: () => _recenter(driving),
            child: const Icon(Icons.my_location_rounded),
          ),
        ),
        // Selected report preview, or count summary.
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: selected != null
                ? ReportCard(
                    key: ValueKey(selected.id),
                    report: selected,
                    onTap: () => ReportDetailScreen.open(context, selected!),
                  )
                : Card(
                    key: const ValueKey('summary'),
                    child: ListTile(
                      leading: Icon(
                        Icons.layers_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        '${reports.length} reports on the map',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Tap a pin for details · sample data is labelled',
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        showCheckmark: false,
        avatar: icon == null
            ? null
            : Icon(icon, size: 18, color: selected ? scheme.onPrimary : color),
        label: Text(label),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? scheme.onPrimary : scheme.onSurface,
        ),
        selectedColor: scheme.primary,
        backgroundColor: Theme.of(context).cardTheme.color,
        elevation: 2,
        shadowColor: Colors.black26,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
