# Launch finish line

**Date:** 2026-10-28
**Status:** Order of work. Not a build plan for any one issue.

The account design is `docs/superpowers/specs/2026-10-26-subscription-account-schema-design.md`. The open launch issues are the `before-launch` label. Do these in order. A later step that needs an earlier one waits.

## Floor

iOS 26. iPhone 11 and newer, including iPhone SE (2nd generation and later), iPhone 16e, iPhone 17e, and iPhone Air. `ios/project.yml` already says `26.0`.

There is no iOS 25. Apple went from iOS 18 to iOS 26. `glassEffect` arrived with iOS 26 and has no earlier version. Staying on 26 keeps the glass and the SpeechAnalyzer backup without wrappers.

That list is seven numbered generations, iPhone 11 through iPhone 17, plus the SE, 16e, 17e, and Air. iPhone XR and XS cannot install iOS 26. iPhone 8 and X cannot either.

## Steps

### 1. Floor — done

[#65](https://github.com/ibbi1020/SpeechApp/issues/65). Decided here. Listing copy that names the floor is step 6. One iPhone 11 running all three exercises is step 7.

### 2. Apple Developer team and production bundle id

[#63](https://github.com/ibbi1020/SpeechApp/issues/63). The paid account is already on a teammate. What they still have to do:

- Add the person who ships builds as Admin or App Manager, and send the Team ID.
- Register `com.speechapp.orator` and `com.speechapp.orator.widget`. Enable Sign in with Apple on the app id. The string can differ. It must not contain `prototype`.
- Create the Orator record in App Store Connect.
- Sign the Paid Applications agreement and finish banking and tax. Only the Account Holder can do this. A subscription cannot be submitted without it.

The project bundle ids are `com.speechapp.orator` and `com.speechapp.orator.widget`. Signing uses team `Q2Z32YFFGP`. The App Store Apple ID is `6818527258`. The old prototype Keychain UUID is not migrated. Later, this team creates the Sign in with Apple key and the App Store Server API key. Not this step.

### 3. Privacy policy

[#22](https://github.com/ibbi1020/SpeechApp/issues/22). Start this beside step 2. Counsel writes it. The inventory they need:

- Conversation audio goes to xAI `grok-voice-3.0`. It does not go to OpenAI and it is not stored by us.
- Reading, Monologue, and listen-back go to xAI `grok-voice-transcribe-2.0`.
- Pause, pace, and review markers run on the phone.
- Recordings stay on the phone. A deleted app does not get them back ([#71](https://github.com/ibbi1020/SpeechApp/issues/71), closed).
- Practice numbers upload only after opt-in.
- The xAI org key must not be in the app ([#61](https://github.com/ibbi1020/SpeechApp/issues/61)).

Ship of Conversation is blocked until this page exists. The store listing needs its URL.

### 4. Worker, D1, then the key off the phone

[#62](https://github.com/ibbi1020/SpeechApp/issues/62), then [#61](https://github.com/ibbi1020/SpeechApp/issues/61).

Host is Cloudflare Workers and D1. Free while building. Workers Paid at $5 a month before anyone pays. No Redis. D1 database `orator` (`3a8b1690-6ace-458d-a8c7-3b658d02d07e`) has the prototype mint tables. The Worker is `https://orator-mint.ibraheemfrq.workers.dev`, and `XAI_API_KEY` is set there. The app calls that URL. The build no longer copies `XAISecrets.plist`.

Inside the step, in this order:

1. Sign in with Apple and Google, checked on the Worker.
2. Subscription mirror and App Store Server Notifications. The phone cannot set `entitled`.
3. The start transaction: not frozen, subscribed, under 20 starts, one open session, 3 mints in 10 minutes.
4. Numeric progress upload. No audio, no transcript.

Reading and Monologue must still start when the Worker is down. Conversation must not.

### 5. Account screens

After step 4 can answer a real sign-in.

- [#16](https://github.com/ibbi1020/SpeechApp/issues/16) Onboarding, including 18+ and the AI disclosure.
- [#17](https://github.com/ibbi1020/SpeechApp/issues/17) Sign in with Apple and Google. No email merge. Reading and Monologue work with no account.
- [#19](https://github.com/ibbi1020/SpeechApp/issues/19) Profile. No stored name.
- [#18](https://github.com/ibbi1020/SpeechApp/issues/18) Paywall. The price is not set. Put a number on the screen only after one `grok-voice-3.0` conversation has a real cost. The old $0.35–$0.75 figure was an OpenAI estimate. Never show the paywall during a live talk. Reading and Monologue stay outside it.
- [#21](https://github.com/ibbi1020/SpeechApp/issues/21) Manage subscription.
- [#24](https://github.com/ibbi1020/SpeechApp/issues/24) Delete account, then a second prompt for local recordings.

### 6. App Store packet

[#64](https://github.com/ibbi1020/SpeechApp/issues/64). After steps 2 and 3. Privacy manifest, nutrition labels that match step 3, export compliance, screenshots, age rating, support URL, review notes. Name iOS 26 and iPhone 11 and newer. Do not claim on-device-only audio. Do not name OpenAI.

### 7. TestFlight on an iPhone 11

No Mac on the network. No xAI key in the app. Reading, a topic talk, and one paid conversation all work. Delete the app, install it again, sign in: the numbers return, the audio does not.

### 8. Crash reporting

[#66](https://github.com/ibbi1020/SpeechApp/issues/66). Before a wider TestFlight. Screen and format only. No transcripts, no audio, no Apple or Google id. Name the reporter in the privacy policy and the Privacy Manifest.

### 9. GOP last

[#67](https://github.com/ibbi1020/SpeechApp/issues/67). Reading already hides pronunciation scores while they are unassessed. Not required to submit the store form. No GOP table in the account database.

## Not on this list

- [#71](https://github.com/ibbi1020/SpeechApp/issues/71) Recordings upload. Closed. Sound stays on the phone.
- [#68](https://github.com/ibbi1020/SpeechApp/issues/68) Splash. Closed.
- [#56](https://github.com/ibbi1020/SpeechApp/issues/56) Ceremony. Product quality. Any time. Does not block the store.
