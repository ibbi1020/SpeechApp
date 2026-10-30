# Paid Apple team

**Date:** 2026-10-30
**Do this only after the paid team exists.** Each block says who can click it. Do the blocks in order. The project already uses `com.speechapp.orator`, `com.speechapp.orator.widget`, and team `Q2Z32YFFGP`. Sign in with Apple is in `ios/App/SpeechApp.entitlements`.

The two bundle ids to register, unless the teammate picks different ones. They must not contain `prototype`.

- App: `com.speechapp.orator`
- Widget: `com.speechapp.orator.widget`

## 1. Invite the person who ships builds

Who: Account Holder or Admin, in App Store Connect.
Source: [Add and edit users](https://developer.apple.com/help/app-store-connect/manage-your-team/add-and-edit-users/).

1. Open [App Store Connect](https://appstoreconnect.apple.com) → Users and Access.
2. Click the add button (+).
3. Enter the shipper’s first name, last name, and Apple Account email.
4. Role: Admin. App Manager is enough to upload builds. Admin is required for the keys in blocks 7 and 8.
5. Click Invite. The invite expires in 3 days.
6. After they accept, send them the 10-character Team ID. It is under [Membership details](https://developer.apple.com/account) on the developer account.

## 2. Register the two App IDs

Who: Account Holder or Admin.
Source: [Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id/) and [Enable Sign in with Apple](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/).

1. Open [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources) → Identifiers → +.
2. Choose App IDs → Continue. App ID type is App → Continue.
3. Description: `Orator`. Bundle ID: Explicit, `com.speechapp.orator`.
4. Under Capabilities, turn on Sign in with Apple. Click Configure. Choose “Enable as a primary App ID”. Leave the server-to-server URL empty. Save.
5. Continue → Register.
6. Repeat for the widget. Description: `Orator Widget`. Bundle ID: Explicit, `com.speechapp.orator.widget`. Do not turn on Sign in with Apple for the widget. Continue → Register.

In-App Purchase is already on for an explicit App ID. Do not add a wildcard id.

## 3. Paid Applications agreement, bank, and tax

Who: Account Holder only. An Admin cannot sign this.
Source: [Sign and update agreements](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/).

A new app record cannot be created until this agreement is signed.

1. App Store Connect → Business.
2. On the Agreements tab, Paid Apps row → View and Agree to Terms.
3. Read the terms. Click Agree. This cannot be undone.
4. On that same Paid Apps row, complete the bank account and the tax forms. Status has to leave “Pending” before a subscription can be submitted.

## 4. Create the Orator record

Who: Account Holder, Admin, or App Manager.
Source: [Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).

1. App Store Connect → Apps → + → New App.
2. Platform: iOS.
3. Name: `Orator`.
4. Primary language: English (U.S.).
5. Bundle ID: choose `com.speechapp.orator` from the menu. If it is missing, block 2 did not finish.
6. SKU: `orator`. This is an internal id. It is not shown on the store.
7. User Access: Full Access.
8. Click Create.
9. App Information shows a numeric Apple ID. For Orator that number is `6818527258`. It is not the Team ID. Do not paste it into `DEVELOPMENT_TEAM`.

## 5. Point the Xcode project at the new team

Who: whoever edits the repo. Do this before the device sign-in test.

The two bundle ids and team `Q2Z32YFFGP` are already in `ios/project.yml` and the Xcode project. Leave the App Store Apple ID `6818527258` out of `DEVELOPMENT_TEAM`.

Regenerate the project if you use XcodeGen, then reload the project in Xcode. A device build must be signed by the new team before block 6.

## 6. Sign in with Apple on a device

Who: the shipper, on a phone, after block 5.

The button and the Sign in with Apple entitlement are already in the app.

1. In Xcode → Settings → Accounts, sign in with an Apple ID that belongs to team `Q2Z32YFFGP`.
2. Build to a device with that team. The system sheet has to return. Cancel is a quiet stay on the screen. Success opens Home.
3. If signing fails with a missing profile, confirm block 2 used the same bundle id as `project.yml`.

The screen keeps the Apple user id in memory for that launch. It does not send it to the Worker. The Worker check waits on the key in block 7.

## 7. Sign in with Apple key

Who: Account Holder or Admin.
Source: [Create a Sign in with Apple private key](https://developer.apple.com/help/account/capabilities/create-a-sign-in-with-apple-private-key/).

The phone can show Apple’s sheet without this key. The Worker cannot revoke Apple on account deletion without it.

1. Certificates, Identifiers & Profiles → Keys → +.
2. Key name: `Orator Sign in with Apple`.
3. Turn on Sign in with Apple → Configure → choose the primary App ID `com.speechapp.orator` → Save.
4. Continue → Register.
5. Download the `.p8`. Apple allows this once. Copy the Key ID from the same page. The file name is `AuthKey_` plus that Key ID.
6. Store the file outside the repo. It becomes a Worker secret, together with the Key ID and the Team ID. Do not commit it.

Server-to-server notices (email hidden, consent revoked, Apple Account deleted) use one URL on the primary App ID. Leave that URL empty until the Worker route exists. Then: Identifiers → `com.speechapp.orator` → Sign in with Apple → Configure → paste the absolute `https://` URL → Save. Source: [Enabling server-to-server notifications](https://developer.apple.com/help/account/capabilities/enabling-server-to-server-notifications/).

## 8. In-App Purchase key

Who: Account Holder or Admin.
Source: [Generate keys for In-App Purchases](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/generate-keys-for-in-app-purchases/).

1. App Store Connect → Users and Access → Integrations.
2. Sidebar, under Keys: In-App Purchase.
3. Generate In-App Purchase Key. Name: `Orator App Store Server`.
4. Download the `.p8` once. Copy the Key ID and the Issuer ID shown on that page.
5. Store the file outside the repo, as a Worker secret. Do not commit it.

## 9. Subscription, with no price

Who: Account Holder, Admin, or App Manager. Block 3 has to be active.

Do not type a price. One real `grok-voice-3.0` conversation has to be costed first.

1. App Store Connect → Apps → Orator.
2. Sidebar, Monetization → Subscriptions.
3. Create a subscription group. Name: `Orator`.
4. Create one auto-renewable subscription inside it. Reference name and product id can be `orator.monthly`. Family Sharing: off.
5. Leave the price empty. Do not submit the subscription.

App Store Server Notifications Version 2 get a production URL and a sandbox URL on the app’s App Information page. Leave both empty until the Worker route exists. When it does, choose Version 2 and paste those two `https://` URLs. A URL that 404s will drop renewals.

## 10. Google client for the production bundle id

Who: whoever owns the Google Cloud project. Do this after block 5, so the bundle id is already the production one.

The bundle ID on an iOS client can be edited later, while App Check is off. Google’s own warning is that turning on App Check freezes that field, and the only fix is a new client. Leave App Check off. Source: [App Check for Google Sign-in on iOS](https://developers.google.com/identity/sign-in/ios/appcheck/get-started).

The app reads one field, `GOOGLE_CLIENT_ID` in `ios/project.yml`. If you do create a second client, paste the new id into that field.

1. Open [Google Auth Platform clients](https://console.cloud.google.com/auth/clients).
2. Create client → iOS. Name: `Orator iOS`.
3. Bundle ID: the production id from block 5, `com.speechapp.orator` unless it was changed.
4. Team ID: the Team ID from block 1. Leave App Check off.
5. Create. Copy the client ID (it ends in `.apps.googleusercontent.com`).
6. Paste it into `GOOGLE_CLIENT_ID` in `ios/project.yml`.
7. On that same client, copy the iOS URL scheme (`com.googleusercontent.apps.` plus the front of the client id). Add it under `CFBundleURLSchemes` in `ios/project.yml`, next to `orator`.
8. If Google also shows a client secret, leave it out of the app and out of git.

The client id and the URL scheme are already in `ios/project.yml`. When the app’s bundle id changes, edit the bundle ID on this same Google client. Leave App Check off. The client id stays put.

## 11. TestFlight

Who: Admin or App Manager, after blocks 4 and 5.

A personal-team install expires in 7 days. This build does not.

1. In Xcode, destination Any iOS Device → Product → Archive.
2. Distribute App → App Store Connect → Upload.
3. The archive’s bundle id must be the production id. The signing team must be the Team ID from block 1.
4. On an iPhone 11 running iOS 26: install from TestFlight. Reading, a topic talk, and one conversation each have to start. Conversation still cannot start while the Worker is down.

The store listing (screenshots, age rating, privacy URL, nutrition labels) is a later packet. It needs this same app record, and it needs a privacy policy URL counsel has approved. Do not submit the listing from this list.
