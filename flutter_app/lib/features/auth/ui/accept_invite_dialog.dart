import 'package:flutter/material.dart';
import '../../../core/network/api_exception.dart';
import '../providers/auth_provider.dart';

Future<void> showAcceptInviteDialog(BuildContext context, AuthProvider auth,
    {String? initialToken}) async {
  final token = TextEditingController(text: initialToken ?? '');
  final name = TextEditingController();
  final password = TextEditingController();
  final repeat = TextEditingController();
  String? error;
  bool busy = false;
  await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: const Text('Welcome to Mynube'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Use your private account invitation to choose your name and password.'),
                  TextField(
                      controller: token,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration:
                          const InputDecoration(labelText: 'Invitation code')),
                  TextField(
                      controller: name,
                      autofillHints: const [AutofillHints.nickname],
                      maxLength: 100,
                      decoration:
                          const InputDecoration(labelText: 'Your name')),
                  TextField(
                      controller: password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: const InputDecoration(
                          labelText: 'Password (at least 8 characters)')),
                  TextField(
                      controller: repeat,
                      obscureText: true,
                      decoration:
                          const InputDecoration(labelText: 'Repeat password')),
                  if (error != null)
                    Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                ])),
                actions: [
                  TextButton(
                      onPressed:
                          busy ? null : () => Navigator.pop(dialogContext),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (password.text != repeat.text ||
                                  password.text.length < 8 ||
                                  name.text.trim().isEmpty) {
                                setState(() {
                                  error =
                                      'Enter your name and matching passwords of at least 8 characters.';
                                });
                                return;
                              }
                              setState(() {
                                busy = true;
                                error = null;
                              });
                              try {
                                await auth.acceptInvitation(token.text.trim(),
                                    name.text.trim(), password.text);
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                              } on ApiException catch (e) {
                                if (dialogContext.mounted) {
                                  setState(() {
                                    busy = false;
                                    error = e.message;
                                  });
                                }
                              } catch (_) {
                                if (dialogContext.mounted) {
                                  setState(() {
                                    busy = false;
                                    error =
                                        'Unable to accept this invitation. Please try again.';
                                  });
                                }
                              }
                            },
                      child: Text(busy
                          ? 'Creating your account…'
                          : 'Create my account'))
                ],
              )));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    token.dispose();
    name.dispose();
    password.dispose();
    repeat.dispose();
  });
}
