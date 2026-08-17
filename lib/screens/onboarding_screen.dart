import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/budget_store.dart';
import '../services/family_profile_store.dart';
import '../services/language_store.dart';
import '../theme/cartsense_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();
  final name = TextEditingController();
  final budget = TextEditingController();
  final members = TextEditingController();
  final male = TextEditingController();
  final female = TextEditingController();
  final children = TextEditingController();
  final seniors = TextEditingController();
  AppLanguage language = AppLanguage.english;
  int index = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.document_scanner_outlined,
      titleKey: 'onboardScanTitle',
      bodyKey: 'onboardScanBody',
    ),
    _OnboardingPage(
      icon: Icons.local_grocery_store_outlined,
      titleKey: 'onboardPlanTitle',
      bodyKey: 'onboardPlanBody',
    ),
    _OnboardingPage(
      icon: Icons.auto_awesome,
      titleKey: 'onboardLearnTitle',
      bodyKey: 'onboardLearnBody',
    ),
    _OnboardingPage(
      icon: Icons.lock_outline,
      titleKey: 'onboardPrivacyTitle',
      bodyKey: 'onboardPrivacyBody',
    ),
  ];

  String t(String key) => appText(language.code, key);

  Future<void> _finish() async {
    final preferences = await SharedPreferences.getInstance();
    final cleanName = name.text.trim();
    if (cleanName.isNotEmpty) {
      await preferences.setString('cartsense_user_name_v1', cleanName);
    }
    final monthlyBudget = double.tryParse(budget.text.trim()) ?? 0;
    if (monthlyBudget > 0) {
      await BudgetStore().save(monthlyBudget);
    }
    await LanguageStore().save(language);
    final totalMembers = int.tryParse(members.text.trim()) ?? 0;
    if (totalMembers > 0) {
      await FamilyProfileStore().save(FamilyProfile(
        members: totalMembers.clamp(0, 30),
        male: (int.tryParse(male.text.trim()) ?? 0).clamp(0, 30),
        female: (int.tryParse(female.text.trim()) ?? 0).clamp(0, 30),
        children: (int.tryParse(children.text.trim()) ?? 0).clamp(0, 30),
        seniors: (int.tryParse(seniors.text.trim()) ?? 0).clamp(0, 30),
      ));
    }
    await preferences.setBool('cartsense_onboarding_complete', true);
    await preferences.setBool('cartsense_family_profile_prompted_v1', true);
    await preferences.setBool('cartsense_guided_tour_acknowledged_v2', true);
    widget.onFinished();
  }

  void _next() {
    if (index == _pages.length) {
      _finish();
    } else {
      controller.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    name.dispose();
    budget.dispose();
    members.dispose();
    male.dispose();
    female.dispose();
    children.dispose();
    seniors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: CartSenseColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: CartSenseColors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.shopping_bag_outlined,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Text(
                        'CartSense',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _finish,
                      child: Text(t('skip')),
                    ),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    controller: controller,
                    onPageChanged: (value) => setState(() => index = value),
                    itemCount: _pages.length + 1,
                    itemBuilder: (context, pageIndex) =>
                        pageIndex == _pages.length
                            ? _FamilyProfilePage(
                                name: name,
                                budget: budget,
                                members: members,
                                male: male,
                                female: female,
                                children: children,
                                seniors: seniors,
                                language: language,
                                onLanguageChanged: (value) =>
                                    setState(() => language = value),
                              )
                            : _OnboardingPageView(
                                page: _pages[pageIndex],
                                languageCode: language.code,
                              ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length + 1,
                    (dot) => AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: dot == index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dot == index
                            ? CartSenseColors.primary
                            : CartSenseColors.outline,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _next,
                  icon: Icon(index == _pages.length
                      ? Icons.check
                      : Icons.arrow_forward),
                  label: Text(
                    index == _pages.length
                        ? t('startUsingCartSense')
                        : t('continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
  });

  final IconData icon;
  final String titleKey;
  final String bodyKey;
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({
    required this.page,
    required this.languageCode,
  });

  final _OnboardingPage page;
  final String languageCode;

  String t(String key) => appText(languageCode, key);

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [CartSenseColors.primaryDark, CartSenseColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(36),
              boxShadow: [
                BoxShadow(
                  color: CartSenseColors.primary.withValues(alpha: .22),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Icon(page.icon, color: CartSenseColors.accent, size: 62),
          ),
          const SizedBox(height: 34),
          Text(
            t(page.titleKey),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 32,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            t(page.bodyKey),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: CartSenseColors.textMuted,
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

class _FamilyProfilePage extends StatelessWidget {
  const _FamilyProfilePage({
    required this.name,
    required this.budget,
    required this.members,
    required this.male,
    required this.female,
    required this.children,
    required this.seniors,
    required this.language,
    required this.onLanguageChanged,
  });

  final TextEditingController name;
  final TextEditingController budget;
  final TextEditingController members;
  final TextEditingController male;
  final TextEditingController female;
  final TextEditingController children;
  final TextEditingController seniors;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: CartSenseColors.success,
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(
                Icons.family_restroom,
                color: CartSenseColors.primary,
                size: 58,
              ),
            ),
            const SizedBox(height: 26),
            Text(
              appText(language.code, 'setUpHousehold'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 30,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              appText(language.code, 'householdSetupBody'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CartSenseColors.textMuted,
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: appText(language.code, 'yourName'),
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<AppLanguage>(
              initialValue: language,
              decoration: InputDecoration(
                labelText: appText(language.code, 'preferredLanguage'),
                prefixIcon: const Icon(Icons.translate_outlined),
                border: const OutlineInputBorder(),
              ),
              items: AppLanguage.values
                  .map(
                    (option) => DropdownMenuItem(
                      value: option,
                      child: Text(option.nativeName),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onLanguageChanged(value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: budget,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: appText(language.code, 'monthlyGroceryBudget'),
                prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            _numberField(members, appText(language.code, 'totalFamilyMembers')),
            Row(
              children: [
                Expanded(
                    child: _numberField(male, appText(language.code, 'male'))),
                const SizedBox(width: 10),
                Expanded(
                    child:
                        _numberField(female, appText(language.code, 'female'))),
              ],
            ),
            Row(
              children: [
                Expanded(
                    child: _numberField(
                        children, appText(language.code, 'children'))),
                const SizedBox(width: 10),
                Expanded(
                    child: _numberField(
                        seniors, appText(language.code, 'seniors'))),
              ],
            ),
          ],
        ),
      );

  Widget _numberField(TextEditingController controller, String label) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );
}
