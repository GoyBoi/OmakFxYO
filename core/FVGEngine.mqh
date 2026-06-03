//+------------------------------------------------------------------+
//|                                              FVGEngine.mqh |
//|                        OmakFxYO — FVG Location Intelligence |
//+------------------------------------------------------------------+
#ifndef OMAK_FVGENGINE_MQH
#define OMAK_FVGENGINE_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Fair Value Gap Detection Engine — Location Context for Scoring"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>

//+------------------------------------------------------------------+
//| FVGZone — Fair Value Gap Structure                               |
//+------------------------------------------------------------------+
struct FVGZone
{
   double high;
   double low;
   datetime time;
   bool bullish;
   bool valid;

   void FVGZone()
   {
      Reset();
   }

   void Reset()
   {
      high = 0.0;
      low = 0.0;
      time = 0;
      bullish = false;
      valid = false;
   }
};

//+------------------------------------------------------------------+
//| FVG DETECTION ENGINE                                             |
//+------------------------------------------------------------------+

FVGZone DetectFVG(
   const string symbol = "",
   ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT,
   int shift = 1
)
{
   FVGZone fvg;
   fvg.Reset();

   if(shift < 1 || shift > 5)
   {
      return fvg;
   }

   string sym = (symbol == "") ? _Symbol : symbol;
   ENUM_TIMEFRAMES tf = (timeframe == PERIOD_CURRENT) ? PERIOD_CURRENT : timeframe;

   double high1 = iHigh(sym, tf, shift);
   double low1  = iLow(sym, tf, shift);

   double high3 = iHigh(sym, tf, shift + 2);
   double low3  = iLow(sym, tf, shift + 2);

   if(high1 <= 0 || low1 <= 0 || high3 <= 0 || low3 <= 0)
   {
      return fvg;
   }

   if(low1 > high3)
   {
      fvg.low  = high3;
      fvg.high = low1;
      fvg.bullish = true;
      fvg.valid = true;
      fvg.time = iTime(sym, tf, shift);

      return fvg;
   }

   if(high1 < low3)
   {
      fvg.high = low3;
      fvg.low  = high1;
      fvg.bullish = false;
      fvg.valid = true;
      fvg.time = iTime(sym, tf, shift);

      return fvg;
   }

   return fvg;
}

FVGZone DetectRecentFVG(
   const string symbol = "",
   ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT
)
{
   FVGZone fvg;
   fvg.Reset();

   for(int shift = 1; shift <= 5; shift++)
   {
      FVGZone candidate = DetectFVG(symbol, timeframe, shift);

      if(candidate.valid)
      {
         return candidate;
      }
   }

   return fvg;
}

#endif // OMAK_FVGENGINE_MQH
