//+------------------------------------------------------------------+
//|                                              FractalState.mqh |
//|                                    OmakFxYO — Fractal State Engine |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_FRACTALSTATE_MQH
#define OMAK_FRACTALSTATE_MQH

#property strict
#property copyright "OMAK"
#property version   "2.01"
#property description "Fractal State Machine — C1 → C2 → C3 → C4 Progression Tracking (TTrades Compliant)"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>       // ENUM_DIRECTION, DIRECTION_NONE, ENUM_FRACTAL_STATE
#include <OmakFxYO/core/LockedSignal.mqh>    // SLockedSignal
#include <OmakFxYO/core/ClosureEngine.mqh>   // DetectClosureSignal declaration
#include <OmakFxYO/core/FractalNarrative.mqh> // SFractalNarrative (v52.5+) - has extern declarations

//+------------------------------------------------------------------+
//| SFractalContext — Fractal Pattern State Container                 |
//| v52.5+: Links to fractal narrative via GUID for shared context   |
//+------------------------------------------------------------------+
struct SFractalContext
{
   ENUM_FRACTAL_STATE state;

   // v52.5+: Narrative GUID links to shared SFractalNarrative context
   ulong narrativeGUID;

   datetime c1_time;
   double c1_high;
   double c1_low;
   double c1_close;

   datetime c2_time;
   double c2_high;
   double c2_low;
   double c2_close;
   int c2_barIndex;

   datetime c3_time;
   double c3_high;
   double c3_low;
   double c3_close;

   datetime c4_time;
   double c4_high;
   double c4_low;
   double c4_close;

   bool liquidity_swept;
   ENUM_DIRECTION sweep_direction;
      // Indicates whether a C2 closure was detected/locked for this fractal
      bool c2ClosureLocked;

   bool is_valid;
   bool is_complete;

   bool entry_taken;
   ENUM_CISD_TYPE entry_type;
   double entry_price;
   double stop_loss_price;

   SClosureSignal closure;

   //--- C2 Formation tracking ---
   bool               c2IsForming;         // True during C2 candle formation
   double             c2FormationHigh;     // High during formation
   double             c2FormationLow;      // Low during formation
   double             c2FormationWick;     // Current wick size %
   datetime           c2FormationStart;    // When C2 started forming

   // C2 validation metrics
   bool               c2WickValid;         // Passes InpMaxC2WickPercent filter
   double             c2WickPercent;       // Actual wick percentage

   void Reset()
   {
      state = FRACTAL_STATE_NONE;
      narrativeGUID = 0;

      c1_time = 0;
      c1_high = 0.0;
      c1_low = 0.0;
      c1_close = 0.0;

      c2_time = 0;
      c2_high = 0.0;
      c2_low = 0.0;
      c2_close = 0.0;
      c2_barIndex = 0;

      c3_time = 0;
      c3_high = 0.0;
      c3_low = 0.0;
      c3_close = 0.0;

      c4_time = 0;
      c4_high = 0.0;
      c4_low = 0.0;
      c4_close = 0.0;

      liquidity_swept = false;
      sweep_direction = DIRECTION_NONE;
         c2ClosureLocked = false; // Initialize c2ClosureLocked in Reset
      is_valid = true;
      is_complete = false;

      entry_taken = false;
      entry_type = CISD_TYPE_NONE;
      entry_price = 0.0;
      stop_loss_price = 0.0;

      closure.Reset();

      // Reset formation tracking
      c2IsForming = false;
      c2FormationHigh = 0.0;
      c2FormationLow = 0.0;
      c2FormationWick = 0.0;
      c2FormationStart = 0;
      c2WickValid = false;
      c2WickPercent = 0.0;
   }
};

//+------------------------------------------------------------------+
//| STATE TRANSITION FUNCTIONS                                       |
//+------------------------------------------------------------------+

