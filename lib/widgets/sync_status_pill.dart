import 'package:flutter/material.dart';

/// Connection and synchronization state with the remote SSH laptop repository.
enum SyncState {
  /// Laptop is reachable or last sync succeeded.
  connected,

  /// Laptop host is unreachable or network is disconnected.
  offline,

  /// A sync transaction is actively executing.
  syncing,

  /// One or more notes are in conflict state.
  conflict,
}

/// An animated status pill widget displaying the current [SyncState].
class SyncStatusPill extends StatelessWidget {
  /// Creates a [SyncStatusPill].
  const SyncStatusPill({
    super.key,
    required this.state,
    this.onTap,
  });

  /// The active synchronization state.
  final SyncState state;

  /// Optional callback invoked when the pill is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (
      Color backgroundColor,
      Color borderColor,
      Color foregroundColor,
      String label,
    ) = switch (state) {
      SyncState.connected => isDark
          ? (
              const Color(0xFF14381C),
              const Color(0xFF2E7D32),
              const Color(0xFF81C784),
              'Connected',
            )
          : (
              const Color(0xFFE8F5E9),
              const Color(0xFFA5D6A7),
              const Color(0xFF1B5E20),
              'Connected',
            ),
      SyncState.offline => isDark
          ? (
              const Color(0xFF2C2C2C),
              const Color(0xFF424242),
              const Color(0xFFBDBDBD),
              'Offline',
            )
          : (
              const Color(0xFFF5F5F5),
              const Color(0xFFE0E0E0),
              const Color(0xFF616161),
              'Offline',
            ),
      SyncState.syncing => isDark
          ? (
              const Color(0xFF0D2847),
              const Color(0xFF1976D2),
              const Color(0xFF90CAF9),
              'Syncing...',
            )
          : (
              const Color(0xFFE3F2FD),
              const Color(0xFF90CAF9),
              const Color(0xFF0D47A1),
              'Syncing...',
            ),
      SyncState.conflict => isDark
          ? (
              const Color(0xFF3F1719),
              const Color(0xFFC62828),
              const Color(0xFFE57373),
              'Conflict',
            )
          : (
              const Color(0xFFFFEBEE),
              const Color(0xFFEF9A9A),
              const Color(0xFFB71C1C),
              'Conflict',
            ),
    };

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          switch (state) {
            SyncState.syncing => _SpinningIcon(
                size: 14,
                color: foregroundColor,
              ),
            SyncState.connected => Icon(
                Icons.check_circle_rounded,
                size: 14,
                color: foregroundColor,
              ),
            SyncState.offline => Icon(
                Icons.cloud_off_rounded,
                size: 14,
                color: foregroundColor,
              ),
            SyncState.conflict => Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: foregroundColor,
              ),
          },
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: foregroundColor,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );

    final semanticLabel = 'Sync status: $label.${onTap != null ? ' Tap to sync with laptop.' : ''}';

    if (onTap == null) {
      return Semantics(
        label: semanticLabel,
        child: content,
      );
    }

    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: content,
      ),
    );
  }
}

class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(
        Icons.sync,
        size: widget.size,
        color: widget.color,
      ),
    );
  }
}
