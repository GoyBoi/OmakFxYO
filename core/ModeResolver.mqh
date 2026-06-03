//+------------------------------------------------------------------+
//|                                           ModeResolver.mqh |
//|                           OmakFxYO — Mode Resolver |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_MODERESOLVER_MQH
#define OMAK_MODERESOLVER_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Mode Resolver — Mutually Exclusive Mode Selection"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>           // Base types
#include <OmakFxYO/core/StructuralTypes.mqh>      // SSE_Output, MarketStructureState, MarketStrategy
#include <OmakFxYO/core/BiasResolver.mqh>             // P09-D: BiasOutput
#include <OmakFxYO/core/LiquidityTierEngine.mqh>      // P09-B: LiquidityOutput
#include <OmakFxYO/core/StructuralStateEngine.mqh>    // P09-A: SSE_AnalyzeStructure (retained for function access)
#include <OmakFxYO/core/LogGovernor.mqh>         // Log governance
#include <OmakFxYO/core/DisplacementValidator.mqh>    // P09-C: DisplacementOutput
//#include <OmakFxYO/core/ClosureEngine.mqh>       // SClosureSignal, ENUM_FRACTAL_STATE, SStageSignal - REMOVED: SClosureSignal is in CoreTypes.mqh
#include <OmakFxYO/core/VolumeAnalyzer.mqh>      // Volume confirmation
#include <OmakFxYO/core/C2WickFilter.mqh>        // C2 wick validation
#include <OmakFxYO/core/UniversalConfig.mqh>     // Global config
#include <OmakFxYO/core/LockedSignal.mqh>        // SLockedSignal

 //+------------------------------------------------------------------+
//| EntryMode — Operational Mode Enum                                |
//+------------------------------------------------------------------+
/**
 * EntryMode
 *
 * MUTUALLY EXCLUSIVE mode selection.
 * MODE_BOTH is ILLEGAL — not defined in this enum.
 *
 * MODES:
 *   MODE_NONE           — No valid mode detected
 *   MODE_ANTICIPATION   — HTF sweep detected, D1 closure missing
 *   MODE_CONFIRMATION   — D1 closure present, all conditions met
 *
 * PRIORITY:
 *   Confirmation ALWAYS overrides Anticipation
 *   If Confirmation conditions met → Anticipation is IGNORED
 */
enum EntryMode
{
   MODE_NONE,            // No valid mode
   MODE_ANTICIPATION,    // Anticipation mode (HTF sweep, no D1 closure)
   MODE_CONFIRMATION     // Confirmation mode (D1 closure present)
   // NOTE: MODE_BOTH is ILLEGAL — not defined
};

//+------------------------------------------------------------------+
 //| Returns risk profile for the given entry mode                    |
 //+------------------------------------------------------------------+
 SRiskProfile GetRiskProfile(EntryMode mode, string symbol = "", double accountEquity = 0.0)
 {
     SRiskProfile profile;
     ZeroMemory(profile);

     // PHASE 3: Use config values from g_trueTTradesConfig if available
     double antiRR = g_trueTTradesConfig.anticipationMinRR;
     double confRR = g_trueTTradesConfig.confirmationMinRR;
     bool allowReversals = g_trueTTradesConfig.allowAnticipationReversals;
     
     // Ensure reasonable defaults if config is uninitialized
     if(antiRR <= 0.0) antiRR = 2.0;
      if(confRR <= 0.0) confRR = 2.0;

     double basePositionFactor = 0.0;

     if(mode == MODE_ANTICIPATION)
     {
        profile.slMultiplier       = 1.5;
        profile.minRR              = (int)antiRR;
        profile.tpMultiplier       = profile.slMultiplier * profile.minRR; // MUST satisfy tp/sl >= minRR
        basePositionFactor         = 0.6;
        profile.maxSpreadFactor    = 5.0;
        profile.useTrailingStop    = true;
        profile.trailingActivation = 1.0;
        profile.trailingStep       = 0.5;
     }
      else if(mode == MODE_CONFIRMATION)
      {
         profile.slMultiplier       = 1.0;
         profile.minRR              = (int)confRR;   // confRR now defaults to 2.0 via global config
         profile.tpMultiplier       = 0.0;   // Deferred — TP set by CalculateProjectionTPs from InpRiskRewardRatio
        basePositionFactor         = 1.0;
        profile.maxSpreadFactor    = 1.0;
        profile.useTrailingStop    = true;
        profile.trailingActivation = 1.5;
        profile.trailingStep       = 1.0;
     }

     profile.positionSizeFactor = basePositionFactor;

      // REGRESSION_GUARD_V52.5_MODE_RESOLVER_FLOOR — risk floor removed from strategy layer, no upward force

// STEP 4: Defensive assertion — verify RR constraint
     double derivedRR = profile.tpMultiplier / profile.slMultiplier;
     if(derivedRR < profile.minRR)
     {
         string rrError = StringFormat("[RISK_PROFILE_ERROR] RR constraint violated for mode %s: derivedRR=%.2f < minRR=%d",
                EnumToString(mode), derivedRR, profile.minRR);
         LogPrint(rrError, LOG_LEVEL_ERROR);
     }

     // STEP 5: Logging
     string riskProfile = StringFormat("[RISK_PROFILE] Mode=%s | SLx=%.2f | TPx=%.2f | minRR=%d | actualRR=%.2f",
         EnumToString(mode),
         profile.slMultiplier,
         profile.tpMultiplier,
         profile.minRR,
         derivedRR
      );
     LogPrint(riskProfile, LOG_LEVEL_DEBUG);

     return profile;
 }

//+------------------------------------------------------------------+
//| ModeOutput — Mode Resolution Result                              |
//+------------------------------------------------------------------+
/**
 * ModeOutput
 *
 * Contains resolved operational mode and validity flags.
 * Modes are MUTUALLY EXCLUSIVE.
 */
