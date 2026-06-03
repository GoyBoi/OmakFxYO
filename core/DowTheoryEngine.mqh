//+------------------------------------------------------------------+
//|                                      DowTheoryEngine.mqh |
//|                        OmakFxYO — Dow Theory Engine |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_DOWTHEORYENGINE_MQH
#define OMAK_DOWTHEORYENGINE_MQH

#property strict

#property copyright "OMAK"
#property version   "1.00"
#property description "Dow Theory Engine — Market Structure Detection"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>         // Base types
#include <OmakFxYO/core/VolumeAnalyzer.mqh>    // SVolumeAnalysis, AnalyzeVolume

// Volume confirmation is opt-in, controlled via g_trueTTradesConfig.useVolumeConfirmation
// from UniversalConfig.mqh. Safe default: disabled for forex/synthetics.

//+------------------------------------------------------------------+
//| ENUM_TREND_DIRECTION — Dow Theory Trend                          |
//+------------------------------------------------------------------+
/**
 * ENUM_TREND_DIRECTION
 * 
 * Defines trend direction based on Dow Theory structure.
 * 
 * BULLISH: HH + HL sequence (Higher Highs + Higher Lows)
 * BEARISH: LH + LL sequence (Lower Highs + Lower Lows)
 * NONE: No clear sequence (ranging/choppy)
 */
enum ENUM_TREND_DIRECTION
{
   TREND_NONE = 0,         // No clear trend
   TREND_BULLISH,          // HH + HL sequence
   TREND_BEARISH           // LH + LL sequence
};

//+------------------------------------------------------------------+
//| ENUM_STRUCTURE_EVENT — Market Structure Events                   |
//+------------------------------------------------------------------+
/**
 * ENUM_STRUCTURE_EVENT
 * 
 * Detects key market structure events.
 * 
 * BOS (Break of Structure): Trend continuation
 * CHoCH (Change of Character): Potential reversal
 */
enum ENUM_STRUCTURE_EVENT
{
   EVENT_NONE = 0,         // No event
   EVENT_BOS,              // Break of Structure
   EVENT_CHoCH             // Change of Character
};

//+------------------------------------------------------------------+
//| SSwingPoint — Swing Point Structure                               |
//+------------------------------------------------------------------+
/**
 * SSwingPoint
 * 
 * Represents a confirmed swing high or low.
 * Used for HH/HL/LH/LL detection.
 */
struct SSwingPoint
{
   datetime time;          // Swing time
   double price;           // Swing price
   bool isHigh;            // true = swing high, false = swing low
   bool isConfirmed;       // true if confirmed by subsequent price action
   int barShift;           // Bar shift where swing occurred
   
   //+------------------------------------------------------------------+
   // | Reset — Clear to defaults                                      |
   //+------------------------------------------------------------------+
   void Reset()
   {
      time = 0;
      price = 0.0;
      isHigh = false;
      isConfirmed = false;
      barShift = 0;
   }
};

//+------------------------------------------------------------------+
//| SDowTheoryContext — Dow Theory Analysis Context                   |
//+------------------------------------------------------------------+
/**
 * SDowTheoryContext
 * 
 * Contains complete Dow Theory structure analysis.
 * Tracks HH/HL/LH/LL and detects BOS/CHoCH events.
 */
struct SDowTheoryContext
{
   // Trend direction
   ENUM_TREND_DIRECTION trend;         // Current trend
   
   // Swing points
   SSwingPoint lastHH;                 // Last Higher High
   SSwingPoint lastHL;                 // Last Higher Low
   SSwingPoint lastLH;                 // Last Lower High
   SSwingPoint lastLL;                 // Last Lower Low
   
   // Structure events
   ENUM_STRUCTURE_EVENT lastEvent;     // Last detected event
   datetime eventTime;                 // When event occurred
   
// Structure flags
    bool isBullishStructure;            // HH + HL both confirmed (STRONG)
    bool isBearishStructure;            // LH + LL both confirmed (STRONG)
    bool isWeakBullishStructure;         // HH confirmed, no bearish pair (WEAK)
    bool isWeakBearishStructure;          // LL confirmed, no bullish pair (WEAK)
   
