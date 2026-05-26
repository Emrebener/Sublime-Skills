---
name: architecture-review
description: A structured architecture-review process — finds shallow, leaky, tightly-coupled modules with the deletion test, proposes concrete deepening refactors, and grills the chosen design (with parallel exploration of alternative interfaces). Design-only; stops at an agreed design and does not implement it. Prefer this over reviewing code ad hoc whenever the user wants an architecture review, asks where or how to refactor or reorganize a codebase, says code feels tangled, hard to test, or hard to navigate, wants to consolidate tightly-coupled modules, or asks whether a module structure makes sense — even if they never say the word "architecture".
---

# Architecture Review

Find architectural friction in a codebase and propose refactors that make it more testable and easier to navigate. The unifying idea: turn **shallow** modules into **deep** ones.

This skill is design-only. It ends at a settled design the user has agreed to — recognizing candidates, choosing one, and grilling its shape. It does not edit the modules or migrate callers; that is a separate task the user runs afterward.

## The core idea

A **module** is anything with an interface and an implementation — a function, a class, a package, a slice of a system. The size doesn't matter; the shape does.

The **interface** is everything a caller has to know to use the module correctly. Not just the type signature — also the invariants it assumes, the order calls must happen in, the errors it can throw, the config it needs. If a caller has to know it, it's part of the interface.

A module is **deep** when a lot of behaviour sits behind a small interface — callers learn a little and get a lot. It's **shallow** when the interface is nearly as complex as the implementation: the caller has to learn almost everything the module does just to use it, so the module is barely earning its place.

Two payoffs come from depth, and they are how you should justify every suggestion:

- **Leverage** — callers get more capability per unit of interface they have to learn. One implementation pays back across many call sites and tests.
- **Locality** — change, bugs, and knowledge concentrate in one place instead of smearing across callers. Fix once, fixed everywhere.

A **seam** is a place where behaviour can be swapped without editing code in place — it's where an interface lives. Seams are how a deep module stays testable: you test through the seam, the same way callers cross it.

## The deletion test

This is the sharpest tool for telling deep from shallow. For any module you suspect is shallow, imagine deleting it and inlining its body into every caller.

- If complexity simply **vanishes** — the module was a pass-through, a thin delegate dressed up as a layer. It wasn't hiding anything. Deleting it is itself a candidate.
- If the same complexity **reappears, duplicated across N callers** — the module was earning its keep. It's deep, or wants to be deepened, not deleted.

Run this test out loud in your reasoning before proposing anything. It stops you from suggesting refactors that just move complexity around.

## What shallow looks like in real code

You're hunting for friction, not pattern-matching names. Concrete tells:

- A module whose every method is a one-line delegate to another module — it forwards, it doesn't decide.
- A `Manager` / `Helper` / `Utils` whose interface basically enumerates its implementation — to use it you must already know what's inside.
- Pure functions extracted purely "for testability", where the real bugs live in *how they're orchestrated* — the tests pass, the integration breaks, because there's no **locality**.
- Understanding one concept requires bouncing between five files; no single module owns it.
- A module that leaks its internals through the interface — returns raw DB rows, hands back a live connection, exposes a half-built object callers must finish.
- Tightly-coupled modules that reach across each other's seams and mutate shared state.
- Code with no test at all because its current interface gives nothing clean to test against.

## Process

### 1. Explore

First, do a deliberate check for project context. These files are opt-in for projects (they may or may not exist), but **if they do exist, you MUST read them before presenting candidates** — skipping them produces vocabulary drift, re-litigated ADRs, and refactors that contradict stated principles. All three waste the user's time when you present.

Check well-known locations:

- **Domain glossary** — the project's real names for things. Check the repo root for `CONTEXT.md`, `GLOSSARY.md`, `DOMAIN.md`, then `docs/` for the same names. If those miss, glob once for `*glossary*` / `*domain-model*` (case-insensitive). Use canonical terms in your candidates; don't invent synonyms.
- **Architecture decision records (ADRs)** — past architecture decisions and their rationale. Check `docs/adr/`, `docs/architecture/decisions/`, `adr/`. If those miss, glob once for `*adr*`. Read the ones relevant to the area you're reviewing; they record decisions you should not blindly re-litigate.
- **Architecture overview** — the project's existing high-level structure. Check `ARCHITECTURE.md`, `docs/ARCHITECTURE.md`. Tells you what the project considers settled before you propose to move things around.
- **Constitution / principles** — non-negotiable project rules. Check `CONSTITUTION.md`, `docs/CONSTITUTION.md`. Any refactor you propose must respect the listed principles.

Stop after one glob per input. If nothing turns up for a given input, proceed without it — don't hunt exhaustively.

**Empty-context case:** if none of these files exist (greenfield project, or one that doesn't capture conventions explicitly), that's a valid state — the review runs against the code itself. Do not halt; do not ask the user to produce convention files. You just won't have anchors for canonical names or stated principles; flag the gap in your candidates if it becomes load-bearing.

Then dispatch an exploration subagent to walk the codebase. Don't run a rigid checklist — explore organically and note where *you* feel friction, using the tells above. Apply the deletion test to anything that smells shallow.

### 2. Present candidates

Give the user a numbered list of refactoring opportunities. For each:

- **Files** — the modules involved
- **Problem** — the friction, ideally with the deletion-test result that confirmed it
- **Solution** — plain English: what module gets deepened, what moves behind the seam
- **Payoff** — stated in **leverage** and **locality**, and concretely in how tests get better

Use the project's own domain vocabulary for the *what* (if a glossary defines "Order", say "the Order intake module", not "the FooHandler"). The architecture words — deep, shallow, seam, leverage, locality — are this skill's; use them so suggestions stay comparable, but don't lecture the user about terminology.

If a candidate contradicts an existing ADR, only raise it when the friction genuinely warrants reopening that decision, and say so plainly: *"this cuts against ADR-0007, but it's worth reopening because…"*. Don't enumerate every refactor an ADR forbids.

Don't design interfaces yet. Ask: **"Which of these would you like to dig into?"**

### 3. Grill the chosen candidate

Once the user picks one, drop into a working conversation about the design. Walk the design tree together — constraints, dependencies, the shape of the deepened module, what sits behind the seam, which tests survive and which become dead weight. See [references/deepening.md](references/deepening.md) for how a module's dependency types dictate its testing strategy across the seam — read it before discussing dependencies.

If the user wants to compare several genuinely different interfaces for the deepened module, see [references/interface-design.md](references/interface-design.md) for a parallel-exploration pattern.

Side effects, handled inline as decisions firm up — all opt-in, all lazy:

- **Naming a module after a concept the project's glossary doesn't have?** If the project keeps a glossary, add the term. If it doesn't, offer to start one — don't impose it.
- **A fuzzy term got sharpened during the conversation?** Update the glossary entry then and there, if one exists.
- **The user rejects a candidate for a load-bearing reason** — a real constraint a future reviewer would otherwise miss and re-suggest the same thing — offer to record it as a short ADR: *"Want me to write this up as an ADR so a future review doesn't re-propose it?"* A minimal ADR is just: title, status, the decision, and the reason. Skip this for ephemeral reasons ("not worth it right now") or self-evident ones.

End when the design is settled and the user agrees. Implementation is theirs to run next.
