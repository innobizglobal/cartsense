import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'demo_receipt.dart';
import 'models/receipt.dart';
import 'models/savings_intelligence.dart';
import 'models/shopping_item.dart';
import 'models/shopping_trip.dart';
import 'models/spending_insights.dart';
import 'screens/account_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/product_master_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shopping_list_screen.dart';
import 'screens/shopping_reconciliation_screen.dart';
import 'services/receipt_export.dart';
import 'services/ai_receipt_service.dart';
import 'services/family_profile_store.dart';
import 'services/language_store.dart';
import 'services/product_memory_store.dart';
import 'services/receipt_parser.dart';
import 'services/receipt_store.dart';
import 'services/shopping_list_store.dart';
import 'theme/cartsense_theme.dart';
import 'widgets/app_footer_nav.dart';
import 'widgets/category_icon.dart';
import 'services/auth_service.dart';
import 'services/cloud_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CartSenseAuthService.initialize();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: CartSenseColors.surface,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const CartSenseApp());
}

const green = CartSenseColors.primary;
const lime = CartSenseColors.accent;
const ivory = CartSenseColors.background;

class CartSenseApp extends StatelessWidget {
  const CartSenseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'CartSense',
        theme: buildCartSenseTheme(),
        home: const OnboardingGate(),
      );
}

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  late Future<_StartupStep> startupStep;
  StreamSubscription? authSubscription;

  @override
  void initState() {
    super.initState();
    startupStep = _loadStartupStep();
    authSubscription = CartSenseAuthService.instance.authStateChanges.listen(
      (_) {
        CartSenseCloudSyncService.instance.syncInBackground();
        _reloadStartupStep();
      },
    );
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    super.dispose();
  }

  void _reloadStartupStep() {
    if (!mounted) return;
    setState(() {
      startupStep = _loadStartupStep();
    });
  }

  Future<_StartupStep> _loadStartupStep() async {
    if (CartSenseAuthService.isConfigured &&
        CartSenseAuthService.instance.currentUser == null) {
      return _StartupStep.login;
    }
    CartSenseCloudSyncService.instance.syncInBackground();

    final preferences = await SharedPreferences.getInstance();
    final guidedTourAcknowledged =
        preferences.getBool('cartsense_guided_tour_acknowledged_v2') == true;
    if (!guidedTourAcknowledged) return _StartupStep.onboarding;

    final onboardingComplete =
        preferences.getBool('cartsense_onboarding_complete') == true;
    if (!onboardingComplete) return _StartupStep.onboarding;

    final familyPrompted =
        preferences.getBool('cartsense_family_profile_prompted_v1') == true;
    if (familyPrompted) return _StartupStep.home;

    final familyProfile = await FamilyProfileStore().load();
    return familyProfile.isConfigured
        ? _StartupStep.home
        : _StartupStep.onboarding;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_StartupStep>(
        future: startupStep,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          switch (snapshot.data!) {
            case _StartupStep.login:
              return AccountScreen(
                startupMode: true,
                onSignedIn: _reloadStartupStep,
              );
            case _StartupStep.onboarding:
              return OnboardingScreen(onFinished: _reloadStartupStep);
            case _StartupStep.home:
              return const HomeScreen();
          }
        },
      );
}

