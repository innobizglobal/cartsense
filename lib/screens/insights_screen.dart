import 'package:flutter/material.dart';
import '../models/receipt.dart';
import '../models/savings_intelligence.dart';
import '../services/budget_store.dart';
import '../theme/cartsense_theme.dart';
import '../widgets/category_icon.dart';

const _green = CartSenseColors.primary;
const _lime = CartSenseColors.accent;
const _ivory = CartSenseColors.background;

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, required this.receipts});

  final List<Receipt> receipts;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final _budgetStore = BudgetStore();
  double budget = 0;

  SavingsIntelligence get insights =>
      SavingsIntelligence.fromReceipts(widget.receipts);

  @override
  void initState() {
    super.initState();
    _loadBudget();
  }

  Future<void> _loadBudget() async {
    final value = await _budgetStore.load();
    if (mounted) setState(() => budget = value);
  }

  Future<void> _editBudget() async {
    final controller = TextEditingController(
      text: budget > 0 ? budget.toStringAsFixed(0) : '',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Monthly grocery budget'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            prefixText: '₹ ',
            hintText: 'For example 10000',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save budget'),
          ),
        ],
      ),
    );
    if (save == true) {
      final value = double.tryParse(controller.text.trim());
      if (value != null && value >= 0) {
        await _budgetStore.save(value);
        if (mounted) setState(() => budget = value);
      }
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = insights;
    final budgetProgress = budget <= 0 ? 0.0 : data.currentMonthTotal / budget;
    final maximumMonth = data.monthlySpend.fold(
      0.0,
      (maximum, item) => item.total > maximum ? item.total : maximum,
    );
    final categories = data.categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      backgroundColor: _ivory,
      appBar: AppBar(title: const Text('Insights')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          Card(
            color: _green,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          color: Colors.white70, size: 19),
                      SizedBox(width: 7),
                      Text(
                        'Grocery spend this month',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${data.currentMonthTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 31,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: budget <= 0 ? 0 : budgetProgress.clamp(0, 1),
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(10),
                    backgroundColor: Colors.white24,
                    color: budgetProgress > 1 ? Colors.orange : _lime,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          budget > 0
                              ? budgetProgress <= 1
                                  ? '₹${(budget - data.currentMonthTotal).toStringAsFixed(0)} remaining of ₹${budget.toStringAsFixed(0)}'
                                  : '₹${(data.currentMonthTotal - budget).toStringAsFixed(0)} over your ₹${budget.toStringAsFixed(0)} budget'
                              : 'Set a budget to track monthly spending',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton(
                        onPressed: _editBudget,
                        style: TextButton.styleFrom(foregroundColor: _lime),
                        child: Text(budget > 0 ? 'Edit' : 'Set budget'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle(
            icon: Icons.show_chart,
            title: 'Spending trend',
          ),
          const SizedBox(height: 10),
          if (maximumMonth == 0)
            const _EmptyCard('Save bills to start seeing spending trends.')
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: data.monthlySpend.map((month) {
                    final label = _monthName(month.month.month);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(width: 38, child: Text(label)),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: maximumMonth == 0
                                  ? 0
                                  : month.total / maximumMonth,
                              minHeight: 12,
                              borderRadius: BorderRadius.circular(8),
                              backgroundColor: CartSenseColors.surfaceMuted,
                              color: _green,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 80,
                            child: Text(
                              '₹${month.total.toStringAsFixed(0)}',
                              textAlign: TextAlign.end,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          const SizedBox(height: 20),
          const _SectionTitle(
            icon: Icons.category_outlined,
            title: 'This month by category',
          ),
          const SizedBox(height: 10),
          if (categories.isEmpty)
            const _EmptyCard('Categories will appear after you save a bill.')
          else
            ...categories.map((entry) => Card(
                  child: ListTile(
                    leading: CategoryAvatar(category: entry.key),
                    title: Text(entry.key),
                    trailing: Text(
                      '₹${entry.value.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                )),
          const SizedBox(height: 20),
          const _SectionTitle(
            icon: Icons.trending_up,
            title: 'Price changes',
          ),
          const SizedBox(height: 10),
          if (data.priceRises.isEmpty)
            const _EmptyCard('No repeated product price rises found yet.')
          else
            ...data.priceRises.take(8).map((item) => Card(
                  color: CartSenseColors.warning,
                  child: ListTile(
                    leading: const Icon(Icons.arrow_upward,
                        color: Colors.deepOrange),
                    title: Text(item.name),
                    subtitle: Text(
                      'Was ₹${item.previousPrice!.toStringAsFixed(2)} · now ₹${item.latestPrice.toStringAsFixed(2)} at ${item.latestStore}',
                    ),
                    trailing: Text(
                      '+${item.priceChangePercent.toStringAsFixed(0)}%',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                )),
          const SizedBox(height: 20),
          const _SectionTitle(
            icon: Icons.storefront_outlined,
            title: 'Better prices nearby',
          ),
          const SizedBox(height: 10),
          if (data.cheaperStoreOptions.isEmpty)
            const _EmptyCard(
              'Scan bills from more than one store to compare prices.',
            )
          else
            ...data.cheaperStoreOptions.take(8).map((item) => Card(
                  color: CartSenseColors.success,
                  child: ListTile(
                    leading: const Icon(Icons.savings_outlined, color: _green),
                    title: Text(item.name),
                    subtitle: Text(
                      'Best seen at ${item.bestStore}: ₹${item.bestPrice.toStringAsFixed(2)}',
                    ),
                    trailing: Text(
                      'Save ₹${item.possibleSaving.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: _green),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Card(
        color: CartSenseColors.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(message),
        ),
      );
}

String _monthName(int month) => const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][month - 1];
