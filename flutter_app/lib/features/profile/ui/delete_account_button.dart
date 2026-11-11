import 'package:flutter/material.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_provider.dart';

class DeleteAccountButton extends StatelessWidget {
  const DeleteAccountButton({super.key, required this.auth});
  final AuthProvider auth;
  Future<void> _delete(BuildContext context) async {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    bool busy = false;
    String? error;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                  title: const Text('Delete your account?'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        'This permanently removes your account, posts, photos, and videos from Mynube. Download anything you want to keep first. Independent backups expire according to the backup retention policy. Family owners must remove other members first, and another account administrator must remain.'),
                    const SizedBox(height: 16),
                    TextField(
                        controller: password,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                            labelText: 'Current password')),
                    TextField(
                        controller: confirmation,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                            labelText: 'Type DELETE to confirm')),
                    if (error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                  ])),
                  actions: [
                    TextButton(
                        onPressed:
                            busy ? null : () => Navigator.pop(dialogContext),
                        child: const Text('Keep my account')),
                    FilledButton(
                        onPressed: busy || confirmation.text != 'DELETE'
                            ? null
                            : () async {
                                setState(() {
                                  busy = true;
                                  error = null;
                                });
                                try {
                                  await auth.deleteAccount(password.text);
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                } on ApiException catch (e) {
                                  if (dialogContext.mounted) {
                                    setState(() {
                                      busy = false;
                                      error = e.code == 'CONFLICT'
                                          ? 'Remove other members from families you own and ensure another account administrator is active before deleting your account.'
                                          : e.message;
                                    });
                                  }
                                } catch (_) {
                                  if (dialogContext.mounted) {
                                    setState(() {
                                      busy = false;
                                      error =
                                          'Unable to delete your account. Please try again.';
                                    });
                                  }
                                }
                              },
                        child: Text(busy ? 'Deleting…' : 'Permanently delete'))
                  ],
                )));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      password.dispose();
      confirmation.dispose();
    });
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: () => _delete(context),
      icon: const Icon(Icons.delete_forever_outlined),
      label: const Text('Delete my account'));
}
