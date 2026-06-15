//+------------------------------------------------------------------+
//|                                          TargetEngine.mqh |
//|                        OmakFxYO — Target Engine |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_TARGETENGINE_MQH
#define OMAK_TARGETENGINE_MQH

#property strict

#property copyright "OMAK"
#property version   "1.00"
#property description "Target Engine — Liquidity-Based Take Profit Calculation"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>        // Base types
#include <OmakFxYO/core/FractalState.mqh>     // Fractal context
#include <OmakFxYO/core/LiquidityEngine.mqh>  // Liquidity context
#include <OmakFxYO/core/ModeResolver.mqh>     // SRiskProfile, GetRiskProfile

//+------------------------------------------------------------------+
//| ENUM_TP_TYPE — Take Profit Target Type                          |
//+------------------------------------------------------------------+
/**
 * ENUM_TP_TYPE
 * 
 * Classifies take profit target by liquidity type.
 * Based on SMC liquidity targeting principles.
 * 
 * Types:
 * - INTERNAL: Swing highs/lows (near-term liquidity)
 * - EXTERNAL: PDH/PDL, PWH/PWL (major liquidity)
 * - EQUAL: Equal highs/lows (engineered liquidity)
 */
enum ENUM_TP_TYPE
{
   TP_NONE = 0,            // No valid target
   TP_INTERNAL,            // Internal liquidity (swing)
   TP_EXTERNAL,            // External liquidity (PDH/PDL)
   TP_EQUAL                // Equal highs/lows
};

//+------------------------------------------------------------------+
//| STargetResult — Take Profit Target Result                        |
//+------------------------------------------------------------------+
/**
 * STargetResult
 * 
 * Contains complete TP target data with multi-TP support.
 * Multi-TP system allows partial exits at different liquidity levels.
 */
struct STargetResult
{
   // TP Levels
   double tp1;                 // TP1 (internal liquidity)
   double tp2;                 // TP2 (external liquidity)
   double tp3;                 // TP3 (optional - equal highs/lows)
   
   // Target classification
   ENUM_TP_TYPE type;          // Primary TP type
   double targetLiquidity;     // Target liquidity price
   string liquiditySource;     // Source description
   
   // Validation
   bool isValid;               // Targets are valid
   double rr_tp1;              // R:R at TP1
   double rr_tp2;              // R:R at TP2
   
   //+------------------------------------------------------------------+
   // | Constructor — Initialize to defaults                           |
   //+------------------------------------------------------------------+
   void STargetResult()
   {
      Reset();
   }
   
   //+------------------------------------------------------------------+
   // | Reset — Clear all state to defaults                            |
   //+------------------------------------------------------------------+
   void Reset()
   {
      tp1 = 0.0;
      tp2 = 0.0;
      tp3 = 0.0;
      type = TP_NONE;
      targetLiquidity = 0.0;
      liquiditySource = "NONE";
      isValid = false;
      rr_tp1 = 0.0;
      rr_tp2 = 0.0;
   }
};

//+------------------------------------------------------------------+
//| LIQUIDITY TARGET DETECTION                                       |
//+------------------------------------------------------------------+

/**
 * DetectEqualHighsTarget — Detect equal highs target
 * 
 * @param highs[] High prices (series array)
 * @param lookback Lookback period
 * @return Equal highs level (0.0 if not found)
 */
double DetectEqualHighsTarget(const double &highs[], int lookback = 50)
{
   if(ArraySize(highs) < lookback)
      return 0.0;
   
   double reference_high = highs[0];
   double tolerance = reference_high * 0.001;  // 0.1% tolerance
   int eqh_count = 0;
   double eqh_level = 0.0;
   
   // Count highs within tolerance
   for(int i = 0; i < lookback && i < ArraySize(highs); i++)
   {
      if(MathAbs(highs[i] - reference_high) <= tolerance)
      {
         eqh_count++;
         eqh_level = MathMax(eqh_level, highs[i]);
      }
   }
   
   // Return equal highs level if found (at least 2 touches)
   if(eqh_count >= 2)
      return eqh_level;
   
   return 0.0;
}

/**
 * DetectEqualLowsTarget — Detect equal lows target
 * 
 * @param lows[] Low prices (series array)
 * @param lookback Lookback period
 * @return Equal lows level (0.0 if not found)
 */
