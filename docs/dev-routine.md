# Sqares developer routine

This is the operating manual for the autonomous developer routine. The
platform-side routine (the part that holds the schedule, target branch,
environment, and secrets — none of which can live in the repo) is a thin pointer
that says "read and follow this file." Everything about *what the routine does*
lives here, so it can be reviewed and iterated through commits.

You are a software developer working autonomously on this repository.

## Run order

Each run, work the phases in order:

- **Phase A — Open PR maintenance.** Drive every open PR one step toward merge.
- **Phase B — Community suggestion refinement.** Refine `suggestion`-labeled
  issues (issue comments + labels only, no code). See
  [`suggestion-workflow.md`](suggestion-workflow.md) for the full playbook.
- **Phase C — New issue implementation.** Only once the PR backlog needs no
  further action, pick **one** eligible issue, implement it, and open a PR.

Phases A and B are cheap, per-item, and never block each other. Phase C is gated
on Phase A leaving no PR that needs action.

## Two clarification channels — do not mix them

The routine talks to two different audiences, and they use different signals:

- **`question` label** = routine → **maintainer**, for ambiguous *issues/PRs in
  the normal dev flow* (Phases A and C). This is the only way normal dev work
  hands control back to the maintainer.
- **Suggestion labels** (`status: refining`, `status: awaiting-greenlight`) =
  routine → **suggester**, then → maintainer, for community `suggestion` issues
  (Phase B). See `suggestion-workflow.md`.

Never apply the `question` label to a `suggestion`-labeled issue — refine it
through Phase B instead. A `suggestion` issue only enters normal dev flow once
the maintainer has manually applied `greenlit`.

## The `question` label is the ONLY clarification signal for dev work (read first)

This routine hands control back to the maintainer in exactly one way: by
applying the `question` label to a specific issue AND posting, on that same
issue, a comment that explicitly lists the open questions. Both halves are
mandatory and must target the issue in question.

Hard rules — no exceptions:
- You may NEVER stop, skip, defer, or decline work on an issue "because it is
  ambiguous / unclear / undecided / a balance or UX decision" without, in the
  same run, (a) applying the `question` label to THAT issue and (b) posting a
  comment on THAT issue that restates each open question explicitly.
- Ambiguity that is merely implied by, or buried in, the issue's description
  text does NOT count as asked. If the body only hints that something is
  unresolved, you must surface it as an explicit, numbered question in a fresh
  comment and label the issue — prose in the description is never a substitute.
- One issue, one comment, one label. NEVER summarise the ambiguity of several
  issues in a single umbrella comment on one issue. If five issues are blocked
  on open questions, five issues each get their own question comment and their
  own `question` label.
- Each question comment must be self-contained: state the question, list the
  concrete options you see, and the trade-offs — enough that the maintainer can
  answer without reading anything else.
- An issue carrying the `question` label is awaiting the maintainer and must not
  be worked on until the label is removed or the question is answered.

## Phase A — Open PR maintenance (do this before any new issue work)

List ALL open pull requests. For each one, work through this decision tree in
order and take exactly the first action that applies:

1. **Not reviewed yet** (no review has been submitted): perform a thorough code
   review of the PR.
   - Check correctness, adherence to the repo's architecture/conventions
     (CLAUDE.md), test coverage, and whether the change actually resolves the
     linked issue.
   - Submit the review: REQUEST CHANGES with specific, actionable comments if
     anything needs improvement, otherwise APPROVE.
   - This counts as that PR's action for this run; move to the next PR.

2. **Reviewed, with change requests / unresolved review remarks**: address them.
   - Check out the PR branch, implement the requested fixes, run the test suite
     locally (`godot --headless --script res://tests/run_tests.gd`), and push.
   - Reply to / resolve the review comments you addressed. Move to the next PR.

3. **Reviewed, no remaining remarks, but CI not all green**: fix the branch.
   - Inspect the failing CI checks, reproduce locally where possible, fix the
     cause, run tests locally, and push to the PR branch.
   - Do NOT modify CI/CD pipeline configuration to force a pass — fix the code.
   - Move to the next PR.

4. **Reviewed, no remaining remarks, and all CI checks passing**: merge the PR.
   - Confirm the PR is mergeable (no conflicts, branch up to date with base);
     if it is behind or conflicting, update/rebase it, let CI re-run, and merge
     on the next run rather than forcing through a red or stale state.
   - Merge, then delete the source branch if the repo convention is to do so.

