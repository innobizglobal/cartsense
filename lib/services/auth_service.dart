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

  SupabaseClient? get client => _client;

  User? get currentUser => _client?.auth.currentUser;

  String get currentUserDisplayName {
    final user = currentUser;
    if (user == null) return '';
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final name = (metadata['name'] ??
            metadata['full_name'] ??
            metadata['display_name'] ??
            '')
        .toString()
        .trim();
    if (name.isNotEmpty) return name.split(RegExp(r'\s+')).first;
    final email = user.email ?? '';
    if (email.contains('@')) return email.split('@').first;
    return '';
  }

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
}

class AuthUnavailableException implements Exception {
  const AuthUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
