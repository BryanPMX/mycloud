import 'package:flutter/material.dart';

import '../../../shared/utils/date_formatter.dart';
import '../../../shared/utils/file_size_formatter.dart';
import '../providers/profile_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.profileProvider});

  final ProfileProvider profileProvider;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: profileProvider,
      builder: (context, _) {
        final theme = Theme.of(context);
        final user = profileProvider.currentUser;

        if (user == null) {
          return const SizedBox.shrink();
        }

        return SingleChildScrollView(
          key: const ValueKey<String>('profile-screen'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  SizedBox(
                    width: 360,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Account snapshot',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            _ProfileRow(label: 'Email', value: user.email),
                            _ProfileRow(label: 'Role', value: user.role.label),
                            _ProfileRow(
                              label: 'Joined',
                              value: DateFormatter.mediumDate(user.createdAt),
                            ),
                            _ProfileRow(
                              label: 'Last login',
                              value: user.lastLoginAt == null
                                  ? 'Unavailable'
                                  : DateFormatter.mediumDateTime(
                                      user.lastLoginAt!,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 420,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Storage posture',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            LinearProgressIndicator(
                              value: user.storagePct.clamp(0, 1),
                              minHeight: 14,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${FileSizeFormatter.compact(user.storageUsed)} of ${FileSizeFormatter.compact(user.quotaBytes)} used',
                              style: theme.textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${(user.storagePct * 100).toStringAsFixed(1)}% of quota currently allocated.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recommended next Flutter slices',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      ...profileProvider.rolloutSteps.map(
                        (step) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                step.done
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: step.done
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      step.title,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      step.description,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deployment endpoints',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      ...profileProvider.endpoints.map(
                        (endpoint) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ProfileRow(
                            label: endpoint.label,
                            value: endpoint.uri.toString(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
