# Subscription account and database

**Date:** 2026-10-26. Revised 2026-10-28.
**Status:** Design, not a build plan. Nothing here is implemented.
**Depends on:** `docs/superpowers/specs/2026-09-21-conversation-technical-layer-design.md` (mint, 20 starts / calendar month, 1 concurrent session, 3 mints / 10 min, anonymous crisis counter, `possible_minor` flag, safety identifier, never-log list). Product shape stays in `docs/product-spec.md`.

This is an engineering reading of those locks plus BIPA, WOPRA, and SB 243 as the conversation spec already names them. Counsel still owns the consent screens and how long a bare transaction id is kept after deletion.

The 2026-10-28 revision picks the host, allows Google beside Apple, and closes holes in the first draft: purchase linking, provider revocation, a dead session lock, out-of-order App Store notifications, and a cap baked into the table.

---

## Where it runs

Cloudflare Workers for the API. Cloudflare D1 for the database. D1 is SQLite.

The workload is small and transactional. A conversation start is a handful of indexed reads and a few writes, at most about 20 times a month per subscriber, plus a webhook when Apple renews or refunds. Progress reads happen when someone opens history on a new phone. This is not a high-read catalog.

| Service | Fit for this app | Cost at the start |
|---|---|---|
| **Workers + D1** | One vendor. Writes are serialized, so the one-open-session check and the 10-minute mint window are safe inside one transaction. Queries do not cold-start. | $0 on Workers Free while building. **$5/month Workers Paid** before anyone pays. |
| Supabase | Postgres, and a free project pauses after a week of inactivity. A paused database drops App Store notifications, so entitlement goes stale. Pro starts at $25/month. | $0, then $25 |
| Neon | Postgres. Free compute sleeps after 5 minutes. That wake-up sits on the path where the person is waiting to start a conversation. | $0 with cold starts, then usage pricing above the $5 Workers plan |
| Turso | SQLite, like D1. Free databases archive after 10 days idle, which is the same webhook problem as a paused Supabase project. | $0, then $4.99 |
| PlanetScale | Postgres from $5/month, no free database. Still needs a separate API host. | $5 plus compute |

