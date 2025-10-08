import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  int _getNotificationId() {
    return DateTime.now().millisecondsSinceEpoch % 2147483647;
  }

  Future<void> init() async {
    try {
      final NotificationSettings settings =
          await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        criticalAlert: true,
        provisional: true,
        sound: true,
      );

      // Disable system-level foreground notifications
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: false, // Changed to false
        badge: false, // Changed to false
        sound: false, // Changed to false
      );

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

      await _handleTokenRetrieval();
      _firebaseMessaging.onTokenRefresh.listen((newToken) async {
        await _saveTokenToFirestore(newToken);
      });

      final DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings();

      await _notifications.initialize(
        InitializationSettings(iOS: initializationSettingsIOS),
        onDidReceiveNotificationResponse:
            (NotificationResponse response) async {
          if (response.payload != null) {
            try {
              final data = jsonDecode(response.payload!);
            } catch (e) {}
          }
        },
      );

      await _configureNotificationChannels();
      _setupAuthListener();
    } catch (e, st) {}
  }

  Future<void> _setupAuthListener() async {
    FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (user != null) {
        final token = await _firebaseMessaging.getToken();
        if (token != null) {
          await _saveTokenToFirestore(token);
        }
      }
    });
  }

  Future<void> _handleTokenRetrieval() async {
    try {
      final token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
      }
    } catch (e, st) {}
  }

  Future<void> _configureNotificationChannels() async {
    try {
      final iOSPlugin = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      if (iOSPlugin != null) {
        await iOSPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (e) {}
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _storePendingToken(token);
    }

    // **NEW GUARD**: only write to `users` once they've verified
    await user.reload();
    if (!user.emailVerified) {
      return _storePendingToken(token);
    }

    // Safe to merge into the real user doc now
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({'fcmToken': token}, SetOptions(merge: true));
  }

  Future<void> _storePendingToken(String token) async {
    try {
      await FirebaseFirestore.instance
          .collection('pending_tokens')
          .doc(token)
          .set({
        'token': token,
        'createdAt': FieldValue.serverTimestamp(),
        'associated': false,
      }, SetOptions(merge: true));
    } catch (e, st) {}
  }

  // Empty handler for foreground messages (no notification shown)
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // Foreground notifications disabled - no action taken
  }

  static Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    try {
      await Firebase.initializeApp();
      final title = message.data['title'] ?? message.notification?.title ?? '';
      final body = message.data['body'] ?? message.notification?.body ?? '';

      if (title.isNotEmpty || body.isNotEmpty) {
        final NotificationService service = NotificationService();
        await service._showNotification(
          title: title,
          body: body,
          data: message.data,
        );
      }
    } catch (e, st) {}
  }

  Future<void> _showNotification({
    required String? title,
    required String? body,
    required Map<String, dynamic> data,
  }) async {
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
      categoryIdentifier: 'ratedly_actions',
      threadIdentifier: 'ratedly_notifications',
    );

    final notificationId = _getNotificationId();
    final finalTitle = title ?? data['title'] ?? 'New Activity';
    final finalBody = body ?? data['body'] ?? 'You have new activity';

    await _notifications.show(
      notificationId,
      finalTitle,
      finalBody,
      const NotificationDetails(iOS: iosDetails),
      payload: jsonEncode(data),
    );
  }

  Future<void> showTestNotification() async {
    try {
      await _notifications.show(
        _getNotificationId(),
        'Test Notification',
        'This is a test notification from Ratedly!',
        const NotificationDetails(iOS: DarwinNotificationDetails()),
        payload: jsonEncode({
          'type': 'test',
          'source': 'debug',
        }),
      );
    } catch (e, st) {}
  }

  Future<void> triggerServerNotification({
    required String type,
    required String targetUserId,
    String? title,
    String? body,
    Map<String, dynamic>? customData,
  }) async {
    try {
      final notificationData = {
        'type': type,
        'targetUserId': targetUserId,
        'title': title ?? 'New Notification',
        'body': body ?? 'You have a new notification',
        'customData': customData ?? {},
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('notifications')
          .add(notificationData);
    } catch (e, st) {}
  }
}
