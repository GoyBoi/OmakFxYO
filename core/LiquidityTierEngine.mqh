//+------------------------------------------------------------------+
//|                                      LiquidityTierEngine.mqh |
//|                        OmakFxYO — Liquidity Tier Engine |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_LIQUIDITYTIERENGINE_MQH
#define OMAK_LIQUIDITYTIERENGINE_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Liquidity Tier Engine — Hierarchical Liquidity Classification"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>           // Base types
#include <OmakFxYO/core/StructuralStateEngine.mqh>    // SSE for againstStructure
#include <OmakFxYO/core/LiquidityEngine.mqh>     // Existing liquidity detection

//+------------------------------------------------------------------+
//| LiquidityTier — Hierarchical Liquidity Classification            |
//+------------------------------------------------------------------+
/**
 * LiquidityTier
 *
 * STRICT HIERARCHY — eliminates IRL/ERL ambiguity.
 *
 * TIERS:
 *   LT_NONE — No liquidity event detected
 *   LT_IRL  — Internal Range Liquidity (equal H/L sweep only)
 *   LT_ERL  — External Range Liquidity (HTF swing sweep)
 *
 * CRITICAL RULE:
 *   If ERL detected → IRL MUST BE IGNORED
 *   ERL takes absolute precedence over IRL
 *
 * HIERARCHY RATIONALE:
 *   - ERL (External) represents HTF swing breaks — major liquidity
 *   - IRL (Internal) represents equal H/L sweeps — minor liquidity
 *   - When both present, ERL is the DOMINANT liquidity event
 *   (Enum defined in CoreTypes.mqh to avoid circular includes)
 */

//+------------------------------------------------------------------+
//| LiquidityOutput — Tier Classification Output                     |
//+------------------------------------------------------------------+
/**
 * LiquidityOutput
 *
 * Contains classified liquidity tier and metadata.
 * This is the SINGLE SOURCE OF TRUTH for liquidity tier.
 */
struct LiquidityOutput
{
   LiquidityTier tier;           // Classified tier (hierarchical)
   bool sweepDetected;           // Any sweep detected
   bool againstStructure;        // Sweep against SSE structure
   datetime lastUpdateTime;      // When classification occurred
   ENUM_TIMEFRAMES timeframe;    // Timeframe analyzed

   // Reversal alignment fields
   bool               sweepAgainstTrend;   // Sweep is against the prevailing trend
   ENUM_DIRECTION     sweepDirection;      // Direction of the sweep (BUY=sweep low, SELL=sweep high)

   //+------------------------------------------------------------------+
   // | Reset — Clear all fields to defaults                           |
   //+------------------------------------------------------------------+
   void Reset()
   {
      tier = LT_NONE;
      sweepDetected = false;
      againstStructure = false;
      lastUpdateTime = 0;
      timeframe = PERIOD_CURRENT;
      sweepAgainstTrend = false;
      sweepDirection = DIRECTION_NONE;
   }
};

//+------------------------------------------------------------------+
//| LiquidityContext — Persistent Tier Context                        |
//+------------------------------------------------------------------+
/**
 * LiquidityContext
 *
 * Holds previous tier for transition tracking.
 */
