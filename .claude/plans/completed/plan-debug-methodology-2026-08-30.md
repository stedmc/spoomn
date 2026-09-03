# Plan: Debug Methodology

Items from needtofix.md: 17

---

## Rule (standing instruction)

If the root cause of a bug is not immediately obvious, do NOT make a speculative fix.

Instead:

1. Create a bug tracking file at `.claude/bugs/bug-<short-name>.md`.
2. Add targeted `debugPrint` / `print` statements to surface the relevant state.
3. Document what was logged and what to look for in `.claude/bugs/bug-<short-name>.md`.
4. Wait for log output before implementing any fix.
5. Once the root cause is confirmed, update the bug file with findings, then fix.
6. Delete the bug file (or mark resolved) after the fix is verified.

---

## Bug files to create alongside this plan

The following bugs from needtofix.md require this treatment before any fix attempt:

- **Items 7 & 8** — Player stuck in trade phase after dice roll → `.claude/bugs/bug-trade-phase-after-roll.md`
- **Item 5** — Duplicate game rooms in list → `.claude/bugs/bug-duplicate-game-rooms.md`

---

## Bug file template

```markdown
# Bug: <short description>

## Symptom
<what the user sees>

## Debug logging added
- File: <path>
- Line: <approx>
- What it logs: <description>

## Findings
<fill in once logs are captured>

## Root cause
<fill in once confirmed>

## Fix
<fill in once implemented>
```