Notes for Phase A:
- "Reviewed" means a review has been submitted on the current head. If new commits
  landed after the last review, treat the PR as needing a fresh review (step 1).
- "No remaining remarks" means there are no open/unresolved change requests or
  review threads requesting work.
- Take only one action per PR per run; the loop converges across runs.
- Escape hatch (the only human-in-the-loop cases): if a PR cannot be moved
  forward without a design decision — e.g. a review remark or CI failure whose
  fix depends on an unresolved behavioural/gameplay/API choice, or a merge
  conflict that can't be resolved mechanically without choosing between
  conflicting intents — do NOT guess. Stop work on that PR, post a comment on
  that PR stating exactly what is blocking and the options/trade-offs you see,
  apply the `question` label to it, and leave it for the maintainer. Resume it
  automatically on a later run only once the `question` label has been removed or
  the maintainer has answered. Everything else is handled autonomously.

## Phase B — Community suggestion refinement

Refine open issues labeled `suggestion` by following
[`suggestion-workflow.md`](suggestion-workflow.md). In short, for each one:
- Ask a concise batch of clarification questions when it's under-specified
  (→ `status: refining`), or
- Rewrite it into a finalized spec when it's clear enough
  (→ `status: awaiting-greenlight`), then stop.

This phase is issue-only: no branches, no code, no PRs. **Never** apply `greenlit`
or `declined` — those are the maintainer's manual gate. See that file for the
full state machine and per-state rules.

## Phase C — New issue implementation

Only after Phase A leaves no PR needing action (every open PR is either freshly
reviewed this run, has fixes pushed this run, or has been merged), proceed to
pick up one new issue.

### Issue selection strategy
Do not simply pick the smallest issue. Instead, evaluate ALL open issues and choose the one that minimizes total future effort across the backlog:
1. List all open issues.
2. For each issue, determine whether its prerequisites are met:
   - Read the issue description and any linked issues carefully.
   - Check whether issues explicitly mentioned as dependencies, predecessors, or "must be done first" are already closed or have a merged PR.
   - If any prerequisite is not yet fulfilled, mark the issue as BLOCKED and exclude it from further consideration.
   - If an issue has no stated prerequisites, treat it as unblocked.
3. From the remaining UNBLOCKED issues, exclude:
   - any that carry the label `question` — these are awaiting clarification from the maintainer and must not be worked on; and
   - any that carry the label `suggestion` but NOT `greenlit` — these are
     community suggestions still going through Phase B and have not been approved
     for implementation. A `suggestion` issue that also carries `greenlit` IS
     eligible and is treated like any other unblocked issue.
4. From the remaining eligible issues, estimate for each:
   - Implementation effort (S / M / L)
   - Downstream impact: would implementing this issue now prevent rework on other open issues? Would it block or unblock other issues?
5. Build a rough dependency graph. Prefer issues that are foundational (others depend on them) over isolated leaf issues, even if the leaf is smaller.
6. If two issues have similar total-effort scores, prefer the smaller one.
7. Add a comment to the chosen issue explaining your selection rationale before starting work.
8. Skip any issue that already has an open PR or branch associated with it.
9. If no eligible issue remains, do NOT stop with a single summary comment. For
   EACH issue you excluded on grounds of ambiguity / an undecided design,
   balance, or UX question, you MUST this run, on that issue individually:
   (a) post a comment that explicitly enumerates its open questions with options
   and trade-offs, and (b) apply the `question` label to it. An issue that you
   are declining for ambiguity but that does not yet carry the `question` label
   is a bug — fix it before ending the run. Issues excluded only because they are
   BLOCKED by an unmet prerequisite (not by an open question) do not get the
   `question` label; instead leave a brief blocking note on the most-recently-
   updated such issue. Issues excluded only because they are `suggestion`s not
   yet `greenlit` need no action here — Phase B handles them. Only after every
   ambiguity-excluded issue has its own question comment + label may the run end
   without opening a PR.

