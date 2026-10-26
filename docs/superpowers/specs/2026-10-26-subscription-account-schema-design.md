# Subscription account and database

**Date:** 2026-10-26
**Status:** Design accepted and stored. Not a build plan. Nothing here is implemented.
**Depends on:** `docs/superpowers/specs/2026-09-21-conversation-technical-layer-design.md` (mint, 20 starts / calendar month, 1 concurrent session, 3 mints / 10 min, anonymous crisis counter, `possible_minor` flag, safety identifier, never-log list). Product shape stays in `docs/product-spec.md`.

This is an engineering reading of those locks plus BIPA, WOPRA, and SB 243 as the conversation spec already names them. Counsel still owns the consent screens and how long a bare transaction id is kept after deletion.

---

## Locks

1. **Sign in with Apple is the account.** No email/password. Email is stored only when the person shares it. The product works with a null email.
2. **Conversation mint requires an active subscription.** Reading and Monologue still run on the phone with no account.
3. **Progress rows are written only after a separate opt-in.** Budget and entitlement are not optional.
4. **One App Store subscription maps to one account.** Family Sharing stays off. A second Sign in with Apple account cannot claim the same `original_transaction_id`.

The current Keychain UUID (`AccountStore`) stops being the mint credential once this account exists. Until then, mint behavior stays as built.

---

## What the database is for

The phone’s Keychain id dies on reinstall, so it cannot be the subscriber.

| Job | Why the phone is not enough | Table |
|---|---|---|
| Who this person is | The Keychain UUID dies with the phone, so the monthly cap and the subscription would reset | `accounts` |
| Proof they accepted a policy | A local flag cannot show which policy version they accepted | `consent_events` |
| Stay signed in | The Apple identity token is short-lived. We store only a hash of our refresh token | `refresh_tokens` |
| Paid entitlement | Apple charges them. We mirror status so mint can refuse an expired sub without trusting the phone | `subscriptions` |
| Notification replay | App Store Server Notifications V2 can be delivered twice | `app_store_notifications` |
| 20 starts in their calendar month | Already specified as server-enforced, in the account timezone | `conversation_months` |
| One open conversation | A second phone must not mint a second live session | `conversation_sessions` |
| Numeric progress on a new phone | Reports today exist only in memory on this phone | `practice_sessions` and the metric tables |
| Crisis volume | The spec counts referrals and forbids attaching them to a person | `crisis_referral_days` |
| A freeze that survives deletion | A new account must not mint a new OpenAI safety hash after a minor flag or a safety block | `mint_blocks` |
| A purchase record with the person removed | Apple transaction disputes can outlive the account. The row has no user id | `financial_retention` |

**Redis, not Postgres:** mint rate (3 attempts / 10 minutes) is key `mint_rate:{account_id}`, an integer with a 10-minute TTL. The fourth mint inside the window is refused. Losing Redis resets that window. It does not reset the month. Nothing about the attempt is written to Postgres.

**Not in this database:** devices and push tokens (until daily pushes exist), audio of any kind, GOP score rows (until that scorer exists), a coach inbox (until that product has its own consent).

---

## What we can keep

Two piles. The first is required to sell the subscription and enforce the cap. The second is practice numbers, and only after they opt in. Both are deleted with the account, except the anonymous crisis counter and a purchase id that no longer points at them.

### Required for the paid product

Apple user id, optional relay email, IANA timezone, 18+ timestamp (no date of birth), subscription status and expiry, consent version and time, mint time, billed seconds, hang-up enum, month start count.

The conversation technical layer already allows mint metadata, duration, hang-up enum, and billed seconds.

### Optional progress sync

The numbers the on-device reports already show. No population norms.

- **Conversation:** speech seconds, turn count, pace (raw syllables/minute, no target), pause seconds (duration only), filled-pause count, English-slip count, language-uncertain flag.
- **Reading:** catalog `passage_id`, match / skip / extra / substitute counts, script word count, completeness ratio, stall count, speech rate, and a miss count per phone symbol plus functional-load band.
- **Monologue:** catalog `prompt_id` when the prompt came from the bank, the generated comparison line, and per take: wall seconds, spoken seconds, phonation-time ratio, pause seconds, gap count (silences ≥ 250 ms), pace, overlap percent versus the previous counting take.

### Safety flags, not content

`possible_minor` boolean and date. `mint_frozen` with reason `possible_minor` or `safety_block`. The words that triggered either flag are not stored.

OpenAI safety identifier: `HMAC-SHA256(server_pepper, account_id)` hex, computed at mint, sent to OpenAI, not stored. Never log it next to the account id. If OpenAI blocks it: generic unavailable, freeze mint, do not issue a new hash.

---

## What never gets a column

