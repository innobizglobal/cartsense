import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/receipt.dart';
import '../models/shopping_item.dart';
import 'onboarding_screen.dart';
import '../services/backup_service.dart';
import '../services/language_store.dart';
import '../services/product_memory_store.dart';
import '../theme/cartsense_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool loading = true;
  bool aiConsent = false;
  int receiptCount = 0;
  int shoppingCount = 0;
  int memoryCount = 0;
  AppLanguage language = AppLanguage.english;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final memory = await ProductMemoryStore().load();
    final savedLanguage = await LanguageStore().load();
    if (!mounted) return;
    setState(() {
      aiConsent = preferences.getBool('cartsense_ai_consent') == true;
      receiptCount = (preferences.getStringList('cartsense_receipts_v1') ?? [])
          .map((value) {
            try {
              return Receipt.decode(value);
            } catch (_) {
              return null;
            }
          })
          .whereType<Receipt>()
          .length;
      shoppingCount =
          (preferences.getStringList('cartsense_shopping_list_v1') ?? [])
              .map((value) {
                try {
                  return ShoppingItem.decode(value);
                } catch (_) {
                  return null;
                }
              })
              .whereType<ShoppingItem>()
              .where((item) => !item.checked)
              .length;
      memoryCount = memory.length;
      language = savedLanguage;
      loading = false;
    });
  }

  Future<void> _chooseLanguage() async {
    final selected = await showModalBottomSheet<AppLanguage>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.translate_outlined),
              title: Text('Choose app language'),
              subtitle: Text('Starter support for the main shopping workflow.'),
            ),
            ...AppLanguage.values.map(
              (option) => ListTile(
                leading: Icon(
                  option.code == language.code
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: option.code == language.code
                      ? CartSenseColors.primary
                      : null,
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
      content: Text('Language changed to ${selected.nativeName}.'),
    ));
  }

  Future<void> _toggleAiConsent(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('cartsense_ai_consent', value);
    if (!mounted) return;
    setState(() => aiConsent = value);
  }

  Future<void> _shareBackup() async {
    try {
      await CartSenseBackupService().shareBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Backup file prepared. Choose where to save/share it.'),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Backup failed: $error'),
      ));
    }
  }

  Future<void> _copyBackupText() async {
    final text = await CartSenseBackupService().backupText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Backup text copied to clipboard.'),
    ));
  }

  Future<void> _restoreFromText() async {
    final controller = TextEditingController();
    final backupText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste CartSense backup text here. This restores receipts, shopping list, product memory and settings.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 6,
                maxLines: 10,
                decoration: const InputDecoration(
                  hintText: '{ "app": "CartSense", ... }',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (backupText == null || backupText.trim().isEmpty) return;
    try {
      final restored =
          await CartSenseBackupService().restoreFromText(backupText);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Restore complete. $restored data sections restored.'),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Restore failed: $error'),
      ));
    }
  }

  Future<void> _clearProductMemory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear product memory?'),
        content: const Text(
          'CartSense will forget learned item/category corrections. Saved receipts and shopping lists will stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear memory'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ProductMemoryStore().clear();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Product memory cleared.'),
    ));
  }

  Future<void> _showOnboardingAgain() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(
          onFinished: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
                children: [
                  Card(
                    color: CartSenseColors.primary,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CartSense data',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '$receiptCount receipts · $shoppingCount shopping items · $memoryCount learned products',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 10),
                          const Row(
                            children: [
                              Icon(Icons.phone_android,
                                  color: CartSenseColors.accent, size: 18),
                              SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  'Your data is stored on this phone unless you choose to export it.',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _settingsSection(
                    'Privacy',
                    [
                      SwitchListTile(
                        value: aiConsent,
                        onChanged: _toggleAiConsent,
                        secondary: const Icon(Icons.auto_awesome),
                        title: const Text('Allow AI Enhanced Scan'),
                        subtitle: const Text(
                          'When enabled, receipt photos can be sent securely for AI recognition. Private scan remains available.',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _settingsSection(
                    'Language',
                    [
                      ListTile(
                        leading: const Icon(Icons.translate_outlined),
                        title: const Text('App language'),
                        subtitle: Text(
                          '${language.nativeName} · Shopping Assistant, Add Product and Trip Mode',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _chooseLanguage,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _settingsSection(
                    'Backup and restore',
                    [
                      ListTile(
                        leading: const Icon(Icons.ios_share_outlined),
                        title: const Text('Export backup file'),
                        subtitle: const Text(
                          'Save or share a CartSense backup JSON file.',
                        ),
                        onTap: _shareBackup,
                      ),
                      ListTile(
                        leading: const Icon(Icons.copy_outlined),
                        title: const Text('Copy backup text'),
                        subtitle: const Text(
                          'Useful if a share target is not available.',
                        ),
                        onTap: _copyBackupText,
                      ),
                      ListTile(
                        leading: const Icon(Icons.restore_page_outlined),
                        title: const Text('Restore from backup text'),
                        subtitle: const Text(
                          'Paste a previous CartSense backup.',
                        ),
                        onTap: _restoreFromText,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _settingsSection(
                    'Product memory',
                    [
                      ListTile(
                        leading: const Icon(Icons.psychology_outlined),
                        title: Text('$memoryCount learned products'),
                        subtitle: const Text(
                          'Corrections you approve help future scans classify products better.',
                        ),
                      ),
                      ListTile(
                        leading:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        title: const Text('Clear product memory'),
                        subtitle: const Text(
                          'Does not delete receipts or shopping list.',
                        ),
                        onTap: memoryCount == 0 ? null : _clearProductMemory,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _settingsSection(
                    'About',
                    [
                      ListTile(
                        leading: const Icon(Icons.school_outlined),
                        title: const Text('Show app guide'),
                        subtitle: const Text(
                          'Replay the CartSense welcome walkthrough.',
                        ),
                        onTap: _showOnboardingAgain,
                      ),
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('CartSense Lite'),
                        subtitle:
                            const Text('Version 0.9.0 · Android test build'),
                      ),
                    ],
                  ),
                ],
              ),
      );

  Widget _settingsSection(String title, List<Widget> children) => Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: CartSenseColors.primary,
                ),
              ),
            ),
            ...children,
          ],
        ),
      );
}
