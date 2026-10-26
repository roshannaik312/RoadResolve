import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/driving_detector.dart';
import '../services/driving_monitor.dart';
import '../services/report_store.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final driving = context.watch<DrivingMonitor>();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const SectionHeader('Account'),
        const _AccountCard(),
        const SizedBox(height: 8),
        const SectionHeader('Siri & Shortcuts'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No setup needed — these phrases work as soon as the app is installed. '
                  'Siri asks what you saw, opens Clear Roads and saves a draft at your location.',
                ),
                const SizedBox(height: 12),
                for (final phrase in const [
                  'Hey Siri, report a hazard in Clear Roads',
                  'Hey Siri, report a fallen tree in Clear Roads',
                  'Hey Siri, report a dead animal with Clear Roads',
                  'Hey Siri, report snow or ice in Clear Roads',
                  'Hey Siri, show my Clear Roads drafts',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.mic_rounded,
                            size: 18,
                            color: Color(0xFF7C3AED),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '“$phrase”',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Text(
                  'Tip: add “Report Hazard” to your Action button or CarPlay Siri suggestions '
                  'from the Shortcuts app.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const SectionHeader('Driving detection'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const DrivingStatusPill(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        driving.sourceLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Clear Roads combines GPS speed with the iPhone motion sensor. '
                  'Submitting unlocks after the car has been still for 45 seconds, '
                  'or as soon as you start walking — so a red light never unlocks it.',
                ),
                if (driving.locationDenied) ...[
                  const SizedBox(height: 12),
                  SafetyBanner(
                    icon: Icons.location_off_rounded,
                    text:
                        'Location is off. Turn it on in Settings so reports are tagged and driving can be detected.',
                    trailing: TextButton(
                      onPressed: driving.retryLocation,
                      child: const Text('Retry'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text('Demo override', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  'For demos without a moving car.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<DrivingOverride>(
                    segments: const [
                      ButtonSegment(
                        value: DrivingOverride.auto,
                        icon: Icon(Icons.sensors_rounded),
                        label: Text('Auto'),
                      ),
                      ButtonSegment(
                        value: DrivingOverride.forceDriving,
                        icon: Icon(Icons.directions_car_rounded),
                        label: Text('Driving'),
                      ),
                      ButtonSegment(
                        value: DrivingOverride.forceStopped,
                        icon: Icon(Icons.local_parking_rounded),
                        label: Text('Stopped'),
                      ),
                    ],
                    selected: {settings.drivingOverride},
                    onSelectionChanged: (s) =>
                        settings.setDrivingOverride(s.first),
                  ),
                ),
                if (driving.state == DrivingState.unknown &&
                    settings.drivingOverride == DrivingOverride.auto) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Waiting for a GPS fix…',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const SectionHeader('Preferences'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.record_voice_over_rounded),
                title: const Text('Spoken prompts'),
                subtitle: const Text(
                  'Ask questions out loud and listen for answers',
                ),
                value: settings.voicePrompts,
                onChanged: settings.setVoicePrompts,
              ),
              const Divider(indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    const Icon(Icons.dark_mode_rounded),
                    const SizedBox(width: 16),
                    const Expanded(child: Text('Appearance')),
                    SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('Auto'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (s) => settings.setThemeMode(s.first),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const SectionHeader('Report website'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.map_rounded),
                title: const Text('Show my reports on the public map'),
                subtitle: const Text(
                  'Submitted reports appear on the website\u2019s incident '
                  'map with their location and description. Your name, '
                  'email and photos are never shared.',
                ),
                value: settings.shareOnMap,
                onChanged: settings.setShareOnMap,
              ),
              const Divider(indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.public_rounded),
                title: const Text('DOT contact site'),
                subtitle: Text(settings.portalUrl),
                trailing: const Icon(Icons.edit_rounded),
                onTap: () => _editPortalUrl(context, settings),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const SectionHeader('Demo data'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.restart_alt_rounded),
            title: const Text('Reset demo'),
            subtitle: const Text(
              'Remove your reports and restore the sample data',
            ),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Reset demo data?'),
                  content: const Text(
                    'Your drafts and reports on this device will be removed.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await context.read<ReportStore>().resetDemo();
              }
            },
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Clear Roads prototype. Classification, priority scoring, jurisdiction routing '
          'and crew recommendations are deterministic simulations; reports are stored on '
          'this device and are not sent to any agency.\n\n'
          'Emergency? Call 911. Never handle your phone while driving.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

Future<void> _editPortalUrl(
  BuildContext context,
  SettingsStore settings,
) async {
  final ctrl = TextEditingController(text: settings.portalUrl);
  final url = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Report website address'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Drafts open this site pre-filled for you to submit. On a phone, '
            'use the hosted site or your computer\u2019s network address, e.g. http://192.168.1.13:8080',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Address'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(c, ctrl.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (url == null) return;
  final uri = Uri.tryParse(url.trim());
  if (url.trim().isNotEmpty &&
      (uri == null || !uri.hasScheme || uri.host.isEmpty)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a full address starting with http://'),
        ),
      );
    }
    return;
  }
  settings.setPortalUrl(url);
}

class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final ids = auth.providers;
    final method = ids.contains('apple.com')
        ? 'Apple'
        : ids.contains('google.com')
        ? 'Google'
        : 'Email';
    final unverified =
        user != null && ids.contains('password') && !user.emailVerified;
    final initial = auth.displayLabel.isEmpty
        ? '?'
        : auth.displayLabel.characters.first.toUpperCase();

    return Card(
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.14,
              ),
              foregroundImage: user?.photoURL == null
                  ? null
                  : NetworkImage(user!.photoURL!),
              child: Text(
                initial,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            title: Text(
              auth.displayLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              [
                if (user?.email != null && user!.email != auth.displayLabel)
                  user.email!,
                'Signed in with $method',
              ].join('\n'),
              style: TextStyle(color: muted),
            ),
          ),
          if (unverified)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SafetyBanner(
                icon: Icons.mark_email_unread_rounded,
                text: 'Verify your email: check your inbox for a link.',
                trailing: TextButton(
                  onPressed: () => _resend(context),
                  child: const Text('Resend'),
                ),
              ),
            ),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Sign out'),
            onTap: () => _signOut(context),
          ),
          ListTile(
            leading: const Icon(
              Icons.delete_forever_rounded,
              color: AppColors.danger,
            ),
            title: const Text(
              'Delete account',
              style: TextStyle(color: AppColors.danger),
            ),
            onTap: () => _delete(context, needsPassword: method == 'Email'),
          ),
        ],
      ),
    );
  }

  Future<void> _resend(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AuthService>().resendVerificationEmail();
      messenger.showSnackBar(
        const SnackBar(content: Text('Verification email sent.')),
      );
    } on AuthFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your drafts stay on this device and will be here when you sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AuthService>().signOut();
    }
  }

  Future<void> _delete(
    BuildContext context, {
    required bool needsPassword,
  }) async {
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              needsPassword
                  ? 'This permanently deletes your Clear Roads account. '
                        'Enter your password to confirm.'
                  : 'This permanently deletes your Clear Roads account. '
                        'You’ll be asked to confirm with your sign-in provider.',
            ),
            if (needsPassword) ...[
              const SizedBox(height: 16),
              TextField(
                controller: password,
                obscureText: true,
                autofocus: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Password'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: AppColors.danger,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    final pw = password.text;
    password.dispose();
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AuthService>().deleteAccount(password: pw);
    } on AuthFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
