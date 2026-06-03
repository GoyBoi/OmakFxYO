//+------------------------------------------------------------------+
//|                                           LiquidityEngine.mqh |
//|                           OmakFxYO — Liquidity Engine |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_LIQUIDITYENGINE_MQH
#define OMAK_LIQUIDITYENGINE_MQH

#property strict

#property copyright "OMAK"
#property version   "1.00"
#property description "Liquidity Engine — Trigger-Based Liquidity Detection"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>        // Base types
#include <OmakFxYO/core/FractalState.mqh>     // Fractal context integration

//+------------------------------------------------------------------+
//| ENUM_LIQUIDITY_TYPE — Liquidity Classification                   |
//+------------------------------------------------------------------+
/**
 * ENUM_LIQUIDITY_TYPE
 * 
 * Classifies liquidity events by type and impact.
 * Based on TTrades Fractal Model liquidity mechanics.
 * 
 * Types:
 * - GRAB: Small stop hunt, quick reversal (entry trigger)
 * - SWEEP: Major liquidity taken, strong reversal (primary trigger)
 * - RAID: Continuation breakout (momentum trigger)
 */
enum ENUM_LIQUIDITY_TYPE
{
   LIQ_NONE = 0,         // No liquidity event
   LIQ_GRAB,             // Small stop hunt (entry trigger)
   LIQ_SWEEP,            // Major liquidity taken (reversal trigger)
   LIQ_RAID              // Continuation breakout (momentum trigger)
};

//+------------------------------------------------------------------+
//| SLiquidityContext — Liquidity Event Container                     |
//+------------------------------------------------------------------+
/**
 * SLiquidityContext
 *
 * Captures complete liquidity event data for decision making.
 * Used by fractal engine to validate C2 entries.
 */
struct SLiquidityContext
{
   // Classification
   ENUM_LIQUIDITY_TYPE type;         // Liquidity type (GRAB/SWEEP/RAID)

   // Event details
   double level;                     // Liquidity level price
   datetime time;                    // Time of liquidity event
   int bar_shift;                    // Bar shift where liquidity occurred

   // Pattern detection
   bool is_swing_high;               // Swing high liquidity
   bool is_swing_low;                // Swing low liquidity
   bool is_eqh;                      // Equal highs detected
   bool is_eql;                      // Equal lows detected

   // ═══════════════════════════════════════════════════════════
// IRL/ERL CLASSIFICATION
    // ═══════════════════════════════════════════════════════════
    bool is_irl;                      // TRUE: sweep source is equal H/L (internal)
   bool is_erl;                      // TRUE: sweep source is swing H/L (external)

   // Detection parameters
   int bars_lookback;                // Lookback period for detection
   double strength;                  // Liquidity strength (0-100)

   // Sweep details
   double sweep_distance;            // Distance swept beyond level (points)
   double sweep_bars;                // Number of bars in sweep

   //+------------------------------------------------------------------+
   // | Constructor — Initialize to defaults                           |
   //+------------------------------------------------------------------+
   void SLiquidityContext()
   {
      Reset();
   }

   //+------------------------------------------------------------------+
   // | Reset — Clear all state to defaults                            |
   //+------------------------------------------------------------------+
   void Reset()
   {
      ZeroMemory(this);
      type = LIQ_NONE;
      level = 0.0;
      time = 0;
      bar_shift = 0;
      is_swing_high = false;
      is_swing_low = false;
      is_eqh = false;
      is_eql = false;
      is_irl = false;
      is_erl = false;
      bars_lookback = 20;
      strength = 0.0;
      sweep_distance = 0.0;
      sweep_bars = 0;
   }
};

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+

/**
 * IsValidIndex — Validate array index is within bounds
 * 
 * @param i Index to validate
 * @param size Array size
 * @return true if index is valid
 */
bool IsValidIndex(int i, int size)
{
   return (i >= 0 && i < size);
}

//+------------------------------------------------------------------+
//| LIQUIDITY DETECTION — EQUAL HIGHS/LOWS                           |
//+------------------------------------------------------------------+

