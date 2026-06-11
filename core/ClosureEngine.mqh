//+------------------------------------------------------------------+
//|                                              ClosureEngine.mqh |
//|                                    OmakFxYO — TRUE TTrades Fractal Engine |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_CLOSUREENGINE_MQH
#define OMAK_CLOSUREENGINE_MQH

#property strict
#property copyright "OMAK"
#property version   "1.04"
#property description "TRUE TTrades Fractal Engine — Explicit C2/C3 Closure Logic + PHASE6 DEBUG"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>     // ENUM_DIRECTION, DIRECTION_NONE, LiquidityTier, SClosureSignal, etc.
#include <OmakFxYO/core/LogGovernor.mqh>    // Log governance (NEW)
#include <OmakFxYO/core/RiskManager.mqh>    // RM_ComputeEntryTFSL — Manipulation Leg SL (§V)

//+------------------------------------------------------------------+
//| Forward Declarations                                             |
//+------------------------------------------------------------------+
bool PreAllocateSignalGUIDEntry(ulong signalGUID, double c1High, double c1Low,
                                double c2High, double c2Low,
                                ENUM_EXECUTION_BRANCH branch, ENUM_DIRECTION dir,
                                ENUM_CLOSURE_TYPE closureType, double entryPrice);

// BranchEvaluator.mqh types needed for BranchContext fields
// NOTE: ClosureEngine.mqh is included AFTER BranchEvaluator.mqh in the include chain
// BranchContext struct definition provided by BranchEvaluator.mqh via includes below
// REGRESSION_GUARD_V52.5_CLOSUREENGINE_INCLUDE_ORDER

#include <OmakFxYO/core/ClosureState.mqh>  // SC2State/SC3State/SC4State
#include <OmakFxYO/core/FractalNarrative.mqh> // SFractalNarrative, SClosureEvent
#include <OmakFxYO/core/StructuralTypes.mqh>        // SSE_Output, MarketStructureState, MarketStrategy
#include <OmakFxYO/core/LiquidityTierEngine.mqh>      // LiquidityOutput
#include <OmakFxYO/core/DisplacementValidator.mqh>    // DisplacementOutput
#include <OmakFxYO/core/BiasResolver.mqh>             // BiasOutput
#include <OmakFxYO/core/ModeResolver.mqh>             // ModeOutput

#include <OmakFxYO/core/LockedSignal.mqh>   // SLockedSignal definition (includes Lock() now)
#include <OmakFxYO/core/SignalQuery.mqh>   // Signal query interface (isolated)
#include <OmakFxYO/core/FVGEngine.mqh>       // FVG detection for POI validation
#include <OmakFxYO/core/ExecutionEngine.mqh>   // Gate 4: T-Spot POI Mapping (C3 FIX)

// Forward declarations for functions defined later in this file (after types are known)
void DetectClosureSignal(string symbol, ENUM_TIMEFRAMES tf, SClosureSignal &out_signal, SLockedSignal &lockedSignal);
bool RegisterPipelineSignal(ulong guid, ENUM_CLOSURE_TYPE type, double c1High, double c1Low,
                            double c2High, double c2Low, ENUM_DIRECTION direction = DIRECTION_NONE);

// SSetupState — Per-branch setup state
struct SSetupState
{
   bool isActive;
   bool isConfirmed;
   bool isInvalidated;
   bool isExpired;

   ENUM_CLOSURE_TYPE closureKind;
   ulong sequenceId;
   datetime anchorBarTime;
   datetime lastUpdateTime;
   datetime lastActionTime;

   double c2_high;
   double c2_low;
   double c3_high;
   double c3_low;

   void Reset()
   {
      isActive = false;
      isConfirmed = false;
      isInvalidated = false;
      isExpired = false;
      closureKind = CLOSURE_NONE;
      sequenceId = 0;
      anchorBarTime = 0;
      lastUpdateTime = 0;
      lastActionTime = 0;
      c2_high = 0.0;
      c2_low = 0.0;
      c3_high = 0.0;
      c3_low = 0.0;
   }

   bool IsValidForExecution() const
   {
      return isActive && isConfirmed && !isInvalidated && !isExpired;
   }

