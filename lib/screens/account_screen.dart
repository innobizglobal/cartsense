import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/language_store.dart';
import '../theme/cartsense_theme.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  StreamSubscription<AuthState>? subscription;
  AppLanguage language = AppLanguage.english;
  bool busy = false;
  bool createAccount = false;
  User? user = CartSenseAuthService.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    subscription = CartSenseAuthService.instance.authStateChanges.listen(
      (event) {
        if (mounted) setState(() => user = event.session?.user);
      },
    );
  }

  Future<void> _loadLanguage() async {
    final saved = await LanguageStore().load();
    if (mounted) setState(() => language = saved);
  }

  String t(String key) => appText(language.code, key);

  @override
  void dispose() {
    subscription?.cancel();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (email.text.trim().isEmpty || password.text.length < 6) {
      _message(t('enterEmailPassword'));
      return;
    }
    setState(() => busy = true);
    try {
      if (createAccount) {
        await CartSenseAuthService.instance.signUpWithEmail(
          email: email.text,
          password: password.text,
        );
        _message(t('accountCreatedCheckEmail'));
      } else {
        await CartSenseAuthService.instance.signInWithEmail(
          email: email.text,
          password: password.text,
        );
        _message(t('signedIn'));
      }
      setState(() => user = CartSenseAuthService.instance.currentUser);
    } on AuthException catch (error) {
      _message(error.message);
    } on AuthUnavailableException catch (error) {
      _message(error.message);
    } catch (_) {
      _message(t('loginFailed'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _sendOtp() async {
    if (email.text.trim().isEmpty) {
      _message(t('enterEmail'));
      return;
    }
    setState(() => busy = true);
    try {
      await CartSenseAuthService.instance.sendEmailOtp(email.text);
      _message(t('magicLinkSent'));
    } on AuthException catch (error) {
      _message(error.message);
    } on AuthUnavailableException catch (error) {
      _message(error.message);
    } catch (_) {
      _message(t('loginFailed'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => busy = true);
    await CartSenseAuthService.instance.signOut();
    if (mounted) {
      setState(() {
        user = null;
        busy = false;
      });
      _message(t('signedOut'));
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: CartSenseColors.background,
        appBar: AppBar(title: Text(t('account'))),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              color: CartSenseColors.primary,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.cloud_done_outlined,
                      color: CartSenseColors.accent,
                      size: 34,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      user == null ? t('guestMode') : t('cloudAccount'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user == null
                          ? t('guestModeBody')
                          : '${t('signedInAs')} ${user!.email ?? user!.phone ?? user!.id}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (!CartSenseAuthService.isConfigured)
              Card(
                color: CartSenseColors.warning,
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(
                    t('cloudLoginNotConfigured'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(t('cloudLoginConfigBody')),
                ),
              )
            else if (user != null)
              _signedInCard()
            else
              _loginCard(),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.phone_android_outlined),
                    title: Text(t('guestModeAvailable')),
                    subtitle: Text(t('guestModeAvailableBody')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: Text(t('cloudSyncComing')),
                    subtitle: Text(t('cloudSyncComingBody')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: Text(t('privateDataControl')),
                    subtitle: Text(t('privateDataControlBody')),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _loginCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                createAccount ? t('createAccount') : t('signIn'),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: t('email'),
                  prefixIcon: const Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: t('password'),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: busy ? null : _submit,
                icon: busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(createAccount ? t('createAccount') : t('signIn')),
              ),
              TextButton(
                onPressed: busy ? null : _sendOtp,
                child: Text(t('sendMagicLink')),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() => createAccount = !createAccount),
                child: Text(
                  createAccount ? t('alreadyHaveAccount') : t('newCreateOne'),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _signedInCard() => Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text(t('cloudLoginActive')),
              subtitle: Text(t('cloudLoginActiveBody')),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(t('signOut')),
              onTap: busy ? null : _signOut,
            ),
          ],
        ),
      );
}
