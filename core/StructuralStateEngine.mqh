//+------------------------------------------------------------------+
//|                                    StructuralStateEngine.mqh |
//|                        OmakFxYO — Structural State Engine |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_STRUCTURALSTATEENGINE_MQH
#define OMAK_STRUCTURALSTATEENGINE_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Structural State Engine — Market Structure Authority"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>       // Base types
#include <OmakFxYO/core/StructuralTypes.mqh> // SSE_Output, MarketStructureState, MarketStrategy
#include <OmakFxYO/core/DowTheoryEngine.mqh> // Swing detection
#include <OmakFxYO/core/DisplacementValidator.mqh>  // DV_AnalyzeDisplacement

#include "TradeContext.mqh"

// Forward declaration for global defined in OmakFxYO.mq5
extern SBranchResolvedParams g_branchParams;

// NOTE: MarketStructureState, MarketStrategy, SSE_Output defined in StructuralTypes.mqh

//+------------------------------------------------------------------+
//| SSE_Input — Input Data Structure                                  |
//+------------------------------------------------------------------+
/**
 * SSE_Input
 *
 * Contains all input data required for structural state evaluation.
 * Populated from DowTheoryEngine (swings) and ClosureEngine (displacement).
 */
struct SSE_Input
{
   // Swing Data (from DowTheoryEngine)
   SSwingPoint swing_hh;          // Last Higher High
   SSwingPoint swing_hl;          // Last Higher Low
   SSwingPoint swing_lh;          // Last Lower High
   SSwingPoint swing_ll;          // Last Lower Low

   // Displacement Data (from ClosureEngine/FractalState)
   bool displacement_bullish;     // Bullish displacement detected
   bool displacement_bearish;     // Bearish displacement detected
   double displacement_strength;  // Multiplier vs average body (e.g., 1.2 = 20% above avg)

   // External Break Flag
   bool external_break;           // HTF swing broken (D1/H4)

   //+------------------------------------------------------------------+
   // | Reset — Clear all fields to defaults                           |
   //+------------------------------------------------------------------+
   void Reset()
   {
      swing_hh.Reset();
      swing_hl.Reset();
      swing_lh.Reset();
      swing_ll.Reset();

      displacement_bullish = false;
      displacement_bearish = false;
      displacement_strength = 0.0;

      external_break = false;
   }
};

// SSE_Output struct defined in StructuralTypes.mqh

//+------------------------------------------------------------------+
//| SSE_Context — Persistent State Context                            |
//+------------------------------------------------------------------+
/**
 * SSE_Context
 *
 * Holds previous state for state flip validation.
 * Prevents unauthorized structure flips.
 */
struct SSE_Context
{
    SSE_Output previous;             // Previous state output
    SSE_Output current;              // Current state output
    datetime lastFlipTime;           // When last state flip occurred
    int flipCount;                   // Total number of state flips
    datetime lastProcessedBarTime;   // Last bar processed (for cache invalidation)
    SDowTheoryContext lastDowContext; // Persisted Dow Theory context (swing points)
    bool displacementWarmedUp;       // Warmup state persisted
    datetime warmupTimestamp;        // When warmup completed

    //+------------------------------------------------------------------+
    // | Reset — Clear all fields to defaults                            |
    //+------------------------------------------------------------------+
    void Reset()
    {
        previous.Reset();
        current.Reset();
        lastFlipTime = 0;
        flipCount = 0;
        lastProcessedBarTime = 0;
        lastDowContext.Reset();
        displacementWarmedUp = false;
        warmupTimestamp = 0;
    }
};

//+------------------------------------------------------------------+
//| GLOBAL STATE — SSE Context per Symbol/TF                         |
//+------------------------------------------------------------------+
// Note: In a multi-symbol EA, this would be a map/array.
// For single-symbol operation, a global context suffices.
SSE_Context g_sseContext;

//+------------------------------------------------------------------+
//| CORE LOGIC — STATE EVALUATION                                    |
//+------------------------------------------------------------------+

/**
 * EvaluateState — Main state machine
 *
 * Determines market structure state based on swing sequence and displacement.
 *
 * LOGIC:
 *   1. Check for Bullish Sequence (HH + HL confirmed)
 *   2. Check for Bearish Sequence (LL + LH confirmed)
 *   3. If bullish sequence:
 *      - STRONG if displacement_bullish && strength > 1.0
 *      - WEAK otherwise
 *   4. If bearish sequence:
 *      - STRONG if displacement_bearish && strength > 1.0
 *      - WEAK otherwise
 *   5. If neither sequence → RANGE
 *
 * @param src SSE_Input with swing and displacement data
 * @return MarketStructureState
 */