struct ModeOutput
{
     EntryMode mode;                 // Selected mode (TIMING MODIFIER ONLY)
     bool hasClosure;                // Closure trigger present (C2 or C3)
     MarketStrategy strategy;        // From SSE for timing decision
     datetime timestamp;             // When resolution occurred

    //+------------------------------------------------------------------+
    // | Reset — Clear all fields to defaults                           |
    //+------------------------------------------------------------------+
    void Reset()
    {
       mode = MODE_NONE;
       hasClosure = false;
       strategy = STRATEGY_RANGE;
       timestamp = 0;
    }
    
    //+------------------------------------------------------------------+
    // | Safe assignment helper - ensures mode field is set correctly  |
    //+------------------------------------------------------------------+
    void SetMode(EntryMode newMode)
    {
        mode = newMode;
    }
};

//+------------------------------------------------------------------+
//| ModeInput — Mode Resolution Input                                |
//+------------------------------------------------------------------+
/**
 * ModeInput
 *
 * Contains all inputs required for mode resolution.
 */
struct ModeInput
{
   BiasOutput bias;                    // From BiasResolver
   LiquidityOutput liquidity;          // From LiquidityTierEngine
   SSE_Output sse;                     // From StructuralStateEngine
   DisplacementOutput displacement;    // From DisplacementValidator
   SClosureSignal entrySignal;         // Entry TF closure signal

   // Reversal alignment fields
   bool               htfReversalForming;      // HTF C2 is forming against prior trend
   ENUM_DIRECTION     htfReversalDirection;    // Direction HTF is attempting to reverse toward
   bool               ltfReversalSignal;       // LTF CISD signal is a reversal (against LTF prior trend)
   ENUM_DIRECTION     ltfReversalDirection;    // Direction LTF reversal signal is pointing
   bool               allowLTFLead;            // User config: allow LTF to signal before HTF starts

   // STRUCTURAL AUTHORITY SYSTEM
   // Pass closure authority to ModeResolver for decision making
   bool               structure_authoritative; // TRUE if ClosureEngine provides valid structure
   ENUM_CLOSURE_TYPE  closureType;             // CLOSURE_C2 or CLOSURE_C3 from ClosureEngine

   //+------------------------------------------------------------------+
   // | Reset — Clear all fields to defaults                           |
   //+------------------------------------------------------------------+
   void Reset()
   {
      bias.Reset();
      liquidity.Reset();
      sse.Reset();
      displacement.Reset();
      entrySignal.Reset();
      htfReversalForming = false;
      htfReversalDirection = DIRECTION_NONE;
      ltfReversalSignal = false;
      ltfReversalDirection = DIRECTION_NONE;
      allowLTFLead = false;
      structure_authoritative = false;
      closureType = CLOSURE_NONE;
   }
};

//+------------------------------------------------------------------+
//| ModeContext — Persistent Resolver Context                        |
//+------------------------------------------------------------------+
/**
 * ModeContext
 *
 * Holds previous mode for transition tracking.
 */
struct ModeContext
{
   ModeOutput previous;                 // Previous mode output
   ModeOutput current;                  // Current mode output
   datetime lastChangeTime;            // When last mode change occurred
   int changeCount;                    // Total number of mode changes

// Dynamic Displacement & Risk Scaling — track previous state for hysteretic buffer
    MarketStructureState previousSSEState;    // Previous SSE state for trend transition detection

   //+------------------------------------------------------------------+
   // | Reset — Clear all fields to defaults                           |
   //+------------------------------------------------------------------+
   void Reset()
   {
      previous.Reset();
      current.Reset();
      lastChangeTime = 0;
      changeCount = 0;
      previousSSEState = MSS_RANGE;
   }
};

//+------------------------------------------------------------------+
//| STrueTTradesInput — True TTrades Mode Resolution Input |
//+------------------------------------------------------------------+
/**
 * STrueTTradesInput
 *
 * Contains all inputs required for true TTrades mode resolution.
 * Used by ResolveTrueTTradesMode() to determine entry timing.
 */
struct STrueTTradesInput
{
    ENUM_FRACTAL_STATE htfStage;           // Current HTF fractal stage
    ENUM_FRACTAL_STATE ltfStage;           // Current LTF fractal stage
    bool               ltfCISDConfirmed;   // LTF shows CISD
    bool               htfC2WickValid;     // HTF C2 passes wick filter
    bool               volumeConfirmed;    // C3 has volume expansion (if applicable)
    bool               htfBiasAligned;     // HTF bias matches intended direction
    ENUM_DIRECTION     intendedDirection;  // BUY or SELL
    double              displacementStrength; // Displacement multiplier (1.0+ = significant)
    BiasType            rawBias;            // Raw bias from BiasResolver (unfiltered)
    ENUM_FRACTAL_STATE htfCandleState;      // HTF candle state for mode resolution
    int                 htfPeriodSeconds;  // HTF period in seconds
    BiasType            d1Bias;             // D1 bias for mode resolution

    void Reset()
    {
htfStage = FRACTAL_STATE_NONE;
        ltfStage = FRACTAL_STATE_NONE;
        ltfCISDConfirmed = false;
        htfC2WickValid = false;
        volumeConfirmed = false;
        htfBiasAligned = false;
        intendedDirection = DIRECTION_NONE;
        displacementStrength = 0.0;
        rawBias = BIAS_NEUTRAL;
        htfCandleState = FRACTAL_STATE_NONE;
        htfPeriodSeconds = 0;
        d1Bias = BIAS_NEUTRAL;
     }
};

//+------------------------------------------------------------------+
//| GLOBAL STATE — Mode Resolver Context (PER BRANCH)                 |
//+------------------------------------------------------------------+
// SINGLE ModeContext — functions don't take branch params, so unified context
ModeContext g_mrContext;