   // Analysis metadata
   ENUM_TIMEFRAMES timeframe;          // Timeframe analyzed
   datetime analysisTime;              // When analysis was performed
   
   //+------------------------------------------------------------------+
   // | Reset — Clear all state to defaults                            |
   //+------------------------------------------------------------------+
   void Reset()
   {
      trend = TREND_NONE;
      lastHH.Reset();
      lastHL.Reset();
      lastLH.Reset();
      lastLL.Reset();
      lastEvent = EVENT_NONE;
      eventTime = 0;
isBullishStructure = false;
       isBearishStructure = false;
       isWeakBullishStructure = false;
       isWeakBearishStructure = false;
      timeframe = PERIOD_CURRENT;
      analysisTime = 0;
   }
};

//+------------------------------------------------------------------+
//| SWING POINT DETECTION                                            |
//+------------------------------------------------------------------+

/**
 * DetectSwingHigh — Detect swing high (fractal high)
 * 
 * @param highs[] High prices (series array)
 * @param left_bars Bars to check on left
 * @param right_bars Bars to check on right
 * @return SSwingPoint if detected, empty if not
 */
SSwingPoint DetectSwingHigh(const double &highs[], int left_bars = 5, int right_bars = 5)
{
   SSwingPoint swing;
   swing.Reset();
   swing.isHigh = true;

   if(ArraySize(highs) < left_bars + right_bars + 1)
      return swing;

   int maxIterations = 500;
   int iterations = 0;

   // Check each bar for swing high
   for(int i = left_bars; i < ArraySize(highs) - right_bars; i++)
   {
      iterations++;
      if(iterations >= maxIterations)
      {
         LogPrint("[ERROR] Loop Timeout DetectSwingHigh - Possible Infinite Search | iterations=" + IntegerToString(iterations), LOG_LEVEL_ERROR);
         break;
      }

      double current_high = highs[i];
      bool is_swing = true;

      // Check left side
      for(int j = 1; j <= left_bars; j++)
      {
         if(highs[i - j] >= current_high)
         {
            is_swing = false;
            break;
         }
      }

      if(!is_swing)
         continue;

      // Check right side
      for(int j = 1; j <= right_bars; j++)
      {
         if(highs[i + j] >= current_high)
         {
            is_swing = false;
            break;
         }
      }

      if(is_swing)
      {
         // Found swing high
         swing.time = TimeCurrent() - (PeriodSeconds() * i * 60);
         swing.price = current_high;
         swing.barShift = i;
         swing.isConfirmed = true;

         return swing;
      }
   }

   return swing;
}

/**
 * DetectSwingLow — Detect swing low (fractal low)
 * 
 * @param lows[] Low prices (series array)
 * @param left_bars Bars to check on left
 * @param right_bars Bars to check on right
 * @return SSwingPoint if detected, empty if not
 */
SSwingPoint DetectSwingLow(const double &lows[], int left_bars = 5, int right_bars = 5)
{
   SSwingPoint swing;
   swing.Reset();
   swing.isHigh = false;

   if(ArraySize(lows) < left_bars + right_bars + 1)
      return swing;

   int maxIterations = 500;
   int iterations = 0;

   // Check each bar for swing low
   for(int i = left_bars; i < ArraySize(lows) - right_bars; i++)
   {
      iterations++;
      if(iterations >= maxIterations)
      {
         LogPrint("[ERROR] Loop Timeout DetectSwingLow - Possible Infinite Search | iterations=" + IntegerToString(iterations), LOG_LEVEL_ERROR);
         break;
      }

      double current_low = lows[i];
      bool is_swing = true;

      // Check left side
      for(int j = 1; j <= left_bars; j++)
      {
         if(lows[i - j] <= current_low)
         {
            is_swing = false;
            break;
         }
      }

      if(!is_swing)
         continue;

      // Check right side
      for(int j = 1; j <= right_bars; j++)
      {
         if(lows[i + j] <= current_low)
         {
            is_swing = false;
            break;
         }
      }

      if(is_swing)
      {
         // Found swing low
         swing.time = TimeCurrent() - (PeriodSeconds() * i * 60);
         swing.price = current_low;
         swing.barShift = i;
         swing.isConfirmed = true;
         
         return swing;
      }
   }
   
   return swing;
}