ENUM_FRACTAL_STATE TransitionToC1(
   SFractalContext &ctx,
   datetime bar_time,
   double high,
   double low,
   double close
)
{
   ctx.Reset();

   ctx.c1_time = bar_time;
   ctx.c1_high = high;
   ctx.c1_low = low;
   ctx.c1_close = close;

   ctx.state = FRACTAL_STATE_C1;
   ctx.is_valid = true;
   ctx.is_complete = false;

LogPrint("[FRACTAL] Transition → C1 | Time=" + TimeToString(bar_time) +
          " | High=" + DoubleToString(high, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
          " | Low=" + DoubleToString(low, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), LOG_LEVEL_DEBUG);

   return ctx.state;
}

ENUM_FRACTAL_STATE TransitionToC2(
   SFractalContext &ctx,
   datetime bar_time,
   double high,
   double low,
   double close,
   ENUM_DIRECTION prev_direction,
   int barIndex
)
{
   if(ctx.state != FRACTAL_STATE_C1 || ctx.c1_time == 0)
   {
      LogPrint("[FRACTAL] TransitionToC2 FAILED | No C1 anchor detected", LOG_LEVEL_WARN);
      return FRACTAL_STATE_NONE;
   }

   bool bullish_sweep = (low < ctx.c1_low && close > ctx.c1_low);
   bool bearish_sweep = (high > ctx.c1_high && close < ctx.c1_high);

   if(!bullish_sweep && !bearish_sweep)
   {
      LogPrint("[FRACTAL] TransitionToC2 FAILED | No liquidity sweep detected", LOG_LEVEL_WARN);
      return FRACTAL_STATE_NONE;
   }

   ctx.c2_time = bar_time;
   ctx.c2_high = high;
   ctx.c2_low = low;
   ctx.c2_close = close;
   ctx.c2_barIndex = barIndex;

   ctx.liquidity_swept = true;
   ctx.sweep_direction = bullish_sweep ? DIRECTION_BUY : DIRECTION_SELL;
   ctx.state = FRACTAL_STATE_C2;

LogPrint("[FRACTAL] Transition → C2 | Time=" + TimeToString(bar_time) +
          " | Sweep=" + (ctx.liquidity_swept ? "TRUE" : "FALSE") +
          " | Direction=" + EnumToString(ctx.sweep_direction) +
          " | High=" + DoubleToString(high, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
          " | Low=" + DoubleToString(low, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), LOG_LEVEL_DEBUG);

   return ctx.state;
}

ENUM_FRACTAL_STATE TransitionToC3(
   SFractalContext &ctx,
   datetime bar_time,
   double high,
   double low,
   double close,
   double open
)
{
   if(ctx.state != FRACTAL_STATE_C2 || ctx.c2_time == 0)
   {
      LogPrint("[FRACTAL] TransitionToC3 FAILED | No C2 signal detected", LOG_LEVEL_WARN);
      return FRACTAL_STATE_NONE;
   }

   if(ctx.sweep_direction == DIRECTION_NONE)
   {
      LogPrint("[FRACTAL] TransitionToC3 FAILED | C2 sweep direction undefined", LOG_LEVEL_WARN);
      return FRACTAL_STATE_NONE;
   }

   bool bullish_confirm = (close > ctx.c2_high);
   bool bearish_confirm = (close < ctx.c2_low);
   bool bullish_engulf = (close > ctx.c2_high && open < ctx.c2_low);
   bool bearish_engulf = (close < ctx.c2_low && open > ctx.c2_high);

   bool direction_valid = false;
   if(ctx.sweep_direction == DIRECTION_BUY && (bullish_confirm || bullish_engulf))
      direction_valid = true;
   else if(ctx.sweep_direction == DIRECTION_SELL && (bearish_confirm || bearish_engulf))
      direction_valid = true;

   if(!direction_valid)
   {
      LogPrint("[FRACTAL] TransitionToC3 FAILED | Direction mismatch with C2", LOG_LEVEL_WARN);
      return FRACTAL_STATE_NONE;
   }

   ctx.c3_time = bar_time;
   ctx.c3_high = high;
   ctx.c3_low = low;
   ctx.c3_close = close;

   ctx.state = FRACTAL_STATE_C3;

LogPrint("[FRACTAL] Transition → C3 | Time=" + TimeToString(bar_time) +
          " | Engulf=" + (bullish_engulf || bearish_engulf ? "TRUE" : "FALSE") +
          " | Direction=" + EnumToString(ctx.sweep_direction) +
          " | High=" + DoubleToString(high, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
          " | Low=" + DoubleToString(low, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), LOG_LEVEL_DEBUG);

   return ctx.state; // REGRESSION_GUARD_V52.5_FractalState
}

ENUM_FRACTAL_STATE TransitionToC4(
   SFractalContext &ctx,
   datetime bar_time,
   double high,
   double low,
   double close,
   double entry_zone_high,
   double entry_zone_low
)
{
   if(ctx.state != FRACTAL_STATE_C3 || ctx.c3_time == 0)
   {
      LogPrint("[FRACTAL] TransitionToC4 FAILED | No C3 expansion detected", LOG_LEVEL_WARN);
      return FRACTAL_STATE_NONE;
   }

   if(entry_zone_high <= 0 || entry_zone_low <= 0 || entry_zone_high <= entry_zone_low)
   {
      LogPrint("[FRACTAL] TransitionToC4 FAILED | Invalid entry zone", LOG_LEVEL_WARN);
      return FRACTAL_STATE_NONE;
   }

   bool retraced = (low <= entry_zone_high && high >= entry_zone_low);

   if(!retraced)
   {
      LogPrint("[FRACTAL] TransitionToC4 FAILED | No retracement into entry zone", LOG_LEVEL_WARN);
      return FRACTAL_STATE_NONE;
   }

   ctx.c4_time = bar_time;
   ctx.c4_high = high;
   ctx.c4_low = low;
   ctx.c4_close = close;

   ctx.state = FRACTAL_STATE_C4;
   ctx.is_complete = true;

LogPrint("[FRACTAL] Transition → C4 | Time=" + TimeToString(bar_time) +
          " | Retracement=TRUE" +
          " | Direction=" + EnumToString(ctx.sweep_direction) +
          " | High=" + DoubleToString(high, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
          " | Low=" + DoubleToString(low, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), LOG_LEVEL_DEBUG);

   return ctx.state;
}

void ResetFractalContext(SFractalContext &ctx)
{
   ctx.Reset();
   LogPrint("[FRACTAL] Context RESET | State=NONE", LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| DETECTION HELPER FUNCTIONS                                       |
//+------------------------------------------------------------------+

ENUM_DIRECTION DetectLiquiditySweep(
   double current_high,
   double current_low,
   double current_close,
   double prev_high,
   double prev_low,
   double prev_close
)
{
   if(current_low < prev_low && current_close > prev_low)
   {
      return DIRECTION_BUY;
   }

   if(current_high > prev_high && current_close < prev_high)
   {
      return DIRECTION_SELL;
   }

   return DIRECTION_NONE;
}

bool DetectCloseBackInsideRange(
   double current_open,
   double current_close,
   double prev_high,
   double prev_low
)
{
   bool bullish_inside = (current_close > prev_low);
   bool bearish_inside = (current_close < prev_high);

   return bullish_inside || bearish_inside;
}

bool DetectC3Confirmation(
   double current_open,
   double current_close,
   double current_high,
   double current_low,
   double c2_high,
   double c2_low,
   ENUM_DIRECTION sweep_direction
)
{
   if(sweep_direction == DIRECTION_BUY)
   {
      bool bullish_confirm = (current_close > c2_high);
      bool bullish_engulf = (current_close > c2_high && current_open < c2_low);
      return bullish_confirm || bullish_engulf;
   }
   else if(sweep_direction == DIRECTION_SELL)
   {
      bool bearish_confirm = (current_close < c2_low);
      bool bearish_engulf = (current_close < c2_low && current_open > c2_high);
      return bearish_confirm || bearish_engulf;
   }

   return false;
}

//+------------------------------------------------------------------+
//| PHASE 2: C2 Formation Tracking                                   |
//+------------------------------------------------------------------+

/**
 * UpdateC2Formation
 *
 * Call every tick during C2 candle formation to track the
 * evolving high, low, and wick percentage.
 *
 * @param ctx     Fractal context to update
 * @param current Current MqlRates candle data
 */
void UpdateC2Formation(SFractalContext &ctx, MqlRates &current)
{
   if(!ctx.c2IsForming)
   {
      // Initialize formation tracking
      ctx.c2IsForming = true;
      ctx.c2FormationStart = current.time;
      ctx.c2FormationHigh = current.high;
      ctx.c2FormationLow = current.low;
   }
   else
   {
      // Update running extremes
      if(current.high > ctx.c2FormationHigh)
         ctx.c2FormationHigh = current.high;
      if(current.low < ctx.c2FormationLow)
         ctx.c2FormationLow = current.low;
   }

   // Calculate current wick percentage
   double range = ctx.c2FormationHigh - ctx.c2FormationLow;
   if(range > 0.0)
   {
      double bodyTop = MathMax(current.open, current.close);
      double bodyBottom = MathMin(current.open, current.close);
      double upperWick = ctx.c2FormationHigh - bodyTop;
      double lowerWick = bodyBottom - ctx.c2FormationLow;
      ctx.c2FormationWick = MathMax(upperWick, lowerWick) / range;
   }
   else
   {
      ctx.c2FormationWick = 0.0;
   }
}

/**
 * IsC2WickValid
 *
 * Checks if the C2 candle's wick percentage is within the
 * acceptable range for anticipation mode entry.
 *
 * @param high        Candle high
 * @param low         Candle low
 * @param open        Candle open
 * @param close       Candle close
 * @param maxPercent  Maximum allowed wick % (from InpMaxC2WickPercent / 100.0)
 * @return true if wick is within acceptable range
 */
bool IsC2WickValid(double high, double low, double open, double close, double maxPercent)
{
   double range = high - low;
   if(range <= 0.0)
      return false;

   double bodyTop = MathMax(open, close);
   double bodyBottom = MathMin(open, close);
   double upperWick = high - bodyTop;
   double lowerWick = bodyBottom - low;
   double maxWick = MathMax(upperWick, lowerWick);
   double wickPercent = maxWick / range;

   return (wickPercent <= maxPercent);
}

//+------------------------------------------------------------------+
//| LOGGING FUNCTIONS                                                |
//+------------------------------------------------------------------+

void LogFractalState(SFractalContext &ctx)
{
   string state_str = "";
   switch(ctx.state)
   {
      case FRACTAL_STATE_NONE:  state_str = "NONE"; break;
      case FRACTAL_STATE_C1:    state_str = "C1"; break;
      case FRACTAL_STATE_C2:    state_str = "C2"; break;
      case FRACTAL_STATE_C3:    state_str = "C3"; break;
      case FRACTAL_STATE_C4:    state_str = "C4"; break;
   }

LogPrint("[FRACTAL] State=" + state_str +
          " | Sweep=" + (ctx.liquidity_swept ? "TRUE" : "FALSE") +
          " | Direction=" + EnumToString(ctx.sweep_direction) +
          " | Valid=" + (ctx.is_valid ? "YES" : "NO") +
          " | Complete=" + (ctx.is_complete ? "YES" : "NO"), LOG_LEVEL_DEBUG);

   if(ctx.state >= FRACTAL_STATE_C1 && ctx.c1_time > 0)
   {
LogPrint("[FRACTAL]   C1 | Time=" + TimeToString(ctx.c1_time) +
             " | H=" + DoubleToString(ctx.c1_high, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
             " | L=" + DoubleToString(ctx.c1_low, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
             " | C=" + DoubleToString(ctx.c1_close, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), LOG_LEVEL_DEBUG);
   }

   if(ctx.state >= FRACTAL_STATE_C2 && ctx.c2_time > 0)
   {
LogPrint("[FRACTAL]   C2 | Time=" + TimeToString(ctx.c2_time) +
             " | H=" + DoubleToString(ctx.c2_high, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
             " | L=" + DoubleToString(ctx.c2_low, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
             " | C=" + DoubleToString(ctx.c2_close, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), LOG_LEVEL_DEBUG);
   }

   if(ctx.state >= FRACTAL_STATE_C3 && ctx.c3_time > 0)
   {
LogPrint("[FRACTAL]   C3 | Time=" + TimeToString(ctx.c3_time) +
             " | H=" + DoubleToString(ctx.c3_high, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
             " | L=" + DoubleToString(ctx.c3_low, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
             " | C=" + DoubleToString(ctx.c3_close, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), LOG_LEVEL_DEBUG);
   }

   if(ctx.state >= FRACTAL_STATE_C4 && ctx.c4_time > 0)
   {
LogPrint("[FRACTAL]   C4 | Time=" + TimeToString(ctx.c4_time) +
             " | H=" + DoubleToString(ctx.c4_high, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
             " | L=" + DoubleToString(ctx.c4_low, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
             " | C=" + DoubleToString(ctx.c4_close, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), LOG_LEVEL_DEBUG);
   }
}

string GetFractalStateString(ENUM_FRACTAL_STATE state)
{
   switch(state)
   {
      case FRACTAL_STATE_NONE:  return "NONE";
      case FRACTAL_STATE_C1:    return "C1";
      case FRACTAL_STATE_C2:    return "C2";
      case FRACTAL_STATE_C3:    return "C3";
      case FRACTAL_STATE_C4:    return "C4";
      default:                  return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| MAIN DETECTION FUNCTION — DetectFractalState                      |
//| v52.5+: references fractal narrative for shared closure context  |
//+------------------------------------------------------------------+

// Helper: find active narrative GUID for current branch/timeframe
ulong FindActiveNarrativeGUID(ENUM_EXECUTION_BRANCH branch)
{
   if(branch == BRANCH_INTRADAY)
   {
      int idx = FN_FindActiveNarrative(g_branchANarratives, branch);
      if(idx >= 0)
         return g_branchANarratives[idx].narrativeGUID;
   }
   else
   {
      int idx = FN_FindActiveNarrative(g_branchBNarratives, branch);
      if(idx >= 0)
         return g_branchBNarratives[idx].narrativeGUID;
   }

   return 0;
}

// Helper: populate SFractalContext from SFractalNarrative
void PopulateFromNarrative(SFractalContext &ctx, const SFractalNarrative &nar, const SClosureSignal &closure)
{
   ctx.narrativeGUID = nar.narrativeGUID;
   ctx.c1_time = nar.c1_barTime;
   ctx.c1_high = nar.c1_high;
   ctx.c1_low = nar.c1_low;
   ctx.c1_close = nar.c1_close;

   ctx.c2_time = nar.c2Event.detectionTime;
   ctx.c2_high = nar.c2Event.c2_high;
   ctx.c2_low = nar.c2Event.c2_low;
   ctx.c2_close = nar.c2Event.c2_close;
   ctx.c2_barIndex = nar.c2Event.barsSinceC1;

   if(nar.c3EventCount > 0)
   {
      ctx.c3_time = nar.c3Event.detectionTime;
      ctx.c3_high = nar.c3Event.event_high;
      ctx.c3_low = nar.c3Event.event_low;
      ctx.c3_close = nar.c3Event.event_close;
   }

   if(nar.c4EventCount > 0)
   {
      ctx.c4_time = nar.c4Event.detectionTime;
      ctx.c4_high = nar.c4Event.event_high;
      ctx.c4_low = nar.c4Event.event_low;
      ctx.c4_close = nar.c4Event.event_close;
   }

   ctx.liquidity_swept = true;
   ctx.sweep_direction = nar.narrativeDirection;
   ctx.is_valid = true;
   ctx.closure = closure;
}

bool IsCandleDoji(
   double open,
   double close,
   double high_high,
   double low_low,
   double min_body_size = 0.0
)
{
   double body = MathAbs(close - open);
   double range = high_high - low_low;

   if(range > 0 && body < (range * 0.05))
      return true;

   if(min_body_size > 0 && body < min_body_size)
      return true;

   return false;
}

bool IsCandleBullish(double open, double close)
{
   return (close > open);
}

bool IsCandleBearish(double open, double close)
{
   return (close < open);
}

bool IsBullishEngulfing(
   double open1,
   double close1,
   double open2,
   double close2
)
{
   if(!IsCandleBearish(open1, close1))
      return false;

   if(!IsCandleBullish(open2, close2))
      return false;

   bool engulfs = (open2 < close1 && close2 > open1);

   return engulfs;
}

bool IsBearishEngulfing(
   double open1,
   double close1,
   double open2,
   double close2
)
{
   if(!IsCandleBullish(open1, close1))
      return false;

   if(!IsCandleBearish(open2, close2))
      return false;

   bool engulfs = (open2 > close1 && close2 < open1);

   return engulfs;
}

bool HasStrongDisplacement(
   double open,
   double close,
   double high_high,
   double low_low,
   double threshold = 0.7
)
{
   double body = MathAbs(close - open);
   double range = high_high - low_low;

   if(range <= 0)
      return false;

   return (body / range) >= threshold;
}

SFractalContext DetectFractalState(
   const string symbol = "",
   ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT,
   double min_body_size = 0.0
)
{
   SFractalContext fractal;
   ZeroMemory(fractal);
   fractal.Reset();

   string sym = (symbol == "" || symbol == NULL) ? _Symbol : symbol;
   ENUM_TIMEFRAMES tf = (timeframe == PERIOD_CURRENT) ? PERIOD_CURRENT : timeframe;

    SClosureSignal closure;
    SLockedSignal dummyLock;  // Not used for locking
    ZeroMemory(closure);
    dummyLock.Reset();
    dummyLock.TransitionStage(STAGE_LOCKED);  // Prevent bridge from locking
    DetectClosureSignal(sym, tf, closure, dummyLock);

   fractal.closure = closure;

   if(!closure.valid)
   {
      LogPrint("[FRACTAL] NONE | No valid closure detected", LOG_LEVEL_DEBUG);
      return fractal;
   }

   // v52.5+: Try to find active narrative for shared context
   ENUM_EXECUTION_BRANCH branch = BRANCH_INTRADAY; // default
   if(tf == PERIOD_H4 || tf == PERIOD_M15)
      branch = BRANCH_SWING;

   ulong narrGUID = FindActiveNarrativeGUID(branch);
   if(narrGUID != 0)
   {
      // Populate from narrative if available — access global arrays directly
      if(branch == BRANCH_INTRADAY)
      {
         int narrIdx = FN_FindActiveNarrative(g_branchANarratives, branch);
         if(narrIdx >= 0)
         {
            PopulateFromNarrative(fractal, g_branchANarratives[narrIdx], closure);
         }
      }
      else
      {
         int narrIdx = FN_FindActiveNarrative(g_branchBNarratives, branch);
         if(narrIdx >= 0)
         {
            PopulateFromNarrative(fractal, g_branchBNarratives[narrIdx], closure);
         }
      }
   }
   else
   {
      // Legacy fallback: populate from closure signal directly
      double c1_high = closure.c1_high;
      double c1_low = closure.c1_low;
      double c1_close = closure.c1_close;

      double c2_high = closure.c2_high;
      double c2_low = closure.c2_low;
      double c2_open = closure.c2_open;
      double c2_close = closure.c2_close;

      double c3_high = closure.c3_high;
      double c3_low = closure.c3_low;
      double c3_open = closure.c3_open;
      double c3_close = closure.c3_close;

      datetime times[];
      ArraySetAsSeries(times, true);
      if(CopyTime(sym, tf, 0, 3, times) < 3)
      {
         LogPrint("[FRACTAL_TIME] CopyTime failed | sym=" + sym + " tf=" + EnumToString(tf), LOG_LEVEL_DEBUG);
         return fractal;
      }

      datetime c1_time = times[2];
      datetime c2_time = times[1];
      datetime c3_time = times[0];

      fractal.c1_time = c1_time;
      fractal.c1_high = c1_high;
      fractal.c1_low = c1_low;
      fractal.c1_close = c1_close;

      fractal.c2_time = c2_time;
      fractal.c2_high = c2_high;
      fractal.c2_low = c2_low;
      fractal.c2_close = c2_close;
      fractal.c2_barIndex = 1;

      fractal.c3_time = c3_time;
      fractal.c3_high = c3_high;
      fractal.c3_low = c3_low;
      fractal.c3_close = c3_close;
   }

   fractal.liquidity_swept = true;
   fractal.sweep_direction = closure.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;
   fractal.is_valid = true;

   if(closure.type == CLOSURE_C2)
   {
      fractal.state = FRACTAL_STATE_C2;
      // Mark that a C2 closure was detected/locked for this fractal sequence
      fractal.c2ClosureLocked = true;
LogPrint("[FRACTAL] C2 " + (closure.is_bullish ? "BUY" : "SELL") +
             " detected | Closure=C2 | C1.Close=" + DoubleToString(closure.c1_close, _Digits) +
             " | C2.Close=" + DoubleToString(closure.c2_close, _Digits), LOG_LEVEL_DEBUG);
   }
else if(closure.type == CLOSURE_C3)
    {
       fractal.state = FRACTAL_STATE_C3;
       fractal.c2ClosureLocked = false;
       LogPrint("[FRACTAL] C3 " + (closure.is_bullish ? "BUY" : "SELL") +
                " detected | Closure=C3 | C1.Close=" + DoubleToString(closure.c1_close, _Digits) +
                " | C2.Close=" + DoubleToString(closure.c2_close, _Digits) +
                " | C3.Close=" + DoubleToString(closure.c3_close, _Digits), LOG_LEVEL_DEBUG);
    }
   else if(closure.type == CLOSURE_C4)
   {
      fractal.state = FRACTAL_STATE_C4;
      fractal.is_complete = true;
      LogPrint("[FRACTAL] C4 " + (closure.is_bullish ? "BUY" : "SELL") +
               " detected | Closure=C4" +
               " | Entry=" + DoubleToString(closure.entry_price, _Digits) +
               " | SL=" + DoubleToString(closure.stop_loss, _Digits), LOG_LEVEL_DEBUG);
   }

   return fractal;
}

//+------------------------------------------------------------------+
//| VALIDATION FUNCTIONS                                             |
//+------------------------------------------------------------------+

bool IsFractalContextValid(SFractalContext &ctx)
{
   if(!ctx.is_valid)
      return false;

   switch(ctx.state)
   {
      case FRACTAL_STATE_NONE:
         return true;

      case FRACTAL_STATE_C1:
         return (ctx.c1_time > 0 && ctx.c1_high > 0 && ctx.c1_low > 0);

      case FRACTAL_STATE_C2:
         return (ctx.c2_time > 0 && ctx.c2_high > 0 && ctx.c2_low > 0 &&
                 ctx.liquidity_swept && ctx.sweep_direction != DIRECTION_NONE);

      case FRACTAL_STATE_C3:
         return (ctx.c3_time > 0 && ctx.c3_high > 0 && ctx.c3_low > 0 &&
                 ctx.liquidity_swept && ctx.sweep_direction != DIRECTION_NONE);

      case FRACTAL_STATE_C4:
         return (ctx.c4_time > 0 && ctx.c4_high > 0 && ctx.c4_low > 0 &&
                 ctx.is_complete);

      default:
         return false;
   }
}

bool ShouldResetFractal(
   SFractalContext &ctx,
   double current_high,
   double current_low
)
{
   if(ctx.is_complete)
      return true;

   if(ctx.state >= FRACTAL_STATE_C2 && ctx.sweep_direction != DIRECTION_NONE)
   {
      if(ctx.sweep_direction == DIRECTION_BUY)
      {
         if(current_high > ctx.c2_high)
            return true;
      }
      else if(ctx.sweep_direction == DIRECTION_SELL)
      {
         if(current_low < ctx.c2_low)
            return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| CLOSURE INTEGRATION FUNCTIONS                                    |
//+------------------------------------------------------------------+

double GetClosureEntryPrice(SFractalContext &ctx)
{
   if(!ctx.is_valid || !ctx.closure.valid)
      return 0.0;

   return ctx.closure.entry_price;
}

double GetClosureStopLoss(SFractalContext &ctx)
{
   if(!ctx.is_valid || !ctx.closure.valid)
      return 0.0;

   return ctx.closure.stop_loss;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+

#endif // OMAK_FRACTALSTATE_MQH
