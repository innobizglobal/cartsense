import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class CartSenseAuthService {
  CartSenseAuthService._();

  static final instance = CartSenseAuthService._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const redirectUrl = 'cartsense://login-callback/';

  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  static Future<void> initialize() async {
    if (!isConfigured) return;
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  }

  SupabaseClient? get _client => isConfigured ? Supabase.instance.client : null;

  User? get currentUser => _client?.auth.currentUser;

  Stream<AuthState> get authStateChanges =>
      _client?.auth.onAuthStateChange ?? const Stream<AuthState>.empty();

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final client = _requireClient();
    return client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final client = _requireClient();
    return client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: redirectUrl,
    );
  }

  Future<void> sendEmailOtp(String email) async {
    final client = _requireClient();
    await client.auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: redirectUrl,
    );
  }

  Future<void> sendPhoneOtp(String phone) async {
    final client = _requireClient();
    await client.auth.signInWithOtp(phone: _cleanPhone(phone));
  }

  Future<AuthResponse> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async {
    final client = _requireClient();
    return client.auth.verifyOTP(
      phone: _cleanPhone(phone),
      token: token.trim(),
      type: OtpType.sms,
    );
  }

  Future<bool> signInWithGoogle() async {
    final client = _requireClient();
    return client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectUrl,
    );
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const AuthUnavailableException(
        'Cloud login is not configured in this build.',
      );
    }
    return client;
  }

  String _cleanPhone(String phone) => phone.replaceAll(RegExp(r'\s+'), '');
}

class AuthUnavailableException implements Exception {
  const AuthUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