//+------------------------------------------------------------------+
//| STRUCTURE ANALYSIS                                               |
struct SDTLookbackConfig
{
   int lookback_bars;
   int min_gap;
};

SDTLookbackConfig DT_GetLookbackConfig(ENUM_TIMEFRAMES tf)
{
   SDTLookbackConfig cfg;
   switch(tf)
   {
      case PERIOD_M1:   cfg.lookback_bars = 2000; cfg.min_gap = 3; break;
      case PERIOD_M5:   cfg.lookback_bars =  600; cfg.min_gap = 3; break;
      case PERIOD_M15:  cfg.lookback_bars =  250; cfg.min_gap = 3; break;
      case PERIOD_M30:  cfg.lookback_bars =  150; cfg.min_gap = 3; break;
      case PERIOD_H1:   cfg.lookback_bars =  480; cfg.min_gap = 3; break;
      case PERIOD_H4:   cfg.lookback_bars =  250; cfg.min_gap = 3; break;
      case PERIOD_D1:   cfg.lookback_bars =  250; cfg.min_gap = 3; break;  // Enhanced: 250 bars (was 60)
      case PERIOD_W1:   cfg.lookback_bars =   30; cfg.min_gap = 2; break;
      case PERIOD_MN1:  cfg.lookback_bars =   24; cfg.min_gap = 2; break;
      default:          cfg.lookback_bars =  300; cfg.min_gap = 3; break;
   }
   return cfg;
}
//+------------------------------------------------------------------+

/**
 * AnalyzeStructure — Perform complete Dow Theory analysis
 *
 * @param symbol Symbol to analyze
 * @param tf Timeframe to analyze
 * @return SDowTheoryContext with complete analysis
 */