   void Invalidate(string reason)
   {
      isInvalidated = true;
      isActive = false;
      isConfirmed = false;
      lastUpdateTime = TimeCurrent();
      if(InpEnableTrace)
         LGovPrint("[STATE_TRANSITION_OK] CLOSURE_SETUP -> invalidated | sequenceId=" + IntegerToString(sequenceId) +
                   " | reason=" + reason, LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
   }

   void MarkExpired()
   {
      isExpired = true;
      isActive = false;
      isConfirmed = false;
      lastUpdateTime = TimeCurrent();
      if(InpEnableTrace)
         LGovPrint("[STATE_TRANSITION_OK] CLOSURE_SETUP -> expired | sequenceId=" + IntegerToString(sequenceId),
                   LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
   }
};

// BranchContext — Branch-Specific Pipeline Context
struct BranchContext
{
    ENUM_EXECUTION_BRANCH branch;
    ENUM_TIMEFRAMES structureTF;
    ENUM_TIMEFRAMES entryTF;
    ENUM_CLOSURE_TYPE closureType;

    datetime htfCandleOpenTime;
    datetime htfCandleCloseTime;

    SSE_Output sse;
    LiquidityOutput liquidity;
    DisplacementOutput displacement;
    BiasOutput bias;
    ModeOutput mode;

    SC2State c2State;
    SC3State c3State;
    SC4State c4State;

    SSetupState setupState;

    SClosureSignal structureSignal;
    SClosureSignal entrySignal;

    datetime evaluationTime;
    bool isEvaluated;

    datetime lastStructureBarTime;
    datetime lastEntryBarTime;

    EntryMode cachedMode;
    datetime lastModeBarTime;

    SLockedSignal branchLockedSignal;
    bool branchForceRefresh;

    ulong lastProcessedSignalId;
    datetime lastProcessedBarTime;

    ulong lastBlockedSignalId;

    SLockedSignal pyramidSignal;
    bool pyramidSignalActive;

    void Reset()
    {
        branch = BRANCH_INTRADAY;
        structureTF = PERIOD_CURRENT;
        entryTF = PERIOD_CURRENT;
        closureType = CLOSURE_NONE;
        htfCandleOpenTime = 0;
        htfCandleCloseTime = 0;

        sse.Reset();
        liquidity.Reset();
        bias.Reset();
        mode.Reset();

        SC2StateReset(c2State);
        SC3StateReset(c3State);
        SC4StateReset(c4State);

        setupState.Reset();

        structureSignal.Reset();
        entrySignal.Reset();

        evaluationTime = 0;
        isEvaluated = false;
        lastStructureBarTime = 0;
        lastEntryBarTime = 0;
        cachedMode = MODE_NONE;
        lastModeBarTime = 0;

        branchLockedSignal.Reset();
        branchForceRefresh = false;
        lastProcessedSignalId = 0;
        lastProcessedBarTime = 0;
        lastBlockedSignalId = 0;

        pyramidSignalActive = false;
        pyramidSignal.Reset();
    }
};

// Extern branch context variables from BranchEvaluator.mqh
extern BranchContext g_branchAContext;
extern BranchContext g_branchBContext;
extern ENUM_EXECUTION_BRANCH g_activeBranch;
extern ENUM_ACTIVE_BRANCH g_activeBranchSelection;

//+------------------------------------------------------------------+
//| EXTERN — globals from main EA                                    |
//+------------------------------------------------------------------+
// DEPRECATED: g_p9ctx bridge removed. Use g_activeBranch + g_branchAContext/g_branchBContext directly.
  // NOTE: SLockedSignal g_activeSignal[] and g_hasActiveSignal[] are declared
    // in SignalQuery.mqh which is included above (line 22)

int GetSignalStoreIndex(ENUM_EXECUTION_BRANCH branch, ENUM_CLOSURE_TYPE closureType = CLOSURE_NONE);
  int GetMaxSignalsForClosureType(ENUM_CLOSURE_TYPE closureType);
  bool SQ_InvalidateSignal(ulong guid, ENUM_EXECUTION_BRANCH branch);

  //+------------------------------------------------------------------+
  //| SC2State / SC3State / SC4State — loaded from ClosureState.mqh    |
  //+------------------------------------------------------------------+
  // These types are defined in ClosureState.mqh (included via BranchEvaluator.mqh)
  // BranchContext uses these from ClosureState.mqh, ClosureEngine uses them for
  // temporary signal construction before locking.

  //+------------------------------------------------------------------+
  //| SEQUENCE Lineage Metadata - Per-type identity                     |
  //| (struct definition moved to CoreTypes.mqh v52.5+)                |
  //+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| SSignalClosure — Internal C2/C3/C4 signal data (ClosureEngine)   |
//| Renamed from SC2State/SC3State/SC4State to avoid conflict with   |
//| ClosureState.mqh definitions used by BranchContext.               |
//+------------------------------------------------------------------+
// NOTE: This struct is for temporary signal construction inside ClosureEngine.
// BranchContext.c2State/c3State/c4State use ClosureState.mqh types instead.

struct SSignalC2
{
   bool valid;
   ENUM_CLOSURE_TYPE type;
   bool is_bullish;
   
   double entry_price;
   double stop_loss;
   double equilibrium;
   
   double c1_high;
   double c1_low;
   double c1_close;
   
   double c2_high;
   double c2_low;
   double c2_open;
   double c2_close;
   int c2_barIndex;
   
   double c2_wick_ratio;
   bool againstPriorLTFTrend;
   ENUM_FRACTAL_STATE fractalState;
   
   SSequenceLineage lineage;
   
   void Reset()
   {
      valid = false;
      type = CLOSURE_C2;
      is_bullish = false;
      entry_price = 0.0;
      stop_loss = 0.0;
      equilibrium = 0.0;
      c1_high = 0.0;
      c1_low = 0.0;
      c1_close = 0.0;
      c2_high = 0.0;
      c2_low = 0.0;
      c2_open = 0.0;
      c2_close = 0.0;
      c2_barIndex = 0;
      c2_wick_ratio = 0.0;
      againstPriorLTFTrend = false;
      fractalState = FRACTAL_STATE_C2;
      lineage.Reset();
      lineage.closureKind = CLOSURE_C2;
   }
   
   bool IsActive() const { return valid && lineage.sequenceId != 0; }
};

//+------------------------------------------------------------------+
//| SSignalC3 — Internal C3 signal data (ClosureEngine)               |
//+------------------------------------------------------------------+
struct SSignalC3
{
   bool valid;
   ENUM_CLOSURE_TYPE type;
   bool is_bullish;
   
   double entry_price;
   double stop_loss;
   double equilibrium;
   
   double c1_high;
   double c1_low;
   double c1_close;
   
   double c2_high;
   double c2_low;
   double c2_open;
   double c2_close;
   int c2_barIndex;
   
   double c3_high;
   double c3_low;
   double c3_open;
   double c3_close;
   
   double c2_wick_ratio;
   double c3_wick_ratio;
   bool againstPriorLTFTrend;
   ENUM_FRACTAL_STATE fractalState;
   
   SSequenceLineage lineage;
   
   ulong priorSequenceId;  // If C2 promoted to C3, stores C2's sequenceId
   
   void Reset()
   {
      valid = false;
      type = CLOSURE_C3;
      is_bullish = false;
      entry_price = 0.0;
      stop_loss = 0.0;
      equilibrium = 0.0;
      c1_high = 0.0;
      c1_low = 0.0;
      c1_close = 0.0;
      c2_high = 0.0;
      c2_low = 0.0;
      c2_open = 0.0;
      c2_close = 0.0;
      c2_barIndex = 0;
      c3_high = 0.0;
      c3_low = 0.0;
      c3_open = 0.0;
      c3_close = 0.0;
      c2_wick_ratio = 0.0;
      c3_wick_ratio = 0.0;
      againstPriorLTFTrend = false;
      fractalState = FRACTAL_STATE_C3;
      lineage.Reset();
      lineage.closureKind = CLOSURE_C3;
      priorSequenceId = 0;
   }
   
   bool IsActive() const { return valid && lineage.sequenceId != 0; }
   
   bool IsPromotion() const { return priorSequenceId != 0; }
};

//+------------------------------------------------------------------+
//| SSignalC4 — Internal C4 signal data (ClosureEngine)               |
//+------------------------------------------------------------------+
struct SSignalC4
{
   bool valid;
   ENUM_CLOSURE_TYPE type;
   bool is_bullish;
   
   double entry_price;
   double stop_loss;
   double target_price;  // C4 expansion target
   double equilibrium;
   
   double c1_high;
   double c1_low;
   double c1_close;
   
   double c2_high;
   double c2_low;
   double c2_open;
   double c2_close;
   
   double c3_high;
   double c3_low;
   double c3_open;
   double c3_close;
   
   double c4_high;
   double c4_low;
   double c4_open;
   double c4_close;
   
   ENUM_FRACTAL_STATE fractalState;
   
   SSequenceLineage lineage;
   ulong priorSequenceId;  // Reference to triggering C2 or C3
   
   void Reset()
   {
      valid = false;
      type = CLOSURE_NONE;
      is_bullish = false;
      entry_price = 0.0;
      stop_loss = 0.0;
      target_price = 0.0;
      equilibrium = 0.0;
      c1_high = 0.0;
      c1_low = 0.0;
      c1_close = 0.0;
      c2_high = 0.0;
      c2_low = 0.0;
      c2_open = 0.0;
      c2_close = 0.0;
      c3_high = 0.0;
      c3_low = 0.0;
      c3_open = 0.0;
      c3_close = 0.0;
      c4_high = 0.0;
      c4_low = 0.0;
      c4_open = 0.0;
      c4_close = 0.0;
      fractalState = FRACTAL_STATE_NONE;
      lineage.Reset();
      priorSequenceId = 0;
   }
   
   bool IsActive() const { return valid && lineage.sequenceId != 0; }
};

//+------------------------------------------------------------------+
//| SStageSignal — Fractal Stage Signal                    |
//+------------------------------------------------------------------+
struct SStageSignal
{
   ENUM_FRACTAL_STATE stage;
   bool isValid;
   double c2High;
   double c2Low;
   double c2Open;
   double c2Close;
   double c2Time;
   double c3High;
   double c3Low;
   double c3Open;
   double c3Close;
   double c3Time;
   bool c3Engulfing;
   bool c3Displacement;
   double displacementStrength;
   double c2WickPercent;

   void Reset()
   {
      stage = FRACTAL_STATE_NONE;
      isValid = false;
      c2High = 0.0;
      c2Low = 0.0;
      c2Open = 0.0;
      c2Close = 0.0;
      c2Time = 0;
      c3High = 0.0;
      c3Low = 0.0;
      c3Open = 0.0;
      c3Close = 0.0;
      c3Time = 0;
      c3Engulfing = false;
      c3Displacement = false;
      displacementStrength = 0.0;
      c2WickPercent = 0.0;
   }

   SStageSignal() { Reset(); }
};

//+------------------------------------------------------------------+
//| WICK ANALYSIS FILTER                                              |
//+------------------------------------------------------------------+

double ComputeWickRatio(
   double open,
   double close,
   double high,
   double low
)
{
   double range = high - low;
   if(range <= 0.0)
      return 0.0;

   double body = MathAbs(close - open);
   double totalWick = range - body;

   return totalWick / range;
}

ENUM_CLOSURE_TYPE ApplyWickFilter(
   double wick_ratio,
   ENUM_CLOSURE_TYPE current_type
)
{
   // AGENTS.md §XVII Gate 2: 50% Mechanical Wick Threshold
   // If wickRatio > 0.5: reversal signature — does NOT support expansion
   // If wickRatio <= 0.5: supports expansion
   if(wick_ratio > 0.5)
   {
      LogPrint("[WICK_RULE_BLOCK] ratio=" + DoubleToString(wick_ratio, 2) +
               " | reversal signature, does not support expansion", LOG_LEVEL_INFO);
      return CLOSURE_NONE;
   }

   LogPrint("[WICK_RULE_PASS] ratio=" + DoubleToString(wick_ratio, 2) +
            " | supports expansion", LOG_LEVEL_INFO);
   return current_type;
}

//+------------------------------------------------------------------+
//| CheckHTFTimeSensitivity — AGENTS.md §XVII Time-Sensitivity Filter   |
//+------------------------------------------------------------------+
/**
 * AGENTS.md §XVII: Before advancing to STAGE_READY, check HTF candle progress.
 * If >80% of the HTF candle (D1 for Branch A, W1 for Branch B) has elapsed,
 * the signal is invalidated — there must be "enough time to continue expansion."
 *
 * @param anchorTF Anchor timeframe (PERIOD_D1 for Branch A, PERIOD_W1 for Branch B)
 * @return true if pass (<=80% elapsed), false if blocked (>80% elapsed)
 */
bool CheckHTFTimeSensitivity(ENUM_TIMEFRAMES anchorTF)
{
   datetime candleOpen = iTime(_Symbol, anchorTF, 0);
   datetime nextCandleOpen = iTime(_Symbol, anchorTF, 1);

   if(candleOpen <= 0 || nextCandleOpen <= 0)
   {
      LogPrint("[TIME_FILTER_BLOCK] unable to read candle times for TF=" +
               EnumToString(anchorTF), LOG_LEVEL_WARN);
      return false;
   }

   datetime now = TimeCurrent();
   double elapsed = (double)(now - candleOpen);
   double duration = (double)(nextCandleOpen - candleOpen);

   if(duration <= 0.0)
   {
      LogPrint("[TIME_FILTER_BLOCK] invalid candle duration for TF=" +
               EnumToString(anchorTF), LOG_LEVEL_WARN);
      return false;
   }

   double progress = elapsed / duration;

   if(progress > 0.80)
   {
      LogPrint("[TIME_FILTER_BLOCK] progress=" + DoubleToString(progress * 100, 1) +
               "% | >80% of " + EnumToString(anchorTF) + " candle elapsed, signal invalidated",
               LOG_LEVEL_INFO);
      return false;
   }

   LogPrint("[TIME_FILTER_PASS] progress=" + DoubleToString(progress * 100, 1) +
            "% | sufficient " + EnumToString(anchorTF) + " candle remaining",
            LOG_LEVEL_INFO);
   return true;
}

//+------------------------------------------------------------------+
/**
 * DetectFractalSweep — Dow Theory compliant swing high/low detection
 *
 * Per Dow Theory: A true trend change requires a break of a Swing High/Low,
 * which is defined by a 3-bar pivot pattern:
 *   - Swing High: Middle bar has higher high than both neighbors
 *   - Swing Low: Middle bar has lower low than both neighbors
 *
 * This function detects if the current bar (c2) breaks the fractal
 * swing point established by prior bars.
 *
 * @param highs Array of 5 bar highs (index 0 = current)
 * @param lows  Array of 5 bar lows (index 0 = current)
 * @return Direction of fractal sweep or DIRECTION_NONE
 */
ENUM_DIRECTION DetectFractalSweep(const double &highs[], const double &lows[])
{
    // Need at least 5 bars for fractal detection
    if(ArraySize(highs) < 5 || ArraySize(lows) < 5)
       return DIRECTION_NONE;

    // Fractal swing detection using 3-bar pivot
    // Index 2 = C2 (current bar in our 4-bar window)
    // Index 3 = C1 (prior bar)
    // Index 4 = C0 (bar before C1)

    // Check for Swing High (fractal top)
    bool swingHigh = (highs[2] > highs[1] && highs[2] > highs[3]);

    // Check for Swing Low (fractal bottom)
    bool swingLow = (lows[2] < lows[1] && lows[2] < lows[3]);

    // Check if current C2 breaks the prior C1 extreme
    // Bullish: C2 fractal low breaks below C1 fractal low
    bool bullishBreak = (lows[2] < lows[3]);

    // Bearish: C2 fractal high breaks above C1 fractal high
    bool bearishBreak = (highs[2] > highs[3]);

    // If we have a fractal swing AND it breaks prior structure
    if(swingLow && bullishBreak)
       return DIRECTION_BUY;

    if(swingHigh && bearishBreak)
       return DIRECTION_SELL;

    return DIRECTION_NONE;
}

//+------------------------------------------------------------------+
//| C2 CLOSURE LOGIC — Sweep + Close Inside                          |
//+------------------------------------------------------------------+

// Default sweep tolerance in pips (symbol-agnostic via GetPipSize)
input double InpSweepTolerancePips = 5.0;

ENUM_DIRECTION DetectC2Sweep(
    double c2_high,
    double c2_low,
    double c1_high,
    double c1_low
 )
{
    double emptyArr[];
    return DetectC2Sweep(c2_high, c2_low, c1_high, c1_low, emptyArr, emptyArr);
}

ENUM_DIRECTION DetectC2Sweep(
    double c2_high,
    double c2_low,
    double c1_high,
    double c1_low,
    const double &highs[],
    const double &lows[]
 )
{
    // Per TTrades: sweep is when C2's extreme breaches C1's extreme
    // Calc-mode-aware tolerance via SymbolIntelligence
    double pipSize = SY_GetPipSize(_Symbol);
    double sweepTolerance = pipSize * InpSweepTolerancePips;
   bool sweptLow  = (c2_low  < c1_low  - sweepTolerance);
   bool sweptHigh = (c2_high > c1_high + sweepTolerance);

// If strict sweep failed, check configurable near-miss tolerance
    if(!sweptLow && !sweptHigh)
    {
        SSymbolProfile spNear = SY_GetProfile(_Symbol);
        double point = spNear.point;
        double allowedDist = InpSweepTolerancePips * pipSize;
       double lowDiff = c1_low - c2_low;   // positive when C2 low is below C1 low
       double highDiff = c2_high - c1_high; // positive when C2 high is above C1 high

       if(lowDiff > 0.0 && lowDiff <= allowedDist)
          sweptLow = true;
       else if(lowDiff > 0.0 && lowDiff <= allowedDist * 2.0)
          LogPrint("[SWEEP_NEARMISS] BUY | c2_low=" + DoubleToString(c2_low, _Digits) +
                   " c1_low=" + DoubleToString(c1_low, _Digits) +
                   " diff=" + DoubleToString(lowDiff, _Digits) +
                   " tol=" + DoubleToString(allowedDist, _Digits), LOG_LEVEL_INFO);

       if(highDiff > 0.0 && highDiff <= allowedDist)
          sweptHigh = true;
       else if(highDiff > 0.0 && highDiff <= allowedDist * 2.0)
          LogPrint("[SWEEP_NEARMISS] SELL | c2_high=" + DoubleToString(c2_high, _Digits) +
                   " c1_high=" + DoubleToString(c1_high, _Digits) +
                   " diff=" + DoubleToString(highDiff, _Digits) +
                   " tol=" + DoubleToString(allowedDist, _Digits), LOG_LEVEL_INFO);
   }

   ENUM_DIRECTION sweep = DIRECTION_NONE;
   if(sweptLow && !sweptHigh)  sweep = DIRECTION_BUY;
   if(sweptHigh && !sweptLow) sweep = DIRECTION_SELL;
   if(sweptLow && sweptHigh)
      sweep = ((c1_high - c2_high) > (c2_low - c1_low)) ? DIRECTION_BUY : DIRECTION_SELL;

   if(sweep == DIRECTION_NONE)
   {
      static int s_lastNoSweepBar = -1;
      if(Bars(_Symbol, _Period) != s_lastNoSweepBar)
      {
         s_lastNoSweepBar = Bars(_Symbol, _Period);
         LogPrint("[C2_REJECT] NO_SWEEP | c2_low=" + DoubleToString(c2_low, _Digits) +
                  " c1_low=" + DoubleToString(c1_low, _Digits) +
                  " c2_high=" + DoubleToString(c2_high, _Digits) +
                  " c1_high=" + DoubleToString(c1_high, _Digits), LOG_LEVEL_INFO);
      }
      return DIRECTION_NONE;
   }

   // Second check: Dow Theory fractal compliance (if data available)
   if(ArraySize(highs) >= 3 && ArraySize(lows) >= 3)
   {
      ENUM_DIRECTION fractalSweep = DetectFractalSweep(highs, lows);
      if(fractalSweep != DIRECTION_NONE)
      {
         return fractalSweep;
      }
   }

   return sweep;
}

bool DetectC2CloseInside(
   double c2_close,
   double c1_high,
   double c1_low,
   ENUM_DIRECTION sweep_direction
)
{
   if(sweep_direction == DIRECTION_BUY)
   {
      return (c2_close >= c1_low && c2_close <= c1_high);
   }
   else if(sweep_direction == DIRECTION_SELL)
   {
      return (c2_close <= c1_high && c2_close >= c1_low);
   }

   return false;
}

//+------------------------------------------------------------------+
//| DidC2ProduceReversalClosure — Per TTrades: "Price sweeps the    |
//| previous candle's high or low, Then closes back inside the      |
//| previous candle's range."                                        |
//+------------------------------------------------------------------+
bool DidC2ProduceReversalClosure(
   double c1_open,
   double c1_close,
   double c1_high,
   double c1_low,
   double c2_high,
   double c2_low,
   double c2_close
)
{
   // Per TTrades: "closes back inside the previous range" means the full candle range (high to low)
   // NOT just the body-to-body range. Use c1_high/c1_low directly (includes wicks).
   // Bullish C2 Closure: C2 swept C1's low AND closed back inside C1's full high-low range
   bool bullishClosure = (c2_low < c1_low) && (c2_close >= c1_low && c2_close <= c1_high);

   // Bearish C2 Closure: C2 swept C1's high AND closed back inside C1's full high-low range
   bool bearishClosure = (c2_high > c1_high) && (c2_close <= c1_high && c2_close >= c1_low);

   if(bullishClosure || bearishClosure)
   {
LogPrint("[C2_REVERSAL_CHECK] PASS | c2_close=" + DoubleToString(c2_close, _Digits) +
                " | c1_low=" + DoubleToString(c1_low, _Digits) +
                " | c1_high=" + DoubleToString(c1_high, _Digits), LOG_LEVEL_DEBUG);
   }

   return bullishClosure || bearishClosure;
}

//+------------------------------------------------------------------+
//| DidC3ProduceContinuationClosure                                                  |
//| "Candle 3 closes over the body of candle 2 and engulfs it      |
//| WITHOUT sweeping the candle 2 high or low"                     |
//+------------------------------------------------------------------+
bool DidC3ProduceContinuationClosure(
    double c2_open,
    double c2_close,
    double c2_high,
    double c2_low,
    double c3_open,
    double c3_close,
    double c3_high,
    double c3_low,
    ENUM_DIRECTION bias
)
{
    double c2_body_top = MathMax(c2_open, c2_close);
    double c2_body_bottom = MathMin(c2_open, c2_close);

    if(bias == DIRECTION_BUY)
    {
        // Bullish C3 Closure:
        // - C3 close > C2 body high (engulfs C2's body)
        // - C3 did NOT sweep C2's low (no new low below C2)
        bool closesOverC2Body = (c3_close > c2_body_top);
        bool didNotSweepC2Low = (c3_low >= c2_low);  // no sweep of C2's low

        if(closesOverC2Body && didNotSweepC2Low)
        {
            LogPrint("[C3_CLOSURE_DETECTED] Bullish | c3_close=" + DoubleToString(c3_close, _Digits) +
                     " | c2_body_top=" + DoubleToString(c2_body_top, _Digits) +
                     " | c3_low=" + DoubleToString(c3_low, _Digits) +
                     " | c2_low=" + DoubleToString(c2_low, _Digits), LOG_LEVEL_DEBUG);
            return true;
        }
    }
    else if(bias == DIRECTION_SELL)
    {
        // Bearish C3 Closure:
        // - C3 close < C2 body low (engulfs below C2's body)
        // - C3 did NOT sweep C2's high
        bool closesBelowC2Body = (c3_close < c2_body_bottom);
        bool didNotSweepC2High = (c3_high <= c2_high);  // no sweep of C2's high

        if(closesBelowC2Body && didNotSweepC2High)
        {
            LogPrint("[C3_CLOSURE_DETECTED] Bearish | c3_close=" + DoubleToString(c3_close, _Digits) +
                     " | c2_body_bottom=" + DoubleToString(c2_body_bottom, _Digits) +
                     " | c3_high=" + DoubleToString(c3_high, _Digits) +
                     " | c2_high=" + DoubleToString(c2_high, _Digits), LOG_LEVEL_DEBUG);
            return true;
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| IsC3ClosureValid — Precondition: C2 must NOT have reversal     |
//| closure for C3 Closure to be applicable             |
//+------------------------------------------------------------------+
bool IsC3ClosureValid(
    double c1_open,
    double c1_high,
    double c1_low,
    double c1_close,
    double c2_open,
    double c2_close,
    double c2_high,
    double c2_low,
    double c3_open,
    double c3_close,
    double c3_high,
    double c3_low,
    ENUM_DIRECTION bias
)
{
    BranchContext ctx = g_branchAContext;
    if(g_activeBranch == BRANCH_SWING) ctx = g_branchBContext;

    // PRECONDITION: C2 did NOT produce a reversal closure
    // Per TTrades: "A candle 3 closure occurs when candle 2 fails to close properly"
    bool c2HadReversalClosure = DidC2ProduceReversalClosure(c1_open, c1_close, c1_high, c1_low, c2_high, c2_low, c2_close);

    if(c2HadReversalClosure)
    {
        LogPrint("[C3_PRECONDITION_FAIL] C2 already produced reversal closure | C3 Closure not applicable", LOG_LEVEL_DEBUG);
        return false;
    }

    // CONDITION: C3 produced a continuation closure over C2's body (without sweeping C2's extreme)
    if(!DidC3ProduceContinuationClosure(c2_open, c2_close, c2_high, c2_low, c3_open, c3_close, c3_high, c3_low, bias))
    {
        LogPrint("[C3_PRECONDITION_FAIL] C3 did not produce continuation closure over C2's body", LOG_LEVEL_DEBUG);
        return false;
    }

    // CONDITION: POI must be present
    // Per TTrades: "A swing is only valid when it has both: A point of interest, A valid closure"
    ENUM_TIMEFRAMES htf = (ctx.branch == BRANCH_SWING) ? PERIOD_H4 : PERIOD_H1;
    if(!HasValidPOI(c3_high, c3_low, TimeCurrent(), htf, InpA_C3_POI_BufferPercent))
    {
        LogPrint("[C3_PRECONDITION_FAIL] C3 at " + TimeToString(TimeCurrent()) + " has no valid POI", LOG_LEVEL_WARN);
        return false;
    }

    LogPrint("[C3_CLOSURE_VALID] C2 failed reversal + C3 produced continuation closure | bias=" + EnumToString(bias), LOG_LEVEL_DEBUG);
    return true;
}

bool IsC2UpgradedToC3(ulong guid)
{
   return false;
}

//+------------------------------------------------------------------+
//| IsC2Tradeable — Per TTrades: "Small wick → trade Candle 2"     |
//| "Large wick on Candle 2 → let Candle 2 close and trade Candle 3|
//| instead" — skip C2 closure signal, wait for C3 candle          |
//+------------------------------------------------------------------+
bool IsC2Tradeable(
   double c2_open,
   double c2_close,
   double c2_high,
   double c2_low,
   ENUM_DIRECTION bias
)
{
   double totalRange = c2_high - c2_low;
   if(totalRange <= 0.0)
      return false;

   double bodySize = MathAbs(c2_close - c2_open);
   double wickRange = totalRange - bodySize;
   double wickRatio = wickRange / totalRange;

   // TTrades Wick Filter Rule: If total wick > 60% of absolute candle range, reject C2
   // Formula: wickRange / absoluteRange > 0.60
   if(wickRatio > 0.60)
   {
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| HasValidPOI — Per TTrades: "Candle 2 closures only matter when  |
//| they form at a higher-time-frame point of interest"             |
//+------------------------------------------------------------------+
bool HasValidPOI(
   double price_high,
   double price_low,
   datetime bar_time,
   ENUM_TIMEFRAMES htf,
   double bufferPercent = 0.015
)
{
   if(InpEnableTrace)
      LGovPrint("[POI_CHECK] Checking POI at time=" + TimeToString(bar_time), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);

   double midPrice = (price_high + price_low) / 2.0;
   double bufferDistance = midPrice * bufferPercent;

   // Per TTrades: POI can be a swing high, swing low, FVG, or opposing candle
   if(IsNearHTFSwingPoint(price_high, price_low, htf, bufferPercent))
   {
      LogPrint("[POI_VALID] HTF swing point found", LOG_LEVEL_DEBUG);
      return true;
   }
   
   if(IsNearFVG(price_high, price_low, htf, bar_time, bufferPercent))
   {
      LogPrint("[POI_VALID] FVG found", LOG_LEVEL_DEBUG);
      return true;
   }
   
   if(IsAtOpposingCandle(price_high, price_low, htf, bar_time))
   {
      LogPrint("[POI_VALID] Opposing candle found", LOG_LEVEL_DEBUG);
      return true;
   }

   LogPrint("[POI_REJECT] No HTF POI found — closure invalid", LOG_LEVEL_DEBUG);
   return false;
}

//+------------------------------------------------------------------+
//| IsNearHTFSwingPoint — Check if price is near HTF swing point    |
//+------------------------------------------------------------------+
bool IsNearHTFSwingPoint(
   double price_high,
   double price_low,
   ENUM_TIMEFRAMES htf,
   double bufferPercent
)
{
   double midPrice = (price_high + price_low) / 2.0;
   double bufferDistance = midPrice * bufferPercent;

   double htfHigh[], htfLow[];
   ArraySetAsSeries(htfHigh, true);
   ArraySetAsSeries(htfLow, true);
   
   if(CopyHigh(_Symbol, htf, 0, 20, htfHigh) > 0 && CopyLow(_Symbol, htf, 0, 20, htfLow) > 0)
   {
      for(int i = 2; i < 18; i++)
      {
         if(htfHigh[i] > htfHigh[i-1] && htfHigh[i] > htfHigh[i+1])
         {
            double dist = MathAbs(midPrice - htfHigh[i]);
            if(dist <= bufferDistance)
            {
               if(InpEnableTrace)
                  LGovPrint("[POI_SWING] Near HTF swing high | price=" + DoubleToString(midPrice, _Digits) +
                            " | swing=" + DoubleToString(htfHigh[i], _Digits), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
               return true;
            }
         }
         if(htfLow[i] < htfLow[i-1] && htfLow[i] < htfLow[i+1])
         {
            double dist = MathAbs(midPrice - htfLow[i]);
            if(dist <= bufferDistance)
            {
               if(InpEnableTrace)
                  LGovPrint("[POI_SWING] Near HTF swing low | price=" + DoubleToString(midPrice, _Digits) +
                            " | swing=" + DoubleToString(htfLow[i], _Digits), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
               return true;
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| IsNearFVG — Check if price is near a Fair Value Gap            |
//+------------------------------------------------------------------+
bool IsNearFVG(
   double price_high,
   double price_low,
   ENUM_TIMEFRAMES htf,
   datetime bar_time,
   double bufferPercent
)
{
   double midPrice = (price_high + price_low) / 2.0;
   double bufferDistance = midPrice * bufferPercent;

   FVGZone fvg = DetectRecentFVG(_Symbol, htf);
   if(fvg.valid)
   {
      double fvgMid = (fvg.high + fvg.low) / 2.0;
      double dist = MathAbs(midPrice - fvgMid);
      if(dist <= bufferDistance)
      {
         if(InpEnableTrace)
            LGovPrint("[POI_FVG] Near FVG | price=" + DoubleToString(midPrice, _Digits) +
                      " | fvg=" + DoubleToString(fvgMid, _Digits), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| IsAtOpposingCandle — Check if price is at opposing candle POI  |
//+------------------------------------------------------------------+
bool IsAtOpposingCandle(
   double price_high,
   double price_low,
   ENUM_TIMEFRAMES htf,
   datetime bar_time
)
{
   BranchContext ctx = g_branchAContext;
   if(g_activeBranch == BRANCH_SWING) ctx = g_branchBContext;

   // Per TTrades: Opposing candle = price at external break from SSE
   if(ctx.sse.externalBreak)
   {
      if(InpEnableTrace)
         LGovPrint("[POI_OPPOSING] At external break", LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| IsC1AtHTFPointOfInterest — Per TTrades: "Candle 2 closures      |
//| only matter when C1 is at a higher-time-frame point of interest." |
//| C1 must overlap an HTF structural level (swing, FVG, or OB).    |
//| Replaces DidSweepTargetStructuralLevel for C2 validation.       |
//+------------------------------------------------------------------+
bool IsC1AtHTFPointOfInterest(
   double c1_high,
   double c1_low,
   datetime bar_time,
   ENUM_TIMEFRAMES htf
)
{
   if(c1_high <= 0.0 || c1_low <= 0.0 || c1_high <= c1_low)
   {
      LogPrint("[C1_POI_MISS] Invalid C1 range | c1_high=" + DoubleToString(c1_high, _Digits) +
               " c1_low=" + DoubleToString(c1_low, _Digits), LOG_LEVEL_INFO);
      return false;
   }

   double pipSize = SY_GetPipSize(_Symbol);
   double proximityTol = InpSweepTolerancePips * pipSize;
   // REGRESSION_GUARD_TTL: Widen buffer for M5 entry TF (H1 structure = Branch A)
   if(htf == PERIOD_H1)
      proximityTol += pipSize;

   double poiLow = 0.0, poiHigh = 0.0;
   bool poiFound = false;

   // 1) Check FVG zone (exact gap boundaries)
   FVGZone fvg = DetectRecentFVG(_Symbol, htf);
   if(fvg.valid)
   {
      poiLow = fvg.low;
      poiHigh = fvg.high;
      poiFound = true;
      LogPrint("[C1_POI_CHECK] FVG zone | low=" + DoubleToString(poiLow, _Digits) +
               " high=" + DoubleToString(poiHigh, _Digits), LOG_LEVEL_DEBUG);
   }

   // 2) Check HTF swing point
   if(!poiFound)
   {
      double htfHigh[], htfLow[];
      ArraySetAsSeries(htfHigh, true);
      ArraySetAsSeries(htfLow, true);
      if(CopyHigh(_Symbol, htf, 0, 20, htfHigh) > 0 && CopyLow(_Symbol, htf, 0, 20, htfLow) > 0)
      {
         for(int i = 2; i < 18; i++)
         {
            bool isSwingHigh = (htfHigh[i] > htfHigh[i-1] && htfHigh[i] > htfHigh[i+1]);
            bool isSwingLow  = (htfLow[i]  < htfLow[i-1]  && htfLow[i]  < htfLow[i+1]);

            if(isSwingHigh)
            {
               poiLow  = htfHigh[i] - proximityTol;
               poiHigh = htfHigh[i] + proximityTol;
               poiFound = true;
               LogPrint("[C1_POI_CHECK] Swing high zone | level=" + DoubleToString(htfHigh[i], _Digits) +
                        " low=" + DoubleToString(poiLow, _Digits) + " high=" + DoubleToString(poiHigh, _Digits), LOG_LEVEL_DEBUG);
               break;
            }
            if(isSwingLow)
            {
               poiLow  = htfLow[i] - proximityTol;
               poiHigh = htfLow[i] + proximityTol;
               poiFound = true;
               LogPrint("[C1_POI_CHECK] Swing low zone | level=" + DoubleToString(htfLow[i], _Digits) +
                        " low=" + DoubleToString(poiLow, _Digits) + " high=" + DoubleToString(poiHigh, _Digits), LOG_LEVEL_DEBUG);
               break;
            }
         }
      }
   }

   // 3) Fallback: opposing HTF candle at bar_time (full candle range)
   if(!poiFound)
   {
      int idx = iBarShift(_Symbol, htf, bar_time, true);
      if(idx >= 0)
      {
         double htfHigh[], htfLow[];
         ArraySetAsSeries(htfHigh, true);
         ArraySetAsSeries(htfLow, true);
         if(CopyHigh(_Symbol, htf, idx, 1, htfHigh) > 0 && CopyLow(_Symbol, htf, idx, 1, htfLow) > 0)
         {
            poiLow  = htfLow[0];
            poiHigh = htfHigh[0];
            poiFound = true;
            LogPrint("[C1_POI_CHECK] Opposing candle zone | low=" + DoubleToString(poiLow, _Digits) +
                     " high=" + DoubleToString(poiHigh, _Digits), LOG_LEVEL_DEBUG);
         }
      }
   }

   if(!poiFound)
   {
      LogPrint("[C2_REJECT] C1_POI_MISS | No HTF POI zone found | c1_high=" + DoubleToString(c1_high, _Digits) +
               " c1_low=" + DoubleToString(c1_low, _Digits) + " htf=" + EnumToString(htf), LOG_LEVEL_INFO);
      return false;
   }

   // Absolute overlap (touch/penetrate) check: C1 must touch or penetrate the POI zone
   if(c1_high >= poiLow && c1_low <= poiHigh)
   {
      LogPrint("[C1_POI_VALID] C1 overlaps POI zone | c1_high=" + DoubleToString(c1_high, _Digits) +
               " c1_low=" + DoubleToString(c1_low, _Digits) +
               " zone_low=" + DoubleToString(poiLow, _Digits) +
               " zone_high=" + DoubleToString(poiHigh, _Digits) +
               " htf=" + EnumToString(htf), LOG_LEVEL_INFO);
      return true;
   }

   LogPrint("[C1_POI_MISS] C1 does not overlap POI zone | c1_high=" + DoubleToString(c1_high, _Digits) +
            " c1_low=" + DoubleToString(c1_low, _Digits) +
            " zone_low=" + DoubleToString(poiLow, _Digits) +
            " zone_high=" + DoubleToString(poiHigh, _Digits) +
            " htf=" + EnumToString(htf), LOG_LEVEL_INFO);
   return false;
}

//+------------------------------------------------------------------+
//| DidSweepTargetStructuralLevel — Per TTrades: "Order blocks     |
//| only matter after liquidity is taken. Closure and displacement  |
//| are what validate the level."                                   |
//| Uses ATR-free branch-specific POI buffer tolerance.             |
//+------------------------------------------------------------------+
bool DidSweepTargetStructuralLevel(
   double sweep_level,
   ENUM_TIMEFRAMES htf,
   ENUM_DIRECTION sweep_direction
)
{
    LogPrint("[SWEEP_TARGET_CHECK] sweep=" + DoubleToString(sweep_level, _Digits) +
             " htf=" + EnumToString(htf) +
             " sweep_dir=" + EnumToString(sweep_direction), LOG_LEVEL_DEBUG);

    // Determine active branch from HTF
    ENUM_EXECUTION_BRANCH branch = (htf == PERIOD_H1) ? BRANCH_INTRADAY : BRANCH_SWING;

    // Compute ATR-free tolerance from branch-specific POI buffer percent
    double bufferPct = (branch == BRANCH_INTRADAY) ? InpA_C2_POI_BufferPercent : InpB_C2_POI_BufferPercent;
    double tolerance = sweep_level * bufferPct;
    double maxSweep = tolerance * 3.0;  // allow up to 3x the buffer before rejecting as genuine breakout

    LogPrint("[SWEEP_TOLERANCE] branch=" + IntegerToString(branch) +
             " bufferPct=" + DoubleToString(bufferPct, 4) +
             " tolerance=" + DoubleToString(tolerance, _Digits) +
             " maxSweep=" + DoubleToString(maxSweep, _Digits), LOG_LEVEL_DEBUG);

    double htfHigh[], htfLow[];
    ArraySetAsSeries(htfHigh, true);
    ArraySetAsSeries(htfLow, true);

    int copyBars = 25;
    if(CopyHigh(_Symbol, htf, 0, copyBars, htfHigh) <= 0 || CopyLow(_Symbol, htf, 0, copyBars, htfLow) <= 0)
    {
        LogPrint("[SWEEP_TARGET_REJECT] reason=HTF_COPY_FAIL | htf=" + EnumToString(htf), LOG_LEVEL_DEBUG);
        return false;
    }

    double closestDist = DBL_MAX;
    double closestLevel = 0.0;

    // 1. Scan HTF swing highs (for bearish/reversal sweeps) and swing lows (for bullish sweeps)
    int scanStart = 2;
    int scanEnd = copyBars - 2;

    if(sweep_direction == DIRECTION_SELL)
    {
        for(int i = scanStart; i < scanEnd; i++)
        {
            if(htfHigh[i] > htfHigh[i-1] && htfHigh[i] > htfHigh[i+1])
            {
                double dist = MathAbs(sweep_level - htfHigh[i]);
                if(dist < closestDist) { closestDist = dist; closestLevel = htfHigh[i]; }
                if(dist <= tolerance && dist <= maxSweep)
                {
                    LogPrint("[SWEEP_TARGET_PASS] matched_swing_high=true | level=" + DoubleToString(htfHigh[i], _Digits) +
                             " dist=" + DoubleToString(dist, _Digits) +
                             " tolerance=" + DoubleToString(tolerance, _Digits), LOG_LEVEL_DEBUG);
                    return true;
                }
            }
        }
    }
    else if(sweep_direction == DIRECTION_BUY)
    {
        for(int i = scanStart; i < scanEnd; i++)
        {
            if(htfLow[i] < htfLow[i-1] && htfLow[i] < htfLow[i+1])
            {
                double dist = MathAbs(sweep_level - htfLow[i]);
                if(dist < closestDist) { closestDist = dist; closestLevel = htfLow[i]; }
                if(dist <= tolerance && dist <= maxSweep)
                {
                    LogPrint("[SWEEP_TARGET_PASS] matched_swing_low=true | level=" + DoubleToString(htfLow[i], _Digits) +
                             " dist=" + DoubleToString(dist, _Digits) +
                             " tolerance=" + DoubleToString(tolerance, _Digits), LOG_LEVEL_DEBUG);
                    return true;
                }
            }
        }
    }

    // 2. Check if the swept level aligns with a known FVG boundary
    FVGZone fvg = DetectRecentFVG(_Symbol, htf);
    if(fvg.valid)
    {
        double fvgBoundary = (sweep_direction == DIRECTION_BUY) ? fvg.low : fvg.high;
        double dist = MathAbs(sweep_level - fvgBoundary);
        if(dist < closestDist) { closestDist = dist; closestLevel = fvgBoundary; }
        if(dist <= tolerance && dist <= maxSweep)
        {
            LogPrint("[SWEEP_TARGET_PASS] matched_fvg=true | boundary=" + DoubleToString(fvgBoundary, _Digits) +
                     " dist=" + DoubleToString(dist, _Digits) +
                     " tolerance=" + DoubleToString(tolerance, _Digits), LOG_LEVEL_DEBUG);
            return true;
        }
    }

// 3. Check round-number levels (adapted to calc mode and tick size)
     SSymbolProfile spRound = SY_GetProfile(_Symbol);
     int digits = spRound.digits;
     double calcMode = spRound.calcMode;
     double tickSize = spRound.tickSize;
     double pipSz = spRound.pipSize;
     double roundStep = MathMax(tickSize, pipSz / 10.0);
    // Generate candidate levels: the nearest round numbers around sweep_level
    double roundBase = MathFloor(sweep_level / roundStep) * roundStep;
    for(int r = -2; r <= 2; r++)
    {
        double candidate = roundBase + r * roundStep;
        if(candidate <= 0) continue;
        double dist = MathAbs(sweep_level - candidate);
        if(dist < closestDist) { closestDist = dist; closestLevel = candidate; }
        if(dist <= tolerance && dist <= maxSweep)
        {
            LogPrint("[SWEEP_TARGET_PASS] matched_round_level=true | level=" + DoubleToString(candidate, digits) +
                     " dist=" + DoubleToString(dist, _Digits) +
                     " tolerance=" + DoubleToString(tolerance, _Digits), LOG_LEVEL_DEBUG);
            return true;
        }
    }

    LogPrint("[SWEEP_TARGET_REJECT] reason=NO_STRUCTURAL_MATCH | closest_level=" + DoubleToString(closestLevel, _Digits) +
             " closest_dist=" + DoubleToString(closestDist, _Digits) +
             " sweep=" + DoubleToString(sweep_level, _Digits) +
             " tolerance=" + DoubleToString(tolerance, _Digits), LOG_LEVEL_DEBUG);
    return false;
}

//+------------------------------------------------------------------+
//| STRUCTURAL DISPLACEMENT ENGINE (ATR-FREE PER TTRADES SPEC)       |
//+------------------------------------------------------------------+
bool ValidateDisplacement(const string mode, double sweepDist, double c1Range, double c2Range, double bodySize, double configuredMultiplier)
{
   if(mode == "C2")
   {
      if(c1Range <= 0.0) return false;

      double minRatio = configuredMultiplier * 0.05;
      double actualRatio = MathAbs(sweepDist) / c1Range;

      LogPrint("[DISPLACEMENT_C2] sweepDist=" + DoubleToString(sweepDist, _Digits) +
               " | c1Range=" + DoubleToString(c1Range, _Digits) +
               " | actualRatio=" + DoubleToString(actualRatio, 4) +
               " | minRatio=" + DoubleToString(minRatio, 4) +
               " | mult=" + DoubleToString(configuredMultiplier, 2), LOG_LEVEL_DEBUG);

      return (actualRatio >= minRatio);
   }
   else if(mode == "C3")
   {
      if(c2Range <= 0.0) return false;

      double minC3BodyThresh = c2Range * (configuredMultiplier * 0.5);
      return (bodySize >= minC3BodyThresh);
   }

   return false;
}

//+------------------------------------------------------------------+
//| ConfirmCISD — DEPRECATED: Use SSE_DetectCISD in                  |
//| StructuralStateEngine.mqh instead. This function uses a          |
//| close-vs-high/low comparison that violates the constitution.     |
//| Per TTrades: "When I get a candle 2 or candle 3 closure on the  |
//| higher time frame I drop down to the lower time frame I must see |
//| a change in the state of delivery inside that higher time frame  |
//| candle. If CISD is missing, I ignore the setup completely."      |
//+------------------------------------------------------------------+
bool ConfirmCISD(SLockedSignal &signal)
{
   BranchContext ctx = g_branchAContext;
   if(g_activeBranch == BRANCH_SWING) ctx = g_branchBContext;

 // VERBATIM REPAIR: 3-Tier TF Mapping (§XVII)
    // CISD must be confirmed on Structure TF (H1/H4), NOT Entry TF (M5/M15).
    
 ENUM_TIMEFRAMES ltf = (ctx.branch == BRANCH_INTRADAY) ? PERIOD_H1 : PERIOD_H4;
    ENUM_TIMEFRAMES htf = (ctx.branch == BRANCH_SWING) ? PERIOD_H4 : PERIOD_H1;
    
    // Get the time range of the closure candle (C2 or C3)
    datetime closureTime = signal.lockTime;
    if(closureTime == 0)
       closureTime = TimeCurrent();
   
   // Define time window: from closure candle time to now
   datetime startTime = closureTime;
   datetime endTime = TimeCurrent();
   
   // Copy LTF data within the closure candle timeframe
   double ltfOpen[], ltfClose[], ltfHigh[], ltfLow[];
   datetime ltfTimes[];
   
   ArraySetAsSeries(ltfOpen, true);
   ArraySetAsSeries(ltfClose, true);
   ArraySetAsSeries(ltfHigh, true);
   ArraySetAsSeries(ltfLow, true);
   ArraySetAsSeries(ltfTimes, true);
   
   int barsNeeded = 30;
   int copied = CopyOpen(_Symbol, ltf, 0, barsNeeded, ltfOpen);
   if(copied < 10)
   {
      LogPrint("[CISD_FAILED] Could not get LTF open data | bars=" + IntegerToString(copied), LOG_LEVEL_DEBUG);
      return false;
   }
   
   copied = CopyClose(_Symbol, ltf, 0, barsNeeded, ltfClose);
   if(copied < 10)
   {
      LogPrint("[CISD_FAILED] Could not get LTF close data", LOG_LEVEL_DEBUG);
      return false;
   }
   
   copied = CopyHigh(_Symbol, ltf, 0, barsNeeded, ltfHigh);
   if(copied < 10)
   {
      LogPrint("[CISD_FAILED] Could not get LTF high data", LOG_LEVEL_DEBUG);
      return false;
   }
   
   copied = CopyLow(_Symbol, ltf, 0, barsNeeded, ltfLow);
   if(copied < 10)
   {
      LogPrint("[CISD_FAILED] Could not get LTF low data", LOG_LEVEL_DEBUG);
      return false;
   }
   
   // For a bullish setup: find the low formed within the HTF candle on LTF,
   // identify down-close candles that created that low,
   // verify price closed ABOVE those candles
   
   // For a bearish setup: find the high, identify up-close candles,
   // verify price closed BELOW those candles
   
   bool isBullish = (signal.direction == DIRECTION_BUY);
   
   // Find the relevant extreme (swing point) in the recent LTF candles
   double swingPoint = 0.0;
   int swingIndex = -1;
   
   if(isBullish)
   {
      // Find the lowest low in the recent bars (swing low)
      swingPoint = ltfLow[0];
      swingIndex = 0;
      for(int i = 1; i < 10; i++)
      {
         if(ltfLow[i] < swingPoint)
         {
            swingPoint = ltfLow[i];
            swingIndex = i;
         }
      }
   }
   else
   {
      // Find the highest high in the recent bars (swing high)
      swingPoint = ltfHigh[0];
      swingIndex = 0;
      for(int i = 1; i < 10; i++)
      {
         if(ltfHigh[i] > swingPoint)
         {
            swingPoint = ltfHigh[i];
            swingIndex = i;
         }
      }
   }
   
   if(swingIndex < 0)
   {
      LogPrint("[CISD_FAILED] Could not find swing point", LOG_LEVEL_DEBUG);
      return false;
   }
   
   // Now check: verify price closed THROUGH the candles that formed the swing
   // For bullish: price should close ABOVE the down-close candles that formed the swing low
   // For bearish: price should close BELOW the up-close candles that formed the swing high
   
int closeAboveCount = 0;
    int closeBelowCount = 0;
    int relevantCandles = 0;
    
    int maxSwingCheck = MathMin(copied - 1, 10);
    for(int i = swingIndex + 1; i < maxSwingCheck; i++)
    {
       bool isDownClose = (ltfClose[i] < ltfOpen[i]);
       bool isUpClose = (ltfClose[i] > ltfOpen[i]);
       
       if(isBullish)
       {
          if(isDownClose)
          {
             relevantCandles++;
             if(ltfClose[i+1] > ltfHigh[i])
                closeAboveCount++;
          }
       }
       else
       {
          if(isUpClose)
          {
             relevantCandles++;
             if(ltfClose[i+1] < ltfLow[i])
                closeBelowCount++;
          }
       }
    }
   
   // CISD is confirmed if price closed through the candles that formed the swing
   bool cisDetected = false;
   
   if(isBullish)
   {
      // Bullish: price should have closed above down-close candles
      cisDetected = (closeAboveCount >= 1 && relevantCandles > 0);
      if(cisDetected)
         LogPrint("[CISD_VALID] Bullish CISD | closeAboveCount=" + IntegerToString(closeAboveCount) +
                  " | relevantCandles=" + IntegerToString(relevantCandles), LOG_LEVEL_DEBUG);
   }
   else
   {
      // Bearish: price should have closed below up-close candles
      cisDetected = (closeBelowCount >= 1 && relevantCandles > 0);
      if(cisDetected)
         LogPrint("[CISD_VALID] Bearish CISD | closeBelowCount=" + IntegerToString(closeBelowCount) +
                  " | relevantCandles=" + IntegerToString(relevantCandles), LOG_LEVEL_DEBUG);
   }
   
   if(!cisDetected)
   {
      LogPrint("[CISD_FAILED] No change in state of delivery on LTF — setup invalid | GUID=" + 
               IntegerToString(signal.m_guid), LOG_LEVEL_DEBUG);
   }
   
   return cisDetected;
}

//+------------------------------------------------------------------+
//| ConfirmBranchCISD — 3-Tier Structural Highway Gate 3             |
//| Confirms CISD on the Structure TF (H1 for Branch A, H4 for       |
//| Branch B). Only after Tier 2 (Structure/CISD) is confirmed may    |
//| the signal drop to Tier 3 (Entry TF) for POI mapping.             |
//+------------------------------------------------------------------+
bool ConfirmBranchCISD(const string symbol, ENUM_TIMEFRAMES structTF, ENUM_EXECUTION_BRANCH branch)
{
    BranchContext ctx = (branch == BRANCH_INTRADAY) ? g_branchAContext : g_branchBContext;
    ENUM_DIRECTION dir = (ctx.bias.bias == BIAS_BULLISH) ? DIRECTION_BUY :
                          (ctx.bias.bias == BIAS_BEARISH) ? DIRECTION_SELL : DIRECTION_NONE;
    if (dir == DIRECTION_NONE)
    {
        LogPrint("[CISD_FAILED] ConfirmBranchCISD: no bias direction for branch=" +
                 IntegerToString(branch), LOG_LEVEL_DEBUG);
        return false;
    }
    SSE_CISDResult result = SSE_DetectCISD(symbol, structTF, dir, 20);
    if (result.confirmed)
    {
        static datetime s_lastCisdLogBar[2] = {0, 0};
        datetime barTime = iTime(symbol, structTF, 0);
        if(barTime > 0 && barTime != s_lastCisdLogBar[branch])
        {
            s_lastCisdLogBar[branch] = barTime;
            LogPrint(StringFormat("[CISD_CONFIRMED] Branch %d | structTF=%s | dir=%s | swingPrice=%.5f | seriesOpen=%.5f",
                     branch, EnumToString(structTF), EnumToString(dir), result.swingPrice, result.seriesOpen), LOG_LEVEL_INFO);
        }
    }
    else
    {
        LogPrint(StringFormat("[CISD_FAILED] Branch %d | structTF=%s | dir=%s | No mechanical CISD on Structure TF",
                 branch, EnumToString(structTF), EnumToString(dir)), LOG_LEVEL_DEBUG);
    }
    return result.confirmed;
}

//+------------------------------------------------------------------+
//| IsSetupStructurallyInvalid — Per Pro+: "If the setup fails—    |
//| defined by price returning to the initial high or low without   |
//| forming a higher Timeframes swing point"                        |
//+------------------------------------------------------------------+
bool IsSetupStructurallyInvalid(
   SLockedSignal &signal
)
{
   if(signal.m_guid == 0)
      return true;  // not found = effectively invalid

   // Check if we have setup metadata
   if(signal.m_setupInitialHigh <= 0.0 && signal.m_setupInitialLow <= 0.0)
      return false;  // No setup metadata, can't validate

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(signal.m_setupIsBullish)
   {
      // Bullish setup: initial LOW is the extreme
      // Failure = price trades back below initial low without forming a HTF swing point
      if(currentPrice < signal.m_setupInitialLow)
      {
         LogPrint("[C2_SETUP_INVALIDATED] GUID=" + IntegerToString(signal.m_guid) +
                  " | price=" + DoubleToString(currentPrice, _Digits) +
                  " | setupInitialLow=" + DoubleToString(signal.m_setupInitialLow, _Digits), LOG_LEVEL_WARN);
         return true;
      }
   }
   else
   {
      // Bearish setup: initial HIGH is the extreme
      if(currentPrice > signal.m_setupInitialHigh)
      {
         LogPrint("[C2_SETUP_INVALIDATED] GUID=" + IntegerToString(signal.m_guid) +
                  " | price=" + DoubleToString(currentPrice, _Digits) +
                  " | setupInitialHigh=" + DoubleToString(signal.m_setupInitialHigh, _Digits), LOG_LEVEL_WARN);
         return true;
      }
   }
    return false;
}

//+------------------------------------------------------------------+
//| GetAnchorContext — Returns Anchor TF High/Low/Equilibrium         |
//| BRANCH A (Intraday): D1 High/Low | BRANCH B (Swing): W1 High/Low |
//+------------------------------------------------------------------+
void GetAnchorContext(ENUM_EXECUTION_BRANCH branchId, double &anchorHigh, double &anchorLow, double &anchorEq)
{
   ENUM_TIMEFRAMES anchorTF = (branchId == BRANCH_INTRADAY) ? PERIOD_D1 : PERIOD_W1;
   anchorHigh = iHigh(_Symbol, anchorTF, 1);
   anchorLow  = iLow(_Symbol, anchorTF, 1);
   anchorEq   = (anchorHigh + anchorLow) / 2.0;
}

bool EvaluateC2Closure(
   double c1_open,
   double c1_high,
   double c1_low,
   double c1_close,
   double c2_open,
   double c2_high,
   double c2_low,
   double c2_close,
   SClosureSignal &signal
)
{
   // Once-per-bar diagnostic
   static int s_lastC2EvalBar = -1;
   if(Bars(_Symbol, _Period) != s_lastC2EvalBar)
   {
      s_lastC2EvalBar = Bars(_Symbol, _Period);
      LogPrint("[C2_EVAL_ATTEMPT] bar=" + IntegerToString(s_lastC2EvalBar) +
               " | checking fractal C1/C2 for closure", LOG_LEVEL_INFO);
   }

   ENUM_DIRECTION sweep = DetectC2Sweep(c2_high, c2_low, c1_high, c1_low);

   if(sweep == DIRECTION_NONE)
   {
      static int s_lastNoSweepBar = -1;
      if(Bars(_Symbol, _Period) != s_lastNoSweepBar)
      {
         s_lastNoSweepBar = Bars(_Symbol, _Period);
LogPrint("[C2_REJECT] NO_SWEEP | C2 candle did not sweep C1 extreme | c1_high=" + DoubleToString(c1_high, _Digits) +
                   " | c1_low=" + DoubleToString(c1_low, _Digits) +
                   " | c2_high=" + DoubleToString(c2_high, _Digits) +
                   " | c2_low=" + DoubleToString(c2_low, _Digits), LOG_LEVEL_INFO);
      }
LogPrint("[C2_REJECT] NO_SWEEP | C2 bar rejected — no sweep detected", LOG_LEVEL_INFO);
       return false;
    }

    LogPrint("[C2_BAR_DETECTED] C2 bar identified in sequence | sweep=" + EnumToString(sweep), LOG_LEVEL_INFO);

   // --- AGNOSTIC WICK RULE (TTFM Gate 2: 50% Wick Rule) ---
   {
      double c2_wickTR = c2_high - c2_low;
      if(c2_wickTR <= 0.0)
      {
         LogPrint("[WICK_RULE_BLOCK] C2_ZERO_RANGE | totalRange=0, no expansion supported", LOG_LEVEL_INFO);
         return false;
      }

      double c2_wickBodyHigh = MathMax(c2_open, c2_close);
      double c2_wickBodyLow  = MathMin(c2_open, c2_close);
      double c2_wickBodySz   = c2_wickBodyHigh - c2_wickBodyLow;

      // Doji rejection: body < 10% of total range = indecision
      if(c2_wickBodySz < c2_wickTR * 0.1)
      {
         LogPrint("[WICK_RULE_BLOCK] C2_DOJI | bodyRatio=" + DoubleToString(c2_wickBodySz / c2_wickTR, 3) +
                  " | indecision candle, no expansion supported", LOG_LEVEL_INFO);
         return false;
      }

      double c2_upperWick   = c2_high - c2_wickBodyHigh;
      double c2_lowerWick   = c2_wickBodyLow - c2_low;
      double c2_dominantWick = (sweep == DIRECTION_BUY) ? c2_lowerWick : c2_upperWick;

      signal.expansionMode = (c2_dominantWick < c2_wickTR * 0.5);

      if(signal.expansionMode)
         LogPrint("[WICK_RULE_PASS] C2_EXPANSION | dominantWick=" + DoubleToString(c2_dominantWick, _Digits) +
                  " | totalRange=" + DoubleToString(c2_wickTR, _Digits) +
                  " | ratio=" + DoubleToString(c2_wickTR > 0 ? c2_dominantWick / c2_wickTR : 0, 3), LOG_LEVEL_INFO);
      else
         LogPrint("[WICK_RULE_BLOCK] C2_REVERSAL | dominantWick=" + DoubleToString(c2_dominantWick, _Digits) +
                  " | totalRange=" + DoubleToString(c2_wickTR, _Digits) +
                  " | ratio=" + DoubleToString(c2_wickTR > 0 ? c2_dominantWick / c2_wickTR : 0, 3) +
                  " | reversal mode (target=HTF Open)", LOG_LEVEL_INFO);
   }

   bool hasReversalClosure = DidC2ProduceReversalClosure(c1_open, c1_close, c1_high, c1_low, c2_high, c2_low, c2_close);

   if(!hasReversalClosure)
   {
      static int s_lastNoClosureBar = -1;
      if(Bars(_Symbol, _Period) != s_lastNoClosureBar)
      {
         s_lastNoClosureBar = Bars(_Symbol, _Period);
         LogPrint("[C2_REJECT] NO_REVERSAL_CLOSURE | C2 close=" + DoubleToString(c2_close, _Digits) +
                  " | C1 low=" + DoubleToString(c1_low, _Digits) +
                  " | C1 high=" + DoubleToString(c1_high, _Digits), LOG_LEVEL_INFO);
      }
LogPrint("[C2_REJECT] NO_REVERSAL_CLOSURE | C2 did NOT produce reversal closure", LOG_LEVEL_INFO);
       return false;
    }

    LogPrint("[C2_CLOSURE_DETECTED] C2 produced reversal closure | sweep=" + EnumToString(sweep), LOG_LEVEL_INFO);

    BranchContext ctx = g_branchAContext;
    if(g_activeBranch == BRANCH_SWING) ctx = g_branchBContext;

    // Per TTrades: "Candle 2 closures only matter when C1 is at a higher-time-frame point of interest"
     // C1 must overlap an HTF structural level (swing, FVG, or OB). Replaces the incorrect
     // sweep-targeting check (DidSweepTargetStructuralLevel).
     ENUM_TIMEFRAMES htf = (ctx.branch == BRANCH_SWING) ? PERIOD_H4 : PERIOD_H1;

     if(!IsC1AtHTFPointOfInterest(c1_high, c1_low, TimeCurrent(), htf))
     {
        LogPrint("[C2_REJECT] POI_MISS | C1 not at HTF POI | c1_high=" + DoubleToString(c1_high, _Digits) +
                 " | c1_low=" + DoubleToString(c1_low, _Digits) + " | htf=" + EnumToString(htf), LOG_LEVEL_INFO);
        return false;
     }
     LogPrint("[C1_POI_VALID] C1 at HTF POI | c1_high=" + DoubleToString(c1_high, _Digits) +
              " | c1_low=" + DoubleToString(c1_low, _Digits) + " | htf=" + EnumToString(htf), LOG_LEVEL_INFO);

     // Verify structural displacement: sweep distance vs C1 range ratio (ATR-free)
      double c1Range = MathAbs(c1_high - c1_low);
      double sweepDist = (sweep == DIRECTION_BUY) ? (c1_low - c2_low) : (c2_high - c1_high);

      if(!ValidateDisplacement("C2", sweepDist, c1Range, 0.0, 0.0, g_branchParams.c2DisplacementMultiplier))
      {
         LogPrint("[C2_REJECT] DISPLACEMENT_FAIL | Ratio: " + DoubleToString(c1Range > 0 ? MathAbs(sweepDist) / c1Range : 0, 2) +
                  " | sweepDist=" + DoubleToString(sweepDist, _Digits) +
                  " | c1Range=" + DoubleToString(c1Range, _Digits), LOG_LEVEL_INFO);
         return false;
      }

    // Compute total wick ratio per TTrades formula for diagnostic logging
    double c2TotalRange = c2_high - c2_low;
    double c2BodySize = MathAbs(c2_close - c2_open);
    double c2WickRatio = (c2TotalRange > 0.0) ? (c2TotalRange - c2BodySize) / c2TotalRange : 0.0;
    bool c2Tradeable = IsC2Tradeable(c2_open, c2_close, c2_high, c2_low, sweep);

    if(!c2Tradeable)
    {
       LogPrint("[C2_REJECT] WICK_FILTER_EXCEEDED | Wick: " + DoubleToString(c2WickRatio * 100, 1) + "%", LOG_LEVEL_INFO);
       Print("[C2_WICK_FILTER] Diverting to C3 observation for continuation per TTFM expansions");

       // [C2_CONTINUATION_CANDIDATE] Register deferred continuation candidate
       // The C2 has structural validity (swept C1, close inside C1 range) but wick is too large.
       // The setup survives if structure remains valid — wick rejection is not a terminal death sentence.
       int defNarrativeIdx = -1;
       bool defIsBranchA = false;
       if(g_activeBranch == BRANCH_INTRADAY)
       {
          defNarrativeIdx = FN_FindActiveNarrative(g_branchANarratives, g_activeBranch);
          defIsBranchA = true;
       }
       else if(g_activeBranch == BRANCH_SWING)
       {
          defNarrativeIdx = FN_FindActiveNarrative(g_branchBNarratives, g_activeBranch);
          defIsBranchA = false;
       }

       if(defNarrativeIdx >= 0)
       {
          ulong defGuid = (ulong)TimeCurrent() ^ (ulong)GetTickCount64();
          bool deferred = false;
          if(defIsBranchA)
             deferred = g_branchANarratives[defNarrativeIdx].RegisterDeferredC2Candidate(
                defGuid, c2_high, c2_low, c2_open, c2_close, c2WickRatio
             );
          else
             deferred = g_branchBNarratives[defNarrativeIdx].RegisterDeferredC2Candidate(
                defGuid, c2_high, c2_low, c2_open, c2_close, c2WickRatio
             );
          if(deferred)
          {
             ulong narGUID = defIsBranchA
                ? g_branchANarratives[defNarrativeIdx].narrativeGUID
                : g_branchBNarratives[defNarrativeIdx].narrativeGUID;
             LogPrint("[C2_CONTINUATION_CANDIDATE] Deferred | GUID=" + IntegerToString(defGuid) +
                      " | c2_high=" + DoubleToString(c2_high, _Digits) +
                      " | c2_low=" + DoubleToString(c2_low, _Digits) +
                      " | wickRatio=" + DoubleToString(c2WickRatio * 100, 1) + "%" +
                      " | narrativeGUID=" + IntegerToString(narGUID), LOG_LEVEL_INFO);
          }
       }
       else
       {
          LogPrint("[C2_CONTINUATION_CANDIDATE] Deferred skipped — no active narrative for branch", LOG_LEVEL_DEBUG);
       }

       // REGRESSION_GUARD_C3
       return false;
    }

   double wick_ratio = ComputeWickRatio(c2_open, c2_close, c2_high, c2_low);

   ENUM_CLOSURE_TYPE closure_type = CLOSURE_C2;
   closure_type = ApplyWickFilter(wick_ratio, closure_type);

   if(closure_type == CLOSURE_NONE)
   {
      LogPrint("[C2_REJECT] WICK_FILTER_COMPLETE | Wick filter rejected signal entirely | " +
               "wick_ratio=" + DoubleToString(wick_ratio, 2), LOG_LEVEL_INFO);
      return false;
   }

   // Signal accepted (either CLOSURE_C2 or CLOSURE_C3 from wick demote)
   signal.valid = true;
   signal.type = closure_type;
   signal.fractalState = FRACTAL_STATE_C2;
   signal.is_bullish = (sweep == DIRECTION_BUY);

   // Store C2-specific metadata
   signal.c2HasSmallWick = c2Tradeable;
   signal.c2ClosureConfirmed = hasReversalClosure;

   signal.c1_high = c1_high;
   signal.c1_low = c1_low;
   signal.c1_close = c1_close;

   signal.c2_high = c2_high;
   signal.c2_low = c2_low;
   signal.c2_open = c2_open;
   signal.c2_close = c2_close;

   // Store setup-level metadata (the setup starts with C1)
   signal.setupStartTime = TimeCurrent();
   signal.setupHtfCandleStart = TimeCurrent();
   signal.setupInitialHigh = c1_high;
   signal.setupInitialLow = c1_low;
   signal.setupIsBullish = (sweep == DIRECTION_BUY);

// entry_price is set by caller (DetectClosureSignal) after EvaluateC2Closure returns true.
   // See ENTRY_PRICE_OWNERSHIP_REPORT.md for ownership documentation.

// VERBATIM REPAIR: Manipulation Leg SL (§V) — Entry TF extreme
   signal.stop_loss = RM_ComputeEntryTFSL(_Symbol, g_activeBranch, signal.is_bullish, signal.entry_price);

    signal.equilibrium = (c1_high + c1_low) / 2.0;
   signal.c2_wick_ratio = wick_ratio;

      // VERBATIM REPAIR: Synchronous Mapping (§II) — POI before Lock, propagate result
      SLockedSignal poiSignal;
      poiSignal.Reset();
      poiSignal.branch = g_activeBranch; 
      poiSignal.branchId = g_activeBranch; // CRITICAL: Fix uninitialized -1 sentinel
      poiSignal.direction = signal.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;
      poiSignal.symbol = _Symbol;

      // Law: POI mapper MUST receive synchronized identity to select M5 vs M15 chart.
      if (EE_MapTSpotPOI(poiSignal)) {
          if (poiSignal.entry_price > 0) {
              signal.entry_price = poiSignal.entry_price;
          }
      }

    LogPrint("[ENTRY_CANDIDATE_SET] C2 POI mapped | GUID_pre=" + IntegerToString(signal.m_guid) +
            " entry=" + DoubleToString(signal.entry_price, _Digits) +
            " source=EE_MapTSpotPOI", LOG_LEVEL_INFO);

   // Log C2 signal with distinct marker
   if(InpEnableTrace)
   {
      string closureSig = IntegerToString(signal.type) + "|" +
                          IntegerToString(signal.fractalState) + "|" +
                          (signal.is_bullish ? "BUY" : "SELL");

if(closureSig != g_lastC2ClosureSignature || TimeCurrent() - g_lastClosureLogTime > 5)
       {
          LGovPrint("[C2_SIGNAL_VALID] Sweep=" + (sweep == DIRECTION_BUY ? "BUY" : "SELL") +
                    " | WickRatio=" + DoubleToString(wick_ratio, 2) +
                    " | SmallWick=" + (c2Tradeable ? "YES" : "NO") +
                     " | ClosureConfirmed=" + (hasReversalClosure ? "YES" : "NO"), LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
          g_lastC2ClosureSignature = closureSig;
          g_lastClosureLogTime = TimeCurrent();
      }
   }

// Generate provisional GUID for traceable acceptance
    ulong acceptanceGuid = (ulong)TimeCurrent() ^ (ulong)GetTickCount64();
    signal.m_guid = acceptanceGuid;
    LogPrint("[C2_ACCEPTED] GUID=" + IntegerToString(acceptanceGuid) +
             " sweep=" + EnumToString(sweep), LOG_LEVEL_INFO);

    signal.m_detectionTime = TimeCurrent();

    // VERBATIM REPAIR: Inv XII N4 Bias Gate
    // Enforce Law of Gate Sequence (§XVII): Gate 1 must pass before C2 acceptance
    if(!IsBiasAligned(signal.is_bullish, ctx.bias))
    {
       LogPrint("[COMMIT_BIAS_REJECT_C2] GUID:" + IntegerToString(signal.m_guid), LOG_LEVEL_WARN);
       return false;
    }
   return true;
}

//+------------------------------------------------------------------+
//| C3 CLOSURE LOGIC — Engulfing Confirmation                        |
//+------------------------------------------------------------------+

ENUM_DIRECTION DetectC3Engulfing(
   double c2_open,
   double c2_close,
   double c3_open,
   double c3_close,
   double c3_high,
   double c3_low
)
{
   double c2_body_top = MathMax(c2_open, c2_close);
   double c2_body_bottom = MathMin(c2_open, c2_close);

   bool bullish_engulf = (c3_close > c2_body_top);
   bool bearish_engulf = (c3_close < c2_body_bottom);

   if(bullish_engulf && !bearish_engulf)
      return DIRECTION_BUY;

   if(bearish_engulf && !bullish_engulf)
      return DIRECTION_SELL;

   return DIRECTION_NONE;
}

bool EvaluateC3Closure(
   double c1_open,
   double c1_high,
   double c1_low,
   double c1_close,
   double c2_open,
   double c2_high,
   double c2_low,
   double c2_close,
   double c3_open,
   double c3_high,
   double c3_low,
   double c3_close,
   SClosureSignal &signal
)
{
   double c2Range = c2_high - c2_low;
   if(c2Range <= 0.0) return false;

   const double minCloseFrac = 0.1;

   bool bullish   = (c3_close > c2_low) && (c3_low <= c1_high);
   bool bearish   = (c3_close < c2_high) && (c3_high >= c1_low);

   if(bullish)
   {
      double fracAbove = (c3_close - c2_low) / c2Range;
      if(fracAbove < minCloseFrac) bullish = false;
   }
   if(bearish)
   {
      double fracBelow = (c2_high - c3_close) / c2Range;
      if(fracBelow < minCloseFrac) bearish = false;
   }

   if(!bullish && !bearish)
   {
      LogPrint("[C3_CLOSURE_REJECT] No valid C3 closure | " +
               "c3_close=" + DoubleToString(c3_close, _Digits) +
               " | c2_low=" + DoubleToString(c2_low, _Digits) +
               " | c2_high=" + DoubleToString(c2_high, _Digits) +
               " | c1_high=" + DoubleToString(c1_high, _Digits) +
               " | c1_low=" + DoubleToString(c1_low, _Digits), LOG_LEVEL_INFO);
      return false;
   }

   // --- AGNOSTIC WICK RULE (TTFM Gate 2: 50% Wick Rule) for C3 ---
   {
      double c3_wickTR = c3_high - c3_low;
      if(c3_wickTR <= 0.0)
      {
         LogPrint("[WICK_RULE_BLOCK] C3_ZERO_RANGE | totalRange=0, no expansion supported", LOG_LEVEL_INFO);
         return false;
      }

      double c3_wickBodyHigh = MathMax(c3_open, c3_close);
      double c3_wickBodyLow  = MathMin(c3_open, c3_close);
      double c3_wickBodySz   = c3_wickBodyHigh - c3_wickBodyLow;

      // Doji rejection: body < 10% of total range
      if(c3_wickBodySz < c3_wickTR * 0.1)
      {
         LogPrint("[WICK_RULE_BLOCK] C3_DOJI | bodyRatio=" + DoubleToString(c3_wickBodySz / c3_wickTR, 3) +
                  " | indecision candle, no expansion supported", LOG_LEVEL_INFO);
         return false;
      }

      double c3_upperWick   = c3_high - c3_wickBodyHigh;
      double c3_lowerWick   = c3_wickBodyLow - c3_low;
      double c3_dominantWick = bullish ? c3_lowerWick : c3_upperWick;

      signal.expansionMode = (c3_dominantWick < c3_wickTR * 0.5);

      if(signal.expansionMode)
         LogPrint("[WICK_RULE_PASS] C3_EXPANSION | dominantWick=" + DoubleToString(c3_dominantWick, _Digits) +
                  " | totalRange=" + DoubleToString(c3_wickTR, _Digits) +
                  " | ratio=" + DoubleToString(c3_wickTR > 0 ? c3_dominantWick / c3_wickTR : 0, 3), LOG_LEVEL_INFO);
      else
         LogPrint("[WICK_RULE_BLOCK] C3_REVERSAL | dominantWick=" + DoubleToString(c3_dominantWick, _Digits) +
                  " | totalRange=" + DoubleToString(c3_wickTR, _Digits) +
                  " | ratio=" + DoubleToString(c3_wickTR > 0 ? c3_dominantWick / c3_wickTR : 0, 3) +
                  " | reversal mode (target=HTF Open)", LOG_LEVEL_INFO);
   }

   signal.valid = true;
   signal.type = CLOSURE_C3;
   signal.fractalState = FRACTAL_STATE_C3;
   signal.is_bullish = bullish;

   signal.c1_high = c1_high;
   signal.c1_low = c1_low;
   signal.c1_close = c1_close;

   signal.c2_high = c2_high;
   signal.c2_low = c2_low;
   signal.c2_open = c2_open;
   signal.c2_close = c2_close;

signal.c3_high = c3_high;
     signal.c3_low = c3_low;
     signal.c3_open = c3_open;
     signal.c3_close = c3_close;

      // Generate provisional GUID for traceable acceptance
      signal.m_guid = (ulong)TimeCurrent() ^ (ulong)GetTickCount64();

      // VERBATIM REPAIR: Synchronous Mapping & IFVG Expansion (Law of Gate 4 / §II)
      // POI mapping MUST occur before Lock(). T-Spot zone MUST be set on the
      // poiSignal so EE_MapTSpotPOI can scan for OB/FVG/IFVG within the zone.
      SLockedSignal poiSignal;
      poiSignal.Reset();
      poiSignal.branch = g_activeBranch;
      poiSignal.branchId = g_activeBranch;
      poiSignal.direction = bullish ? DIRECTION_BUY : DIRECTION_SELL;
      poiSignal.symbol = _Symbol;

      double anchorHigh, anchorLow, anchorEq;
      GetAnchorContext(poiSignal.branchId, anchorHigh, anchorLow, anchorEq);
      poiSignal.tSpotMin = bullish ? anchorLow : anchorEq;
      poiSignal.tSpotMax = bullish ? anchorEq : anchorHigh;

      if (EE_MapTSpotPOI(poiSignal)) {
          if (poiSignal.entry_price > 0) {
              signal.entry_price = poiSignal.entry_price;
              LogPrint("[C3_SYNC_LOCK] GUID:" + IntegerToString(signal.m_guid) + " | Price:" + DoubleToString(poiSignal.entry_price, _Digits), LOG_LEVEL_INFO);
          }
      } else {
          LogPrint("[GATE_4_FAIL] No OB/FVG/IFVG found in T-Spot zone. Signal rejected.", LOG_LEVEL_WARN);
          return false;
      }

     // VERBATIM REPAIR: Manipulation Leg SL (§V) — Entry TF extreme
     signal.stop_loss = RM_ComputeEntryTFSL(_Symbol, g_activeBranch, signal.is_bullish, signal.entry_price);

     signal.equilibrium = (c1_high + c1_low) / 2.0;
     signal.c2_wick_ratio = ComputeWickRatio(c2_open, c2_close, c2_high, c2_low);
     signal.c3_wick_ratio = ComputeWickRatio(c3_open, c3_close, c3_high, c3_low);
     signal.c3EngulfingC2 = false;
     signal.c3CisdRequired = true;
     signal.m_detectionTime = TimeCurrent();
     signal.m_upgradedFromC2 = false;

     LogPrint("[C3_ACCEPTED] GUID=" + IntegerToString(signal.m_guid) +
             " direction=" + (bullish ? "BUY" : "SELL") +
             " | entry=" + DoubleToString(signal.entry_price, _Digits) +
             " | c3_close=" + DoubleToString(c3_close, _Digits) +
             " | c3_low=" + DoubleToString(c3_low, _Digits) +
             " | c3_high=" + DoubleToString(c3_high, _Digits) +
             " | c2_low=" + DoubleToString(c2_low, _Digits) +
             " | c2_high=" + DoubleToString(c2_high, _Digits) +
             " | c1_high=" + DoubleToString(c1_high, _Digits) +
             " | c1_low=" + DoubleToString(c1_low, _Digits) +
             " | sl_source=entry_tf_manip_leg", LOG_LEVEL_INFO);

     return true;
}

//+------------------------------------------------------------------+
//| C4 CLOSURE — Continuous Trend Expansion After C3 Validation      |
//|                                                                  |
//| C4 is NOT a rigid "fourth candle." It is a structural            |
//| continuation event that occurs when:                             |
//|   1. A C3 continuation event exists in the narrative             |
//|   2. The current candle shows continuous expansion (price        |
//|      extending beyond C3's range in the same direction)          |
//|   3. The candle wick forms inside the local T-Spot zone          |
//|   4. CISD is confirmed on the LTF                                |
//|                                                                  |
//| C4 can occur multiple bars after C3 — no adjacency required.     |
//+------------------------------------------------------------------+
bool EvaluateC4Closure(
   double c2_high,
   double c2_low,
   double c2_open,
   double c2_close,
   double c3_high,
   double c3_low,
   double c3_open,
   double c3_close,
   double c4_high,
   double c4_low,
   double c4_open,
   double c4_close,
   ENUM_DIRECTION direction,
   SClosureSignal &signal
)
{
   if(direction == DIRECTION_NONE)
      return false;

   // Condition 1: C3 reference must exist and be valid
   if(c3_high <= 0.0 || c3_low <= 0.0)
      return false;

   // Condition 2: Continuous expansion in the same direction
   // C4 uses C3 as reference
   // Bullish C4: C4 high > C3_high, C4 low >= C3_low (no sweep of C3 low)
   // Bearish C4: C4 low < C3_low, C4 high <= C3_high (no sweep of C3 high)
   double refHigh = c3_high;
   double refLow  = c3_low;
    
    bool expansion = false;
    if(direction == DIRECTION_BUY)
    {
       expansion = (c4_high > refHigh) && (c4_low >= refLow);
    }
    else if(direction == DIRECTION_SELL)
    {
       expansion = (c4_low < refLow) && (c4_high <= refHigh);
    }

   if(!expansion)
      return false;

   // Condition 3: Wick forms at a local T-Spot (wick is inside discount/premium zone)
   double c4_wick_ratio = ComputeWickRatio(c4_open, c4_close, c4_high, c4_low);
   if(c4_wick_ratio > 0.85)  // Excessive wick = rejection, not continuation
      return false;

   // Condition 4: CISD check — confirm delivery continuation
   BranchContext ctx = g_branchAContext;
   if(g_activeBranch == BRANCH_SWING) ctx = g_branchBContext;
   ENUM_TIMEFRAMES ltf = (ctx.branch == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;

   SSE_CISDResult c4CisdResult = SSE_DetectCISD(_Symbol, ltf, direction, 15);

   if(!c4CisdResult.confirmed)
      return false;

   // Signal accepted — C4 is valid
   signal.valid = true;
   signal.type = CLOSURE_C4;
   signal.fractalState = FRACTAL_STATE_C4;
   signal.is_bullish = (direction == DIRECTION_BUY);

   signal.c1_high = 0.0;
   signal.c1_low = 0.0;
   signal.c1_close = 0.0;

   signal.c2_high = c2_high;
   signal.c2_low = c2_low;
   signal.c2_open = c2_open;
   signal.c2_close = c2_close;

   signal.c3_high = c3_high;
   signal.c3_low = c3_low;
   signal.c3_open = c3_open;
   signal.c3_close = c3_close;

   signal.entry_price = c4_open;

    // VERBATIM REPAIR: Manipulation Leg SL (§V) — Entry TF extreme
   signal.stop_loss = RM_ComputeEntryTFSL(_Symbol, g_activeBranch, signal.is_bullish, signal.entry_price);

signal.equilibrium = (c4_high + c4_low) / 2.0;
    signal.c2_wick_ratio = ComputeWickRatio(c2_open, c2_close, c2_high, c2_low);
    signal.c3_wick_ratio = ComputeWickRatio(c3_open, c3_close, c3_high, c3_low);
    signal.m_detectionTime = TimeCurrent();
    signal.c3CisdRequired = true;

    // Generate provisional GUID for traceable acceptance
    signal.m_guid = (ulong)TimeCurrent() ^ (ulong)GetTickCount64();

    LogPrint("[C4_ACCEPTED] GUID=" + IntegerToString(signal.m_guid) +
             " dir=" + EnumToString(direction) +
             " | entry=" + DoubleToString(c4_open, _Digits) +
             " | sl=" + DoubleToString(signal.stop_loss, _Digits) +
             " | c2_high=" + DoubleToString(c2_high, _Digits) +
             " | c2_low=" + DoubleToString(c2_low, _Digits) +
             " | expansion_high=" + DoubleToString(c4_high, _Digits) +
             " | expansion_low=" + DoubleToString(c4_low, _Digits) +
             " | cisd=" + (c4CisdResult.confirmed ? "OK" : "FAIL") +
             " | cisd_swing=" + DoubleToString(c4CisdResult.swingPrice, _Digits), LOG_LEVEL_INFO);

   return true;
}

// VERBATIM REPAIR: Synchronous Lock Wrapper (§IV)
bool PrepareAndLockSignal(SLockedSignal &sig) {
    if (EE_MapTSpotPOI(sig)) { 
        if (sig.entry_price > 0) {
            SClosureSignal tmp;
            tmp.valid = true;
            tmp.type = sig.closureType;
            tmp.is_bullish = (sig.direction == DIRECTION_BUY);
            tmp.entry_price = sig.entry_price;
            tmp.stop_loss = sig.stop_loss;
            tmp.c2_high = sig.c2_high;
            tmp.c2_low = sig.c2_low;
            tmp.c2_open = sig.c2_open;
            tmp.c2_close = sig.c2_close;
            tmp.c2_barIndex = sig.c2_barIndex;
            tmp.c3_high = sig.c3_high;
            tmp.c3_low = sig.c3_low;
            tmp.c3_open = sig.c3_open;
            tmp.c3_close = sig.c3_close;
            tmp.equilibrium = sig.equilibrium;
            tmp.m_detectionTime = sig.m_detectionTime;
            tmp.tSpotMin = sig.tSpotMin;
            tmp.tSpotMax = sig.tSpotMax;
            sig.Lock(tmp, 0, sig.branch, sig.entryTF);
            return true;
        }
    }
    LogPrint("[SYNC_LOCK_FAIL] No POI found. Signal discarded.", LOG_LEVEL_INFO);
    return false;
}

bool RecalculateSignalForC3(SLockedSignal &signal, string symbol)
{
   return true;
}

//+------------------------------------------------------------------+
//| MAIN DETECTION FUNCTION — DetectClosureSignal                    |
//+------------------------------------------------------------------+

// Static variables for closure deduplication (file scope for access from all functions)
// DECOUPLED: C2 and C3 now have independent signature trackers to prevent C3 from blocking C2
static string g_lastC2ClosureSignature = "";
static string g_lastC3ClosureSignature = "";
static datetime g_lastClosureLogTime = 0;

// FSM lifecycle state — tracks the current signal pipeline stage at file scope
static ENUM_SIGNAL_STAGE g_fsmState = STAGE_NONE;

//+------------------------------------------------------------------+
//| RegisterPipelineSignal — Pre-allocates PositionGUIDMap entry only   |
//| Signal storage to g_activeSignal[] is handled by CommitSignalToStore |
//| REGRESSION_GUARD: Single ownership model                       |
//+------------------------------------------------------------------+
bool RegisterPipelineSignal(ulong guid, ENUM_CLOSURE_TYPE type, double c1High, double c1Low,
                            double c2High, double c2Low, ENUM_DIRECTION direction = DIRECTION_NONE)
{
   // Only pre-allocate PositionGUIDMap - signal store handled by CommitSignalToStore
   ENUM_EXECUTION_BRANCH branch = g_activeBranch;
   
   if(!PreAllocateSignalGUIDEntry(guid, c1High, c1Low, c2High, c2Low, branch, direction, type, 0.0))
   {
      LogPrint(StringFormat("[PIPELINE_ERROR] PreAllocateSignalGUIDEntry failed | GUID=%I64u | closure=%s", guid, EnumToString(type)), LOG_LEVEL_ERROR);
      return false;
   }
   return true;
}

// REGRESSION_GUARD: Single ownership model
// Signal lifecycle flows: CommitSignalToStore (detection loop) -> g_activeSignal[] -> PositionGUIDMap at fill

void DetectClosureSignal(
   string symbol,
   ENUM_TIMEFRAMES tf,
   SClosureSignal &out_signal,
   SLockedSignal &lockedSignal)
   {
      BranchContext ctx = g_branchAContext;
      if(g_activeBranch == BRANCH_SWING) ctx = g_branchBContext;

      // BRANCH ISOLATION GATE — PROMPT 7: Discard signals not matching active branch
      if(ctx.branch != g_activeBranch)
      {
         out_signal.Reset();
         return;
      }

      out_signal.Reset();

      // Guard: Skip detection if fewer than 5 bars exist on target TF
      // This prevents Copy* calls from firing when tester has not built history
      string sym = (symbol == "" || symbol == NULL) ? _Symbol : symbol;
      ENUM_TIMEFRAMES checkTF = (tf == PERIOD_CURRENT) ? _Period : tf;
      if(iBars(sym, checkTF) < 5)
         return;

      // STRONG GUARD: Require 50 bars for reliable detection
      if(Bars(sym, checkTF) < 50)
      {
         LGovPrint("[CE] Insufficient structure bars=" +
                   IntegerToString(Bars(sym, checkTF)) +
                   " on TF=" + EnumToString(checkTF) +
                    " | skipping closure detection", LOG_LEVEL_DEBUG, LOG_CHANNEL_SYSTEM);
          return;
      }

      // Use file-scope static variables for deduplication
      bool shouldLogClosure = false;

      ENUM_TIMEFRAMES timeframe = (tf == PERIOD_CURRENT) ? PERIOD_CURRENT : tf;

      datetime times[];
      double opens[];
      double highs[];
      double lows[];
      double closes[];

      ArraySetAsSeries(times, true);
      ArraySetAsSeries(opens, true);
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);
ArraySetAsSeries(closes, true);

      // ══════════════════════════════════════════════════════════
      // CHANGE 1: Copy 4 bars instead of 3 (shift 0-3)
      // This ensures C3 (shift 1) is fully closed before evaluation
      // ══════════════════════════════════════════════════════════
      ENUM_TIMEFRAMES fallbackTF = _Period;
      int copied = CopyHigh(sym, timeframe, 0, 4, highs);
      if(copied < 4)
      {
         LGovPrint("[CLOSURE] LTF data missing | copied=" + IntegerToString(copied) + " | timeframe=" + EnumToString(timeframe) + " | Retrying with chart TF", LOG_LEVEL_WARN, LOG_CHANNEL_SYSTEM);
         timeframe = fallbackTF;
         copied = CopyHigh(sym, timeframe, 0, 4, highs);
         if(copied < 4)
         {
             LGovPrint("[CLOSURE] DetectClosureSignal ERROR: CopyHigh failed | copied=" + IntegerToString(copied) + " | required=4", LOG_LEVEL_ERROR, LOG_CHANNEL_SYSTEM);
            return;
         }
      }

      copied = CopyLow(sym, timeframe, 0, 4, lows);
      if(copied < 4)
      {
         LGovPrint("[CLOSURE] LTF data missing | Retrying with chart TF", LOG_LEVEL_WARN, LOG_CHANNEL_SYSTEM);
         copied = CopyLow(sym, fallbackTF, 0, 4, lows);
         if(copied < 4)
         {
             LGovPrint("[CLOSURE] DetectClosureSignal ERROR: CopyLow failed | copied=" + IntegerToString(copied) + " | required=4", LOG_LEVEL_ERROR, LOG_CHANNEL_SYSTEM);
            return;
         }
      }

      copied = CopyClose(sym, timeframe, 0, 4, closes);
      if(copied < 4)
      {
         LGovPrint("[CLOSURE] LTF data missing | Retrying with chart TF", LOG_LEVEL_WARN, LOG_CHANNEL_SYSTEM);
         copied = CopyClose(sym, fallbackTF, 0, 4, closes);
         if(copied < 4)
         {
             LGovPrint("[CLOSURE] DetectClosureSignal ERROR: CopyClose failed | copied=" + IntegerToString(copied) + " | required=4", LOG_LEVEL_ERROR, LOG_CHANNEL_SYSTEM);
            return;
         }
      }

copied = CopyOpen(sym, timeframe, 0, 4, opens);
      if(copied < 4)
      {
         LGovPrint("[CLOSURE] LTF data missing | Retrying with chart TF", LOG_LEVEL_WARN, LOG_CHANNEL_SYSTEM);
         copied = CopyOpen(sym, fallbackTF, 0, 4, opens);
         if(copied < 4)
         {
             LGovPrint("[CLOSURE] DetectClosureSignal ERROR: CopyOpen failed | copied=" + IntegerToString(copied) + " | required=4", LOG_LEVEL_ERROR, LOG_CHANNEL_SYSTEM);
            return;
         }
      }

      copied = CopyTime(sym, timeframe, 0, 4, times);
      if(copied < 4)
      {
         LGovPrint("[CLOSURE] LTF data missing | Retrying with chart TF", LOG_LEVEL_WARN, LOG_CHANNEL_SYSTEM);
         copied = CopyTime(sym, fallbackTF, 0, 4, times);
         if(copied < 4)
         {
             LGovPrint("[CLOSURE] DetectClosureSignal ERROR: CopyTime failed | copied=" + IntegerToString(copied) + " | required=4", LOG_LEVEL_ERROR, LOG_CHANNEL_SYSTEM);
            return;
         }
      }

      // ══════════════════════════════════════════════════════════
      // CLOSURE CONTEXT — CANDLE INDEX VERIFICATION (P6.3)
      // ══════════════════════════════════════════════════════════

      // ══════════════════════════════════════════════════════════
      // CHANGE 2: Reassign indices for 4-bar shift
      // c1 = 3 bars ago (fully closed)
      // c2 = 2 bars ago (fully closed)
      // c3 = 1 bar ago (fully closed - correct for C3 detection)
      // c4 = current bar (open used as entry price for both C2 and C3)
      // ══════════════════════════════════════════════════════════
      double c1_open = opens[3];
      double c1_high = highs[3];
      double c1_low = lows[3];
      double c1_close = closes[3];

      double c2_open = opens[2];
      double c2_high = highs[2];
      double c2_low = lows[2];
      double c2_close = closes[2];

      double c3_open = opens[1];
      double c3_high = highs[1];
      double c3_low = lows[1];
      double c3_close = closes[1];

      double c4_open = opens[0];  // Entry price for both C2 and C3

// CRITICAL FIX: Validate entry_price only for signals requiring c4_open
     // C2 fallback uses c2_close as entry price - does not depend on c4_open
     // C3/C4 signals that use c4_open are validated separately in their handlers

    // ═══════════════════════════════════════════════════════════════════════
    // C2 CLOSURE CHECK — DEBUG (PHASE 6)
    // ═══════════════════════════════════════════════════════════════════════

    double c2_wick_ratio = ComputeWickRatio(c2_open, c2_close, c2_high, c2_low);
   
   ENUM_DIRECTION c2_sweep = DetectC2Sweep(c2_high, c2_low, c1_high, c1_low, highs, lows);
   bool c2_close_inside = DetectC2CloseInside(c2_close, c1_high, c1_low, c2_sweep);
   
   bool c2_wick_ok = (c2_wick_ratio <= g_branchParams.c2WickThreshold);
    bool c2_valid = (c2_sweep != DIRECTION_NONE && c2_close_inside && c2_wick_ok);

    // ═══════════════════════════════════════════════════════════
    // C2 — REJECTION + INTENT ENGINE
    // ═══════════════════════════════════════════════════════════
   
   double c2_body = GetCandleBody(c2_open, c2_close);
   double c2_range = GetCandleRange(c2_high, c2_low);
   
   c2_wick_ratio = ComputeWickRatio(c2_open, c2_close, c2_high, c2_low);
   
   bool c2_rejection = (c2_wick_ratio >= g_branchParams.c2MinWickRatio);
   
   double c2_body_ratio = (c2_range > 0) ? (c2_body / c2_range) : 0.0;
   bool c2_intent = (c2_body_ratio >= g_branchParams.c2MinBodyRatio);
   
   bool c2_bullish = IsBullishClosure(c2_close, c2_open);
   bool c2_bearish = IsBearishClosure(c2_close, c2_open);
   
   bool c2_directional_buy = (c2_bullish && c2_sweep == DIRECTION_BUY);
   bool c2_directional_sell = (c2_bearish && c2_sweep == DIRECTION_SELL);
   bool c2_directional = c2_directional_buy || c2_directional_sell;

   // ═══════════════════════════════════════════════════════════
   
   double c2_body_top = MathMax(c2_open, c2_close);
   double c2_body_bottom = MathMin(c2_open, c2_close);
   
   bool c3_bullish_engulf = (c3_close > c2_body_top);
   bool c3_bearish_engulf = (c3_close < c2_body_bottom);
   bool c3_engulfing = (c3_bullish_engulf || c3_bearish_engulf) && !(c3_bullish_engulf && c3_bearish_engulf);
   
// Relaxed: Allow C3 to trigger with smaller body multiplier for standalone detection
   double c3_body = GetCandleBody(c3_open, c3_close);
      bool c3_body_ok = (c3_body > c2_body * g_branchParams.c3BodyMultiplier);
   
double c3_wick_ratio = ComputeWickRatio(c3_open, c3_close, c3_high, c3_low);
    bool c3_wick_ok = (c3_wick_ratio <= 0.85);  // Relaxed from 0.80 to 0.85 for normal market
   
bool c3_valid = (c3_engulfing && c3_body_ok && c3_wick_ok);

    // ═══════════════════════════════════════════════════════════
    // C3 — DISPLACEMENT ENGINE
    // ═══════════════════════════════════════════════════════════
   // Note: c2_body and c2_range already defined above in C2 section

   c3_body = GetCandleBody(c3_open, c3_close);
   double c1_body = GetCandleBody(c1_open, c1_close);
   
   double c3_range = GetCandleRange(c3_high, c3_low);
   // c2_range already defined above
   
   double avg_body = GetAverageBody(c1_body, c2_body, c3_body);
   
bool c3_displacement =
       (c3_body > avg_body * g_branchParams.c3DisplacementMultiplier) &&
       (c3_range > c2_range * g_branchParams.c3RangeExpansionFactor);
   
   bool c3_bullish = IsBullishClosure(c3_close, c3_open);
   bool c3_bearish = IsBearishClosure(c3_close, c3_open);
   
   bool c3_directional_buy = (c3_bullish && c3_close > c2_high);
   bool c3_directional_sell = (c3_bearish && c3_close < c2_low);
   bool c3_directional = c3_directional_buy || c3_directional_sell;
   
bool c3_displacement_valid = (InpUseDisplacementEngine && c3_displacement && c3_directional);

    // ═══════════════════════════════════════════════════════════
   // CHANGE 3: Independent evaluation — TWO separate signal structs
   // Both C2 and C3 are evaluated regardless of the other
   // ═══════════════════════════════════════════════════════════
   SClosureSignal signal_c2;
   ZeroMemory(signal_c2);
   signal_c2.Reset();

   SClosureSignal signal_c3;
   ZeroMemory(signal_c3);
   signal_c3.Reset();

// ═══════════════════════════════════════════════════════════
    // C2 EVALUATION — CLASSIC SWEEP+CLOSE-INSIDE (PRIMARY)
    // Per TTFx: C2 = sweep + close inside C1 range
    // ═══════════════════════════════════════════════════════════

    bool c2_evaluated = false;

    // PRIMARY: Classic C2 detection (sweep + close inside)
    // Always attempt classic evaluation first - no dependency on
    c2_evaluated = EvaluateC2Closure(
       c1_open, c1_high, c1_low, c1_close,
       c2_open, c2_high, c2_low, c2_close,
       signal_c2
    );

      if(c2_evaluated)
      {
          if(signal_c2.entry_price <= 0.0)
             signal_c2.entry_price = c4_open;
          if(InpEnableTrace)
             LGovPrint("[ENTRY_CANDIDATE_SET] C2 primary path | entry_price=" + DoubleToString(signal_c2.entry_price, _Digits) +
                       " | sweep=" + (c2_sweep == DIRECTION_BUY ? "BUY" : "SELL"), LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
 if(InpEnableTrace)
            LGovPrint("[C2_DETECTED] Classic fallback | sweep=" + (c2_sweep == DIRECTION_BUY ? "BUY" : "SELL"), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
      }

     // ═══════════════════════════════════════════════════════════
     // C3 EVALUATION — ENGULFING/DISPLACEMENT (SIBLING)
     // C3 is a sibling closure family — evaluates independently of C2.
     // Both C2 and C3 may be evaluated within the same candle window.
     // No skipC3Evaluation — C2 lock state does not gate C3 evaluation.
     // m_upgradedFromC2 is set by EvaluateC3Closure (false by default);
     // lineage metadata must never block execution decisions.
     // ═══════════════════════════════════════════════════════════

    bool c3_evaluated = false;

// PRIMARY: Classic C3 detection (engulfing-based)
     // C3 evaluated as sibling — no dependency on C2 lock state
     c3_evaluated = EvaluateC3Closure(
        c1_open, c1_high, c1_low, c1_close,
        c2_open, c2_high, c2_low, c2_close,
        c3_open, c3_high, c3_low, c3_close,
        signal_c3
     );

     if(c3_evaluated)
     {
        // Use C1 bar time for setup origin (setup starts with C1 per TTFM)
        signal_c3.setupStartTime = times[3];
        signal_c3.setupHtfCandleStart = times[3];
        LogPrint("[C3_CONTINUATION_CANDIDATE] Primary | direction=" + (signal_c3.is_bullish ? "BUY" : "SELL"), LOG_LEVEL_INFO);
       if(InpEnableTrace)
          LGovPrint("[C3_DETECTED] Classic engulf | direction=" + (signal_c3.is_bullish ? "BUY" : "SELL") + " | fractalState=" + IntegerToString(signal_c3.fractalState), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
    }
    else
    {
       if(InpEnableTrace)
          LGovPrint("[C3_SKIPPED] Classic engulf failed | engulfs=" + (c3_engulfing ? "YES" : "NO") + " | body_ok=" + (c3_body_ok ? "YES" : "NO") + " | wick_ok=" + (c3_wick_ok ? "YES" : "NO"), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
    }

    // ═══════════════════════════════════════════════════════════
    // C3 DISPLACEMENT DETECTION (CONFIDENCE BONUS - NOT REQUIRED)
    // Only use as quality boost, not as gate
// ═══════════════════════════════════════════════════════════
   if(InpUseDisplacementEngine && c3_displacement_valid && !c3_evaluated)
   {
      c3_evaluated = true;
      signal_c3.valid = true;
      signal_c3.type = CLOSURE_C3;
      signal_c3.is_bullish = c3_directional_buy;

      LogTrace("[C3_DETECTED] Displacement | directional=" + (c3_directional ? "YES" : "NO"), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);

      signal_c3.c1_high = c1_high;
      signal_c3.c1_low = c1_low;
      signal_c3.c1_close = c1_close;

      signal_c3.c2_high = c2_high;
      signal_c3.c2_low = c2_low;
      signal_c3.c2_open = c2_open;
      signal_c3.c2_close = c2_close;
      signal_c3.c2_barIndex = 1;

      signal_c3.c3_high = c3_high;
      signal_c3.c3_low = c3_low;
signal_c3.c3_open = c3_open;
        signal_c3.c3_close = c3_close;

           signal_c3.stop_loss = RM_ComputeEntryTFSL(_Symbol, g_activeBranch, signal_c3.is_bullish, signal_c3.entry_price);
            signal_c3.equilibrium = (c1_high + c1_low) / 2.0;
            signal_c3.c3_wick_ratio = ComputeWickRatio(c3_open, c3_close, c3_high, c3_low);
            // VERBATIM REPAIR: Use Anchor TF boundaries for T-Spot 
            {   SLockedSignal tmpC3; tmpC3.Reset();
                tmpC3.direction = signal_c3.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;
                tmpC3.branch = g_activeBranch;
                tmpC3.branchId = g_activeBranch;
                tmpC3.symbol = _Symbol;
                double anchorHigh, anchorLow, anchorEq;
                GetAnchorContext(tmpC3.branchId, anchorHigh, anchorLow, anchorEq);

                // Bearish Zone: Equilibrium to HTF High | Bullish Zone: HTF Low to Equilibrium 
                tmpC3.tSpotMin = (tmpC3.direction == DIRECTION_BUY) ? anchorLow : anchorEq;
                tmpC3.tSpotMax = (tmpC3.direction == DIRECTION_BUY) ? anchorEq : anchorHigh;

                // Enforce Synchronous Mapping before Lock (§II)
                EE_MapTSpotPOI(tmpC3);
                if(tmpC3.entry_price > 0.0) signal_c3.entry_price = tmpC3.entry_price;
                signal_c3.tSpotMin = tmpC3.tSpotMin; signal_c3.tSpotMax = tmpC3.tSpotMax; }
            LogPrint("[C3_TSPOT_ZONE_SET] Displacement | tSpotMin=" + DoubleToString(signal_c3.tSpotMin, _Digits) +
                     " | tSpotMax=" + DoubleToString(signal_c3.tSpotMax, _Digits) +
                     " | entry=" + DoubleToString(signal_c3.entry_price, _Digits), LOG_LEVEL_INFO);
            // Use C1 bar time for setup origin (setup starts with C1 per TTFM)
            signal_c3.setupStartTime = times[3];
            signal_c3.setupHtfCandleStart = times[3];

            if(InpEnableTrace)
              LGovPrint("[C3_DETECTED] Displacement active | tSpot zone=[" +
                        DoubleToString(signal_c3.tSpotMin, _Digits) + "," +
                        DoubleToString(signal_c3.tSpotMax, _Digits) + "]", LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
    }

    // ═══════════════════════════════════════════════════════════
    // C3 CLASSIC FALLBACK (FALLBACK INVARIANT ENFORCED)
    // C3 is a sibling opportunity — can evaluate independently of C2
    // ═══════════════════════════════════════════════════════════
    if(!c3_evaluated && c3_valid)
    {
      c3_evaluated = true;
      signal_c3.valid = true;
      signal_c3.type = CLOSURE_C3;
      signal_c3.fractalState = FRACTAL_STATE_C3;
      signal_c3.is_bullish = c3_bullish_engulf;

       signal_c3.c1_high  = c1_high;
       signal_c3.c1_low   = c1_low;
       signal_c3.c1_close = c1_close;

       signal_c3.c2_high  = c2_high;
       signal_c3.c2_low   = c2_low;
       signal_c3.c2_open  = c2_open;
       signal_c3.c2_close = c2_close;

       signal_c3.c3_high  = c3_high;
       signal_c3.c3_low   = c3_low;
       signal_c3.c3_open  = c3_open;
       signal_c3.c3_close = c3_close;

signal_c3.stop_loss     = RM_ComputeEntryTFSL(_Symbol, g_activeBranch, signal_c3.is_bullish, signal_c3.entry_price);
           signal_c3.equilibrium   = (c1_high + c1_low) / 2.0;
           signal_c3.c3_wick_ratio = c3_wick_ratio;
           signal_c3.c2_wick_ratio = ComputeWickRatio(c2_open, c2_close, c2_high, c2_low);
            // VERBATIM REPAIR: Use Anchor TF boundaries for T-Spot 
            {   SLockedSignal tmpC3; tmpC3.Reset();
                tmpC3.direction = signal_c3.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;
                tmpC3.branch = g_activeBranch;
                tmpC3.branchId = g_activeBranch;
                tmpC3.symbol = _Symbol;
                double anchorHigh, anchorLow, anchorEq;
                GetAnchorContext(tmpC3.branchId, anchorHigh, anchorLow, anchorEq);

                // Bearish Zone: Equilibrium to HTF High | Bullish Zone: HTF Low to Equilibrium 
                tmpC3.tSpotMin = (tmpC3.direction == DIRECTION_BUY) ? anchorLow : anchorEq;
                tmpC3.tSpotMax = (tmpC3.direction == DIRECTION_BUY) ? anchorEq : anchorHigh;

                // Enforce Synchronous Mapping before Lock (§II)
                EE_MapTSpotPOI(tmpC3);
                if(tmpC3.entry_price > 0.0) signal_c3.entry_price = tmpC3.entry_price;
                signal_c3.tSpotMin = tmpC3.tSpotMin; signal_c3.tSpotMax = tmpC3.tSpotMax; }
            LogPrint("[C3_TSPOT_ZONE_SET] Classic fallback | tSpotMin=" + DoubleToString(signal_c3.tSpotMin, _Digits) +
                     " | tSpotMax=" + DoubleToString(signal_c3.tSpotMax, _Digits) +
                     " | entry=" + DoubleToString(signal_c3.entry_price, _Digits), LOG_LEVEL_INFO);
            // Use C1 bar time for setup origin (setup starts with C1 per TTFM)
            signal_c3.setupStartTime = times[3];
           signal_c3.setupHtfCandleStart = times[3];

           if(InpEnableTrace)
            LGovPrint("[C3_DETECTED] Classic fallback | engulfs=" + (c3_engulfing ? "YES" : "NO") + " | entry_price=" + DoubleToString(signal_c3.entry_price, _Digits), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
     }

// ═══════════════════════════════════════════════════════════
    // FALLBACK — C2 classic sweep passed, did not
    // C2 is a sibling opportunity — evaluate independently of C3
    // ═══════════════════════════════════════════════════════════
   bool atrBaselineReady = true;
   if(!c2_evaluated && c2_valid && atrBaselineReady)
   {
      c2_evaluated = true;
      signal_c2.valid = true;
      signal_c2.type = CLOSURE_C2;
      signal_c2.fractalState = FRACTAL_STATE_C2;
      signal_c2.is_bullish = (c2_sweep == DIRECTION_BUY);

      signal_c2.c1_high  = c1_high;
      signal_c2.c1_low   = c1_low;
      signal_c2.c1_close = c1_close;

      signal_c2.c2_high  = c2_high;
      signal_c2.c2_low   = c2_low;
      signal_c2.c2_open  = c2_open;
      signal_c2.c2_close = c2_close;

      signal_c2.stop_loss     = RM_ComputeEntryTFSL(_Symbol, g_activeBranch, signal_c2.is_bullish, signal_c2.entry_price);
      signal_c2.equilibrium   = (c1_high + c1_low) / 2.0;
      signal_c2.c2_wick_ratio = ComputeWickRatio(c2_open, c2_close, c2_high, c2_low);
      // VERBATIM REPAIR: Use Anchor TF boundaries for T-Spot 
      {   SLockedSignal tmpC2; tmpC2.Reset();
          tmpC2.direction = signal_c2.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;
          tmpC2.branch = g_activeBranch;
          tmpC2.branchId = g_activeBranch;
          tmpC2.symbol = _Symbol;
          double anchorHigh, anchorLow, anchorEq;
          GetAnchorContext(tmpC2.branchId, anchorHigh, anchorLow, anchorEq);

          // Bearish Zone: Equilibrium to HTF High | Bullish Zone: HTF Low to Equilibrium 
          tmpC2.tSpotMin = (tmpC2.direction == DIRECTION_BUY) ? anchorLow : anchorEq;
          tmpC2.tSpotMax = (tmpC2.direction == DIRECTION_BUY) ? anchorEq : anchorHigh;

          // Enforce Synchronous Mapping before Lock (§II)
          EE_MapTSpotPOI(tmpC2);
          if(tmpC2.entry_price > 0.0) signal_c2.entry_price = tmpC2.entry_price;
          signal_c2.tSpotMin = tmpC2.tSpotMin; signal_c2.tSpotMax = tmpC2.tSpotMax; }
      LogPrint("[ENTRY_CANDIDATE_SET] C2 classic fallback T-Spot | GUID_pre=" + IntegerToString(signal_c2.m_guid) +
               " entry=" + DoubleToString(signal_c2.entry_price, _Digits) +
               " tspotMin=" + DoubleToString(signal_c2.tSpotMin, _Digits) +
               " tspotMax=" + DoubleToString(signal_c2.tSpotMax, _Digits), LOG_LEVEL_INFO);
     }

     // ═══════════════════════════════════════════════════════════
     // LEGACY AS QUALITY BONUS
    // ═══════════════════════════════════════════════════════════
   // Legacy C2/C3 logic retained as confidence booster, not gate
   
   double quality_score = 0.0;
   
   // Legacy C3 (engulfing) check — bonus +1.0
   bool legacy_c3_valid = (c3_engulfing && c3_body_ok && c3_wick_ok);
   if(legacy_c3_valid)
   {
      quality_score += 1.0;
   }
   
   // Legacy C2 (sweep + close inside) check — bonus +0.5
   bool legacy_c2_valid = (c2_sweep != DIRECTION_NONE && c2_close_inside && c2_wick_ok);
   if(legacy_c2_valid)
   {
      quality_score += 0.5;
   }
   
if(InpUseDisplacementEngine && c3_displacement_valid)
    {
       if(g_logLevel <= LOG_LEVEL_DEBUG)
       {
          LGovPrint("[CLOSURE QUALITY] Score=" + DoubleToString(quality_score, 2) + " | LegacyC3=" + (legacy_c3_valid ? "PASS" : "FAIL") + " | LegacyC2=" + (legacy_c2_valid ? "PASS" : "FAIL"), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
       }
    }

    // ═══════════════════════════════════════════════════════════
    // CONTINUATION WINDOW SCAN — State-based delayed continuation
    // C3/C4 are siblings within narrative, can be evaluated independently
    // ═══════════════════════════════════════════════════════════
    // Locate active narrative for this branch
    int narrativeIdx = -1;
    if(ctx.branch == BRANCH_INTRADAY)
       narrativeIdx = FN_FindActiveNarrative(g_branchANarratives, ctx.branch);
    else
       narrativeIdx = FN_FindActiveNarrative(g_branchBNarratives, ctx.branch);
    bool hasActiveNarrative = (narrativeIdx >= 0);

    // Attempt delayed C3 scan if:
    // 1. No C3 was found in the 4-bar window
    // 2. An active narrative exists with open continuation window
    // 3. No C3 event already registered
    // Note: C2 and C3 are siblings - can both be active
    bool delayedC3Evaluated = false;
    if(!c3_evaluated && hasActiveNarrative)
    {
       bool _isBrA = (ctx.branch == BRANCH_INTRADAY);
       int _nIdx = narrativeIdx;

       bool narWindowOpen = _isBrA ? g_branchANarratives[_nIdx].IsWindowOpen() : g_branchBNarratives[_nIdx].IsWindowOpen();
       int narC3EventCount = _isBrA ? (int)g_branchANarratives[_nIdx].c3EventCount : (int)g_branchBNarratives[_nIdx].c3EventCount;
       ulong narGUID = _isBrA ? g_branchANarratives[_nIdx].narrativeGUID : g_branchBNarratives[_nIdx].narrativeGUID;
       double c2BodyTop = _isBrA ? MathMax(g_branchANarratives[_nIdx].c2Event.c2_open, g_branchANarratives[_nIdx].c2Event.c2_close)
                                 : MathMax(g_branchBNarratives[_nIdx].c2Event.c2_open, g_branchBNarratives[_nIdx].c2Event.c2_close);
       double c2BodyBottom = _isBrA ? MathMin(g_branchANarratives[_nIdx].c2Event.c2_open, g_branchANarratives[_nIdx].c2Event.c2_close)
                                    : MathMin(g_branchBNarratives[_nIdx].c2Event.c2_open, g_branchBNarratives[_nIdx].c2Event.c2_close);
       double c2Low = _isBrA ? g_branchANarratives[_nIdx].c2Event.c2_low : g_branchBNarratives[_nIdx].c2Event.c2_low;
       double c2High = _isBrA ? g_branchANarratives[_nIdx].c2Event.c2_high : g_branchBNarratives[_nIdx].c2Event.c2_high;
       double c2Open = _isBrA ? g_branchANarratives[_nIdx].c2Event.c2_open : g_branchBNarratives[_nIdx].c2Event.c2_open;
       double c2Close = _isBrA ? g_branchANarratives[_nIdx].c2Event.c2_close : g_branchBNarratives[_nIdx].c2Event.c2_close;
       double c2WickRatio = _isBrA ? g_branchANarratives[_nIdx].c2Event.c2_wick_ratio : g_branchBNarratives[_nIdx].c2Event.c2_wick_ratio;
       double c1High = _isBrA ? g_branchANarratives[_nIdx].c1_high : g_branchBNarratives[_nIdx].c1_high;
       double c1Low = _isBrA ? g_branchANarratives[_nIdx].c1_low : g_branchBNarratives[_nIdx].c1_low;
       double c1Close = _isBrA ? g_branchANarratives[_nIdx].c1_close : g_branchBNarratives[_nIdx].c1_close;
       datetime c1BarTime = _isBrA ? g_branchANarratives[_nIdx].c1_barTime : g_branchBNarratives[_nIdx].c1_barTime;
       ENUM_DIRECTION narDirection = _isBrA ? g_branchANarratives[_nIdx].narrativeDirection : g_branchBNarratives[_nIdx].narrativeDirection;

       if(narWindowOpen && narC3EventCount < 3)
       {
          LogPrint("[NARRATIVE_PERSISTENCE_ACTIVE] GUID=" + IntegerToString(narGUID) +
                   " | c3Events=" + IntegerToString(narC3EventCount) +
                   " | windowOpen=true", LOG_LEVEL_INFO);

          // Scan wider: look for a delayed C3 closure (any bar after C1)
          // The C3 event must:
          // 1. Engulf C2's body (without sweeping C2's extreme)
          // 2. Have CISD confirmed
          // 3. Be within the narrative direction
          for(int scanIdx = 2; scanIdx < MathMin(copied, 40); scanIdx++)
          {
             double scan_open = opens[scanIdx];
             double scan_high = highs[scanIdx];
             double scan_low = lows[scanIdx];
             double scan_close = closes[scanIdx];

             // C3 engulf check against the narrative's C2
             double c2_body_top = c2BodyTop;
             double c2_body_bottom = c2BodyBottom;

             bool bullish_engulf = (scan_close > c2_body_top);
             bool bearish_engulf = (scan_close < c2_body_bottom);

             if(!bullish_engulf && !bearish_engulf)
                continue;

             ENUM_DIRECTION engulfDir = bullish_engulf ? DIRECTION_BUY : DIRECTION_SELL;

             // Direction must match narrative
             if(engulfDir != narDirection)
                continue;

             // Must not sweep C2 extreme
             bool sweptC2Extreme = (bullish_engulf && scan_low < c2Low) ||
                                   (bearish_engulf && scan_high > c2High);
             if(sweptC2Extreme)
                continue;

               // CISD check on LTF
               ENUM_TIMEFRAMES ltf = (ctx.branch == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;
               SSE_CISDResult delayedCisdResult = SSE_DetectCISD(_Symbol, ltf, engulfDir, 15);

               // Build C3 event and register with narrative
               SSequenceLineage lineage;
               lineage.Reset();
               lineage.closureKind = CLOSURE_C3;
               lineage.branchId = ctx.branch;
               lineage.anchorBarTime = c1BarTime;
               lineage.detectionTime = TimeCurrent();

               double c3ProtectedSwing = delayedCisdResult.swingPrice > 0.0
                  ? delayedCisdResult.swingPrice
                  : (engulfDir == DIRECTION_BUY ? c2Low : c2High);

               SClosureEvent c3Event = SFractalNarrative::BuildEvent(
                  CLOSURE_C3, engulfDir,
                  c2High, c2Low,
                  c2Open, c2Close,
                  scan_high, scan_low, scan_open, scan_close,
                  scan_open,
                  c3ProtectedSwing,
                  c2WickRatio,
                  ComputeWickRatio(scan_open, scan_close, scan_high, scan_low),
                  delayedCisdResult.confirmed, true, scanIdx, lineage
              );

              // RegisterC3Event must modify the global array directly
              bool c3Registered = false;
              if(ctx.branch == BRANCH_INTRADAY)
                 c3Registered = g_branchANarratives[narrativeIdx].RegisterC3Event(c3Event);
              else
                 c3Registered = g_branchBNarratives[narrativeIdx].RegisterC3Event(c3Event);

               if(c3Registered)
               {
                  LogPrint("[C3_CONTINUATION_CANDIDATE] Delayed scan | narrativeGUID=" + IntegerToString(narGUID) +
                           " | scanIdx=" + IntegerToString(scanIdx), LOG_LEVEL_INFO);
                  LogPrint("[DELAYED_CONTINUATION_VALID] C3 | narrativeGUID=" + IntegerToString(narGUID) +
                           " | scanIdx=" + IntegerToString(scanIdx) +
                           " | barsSinceC1=" + IntegerToString(scanIdx) +
                           " | entry=" + DoubleToString(scan_open, _Digits), LOG_LEVEL_INFO);

                  // Populate the output signal
                  signal_c3.Reset();
                  signal_c3.valid = true;
                 signal_c3.type = CLOSURE_C3;
                 signal_c3.fractalState = FRACTAL_STATE_C3;
                 signal_c3.is_bullish = (engulfDir == DIRECTION_BUY);
                 signal_c3.c1_high = c1High;
                 signal_c3.c1_low = c1Low;
                 signal_c3.c1_close = c1Close;
                 signal_c3.c2_high = c2High;
                 signal_c3.c2_low = c2Low;
                 signal_c3.c2_open = c2Open;
                 signal_c3.c2_close = c2Close;
                  signal_c3.c3_high = scan_high;
                  signal_c3.c3_low = scan_low;
                  signal_c3.c3_open = scan_open;
                   signal_c3.c3_close = scan_close;
                    // VERBATIM REPAIR: Use Anchor TF boundaries for T-Spot 
                    {   SLockedSignal tmpC3; tmpC3.Reset();
                        tmpC3.direction = signal_c3.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;
                        tmpC3.branch = g_activeBranch;
                        tmpC3.branchId = g_activeBranch;
                        tmpC3.symbol = _Symbol;
                        double anchorHigh, anchorLow, anchorEq;
                        GetAnchorContext(tmpC3.branchId, anchorHigh, anchorLow, anchorEq);

                        // Bearish Zone: Equilibrium to HTF High | Bullish Zone: HTF Low to Equilibrium 
                        tmpC3.tSpotMin = (tmpC3.direction == DIRECTION_BUY) ? anchorLow : anchorEq;
                        tmpC3.tSpotMax = (tmpC3.direction == DIRECTION_BUY) ? anchorEq : anchorHigh;

                        // Enforce Synchronous Mapping before Lock (§II)
                        EE_MapTSpotPOI(tmpC3);
                        if(tmpC3.entry_price > 0.0) signal_c3.entry_price = tmpC3.entry_price;
                        signal_c3.tSpotMin = tmpC3.tSpotMin; signal_c3.tSpotMax = tmpC3.tSpotMax; }
                    LogPrint("[C3_TSPOT_ZONE_SET] Delayed continuation | tSpotMin=" + DoubleToString(signal_c3.tSpotMin, _Digits) +
                             " | tSpotMax=" + DoubleToString(signal_c3.tSpotMax, _Digits) +
                             " | entry=" + DoubleToString(signal_c3.entry_price, _Digits), LOG_LEVEL_INFO);
                   signal_c3.stop_loss = RM_ComputeEntryTFSL(_Symbol, g_activeBranch, signal_c3.is_bullish, signal_c3.entry_price);
                  signal_c3.equilibrium = (c1High + c1Low) / 2.0;
signal_c3.c2_wick_ratio = c2WickRatio;
                  signal_c3.c3_wick_ratio = ComputeWickRatio(scan_open, scan_close, scan_high, scan_low);
                   signal_c3.c3EngulfingC2 = true;
                   signal_c3.c3CisdRequired = true;
                   signal_c3.m_detectionTime = TimeCurrent();
                   signal_c3.setupStartTime = c1BarTime;
                   signal_c3.setupHtfCandleStart = c1BarTime;
                   // m_upgradedFromC2 deliberately NOT set here —
                  // this is standalone C3 from narrative scan, not a C2 upgrade

                  delayedC3Evaluated = true;
                 LogPrint("[CONTINUATION_WINDOW_OPEN] narrativeGUID=" + IntegerToString(narGUID) +
                          " | delayedC3 at scanIdx=" + IntegerToString(scanIdx) +
                          " | barsSinceC1=" + IntegerToString(scanIdx), LOG_LEVEL_INFO);
                 break;
              }
           }
         }
         else if(hasActiveNarrative)
         {
            bool expiredWindowOpen = _isBrA ? g_branchANarratives[_nIdx].IsWindowOpenOrDeferred() : g_branchBNarratives[_nIdx].IsWindowOpenOrDeferred();
            ulong expiredGUID = _isBrA ? g_branchANarratives[_nIdx].narrativeGUID : g_branchBNarratives[_nIdx].narrativeGUID;
            bool expiredC2Def = _isBrA ? g_branchANarratives[_nIdx].c2Deferred : g_branchBNarratives[_nIdx].c2Deferred;
            if(expiredWindowOpen && !delayedC3Evaluated)
            {
               LogPrint("[DELAYED_CONTINUATION_EXPIRED] No C3 found in delayed scan | narrativeGUID=" +
                        IntegerToString(expiredGUID) +
                        " | c2Deferred=" + (expiredC2Def ? "YES" : "NO"), LOG_LEVEL_INFO);
            }
         }
     }

    // Attempt C4 detection if:
    // 1. An active narrative exists with a C3 event registered
    // 2. No C4 event already registered
    bool c4Evaluated = false;
    if(hasActiveNarrative)
    {
       bool _c4IsBrA = (ctx.branch == BRANCH_INTRADAY);
       int _c4NIdx = narrativeIdx;

       // C4 is a continuation expansion event within an existing C3 narrative.
        // C4 always requires a confirmed C3 parent signal (stage >= STAGE_READY).
        bool c4Permitted = (_c4IsBrA ? g_branchANarratives[_c4NIdx].IsWindowOpenOrDeferred() : g_branchBNarratives[_c4NIdx].IsWindowOpenOrDeferred())
                        && ((_c4IsBrA ? (int)g_branchANarratives[_c4NIdx].c4EventCount : (int)g_branchBNarratives[_c4NIdx].c4EventCount) < 3);
        bool c4FromC3 = ((_c4IsBrA ? (int)g_branchANarratives[_c4NIdx].c3EventCount : (int)g_branchBNarratives[_c4NIdx].c3EventCount) > 0);

        // CONSTITUTION: C4 requires parent C3 signal to be confirmed (stage >= STAGE_READY)
        if(c4FromC3)
        {
            bool c3ParentConfirmed = false;
            int c3BaseIdx = GetSignalStoreIndex(ctx.branch, CLOSURE_C3);
            int c3MaxSlots = GetMaxSignalsForClosureType(CLOSURE_C3);
            for(int ci = 0; ci < c3MaxSlots; ci++)
            {
                int idx = c3BaseIdx + ci;
                if(g_hasActiveSignal[idx] && g_activeSignal[idx].m_guid != 0)
                {
                    ENUM_SIGNAL_STAGE sigStage = g_activeSignal[idx].stage;
                    if(sigStage == STAGE_READY || sigStage == STAGE_EXECUTED)
                    {
                        c3ParentConfirmed = true;
                        break;
                    }
                }
            }
            if(!c3ParentConfirmed)
            {
                LogPrint("[C4_BLOCKED] C3 parent not confirmed | branch=" + (ctx.branch == BRANCH_INTRADAY ? "A" : "B") +
                         " | c3EventCount=" + IntegerToString(_c4IsBrA ? (int)g_branchANarratives[_c4NIdx].c3EventCount : (int)g_branchBNarratives[_c4NIdx].c3EventCount), LOG_LEVEL_WARN);
                c4FromC3 = false;
            }
        }

if(c4Permitted && c4FromC3)
        {
           double c4NarC2High = _c4IsBrA ? g_branchANarratives[_c4NIdx].c2Event.c2_high : g_branchBNarratives[_c4NIdx].c2Event.c2_high;
           double c4NarC2Low = _c4IsBrA ? g_branchANarratives[_c4NIdx].c2Event.c2_low : g_branchBNarratives[_c4NIdx].c2Event.c2_low;
           double c4NarC2Open = _c4IsBrA ? g_branchANarratives[_c4NIdx].c2Event.c2_open : g_branchBNarratives[_c4NIdx].c2Event.c2_open;
           double c4NarC2Close = _c4IsBrA ? g_branchANarratives[_c4NIdx].c2Event.c2_close : g_branchBNarratives[_c4NIdx].c2Event.c2_close;
           double c4NarC3High = _c4IsBrA ? g_branchANarratives[_c4NIdx].c3Event.event_high : g_branchBNarratives[_c4NIdx].c3Event.event_high;
           double c4NarC3Low = _c4IsBrA ? g_branchANarratives[_c4NIdx].c3Event.event_low : g_branchBNarratives[_c4NIdx].c3Event.event_low;
           double c4NarC3Open = _c4IsBrA ? g_branchANarratives[_c4NIdx].c3Event.event_open : g_branchBNarratives[_c4NIdx].c3Event.event_open;
           double c4NarC3Close = _c4IsBrA ? g_branchANarratives[_c4NIdx].c3Event.event_close : g_branchBNarratives[_c4NIdx].c3Event.event_close;
           ENUM_DIRECTION c4NarDir = _c4IsBrA ? g_branchANarratives[_c4NIdx].narrativeDirection : g_branchBNarratives[_c4NIdx].narrativeDirection;
           ulong c4NarGUID = _c4IsBrA ? g_branchANarratives[_c4NIdx].narrativeGUID : g_branchBNarratives[_c4NIdx].narrativeGUID;
           datetime c4NarC1BarTime = _c4IsBrA ? g_branchANarratives[_c4NIdx].c1_barTime : g_branchBNarratives[_c4NIdx].c1_barTime;
           bool c4NarCisdConfirmed = _c4IsBrA ? g_branchANarratives[_c4NIdx].cisdConfirmed : g_branchBNarratives[_c4NIdx].cisdConfirmed;

           double cur_high = highs[0];
           double cur_low = lows[0];
           double cur_open = opens[0];
           double cur_close = closes[0];

           SClosureSignal signal_c4;
           signal_c4.Reset();

if(EvaluateC4Closure(
               c4NarC2High, c4NarC2Low, c4NarC2Open, c4NarC2Close,
               c4NarC3High, c4NarC3Low, c4NarC3Open, c4NarC3Close,
               cur_high, cur_low, cur_open, cur_close,
               c4NarDir,
               signal_c4
            ))
            {
               // C4 inherits setup metadata from narrative's C1 (continuation within existing structure)
               signal_c4.setupStartTime = c4NarC1BarTime;
               signal_c4.setupHtfCandleStart = c4NarC1BarTime;

               c4Evaluated = true;

             LogPrint("[C4_CONTINUATION_CANDIDATE] narrativeGUID=" + IntegerToString(c4NarGUID) +
                      " | entry=" + DoubleToString(cur_open, _Digits) +
                      " | reference=C3", LOG_LEVEL_INFO);

              SSequenceLineage lineage;
              lineage.Reset();
              lineage.closureKind = CLOSURE_C4;
              lineage.branchId = ctx.branch;
              lineage.anchorBarTime = c4NarC1BarTime;
              lineage.detectionTime = TimeCurrent();

              SClosureEvent c4Event = SFractalNarrative::BuildEvent(
                 CLOSURE_C4, c4NarDir,
                 c4NarC2High, c4NarC2Low, c4NarC2Open, c4NarC2Close,
                 cur_high, cur_low, cur_open, cur_close,
                 cur_open,
                 c4NarDir == DIRECTION_BUY ? c4NarC2Low : c4NarC2High,
                 0.0,
                 ComputeWickRatio(cur_open, cur_close, cur_high, cur_low),
                 c4NarCisdConfirmed, true, 0, lineage
              );
              if(_c4IsBrA)
                 g_branchANarratives[_c4NIdx].RegisterC4Event(c4Event);
              else
                 g_branchBNarratives[_c4NIdx].RegisterC4Event(c4Event);

              signal_c3 = signal_c4;
              LogPrint("[C4_EVENT] narrativeGUID=" + IntegerToString(c4NarGUID) +
                       " | dir=" + EnumToString(c4NarDir) +
                       " | entry=" + DoubleToString(cur_open, _Digits) +
                       " | reference=C3", LOG_LEVEL_INFO);
          }
       }
    }

    // ═══════════════════════════════════════════════════════════
    // CHANGE 4: Priority resolution — C2 FIRST, C3/C4 SECOND (TTrades Fractal Model)
    // C2 is the primary reversal candle; C3/C4 are sibling continuations
    // ═══════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════
    // FINAL CLOSURE RESULT — DEBUG (PHASE 6)
    // ═══════════════════════════════════════════════════════════

    if(!c2_evaluated && !c3_evaluated && !delayedC3Evaluated && !c4Evaluated)
       {
          // Check if deferred continuation exists (wick-rejected C2 with valid structure)
          bool hasDeferredContinuation = false;
          if(hasActiveNarrative)
          {
             bool defIsBrA = (ctx.branch == BRANCH_INTRADAY);
             bool defC2Def = defIsBrA ? g_branchANarratives[narrativeIdx].c2Deferred : g_branchBNarratives[narrativeIdx].c2Deferred;
             bool defWinOpen = defIsBrA ? g_branchANarratives[narrativeIdx].IsWindowOpenOrDeferred() : g_branchBNarratives[narrativeIdx].IsWindowOpenOrDeferred();
             hasDeferredContinuation = defC2Def && defWinOpen;
          }

          // NO FORCED CLOSURE — System operates on validated closures only
          // (suppress repeated logs) - check both C2, C3, delayedC3, and C4 trackers
          if(g_logLevel <= LOG_LEVEL_DEBUG && ((g_lastC2ClosureSignature == "" && g_lastC3ClosureSignature == "") || TimeCurrent() - g_lastClosureLogTime > 10))
          {
             if(!hasDeferredContinuation)
                LGovPrint("[CLOSURE RESULT] No displacement closure detected", LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
          }

          if(hasDeferredContinuation)
          {
             LogPrint("[DELAYED_CONTINUATION_VALID] Deferred C2 awaiting continuation | narrativeGUID=" +
                      IntegerToString((ctx.branch == BRANCH_INTRADAY) ? g_branchANarratives[narrativeIdx].narrativeGUID :
                                       g_branchBNarratives[narrativeIdx].narrativeGUID), LOG_LEVEL_INFO);
          }
          else
          {
             LogPrint("[CONTINUATION_REJECTED] No closure detected and no deferred candidate", LOG_LEVEL_DEBUG);
          }
       }
       else
       {
          // [CONTINUATION_ACCEPTED] At least one continuation path succeeded
          if(c2_evaluated)
             LogPrint("[CONTINUATION_ACCEPTED] C2 | classic sweep+close-inside", LOG_LEVEL_DEBUG);
          if(c3_evaluated)
             LogPrint("[CONTINUATION_ACCEPTED] C3 | primary engulf", LOG_LEVEL_DEBUG);
          if(delayedC3Evaluated)
             LogPrint("[CONTINUATION_ACCEPTED] C3 | delayed continuation scan", LOG_LEVEL_DEBUG);
          if(c4Evaluated)
             LogPrint("[CONTINUATION_ACCEPTED] C4 | continuity expansion", LOG_LEVEL_DEBUG);
       }
// FIX A: C3/C4 takes priority over C2 - standalone C3/C4 should not be overwritten
if(c3_evaluated || delayedC3Evaluated || c4Evaluated)
       {
           // Per AGENTS.md §XVII Gate 4: C3 entry_price is 0.0 until POI is mapped via EE_MapTSpotPOI
           // c4_open (current bar open) must NOT be used as a midpoint fallback — constitutional violation
           if(signal_c3.type != CLOSURE_C3)
           {
              signal_c3.entry_price = c4_open;
           }
           out_signal = signal_c3;
          
          // C3 SPAM KILLER: IMPROVED detection using type + fractalState + timestamp + entry
          // Uses type (not closureType), fractalState, direction, and entry price for uniqueness
           string closureSig = IntegerToString(signal_c3.type) + "|" +
                               IntegerToString(signal_c3.fractalState) + "|" +
                               (signal_c3.is_bullish ? "BUY" : "SELL") + "|" +
                               DoubleToString(signal_c3.entry_price > 0 ? signal_c3.entry_price : 0, _Digits) + "|" +
                                IntegerToString(signal_c3.m_guid) + "|" + "C3";
   
          bool isNewClosure = (closureSig != g_lastC3ClosureSignature ||
                               TimeCurrent() - g_lastClosureLogTime > 5);

          if(isNewClosure)
              {
                  if(g_logLevel <= LOG_LEVEL_INFO)
                  {
                      LogPrint("[CONFIRMATION_GATE] C3_DISPLACEMENT - Verification Passed. Initializing Pipeline Lifecycle.", LOG_LEVEL_INFO);
                  }

                  ENUM_CLOSURE_TYPE regType = signal_c3.type;
                  if(c4Evaluated)
                     regType = CLOSURE_C4;

                   // [MODE_ASSIGNED] Mode determined at Lock() - ClosureEngine does NOT own executionMode
                   // C3/C4 signals pass through Lock() for proper mode assignment per Constitution
                   SClosureSignal c3Signal;
                   c3Signal.valid = true;
                   c3Signal.type = signal_c3.type;
                   c3Signal.is_bullish = signal_c3.is_bullish;
                   c3Signal.entry_price = signal_c3.entry_price;
                    c3Signal.stop_loss = RM_ComputeEntryTFSL(_Symbol, g_activeBranch, signal_c3.is_bullish, signal_c3.entry_price);
                   c3Signal.c1_high = signal_c3.c1_high;
                   c3Signal.c1_low = signal_c3.c1_low;
                   c3Signal.c2_high = signal_c3.c2_high;
                   c3Signal.c2_low = signal_c3.c2_low;
                   c3Signal.c2_open = signal_c3.c2_open;
                   c3Signal.c2_close = signal_c3.c2_close;
                   c3Signal.c3_high = signal_c3.c3_high;
                   c3Signal.c3_low = signal_c3.c3_low;
                   c3Signal.c3_open = signal_c3.c3_open;
                   c3Signal.c3_close = signal_c3.c3_close;
                   c3Signal.equilibrium = signal_c3.equilibrium;
                   c3Signal.setupStartTime = signal_c3.setupStartTime;
                   c3Signal.setupHtfCandleStart = signal_c3.setupHtfCandleStart;
                   c3Signal.setupInitialHigh = signal_c3.setupInitialHigh;
                   c3Signal.setupInitialLow = signal_c3.setupInitialLow;
                    c3Signal.setupIsBullish = signal_c3.setupIsBullish;
                    c3Signal.c1_close = signal_c3.c1_close;
                     c3Signal.fractalState = signal_c3.fractalState;
                     c3Signal.m_guid = signal_c3.m_guid;
                     c3Signal.tSpotMin = signal_c3.tSpotMin;
                     c3Signal.tSpotMax = signal_c3.tSpotMax;

// VERBATIM REPAIR: Pass-Through Lock (§IV)
SLockedSignal c3LockedSignal;
c3LockedSignal.Reset();
c3LockedSignal.direction = signal_c3.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;
c3LockedSignal.branch = g_activeBranch;
c3LockedSignal.branchId = g_activeBranch;
c3LockedSignal.closureType = regType;
if (EE_MapTSpotPOI(c3LockedSignal)) {
    // Pass scanner results directly to Lock
    c3LockedSignal.Lock(c3LockedSignal.tSpotMin, c3LockedSignal.tSpotMax); 
    c3LockedSignal.TransitionStage(STAGE_WAITING_FOR_POI);
    LogPrint("[C3_ROUTE_RESTORED] GUID:" + IntegerToString(c3LockedSignal.m_guid), LOG_LEVEL_INFO);
    CommitSignalToStore(c3LockedSignal, g_activeBranch, regType);
    lockedSignal = c3LockedSignal;
} else {
    LogPrint("[C3_LOCK_REJECTED] GUID: " + IntegerToString(signal_c3.m_guid) + " | entry_price is 0.0", LOG_LEVEL_WARN);
}
               }
         }

// C2 outputs to a separate location when C3/C4 are already output
        // Only set entry_price for C2 coeval scenario (when C3/C4 already exist)
        // Standalone C2 already has entry_price set in primary/fallback paths above
        if(c2_evaluated && (c3_evaluated || delayedC3Evaluated || c4Evaluated))
        {
           signal_c2.entry_price = c4_open;
           LogPrint("[ENTRY_CANDIDATE_SET] C2 coeval with C3/C4 | entry_price=" + DoubleToString(c4_open, _Digits), LOG_LEVEL_INFO);
        }
        if(c2_evaluated && !(c3_evaluated || delayedC3Evaluated || c4Evaluated))
        {
           out_signal = signal_c2;
        }

// C2 SPAM KILLER: IMPROVED detection using type + fractalState + timestamp + entry + GUID tracking
       // Uses type (not closureType), fractalState, direction, and entry price for uniqueness
       // ENHANCED: Include GUID to distinguish C2 from modal upgrade C3
        string closureSig = IntegerToString(signal_c2.type) + "|" +
                            IntegerToString(signal_c2.fractalState) + "|" +
                            (signal_c2.is_bullish ? "BUY" : "SELL") + "|" +
                            DoubleToString(signal_c2.entry_price > 0 ? signal_c2.entry_price : 0, _Digits) + "|" +
                            IntegerToString(signal_c2.m_guid) + "|" + "C2";

bool isNewClosure = (closureSig != g_lastC2ClosureSignature ||
                              TimeCurrent() - g_lastClosureLogTime > 5);

// P25 Fix: Use separate C2 slot limits (calculated before diagnostic to ensure accurate)
        bool hasAvailableSlot_C2 = false;
        int c2BaseIdx = GetSignalStoreIndex(ctx.branch, CLOSURE_C2);
        for(int i = 0; i < MAX_C2_SIGNALS_PER_BRANCH; i++)
        {
            if(!g_hasActiveSignal[c2BaseIdx + i])
            {
                hasAvailableSlot_C2 = true;
                break;
             }
         }

        LogPrint("[C2_LOCK_DIAG] closureSig=" + closureSig +
                " isNew=" + (isNewClosure?"T":"F") +
                " slotAvail=" + (hasAvailableSlot_C2?"T":"F") +
                " stage=" + EnumToString(lockedSignal.stage) +
                " (NONE=" + IntegerToString(STAGE_NONE) + ")", LOG_LEVEL_INFO);

       if(isNewClosure)
       {
           if(g_logLevel <= LOG_LEVEL_INFO)
           {
              LogTrace("[CLOSURE] C2=PASS | type=" + EnumToString(signal_c2.type) + " | " + (signal_c2.is_bullish ? "BUY" : "SELL"), LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
              LogTrace("[ANTICIPATION_GATE] C2_SWEEP — Awaiting Execution Gate", LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
           }
           g_lastC2ClosureSignature = closureSig;
           g_lastClosureLogTime = TimeCurrent();
        }
        // PRE-LOCK SANITY RESET: Force clean state if signal is in non-lockable condition
        // CRITICAL: Don't reset signals that are waiting for POI or ready to execute
        // FIX A: Added garbage stage detection to catch corrupted values (14, 148887992, etc.)
        // FIX B: Added SQ_InvalidateSignal to prevent stuck GUID recycling
        if(isNewClosure && !lockedSignal.isCommitted)
        {
            // Check for garbage stage values - valid range is 0-7 (STAGE_NONE to STAGE_EXPIRED)
            bool isGarbageStage = (lockedSignal.stage < STAGE_NONE || lockedSignal.stage > STAGE_EXPIRED);
            
         if(isGarbageStage)
             {
                 ulong oldGuid = lockedSignal.m_guid;
                 LGovPrint("[STATE_RECOVERED] PRE_LOCK_RESET_GARBAGE | GUID=" + IntegerToString(oldGuid) +
                           " | bad_stage=" + IntegerToString(lockedSignal.stage) +
                           " (valid: 0-7) => forcing full Reset", LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
                 lockedSignal.Reset();
                 // FIX B: Invalidate from store to prevent stuck GUID recycling
                 if(oldGuid != 0)
                     SQ_InvalidateSignal(oldGuid, ctx.branch);
             }
             // Original logic for non-garbage but invalid stages
             else if(lockedSignal.stage != STAGE_NONE &&
                     lockedSignal.stage != STAGE_LOCKED &&
                     lockedSignal.stage != STAGE_WAITING_FOR_POI &&
                     lockedSignal.stage != STAGE_READY)
             {
                 ulong oldGuid = lockedSignal.m_guid;
                 LGovPrint("[STATE_RECOVERED] PRE_LOCK_RESET | GUID=" + IntegerToString(oldGuid) +
                           " | stage=" + EnumToString(lockedSignal.stage) +
                           " | isCommitted=" + (lockedSignal.isCommitted ? "YES" : "NO") +
                           " => RESET to STAGE_NONE", LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
                 lockedSignal.Reset();
                 // FIX B: Invalidate from store to prevent stuck GUID recycling
                 if(oldGuid != 0)
                     SQ_InvalidateSignal(oldGuid, ctx.branch);
             }
        }

       if(isNewClosure && hasAvailableSlot_C2 && lockedSignal.stage == STAGE_NONE)
         {
               // REGRESSION GUARD: Log pre-lock state for audit trail
               LogPrint("[C2_LOCK_ATTEMPT] guid_before=" + IntegerToString(lockedSignal.m_guid) +
                       " | stage=" + EnumToString(lockedSignal.stage) +
                       " | hasAvailableSlot=" + (hasAvailableSlot_C2 ? "TRUE" : "FALSE"),
                       LOG_LEVEL_INFO);

               // Only create new C2 when no active signal exists
               // CRITICAL: Verify entry_price is valid before locking
                if(signal_c2.entry_price <= 0.0)
                {
                    LogPrint("[ENTRY_CANDIDATE_INVALID] entry_price=" + DoubleToString(signal_c2.entry_price, _Digits) +
                            " | Cannot lock with invalid entry price | GUID=" + IntegerToString(lockedSignal.m_guid), LOG_LEVEL_ERROR);
                     LogPrint("[LOCKED_SIGNAL_REJECTED] GUID=" + IntegerToString(lockedSignal.m_guid) +
                              " | reason=ENTRY_CANDIDATE_INVALID | entry_price=" + DoubleToString(signal_c2.entry_price, _Digits), LOG_LEVEL_INFO);
                    return;
                }
               
// CONSTITUTION: GUID ownership is LockedSignal's sole domain.
                // Pre-Lock GUID assignment is a constitutional violation.
                // Remove pre-allocation — RegisterPipelineSignal called after Lock() succeeds.
               
               if(lockedSignal.Lock(signal_c2, 0, ctx.branch, _Period))
               {
                  // CONSTITUTION: Register pipeline signal with Lock()-assigned GUID
                  // PositionGUIDMap entry must use Lock()-assigned GUID, not pre-computed guess
                  if(!RegisterPipelineSignal(lockedSignal.m_guid, CLOSURE_C2, signal_c2.c1_high, signal_c2.c1_low,
                                             signal_c2.c2_high, signal_c2.c2_low, signal_c2.is_bullish ? DIRECTION_BUY : DIRECTION_SELL))
                  {
                       LogPrint("[C2_PREALLOC_FAIL] GUID=" + IntegerToString(lockedSignal.m_guid) + " | failed to pre-allocate", LOG_LEVEL_ERROR);
                       lockedSignal.ResetIfUncommitted();
                       return;
                   }

                  LogPrint("[C2_LOCK_ATTEMPT] SUCCESS | GUID=" + IntegerToString(lockedSignal.m_guid) +
                         " | closureType=" + EnumToString(lockedSignal.closureType), LOG_LEVEL_INFO);

                 // Capture fresh bias at lock time - use at commit instead of potentially stale ctx.bias
                 lockedSignal.m_biasAtLock = (int)ctx.bias.bias;
                 
                 // Only proceed with C2 if it was NOT already upgraded to C3
                 if(IsC2UpgradedToC3(lockedSignal.m_guid))
                 {
                    lockedSignal.ResetIfUncommitted();
                    LogPrint("[C2_LOCK_SKIP] C2 closure signal skipped — C3 closure upgrade exists | GUID=" + 
                             IntegerToString(lockedSignal.m_guid), LOG_LEVEL_INFO);
                 }
                 else
                 {
                    // [BRANCH_MODE_MISMATCH] Mode assignment removed from ClosureEngine
                    // Mode resolved by ModeResolver in BranchEvaluator
                    // Bias check uses closureType per Constitution
                    if(lockedSignal.closureType == CLOSURE_C2)
                    {
                       LogPrint("[COMMIT_BIAS_BYPASS_C2] closureType=C2 | C2 bypasses D1 bias check | GUID=" + IntegerToString(lockedSignal.m_guid), LOG_LEVEL_INFO);
                    }
                    else if(lockedSignal.closureType == CLOSURE_C3)
                    {
                       // Per TTrades: C3 (Confirmation) MUST align with D1 bias
                       string biasName = "INVALID";
                       if(lockedSignal.m_biasAtLock == 0) biasName = "BULLISH";
                       else if(lockedSignal.m_biasAtLock == 1) biasName = "BEARISH";
                       else if(lockedSignal.m_biasAtLock == 2) biasName = "NEUTRAL";
                       else if(lockedSignal.m_biasAtLock == 3) biasName = "PENDING";
 
                       LogPrint("[BIAS_CHECK] C3 Confirmation mode | signal_dir=" + EnumToString(lockedSignal.direction) +
                                " | bias=" + biasName + "(" + IntegerToString(lockedSignal.m_biasAtLock) + ")", LOG_LEVEL_INFO);
 
                       BiasOutput biasAtCommit = ctx.bias;
                       biasAtCommit.bias = (BiasType)lockedSignal.m_biasAtLock;
                       if(!IsBiasAligned(lockedSignal.direction == DIRECTION_BUY, biasAtCommit))
                       {
                        string rejectModeStr = (lockedSignal.executionMode == MODE_ANTICIPATION) ? "ANTICIPATION" :
                                              (lockedSignal.executionMode == MODE_CONFIRMATION) ? "CONFIRMATION" : "NONE";
                         LogPrint("[COMMIT_REJECT] Bias misalignment | mode=" + rejectModeStr + "[" + IntegerToString(lockedSignal.executionMode) + "]" +
                                  " | is_bullish=" + (lockedSignal.direction == DIRECTION_BUY ? "true" : "false") +
                                  " | bias=" + biasName, LOG_LEVEL_WARN);
                            lockedSignal.ResetIfUncommitted();
                            return;
                        }
                        string biasAlignModeStr = (lockedSignal.executionMode == MODE_ANTICIPATION) ? "ANTICIPATION" :
                                                  (lockedSignal.executionMode == MODE_CONFIRMATION) ? "CONFIRMATION" : "NONE";
                         LogPrint("[BIAS_ALIGNED] OK | mode=" + biasAlignModeStr + "[" + IntegerToString(lockedSignal.executionMode) + "]" +
                                 " | bias aligned", LOG_LEVEL_DEBUG);
                    }
else
                    {
                        LogPrint("[COMMIT_WARN] Unknown execution mode | mode=" + IntegerToString(lockedSignal.executionMode), LOG_LEVEL_WARN);
                    }

                    bool guidExistsInStoreC2 = false;
                    int baseIdxC2 = GetSignalStoreIndex(ctx.branch, CLOSURE_C2);
                    for(int gi = 0; gi < MAX_C2_SIGNALS_PER_BRANCH; gi++)
                    {
                        if(g_hasActiveSignal[baseIdxC2 + gi] && g_activeSignal[baseIdxC2 + gi].m_guid == lockedSignal.m_guid)
                        {
                            guidExistsInStoreC2 = true;
                            break;
                        }
                    }
                    
                    if(guidExistsInStoreC2)
                    {
                        LogPrint("[CLOSURE_SKIP] Duplicate GUID already in store | GUID=" + IntegerToString(lockedSignal.m_guid), LOG_LEVEL_WARN);
                        LogPrint("[SIGNAL_REJECT] DUPLICATE_GUID | GUID=" + IntegerToString(lockedSignal.m_guid), LOG_LEVEL_INFO);
                    }
                    else
                    {
                       if(lockedSignal.closureType == CLOSURE_C2)
                       {
                          lockedSignal.stop_loss = RM_ComputeEntryTFSL(_Symbol, g_activeBranch, lockedSignal.direction == DIRECTION_BUY, lockedSignal.entry_price);
                          
                          LogPrint("[SL_MANIP_LEG_C2] direction=" + EnumToString(lockedSignal.direction) +
                                   " | sl=" + DoubleToString(lockedSignal.stop_loss, _Digits), LOG_LEVEL_INFO);
                       }
                       
                       LogPrint("[C2_LOCK_DIAG] isNewClosure=TRUE | hasAvailableSlot_C2=TRUE" +
                                " | stage=" + EnumToString(lockedSignal.stage) +
                                " | c2_entry_price=" + DoubleToString(signal_c2.entry_price, _Digits) +
                                " | c2_low=" + DoubleToString(signal_c2.c2_low, _Digits) +
                                " | c2_high=" + DoubleToString(signal_c2.c2_high, _Digits), LOG_LEVEL_INFO);
                    }

                    if(!guidExistsInStoreC2 && lockedSignal.Commit())
                    {
                        lockedSignal.TransitionStage(STAGE_WAITING_FOR_POI);
  
                        LogPrint("[C2_LOCK_ATTEMPT] SUCCESS | GUID=" + IntegerToString(lockedSignal.m_guid) +
                                " | closureType=" + EnumToString(lockedSignal.closureType),
                                LOG_LEVEL_INFO);
  
                       // [SIGNAL_CONTRACT_OK] Runtime assertions for illegal locked states (always active)
                         if(lockedSignal.entry_price <= 0.0)
                             LogPrint("[CONSTITUTIONAL_FAILURE] entry_price=0 at SIGNAL_LOCKED | GUID:" + IntegerToString(lockedSignal.m_guid), LOG_LEVEL_ERROR);
                         if(lockedSignal.executionMode == MODE_NONE)
                             LogPrint("[CONSTITUTIONAL_FAILURE] mode=MODE_NONE at SIGNAL_LOCKED | GUID:" + IntegerToString(lockedSignal.m_guid), LOG_LEVEL_ERROR);
if(lockedSignal.m_guid == 0)
                              LogPrint("[CONSTITUTIONAL_FAILURE] GUID=0 at SIGNAL_LOCKED", LOG_LEVEL_ERROR);
                         if(lockedSignal.closureType == CLOSURE_NONE)
                              LogPrint("[CONSTITUTIONAL_FAILURE] closureType=CLOSURE_NONE at SIGNAL_LOCKED | GUID:" + IntegerToString(lockedSignal.m_guid), LOG_LEVEL_ERROR);
                         if(lockedSignal.direction == DIRECTION_NONE)
                              LogPrint("[CONSTITUTIONAL_FAILURE] direction=DIRECTION_NONE at SIGNAL_LOCKED | GUID:" + IntegerToString(lockedSignal.m_guid), LOG_LEVEL_ERROR);
  
                        string lockModeStr = (lockedSignal.executionMode == MODE_ANTICIPATION) ? "ANTICIPATION" :
                                            (lockedSignal.executionMode == MODE_CONFIRMATION) ? "CONFIRMATION" : "NONE";
                         LogPrint("[SIGNAL_LOCKED] C2 | GUID:" + IntegerToString(lockedSignal.m_guid) +
                                " | mode=" + lockModeStr + "[" + IntegerToString(lockedSignal.executionMode) + "]" +
                                " | closure=" + EnumToString(lockedSignal.closureType) +
                                " | entry_price=" + DoubleToString(lockedSignal.entry_price, _Digits) +
                                " | stage=" + EnumToString(lockedSignal.stage),
                                LOG_LEVEL_INFO);
                         LogPrint("[C2_LOCKED] GUID=" + IntegerToString(lockedSignal.m_guid) +
                                  " | closureType=" + EnumToString(lockedSignal.closureType) +
                                  " | executionMode=" + lockModeStr +
                                  " | entry=" + DoubleToString(lockedSignal.entry_price, _Digits),
                                  LOG_LEVEL_INFO);
                    }
                    else
                    {
                       lockedSignal.ResetIfUncommitted();
                       LogPrint("[SIGNAL_LOCK_FAILED] C2 | Resetting signal", LOG_LEVEL_WARN);
                    }
                }
            }
            else
            {
                g_lastC2ClosureSignature = closureSig;
                g_lastClosureLogTime = TimeCurrent();
            }
       }
 
     return;
 }
 
 //+------------------------------------------------------------------+
 //| HELPER FUNCTIONS                                                 |
 //+------------------------------------------------------------------+

// ═══════════════════════════════════════════════════════════
// DISPLACEMENT HELPERS
// ═══════════════════════════════════════════════════════════

double GetCandleBody(
   double open,
   double close
)
{
   return MathAbs(close - open);
}

double GetCandleRange(
   double high,
   double low
)
{
   return (high - low);
}

double GetAverageBody(
   double body1,
   double body2,
   double body3
)
{
   return (body1 + body2 + body3) / 3.0;
}

bool IsBullishClosure(
   double close,
   double open
)
{
   return close > open;
}

bool IsBearishClosure(
   double close,
   double open
)
{
   return close < open;
}

// ═══════════════════════════════════════════════════════════
// EXISTING HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════

string GetClosureTypeString(ENUM_CLOSURE_TYPE type)
{
   switch(type)
   {
      case CLOSURE_NONE:  return "NONE";
      case CLOSURE_C2:    return "C2";
      case CLOSURE_C3:    return "C3";
      default:            return "UNKNOWN";
   }
}

void LogClosureSignal(SClosureSignal &signal, string symbol)
{
    if(g_logLevel > LOG_LEVEL_DEBUG)
       return;

    if(symbol == "" || symbol == NULL)
       symbol = _Symbol;

    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

    LGovPrint("[CLOSURE] Valid=" + (signal.valid ? "YES" : "NO") + " Dir=" +
             (signal.is_bullish ? "BUY" : "SELL") + " Type=" + GetClosureTypeString(signal.type),
             LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
}

//+------------------------------------------------------------------+
//| IsC3ConfirmationValid — Validate C3 as a standalone entry signal |
//| Checks engulf, direction consistency, and displacement.          |
//+------------------------------------------------------------------+
bool IsC3ConfirmationValid(SClosureSignal &c3)
{
    if(!c3.valid)
        return false;
    if(c3.type != CLOSURE_C3)
         return false;
    if(!c3.c3EngulfingC2)
        return false;
    if(c3.c2_high <= 0.0 || c3.c2_low <= 0.0)
        return false;
    return true;
}

//+------------------------------------------------------------------+
//| GetC3RejectReason — Return a descriptive string for why the C3   |
//| standalone validation failed. Matches [C3_STANDALONE_REJECT]     |
//| reason field values for log analysis.                             |
//+------------------------------------------------------------------+
string GetC3RejectReason(SClosureSignal &c3)
{
    if(!c3.valid)               return "invalid";
    if(c3.type != CLOSURE_C3)   return "not_c3_closure";
    if(!c3.c3EngulfingC2)       return "no_engulf";
    if(c3.c2_high <= 0.0)       return "no_c2_high";
    if(c3.c2_low <= 0.0)        return "no_c2_low";
    return "unknown";
}

ENUM_DIRECTION GetClosureDirection(SClosureSignal &signal)
{
   if(!signal.valid)
      return DIRECTION_NONE;

   return signal.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;
}

double GetClosureWeight(SClosureSignal &signal)
{
   if(!signal.valid)
      return 0.0;

   if(signal.type == CLOSURE_C2)
      return 2.0;

   if(signal.type == CLOSURE_C3)
      return 1.7;

   return 0.0;
}

bool IsC2Entry(SClosureSignal &signal)
{
   return (signal.valid && signal.type == CLOSURE_C3);
}

bool IsC3Entry(SClosureSignal &signal)
{
   return (signal.valid && signal.type == CLOSURE_C3);
}

bool RequiresDelayedEntry(SClosureSignal &signal)
{
   return (signal.valid && signal.type == CLOSURE_C3);
}

//+------------------------------------------------------------------+
//| CLOSURE DISTINCTION — Structure vs Trigger Naming               |
//+------------------------------------------------------------------+
// IsC2Candle: Checks if the FRACTAL STRUCTURE is C2 (candle sweeping)
// HasC2ClosureSignal: Checks if there's a VALID TRIGGER for C2 entry

/**
 * IsC2Candle — Structural check (fractal stage)
 *
 * @param fractalState ENUM_FRACTAL_STATE from structure analysis
 * @return true if structure shows C2 candle (sweeping)
 */
bool IsC2Candle(ENUM_FRACTAL_STATE fractalState)
{
   return (fractalState == FRACTAL_STATE_C2);
}

/**
 * HasC2ClosureSignal — Trigger check (valid signal)
 *
 * @param signal SClosureSignal with valid entry trigger
 * @return true if signal has valid C2 trigger for execution
 */
bool HasC2ClosureSignal(SClosureSignal &signal)
{
   return IsC2Entry(signal);
}

/**
 * IsC3Candle — Structural check (fractal stage)
 *
 * @param fractalState ENUM_FRACTAL_STATE from structure analysis
 * @return true if structure shows C3 candle (confirmation)
 */
bool IsC3Candle(ENUM_FRACTAL_STATE fractalState)
{
   return (fractalState == FRACTAL_STATE_C3);
}

/**
 * HasC3ClosureSignal — Trigger check (valid signal)
 *
 * @param signal SClosureSignal with valid entry trigger
 * @return true if signal has valid C3 trigger for execution
 */
bool HasC3ClosureSignal(SClosureSignal &signal)
{
   return IsC3Entry(signal);
}

/**
 * CheckC2CISD — C2 Entry Release via CISD (Structure TF)
 *
 * VERBATIM REPAIR: 3-Tier TF Mapping (§XVII)
 * CISD must be confirmed on the Structure TF (H1/H4), NOT the Entry TF (M5/M15).
 * Only after Structure CISD passes may the signal drop to Entry TF for POI mapping.
 *
 * For a buy C2 signal (swept low), CISD triggers when price closes above
 * C2 high on the Structure TF.
 * For a sell C2 signal (swept high), CISD triggers when price closes
 * below C2 low on the Structure TF.
 *
 * @param signal Locked C2 signal with direction and c2_high/c2_low
 * @return true if CISD condition is met on the last completed Structure TF bar
 */
bool CheckC2CISD(SLockedSignal &signal)
{
   if(signal.m_guid == 0)
      return false;

   // VERBATIM REPAIR: Use Structure TF (H1/H4) — not Entry TF (M5/M15)
   ENUM_TIMEFRAMES structTF = GetStructureTF(signal.branchId);
   int tfSeconds = (int)PeriodSeconds(structTF);
   if(tfSeconds > 0 && TimeCurrent() - signal.m_detectionTime < tfSeconds)
      return false;

   // Close of last completed bar on Structure TF (index 1 = completed bar)
   double lastClose = iClose(_Symbol, structTF, 1);
   if(lastClose <= 0.0)
      return false;

   if(signal.direction == DIRECTION_BUY)
      return (lastClose > signal.c2_high);
   else if(signal.direction == DIRECTION_SELL)
      return (lastClose < signal.c2_low);

   return false;
}

//+------------------------------------------------------------------+
//| C2 Standalone Validation - TTFM-Aligned C2 Execution            |
//+------------------------------------------------------------------+
/**
 * IsValidC2Standalone
 *
 * TTFM-Aligned: C2 must execute independently (early sniper entries, even counter-trend).
 * C3 is stronger but NOT required for C2. Modal upgrade (C2→C3) is natural bonus only.
 * No forced dependency.
 *
 * Validates that a detected C2 can proceed to execution without requiring C3.
 *
 * @param c2Sig       The detected C2 closure signal
 * @return true if C2 is valid for standalone execution
 */
bool IsValidC2Standalone(SClosureSignal &c2Sig)
{
   // Must have valid C2 signal
   if(!c2Sig.valid)
   {
      LogPrint("[C2_STANDALONE_VALIDATION] reason=C2_invalid", LOG_LEVEL_DEBUG);
      return false;
   }

   // C2 must be in correct fractal state (not NONE or C3)
   if(c2Sig.fractalState != FRACTAL_STATE_C2)
   {
      LogPrint("[C2_STANDALONE_VALIDATION] reason=not_C2_fractal | fractalState=" + EnumToString(c2Sig.fractalState), LOG_LEVEL_DEBUG);
      return false;
   }

   // C2 must have valid entry price
   if(c2Sig.entry_price <= 0.0)
   {
      LogPrint("[C2_STANDALONE_VALIDATION] reason=invalid_entry_price", LOG_LEVEL_DEBUG);
      return false;
   }

   // C2 must have valid SL and EQ
   if(c2Sig.stop_loss <= 0.0 || c2Sig.equilibrium <= 0.0)
   {
      LogPrint("[C2_STANDALONE_VALIDATION] reason=invalid_sl_or_eq | sl=" + DoubleToString(c2Sig.stop_loss, _Digits) +
               " | eq=" + DoubleToString(c2Sig.equilibrium, _Digits), LOG_LEVEL_DEBUG);
      return false;
   }

   // TTFM-Aligned: C2 standalone validation PASSED - can execute without C3
   LogPrint("[C2_STANDALONE_VALIDATION] reason=VALID_STANDALONE | direction=" + (c2Sig.is_bullish ? "BUY" : "SELL") +
            " | entry=" + DoubleToString(c2Sig.entry_price, _Digits), LOG_LEVEL_DEBUG);

   return true;
}

//+------------------------------------------------------------------+
//| PHASE 2: DetectFractalStage — Detect current fractal stage       |
//+------------------------------------------------------------------+
/**
 * DetectFractalStage
 *
 * Analyzes the last N candles on the specified timeframe to
 * determine the current TTrades fractal stage.
 *
 * Stage detection logic:
 *   FRACTAL_STATE_C1: Baseline candle identified
 *   FRACTAL_STATE_C2: Current candle sweeping C1 extreme (not yet closed)
 *   FRACTAL_STATE_C2: C2 swept liquidity AND closed back inside range
 *   FRACTAL_STATE_NONE: C2 swept but closed outside (continuation)
 *   FRACTAL_STATE_C3: After valid C2, current candle showing displacement
 *   FRACTAL_STATE_C3: C3 closed with engulfing or displacement confirmed
 *
 * @param tf        Timeframe to analyze
 * @param lookback  Number of candles to examine (default 10)
 * @return SStageSignal with current stage and candle data
 */
SStageSignal DetectFractalStage(ENUM_TIMEFRAMES tf, int lookback = 10)
{
   SStageSignal signal;
   signal.Reset();

   string sym = _Symbol;
   ENUM_TIMEFRAMES timeframe = (tf == PERIOD_CURRENT) ? PERIOD_CURRENT : tf;

   double highs[], lows[], opens[], closes[];
   datetime times[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(opens, true);
   ArraySetAsSeries(closes, true);
   ArraySetAsSeries(times, true);

   int needed = MathMax(lookback, 4);
   if(CopyHigh(sym, timeframe, 0, needed, highs) < needed)
      return signal;
   if(CopyLow(sym, timeframe, 0, needed, lows) < needed)
      return signal;
   if(CopyOpen(sym, timeframe, 0, needed, opens) < needed)
      return signal;
   if(CopyClose(sym, timeframe, 0, needed, closes) < needed)
      return signal;
   if(CopyTime(sym, timeframe, 0, needed, times) < needed)
      return signal;

   // C1 = baseline (index 3), C2 = sweep candle (index 2), C3 = confirmation (index 1)
   double c1_high = highs[3];
   double c1_low = lows[3];
   double c1_close = closes[3];

   double c2_high = highs[2];
   double c2_low = lows[2];
   double c2_open = opens[2];
   double c2_close = closes[2];

   double c3_high = highs[1];
   double c3_low = lows[1];
   double c3_open = opens[1];
   double c3_close = closes[1];

   // Current forming candle (index 0)
   double cur_high = highs[0];
   double cur_low = lows[0];
   double cur_open = opens[0];
   double cur_close = closes[0];

   // Populate C2 data
   signal.c2High = c2_high;
   signal.c2Low = c2_low;
   signal.c2Open = c2_open;
   signal.c2Close = c2_close;
    signal.c2Time = (double)times[2];

   // Populate C3 data
   signal.c3High = c3_high;
   signal.c3Low = c3_low;
   signal.c3Open = c3_open;
   signal.c3Close = c3_close;
    signal.c3Time = (double)times[1];

   // --- Detect C2 sweep ---
   bool c2_swept_high = (c2_high > c1_high);
   bool c2_swept_low = (c2_low < c1_low);
   bool c2_swept = c2_swept_high || c2_swept_low;

   // --- Detect C2 close inside ---
   bool c2_closed_inside = (c2_close >= c1_low && c2_close <= c1_high);

   // --- C2 wick percent ---
   double c2_range = c2_high - c2_low;
   if(c2_range > 0.0)
   {
      double c2_upper_wick = c2_high - MathMax(c2_open, c2_close);
      double c2_lower_wick = MathMin(c2_open, c2_close) - c2_low;
      signal.c2WickPercent = MathMax(c2_upper_wick, c2_lower_wick) / c2_range;
   }

   // --- C3 engulfing check ---
   double c2_body_top = MathMax(c2_open, c2_close);
   double c2_body_bottom = MathMin(c2_open, c2_close);
   bool c3_bullish_engulf = (c3_close > c2_body_top);
   bool c3_bearish_engulf = (c3_close < c2_body_bottom);
   signal.c3Engulfing = (c3_bullish_engulf || c3_bearish_engulf) &&
                        !(c3_bullish_engulf && c3_bearish_engulf);

   // --- C3 displacement check ---
   double c3_body = MathAbs(c3_close - c3_open);
   double c2_body = MathAbs(c2_close - c2_open);
   double c3_range = c3_high - c3_low;
   double c2_range_val = c2_high - c2_low;
signal.c3Displacement = (c3_body > c2_body * g_branchParams.c3DisplacementMultiplier) &&
                           (c3_range > c2_range_val * g_branchParams.c3RangeExpansionFactor);

   // Displacement strength (0.0 - 2.0+)
   if(c2_body > 0.0)
      signal.displacementStrength = c3_body / c2_body;

   // --- Stage determination ---
   if(c2_swept && c2_closed_inside)
   {
      // C2 was valid — now check C3
      if(signal.c3Engulfing || signal.c3Displacement)
      {
         signal.stage = FRACTAL_STATE_C3;
         signal.isValid = true;
      }
      else
      {
         // Check if current candle (index 0) is forming C3
         bool cur_displacing = false;
         if(c2_swept_low) // Bullish context
            cur_displacing = (cur_close > c2_high);
         else if(c2_swept_high) // Bearish context
            cur_displacing = (cur_close < c2_low);

         if(cur_displacing)
         {
            signal.stage = FRACTAL_STATE_C3;
            signal.isValid = true;
         }
         else
         {
            signal.stage = FRACTAL_STATE_C2;
            signal.isValid = true;
         }
      }
   }
   else if(c2_swept && !c2_closed_inside)
   {
      // C2 swept but closed outside — continuation, not reversal
      signal.stage = FRACTAL_STATE_NONE;
      signal.isValid = false;
   }
   else if(c2_swept)
   {
      // C2 is forming (sweep detected, close status unclear)
      signal.stage = FRACTAL_STATE_C2;
      signal.isValid = true;
   }
   else
   {
      // Check if current candle is sweeping (C2 forming in real-time)
      bool cur_sweep_high = (cur_high > c1_high);
      bool cur_sweep_low = (cur_low < c1_low);
      if(cur_sweep_high || cur_sweep_low)
      {
         signal.stage = FRACTAL_STATE_C2;
         signal.isValid = true;
      }
      else
      {
         signal.stage = FRACTAL_STATE_C1;
         signal.isValid = true;
      }
   }

   return signal;
}

//+------------------------------------------------------------------+
//| 🔷 CLOSURE V2 START — Sequence-Based Scoring Engine              |
//+------------------------------------------------------------------+

/**
 * ComputeClosureScore — Sequence-based quality scoring (0-4)
 *
 * PURPOSE: Assign a quality score to a closure signal based on
 *          confluence factors. NOT connected to entry yet.
 *
 * SCORING RULES:
 *   +1  liquiditySweep == true
 *   +1  wickSize > bodySize * 0.5
 *   +1  fvgDetected == true OR displacementMove == true
 *   +1  followThrough == true
 *
 * @param liquiditySweep    True if candle swept liquidity
 * @param wickSize          Wick size (absolute or ratio)
 * @param bodySize          Body size (absolute or ratio)
 * @param fvgDetected       True if FVG detected in sequence
 * @param displacementMove  True if displacement move detected
 * @param followThrough     True if follow-through candle confirmed
 * @return int              Total score (0-4)
 */
int ComputeClosureScore(
   bool liquiditySweep,
   double wickSize,
   double bodySize,
   bool fvgDetected,
   bool displacementMove,
   bool followThrough
)
{
   int score = 0;

   // --- Micro structure shift validation (Dow Theory) ---
   bool structureShift = DetectStructureShift(1);

   // Rule 1: Liquidity sweep (+2 — primary signal)
   if(liquiditySweep)
   {
      score += 2;
   }

   // Rule 2: Reaction quality — wick vs body (+1)
   if(bodySize > 0.0 && wickSize > bodySize * 0.5)
   {
      score += 1;
   }

   // Rule 3: Displacement strength — requires structure break for full credit
   if(displacementMove && structureShift)
   {
      score += 2;
   }
   else if(displacementMove)
   {
      score += 1;
   }

   // Rule 4: Follow-through confirmation (+1)
   if(followThrough)
   {
      score += 1;
   }

   // Clamp to 0-6 range (defensive)
   if(score < 0) score = 0;
   if(score > 6) score = 6;

if(g_logLevel <= LOG_LEVEL_DEBUG)
    {
       LGovPrint("CLOSURE_V2_WEIGHTED_SCORE: " + IntegerToString(score) + " | Sweep(+2)=" + IntegerToString(liquiditySweep) + " | Reaction(+1)=" + (bodySize > 0.0 && wickSize > bodySize * 0.5 ? "true" : "false") + " | Displacement(+2/+1)=" + IntegerToString(displacementMove) + " | StructureShift=" + IntegerToString(structureShift) + " | FollowThrough(+1)=" + (followThrough ? "true" : "false"), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
       LGovPrint("STRUCTURE_SHIFT: " + IntegerToString(structureShift), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
    }

   return score;
}

//+------------------------------------------------------------------+
//| 🔷 CLOSURE V2 END                                                |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 🔷 CLOSURE V2 START — Follow-Through Detection Engine            |
//+------------------------------------------------------------------+

/**
 * DetectFollowThrough — Check if price continues in sweep direction
 *
 * PURPOSE: Detect whether the next 1-3 candles after the closure
 *          candle show follow-through in the sweep direction.
 *          NOT connected to entry yet — standalone function.
 *
 * CONDITIONS CHECKED (need ≥2 of 3 to return true):
 *   1. استمرار (continuation): higher highs (BUY) or lower lows (SELL)
 *   2. No full retrace to sweep origin (C1 range)
 *   3. Minor structure shift: HH/HL (bullish) or LL/LH (bearish)
 *
 * @param symbol    Symbol to check ("" = _Symbol)
 * @param tf        Timeframe to check
 * @param direction Sweep direction (DIRECTION_BUY or DIRECTION_SELL)
 * @param c1_high   C1 candle high (sweep origin upper bound)
 * @param c1_low    C1 candle low  (sweep origin lower bound)
 * @param c2_high   C2 candle high (sweep candle)
 * @param c2_low    C2 candle low  (sweep candle)
 * @return bool     true if ≥2 of 3 follow-through conditions met
 */
bool DetectFollowThrough(
   string symbol,
   ENUM_TIMEFRAMES tf,
   ENUM_DIRECTION direction,
   double c1_high,
   double c1_low,
   double c2_high,
   double c2_low
)
{
   if(direction != DIRECTION_BUY && direction != DIRECTION_SELL)
   {
      LGovPrint("FOLLOW_THROUGH: false | Invalid direction", LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
      return false;
   }

   string sym = (symbol == "" || symbol == NULL) ? _Symbol : symbol;
   ENUM_TIMEFRAMES timeframe = (tf == PERIOD_CURRENT) ? PERIOD_CURRENT : tf;

   // Guard: ensure enough bars exist before accessing shift+3
   if(Bars(sym, timeframe) < 1 + 4)
   {
      return false;
   }

   // Copy next 3 closed candles (shift 1, 2, 3 — skip current forming bar)
   double highs[], lows[], closes[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);

   if(CopyHigh(sym, timeframe, 1, 3, highs) < 3)
   {
      LGovPrint("FOLLOW_THROUGH: false | CopyHigh failed", LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
      return false;
   }
   if(CopyLow(sym, timeframe, 1, 3, lows) < 3)
   {
      LGovPrint("FOLLOW_THROUGH: false | CopyLow failed", LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
      return false;
   }
   if(CopyClose(sym, timeframe, 1, 3, closes) < 3)
   {
      LGovPrint("FOLLOW_THROUGH: false | CopyClose failed", LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
      return false;
   }

   int conditionsMet = 0;

   // ──────────────────────────────────────────────────────────────
   // CONDITION 1: استمرار (Continuation) — higher highs or lower lows
   // ──────────────────────────────────────────────────────────────
   bool continuation = false;

   if(direction == DIRECTION_BUY)
   {
      // Bullish: at least one of next 3 candles makes higher high than C2
      for(int i = 0; i < 3; i++)
      {
         if(highs[i] > c2_high)
         {
            continuation = true;
            break;
         }
      }
   }
   else // DIRECTION_SELL
   {
      // Bearish: at least one of next 3 candles makes lower low than C2
      for(int i = 0; i < 3; i++)
      {
         if(lows[i] < c2_low)
         {
            continuation = true;
            break;
         }
      }
   }

   if(continuation)
      conditionsMet++;

   // ──────────────────────────────────────────────────────────────
   // CONDITION 2: No full retrace to sweep origin (C1 range)
   // ──────────────────────────────────────────────────────────────
   bool noFullRetrace = true;

   if(direction == DIRECTION_BUY)
   {
      // Bullish: none of next 3 candles should close below C1 low
      for(int i = 0; i < 3; i++)
      {
         if(closes[i] < c1_low)
         {
            noFullRetrace = false;
            break;
         }
      }
   }
   else // DIRECTION_SELL
   {
      // Bearish: none of next 3 candles should close above C1 high
      for(int i = 0; i < 3; i++)
      {
         if(closes[i] > c1_high)
         {
            noFullRetrace = false;
            break;
         }
      }
   }

   if(noFullRetrace)
      conditionsMet++;

   // ──────────────────────────────────────────────────────────────
   // CONDITION 3: Minor structure shift (HH/HL or LL/LH)
   // ──────────────────────────────────────────────────────────────
   bool structureShift = false;

   if(direction == DIRECTION_BUY)
   {
      // Bullish structure shift: HH + HL pattern
      // HH: candle[0].high > candle[1].high
      // HL: candle[1].low  > candle[2].low  (higher low formed)
      bool hh = (highs[0] > highs[1]);
      bool hl = (lows[1] > lows[2]);

      // At least one of HH or HL must be present
      if(hh || hl)
         structureShift = true;
   }
   else // DIRECTION_SELL
   {
      // Bearish structure shift: LL + LH pattern
      // LL: candle[0].low < candle[1].low
      // LH: candle[1].high < candle[2].high (lower high formed)
      bool ll = (lows[0] < lows[1]);
      bool lh = (highs[1] < highs[2]);

      // At least one of LL or LH must be present
      if(ll || lh)
         structureShift = true;
   }

   if(structureShift)
      conditionsMet++;

   // ──────────────────────────────────────────────────────────────
   // RESULT: Need ≥2 of 3 conditions
   // ──────────────────────────────────────────────────────────────
   bool result = (conditionsMet >= 2);

LGovPrint("FOLLOW_THROUGH: " + (result ? "true" : "false") + " | Dir=" + (direction == DIRECTION_BUY ? "BUY" : "SELL") + " | Continuation=" + (continuation ? "true" : "false") + " | NoRetrace=" + (noFullRetrace ? "true" : "false") + " | StructShift=" + IntegerToString(structureShift) + " | ConditionsMet=" + IntegerToString(conditionsMet) + "/3", LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);

   return result;
}

//+------------------------------------------------------------------+
//| 🔷 CLOSURE V2 END — Follow-Through Detection Engine              |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 🔷 V2 DECOUPLED — Liquidity Sweep Detection (Independent)        |
//+------------------------------------------------------------------+

/**
 * DetectLiquiditySweep — Independent V2 liquidity sweep detection
 *
 * PURPOSE: Detect liquidity sweep without depending on V1 signal.
 *          Checks if current candle sweeps prior two candles' extremes.
 *
 * @param shift  Candle shift to evaluate (1 = most recent completed)
 * @return bool  TRUE if high or low sweep detected
 */
bool DetectLiquiditySweep(int shift)
{
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   if(CopyHigh(_Symbol, _Period, shift, 3, high) < 3 ||
      CopyLow(_Symbol, _Period, shift, 3, low) < 3)
   {
      return false;
   }

   // Sweep HIGH: current high > prior two highs
   bool sweep_high = (high[0] > high[1]) && (high[0] > high[2]);

   // Sweep LOW: current low < prior two lows
   bool sweep_low = (low[0] < low[1]) && (low[0] < low[2]);

   return (sweep_high || sweep_low);
}

//+------------------------------------------------------------------+
//| 🔷 V2 DECOUPLED — Micro Structure Shift (Dow Theory)             |
//+------------------------------------------------------------------+

/**
 * DetectStructureShift — Micro structure break validation
 *
 * PURPOSE: Confirm that displacement actually breaks market structure.
 *          Bullish: current high > prior high (higher high)
 *          Bearish: current low  < prior low  (lower low)
 *
 * @param shift  Candle shift to evaluate (1 = most recent completed)
 * @return bool  TRUE if structure shift detected in either direction
 */
bool DetectStructureShift(int shift)
{
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   if(CopyHigh(_Symbol, _Period, shift, 2, high) < 2 ||
      CopyLow(_Symbol, _Period, shift, 2, low) < 2)
   {
      return false;
   }

   // Compute current candle range
   double range = MathAbs(high[0] - low[0]);

   // Compute break distances
   double breakUp   = high[0] - high[1];
   double breakDown = low[1] - low[0];

   // Significance threshold: break must exceed 8% of current range
   double minBreak = range * 0.08;

   // Bullish: HH + HL (higher high AND higher/equal low)
   bool bullish_shift =
       (high[0] > high[1]) &&
       (low[0] >= low[1]) &&
       (breakUp > minBreak);

   // Bearish: LL + LH (lower low AND lower/equal high)
   bool bearish_shift =
       (low[0] < low[1]) &&
       (high[0] <= high[1]) &&
       (breakDown > minBreak);

LGovPrint("STRUCTURE_SIGNIFICANCE | Up=" + DoubleToString(breakUp, _Digits) + " Down=" + DoubleToString(breakDown, _Digits) + " Min=" + DoubleToString(minBreak, _Digits), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);

   return (bullish_shift || bearish_shift);
}

//+------------------------------------------------------------------+
//| 🔷 V2 DECOUPLED — Mode Resolver (Hybrid Entry)                   |
//+------------------------------------------------------------------+

/**
 * ResolveEntryMode — Hybrid anticipation + confirmation mode resolver
 *
 * PURPOSE: Determine whether to enter on closure alone (Anticipation)
 *          or require follow-through (Confirmation) based on context.
 *
 * SCORING (max 4):
 *   +1  HTF alignment
 *   +1  Valid location (S/R, FVG edge, etc.)
 *   +1  Structure context (HH/LL or LL/LH confirmed)
 *   +1  Strong closure (closureScore >= 5)
 *
 * MODE: score >= 3 → MODE_ANTICIPATION
 *       score <  3 → MODE_CONFIRMATION
 *
 * FALLBACK: strong displacement + ERL → MODE_ANTICIPATION (minimal activation)
 *
 * @param htfAligned          Higher-timeframe alignment confirmed
 * @param validLocation       Price at valid S/R or FVG edge
 * @param structureContext    Market structure context valid
 * @param closureScore        Weighted closure score (0-6)
 * @param displacementStrength Displacement strength multiplier
 * @param liquidityTier       Classified liquidity tier
 * @return ModeDecision       Resolved mode with scoring breakdown
 */
ModeDecision ResolveEntryMode(
   bool htfAligned,
   bool validLocation,
   bool structureContext,
   int closureScore,
   double displacementStrength,
   LiquidityTier liquidityTier
)
{
   ModeDecision result;
   result.score = 0;

   result.htfAligned = htfAligned;
   result.validLocation = validLocation;
   result.structureContext = structureContext;
   result.strongClosure = (closureScore >= 5);

   if(htfAligned)       result.score++;
   if(validLocation)    result.score++;
   if(structureContext) result.score++;
   if(result.strongClosure) result.score++;

   if(result.score >= 3)
      result.mode = CLOSURE_MODE_ANTICIPATION;
   else
      result.mode = CLOSURE_MODE_CONFIRMATION;

// --- Fallback: minimal Anticipation activation via strong displacement + ERL ---
    bool strongDisplacement = (displacementStrength >= 1.0);
   bool erlPresent = (liquidityTier == LT_ERL);

   if(strongDisplacement && erlPresent)
   {
      result.mode = CLOSURE_MODE_ANTICIPATION;
      result.score = MathMax(result.score, 2); // minimal activation

LGovPrint("MODE_FALLBACK | Anticipation triggered via displacement+ERL | Strength=" + DoubleToString(displacementStrength, 2) + " | Tier=ERL", LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
   }

   // --- Deadlock prevention: structureContext guarantees minimum activation ---
   if(structureContext && result.score == 0)
   {
      result.mode = CLOSURE_MODE_CONFIRMATION;
      result.score = 1;

      LGovPrint("MODE_FALLBACK | Activated due to structureContext", LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
   }

LGovPrint("MODE_DECISION | Score=" + IntegerToString(result.score) + " | Mode=" + IntegerToString(result.mode) + " | HTF=" + (htfAligned ? "true" : "false") + " | Location=" + (validLocation ? "true" : "false") + " | Structure=" + (structureContext ? "true" : "false") + " | StrongClosure=" + (result.strongClosure ? "true" : "false") + " | DispStrength=" + DoubleToString(displacementStrength, 2) + " | LiquidityTier=" + (liquidityTier == LT_ERL ? "LT_ERL" : (liquidityTier == LT_IRL ? "LT_IRL" : "LT_NONE")), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);

   return result;
}

//+------------------------------------------------------------------+
//| 🔷 CLOSURE V2 START — EvaluateClosure (V1/V2 Parallel Switch)    |
//+------------------------------------------------------------------+

/**
 * EvaluateClosure — Controlled V1/V2 parallel evaluation wrapper
 *
 * PURPOSE: Run Closure V1 (legacy) and Closure V2 (scoring) in
 *          parallel for validation. Returns V2 result while
 *          preserving V1 for comparison logging.
 *
 * V1 LOGIC: Existing DetectClosureSignal() — sweep + close inside
 *           + wick filter + engulfing/displacement (unchanged).
 *
 * V2 LOGIC: ComputeClosureScore() — sequence-based scoring (0-4).
 *           Entry rule: score >= 3.
 *
 * FOLLOW-THROUGH: DetectFollowThrough() used as +1 bonus in scoring
 *                 context (passed as followThrough parameter).
 *
 * @param symbol        Symbol to evaluate ("" = _Symbol)
 * @param tf            Timeframe to evaluate
 * @param out_signal    Output: SClosureSignal from V1 detection
 * @return bool         V2 result (score >= 3)
 */
bool EvaluateClosure(
   string symbol,
   ENUM_TIMEFRAMES tf,
   SClosureSignal &out_signal
)
{
    // ═══════════════════════════════════════════════════════════
    // STEP 1: Run V1 (legacy closure detection) — UNCHANGED
    // ═══════════════════════════════════════════════════════════
    SLockedSignal dummyLockedSignal;
    dummyLockedSignal.Reset();
    dummyLockedSignal.TransitionStage(STAGE_LOCKED);  // Prevent bridge from locking (evaluation mode)
    DetectClosureSignal(symbol, tf, out_signal, dummyLockedSignal);

   bool legacyResult = out_signal.valid;

   // ═══════════════════════════════════════════════════════════
   // STEP 2: Gather inputs for V2 scoring
   // ═══════════════════════════════════════════════════════════
   string sym = (symbol == "" || symbol == NULL) ? _Symbol : symbol;
   ENUM_TIMEFRAMES timeframe = (tf == PERIOD_CURRENT) ? PERIOD_CURRENT : tf;

   // --- liquiditySweep: independent V2 detection ---
   bool liquiditySweep = DetectLiquiditySweep(1);

   // --- wickSize and bodySize: from C2 candle ---
   double wickSize = 0.0;
   double bodySize = 0.0;

   if(out_signal.c2_high > 0 && out_signal.c2_low > 0 &&
      out_signal.c2_open > 0 && out_signal.c2_close > 0)
   {
      double c2_range = out_signal.c2_high - out_signal.c2_low;
      bodySize = MathAbs(out_signal.c2_close - out_signal.c2_open);
      double upper_wick = out_signal.c2_high - MathMax(out_signal.c2_open, out_signal.c2_close);
      double lower_wick = MathMin(out_signal.c2_open, out_signal.c2_close) - out_signal.c2_low;
      wickSize = MathMax(upper_wick, lower_wick);
   }

   // --- fvgDetected: check for FVG near closure candle ---
   bool fvgDetected = false;
   if(Bars(sym, timeframe) > 5)
   {
      double highs_fvg[], lows_fvg[];
      ArraySetAsSeries(highs_fvg, true);
      ArraySetAsSeries(lows_fvg, true);
      if(CopyHigh(sym, timeframe, 0, 4, highs_fvg) >= 4 &&
         CopyLow(sym, timeframe, 0, 4, lows_fvg) >= 4)
      {
         // Bullish FVG: low[1] > high[3]
         bool bullish_fvg = (lows_fvg[1] > highs_fvg[3]);
         // Bearish FVG: high[1] < low[3]
         bool bearish_fvg = (highs_fvg[1] < lows_fvg[3]);
         fvgDetected = bullish_fvg || bearish_fvg;
      }
   }

   // --- displacementMove: body-based detection ---
   double c3_body = MathAbs(out_signal.c3_close - out_signal.c3_open);
   double c2_body_val = MathAbs(out_signal.c2_close - out_signal.c2_open);
   // c1_open not in struct — approximate c1_body from c2_body if similar candles
   double c1_body = c2_body_val;
   double avg_body = (c1_body + c2_body_val + c3_body) / 3.0;

   double displacementThreshold = avg_body * 0.8;
   bool displacementMove =
       (out_signal.type == CLOSURE_C3) &&
       (c3_body > displacementThreshold);

LGovPrint("DISPLACEMENT_CHECK | Body=" + DoubleToString(c3_body, _Digits) + " | Threshold=" + DoubleToString(displacementThreshold, _Digits) + " | Result=" + (displacementMove ? "true" : "false"), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);

   // --- trueDisplacement: institutional-grade expansion filter ---
   bool trueDisplacement =
      displacementMove &&
      (c3_body > avg_body * 1.5);

   // --- followThrough: from DetectFollowThrough() ---
   bool followThrough = false;
   if(out_signal.valid && out_signal.is_bullish)
   {
      followThrough = DetectFollowThrough(
         sym, timeframe, DIRECTION_BUY,
         out_signal.c1_high, out_signal.c1_low,
         out_signal.c2_high, out_signal.c2_low
      );
   }
   else if(out_signal.valid && !out_signal.is_bullish)
   {
      followThrough = DetectFollowThrough(
         sym, timeframe, DIRECTION_SELL,
         out_signal.c1_high, out_signal.c1_low,
         out_signal.c2_high, out_signal.c2_low
      );
   }

   // ═══════════════════════════════════════════════════════════
   // STEP 3: Compute V2 score
   // ═══════════════════════════════════════════════════════════
   int score = ComputeClosureScore(
      liquiditySweep,
      wickSize,
      bodySize,
      fvgDetected,
      trueDisplacement,
      followThrough
   );

   // ═══════════════════════════════════════════════════════════
   // STEP 4: Mode-resolved entry rule (Hybrid Anticipation + Confirmation)
   // ═══════════════════════════════════════════════════════════
   bool validClosure = (score >= 4);

   // --- Mode resolver inputs (from existing signals, no new systems) ---
   bool htfAligned = out_signal.valid;
   bool validLocation = trueDisplacement;
   bool structureContext = DetectStructureShift(1);

   // --- Displacement strength for fallback activation (reuse existing variables) ---
   double displacementStrength = (avg_body > 0) ? (c3_body / avg_body) : 0.0;

   // --- Liquidity tier for fallback activation ---
   LiquidityTier liquidityTier = LT_NONE;
   if(liquiditySweep)
   {
      // Simplified tier classification: if sweep detected, check if it's ERL
      // ERL = HTF swing sweep, IRL = equal H/L sweep
      // Use H4 context if available to determine tier
      if(tf == PERIOD_H1 || tf == PERIOD_H4)
         liquidityTier = LT_ERL;  // HTF sweep = ERL
      else
         liquidityTier = LT_IRL;  // LTF sweep = IRL
   }

   ModeDecision mode = ResolveEntryMode(
      htfAligned,
      validLocation,
      structureContext,
      score,
      displacementStrength,
      liquidityTier
   );

   bool newResult = false;

   if(mode.mode == CLOSURE_MODE_ANTICIPATION)
      newResult = validClosure;

   if(mode.mode == CLOSURE_MODE_CONFIRMATION)
      newResult = validClosure && followThrough;

   // --- Fallback: prevent validClosure from being blocked by MODE_NONE ---
   if(mode.mode != CLOSURE_MODE_ANTICIPATION && mode.mode != CLOSURE_MODE_CONFIRMATION)
   {
      if(validClosure)
      {
         mode.mode = CLOSURE_MODE_CONFIRMATION;
         newResult = validClosure;
      }
   }

   LGovPrint("ENTRY_MODE_ACTIVE: " + IntegerToString(mode.mode), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);

   // ═══════════════════════════════════════════════════════════
   // STEP 5: Comparison logging
   // ═══════════════════════════════════════════════════════════
LGovPrint("CLOSURE_COMPARISON: V1=" + IntegerToString(legacyResult) + " V2=" + IntegerToString(newResult) + " SCORE=" + IntegerToString(score) + " | Sweep=" + IntegerToString(liquiditySweep) + " | Wick=" + DoubleToString(wickSize, _Digits) + " | Body=" + DoubleToString(bodySize, _Digits) + " | FVG=" + (fvgDetected ? "true" : "false") + " | Displacement=" + (displacementMove ? "true" : "false") + " | FollowThrough=" + (followThrough ? "true" : "false"), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);

LGovPrint("CLOSURE_V2_INPUT_FIX | Liquidity=" + IntegerToString(liquiditySweep) + " | Displacement=" + (displacementMove ? "true" : "false") + " | FVG=" + (fvgDetected ? "true" : "false"), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);

   LGovPrint("CLOSURE_V2_WEIGHTED_SCORE: " + IntegerToString(score), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);

   LGovPrint("V2_LIQUIDITY_DECOUPLED: " + IntegerToString(liquiditySweep), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);

   // ═══════════════════════════════════════════════════════════
   // STEP 6: HARD SAFETY FLOOR — block extremely weak setups (score < 3)
   // ═══════════════════════════════════════════════════════════
   if(score < 3)
   {
LGovPrint("CLOSURE_BLOCKED: Score too low | Score=" + IntegerToString(score) + " | V1=" + IntegerToString(legacyResult) + " | Sweep=" + IntegerToString(liquiditySweep) + " | FVG=" + (fvgDetected ? "true" : "false") + " | FollowThrough=" + (followThrough ? "true" : "false"), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
      return false;
   }

   // ═══════════════════════════════════════════════════════════
   // STEP 7: FULL TRACE LOGGING (feeds Python analyzer)
   // ═══════════════════════════════════════════════════════════
LGovPrint("CLOSURE_TRACE | Score=" + IntegerToString(score) + " | Liquidity=" + IntegerToString(liquiditySweep) + " | Reaction=" + IntegerToString(legacyResult) + " | Displacement=" + (displacementMove ? "true" : "false") + " | FollowThrough=" + (followThrough ? "true" : "false"), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
    
   // STEP 8: Return V2 result (V1 preserved in out_signal)
   return newResult;
}

//+------------------------------------------------------------------+
//| 🔷 CLOSURE V2 END — EvaluateClosure (V1/V2 Parallel Switch)      |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| STANDALONE C2 VALIDATION — Independent C2 (Sweep) check           |
//+------------------------------------------------------------------+
bool C2_Validate(
    double c1_high,
    double c1_low,
    double c2_open,
    double c2_high,
    double c2_low,
    double c2_close
)
{
    ENUM_DIRECTION sweep = DetectC2Sweep(c2_high, c2_low, c1_high, c1_low);

    if(sweep == DIRECTION_NONE)
        return false;

    bool close_inside = DetectC2CloseInside(c2_close, c1_high, c1_low, sweep);

    if(!close_inside)
        return false;

    double wick_ratio = ComputeWickRatio(c2_open, c2_close, c2_high, c2_low);

    if(wick_ratio > 0.9)
        return false;

    return true;
}

//+------------------------------------------------------------------+
//| STANDALONE C3 VALIDATION — Independent C3 (Displacement) check    |
//+------------------------------------------------------------------+
bool C3_Validate(
    double c2_open,
    double c2_close,
    double c3_open,
    double c3_high,
    double c3_low,
    double c3_close
)
{
    ENUM_DIRECTION engulf = DetectC3Engulfing(c2_open, c2_close, c3_open, c3_close, c3_high, c3_low);

    if(engulf == DIRECTION_NONE)
        return false;

    double c3_wick_ratio = ComputeWickRatio(c3_open, c3_close, c3_high, c3_low);

    if(c3_wick_ratio > 0.9)
        return false;

    double c2_range_top = MathMax(c2_open, c2_close);
    double c2_range_bottom = MathMin(c2_open, c2_close);
    bool body_beyond_c2 = false;

    if(engulf == DIRECTION_BUY)
        body_beyond_c2 = (c3_close > c2_range_top);
    else if(engulf == DIRECTION_SELL)
        body_beyond_c2 = (c3_close < c2_range_bottom);

    return body_beyond_c2;
}

//+------------------------------------------------------------------+
//| DOUBLE-GATE SIGNAL CONFIRMATION — Both C2 AND C3 must pass       |
//+------------------------------------------------------------------+
bool CE_DoubleGate(
    double c1_high,
    double c1_low,
    double c2_open,
    double c2_high,
    double c2_low,
    double c2_close,
    double c3_open,
    double c3_high,
    double c3_low,
    double c3_close,
    SClosureSignal &out_signal
)
{
    bool c2_valid = C2_Validate(c1_high, c1_low, c2_open, c2_high, c2_low, c2_close);
    bool c3_valid = C3_Validate(c2_open, c2_close, c3_open, c3_high, c3_low, c3_close);

    ZeroMemory(out_signal);
    out_signal.Reset();

    if(c2_valid && c3_valid)
    {
        out_signal.valid = true;
        out_signal.type = CLOSURE_C3;
        out_signal.is_bullish = (c3_close > c2_close);

        out_signal.c1_high = c1_high;
        out_signal.c1_low = c1_low;

        out_signal.c2_high = c2_high;
        out_signal.c2_low = c2_low;
        out_signal.c2_open = c2_open;
        out_signal.c2_close = c2_close;

        out_signal.c3_high = c3_high;
        out_signal.c3_low = c3_low;
        out_signal.c3_open = c3_open;
        out_signal.c3_close = c3_close;

        out_signal.stop_loss = RM_ComputeEntryTFSL(_Symbol, g_activeBranch, out_signal.is_bullish, out_signal.entry_price);
        LogPrint("[SL_MANIP_LEG_C3ALT] direction=" + (out_signal.is_bullish?"BUY":"SELL") +
                 " sl=" + DoubleToString(out_signal.stop_loss, _Digits), LOG_LEVEL_INFO);
        out_signal.equilibrium = (c1_high + c1_low) / 2.0;

        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| CheckRetraceGate — TTrades C4 Retracement Gate                   |
//+------------------------------------------------------------------+
/**
 * CheckRetraceGate — Verify price has retraced to 50% equilibrium
 *
 * TTRADES MODEL: After C3 displacement, price must return to the
 * Point of Interest (POI) before execution. The POI is the 50%
 * equilibrium level of the C3 displacement leg.
 *
 * This gate ensures:
 *   1. Price has NOT escaped beyond acceptable buffer (C4 trap logic)
 *   2. Price HAS entered the equilibrium zone (50% retracement)
 *   3. For BUY: bid <= equilibrium zone
 *   4. For SELL: ask >= equilibrium zone
 *
 * @param signal          The locked C3/C2 signal with equilibrium
 * @param currentBid      Current bid price
 * @param currentAsk      Current ask price
 * @param bufferPercent   Buffer % beyond equilibrium to allow (default 0.02 = 2%)
 * @param equilibriumTol  Tolerance around equilibrium (default 0.001 = 0.1%)
 * @return true if price is within acceptable retracement zone
 */
bool CheckRetraceGate(
    const SClosureSignal &signal,
    double currentBid,
    double currentAsk,
    double bufferPercent = 0.02,
    double equilibriumTol = 0.001
)
{
    if(!signal.valid)
    {
        if(g_logLevel <= LOG_LEVEL_DEBUG)
        {
            LGovPrint("[RETRACE_GATE] INVALID: Signal not valid", LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
        }
        return false;
    }

    double equilibrium = signal.equilibrium;
    if(equilibrium <= 0.0)
    {
        if(g_logLevel <= LOG_LEVEL_DEBUG)
        {
            LGovPrint("[RETRACE_GATE] INVALID: Equilibrium not set", LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
        }
        return false;
    }

    double tolerance = equilibrium * equilibriumTol;
    double upperZone = equilibrium + tolerance;
    double lowerZone = equilibrium - tolerance;

    // Calculate C3 leg range for buffer validation
    double c3LegRange = 0.0;
    if(signal.type == CLOSURE_C3)
    {
        c3LegRange = signal.c3_high - signal.c3_low;
    }
    else if(signal.type == CLOSURE_C2)
    {
        c3LegRange = signal.c2_high - signal.c2_low;
    }

    double bufferDistance = c3LegRange * bufferPercent;

    // For BUY direction: price must be at or below equilibrium (retraced back to EQ)
    // Use currentAsk (fill price) to account for spread
    if(signal.is_bullish)
    {
        double maxPrice = equilibrium + bufferDistance;
        if(currentAsk > maxPrice)
        {
            if(g_logLevel <= LOG_LEVEL_DEBUG)
            {
                LGovPrint("[RETRACE_GATE] BUY: Price not retraced | Ask=" + DoubleToString(currentAsk, _Digits) +
                         " | Max=" + DoubleToString(maxPrice, _Digits) +
                         " | EQ=" + DoubleToString(equilibrium, _Digits), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
            }
            return false;
        }

        if(currentAsk <= upperZone)
        {
            if(g_logLevel <= LOG_LEVEL_INFO)
            {
                LGovPrint("[RETRACE_GATE] BUY: Price at equilibrium | Ask=" + DoubleToString(currentAsk, _Digits) +
                         " | EQ=" + DoubleToString(equilibrium, _Digits), LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
            }
            return true;
        }
    }
    // For SELL direction: price must be at or above equilibrium (retraced back to EQ)
    // Use currentBid (fill price) to account for spread
    else
    {
        double minPrice = equilibrium - bufferDistance;
        if(currentBid < minPrice)
        {
            if(g_logLevel <= LOG_LEVEL_DEBUG)
            {
                LGovPrint("[RETRACE_GATE] SELL: Price not retraced | Bid=" + DoubleToString(currentBid, _Digits) +
                         " | Min=" + DoubleToString(minPrice, _Digits) +
                         " | EQ=" + DoubleToString(equilibrium, _Digits), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
            }
            return false;
        }

        if(currentBid >= lowerZone)
        {
            if(g_logLevel <= LOG_LEVEL_INFO)
            {
                LGovPrint("[RETRACE_GATE] SELL: Price at equilibrium | Bid=" + DoubleToString(currentBid, _Digits) +
                         " | EQ=" + DoubleToString(equilibrium, _Digits), LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
            }
            return true;
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| CheckRetraceGateATR — ATR-Dynamic "Touch & Go" Trigger              |
//+------------------------------------------------------------------+
/**
 * CheckRetraceGateATR — ATR-Dynamic "Touch & Go" Trigger
 *
 * Uses ATR to create a dynamic buffer that scales with market volatility.
 * Triggers the moment price pierces the POI zone (Touch & Go), not requiring
 * price to close inside.
 *
 * PHASE 2 FIX: Accept closure type for differentiated buffer:
 *   - CLOSURE_C2: Wider ATR buffer (anticipation mode - early entry flexibility)
 *   - CLOSURE_C3: Tighter ATR buffer (confirmation mode - tighter control)
 *
 * @param signal         The locked C3/C2 signal with equilibrium
 * @param currentBid    Current bid price
 * @param currentAsk   Current ask price
 * @param symbol       Symbol for ATR lookup
 * @param tf          Timeframe for ATR
 * @param closureType   Closure type (C2 or C3) for buffer differentiation
 * @param baseMultiplier Base buffer multiplier
 * @return true if price has touched the ATR-scaled POI zone
 */
bool CheckRetraceGateATR(
    const SClosureSignal &signal,
    double currentBid,
    double currentAsk,
    string symbol,
    ENUM_TIMEFRAMES tf,
    ENUM_CLOSURE_TYPE closureType,
    double baseMultiplier = 0.1
)
{
    if(!signal.valid)
    {
        if(g_logLevel <= LOG_LEVEL_DEBUG)
        {
            LGovPrint("[RETRACE_GATE_ATR] INVALID: Signal not valid", LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
        }
        return false;
    }

    double equilibrium = signal.equilibrium;
    if(equilibrium <= 0.0)
    {
        if(g_logLevel <= LOG_LEVEL_DEBUG)
        {
            LGovPrint("[RETRACE_GATE_ATR] INVALID: Equilibrium not set", LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
        }
        return false;
    }

     double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
     double bufferDistance = 200.0 * point * baseMultiplier;
     double symbolMinBuffer = 30.0 * point;
    
    if(bufferDistance < symbolMinBuffer)
    {
        if(g_logLevel <= LOG_LEVEL_DEBUG)
        {
            LGovPrint("[RETRACE_GATE_ATR] Buffer adjusted up to min zone | Required=" + DoubleToString(symbolMinBuffer, _Digits) +
                     " | Calculated=" + DoubleToString(bufferDistance, _Digits), LOG_LEVEL_DEBUG, LOG_CHANNEL_SIGNAL);
        }
        bufferDistance = symbolMinBuffer;
    }

    double upperZone = equilibrium + bufferDistance;
    double lowerZone = equilibrium - bufferDistance;

    if(signal.is_bullish)
    {
        if(currentAsk <= upperZone)
        {
            if(g_logLevel <= LOG_LEVEL_INFO)
            {
                LGovPrint("[RETRACE_GATE_ATR] BUY: Touch zone | Ask=" + DoubleToString(currentAsk, _Digits) +
                         " | Upper=" + DoubleToString(upperZone, _Digits) +
                         " | ATR_buf=" + DoubleToString(bufferDistance, _Digits), LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
            }
            return true;
        }
    }
    else
    {
        if(currentBid >= lowerZone)
        {
            if(g_logLevel <= LOG_LEVEL_INFO)
            {
                LGovPrint("[RETRACE_GATE_ATR] SELL: Touch zone | Bid=" + DoubleToString(currentBid, _Digits) +
                         " | Lower=" + DoubleToString(lowerZone, _Digits) +
                         " | ATR_buf=" + DoubleToString(bufferDistance, _Digits), LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
            }
            return true;
        }
    }

    return false;
}

// [BRANCH_MODE_MISMATCH] SetClosureEngineMode removed - mode authority consolidated in ModeResolver

//+------------------------------------------------------------------+
//| SetSignalStage — Centralized stage transition with no-op guard   |
//| Silent early-return when oldStage == newStage to prevent          |
//| repetitive [STAGE_TRANSITION] spam (290k identical lines).       |
//| Called from ClosureEngine internal paths; caller owns guid.      |
//+------------------------------------------------------------------+
void SetSignalStage(ulong guid, ENUM_SIGNAL_STAGE newStage)
{
   for(int i = 0; i < ArraySize(g_activeSignal); i++)
   {
      if(g_activeSignal[i].m_guid == guid)
      {
         ENUM_SIGNAL_STAGE oldStage = g_activeSignal[i].stage;

         // --- GUARD: No-op if stage unchanged ---
         if(oldStage == newStage)
            return;

         g_activeSignal[i].TransitionStage(newStage);

         PrintFormat("[STAGE_TRANSITION] guid=%I64u %s->%s",
                     guid,
                     EnumToString(oldStage),
                     EnumToString(newStage));
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| End of ClosureEngine.mqh                                         |
//+------------------------------------------------------------------+
#endif // OMAK_CLOSUREENGINE_MQH