| Data | Where it stays | Why |
|---|---|---|
| Audio, PCM, AAC, waveforms | Conversation: process and delete. Monologue: this phone only | BIPA and WOPRA treat a voiceprint as biometric. The spec already forbids upload and speaker embeddings |
| Transcripts, notes, custom topic text, partner speech, stance card | On the phone for the live session. Monologue transcript stays in the local recording | Technical layer: never log ASR text, partner transcript, or stance card |
| Crisis words, and any mark that this account hit crisis | Anonymous daily counter only | Spec: crisis referral has no user id and no transcript |
| The sentence that triggered a minor flag | Boolean and timestamp on the account | Spec: not the utterance |
| OpenAI safety identifier beside the account id | Computed at mint. Not stored | Spec: never log the hash next to the account id |
| Card numbers, precise location, advertising id, birth date, disability | Apple holds payment. Timezone is a region name they can change | Not needed to run practice or billing |
| Filler locations and word-by-word reading rows | On-device report | A count or a phone symbol is enough for a personal trend. The words reconstruct the take |
| Coach audio and GOP audio slices | Not this database. A later queue would delete the bytes after scoring | Separate biometric consent. Out of this schema until that product exists |

A topic the person typed themselves is not stored. `monologue_regimens.prompt_id` stays null. Their notes stay on the phone.

---

## How a paid conversation starts

1. The phone signs in with Apple. The API checks the identity token, upserts `accounts`, and returns a short-lived access token. The refresh token is random. The database stores its SHA-256.
2. Start is one Postgres transaction. The server, not the phone, checks: account exists, not frozen, `subscriptions.entitled` is true, `starts_used < 20` for the open calendar month, and no `conversation_sessions` row is `minted` or `started`.
3. The month boundary uses `conversation_months.timezone`, frozen when that row is created. Changing `accounts.timezone` applies to the next month, so a timezone change cannot grant a second month.
4. Mint computes the OpenAI safety identifier, sends it with the ephemeral key, and does not write it down. Audio goes to OpenAI, not to us.
5. When the session counts as a start, set `started_at` and `counts_as_start` and increment `starts_used`. A drop before that does not consume a start. Idempotent on the client-generated session id.
6. On hang-up the phone reports billed seconds and an end reason from `user_stop`, `wrap`, `pause_ttl`, `drop`, `config_drift`.
7. A crisis ending uploads no practice row. The server increments `crisis_referral_days` for that UTC day and closes the open session with `end_reason` left null, so the one-session lock releases without labeling the account.
8. If `progress_sync_at` is set, a second call uploads the numeric report. Unknown fields are rejected. The call is refused when the opt-in is null. `client_report_id` makes retries safe.
9. App Store Server Notifications V2 update `subscriptions`. Insert `notification_uuid` first. A duplicate delivery stops there. The phone cannot talk the server into `entitled`. The signed payload is not stored.

`entitled` is copied from Apple. Mint checks that boolean. Status is for display and support.

---

## Deletion

Order:

1. If `mint_frozen`, insert `mint_blocks` with `HMAC-SHA256(server_pepper, apple_sub)` and the freeze reason. This row has no `account_id`. Sign-in recomputes the hash and refuses to create a new account, so a deleted blocked person cannot receive a new safety identifier.
2. Copy `original_transaction_id`, `product_id`, and `environment` into `financial_retention`. No user id. Counsel sets when this row is purged.
3. Delete the `subscriptions` row (`on delete restrict` on the account foreign key forces this first).
4. Delete the account. Cascade removes consent, refresh tokens, conversation months, conversation sessions, and practice rows.

`crisis_referral_days` is left as it is. It never pointed at the person.

`mint_blocks` is written at deletion, not while the account row still exists, so the hash and the account id do not sit together in normal operation.

---

## Schema

Postgres. Ids are UUIDs. Times are `timestamptz`.