SDowTheoryContext AnalyzeStructure(
   const string symbol,
   ENUM_TIMEFRAMES tf
)
{
   SDowTheoryContext ctx;
   ZeroMemory(ctx);
   ctx.Reset();
   ctx.timeframe = tf;
   ctx.analysisTime = TimeCurrent();

   SDTLookbackConfig cfg = DT_GetLookbackConfig(tf);
   int lookback_bars = cfg.lookback_bars;
   int min_gap       = cfg.min_gap;

   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);

   int copied_h = CopyHigh(symbol, tf, 0, lookback_bars, highs);
   int copied_l = CopyLow(symbol, tf, 0, lookback_bars, lows);
   if(copied_h < lookback_bars || copied_l < lookback_bars)
      return ctx;

   SSwingPoint swingHigh = DetectSwingHigh(highs, 5, 5);
   SSwingPoint swingLow  = DetectSwingLow(lows, 5, 5);

   LogPrint(StringFormat("[DOW-DBG] SH: confirmed=%s price=%.2f | SL: confirmed=%s price=%.2f | TF=%s",
      swingHigh.isConfirmed ? "YES" : "NO", swingHigh.price,
      swingLow.isConfirmed  ? "YES" : "NO", swingLow.price,
      EnumToString(tf)), LOG_LEVEL_DEBUG);

   SSwingPoint prevSwingHigh, prevSwingLow;
   prevSwingHigh.Reset();
   prevSwingLow.Reset();

   if(swingHigh.isConfirmed && swingHigh.barShift + min_gap < lookback_bars)
   {
      int prev_lookback = lookback_bars;
      int start = swingHigh.barShift + 1;
      int min_needed = (min_gap * 2 + 1) + 5;
      if(prev_lookback >= min_needed && start > 0)
      {
         double highs2[];
         ArraySetAsSeries(highs2, true);
         int copied = CopyHigh(symbol, tf, start, prev_lookback, highs2);
         if(copied >= min_needed)
         {
            prevSwingHigh = DetectSwingHigh(highs2, 5, 5);
            if(prevSwingHigh.isConfirmed)
               prevSwingHigh.barShift += start;
         }
      }
   }

   if(swingLow.isConfirmed && swingLow.barShift + min_gap < lookback_bars)
   {
      int prev_lookback = lookback_bars;
      int start = swingLow.barShift + 1;
      int min_needed = (min_gap * 2 + 1) + 5;
      if(prev_lookback >= min_needed && start > 0)
      {
         double lows2[];
         ArraySetAsSeries(lows2, true);
         int copied = CopyLow(symbol, tf, start, prev_lookback, lows2);
         if(copied >= min_needed)
         {
            prevSwingLow = DetectSwingLow(lows2, 5, 5);
            if(prevSwingLow.isConfirmed)
               prevSwingLow.barShift += start;
         }
      }
   }

   LogPrint(StringFormat("[DOW-DBG] prevSH: confirmed=%s price=%.2f | prevSL: confirmed=%s price=%.2f",
      prevSwingHigh.isConfirmed ? "YES" : "NO", prevSwingHigh.price,
      prevSwingLow.isConfirmed  ? "YES" : "NO", prevSwingLow.price), LOG_LEVEL_DEBUG);

   // Two confirmed consecutive swings required. One swing alone is never sufficient.
   bool has_HH = (swingHigh.isConfirmed && prevSwingHigh.isConfirmed &&
                 swingHigh.price > prevSwingHigh.price);
   bool has_HL = (swingLow.isConfirmed && prevSwingLow.isConfirmed &&
                 swingLow.price > prevSwingLow.price);
   bool has_LH = (swingHigh.isConfirmed && prevSwingHigh.isConfirmed &&
                 swingHigh.price < prevSwingHigh.price);
   bool has_LL = (swingLow.isConfirmed && prevSwingLow.isConfirmed &&
                 swingLow.price < prevSwingLow.price);

   LogPrint(StringFormat("[DOW-DBG] has_HH=%s has_HL=%s has_LH=%s has_LL=%s",
      has_HH ? "T" : "F", has_HL ? "T" : "F",
      has_LH ? "T" : "F", has_LL ? "T" : "F"), LOG_LEVEL_DEBUG);

   if(swingHigh.isConfirmed) { ctx.lastHH = swingHigh; ctx.lastLH = swingHigh; }
   if(swingLow.isConfirmed)  { ctx.lastHL = swingLow;  ctx.lastLL = swingLow;  }

   if(has_HH) ctx.lastHH = swingHigh;
   if(has_HL) ctx.lastHL = swingLow;
   if(has_LH) ctx.lastLH = swingHigh;
   if(has_LL) ctx.lastLL = swingLow;

ctx.isBullishStructure = (has_HH && has_HL);
    ctx.isBearishStructure = (has_LH && has_LL);

    // WEAK tier: at least one confirmed pair in dominant direction
    // Rationale: on H1/H4, HH alone or LL alone is sufficient structural evidence
ctx.isWeakBullishStructure = (has_HH && !ctx.isBearishStructure);
   ctx.isWeakBearishStructure = (has_LL && !ctx.isBullishStructure);

   LogPrint(StringFormat("[DOW-DBG] isBull=%s isBear=%s isWeakBull=%s isWeakBear=%s",
      ctx.isBullishStructure     ? "T" : "F",
      ctx.isBearishStructure     ? "T" : "F",
      ctx.isWeakBullishStructure ? "T" : "F",
      ctx.isWeakBearishStructure ? "T" : "F"), LOG_LEVEL_DEBUG);

   ctx.trend = DetermineTrend(ctx);

// Wire DetectBOS() - previously omitted (Q&A Report Q7-a)
   double current_price = SymbolInfoDouble(symbol, SYMBOL_BID);
   ctx.lastEvent = DetectBOS(ctx, current_price);

   LogPrint(StringFormat("[DOW-DBG] lastEvent=%s trend=%s",
      EnumToString(ctx.lastEvent),
      EnumToString(ctx.trend)), LOG_LEVEL_DEBUG);

   return ctx;
}

