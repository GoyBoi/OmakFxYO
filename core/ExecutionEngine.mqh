//+------------------------------------------------------------------+
//|                                         ExecutionEngine.mqh |
//|                        OmakFxYO — Gate 4: T-Spot POI Mapping |
//|                                                                  |
//| Sole responsibility: Map the T-Spot zone on the Entry TF and     |
//| identify a PD Array (Breaker Block, FVG, Order Block, or         |
//| Inversion FVG) as the candidateEntryPrice.                       |
//|                                                                  |
//| Per AGENTS.md §XVI Gate 4:                                       |
//|   - T-Spot is a ZONE (not fixed midpoint)                        |
//|   - Bullish zone: HTF Low to Equilibrium                         |
//|   - Bearish zone: Equilibrium to HTF High                        |
//|   - PD Array priority: Breaker Block > FVG > OB > InvFVG        |
//|   - If no PD Array found → STAGE_WAITING_FOR_POI (not fallback) |
//+------------------------------------------------------------------+
#ifndef OMAK_EXECUTIONENGINE_MQH
#define OMAK_EXECUTIONENGINE_MQH

#include <OmakFxYO/core/CoreTypes.mqh>
#include <OmakFxYO/core/LogGovernor.mqh>

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Execution Engine — Gate 4: T-Spot POI Mapping"

//+------------------------------------------------------------------+
//| ENUM_POI_STATUS — Result of T-Spot POI scan                      |
//+------------------------------------------------------------------+
enum ENUM_POI_STATUS
{
   POI_NONE    = 0,
   POI_MAPPED  = 1,
   POI_MISSING = 2
};

//+------------------------------------------------------------------+
//| ENUM_PD_ARRAY_TYPE — PD Array classification                     |
//+------------------------------------------------------------------+
enum ENUM_PD_ARRAY_TYPE
{
   PD_NONE        = 0,
   PD_BREAKER_BLOCK,   // Priority 1 — highest
   PD_FVG,              // Priority 2
   PD_ORDER_BLOCK,      // Priority 3
   PD_INVERSION_FVG     // Priority 4
};

//+------------------------------------------------------------------+
//| SPDArrayResult — Result from zone scan                           |
//+------------------------------------------------------------------+
struct SPDArrayResult
{
   bool   found;
   double price;            // Entry price (PD Array open or 0.5 level)
   ENUM_PD_ARRAY_TYPE type; // PD Array classification
   int    barIndex;         // Bar index on entry TF where POI was found
   double distanceFromEq;   // Absolute distance from Equilibrium (for closest-to-EQ tiebreaker)

   void Reset()
   {
      found = false;
      price = 0.0;
      type = PD_NONE;
      barIndex = -1;
      distanceFromEq = 0.0;
   }
};

//+------------------------------------------------------------------+
//| STSpotZone — T-Spot zone bounds                                  |
//|                                                                  |
//| Per AGENTS.md §XVI Gate 4:                                       |
//|   Bullish: low  = HTF Low                                        |
//|            high = Equilibrium (50%)                               |
//|   Bearish: low  = Equilibrium (50%)                               |
//|            high = HTF High                                        |
//+------------------------------------------------------------------+
struct STSpotZone
{
   double low;
   double high;
   double equilibrium;

   void Compute(double htfHigh, double htfLow, bool bullish)
   {
      equilibrium = (htfHigh + htfLow) / 2.0;
      if(bullish)
      {
         low  = htfLow;
         high = equilibrium;
      }
      else
      {
         low  = equilibrium;
         high = htfHigh;
      }
   }
};

//+------------------------------------------------------------------+
//| HELPER — Check if a price falls within the T-Spot zone           |
//+------------------------------------------------------------------+
bool InZone(double price, const STSpotZone &zone)
{
   return (price >= zone.low - 0.5 * _Point) &&
          (price <= zone.high + 0.5 * _Point);
}

