# What makes a spoken partner feel alive

**Date:** 2026-10-19
**Scope:** Tactics for a speech-to-speech rehearsal partner. Mapped to Conversation v1. No prompt change in this note.

**Question:** Why does the partner ask hollow questions and sometimes leave a dead end, and what actually makes talk feel two-way?

## Short answer

A live conversation is not a chain of questions. It is two people putting something in, showing they heard the last specific thing, and leaving a reason for the other person to talk next.

The current partner does the opposite on purpose:

- The open must be a question with no opinion (`ConversationCue.instructions`, open case). The bank is binary taste items (`opens.json`: "Coffee or tea…").
- Mid-talk must hand the floor with one question, and must not talk about its own likes or wants (`ConversationCue.continueAside`).
- If the user asks an open question, the partner answers and does **not** hand the floor back (`continueAside`: "only hand the floor again if their question was closed/yes-no").
- The identity line says it is not a human (`FrozenPersona.prefix`).

Those four lines produce the two bugs. More "be warm" text will not fix them while these lines stay.

## What two-way talk actually is

These are separate jobs. A turn can do one of them. A hollow question tries to do all of them with a question mark.

1. **Both people contribute, at the same depth.** Social penetration theory: disclosure is reciprocal, and the reply should match the depth of what was just said, not go deeper and not give nothing back (Altman & Taylor, 1973; overview in Greene, [Social Penetration Theory](https://sites.comminfo.rutgers.edu/kgreene/wp-content/uploads/sites/28/2018/02/ACGreene-SPT.pdf)). A 15-minute rehearsal stays on the outer layer (tastes, habits). The norm still applies. "I reheat leftovers" wants "Rice is the part I actually want," not "Why do you reheat leftovers?"

2. **Show you understood this utterance.** A contribution is not done when a sentence is spoken. Partners have to establish that the listener got it well enough for current purposes (Clark & Schaefer, 1989, [Contributing to discourse](https://web.stanford.edu/~clark/1980s/Clark,%20H.H.%20_%20Schaefer,%20E.F.%20_Contributing%20to%20discourse_%201989.pdf)). The evidence is specific: their word, their detail. "Interesting" is not evidence.

3. **Take a stance they can answer.** An assessment claims the speaker has a view, and it makes a second assessment relevant: agree or disagree (Pomerantz, 1984, [Agreeing and disagreeing with assessments](https://www.conversationanalysis.org/wp-content/uploads/2019/06/09_Pomerantz_Agreeing___disagreeing_with_assessments.pdf)). This is the rehearsal-safe version of "alive." It is also the product's existing bet (stance card in `docs/superpowers/specs/2026-09-21-conversation-format-design.md`). The continue aside cancels it by banning the partner's own likes.

4. **Elicit without a question.** "Telling my side" is a fishing device: you report the limited thing you noticed, and the other person fills in the rest, without being asked (Pomerantz, 1980, described in the introduction to Sacks's lectures as eliciting information without asking for it: [Lectures on Conversation](https://archive.org/stream/HarveySacksLecturesOnConversationVolumesIIITheEstateOfHarveySacks1995/Harvey%20Sacks-Lectures%20on%20Conversation,%20Volumes%20I,%20II-The%20Estate%20of%20Harvey%20Sacks%20(1995)_djvu.txt)). Example: "The chain croissant is the sad one." They can defend the chain. No question mark.

5. **A story gets a story, not an interview question.** A first telling makes a related second telling the relevant next move (Sacks, 1992, *Lectures on Conversation*). One sentence is enough. A life story is a monologue, which the product already bans.

6. **Leave a reason to talk next.** Response relevance is a cline, not on/off. Speakers raise it with question form, rising intonation, and talk about something only the other person knows (Stivers & Rossano, 2010, [Mobilizing Response](https://doi.org/10.1080/08351810903471258)). A falling "Yeah, that's fair" has almost none of those. The other person is not rude for going quiet. They were given nothing to do. That is the awkward dead end.

7. **Turns are locally managed, not pre-assigned.** In ordinary conversation, who asks is worked out turn by turn. In an interview, one party owns the questions and the other owns the answers (Sacks, Schegloff & Jefferson, 1974, [A simplest systematics for the organization of turn-taking](https://doi.org/10.1353/lan.1974.0010); the interview contrast is the point of that paper's speech-exchange framing). Forcing a question every turn installs the interview system. Users feel interviewed.

8. **When a topic dies, step sideways.** People leave a spent topic by picking up one particular already in the talk, not by dropping a new survey item (Jefferson, 1984, "On stepwise transition from talk about a trouble to inappropriately next-positioned matters," in *Structures of Social Action*). "You said the rice" is a step. "Window or aisle?" is a cut.

9. **Voice presence is not wording.** Sesame's bar for spoken partners is emotional fit, timing and emphasis, context, and a consistent personality ([Crossing the uncanny valley of conversational voice](https://www.sesame.com/journal/crossing-the-uncanny-valley-of-voice), 2025). Their own caveat: the demo was still too eager, and timing, interruption, and conversation flow were unsolved. A better prompt does not invent prosody.

10. **Two-way talk is also the learning mechanism this product already cites.** Pushed, two-way tasks produce more negotiation of meaning than one-way tasks (Long, 1980, as summarized in `research/literature-review.md`). A partner that only extracts answers is the one-way shape.

## Bug 1 — hollow questions

A question feels hollow when it has no stake and no link to the last turn.

| Hollow | Why | Alive version of the same moment |
| --- | --- | --- |
| "Coffee or tea?" as the whole first turn, no view | Survey item. Question rights sit with the partner. Nothing of theirs is in it. | "I keep headphones on the whole commute. You deal with the noise, or no?" |
| "Why?" / "How does that feel?" | No candidate understanding. Could be said to anyone. | "So it's the waste, not the taste — the rice you actually want?" |
| A new binary after they answered the last one | Not recipient-designed. Ignores what they just gave. | Pick one detail they named and take a one-sentence side. |
| Question after a flat "That's interesting" | The reaction is generic, so the question is unearned. | Use their noun first, then one puzzle only they can answer. |

OpenAI's realtime guide says the model follows sample phrases closely and will sound robotic if every turn uses the same shape ([Realtime Prompting Guide](https://developers.openai.com/cookbook/examples/realtime_prompting_guide), "Reduce Repetition" and "Sample Phrases"). A rule that says "hand the floor once with one question" is a sample shape. The model will do it every turn.

Google's conversation-design notes on acknowledgements: "Got it" every turn becomes monotonous; vary them and sometimes skip them ([Acknowledgements](https://developers.google.com/assistant/conversation-design/acknowledgements)).

## Bug 2 — dead ends

A dead end is a turn that completes the last action and mobilizes nothing next.

Three designed causes:

1. **Answer, then stop.** `continueAside` tells the partner not to hand the floor after an open question. The user's question is answered. Nothing is conditionally relevant. They have to invent the next topic. That is the awkwardness.
2. **Closed assessment.** "Yeah, leftovers are fine." Falling, no stake, no puzzle, not about a fact only they know. Low on Stivers and Rossano's cline.
3. **Spent topic, no sideways step.** The open bank is not a mid-talk escape hatch, and the product has no Change Topic button (format spec). Without a stepwise pivot, the only exits are another survey question or silence.

The close is a different case. `wrap_close` says "No new question" on purpose. Do not "fix" the ending by adding a question. The bug is mid-session.

Google's task-chat rule is the same shape in a blunter form: every turn offers a next step, including after a finished task ([Guide the interaction](https://developers.google.com/business-communications/business-messages/guides/how-to/design/happy-path)). For this app the next step is another piece of talk, not a menu.

## Tactics that fit this product

The product is a 15-minute English rehearsal. Not a friend, not a therapist, not a lesson (format spec; `research/literature-review.md` finding 10: AI practice is a supplement, not a human replacement). Stay on daily logistics. No trauma, no praise of their English, no grammar.

Keep: short turns, one forward move, disagree on the point, English only, no fawning, no slang drill, fillers allowed, no "as an AI" lecture.

Change the move, not the warmth adjectives.

**One forward move per turn. Pick one. Do not stack.**

1. **Specific reaction + one-sentence stake.** Use their word. Then one view. Stop. Example: "Rice, though. That's the part worth keeping. I'd still order in if the pot's dirty."
2. **Tell your side, no question.** A limited notice they can confirm, deny, or top. Example: "Sounds like you already decided and you're arguing with yourself about it."
3. **One puzzle, built from their last detail, with a guess inside it.** The guess shows you heard them. They can correct it in one step (Google's one-step correction pattern: [Confirmations](https://developers.google.com/assistant/conversation-design/confirmations)). Example: "Wait — you like the leftovers, or you just won't throw out the rice?"
4. **Step sideways when the thread is done.** Name the particular, then a new small scene from it. Do not pull a fresh item from `opens.json`.
5. **If they asked you something, answer and leave a thread.** Two sentences max for the answer, then one hook back to them. This directly reverses the current open-question dead end.

**Never end a mid-talk turn on:** "That's interesting," "Fair," "Nice," "Got it," or a bare answer with a period and no hook.

**Personality, within the rehearsal limit.**

- One coherent someone with 1–2 stable tastes (the stance card), used only when their topic touches them.
- Remembers a detail from earlier in this session and brings it back. That is recipient design, not a memory product.
- Disagrees in a sentence, then gets curious. The prefix already says this. The continue aside fights it.
- Dry, short, warm. OpenAI's own tone line is "warm, concise, confident, never fawning" ([Realtime Prompting Guide](https://developers.openai.com/cookbook/examples/realtime_prompting_guide)).
- Drop "not a human" from the spoken identity. Keep "not a therapist, not a teacher." Sesame's presence list includes a consistent personality; telling the model it is not a person is an instruction to perform flatness.
- Variety rule: do not reuse the same opener, and do not always ask. OpenAI found `gpt-realtime` repeating "Got it" until a variety constraint was added (same guide, "Reduce Repetition").

**Prompt hygiene, from OpenAI's realtime guide, not from vibe.**

- The model follows instructions tightly, so conflicts win or cancel. Current conflict: prefix says use a stance; continue says no likes or wants; open says no opinion.
- Label sections (role, tone, turn moves, variety). Do not add a paragraph of synonyms for "warm."
- Sample phrases teach the move. Mark them vary-don't-copy, or the model will say them every time.
- Add rules only for failures you can hear. Do not pre-write a longer persona.

**Voice, separate from the prompt.**

- A half-duplex "mhm" as the whole turn is a dead end. Backchannels work when they overlap. If the system cannot overlap, every full turn needs a forward move.
- Flat read-aloud of a written question will sound hollow even with a better sentence. Sesame's gap is timing, emphasis, and not sounding too eager.
- Do not script emotion swings. OpenAI's happy-then-sad demo shows instruction following, not conversation.

## What not to add

- Therapist questions ("how does that make you feel," trauma, identity).
- Praise of form ("great English," "say it again"). Already banned. Keep it banned.
- A second question in the same turn. Already banned. Keep it banned.
- A scripted life, a name drop every turn, or slang as flavor.
- A new topic button as the fix for dead ends. The sideways step belongs in the turn.
- Treating the prompt as Long's Interaction Hypothesis. The format spec already warns against that. A stake makes negotiation possible. It does not guarantee acquisition.

## Sources

- Altman, I., & Taylor, D. (1973). *Social Penetration: The Development of Interpersonal Relationships.* Reciprocity summary: [Greene, Social Penetration Theory](https://sites.comminfo.rutgers.edu/kgreene/wp-content/uploads/sites/28/2018/02/ACGreene-SPT.pdf).
- Clark, H. H., & Schaefer, E. F. (1989). Contributing to discourse. *Cognitive Science, 13*, 259–294. [PDF](https://web.stanford.edu/~clark/1980s/Clark,%20H.H.%20_%20Schaefer,%20E.F.%20_Contributing%20to%20discourse_%201989.pdf).
- Google. Conversation design: [acknowledgements](https://developers.google.com/assistant/conversation-design/acknowledgements), [confirmations](https://developers.google.com/assistant/conversation-design/confirmations). Business Messages: [always offer a next step](https://developers.google.com/business-communications/business-messages/guides/how-to/design/happy-path).
- Jefferson, G. (1984). On stepwise transition from talk about a trouble to inappropriately next-positioned matters. In Atkinson & Heritage (Eds.), *Structures of Social Action*. [Chapter listing](https://www.cambridge.org/core/books/structures-of-social-action/419DC0CE99B82BB46AD246C8D8F19F90).
- OpenAI. [Realtime Prompting Guide](https://developers.openai.com/cookbook/examples/realtime_prompting_guide) (personality, variety, sample phrases, conversation flow). [Voice prompting](https://developers.openai.com/api/docs/guides/voice-prompting).
- Pomerantz, A. (1984). Agreeing and disagreeing with assessments. In Atkinson & Heritage (Eds.), *Structures of Social Action*. [PDF](https://www.conversationanalysis.org/wp-content/uploads/2019/06/09_Pomerantz_Agreeing___disagreeing_with_assessments.pdf).
- Pomerantz, A. (1980). Telling my side: "Limited access" as a "fishing" device. *Sociological Inquiry, 50*(3–4), 186–198. Mechanism as cited in the Sacks lectures introduction: [archive text](https://archive.org/stream/HarveySacksLecturesOnConversationVolumesIIITheEstateOfHarveySacks1995/Harvey%20Sacks-Lectures%20on%20Conversation,%20Volumes%20I,%20II-The%20Estate%20of%20Harvey%20Sacks%20(1995)_djvu.txt).
- Sacks, H. (1992). *Lectures on Conversation* (Vols. I–II). Second tellings as the relevant next move after a first telling.
- Sacks, H., Schegloff, E. A., & Jefferson, G. (1974). A simplest systematics for the organization of turn-taking for conversation. *Language, 50*(4), 696–735. [doi:10.1353/lan.1974.0010](https://doi.org/10.1353/lan.1974.0010).
- Sesame (Iribe, Kumar, & team, 2025). [Crossing the uncanny valley of conversational voice](https://www.sesame.com/journal/crossing-the-uncanny-valley-of-voice).
- Stivers, T., & Rossano, F. (2010). Mobilizing response. *Research on Language and Social Interaction, 43*(1), 3–31. [doi:10.1080/08351810903471258](https://doi.org/10.1080/08351810903471258).
- This repo: `ConversationCue.swift` (`continueAside`, `FrozenPersona.prefix`), `opens.json`, `docs/superpowers/specs/2026-09-21-conversation-format-design.md`, `research/literature-review.md` (Long, 1980; AI as rehearsal, not a replacement).