/**
 * DetectEqualHighs — Detect equal highs (EQH) pattern
 *
 * EQH: Two or more highs at approximately same price level
 * Creates liquidity pool above the highs
 *
 * @param highs[] Array of high prices (index 0 = current bar)
 * @param lookback Bars to look back for EQH detection
 * @param tolerance Tolerance in points for "equal" comparison
 * @return true if EQH detected
 */
bool DetectEqualHighs(double &highs[], int lookback = 20, double tolerance = 0.0)
{
   int array_size = ArraySize(highs);
   
   // HARD GUARD: Minimum bars
   if(array_size < 5)
   {
      LogPrint("[LIQUIDITY] DetectEqualHighs ERROR: Not enough bars | size=" + IntegerToString(array_size), LOG_LEVEL_WARN);
      return false;
   }
   
   // Limit lookback to array size
   int safe_lookback = (lookback < array_size) ? lookback : array_size;

   int eqh_count = 0;
   double reference_high = highs[0];

   if(tolerance <= 0)
   {
      // Auto tolerance: 0.1% of price
      tolerance = reference_high * 0.001;
   }

   // Count highs within tolerance of reference (SAFE: bounded by safe_lookback)
   for(int i = 0; i < safe_lookback; i++)
   {
      if(!IsValidIndex(i, array_size))
         continue;
      
      if(MathAbs(highs[i] - reference_high) <= tolerance)
         eqh_count++;
   }

   // EQH requires at least 2 touches
   return eqh_count >= 2;
}

/**
 * DetectEqualLows — Detect equal lows (EQL) pattern
 *
 * EQL: Two or more lows at approximately same price level
 * Creates liquidity pool below the lows
 *
 * @param lows[] Array of low prices (index 0 = current bar)
 * @param lookback Bars to look back for EQL detection
 * @param tolerance Tolerance in points for "equal" comparison
 * @return true if EQL detected
 */
bool DetectEqualLows(double &lows[], int lookback = 20, double tolerance = 0.0)
{
   int array_size = ArraySize(lows);
   
   // HARD GUARD: Minimum bars
   if(array_size < 5)
   {
      LogPrint("[LIQUIDITY] DetectEqualLows ERROR: Not enough bars | size=" + IntegerToString(array_size), LOG_LEVEL_WARN);
      return false;
   }
   
   // Limit lookback to array size
   int safe_lookback = (lookback < array_size) ? lookback : array_size;

   int eql_count = 0;
   double reference_low = lows[0];

   if(tolerance <= 0)
   {
      // Auto tolerance: 0.1% of price
      tolerance = reference_low * 0.001;
   }

   // Count lows within tolerance of reference (SAFE: bounded by safe_lookback)
   for(int i = 0; i < safe_lookback; i++)
   {
      if(!IsValidIndex(i, array_size))
         continue;
      
      if(MathAbs(lows[i] - reference_low) <= tolerance)
         eql_count++;
   }

   // EQL requires at least 2 touches
   return eql_count >= 2;
}

//+------------------------------------------------------------------+
//| LIQUIDITY DETECTION — SWING HIGHS/LOWS                           |
//+------------------------------------------------------------------+

/**
 * IsLiquiditySwingHigh — Detect swing high (fractal high) for liquidity engine
 *
 * Swing High: High that is higher than N bars before and after
 *
 * @param highs[] Array of high prices
 * @param shift Bar shift to check for swing high
 * @param left_bars Bars to compare on left side
 * @param right_bars Bars to compare on right side
 * @return true if swing high detected
 */
