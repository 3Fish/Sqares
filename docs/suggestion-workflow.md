# Community feature-suggestion workflow

This is the playbook for the **suggestion refinement** stage. It is read by the
recurring developer routine on each run — there is **no GitHub→Claude callback**
involved, so it does not depend on any webhook firing. The routine *polls* the
repo for suggestions that need attention and acts on them.

## How a suggestion flows

1. **Created** — Anyone (no repo access needed) files an issue via the
   *Feature suggestion* form. GitHub applies `suggestion` and
   `status: needs-refinement` automatically.
2. **Refined** — The developer routine reads the suggestion and either asks
   clarification questions (→ `status: refining`) or, once it has enough,
   rewrites the issue into a finalized spec (→ `status: awaiting-greenlight`).
3. **Greenlit** — The **maintainer manually** applies `greenlit` (or `declined`).
   The routine never applies these — only the maintainer can.

## Label state machine

| Label | Meaning | Who sets it |
|---|---|---|
| `suggestion` | It's a community suggestion | Issue form |
| `status: needs-refinement` | New; routine hasn't engaged yet | Issue form |
| `status: refining` | Routine asked questions; waiting on the suggester | Routine |
| `status: awaiting-greenlight` | Finalized spec ready for the maintainer | Routine |
| `greenlit` | Approved for implementation | **Maintainer only** |
| `declined` | Not being taken forward | **Maintainer only** |

## What the routine does each run

Operate only on **open** issues labeled `suggestion`. For each one, decide its
state from its labels and the comment thread:

### A. `status: needs-refinement` (brand new)
- Read the suggestion against the project's design (see `CLAUDE.md` — especially
  the mod-first architecture: stats/cards/arenas/modes are registered at runtime,
  not hard-coded).
- If it's spam, off-topic, or empty: leave a short polite comment and **skip**
  (do not relabel). The maintainer can `declined` it. Do not engage further.
- If it's a real idea but under-specified: post **one concise comment** with a
  short batch of the most important clarification questions (aim for 3–5, not an
  interrogation). Then set `status: refining` (remove `status: needs-refinement`).
- If it's already clear enough on its own: go straight to **C (finalize)**.

### B. `status: refining` (waiting on the suggester)
- If the **latest comment is from the routine** (i.e. the suggester hasn't
  replied yet): **skip** — still waiting on them. Don't nag.
- If the **suggester has replied** since the last routine comment: read the new
  info.
  - Still material gaps: ask a **short** follow-up and stay in `status: refining`.
  - Enough to act on: go to **C (finalize)**.
- Don't loop forever. After roughly two rounds of questions, finalize with the
  best understanding available and note any open assumptions in the spec.

### C. Finalize (→ `status: awaiting-greenlight`)
- Rewrite the **issue body** into a clean, self-contained spec with these
  sections:
  - **Summary** — one or two sentences.
  - **Problem / motivation** — why it's worth doing.
  - **Proposed behavior** — concrete, testable description.
  - **Scope & fit** — how it maps onto the mod system (which registries: stats,
    cards, arenas, game modes, player actions), and whether it's a base-game
    addition or better as a separate mod.
  - **Acceptance criteria** — bullet checklist.
  - **Open questions / assumptions** — anything still unresolved.
- Preserve the suggester's original text (move it under an
  *Original suggestion* heading at the bottom; don't discard their words).
- Post a brief comment summarizing the finalized spec and thanking them.
- Set `status: awaiting-greenlight` (remove `status: refining` /
  `status: needs-refinement`). **Stop here** — the maintainer takes it from here.

### D. `greenlit`
- This is the maintainer's go-ahead. Implementation is a **separate concern** from
  refinement; only act on it if the routine's own instructions tell it to start
  implementation work. Otherwise leave greenlit issues alone.

## Hard rules

- **Never** apply `greenlit` or `declined`. Those are the maintainer's manual gate.
- **Never** push code, open PRs, or create branches as part of *refinement* — this
  stage is issue-only.
- Be concise and friendly in comments; suggesters are volunteers with no repo
  access. One comment per pass per issue.