//+------------------------------------------------------------------+
//| ScanForOB — Scan entry TF for Order Block inside zone            |
//|                                                                  |
//| OB: Candle whose open is inside the zone.                        |
//+------------------------------------------------------------------+
bool ScanForOB(const string symbol, ENUM_TIMEFRAMES entryTF, double zoneLow, double zoneHigh, double &outPrice)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, entryTF, 0, 52, rates);
   if(copied < 5) return false;

   int maxBars = MathMin(50, copied - 1);
   for(int i = 1; i < maxBars; i++)
   {
      double obOpen = rates[i].open;
      if(obOpen < zoneLow || obOpen > zoneHigh) continue;

      bool isDownClose = (rates[i].close < rates[i].open);
      bool isUpClose   = (rates[i].close > rates[i].open);
      if(!isDownClose && !isUpClose) continue;

      outPrice = obOpen;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| ScanForFVG — Scan entry TF for Fair Value Gap (0.5 midpoint)     |
//|                                                                  |
//| FVG: Three-candle imbalance. Entry price = gap midpoint (0.5).   |
//+------------------------------------------------------------------+
bool ScanForFVG(const string symbol, ENUM_TIMEFRAMES entryTF, double zoneLow, double zoneHigh, double &outPrice)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, entryTF, 0, 52, rates);
   if(copied < 5) return false;

   int maxBars = MathMin(50, copied - 2);
   for(int i = 1; i < maxBars; i++)
   {
      double gapHigh = MathMin(rates[i+1].high, rates[i-1].high);
      double gapLow  = MathMax(rates[i+1].low,  rates[i-1].low);
      if(gapHigh >= gapLow) continue;

      bool isBullishGap = (rates[i+1].high < rates[i-1].low);
      bool isBearishGap = (rates[i+1].low  > rates[i-1].high);
      if(!isBullishGap && !isBearishGap) continue;

      double fvgMid = (gapHigh + gapLow) / 2.0;
      if(fvgMid < zoneLow || fvgMid > zoneHigh) continue;

      outPrice = fvgMid;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| ScanForIFVG — Scan entry TF for Inversion FVG                    |
//|                                                                  |
//| IFVG: A gap that price has aggressively closed through.          |
//+------------------------------------------------------------------+
bool ScanForIFVG(const string symbol, ENUM_TIMEFRAMES entryTF, double zoneLow, double zoneHigh, double &outPrice)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, entryTF, 0, 52, rates);
   if(copied < 5) return false;

   int maxBars = MathMin(50, copied - 2);
   for(int i = 1; i < maxBars; i++)
   {
      double gapHigh = MathMin(rates[i+1].high, rates[i-1].high);
      double gapLow  = MathMax(rates[i+1].low,  rates[i-1].low);
      if(gapHigh >= gapLow) continue;

      bool isBullishGap = (rates[i+1].high < rates[i-1].low);
      bool isBearishGap = (rates[i+1].low  > rates[i-1].high);
      if(!isBullishGap && !isBearishGap) continue;

      // Zone overlap check (not strict midpoint containment)
      if(gapHigh <= zoneLow || gapLow >= zoneHigh) continue;

      // Check reclamation: price closed through the gap
      for(int j = i - 1; j >= 0; j--)
      {
         bool reclaimed = false;
         if(isBullishGap)
            reclaimed = (rates[j].close < gapLow);
         else if(isBearishGap)
            reclaimed = (rates[j].close > gapHigh);

         if(reclaimed)
         {
            outPrice = (gapHigh + gapLow) / 2.0;
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| CheckBreakerCondition — Check if a bar forms a Breaker Block     |
//|                                                                  |
//| A Breaker Block is a structural swing that was broken (swept)    |
//| and now serves as support/resistance. Entry price = swing        |
//| point open within the T-Spot zone.                              |
//+------------------------------------------------------------------+
bool CheckBreakerCondition(const string symbol, ENUM_TIMEFRAMES tf, int bar, double low, double high, double &outEntry)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, 0, 52, rates);
   if(copied < 5) return false;

   if(bar < 2 || bar >= copied - 2) return false;

   // Bearish Breaker Block: swing high broken, level acts as resistance
   if(rates[bar].high > rates[bar-1].high && rates[bar].high > rates[bar-2].high &&
      rates[bar].high >= rates[bar+1].high && rates[bar].high >= rates[bar+2].high)
   {
      bool broken = false;
      for(int j = bar - 1; j >= 0; j--)
      {
         if(rates[j].high > rates[bar].high + 0.5 * _Point)
         {
            broken = true;
            break;
         }
      }
      if(!broken) return false;

      double level = rates[bar].open;
      if(level >= low - 0.5 * _Point && level <= high + 0.5 * _Point)
      {
         outEntry = level;
         return true;
      }
   }

   // Bullish Breaker Block: swing low broken, level acts as support
   if(rates[bar].low < rates[bar-1].low && rates[bar].low < rates[bar-2].low &&
      rates[bar].low <= rates[bar+1].low && rates[bar].low <= rates[bar+2].low)
   {
      bool broken = false;
      for(int j = bar - 1; j >= 0; j--)
      {
         if(rates[j].low < rates[bar].low - 0.5 * _Point)
         {
            broken = true;
            break;
         }
      }
      if(!broken) return false;

      double level = rates[bar].open;
      if(level >= low - 0.5 * _Point && level <= high + 0.5 * _Point)
      {
         outEntry = level;
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| ScanForBreakerBlock — Mechanical BK detection (highest priority) |
//|                                                                  |
//| VERBATIM REPAIR: Investigation VIII - Breaker Block Priority     |
//| Scans the last 20 bars on the entry TF for a Breaker Block       |
//| within the T-Spot zone. BK is the highest-priority PD Array.     |
//+------------------------------------------------------------------+
bool ScanForBreakerBlock(const string symbol, ENUM_TIMEFRAMES tf, double low, double high, double &outEntry)
{
   int total = iBars(symbol, tf);
   for(int i = 1; i < 20 && i < total; i++)
   {
      if(CheckBreakerCondition(symbol, tf, i, low, high, outEntry)) return true;
   }
   return false;
}

// VERBATIM REPAIR: Trinity Scanner Sequence (§3)
bool EE_ScanPDArray(const string symbol, ENUM_TIMEFRAMES tf, double low, double high, double &outEntry) {
    // Priority 1: Breaker Block (BK)
    if (ScanForBreakerBlock(symbol, tf, low, high, outEntry)) return true;
    
    // Priority 2: Order Block (OB)
    if (ScanForOB(symbol, tf, low, high, outEntry)) return true;
    
    // Priority 3: FVG (0.5 Midpoint)
    if (ScanForFVG(symbol, tf, low, high, outEntry)) return true;
    
    // Priority 4: Inversion FVG (IFVG)
    if (ScanForIFVG(symbol, tf, low, high, outEntry)) return true;

    outEntry = 0.0;
    return false; // Hard Reject: No PD Array Oxygen found
}

//+------------------------------------------------------------------+
//| EE_MapPOI — Main entry: Map T-Spot zone and find PD Array       |
//|                                                                  |
//| This is the primary Gate 4 function. It:                        |
//|   1. Computes the T-Spot zone from HTF high/low                  |
//|   2. Scans the entry TF for a PD Array within the zone          |
//|   3. Sets candidateEntryPrice or returns POI_MISSING             |
//|                                                                  |
//| @param symbol               Trading symbol                       |
//| @param entryTf              Entry timeframe                      |
//| @param htfHigh              HTF candle high                      |
//| @param htfLow               HTF candle low                       |
//| @param bullish              True for BUY, false for SELL         |
//| @param candidateEntryPrice  Output: entry price from PD Array    |
//| @param mappedPrice          Output: raw price of mapped POI      |
//| @param mappedType           Output: PD Array type                |
//| @return POI_MAPPED on success, POI_MISSING if no PD Array found |
//+------------------------------------------------------------------+
ENUM_POI_STATUS EE_MapPOI(
   const string symbol,
   ENUM_TIMEFRAMES entryTf,
   double htfHigh,
   double htfLow,
   bool bullish,
   double &candidateEntryPrice,
   double &mappedPrice,
   ENUM_PD_ARRAY_TYPE &mappedType
)
{
   // Step 1: Compute T-Spot zone
   STSpotZone zone;
   zone.Compute(htfHigh, htfLow, bullish);

   // Step 2: Scan for PD Array using Trinity scanner
   double outEntry = 0.0;
   bool found = EE_ScanPDArray(symbol, entryTf, zone.low, zone.high, outEntry);

   if(!found)
   {
      candidateEntryPrice = 0.0;
      mappedPrice = 0.0;
      mappedType = PD_NONE;

      LogPrint("[TSPOT_POI_MISSING] No PD Array found on " + EnumToString(entryTf) +
               " | zone=[" + DoubleToString(zone.low, _Digits) + ", " +
               DoubleToString(zone.high, _Digits) + "]" +
               " | eq=" + DoubleToString(zone.equilibrium, _Digits) +
               " | dir=" + (bullish ? "BUY" : "SELL"), LOG_LEVEL_INFO);
      return POI_MISSING;
   }

   // Step 3: Assign entry price
   candidateEntryPrice = outEntry;
   mappedPrice = outEntry;
   mappedType = PD_NONE;

   // Step 4: Log the mapping
   LogPrint("[TSPOT_POI_MAPPED] on " + EnumToString(entryTf) +
            " | price=" + DoubleToString(outEntry, _Digits) +
            " | zone=[" + DoubleToString(zone.low, _Digits) + ", " +
            DoubleToString(zone.high, _Digits) + "]" +
            " | eq=" + DoubleToString(zone.equilibrium, _Digits) +
            " | dir=" + (bullish ? "BUY" : "SELL"), LOG_LEVEL_INFO);

   return POI_MAPPED;
}

//+------------------------------------------------------------------+
//| EE_MapPOIForSignal — Map T-Spot POI on an SLockedSignal          |
//|                                                                  |
//| The primary Gate 4 entry point for the signal lifecycle.          |
//| Determines entry TF from signal branch, computes the T-Spot       |
//| zone from HTF high/low, scans for a PD Array, and sets           |
//| signal.requestedEntryPrice on success.                            |
//|                                                                  |
//| Returns POI_MAPPED on success, POI_MISSING if no PD Array found. |
//| On POI_MISSING, signal.requestedEntryPrice is set to 0.0 so      |
//| the lifecycle engine may transition to STAGE_WAITING_FOR_POI.    |
//|                                                                  |
//| Per AGENTS.md §XVI Gate 4:                                       |
//|   - No fixed midpoint fallback — strictly zone-based PD scan     |
//|   - If no PD Array found → STAGE_WAITING_FOR_POI                 |
//+------------------------------------------------------------------+
ENUM_POI_STATUS EE_MapPOIForSignal(
   SLockedSignal &signal,
   double htfHigh,
   double htfLow,
   bool bullish
)
{
   ENUM_TIMEFRAMES entryTf = (signal.branchId == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;

   double mappedPrice = 0.0;
   ENUM_PD_ARRAY_TYPE mappedType = PD_NONE;

   ENUM_POI_STATUS status = EE_MapPOI(
      signal.symbol, entryTf, htfHigh, htfLow, bullish,
      signal.candidateEntryPrice, mappedPrice, mappedType
   );

   if(status == POI_MAPPED)
   {
      signal.requestedEntryPrice = mappedPrice;
      LogPrint("[TSPOT_POI_MAPPED] GUID=" + IntegerToString(signal.m_guid) +
               " | price=" + DoubleToString(mappedPrice, _Digits) +
               " | type=" + EnumToString(mappedType) +
               " | zone=[L:" + DoubleToString(htfLow, _Digits) +
               ", H:" + DoubleToString(htfHigh, _Digits) + "]" +
               " | dir=" + (bullish ? "BUY" : "SELL"), LOG_LEVEL_INFO);
   }
   else
   {
      signal.requestedEntryPrice = 0.0;
      LogPrint("[TSPOT_POI_MISSING] GUID=" + IntegerToString(signal.m_guid) +
               " | zone=[L:" + DoubleToString(htfLow, _Digits) +
               ", H:" + DoubleToString(htfHigh, _Digits) + "]" +
               " | dir=" + (bullish ? "BUY" : "SELL"), LOG_LEVEL_INFO);
   }

   return status;
}

//+------------------------------------------------------------------+
//| EE_MapPOISimple — Simplified variant (sets candidateEntryPrice   |
//| directly on an SLockedSignal-like struct)                        |
//|                                                                  |
//| Returns true if POI was mapped, false if missing.                |
//+------------------------------------------------------------------+
bool EE_MapPOISimple(
   const string symbol,
   ENUM_TIMEFRAMES entryTf,
   double htfHigh,
   double htfLow,
   bool bullish,
   double &candidateEntryPrice
)
{
   double mappedPrice = 0.0;
   ENUM_PD_ARRAY_TYPE mappedType = PD_NONE;

   ENUM_POI_STATUS status = EE_MapPOI(
      symbol, entryTf, htfHigh, htfLow, bullish,
      candidateEntryPrice, mappedPrice, mappedType
   );

   return (status == POI_MAPPED);
}

//+------------------------------------------------------------------+
//| EE_CheckZoneOverlap — Check if a price falls in the T-Spot zone |
//|                                                                  |
//| Useful for STAGE_WAITING_FOR_POI: check whether the current      |
//| price has entered the zone, indicating a possible POI trigger.   |
//+------------------------------------------------------------------+
bool EE_CheckZoneOverlap(
   double price,
   double htfHigh,
   double htfLow,
   bool bullish
)
{
   STSpotZone zone;
   zone.Compute(htfHigh, htfLow, bullish);
   return InZone(price, zone);
}

//+------------------------------------------------------------------+
//| ScanForPDArray — Unified PD Array scanner wrapper                |
//|                                                                  |
//| Per Prompt 6 / §XVII Gate 4: Scans the T-Spot zone for OB or FVG |
//| and returns the POI price. Returns 0.0 if no POI found.          |
//|                                                                  |
//| @param tSpotMin  Zone lower bound                                 |
//| @param tSpotMax  Zone upper bound                                 |
//| @param bullish   True for BUY, false for SELL                     |
//| @param symbol    Trading symbol                                   |
//| @param entryTf   Entry timeframe                                  |
//| @return POI price, or 0.0 if no PD Array found                   |
//+------------------------------------------------------------------+
double ScanForPDArray(double tSpotMin, double tSpotMax, bool bullish, const string symbol, ENUM_TIMEFRAMES entryTf)
{
   double zoneLow = MathMin(tSpotMin, tSpotMax);
   double zoneHigh = MathMax(tSpotMin, tSpotMax);

   if(zoneLow <= 0.0 || zoneHigh <= 0.0 || zoneLow >= zoneHigh)
      return 0.0;

   double outPrice = 0.0;
   if(!EE_ScanPDArray(symbol, entryTf, zoneLow, zoneHigh, outPrice))
      return 0.0;

   return outPrice;
}

//+------------------------------------------------------------------+
//| EE_MapC3POI — Gate 4 for C3 signals (zone via tSpotMin/Max)     |
//|                                                                  |
//| SURGICAL LOGIC: No midpoints allowed. Strict PD Array scan per   |
//| Prompt 6 / §XVII Gate 4. Sets signal.entry_price directly.       |
//+------------------------------------------------------------------+
void EE_MapC3POI(SLockedSignal &sig) {
    ENUM_TIMEFRAMES entryTf = (sig.branchId == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;
    bool bullish = (sig.direction == DIRECTION_BUY);
    double mappedPrice = ScanForPDArray(sig.tSpotMin, sig.tSpotMax, bullish, sig.symbol, entryTf);
    if (mappedPrice > 0) {
        sig.entry_price = mappedPrice;
        sig.requestedEntryPrice = mappedPrice; // CRITICAL: Pipeline check
        sig.candidateEntryPrice = mappedPrice;
        LogPrint("[TSPOT_POI_MAPPED] C3 | Price: " + DoubleToString(mappedPrice, _Digits) + " | Branch " + IntegerToString(g_activeBranch), LOG_LEVEL_INFO);
    }
}

//+------------------------------------------------------------------+
//| EE_MapTSpotPOI — Gate 4 POI mapper (PD Array Supremacy)         |
//|                                                                  |
//| VERBATIM REPAIR: Gate 4 PD Array Supremacy (§XVII)              |
//| Entry MUST be a real Order Block or FVG. Midpoint fallbacks      |
//| are prohibited.                                                  |
//+------------------------------------------------------------------+
bool EE_MapTSpotPOI(SLockedSignal &sig)
{
   ENUM_TIMEFRAMES entryTf = (sig.branch == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;
   bool bullish = (sig.direction == DIRECTION_BUY);

   // VERBATIM REPAIR: T-Spot Boundary Law (§II)
   // Bullish: Equilibrium to HTF Low | Bearish: Equilibrium to HTF High
   ENUM_TIMEFRAMES anchorTF = (sig.branch == BRANCH_INTRADAY) ? PERIOD_D1 : PERIOD_W1;
   double htfHigh = iHigh(_Symbol, anchorTF, 1);
   double htfLow  = iLow(_Symbol, anchorTF, 1);
   double htfRange = MathAbs(htfHigh - htfLow);
   double equilibrium = htfLow + (htfRange * 0.5);

   if (bullish) {
       sig.tSpotMin = htfLow;        // HTF Extreme
       sig.tSpotMax = equilibrium;   // Midpoint
   } else {
       sig.tSpotMin = equilibrium;   // Midpoint
       sig.tSpotMax = htfHigh;       // HTF Extreme
   }

   double zoneLow  = MathMin(sig.tSpotMin, sig.tSpotMax);
   double zoneHigh = MathMax(sig.tSpotMin, sig.tSpotMax);
   if(zoneLow <= 0.0 || zoneHigh <= 0.0 || zoneLow >= zoneHigh)
   {
      sig.entry_price = 0.0;
      sig.requestedEntryPrice = 0.0;
      sig.candidateEntryPrice = 0.0;
      LogPrint("[GATE_4_REJECT] Invalid zone bounds.", LOG_LEVEL_INFO);
      return false;
   }

   double mappedPrice = 0.0;
   if(!EE_ScanPDArray(sig.symbol, entryTf, zoneLow, zoneHigh, mappedPrice))
   {
      sig.entry_price = 0.0;
      sig.requestedEntryPrice = 0.0;
      sig.candidateEntryPrice = 0.0;
      LogPrint("[GATE_4_REJECT] T-Spot zone empty. Entry denied.", LOG_LEVEL_INFO);
      return false;
   }

   sig.entry_price = mappedPrice;
   sig.requestedEntryPrice = mappedPrice;
   sig.candidateEntryPrice = mappedPrice;
   LogPrint("[TSPOT_POI_MAPPED] Trinity scan | Price=" + DoubleToString(mappedPrice, _Digits), LOG_LEVEL_INFO);
   return true;
}

//+------------------------------------------------------------------+
//| EE_IsStageWaitingForPOI — Check if signal wait is still valid    |
//|                                                                  |
//| Returns true if the signal is in STAGE_WAITING_FOR_POI and has    |
//| not exceeded the max wait bars limit (default 50).               |
//|                                                                  |
//| Per AGENTS.md §XVI Gate 4: If no PD Array found, the signal must |
//| wait — it must not fall back to a fixed midpoint.                |
//+------------------------------------------------------------------+
bool EE_IsStageWaitingForPOI(const SLockedSignal &signal, int currentBar, int maxWaitBars = 50)
{
   if(signal.stage != STAGE_WAITING_FOR_POI)
      return false;
   if(signal.m_detectionTime <= 0)
      return false;
   ENUM_TIMEFRAMES _entryTfWait = (signal.branchId == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;
   int secondsSinceDetection = (int)(TimeCurrent() - signal.m_detectionTime);
   int barsWaited = secondsSinceDetection / PeriodSeconds(_entryTfWait);
   if(barsWaited > maxWaitBars)
   {
      LogPrint("[POI_WAIT_EXPIRED] GUID=" + IntegerToString(signal.m_guid) +
               " | barsWaited=" + IntegerToString(barsWaited) +
               " | max=" + IntegerToString(maxWaitBars), LOG_LEVEL_INFO);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| EE_ResolvePOIWait — Re-scan T-Spot zone for a waiting signal     |
//|                                                                  |
//| Called periodically while a signal is in STAGE_WAITING_FOR_POI.   |
//| Re-scans the Entry TF for a PD Array. If found, sets              |
//| requestedEntryPrice and returns POI_MAPPED.                       |
//|                                                                  |
//| Returns:                                                          |
//|   POI_MAPPED  — POI resolved, caller should advance stage        |
//|   POI_MISSING — Still no POI, remain in STAGE_WAITING_FOR_POI    |
//|   POI_NONE    — Signal not in WAITING_FOR_POI stage, no action   |
//|                                                                  |
//| Per AGENTS.md §XVI Gate 4:                                       |
//|   - No fixed midpoint fallback — must find real PD Array         |
//+------------------------------------------------------------------+
ENUM_POI_STATUS EE_ResolvePOIWait(
   SLockedSignal &signal,
   double htfHigh,
   double htfLow,
   bool bullish,
   int currentBar
)
{
   if(signal.stage != STAGE_WAITING_FOR_POI)
      return POI_NONE;

   ENUM_TIMEFRAMES entryTf = (signal.branchId == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;

   STSpotZone zone;
   zone.Compute(htfHigh, htfLow, bullish);

   double outPrice = 0.0;
   bool found = EE_ScanPDArray(signal.symbol, entryTf, zone.low, zone.high, outPrice);

   if(found)
   {
      signal.requestedEntryPrice = outPrice;
      LogPrint("[TSPOT_POI_MAPPED] Resolved from WAITING | GUID=" + IntegerToString(signal.m_guid) +
               " | price=" + DoubleToString(outPrice, _Digits) +
               " | zone=[L:" + DoubleToString(zone.low, _Digits) +
               ", H:" + DoubleToString(zone.high, _Digits) + "]" +
               " | bar=" + IntegerToString(currentBar), LOG_LEVEL_INFO);
      return POI_MAPPED;
   }

   if(signal.m_detectionTime > 0)
   {
      int secondsWaited = (int)(TimeCurrent() - signal.m_detectionTime);
      int barsWaited = secondsWaited / PeriodSeconds(entryTf);
      if(barsWaited > 0 && barsWaited % 5 == 0)
      {
         LogPrint("[TSPOT_POI_MISSING] Still waiting | GUID=" + IntegerToString(signal.m_guid) +
                  " | barsWaited=" + IntegerToString(barsWaited) +
                  " | secondsWaited=" + IntegerToString(secondsWaited) +
                  " | zone=[L:" + DoubleToString(zone.low, _Digits) +
                  ", H:" + DoubleToString(zone.high, _Digits) + "]", LOG_LEVEL_DEBUG);
      }
   }

   return POI_MISSING;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+

#endif // OMAK_EXECUTIONENGINE_MQH
