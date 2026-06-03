//+------------------------------------------------------------------+
//| C2WickFilter.mqh                                                 |
//|: C2 wick size validation for anticipation mode           |
//| Part of Omak FxYO — True TTrades Enhancement Framework           |
//+------------------------------------------------------------------+
#ifndef OMAK_C2WICKFILTER_MQH
#define OMAK_C2WICKFILTER_MQH

#property strict

#include <OmakFxYO/core/CoreTypes.mqh>  // STrueTTradesConfig, g_trueTTradesConfig
#include <OmakFxYO/core/LogGovernor.mqh> // LogPrint macro
#include <OmakFxYO/core/UniversalConfig.mqh>

//+------------------------------------------------------------------+
//| CalculateWickPercent — Wick size as % of candle range            |
//+------------------------------------------------------------------+
/**
 * CalculateWickPercent
 *
 * For bullish C2: lower wick = min(open,close) - low
 * For bearish C2: upper wick = high - max(open,close)
 *
 * Wick % = wick size / (high - low)
 *
 * @param high       Candle high
 * @param low        Candle low
 * @param open       Candle open
 * @param close      Candle close
 * @param isUpper    true = measure upper wick, false = measure lower wick
 * @return Wick percentage (0.0 - 1.0), or 0.0 if range is zero
 */
double CalculateWickPercent(double high, double low, double open, double close, bool isUpper)
{
   double range = high - low;
   if(range <= 0.0)
      return 0.0;

   double wickSize;
   if(isUpper)
   {
      // Upper wick: distance from body top to high
      wickSize = high - MathMax(open, close);
   }
   else
   {
      // Lower wick: distance from body bottom to low
      wickSize = MathMin(open, close) - low;
   }

   if(wickSize < 0.0)
      wickSize = 0.0;

   return wickSize / range;
}

//+------------------------------------------------------------------+
//| ValidateC2ForAnticipation — Check if C2 wick passes filter       |
//+------------------------------------------------------------------+
/**
 * ValidateC2ForAnticipation
 *
 * For anticipation mode (early C2 entry), the wick on the
 * rejection side should be small — indicating clean sweep and
 * reversal, not a doji or indecision candle.
 *
 * Bullish reversal: check lower wick (should be small)
 * Bearish reversal: check upper wick (should be small)
 *
 * @param high           Candle high
 * @param low            Candle low
 * @param open           Candle open
 * @param close          Candle close
 * @param isBullish      true = bullish reversal, false = bearish
 * @param maxWickPercent Maximum allowed wick % (0.6 = 60%)
 * @return true if wick is within acceptable range
 */
bool ValidateC2ForAnticipation(double high, double low, double open, double close,
                                bool isBullish, double maxWickPercent,
                                bool &waitForC3)
{
   double bodyTop = MathMax(open, close);
   double bodyBottom = MathMin(open, close);
   double range = high - low;

   waitForC3 = false;

   if(range <= 0.0)
      return false;

   double wickSize;
   if(isBullish)
   {
      // For bullish reversal, check lower wick (should be small)
      wickSize = bodyBottom - low;
   }
   else
   {
      // For bearish reversal, check upper wick (should be small)
      wickSize = high - bodyTop;
   }

   if(wickSize < 0.0)
      wickSize = 0.0;

   double wickPercent = wickSize / range;
   if(wickPercent > maxWickPercent)
   {
      LogPrint("[C2_WICK_FILTER] Large wick detected=" + DoubleToString(wickPercent * 100.0, 1) + "%", LOG_LEVEL_INFO);
      LogPrint("[C2_WICK_FILTER] Waiting for C3 candle — C3 active", LOG_LEVEL_INFO);
      waitForC3 = true;
   }
   return (wickPercent <= maxWickPercent);
}

//+------------------------------------------------------------------+
//| GetCandleBodyPercent — Body size as % of range                   |
//+------------------------------------------------------------------+
double GetCandleBodyPercent(double high, double low, double open, double close)
{
   double range = high - low;
   if(range <= 0.0)
      return 0.0;
   return MathAbs(close - open) / range;
}

//+------------------------------------------------------------------+
//| IsC2WickValid — Wrapper using global config                      |
//+------------------------------------------------------------------+
bool IsC2WickValid(double high, double low, double open, double close, bool isBullish, bool &waitForC3)
{
   return ValidateC2ForAnticipation(high, low, open, close, isBullish,
                                     g_trueTTradesConfig.maxC2WickPercent, waitForC3);
}

#endif // OMAK_C2WICKFILTER_MQH
