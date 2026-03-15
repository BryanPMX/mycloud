import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authProvider,
    required this.apiClient,
    required this.config,
  });

  final AuthProvider authProvider;
  final ApiClient apiClient;
  final AppConfig config;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(
      text: widget.config.useDemoData ? 'member@mynube.live' : '',
    );
    _passwordController = TextEditingController(
      text: widget.config.useDemoData ? 'demo-password' : '',
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: widget.authProvider,
      builder: (context, _) {
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.25),
                  theme.scaffoldBackgroundColor,
                  theme.colorScheme.secondary.withValues(alpha: 0.22),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Wrap(
                      spacing: 24,
                      runSpacing: 24,
                      alignment: WrapAlignment.center,
                      children: [
                        SizedBox(
                          width: 420,
                          child: _IntroPanel(config: widget.config),
                        ),
                        SizedBox(
                          width: 420,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sign in to ${widget.config.appName}',
                                    style: theme.textTheme.headlineMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.config.useDemoData
                                        ? 'Demo mode keeps the seeded app shell available for smoke tests and offline UI work.'
                                        : 'This client now targets the live auth endpoints and restores browser sessions before showing protected routes.',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  TextField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                      prefixIcon: Icon(
                                        Icons.mail_outline_rounded,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _passwordController,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Password',
                                      prefixIcon: Icon(
                                        Icons.lock_outline_rounded,
                                      ),
                                    ),
                                  ),
                                  if (widget.authProvider.errorMessage !=
                                      null) ...[
                                    const SizedBox(height: 16),
                                    Text(
                                      widget.authProvider.errorMessage!,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 20),
                                  FilledButton.icon(
                                    onPressed: widget.authProvider.isBusy
                                        ? null
                                        : () {
                                            widget.authProvider.signIn(
                                              email: _emailController.text,
                                              password:
                                                  _passwordController.text,
                                            );
                                          },
                                    icon: widget.authProvider.isBusy
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.login_rounded),
                                    label: const Text('Enter workspace'),
                                  ),
                                  if (widget.config.useDemoData) ...[
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      children: [
                                        OutlinedButton(
                                          onPressed: widget.authProvider.isBusy
                                              ? null
                                              : () {
                                                  widget.authProvider
                                                      .signInAsDemoMember();
                                                },
                                          child: const Text('Use demo member'),
                                        ),
                                        OutlinedButton(
                                          onPressed: widget.authProvider.isBusy
                                              ? null
                                              : () {
                                                  widget.authProvider
                                                      .signInAsDemoAdmin();
                                                },
                                          child: const Text('Use demo admin'),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 20),
                                  const Divider(),
                                  const SizedBox(height: 12),
                                  _EndpointRow(
                                    label: 'Login endpoint',
                                    value:
                                        widget.apiClient.loginUri().toString(),
                                  ),
                                  const SizedBox(height: 8),
                                  _EndpointRow(
                                    label: 'Restore session',
                                    value: widget.apiClient
                                        .currentUserUri()
                                        .toString(),
                                  ),
                                  const SizedBox(height: 8),
                                  _EndpointRow(
                                    label: 'Progress socket',
                                    value:
                                        widget.config.websocketUri.toString(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IntroPanel extends StatelessWidget {
  const _IntroPanel({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Chip(
              avatar: const Icon(Icons.construction_rounded, size: 18),
              label: Text('${config.environmentLabel} foundation slice'),
            ),
            const SizedBox(height: 20),
            Text(
              'A route-aware Flutter shell for the live backend.',
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: 16),
            Text(
              config.useDemoData
                  ? 'Demo mode mirrors the live contracts while keeping the app deterministic for local walkthroughs and tests.'
                  : 'Recent repository logs show the backend is ready for client auth, media reads, albums, comments, admin stats, uploads, and worker progress. This client now exercises those live reads plus the browser multipart upload path.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            const _CheckItem(
              title: 'Router-backed web shell',
              detail:
                  'Address-bar sync is ready for media, albums, profile, and admin sections.',
            ),
            const _CheckItem(
              title: 'Adaptive navigation',
              detail:
                  'The UI switches between NavigationBar and NavigationRail based on available width.',
            ),
            const _CheckItem(
              title: 'Latest delivery',
              detail:
                  'Browser multipart uploads and worker progress are now wired; the next step is finishing profile, album, comment, and admin write flows.',
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  const _CheckItem({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(value),
      ],
    );
  }
}
