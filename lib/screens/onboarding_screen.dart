import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/cartsense_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();
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
    await preferences.setBool('cartsense_onboarding_complete', true);
    widget.onFinished();
  }

  void _next() {
    if (index == _pages.length - 1) {
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
                    itemCount: _pages.length,
                    itemBuilder: (context, pageIndex) =>
                        _OnboardingPageView(page: _pages[pageIndex]),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length,
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
                  icon: Icon(index == _pages.length - 1
                      ? Icons.check
                      : Icons.arrow_forward),
                  label: Text(
                    index == _pages.length - 1
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