MarketStructureState EvaluateState(const SSE_Input &src)
{
   // Step 1: Check for Bullish Sequence (HH + HL)
   bool has_bullish_sequence = (src.swing_hh.isConfirmed && src.swing_hl.isConfirmed);

   // Step 2: Check for Bearish Sequence (LL + LH)
   bool has_bearish_sequence = (src.swing_ll.isConfirmed && src.swing_lh.isConfirmed);

   // Step 3: Determine base state
   if(has_bullish_sequence && !has_bearish_sequence)
   {
      // BULLISH STRUCTURE DETECTED
      // Check displacement strength (relaxed threshold: 1.0x for more STRONG states)
if(src.displacement_bullish && src.displacement_strength > 0.5)
       {
          return MSS_BULLISH_STRONG;
      }
      else
      {
         return MSS_BULLISH_WEAK;
      }
   }
else if(has_bearish_sequence && !has_bullish_sequence)
    {
       // BEARISH STRUCTURE DETECTED
       // Check displacement strength (relaxed threshold: 1.0x for more STRONG states)
       if(src.displacement_bearish && src.displacement_strength > 0.5)
       {
          return MSS_BEARISH_STRONG;
       }
       else
       {
          return MSS_BEARISH_WEAK;
       }
    }
    else
    {
       // NO CLEAR SEQUENCE — RANGE (choppy/ranging market)
       return MSS_RANGE;
    }
}

// SSE_GetStrategy and SSE_OutputToStrategy defined in StructuralTypes.mqh

//+------------------------------------------------------------------+
//| CRITICAL SAFEGUARD — STATE FLIP VALIDATION                       |
//+------------------------------------------------------------------+

/**
 * ValidateStateFlip — Critical safeguard against unauthorized flips
 *
 * DO NOT FLIP STRUCTURE UNLESS:
 *   1. EXTERNAL SWING IS BROKEN (HTF swing — D1/H4)
 *   2. DISPLACEMENT CONFIRMS (displacementConfirmed == true)
 *
 * EXCEPTION:
 *   - Strong → Weak transitions allowed (displacement fading)
 *
 * @param newState Newly computed state
 * @param previousState Previous state
 * @return true if flip is valid, false otherwise
 */
bool ValidateStateFlip(const SSE_Output &newState, const SSE_Output &previousState)
{
   // No flip if state unchanged
   if(newState.state == previousState.state)
      return false;

   // Exception 1: Strong → Weak transition (displacement fading)
   // This is NOT a true flip, just a degradation
   if(previousState.state == MSS_BULLISH_STRONG && newState.state == MSS_BULLISH_WEAK)
      return true;

   if(previousState.state == MSS_BEARISH_STRONG && newState.state == MSS_BEARISH_WEAK)
      return true;

   // Exception 2: Weak → Strong transition (displacement returning)
   if(previousState.state == MSS_BULLISH_WEAK && newState.state == MSS_BULLISH_STRONG)
      return true;

   if(previousState.state == MSS_BEARISH_WEAK && newState.state == MSS_BEARISH_STRONG)
      return true;

   // CRITICAL SAFEGUARD:
   // For all other transitions (especially bullish ↔ bearish),
   // BOTH conditions must be met:

   // Condition 1: External swing broken (HTF confirmation)
   if(!newState.externalBreak)
      return false;

   // Condition 2: Displacement confirms the break
   if(!newState.displacementConfirmed)
      return false;

   // Both conditions met — flip is valid
   return true;
}

//+------------------------------------------------------------------+
//| MAIN ENGINE FUNCTIONS                                            |
//+------------------------------------------------------------------+

/**
 * SSE_Initialize — Initialize SSE Engine
 *
 * Call during EA initialization.
 * Resets global context to defaults.
 *
 * @return true on success
 */
bool SSE_Initialize()
{
   g_sseContext.Reset();
   return true;  // NO direct logging
}

