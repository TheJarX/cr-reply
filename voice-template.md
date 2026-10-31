# Voice template

Fill this from a corpus produced by `scripts/gather-voice.sh`, then save the result as `~/.config/cr-reply/voice.md`. The skill reads that file before drafting.

Rules for whoever fills it in (human or agent):

- Only what the corpus shows. Quote verbatim; don't paraphrase the examples or "improve" their grammar. Non-native phrasing, dropped periods, lowercase openers and slang are the voice, keep them.
- Discard entries that are tool output posted from the account (severity badges, `suggestion` blocks, "Prompt To Fix", auto-review headers). The voice is the human replies.
- Prefer variety over volume in the examples: one or two per situation beats ten "Fixed in …".
- Hard avoids are things the corpus never does that drafts tend to add. Say them explicitly.
- Keep it under ~120 lines. A voice file is a lens, not an archive; the corpus stays in `/tmp`.

Delete these instructions and the angle-bracket placeholders in the saved file.

---

# <Name>: writing voice for PR replies

Built from <N> replies across <M> PRs (<org / repos>) on <date>. Match this voice. Do not invent a more formal review-reply persona.

## Voice (always)

- <register: Slack-teammate / terse / measured; what the replies sound like in one line>
- <person and contractions: I / we / you; "I'm", "we're", "don't" or spelled out?>
- <openers and closers they actually type, verbatim: e.g. "Yep,", "Good catch", "Makes sense", "Will fix!", "Thoughts?">
- <how they agree and concede: soft ("Yeah probably…") or flat ("Agreed.")?>
- <how they push back: "Fair point, but…" / direct / with a question?>
- <how they own mistakes, defer, or hand off; emoji use (which ones, how often)>
- <quirks to keep: drops final period on short replies, "tho", lowercase, ESL phrasing, dry humor>
- <how they refer to product behavior and people: "the user", "we", tags people / bots casually?>

## Length

| Surface | Default |
| --- | --- |
| PR review reply | <e.g. 1–2 sentences> |
| Longer reply / pushback | <e.g. short paragraph + disposition> |
| PR conversation comment | <…> |

## Hard avoids

- <punctuation they never use, e.g. em dashes>
- <phrasing they never use, e.g. "Thanks for the thorough review", "Acknowledged.", "I've gone ahead and…">
- <structure they never use, e.g. bullet-pointed replies, headers inside a reply, badge markup>

## Reply shapes

| Situation | Shape (their words) |
| --- | --- |
| Fixed | <e.g. `Fixed in <sha>.` + one plain sentence of what changed> |
| Taking the suggestion | <e.g. `Oh nice one will add the change!` / `Will fix!`> |
| Agree casually | <…> |
| Agree, out of scope | <…> |
| Pre-existing, not this PR | <…> |
| Disagree, leaving it | <…> |
| Clarify a confusion | <…> |
| Defer / follow-up | <…> |
| Own a mistake | <…> |

## Real examples (copy the register, not the content)

PR #<n> (<situation>):

> <verbatim reply>

PR #<n> (<situation>):

> <verbatim reply>

<8–15 total, spread across the situations above; include the reviewer's line above a reply when it clarifies the shape>

## Bad (too AI / too stiff)

> <one real example rewritten the way a generic assistant would say it, so the contrast is obvious>

> <another>