//+------------------------------------------------------------------+
//| GetModeContext — Get ModeContext (returns by value, MQL5-safe)    |
//+------------------------------------------------------------------+
ModeContext GetModeContext(ENUM_EXECUTION_BRANCH branch)
{
   return g_mrContext;
}

//+------------------------------------------------------------------+
//| GUID-based mode cache — avoids re-resolving on every tick        |
//+------------------------------------------------------------------+
#define MAX_MODE_CACHE_SIZE 16

struct ModeCacheEntry
{
    ulong guid;
    EntryMode cachedMode;
    datetime lastUpdate;
    bool valid;
};

ModeCacheEntry g_modeCache[MAX_MODE_CACHE_SIZE * 2];  // 16 per branch
int g_modeCacheIndex = 0;

//+------------------------------------------------------------------+
//| GetCachedModeForGUID — Retrieve cached mode for signal           |
//+------------------------------------------------------------------+
EntryMode GetCachedModeForGUID(ulong guid, ENUM_EXECUTION_BRANCH branch = BRANCH_INTRADAY)
{
    if(guid == 0) return MODE_NONE;
    
    for(int i = 0; i < MAX_MODE_CACHE_SIZE * 2; i++)
    {
        if(g_modeCache[i].valid && g_modeCache[i].guid == guid)
        {
            return g_modeCache[i].cachedMode;
        }
    }
    return MODE_NONE;  // Not found
}

//+------------------------------------------------------------------+
//| SetCachedModeForGUID — Store mode for signal GUID                 |
//+------------------------------------------------------------------+
void SetCachedModeForGUID(ulong guid, EntryMode mode)
{
    if(guid == 0) return;
    
    int cacheSize = MAX_MODE_CACHE_SIZE * 2;
    
    // Check if entry exists
    for(int i = 0; i < cacheSize; i++)
    {
        if(g_modeCache[i].valid && g_modeCache[i].guid == guid)
        {
            g_modeCache[i].cachedMode = mode;
            g_modeCache[i].lastUpdate = TimeCurrent();
            return;
        }
    }
    
    // Not found, use round-robin replacement
    int idx = g_modeCacheIndex % cacheSize;
    g_modeCache[idx].guid = guid;
    g_modeCache[idx].cachedMode = mode;
    g_modeCache[idx].lastUpdate = TimeCurrent();
    g_modeCache[idx].valid = true;
    g_modeCacheIndex++;
}