double DetectEqualLowsTarget(const double &lows[], int lookback = 50)
{
   if(ArraySize(lows) < lookback)
      return 0.0;
   
   double reference_low = lows[0];
   double tolerance = reference_low * 0.001;  // 0.1% tolerance
   int eql_count = 0;
   double eql_level = 0.0;
   
   // Count lows within tolerance
   for(int i = 0; i < lookback && i < ArraySize(lows); i++)
   {
      if(MathAbs(lows[i] - reference_low) <= tolerance)
      {
         eql_count++;
         eql_level = (eql_level == 0.0) ? lows[i] : MathMin(eql_level, lows[i]);
      }
   }
   
   // Return equal lows level if found (at least 2 touches)
   if(eql_count >= 2)
      return eql_level;
   
   return 0.0;
}

/**
 * DetectSwingHighTarget — Detect swing high target
 * 
 * @param highs[] High prices
 * @param shift Bar shift to check
 * @return Swing high level
 */
double DetectSwingHighTarget(const double &highs[], int shift = 5)
{
   if(ArraySize(highs) <= shift)
      return 0.0;
   
   return highs[shift];
}

/**
 * DetectSwingLowTarget — Detect swing low target
 * 
 * @param lows[] Low prices
 * @param shift Bar shift to check
 * @return Swing low level
 */
double DetectSwingLowTarget(const double &lows[], int shift = 5)
{
   if(ArraySize(lows) <= shift)
      return 0.0;
   
   return lows[shift];
}

/**
 * GetPDH — Get Previous Day High
 * 
 * @param symbol Symbol
 * @param date Date to get PDH for (0 = previous day)
 * @return Previous day high
 */
double GetPDH(string symbol, datetime date = 0)
{
   datetime today = TimeCurrent();
   
   if(date == 0)
   {
      // Get previous day
      datetime yesterday = today - (60 * 60 * 24);
      date = yesterday;
   }
   
   // Copy high from daily timeframe
   double highs[];
   ArraySetAsSeries(highs, true);
   
   int copied = CopyHigh(symbol, PERIOD_D1, date, 1, highs);
   if(copied > 0 && highs[0] > 0)
      return highs[0];
   
   return 0.0;
}

/**
 * GetPDL — Get Previous Day Low
 * 
 * @param symbol Symbol
 * @param date Date to get PDL for (0 = previous day)
 * @return Previous day low
 */
double GetPDL(string symbol, datetime date = 0)
{
   datetime today = TimeCurrent();
   
   if(date == 0)
   {
      // Get previous day
      datetime yesterday = today - (60 * 60 * 24);
      date = yesterday;
   }
   
   // Copy low from daily timeframe
   double lows[];
   ArraySetAsSeries(lows, true);
   
   int copied = CopyLow(symbol, PERIOD_D1, date, 1, lows);
   if(copied > 0 && lows[0] > 0)
      return lows[0];
   
   return 0.0;
}

/**
 * GetPWH — Get Previous Week High
 * 
 * @param symbol Symbol
 * @param date Date to get PWH for (0 = previous week)
 * @return Previous week high
 */
double GetPWH(string symbol, datetime date = 0)
{
   datetime today = TimeCurrent();
   
   if(date == 0)
   {
      // Get previous week
      datetime last_week = today - (60 * 60 * 24 * 7);
      date = last_week;
   }
   
   // Copy high from weekly timeframe
   double highs[];
   ArraySetAsSeries(highs, true);
   
   int copied = CopyHigh(symbol, PERIOD_W1, date, 1, highs);
   if(copied > 0 && highs[0] > 0)
      return highs[0];
   
   return 0.0;
}

/**
 * GetPWL — Get Previous Week Low
 * 
 * @param symbol Symbol
 * @param date Date to get PWL for (0 = previous week)
 * @return Previous week low
 */
double GetPWL(string symbol, datetime date = 0)
{
   datetime today = TimeCurrent();
   
   if(date == 0)
   {
      // Get previous week
      datetime last_week = today - (60 * 60 * 24 * 7);
      date = last_week;
   }
   
   // Copy low from weekly timeframe
   double lows[];
   ArraySetAsSeries(lows, true);
   
   int copied = CopyLow(symbol, PERIOD_W1, date, 1, lows);
   if(copied > 0 && lows[0] > 0)
      return lows[0];
   
   return 0.0;
}

//+------------------------------------------------------------------+
//| TP CALCULATION                                                  |
//+------------------------------------------------------------------+

