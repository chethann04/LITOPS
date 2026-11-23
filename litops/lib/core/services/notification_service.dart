import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../../core/supabase/supabase_config.dart';
import '../../core/supabase/supabase_tables.dart';
import '../enums/enums.dart';
import '../utils/app_utils.dart';
import '../widgets/top_notification.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling a background message: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  RealtimeChannel? _notificationChannel;
  final Map<String, DateTime> _handledNotificationKeys = {};

  bool _isDuplicate(String key) {
    if (key.isEmpty) return false;
    final now = DateTime.now();
    _handledNotificationKeys.removeWhere((_, time) => now.difference(time).inMinutes > 2);
    if (_handledNotificationKeys.containsKey(key)) {
      return true;
    }
    _handledNotificationKeys[key] = now;
    return false;
  }

  Future<void> initialize() async {
    debugPrint('NotificationService: Initializing...');
    
    // Android initialization
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_notification');

    // iOS initialization
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('NotificationService: Notification clicked: ${response.payload}');
      },
    );

    // Initialize Firebase Cloud Messaging
    try {
      debugPrint('NotificationService: Initializing Firebase Messaging...');
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      
      // Request permissions (specifically for iOS/Android 13+)
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      debugPrint('NotificationService: Permission status: ${settings.authorizationStatus}');

      // Get APNs token for iOS
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken = await messaging.getAPNSToken();
        debugPrint('NotificationService: APNs token: $apnsToken');
      }

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      debugPrint('NotificationService: Background handler registered');

      // Listen for foreground FCM messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('NotificationService: Got FCM message in foreground: ${message.messageId}');
        final msgId = message.messageId ?? (message.data['id'] as String? ?? '');
        final senderId = message.data['sender_user_id'] as String?;
        final currentUserId = SupabaseConfig.client.auth.currentUser?.id;

        // Never notify the sender/publisher themselves
        if (currentUserId != null && senderId == currentUserId) {
          debugPrint('NotificationService: Ignoring FCM sent by current user ($currentUserId)');
          return;
        }

        // Deduplicate against Realtime or duplicate FCM delivery
        final dedupKey = msgId.isNotEmpty ? msgId : '${message.notification?.title}_${message.notification?.body}';
        if (_isDuplicate(dedupKey)) {
          debugPrint('NotificationService: Skipping duplicate FCM message: $dedupKey');
          return;
        }

        if (message.notification != null) {
          final title = message.notification!.title ?? 'New Notification';
          final body = message.notification!.body ?? '';
          final isResult = title.toLowerCase().contains('result') || body.toLowerCase().contains('result');
          NotificationsNotifier.postGlobal(
            title: title,
            message: body,
            type: isResult ? NotificationType.result : NotificationType.info,
          );
        }
      });

      // Handle notification interaction when app is launched from background or terminated states
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('NotificationService: FCM Notification clicked to open app: ${message.data}');
      });

      FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
        if (message != null) {
          debugPrint('NotificationService: App opened from terminated state by FCM: ${message.data}');
        }
      });
    } catch (e) {
      debugPrint('NotificationService: Error initializing Firebase Messaging: $e');
    }

    // Listen to Supabase auth changes to start/stop listening to notifications
    SupabaseConfig.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        debugPrint('NotificationService: User logged in, starting listening...');
        _startListening(session.user.id);
        _registerFcmToken(session.user.id);
      } else {
        debugPrint('NotificationService: User logged out, stopping listening...');
        unregisterFcmToken();
        _stopListening();
      }
    });

    // Start listening immediately if already logged in
    final currentUser = SupabaseConfig.client.auth.currentUser;
    if (currentUser != null) {
      debugPrint('NotificationService: User already logged in, starting listening...');
      _startListening(currentUser.id);
      _registerFcmToken(currentUser.id);
    }
  }

  void _startListening(String userId) {
    debugPrint('NotificationService: Starting to listen for notifications for user: $userId');
    _stopListening();

    _notificationChannel = SupabaseConfig.client
        .channel('public:notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: SupabaseTables.notifications,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            debugPrint('NotificationService: Received new notification from Supabase: $payload');
            final newRecord = payload.newRecord;
            final notifId = newRecord['id'] as String? ?? '';
            final senderId = newRecord['sender_user_id'] as String?;
            final eventId = newRecord['event_id'] as String? ?? '';
            final notifTypeStr = newRecord['type'] as String? ?? '';

            // 1. Never notify the sender/publisher themselves
            if (senderId != null && senderId == userId) {
              debugPrint('NotificationService: Ignoring Realtime notification sent by current user ($userId)');
              return;
            }

            // 2. Deduplicate against FCM and duplicate Realtime events
            final dedupKey = notifId.isNotEmpty ? notifId : '${eventId}_${notifTypeStr}_$userId';
            if (_isDuplicate(dedupKey)) {
              debugPrint('NotificationService: Skipping duplicate Realtime notification: $dedupKey');
              return;
            }

            final title = newRecord['title'] as String? ?? 'New Notification';
            final body = newRecord['message'] as String? ?? '';
            final isResult = title.toLowerCase().contains('result') || body.toLowerCase().contains('result');
            final notifType = isResult ? NotificationType.result : NotificationType.info;

            // Show ONE single clean in-app toast
            NotificationsNotifier.postGlobal(
              title: title,
              message: body,
              type: notifType,
            );
          },
        )
        .subscribe();
  }

  void _stopListening() {
    if (_notificationChannel != null) {
      debugPrint('NotificationService: Stopping listening for notifications');
      SupabaseConfig.client.removeChannel(_notificationChannel!);
      _notificationChannel = null;
    }
  }

  Future<void> _registerFcmToken(String userId) async {
    debugPrint('NotificationService: Registering FCM token for user: $userId');
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      debugPrint('NotificationService: FCM token: $token');
      if (token == null) {
        debugPrint('NotificationService: FCM token is null, skipping registration');
        return;
      }

      final deviceType = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

      await SupabaseConfig.client.from('user_fcm_tokens').upsert({
        'user_id': userId,
        'fcm_token': token,
        'device_type': deviceType,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'fcm_token');
      debugPrint('NotificationService: FCM token registered successfully');

      // Listen for token refreshes
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        debugPrint('NotificationService: FCM token refreshed: $newToken');
        await SupabaseConfig.client.from('user_fcm_tokens').upsert({
          'user_id': userId,
          'fcm_token': newToken,
          'device_type': deviceType,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'fcm_token');
        debugPrint('NotificationService: Refreshed FCM token registered successfully');
      });
    } catch (e) {
      debugPrint('NotificationService: Error registering FCM token: $e');
    }
  }

  Future<void> unregisterFcmToken() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await SupabaseConfig.client
            .from('user_fcm_tokens')
            .delete()
            .eq('fcm_token', token);
      }
    } catch (e) {
      debugPrint('Error unregistering FCM token: $e');
    }
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    debugPrint('NotificationService: Showing local notification - Title: $title, Body: $body');
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'litops_notifications',
      'Lit Life Notifications',
      channelDescription: 'Notifications for Lit Life app',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      icon: '@drawable/ic_notification',
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _localNotifications.show(
      id: DateTime.now().millisecond,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
      payload: payload,
    );
  }

  /// Sends notifications to all 3rd and 4th year members (and ONLY 3rd and 4th year members)
  /// when event results are published.
  Future<int> notifySeniorMembersOnResultsPublished({
    required String eventId,
    required String eventName,
    String? publisherUserId,
    String? summaryText,
  }) async {
    final title = '🏆 Results Published: $eventName';
    String body = 'Results for "$eventName" have been published.';
    if (summaryText != null && summaryText.trim().isNotEmpty) {
      body += '\n${summaryText.trim()}';
    }
    body += '\nCheck the leaderboard for updated branch standings!';

    // 1. Try secure database RPC first (runs with SECURITY DEFINER in PostgreSQL)
    try {
      final rpcRes = await SupabaseConfig.client.rpc(
        'notify_senior_members_on_results_published_rpc',
        params: {
          'p_event_id': eventId,
          'p_event_name': eventName,
          'p_summary_text': summaryText,
        },
      );
      if (rpcRes != null) {
        final count = (rpcRes is int) ? rpcRes : int.tryParse(rpcRes.toString()) ?? 1;
        debugPrint('NotificationService: Database RPC dispatched results notifications to $count members.');
        return count;
      }
    } catch (rpcErr) {
      debugPrint('NotificationService: RPC fallback to direct query: $rpcErr');
    }

    // 2. Direct client query fallback
    try {
      debugPrint('NotificationService: Fetching 3rd & 4th year members for event "$eventName"...');
      final profilesRes = await SupabaseConfig.client
          .from(SupabaseTables.profiles)
          .select('id, full_name, role, year, usn, is_active, profile_status');

      final eligibleUserIds = <String>{};

      for (final p in profilesRes as List) {
        final id = p['id'] as String?;
        if (id == null) continue;
        if (publisherUserId != null && id == publisherUserId) {
          // Do not send notification to the publisher themselves
          continue;
        }

        final isActive = (p['is_active'] as bool?) ?? true;
        final profileStatus = p['profile_status'] as String? ?? 'approved';
        if (!isActive || profileStatus == 'rejected') {
          continue;
        }

        // Determine study year (1–4)
        int? studyYear = p['year'] as int?;
        if (studyYear == null) {
          final usn = p['usn'] as String?;
          if (usn != null && usn.trim().isNotEmpty) {
            studyYear = AppUtils.inferCurrentStudyYearFromUsn(usn);
          }
        }

        // STRICT EXCLUSION: Never send to 1st or 2nd year members
        if (studyYear == 1 || studyYear == 2) {
          continue;
        }

        // STRICT MATCH: Only 3rd and 4th year members
        if (studyYear == 3 || studyYear == 4) {
          eligibleUserIds.add(id);
          continue;
        }

        // Fallback for unpopulated year: check role
        final roleStr = p['role'] as String? ?? '';
        if (roleStr == 'junior_wing' || roleStr == 'assistant_coordinator') {
          // Junior Wing = Year 1, Assistant Coordinator = Year 2 -> EXCLUDE
          continue;
        }

        // Core heads / coordinators / directors are 3rd & 4th years
        final isSeniorRole = UserRole.values.any((r) =>
            r.value == roleStr &&
            r != UserRole.juniorWing &&
            r != UserRole.assistantCoordinator);

        if (isSeniorRole) {
          eligibleUserIds.add(id);
        }
      }

      if (eligibleUserIds.isEmpty) {
        debugPrint('NotificationService: No eligible 3rd/4th year members found.');
        return 0;
      }

      // If re-publishing, remove older results_published notifications for this event so updated ones are received
      try {
        await SupabaseConfig.client
            .from(SupabaseTables.notifications)
            .delete()
            .eq('event_id', eventId)
            .eq('type', 'results_published');
      } catch (delErr) {
        debugPrint('NotificationService: (Notice) Previous notifications clear: $delErr');
      }

      final notificationRows = eligibleUserIds.map((userId) => {
        'user_id': userId,
        'sender_user_id': publisherUserId,
        'title': title,
        'message': body,
        'type': 'results_published',
        'is_read': false,
        'event_id': eventId,
      }).toList();

      await SupabaseConfig.client
          .from(SupabaseTables.notifications)
          .insert(notificationRows);

      debugPrint('NotificationService: Successfully dispatched results_published notifications to ${notificationRows.length} 3rd and 4th year members.');

      return notificationRows.length;
    } catch (e) {
      debugPrint('NotificationService: Error notifying senior members on results published: $e');
      return 0;
    }
  }
}
