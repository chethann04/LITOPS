import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/common_widgets.dart';

/// All toast notification types requested:
/// processing, success, failed, warning, loading, completed, updating, result, info
enum ToastType {
  processing,
  loading,
  updating,
  success,
  completed,
  failed,
  error,
  warning,
  result,
  info,
}

// Backwards compatibility alias
typedef NotificationType = ToastType;

class NotificationData {
  final String id;
  final String? title;
  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback? onTap;
  final IconData? customIcon;
  final String? actionLabel;
  final VoidCallback? onAction;

  NotificationData({
    required this.id,
    this.title,
    required this.message,
    this.type = ToastType.info,
    this.duration = const Duration(seconds: 4),
    this.onTap,
    this.customIcon,
    this.actionLabel,
    this.onAction,
  });
}

// Provider to manage toast notifications across the entire app
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
    ToastType type = ToastType.info,
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
    ToastType type = ToastType.info,
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

/// Unified AppToast helper class providing clean, expressive toast triggers
class AppToast {
  static void show(
    BuildContext? context,
    String message, {
    String? title,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onTap,
    IconData? customIcon,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    showTopNotification(
      context,
      message,
      title: title,
      type: type,
      duration: duration,
      onTap: onTap,
      customIcon: customIcon,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// 1. Processing toast (spinning ember indicator)
  static void processing(BuildContext? context, String message, {String? title, Duration? duration}) =>
      show(context, message, title: title ?? 'Processing...', type: ToastType.processing, duration: duration ?? const Duration(seconds: 4));

  /// 2. Loading toast (spinning cyan-blue indicator)
  static void loading(BuildContext? context, String message, {String? title, Duration? duration}) =>
      show(context, message, title: title ?? 'Loading...', type: ToastType.loading, duration: duration ?? const Duration(seconds: 4));

  /// 3. Updating toast (rotating sync amber indicator)
  static void updating(BuildContext? context, String message, {String? title, Duration? duration}) =>
      show(context, message, title: title ?? 'Updating...', type: ToastType.updating, duration: duration ?? const Duration(seconds: 4));

  /// 4. Success toast (emerald checkmark)
  static void success(BuildContext? context, String message, {String? title, Duration? duration}) =>
      show(context, message, title: title ?? 'Success', type: ToastType.success, duration: duration ?? const Duration(seconds: 4));

  /// 5. Completed toast (vibrant completion checkmark)
  static void completed(BuildContext? context, String message, {String? title, Duration? duration}) =>
      show(context, message, title: title ?? 'Completed', type: ToastType.completed, duration: duration ?? const Duration(seconds: 4));

  /// 6. Failed toast (coral error indicator)
  static void failed(BuildContext? context, String message, {String? title, Duration? duration}) =>
      show(context, message, title: title ?? 'Failed', type: ToastType.failed, duration: duration ?? const Duration(seconds: 4));

  /// 7. Error alias
  static void error(BuildContext? context, String message, {String? title, Duration? duration}) =>
      failed(context, message, title: title ?? 'Error', duration: duration);

  /// 8. Warning toast (amber warning triangle)
  static void warning(BuildContext? context, String message, {String? title, Duration? duration}) =>
      show(context, message, title: title ?? 'Warning', type: ToastType.warning, duration: duration ?? const Duration(seconds: 4));

  /// 9. Result toast (trophy badge)
  static void result(BuildContext? context, String message, {String? title, Duration? duration}) =>
      show(context, message, title: title ?? '🏆 Results Published', type: ToastType.result, duration: duration ?? const Duration(seconds: 5));

  /// 10. Info toast
  static void info(BuildContext? context, String message, {String? title, Duration? duration}) =>
      show(context, message, title: title ?? 'Notice', type: ToastType.info, duration: duration ?? const Duration(seconds: 4));
}

/// Helper function to show notifications easily (backwards compatible)
void showTopNotification(
  BuildContext? context,
  String message, {
  String? title,
  ToastType type = ToastType.info,
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

/// TopNotificationWidget mounted at MaterialApp root builder
class TopNotificationWidget extends ConsumerWidget {
  const TopNotificationWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.transparent,
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
  AnimationController? _spinController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  Timer? _timer;

  bool get _isSpinning =>
      widget.notification.type == ToastType.processing ||
      widget.notification.type == ToastType.loading ||
      widget.notification.type == ToastType.updating;

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

    // Continuous spin animation for processing/loading/updating
    if (_isSpinning) {
      _spinController = AnimationController(
        duration: const Duration(milliseconds: 1100),
        vsync: this,
      )..repeat();
    }

    // Light tactile haptic feedback on arrival
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
    _spinController?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Color _getAccentColor(ToastType type) {
    switch (type) {
      case ToastType.processing:
        return const Color(0xFFFF6A2C); // LitColors.ember
      case ToastType.loading:
        return const Color(0xFF38BDF8); // Cyan-blue
      case ToastType.updating:
        return const Color(0xFFFFB14D); // LitColors.amber
      case ToastType.success:
        return const Color(0xFF6FAE8F); // LitColors.moss
      case ToastType.completed:
        return const Color(0xFF4ADE80); // Bright emerald
      case ToastType.failed:
      case ToastType.error:
        return const Color(0xFFFF5C5C); // LitColors.coral
      case ToastType.warning:
        return const Color(0xFFFFB14D); // LitColors.amber
      case ToastType.result:
        return const Color(0xFFFF6A2C); // LitColors.ember
      case ToastType.info:
        return const Color(0xFFA8A29E); // Ash/Stone
    }
  }

  Widget _buildIcon(ToastType type, Color accentColor) {
    if (widget.notification.customIcon != null) {
      return Icon(widget.notification.customIcon, color: accentColor, size: 20);
    }

    switch (type) {
      case ToastType.processing:
        return _spinController != null
            ? RotationTransition(
                turns: _spinController!,
                child: Icon(Icons.sync_rounded, color: accentColor, size: 20),
              )
            : Icon(Icons.sync_rounded, color: accentColor, size: 20);

      case ToastType.loading:
        return SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            valueColor: AlwaysStoppedAnimation<Color>(accentColor),
          ),
        );

      case ToastType.updating:
        return _spinController != null
            ? RotationTransition(
                turns: _spinController!,
                child: Icon(Icons.refresh_rounded, color: accentColor, size: 20),
              )
            : Icon(Icons.refresh_rounded, color: accentColor, size: 20);

      case ToastType.success:
        return Icon(Icons.check_circle_rounded, color: accentColor, size: 20);

      case ToastType.completed:
        return Icon(Icons.task_alt_rounded, color: accentColor, size: 20);

      case ToastType.failed:
      case ToastType.error:
        return Icon(Icons.cancel_rounded, color: accentColor, size: 20);

      case ToastType.warning:
        return Icon(Icons.warning_amber_rounded, color: accentColor, size: 20);

      case ToastType.result:
        return Icon(Icons.emoji_events_rounded, color: accentColor, size: 20);

      case ToastType.info:
        return Icon(Icons.info_outline_rounded, color: accentColor, size: 20);
    }
  }

  String _getDefaultTitle(ToastType type) {
    switch (type) {
      case ToastType.processing:
        return 'Processing...';
      case ToastType.loading:
        return 'Loading...';
      case ToastType.updating:
        return 'Updating...';
      case ToastType.success:
        return 'Success';
      case ToastType.completed:
        return 'Completed';
      case ToastType.failed:
      case ToastType.error:
        return 'Failed';
      case ToastType.warning:
        return 'Warning';
      case ToastType.result:
        return '🏆 Results Published';
      case ToastType.info:
        return 'Notice';
    }
  }

  String _getTagLabel(ToastType type) {
    switch (type) {
      case ToastType.processing:
        return 'PROCESSING';
      case ToastType.loading:
        return 'LOADING';
      case ToastType.updating:
        return 'UPDATING';
      case ToastType.success:
        return 'SUCCESS';
      case ToastType.completed:
        return 'DONE';
      case ToastType.failed:
      case ToastType.error:
        return 'FAILED';
      case ToastType.warning:
        return 'WARNING';
      case ToastType.result:
        return 'TROPHY';
      case ToastType.info:
        return 'INFO';
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _getAccentColor(widget.notification.type);
    final displayTitle = widget.notification.title ?? _getDefaultTitle(widget.notification.type);
    final tagLabel = _getTagLabel(widget.notification.type);

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
            child: Material(
              color: Colors.transparent,
              elevation: 0,
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
                      color: Colors.black.withValues(alpha: 0.60),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.14),
                      blurRadius: 12,
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
                    GestureDetector(
                      onTap: widget.notification.onTap != null
                          ? () {
                              widget.notification.onTap!();
                              _dismiss();
                            }
                          : null,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Left Squircle Icon Badge
                            Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: accentColor.withValues(alpha: 0.35),
                                  width: 1.0,
                                ),
                              ),
                              child: _buildIcon(widget.notification.type, accentColor),
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
                                          tagLabel,
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
                            GestureDetector(
                              onTap: _dismiss,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                child: const Icon(Icons.close_rounded, size: 16, color: LitColors.ash),
                              ),
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
      ),
    );
  }
}
