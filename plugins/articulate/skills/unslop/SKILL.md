---
name: unslop
description: Cut AI tells from writing a person will read, such as docs, READMEs, PR descriptions and messages.
disable-model-invocation: true
---

# Unslop

Edit text so it reads as written by a person.

## Process

1. Check the text against every rule below and rewrite what fails. Keep the meaning and the intended tone.
2. Ask "what still makes this read as AI-generated?" and fix what that turns up.

The pass is done when every rule has been checked against the text, not when it reads fine at a glance.
Break any rule sooner than write something barbarous.

## Characters

- **Plain ASCII.** Use only what a keyboard types: straight quotes, three dots for an ellipsis, "is one of" instead of a set-membership sign.
- **No em or en dashes.** End the sentence or use a comma. Where a sentence truly needs a break, use a spaced hyphen ` - `.

## Content

- **Superficial -ing phrases.** "highlighting...", "ensuring...", "reflecting...", "showcasing...", "fostering...". Delete them, or say the concrete thing.
- **Vague attributions.** "Experts believe", "Industry reports suggest". Name the source or delete the claim.
- **Straw men.** "Not just X, but Y" and "it's not X, it's Y" knock down a position nobody held. Use the pattern once per piece at most.
- **Announcing.** "Here's the thing:", "Honestly?", "Let's dive in". Say the point.
- **The neutral middle.** "While X offers Y, it is important to consider Z". When you have a view, state it.
- **Generic conclusions.** "The future looks bright." End on a specific plan or fact, or end earlier.
- **Say what it does.** "SQL you can read" names a feeling; "`.toSQL()` returns the exact string sent to the database" names the mechanism. If a sentence could appear unchanged in another project's docs, it says nothing about this one. Cut it.

## Words

- **The short word.** use, not utilize or leverage. help, not facilitate. many, not numerous. if, not in the event that.
- **AI vocabulary.** additionally, crucial, delve, elevate, enduring, enhance, foster, garner, interplay, intricate, landscape, navigate, paramount, pivotal, realm, seamless, showcase, tapestry, testament, transformative, underscore, unlock, vibrant, vital. Replace with the plain word.
- **Fancy ways to say "is".** "serves as", "stands as", "boasts", "features". Say "is" or "has".
- **Metaphor nouns.** substrate, wedge, vector, locus, nexus, primitive, surface (as in "API surface"), scaffolding, paradigm, north star, flywheel, endgame. Name the concrete thing: "base", "add", "way", "the last phase".
- **Stock figures of speech.** Any metaphor or simile you are used to seeing in print, aphorisms ("wire it or delete it"), personified code ("the plan holds it"), figurative verbs ("rides along"). Use the literal phrase.
- **Synonym cycling.** Protagonist, main character, hero in one paragraph. Pick one word and repeat it.
- **False ranges.** "from X to Y" where X and Y aren't on a scale. List the items.
- **Stock transitions.** Furthermore, Moreover, Consequently, Ultimately. Drop them; the order of the sentences carries the logic.
- **Filler.** "In order to" becomes "to". "Due to the fact that" becomes "because". "It is important to note that" goes.
- **Hedging.** "could potentially be argued that it might" becomes "may".
- **Adverbs.** "runs quickly" becomes "is fast" or the number. An adverb propping up a verb means the verb is wrong.

## Sentences

- **Cut every word you can.**
- **Active voice.** "queries are validated" becomes "the compiler validates queries". Passive is fine when the actor is unknown or doesn't matter.
- **One idea per sentence.** If the reader has to backtrack, split it.
- **Whole sentences.** Keep the articles and verbs. Spell out arrows and abbreviations. "Parser rejects bad date -> exit 2" becomes "The parser rejects a bad date and exits with code 2."
- **Two examples.** Groups of three are a tell. Use the natural number, and two is usually enough.
- **Varied rhythm.** Neighbouring sentences and paragraphs differ in length and shape. Don't end two paragraphs in a row on a punchline.

## Formatting

- **Headings.** Sentence case, and only where a reader would use one to find their place.
- **Bold.** Not on every term. A bold lead-in that ends in a period and is followed by new detail is fine; "**Performance:** Performance improved" is not.
- **Colons.** Before a list or an example, not as a connector in the middle of a sentence.
- **Emojis.** None in headings or bullets.

## Chat

- **Chatbot phrases.** "I hope this helps!", "Let me know if...", "Certainly!". Delete.
- **Sycophancy.** "Great question! You're absolutely right!" Answer directly.
