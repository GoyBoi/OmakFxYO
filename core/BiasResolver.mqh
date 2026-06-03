//+------------------------------------------------------------------+
//|                                          BiasResolver.mqh |
//|                          OmakFxYO — Bias Resolver |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_BIASRESOLVER_MQH
#define OMAK_BIASRESOLVER_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Bias Resolver — SSE-Based Bias Derivation"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>           // Base types
#include <OmakFxYO/core/StructuralStateEngine.mqh>    // P09-A: SSE_Output
#include <OmakFxYO/core/LiquidityTierEngine.mqh>      // P09-B: LiquidityOutput
#include <OmakFxYO/core/DisplacementValidator.mqh>    // P09-C: DisplacementOutput
#include <OmakFxYO/core/FractalState.mqh>             // ENUM_FRACTAL_STATE

//+------------------------------------------------------------------+
//| BiasType — Bias Direction Enum                                   |
//+------------------------------------------------------------------+
/**
 * BiasType
 *
 * Directional bias derived SOLELY from Structural State Engine.
 * NO candle dependency — pure structure-based bias.
 *
 * VALUES:
 *   BIAS_BULLISH  — SSE state is MSS_BULLISH_*
 *   BIAS_BEARISH  — SSE state is MSS_BEARISH_*
 *   BIAS_NEUTRAL  — SSE state is MSS_RANGE (true neutral/range)
 *   BIAS_PENDING — SSE state is MSS_UNINITIALIZED (temporary, recovery possible)
 */
enum BiasType
{
   BIAS_BULLISH,     // SSE: MSS_BULLISH_*
   BIAS_BEARISH,     // SSE: MSS_BEARISH_*
   BIAS_NEUTRAL,     // SSE: MSS_RANGE (confirmed range)
   BIAS_PENDING     // SSE: MSS_UNINITIALIZED (temporary, waiting for structure)
};

//+------------------------------------------------------------------+
//| BiasOutput — Bias Resolution Result                              |
//+------------------------------------------------------------------+
/**
 * BiasOutput
 *
 * Contains resolved bias direction and strength.
 * Derived from SSE state with liquidity override applied.
 */
struct BiasOutput
{
     BiasType bias;              // Resolved bias direction
     bool isStrong;              // Bias strength flag (from SSE displacement)
     double strengthScore;       // 0.0-1.0 strength (derived from SSE only)
     datetime timestamp;         // When resolution occurred
     string rationale;          // Human-readable explanation
     BiasType liquidityOverride; // Override from liquidity tier (none if neutral)
     string source;            // Bias source: D1_CLOSURE, STRUCTURE_TF, SSE

     //+------------------------------------------------------------------+
     // | Reset — Clear all fields to defaults                           |
     //+------------------------------------------------------------------+
     void Reset()
     {
         bias = BIAS_NEUTRAL;
         isStrong = false;
         strengthScore = 0.0;
         timestamp = 0;
         rationale = "";
         liquidityOverride = BIAS_NEUTRAL;
         source = "";
     }
};

//+------------------------------------------------------------------+
//| BiasContext — Persistent Resolver Context                        |
//+------------------------------------------------------------------+
/**
 * BiasContext
 *
 * Holds previous bias for transition tracking.
 */
struct BiasContext
{
   BiasOutput previous;          // Previous bias output
   BiasOutput current;           // Current bias output
   datetime lastChangeTime;      // When last bias change occurred
   int changeCount;              // Total number of bias changes

   //+------------------------------------------------------------------+
   // | Constructor — Initialize to defaults                           |
   //+------------------------------------------------------------------+
   void BiasContext()
   {
      Reset();
   }

   //+------------------------------------------------------------------+
   // | Reset — Clear all fields to defaults                           |
   //+------------------------------------------------------------------+
   void Reset()
   {
      previous.Reset();
      current.Reset();
      lastChangeTime = 0;
      changeCount = 0;
   }
};

//+------------------------------------------------------------------+
//| GLOBAL STATE — Bias Resolver Context                              |
//+------------------------------------------------------------------+
BiasContext g_brContext;

//+------------------------------------------------------------------+
//| CORE LOGIC — BIAS RESOLUTION                                     |
//+------------------------------------------------------------------+

