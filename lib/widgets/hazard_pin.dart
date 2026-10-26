import 'package:flutter/material.dart';

import '../models/hazard.dart';

class HazardMapPin extends StatelessWidget {
  const HazardMapPin({super.key, required this.hazard, this.selected = false});
  final HazardType hazard;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1.25 : 1,
      duration: const Duration(milliseconds: 200),
      child: Container(
        decoration: BoxDecoration(
          color: hazard.color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(hazard.icon, color: Colors.white, size: 20),
      ),
    );
  }
}
