import { test } from "node:test";
import assert from "node:assert/strict";
import { decideStart, monthKey } from "./mint.mjs";

test("20th start in a calendar month is allowed, 21st is not", () => {
  const month = "2026-09";
  const st = { month, count: 19, concurrent: 0 };
  const ok = decideStart(st, month, Date.parse("2026-09-21T12:00:00Z"));
  assert.equal(ok.allow, true);
  assert.equal(ok.nextCount, 20);
  const no = decideStart({ month, count: 20, concurrent: 0 }, month);
  assert.equal(no.allow, false);
  assert.equal(no.reason, "budget");
});

test("new calendar month resets", () => {
  const st = { month: "2026-08", count: 20, concurrent: 0 };
  const ok = decideStart(st, "2026-09");
  assert.equal(ok.allow, true);
  assert.equal(ok.nextCount, 1);
});

test("concurrent session blocked", () => {
  const no = decideStart({ month: "2026-09", count: 3, concurrent: 1 }, "2026-09");
  assert.equal(no.allow, false);
  assert.equal(no.reason, "concurrent");
});
