import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/shopping_item.dart';

class ShoppingReminderService {
  ShoppingReminderService._();

  static final instance = ShoppingReminderService._();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
      ),
    );
    _initialized = true;
  }

  Future<bool> schedule(ShoppingItem item) async {
    final reminder = item.remindAt;
    if (reminder == null || item.checked) {
      await cancel(item);
      return true;
    }
    await initialize();
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission() ?? true;
    if (!granted) return false;

    var scheduled = tz.TZDateTime(
      tz.local,
      reminder.year,
      reminder.month,
      reminder.day,
      reminder.hour,
      reminder.minute,
    );
    final now = tz.TZDateTime.now(tz.local);
    if (!scheduled.isAfter(now)) {
      scheduled = now.add(const Duration(minutes: 1));
    }
    await _notifications.zonedSchedule(
      id: item.notificationId,
      title: 'Shopping reminder',
      body: 'Remember to buy ${item.name}.',
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'cartsense_shopping_reminders',
          'Shopping reminders',
          channelDescription: 'Reminders for products on your CartSense list',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: item.id,
    );
    return true;
  }

  Future<void> cancel(ShoppingItem item) async {
    await initialize();
    await _notifications.cancel(id: item.notificationId);
  }
}