struct LiquidityContext
{
   LiquidityOutput previous;     // Previous tier output
   LiquidityOutput current;      // Current tier output
   datetime lastChangeTime;      // When last tier change occurred
   int changeCount;              // Total number of tier changes

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
//| GLOBAL STATE — Liquidity Tier Context                             |
//+------------------------------------------------------------------+
LiquidityContext g_lteContext;

//+------------------------------------------------------------------+
//| CORE LOGIC — HIERARCHICAL TIER CLASSIFICATION                    |
//+------------------------------------------------------------------+

/**
 * ClassifyTier — Hierarchical tier classification
 *
 * CRITICAL RULE:
 *   if ERL detected:
 *       IRL must be ignored
 *       return LT_ERL
 *
 * LOGIC:
 *   1. If swing_high OR swing_low → ERL detected → return LT_ERL
 *   2. Else if eqh OR eql → IRL detected → return LT_IRL
 *   3. Else → return LT_NONE
 *
 * @param swing_high true if swing high liquidity
 * @param swing_low true if swing low liquidity
 * @param eqh true if equal highs
 * @param eql true if equal lows
 * @return LiquidityTier (hierarchical classification)
 */
LiquidityTier ClassifyTier(
   bool swing_high,
   bool swing_low,
   bool eqh,
   bool eql
)
{
   // Step 1: Check for ERL (External Range Liquidity)
   // ERL = swing high OR swing low (HTF swing break)
   bool has_erl = (swing_high || swing_low);

   // Step 2: Check for IRL (Internal Range Liquidity)
   // IRL = equal highs OR equal lows (internal inducement)
   bool has_irl = (eqh || eql);

   // CRITICAL RULE: If ERL detected, IRL must be ignored
   if(has_erl)
   {
      // ERL takes absolute precedence
      return LT_ERL;
   }

   // No ERL — check for IRL
   if(has_irl)
   {
      return LT_IRL;
   }

   // No liquidity event
   return LT_NONE;
}

//+------------------------------------------------------------------+
//| SWEEP DETECTION                                                  |
//+------------------------------------------------------------------+

/**
 * DetectSweep — Detect liquidity sweep
 *
 * A sweep occurs when price:
 *   1. Takes out a liquidity level (swing or equal H/L)
 *   2. Reverses (closes back inside range)
 *
 * @param current_high Current bar high
 * @param current_low Current bar low
 * @param current_close Current bar close
 * @param prev_high Previous bar high
 * @param prev_low Previous bar low
 * @param prev_close Previous bar close
 * @param swing_high true if swing high present
 * @param swing_low true if swing low present
 * @param eqh true if equal highs present
 * @param eql true if equal lows present
 * @return true if sweep detected
 */
bool DetectSweep(
   double current_high,
   double current_low,
   double current_close,
   double prev_high,
   double prev_low,
   double prev_close,
   bool swing_high,
   bool swing_low,
   bool eqh,
   bool eql
)
{
   // Check for bullish sweep (takes out low, closes higher)
   bool bullish_sweep = false;

   if(swing_low || eql)
   {
      // Price took out liquidity level
      if(current_low < prev_low)
      {
         // Price reversed (close > low, bullish rejection)
         if(current_close > current_low + (current_high - current_low) * 0.5)
         {
            bullish_sweep = true;
         }
      }
   }

   // Check for bearish sweep (takes out high, closes lower)
   bool bearish_sweep = false;

   if(swing_high || eqh)
   {
      // Price took out liquidity level
      if(current_high > prev_high)
      {
         // Price reversed (close < high, bearish rejection)
         if(current_close < current_high - (current_high - current_low) * 0.5)
         {
            bearish_sweep = true;
         }
      }
   }

   return (bullish_sweep || bearish_sweep);
}

//+------------------------------------------------------------------+
//| STRUCTURE ANALYSIS                                               |
//+------------------------------------------------------------------+

/**
 * IsAgainstStructure — Check if sweep is against market structure
 *
 * A sweep is "against structure" when:
 *   - Bullish sweep occurs in BEARISH structure
 *   - Bearish sweep occurs in BULLISH structure
 *
 * PROACTIVE RANGE LOGIC:
 *   - If MSS_RANGE with valid ERL sweep AND displacement > 1.2:
 *     - Return true with direction opposite to sweep
 *     - This allows BiasResolver to establish bias from range
 *
 * @param tier Liquidity tier
 * @param isBullishSweep true if bullish sweep
 * @param sseState Current SSE market structure state
 * @param displacementStrength Displacement strength score (optional, default 0)
 * @return true if sweep is against structure
 */
bool IsAgainstStructure(
   LiquidityTier tier,
   bool isBullishSweep,
   MarketStructureState sseState,
   double displacementStrength = 0.0
)
{
   // No tier = no structure analysis
   if(tier == LT_NONE)
      return false;

   // Check against bullish structure
   if(sseState == MSS_BULLISH_STRONG || sseState == MSS_BULLISH_WEAK)
   {
      // Bearish sweep (taking out highs) in bullish structure
      // This is WITH structure, not against
      if(!isBullishSweep)
         return false;

      // Bullish sweep (taking out lows) in bullish structure
      // This is AGAINST structure (counter-trend)
      if(isBullishSweep)
         return true;
   }

   // Check against bearish structure
   if(sseState == MSS_BEARISH_STRONG || sseState == MSS_BEARISH_WEAK)
   {
      // Bullish sweep (taking out lows) in bearish structure
      // This is WITH structure, not against
      if(isBullishSweep)
         return false;

      // Bearish sweep (taking out highs) in bearish structure
      // This is AGAINST structure (counter-trend)
      if(!isBullishSweep)
         return true;
   }

   // Range structure — proactive logic for establishing bias
   if(sseState == MSS_RANGE)
   {
      // If we have valid ERL sweep AND strong displacement
      // Consider it "against the range" to allow bias establishment
      if(tier == LT_ERL && displacementStrength >= 1.0)
      {
         // Proactive: sweep is against the range boundary
         // This enables BiasResolver to establish directional bias
         return true;
      }
      // Traditional: no clear direction in range
      return false;
   }

   return false;
}

//+------------------------------------------------------------------+
//| MAIN ENGINE FUNCTIONS                                            |
//+------------------------------------------------------------------+

/**
 * LTE_Initialize — Initialize Liquidity Tier Engine
 *
 * Call during EA initialization.
 * Resets global context to defaults.
 *
 * @return true on success
 */
bool LTE_Initialize()
{
   g_lteContext.Reset();
   if(g_logLevel <= LOG_LEVEL_DEBUG)
   {
   LogPrint("[LTE] Liquidity Tier Engine initialized", LOG_LEVEL_DEBUG);
   }
   return true;
}

/**
 * LTE_ComputeTier — Compute liquidity tier classification
 *
 * MAIN ENTRY POINT for tier classification.
 * Stateless per tick — recomputes cleanly from input data.
 *
 * STEPS:
 *   1. Classify tier using ClassifyTier()
 *   2. Detect sweep
 *   3. Check against structure (using SSE)
 *   4. Update global context
 *   5. Log tier change if occurred
 *
 * @param symbol Symbol to analyze
 * @param tf Timeframe to analyze
 * @param swing_high Swing high flag
 * @param swing_low Swing low flag
 * @param eqh Equal highs flag
 * @param eql Equal lows flag
 * @param sseState Current SSE market structure state
 * @return LiquidityOutput with classified tier
 */
LiquidityOutput LTE_ComputeTier(
   const string symbol,
   ENUM_TIMEFRAMES tf,
   bool swing_high,
   bool swing_low,
   bool eqh,
   bool eql,
   MarketStructureState sseState
)
{
   LiquidityOutput output;
   ZeroMemory(output);
   output.Reset();
   output.timeframe = tf;
   output.lastUpdateTime = TimeCurrent();

   // Step 1: Classify tier (hierarchical)
   output.tier = ClassifyTier(swing_high, swing_low, eqh, eql);

   // Step 2: Detect sweep
   // Note: In production, pass actual price data
   // For now, use simplified detection
   output.sweepDetected = (output.tier != LT_NONE);

   // Step 3: Check against structure
   // Determine sweep direction (simplified)
   // Note: displacementStrength not available in this context, use default
   bool isBullishSweep = swing_low || eql;  // Taking out lows
   output.againstStructure = IsAgainstStructure(output.tier, isBullishSweep, sseState, 0.0);

   // Step 4: Update global context
   g_lteContext.previous = g_lteContext.current;
   g_lteContext.current = output;

   // Step 5: Log tier change if occurred
   if(output.tier != g_lteContext.previous.tier)
   {
      g_lteContext.changeCount++;
      g_lteContext.lastChangeTime = TimeCurrent();
      LTE_LogTierChange(g_lteContext.previous, output);
   }

   return output;
}

/**
 * LTE_GetCurrentTier — Get current cached tier
 *
 * Returns the most recently computed tier without recomputation.
 * Use for quick tier checks between compute cycles.
 *
 * @param symbol Symbol (ignored for single-symbol operation)
 * @param tf Timeframe (ignored for single-symbol operation)
 * @return LiquidityOutput &current tier
 */
LiquidityOutput LTE_GetCurrentTier(const string symbol, ENUM_TIMEFRAMES tf)
{
   return g_lteContext.current;
}

//+------------------------------------------------------------------+
//| LOGGING & TELEMETRY                                              |
//+------------------------------------------------------------------+

/**
 * LTE_TierToString — Convert tier to string
 *
 * @param tier LiquidityTier
 * @return String representation
 */
string LTE_TierToString(LiquidityTier tier)
{
   switch(tier)
   {
      case LT_NONE:  return "LT_NONE";
      case LT_IRL:   return "LT_IRL (Internal)";
      case LT_ERL:   return "LT_ERL (External)";
      default:       return "LT_UNKNOWN";
   }
}

/**
 * LTE_LogTierChange — Log tier change (telemetry)
 *
 * @param previous Previous tier output
 * @param current Current tier output
 */
void LTE_LogTierChange(const LiquidityOutput &previous, const LiquidityOutput &current)
{
   // Throttle: log at most once per structure-TF bar to prevent spam.
   // Use separate statics for H1 (Branch A) and H4 (Branch B) to avoid cross-branch interference.
   static datetime s_lastLTEBarH1 = 0;
   static datetime s_lastLTEBarH4 = 0;
    if(g_activeBranch == BRANCH_SWING)
   {
      datetime h4Bar = iTime(_Symbol, PERIOD_H4, 0);
      if(h4Bar == s_lastLTEBarH4) return;
      s_lastLTEBarH4 = h4Bar;
   }
   else
   {
      datetime h1Bar = iTime(_Symbol, PERIOD_H1, 0);
      if(h1Bar == s_lastLTEBarH1) return;
      s_lastLTEBarH1 = h1Bar;
   }

   string prev_str = LTE_TierToString(previous.tier);
   string curr_str = LTE_TierToString(current.tier);

   if(g_logLevel <= LOG_LEVEL_INFO)
   {
   LGovPrint("[LTE] ═══════════════════════════════════════════════════", LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
   LGovPrint("[LTE] TIER CHANGE DETECTED", LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
   LGovPrint("[LTE] Previous: " + prev_str, LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
   LGovPrint("[LTE] Current:  " + curr_str, LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
   LGovPrint("[LTE] Sweep Detected: " + (current.sweepDetected ? "YES" : "NO"), LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
   LGovPrint("[LTE] Against Structure: " + (current.againstStructure ? "YES" : "NO"), LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
   LGovPrint("[LTE] Timeframe: " + EnumToString(current.timeframe), LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
   LGovPrint("[LTE] Time: " + TimeToString(current.lastUpdateTime), LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);

   // Generate rationale
   string rationale = "";

   if(current.tier == LT_ERL)
      rationale = "External Range Liquidity — HTF swing break (DOMINANT)";
   else if(current.tier == LT_IRL)
      rationale = "Internal Range Liquidity — Equal H/L sweep";
   else if(current.tier == LT_NONE)
      rationale = "No liquidity event detected";

   if(current.againstStructure)
      rationale += " | AGAINST STRUCTURE (counter-trend signal)";

   if(StringLen(rationale) > 0)
      LGovPrint("[LTE] Rationale: " + rationale, LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
   LGovPrint("[LTE] ═══════════════════════════════════════════════════", LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
   }
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS — INTEGRATION WITH LIQUIDITY ENGINE             |
//+------------------------------------------------------------------+

/**
 * LTE_FromLiquidityContext — Convert from existing LiquidityContext
 *
 * Convenience function to classify tier from existing SLiquidityContext
 * (from LiquidityEngine.mqh).
 *
 * @param liqContext SLiquidityContext from LiquidityEngine
 * @return LiquidityTier (hierarchical classification)
 */
LiquidityTier LTE_FromLiquidityContext(const SLiquidityContext &liqContext)
{
   // Use hierarchical classification
   // CRITICAL RULE: If ERL detected, IRL must be ignored
   if(liqContext.is_erl)
   {
      return LT_ERL;
   }

   if(liqContext.is_irl)
   {
      return LT_IRL;
   }

   return LT_NONE;
}

/**
 * LTE_PopulateFromLiquidityContext — Populate LiquidityOutput from context
 *
 * Convenience function to create full LiquidityOutput from SLiquidityContext.
 *
 * @param liqContext SLiquidityContext from LiquidityEngine
 * @param sseState Current SSE market structure state
 * @return LiquidityOutput populated with data
 */
LiquidityOutput LTE_PopulateFromLiquidityContext(
   const SLiquidityContext &liqContext,
   MarketStructureState sseState
)
{
   LiquidityOutput output;
   ZeroMemory(output);
   output.Reset();

   // Classify tier (hierarchical)
   output.tier = LTE_FromLiquidityContext(liqContext);

   // Set sweep detected
   output.sweepDetected = (liqContext.type != LIQ_NONE);

   // Check against structure
   // Note: displacementStrength not available in this context, use default
   bool isBullishSweep = liqContext.is_swing_low || liqContext.is_eql;
   output.againstStructure = IsAgainstStructure(output.tier, isBullishSweep, sseState, 0.0);

   // Set metadata
   output.lastUpdateTime = liqContext.time;
   output.timeframe = PERIOD_CURRENT;

   return output;
}

//+------------------------------------------------------------------+
//| VALIDATION HELPERS                                               |
//+------------------------------------------------------------------+

/**
 * LTE_IsValidTier — Validate tier is not NONE
 *
 * @param tier LiquidityTier to validate
 * @return true if tier is valid (IRL or ERL)
 */
bool LTE_IsValidTier(LiquidityTier tier)
{
   return (tier == LT_IRL || tier == LT_ERL);
}

/**
 * LTE_IsERL — Quick check for ERL tier
 *
 * @param tier LiquidityTier to check
 * @return true if tier is LT_ERL
 */
bool LTE_IsERL(LiquidityTier tier)
{
   return (tier == LT_ERL);
}

/**
 * LTE_IsIRL — Quick check for IRL tier
 *
 * @param tier LiquidityTier to check
 * @return true if tier is LT_IRL
 */
bool LTE_IsIRL(LiquidityTier tier)
{
   return (tier == LT_IRL);
}

//+------------------------------------------------------------------+
//| ANALYSIS HELPER — Full Liquidity Analysis                        |
//+------------------------------------------------------------------+

/**
 * LTE_AnalyzeLiquidity — Complete liquidity analysis
 *
 * High-level function that performs full analysis:
 *   1. Detects liquidity from LiquidityEngine
 *   2. Classifies tier (hierarchical)
 *   3. Checks against structure (using SSE)
 *
 * @param symbol Symbol to analyze
 * @param tf Timeframe to analyze
 * @param sseState Current SSE market structure state
 * @return LiquidityOutput with complete analysis
 */
LiquidityOutput LTE_AnalyzeLiquidity(
   const string symbol,
   ENUM_TIMEFRAMES tf,
   MarketStructureState sseState
)
{
   // Step 1: Get liquidity context from LiquidityEngine
   SLiquidityContext liqContext = DetectLiquidity(symbol, tf, 20);

   // Step 2: Populate and classify tier
   LiquidityOutput output = LTE_PopulateFromLiquidityContext(liqContext, sseState);
   output.timeframe = tf;
   output.lastUpdateTime = TimeCurrent();

   // Step 3: Update global context
   g_lteContext.previous = g_lteContext.current;
   g_lteContext.current = output;

   // Step 4: Log tier change if occurred
   if(output.tier != g_lteContext.previous.tier)
   {
      g_lteContext.changeCount++;
      g_lteContext.lastChangeTime = TimeCurrent();
      LTE_LogTierChange(g_lteContext.previous, output);
   }

   return output;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+

#endif // OMAK_LIQUIDITYTIERENGINE_MQH