/**
 * CalculateLiquidityTargets — Calculate multi-TP targets
 * 
 * BUY Targets:
 * - TP1: Nearest swing high (internal)
 * - TP2: PDH or equal highs (external)
 * - TP3: PWH (major external)
 * 
 * SELL Targets:
 * - TP1: Nearest swing low (internal)
 * - TP2: PDL or equal lows (external)
 * - TP3: PWL (major external)
 * 
 * @param fractal Fractal context
 * @param liq Liquidity context
 * @param direction Entry direction
 * @param entryPrice Entry price
 * @return STargetResult with TP levels
 */
STargetResult CalculateLiquidityTargets(
   SFractalContext &fractal,
   SLiquidityContext &liq,
   ENUM_DIRECTION direction,
   double entryPrice
)
{
   STargetResult result;
   result.Reset();

   // Validate inputs
   if(entryPrice <= 0)
      return result;
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   
   // Copy price data
   int copied = CopyHigh(_Symbol, PERIOD_CURRENT, 0, 100, highs);
   if(copied < 100)
      return result;
   
   copied = CopyLow(_Symbol, PERIOD_CURRENT, 0, 100, lows);
   if(copied < 100)
      return result;
   
   // Calculate targets based on direction
   if(direction == DIRECTION_BUY)
   {
      // BUY: Targets above entry
      
       // TP1: Nearest swing high (internal) — NO point fallback
       result.tp1 = DetectSwingHighTarget(highs, 5);
       
       // TP2: PDH or equal highs (external) — NO point fallback
       double pdh = GetPDH(_Symbol);
       double eqh = DetectEqualHighsTarget(highs, 50);
       
       if(pdh > entryPrice && (eqh <= entryPrice || pdh <= eqh))
          result.tp2 = pdh;
       else if(eqh > entryPrice)
          result.tp2 = eqh;
       
       // TP3: PWH (major external) — NO point fallback
       double pwh = GetPWH(_Symbol);
       if(pwh > result.tp2)
          result.tp3 = pwh;
   }
   else if(direction == DIRECTION_SELL)
   {
      // SELL: Targets below entry
      
       // TP1: Nearest swing low (internal) — NO point fallback
       result.tp1 = DetectSwingLowTarget(lows, 5);
       
       // TP2: PDL or equal lows (external) — NO point fallback
       double pdl = GetPDL(_Symbol);
       double eql = DetectEqualLowsTarget(lows, 50);
       
       if(pdl < entryPrice && pdl > 0 && (eql <= 0 || pdl >= eql))
          result.tp2 = pdl;
       else if(eql < entryPrice && eql > 0)
          result.tp2 = eql;
       
       // TP3: PWL (major external) — NO point fallback
       double pwl = GetPWL(_Symbol);
       if(pwl > 0 && pwl < result.tp2)
          result.tp3 = pwl;
   }
   
   // Set primary target type
   if(result.tp2 > 0)
   {
      result.type = TP_EXTERNAL;
      result.targetLiquidity = result.tp2;
      result.liquiditySource = "PDH/PDL or Equal H/L";
   }
   else if(result.tp1 > 0)
   {
      result.type = TP_INTERNAL;
      result.targetLiquidity = result.tp1;
      result.liquiditySource = "Swing High/Low";
   }
   
   // Mark as valid
   result.isValid = (result.tp1 > 0);
   
   return result;
}

/**
 * CalculateRR — Calculate risk-reward ratio at target
 * 
 * @param entryPrice Entry price
 * @param stopLoss Stop loss price
 * @param takeProfit Take profit price
 * @param direction Entry direction
 * @return R:R ratio
 */
double CalculateRR(double entryPrice, double stopLoss, double takeProfit, ENUM_DIRECTION direction)
{
   if(entryPrice <= 0 || stopLoss <= 0 || takeProfit <= 0)
      return 0.0;
   
   double risk = MathAbs(entryPrice - stopLoss);
   double reward = 0.0;
   
   if(direction == DIRECTION_BUY)
      reward = takeProfit - entryPrice;
   else
      reward = entryPrice - takeProfit;
   
   if(risk <= 0)
      return 0.0;
   
   return reward / risk;
}

//+------------------------------------------------------------------+
//| LOGGING FUNCTIONS                                                |
//+------------------------------------------------------------------+

/**
 * LogTargetCalculation — Log TP target calculation
 * 
 * Format:
 * [TP] Target=Liquidity | Price=xxx
 * 
 * @param result Target result to log
 * @param direction Entry direction
 */
