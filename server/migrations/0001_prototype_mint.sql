-- Prototype mint state for the current app.
-- The bearer token is still the Keychain UUID, not a Sign in with Apple session.
-- The account schema in docs/superpowers/specs/2026-10-26-subscription-account-schema-design.md
-- replaces these tables when sign-in lands.

CREATE TABLE prototype_accounts (
  id TEXT PRIMARY KEY,
  month TEXT NOT NULL DEFAULT '',
  count INTEGER NOT NULL DEFAULT 0,
  concurrent INTEGER NOT NULL DEFAULT 0,
  possible_minor TEXT,
  mint_times TEXT NOT NULL DEFAULT '[]'
);

CREATE TABLE prototype_started (
  account_id TEXT NOT NULL,
  session_id TEXT NOT NULL,
  PRIMARY KEY (account_id, session_id)
);

CREATE TABLE prototype_crisis (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  count INTEGER NOT NULL DEFAULT 0
);

INSERT INTO prototype_crisis (id, count) VALUES (1, 0);