//+------------------------------------------------------------------+
//| ClearCachedModeForGUID — Clear cached mode when signal cleared   |
//+------------------------------------------------------------------+
void ClearCachedModeForGUID(ulong guid)
{
    if(guid == 0) return;
    
    for(int i = 0; i < MAX_MODE_CACHE_SIZE; i++)
    {
        if(g_modeCache[i].valid && g_modeCache[i].guid == guid)
        {
            g_modeCache[i].valid = false;
            g_modeCache[i].guid = 0;
            g_modeCache[i].cachedMode = MODE_NONE;
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| ClearAllModeCache — Clear all cached modes (call on deinit)      |
//+------------------------------------------------------------------+
void ClearAllModeCache()
{
    for(int i = 0; i < MAX_MODE_CACHE_SIZE; i++)
    {
        g_modeCache[i].valid = false;
        g_modeCache[i].guid = 0;
        g_modeCache[i].cachedMode = MODE_NONE;
        g_modeCache[i].lastUpdate = 0;
    }
    g_modeCacheIndex = 0;
}

//+------------------------------------------------------------------+
//| Validates LTF-HTF reversal direction alignment                   |
//| Returns true if reversal entry is structurally valid             |
//+------------------------------------------------------------------+
bool IsReversalAligned(const ModeInput &src)
{
   // Not a reversal scenario — skip alignment check
   if(!src.htfReversalForming && !src.ltfReversalSignal)
      return true; // Continuation trade, no reversal check needed

   // HTF reversing + LTF confirming same direction = VALID
   if(src.htfReversalForming && src.ltfReversalSignal &&
      src.htfReversalDirection == src.ltfReversalDirection)
      return true;

   // LTF reversing but HTF not yet forming reversal
   if(!src.htfReversalForming && src.ltfReversalSignal)
   {
      if(src.allowLTFLead)
         return true;  // Aggressive mode: allow LTF to lead
      return false;    // Conservative mode: block
   }

   // HTF reversing but LTF not yet confirming — wait
   if(src.htfReversalForming && !src.ltfReversalSignal)
      return false;

   // Directions conflict
   if(src.htfReversalForming && src.ltfReversalSignal &&
      src.htfReversalDirection != src.ltfReversalDirection)
      return false;

   return false;
}

//+------------------------------------------------------------------+
//| CORE LOGIC — MODE RESOLUTION                                     |
//+------------------------------------------------------------------+

/**
 * CheckConfirmationConditions — Check if confirmation mode conditions are met
 *
 * CONFIRMATION MODE CONDITIONS (ALL must be true):
 *   1. Bias aligned (BIAS_BULLISH or BIAS_BEARISH)
 *   2. Structure strong (MSS_BULLISH_STRONG or MSS_BEARISH_STRONG)
 *   3. ERL present (LT_ERL)
 *   4. Closure valid (entrySignal.valid == true)
 *
 * @param src ModeInput with all resolution inputs
 * @return true if ALL confirmation conditions are met
 */
bool CheckConfirmationConditions(const ModeInput &src)
{
   // Fail fast: reversal alignment check
   if(!IsReversalAligned(src))
      return false;

   // Condition 1: Bias aligned (not neutral)
   bool bias_aligned = (src.bias.bias == BIAS_BULLISH ||
                        src.bias.bias == BIAS_BEARISH);

   if(!bias_aligned)
      return false;

   // Condition 2: Structure strong
   bool structure_strong = (src.sse.state == MSS_BULLISH_STRONG ||
                            src.sse.state == MSS_BEARISH_STRONG);

   if(!structure_strong)
      return false;

   // Condition 3: ERL present
   bool erl_present = (src.liquidity.tier == LT_ERL);

   if(!erl_present)
      return false;

   // Condition 4: Closure valid
   bool closure_valid = src.entrySignal.valid;

   if(!closure_valid)
      return false;    // ═══════════════════════════════════════════════════════════════════════
    // Dynamic Displacement & Risk Scaling — Hysteretic buffer for trend transitions
    // FIXED: Configurable thresholds (Priority 3) — more reasonable for general market
    // ═══════════════════════════════════════════════════════════════════════
    bool wasTrending = (g_mrContext.previousSSEState == MSS_BULLISH_STRONG ||
                       g_mrContext.previousSSEState == MSS_BEARISH_STRONG);
    double displacementThreshold = wasTrending 
        ? g_trueTTradesConfig.displacementThresholdTrending    // Default 1.0 (was 1.3)
        : g_trueTTradesConfig.displacementThresholdNonTrending; // Default 1.2 (was 1.5)

    // Validate displacement strength with dynamic threshold
    if(src.displacement.strengthScore < displacementThreshold)
       return false;

   // Update previous SSE state for next iteration
   g_mrContext.previousSSEState = src.sse.state;

   // ALL conditions met
   return true;
}

/**
 * CheckAnticipationConditions — Check if anticipation mode conditions are met
 *
 * ANTICIPATION MODE CONDITIONS (ALL must be true):
 *   1. Sweep must be ERL (external liquidity — institutional stop-hunt)
 *   2. Sweep must NOT be against structure (rejects inducement/continuation traps)
 *   3. Displacement valid with strengthScore >= 0.60 (conviction filter)
 *   4. Entry timeframe closure valid (C2 or C3 — early entry preserved)
 *
 * @param src ModeInput with all resolution inputs
 * @return true if ALL anticipation conditions are met
 */
bool CheckAnticipationConditions(const ModeInput &src)
{
   // Fail fast: reversal alignment check
   if(!IsReversalAligned(src))
      return false;

   // ═══════════════════════════════════════════════════════
   // GATE 1: Sweep must be ERL (external liquidity)
   // ═══════════════════════════════════════════════════════
   // IRL sweeps are equal H/L — minor liquidity, often noise
   // ERL sweeps are HTF swing takes — institutional stop-hunts
   // This is the PRIMARY frequency reducer
   if(src.liquidity.tier != LT_ERL)
      return false;

   // ═══════════════════════════════════════════════════════
   // GATE 2: Reject against-structure sweeps
   // ═══════════════════════════════════════════════════════
   // Sweeps against structure are often inducement or continuation traps
   // We only want sweeps that align with the prevailing structure
   if(src.liquidity.againstStructure)
      return false;

   // ═══════════════════════════════════════════════════════
   // GATE 3: Displacement must show conviction
   // ═══════════════════════════════════════════════════════
   // isValid alone is too loose — minDisplacementStrength is ~0.3
// We require strengthScore >= configurable threshold (Priority 3) to ensure meaningful move
    // This filters candles that pass isValid but are weak
    if(!src.displacement.isValid)
       return false;
    if(src.displacement.strengthScore < g_trueTTradesConfig.anticipationDisplacementMin)  // Default 0.40 (was 0.60)
    {
       // Anticipation dropped due to low displacement strength - NO LOGGING (pure function)
       return false;
    }

   // ═══════════════════════════════════════════════════════
   // GATE 4: Entry closure must exist (C2 or C3)
   // ═══════════════════════════════════════════════════════
   // C2 = body closes beyond level (early signal)
   // C3 = full candle beyond level (stronger signal)
   // BOTH accepted — this preserves Anticipation's early-entry nature
   if(!src.entrySignal.valid)
      return false;

   // ALL gates passed
   return true;
}

/**
 * ResolveMode — Resolve operational mode (mutually exclusive)
 *
 * CRITICAL LOGIC:
 *   1. Check Confirmation conditions FIRST
 *   2. If Confirmation met → return MODE_CONFIRMATION (Anticipation IGNORED)
 *   3. Else check Anticipation conditions
 *   4. If Anticipation met → return MODE_ANTICIPATION
 *   5. Else → return MODE_NONE
 *
 * MODE_BOTH is ILLEGAL — impossible by design.
 *
 * @param src ModeInput with all resolution inputs
 * @return EntryMode (mutually exclusive)
 */
EntryMode ResolveMode(const SSE_Output &sse, const SClosureSignal &closure, const BiasOutput &freshBias)
{
    if(!closure.valid)
    {
        return g_mrContext.current.mode;
    }

    // ═══════════════════════════════════════════════════════════════
    // DECOUPLED MODE RESOLUTION (v52.5+)
    // Mode derives from structural context + bias alignment,
    // NOT from closure type (C2/C3/C4 are closure-family events
    // sharing the same structural heritage).
    //
    // ANTICIPATION = early entry during structural transition
    // CONFIRMATION = structural trend confirmed + bias aligned
    // ═══════════════════════════════════════════════════════════════

    bool signalIsBullish = closure.is_bullish;
    bool biasAligned = IsBiasAligned(signalIsBullish, freshBias);
    MarketStrategy strategy = SSE_OutputToStrategy(sse);

    // Mode resolution by structural context
    switch(strategy)
    {
        case STRATEGY_TREND:
            // TREND + closure + displacement/bias confirmed → CONFIRMATION
            if(sse.displacementConfirmed || biasAligned)
            {
                LogPrint("[MODE_RESOLVE] MODE_CONFIRMATION | strategy=TREND | closure=" +
                         EnumToString(closure.type) + " | biasAligned=" +
                         (biasAligned ? "TRUE" : "FALSE"), LOG_LEVEL_DEBUG);
                return MODE_CONFIRMATION;
            }
            // TREND + closure but awaiting displacement → ANTICIPATION (early)
            LogPrint("[MODE_RESOLVE] MODE_ANTICIPATION | strategy=TREND | closure=" +
                     EnumToString(closure.type) + " | awaiting displacement", LOG_LEVEL_DEBUG);
            return MODE_ANTICIPATION;

        case STRATEGY_TRANSITION:
            // TRANSITION + closure → ANTICIPATION (reversal expected)
            LogPrint("[MODE_RESOLVE] MODE_ANTICIPATION | strategy=TRANSITION | closure=" +
                     EnumToString(closure.type), LOG_LEVEL_DEBUG);
            return MODE_ANTICIPATION;

        case STRATEGY_RANGE:
            // RANGE + closure + bias aligned → ANTICIPATION
            if(biasAligned)
            {
                LogPrint("[MODE_RESOLVE] MODE_ANTICIPATION | strategy=RANGE | biasAligned=TRUE | closure=" +
                         EnumToString(closure.type), LOG_LEVEL_DEBUG);
                return MODE_ANTICIPATION;
            }
            // RANGE + no bias → preserve current mode
            LogPrint("[MODE_RESOLVE] MODE_NONE | strategy=RANGE | bias not aligned | closure=" +
                     EnumToString(closure.type), LOG_LEVEL_DEBUG);
            return g_mrContext.current.mode;

        default:
            return g_mrContext.current.mode;
    }
}

//+------------------------------------------------------------------+
//| PHASE 2: True TTrades Mode Resolution                            |
//+------------------------------------------------------------------+

/**
 * ResolveTrueTTradesMode — True TTrades entry timing
 *
 * ANTICIPATION MODE (Early C2 Entry):
 *   - HTF is in FRACTAL_STATE_C2 (C2 candle currently sweeping)
 *   - LTF shows CISD confirmed
 *   - HTF C2 wick is valid (not too large)
 *   - HTF bias aligns with intended direction (preferred)
 *
 * CONFIRMATION MODE (Confirmed C3 Entry):
 *   - HTF C2 has closed validly (FRACTAL_STATE_C2)
 *   - HTF C3 is forming or has closed (FRACTAL_STATE_C3)
 *   - LTF CISD confirmed
 *   - Volume expansion confirmed (if applicable)
 *   - HTF bias MUST be aligned
 *
 * @param input STrueTTradesInput with all resolution inputs
 * @return EntryMode (MODE_ANTICIPATION, MODE_CONFIRMATION, or MODE_NONE)
 */
EntryMode ResolveTrueTTradesMode(const STrueTTradesInput &src)
{
// ═══════════════════════════════════════════════════════════════════════
     // STEP 2: FULL TRACE — Log ALL inputs at function entry
     // ═══════════════════════════════════════════════════════════════════════
     LogPrint("[MODE_TRACE] "
          + "HTF_Stage=" + EnumToString(src.htfStage)
          + " | LTF_Stage=" + EnumToString(src.ltfStage)
          + " | LTF_CISD=" + (src.ltfCISDConfirmed ? "TRUE" : "FALSE")
          + " | RawBias=" + EnumToString(src.rawBias)
          + " | BiasAligned=" + (src.htfBiasAligned ? "TRUE" : "FALSE")
          + " | IntendedDir=" + EnumToString(src.intendedDirection)
          + " | Disp=" + DoubleToString(src.displacementStrength, 2)
          + " | Volume=" + (src.volumeConfirmed ? "TRUE" : "FALSE"),
          LOG_LEVEL_DEBUG);

     // --- HTF REGIME IS ALWAYS VALID (Not a validation gate) ---
     // HTF provides regime context, NOT execution blocking

     // Determine HTF regime (for context, not gating)
     bool htfIsC2 = (src.htfStage == FRACTAL_STATE_C2);
     bool htfIsC3 = (src.htfStage == FRACTAL_STATE_C3);
     bool htfHasFractal = (src.htfStage != FRACTAL_STATE_NONE);

     // HTF bias is still required (directional alignment)
     bool htfBiasValid = src.htfBiasAligned;

     // --- LTF DISPLACEMENT IS MANDATORY (Execution trigger) ---
     bool ltfIsC2 = (src.ltfStage == FRACTAL_STATE_C2);
     bool ltfIsC3 = (src.ltfStage == FRACTAL_STATE_C3);
     bool ltfSignalValid = (src.ltfCISDConfirmed && (ltfIsC2 || ltfIsC3));

     // --- STEP 4: FAILURE TRACKING — Initialize failure reasons ---
     string antiFailReason = "N/A";
     string confFailReason = "N/A";

     // --- MODE RESOLUTION: LTF signal + Bias alignment ---

     // --- ANTICIPATION MODE (LTF C2 + Bias aligned) ---
     if(ltfIsC2 && ltfSignalValid)
     {
         // Bias can be aligned OR sweep direction provides intent in range
         bool biasPermits = htfBiasValid || (src.intendedDirection != DIRECTION_NONE);

         if(biasPermits)
         {
             // STEP 3: Trace Anticipation pass
             LogPrint("[MODE_DECISION] ANTICIPATION_PASS | Reason=LTF_C2 + BiasPermits", LOG_LEVEL_DEBUG);
             return MODE_ANTICIPATION;
         }
         else
         {
             antiFailReason = "BiasBlock: htfBiasValid=FALSE + intendedDirection=NONE";
         }
      }

      // --- CONFIRMATION MODE (LTF C3 + Bias aligned OR Range continuation) ---
      if(ltfIsC3 && ltfSignalValid)
      {
          // C3 confirmation requires bias alignment OR strong displacement in range
          bool confirmationPermitted = htfBiasValid || (src.displacementStrength > 1.5);

          if(!confirmationPermitted)
          {
              confFailReason = "BiasDispFail: htfBiasValid=FALSE + Disp<=" + DoubleToString(src.displacementStrength, 2);
// Print failure trace before returning
               LogPrint("[MODE_FAIL] "
                   + "AntiFail=" + antiFailReason
                   + " | ConfFail=" + confFailReason
                   + " | LTF_Valid=" + (ltfSignalValid ? "TRUE" : "FALSE")
                   + " | RawBias=" + EnumToString(src.rawBias)
                   + " | Disp=" + DoubleToString(src.displacementStrength, 2),
                   LOG_LEVEL_WARN);
               static EntryMode lastLoggedMode = MODE_NONE;
               if(MODE_NONE != lastLoggedMode)
               {
                  lastLoggedMode = MODE_NONE;
                  LogPrint("[MODE_CHG] Mode=" + EnumToString(MODE_NONE), LOG_LEVEL_INFO);
               }
              return MODE_NONE;
          }

         // Volume check (if enabled)
         if(g_trueTTradesConfig.useVolumeConfirmation)
         {
              SMarketProfile profile = GetMarketProfile(_Symbol);
               if(profile.requiresVolume && !src.volumeConfirmed)
               {
                   confFailReason = "VolumeFail: volumeConfirmed=FALSE";
// Print failure trace before returning
                    LogPrint("[MODE_FAIL] "
                        + "AntiFail=" + antiFailReason
                        + " | ConfFail=" + confFailReason
                        + " | LTF_Valid=" + (ltfSignalValid ? "TRUE" : "FALSE")
                        + " | RawBias=" + EnumToString(src.rawBias)
                        + " | Disp=" + DoubleToString(src.displacementStrength, 2),
                        LOG_LEVEL_WARN);
                    static EntryMode lastLoggedMode = MODE_NONE;
                    if(MODE_NONE != lastLoggedMode)
                    {
                       lastLoggedMode = MODE_NONE;
                       LogPrint("[MODE_CHG] Mode=" + EnumToString(MODE_NONE), LOG_LEVEL_INFO);
                    }
                   return MODE_NONE;
               }
           }

// STEP 3: Trace Confirmation pass
               LogPrint("[MODE_DECISION] CONFIRMATION_PASS | Reason=LTF_C3 + Bias/Disp OK", LOG_LEVEL_DEBUG);
              return MODE_CONFIRMATION;
          }

      // --- RANGE MODE (LTF signal exists but no clear direction) ---
      // Allow execution in ranging markets if displacement exists
      if(ltfSignalValid && src.displacementStrength > 1.0)
      {
// Range mode: enter on displacement even without bias
           // STEP 3: Trace Range pass
           LogPrint("[MODE_DECISION] RANGE_PASS | Reason=LTF_VALID + Disp>1.0", LOG_LEVEL_DEBUG);
          return MODE_ANTICIPATION;
      }

      // --- STEP 4: MODE_NONE FAILURE TRACE ---
      // Determine Anticipation failure reason
      if(ltfIsC2 && ltfSignalValid)
      {
          // We had C2 but bias didn't permit
          antiFailReason = "C2_BiasBlock: biasPermits=FALSE (htfBiasValid=FALSE + intendedDirection=NONE)";
      }
      else if(!ltfSignalValid)
      {
          antiFailReason = "No_LTF_Signal: ltfCISDConfirmed=" + (src.ltfCISDConfirmed ? "TRUE" : "FALSE") +
                          " ltfIsC2=" + (ltfIsC2 ? "TRUE" : "FALSE") +
                          " ltfIsC3=" + (ltfIsC3 ? "TRUE" : "FALSE");
      }
      else
      {
          antiFailReason = "C2_Check_Failed: unknown";
      }

      // Confirmation failure (C3 path would have set confFailReason)
      if(ltfIsC3 && ltfSignalValid && confFailReason == "N/A")
      {
          // Shouldn't reach here (early return would have happened)
          // But just in case, set generic
          confFailReason = "C3_UnknownFail";
      }
      else if(confFailReason == "N/A")
      {
          confFailReason = "N/A (C3 not attempted)";
      }

// STEP 4: Print comprehensive failure trace
       LogPrint("[MODE_FAIL] "
           + "AntiFail=" + antiFailReason
           + " | ConfFail=" + confFailReason
           + " | LTF_Valid=" + (ltfSignalValid ? "TRUE" : "FALSE")
           + " | RawBias=" + EnumToString(src.rawBias)
           + " | Disp=" + DoubleToString(src.displacementStrength, 2),
           LOG_LEVEL_WARN);
       static EntryMode lastLoggedMode = MODE_NONE;
       if(MODE_NONE != lastLoggedMode)
       {
          lastLoggedMode = MODE_NONE;
          LogPrint("[MODE_CHG] Mode=" + EnumToString(MODE_NONE), LOG_LEVEL_INFO);
       }

      // --- MODE_NONE (No LTF signal) ---
      return MODE_NONE;
 }

/**
 * MR_Resolve — Main mode resolution with true TTrades support
 *
 * MAIN ENTRY POINT for mode selection.
 * Routes to true TTrades or legacy mode based on config.
 *
 * @param src     Legacy mode input
 * @param ttInput True TTrades mode input
 * @return ModeOutput with resolved mode
 */
ModeOutput MR_Resolve(const ModeInput &src, const STrueTTradesInput &ttInput)
{
   ModeOutput output;
   ZeroMemory(output);
   output.Reset();
   output.timestamp = TimeCurrent();

   // STICKY MODE: Only resolve new mode when closure is valid
   // If closure not valid, preserve existing mode (defensive)
if(src.entrySignal.valid)
    {
       // TIMING MODIFIER: Use SSE strategy + closure presence (not structural authority)
       output.strategy = SSE_OutputToStrategy(src.sse);
       output.hasClosure = true;
       output.mode = ResolveMode(src.sse, src.entrySignal, src.bias);

      // REGRESSION GUARD: Log when mode is resolved
      LogTrace("[MODE_RESOLVED] closureValid=true | mode=" + MR_ModeToString(output.mode), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
   }
   else
   {
      // No closure — preserve existing mode (don't destroy with MODE_NONE)
      output.strategy = SSE_OutputToStrategy(src.sse);
      output.hasClosure = false;
      output.mode = g_mrContext.current.mode;  // Preserve previous valid mode

      // REGRESSION GUARD: Log when mode is preserved (no closure)
      if(output.mode != MODE_NONE)
         LogTrace("[MODE_PRESERVED] closureValid=false | mode=" + MR_ModeToString(output.mode), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
   }

   // Update context (NO LOGGING here - pure function, log in OmakFxYO)
   g_mrContext.previous = g_mrContext.current;
   g_mrContext.current = output;
   if(output.mode != g_mrContext.previous.mode)
   {
      g_mrContext.changeCount++;
      g_mrContext.lastChangeTime = output.timestamp;
   }

   return output;
}

//+------------------------------------------------------------------+
//| MAIN ENGINE FUNCTIONS                                            |
//+------------------------------------------------------------------+

/**
 * MR_Initialize — Initialize Mode Resolver
 *
 * Call during EA initialization.
 * Resets global context to defaults.
 *
 * @return true on success
 */
bool MR_Initialize()
{
   g_mrContext.Reset();
   if(g_logLevel <= LOG_LEVEL_DEBUG)
   {
   LogPrint("[MR] Mode Resolver initialized", LOG_LEVEL_INFO);
   }
   return true;
}

/**
 * MR_Resolve — Main mode resolution
 *
 * MAIN ENTRY POINT for mode selection.
 * Enforces MUTUAL EXCLUSIVITY — Confirmation overrides Anticipation.
 *
 * STEPS:
 *   1. Check confirmation conditions
 *   2. Check anticipation conditions
 *   3. Resolve mode (confirmation overrides)
 *   4. Update global context
 *   5. Log mode change if occurred
 *
 * @param src ModeInput with all resolution inputs
 * @return ModeOutput with resolved mode
 */
ModeOutput MR_Resolve(const SSE_Output &sse, const SClosureSignal &closure, const BiasOutput &bias)
{
    ModeOutput output;
    ZeroMemory(output);
    output.Reset();
    output.timestamp = TimeCurrent();

    // STICKY MODE: Only resolve new mode when closure is valid
    // If closure not valid, preserve existing mode (defensive)
    if(closure.valid)
    {
       // TIMING MODIFIER: Mode determined by SSE strategy + closure presence
       output.strategy = SSE_OutputToStrategy(sse);
       output.hasClosure = true;
       output.mode = ResolveMode(sse, closure, bias);
    }
    else
    {
       // No closure — preserve existing mode (don't destroy with MODE_NONE)
       output.strategy = SSE_OutputToStrategy(sse);
       output.hasClosure = false;
       output.mode = g_mrContext.current.mode;  // Preserve previous valid mode
    }

    // Update global context
    g_mrContext.previous = g_mrContext.current;
    g_mrContext.current = output;

    LogPrint("[MODE_RESOLVED] mode=" + EnumToString(output.mode), LOG_LEVEL_DEBUG);
    return output;
}

/**
 * MR_GetCurrentMode — Get current cached mode
 *
 * Returns the most recently computed mode without recomputation.
 *
 * @return const ModeOutput &current mode
 */
ModeOutput MR_GetCurrentMode()
{
   return g_mrContext.current;
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+

/**
 * GenerateModeRationale — Generate mode rationale string
 *
 * @param mode Resolved mode
 * @param confirmation_ok Confirmation conditions flag
 * @param anticipation_ok Anticipation conditions flag
 * @param src ModeInput
 * @return Rationale string
 */
string GenerateModeRationale(
   EntryMode mode,
   bool confirmation_ok,
   bool anticipation_ok,
   const ModeInput &src
)
{
   string rationale = "";

   if(mode == MODE_CONFIRMATION)
   {
      rationale = "MODE_CONFIRMATION";

      // List confirmed conditions
      if(src.bias.bias == BIAS_BULLISH)
         rationale += " | Bullish Bias";
      else if(src.bias.bias == BIAS_BEARISH)
         rationale += " | Bearish Bias";

      if(src.sse.state == MSS_BULLISH_STRONG || src.sse.state == MSS_BEARISH_STRONG)
         rationale += " | Strong Structure";

      if(src.liquidity.tier == LT_ERL)
         rationale += " | ERL Present";

      if(src.entrySignal.valid)
         rationale += " | Closure Valid";
   }
   else if(mode == MODE_ANTICIPATION)
   {
      rationale = "MODE_ANTICIPATION";

      // List confirmed conditions
      if(src.liquidity.sweepDetected)
         rationale += " | Sweep Detected";

      if(src.displacement.isValid)
         rationale += " | Displacement Valid";

      if(src.entrySignal.valid)
         rationale += " | Closure Valid";
   }
   else
   {
      rationale = "MODE_NONE";

      // Explain why neither mode is valid
      if(!confirmation_ok && !anticipation_ok)
      {
         rationale += " | No conditions met";
      }
      else if(!confirmation_ok)
      {
         rationale += " | Confirmation conditions failed";
      }
      else if(!anticipation_ok)
      {
         rationale += " | Anticipation conditions failed";
      }
   }

   return rationale;
}

/**
 * MR_ModeToString — Convert mode to string
 *
 * @param mode EntryMode
 * @return String representation
 */
string MR_ModeToString(EntryMode mode)
{
   switch(mode)
   {
      case MODE_NONE:           return "MODE_NONE";
      case MODE_ANTICIPATION:   return "MODE_ANTICIPATION";
      case MODE_CONFIRMATION:   return "MODE_CONFIRMATION";
      default:                  return "MODE_UNKNOWN";
   }
}

/**
 * MR_LogModeChange — Log mode change (telemetry)
 *
 * @param previous Previous mode output
 * @param current Current mode output
 */
void MR_LogModeChange(const ModeOutput &previous, const ModeOutput &current)
{
   // PURE FUNCTION - NO LOGGING
   // Mode change logging moved to OmakFxYO after BE_GetBestBranch()
   // This function kept for telemetry/callback compatibility only
}

//+------------------------------------------------------------------+
//| VALIDATION HELPERS                                               |
//+------------------------------------------------------------------+

/**
 * MR_IsConfirmation — Quick confirmation mode check
 *
 * @param output ModeOutput to check
 * @return true if mode is MODE_CONFIRMATION
 */
bool MR_IsConfirmation(const ModeOutput &output)
{
   return (output.mode == MODE_CONFIRMATION);
}

/**
 * MR_IsAnticipation — Quick anticipation mode check
 *
 * @param output ModeOutput to check
 * @return true if mode is MODE_ANTICIPATION
 */
bool MR_IsAnticipation(const ModeOutput &output)
{
   return (output.mode == MODE_ANTICIPATION);
}

/**
 * MR_IsValid — Check if mode is valid (not MODE_NONE)
 *
 * @param output ModeOutput to check
 * @return true if mode is MODE_CONFIRMATION or MODE_ANTICIPATION
 */
bool MR_IsValid(const ModeOutput &output)
{
   return (output.mode == MODE_CONFIRMATION || output.mode == MODE_ANTICIPATION);
}

//+------------------------------------------------------------------+
//| ANALYSIS HELPER — Full Mode Analysis                             |
//+------------------------------------------------------------------+

/**
 * MR_AnalyzeMode — Complete mode analysis
 *
 * High-level function that performs full analysis:
 *   1. Gets bias from BiasResolver
 *   2. Gets liquidity from LiquidityTierEngine
 *   3. Gets SSE from StructuralStateEngine
 *   4. Gets displacement from DisplacementValidator
 *   5. Gets closure signal from ClosureEngine
 *   6. Resolves mode with all inputs
 *
 * @param symbol Symbol to analyze
 * @param tf Timeframe to analyze
 * @return ModeOutput with complete analysis
 */
ModeOutput MR_AnalyzeMode(
   const string symbol,
   ENUM_TIMEFRAMES tf
)
{
   ModeOutput output;
   ZeroMemory(output);
   output.Reset();

   // Step 1: Gather all inputs
   ModeInput src;

   // Get bias
   src.bias = BR_AnalyzeBias(symbol, tf);

   // Get liquidity
   // First need SSE state for liquidity analysis
   src.sse = SSE_AnalyzeStructure(symbol, tf);
   src.liquidity = LTE_AnalyzeLiquidity(symbol, tf, src.sse.state);

   // Get displacement
   src.displacement = DV_AnalyzeDisplacement(symbol, tf);

    // Get closure signal (entry timeframe)
    // Use M15 for entry by default
ENUM_TIMEFRAMES entryTF = PERIOD_M15;
     SLockedSignal dummyLock;  // Not used for locking
     dummyLock.Reset();
     dummyLock.TransitionStage(STAGE_LOCKED);  // Prevent bridge from locking
     // DetectClosureSignal removed - cannot include ClosureEngine.mqh due to circular dependency
     // Entry signal will be populated by caller if needed
     src.entrySignal.valid = false;
     src.entrySignal.is_bullish = false;

     // Step 2: Resolve mode
     STrueTTradesInput ttInput;
     ttInput.Reset();
     output = MR_Resolve(src.sse, src.entrySignal, src.bias);

    return output;
 }

//+------------------------------------------------------------------+
//| MODE SELECTION DECISION TREE                                     |
//+------------------------------------------------------------------+
/**
 * MODE SELECTION DECISION TREE
 * 
 * This diagram shows the EXACT decision flow:
 * 
 *                          START
 *                            │
 *                            ▼
 *              ┌─────────────────────────┐
 *              │ Check Confirmation      │
 *              │ Conditions              │
 *              └───────────┬─────────────┘
 *                          │
 *              ┌───────────┴─────────────┐
 *              │                         │
 *              ▼                         ▼
 *         MET? YES                  MET? NO
 *              │                         │
 *              │                         ▼
 *              │              ┌─────────────────────────┐
 *              │              │ Check Anticipation      │
 *              │              │ Conditions              │
 *              │              └───────────┬─────────────┘
 *              │                          │
 *              │              ┌───────────┴─────────────┐
 *              │              │                         │
 *              │              ▼                         ▼
 *              │         MET? YES                  MET? NO
 *              │              │                         │
 *              │              │                         │
 *              ▼              ▼                         ▼
 *     MODE_CONFIRMATION   MODE_ANTICIPATION        MODE_NONE
 *     (OVERRIDES)         (FALLBACK)               (INVALID)
 * 
 * CRITICAL: Confirmation ALWAYS checked FIRST
 *           If Confirmation met → Anticipation NOT checked
 *           MODE_BOTH is IMPOSSIBLE (not in enum)
 */

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+

#endif // OMAK_MODERESOLVER_MQH