void LogTargetCalculation(STargetResult &result, ENUM_DIRECTION direction)
{
   string type_str = "";
   switch(result.type)
   {
      case TP_INTERNAL:  type_str = "Internal"; break;
      case TP_EXTERNAL:  type_str = "External"; break;
      case TP_EQUAL:     type_str = "Equal H/L"; break;
      default:           type_str = "NONE"; break;
   }

   string dir_str = EnumToString(direction);
   
LogPrint("[TP] Target=" + type_str +
          " | Direction=" + dir_str +
          " | TP1=" + DoubleToString(result.tp1, _Digits) +
          " | TP2=" + DoubleToString(result.tp2, _Digits) +
          " | TP3=" + DoubleToString(result.tp3, _Digits) +
          " | Valid=" + (result.isValid ? "TRUE" : "FALSE"), LOG_LEVEL_DEBUG);
    
    if(result.rr_tp1 > 0)
       LogPrint("[TP] R:R at TP1=" + DoubleToString(result.rr_tp1, 2) +
             " | R:R at TP2=" + DoubleToString(result.rr_tp2, 2), LOG_LEVEL_DEBUG);
}

/**
 * LogTargetHit — Log when price hits a target
 * 
 * @param tp_level TP level hit (1, 2, or 3)
 * @param price Price at hit
 * @param profit Profit at hit
 */
