//+------------------------------------------------------------------+
//|                                        SpreadFilter.mqh           |
//|                        OmakFxYO — Hybrid Spread Validation     |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_SPREAD_FILTER_MQH
#define OMAK_SPREAD_FILTER_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Hybrid Spread Filter — Triple Layer Validation"

#include <OmakFxYO/core/CoreTypes.mqh>
#include <OmakFxYO/core/LogGovernor.mqh>


//+------------------------------------------------------------------+
//| SYMBOL CLASS — Instrument Classification                           |
//+------------------------------------------------------------------+
enum ENUM_SYMBOL_CLASS
{
   CLASS_FOREX,
   CLASS_METAL,
   CLASS_INDEX,
   CLASS_CRYPTO,
   CLASS_SYNTHETIC
};

//+------------------------------------------------------------------+
//| HYBRID CONFIG — Per-Class Multipliers                               |
//+------------------------------------------------------------------+
struct SHybridSpreadConfig
{
   ENUM_SYMBOL_CLASS symbolClass;
   double avgSpreadMultiplier;
   double atrThreshold;
   double absoluteMaxSpread;
};

SHybridSpreadConfig g_spreadConfig[];

void InitializeSpreadConfig()
{
   int size = 5;
   ArrayResize(g_spreadConfig, size);

   g_spreadConfig[0].symbolClass = CLASS_FOREX;
   g_spreadConfig[0].avgSpreadMultiplier = 2.5;
   g_spreadConfig[0].atrThreshold = 0.15;
   g_spreadConfig[0].absoluteMaxSpread = 30.0;

   g_spreadConfig[1].symbolClass = CLASS_METAL;
   g_spreadConfig[1].avgSpreadMultiplier = 5.0;
   g_spreadConfig[1].atrThreshold = 0.25;
   g_spreadConfig[1].absoluteMaxSpread = 80.0;

   g_spreadConfig[2].symbolClass = CLASS_INDEX;
   g_spreadConfig[2].avgSpreadMultiplier = 6.0;
   g_spreadConfig[2].atrThreshold = 0.30;
   g_spreadConfig[2].absoluteMaxSpread = 60.0;

   g_spreadConfig[3].symbolClass = CLASS_CRYPTO;
   g_spreadConfig[3].avgSpreadMultiplier = 8.0;
   g_spreadConfig[3].atrThreshold = 0.40;
   g_spreadConfig[3].absoluteMaxSpread = 200.0;

   g_spreadConfig[4].symbolClass = CLASS_SYNTHETIC;
   g_spreadConfig[4].avgSpreadMultiplier = 6.0;
   g_spreadConfig[4].atrThreshold = 0.35;
   g_spreadConfig[4].absoluteMaxSpread = 50.0;
}

//+------------------------------------------------------------------+
//| GetConfig — Retrieve config by symbol class                       |
//+------------------------------------------------------------------+
SHybridSpreadConfig GetSpreadConfig(ENUM_SYMBOL_CLASS cls)
{
   SHybridSpreadConfig defaultConfig;
   ZeroMemory(defaultConfig);
   defaultConfig.symbolClass = CLASS_FOREX;
   defaultConfig.avgSpreadMultiplier = 2.5;
   defaultConfig.atrThreshold = 0.15;
   defaultConfig.absoluteMaxSpread = 30.0;

   for(int i = 0; i < ArraySize(g_spreadConfig); i++)
   {
      if(g_spreadConfig[i].symbolClass == cls)
         return g_spreadConfig[i];
   }

   return defaultConfig;
}

//+------------------------------------------------------------------+
//| SPREADCONTEXT — Hybrid Spread Validation Result                     |
//+------------------------------------------------------------------+
struct SSpreadContext
{
   double currentSpread;
   double avgSpread;
   double allowedSpread;
   double spreadRatio;
   ENUM_SYMBOL_CLASS symbolClass;
   bool layer1_pass;
   bool layer2_pass;
   bool layer3_pass;
   bool pass;