/**
 * ResolveBiasFromSSE — Resolve bias from SSE state
 *
 * BIAS LOGIC:
 *   - MSS_UNINITIALIZED → BIAS_PENDING (temporary, recovery expected)
 *   - MSS_BULLISH_STRONG → BIAS_BULLISH (isStrong = true)
 *   - MSS_BULLISH_WEAK   → BIAS_BULLISH (isStrong = false)
 *   - MSS_BEARISH_STRONG → BIAS_BEARISH (isStrong = true)
 *   - MSS_BEARISH_WEAK   → BIAS_BEARISH (isStrong = false)
 *   - MSS_RANGE          → BIAS_NEUTRAL  (confirmed range)
 *
 * @param sseState SSE market structure state
 * @return BiasType resolved bias
 */
BiasType ResolveBiasFromSSE(MarketStructureState sseState)
{
    // Temporary uninitialized state — recovery path is open
    // SSE will re-analyze on next tick/bar
    if(sseState == MSS_UNINITIALIZED)
    {
        LogPrint("[BIAS] PENDING — SSE uninitialized, awaiting structure", LOG_LEVEL_INFO);
        return BIAS_PENDING;
    }

    // Bullish structure → BIAS_BULLISH
    if(sseState == MSS_BULLISH_STRONG || sseState == MSS_BULLISH_WEAK)
    {
        return BIAS_BULLISH;
    }

// Bearish structure → BIAS_BEARISH
    if(sseState == MSS_BEARISH_STRONG || sseState == MSS_BEARISH_WEAK)
    {
        return BIAS_BEARISH;
    }

    // Default: neutral for unhandled states
    return BIAS_NEUTRAL;
}

/**
 * DailyClosureBias — Resolve bias from mechanical daily candle rule
 *
 * TTrades mechanical rule: Daily bias derived from the relationship
 * of yesterday's close to the prior day's high/low, with sweep-and-close-back
 * reversal detection. Both deep research reports confirm this rule.
 *
 * Reads CLOSED bars only (bar index 1+), NEVER reads bar 0.
 *
 * MECHANICAL RULE (per research reports):
 *   pdc > p2h                          → BULLISH (close above prior range)
 *   pdc < p2l                          → BEARISH (close below prior range)
 *   pdh > p2h && pdc < p2h             → BEARISH (swept high, closed inside)
 *   pdl < p2l && pdc > p2l             → BULLISH (swept low, closed inside)
 *   otherwise                          → NEUTRAL
 *
 *   where: pdc = D1[1].close, pdh = D1[1].high, pdl = D1[1].low
 *          p2h = D1[2].high, p2l = D1[2].low
 *
 * Cache resets at the start of each new D1 bar.
 *
 * @param symbol Symbol to analyze
 * @return BiasType resolved bias
 */
BiasType DailyClosureBias(const string symbol)
{
    static datetime s_lastBiasCalcTime = 0;
    static BiasType s_cachedBias = BIAS_NEUTRAL;

    datetime currentDayStart = iTime(symbol, PERIOD_D1, 0);
    if(currentDayStart == s_lastBiasCalcTime && s_lastBiasCalcTime > 0)
    {
        return s_cachedBias;
    }

    s_lastBiasCalcTime = currentDayStart;

    double pdc = iClose(symbol, PERIOD_D1, 1);
    double pdh = iHigh(symbol, PERIOD_D1, 1);
    double pdl = iLow(symbol, PERIOD_D1, 1);
    double p2h = iHigh(symbol, PERIOD_D1, 2);
    double p2l = iLow(symbol, PERIOD_D1, 2);

    if(pdc == 0.0 || pdh == 0.0 || pdl == 0.0 || p2h == 0.0 || p2l == 0.0)
    {
        LogPrint("[D1_BIAS] PENDING | Invalid price data", LOG_LEVEL_INFO);
        s_cachedBias = BIAS_PENDING;
        return BIAS_PENDING;
    }

         if(pdc > p2h)
    {
        s_cachedBias = BIAS_BULLISH;
        LogPrint("[D1_BIAS] BULLISH | pdc=" + DoubleToString(pdc, _Digits) +
                 " > p2h=" + DoubleToString(p2h, _Digits) + " (close above prior range)", LOG_LEVEL_INFO);
    }
    else if(pdc < p2l)
    {
        s_cachedBias = BIAS_BEARISH;
        LogPrint("[D1_BIAS] BEARISH | pdc=" + DoubleToString(pdc, _Digits) +
                 " < p2l=" + DoubleToString(p2l, _Digits) + " (close below prior range)", LOG_LEVEL_INFO);
    }
    else if(pdh > p2h && pdc < p2h)
    {
        s_cachedBias = BIAS_BEARISH;
        LogPrint("[D1_BIAS] BEARISH | pdh=" + DoubleToString(pdh, _Digits) +
                 " > p2h=" + DoubleToString(p2h, _Digits) +
                 " && pdc=" + DoubleToString(pdc, _Digits) + " < p2h (swept high, closed inside)", LOG_LEVEL_INFO);
    }
    else if(pdl < p2l && pdc > p2l)
    {
        s_cachedBias = BIAS_BULLISH;
        LogPrint("[D1_BIAS] BULLISH | pdl=" + DoubleToString(pdl, _Digits) +
                 " < p2l=" + DoubleToString(p2l, _Digits) +
                 " && pdc=" + DoubleToString(pdc, _Digits) + " > p2l (swept low, closed inside)", LOG_LEVEL_INFO);
    }
    else
    {
        s_cachedBias = BIAS_NEUTRAL;
        LogPrint("[D1_BIAS] NEUTRAL | pdc=" + DoubleToString(pdc, _Digits) +
                 " no mechanical rule triggered", LOG_LEVEL_INFO);
    }

    return s_cachedBias;
}