void LogTargetHit(int tp_level, double price, double profit = 0.0)
{
LogPrint("[TP] TARGET HIT | TP" + IntegerToString(tp_level) +
          " | Price=" + DoubleToString(price, _Digits) +
          " | Profit=" + DoubleToString(profit, 2), LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+

/**
 * GetTPTypeString — Convert TP type to string
 * 
 * @param type TP type
 * @return String representation
 */
string GetTPTypeString(ENUM_TP_TYPE type)
{
   switch(type)
   {
      case TP_INTERNAL:  return "INTERNAL";
      case TP_EXTERNAL:  return "EXTERNAL";
      case TP_EQUAL:     return "EQUAL";
      default:           return "NONE";
   }
}

/**
 * IsValidTarget — Quick target validity check
 * 
 * @param tp_price Target price
 * @param entry_price Entry price
 * @param direction Direction
 * @return true if valid
 */
bool IsValidTarget(double tp_price, double entry_price, ENUM_DIRECTION direction)
{
   if(tp_price <= 0 || entry_price <= 0)
      return false;
   
   if(direction == DIRECTION_BUY)
      return (tp_price > entry_price);
   else if(direction == DIRECTION_SELL)
      return (tp_price < entry_price);
   
   return false;
}

/**
 * GetNearestTarget — Get nearest valid TP target
 * 
 * @param result Target result
 * @return Nearest TP price
 */
double GetNearestTarget(STargetResult &result)
{
   if(result.tp1 > 0)
      return result.tp1;
   else if(result.tp2 > 0)
      return result.tp2;
   else if(result.tp3 > 0)
      return result.tp3;

   return 0.0;
}

/**
 * GetFurthestTarget — Get furthest valid TP target
 * 
 * @param result Target result
 * @return Furthest TP price
 */
double GetFurthestTarget(STargetResult &result)
{
   if(result.tp3 > 0)
      return result.tp3;
   else if(result.tp2 > 0)
      return result.tp2;
   else if(result.tp1 > 0)
      return result.tp1;

   return 0.0;
}

// [REMOVED] CalculateModeSpecificTargets — non-structural RR-based TP. Invalid per Constitution 2.5.
// REGRESSION_GUARD_V52.5_TARGETENGINE_FALLBACK_REMOVED

//+------------------------------------------------------------------+
//| VERBATIM REPAIR: Finding 2 — Synchronous TP/SL Recalculation      |
//+------------------------------------------------------------------+

/**
 * CalculateHTFLiquidityPool — Get the nearest HTF liquidity pool target
 *
 * Branch-aware: Branch A (Intraday) uses D1 levels (PDH/PDL).
 *              Branch B (Swing) uses W1 levels (PWH/PWL).
 *
 * For BUY: highest HTF liquidity level above current price
 * For SELL: lowest HTF liquidity level below current price
 *
 * @param symbol Trading symbol
 * @param direction Trade direction
 * @param branch Execution branch (BRANCH_INTRADAY → D1, BRANCH_SWING → W1)
 * @return HTF liquidity pool price (0.0 if none found)
 */
double CalculateHTFLiquidityPool(const string symbol, ENUM_DIRECTION direction, ENUM_EXECUTION_BRANCH branch)
{
   if(direction == DIRECTION_BUY)
   {
      if(branch == BRANCH_SWING)
      {
         double pwh = GetPWH(symbol);
         return (pwh > 0) ? pwh : GetPDH(symbol);
      }
      else
      {
         double pdh = GetPDH(symbol);
         return (pdh > 0) ? pdh : GetPWH(symbol);
      }
   }
   else if(direction == DIRECTION_SELL)
   {
      if(branch == BRANCH_SWING)
      {
         double pwl = GetPWL(symbol);
         return (pwl > 0) ? pwl : GetPDL(symbol);
      }
      else
      {
         double pdl = GetPDL(symbol);
         return (pdl > 0) ? pdl : GetPWL(symbol);
      }
   }
   return 0.0;
}

/**
 * CalculateSDProjection — Standard Deviation projection target
 *
 * Projects a target at (level * candle range) from entry price.
 * Uses C2 range first, falls back to C3 range for standalone C3 signals.
 * Level -2.5 is the standard mechanical expansion target.
 *
 * @param sig Locked signal (c2_high/c2_low or c3_high/c3_low for range, entry_price for base)
 * @param level SD level multiplier (e.g., -2.5)
 * @return Projected TP price (0.0 if range is invalid)
 */
double CalculateSDProjection(const SLockedSignal &sig, double level)
{
   double c2Range = MathAbs(sig.c2_high - sig.c2_low);
   double c3Range = MathAbs(sig.c3_high - sig.c3_low);
   double baseRange = (c2Range > 0.0) ? c2Range : c3Range;
   if(baseRange <= 0.0)
      return 0.0;

   double projection = baseRange * MathAbs(level);
   if(sig.direction == DIRECTION_BUY)
      return sig.entry_price + projection;
   else
      return sig.entry_price - projection;
}

/**
 * ValidateRRConvergence — Clamp TP to minR-maxR band relative to refined SL
 *
 * If the current R:R is below minR, TP is widened to meet minR.
 * If above maxR, TP is tightened to maxR.
 *
 * @param sig Locked signal (entry_price, stop_loss, tp are read/written)
 * @param minR Minimum acceptable R:R (default 2.0)
 * @param maxR Maximum acceptable R:R (default 4.0)
 */
void ValidateRRConvergence(SLockedSignal &sig, double minR, double maxR)
{
   if(sig.stop_loss <= 0.0 || sig.tp <= 0.0)
      return;

   double risk = MathAbs(sig.entry_price - sig.stop_loss);
   if(risk <= 0.0)
      return;

   double reward = (sig.direction == DIRECTION_BUY)
      ? (sig.tp - sig.entry_price)
      : (sig.entry_price - sig.tp);

   if(reward <= 0.0)
      return;

   double rr = reward / risk;

   if(rr < minR)
   {
      if(sig.direction == DIRECTION_BUY)
         sig.tp = sig.entry_price + risk * minR;
      else
         sig.tp = sig.entry_price - risk * minR;
   }
   else if(rr > maxR)
   {
      if(sig.direction == DIRECTION_BUY)
         sig.tp = sig.entry_price + risk * maxR;
      else
         sig.tp = sig.entry_price - risk * maxR;
   }
}

/**
 * SyncRefinedTargets — Force TP recalculation when SL is synced to manipulation leg
 *
 * Called immediately after SL refinement to ensure TP stays anchored
 * to HTF Liquidity Pools with SD Projection fallback, clamped to 2R-4R band.
 *
 * @param sig Locked signal to update (entry_price, stop_loss, tp must be set)
 */
void SyncRefinedTargets(SLockedSignal &sig)
{
   double oldTP = sig.tp;

   double liquidityTP = CalculateHTFLiquidityPool(sig.symbol, sig.direction, sig.branch);
   double projectionTP = CalculateSDProjection(sig, -2.5);

    if(sig.tp <= 0.0)
    {
        if(liquidityTP > 0.0)
           sig.tp = liquidityTP;
        else if(projectionTP > 0.0)
           sig.tp = projectionTP;
    }

   if(sig.tp > 0.0)
      ValidateRRConvergence(sig, 2.0, 4.0);

   if(oldTP != sig.tp)
      LogPrint(StringFormat("[TP_SYNC] GUID:%I64u | NewTP:%.5f (Old:%.5f)", sig.m_guid, sig.tp, oldTP), LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+

#endif // OMAK_TARGETENGINE_MQH
