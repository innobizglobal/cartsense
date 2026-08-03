import 'package:flutter/material.dart';
import '../models/receipt.dart';
import '../models/shopping_item.dart';
import '../models/shopping_reconciliation.dart';
import '../services/shopping_list_store.dart';
import '../services/shopping_reminder_service.dart';
import '../theme/cartsense_theme.dart';
import '../widgets/app_footer_nav.dart';
import '../widgets/category_icon.dart';

const _green = CartSenseColors.primary;
const _lime = CartSenseColors.accent;
const _ivory = CartSenseColors.background;

class ShoppingReconciliationScreen extends StatefulWidget {
  const ShoppingReconciliationScreen({
    super.key,
    required this.receipt,
    required this.plannedItems,
    this.activeShoppingCount = 0,
    this.onOpenShoppingList,
    this.onOpenInsights,
  });

  final Receipt receipt;
  final List<ShoppingItem> plannedItems;
  final int activeShoppingCount;
  final VoidCallback? onOpenShoppingList;
  final VoidCallback? onOpenInsights;

  @override
  State<ShoppingReconciliationScreen> createState() =>
      _ShoppingReconciliationScreenState();
}

class _ShoppingReconciliationScreenState
    extends State<ShoppingReconciliationScreen> {
  late final Map<String, int> assignments = ShoppingReconciliation.suggest(
    widget.plannedItems,
    widget.receipt,
  );
  bool finishing = false;

  double get plannedEstimate => widget.plannedItems.fold(
        0,
        (total, item) => total + item.estimatedTotal,
      );

  double get billTotal => widget.receipt.printedTotal > 0
      ? widget.receipt.printedTotal
      : widget.receipt.calculatedTotal;

  Set<int> get assignedReceiptRows => assignments.values.toSet();

  List<int> get unplannedRows => List.generate(
        widget.receipt.items.length,
        (index) => index,
      ).where((index) => !assignedReceiptRows.contains(index)).toList();

  int get missingCount => widget.plannedItems.length - assignments.length;

  Future<void> _changeMatch(ShoppingItem planned) async {
    final current = assignments[planned.id];
    final usedByOthers = assignments.entries
        .where((entry) => entry.key != planned.id)
        .map((entry) => entry.value)
        .toSet();
    final available = List.generate(
      widget.receipt.items.length,
      (index) => index,
    ).where((index) => !usedByOthers.contains(index)).toList();
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'What did you buy for this product?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.remove_shopping_cart_outlined),
              title: const Text('Not purchased'),
              subtitle: const Text('Keep it on the shopping list'),
              selected: current == null,
              onTap: () => Navigator.pop(context, -1),
            ),
            const Divider(),
            ...available.map((index) {
              final item = widget.receipt.items[index];
              return ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(item.name),
                subtitle: Text(
                  '${_quantity(item.quantity)} × ₹${item.unitPrice.toStringAsFixed(2)} · ${item.category}',
                ),
                trailing: Text(
                  '₹${item.total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                selected: current == index,
                onTap: () => Navigator.pop(context, index),
              );
            }),
          ],
        ),
      ),
    );
    if (selected == null) return;
    setState(() {
      if (selected < 0) {
        assignments.remove(planned.id);
      } else {
        assignments[planned.id] = selected;
      }
    });
  }

  Future<void> _finish() async {
    if (finishing) return;
    setState(() => finishing = true);
    final result = ShoppingReconciliation.buildResult(
      planned: widget.plannedItems,
      receipt: widget.receipt,
      assignments: assignments,
    );
    await ShoppingListStore().applyReconciliation(
      receipt: widget.receipt,
      plannedItemIds: widget.plannedItems.map((item) => item.id).toList(),
      assignments: assignments,
    );
    await Future.wait(
      widget.plannedItems
          .where((item) => assignments.containsKey(item.id))
          .map(ShoppingReminderService.instance.cancel),
    );
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _ivory,
        appBar: AppBar(title: const Text('Review this trip')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
          children: [
            const _TripProgress(),
            const SizedBox(height: 14),
            Card(
              color: _green,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.receipt.store,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _amount(
                            'Planned estimate',
                            plannedEstimate,
                            Colors.white,
                          ),
                        ),
                        Expanded(
                          child: _amount('Bill total', billTotal, _lime),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${assignments.length} matched · $missingCount still needed · ${unplannedRows.length} unplanned',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Card(
              color: CartSenseColors.surfaceMuted,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome, color: _green),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'We matched your saved list with this receipt. Check the suggestions before finishing.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _sectionTitle(Icons.checklist, 'Your planned products'),
            ...widget.plannedItems.map(_plannedCard),
            if (unplannedRows.isNotEmpty) ...[
              const SizedBox(height: 20),
              _sectionTitle(Icons.add_shopping_cart, 'Unplanned purchases'),
              ...unplannedRows.map((index) {
                final item = widget.receipt.items[index];
                return Card(
                  color: CartSenseColors.warning,
                  child: ListTile(
                    leading: CategoryAvatar(category: item.category),
                    title: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(item.category),
                    trailing: Text(
                      '₹${item.total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SafeArea(
              top: false,
              bottom: false,
              child: Container(
                color: _ivory,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    padding: const EdgeInsets.all(16),
                  ),
                  onPressed: finishing ? null : _finish,
                  icon: finishing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.done_all),
                  label: Text(
                    finishing
                        ? 'Finishing trip…'
                        : 'Finish trip · keep $missingCount on list',
                  ),
                ),
              ),
            ),
            CartSenseFooterNav(
              selectedIndex: 1,
              activeShoppingCount: widget.activeShoppingCount,
              onDestinationSelected: (index) {
                if (index == 0) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                } else if (index == 2) {
                  widget.onOpenShoppingList?.call();
                } else if (index == 3) {
                  widget.onOpenInsights?.call();
                }
              },
            ),
          ],
        ),
      );

  Widget _plannedCard(ShoppingItem planned) {
    final receiptIndex = assignments[planned.id];
    final purchased =
        receiptIndex == null ? null : widget.receipt.items[receiptIndex];
    final confidence = purchased == null
        ? 0.0
        : ShoppingReconciliation.matchScore(planned, purchased);
    final difference =
        purchased == null ? 0.0 : purchased.total - planned.estimatedTotal;
    final priceMessage = purchased == null || planned.expectedUnitPrice <= 0
        ? null
        : difference.abs() < .01
            ? 'price as expected'
            : difference > 0
                ? '₹${difference.abs().toStringAsFixed(2)} over estimate'
                : '₹${difference.abs().toStringAsFixed(2)} under estimate';
    return Card(
      color: purchased == null
          ? CartSenseColors.warning
          : confidence < .75
              ? CartSenseColors.warning
              : Colors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: purchased == null ? Colors.orange.shade100 : _lime,
          foregroundColor: _green,
          child: Icon(
            purchased == null
                ? Icons.remove_shopping_cart_outlined
                : Icons.check,
          ),
        ),
        title: Text(
          '${_quantity(planned.quantity)} × ${planned.name}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          purchased == null
              ? 'Not found on this bill · remains on your list'
              : 'Matched: ${purchased.name}\n₹${purchased.total.toStringAsFixed(2)}${priceMessage == null ? '' : ' · $priceMessage'} · ${(confidence * 100).round()}% match',
        ),
        isThreeLine: purchased != null,
        trailing: TextButton(
          onPressed: () => _changeMatch(planned),
          child: const Text('Change'),
        ),
      ),
    );
  }

  Widget _amount(String label, double value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(
            '₹${value.toStringAsFixed(2)}',
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      );

  Widget _sectionTitle(IconData icon, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, color: _green),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );
}

class _TripProgress extends StatelessWidget {
  const _TripProgress();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.format_list_bulleted, 'Plan'),
      (Icons.shopping_cart_outlined, 'Shop'),
      (Icons.document_scanner_outlined, 'Scan'),
      (Icons.fact_check_outlined, 'Review'),
    ];
    return Row(
      children: List.generate(steps.length, (index) {
        final step = steps[index];
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: index == steps.length - 1
                            ? CartSenseColors.primary
                            : CartSenseColors.success,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        index == steps.length - 1 ? step.$1 : Icons.check,
                        size: 18,
                        color: index == steps.length - 1
                            ? Colors.white
                            : CartSenseColors.primary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      step.$2,
                      style: TextStyle(
                        color: index == steps.length - 1
                            ? CartSenseColors.primary
                            : CartSenseColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (index < steps.length - 1)
                const Expanded(
                  child: Divider(color: CartSenseColors.primary),
                ),
            ],
          ),
        );
      }),
    );
  }
}

String _quantity(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();