/**
 * IsBiasAligned — Check if signal direction aligns with current market bias
 *
 * @param signalIsBullish True for bullish signal, false for bearish
 * @param bias Current BiasOutput from branch context (const - read only)
 * @return true if aligned (or bias is NEUTRAL/NONE), false if contra-trend
 */
bool IsBiasAligned(bool signalIsBullish, const BiasOutput &bias)
{
    if(bias.bias == BIAS_NEUTRAL || bias.bias == BIAS_PENDING)
    {
        LogPrint("[BIAS_ALIGNED] NEUTRAL/PENDING bias — REJECTING signal (no edge)", LOG_LEVEL_WARN);
        LogPrint("[BIAS_MISALIGNED] bias=NEUTRAL | signal has no directional edge", LOG_LEVEL_DEBUG);
        return false;
    }

    if(bias.bias == BIAS_BULLISH)
    {
        if(!signalIsBullish)
        {
            LogPrint("[BIAS_MISALIGNED] REJECT | signal=BEAR but bias=BULLISH", LOG_LEVEL_WARN);
            return false;
        }
        LogPrint("[BIAS_ALIGNED] OK | signal=BULL and bias=BULLISH", LOG_LEVEL_DEBUG);
        return true;
    }

    if(bias.bias == BIAS_BEARISH)
    {
        if(signalIsBullish)
        {
            LogPrint("[BIAS_MISALIGNED] REJECT | signal=BULL but bias=BEARISH", LOG_LEVEL_WARN);
            return false;
        }
        LogPrint("[BIAS_ALIGNED] OK | signal=BEAR and bias=BEARISH", LOG_LEVEL_DEBUG);
        return true;
    }

return true;
}

/**
 * IsStructureTFAligned — Check if signal direction aligns with structure TF (H1/H4) state
 *
 * Used for C2 Closure signals which skip D1 bias check but still need structure TF alignment.
 *
 * @param signalIsBullish True for bullish signal, false for bearish
 * @param structureTf Structure timeframe (H1 for intraday, H4 for swing)
 * @return true if aligned (or neutral), false if contra-structure
 */
bool IsStructureTFAligned(bool signalIsBullish, ENUM_TIMEFRAMES structureTf)
{
    SSE_Output sse = SSE_AnalyzeStructure(_Symbol, structureTf);
    
    // Allow signals when structure is uninitialized or ranging (no clear direction)
    if(sse.state == MSS_UNINITIALIZED || sse.state == MSS_RANGE)
    {
        LogPrint("[STRUCT_ALIGN] NEUTRAL/RANGE structure — allowing signal", LOG_LEVEL_DEBUG);
        return true;
    }
    
    // Check for bearish structure (LL+LH sequence)
    if(signalIsBullish && (sse.state == MSS_BEARISH_STRONG || sse.state == MSS_BEARISH_WEAK))
    {
        LogPrint("[STRUCT_ALIGN] REJECT | H1/H4 structure is BEARISH but signal is BULLISH", LOG_LEVEL_WARN);
        return false;
    }
    // Check for bullish structure (HH+HL sequence)
    if(!signalIsBullish && (sse.state == MSS_BULLISH_STRONG || sse.state == MSS_BULLISH_WEAK))
    {
        LogPrint("[STRUCT_ALIGN] REJECT | H1/H4 structure is BULLISH but signal is BEARISH", LOG_LEVEL_WARN);
        return false;
    }
    
    LogPrint("[STRUCT_ALIGN] OK | signal direction aligns with structure TF state", LOG_LEVEL_DEBUG);
    return true;
}

