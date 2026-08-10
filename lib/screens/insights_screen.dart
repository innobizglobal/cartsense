import 'package:flutter/material.dart';
import '../models/receipt.dart';
import '../models/savings_intelligence.dart';
import '../services/budget_store.dart';
import '../services/language_store.dart';
import '../services/price_intelligence_api.dart';
import '../services/receipt_export.dart';
import '../services/receipt_store.dart';
import '../theme/cartsense_theme.dart';
import '../widgets/app_footer_nav.dart';
import '../widgets/category_icon.dart';

const _green = CartSenseColors.primary;
const _lime = CartSenseColors.accent;
const _ivory = CartSenseColors.background;

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({
    super.key,
    required this.receipts,
    this.activeShoppingCount = 0,
    this.onScan,
    this.onOpenShoppingList,
  });

  final List<Receipt> receipts;
  final int activeShoppingCount;
  final VoidCallback? onScan;
  final VoidCallback? onOpenShoppingList;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final _budgetStore = BudgetStore();
  final _receiptStore = ReceiptStore();
  final _priceApi = PriceIntelligenceApi();
  late List<Receipt> _receipts = widget.receipts;
  AppLanguage language = AppLanguage.english;
  double budget = 0;
  Future<List<OnlinePriceComparison>>? onlinePriceComparisons;

  SavingsIntelligence get insights =>
      SavingsIntelligence.fromReceipts(_receipts);

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _loadBudget();
    _loadReceipts();
  }

  @override
  void didUpdateWidget(covariant InsightsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receipts != widget.receipts) {
      _receipts = widget.receipts;
      _loadReceipts();
      _refreshOnlinePrices();
    }
  }

  Future<void> _loadLanguage() async {
    final saved = await LanguageStore().load();
    if (mounted) setState(() => language = saved);
  }

  String t(String key) => appText(language.code, key);

  Future<void> _loadBudget() async {
    final value = await _budgetStore.load();
    if (mounted) setState(() => budget = value);
  }

  Future<void> _loadReceipts() async {
    final receipts = await _receiptStore.load();
    if (mounted) {
      setState(() => _receipts = receipts);
      _refreshOnlinePrices();
    }
  }

  void _refreshOnlinePrices() {
    if (_receipts.isEmpty) {
      setState(() => onlinePriceComparisons = null);
      return;
    }
    setState(() {
      onlinePriceComparisons = _priceApi.compareReceiptPrices(_receipts);
    });
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

  Future<void> _showReportExportOptions() async {
    if (_receipts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Save a bill first, then CartSense can export a report.'),
      ));
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Export reports',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('Choose the format you want to share or save.'),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('CSV report'),
              subtitle: const Text('Open in Excel or Google Sheets'),
              onTap: () => Navigator.pop(context, 'csv'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Monthly PDF report'),
              subtitle: const Text('Readable summary for sharing'),
              onTap: () => Navigator.pop(context, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('WhatsApp summary'),
              subtitle: const Text('Short message with totals and categories'),
              onTap: () => Navigator.pop(context, 'text'),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('Category chart image'),
              subtitle: const Text('Share category spend as an image file'),
              onTap: () => Navigator.pop(context, 'chart'),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Full export bundle'),
              subtitle: const Text('Reports plus CartSense backup'),
              onTap: () => Navigator.pop(context, 'bundle'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final export = ReceiptExport();
    if (choice == 'csv') {
      await export.shareInsightsReport(_receipts);
    } else if (choice == 'pdf') {
      await export.shareMonthlyPdfReport(_receipts);
    } else if (choice == 'text') {
      await export.shareWhatsAppSummary(_receipts);
    } else if (choice == 'chart') {
      await export.shareCategoryChart(_receipts);
    } else if (choice == 'bundle') {
      await export.shareFullExportBundle(_receipts);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = insights;
    final budgetProgress = budget <= 0 ? 0.0 : data.currentMonthTotal / budget;
    final maximumMonth = data.monthlySpend.fold(
      0.0,
      (maximum, item) => item.total > maximum ? item.total : maximum,
    );
    final allCategoryTotals = _categoryTotals(_receipts);
    final showingAllCategories =
        data.categoryTotals.isEmpty && allCategoryTotals.isNotEmpty;
    final categorySource =
        showingAllCategories ? allCategoryTotals : data.categoryTotals;
    final categories = categorySource.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final storeTotals = _storeTotals(_receipts);
    final expensiveItems = _topExpensiveItems(_receipts);
    final monthAlerts = _monthAlerts(_receipts, budget);
    final categoryAlerts = _categoryIncreaseAlerts(_receipts);
    final dueProducts = data.frequentProducts
        .where((item) => item.isDueAt(DateTime.now()))
        .take(6)
        .toList();

    return Scaffold(
      backgroundColor: _ivory,
      appBar: AppBar(
        title: Text(t('insights')),
        actions: [
          IconButton(
            tooltip: t('exportGroceryReport'),
            onPressed: _showReportExportOptions,
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          Card(
            color: CartSenseColors.surface,
            child: ListTile(
              leading: const Icon(Icons.file_download_outlined, color: _green),
              title: Text(
                t('exportGroceryReport'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                t('exportGroceryReportBody'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showReportExportOptions,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: _green,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined,
                          color: Colors.white70, size: 19),
                      const SizedBox(width: 7),
                      Text(
                        t('grocerySpendMonth'),
                        style: const TextStyle(color: Colors.white70),
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
                              : t('setBudget'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      TextButton(
                        onPressed: _editBudget,
                        style: TextButton.styleFrom(foregroundColor: _lime),
                        child: Text(budget > 0 ? t('edit') : t('setBudget')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (monthAlerts.isNotEmpty) ...[
            _SmartInsightCard(alerts: monthAlerts),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: Icons.receipt_long_outlined,
                  label: t('savedBills'),
                  value: '${_receipts.length}',
                  color: CartSenseColors.surface,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  icon: Icons.savings_outlined,
                  label: t('possibleSaving'),
                  value: '₹${data.possibleBasketSaving.toStringAsFixed(0)}',
                  color: CartSenseColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionTitle(
            icon: Icons.auto_graph_outlined,
            title: t('spendingAlerts'),
          ),
          const SizedBox(height: 10),
          if (categoryAlerts.isEmpty)
            _EmptyCard(
              t('scanAnotherMonth'),
            )
          else
            ...categoryAlerts.take(5).map((alert) => Card(
                  color: CartSenseColors.warning,
                  child: ListTile(
                    leading: CategoryAvatar(category: alert.category),
                    title: Text(
                      categoryText(language.code, alert.category),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      'Last month ₹${alert.previous.toStringAsFixed(0)} • this month ₹${alert.current.toStringAsFixed(0)}',
                    ),
                    trailing: Text(
                      '+${alert.percent.toStringAsFixed(0)}%',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                )),
          const SizedBox(height: 20),
          _SectionTitle(
            icon: Icons.show_chart,
            title: t('spendingTrend'),
          ),
          const SizedBox(height: 10),
          if (maximumMonth == 0)
            _EmptyCard(t('saveBillsTrend'))
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
          _SectionTitle(
            icon: Icons.category_outlined,
            title: t('categorySpend'),
          ),
          Text(
            showingAllCategories ? t('allSavedBills') : t('thisMonth'),
            style: const TextStyle(color: CartSenseColors.textMuted),
          ),
          const SizedBox(height: 10),
          if (categories.isEmpty)
            _EmptyCard(t('categoriesAppear'))
          else
            _ThinScrollableCard(
              rowCount: categories.length,
              children: categories
                  .map(
                    (entry) => ListTile(
                      leading: CategoryAvatar(category: entry.key),
                      title: Text(categoryText(language.code, entry.key)),
                      trailing: Text(
                        '₹${entry.value.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 20),
          _SectionTitle(
            icon: Icons.store_mall_directory_outlined,
            title: t('storeComparison'),
          ),
          const SizedBox(height: 10),
          if (storeTotals.isEmpty)
            _EmptyCard(t('storeSpendAppears'))
          else
            ...storeTotals.take(5).map((store) => Card(
                  child: ListTile(
                    leading:
                        const Icon(Icons.storefront_outlined, color: _green),
                    title: Text(
                      store.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('${store.billCount} bills'),
                    trailing: Text(
                      '₹${store.total.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                )),
          const SizedBox(height: 20),
          _SectionTitle(
            icon: Icons.local_fire_department_outlined,
            title: t('topExpensiveProducts'),
          ),
          const SizedBox(height: 10),
          if (expensiveItems.isEmpty)
            _EmptyCard(t('productRankingAppears'))
          else
            _ThinScrollableCard(
              rowCount: expensiveItems.length,
              children: expensiveItems
                  .map(
                    (item) => ListTile(
                      leading: CategoryAvatar(category: item.category),
                      title: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${categoryText(language.code, item.category)} · bought ${item.quantity.g}',
                      ),
                      trailing: Text(
                        '₹${item.total.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 20),
          _SectionTitle(
            icon: Icons.trending_up,
            title: t('priceChanges'),
          ),
          const SizedBox(height: 10),
          if (data.priceRises.isEmpty)
            _EmptyCard(t('noPriceRises'))
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
          _SectionTitle(
            icon: Icons.trending_down,
            title: t('priceDrops'),
          ),
          const SizedBox(height: 10),
          if (data.priceDrops.isEmpty)
            _EmptyCard(t('priceDropsAppear'))
          else
            ...data.priceDrops.take(8).map((item) => Card(
                  color: CartSenseColors.success,
                  child: ListTile(
                    leading: const Icon(Icons.arrow_downward, color: _green),
                    title: Text(item.name),
                    subtitle: Text(
                      'Was ₹${item.previousPrice!.toStringAsFixed(2)} · now ₹${item.latestPrice.toStringAsFixed(2)} at ${item.latestStore}',
                    ),
                    trailing: Text(
                      '${item.priceChangePercent.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                )),
          const SizedBox(height: 20),
          _SectionTitle(
            icon: Icons.storefront_outlined,
            title: t('betterPricesNearby'),
          ),
          const SizedBox(height: 10),
          _OnlinePriceCard(
            future: onlinePriceComparisons,
            fallback: data.cheaperStoreOptions,
            onRefresh: _refreshOnlinePrices,
          ),
          if (data.cheaperStoreOptions.isEmpty &&
              onlinePriceComparisons == null) ...[
            const SizedBox(height: 8),
            _EmptyCard(
              t('scanMoreStores'),
            )
          ] else ...[
            const SizedBox(height: 8),
            ...data.cheaperStoreOptions.take(6).map((item) => Card(
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
          const SizedBox(height: 20),
          _SectionTitle(
            icon: Icons.replay_outlined,
            title: t('buyAgainSoon'),
          ),
          const SizedBox(height: 10),
          if (dueProducts.isEmpty)
            _EmptyCard(
              t('repeatedProductsAppear'),
            )
          else
            ...dueProducts.map((item) => Card(
                  child: ListTile(
                    leading: CategoryAvatar(category: item.category),
                    title: Text(item.name),
                    subtitle: Text(
                      'Usually every ${item.averageDaysBetweenPurchases} days · best ₹${item.bestPrice.toStringAsFixed(2)} at ${item.bestStore}',
                    ),
                    trailing:
                        const Icon(Icons.add_task_outlined, color: _green),
                  ),
                )),
        ],
      ),
      bottomNavigationBar: CartSenseFooterNav(
        selectedIndex: 3,
        activeShoppingCount: widget.activeShoppingCount,
        languageCode: language.code,
        onDestinationSelected: (index) {
          if (index == 0) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          } else if (index == 1) {
            widget.onScan?.call();
          } else if (index == 2) {
            widget.onOpenShoppingList?.call();
          }
        },
      ),
    );
  }
}

class _ThinScrollableCard extends StatefulWidget {
  const _ThinScrollableCard({
    required this.rowCount,
    required this.children,
  });

  final int rowCount;
  final List<Widget> children;

  @override
  State<_ThinScrollableCard> createState() => _ThinScrollableCardState();
}

class _ThinScrollableCardState extends State<_ThinScrollableCard> {
  late final ScrollController _controller = ScrollController();

  bool get _needsScroll => widget.rowCount > 5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
        child: SizedBox(
          height: _needsScroll ? 360 : null,
          child: Scrollbar(
            controller: _controller,
            thumbVisibility: _needsScroll,
            thickness: 3,
            radius: const Radius.circular(12),
            child: ListView.separated(
              controller: _controller,
              shrinkWrap: !_needsScroll,
              physics: _needsScroll
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemCount: widget.children.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => widget.children[index],
            ),
          ),
        ),
      );
}

class _SmartInsightCard extends StatelessWidget {
  const _SmartInsightCard({required this.alerts});

  final List<_MonthAlert> alerts;

  @override
  Widget build(BuildContext context) => Card(
        color: CartSenseColors.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: _green),
                  SizedBox(width: 8),
                  Text(
                    'Smart summary',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...alerts.map(
                (alert) => Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(alert.icon, color: _green, size: 20),
                      const SizedBox(width: 9),
                      Expanded(child: Text(alert.message)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
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

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        color: color,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: _green),
              const SizedBox(height: 10),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: CartSenseColors.textMuted),
              ),
            ],
          ),
        ),
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

class _OnlinePriceCard extends StatelessWidget {
  const _OnlinePriceCard({
    required this.future,
    required this.fallback,
    required this.onRefresh,
  });

  final Future<List<OnlinePriceComparison>>? future;
  final List<ProductPriceInsight> fallback;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final pending = future;
    if (pending == null) {
      return _onlineShell(
        child: ListTile(
          leading: const Icon(Icons.cloud_sync_outlined, color: _green),
          title: const Text(
            'Online price check',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: const Text(
            'Save a receipt first. CartSense will then compare your products with online prices.',
          ),
          trailing: IconButton(
            tooltip: 'Refresh online prices',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ),
      );
    }

    return FutureBuilder<List<OnlinePriceComparison>>(
      future: pending,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _onlineShell(
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud_sync_outlined, color: _green),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Checking live online prices...',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  LinearProgressIndicator(),
                ],
              ),
            ),
          );
        }

        final comparisons = snapshot.data ?? const <OnlinePriceComparison>[];
        if (snapshot.hasError || comparisons.isEmpty) {
          final message = fallback.isEmpty
              ? 'Online API is connected. Scan and save a receipt so CartSense knows which products to compare.'
              : 'No online offer beat your saved receipt prices yet. Store-to-store savings are shown below.';
          return _onlineShell(
            child: ListTile(
              leading: const Icon(Icons.wifi_tethering, color: _green),
              title: const Text(
                'Live price check ready',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(message),
              trailing: IconButton(
                tooltip: 'Refresh online prices',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ),
          );
        }

        return _onlineShell(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_tethering, color: _green),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Live online matches',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh online prices',
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              ...comparisons.map((comparison) {
                final offer = comparison.offer;
                final provider = offer.source == 'demo'
                    ? '${offer.providerLabel} · demo'
                    : offer.providerLabel;
                final priceText =
                    'Receipt: ₹${comparison.localPrice.toStringAsFixed(2)} at ${comparison.localStore}\n'
                    '$provider: ₹${offer.sellingPrice.toStringAsFixed(2)}'
                    '${offer.packSize == null ? '' : ' · ${offer.packSize}'}';
                return ListTile(
                  leading: Icon(
                    comparison.isCheaperOnline
                        ? Icons.savings_outlined
                        : Icons.shopping_bag_outlined,
                    color: _green,
                  ),
                  title: Text(
                    offer.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(priceText),
                  trailing: comparison.isCheaperOnline
                      ? Text(
                          'Save ₹${comparison.possibleSaving.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: _green,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : Text(
                          '₹${offer.sellingPrice.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _onlineShell({required Widget child}) => Card(
        color: CartSenseColors.surfaceMuted,
        child: child,
      );
}

List<_MonthAlert> _monthAlerts(List<Receipt> receipts, double budget) {
  final now = DateTime.now();
  final thisMonth = _monthTotal(receipts, now);
  final previousMonth =
      _monthTotal(receipts, DateTime(now.year, now.month - 1));
  final alerts = <_MonthAlert>[];
  if (previousMonth > 0) {
    final difference = thisMonth - previousMonth;
    final percent = (difference / previousMonth) * 100;
    alerts.add(_MonthAlert(
      percent >= 0 ? Icons.trending_up : Icons.trending_down,
      percent >= 0
          ? 'This month is ₹${difference.abs().toStringAsFixed(0)} higher than last month (+${percent.toStringAsFixed(0)}%).'
          : 'This month is ₹${difference.abs().toStringAsFixed(0)} lower than last month (${percent.toStringAsFixed(0)}%).',
    ));
  }
  if (budget > 0) {
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final projected =
        now.day == 0 ? thisMonth : thisMonth / now.day * daysInMonth;
    final basis =
        'Based on ₹${thisMonth.toStringAsFixed(0)} spent in ${now.day} day${now.day == 1 ? '' : 's'} × $daysInMonth days.';
    alerts.add(_MonthAlert(
      projected > budget
          ? Icons.warning_amber_rounded
          : Icons.verified_outlined,
      projected > budget
          ? 'Projected monthly spend is ₹${projected.toStringAsFixed(0)}, about ₹${(projected - budget).toStringAsFixed(0)} over budget. $basis'
          : 'Projected monthly spend is ₹${projected.toStringAsFixed(0)}, within your ₹${budget.toStringAsFixed(0)} budget. $basis',
    ));
  }
  return alerts;
}

double _monthTotal(List<Receipt> receipts, DateTime month) => receipts
    .where((receipt) =>
        receipt.purchasedAt.year == month.year &&
        receipt.purchasedAt.month == month.month)
    .fold(0.0, (total, receipt) => total + receipt.calculatedTotal);

List<_CategoryAlert> _categoryIncreaseAlerts(List<Receipt> receipts) {
  final now = DateTime.now();
  final current = _categoryTotalsForMonth(receipts, now);
  final previous = _categoryTotalsForMonth(
    receipts,
    DateTime(now.year, now.month - 1),
  );
  final alerts = <_CategoryAlert>[];
  for (final entry in current.entries) {
    final old = previous[entry.key] ?? 0;
    if (old <= 0 || entry.value <= old) continue;
    final percent = ((entry.value - old) / old) * 100;
    if (percent < 20 && entry.value - old < 100) continue;
    alerts.add(_CategoryAlert(entry.key, old, entry.value, percent));
  }
  alerts.sort((a, b) => b.percent.compareTo(a.percent));
  return alerts;
}

Map<String, double> _categoryTotalsForMonth(
  List<Receipt> receipts,
  DateTime month,
) {
  final filtered = receipts.where((receipt) =>
      receipt.purchasedAt.year == month.year &&
      receipt.purchasedAt.month == month.month);
  final totals = <String, double>{};
  for (final receipt in filtered) {
    for (final item in receipt.items) {
      totals[item.category] = (totals[item.category] ?? 0) + item.total;
    }
  }
  return totals;
}

class _MonthAlert {
  const _MonthAlert(this.icon, this.message);

  final IconData icon;
  final String message;
}

class _CategoryAlert {
  const _CategoryAlert(
      this.category, this.previous, this.current, this.percent);

  final String category;
  final double previous;
  final double current;
  final double percent;
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

List<_StoreSpend> _storeTotals(List<Receipt> receipts) {
  final stores = <String, _StoreSpend>{};
  for (final receipt in receipts) {
    final name = receipt.store.trim().isEmpty ? 'Unknown store' : receipt.store;
    final current = stores[name] ?? _StoreSpend(name, 0, 0);
    stores[name] = _StoreSpend(
      name,
      current.total + receipt.calculatedTotal,
      current.billCount + 1,
    );
  }
  return stores.values.toList()..sort((a, b) => b.total.compareTo(a.total));
}

Map<String, double> _categoryTotals(List<Receipt> receipts) {
  final categories = <String, double>{};
  for (final receipt in receipts) {
    for (final item in receipt.items) {
      final category =
          item.category.trim().isEmpty ? GroceryCategory.other : item.category;
      categories.update(
        category,
        (value) => value + item.total,
        ifAbsent: () => item.total,
      );
    }
  }
  return categories;
}

List<_ProductSpend> _topExpensiveItems(List<Receipt> receipts) {
  final items = <String, _ProductSpend>{};
  for (final receipt in receipts) {
    for (final item in receipt.items) {
      final key = normalizedProductName(item.name);
      if (key.length < 2) continue;
      final current =
          items[key] ?? _ProductSpend(item.name, item.category, 0, 0);
      items[key] = _ProductSpend(
        item.name,
        item.category,
        current.total + item.total,
        current.quantity + item.quantity,
      );
    }
  }
  final ranked = items.values.toList()
    ..sort((a, b) => b.total.compareTo(a.total));
  if (ranked.isEmpty) return ranked;
  final threshold = (ranked.first.total * .1).clamp(75, double.infinity);
  final focused =
      ranked.where((item) => item.total >= threshold).take(12).toList();
  return focused.isEmpty ? ranked.take(8).toList() : focused;
}

class _StoreSpend {
  const _StoreSpend(this.name, this.total, this.billCount);

  final String name;
  final double total;
  final int billCount;
}

class _ProductSpend {
  const _ProductSpend(this.name, this.category, this.total, this.quantity);

  final String name;
  final String category;
  final double total;
  final double quantity;
}

extension on double {
  String get g => this == roundToDouble()
      ? toStringAsFixed(0)
      : toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
}
