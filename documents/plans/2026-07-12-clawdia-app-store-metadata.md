# Clawdia App Store metadata refresh

## Goal

Complete the new App Store Connect record for Clawdia by Sycamore and make the repository's iOS branding artifacts consistent with the new app identity.

## Scope

1. Audit the new App Store Connect record and current iOS target settings.
2. Adapt the existing ScarfGo listing copy to Clawdia and the app's current feature set.
3. Fill the non-sensitive App Information and iOS version metadata fields.
4. Keep review credentials and private contact details untouched.
5. Replace the iOS icon asset set with the supplied Clawdia portrait and verify that the 1024x1024 master is packaged by the iOS target; note that App Store Connect displays it only after a processed build is uploaded.
6. Record the canonical Clawdia listing copy in `releases/v2.16.0/APP_STORE_METADATA.md`.

## Verification

- Re-read the saved App Store Connect fields.
- Confirm every listing field is within Apple's displayed character limits.
- Run an unsigned iOS build or asset-catalog validation if source files change.
- Confirm the app icon source is 1024x1024 and referenced by the `AppIcon` asset set.

## Deferred / requires owner input

- App Review sign-in credentials and reviewer contact information.
- Final screenshots if no current App Store-size captures exist.