/**
 * CalculateBiasStrength — Calculate bias strength score
 *
 * Strength factors:
 *   - SSE state (STRONG = 1.0, WEAK = 0.5)
 *   - External break confirmation (+0.2)
 *   - Displacement confirmation (+0.3)
 *
 * Total: 0.0 - 1.5 (higher = stronger bias)
 *
 * @param sseState SSE market structure state
 * @param sseOutput SSE output with confirmation flags
 * @return Strength score (0.0 - 1.5)
 */
double CalculateBiasStrength(
    MarketStructureState sseState,
    const SSE_Output &sseOutput
 )
 {
    double strength = 0.0;

    // Handle uninitialized — strength is indeterminate, waiting for recovery
    if(sseState == MSS_UNINITIALIZED)
    {
       return 0.0;  // Pending recovery
    }

    // Factor 1: Base strength from SSE state
    if(sseState == MSS_BULLISH_STRONG || sseState == MSS_BEARISH_STRONG)
    {
       strength = 1.0;  // Strong base
    }
    else if(sseState == MSS_BULLISH_WEAK || sseState == MSS_BEARISH_WEAK)
    {
       strength = 0.5;  // Weak base
    }
    else
    {
       return 0.0;  // MSS_RANGE = no bias
    }

    // Factor 2: External break confirmation (+0.2)
    if(sseOutput.externalBreak)
    {
       strength += 0.2;
    }

    // Factor 3: Displacement confirmation (+0.3)
    if(sseOutput.displacementConfirmed)
    {
       strength += 0.3;
    }

    return strength;
 }

//+------------------------------------------------------------------+
//| MAIN ENGINE FUNCTIONS                                            |
//+------------------------------------------------------------------+

/**
 * BR_Initialize — Initialize Bias Resolver
 *
 * Call during EA initialization.
 * Resets global context to defaults.
 *
 * @return true on success
 */
bool BR_Initialize()
{
   g_brContext.Reset();
   if(g_logLevel <= LOG_LEVEL_DEBUG)
   {
   LogPrint("[BR] Bias Resolver initialized", LOG_LEVEL_DEBUG);
   }
   return true;
}

/**
 * BR_Resolve — Main bias resolution
 *
 * MAIN ENTRY POINT for bias derivation.
 * Derives bias SOLELY from SSE state.
 * Applies liquidity override if conditions met.
 *
 * STEPS:
 *   1. Resolve bias from SSE state
 *   2. Calculate strength score
 *   3. Apply liquidity override (if ERL + displacement)
 *   4. Update global context
 *   5. Log bias change if occurred
 *
 * @param sseOutput SSE output from StructuralStateEngine
 * @param liqOutput Liquidity output from LiquidityTierEngine
 * @param dvOutput Displacement output from DisplacementValidator
 * @return BiasOutput with resolved bias
 */
