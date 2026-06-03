# Prompt 3 — T-Spot POI Mapping (Gate 4)

**Focus:** Create `ExecutionEngine.mqh` to map the T-Spot zone and scan for a PD Array (Breaker Block, FVG, Order Block, Inversion FVG) as the `candidateEntryPrice`, solving the `entry_price = 0` signal death.

**Constitutional Authority:** AGENTS.md §XVI Gate 4, §XVII T-Spot POI Mapping (Zone-Based)

---

## File Created

`OmakFxYO/core/ExecutionEngine.mqh` (new)

---

## Architecture

### T-Spot Zone Definition (per AGENTS.md §XVI Gate 4)

| Direction | Zone Range       | Lower Bound | Upper Bound |
|-----------|------------------|-------------|-------------|
| Bullish   | HTF Low → Equilibrium | `htfLow` | `htfEq` |
| Bearish   | Equilibrium → HTF High | `htfEq` | `htfHigh` |

Equilibrium formula: `(htfHigh + htfLow) / 2.0`

### PD Array Priority (per AGENTS.md §XVII)

1. **Breaker Block** — last candle before a significant move
2. **Fair Value Gap** — three-candle imbalance (`gapHigh < gapLow`)
3. **Order Block** — last down/up candle before reversal
4. **Inversion FVG** — FVG that was traded through and reclaimed

When multiple PD Arrays are found, the one **closest to Equilibrium** is selected.

---

## Public API

| Function | Purpose | Returns |
|----------|---------|---------|
| `EE_MapPOI()` | Full POI mapping with type and price output | `ENUM_POI_STATUS` (`POI_MAPPED` / `POI_MISSING`) |
| `EE_MapPOISimple()` | Simplified variant, returns `bool` | `true` if mapped, `false` if missing |
| `EE_CheckZoneOverlap()` | Check if a price falls inside the T-Spot zone | `bool` |

### EE_MapPOI Signature

```cpp
ENUM_POI_STATUS EE_MapPOI(
   const string symbol,
   ENUM_TIMEFRAMES entryTf,
   double htfHigh,
   double htfLow,
   bool bullish,
   double &candidateEntryPrice,
   double &mappedPrice,
   ENUM_PD_ARRAY_TYPE &mappedType
);
```

---

## Internal Helpers

| Helper | Purpose |
|--------|---------|
| `STSpotZone::Compute()` | Sets zone.low, zone.high, zone.equilibrium from HTF extremes and direction |
| `InZone()` | Checks if a price falls within the zone (with 0.5 pip tolerance) |
| `EE_ScanPDArray()` | Scans entry TF bars [1..scanBars-1] for OB, FVG, and InvFVG within zone |

### EE_ScanPDArray Logic

- **Order Block:** Any candle whose `open` falls in the zone, with a clear close direction (`close < open` for down, `close > open` for up)
- **Fair Value Gap:** Three-candle pattern where candle `i+1` and candle `i-1` do not overlap, leaving an imbalance. The gap midpoint is the reference price; entry at 0.5 level of gap.
- **Inversion FVG:** FVG where a subsequent bar reclaimed it (closed beyond the gap boundary on the opposite side)

---

## Canonical Markers

| Marker | When | Data |
|--------|------|------|
| `[TSPOT_POI_MAPPED]` | PD Array found in zone | type, price, barIndex, zone [low, high], eq, direction |
| `[TSPOT_POI_MISSING]` | No PD Array found | zone [low, high], eq, direction |

---

## Key Design Decisions

1. **Zone bounds corrected** to match AGENTS.md §XVI Gate 4 (prompt's code had swapped direction)
2. **No fixed midpoint fallback** — if no PD Array found, `candidateEntryPrice` stays 0 and `POI_MISSING` is returned (signal enters `STAGE_WAITING_FOR_POI`)
3. **PD Array priority** implemented with closest-to-Equilibrium tiebreaker
4. **Entry price** = PD Array open (for OB) or gap 0.5 level (for FVG)
5. **Stop loss** not set here — it is placed beyond the Protected Swing by the Risk subsystem (per AGENTS.md §VI)
