import 'package:flutter/material.dart';
import '../domain/backup_preferences.dart';
import '../domain/photo_library.dart';
import '../providers/device_backup_provider.dart';

class BackupSettingsCard extends StatelessWidget {
  const BackupSettingsCard({super.key, required this.provider});
  final DeviceBackupProvider provider;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: provider,
      builder: (context, _) => Card(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.backup_outlined),
                      const SizedBox(height: 12),
                      Text('Backup on this device',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                          provider.supported
                              ? 'Your choice. Your albums. Private copies in your vault. Backup is off until you choose what to include.'
                              : 'Automatic photo backup is available in the mobile app. On the website, choose files in Add memories and keep the tab open.',
                          textAlign: TextAlign.center),
                      if (provider.supported) ...[
                        const SizedBox(height: 12),
                        Text(
                            provider.preferences.enabled
                                ? 'Backup on • ${provider.preferences.wifiOnly ? 'Wi-Fi only' : 'Wi-Fi and mobile data'}'
                                : 'Backup off',
                            textAlign: TextAlign.center),
                        if (provider.message != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(provider.message!,
                                  textAlign: TextAlign.center)),
                        if (provider.busy) const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                  onPressed: provider.busy
                                      ? null
                                      : () => _configure(context),
                                  child: const Text('Choose backup albums')),
                              if (provider.preferences.enabled)
                                TextButton(
                                    onPressed: () => provider.update(provider
                                        .preferences
                                        .copyWith(enabled: false)),
                                    child: const Text('Turn off backup')),
                              if (provider.preferences.enabled)
                                TextButton(
                                    onPressed:
                                        provider.busy ? null : provider.scan,
                                    child:
                                        const Text('Check for new memories')),
                            ]),
                        const SizedBox(height: 12),
                        const Text(
                            'Checks run while Mynube is open and when you return. Queued transfers may continue when your phone allows. Reopen Mynube to resume or finish. Live Photos are not backed up automatically yet.',
                            textAlign: TextAlign.center),
                      ],
                      const SizedBox(height: 12),
                      const Text(
                          'Device albums are separate from Collections. Turning backup off or deleting a phone photo never deletes a vault copy.',
                          textAlign: TextAlign.center),
                    ])),
          ));
  Future<void> _configure(BuildContext context) async {
    await provider.chooseAccess();
    if (!context.mounted || provider.access == PhotoAccess.denied) return;
    var draft = provider.preferences.copyWith(
        albumIds: provider.preferences.albumIds
            .intersection(provider.albums.map((a) => a.id).toSet()));
    final result = await showDialog<BackupPreferences>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                  title: const Text('Choose your backup'),
                  content: SizedBox(
                      width: 520,
                      child: SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            Text(provider.access == PhotoAccess.limited
                                ? 'Only photos and videos you allow are visible to Mynube. Your device may not expose album names with limited access.'
                                : 'Select device albums to copy into your private vault. Existing copies stay safe if you change this selection.'),
                            const SizedBox(height: 12),
                            for (final album in provider.albums)
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(album.name),
                                  value: draft.albumIds.contains(album.id),
                                  onChanged: (value) => setState(() {
                                        final selected =
                                            Set<String>.of(draft.albumIds);
                                        if (value == true) {
                                          selected.add(album.id);
                                        } else {
                                          selected.remove(album.id);
                                        }
                                        draft =
                                            draft.copyWith(albumIds: selected);
                                      })),
                            if (provider.albums.isEmpty)
                              const Text(
                                  'No accessible albums. Review Photos access and try again.'),
                            const Divider(),
                            SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Automatic backup'),
                                value: draft.enabled,
                                onChanged: (value) => setState(() =>
                                    draft = draft.copyWith(enabled: value))),
                            CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                    'Include existing photos and videos'),
                                subtitle: const Text(
                                    'Off: only items captured after backup was first enabled. Existing items use your vault quota too.'),
                                value: draft.includeExisting,
                                onChanged: (v) => setState(() => draft =
                                    draft.copyWith(includeExisting: v))),
                            SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Include videos'),
                                value: draft.includeVideos,
                                onChanged: (v) => setState(() =>
                                    draft = draft.copyWith(includeVideos: v))),
                            SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Wi-Fi only'),
                                value: draft.wifiOnly,
                                subtitle: const Text(
                                    'Turn off to also use mobile data. Your carrier’s data charges may apply.'),
                                onChanged: (v) => setState(
                                    () => draft = draft.copyWith(wifiOnly: v))),
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, draft),
                        child: const Text('Save backup choices'))
                  ],
                )));
    if (result != null) await provider.update(result);
  }
}
