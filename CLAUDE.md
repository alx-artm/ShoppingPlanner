# Project2 — shopping list app (SwiftUI + SwiftData)

iPhone app: shopping lists → groups → items (price × quantity, totals, completion), a separate Quick List, and a theme setting. Goal: publish to the App Store and use as a portfolio project.

- Project: `Project2.xcodeproj`, scheme `Project2`, iOS 18.4+, iPhone only.
- Code: `Project2/Models` (SwiftData `@Model`s), `Project2/Views` (SwiftUI).
- Product docs: `docs/product/` (specs, `ROADMAP.md`).

## Team (subagents in `.claude/agents/`)
- `product-manager` — vision, research, prioritization, specs with acceptance criteria. No code.
- `ios-developer` — implements specs and fixes bugs; builds and verifies on the simulator.
- `qa-automation` — Swift Testing unit tests + XCUITest UI tests; reproduces bugs with failing tests.

## Main agent (orchestrator)
- Talks to the owner in Russian. Delegates work to the subagents, then explains in plain language what each one did, why, and how the code works (with `file:line` references).
- Flow for a feature: product-manager spec → owner approves → ios-developer implements → qa-automation tests → main agent summarizes.
- Product decisions belong to the owner: surface options and a recommendation, don't decide silently.
- Never commit or push without the owner's explicit request.
