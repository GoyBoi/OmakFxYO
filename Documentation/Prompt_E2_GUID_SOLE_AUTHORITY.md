# Prompt E2: GUID Sole Authority + Hygiene (Lock/Commit Layer)

**Date:** 2026-06-03  
**Constitutional Basis:** AGENTS.md §II (GUID Ownership), §V (Locked-Signal Mutation Precedence), §VII (Prohibited — GUID reuse, invisible state mutation)

---

## Summary

Eliminated provisional GUID adoption and sentinel-based GUID fallback. `LockedSignal::Lock()` is now the **sole GUID authority** — it always generates a fresh GUID, ignoring any provisional GUID from `SClosureSignal.m_guid`. `CommitSignalToStore` forces a zero-out on duplicate collision to trigger regen on retry.

---

## Changes

### 1. `core/CoreTypes.mqh` — `SLockedSignal::Lock()` (lines 434–442)

**Before (4-phase ambiguity):**
```
Phase 1: GUID_RESET — Clear stale GUID
Phase 2: GUID_ADOPTED — Adopt provisional from signal.m_guid if not retired
Phase 3: GUID_GENERATED — Fallback generate if adoption failed
Phase 4: GUID_REJECTED — Fail if zero
```

**After (sole authority, always fresh):**
```cpp
// Sole authority — ignore provisional, always generate fresh
this.m_guid = 0;
this.m_guid = GenerateSignalGUID(signal, execBranch, tf);

LogPrint("[GUID_ASSIGNED] sole_authority | GUID=" + IntegerToString(this.m_guid) +
         " | closure=" + EnumToString(signal.type), LOG_LEVEL_INFO);
```

**Rationale:**
- Provisional GUIDs from `SClosureSignal` created ambiguity — two potential sources of truth.
- `GUID_ADOPTED` could propagate stale/retired GUIDs despite the retirement check.
- The 4-phase logic introduced sentinel ranges (`GUID_SENTINEL_MIN`) that created hidden fallback paths.
- LockedSignal is the constitutional sole owner of GUID (AGENTS.md §II, File Ownership Map). It must not delegate or adopt GUIDs from other subsystems.

---

### 2. `OmakFxYO.mq5` — `CommitSignalToStore` (lines 1142–1148)

**Before:**
```cpp
if(IsGuidInStoreSafe(signal.m_guid, branch))
{
   LogPrint(StringFormat("[GUID_DUPLICATE_BLOCKED] GUID=%I64u | branch=%d", signal.m_guid, branch), LOG_LEVEL_WARN);
   return false;
}
```

**After:**
```cpp
if(IsGuidInStoreSafe(signal.m_guid, branch))
{
   LogPrint(StringFormat("[GUID_DUPLICATE_BLOCKED] Attempting regen | GUID=%I64u | branch=%d", signal.m_guid, branch), LOG_LEVEL_WARN);
   signal.m_guid = 0; // force regen in Lock on retry
   return false;
}
```

**Rationale:**
- Previously, a duplicate collision returned `false` without clearing `signal.m_guid`. The caller would retry Lock() but retain the same stale GUID, causing an infinite collision loop.
- Zeroing `signal.m_guid` guarantees that the next `Lock()` invocation enters the fresh-generation path.
- Per AGENTS.md §II: GUID reuse across signals = `[GUID_DUPLICATE_BLOCKED]`. This does not reuse the GUID — it blocks the commit and forces a new GUID.

---

## Verification

| Check | Expectation |
|-------|-------------|
| `Lock()` assigns GUID | `[GUID_ASSIGNED] sole_authority` logged with GUID and closure type |
| `CommitSignalToStore` duplicate | `[GUID_DUPLICATE_BLOCKED] Attempting regen` logged, `signal.m_guid` zeroed |
| No `[GUID_ADOPTED]` markers | Removed — no provisional adoption path exists |
| No `[GUID_GENERATED]` markers | Replaced by `[GUID_ASSIGNED]` |
| No `[GUID_REJECTED]` markers | Removed — generation always succeeds |
| Retry after duplicate | `Lock()` called again with `signal.m_guid == 0` → fresh GUID generated |

---

## Downstream Impact

- `SClosureSignal.m_guid` in `SClosureSignal::Reset()` still zeroes the field (line 351). This is harmless and serves as forensic trace only — Lock() no longer reads it.
- `IsRetiredGUIDCheck()` guard in Lock() is eliminated. Retirement is still enforced via `RetireGUID()` in `SLockedSignal::Reset()` — retired GUIDs never reach Lock() because `Reset()` clears them first.
- `GenerateSignalGUID(signal, execBranch, tf)` wrapper still delegates to `SLockedSignal::GenerateSignalGUID()`. Third parameter is unused; wrapper retained for backward compatibility.

---

## Compliance

- [x] GUID assigned once at Lock, immutable for signal life (§II)
- [x] GUID SOLELY owned by LockedSignal (§II)
- [x] No GUID reuse — `[GUID_DUPLICATE_BLOCKED]` blocks commit (§VII)
- [x] No invisible state mutation — `[GUID_ASSIGNED]`, `[GUID_DUPLICATE_BLOCKED]` logged (§V)
- [x] No partial fix — both Lock() and CommitSignalToStore updated