   void Reset()
   {
      currentSpread = 0.0;
      avgSpread = 0.0;
      allowedSpread = 0.0;
      spreadRatio = 0.0;
      symbolClass = CLASS_FOREX;
      layer1_pass = false;
      layer2_pass = false;
      layer3_pass = false;
      pass = false;
   }
};

//+------------------------------------------------------------------+
//| DetectSymbolClass — Classify instrument type                     |
//| Primary: SYMBOL_TRADE_CALC_MODE from broker.                     |
//| Secondary: symbol name pattern matching (backward compat).       |
//+------------------------------------------------------------------+
ENUM_SYMBOL_CLASS DetectSymbolClass(const string symbol)
{
   int calcMode = SY_GetCalcMode(symbol);

   // Calc-mode-based classification (authoritative)
   if(calcMode == SY_CALC_FOREX || calcMode == SY_CALC_FOREX_NO_LEV)
      return CLASS_FOREX;

   if(calcMode == SY_CALC_CFDINDEX)
      return CLASS_INDEX;

   if(calcMode == SY_CALC_CFD)
   {
      // CFD can be energy, commodity, or stock — use name matching for sub-class
      string s = symbol;
      StringToUpper(s);
      if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0 ||
         StringFind(s, "XAG") >= 0 || StringFind(s, "SILVER") >= 0)
         return CLASS_METAL;
      return CLASS_SYNTHETIC;
   }

   if(calcMode == SY_CALC_FUTURES)
      return CLASS_SYNTHETIC;

   if(calcMode == SY_CALC_CFDLEVERAGE)
   {
      string s = symbol;
      StringToUpper(s);

      if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0 ||
         StringFind(s, "XAG") >= 0 || StringFind(s, "SILVER") >= 0)
         return CLASS_METAL;

      if(StringFind(s, "BTC") >= 0 || StringFind(s, "ETH") >= 0 ||
         StringFind(s, "LTC") >= 0 || StringFind(s, "XRP") >= 0)
         return CLASS_CRYPTO;

      if(StringFind(s, "US500") >= 0 || StringFind(s, "US30") >= 0 ||
         StringFind(s, "US100") >= 0 || StringFind(s, "NAS100") >= 0 ||
         StringFind(s, "JAP225") >= 0 || StringFind(s, "GER40") >= 0 ||
         StringFind(s, "UK100") >= 0 || StringFind(s, "FRA40") >= 0)
         return CLASS_INDEX;

      if(StringFind(s, "VIX") >= 0 || StringFind(s, "SYNTH") >= 0 ||
         StringFind(s, "RANDOM") >= 0 || StringFind(s, "VOLATILITY") >= 0 ||
         StringFind(s, "BOOM") >= 0 || StringFind(s, "CRASH") >= 0)
         return CLASS_SYNTHETIC;

      return CLASS_SYNTHETIC;
   }

   // Unknown calc mode — fallback to string matching
   string s = symbol;
   StringToUpper(s);

   if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0)
      return CLASS_METAL;
   if(StringFind(s, "XAG") >= 0 || StringFind(s, "SILVER") >= 0)
      return CLASS_METAL;

   if(StringFind(s, "BTC") >= 0 || StringFind(s, "ETH") >= 0 ||
      StringFind(s, "LTC") >= 0 || StringFind(s, "XRP") >= 0)
      return CLASS_CRYPTO;

   if(StringFind(s, "US500") >= 0 || StringFind(s, "US30") >= 0 ||
      StringFind(s, "US100") >= 0 || StringFind(s, "NAS100") >= 0 ||
      StringFind(s, "JAP225") >= 0 || StringFind(s, "GER40") >= 0 ||
      StringFind(s, "UK100") >= 0 || StringFind(s, "FRA40") >= 0)
      return CLASS_INDEX;

   if(StringFind(s, "SYNTH") >= 0 || StringFind(s, "RANDOM") >= 0 ||
      StringFind(s, "INDEX") >= 0 || StringFind(s, "VIX") >= 0)
      return CLASS_SYNTHETIC;

   return CLASS_FOREX;
}

