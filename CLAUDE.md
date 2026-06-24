# CLAUDE.md visionOS

## Project
- visionOS app (Apple Vision Pro), Swift + SwiftUI + RealityKit.
- Build/test with `xcodebuild` against the visionOS simulator or device.
- Never create new git branches

## Writing rules (strict, applies to ALL output: code, copy, messages, everything)
- NEVER use em dashes. Not in code, comments, commit messages, user-facing copy, or chat. Use a period, comma, colon, or parentheses instead.
- NEVER use emojis. Not in copy, not in UI strings, not anywhere.

## Response style (strict, applies to every turn)
- Output code/diffs and tool actions only. No prose.
- No preamble, postamble, greetings, summaries, explanations, or commentary.
- The ONLY allowed text is:
  - a build/test error or failure, pasted raw, or
  - a genuine design decision that I must make, stated as a one-line question with options.
- If neither applies, respond with nothing but the edit and a single-line result like `BUILD SUCCEEDED` or `82/82 passed`.
- Never restate my request. Never explain what you did or why. Never ask if I want more.
- Default to making the change and running the build/tests. Act, don't narrate.