BiasOutput BR_Resolve(
    const SSE_Output &sseOutput,
    const LiquidityOutput &liqOutput,
    const DisplacementOutput &dvOutput
)
{
    string rationale = "";
    BiasOutput output;
    ZeroMemory(output);
    output.Reset();
    output.timestamp = TimeCurrent();

    // Step 1: Resolve bias from SSE state ONLY (no independent logic)
    output.bias = ResolveBiasFromSSE(sseOutput.state);

    // Step 2: Calculate strength score from SSE displacement
    output.strengthScore = CalculateBiasStrength(sseOutput.state, sseOutput);
    output.isStrong = sseOutput.displacementConfirmed;

// STEP 3: Trace NEUTRAL case with reason
     if(output.bias == BIAS_NEUTRAL)
     {
         // Silent exit — no BIAS_FAIL log during init
         if(sseOutput.state == MSS_UNINITIALIZED)
            return output;

         // Determine why bias is NEUTRAL
        string neutralReason = "NoDirectionalConsensus";
        if(sseOutput.state == MSS_RANGE)
        {
            neutralReason = "SSE_RANGE: sseOutput.state=MSS_RANGE";
        }
        else if(sseOutput.state == MSS_BULLISH_WEAK || sseOutput.state == MSS_BEARISH_WEAK)
        {
            neutralReason = "WeakStructure: state=" + EnumToString(sseOutput.state);
        }
        else
        {
            neutralReason = "UnknownState: state=" + EnumToString(sseOutput.state);
        }

        LogPrint("[BIAS_FAIL] Reason=" + neutralReason, LOG_LEVEL_WARN);
     }

     // Populate bias.source BEFORE returning (used by BRANCH_CFG log)
     if(sseOutput.state == MSS_BULLISH_STRONG || sseOutput.state == MSS_BULLISH_WEAK)
     {
        output.source = "D1_STRUCT";
     }
     else if(sseOutput.state == MSS_BEARISH_STRONG || sseOutput.state == MSS_BEARISH_WEAK)
     {
        output.source = "D1_STRUCT";
     }
     else
     {
        output.source = "D1_MANUAL";
     }

    // Step 4: Generate rationale
    output.rationale = GenerateRationale(output.bias, output.isStrong, sseOutput, liqOutput);

// STEP 2: Log decision on bias change
     static BiasType lastLoggedBias = BIAS_NEUTRAL;
     if(output.bias != lastLoggedBias)
     {
        lastLoggedBias = output.bias;
        LogPrint("[BIAS_CHG] Bias=" + EnumToString(output.bias)
                 + " | Strength=" + DoubleToString(output.strengthScore, 2),
                 LOG_LEVEL_INFO);
     }

    // Step 5: Update global context
    g_brContext.previous = g_brContext.current;
    g_brContext.current = output;

    // Step 6: Log bias change if occurred
    if(output.bias != g_brContext.previous.bias)
    {
       g_brContext.changeCount++;
       g_brContext.lastChangeTime = output.timestamp;
       BR_LogBiasChange(g_brContext.previous, output);
    }

    return output;
}

/**
 * BR_GetCurrentBias — Get current cached bias
 *
 * Returns the most recently computed bias without recomputation.
 *
 * @return const BiasOutput &current bias
 */
