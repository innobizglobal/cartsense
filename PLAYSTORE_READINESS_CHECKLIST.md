# CartSense Play Store readiness checklist

## Current release candidate

- App name: CartSense
- Package name: `com.innobizglobal.cartsense_lite`
- Release version: `1.0.0`
- Version code: `16`
- Release artifact needed by Play Console: Android App Bundle (`.aab`)
- Signing approach: local upload key / Play App Signing compatible

## Ready

- Branded launcher icon is present.
- App label is `CartSense`.
- Android package name is stable.
- Release builds use a private upload keystore when the signing variables are supplied.
- App supports authenticated and guest flows.
- Receipt scan, shopping list, bills, insights, language selection and account entry points are present.

## Permissions to declare in Play Console

- Internet: used for AI receipt scan, Supabase login/cloud sync and price intelligence API.
- Microphone: used for voice shopping-list input.
- Notifications: used for optional shopping reminders.
- Run at startup: used to keep reminder scheduling available after phone restart.

## Data Safety draft answers

- The app may collect account identifiers such as email/name when the user signs in.
- The app may process receipt images and extracted grocery items for receipt scanning and shopping insights.
- The app may store shopping lists, receipts, family profile preferences and budget settings.
- Data is used for app functionality, personalization, analytics and backup/sync where enabled.
- If anonymous FMCG analytics is enabled, product/category/store/pricing trends should be aggregated and not tied to personally identifiable users.
- Do not sell personal data. If FMCG reports are sold later, sell only aggregated anonymous insights.

## Before production public launch

- Create a public privacy policy URL.
- Complete Google Play Data Safety form using the latest permissions and cloud-sync behavior.
- Upload the `.aab` to Internal testing first.
- Test login, scanning, long receipt capture, shopping list, bills and language flows on at least two Android phones.
- Keep the upload key and password file private. Do not upload them to GitHub.