enum _StartupStep { login, onboarding, home }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final picker = ImagePicker();
  final parser = ReceiptParser();
  final aiService = AiReceiptService();
  final store = ReceiptStore();
  final searchController = TextEditingController();
  final homeScrollController = ScrollController();
  final billsSectionKey = GlobalKey();
  List<Receipt> history = [];
  int activeShoppingCount = 0;
  bool busy = false;
  bool usingAi = false;
  double scanProgress = 0;
  String scanStage = 'Preparing receipt...';
  Timer? scanTimer;
  String query = '';
  AppLanguage language = AppLanguage.english;
  String userName = '';

  SpendingInsights get monthlyInsights => SpendingInsights.forMonth(history);
  double get totalPaid =>
      history.fold(0, (sum, receipt) => sum + receipt.calculatedTotal);
  double get totalSavings => history.fold(
        0,
        (sum, receipt) =>
            sum +
            receipt.billDiscount +
            receipt.items.fold(0, (itemSum, item) => itemSum + item.discount),
      );
  bool get showMonthlySummaryCard => false;
  bool get showHomeBillsPreview => false;

  List<Receipt> get filteredHistory {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return history;
    return history
        .where((receipt) =>
            receipt.store.toLowerCase().contains(needle) ||
            receipt.items.any((item) =>
                item.name.toLowerCase().contains(needle) ||
                item.category.toLowerCase().contains(needle)))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadLanguage();
    _loadUserName();
  }

  @override
  void dispose() {
    scanTimer?.cancel();
    searchController.dispose();
    homeScrollController.dispose();
    super.dispose();
  }

  void _startScanProgress({required bool aiEnhanced}) {
    scanTimer?.cancel();
    final stages = aiEnhanced
        ? const [
            'Uploading securely...',
            'Finding the receipt edges...',
            'Reading product rows...',
            'Checking quantities and prices...',
            'Matching totals...',
            'Removing repeated overlap rows...',
            'Final AI cleanup...',
            'Preparing your bill review...',
          ]
        : const [
            'Opening photo on this phone...',
            'Finding receipt text...',
            'Reading product rows...',
            'Checking prices...',
            'Preparing your bill review...',
          ];
    var tick = 0;
    setState(() {
      busy = true;
      usingAi = aiEnhanced;
      scanProgress = .04;
      scanStage = stages.first;
    });
    scanTimer = Timer.periodic(const Duration(milliseconds: 520), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      tick += 1;
      final ceiling = aiEnhanced ? .98 : .90;
      final next =
          (scanProgress + (aiEnhanced ? .035 : .07)).clamp(0.0, ceiling);
      final stageIndex = ((next / ceiling) * stages.length)
          .floor()
          .clamp(0, stages.length - 1);
      setState(() {
        scanProgress = next;
        scanStage = stages[stageIndex];
      });
      if (tick > 36) {
        setState(() {
          scanStage = aiEnhanced
              ? 'Final AI cleanup — checking totals and duplicates...'
              : 'Still reading on this device...';
        });
      }
    });
  }

  void _finishScanProgress() {
    scanTimer?.cancel();
    scanTimer = null;
    if (!mounted) return;
    setState(() {
      scanProgress = 1;
      scanStage = 'Receipt scanned';
    });
  }

  Future<void> _refresh() async {
    final items = await store.load();
    final shoppingItems = await ShoppingListStore().load();
    if (mounted) {
      setState(() {
        history = items;
        activeShoppingCount =
            shoppingItems.where((item) => !item.checked).length;
      });
    }
  }

  Future<void> _loadLanguage() async {
    final saved = await LanguageStore().load();
    if (mounted) setState(() => language = saved);
  }

  Future<void> _loadUserName() async {
    final preferences = await SharedPreferences.getInstance();
    final savedName = preferences.getString('cartsense_user_name_v1') ?? '';
    final authName = CartSenseAuthService.instance.currentUserDisplayName;
    final displayName = savedName.trim().isNotEmpty ? savedName : authName;
    if (mounted) setState(() => userName = displayName.trim());
  }

  String t(String key) => appText(language.code, key);

  Future<void> _chooseLanguage() async {
    final selected = await showModalBottomSheet<AppLanguage>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.translate_outlined),
              title: Text('Choose language / भाषा / భాష'),
              subtitle: Text('English, Hindi and Telugu starter support.'),
            ),
            ...AppLanguage.values.map(
              (option) => ListTile(
                leading: Icon(
                  option.code == language.code
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: option.code == language.code ? green : null,
                ),
                title: Text(option.nativeName),
                subtitle: Text(option.name),
                onTap: () => Navigator.pop(context, option),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await LanguageStore().save(selected);
    if (!mounted) return;
    setState(() => language = selected);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${t('languageChanged')}: ${selected.nativeName}.'),
    ));
  }

  Future<bool> _confirmAiConsent() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool('cartsense_ai_consent') == true) return true;
    if (!mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('useAiEnhancedScan')),
        content: Text(t('aiConsentBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('notNow')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('agreeContinue')),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await preferences.setBool('cartsense_ai_consent', true);
      return true;
    }
    return false;
  }

  Future<void> _capture(
    ImageSource source, {
    bool aiEnhanced = false,
    bool reconcileAfterScan = false,
  }) async {
    if (aiEnhanced && !aiService.isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('aiScanUnavailable')),
        ));
      }
      return;
    }
    if (aiEnhanced && !await _confirmAiConsent()) return;
    final image = await picker.pickImage(
      source: source,
      imageQuality: aiEnhanced ? 78 : 92,
      maxWidth: aiEnhanced ? 1800 : 2400,
      maxHeight: aiEnhanced ? 3600 : null,
    );
    if (image == null || !mounted) return;
    if (aiEnhanced && !await _reviewReceiptPhoto(image.path)) return;
    _startScanProgress(aiEnhanced: aiEnhanced);
    try {
      final file = File(image.path);
      final receipt =
          aiEnhanced ? await aiService.parse(file) : await parser.parse(file);
      await ProductMemoryStore().applyToReceipt(receipt);
      _finishScanProgress();
      if (mounted) {
        if (reconcileAfterScan) {
          await _openReconciliationForReceipt(receipt);
        } else {
          await _open(receipt);
        }
      }
    } catch (error) {
      if (mounted) {
        final message = error is AiReceiptException
            ? error.message
            : error is FormatException
                ? error.message.toString()
                : error is PlatformException
                    ? 'On-device reader error ${error.code}: ${error.message ?? 'unknown error'}'
                    : 'The bill could not be read. Please try another photo.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) {
        scanTimer?.cancel();
        setState(() {
          busy = false;
          usingAi = false;
          scanProgress = 0;
          scanStage = 'Preparing receipt...';
        });
      }
    }
  }

  Future<bool> _reviewReceiptPhoto(String imagePath) async {
    if (!mounted) return false;
    return await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => ReceiptCaptureReviewScreen(imagePath: imagePath),
          ),
        ) ??
        false;
  }

  Future<void> _captureLongReceipt({bool reconcileAfterScan = false}) async {
    if (!aiService.isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('aiScanUnavailable')),
        ));
      }
      return;
    }
    if (!await _confirmAiConsent()) return;
    if (!mounted) return;
    final paths = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const LongReceiptCaptureScreen(),
      ),
    );
    if (paths == null || paths.isEmpty || !mounted) return;
    _startScanProgress(aiEnhanced: true);
    try {
      final receipt = _removeLikelyOverlapDuplicates(
        await aiService.parseImages(paths.map((path) => File(path)).toList()),
      );
      await ProductMemoryStore().applyToReceipt(receipt);
      _finishScanProgress();
      if (mounted) {
        if (reconcileAfterScan) {
          await _openReconciliationForReceipt(receipt);
        } else {
          await _open(receipt);
        }
      }
    } catch (error) {
      if (mounted) {
        final message = error is AiReceiptException
            ? error.message
            : 'The long bill could not be read. Retake clearer sections with overlap.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) {
        scanTimer?.cancel();
        setState(() {
          busy = false;
          usingAi = false;
          scanProgress = 0;
          scanStage = 'Preparing receipt...';
        });
      }
    }
  }

  Future<void> _showPrivateScanOptions(
      {bool reconcileAfterScan = false}) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(t('privateReader'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(t('photoStaysPhone')),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: Text(t('takePhoto')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(t('chooseGallery')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null && mounted) {
      await _capture(source, reconcileAfterScan: reconcileAfterScan);
    }
  }

  Receipt _removeLikelyOverlapDuplicates(Receipt receipt) {
    final seen = <String>{};
    final cleaned = <ReceiptItem>[];
    var removed = 0;
    for (final item in receipt.items) {
      final key = [
        normalizedProductName(item.name),
        item.quantity.toStringAsFixed(3),
        item.unitPrice.toStringAsFixed(2),
        item.discount.toStringAsFixed(2),
        item.total.toStringAsFixed(2),
      ].join('|');
      if (key.trim().isEmpty || !seen.add(key)) {
        removed += 1;
        continue;
      }
      cleaned.add(item);
    }
    if (removed > 0) {
      receipt.items = cleaned;
      receipt.warnings = [
        ...receipt.warnings,
        'Removed $removed repeated row${removed == 1 ? '' : 's'} likely caused by overlapping long-bill photos.',
      ];
    }
    return receipt;
  }

  Future<void> _openReconciliationForReceipt(Receipt receipt) async {
    await ProductMemoryStore().applyToReceipt(receipt);
    await ReceiptStore().save(receipt);
    final shoppingItems = await ShoppingListStore().load();
    final plannedItems = shoppingItems
        .where((item) => item.reconciledReceiptId == null)
        .toList();
    if (!mounted) return;
    if (plannedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('billSavedPlanFirst')),
      ));
      await _open(receipt);
      return;
    }
    final result = await Navigator.of(context).push<ShoppingTripResult>(
      MaterialPageRoute(
        builder: (_) => ShoppingReconciliationScreen(
          receipt: receipt,
          plannedItems: plannedItems,
          activeShoppingCount: activeShoppingCount,
          onOpenShoppingList: _openShoppingAssistant,
          onOpenInsights: _openInsights,
        ),
      ),
    );
    if (result == null || !mounted) {
      await _refresh();
      return;
    }
    receipt.shoppingTrip = result;
    await ReceiptStore().save(receipt);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '${t('checkoutChecked')}: ${result.matches.length} ${t('bought')}, ${result.missing.length} ${t('stillOnList')}, ${result.unplanned.length} ${t('extra')}.',
      ),
    ));
  }

  Future<void> _showCheckoutScanOptions(
      {bool reconcileAfterScan = false}) async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                t('howScanBill'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(t('chooseEasiestBillOption')),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(t('takePhotoOfBill')),
              subtitle: Text(t('normalGroceryBill')),
              onTap: () => Navigator.pop(context, 'ai_camera'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(t('longBillManyPhotos')),
              subtitle: Text(t('forLongGroceryBills')),
              onTap: () => Navigator.pop(context, 'ai_long'),
            ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: Text(t('chooseFromGallery')),
              subtitle: Text(t('existingBillPhoto')),
              onTap: () => Navigator.pop(context, 'ai_gallery'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selection == null) return;
    if (selection == 'ai_camera') {
      await _capture(
        ImageSource.camera,
        aiEnhanced: true,
        reconcileAfterScan: reconcileAfterScan,
      );
    } else if (selection == 'ai_gallery') {
      await _capture(
        ImageSource.gallery,
        aiEnhanced: true,
        reconcileAfterScan: reconcileAfterScan,
      );
    } else if (selection == 'ai_long') {
      await _captureLongReceipt(reconcileAfterScan: reconcileAfterScan);
    } else {
      await _showPrivateScanOptions(reconcileAfterScan: reconcileAfterScan);
    }
  }

  Future<void> _open(Receipt receipt) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReceiptScreen(
        receipt: receipt,
        history: history,
        activeShoppingCount: activeShoppingCount,
        onScan: _showCheckoutScanOptions,
        onOpenShoppingList: _openShoppingAssistant,
        onOpenInsights: _openInsights,
        onOpenBills: _openBills,
      ),
    ));
    await _refresh();
  }

  Future<void> _openInsights() async {
    await _refresh();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InsightsScreen(
        receipts: history,
        activeShoppingCount: activeShoppingCount,
        onScan: _showCheckoutScanOptions,
        onOpenShoppingList: _openShoppingAssistant,
        onOpenBills: _openBills,
      ),
    ));
  }

  Future<void> _openBills() async {
    await _refresh();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MyBillsScreen(
        receipts: history,
        activeShoppingCount: activeShoppingCount,
        onOpenReceipt: _open,
        languageCode: language.code,
        onScan: _showCheckoutScanOptions,
        onOpenShoppingList: _openShoppingAssistant,
        onOpenInsights: _openInsights,
      ),
    ));
    await _refresh();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const SettingsScreen(),
    ));
    await _refresh();
    await _loadLanguage();
    await _loadUserName();
  }

  Future<void> _openAccount() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const AccountScreen(),
    ));
    await _refresh();
    await _loadUserName();
  }

  Future<void> _openProductMaster() async {
    await _refresh();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProductMasterScreen(
        receipts: history,
        activeShoppingCount: activeShoppingCount,
        onScan: _showCheckoutScanOptions,
        onOpenShoppingList: _openShoppingAssistant,
        onOpenInsights: _openInsights,
      ),
    ));
    await _refresh();
  }

  Future<void> _openShoppingAssistant() async {
    final scanNow = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ShoppingListScreen(
        receipts: history,
        activeShoppingCount: activeShoppingCount,
        onOpenInsights: _openInsights,
        onOpenBills: _openBills,
      ),
    ));
    await _refresh();
    if (scanNow == true && mounted) {
      await _showCheckoutScanOptions(reconcileAfterScan: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          title: Row(
            children: [
              const _BrandMark(),
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CartSense'),
                  Text(
                    userName.isEmpty
                        ? t('smartGroceryCompanion')
                        : '${t('hello')} $userName',
                    style: const TextStyle(
                      color: CartSenseColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: t('language'),
              onPressed: _chooseLanguage,
              icon: const Icon(Icons.translate_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: t('moreOptions'),
              onSelected: (value) {
                if (value == 'account') {
                  _openAccount();
                } else if (value == 'private') {
                  _showPrivateScanOptions();
                } else if (value == 'demo') {
                  _open(createDemoReceipt());
                } else if (value == 'settings') {
                  _openSettings();
                } else if (value == 'products') {
                  _openProductMaster();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'account',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(t('account')),
                    subtitle: Text(CartSenseAuthService.isConfigured
                        ? t('guestOrCloudSync')
                        : t('guestMode')),
                  ),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.settings_outlined),
                    title: Text(t('settings')),
                  ),
                ),
                const PopupMenuItem(
                  value: 'products',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.inventory_2_outlined),
                    title: Text('Product memory'),
                  ),
                ),
                PopupMenuItem(
                  value: 'private',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_outline),
                    title: Text(t('privateScan')),
                  ),
                ),
                PopupMenuItem(
                  value: 'demo',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.science_outlined),
                    title: Text(t('openSampleReceipt')),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: busy
            ? ReceiptScanProgressView(
                progress: scanProgress,
                stage: scanStage,
                aiEnhanced: usingAi,
              )
            : SafeArea(
                child: ListView(
                  controller: homeScrollController,
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                  children: [
                    _CommercialGreetingCard(
                      userName: userName,
                      totalPaid: totalPaid,
                      totalSavings: totalSavings,
                      billCount: history.length,
                      languageCode: language.code,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF064A72),
                            CartSenseColors.primaryDark,
                            green,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33145A43),
                            blurRadius: 22,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const _HeroIcon(),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t('scanYourBill'),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        height: 1.1,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      t('readItemsPricesTotal'),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              _HeroPill(
                                icon: Icons.savings_outlined,
                                label:
                                    '${t('saved')} ₹${totalSavings.toStringAsFixed(0)}',
                              ),
                              const SizedBox(width: 8),
                              _HeroPill(
                                icon: Icons.receipt_long_outlined,
                                label: '${history.length} bills',
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                  backgroundColor: lime,
                                  foregroundColor: green,
                                  padding: const EdgeInsets.all(16)),
                              onPressed: _showCheckoutScanOptions,
                              icon: const Icon(Icons.document_scanner),
                              label: Text(t('scanNow'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.shield_outlined,
                                  size: 16, color: Colors.white70),
                              const SizedBox(width: 6),
                              Text(
                                t('chooseAiOrPrivate'),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      t('whatDoYouWant'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _HomeFeatureButton(
                            icon: Icons.shopping_basket_outlined,
                            title: t('shoppingList'),
                            subtitle: activeShoppingCount == 0
                                ? t('planTodayItems')
                                : '$activeShoppingCount ${t('itemsToBuy')}',
                            onTap: _openShoppingAssistant,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _HomeFeatureButton(
                            icon: Icons.receipt_long_outlined,
                            title: t('myBills'),
                            subtitle: history.isEmpty
                                ? t('viewSavedBills')
                                : '${history.length} ${t('billsSaved')}',
                            onTap: _openBills,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _HomeFeatureButton(
                      icon: Icons.insights_outlined,
                      title: t('mySpend'),
                      subtitle: monthlyInsights.billCount == 0
                          ? t('seeWhereMoneyGoes')
                          : 'This month ₹${monthlyInsights.total.toStringAsFixed(0)}',
                      onTap: _openInsights,
                    ),
                    if (showMonthlySummaryCard &&
                        monthlyInsights.billCount > 0) ...[
                      const SizedBox(height: 18),
                      Card(
                        color: CartSenseColors.surfaceMuted,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.insights_outlined,
                                      color: green),
                                  const SizedBox(width: 8),
                                  Text(
                                    t('thisMonth'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '₹${monthlyInsights.total.toStringAsFixed(2)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      color: green,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              Text(
                                '${monthlyInsights.billCount} saved ${monthlyInsights.billCount == 1 ? 'bill' : 'bills'}',
                              ),
                              if (monthlyInsights.topCategory != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Top category: ${monthlyInsights.topCategory} · ₹${monthlyInsights.topCategoryTotal.toStringAsFixed(2)}',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (showHomeBillsPreview) ...[
                      const SizedBox(height: 26),
                      _HomeSectionTitle(
                        t('myBills'),
                        key: billsSectionKey,
                        trailing:
                            history.isEmpty ? null : '${history.length} saved',
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (showHomeBillsPreview && history.isNotEmpty) ...[
                      TextField(
                        controller: searchController,
                        onChanged: (value) => setState(() => query = value),
                        decoration: InputDecoration(
                          hintText: t('searchStoresItems'),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: t('clearSearch'),
                                  onPressed: () {
                                    searchController.clear();
                                    setState(() => query = '');
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (showHomeBillsPreview && history.isEmpty)
                      _HomeEmptyState(
                        languageCode: language.code,
                        onScan: _showCheckoutScanOptions,
                        onPlan: _openShoppingAssistant,
                        onDemo: () => _open(createDemoReceipt()),
                      )
                    else if (showHomeBillsPreview && filteredHistory.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(t('noSavedBillsMatch')),
                        ),
                      )
                    else if (showHomeBillsPreview)
                      ...filteredHistory.map((receipt) => _BillSavingsCard(
                                receipt: receipt,
                                languageCode: language.code,
                                onTap: () => _open(receipt),
                              ) /*Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(
                                14,
                                7,
                                10,
                                7,
                              ),
                              onTap: () => _open(receipt),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: CartSenseColors.success,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.receipt_long_outlined,
                                  color: green,
                                ),
                              ),
                              title: Text(
                                receipt.store,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                '${receipt.items.length} products · ${_shortDate(receipt.purchasedAt)}${receipt.shoppingTrip == null ? '' : ' · reconciled'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '₹${receipt.calculatedTotal.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: CartSenseColors.textMuted,
                                  ),
                                ],
                              ),
                            ),
                          )*/
                          ),
                  ],
                ),
              ),
        bottomNavigationBar: CartSenseFooterNav(
          selectedIndex: 0,
          activeShoppingCount: activeShoppingCount,
          languageCode: language.code,
          onDestinationSelected: (index) {
            if (index == 1) {
              _openShoppingAssistant();
            } else if (index == 2) {
              _showCheckoutScanOptions();
            } else if (index == 3) {
              _openBills();
            } else if (index == 4) {
              _openInsights();
            }
          },
        ),
      );
}

class LongReceiptCaptureScreen extends StatefulWidget {
  const LongReceiptCaptureScreen({super.key});

  @override
  State<LongReceiptCaptureScreen> createState() =>
      _LongReceiptCaptureScreenState();
}

class _LongReceiptCaptureScreenState extends State<LongReceiptCaptureScreen> {
  final picker = ImagePicker();
  final parts = <String>[];
  bool picking = false;

  Future<void> _addPart(ImageSource source) async {
    if (picking || parts.length >= 4) return;
    setState(() => picking = true);
    try {
      final image = await picker.pickImage(
        source: source,
        imageQuality: 78,
        maxWidth: 1800,
        maxHeight: 2600,
      );
      if (image != null && mounted) {
        setState(() => parts.add(image.path));
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  void _removePart(int index) {
    setState(() => parts.removeAt(index));
  }

  void _movePart(int index, int direction) {
    final target = index + direction;
    if (target < 0 || target >= parts.length) return;
    setState(() {
      final item = parts.removeAt(index);
      parts.insert(target, item);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: CartSenseColors.surface,
        appBar: AppBar(
          title: const Text('Long bill scan'),
          actions: [
            TextButton(
              onPressed: parts.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(List<String>.from(parts)),
              child: const Text('Scan'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: CartSenseColors.primaryDark,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          color: CartSenseColors.accent,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Capture in order: top → middle → bottom',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Each photo should overlap the previous section by a few rows. Make sure the final photo includes the printed total.',
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: picking || parts.length >= 4
                                ? null
                                : () => _addPart(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: Text(parts.isEmpty
                                ? 'Add top photo'
                                : 'Add next photo'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          tooltip: 'Choose from gallery',
                          onPressed: picking || parts.length >= 4
                              ? null
                              : () => _addPart(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (parts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Icon(
                        Icons.add_a_photo_outlined,
                        size: 38,
                        color: green,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'No sections added yet',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Start with the top of the receipt and continue downward.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: CartSenseColors.textMuted),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...List.generate(parts.length, (index) {
                final label = index == 0
                    ? 'Top section'
                    : index == parts.length - 1
                        ? 'Bottom / total section'
                        : 'Middle section';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(
                            File(parts[index]),
                            width: 74,
                            height: 96,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Photo ${index + 1}: $label',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                index == parts.length - 1
                                    ? 'Must include the final payable total.'
                                    : 'Overlap a few rows with the next photo.',
                                style: const TextStyle(
                                  color: CartSenseColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            IconButton(
                              tooltip: 'Move up',
                              onPressed: index == 0
                                  ? null
                                  : () => _movePart(index, -1),
                              icon: const Icon(Icons.keyboard_arrow_up),
                            ),
                            IconButton(
                              tooltip: 'Move down',
                              onPressed: index == parts.length - 1
                                  ? null
                                  : () => _movePart(index, 1),
                              icon: const Icon(Icons.keyboard_arrow_down),
                            ),
                          ],
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () => _removePart(index),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: parts.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(List<String>.from(parts)),
              icon: const Icon(Icons.auto_awesome),
              label: Text(parts.length == 1
                  ? 'Scan 1 section'
                  : 'Scan ${parts.length} sections together'),
            ),
          ],
        ),
      );
}

class ReceiptCaptureReviewScreen extends StatelessWidget {
  const ReceiptCaptureReviewScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: CartSenseColors.primaryDark,
        appBar: AppBar(
          title: const Text('Check receipt photo'),
          backgroundColor: CartSenseColors.primaryDark,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        InteractiveViewer(
                          minScale: .8,
                          maxScale: 4,
                          child: Image.file(
                            File(imagePath),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Text(
                                'Could not open this receipt photo.',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: CartSenseColors.accent,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                decoration: const BoxDecoration(
                  color: CartSenseColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Ready for AI cleanup',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'For best accuracy, make sure the full receipt is visible, not clipped, and the printed rows are readable. Pinch to check before scanning.',
                      style: TextStyle(
                        color: CartSenseColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: Icon(Icons.crop_free, size: 18),
                          label: Text('Full bill visible'),
                        ),
                        Chip(
                          avatar: Icon(Icons.straighten, size: 18),
                          label: Text('Rows readable'),
                        ),
                        Chip(
                          avatar: Icon(Icons.auto_awesome, size: 18),
                          label: Text('AI will clean up'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: const Text('Use photo and scan'),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Retake or choose another'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class ReceiptScanProgressView extends StatefulWidget {
  const ReceiptScanProgressView({
    super.key,
    required this.progress,
    required this.stage,
    required this.aiEnhanced,
  });

  final double progress;
  final String stage;
  final bool aiEnhanced;

  @override
  State<ReceiptScanProgressView> createState() =>
      _ReceiptScanProgressViewState();
}

class _ReceiptScanProgressViewState extends State<ReceiptScanProgressView>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final percent = (widget.progress.clamp(0.0, 1.0) * 100).round();
    return SafeArea(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3F6F9D), CartSenseColors.primaryDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CartSense',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.aiEnhanced
                  ? 'AI is scanning your receipt'
                  : 'Private reader is scanning',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.aiEnhanced
                  ? 'Finding grocery items, prices, discounts and totals.'
                  : 'Reading receipt text on this phone only.',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                height: 1.35,
              ),
            ),
            const Spacer(),
            Center(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, child) {
                  final beamTop = 34 + controller.value * 250;
                  return Transform.rotate(
                    angle: -.22,
                    child: Container(
                      width: 230,
                      height: 330,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 28,
                            offset: Offset(0, 18),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(
                          children: [
                            Container(
                              color: const Color(0xFFEFE8D8),
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 92,
                                    height: 12,
                                    color: Colors.black87,
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: 132,
                                    height: 8,
                                    color: Colors.black54,
                                  ),
                                  const SizedBox(height: 18),
                                  ...List.generate(
                                    10,
                                    (index) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: index.isEven ? 6 : 4,
                                            child: Container(
                                              height: 7,
                                              color: Colors.black54,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Container(
                                            width: 42,
                                            height: 7,
                                            color: Colors.black54,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    width: double.infinity,
                                    height: 2,
                                    color: Colors.black45,
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Container(
                                      width: 84,
                                      height: 13,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              top: beamTop,
                              left: -30,
                              right: -30,
                              child: Container(
                                height: 72,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.red.withValues(alpha: 0),
                                      Colors.red.withValues(alpha: .28),
                                      Colors.red.withValues(alpha: 0),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Container(
                                    height: 7,
                                    color: const Color(0xFFFF2E2E),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: widget.progress.clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: Colors.white.withValues(alpha: .22),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          CartSenseColors.accent),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  widget.aiEnhanced ? Icons.auto_awesome : Icons.lock_outline,
                  color: CartSenseColors.accent,
                  size: 19,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.stage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: green,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.shopping_bag_outlined,
            color: Colors.white, size: 21),
      );
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon();

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.receipt_long_outlined,
            color: Colors.white, size: 28),
      );
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _CommercialGreetingCard extends StatelessWidget {
  const _CommercialGreetingCard({
    required this.userName,
    required this.totalPaid,
    required this.totalSavings,
    required this.billCount,
    required this.languageCode,
  });

  final String userName;
  final double totalPaid;
  final double totalSavings;
  final int billCount;
  final String languageCode;

  String t(String key) => appText(languageCode, key);

  @override
  Widget build(BuildContext context) {
    final greetingName = userName.isEmpty ? t('there') : userName;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CartSenseColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: CartSenseColors.outline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140B3D2D),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: CartSenseColors.success,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.waving_hand_outlined,
                  color: CartSenseColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t('hello')} $greetingName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      t('makeShoppingEasier'),
                      style: const TextStyle(
                        color: CartSenseColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeSectionTitle extends StatelessWidget {
  const _HomeSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(
                color: CartSenseColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      );
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState({
    required this.languageCode,
    required this.onScan,
    required this.onPlan,
    required this.onDemo,
  });

  final String languageCode;
  final VoidCallback onScan;
  final VoidCallback onPlan;
  final VoidCallback onDemo;

  String t(String key) => appText(languageCode, key);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: CartSenseColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    color: green, size: 30),
              ),
              const SizedBox(height: 14),
              Text(
                t('noReceiptsYet'),
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                t('scanFirstReceiptBody'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: CartSenseColors.textMuted),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.document_scanner_outlined),
                label: Text(t('scanBill')),
              ),
            ],
          ),
        ),
      );
}

class _HomeFeatureButton extends StatelessWidget {
  const _HomeFeatureButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: CartSenseColors.success,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: green),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CartSenseColors.textMuted,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _BillSavingsCard extends StatelessWidget {
  const _BillSavingsCard({
    required this.receipt,
    required this.onTap,
    this.languageCode = 'en',
  });

  final Receipt receipt;
  final VoidCallback onTap;
  final String languageCode;

  String t(String key) => appText(languageCode, key);

  double get savings =>
      receipt.billDiscount +
      receipt.items.fold(0, (sum, item) => sum + item.discount);

  String get invoiceNo {
    final compact = receipt.id.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    if (compact.length <= 8) return compact;
    return compact.substring(compact.length - 8);
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${t('invoiceNo')}: $invoiceNo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      _shortDate(receipt.purchasedAt),
                      style: const TextStyle(
                        color: CartSenseColors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${t('youPaid')}: ₹${receipt.calculatedTotal.toStringAsFixed(2)} (${receipt.items.length} ${t('items')})',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${t('location')}: ${receipt.store}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CartSenseColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: CartSenseColors.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${t('youSaved')} ₹${savings.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: CartSenseColors.primaryDark,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      t('viewBill'),
                      style: const TextStyle(
                        color: Color(0xFFD46524),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: Color(0xFFD46524),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

String _shortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

class MyBillsScreen extends StatefulWidget {
  const MyBillsScreen({
    super.key,
    required this.receipts,
    required this.activeShoppingCount,
    required this.onOpenReceipt,
    this.languageCode = 'en',
    this.onScan,
    this.onOpenShoppingList,
    this.onOpenInsights,
  });

  final List<Receipt> receipts;
  final int activeShoppingCount;
  final Future<void> Function(Receipt receipt) onOpenReceipt;
  final String languageCode;
  final VoidCallback? onScan;
  final VoidCallback? onOpenShoppingList;
  final VoidCallback? onOpenInsights;

  @override
  State<MyBillsScreen> createState() => _MyBillsScreenState();
}

class _MyBillsScreenState extends State<MyBillsScreen> {
  final searchController = TextEditingController();
  String query = '';

  String t(String key) => appText(widget.languageCode, key);

  List<Receipt> get filteredReceipts {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return widget.receipts;
    return widget.receipts
        .where((receipt) =>
            receipt.store.toLowerCase().contains(needle) ||
            receipt.items.any((item) =>
                item.name.toLowerCase().contains(needle) ||
                item.category.toLowerCase().contains(needle)))
        .toList();
  }

  double get totalPaid => widget.receipts.fold(
        0,
        (sum, receipt) => sum + receipt.calculatedTotal,
      );

  double get totalSavings => widget.receipts.fold(
        0,
        (sum, receipt) =>
            sum +
            receipt.billDiscount +
            receipt.items.fold(0, (itemSum, item) => itemSum + item.discount),
      );

  int get totalItems => widget.receipts.fold(
        0,
        (sum, receipt) => sum + receipt.items.length,
      );

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(t('myBills')),
          actions: [
            IconButton(
              tooltip: t('scanBill'),
              onPressed: widget.onScan,
              icon: const Icon(Icons.document_scanner_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              _BillsCelebrationCard(
                totalPaid: totalPaid,
                totalSavings: totalSavings,
                billCount: widget.receipts.length,
                itemCount: totalItems,
                languageCode: widget.languageCode,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: searchController,
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(
                  hintText: t('searchStoreProduct'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: t('clearSearch'),
                          onPressed: () {
                            searchController.clear();
                            setState(() => query = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.receipt_long_outlined, color: green),
                  const SizedBox(width: 8),
                  Text(
                    filteredReceipts.isEmpty
                        ? t('savedBills')
                        : '${filteredReceipts.length} ${t('savedBills')}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (widget.receipts.isEmpty)
                _BillsEmptyCard(
                  onScan: widget.onScan,
                  languageCode: widget.languageCode,
                )
              else if (filteredReceipts.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(t('noBillsMatch')),
                  ),
                )
              else
                ...filteredReceipts.map(
                  (receipt) => _BillSavingsCard(
                    receipt: receipt,
                    languageCode: widget.languageCode,
                    onTap: () => widget.onOpenReceipt(receipt),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: CartSenseFooterNav(
          selectedIndex: 3,
          activeShoppingCount: widget.activeShoppingCount,
          languageCode: widget.languageCode,
          onDestinationSelected: (index) {
            if (index == 0) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            } else if (index == 1) {
              widget.onOpenShoppingList?.call();
            } else if (index == 2) {
              widget.onScan?.call();
            } else if (index == 4) {
              widget.onOpenInsights?.call();
            }
          },
        ),
      );
}

class _BillsCelebrationCard extends StatelessWidget {
  const _BillsCelebrationCard({
    required this.totalPaid,
    required this.totalSavings,
    required this.billCount,
    required this.itemCount,
    required this.languageCode,
  });

  final double totalPaid;
  final double totalSavings;
  final int billCount;
  final int itemCount;
  final String languageCode;

  String t(String key) => appText(languageCode, key);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF8A3D), Color(0xFFFFC166)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33D46524),
              blurRadius: 20,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wallet_giftcard_outlined,
                      color: Color(0xFFD46524), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    t('yourShoppingRecord'),
                    style: const TextStyle(
                      color: Color(0xFFD46524),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              t('totalPaid'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '₹${totalPaid.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ColorMetricTile(
                    label: t('saved'),
                    value: '₹${totalSavings.toStringAsFixed(0)}',
                    icon: Icons.savings_outlined,
                    color: CartSenseColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ColorMetricTile(
                    label: t('bills'),
                    value: '$billCount',
                    icon: Icons.receipt_long_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ColorMetricTile(
                    label: t('items'),
                    value: '$itemCount',
                    icon: Icons.shopping_basket_outlined,
                    color: const Color(0xFFFFF4D8),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _ColorMetricTile extends StatelessWidget {
  const _ColorMetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: CartSenseColors.primary, size: 18),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              label,
              style: const TextStyle(
                color: CartSenseColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _BillsEmptyCard extends StatelessWidget {
  const _BillsEmptyCard({
    this.onScan,
    required this.languageCode,
  });

  final VoidCallback? onScan;
  final String languageCode;

  String t(String key) => appText(languageCode, key);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: CartSenseColors.success,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: green,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                t('noBillsSavedYet'),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                t('scanFirstBillSaveHere'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: CartSenseColors.textMuted),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.document_scanner_outlined),
                label: Text(t('scanBill')),
              ),
            ],
          ),
        ),
      );
}

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({
    super.key,
    required this.receipt,
    this.history = const [],
    this.activeShoppingCount = 0,
    this.onScan,
    this.onOpenShoppingList,
    this.onOpenInsights,
    this.onOpenBills,
  });
  final Receipt receipt;
  final List<Receipt> history;
  final int activeShoppingCount;
  final VoidCallback? onScan;
  final VoidCallback? onOpenShoppingList;
  final VoidCallback? onOpenInsights;
  final VoidCallback? onOpenBills;
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  late Receipt receipt = widget.receipt;
  bool saving = false;

  bool get _hasReceiptImage {
    final path = receipt.imagePath;
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  Future<void> _showOriginalReceipt({String? focusItem}) async {
    final path = receipt.imagePath;
    if (path == null || !File(path).existsSync()) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptImageScreen(
          imagePath: path,
          focusItem: focusItem,
        ),
      ),
    );
  }

  Future<void> _deleteReceipt() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete receipt?'),
        content: Text(
          '${receipt.store} and its saved image will be removed from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete receipt'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ReceiptStore().delete(receipt.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _reviewNextItem() async {
    final index = receipt.items.indexWhere((item) => item.needsReview);
    if (index >= 0) await _editItem(index);
  }

  Future<void> _approveItem(int index) async {
    final item = receipt.items[index];
    item.confidence = 1;
    await ProductMemoryStore().rememberItem(
      scannedName: item.name,
      corrected: item,
    );
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${item.name} approved. CartSense learned it.'),
    ));
  }

  Future<void> _markAllReviewed() async {
    for (final item in receipt.items) {
      item.confidence = 1;
      await ProductMemoryStore().rememberItem(
        scannedName: item.name,
        corrected: item,
      );
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Review completed. CartSense learned these products.'),
    ));
  }

  Future<void> _addToShoppingList(ReceiptItem item) async {
    final priceInsight = _priceInsightFor(item);
    final unitPrice = item.unitPrice > 0
        ? item.unitPrice
        : item.quantity > 0
            ? item.total / item.quantity
            : item.total;
    await ShoppingListStore().add(ShoppingItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: item.name,
      quantity: 1,
      category: item.category,
      expectedUnitPrice: unitPrice,
      bestUnitPrice: priceInsight?.bestPrice ?? unitPrice,
      bestStore: priceInsight?.bestStore ?? receipt.store,
      latestStore: receipt.store,
      sourceReceiptId: receipt.id,
      createdAt: DateTime.now(),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.name} added to your shopping list.')),
    );
  }

  List<ProductPriceInsight> get _currentPriceInsights {
    final combined = [
      ...widget.history.where((item) => item.id != receipt.id),
      receipt,
    ];
    final receiptKeys = receipt.items
        .map((item) => normalizedProductName(item.name))
        .where((key) => key.length > 1)
        .toSet();
    return SavingsIntelligence.fromReceipts(combined)
        .priceInsights
        .where((item) => receiptKeys.contains(normalizedProductName(item.name)))
        .toList();
  }

  ProductPriceInsight? _priceInsightFor(ReceiptItem item) {
    final key = normalizedProductName(item.name);
    for (final insight in _currentPriceInsights) {
      if (normalizedProductName(insight.name) == key) return insight;
    }
    return null;
  }

  Future<void> _saveAndReconcile() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await ReceiptStore().save(receipt);
      if (!mounted) return;
      if (receipt.shoppingTrip != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bill changes saved on this device.'),
        ));
        return;
      }
      final shoppingItems = await ShoppingListStore().load();
      final plannedItems = shoppingItems
          .where((item) => item.reconciledReceiptId == null)
          .toList();
      if (!mounted) return;
      if (plannedItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            'Receipt saved. Add products to your shopping list to plan the next trip.',
          ),
        ));
        return;
      }
      final result = await Navigator.of(context).push<ShoppingTripResult>(
        MaterialPageRoute(
          builder: (_) => ShoppingReconciliationScreen(
            receipt: receipt,
            plannedItems: plannedItems,
            activeShoppingCount: widget.activeShoppingCount,
            onOpenShoppingList: widget.onOpenShoppingList,
            onOpenInsights: widget.onOpenInsights,
          ),
        ),
      );
      if (result == null || !mounted) return;
      setState(() => receipt.shoppingTrip = result);
      await ReceiptStore().save(receipt);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Trip finished: ${result.matches.length} bought, ${result.missing.length} still on your list.',
        ),
      ));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _editDetails() async {
    final store = TextEditingController(text: receipt.store);
    final date = TextEditingController(
      text:
          '${receipt.purchasedAt.day}/${receipt.purchasedAt.month}/${receipt.purchasedAt.year}',
    );
    final total =
        TextEditingController(text: receipt.printedTotal.toStringAsFixed(2));
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit bill details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: store,
                decoration: const InputDecoration(labelText: 'Store name'),
              ),
              TextField(
                controller: date,
                keyboardType: TextInputType.datetime,
                decoration:
                    const InputDecoration(labelText: 'Date (day/month/year)'),
              ),
              TextField(
                controller: total,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Printed bill total'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (shouldSave == true) {
      final dateParts = date.text.trim().split(RegExp(r'[/.-]'));
      DateTime? parsedDate;
      if (dateParts.length == 3) {
        final day = int.tryParse(dateParts[0]);
        final month = int.tryParse(dateParts[1]);
        final year = int.tryParse(dateParts[2]);
        if (day != null && month != null && year != null) {
          final candidate = DateTime(year, month, day);
          if (candidate.day == day &&
              candidate.month == month &&
              candidate.year == year) {
            parsedDate = candidate;
          }
        }
      }
      setState(() {
        if (store.text.trim().isNotEmpty) receipt.store = store.text.trim();
        receipt.printedTotal =
            double.tryParse(total.text) ?? receipt.printedTotal;
        receipt.purchasedAt = parsedDate ?? receipt.purchasedAt;
      });
      await ReceiptStore().save(receipt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Receipt details saved.'),
        ));
      }
    }
    store.dispose();
    date.dispose();
    total.dispose();
  }

  Future<void> _editItem(int index) async {
    final item = receipt.items[index];
    final scannedName = item.name;
    final name = TextEditingController(text: item.name);
    final quantity = TextEditingController(text: item.quantity.toString());
    final price =
        TextEditingController(text: item.unitPrice.toStringAsFixed(2));
    final discount =
        TextEditingController(text: item.discount.toStringAsFixed(2));
    var category = item.category;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit item'),
        content: SingleChildScrollView(
          child: Column(children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Product name')),
            TextField(
                controller: quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity')),
            TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Unit price')),
            TextField(
                controller: discount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Discount')),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: GroceryCategory.values
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) category = value;
              },
            ),
          ]),
        ),
        actions: [
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, 'delete'),
              child: const Text('Delete')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Save')),
        ],
      ),
    );
    if (action == 'delete') {
      setState(() => receipt.items.removeAt(index));
    } else if (action == 'save') {
      setState(() {
        item.name = name.text.trim();
        item.quantity = double.tryParse(quantity.text) ?? item.quantity;
        item.unitPrice = double.tryParse(price.text) ?? item.unitPrice;
        item.discount = double.tryParse(discount.text) ?? item.discount;
        item.category = category;
        item.parsedLineTotal = null;
        item.confidence = 1;
      });
      await ProductMemoryStore().rememberItem(
        scannedName: scannedName,
        corrected: item,
      );
      final changed = await ProductMemoryStore().applyToReceipt(receipt);
      if (mounted) {
        if (changed) setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            changed
                ? 'Saved. Similar products were updated from memory.'
                : 'Saved. CartSense will remember ${item.name}.',
          ),
        ));
      }
    }
    name.dispose();
    quantity.dispose();
    price.dispose();
    discount.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Receipt details'),
              Text(
                receipt.store,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CartSenseColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Receipt options',
              onSelected: (value) {
                if (value == 'image') {
                  _showOriginalReceipt();
                } else if (value == 'export') {
                  ReceiptExport().shareCsv(receipt);
                } else if (value == 'delete') {
                  _deleteReceipt();
                }
              },
              itemBuilder: (context) => [
                if (_hasReceiptImage)
                  const PopupMenuItem(
                    value: 'image',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.image_outlined),
                      title: Text('View receipt image'),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.ios_share_outlined),
                    title: Text('Export receipt'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('Delete receipt'),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _receiptResultHero(),
            const SizedBox(height: 14),
            _receiptStatsCard(),
            const SizedBox(height: 8),
            if (receipt.shoppingTrip case final trip?) ...[
              _tripSummary(trip),
              const SizedBox(height: 8),
            ],
            if (_hasReceiptImage) ...[
              _receiptPhotoCompareCard(),
              const SizedBox(height: 8),
            ],
            if (_currentPriceInsights.isNotEmpty) ...[
              _priceIntelligenceCard(),
              const SizedBox(height: 8),
            ],
            if (receipt.reviewItemCount > 0) ...[
              Card(
                color: CartSenseColors.warning,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.fact_check_outlined, color: green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${receipt.reviewItemCount} ${receipt.reviewItemCount == 1 ? 'item needs' : 'items need'} your review',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: _reviewNextItem,
                        child: const Text('Review next'),
                      ),
                      TextButton(
                        onPressed: _markAllReviewed,
                        child: const Text('Looks good'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _reviewQueue(),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              onPressed: _editDetails,
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Edit receipt details'),
            ),
            const SizedBox(height: 6),
            if (receipt.isAiEnhanced) ...[
              Card(
                color: CartSenseColors.surfaceMuted,
                child: ExpansionTile(
                  leading: const Icon(Icons.auto_awesome, color: green),
                  title: const Text(
                    'Scan quality',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${(receipt.overallConfidence * 100).round()}% confidence${receipt.warnings.isEmpty ? '' : ' · ${receipt.warnings.length} notes'}',
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (receipt.printedItemCount != null)
                          Chip(
                            label: Text(
                              '${receipt.items.length}/${receipt.printedItemCount} products',
                            ),
                          ),
                        if (receipt.printedQuantityTotal != null)
                          Chip(
                            label: Text(
                              'Quantity ${receipt.printedQuantityTotal!.g}',
                            ),
                          ),
                      ],
                    ),
                    if (receipt.warnings.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...receipt.warnings.take(4).map(
                            (warning) => Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.info_outline,
                                      size: 17, color: green),
                                  const SizedBox(width: 7),
                                  Expanded(child: Text(warning)),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            _HomeSectionTitle(
              'Products by category',
              trailing: '${receipt.items.length}',
            ),
            const SizedBox(height: 7),
            ..._productCategoryGroups(),
            if (receipt.items.isEmpty)
              ...List.generate(receipt.items.length, (index) {
                final item = receipt.items[index];
                return Card(
                  color:
                      item.needsReview ? CartSenseColors.warning : Colors.white,
                  child: ListTile(
                    onTap: () => _editItem(index),
                    leading: CategoryAvatar(category: item.category),
                    title: Text(item.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${item.quantity.g} × ₹${item.unitPrice.toStringAsFixed(2)}  •  Discount ₹${item.discount.toStringAsFixed(2)}\n${item.category}${item.needsReview ? '  •  REVIEW' : ''}'),
                    isThreeLine: true,
                    trailing: SizedBox(
                      width: 104,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              '₹${item.total.toStringAsFixed(2)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Add to shopping list',
                            onPressed: () => _addToShoppingList(item),
                            icon: const Icon(Icons.add_shopping_cart_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            TextButton.icon(
              onPressed: () => setState(() => receipt.items.add(ReceiptItem(
                  name: 'New item',
                  quantity: 1,
                  unitPrice: 0,
                  discount: 0,
                  confidence: 1))),
              icon: const Icon(Icons.add),
              label: const Text('Add missing item'),
            ),
            const SizedBox(height: 10),
            _totalsCard(),
            if (receipt.items.isEmpty && receipt.items.isNotEmpty) ...[
              const Divider(height: 28),
              _total('Product subtotal', receipt.itemSubtotal),
              if (receipt.taxTotal > 0) _total('Tax', receipt.taxTotal),
              if (receipt.otherCharges > 0)
                _total('Other charges', receipt.otherCharges),
              if (receipt.billDiscount > 0)
                _total('Bill discount', -receipt.billDiscount),
              _total('Printed bill total', receipt.printedTotal),
              _total('Calculated total', receipt.calculatedTotal, strong: true),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: saving ? null : _saveAndReconcile,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(receipt.shoppingTrip == null
                      ? Icons.sync_alt
                      : Icons.save_outlined),
              label: Text(saving
                  ? 'Saving…'
                  : receipt.shoppingTrip == null
                      ? 'Save bill & reconcile shopping list'
                      : 'Save bill changes'),
            ),
          ],
        ),
        bottomNavigationBar: CartSenseFooterNav(
          selectedIndex: 3,
          activeShoppingCount: widget.activeShoppingCount,
          onDestinationSelected: (index) {
            if (index == 0) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            } else if (index == 1) {
              widget.onOpenShoppingList?.call();
            } else if (index == 2) {
              widget.onScan?.call();
            } else if (index == 4) {
              widget.onOpenInsights?.call();
            }
          },
        ),
      );

  Widget _receiptResultHero() {
    final isClean = receipt.confidentlyReconciled;
    final needsReview = receipt.reviewItemCount > 0;
    final statusText = isClean
        ? 'Bill read successfully'
        : receipt.reconciled
            ? 'Bill total matches'
            : 'Please check the bill total';
    final helperText = isClean
        ? 'Store, products and total look ready to save.'
        : needsReview
            ? '${receipt.reviewItemCount} products need a quick review before final save.'
            : 'The printed and calculated totals differ by ₹${receipt.difference.abs().toStringAsFixed(2)}.';
    return Card(
      color: isClean ? CartSenseColors.success : CartSenseColors.warning,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .72),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isClean
                        ? Icons.verified_outlined
                        : Icons.fact_check_outlined,
                    color: green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        helperText,
                        style: const TextStyle(
                          color: CartSenseColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.storefront_outlined, size: 18),
                  label: Text(
                    receipt.store.trim().isEmpty
                        ? 'Store not found'
                        : receipt.store,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text('${receipt.items.length} products'),
                ),
                Chip(
                  avatar: const Icon(Icons.payments_outlined, size: 18),
                  label: Text('₹${receipt.printedTotal.toStringAsFixed(2)}'),
                ),
              ],
            ),
            if (needsReview) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _reviewNextItem,
                icon: const Icon(Icons.manage_search_outlined),
                label: const Text('Review highlighted products'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _receiptStatsCard() => Card(
        color: CartSenseColors.surface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: _receiptMetric(
                  Icons.shopping_basket_outlined,
                  'Products',
                  '${receipt.items.length}',
                ),
              ),
              Expanded(
                child: _receiptMetric(
                  Icons.rule_folder_outlined,
                  'Review',
                  receipt.reviewItemCount == 0
                      ? 'Clear'
                      : '${receipt.reviewItemCount}',
                ),
              ),
              Expanded(
                child: _receiptMetric(
                  Icons.payments_outlined,
                  'Total',
                  '₹${receipt.printedTotal.toStringAsFixed(0)}',
                ),
              ),
            ],
          ),
        ),
      );

  Widget _receiptMetric(IconData icon, String label, String value) => Column(
        children: [
          Icon(icon, color: green),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            style: const TextStyle(
              color: CartSenseColors.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      );

  List<Widget> _productCategoryGroups() {
    final indexesByCategory = <String, List<int>>{};
    for (var index = 0; index < receipt.items.length; index += 1) {
      final item = receipt.items[index];
      indexesByCategory.putIfAbsent(item.category, () => []).add(index);
    }
    final entries = indexesByCategory.entries.toList()
      ..sort((a, b) {
        final totalA = a.value.fold(
          0.0,
          (sum, index) => sum + receipt.items[index].total,
        );
        final totalB = b.value.fold(
          0.0,
          (sum, index) => sum + receipt.items[index].total,
        );
        return totalB.compareTo(totalA);
      });
    return entries.map((entry) {
      final total = entry.value.fold(
        0.0,
        (sum, index) => sum + receipt.items[index].total,
      );
      final reviewCount =
          entry.value.where((index) => receipt.items[index].needsReview).length;
      return Card(
        color: reviewCount > 0 ? CartSenseColors.warning : Colors.white,
        child: ExpansionTile(
          initiallyExpanded: reviewCount > 0 || entries.length <= 3,
          leading: CategoryAvatar(category: entry.key),
          title: Text(
            entry.key,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            '${entry.value.length} products${reviewCount > 0 ? ' • $reviewCount review' : ''}',
          ),
          trailing: Text(
            '₹${total.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          children: entry.value.map((index) {
            final item = receipt.items[index];
            return ListTile(
              onTap: () => _editItem(index),
              title: Text(
                item.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${item.quantity.g} × ₹${item.unitPrice.toStringAsFixed(2)} • Discount ₹${item.discount.toStringAsFixed(2)}${item.needsReview ? ' • REVIEW' : ''}',
              ),
              trailing: SizedBox(
                width: 104,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        '₹${item.total.toStringAsFixed(2)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Add to shopping list',
                      onPressed: () => _addToShoppingList(item),
                      icon: const Icon(Icons.add_shopping_cart_outlined),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      );
    }).toList();
  }

  Widget _totalsCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.receipt_long_outlined, color: green),
                  SizedBox(width: 8),
                  Text(
                    'Bill totals',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _total('Product subtotal', receipt.itemSubtotal),
              if (receipt.taxTotal > 0) _total('Tax', receipt.taxTotal),
              if (receipt.otherCharges > 0)
                _total('Other charges', receipt.otherCharges),
              if (receipt.billDiscount > 0)
                _total('Bill discount', -receipt.billDiscount),
              const Divider(),
              _total('Printed bill total', receipt.printedTotal),
              _total('Calculated total', receipt.calculatedTotal, strong: true),
            ],
          ),
        ),
      );

  Widget _reviewQueue() {
    final reviewIndexes = <int>[];
    for (var i = 0; i < receipt.items.length; i += 1) {
      if (receipt.items[i].needsReview) reviewIndexes.add(i);
    }
    if (reviewIndexes.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.manage_search_outlined, color: green),
                SizedBox(width: 8),
                Text(
                  'Review queue',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Check these first. Approving teaches CartSense for future scans.',
              style: TextStyle(color: CartSenseColors.textMuted),
            ),
            const SizedBox(height: 10),
            ...reviewIndexes.map((index) {
              final item = receipt.items[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CartSenseColors.warning,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CartSenseColors.outline),
                ),
                child: Row(
                  children: [
                    CategoryAvatar(category: item.category),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${item.category} · ₹${item.total.toStringAsFixed(2)} · ${(item.confidence * 100).round()}% confidence',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CartSenseColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _approveItem(index),
                      child: const Text('Approve'),
                    ),
                    if (_hasReceiptImage)
                      IconButton(
                        tooltip: 'Compare with photo',
                        onPressed: () =>
                            _showOriginalReceipt(focusItem: item.name),
                        icon: const Icon(Icons.image_search_outlined),
                      ),
                    IconButton(
                      tooltip: 'Edit',
                      onPressed: () => _editItem(index),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _priceIntelligenceCard() {
    final insights = _currentPriceInsights
        .where((item) =>
            item.purchaseCount > 1 &&
            (item.priceChangePercent.abs() >= 5 || item.possibleSaving >= 1))
        .take(5)
        .toList();
    if (insights.isEmpty) {
      return Card(
        color: CartSenseColors.surfaceMuted,
        child: const ListTile(
          leading: Icon(Icons.price_check_outlined, color: green),
          title: Text(
            'Price intelligence is learning',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            'Scan this product again later to compare prices and spot savings.',
          ),
        ),
      );
    }
    return Card(
      color: CartSenseColors.surfaceMuted,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.price_change_outlined, color: green),
        title: const Text(
          'Price intelligence',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text('${insights.length} useful price notes found'),
        children: insights.map((item) {
          final wentUp = item.priceChangePercent >= 5;
          final cheaperElsewhere =
              item.bestStore != item.latestStore && item.possibleSaving >= 1;
          return ListTile(
            dense: true,
            leading: Icon(
              wentUp ? Icons.trending_up : Icons.savings_outlined,
              color: wentUp ? Colors.deepOrange : green,
            ),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              wentUp
                  ? 'Was ₹${item.previousPrice!.toStringAsFixed(2)}, now ₹${item.latestPrice.toStringAsFixed(2)}.'
                  : 'Best seen at ${item.bestStore} for ₹${item.bestPrice.toStringAsFixed(2)}.',
            ),
            trailing: Text(
              wentUp
                  ? '+${item.priceChangePercent.toStringAsFixed(0)}%'
                  : cheaperElsewhere
                      ? 'Save ₹${item.possibleSaving.toStringAsFixed(0)}'
                      : '',
              style: TextStyle(
                color: wentUp ? Colors.deepOrange : green,
                fontWeight: FontWeight.w900,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _receiptPhotoCompareCard() => Card(
        color: CartSenseColors.surfaceMuted,
        child: ListTile(
          leading: const Icon(Icons.document_scanner_outlined, color: green),
          title: const Text(
            'Compare with original photo',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: const Text(
            'Open the receipt image while checking product names, prices and totals.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showOriginalReceipt,
        ),
      );

  Widget _tripSummary(ShoppingTripResult trip) => Card(
        color: CartSenseColors.success,
        child: ExpansionTile(
          leading: const Icon(Icons.done_all, color: green),
          title: const Text(
            'Shopping trip reconciled',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            '${trip.matches.length} bought · ${trip.missing.length} still needed · ${trip.unplanned.length} unplanned\nPlanned ₹${trip.plannedEstimate.toStringAsFixed(2)} · Bill ₹${trip.billTotal.toStringAsFixed(2)}',
          ),
          children: [
            if (trip.matches.isNotEmpty)
              ...trip.matches.map((item) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text('${item.plannedName} → ${item.purchasedName}'),
                    trailing: Text('₹${item.actualTotal.toStringAsFixed(2)}'),
                  )),
            if (trip.missing.isNotEmpty)
              ...trip.missing.map((item) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.pending_outlined),
                    title: Text('${item.name} remains on the list'),
                  )),
            if (trip.unplanned.isNotEmpty)
              ...trip.unplanned.map((item) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text('${item.name} was unplanned'),
                    trailing: Text('₹${item.actualTotal.toStringAsFixed(2)}'),
                  )),
          ],
        ),
      );

  Widget _total(String label, double amount, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: TextStyle(
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w500)),
          Text('₹${amount.toStringAsFixed(2)}',
              style: TextStyle(
                  fontSize: strong ? 21 : 16, fontWeight: FontWeight.w800)),
        ]),
      );
}

class ReceiptImageScreen extends StatelessWidget {
  const ReceiptImageScreen({
    super.key,
    required this.imagePath,
    this.focusItem,
  });

  final String imagePath;
  final String? focusItem;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(focusItem == null ? 'Original receipt' : 'Check product'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  boundaryMargin: const EdgeInsets.all(80),
                  child: Image.file(
                    File(imagePath),
                    semanticLabel: 'Original grocery receipt',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'The original receipt image is no longer available.',
                        style: TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.zoom_in, color: Colors.white),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            focusItem == null
                                ? 'Pinch to zoom and drag the photo to compare it with captured details.'
                                : 'Find "$focusItem" on the original receipt. Pinch to zoom, then go back to approve or edit.',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

extension CompactNumber on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