//+------------------------------------------------------------------+
//| ComputeAverageSpread — Rolling mean (lightweight)                  |
//+------------------------------------------------------------------+
double ComputeAverageSpread(const string symbol, ENUM_TIMEFRAMES tf, int samples = 50)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 10.0 * point;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int count = MathMin(samples, 100);
   if(CopyRates(symbol, tf, 0, count, rates) != count)
      return 10.0 * point;

   double sum = 0.0;
   int valid = 0;
   for(int i = 0; i < count; i++)
   {
      if(rates[i].spread > 0)
      {
         sum += rates[i].spread;
         valid++;
      }
   }

   if(valid > 0)
      return (sum / valid) * point;

   return 10.0 * point;
}

//+------------------------------------------------------------------+
//| ValidateSpread — Universal Dynamic Spread Validation            |
//+------------------------------------------------------------------+
/**
 * ValidateSpread — Universal Dynamic Spread Filter
 *
 * Uses dynamic baseline learned from historical spread data instead of
 * hardcoded class-based thresholds. Adapts to any asset class automatically.
 *
 * @param symbol        Symbol to validate (e.g., "XAUUSD", "BTCUSD")
 * @param tf            Timeframe for ATR calculation
 * @param spikeMultiplier  Max multiple of avg spread to allow (default 2.5)
 * @return SSpreadContext with validation results
 */
SSpreadContext ValidateSpread(const string symbol, ENUM_TIMEFRAMES tf, double spikeMultiplier = 2.5)
{
   SSpreadContext ctx;
   ctx.Reset();

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   ctx.currentSpread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD) * point;

   ctx.symbolClass = DetectSymbolClass(symbol);
   SHybridSpreadConfig config = GetSpreadConfig(ctx.symbolClass);

   ctx.avgSpread = ComputeAverageSpread(symbol, tf, 50);
   ctx.allowedSpread = ctx.avgSpread * config.avgSpreadMultiplier;

   double dynamicBaseline = ctx.avgSpread * spikeMultiplier;
   double minBaseline = point * 10.0;
   double layer1Max = MathMax(minBaseline, dynamicBaseline);
   ctx.layer1_pass = (ctx.currentSpread <= layer1Max);

ctx.layer2_pass = (ctx.currentSpread <= ctx.allowedSpread);

    // ATR removed — layer3 always passes
    ctx.spreadRatio = 0.0;
    ctx.layer3_pass = true;

    ctx.pass = ctx.layer1_pass && ctx.layer2_pass;

   if(!ctx.pass)
   {
      string classStr = "FOREX";
      if(ctx.symbolClass == CLASS_METAL) classStr = "METAL";
      else if(ctx.symbolClass == CLASS_INDEX) classStr = "INDEX";
      else if(ctx.symbolClass == CLASS_CRYPTO) classStr = "CRYPTO";
      else if(ctx.symbolClass == CLASS_SYNTHETIC) classStr = "SYNTHETIC";

      LogTrace(StringFormat("[SPREAD_FAIL] symbol=%s class=%s spread=%.2f avg=%.2f ratio=%.2f L1=%d L2=%d L3=%d",
         symbol, classStr, ctx.currentSpread, ctx.avgSpread, ctx.spreadRatio,
         ctx.layer1_pass ? 1 : 0, ctx.layer2_pass ? 1 : 0, ctx.layer3_pass ? 1 : 0),
         LOG_LEVEL_WARN, LOG_CHANNEL_SPREAD);
   }

   return ctx;
}

//+------------------------------------------------------------------+
//| ValidateSpreadSimple — Legacy fallback (single threshold)           |
//+------------------------------------------------------------------+
bool ValidateSpreadSimple(const string symbol, double spreadFactor)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   double currentSpread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD) * point;
   double typicalSpread = point * 10.0;
   double maxAllowedSpread = typicalSpread * spreadFactor;

   return (currentSpread <= maxAllowedSpread);
}

//+------------------------------------------------------------------+
//| SpreadFilter_Initialize — Initialize module                       |
//+------------------------------------------------------------------+
bool SpreadFilter_Initialize()
{
   InitializeSpreadConfig();
   return true;
}

//+------------------------------------------------------------------+
#endif // OMAK_SPREAD_FILTER_MQH