//+------------------------------------------------------------------+
//| TREND DETERMINATION                                              |
//+------------------------------------------------------------------+

/**
 * DetermineTrend — Determine trend from structure
 * 
 * @param ctx Dow Theory context
 * @return ENUM_TREND_DIRECTION
 */
ENUM_TREND_DIRECTION DetermineTrend(SDowTheoryContext &ctx)
{
   // Bullish trend: HH + HL sequence
   if(ctx.isBullishStructure && !ctx.isBearishStructure)
      return TREND_BULLISH;

   // Bearish trend: LH + LL sequence
   if(ctx.isBearishStructure && !ctx.isBullishStructure)
      return TREND_BEARISH;

   // No clear trend (ranging or conflicting)
   return TREND_NONE;
}

//+------------------------------------------------------------------+
//| EVENT DETECTION                                                  |
//+------------------------------------------------------------------+

struct SDowTheoryEvent
{
   ENUM_STRUCTURE_EVENT type;
   datetime             time;
   double               price;
   bool                 volumeConfirmed;  // Always true when InpUseVolumeConfirmation=false
   double               volumeRatio;
   bool                 isValid;
};

//+------------------------------------------------------------------+
//| BOS detection with optional volume confirmation                  |
//| Volume confirmation only blocks when InpUseVolumeConfirmation=true|
//| AND instrument has reliable volume data                          |
//+------------------------------------------------------------------+
SDowTheoryEvent DetectBOSWithVolume(const SDowTheoryContext &ctx,
                                     ENUM_TIMEFRAMES tf)
{
   SDowTheoryEvent event;
   ZeroMemory(event);
   event.type = EVENT_NONE;

   bool bosDetected = (ctx.lastEvent == EVENT_BOS);
   if(!bosDetected) return event;

   event.type  = EVENT_BOS;
   event.time  = ctx.eventTime;
   event.price = ctx.lastHH.price; // or lastLL depending on direction — caller context

   SVolumeAnalysis vol = AnalyzeVolume(tf, 0, 10);
   event.volumeConfirmed = vol.isExpanding || !vol.dataAvailable;
   event.volumeRatio     = vol.expansionRatio;

   // isValid: always true when volume confirmation is off
   event.isValid = !g_trueTTradesConfig.useVolumeConfirmation || event.volumeConfirmed;

   return event;
}

/**
 * DetectBOS — Detect Break of Structure
 * 
 * BOS occurs when price breaks previous high in uptrend or low in downtrend
 * 
 * @param ctx Dow Theory context
 * @param current_price Current price
 * @return EVENT_BOS if detected, EVENT_NONE otherwise
 */
ENUM_STRUCTURE_EVENT DetectBOS(SDowTheoryContext &ctx, double current_price)
{
   if(ctx.trend == TREND_BULLISH)
   {
      // In uptrend, BOS = break of previous high (LH)
      if(ctx.lastLH.isConfirmed && current_price > ctx.lastLH.price)
      {
         return EVENT_BOS;
      }
   }
   else if(ctx.trend == TREND_BEARISH)
   {
      // In downtrend, BOS = break of previous low (HL)
      if(ctx.lastHL.isConfirmed && current_price < ctx.lastHL.price)
      {
         return EVENT_BOS;
      }
   }
   
   return EVENT_NONE;
}

/**
 * DetectCHoCH — Detect Change of Character
 * 
 * CHoCH occurs when trend structure is violated
 * - Bullish → Bearish: Price breaks below last HL
 * - Bearish → Bullish: Price breaks above last LH
 * 
 * @param ctx Dow Theory context
 * @param prev_trend Previous trend direction
 * @return EVENT_CHoCH if detected, EVENT_NONE otherwise
 */
ENUM_STRUCTURE_EVENT DetectCHoCH(
   SDowTheoryContext &ctx,
   ENUM_TREND_DIRECTION prev_trend
)
{
   // Bullish to Bearish CHoCH
   if(prev_trend == TREND_BULLISH && ctx.trend == TREND_BEARISH)
   {
      return EVENT_CHoCH;
   }

   // Bearish to Bullish CHoCH
   if(prev_trend == TREND_BEARISH && ctx.trend == TREND_BULLISH)
   {
      return EVENT_CHoCH;
   }
   
   return EVENT_NONE;
}

