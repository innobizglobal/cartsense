import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/family_profile_store.dart';
import '../theme/cartsense_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();
  final members = TextEditingController();
  final male = TextEditingController();
  final female = TextEditingController();
  final children = TextEditingController();
  final seniors = TextEditingController();
  int index = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.document_scanner_outlined,
      title: 'Scan grocery bills',
      body:
          'Use AI Enhanced Scan for difficult receipts, or private on-device scan when you want everything to stay on your phone.',
    ),
    _OnboardingPage(
      icon: Icons.local_grocery_store_outlined,
      title: 'Plan before shopping',
      body:
          'Create a shopping list, open Trip Mode in the store, tick items as you buy, then scan the checkout bill.',
    ),
    _OnboardingPage(
      icon: Icons.auto_awesome,
      title: 'CartSense learns with you',
      body:
          'When you approve or correct products, CartSense remembers categories locally so future scans become smarter.',
    ),
    _OnboardingPage(
      icon: Icons.lock_outline,
      title: 'Your data, your control',
      body:
          'Receipts, lists, backups and product memory live on this phone unless you choose to export or share them.',
    ),
  ];

  Future<void> _finish() async {
    final preferences = await SharedPreferences.getInstance();
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
                      child: const Text('Skip'),
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
                                members: members,
                                male: male,
                                female: female,
                                children: children,
                                seniors: seniors,
                              )
                            : _OnboardingPageView(page: _pages[pageIndex]),
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
                        ? 'Start using CartSense'
                        : 'Continue',
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
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({required this.page});

  final _OnboardingPage page;

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
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 32,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            page.body,
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
    required this.members,
    required this.male,
    required this.female,
    required this.children,
    required this.seniors,
  });

  final TextEditingController members;
  final TextEditingController male;
  final TextEditingController female;
  final TextEditingController children;
  final TextEditingController seniors;

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
            const Text(
              'Set up your household',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 30,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'CartSense uses this only on this phone to estimate monthly grocery needs. You can skip it and fill it later.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CartSenseColors.textMuted,
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            _numberField(members, 'Total family members'),
            Row(
              children: [
                Expanded(child: _numberField(male, 'Male')),
                const SizedBox(width: 10),
                Expanded(child: _numberField(female, 'Female')),
              ],
            ),
            Row(
              children: [
                Expanded(child: _numberField(children, 'Children')),
                const SizedBox(width: 10),
                Expanded(child: _numberField(seniors, 'Seniors')),
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
