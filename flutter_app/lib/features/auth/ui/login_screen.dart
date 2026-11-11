import 'package:flutter/material.dart';
import '../../../shared/widgets/vault_ui.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../providers/auth_provider.dart';
import 'accept_invite_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.invitationToken,
    required this.authProvider,
    required this.apiClient,
    required this.config,
  });

  final String? invitationToken;
  final AuthProvider authProvider;
  final ApiClient apiClient;
  final AppConfig config;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _showPassword = false;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(
      text: widget.config.useDemoData ? 'member@mynube.live' : '',
    );
    if (widget.invitationToken != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showAcceptInviteDialog(context, widget.authProvider,
              initialToken: widget.invitationToken);
        }
      });
    }
    _passwordController = TextEditingController(
      text: widget.config.useDemoData ? 'demo-password' : '',
    );
  }

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.invitationToken != null &&
        oldWidget.invitationToken != widget.invitationToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showAcceptInviteDialog(context, widget.authProvider,
              initialToken: widget.invitationToken);
        }
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    widget.authProvider.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text);
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AutofillGroup(
        child: Form(
            key: _formKey,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const VaultEyebrow('Your personal vault'),
                  const SizedBox(height: 12),
                  Text('Welcome home.', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 10),
                  Text('A little space for everything that matters.',
                      style: TextStyle(
                          color: colors.onSurfaceVariant, height: 1.6)),
                  const SizedBox(height: 32),
                  TextFormField(
                      key: const ValueKey<String>('login-email'),
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email
                      ],
                      autocorrect: false,
                      validator: (value) =>
                          value == null || !value.contains('@')
                              ? 'Enter your email address.'
                              : null,
                      decoration: const InputDecoration(
                          labelText: 'Email address',
                          hintText: 'you@example.com')),
                  const SizedBox(height: 16),
                  TextFormField(
                      key: const ValueKey<String>('login-password'),
                      controller: _passwordController,
                      obscureText: !_showPassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Enter your password.'
                          : null,
                      decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                              tooltip: _showPassword
                                  ? 'Hide password'
                                  : 'Show password',
                              onPressed: () => setState(
                                  () => _showPassword = !_showPassword),
                              icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 20)))),
                  if (widget.authProvider.errorMessage != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                            liveRegion: true,
                            child: Text(widget.authProvider.errorMessage!,
                                style: TextStyle(color: colors.error)))),
                  const SizedBox(height: 24),
                  FilledButton(
                      key: const ValueKey<String>('login-submit'),
                      onPressed: widget.authProvider.isBusy ? null : _submit,
                      child: widget.authProvider.isBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                  Text('Sign in'),
                                  SizedBox(width: 12),
                                  Icon(Icons.arrow_forward_rounded, size: 18)
                                ])),
                  const SizedBox(height: 20),
                  Center(
                      child: TextButton(
                          onPressed: widget.authProvider.isBusy
                              ? null
                              : () => showAcceptInviteDialog(
                                  context, widget.authProvider),
                          child: const Text(
                              'Have an invitation? Join your space',
                              style: TextStyle(fontSize: 12)))),
                  if (widget.config.useDemoData) ...[
                    const Divider(height: 32),
                    const Center(child: VaultEyebrow('Explore a sample vault')),
                    const SizedBox(height: 12),
                    Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton(
                              onPressed: widget.authProvider.isBusy
                                  ? null
                                  : widget.authProvider.signInAsDemoMember,
                              child: const Text('Use demo member')),
                          TextButton(
                              onPressed: widget.authProvider.isBusy
                                  ? null
                                  : widget.authProvider.signInAsDemoAdmin,
                              child: const Text('Use demo admin'))
                        ])
                  ],
                  const SizedBox(height: 32),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 13, color: colors.secondary),
                    const SizedBox(width: 7),
                    Flexible(
                        child: Text('Only you decide what gets shared.',
                            style: TextStyle(
                                fontSize: 10, color: colors.onSurfaceVariant)))
                  ]),
                ])));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.authProvider,
      builder: (context, _) {
        final theme = Theme.of(context);
        return Scaffold(body:
            SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 900;
          if (desktop) {
            return Row(children: [
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(52, 32, 40, 28),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const VaultLogo(),
                            const Spacer(),
                            VaultEnter(
                                child: Text('Your life.\nIn your keeping.',
                                    style: TextStyle(
                                        fontFamily: 'DMSerifDisplay',
                                        fontSize: constraints.maxWidth > 1250
                                            ? 62
                                            : 48,
                                        height: 1.06,
                                        letterSpacing: -1.6,
                                        color: theme.colorScheme.onSurface))),
                            const SizedBox(height: 18),
                            ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 380),
                                child: Text(
                                    'The big adventures. The everyday magic. A private home for all of it.',
                                    style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        height: 1.7))),
                            const SizedBox(height: 28),
                            const Flexible(flex: 6, child: _WelcomeMosaic()),
                            const Spacer(),
                            Row(children: [
                              const VaultEyebrow(
                                  'Made for memories. Kept by you.'),
                              const Spacer(),
                              Icon(Icons.favorite_border_rounded,
                                  size: 15, color: theme.colorScheme.primary)
                            ]),
                          ]))),
              Container(
                  width: constraints.maxWidth > 1250 ? 500 : 430,
                  height: double.infinity,
                  decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(
                          left: BorderSide(
                              color: theme.colorScheme.outlineVariant))),
                  child: Center(
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 52, vertical: 40),
                          child: VaultEnter(child: _form(context))))),
            ]);
          }
          return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const VaultLogo(),
                            const SizedBox(height: 28),
                            const SizedBox(
                                height: 190, child: _WelcomeMosaic()),
                            const SizedBox(height: 32),
                            VaultEnter(child: _form(context))
                          ]))));
        })));
      });
}

class _WelcomeMosaic extends StatelessWidget {
  const _WelcomeMosaic();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, constraints) => ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
                flex: 6,
                child: Stack(fit: StackFit.expand, children: [
                  const VaultImage(url: 'asset:assets/demo/memory-5.jpg'),
                  const DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                        Colors.transparent,
                        Color(0x55000000)
                      ]))),
                  Positioned(
                      left: 18,
                      bottom: 18,
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .92),
                              borderRadius: BorderRadius.circular(30)),
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline_rounded,
                                    size: 12, color: Color(0xFF252923)),
                                SizedBox(width: 6),
                                Text('A world of your own',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF252923)))
                              ]))),
                ])),
            const SizedBox(width: 8),
            const Expanded(
                flex: 4,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                          child: VaultImage(
                              url: 'asset:assets/demo/memory-4.jpg')),
                      SizedBox(height: 8),
                      Expanded(
                          child:
                              VaultImage(url: 'asset:assets/demo/memory-2.jpg'))
                    ])),
          ])));
}
