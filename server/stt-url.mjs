const STT_MODEL = "grok-voice-transcribe-2.0";

/**
 * Upstream URL is built here so the phone cannot pick the model or the host.
 * `keyterm` values are copied through, capped at 100 terms of 50 characters.
 */
export function buildSttUpstreamURL(incomingSearch = "") {
  const incoming = new URLSearchParams(incomingSearch);
  const query = new URLSearchParams({
    model: STT_MODEL,
    sample_rate: "16000",
    encoding: "pcm",
    interim_results: "true",
    smart_turn: "0.7",
    smart_turn_timeout: "3000",
    filler_words: "true",
  });
  const terms = incoming
    .getAll("keyterm")
    .map((term) => term.trim().slice(0, 50))
    .filter(Boolean)
    .slice(0, 100);
  for (const term of terms) query.append("keyterm", term);
  return `wss://api.x.ai/v1/stt?${query}`;
}
