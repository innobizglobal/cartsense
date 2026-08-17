import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/language_store.dart';
import '../theme/cartsense_theme.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    this.startupMode = false,
    this.onSignedIn,
  });

  final bool startupMode;
  final VoidCallback? onSignedIn;

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
  DateTime? lastSyncedAt;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _loadSyncStatus();
    subscription = CartSenseAuthService.instance.authStateChanges.listen(
      (event) {
        if (!mounted) return;
        setState(() => user = event.session?.user);
        if (event.session?.user != null) {
          CartSenseCloudSyncService.instance.syncInBackground();
          _loadSyncStatus();
          widget.onSignedIn?.call();
        }
      },
    );
  }

  Future<void> _loadSyncStatus() async {
    final value = await CartSenseCloudSyncService.instance.lastSyncedAt();
    if (mounted) setState(() => lastSyncedAt = value);
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
        CartSenseCloudSyncService.instance.syncInBackground();
        _message(t('signedIn'));
      }
      setState(() => user = CartSenseAuthService.instance.currentUser);
      if (CartSenseAuthService.instance.currentUser != null) {
        _loadSyncStatus();
        widget.onSignedIn?.call();
      }
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

  Future<void> _signInWithGoogle() async {
    setState(() => busy = true);
    try {
      final launched = await CartSenseAuthService.instance.signInWithGoogle();
      if (!launched) _message(t('googleLoginFailed'));
    } on AuthException catch (error) {
      _message(error.message);
    } on AuthUnavailableException catch (error) {
      _message(error.message);
    } catch (_) {
      _message(t('googleLoginFailed'));
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
        appBar: AppBar(
          automaticallyImplyLeading: !widget.startupMode,
          title:
              Text(widget.startupMode ? t('welcomeToCartSense') : t('account')),
        ),
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
                      user == null
                          ? t('welcomeToCartSense')
                          : t('cloudAccount'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user == null
                          ? t('loginFirstBody')
                          : '${t('signedInAs')} ${user!.email ?? user!.id}',
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
            if (!widget.startupMode)
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
                      leading: const Icon(Icons.cloud_sync_outlined),
                      title: Text(t('cloudSyncActive')),
                      subtitle: Text(t('cloudSyncActiveBody')),
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
              OutlinedButton.icon(
                onPressed: busy ? null : _signInWithGoogle,
                icon: const Icon(Icons.g_mobiledata),
                label: Text(t('continueWithGoogle')),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() => createAccount = !createAccount),
                child: Text(
                  createAccount ? t('alreadyHaveAccount') : t('newCreateOne'),
                ),
              ),
              if (widget.startupMode) ...[
                const SizedBox(height: 12),
                Text(
                  t('loginFirstFooter'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: CartSenseColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
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
              subtitle: Text(lastSyncedAt == null
                  ? t('cloudLoginActiveBody')
                  : '${t('lastSynced')} ${_shortSyncTime(lastSyncedAt!)}'),
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

String _shortSyncTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
