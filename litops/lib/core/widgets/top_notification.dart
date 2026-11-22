import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/common_widgets.dart';

enum NotificationType { success, error, warning, info, result }

class NotificationData {
  final String id;
  final String? title;
  final String message;
  final NotificationType type;
  final Duration duration;
  final VoidCallback? onTap;
  final IconData? customIcon;
  final String? actionLabel;
  final VoidCallback? onAction;

  NotificationData({
    required this.id,
    this.title,
    required this.message,
    this.type = NotificationType.info,
    this.duration = const Duration(seconds: 4),
    this.onTap,
    this.customIcon,
    this.actionLabel,
    this.onAction,
  });
}

// Provider to manage notifications
final notificationsProvider = StateNotifierProvider<NotificationsNotifier, List<NotificationData>>((ref) {
  return NotificationsNotifier();
});

class NotificationsNotifier extends StateNotifier<List<NotificationData>> {
  static NotificationsNotifier? _globalInstance;

  NotificationsNotifier() : super([]) {
    _globalInstance = this;
  }

  void showNotification({
    String? title,
    required String message,
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onTap,
    IconData? customIcon,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final notification = NotificationData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      message: message,
      type: type,
      duration: duration,
      onTap: onTap,
      customIcon: customIcon,
      actionLabel: actionLabel,
      onAction: onAction,
    );
    state = [...state, notification];
  }

  void hideNotification(String id) {
    state = state.where((n) => n.id != id).toList();
  }

  static void postGlobal({
    String? title,
    required String message,
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onTap,
    IconData? customIcon,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _globalInstance?.showNotification(
      title: title,
      message: message,
      type: type,
      duration: duration,
      onTap: onTap,
      customIcon: customIcon,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

// Helper function to show notifications easily
void showTopNotification(
  BuildContext? context,
  String message, {
  String? title,
  NotificationType type = NotificationType.info,
  Duration duration = const Duration(seconds: 4),
  VoidCallback? onTap,
  IconData? customIcon,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  if (context != null) {
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      container.read(notificationsProvider.notifier).showNotification(
            title: title,
            message: message,
            type: type,
            duration: duration,
            onTap: onTap,
            customIcon: customIcon,
            actionLabel: actionLabel,
            onAction: onAction,
          );
      return;
    } catch (_) {}
  }

  NotificationsNotifier.postGlobal(
    title: title,
    message: message,
    type: type,
    duration: duration,
    onTap: onTap,
    customIcon: customIcon,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

class TopNotificationWidget extends ConsumerWidget {
  const TopNotificationWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: notifications.map((notification) {
            return NotificationItem(
              key: Key(notification.id),
              notification: notification,
              onDismiss: () => ref.read(notificationsProvider.notifier).hideNotification(notification.id),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class NotificationItem extends StatefulWidget {
  final NotificationData notification;
  final VoidCallback onDismiss;

  const NotificationItem({
    super.key,
    required this.notification,
    required this.onDismiss,
  });

  @override
  State<NotificationItem> createState() => _NotificationItemState();
}

class _NotificationItemState extends State<NotificationItem> with TickerProviderStateMixin {
  late AnimationController _entryController;
  late AnimationController _progressController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Entry animation
    _entryController = AnimationController(
      duration: const Duration(milliseconds: 380),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOutBack));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOut));

    _scaleAnimation = Tween<double>(
      begin: 0.92,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOutBack));

    // Progress bar animation for duration
    _progressController = AnimationController(
      duration: widget.notification.duration,
      vsync: this,
    );

    // Light tactile feedback on arrival
    HapticFeedback.lightImpact();

    _entryController.forward();
    _progressController.forward();

    if (widget.notification.duration.inMilliseconds > 0) {
      _timer = Timer(widget.notification.duration, () {
        if (mounted) _dismiss();
      });
    }
  }

  void _dismiss() {
    _timer?.cancel();
    _entryController.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    _progressController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Color _getAccentColor(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return const Color(0xFF6FAE8F); // LitColors.moss
      case NotificationType.error:
        return const Color(0xFFFF5C5C); // LitColors.coral
      case NotificationType.warning:
        return const Color(0xFFFFB14D); // LitColors.amber
      case NotificationType.result:
        return const Color(0xFFFF6A2C); // LitColors.ember
      case NotificationType.info:
        return const Color(0xFFFF8A4C); // LitColors.ember soft
    }
  }

  IconData _getIcon(NotificationType type) {
    if (widget.notification.customIcon != null) {
      return widget.notification.customIcon!;
    }
    switch (type) {
      case NotificationType.success:
        return Icons.check_circle_rounded;
      case NotificationType.error:
        return Icons.error_rounded;
      case NotificationType.warning:
        return Icons.warning_amber_rounded;
      case NotificationType.result:
        return Icons.emoji_events_rounded;
      case NotificationType.info:
        return Icons.notifications_active_rounded;
    }
  }

  String _getDefaultTitle(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return 'Success';
      case NotificationType.error:
        return 'Alert';
      case NotificationType.warning:
        return 'Notice';
      case NotificationType.result:
        return '🏆 Results Update';
      case NotificationType.info:
        return 'LitOps Update';
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _getAccentColor(widget.notification.type);
    final displayTitle = widget.notification.title ?? _getDefaultTitle(widget.notification.type);

    return Dismissible(
      key: Key('dismiss_${widget.notification.id}'),
      direction: DismissDirection.up,
      onDismissed: (_) {
        _timer?.cancel();
        widget.onDismiss();
      },
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              decoration: BoxDecoration(
                color: const Color(0xFF181514),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Ambient corner glow
                  Positioned(
                    top: -24,
                    left: -24,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: widget.notification.onTap != null
                        ? () {
                            widget.notification.onTap!();
                            _dismiss();
                          }
                        : null,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Left Squircle Icon Badge
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: accentColor.withValues(alpha: 0.35),
                                width: 1.0,
                              ),
                            ),
                            child: Icon(
                              _getIcon(widget.notification.type),
                              color: accentColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Content Column
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        displayTitle,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: LitColors.bone,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        widget.notification.type.name.toUpperCase(),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w700,
                                          color: accentColor,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.notification.message,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11.5,
                                    color: LitColors.ash,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.notification.actionLabel != null) ...[
                                  const SizedBox(height: 6),
                                  GestureDetector(
                                    onTap: () {
                                      widget.notification.onAction?.call();
                                      _dismiss();
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          widget.notification.actionLabel!,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: accentColor,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 13,
                                          color: accentColor,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Close button
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16, color: LitColors.ash),
                            splashRadius: 18,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            onPressed: _dismiss,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Sleek Bottom Progress Timer Indicator
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, _) {
                        return LinearProgressIndicator(
                          value: 1.0 - _progressController.value,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            accentColor.withValues(alpha: 0.45),
                          ),
                          minHeight: 2.2,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
