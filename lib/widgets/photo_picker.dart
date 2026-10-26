import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/report.dart';
import '../services/report_store.dart';

/// Takes or picks a photo and attaches it to [report]'s draft.
Future<void> attachPhoto(
  BuildContext context,
  Report report,
  ImageSource source,
) async {
  final store = context.read<ReportStore>();
  try {
    final x = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (x == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dest =
        '${dir.path}/report_${report.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(x.path).copy(dest);
    report.photoPath = dest;
    await store.update(report);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not attach the photo.')),
      );
    }
  }
}

/// Bottom sheet: take a photo or choose one from the library.
void choosePhotoSource(BuildContext context, Report report) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded),
            title: const Text('Take photo'),
            onTap: () {
              Navigator.pop(c);
              attachPhoto(context, report, ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('Choose from library'),
            onTap: () {
              Navigator.pop(c);
              attachPhoto(context, report, ImageSource.gallery);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
