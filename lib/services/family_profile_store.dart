import 'dart:convert';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_sync_service.dart';

class FamilyProfile {
  const FamilyProfile({
    required this.members,
    required this.male,
    required this.female,
    required this.children,
    required this.seniors,
  });

  final int members;
  final int male;
  final int female;
  final int children;
  final int seniors;

  bool get isConfigured => members > 0;

  double get householdScale {
    if (members <= 0) return 1;
    final adultEquivalent =
        (male + female).clamp(0, 20) + (children * .6) + (seniors * .8);
    return (adultEquivalent <= 0 ? members : adultEquivalent)
        .clamp(1, 12)
        .toDouble();
  }

  Map<String, dynamic> toJson() => {
        'members': members,
        'male': male,
        'female': female,
        'children': children,
        'seniors': seniors,
      };

  factory FamilyProfile.fromJson(Map<String, dynamic> json) => FamilyProfile(
        members: (json['members'] as num?)?.toInt() ?? 0,
        male: (json['male'] as num?)?.toInt() ?? 0,
        female: (json['female'] as num?)?.toInt() ?? 0,
        children: (json['children'] as num?)?.toInt() ?? 0,
        seniors: (json['seniors'] as num?)?.toInt() ?? 0,
      );

  static const empty = FamilyProfile(
    members: 0,
    male: 0,
    female: 0,
    children: 0,
    seniors: 0,
  );
}

class FamilyProfileStore {
  static const _key = 'cartsense_family_profile_v1';

  Future<FamilyProfile> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.trim().isEmpty) return FamilyProfile.empty;
    try {
      return FamilyProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return FamilyProfile.empty;
    }
  }

  Future<void> save(FamilyProfile profile) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(profile.toJson()));
    unawaited(CartSenseCloudSyncService.instance.pushProfileAndSettings());
  }
}
