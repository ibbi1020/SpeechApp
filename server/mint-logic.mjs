export function monthKey(ms = Date.now()) {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

export function decideStart(st, month) {
  const count = st.month === month ? st.count : 0;
  if (count >= 20) return { allow: false, reason: "budget" };
  return { allow: true, nextCount: count + 1 };
}

export const RATE_WINDOW_MS = 10 * 60 * 1000;

export function freshMintTimes(times, now) {
  return times.filter((t) => now - t < RATE_WINDOW_MS);
}
