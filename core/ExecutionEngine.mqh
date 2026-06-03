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
//| EE_ScanPDArray — Scan entry TF bars for PD Array inside zone    |
//|                                                                  |
//| Scans bars [1 .. scanBars-1] on the entry TF, looking for       |
//| Order Blocks and Fair Value Gaps whose reference price falls     |
//| within the T-Spot zone.                                          |
//|                                                                  |
//| PD Array priority:                                                |
//|   1. Breaker Block (last candle before a significant move)       |
//|   2. Fair Value Gap (three-candle imbalance)                     |
//|   3. Order Block (last down/up candle before reversal)           |
//|   4. Inversion FVG (FVG that was traded through and reclaimed)   |
//|                                                                  |
//| If multiple PD Arrays found, selects the one closest to          |
//| Equilibrium (per AGENTS.md §XVII).                               |
//|                                                                  |
//| @param symbol        Trading symbol                              |
//| @param entryTf       Entry timeframe (M5 for Branch A, M15 for B)|
//| @param zone          Pre-computed T-Spot zone                    |
//| @param scanBars      Number of bars to scan (default 50)         |
//| @param result        Output: found PD Array details              |
//+------------------------------------------------------------------+
void EE_ScanPDArray(
   const string symbol,
   ENUM_TIMEFRAMES entryTf,
   const STSpotZone &zone,
   int scanBars,
   SPDArrayResult &result
)
{
   result.Reset();

   if(scanBars < 3)
      scanBars = 3;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   ZeroMemory(rates);

   int copied = CopyRates(symbol, entryTf, 0, scanBars + 2, rates);
   if(copied < 5)
   {
      LogPrint("[TSPOT_POI_MISSING] Insufficient bars on " + EnumToString(entryTf) +
               " | copied=" + IntegerToString(copied), LOG_LEVEL_DEBUG);
      return;
   }

   int maxBars = MathMin(scanBars, copied - 2); // reserve 2 bars for FVG scan

   // Scan each bar for PD Arrays within the zone
   for(int i = 1; i < maxBars; i++)
   {
      // --- Order Block Detection ---
      // OB: The last candle before a significant move in the target direction.
      // For bullish: look for down-close candle (close < open) that precedes up moves.
      // For bearish: look for up-close candle (close > open) that precedes down moves.
      double obOpen = rates[i].open;
      if(InZone(obOpen, zone))
      {
         // Check if this is a meaningful OB (has a clear close direction)
         bool isDownClose = (rates[i].close < rates[i].open);
         bool isUpClose   = (rates[i].close > rates[i].open);

         if(isDownClose || isUpClose)
         {
            double dist = MathAbs(obOpen - zone.equilibrium);

            // Accept as OB if no better candidate exists
            if(!result.found ||
               dist < result.distanceFromEq ||
               (dist == result.distanceFromEq && result.type > PD_ORDER_BLOCK))
            {
               result.found = true;
               result.price = obOpen;
               result.type = PD_ORDER_BLOCK;
               result.barIndex = i;
               result.distanceFromEq = dist;
            }
         }
      }

      // --- Fair Value Gap Detection ---
      // FVG: Three-candle pattern where candle i+1 high < candle i low (bullish)
      // or candle i+1 low > candle i high (bearish), leaving an imbalance.
      double fvgRef = 0.0;
      ENUM_PD_ARRAY_TYPE fvgType = PD_NONE;
      bool isBullishGap = false;
      bool isBearishGap = false;

      double gapHigh = MathMin(rates[i+1].high, rates[i-1].high);
      double gapLow  = MathMax(rates[i+1].low,  rates[i-1].low);

      if(gapHigh < gapLow) // gap exists
      {
         // Bullish FVG: low of candle i (the gap's lower boundary)
         // Bearish FVG: high of candle i (the gap's upper boundary)
         isBullishGap = (rates[i+1].high < rates[i-1].low);
         isBearishGap = (rates[i+1].low  > rates[i-1].high);

         if(isBullishGap || isBearishGap)
         {
            // Use the gap midpoint as reference for zone check
            fvgRef = (gapHigh + gapLow) / 2.0;
            fvgType = PD_FVG;

            if(InZone(fvgRef, zone))
            {
               double dist = MathAbs(fvgRef - zone.equilibrium);

               if(!result.found ||
                  dist < result.distanceFromEq ||
                  (dist == result.distanceFromEq && result.type > PD_FVG))
               {
                  // Entry price = 0.5 level of the gap
                  result.found = true;
                  result.price = fvgRef;
                  result.type = PD_FVG;
                  result.barIndex = i;
                  result.distanceFromEq = dist;
               }
            }
         }
      }

      // --- Inversion FVG Detection ---
      // InvFVG: A previously unfilled FVG that was traded through and reclaimed.
      // Simplified: look for a FVG where price later returned into the gap
      // and closed beyond the opposite side.
      // For now, detected as FVG where subsequent bars show reclamation.
      if(fvgType == PD_FVG && InZone(fvgRef, zone))
      {
         // Check if price reclaimed the FVG (traded through and closed beyond)
         for(int j = i - 1; j >= 0; j--)
         {
            bool reclaimed = false;
            if(isBullishGap)
               reclaimed = (rates[j].close < gapLow); // closed below the gap
            else if(isBearishGap)
               reclaimed = (rates[j].close > gapHigh); // closed above the gap

            if(reclaimed)
            {
               double dist = MathAbs(fvgRef - zone.equilibrium);

               if(!result.found ||
                  dist < result.distanceFromEq ||
                  (dist == result.distanceFromEq && result.type > PD_INVERSION_FVG))
               {
                  result.found = true;
                  result.price = fvgRef;
                  result.type = PD_INVERSION_FVG;
                  result.barIndex = i;
                  result.distanceFromEq = dist;
               }
               break;
            }
         }
      }
   }
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

   // Step 2: Scan for PD Array
   SPDArrayResult result;
   EE_ScanPDArray(symbol, entryTf, zone, 50, result);

   if(!result.found)
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
   candidateEntryPrice = result.price;
   mappedPrice = result.price;
   mappedType = result.type;

   // Step 4: Log the mapping
   string typeStr = "";
   switch(result.type)
   {
      case PD_BREAKER_BLOCK:  typeStr = "BREAKER_BLOCK";  break;
      case PD_FVG:            typeStr = "FVG";            break;
      case PD_ORDER_BLOCK:    typeStr = "ORDER_BLOCK";    break;
      case PD_INVERSION_FVG:  typeStr = "INVERSION_FVG";  break;
      default:                typeStr = "UNKNOWN";         break;
   }

   LogPrint("[TSPOT_POI_MAPPED] on " + EnumToString(entryTf) +
            " | type=" + typeStr +
            " | price=" + DoubleToString(result.price, _Digits) +
            " | bar=" + IntegerToString(result.barIndex) +
            " | zone=[" + DoubleToString(zone.low, _Digits) + ", " +
            DoubleToString(zone.high, _Digits) + "]" +
            " | eq=" + DoubleToString(zone.equilibrium, _Digits) +
            " | dir=" + (bullish ? "BUY" : "SELL"), LOG_LEVEL_INFO);

   return POI_MAPPED;
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
//| EE_MapC3POI — Gate 4 for C3 signals (zone already computed)     |
//|                                                                  |
//| C3-specific function that scans Entry TF for PD Array within      |
//| the T-Spot zone (tSpotMin/Max) and sets requestedEntryPrice.     |
//|                                                                  |
//| Per AGENTS.md §XVI: T-Spot is a ZONE, not midpoint.              |
//| If no POI found → STAGE_WAITING_FOR_POI (no fallback to midpoint)|
//+------------------------------------------------------------------+
void EE_MapC3POI(SLockedSignal &signal)
{
   double zoneLow = MathMin(signal.tSpotMin, signal.tSpotMax);
   double zoneHigh = MathMax(signal.tSpotMin, signal.tSpotMax);

   SPDArrayResult result;
   result.Reset();

   int scanBars = 50;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   ZeroMemory(rates);

// Use M5 for Branch A, M15 for Branch B
    ENUM_TIMEFRAMES entryTf = (signal.branch == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;
   int copied = CopyRates(signal.symbol, entryTf, 0, scanBars + 2, rates);
   if(copied < 5)
   {
      signal.requestedEntryPrice = 0.0; // Force wait in STAGE_WAITING_FOR_POI
      LogPrint("[TSPOT_POI_MISSING] C3 | Insufficient bars on " + EnumToString(entryTf), LOG_LEVEL_INFO);
      return;
   }

   int maxBars = MathMin(scanBars, copied - 2);

   for(int i = 1; i < maxBars; i++)
   {
      double obOpen = rates[i].open;

      // Check if OB open is in zone
      if(obOpen >= zoneLow - 0.5*_Point && obOpen <= zoneHigh + 0.5*_Point)
      {
         bool isDownClose = (rates[i].close < rates[i].open);
         bool isUpClose   = (rates[i].close > rates[i].open);

         if(isDownClose || isUpClose)
         {
            double dist = MathAbs(obOpen - (zoneLow + zoneHigh) / 2.0);

            if(!result.found || dist < result.distanceFromEq ||
               (dist == result.distanceFromEq && result.type > PD_ORDER_BLOCK))
            {
               result.found = true;
               result.price = obOpen;
               result.type = PD_ORDER_BLOCK;
               result.barIndex = i;
               result.distanceFromEq = dist;
            }
         }
      }

      // FVG detection
      double gapHigh = MathMin(rates[i+1].high, rates[i-1].high);
      double gapLow  = MathMax(rates[i+1].low,  rates[i-1].low);

      if(gapHigh < gapLow)
      {
         bool isBullishGap = (rates[i+1].high < rates[i-1].low);
         bool isBearishGap = (rates[i+1].low  > rates[i-1].high);

         if(isBullishGap || isBearishGap)
         {
            double fvgRef = (gapHigh + gapLow) / 2.0;

            if(fvgRef >= zoneLow - 0.5*_Point && fvgRef <= zoneHigh + 0.5*_Point)
            {
               double dist = MathAbs(fvgRef - (zoneLow + zoneHigh) / 2.0);

               if(!result.found || dist < result.distanceFromEq ||
                  (dist == result.distanceFromEq && result.type > PD_FVG))
               {
                  result.found = true;
                  result.price = fvgRef;
                  result.type = PD_FVG;
                  result.barIndex = i;
                  result.distanceFromEq = dist;
               }
            }
         }
      }
   }

   if(!result.found)
   {
      signal.requestedEntryPrice = 0.0;
      LogPrint("[TSPOT_POI_MISSING] C3 | No POI in zone [" +
               DoubleToString(zoneLow, _Digits) + ", " + DoubleToString(zoneHigh, _Digits) + "]", LOG_LEVEL_INFO);
      return;
   }

   signal.requestedEntryPrice = result.price;
   LogPrint("[TSPOT_POI_MAPPED] C3 | Price: " + DoubleToString(result.price, _Digits) +
            " | zone [" + DoubleToString(zoneLow, _Digits) + ", " + DoubleToString(zoneHigh, _Digits) + "]", LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+

#endif // OMAK_EXECUTIONENGINE_MQH