BiasOutput BR_GetCurrentBias()
{
   return g_brContext.current;
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+

/**
 * GenerateRationale — Generate bias rationale string
 *
 * @param bias Resolved bias type
 * @param isStrong Bias strength flag
 * @param sseOutput SSE output
 * @param liqOutput Liquidity output
 * @return Rationale string
 */
string GenerateRationale(
   BiasType bias,
   bool isStrong,
   const SSE_Output &sseOutput,
   const LiquidityOutput &liqOutput
)
{
   string rationale = "";

   // Bias direction
   if(bias == BIAS_BULLISH)
   {
      rationale = "BULLISH";
   }
   else if(bias == BIAS_BEARISH)
   {
      rationale = "BEARISH";
   }
   else
   {
      rationale = "NEUTRAL";
   }

   // Strength
   if(isStrong)
   {
      rationale += " (STRONG)";
   }
   else
   {
      rationale += " (WEAK)";
   }

   // SSE state contribution
   if(sseOutput.externalBreak)
   {
      rationale += " | External Break";
   }

   if(sseOutput.displacementConfirmed)
   {
      rationale += " | Displacement Confirmed";
   }

   // Liquidity override
   if(liqOutput.tier == LT_ERL)
   {
      rationale += " | ERL Detected";

      if(liqOutput.againstStructure)
      {
         rationale += " (Against Structure)";
      }
   }
   else if(liqOutput.tier == LT_IRL)
   {
      rationale += " | IRL Detected";
   }

   return rationale;
}

/**
 * BR_BiasToString — Convert bias to string
 *
 * @param bias BiasType
 * @return String representation
 */
string BR_BiasToString(BiasType bias)
{
   switch(bias)
   {
      case BIAS_BULLISH:  return "BIAS_BULLISH";
      case BIAS_BEARISH:  return "BIAS_BEARISH";
      case BIAS_NEUTRAL:  return "BIAS_NEUTRAL";
      default:            return "BIAS_UNKNOWN";
   }
}

/**
 * BR_LogBiasChange — Log bias change (telemetry)
 *
 * @param previous Previous bias output
 * @param current Current bias output
 */
void BR_LogBiasChange(const BiasOutput &previous, const BiasOutput &current)
{
    bool liquidityOverride = false;
    string rationale = "";
    string prev_str = BR_BiasToString(previous.bias);
   string curr_str = BR_BiasToString(current.bias);

if(g_logLevel <= LOG_LEVEL_INFO)
    {
    LogPrint("[BR] ═══════════════════════════════════════════════════", LOG_LEVEL_INFO);
    LogPrint("[BR] BIAS CHANGE DETECTED", LOG_LEVEL_INFO);
    LogPrint("[BR] Previous: " + prev_str, LOG_LEVEL_INFO);
    LogPrint("[BR] Current:  " + curr_str, LOG_LEVEL_INFO);
    LogPrint("[BR] Strength: " + DoubleToString(current.strengthScore, 2) +
                " (" + (current.isStrong ? "STRONG" : "WEAK") + ")", LOG_LEVEL_INFO);
    LogPrint("[BR] Liquidity Override: " + (current.liquidityOverride ? "APPLIED" : "NONE"), LOG_LEVEL_INFO);
    LogPrint("[BR] Time: " + TimeToString(current.timestamp), LOG_LEVEL_INFO);
    LogPrint("[BR] Rationale: " + current.rationale, LOG_LEVEL_INFO);
    LogPrint("[BR] ═══════════════════════════════════════════════════", LOG_LEVEL_INFO);
    }
}

//+------------------------------------------------------------------+
//| VALIDATION HELPERS                                               |
//+------------------------------------------------------------------+

/**
 * BR_IsBullish — Quick bullish check
 *
 * @param bias BiasOutput to check
 * @return true if bias is BIAS_BULLISH
 */
bool BR_IsBullish(const BiasOutput &bias)
{
   return (bias.bias == BIAS_BULLISH);
}

/**
 * BR_IsBearish — Quick bearish check
 *
 * @param bias BiasOutput to check
 * @return true if bias is BIAS_BEARISH
 */
bool BR_IsBearish(const BiasOutput &bias)
{
   return (bias.bias == BIAS_BEARISH);
}

/**
 * BR_IsNeutral — Quick neutral check
 *
 * @param bias BiasOutput to check
 * @return true if bias is BIAS_NEUTRAL
 */
bool BR_IsNeutral(const BiasOutput &bias)
{
   return (bias.bias == BIAS_NEUTRAL);
}

/**
 * BR_IsValid — Check if bias is valid (not neutral)
 *
 * @param bias BiasOutput to check
 * @return true if bias is BIAS_BULLISH or BIAS_BEARISH
 */
bool BR_IsValid(const BiasOutput &bias)
{
   return (bias.bias == BIAS_BULLISH || bias.bias == BIAS_BEARISH);
}

//+------------------------------------------------------------------+
//| ANALYSIS HELPER — Full Bias Analysis                             |
//+------------------------------------------------------------------+

/**
 * BR_AnalyzeBias — Complete bias analysis
 *
 * High-level function that performs full analysis:
 *   1. Gets SSE state from StructuralStateEngine
 *   2. Gets liquidity from LiquidityTierEngine
 *   3. Gets displacement from DisplacementValidator
 *   4. Resolves bias with all inputs
 *
 * @param symbol Symbol to analyze
 * @param tf Timeframe to analyze
 * @return BiasOutput with complete analysis
 */
BiasOutput BR_AnalyzeBias(
   const string symbol,
   ENUM_TIMEFRAMES tf
)
{
   BiasOutput output;
   ZeroMemory(output);
   output.Reset();

   // Step 1: Get SSE state
   SSE_Output sseOutput = SSE_AnalyzeStructure(symbol, tf);

   // Step 2: Get liquidity tier
   LiquidityOutput liqOutput = LTE_AnalyzeLiquidity(symbol, tf, sseOutput.state);

   // Step 3: Get displacement validation
   DisplacementOutput dvOutput = DV_AnalyzeDisplacement(symbol, tf);

   // Step 4: Resolve bias
   output = BR_Resolve(sseOutput, liqOutput, dvOutput);

   return output;
}

// BR_AnalyzeBiasWithTimeframe — Analyze bias for a specific timeframe
BiasOutput BR_AnalyzeBiasWithTimeframe(
   const string symbol,
   ENUM_TIMEFRAMES tf,
   ENUM_TIMEFRAMES fallbackTf // D1 for global fallback
)
{
   BiasOutput output;
   ZeroMemory(output);
   output.Reset();

   SSE_Output sseOutput = SSE_AnalyzeStructure(symbol, tf);
   
   if(sseOutput.state == MSS_RANGE)
   {
      SSE_Output d1Output = SSE_AnalyzeStructure(symbol, fallbackTf);
      output = BR_Resolve(d1Output, LTE_AnalyzeLiquidity(symbol, fallbackTf, d1Output.state), DV_AnalyzeDisplacement(symbol, fallbackTf));
      output.rationale += " | FALLBACK: " + EnumToString(fallbackTf);
      return output;
   }

   output = BR_Resolve(sseOutput, LTE_AnalyzeLiquidity(symbol, tf, sseOutput.state), DV_AnalyzeDisplacement(symbol, tf));
   return output;
}

//+------------------------------------------------------------------+
//| BR_ResolveForTimeframe — Resolve bias for branch with D1 fallback |
//+------------------------------------------------------------------+
// We define a helper inline to avoid include complexity
string BR_TfToString(ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_M5) return "M5";
   if(tf == PERIOD_M15) return "M15";
   if(tf == PERIOD_M30) return "M30";
   if(tf == PERIOD_H1) return "H1";
   if(tf == PERIOD_H4) return "H4";
   if(tf == PERIOD_D1) return "D1";
   return "UNKNOWN";
}

