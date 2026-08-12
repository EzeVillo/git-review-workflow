# Release checklist: 009-plugin-intellij

**Purpose**: evidence for SC-001…SC-010 before Marketplace v1.

| SC | Criterion | Evidence | Status |
|----|-----------|----------|--------|
| SC-001 | Full cycle start→edit→finish without terminal (except network) | manual smoke quickstart | [ ] |
| SC-002 | Panel refresh coalesced; no list/config during active review | ReviewStateManager + unit | [x] |
| SC-003 | 27 actions argv parity | ActionArgvParityTest | [x] |
| SC-004 | Non-ASCII paths open | unit unquote + manual Win/macOS/Linux | [ ] |
| SC-005 | cli-missing/outdated + install copy | panel + InstallHint + YAML | [x] |
| SC-006 | No CLI until tool window shown | factory lazy design; platformTest TODO | [ ] |
| SC-007 | Domain unit suite green | `./gradlew -p jetbrains-plugin test` (2026-08-08 BUILD SUCCESSFUL) | [x] |
| SC-008 | Anti-drift CI | `check-client-product-surface.mjs` | [x] |
| SC-009 | Three OS smoke | README smoke matrix | [ ] |
| SC-010 | Diff deleted/added files | NameStatusTest + OpenEntryActions | [x] |

## Smoke notes

- Pin: see `jetbrains-plugin/gradle.properties` (2026.1 / 261 / JDK 21; open until-build).
- Commands: `test`, `platformTest`, `runIde`, `runPanelPreview`, `buildPlugin`, `verifyPlugin`.