//+------------------------------------------------------------------+
//| LOGGING FUNCTIONS                                                |
//+------------------------------------------------------------------+

/**
 * LogDowTheoryAnalysis — Log Dow Theory analysis
 *
 * @param ctx Dow Theory context
 */
void LogDowTheoryAnalysis(SDowTheoryContext &ctx)
{
   string trend_str = "";
   switch(ctx.trend)
   {
      case TREND_BULLISH:  trend_str = "BULLISH"; break;
      case TREND_BEARISH:  trend_str = "BEARISH"; break;
      default:             trend_str = "NONE"; break;
   }

LogPrint("[DOW] Trend=" + trend_str +
          " | HH/HL=" + (ctx.isBullishStructure ? "YES" : "NO") +
          " | LH/LL=" + (ctx.isBearishStructure ? "YES" : "NO") +
          " | TF=" + EnumToString(ctx.timeframe), LOG_LEVEL_DEBUG);
    
    if(ctx.lastEvent != EVENT_NONE)
    {
       string event_str = (ctx.lastEvent == EVENT_BOS) ? "BOS" : "CHoCH";
       LogPrint("[DOW] Event=" + event_str + " | Time=" + TimeToString(ctx.eventTime), LOG_LEVEL_DEBUG);
    }
}

/**
 * LogTrendConfirmation — Log trend confirmation
 * 
 * @param trend Trend direction
 * @param isConfirmed Confirmation status
 */
void LogTrendConfirmation(ENUM_TREND_DIRECTION trend, bool isConfirmed)
{
   string trend_str = "";
   switch(trend)
   {
      case TREND_BULLISH:  trend_str = "BULLISH"; break;
      case TREND_BEARISH:  trend_str = "BEARISH"; break;
      default:             trend_str = "NONE"; break;
   }
   
   if(isConfirmed)
LogPrint("[DOW] Trend=" + trend_str + " | HH/HL confirmed", LOG_LEVEL_DEBUG);
    else
       LogPrint("[DOW] Trend=" + trend_str + " | Structure weak", LOG_LEVEL_DEBUG);
}

/**
 * LogCHoCHDetection — Log CHoCH detection
 * 
 * @param prev_trend Previous trend
 * @param new_trend New trend
 */
void LogCHoCHDetection(ENUM_TREND_DIRECTION prev_trend, ENUM_TREND_DIRECTION new_trend)
{
   string prev_str = (prev_trend == TREND_BULLISH) ? "BULLISH" : "BEARISH";
   string new_str = (new_trend == TREND_BULLISH) ? "BULLISH" : "BEARISH";
   
   LogPrint("[DOW] CHoCH detected → possible reversal | " + prev_str + " → " + new_str, LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+

/**
 * GetTrendString — Convert trend to string
 * 
 * @param trend Trend direction
 * @return String representation
 */
string GetTrendString(ENUM_TREND_DIRECTION trend)
{
   switch(trend)
   {
      case TREND_BULLISH:  return "BULLISH";
      case TREND_BEARISH:  return "BEARISH";
      default:             return "NONE";
   }
}

/**
 * GetEventString — Convert event to string
 * 
 * @param event Structure event
 * @return String representation
 */
string GetEventString(ENUM_STRUCTURE_EVENT event)
{
   switch(event)
   {
      case EVENT_BOS:   return "BOS";
      case EVENT_CHoCH: return "CHoCH";
      default:          return "NONE";
   }
}

/**
 * IsTrendValid — Quick trend validity check
 * 
 * @param ctx Dow Theory context
 * @return true if trend is valid (confirmed structure)
 */
bool IsTrendValid(SDowTheoryContext &ctx)
{
   if(ctx.trend == TREND_BULLISH)
      return ctx.isBullishStructure;

   if(ctx.trend == TREND_BEARISH)
      return ctx.isBearishStructure;

   return false;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+

#endif // OMAK_DOWTHEORYENGINE_MQH
