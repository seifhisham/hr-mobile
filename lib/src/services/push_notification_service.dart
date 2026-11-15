import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../firebase_options.dart';
import '../utils/utils.dart';
import 'push_device_service.dart';

@pragma('vm:entry-point')
Future<void> androidPushBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
  // Android displays notification payloads itself; do not create a duplicate.
}

class PushNotificationService {
  PushNotificationService();
  static final instance = PushNotificationService();
  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || _isIos);
  static bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;
  static const channel = AndroidNotificationChannel(
      'hodour_push', 'Hodour notifications',
      importance: Importance.high);
  final _local = FlutterLocalNotificationsPlugin();
  final _events = StreamController<bool>.broadcast();
  Stream<bool> get events => _events.stream;
  Future<void>? _localInitializing;
  bool _pendingOpen = false;
  bool _iosRegistrationPending = false;
  Future<void>? _iosRegistration;
  int _notificationId = 1000;

  bool takePendingOpen() {
    final pending = _pendingOpen;
    _pendingOpen = false;
    return pending;
  }

  void _opened() {
    _pendingOpen = true;
    _events.add(true);
  }

  void handleLocalResponse(NotificationResponse response) {
    if (response.payload == 'fcm') _opened();
  }

  Future<void> initializeLocalNotifications() =>
      _localInitializing ??= () async {
        await _local.initialize(
            settings: const InitializationSettings(
                android: AndroidInitializationSettings('ic_attendance')),
            onDidReceiveNotificationResponse: handleLocalResponse);
      }();

  Future<void> start() async {
    if (kIsWeb || (!supported && defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
      if (!supported) return;
      if (_isIos) {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
                alert: true, badge: true, sound: true);
      } else {
        FirebaseMessaging.onBackgroundMessage(androidPushBackgroundHandler);
        await initializeLocalNotifications();
        await _local
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()!
            .createNotificationChannel(channel);
      }
      FirebaseMessaging.onMessage.listen((message) {
        _events.add(false);
        if (!_isIos) unawaited(_showForeground(message));
      });
      FirebaseMessaging.onMessageOpenedApp.listen((_) => _opened());
      // The backend requires registration tokens; keep one registration flow.
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh.listen(
          (token) => unawaited(PushDeviceService.instance.tokenChanged(token)),
          onError: (Object error) => _failed(error));
      final launch =
          _isIos ? null : await _local.getNotificationAppLaunchDetails();
      if ((launch?.didNotificationLaunchApp ?? false) &&
          launch?.notificationResponse?.payload == 'fcm') {
        _opened();
      }
      if (await FirebaseMessaging.instance.getInitialMessage() != null) {
        _opened();
      }
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (_isIos) {
        _iosRegistrationPending =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
                settings.authorizationStatus == AuthorizationStatus.provisional;
        await PushDeviceService.diagnostic('permission',
            present: _iosRegistrationPending);
        resume();
        return;
      }
      // Keep compatible with the backend's registration-token contract.
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await PushDeviceService.instance.tokenChanged(token);
    } catch (error) {
      _failed(error);
    }
  }

  void resume() {
    if (!_iosRegistrationPending || _iosRegistration != null) return;
    _iosRegistration =
        _registerIos().whenComplete(() => _iosRegistration = null);
  }

  Future<void> _registerIos() async {
    try {
      final messaging = FirebaseMessaging.instance;
      var apnsPresent = false;
      for (var attempt = 0; attempt < 8; attempt++) {
        if (await messaging.getAPNSToken() != null) {
          if (!apnsPresent) {
            apnsPresent = true;
            await PushDeviceService.diagnostic('apns', present: true);
          }
          // Keep compatible with the backend's registration-token contract.
          // ignore: deprecated_member_use
          final token = await messaging.getToken();
          await PushDeviceService.diagnostic('firebase',
              present: token != null);
          if (token != null) {
            await PushDeviceService.instance.tokenChanged(token);
            _iosRegistrationPending = false;
            return;
          }
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!apnsPresent) {
        await PushDeviceService.diagnostic('apns', present: false);
      }
    } on FirebaseException catch (error) {
      await PushDeviceService.diagnostic('firebase', code: error.code);
    } catch (error) {
      _failed(error);
    }
  }

  void _failed(Object error) =>
      AppLogger.warning('Firebase startup unavailable',
          context: {'type': error.runtimeType.toString()});

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    try {
      await _local.show(
          id: _notificationId++,
          title: notification.title,
          body: notification.body,
          payload: 'fcm',
          notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                  'hodour_push', 'Hodour notifications',
                  importance: Importance.high,
                  priority: Priority.high,
                  icon: 'ic_attendance')));
    } catch (error) {
      _failed(error);
    }
  }
}