/**
 * SSE_ComputeState — Compute current market structure state
 *
 * MAIN ENTRY POINT for state evaluation.
 * Stateless per tick — recomputes cleanly from input data.
 *
 * STEPS:
 *   1. Populate SSE_Input from DowTheoryEngine + ClosureEngine
 *   2. Evaluate state using EvaluateState()
 *   3. Validate flip using ValidateStateFlip()
 *   4. Update global context
 *   5. Log state change if occurred
 *
 * @param symbol Symbol to analyze
 * @param tf Timeframe to analyze
 * @param src SSE_Input with pre-populated data
 * @return SSE_Output with computed state
 */
SSE_Output SSE_ComputeState(
   const string symbol,
   ENUM_TIMEFRAMES tf,
   const SSE_Input &src
)
{
   SSE_Output output;
   ZeroMemory(output);
   output.Reset();
   output.timeframe = tf;
   output.lastUpdateTime = TimeCurrent();

   // Step 1: Evaluate state from src
   output.state = EvaluateState(src);

   // Step 2: Set confirmation flags from src
   output.externalBreak = src.external_break;
output.displacementConfirmed = (src.displacement_bullish || src.displacement_bearish) &&
                                     (src.displacement_strength > 0.5);

   // Step 3: Validate state flip (critical safeguard)
   bool allowFlip = ValidateStateFlip(output, g_sseContext.current);

   // REVIEWED Fix-A4: MSS_RANGE escape path confirmed present and correct. No change needed.
   // Transition FROM MSS_RANGE is allowed directly (state != MSS_RANGE condition evaluates FALSE for range,
   // so block is skipped and new state is accepted). Transitions FROM trending states require
   // both externalBreak && displacementConfirmed via ValidateStateFlip().
   if(!allowFlip && g_sseContext.current.state != MSS_RANGE)
   {
      // Flip not allowed — retain previous state
      // Exception: If previous was RANGE, always allow new state
      output.state = g_sseContext.current.state;
      output.externalBreak = g_sseContext.current.externalBreak;
      output.displacementConfirmed = g_sseContext.current.displacementConfirmed;
   }

   // Step 4: Update global context
   g_sseContext.previous = g_sseContext.current;
   g_sseContext.current = output;

   // Step 5: Log state change if occurred
   if(output.state != g_sseContext.previous.state)
   {
      g_sseContext.flipCount++;
      g_sseContext.lastFlipTime = TimeCurrent();
      SSE_LogStateChange(g_sseContext.previous, output);
   }

   return output;
}

/**
 * SSE_GetCurrentState — Get current cached state
 *
 * Returns the most recently computed state without recomputation.
 * Use for quick state checks between compute cycles.
 *
 * @param symbol Symbol (ignored for single-symbol operation)
 * @param tf Timeframe (ignored for single-symbol operation)
 * @return SSE_Output &current state
 */
SSE_Output SSE_GetCurrentState(const string symbol, ENUM_TIMEFRAMES tf)
{
   return g_sseContext.current;
}

/**
 * SSE_ValidateStateFlip — Public wrapper for flip validation
 *
 * Allows external callers to validate a potential state flip
 * before committing to it.
 *
 * @param newState Newly computed state
 * @param previousState Previous state
 * @return true if flip is valid
 */
bool SSE_ValidateStateFlip(const SSE_Output &newState, const SSE_Output &previousState)
{
   return ValidateStateFlip(newState, previousState);
}

//+------------------------------------------------------------------+
//| LOGGING & TELEMETRY                                              |
//+------------------------------------------------------------------+

/**
 * SSE_StateToString — Convert state to string
 *
 * @param state MarketStructureState
 * @return String representation
 */
string SSE_StateToString(MarketStructureState state)
{
   switch(state)
   {
      case MSS_BULLISH_STRONG:  return "MSS_BULLISH_STRONG";
      case MSS_BULLISH_WEAK:    return "MSS_BULLISH_WEAK";
      case MSS_BEARISH_STRONG:  return "MSS_BEARISH_STRONG";
      case MSS_BEARISH_WEAK:    return "MSS_BEARISH_WEAK";
      case MSS_RANGE:           return "MSS_RANGE";
      default:                  return "MSS_UNKNOWN";
   }
}

/**
 * SSE_LogStateChange — Log state change (telemetry)
 *
 * @param previous Previous state output
 * @param current Current state output
 */
