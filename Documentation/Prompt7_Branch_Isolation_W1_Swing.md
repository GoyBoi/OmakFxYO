## Prompt 7 Report: Branch Isolation & W1 Swing Shift [INTERPRETIVE]

### Changes Applied

**1. `CoreTypes.mqh` — New enum added**
`core/CoreTypes.mqh:72-79`: Added `ENUM_ACTIVE_BRANCH { BRANCH_A = 0, BRANCH_B = 1 }` alongside `ENUM_EXECUTION_BRANCH`. Values are intentionally aligned for implicit casting.

**2. `OmakFxYO.mq5` — Input + globals + OnInit override**

- `OmakFxYO.mq5:33`: Added `input ENUM_ACTIVE_BRANCH InpActiveBranch = BRANCH_A`
- `OmakFxYO.mq5:221`: `g_activeBranch` now derives from `InpActiveBranch` (was `InpBranch`)
- `OmakFxYO.mq5:222`: Added `ENUM_ACTIVE_BRANCH g_activeBranchSelection = InpActiveBranch` for cross-file access
- `OmakFxYO.mq5:3221-3225`: When `InpActiveBranch == BRANCH_B`, overrides `g_branchTF.biasTF = PERIOD_W1` (was D1 for both branches)

**3. `ClosureEngine.mqh` — Branch gate + extern**

- `ClosureEngine.mqh:205`: Added `extern ENUM_ACTIVE_BRANCH g_activeBranchSelection`
- `ClosureEngine.mqh:2158-2163`: Added isolation gate in `DetectClosureSignal` — rejects signals if `ctx.branch != g_activeBranch`

### Constitutional Compliance

| Rule | Status |
|------|--------|
| Branch isolation (§I) | Enforced — no signal from wrong branch leaks through `DetectClosureSignal` |
| Branch B anchor = W1 (§I) | `biasTF` overridden to `PERIOD_W1` in `OnInit` when `BRANCH_B` active |
| No branch contamination (§VII) | Gate ensures only the active branch's signals enter the pipeline |
| Canonical markers | Not emitted here — markers follow downstream detection paths |
| No silent mutation | `g_branchTF.biasTF` override logged at INFO via existing OnInit logging |

### Open Question

The current `GetBranchTimeframes()` (`BranchRouter.mqh:79`) still sets `biasTF = PERIOD_D1` for both branches. The override in `OnInit` patches the discrepancy, but a future refactor should update `GetBranchTimeframes()` itself to return `PERIOD_W1` for `BRANCH_SWING`. This would eliminate the two-step init.