bool IsLiquiditySwingHigh(double &highs[], int shift = 0, int left_bars = 2, int right_bars = 2)
{
   int array_size = ArraySize(highs);

   // HARD GUARD: Minimum bars required (P17.1 FIX: reduced from 5 to 4)
   if(array_size < 4)
   {
      return false;
   }

   // STRICT BOUNDS VALIDATION (P17.1 FIX: Check BEFORE any array access)
   if(shift < left_bars)
   {
      return false;  // Not enough bars on left
   }

   if(shift + right_bars >= array_size)
   {
      return false;  // Not enough bars on right
   }

   double current_high = highs[shift];

   // Check left side (P17.1 FIX: Safe iteration with validated bounds)
   for(int i = shift - left_bars; i < shift; i++)
   {
      if(highs[i] >= current_high)
         return false;
   }

   // Check right side (P17.1 FIX: Safe iteration with validated bounds)
   for(int i = shift + 1; i <= shift + right_bars; i++)
   {
      if(highs[i] >= current_high)
         return false;
   }

   return true;
}

/**
 * IsLiquiditySwingLow — Detect swing low (fractal low) for liquidity engine
 *
 * Swing Low: Low that is lower than N bars before and after
 *
 * @param lows[] Array of low prices
 * @param shift Bar shift to check for swing low
 * @param left_bars Bars to compare on left side
 * @param right_bars Bars to compare on right side
 * @return true if swing low detected
 */