```sql
create table accounts (
  id uuid primary key,
  apple_sub text not null unique,
  email text,
  timezone text not null,
  created_at timestamptz not null default now(),
  attested_18_at timestamptz,
  possible_minor boolean not null default false,
  possible_minor_at timestamptz,
  mint_frozen boolean not null default false,
  mint_frozen_reason text,
  progress_sync_at timestamptz,
  check (email is null or char_length(email) <= 320),
  check (possible_minor = false or possible_minor_at is not null),
  check (mint_frozen = false or mint_frozen_reason in ('possible_minor', 'safety_block')),
  check (mint_frozen = true or mint_frozen_reason is null)
);

create table consent_events (
  id uuid primary key,
  account_id uuid not null references accounts (id) on delete cascade,
  kind text not null check (kind in (
    'terms', 'privacy', 'ai_disclosure', 'voice_to_openai', 'progress_sync'
  )),
  policy_version text not null,
  accepted_at timestamptz not null,
  app_version text not null
);

create table refresh_tokens (
  id uuid primary key,
  account_id uuid not null references accounts (id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz
);

create table subscriptions (
  id uuid primary key,
  account_id uuid not null references accounts (id) on delete restrict,
  original_transaction_id text not null unique,
  product_id text not null,
  status text not null check (status in (
    'active', 'expired', 'in_grace', 'in_billing_retry', 'revoked', 'refunded'
  )),
  entitled boolean not null,
  environment text not null check (environment in ('sandbox', 'production')),
  current_period_start timestamptz not null,
  expires_at timestamptz not null,
  will_renew boolean not null,
  updated_at timestamptz not null
);

create table app_store_notifications (
  notification_uuid text primary key,
  original_transaction_id text not null,
  notification_type text not null,
  subtype text,
  received_at timestamptz not null default now()
);

create table conversation_months (
  account_id uuid not null references accounts (id) on delete cascade,
  month_start date not null,
  timezone text not null,
  starts_used int not null default 0 check (starts_used between 0 and 20),
  primary key (account_id, month_start)
);

create table conversation_sessions (
  id uuid primary key,
  account_id uuid not null references accounts (id) on delete cascade,
  state text not null check (state in ('minted', 'started', 'ended')),
  minted_at timestamptz not null,
  started_at timestamptz,
  ended_at timestamptz,
  end_reason text check (end_reason in (
    'user_stop', 'wrap', 'pause_ttl', 'drop', 'config_drift'
  )),
  billed_seconds int check (billed_seconds is null or billed_seconds >= 0),
  counts_as_start boolean not null default false
);

create unique index conversation_one_open
  on conversation_sessions (account_id)
  where state in ('minted', 'started');

create table practice_sessions (
  id uuid not null,
  account_id uuid not null references accounts (id) on delete cascade,
  format text not null check (format in ('conversation', 'reading', 'monologue')),
  client_report_id uuid not null,
  occurred_at timestamptz not null,
  duration_seconds numeric not null check (duration_seconds >= 0),
  kind text not null check (kind in ('thin', 'full')),
  limited_analysis boolean not null default false,
  primary key (id),
  unique (id, format),
  unique (account_id, client_report_id)
);

create table conversation_metrics (
  practice_session_id uuid not null,
  format text not null default 'conversation' check (format = 'conversation'),
  speech_seconds numeric not null check (speech_seconds >= 0),
  turn_count int not null check (turn_count >= 0),
  pace_syllables_per_minute numeric,
  pause_seconds numeric,
  filled_pause_count int,
  english_slip_count int,
  language_uncertain boolean,
  primary key (practice_session_id),
  foreign key (practice_session_id, format)
    references practice_sessions (id, format) on delete cascade
);

create table reading_metrics (
  practice_session_id uuid not null,
  format text not null default 'reading' check (format = 'reading'),
  passage_id text not null,
  match_count int not null,
  skip_count int not null,
  extra_count int not null,
  substitute_count int not null,
  script_word_count int not null,
  completeness_ratio numeric not null,
  stall_event_count int not null,
  speech_rate_syllables_per_minute numeric not null,
  primary key (practice_session_id),
  foreign key (practice_session_id, format)
    references practice_sessions (id, format) on delete cascade
);

create table reading_phone_misses (
  practice_session_id uuid not null references reading_metrics (practice_session_id) on delete cascade,
  phone text not null,
  fl_band text not null,
  miss_count int not null check (miss_count > 0),
  primary key (practice_session_id, phone)
);

create table monologue_regimens (
  practice_session_id uuid not null,
  format text not null default 'monologue' check (format = 'monologue'),
  prompt_id text,
  comparison text,
  primary key (practice_session_id),
  foreign key (practice_session_id, format)
    references practice_sessions (id, format) on delete cascade
);

create table monologue_takes (
  practice_session_id uuid not null references monologue_regimens (practice_session_id) on delete cascade,
  take_index int not null check (take_index >= 1),
  wall_seconds numeric not null,
  spoken_seconds numeric not null,
  phonation_time_ratio numeric,
  pause_seconds numeric not null,
  gap_count int not null,
  pace_syllables_per_minute numeric,
  overlap_percent numeric,
  primary key (practice_session_id, take_index)
);

create table crisis_referral_days (
  day date primary key,
  event_count int not null check (event_count >= 0)
);

create table mint_blocks (
  subject_hash text primary key,
  reason text not null check (reason in ('possible_minor', 'safety_block')),
  blocked_at timestamptz not null default now()
);

create table financial_retention (
  original_transaction_id text primary key,
  product_id text not null,
  environment text not null check (environment in ('sandbox', 'production')),
  retained_at timestamptz not null default now()
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
