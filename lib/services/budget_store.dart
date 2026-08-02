import 'package:shared_preferences/shared_preferences.dart';

class BudgetStore {
  static const _key = 'cartsense_monthly_budget_v1';

  Future<double> load() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getDouble(_key) ?? 0;
  }

  Future<void> save(double value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_key, value.clamp(0, double.infinity));
  }
}
