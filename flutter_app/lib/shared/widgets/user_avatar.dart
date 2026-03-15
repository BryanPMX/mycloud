import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/directory/providers/family_directory_provider.dart';

class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    required this.userId,
    required this.displayName,
    required this.directoryProvider,
    this.initialAvatarUrl,
    this.radius = 20,
  });

  final String userId;
  final String displayName;
  final FamilyDirectoryProvider directoryProvider;
  final String? initialAvatarUrl;
  final double radius;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  @override
  void initState() {
    super.initState();
    unawaited(_ensureAvatar());
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.initialAvatarUrl != widget.initialAvatarUrl) {
      unawaited(_ensureAvatar());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: widget.directoryProvider,
      builder: (context, _) {
        final avatarUrl = widget.directoryProvider.avatarUrlFor(widget.userId);
        if (widget.directoryProvider.avatarNeedsRefresh(widget.userId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              unawaited(_ensureAvatar());
            }
          });
        }

        return CircleAvatar(
          radius: widget.radius,
          backgroundColor: theme.colorScheme.primaryContainer,
          backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
          onBackgroundImageError: avatarUrl == null
              ? null
              : (_, __) {
                  unawaited(
                    widget.directoryProvider.handleAvatarLoadError(
                      widget.userId,
                    ),
                  );
                },
          child: avatarUrl == null
              ? Text(
                  _initialsFromName(widget.displayName),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                )
              : null,
        );
      },
    );
  }

  Future<void> _ensureAvatar() {
    return widget.directoryProvider.ensureAvatar(
      userId: widget.userId,
      initialAvatarUrl: widget.initialAvatarUrl,
    );
  }
}

String _initialsFromName(String displayName) {
  final parts = displayName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return '?';
  }
  if (parts.length == 1) {
    return parts.first.characters.take(1).toString().toUpperCase();
  }

  return '${parts.first.characters.take(1)}${parts.last.characters.take(1)}'
      .toUpperCase();
}
