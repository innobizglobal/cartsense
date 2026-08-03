import 'package:shared_preferences/shared_preferences.dart';

class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
  });

  final String code;
  final String name;
  final String nativeName;

  static const english = AppLanguage(
    code: 'en',
    name: 'English',
    nativeName: 'English',
  );
  static const hindi = AppLanguage(
    code: 'hi',
    name: 'Hindi',
    nativeName: 'हिन्दी',
  );
  static const telugu = AppLanguage(
    code: 'te',
    name: 'Telugu',
    nativeName: 'తెలుగు',
  );

  static const values = [english, hindi, telugu];

  static AppLanguage byCode(String code) => values.firstWhere(
        (language) => language.code == code,
        orElse: () => english,
      );
}

class LanguageStore {
  static const _key = 'cartsense_language_code_v1';

  Future<AppLanguage> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AppLanguage.byCode(preferences.getString(_key) ?? 'en');
  }

  Future<void> save(AppLanguage language) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, language.code);
  }
}

String appText(String languageCode, String key) {
  final localized = _translations[languageCode]?[key];
  if (localized != null) return localized;
  return _translations['en']?[key] ?? key;
}

const _translations = {
  'en': {
    'shoppingAssistant': 'Shopping Assistant',
    'estimatedBasket': 'Estimated basket',
    'startTrip': 'Start trip',
    'shareList': 'Share list',
    'smartTripAssistant': 'Smart trip assistant',
    'productsToBuy': 'Products to buy',
    'addProduct': 'Add product',
    'editProduct': 'Edit product',
    'scanShelfPrice': 'Scan shelf price label',
    'readingShelfPrice': 'Reading shelf price...',
    'tripMode': 'Trip mode',
    'inStoreChecklist': 'In-store checklist',
    'stillToBuy': 'Still to buy',
    'inCart': 'In cart',
    'extraPicked': 'Extra picked in store',
    'checkoutScanBill': 'Checkout done — scan bill',
    'setTripBudget': 'Set trip budget',
    'addExtraItem': 'Add extra item',
  },
  'hi': {
    'shoppingAssistant': 'खरीदारी सहायक',
    'estimatedBasket': 'अनुमानित बिल',
    'startTrip': 'खरीदारी शुरू करें',
    'shareList': 'सूची शेयर करें',
    'smartTripAssistant': 'स्मार्ट खरीदारी सहायक',
    'productsToBuy': 'खरीदने वाले सामान',
    'addProduct': 'सामान जोड़ें',
    'editProduct': 'सामान बदलें',
    'scanShelfPrice': 'शेल्फ कीमत स्कैन करें',
    'readingShelfPrice': 'शेल्फ कीमत पढ़ रहे हैं...',
    'tripMode': 'स्टोर मोड',
    'inStoreChecklist': 'स्टोर चेकलिस्ट',
    'stillToBuy': 'अभी खरीदना है',
    'inCart': 'कार्ट में',
    'extraPicked': 'स्टोर में अतिरिक्त लिया',
    'checkoutScanBill': 'बिल हो गया — स्कैन करें',
    'setTripBudget': 'ट्रिप बजट सेट करें',
    'addExtraItem': 'अतिरिक्त सामान जोड़ें',
  },
  'te': {
    'shoppingAssistant': 'షాపింగ్ అసిస్టెంట్',
    'estimatedBasket': 'అంచనా బిల్',
    'startTrip': 'షాపింగ్ మొదలుపెట్టు',
    'shareList': 'లిస్ట్ షేర్ చేయండి',
    'smartTripAssistant': 'స్మార్ట్ షాపింగ్ అసిస్టెంట్',
    'productsToBuy': 'కొనాల్సిన వస్తువులు',
    'addProduct': 'వస్తువు జోడించండి',
    'editProduct': 'వస్తువు మార్చండి',
    'scanShelfPrice': 'షెల్ఫ్ ధర స్కాన్ చేయండి',
    'readingShelfPrice': 'షెల్ఫ్ ధర చదువుతోంది...',
    'tripMode': 'స్టోర్ మోడ్',
    'inStoreChecklist': 'స్టోర్ చెక్‌లిస్ట్',
    'stillToBuy': 'ఇంకా కొనాల్సినవి',
    'inCart': 'కార్ట్‌లో',
    'extraPicked': 'స్టోర్‌లో అదనంగా తీసుకున్నవి',
    'checkoutScanBill': 'బిల్ అయింది — స్కాన్ చేయండి',
    'setTripBudget': 'ట్రిప్ బడ్జెట్ సెట్ చేయండి',
    'addExtraItem': 'అదనపు వస్తువు జోడించండి',
  },
};