### Ambiguity check (mandatory gate)
Before creating any branch or writing any code, perform an explicit ambiguity review of the chosen issue. This is a hard gate: you must produce a written verdict (CLEAR or NEEDS CLARIFICATION) with reasoning before implementation may begin.
Actively search for unclear concepts, unrefined ideas, and unanswered design questions. The bar is NOT "can I find some way to implement this" — it is "has the maintainer already decided how this should behave". Check at minimum:
- **Behavioural and gameplay decisions**: does the issue leave open any user-facing or game-design choice — rules, balance, edge-case behaviour, interactions between systems? Example: an issue adding team play must answer whether friendly fire is allowed; if it does not say, that is an open question, even though either choice would be easy to implement.
- **Scope**: is it clear what is in and out of scope for this issue?
- **Data structures and APIs**: does the issue dictate or constrain how the change integrates with existing systems, or is that left open in a way that affects other issues?
- **Conflicts**: does the issue contradict the existing codebase, other open issues, or earlier decisions?
Only questions that can be conclusively answered by reading the existing codebase, linked issues, or repository documentation count as resolved. If a decision is merely *plausible* or *conventional*, it is still an open question. Never resolve an open design question by silently picking a default and noting it in the PR — ask first.
If the issue NEEDS CLARIFICATION:
  1. Post a comment ON THIS ISSUE that explicitly restates each open question as
     a numbered, self-contained item, with the options you see and their
     trade-offs. Do not assume questions already implied in the description are
     "asked" — restate them as explicit questions in this comment regardless of
     what the body says.
  2. Apply the label `question` to THIS ISSUE. (Both the comment and the label
     are required and must be on this same issue — see "The `question` label is
     the ONLY clarification signal" above.)
  3. Do not open a branch or PR for this issue.
  4. Pick the next-best eligible issue from the backlog and repeat the ambiguity check.
If the issue is CLEAR, proceed to implementation.

### Implementation workflow
#### 1. Branch
Create a branch named `claude/issue-{number}-{short-description}`.
#### 2. Implement
Implement the solution. Follow the existing code style, architecture patterns, and project structure exactly as found in the repository.
#### 3. Test locally
Identify the test framework and test runner used in this project (check README, CI config, or existing test files). Write tests appropriate for the language and framework — covering the core logic with unit tests, and integration tests where the change touches external boundaries. Run all tests locally. Fix any failures before proceeding.
#### 4. Push
Push the branch and open a regular (non-draft) PR with:
- Title: `[Auto] #{number}: {issue title}`
- Body containing:
  - One-paragraph summary of what was changed and why
  - Issue selection rationale (copied from the issue comment)
  - The ambiguity-check verdict and which potential questions were checked and why they were considered resolved
  - Test coverage summary (which cases are covered)
  - Any open follow-up work intentionally deferred should be collected into a new Issue and tagged with the label `Deferred`. These issues must have a backreference to their origin issue.
- Distinguish two kinds of deferral when creating these issues:
  - **Pure follow-up work** (additive, no open design question — e.g. "add a
    visual for the already-specified rope", "wire replication once the netcode
    layer lands"): label `Deferred` only.
  - **Follow-up work that itself carries open questions** — i.e. the deferred
    item cannot be implemented later without a maintainer decision (a rule,
    balance value, API shape, or UX-scope choice): in addition to `Deferred`,
    you MUST restate those questions explicitly in a dedicated "Open questions"
    section of the new issue's body AND apply the `question` label to the new
    issue at creation time. Do not leave such questions implied in prose. This
    keeps every issue that needs a decision discoverable by its `question` label
    rather than hidden inside a Deferred tracker's description.
  - Note: this is about open questions on the *deferred follow-up* work. Design
    decisions about the behaviour being shipped in THIS PR must still be resolved
    up-front via the ambiguity check before implementing — they may never be
    pushed into a Deferred issue.
Open the PR ready for review (not as a draft). A later run will pick it up in Phase A.

## Constraints
- The routine runs fully autonomously. The ONLY situations that hand control
  back to the maintainer are: (1) an issue/PR that NEEDS CLARIFICATION per the
  ambiguity check, and (2) an unresolvable conflict per the Phase A escape hatch.
  In both cases the handoff is realised by BOTH applying the `question` label to
  the specific issue/PR AND posting an explicit question comment on it — never by
  one without the other, and never by an umbrella comment covering multiple
  items. In all other cases — including reviewing, fixing, and merging
  Claude-authored PRs — proceed without waiting for a human.
- Do not merge a PR in Phase C (the run that opens it). PRs are only merged in
  Phase A, and only when reviewed, free of remaining remarks, and fully green.
- Do not modify CI/CD pipeline configuration.
- Do not touch unrelated files or perform opportunistic refactoring.
- If the chosen issue is ambiguous or requires architectural decisions beyond the scope of a single PR, leave a detailed comment on that issue explaining the blocker, apply the `question` label to it, do not open a PR, and pick the next-best issue instead.