BiasOutput BR_ResolveForTimeframe(
   const string symbol,
   ENUM_TIMEFRAMES branchTf,
   ENUM_TIMEFRAMES fallbackTf
)
{
   BiasOutput output;
   ZeroMemory(output);
   output.Reset();

   SSE_Output branchSse = SSE_AnalyzeStructure(symbol, branchTf);

   if(branchSse.state != MSS_RANGE)
   {
      output = BR_Resolve(branchSse, LTE_AnalyzeLiquidity(symbol, branchTf, branchSse.state), DV_AnalyzeDisplacement(symbol, branchTf));
      output.rationale += " | Primary: " + BR_TfToString(branchTf);

      BiasType d1Bias = DailyClosureBias(symbol);
      if(d1Bias == BIAS_BULLISH || d1Bias == BIAS_BEARISH)
      {
         output.bias = d1Bias;
         output.source = "D1_CLOSURE";
         output.rationale += " | OVERRIDE: D1ClosureBias=" + EnumToString(d1Bias);
         LogPrint("[BR_RESOLVE] D1 Closure Bias override | bias=" + EnumToString(d1Bias), LOG_LEVEL_INFO);
      }
      return output;
   }

   SSE_Output d1Sse = SSE_AnalyzeStructure(symbol, fallbackTf);
   output = BR_Resolve(d1Sse, LTE_AnalyzeLiquidity(symbol, fallbackTf, d1Sse.state), DV_AnalyzeDisplacement(symbol, fallbackTf));
   output.rationale += " | Fallback: " + BR_TfToString(fallbackTf);

   BiasType d1Bias = DailyClosureBias(symbol);
   if(d1Bias == BIAS_BULLISH || d1Bias == BIAS_BEARISH)
   {
      output.bias = d1Bias;
      output.source = "D1_CLOSURE";
      output.rationale += " | OVERRIDE: D1ClosureBias=" + EnumToString(d1Bias);
      LogPrint("[BR_RESOLVE] D1 Closure Bias override (range fallback) | bias=" + EnumToString(d1Bias), LOG_LEVEL_INFO);
   }
   return output;
}

//+------------------------------------------------------------------+
//| BR_Warmup — Seed BiasResolver from historical bars                  |
//+------------------------------------------------------------------+
void BR_Warmup(const string symbol, ENUM_TIMEFRAMES tf, ENUM_TIMEFRAMES fallbackTf, int warmupBars = 25)
{
   BiasOutput result = BR_ResolveForTimeframe(symbol, tf, fallbackTf);

   if(result.bias == BIAS_PENDING)
   {
      LogPrint("[SSE_WARMUP] WARNING — D1 bias still BIAS_PENDING after " 
               + IntegerToString(warmupBars) + " warmup bars. "
               + "Backtest will start with blocked execution until D1 swing resolves.",
               LOG_LEVEL_WARN);
   }
   else
   {
      LogPrint("[SSE_WARMUP] D1 bias resolved after warmup: "
              + BR_BiasToString(result.bias), LOG_LEVEL_INFO);
   }
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+
// REGRESSION_GUARD_V52.5_BIASRESOLVER: Removed dead BR_ResolveWithPhase and SBiasInput
#endif // OMAK_BIASRESOLVER_MQH
