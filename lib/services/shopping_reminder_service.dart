import '../models/shopping_item.dart';

class ShoppingReminderService {
  ShoppingReminderService._();

  static final instance = ShoppingReminderService._();

  Future<bool> initialize() async => true;

  Future<bool> schedule(ShoppingItem item) async {
    // CartSense stores reminder dates with the shopping-list item. This build
    // avoids native notification scheduling so Android release builds stay
    // stable across local environments.
    return item.remindAt == null || !item.checked;
  }

  Future<void> cancel(ShoppingItem item) async {}
}