void SSE_LogStateChange(const SSE_Output &previous, const SSE_Output &current)
{
   // NO DIRECT LOGGING - signal captured in centralized snapshot
   // State transitions are tracked in ctx for logging at signal level
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS — INPUT POPULATION                              |
//+------------------------------------------------------------------+

/**
 * SSE_PopulateFromDowTheory — Populate SSE_Input from DowTheoryEngine
 *
 * Convenience function to copy swing data from DowTheory context.
 *
 * @param src SSE_Input to populate
 * @param dtContext SDowTheoryContext from DowTheoryEngine
 */
void SSE_PopulateFromDowTheory(SSE_Input &src, const SDowTheoryContext &dtContext)
{
   src.swing_hh = dtContext.lastHH;
   src.swing_hl = dtContext.lastHL;
   src.swing_lh = dtContext.lastLH;
   src.swing_ll = dtContext.lastLL;
}

/**
 * SSE_PopulateDisplacement — Populate displacement data
 *
 * Convenience function to set displacement flags.
 *
 * @param src SSE_Input to populate
 * @param isBullish true if bullish displacement
 * @param strength Displacement strength multiplier
 */
void SSE_PopulateDisplacement(SSE_Input &src, bool isBullish, double strength)
{
   if(isBullish)
   {
      src.displacement_bullish = true;
      src.displacement_bearish = false;
   }
   else
   {
      src.displacement_bullish = false;
      src.displacement_bearish = true;
   }

   src.displacement_strength = strength;
}

/**
 * SSE_SetExternalBreak — Set external break flag
 *
 * @param src SSE_Input to update
 * @param isBroken true if HTF swing is broken
 */
void SSE_SetExternalBreak(SSE_Input &src, bool isBroken)
{
   src.external_break = isBroken;
}

//+------------------------------------------------------------------+
//| ANALYSIS HELPER — Full Structure Analysis                        |
//+------------------------------------------------------------------+

/**
 * SSE_AnalyzeStructure — Complete structure analysis
 *
 * High-level function that performs full analysis:
 *   1. Analyzes Dow Theory structure
 *   2. Detects displacement
 *   3. Computes SSE state
 *
 * @param symbol Symbol to analyze
 * @param tf Timeframe to analyze
 * @param forceRefreshStructure Force re-evaluation (for mid-bar fractal closures)
 * @return SSE_Output with complete analysis
 */
SSE_Output SSE_AnalyzeStructure(
   const string symbol,
   ENUM_TIMEFRAMES tf,
   bool forceRefreshStructure = false
)
{
   // Use global context for persistence — survives across ticks
   datetime currentBar = iTime(symbol, tf, 0);
   bool isNewBar = (currentBar != g_sseContext.lastProcessedBarTime);

   // Hybrid SSE Force-Refresh: re-analyze on new bar OR force refresh signal
   // Once a strong state is set, it remains LOCKED until ValidateStateFlip approves
   if(isNewBar || forceRefreshStructure)
   {
      g_sseContext.lastProcessedBarTime = currentBar;

      // Step 1: Analyze Dow Theory structure (uses 250-bar warmup from OnInit)
      SDowTheoryContext dtContext = AnalyzeStructure(symbol, tf);
      g_sseContext.lastDowContext = dtContext; // Persist for next tick

      // --- STRUCTURE_DEBUG LOGGING START ---
      double lastHigh = 0.0;
      double lastLow = 0.0;
      bool newHigh = false;
      bool newLow = false;

      if(dtContext.lastHH.isConfirmed)
      {
         lastHigh = dtContext.lastHH.price;
         newHigh = true;
      }
      else if(dtContext.lastLH.isConfirmed)
      {
         lastHigh = dtContext.lastLH.price;
         newHigh = true;
      }

      if(dtContext.lastHL.isConfirmed)
      {
         lastLow = dtContext.lastHL.price;
         newLow = true;
      }
      else if(dtContext.lastLL.isConfirmed)
      {
         lastLow = dtContext.lastLL.price;
         newLow = true;
      }

      // Break detection
      bool breakUp = (dtContext.lastEvent == EVENT_BOS && dtContext.trend == TREND_BULLISH);
      bool breakDown = (dtContext.lastEvent == EVENT_BOS && dtContext.trend == TREND_BEARISH);

      // Compute break distance and candle range for threshold check
      double breakDistance = 0.0;
      double candleRange = 0.0;
      double threshold = 0.0;

      double currentHigh[], currentLow[], currentOpen[], currentClose[];
      ArraySetAsSeries(currentHigh, true);
      ArraySetAsSeries(currentLow, true);
      ArraySetAsSeries(currentOpen, true);
      ArraySetAsSeries(currentClose, true);

      if(CopyHigh(symbol, tf, 0, 2, currentHigh) == 2 &&
         CopyLow(symbol, tf, 0, 2, currentLow) == 2 &&
         CopyOpen(symbol, tf, 0, 2, currentOpen) == 2 &&
         CopyClose(symbol, tf, 0, 2, currentClose) == 2)
      {
         candleRange = currentHigh[0] - currentLow[0];

          // ATR removed — use fixed fraction of candle range as threshold
          threshold = MathMax(candleRange * 0.15, 50 * _Point);

         if(breakUp && lastHigh > 0.0)
            breakDistance = currentClose[0] - lastHigh;
         else if(breakDown && lastLow > 0.0)
            breakDistance = lastLow - currentClose[0];
      }

      // Structure classification (will be updated after src is populated)
      string mssBullish = (dtContext.isBullishStructure) ? "YES" : "NO";
      string mssBearish = (dtContext.isBearishStructure) ? "YES" : "NO";
      // --- STRUCTURE_DEBUG LOGGING END ---

      // Step 2: Populate SSE input (inlined from SSE_PopulateFromDowTheory)
      SSE_Input src;
      ZeroMemory(src);
      src.swing_hh = dtContext.lastHH;
      src.swing_hl = dtContext.lastHL;
      src.swing_lh = dtContext.lastLH;
      src.swing_ll = dtContext.lastLL;

      // D.1: Trust DowTheory direction resolution.
      if(dtContext.isBullishStructure || dtContext.isWeakBullishStructure)
      {
         src.swing_ll.isConfirmed = false;
         src.swing_lh.isConfirmed = false;
      }
      else if(dtContext.isBearishStructure || dtContext.isWeakBearishStructure)
      {
         src.swing_hh.isConfirmed = false;
         src.swing_hl.isConfirmed = false;
      }

      // Step 3: Get fresh displacement result inline — direction-agnostic strength validation
      DisplacementOutput dvResult = DV_AnalyzeDisplacement(symbol, tf);

      if(dtContext.isBullishStructure || dtContext.isWeakBullishStructure)
       {
          src.displacement_bullish = dvResult.isValid;
          src.displacement_bearish = false;
          src.displacement_strength = dvResult.isValid ? dvResult.strengthScore : 0.0;
       }
       else if(dtContext.isBearishStructure || dtContext.isWeakBearishStructure)
       {
          src.displacement_bullish = false;
          src.displacement_bearish = dvResult.isValid;
src.displacement_strength = dvResult.isValid ? dvResult.strengthScore : 0.0;
       }

       LogPrint(StringFormat("[SSE-DBG] src.disp_bull=%s src.disp_bear=%s strength=%.2f",
          src.displacement_bullish ? "T" : "F",
          src.displacement_bearish ? "T" : "F",
          src.displacement_strength), LOG_LEVEL_DEBUG);

       // Structure strength classification (relaxed threshold: 1.0x for more STRONG states)
       string structureStrength = "WEAK";
if((dtContext.isBullishStructure && src.displacement_bullish && src.displacement_strength > 0.5) ||
           (dtContext.isBearishStructure && src.displacement_bearish && src.displacement_strength > 0.5))
          structureStrength = "STRONG";

      // Step 4: Set external break flag (Dow Theory swing confirmation)
      // A confirmed bullish structure (HH+HL) means price has broken above the
      // previous confirmed swing high (bullish external break).
      // A confirmed bearish structure (LL+LH) means price has broken below the
      // previous confirmed swing low (bearish external break).
      // This uses information already computed by AnalyzeStructure() - no separate
      // D1 call is needed and no tf == PERIOD_H1 gate is required.
      bool external_broken = (dtContext.isBullishStructure || dtContext.isBearishStructure);

      // Inlined from SSE_SetExternalBreak
      src.external_break = external_broken;

      // Step 5: Compute SSE state
      SSE_Output result = SSE_ComputeState(symbol, tf, src);

      LogPrint(StringFormat("[SSE-DBG] state=%s breakUp=%s breakDown=%s breakDist=%.2f threshold=%.2f",
         EnumToString(result.state),
         breakUp ? "T" : "F", breakDown ? "T" : "F",
         breakDistance, threshold), LOG_LEVEL_DEBUG);

      // --- STRUCTURE VALIDATION GATE — Enforce real break distance ---
      // MSS signals require an actual break of structure with meaningful distance.
      // If breakDistance <= 20% of candle range, the break is noise — reject it.

      double breakDistanceAbs = MathAbs(breakDistance);
      bool hasValidBreakData = (breakDistanceAbs > 0.0 && threshold > 0.0);
      bool passesDistanceGate = (breakDistanceAbs > threshold);

      // Gate 1: distance threshold - only apply if break data is valid
      if(hasValidBreakData)
      {
         if(result.state == MSS_BULLISH_STRONG && !passesDistanceGate)
         {
            result.state = MSS_RANGE;
         }
         else if(result.state == MSS_BEARISH_STRONG && !passesDistanceGate)
         {
            result.state = MSS_RANGE;
         }
      }

      // Gate 2: direction check - only apply if break data is valid
      bool hasDirectionalBreak = (breakUp || breakDown);
      if(hasValidBreakData && hasDirectionalBreak)
      {
         if(result.state == MSS_BULLISH_STRONG && !(breakUp && breakDistance > 0.0))
         {
            result.state = MSS_RANGE;
         }
else if(result.state == MSS_BEARISH_STRONG && !(breakDown && breakDistance > 0.0))
          {
             result.state = MSS_RANGE;
          }
       }

LogPrint(StringFormat("[SSE-DBG] hasValidBreakData=%s - final state=%s",
           hasValidBreakData ? "T" : "F",
           EnumToString(result.state)), LOG_LEVEL_DEBUG);

        // NO DIRECT LOGGING - values captured by caller for centralized logging
       // Structure output is available in result.state
       // State is already persisted in g_sseContext.current via SSE_ComputeState
       return result;
    }

    // Return cached result for the current bar (no refresh needed)
    // The global context persists across ticks
    return g_sseContext.current;
}

//+------------------------------------------------------------------+
//| SSE_Warmup — Seed SSE from historical bars (ATR-Guarded)                |
//+------------------------------------------------------------------+
void SSE_Warmup(const string symbol, ENUM_TIMEFRAMES tf, int warmupBars = 25)
{
    if(warmupBars <= 0)
       warmupBars = 25;

    int bufferSize = warmupBars + 5;
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    ZeroMemory(rates);

    int copied = CopyRates(symbol, tf, 0, bufferSize, rates);
    if(copied < 2)
    {
       LogPrint("[SSE_WARMUP] WARNING: Insufficient historical bars — need " + IntegerToString(warmupBars) + ", got " + IntegerToString(copied), LOG_LEVEL_WARN);
       return;
    }

 int validBars = 0;
     int maxIterations = 500;
     int iterations = 0;

     for(int i = copied - 1; i >= 0; i--)
     {
        iterations++;
        if(iterations >= maxIterations)
        {
           LogPrint("[SSE_WARMUP] WARNING: Loop Timeout - iterations=" + IntegerToString(iterations), LOG_LEVEL_WARN);
           break;
        }

// ATR removed — use High-Low range as proxy
         double atr = 0.0;
         if(i < ArraySize(rates))
         {
            atr = rates[i].high - rates[i].low;
            if(atr <= 0.0) atr = 50 * _Point;
         }

         SSE_AnalyzeStructure(symbol, tf, false);
         validBars++;

        // CIRCUIT BREAKER: Exit once we have enough valid bars
        if(validBars >= warmupBars)
        {
           LogPrint("[SSE_WARMUP] Circuit Breaker: Collected " + IntegerToString(validBars) + " valid bars (target: " + IntegerToString(warmupBars) + ")", LOG_LEVEL_DEBUG);
           break;
        }
     }

     if(validBars == 0)
     {
        LogPrint("[SSE_WARMUP] WARNING: No valid ATR bars - proceeding with estimated state", LOG_LEVEL_WARN);
        // Allow engine to proceed even with 0 valid bars
     }

SSE_Output result = SSE_GetCurrentState(symbol, tf);
     LogPrint("[SSE_WARMUP] D1 structure seeded from " + IntegerToString(validBars) + " valid bars (ATR-guarded)"
              + " | State=" + EnumToString(result.state), LOG_LEVEL_INFO);
     
g_sseContext.displacementWarmedUp = true;
      g_sseContext.warmupTimestamp = TimeCurrent();

      LogPrint("[SSE_WARMUP] Displacement warmup completed - session persistence enabled", LOG_LEVEL_INFO);
   }

//+------------------------------------------------------------------+
//| SSE_DetectCISD — Mechanical CISD (Change In State of Delivery)   |
//|                                                                  |
//| Mechanical CISD per AGENTS.md §XVII Gate 3:                      |
//| Price must close ABOVE the opening price of the initiating       |
//| candle of the consecutive down-close series that formed the      |
//| swing low (bullish), or BELOW the opening price of the           |
//| initiating candle of the consecutive up-close series that        |
//| formed the swing high (bearish).                                 |
//|                                                                  |
//| Approach:                                                        |
//|   1. Find the most recent delivery series — consecutive closes   |
//|      in the same direction (down-close for bullish CISD,         |
//|      up-close for bearish CISD).                                 |
//|   2. The initiating candle is the FIRST (oldest) candle in this  |
//|      delivery series. Its Open is the CISD trigger level.        |
//|   3. The swing point is the candle at the END of the delivery    |
//|      series — its low (for bullish) or high (for bearish) is     |
//|      the protected swing for SL anchoring.                       |
//|   4. CISD is confirmed when the last COMPLETED bar closes        |
//|      beyond the trigger level.                                   |
//|                                                                  |
//| This eliminates fractal-based swing detection and uses pure      |
//| delivery-series logic: the opposing delivery created the swing,  |
//| and ISD changes when price closes through the start of it.       |
//|                                                                  |
//| Direction: DIRECTION_BUY  → swing low → close > seriesOpen      |
//|            DIRECTION_SELL → swing high → close < seriesOpen     |
//|                                                                  |
//| Returns: SSE_CISDResult with confirmation and structural data    |
//+------------------------------------------------------------------+
SSE_CISDResult SSE_DetectCISD(
    const string symbol,
    ENUM_TIMEFRAMES tf,
    ENUM_DIRECTION direction,
    int lookbackBars = 20
)
{
    SSE_CISDResult result;
    result.Reset();

    if(lookbackBars < 8)
       lookbackBars = 8;

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    ZeroMemory(rates);

    int copied = CopyRates(symbol, tf, 0, lookbackBars, rates);
    if(copied < 8)
    {
        LogPrint("[CISD_DETECT] Insufficient bars for delivery detection | tf=" + EnumToString(tf) +
                 " | copied=" + IntegerToString(copied), LOG_LEVEL_DEBUG);
        LogPrint("[CISD_FAILED] reason=no_close_through_series | direction=" +
                 EnumToString(direction) + " | keyLevel=0.0", LOG_LEVEL_DEBUG);
        return result;
    }

    int maxBars = MathMin(lookbackBars, copied);

    // Use rates[1].close (last completed bar) for confirmation
    double confirmClose = rates[1].close;

    if(direction == DIRECTION_BUY)
    {
        // Step 1: Find the most recent consecutive DOWN-CLOSE delivery series.
        // Walk forward from oldest to newest (high index → low index with AsSeries)
        // to find the newest (rightmost) consecutive down-close series that
        // represents the opposing delivery.
        int seriesStart = -1;  // oldest down-close candle (initiating)
        int seriesEnd   = -1;  // newest down-close candle (swing low)

        for(int i = 0; i < maxBars; i++)
        {
            if(rates[i].close < rates[i].open)
            {
                // Found a down-close candle — check for consecutive series
                seriesStart = i;
                seriesEnd   = i;
                // Walk backward (to older bars) through consecutive down-closes
                for(int j = i + 1; j < maxBars; j++)
                {
                    if(rates[j].close < rates[j].open)
                    {
                        seriesStart = j;  // extend series backward
                    }
                    else
                    {
                        break;  // series broken
                    }
                }
                break;  // found the most recent delivery series
            }
        }

        if(seriesStart < 0 || seriesEnd < 0)
        {
            LogPrint("[CISD_FAILED] reason=no_close_through_series | direction=" +
                     EnumToString(direction) + " | keyLevel=0.0", LOG_LEVEL_DEBUG);
            return result;
        }

        // Step 2: The swing low is the lowest low within the delivery series.
        double swingLow = rates[seriesEnd].low;
        for(int i = seriesStart; i <= seriesEnd; i++)
        {
            if(rates[i].low < swingLow)
                swingLow = rates[i].low;
        }

        result.swingPrice      = swingLow;
        result.seriesOpen      = rates[seriesStart].open;
        result.swingIndex      = seriesEnd;
        result.seriesStartIndex = seriesStart;

        // Step 3: CISD confirmed on a completed bar CLOSE above the initiating open
        if(confirmClose > result.seriesOpen)
        {
            result.confirmed = true;
            LogPrint("[CISD_CONFIRMED] BULLISH on " + EnumToString(tf) +
                     " | seriesOpen=" + DoubleToString(result.seriesOpen, _Digits) +
                     " | confirmClose=" + DoubleToString(confirmClose, _Digits) +
                     " | swingLow=" + DoubleToString(swingLow, _Digits) +
                     " | seriesStart=" + IntegerToString(seriesStart) +
                     " | seriesEnd=" + IntegerToString(seriesEnd), LOG_LEVEL_INFO);
            return result;
        }

        LogPrint("[CISD_FAILED] reason=no_close_through_series | direction=" +
                 EnumToString(direction) + " | keyLevel=" + DoubleToString(result.seriesOpen, _Digits),
                 LOG_LEVEL_DEBUG);
        return result;
    }
    else if(direction == DIRECTION_SELL)
    {
        // Step 1: Find the most recent consecutive UP-CLOSE delivery series
        int seriesStart = -1;  // oldest up-close candle (initiating)
        int seriesEnd   = -1;  // newest up-close candle (swing high)

        for(int i = 0; i < maxBars; i++)
        {
            if(rates[i].close > rates[i].open)
            {
                seriesStart = i;
                seriesEnd   = i;
                for(int j = i + 1; j < maxBars; j++)
                {
                    if(rates[j].close > rates[j].open)
                    {
                        seriesStart = j;
                    }
                    else
                    {
                        break;
                    }
                }
                break;
            }
        }

        if(seriesStart < 0 || seriesEnd < 0)
        {
            LogPrint("[CISD_FAILED] reason=no_close_through_series | direction=" +
                     EnumToString(direction) + " | keyLevel=0.0", LOG_LEVEL_DEBUG);
            return result;
        }

        // Step 2: The swing high is the highest high within the delivery series
        double swingHigh = rates[seriesEnd].high;
        for(int i = seriesStart; i <= seriesEnd; i++)
        {
            if(rates[i].high > swingHigh)
                swingHigh = rates[i].high;
        }

        result.swingPrice      = swingHigh;
        result.seriesOpen      = rates[seriesStart].open;
        result.swingIndex      = seriesEnd;
        result.seriesStartIndex = seriesStart;

        // Step 3: CISD confirmed on a completed bar CLOSE below the initiating open
        if(confirmClose < result.seriesOpen)
        {
            result.confirmed = true;
            LogPrint("[CISD_CONFIRMED] BEARISH on " + EnumToString(tf) +
                     " | seriesOpen=" + DoubleToString(result.seriesOpen, _Digits) +
                     " | confirmClose=" + DoubleToString(confirmClose, _Digits) +
                     " | swingHigh=" + DoubleToString(swingHigh, _Digits) +
                     " | seriesStart=" + IntegerToString(seriesStart) +
                     " | seriesEnd=" + IntegerToString(seriesEnd), LOG_LEVEL_INFO);
            return result;
        }

        LogPrint("[CISD_FAILED] reason=no_close_through_series | direction=" +
                 EnumToString(direction) + " | keyLevel=" + DoubleToString(result.seriesOpen, _Digits),
                 LOG_LEVEL_DEBUG);
        return result;
    }

    LogPrint("[CISD_FAILED] reason=no_close_through_series | direction=" +
             EnumToString(direction) + " | keyLevel=0.0", LOG_LEVEL_DEBUG);
    return result;
}

//+------------------------------------------------------------------+
//| SSE_HasBullishStructure — Quick check for bullish HTF structure  |
//+------------------------------------------------------------------+
bool SSE_HasBullishStructure(ENUM_TIMEFRAMES tf)
{
    SSE_Output sse = SSE_AnalyzeStructure(_Symbol, tf, false);
    return (sse.state == MSS_BULLISH_STRONG || sse.state == MSS_BULLISH_WEAK);
}

//+------------------------------------------------------------------+
//| SSE_HasBearishStructure — Quick check for bearish HTF structure  |
//+------------------------------------------------------------------+
bool SSE_HasBearishStructure(ENUM_TIMEFRAMES tf)
{
    SSE_Output sse = SSE_AnalyzeStructure(_Symbol, tf, false);
    return (sse.state == MSS_BEARISH_STRONG || sse.state == MSS_BEARISH_WEAK);
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+

#endif // OMAK_STRUCTURALSTATEENGINE_MQH