Workers Paid is the uptime step, not a feature step. The same Worker and the same D1 database move up. Paid removes three free-plan cliffs: the [10 ms CPU cap](https://developers.cloudflare.com/workers/platform/pricing/) per request (Apple and Google token checks can exceed it), the [daily D1 hard stop](https://developers.cloudflare.com/changelog/post/2026-09-01-d1-free-tier-limit-enforcement/) (since 2026-09-01, queries fail until midnight UTC after 5 million rows read or 100,000 rows written), and 7-day Time Travel. Paid includes 30-day Time Travel, which is the backup for a billing database. Included D1 usage on Paid is 25 billion rows read and 50 million rows written a month, then [$0.001 and $1.00 per extra million](https://developers.cloudflare.com/d1/platform/pricing/).

D1 bills rows scanned, not rows returned. Every lookup column in this schema is indexed so a mint does not scan the table.

No Redis and no Durable Object. The Cloudflare [rate-limit binding](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/) counts per data center, so two phones in two cities would each get 3 mints. D1 already serializes writes. `mint_attempts` is the 10-minute window. The Worker deletes that account's rows older than 10 minutes inside the mint transaction, then counts what remains. A lost database resets the window. It does not reset the month. Rows that survive are an account id and a timestamp, for at most 10 minutes. They cascade away with the account.

The monthly cap of 20 is configuration in the Worker, checked in that same transaction. It is not a `CHECK` on the column. Changing 20 must not be a migration.

---

## Locks

1. **Apple and Google can both sign a person in.** No email/password. The first sign-in creates the account. A second provider attaches only while they are already signed in. The same email address does not merge two accounts. Email is stored on the identity, only when that provider shares it. The product works with a null email.
2. **Conversation mint requires an active subscription.** Reading and Monologue still run on the phone with no account.
3. **Progress rows are written only after a separate opt-in.** Budget and entitlement are not optional.
4. **One App Store subscription maps to one account.** Family Sharing stays off. A second account cannot claim the same `original_transaction_id`. `accounts.id` is the StoreKit `appAccountToken` on every purchase.

The current Keychain UUID (`AccountStore`) stops being the mint credential once this account exists. Until then, mint behavior stays as built.

---

## What the database is for

The phone’s Keychain id dies on reinstall, so it cannot be the subscriber.

| Job | Why the phone is not enough | Table |
|---|---|---|
| Who this person is | The Keychain UUID dies with the phone, so the monthly cap and the subscription would reset | `accounts` |
| Which Apple or Google id is theirs | One person may sign in with either provider | `account_identities` |
| Proof they accepted a policy | A local flag cannot show which policy version they accepted | `consent_events` |
| Stay signed in | Provider identity tokens are short-lived. We store only a hash of our refresh token | `refresh_tokens` |
| Revoke the provider when they delete | Apple's revoke API needs the refresh token Apple issued. A hash cannot be sent back | `provider_credentials` |
| Provider account changes | Apple notifies us when email forwarding, consent, or the Apple Account changes | `identity_events` |
| Paid entitlement | Apple charges them. We mirror status so mint can refuse an expired sub without trusting the phone | `subscriptions` |
| Notification replay and ordering | App Store Server Notifications V2 can be delivered twice, and out of order | `app_store_notifications` |
| 20 starts in their calendar month | Already specified as server-enforced, in the account timezone | `conversation_months` |
| One open conversation | A second phone must not mint a second live session | `conversation_sessions` |
| 3 mints / 10 minutes | A per-city counter would give each city its own 3 | `mint_attempts` |
| Numeric progress on a new phone | Reports today exist only in memory on this phone | `practice_sessions` and the metric tables |
| Crisis volume | The spec counts referrals and forbids attaching them to a person | `crisis_referral_days` |
| A freeze that survives deletion | A new account on a known provider id must not mint a new OpenAI safety hash | `mint_blocks` |
| A purchase record with the person removed | Apple transaction disputes can outlive the account. The row has no user id | `financial_retention` |

**Not in this database:** devices and push tokens (until daily pushes exist), audio of any kind, GOP score rows (until that scorer exists), a coach inbox (until that product has its own consent).

---

## What we can keep

Two piles. The first is required to sell the subscription and enforce the cap. The second is practice numbers, and only after they opt in. Both are deleted with the account, except the anonymous crisis counter and a purchase id that no longer points at them.

### Required for the paid product

Provider subject, optional email on that identity, IANA timezone, 18+ timestamp (no date of birth), subscription status and expiry, consent version and time, mint time, billed seconds, hang-up enum, month start count.

The conversation technical layer already allows mint metadata, duration, hang-up enum, and billed seconds.

The provider refresh token is stored encrypted. The key lives in a Worker secret. The database holds ciphertext. Our own refresh token is stored as a SHA-256 hash. Those are different tokens.

### Optional progress sync

The numbers the on-device reports already show. No population norms.

- **Conversation:** speech seconds, turn count, pace (raw syllables/minute, no target), pause seconds (duration only), filled-pause count, English-slip count, language-uncertain flag.
- **Reading:** catalog `passage_id`, match / skip / extra / substitute counts, script word count, completeness ratio, stall count, speech rate, and a miss count per phone symbol plus functional-load band.
- **Monologue:** catalog `prompt_id` when the prompt came from the bank, the generated comparison line, and per take: wall seconds, spoken seconds, phonation-time ratio, pause seconds, gap count (silences ≥ 250 ms), pace, overlap percent versus the previous counting take.

At the first opt-in, the phone uploads the practice numbers already on that device, then each new session while sync stays on. `client_report_id` makes a retry the same row. The upload is the numeric report only. The recording stays on the phone that made it.

Turning sync off sets `progress_sync_at` null and appends a `progress_sync_off` consent event. Rows already stored stay. The phone uploads nothing while it is null. Turning it on again sets `progress_sync_at` and uploads sessions that happen after that time. Sessions from the off window stay on the phone and are not sent later.

### Safety flags, not content

`possible_minor` flag and date. `mint_frozen` with reason `possible_minor` or `safety_block`. The words that triggered either flag are not stored.

OpenAI safety identifier: `HMAC-SHA256(server_pepper, account_id)` hex, computed at mint, sent to OpenAI, not stored. Never log it next to the account id. If OpenAI blocks it: generic unavailable, freeze mint, do not issue a new hash.

---

## What never gets a column

| Data | Where it stays | Why |
|---|---|---|
| Audio, PCM, AAC, waveforms | Conversation: process and delete. Monologue: this phone only | BIPA and WOPRA treat a voiceprint as biometric. The spec already forbids upload and speaker embeddings |
| Transcripts, notes, custom topic text, partner speech, stance card | On the phone for the live session. Monologue transcript stays in the local recording | Technical layer: never log ASR text, partner transcript, or stance card |
| Crisis words, and any mark that this account hit crisis | Anonymous daily counter only | Spec: crisis referral has no user id and no transcript |
| The sentence that triggered a minor flag | Flag and timestamp on the account | Spec: not the utterance |
| OpenAI safety identifier beside the account id | Computed at mint. Not stored | Spec: never log the hash next to the account id |
| Card numbers, precise location, advertising id, birth date, disability | Apple holds payment. Timezone is a region name they can change | Not needed to run practice or billing |
| Filler locations and word-by-word reading rows | On-device report | A count or a phone symbol is enough for a personal trend. The words reconstruct the take |
| Coach audio and GOP audio slices | Not this database. A later queue would delete the bytes after scoring | Separate biometric consent. Out of this schema until that product exists |
| Plaintext provider refresh token | Ciphertext in `provider_credentials`. Key in a Worker secret | Needed to call Apple's revoke API on deletion. A hash cannot be revoked |

A topic the person typed themselves is not stored. `monologue_regimens.prompt_id` stays null. Their notes stay on the phone.

---

## How a paid conversation starts

1. The phone signs in with Apple or Google. The Worker checks the identity token against that provider's keys, upserts `account_identities` and `accounts`, and returns a short-lived access token. Our refresh token is random, one family per sign-in. The database stores its SHA-256. Reuse of a revoked token in that family revokes the whole family.
2. Linking a second provider happens on a request that already carries our access token. If that provider subject already belongs to another account, the link is refused.
3. The purchase uses `accounts.id` as StoreKit `appAccountToken`. App Store Server Notifications V2 carry that token back. Insert `notification_uuid` first. A duplicate delivery stops there. Apply the body only when its `signed_at` is strictly newer than `subscriptions.last_signed_at`. An older notification cannot clear `entitled`. The phone cannot talk the server into `entitled`. The signed payload is not stored.
4. Start is one D1 batch, which runs as one transaction. The Worker, not the phone, checks: account exists, not frozen, `subscriptions.entitled` is 1, `starts_used` is under the configured cap for the open calendar month, expired open sessions for this account are closed, no `conversation_sessions` row is still `minted` or `started`, and this account has fewer than 3 `mint_attempts` in the last 10 minutes.
5. The month boundary uses `conversation_months.timezone`, frozen when that row is created. Changing `accounts.timezone` applies to the next month, so a timezone change cannot grant a second month.
6. `conversation_sessions.id` is the UUID the phone generated. A retry of the same id is the same row.
7. A `minted` row leases for 3 minutes (the 120-second OpenAI secret, plus slack). Moving to `started` sets the lease to 30 minutes from `started_at` (15-minute wall clock, plus the 10-minute pause TTL, plus slack for the hang-up call). These two durations are locked. A cron closes expired leases. The start transaction also closes this account's expired lease, so correctness does not depend on the cron. `end_reason` for that close is `lease_expired`.
8. Mint computes the OpenAI safety identifier, sends it with the ephemeral key, and does not write it down. Audio goes to OpenAI, not to us.
9. When the session counts as a start, set `started_at` and `counts_as_start` and increment `starts_used`. A drop before that does not consume a start.
10. On hang-up the phone reports billed seconds and an end reason from `user_stop`, `wrap`, `pause_ttl`, `drop`, `config_drift`.
11. A crisis ending uploads no practice row. The server increments `crisis_referral_days` for that UTC day and closes the open session with `end_reason` left null, so the one-session lock releases without labeling the account.
12. If `progress_sync_at` is set, a second call uploads the numeric report. Unknown fields are rejected. The call is refused when `progress_sync_at` is null. `client_report_id` makes retries safe. Turning sync off does not delete practice rows.

`entitled` is copied from Apple. Mint checks that flag. Status is for display and support.

### Provider notifications

Apple server-to-server events land in `identity_events`, keyed by the JWT `jti`. A duplicate `jti` stops there. The signed JWT is not stored.

- `email-disabled`: clear `account_identities.email` for that Apple subject. The next sign-in can write it again.
- `email-enabled`: record the event. The address arrives on the next sign-in, not in the notification.
- `consent-revoked` or `account-deleted`: delete that identity. If it was the last identity on the account, run the deletion procedure below. If another identity remains, the account, the subscription, and the practice rows stay.

---

## Deletion

In-app deletion is required. The Worker calls the provider revoke endpoint with the decrypted refresh token, then:

1. If `mint_frozen`, insert one `mint_blocks` row per linked identity: `HMAC-SHA256(server_pepper, provider || ':' || subject)` and the freeze reason. These rows have no `account_id`. Sign-in recomputes the hash and refuses to create an account for that provider subject. A provider that was never linked is not blocked. That limit is accepted.
2. Copy `original_transaction_id`, `product_id`, and `environment` into `financial_retention`. No user id. Counsel sets when this row is purged.
3. Delete the `subscriptions` row (`on delete restrict` on the account foreign key forces this first).
4. Delete the account. Cascade removes identities, provider credentials, consent, refresh tokens, mint attempts, conversation months, conversation sessions, and practice rows.

`crisis_referral_days` is left as it is. It never pointed at the person.

`mint_blocks` is written at deletion, not while the account row still exists, so the hash and the account id do not sit together in normal operation.

Server deletion does not erase recordings on the phone. After they confirm account deletion, a second prompt asks whether to delete local recordings on this phone too. Yes erases the local reports and recordings on this phone. No leaves them. Another phone does not erase its copy in the background. The next time that phone opens and the account is gone, it asks the same question.

---

## Schema

D1 (SQLite). Ids are UUID strings. Times are ISO-8601 UTC text, written by the Worker. Flags are integers, 0 or 1. Foreign keys are enforced by D1.

```sql
create table accounts (
  id text primary key, -- also the StoreKit appAccountToken
  timezone text not null,
  created_at text not null,
  attested_18_at text,
  possible_minor integer not null default 0 check (possible_minor in (0, 1)),
  possible_minor_at text,
  mint_frozen integer not null default 0 check (mint_frozen in (0, 1)),
  mint_frozen_reason text,
  progress_sync_at text,
  check (possible_minor = 0 or possible_minor_at is not null),
  check (mint_frozen = 0 or mint_frozen_reason in ('possible_minor', 'safety_block')),
  check (mint_frozen = 1 or mint_frozen_reason is null)
);

create table account_identities (
  id text primary key,
  account_id text not null references accounts (id) on delete cascade,
  provider text not null check (provider in ('apple', 'google')),
  subject text not null,
  email text,
  created_at text not null,
  unique (provider, subject),
  check (email is null or length(email) <= 320)
);

create index account_identities_account
  on account_identities (account_id);

create table provider_credentials (
  account_identity_id text primary key
    references account_identities (id) on delete cascade,
  refresh_token_ciphertext text not null,
  updated_at text not null
);

create table identity_events (
  event_id text primary key, -- provider JWT jti
  provider text not null check (provider in ('apple', 'google')),
  event_type text not null,
  subject text not null,
  received_at text not null
);

create table consent_events (
  id text primary key,
  account_id text not null references accounts (id) on delete cascade,
  kind text not null check (kind in (
    'terms', 'privacy', 'ai_disclosure', 'voice_to_openai', 'progress_sync',
    'progress_sync_off'
  )),
  policy_version text not null,
  accepted_at text not null,
  app_version text not null
);

create index consent_events_account
  on consent_events (account_id, accepted_at);

create table refresh_tokens (
  id text primary key,
  account_id text not null references accounts (id) on delete cascade,
  family_id text not null,
  token_hash text not null unique,
  expires_at text not null,
  revoked_at text
);

create index refresh_tokens_account
  on refresh_tokens (account_id);

create index refresh_tokens_family
  on refresh_tokens (family_id);

create table subscriptions (
  id text primary key,
  account_id text not null references accounts (id) on delete restrict,
  original_transaction_id text not null unique,
  product_id text not null,
  status text not null check (status in (
    'active', 'expired', 'in_grace', 'in_billing_retry', 'revoked', 'refunded'
  )),
  entitled integer not null check (entitled in (0, 1)),
  environment text not null check (environment in ('sandbox', 'production')),
  current_period_start text not null,
  expires_at text not null,
  will_renew integer not null check (will_renew in (0, 1)),
  last_signed_at text not null,
  updated_at text not null
);

create index subscriptions_account
  on subscriptions (account_id);

create unique index subscriptions_one_production
  on subscriptions (account_id)
  where environment = 'production';

create table app_store_notifications (
  notification_uuid text primary key,
  original_transaction_id text not null,
  app_account_token text, -- accounts.id when Apple included one
  notification_type text not null,
  subtype text,
  signed_at text not null,
  received_at text not null
);

create index app_store_notifications_transaction
  on app_store_notifications (original_transaction_id);

create table conversation_months (
  account_id text not null references accounts (id) on delete cascade,
  month_start text not null, -- YYYY-MM-DD in the frozen timezone
  timezone text not null,
  starts_used integer not null default 0 check (starts_used >= 0),
  primary key (account_id, month_start)
);

create table conversation_sessions (
  id text primary key, -- client-generated UUID; a retry is the same row
  account_id text not null references accounts (id) on delete cascade,
  state text not null check (state in ('minted', 'started', 'ended')),
  minted_at text not null,
  started_at text,
  ended_at text,
  lease_until text not null,
  end_reason text check (end_reason in (
    'user_stop', 'wrap', 'pause_ttl', 'drop', 'config_drift', 'lease_expired'
  )),
  billed_seconds integer check (billed_seconds is null or billed_seconds >= 0),
  counts_as_start integer not null default 0 check (counts_as_start in (0, 1))
);

create unique index conversation_one_open
  on conversation_sessions (account_id)
  where state in ('minted', 'started');

create index conversation_sessions_account
  on conversation_sessions (account_id, minted_at);

create table mint_attempts (
  id text primary key,
  account_id text not null references accounts (id) on delete cascade,
  attempted_at text not null
);

create index mint_attempts_account_time
  on mint_attempts (account_id, attempted_at);

create table practice_sessions (
  id text not null,
  account_id text not null references accounts (id) on delete cascade,
  format text not null check (format in ('conversation', 'reading', 'monologue')),
  client_report_id text not null,
  occurred_at text not null,
  duration_seconds real not null check (duration_seconds >= 0),
  kind text not null check (kind in ('thin', 'full')),
  limited_analysis integer not null default 0 check (limited_analysis in (0, 1)),
  primary key (id),
  unique (id, format),
  unique (account_id, client_report_id)
);

create index practice_sessions_account_time
  on practice_sessions (account_id, occurred_at);

create table conversation_metrics (
  practice_session_id text not null,
  format text not null default 'conversation' check (format = 'conversation'),
  speech_seconds real not null check (speech_seconds >= 0),
  turn_count integer not null check (turn_count >= 0),
  pace_syllables_per_minute real,
  pause_seconds real,
  filled_pause_count integer,
  english_slip_count integer,
  language_uncertain integer check (language_uncertain in (0, 1)),
  primary key (practice_session_id),
  foreign key (practice_session_id, format)
    references practice_sessions (id, format) on delete cascade
);

create table reading_metrics (
  practice_session_id text not null,
  format text not null default 'reading' check (format = 'reading'),
  passage_id text not null,
  match_count integer not null,
  skip_count integer not null,
  extra_count integer not null,
  substitute_count integer not null,
  script_word_count integer not null,
  completeness_ratio real not null,
  stall_event_count integer not null,
  speech_rate_syllables_per_minute real not null,
  primary key (practice_session_id),
  foreign key (practice_session_id, format)
    references practice_sessions (id, format) on delete cascade
);

create table reading_phone_misses (
  practice_session_id text not null references reading_metrics (practice_session_id) on delete cascade,
  phone text not null,
  fl_band text not null,
  miss_count integer not null check (miss_count > 0),
  primary key (practice_session_id, phone)
);

create table monologue_regimens (
  practice_session_id text not null,
  format text not null default 'monologue' check (format = 'monologue'),
  prompt_id text,
  comparison text,
  primary key (practice_session_id),
  foreign key (practice_session_id, format)
    references practice_sessions (id, format) on delete cascade
);

create table monologue_takes (
  practice_session_id text not null references monologue_regimens (practice_session_id) on delete cascade,
  take_index integer not null check (take_index >= 1),
  wall_seconds real not null,
  spoken_seconds real not null,
  phonation_time_ratio real,
  pause_seconds real not null,
  gap_count integer not null,
  pace_syllables_per_minute real,
  overlap_percent real,
  primary key (practice_session_id, take_index)
);

create table crisis_referral_days (
  day text primary key, -- YYYY-MM-DD UTC
  event_count integer not null check (event_count >= 0)
);

create table mint_blocks (
  subject_hash text primary key,
  reason text not null check (reason in ('possible_minor', 'safety_block')),
  blocked_at text not null
);

create table financial_retention (
  original_transaction_id text primary key,
  product_id text not null,
  environment text not null check (environment in ('sandbox', 'production')),
  retained_at text not null
);
```

`practice_sessions` is unique on `(id, format)` so a metric table cannot attach to the wrong format. Conversation, reading, and monologue metrics each pin `format` to their own value and foreign-key `(practice_session_id, format)`.

---

## Left out on purpose

- No `devices` table until push notifications exist.
- No audio bucket.
- No GOP score table until that scorer exists. Its audio would be a short-lived file, not a row.
- No coach inbox until that product has its own consent.
- No IP address column on consent or mint.
- No separate identities merge on equal email.
