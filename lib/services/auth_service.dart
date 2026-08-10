import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class CartSenseAuthService {
  CartSenseAuthService._();

  static final instance = CartSenseAuthService._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

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
    );
  }

  Future<void> sendEmailOtp(String email) async {
    final client = _requireClient();
    await client.auth.signInWithOtp(email: email.trim());
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
