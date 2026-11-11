import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_provider.dart';

class ChangePasswordButton extends StatelessWidget {
  const ChangePasswordButton({super.key, required this.auth});
  final AuthProvider auth;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      key: const ValueKey('profile-password-change'),
      onPressed: auth.usesDemoData
          ? null
          : () => showDialog<void>(
              context: context, builder: (_) => _PasswordDialog(auth: auth)),
      icon: const Icon(Icons.password_rounded, size: 18),
      label: const Text('Change password'));
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.auth});
  final AuthProvider auth;
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirmation = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_form.currentState?.validate() != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.changePassword(_current.text, _next.text);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to change your password. Please try again.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('A password only you know.'),
          content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text(
                            'Use at least 12 characters. You’ll sign in again on each device with your new password.'),
                        const SizedBox(height: 20),
                        TextFormField(
                            controller: _current,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                                labelText: 'Current password'),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Enter your current password.'
                                : null),
                        const SizedBox(height: 14),
                        TextFormField(
                            controller: _next,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                                labelText: 'New password'),
                            validator: (v) {
                              if (v == null || v.runes.length < 12) {
                                return 'Use at least 12 characters.';
                              }
                              if (utf8.encode(v).length > 72) {
                                return 'Try a shorter password.';
                              }
                              if (v == _current.text) {
                                return 'Choose a different password.';
                              }
                              return null;
                            }),
                        const SizedBox(height: 14),
                        TextFormField(
                            controller: _confirmation,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) {
                              if (!_busy) _save();
                            },
                            decoration: const InputDecoration(
                                labelText: 'New password, once more'),
                            validator: (v) => v != _next.text
                                ? 'The passwords don’t match yet.'
                                : null),
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Semantics(
                                  liveRegion: true,
                                  child: Text(_error!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error)))),
                      ])))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Updating…' : 'Update password'))
          ]);
}