bool IsLiquiditySwingLow(double &lows[], int shift = 0, int left_bars = 2, int right_bars = 2)
{
   int array_size = ArraySize(lows);

   // HARD GUARD: Minimum bars required (P17.1 FIX: reduced from 5 to 4)
   if(array_size < 4)
   {
      return false;
   }

   // STRICT BOUNDS VALIDATION (P17.1 FIX: Check BEFORE any array access)
   if(shift < left_bars)
   {
      return false;  // Not enough bars on left
   }

   if(shift + right_bars >= array_size)
   {
      return false;  // Not enough bars on right
   }

   double current_low = lows[shift];

   // Check left side (P17.1 FIX: Safe iteration with validated bounds)
   for(int i = shift - left_bars; i < shift; i++)
   {
      if(lows[i] <= current_low)
         return false;
   }

   // Check right side (P17.1 FIX: Safe iteration with validated bounds)
   for(int i = shift + 1; i <= shift + right_bars; i++)
   {
      if(lows[i] <= current_low)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| LIQUIDITY CLASSIFICATION                                         |
//+------------------------------------------------------------------+

/**
 * ClassifyLiquidity — Classify liquidity event type
 * 
 * Classification Rules:
 * - GRAB: Small sweep (< 50% of previous range), quick reversal
 * - SWEEP: Major sweep (>= 50% of previous range), strong reversal
 * - RAID: Breakout without reversal (continuation)
 * 
 * @param sweep_distance Distance swept beyond level (points)
 * @param previous_range Previous candle range (points)
 * @param is_swing True if swing level
 * @param is_reversal True if price reversed after sweep
 * @return ENUM_LIQUIDITY_TYPE
 */
ENUM_LIQUIDITY_TYPE ClassifyLiquidity(
   double sweep_distance,
   double previous_range,
   bool is_swing,
   bool is_reversal
)
{
   if(sweep_distance <= 0 || previous_range <= 0)
      return LIQ_NONE;
   
   // Calculate sweep percentage
   double sweep_pct = (sweep_distance / previous_range) * 100.0;
   
   // RAID: Breakout without reversal
   if(!is_reversal)
      return LIQ_RAID;
   
   // GRAB: Small sweep (< 50% of range)
   if(sweep_pct < 50.0)
      return LIQ_GRAB;
   
   // SWEEP: Major sweep (>= 50% of range)
   // Bonus if swing level
   if(sweep_pct >= 50.0)
      return LIQ_SWEEP;
   
   return LIQ_NONE;
}

//+------------------------------------------------------------------+
//| MAIN LIQUIDITY DETECTION ENGINE                                  |
//+------------------------------------------------------------------+

/**
 * DetectLiquidity — Main liquidity detection function
 *
 * Detects and classifies liquidity events for a symbol/timeframe.
 * Combines EQH/EQL detection with swing analysis.
 *
 * @param symbol Symbol to analyze (empty = current)
 * @param timeframe Timeframe to analyze (PERIOD_CURRENT = current)
 * @param lookback Lookback period for detection
 * @return SLiquidityContext with detection results
 */
SLiquidityContext DetectLiquidity(
   const string symbol = "",
   ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT,
   int lookback = 20
)
{
   SLiquidityContext ctx;
   ctx.Reset();
   ctx.bars_lookback = lookback;

   // Get symbol
   string sym = (symbol == "") ? _Symbol : symbol;
   ENUM_TIMEFRAMES tf = (timeframe == PERIOD_CURRENT) ? PERIOD_CURRENT : timeframe;

   // Copy price data
   double highs[], lows[], closes[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);

   // HARD GUARD: Ensure minimum 50 bars for reliable detection
   int required_bars = lookback + 20;
   if(required_bars < 50)
      required_bars = 50;

   int copied = CopyHigh(sym, tf, 0, required_bars, highs);
   if(copied < 50)  // HARD GUARD: Minimum 50 bars required
   {
LogPrint("[LIQUIDITY] DetectLiquidity ERROR: Insufficient bars | copied=" + IntegerToString(copied) + " | required=50", LOG_LEVEL_WARN);
       return ctx;
    }

    copied = CopyLow(sym, tf, 0, required_bars, lows);
    if(copied < 50)  // HARD GUARD
    {
       LogPrint("[LIQUIDITY] DetectLiquidity ERROR: CopyLow failed | copied=" + IntegerToString(copied), LOG_LEVEL_WARN);
       return ctx;
    }

    copied = CopyClose(sym, tf, 0, required_bars, closes);
    if(copied < 50)  // HARD GUARD
    {
       LogPrint("[LIQUIDITY] DetectLiquidity ERROR: CopyClose failed | copied=" + IntegerToString(copied), LOG_LEVEL_WARN);
       return ctx;
    }

    // SAFE ARRAY ACCESS: Validate indices before fixed access
    if(!IsValidIndex(0, copied) || !IsValidIndex(1, copied))
    {
       LogPrint("[LIQUIDITY] DetectLiquidity ERROR: Invalid array indices | copied=" + IntegerToString(copied), LOG_LEVEL_WARN);
      return ctx;
   }

   // Detect patterns (P17.1 FIX: Use shift=2 with default left_bars=2, right_bars=2)
   bool eqh = DetectEqualHighs(highs, lookback);
   bool eql = DetectEqualLows(lows, lookback);
   bool swing_high = IsLiquiditySwingHigh(highs, 2, 2, 2);  // P17.1 FIX: shift=2 is now SAFE
   bool swing_low = IsLiquiditySwingLow(lows, 2, 2, 2);    // P17.1 FIX: shift=2 is now SAFE

   ctx.is_eqh = eqh;
   ctx.is_eql = eql;
ctx.is_swing_high = swing_high;
    ctx.is_swing_low = swing_low;

    // ═══════════════════════════════════════════════════════════
    // IRL/ERL CLASSIFICATION
    // ═══════════════════════════════════════════════════════════
    // ERL (External Range Liquidity): Sweep of swing high/low
    // IRL (Internal Range Liquidity): Sweep of equal H/L (inducement)
   if(swing_high || swing_low)
      ctx.is_erl = true;
   if(eqh || eql)
      ctx.is_irl = true;
   // Note: both can be true if sweep hits swing AND equal H/L

   // Determine liquidity level (SAFE: indices 0 and 1 validated)
   if(swing_high || eqh)
   {
      ctx.level = highs[1];  // Previous bar high
      ctx.type = LIQ_SWEEP;  // Assume sweep until classified
   }
   else if(swing_low || eql)
   {
      ctx.level = lows[1];  // Previous bar low
      ctx.type = LIQ_SWEEP;
   }

   // Calculate sweep distance (SAFE: indices 0 and 1 validated)
   double current_high = highs[0];
   double current_low = lows[0];
   double prev_range = highs[1] - lows[1];
   
   if(ctx.level > 0)
   {
      if(current_high > ctx.level)
      {
         ctx.sweep_distance = current_high - ctx.level;
         ctx.time = TimeCurrent();
         ctx.bar_shift = 0;
      }
      else if(current_low < ctx.level)
      {
         ctx.sweep_distance = ctx.level - current_low;
         ctx.time = TimeCurrent();
         ctx.bar_shift = 0;
      }
   }
   
   // Convert sweep distance to points
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point > 0 && ctx.sweep_distance > 0)
   {
      double sweep_points = ctx.sweep_distance / point;
      
      // Classify liquidity
      bool is_reversal = (ctx.is_swing_high && closes[0] < closes[1]) || 
                         (ctx.is_swing_low && closes[0] > closes[1]);
      
      ctx.type = ClassifyLiquidity(
         sweep_points,
         prev_range / point,
         swing_high || swing_low,
         is_reversal
      );
   }
   
   // Calculate strength (0-100)
   ctx.strength = CalculateLiquidityStrength(ctx, highs, lows, lookback);
   
   return ctx;
}

//+------------------------------------------------------------------+
//| LIQUIDITY STRENGTH CALCULATION                                   |
//+------------------------------------------------------------------+

/**
 * CalculateLiquidityStrength — Calculate liquidity strength score
 * 
 * Factors:
 * - Number of touches (EQH/EQL)
 * - Swing significance (lookback period)
 * - Sweep magnitude
 * 
 * @param ctx Liquidity context
 * @param highs[] High prices
 * @param lows[] Low prices
 * @param lookback Lookback period
 * @return Strength score (0-100)
 */
double CalculateLiquidityStrength(
   SLiquidityContext &ctx,
   double &highs[],
   double &lows[],
   int lookback
)
{
   double strength = 0.0;
   
   // Base strength from pattern type
   if(ctx.is_eqh || ctx.is_eql)
      strength += 30.0;  // Equal highs/lows significant
   
   if(ctx.is_swing_high || ctx.is_swing_low)
      strength += 40.0;  // Swing levels more significant
   
   // Strength from sweep magnitude
   if(ctx.sweep_distance > 0)
   {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double sweep_points = ctx.sweep_distance / point;
      
      // More points = stronger (max 30 points)
      strength += MathMin(sweep_points / 10.0, 30.0);
   }
   
   // Cap at 100
   return MathMin(strength, 100.0);
}

//+------------------------------------------------------------------+
//| FRACTAL INTEGRATION                                              |
//+------------------------------------------------------------------+

/**
 * UpdateFractalLiquidity — Update fractal context with liquidity data
 * 
 * Validates C2 requirements:
 * - C2 MUST include: liquidity_type == SWEEP OR GRAB
 * 
 * @param fractal Fractal context to update
 * @param liq Liquidity context
 * @return true if liquidity validates C2 entry
 */
bool UpdateFractalLiquidity(SFractalContext &fractal, SLiquidityContext &liq)
{
   // Check if liquidity event validates C2
   bool valid_for_c2 = (liq.type == LIQ_SWEEP || liq.type == LIQ_GRAB);

   if(valid_for_c2 && fractal.state == FRACTAL_STATE_C2)
   {
      // Liquidity confirms C2
      fractal.liquidity_swept = true;

      // Update sweep direction based on liquidity type
      if(liq.is_swing_low || liq.is_eql)
         fractal.sweep_direction = DIRECTION_BUY;
      else if(liq.is_swing_high || liq.is_eqh)
         fractal.sweep_direction = DIRECTION_SELL;
      
LogPrint("[LIQUIDITY] C2 Validated | Type=" + GetLiquidityTypeString(liq.type) +
             " | Level=" + DoubleToString(liq.level, _Digits), LOG_LEVEL_DEBUG);
      
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| LOGGING FUNCTIONS                                                |
//+------------------------------------------------------------------+

/**
 * LogLiquidityEvent — Log liquidity event in required format
 * 
 * Format:
 * [LIQUIDITY] Type=SWEEP | Level=xxx
 *
 * @param ctx Liquidity context to log
 */
void LogLiquidityEvent(SLiquidityContext &ctx)
{
   string type_str = GetLiquidityTypeString(ctx.type);

LogPrint("[LIQUIDITY] Type=" + type_str +
          " | Level=" + DoubleToString(ctx.level, _Digits) +
          " | Strength=" + DoubleToString(ctx.strength, 1) +
          " | Swing=" + (ctx.is_swing_high || ctx.is_swing_low ? "YES" : "NO") +
          " | EQ=" + (ctx.is_eqh || ctx.is_eql ? "YES" : "NO"), LOG_LEVEL_DEBUG);
}

void LogLiquidityDetection(
   string symbol,
   ENUM_TIMEFRAMES timeframe,
   SLiquidityContext &ctx
)
{
   if(ctx.type == LIQ_NONE)
   {
      LogPrint("[LIQUIDITY] No event detected | " + symbol + " | " + EnumToString(timeframe), LOG_LEVEL_DEBUG);
      return;
   }

   LogPrint("[LIQUIDITY] Detected | Symbol=" + symbol +
          " | TF=" + EnumToString(timeframe) +
          " | Type=" + GetLiquidityTypeString(ctx.type) +
          " | Level=" + DoubleToString(ctx.level, _Digits) +
          " | Sweep=" + DoubleToString(ctx.sweep_distance, _Digits), LOG_LEVEL_DEBUG);
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+

/**
 * GetLiquidityTypeString — Convert liquidity type to string
 * 
 * @param type Liquidity type
 * @return String representation
 */
string GetLiquidityTypeString(ENUM_LIQUIDITY_TYPE type)
{
   switch(type)
   {
      case LIQ_GRAB:   return "GRAB";
      case LIQ_SWEEP:  return "SWEEP";
      case LIQ_RAID:   return "RAID";
      default:         return "NONE";
   }
}

/**
 * GetLiquidityAssessment — Get liquidity event assessment
 * 
 * @param ctx Liquidity context
 * @return Assessment string
 */
string GetLiquidityAssessment(SLiquidityContext &ctx)
{
   if(ctx.type == LIQ_NONE)
      return "No liquidity event";

   string assessment = GetLiquidityTypeString(ctx.type);

   if(ctx.strength >= 80.0)
      assessment += " (VERY STRONG)";
   else if(ctx.strength >= 60.0)
      assessment += " (STRONG)";
   else if(ctx.strength >= 40.0)
      assessment += " (MODERATE)";
   else
      assessment += " (WEAK)";
   
   return assessment;
}

/**
 * IsLiquidityValidForEntry — Check if liquidity validates entry
 * 
 * Valid for entry:
 * - Type is SWEEP or GRAB
 * - Strength >= 30
 * - Level is valid (> 0)
 * 
 * @param ctx Liquidity context
 * @return true if valid for entry
 */
bool IsLiquidityValidForEntry(SLiquidityContext &ctx)
{
   if(ctx.type != LIQ_SWEEP && ctx.type != LIQ_GRAB)
      return false;

   if(ctx.strength < 30.0)
      return false;

   if(ctx.level <= 0)
      return false;

   return true;
}

/**
 * GetLiquidityDirection — Get liquidity event direction
 * 
 * @param ctx Liquidity context
 * @return DIRECTION_BUY, DIRECTION_SELL, or DIRECTION_NONE
 */
ENUM_DIRECTION GetLiquidityDirection(SLiquidityContext &ctx)
{
   if(ctx.is_swing_low || ctx.is_eql)
      return DIRECTION_BUY;  // Swept lows → bullish reversal

   if(ctx.is_swing_high || ctx.is_eqh)
      return DIRECTION_SELL;  // Swept highs → bearish reversal

   return DIRECTION_NONE;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+

#endif // OMAK_LIQUIDITYENGINE_MQH
