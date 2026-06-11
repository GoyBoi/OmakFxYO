//+------------------------------------------------------------------+
//| SymbolIntelligence.mqh                                           |
//| OmakFxYO — Broker-Reality Symbol Intelligence Layer              |
//| Resolves symbol calc mode, pip/point mapping, margin feasibility,|
//| profit projection, and lot normalization from LIVE broker data.  |
//| No FX assumptions. No hardcoded digit/pip rules.                 |
//+------------------------------------------------------------------+
#ifndef OMAK_SYMBOL_INTELLIGENCE_MQH
#define OMAK_SYMBOL_INTELLIGENCE_MQH

#property strict

//+------------------------------------------------------------------+
//| Calc-mode aliases (SYMBOL_TRADE_CALC_MODE values)                |
//+------------------------------------------------------------------+
#define SY_CALC_FOREX           0
#define SY_CALC_CFD             1
#define SY_CALC_FUTURES         2
#define SY_CALC_CFDINDEX        3
#define SY_CALC_CFDLEVERAGE     4
#define SY_CALC_FOREX_NO_LEV    5
#define SY_CALC_TOTAL           6

//+------------------------------------------------------------------+
//| ENUM_SYM_CLASSIFICATION — Comprehensive symbol classification    |
//+------------------------------------------------------------------+
enum ENUM_SYM_CLASSIFICATION
{
   SYM_CLASS_FOREX_MAJOR,
   SYM_CLASS_FOREX_MINOR,
   SYM_CLASS_FOREX_EXOTIC,
   SYM_CLASS_METAL_SPOT,
   SYM_CLASS_CFD_INDEX,
   SYM_CLASS_CFD_ENERGY,
   SYM_CLASS_CFD_COMMODITY,
   SYM_CLASS_CFD_STOCK,
   SYM_CLASS_CRYPTO,
   SYM_CLASS_FUTURES,
   SYM_CLASS_SYNTHETIC,
   SYM_CLASS_UNKNOWN
};

//+------------------------------------------------------------------+
//| SSymbolProfile — Cached broker-reality symbol spec              |
//+------------------------------------------------------------------+
 struct SSymbolProfile
 {
    string   symbol;
    int      calcMode;
    ENUM_SYM_CLASSIFICATION classification;
    double   point;
    double   tickSize;
    double   tickValue;
    double   tickBid;
    double   tickAsk;
    double   contractSize;
    double   volumeMin;
    double   volumeMax;
    double   volumeStep;
    double   marginInitial;
    double   marginHedged;
    string   marginCurrency;
    string   profitCurrency;
    int      digits;
    long     stopsLevel;
    long     freezeLevel;
    long     fillingModes;
    double   pipSize;
    double   accountLeverage;
    bool     isValid;
    datetime lastUpdated;

   // --- Fields from SymbolProfileManager (classification helpers) ---
   bool     isSynthetic;
   bool     isCrypto;
   bool     isMetal;
   bool     isForex;
   int      spread;
   bool     sessionsExist;
   datetime nextSessionOpen;
   datetime nextSessionClose;

void Reset()
    {
       symbol = "";
       calcMode = -1;
       classification = SYM_CLASS_UNKNOWN;
       point = 0.0;
       tickSize = 0.0;
       tickValue = 0.0;
       tickBid = 0.0;
       tickAsk = 0.0;
       contractSize = 0.0;
       volumeMin = 0.0;
       volumeMax = 0.0;
       volumeStep = 0.0;
       marginInitial = 0.0;
       marginHedged = 0.0;
       marginCurrency = "";
       profitCurrency = "";
       digits = 0;
       stopsLevel = 0;
       freezeLevel = 0;
       fillingModes = 0;
       pipSize = 0.0;
       accountLeverage = 0.0;
       isValid = false;
       lastUpdated = 0;

       // --- Classification helper fields ---
       isSynthetic = false;
       isCrypto = false;
       isMetal = false;
       isForex = false;
       spread = 0;
       sessionsExist = false;
       nextSessionOpen = 0;
       nextSessionClose = 0;
    }

   SSymbolProfile() { Reset(); }
};

//+------------------------------------------------------------------+
//| Global profile cache (per-symbol, single slot for active sym)    |
//+------------------------------------------------------------------+
static SSymbolProfile g_symProfile;
static bool g_symProfileInitialized = false;

//+------------------------------------------------------------------+
//| SY_GetCalcMode — Read SYMBOL_TRADE_CALC_MODE from broker         |
//+------------------------------------------------------------------+
int SY_GetCalcMode(string symbol)
{
   long mode = SymbolInfoInteger(symbol, SYMBOL_TRADE_CALC_MODE);
   if(mode < 0 || mode > 6)
      return -1;
   return (int)mode;
}

//+------------------------------------------------------------------+
//| SY_ClassifyByCalcMode — Classify using calc mode (primary) and  |
//| symbol name (secondary).                                         |
//| Emits [SYM_CLASSIFIED] on every classification.                  |
//+------------------------------------------------------------------+
ENUM_SYM_CLASSIFICATION SY_ClassifyByCalcMode(string symbol)
{
   int mode = SY_GetCalcMode(symbol);
   string name = symbol;
   StringToUpper(name);

   ENUM_SYM_CLASSIFICATION result = SYM_CLASS_UNKNOWN;

   if(mode == SY_CALC_FOREX || mode == SY_CALC_FOREX_NO_LEV)
   {
      bool isMajor = (StringFind(name, "EUR") >= 0 || StringFind(name, "GBP") >= 0 ||
                      StringFind(name, "USD") >= 0 || StringFind(name, "JPY") >= 0 ||
                      StringFind(name, "CHF") >= 0 || StringFind(name, "AUD") >= 0 ||
                      StringFind(name, "CAD") >= 0 || StringFind(name, "NZD") >= 0);
      result = isMajor ? SYM_CLASS_FOREX_MAJOR : SYM_CLASS_FOREX_EXOTIC;
   }
   else if(mode == SY_CALC_CFD)
   {
      result = SYM_CLASS_CFD_ENERGY;
   }
   else if(mode == SY_CALC_FUTURES)
   {
      result = SYM_CLASS_FUTURES;
   }
   else if(mode == SY_CALC_CFDINDEX)
   {
      result = SYM_CLASS_CFD_INDEX;
   }
   else if(mode == SY_CALC_CFDLEVERAGE)
   {
      // Metals detection — catch GOLDmicro, XAUUSD, XAG*, SILVER* variants
      if(StringFind(name, "XAU") >= 0 || StringFind(name, "GOLD") >= 0 ||
         StringFind(name, "XAG") >= 0 || StringFind(name, "SILVER") >= 0)
         result = SYM_CLASS_METAL_SPOT;
      else if(StringFind(name, "BTC") >= 0 || StringFind(name, "ETH") >= 0 ||
              StringFind(name, "LTC") >= 0 || StringFind(name, "XRP") >= 0)
         result = SYM_CLASS_CRYPTO;
      else if(StringFind(name, "VIX") >= 0 || StringFind(name, "SYNTH") >= 0 ||
              StringFind(name, "VOLATILITY") >= 0 || StringFind(name, "BOOM") >= 0 ||
              StringFind(name, "CRASH") >= 0)
         result = SYM_CLASS_SYNTHETIC;
      else if(StringFind(name, "US500") >= 0 || StringFind(name, "SPX") >= 0 ||
              StringFind(name, "US30") >= 0 || StringFind(name, "DJI") >= 0 ||
              StringFind(name, "NAS100") >= 0 || StringFind(name, "NDX") >= 0)
         result = SYM_CLASS_CFD_INDEX;
      else
         result = SYM_CLASS_CFD_COMMODITY;
   }

   Print("[SYM_CLASSIFIED] symbol=" + symbol +
         " | calcMode=" + IntegerToString(mode) +
         " | classification=" + EnumToString(result));

   return result;
}

//+------------------------------------------------------------------+
//| SY_GetPipSize — Calc-mode-and-class-aware pip size.              |
//| Forex modes: pip = 10 * point (standard 5-digit).                |
//| CFD/Futures/Synthetic/Crypto/Index: pip = tickSize               |
//| (instrument's natural increment — no FX digit assumption).       |
//+------------------------------------------------------------------+
double SY_GetPipSize(string symbol)
{
   double pt = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(pt <= 0.0)
   {
      double fallbackPt = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(fallbackPt > 0.0)
         pt = fallbackPt;
      else
         pt = 0.00001;
   }

   int mode = SY_GetCalcMode(symbol);
   // Only pure forex modes use 10*point pip convention
   if(mode == SY_CALC_FOREX || mode == SY_CALC_FOREX_NO_LEV)
   {
      return pt * 10.0;
   }

   // All non-forex: CFD, Futures, CFD-Index, CFD-Leverage (metals, crypto, synthetics, indices)
   // use tickSize as pip — no digit/point assumption
   double tickSz = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSz > 0.0)
      return tickSz;

   return pt;
}

//+------------------------------------------------------------------+
//| SY_GetPipValue — Value of one pip in account currency per lot.  |
//+------------------------------------------------------------------+
double SY_GetPipValue(string symbol)
{
   double pipSize = SY_GetPipSize(symbol);
   double tickSz = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSz <= 0.0 || tickVal <= 0.0)
      return 0.0;

   double ticksPerPip = pipSize / tickSz;
   return ticksPerPip * tickVal;
}

//+------------------------------------------------------------------+
//| SY_BuildProfile — Query broker live data and populate profile.  |
//+------------------------------------------------------------------+
SSymbolProfile SY_BuildProfile(string symbol)
 {
    SSymbolProfile p;
    p.symbol = symbol;
    p.calcMode = SY_GetCalcMode(symbol);
    p.classification = SY_ClassifyByCalcMode(symbol);
    p.point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    p.tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    p.tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    
    MqlTick tick;
    if(SymbolInfoTick(symbol, tick))
    {
       p.tickBid = tick.bid;
       p.tickAsk = tick.ask;
    }
    
    p.contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    p.volumeMin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    p.volumeMax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    p.volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    p.marginInitial = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL);
    p.marginHedged = SymbolInfoDouble(symbol, SYMBOL_MARGIN_HEDGED);
    p.marginCurrency = SymbolInfoString(symbol, SYMBOL_CURRENCY_MARGIN);
    p.profitCurrency = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
    p.digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    p.stopsLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
    p.freezeLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
    p.fillingModes = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
    p.spread = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
    p.accountLeverage = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);
    p.pipSize = SY_GetPipSize(symbol);
    p.lastUpdated = TimeCurrent();

    p.isValid = (p.point > 0.0 && p.tickSize > 0.0 &&
                 p.volumeMin > 0.0 && p.volumeStep > 0.0 &&
                 p.digits > 0);

    return p;
 }

//+------------------------------------------------------------------+
//| SY_GetProfile — Return cached profile; refresh if stale or      |
//| different symbol.                                                |
//+------------------------------------------------------------------+
SSymbolProfile SY_GetProfile(string symbol)
{
   if(!g_symProfileInitialized || g_symProfile.symbol != symbol ||
      TimeCurrent() - g_symProfile.lastUpdated > 3600)
   {
      g_symProfile = SY_BuildProfile(symbol);
      g_symProfileInitialized = true;
   }
   return g_symProfile;
}

//+------------------------------------------------------------------+
//| SY_RefreshProfile — Force refresh the profile cache.            |
//+------------------------------------------------------------------+
SSymbolProfile SY_RefreshProfile(string symbol)
{
   g_symProfile = SY_BuildProfile(symbol);
   g_symProfileInitialized = true;
   return g_symProfile;
}

//+------------------------------------------------------------------+
//| SY_NormalizePrice — Normalize price to symbol's digit precision.|
//+------------------------------------------------------------------+
double SY_NormalizePrice(string symbol, double price)
{
   SSymbolProfile sp = SY_GetProfile(symbol);
   if(!sp.isValid || sp.digits <= 0)
      return NormalizeDouble(price, 5);
   return NormalizeDouble(price, sp.digits);
}

//+------------------------------------------------------------------+
//| SY_NormalizeLot — Normalize lot to broker's step with correct   |
//| decimal precision derived from step.                             |
//+------------------------------------------------------------------+
double SY_NormalizeLot(string symbol, double lot)
{
   SSymbolProfile sp = SY_GetProfile(symbol);
   if(!sp.isValid || sp.volumeStep <= 0.0)
      return NormalizeDouble(lot, 2);

   double step = sp.volumeStep;
   double normalised = MathFloor(lot / step) * step;

   int stepDigits = 0;
   double stepTemp = step;
   while(stepTemp < 1.0 && stepDigits < 8)
   {
      stepTemp *= 10.0;
      stepDigits++;
   }

   return NormalizeDouble(normalised, stepDigits);
}

//+------------------------------------------------------------------+
//| SY_ComputeMaxLoss — Compute maximum loss in account currency     |
//| VERBATIM REPAIR: Universal Risk Sincerity (§V)                   |
//| Uses tickValue/tickSize formula directly — no OrderCalcProfit.   |
//| Avoids 100x 'pips mode' inflation in the MT5 tester.            |
//+------------------------------------------------------------------+
double SY_ComputeMaxLoss(
   string symbol,
   int orderType,
   double volume,
   double entryPrice,
   double stopLoss
)
{
   if(volume <= 0.0 || entryPrice <= 0.0 || stopLoss <= 0.0)
      return 0.0;

   SSymbolProfile sp = SY_GetProfile(symbol);
   if(!sp.isValid)
      return 0.0;

   double slDist = MathAbs(entryPrice - stopLoss);
   double tickSz = sp.tickSize;
   double tickVal = sp.tickValue;

   if(tickSz <= 0.0 || tickVal <= 0.0 || slDist <= 0.0)
      return 0.0;

   double ticks = slDist / tickSz;
   double loss = ticks * tickVal * volume;

   if(loss <= 0.0)
      return 0.0;

   LogPrint("[LOT_CALCPROFIT] sym=" + symbol +
            " | volume=" + DoubleToString(volume, 4) +
            " | entry=" + DoubleToString(entryPrice, _Digits) +
            " | sl=" + DoubleToString(stopLoss, _Digits) +
            " | slDist=" + DoubleToString(slDist, _Digits) +
            " | tickSz=" + DoubleToString(tickSz, 8) +
            " | tickVal=" + DoubleToString(tickVal, 8) +
            " | ticks=" + DoubleToString(ticks, 2) +
            " | loss=" + DoubleToString(loss, 2) +
            " | source=formula", LOG_LEVEL_DEBUG);
   return loss;
}

//+------------------------------------------------------------------+
//| SY_ValidateSymbol — Full symbol health check.                   |
//| Returns true if symbol is tradeable. Logs markers:              |
//| [SYM_PROFILE_OK], [SYM_PROFILE_FAIL], [BROKER_MARGIN_OK], etc. |
//+------------------------------------------------------------------+
bool SY_ValidateSymbol(
   string symbol,
   int orderType,
   double volume,
   double entryPrice,
   double stopLoss,
   string &failReason
)
{
   failReason = "";

   SSymbolProfile sp = SY_GetProfile(symbol);
   if(!sp.isValid)
   {
      Print("[SYM_PROFILE_FAIL] symbol=" + symbol +
            " | reason=INCOMPLETE_PROFILE | point=" + DoubleToString(sp.point, 6) +
            " | tickSize=" + DoubleToString(sp.tickSize, 6) +
            " | volumeMin=" + DoubleToString(sp.volumeMin, 2) +
            " | digits=" + IntegerToString(sp.digits));
      failReason = "INCOMPLETE_SYMBOL_PROFILE";
      return false;
   }

   Print("[SYM_PROFILE_OK] symbol=" + symbol +
         " | calcMode=" + IntegerToString(sp.calcMode) +
         " | classification=" + EnumToString(sp.classification) +
         " | digits=" + IntegerToString(sp.digits) +
         " | point=" + DoubleToString(sp.point, 6) +
         " | tickSize=" + DoubleToString(sp.tickSize, 6) +
         " | tickValue=" + DoubleToString(sp.tickValue, 6) +
         " | contractSize=" + DoubleToString(sp.contractSize, 2) +
         " | pipSize=" + DoubleToString(sp.pipSize, 6) +
         " | volMin=" + DoubleToString(sp.volumeMin, 4) +
         " | volMax=" + DoubleToString(sp.volumeMax, 4) +
         " | volStep=" + DoubleToString(sp.volumeStep, 4) +
         " | marginCurrency=" + sp.marginCurrency +
         " | profitCurrency=" + sp.profitCurrency);

   if(sp.tickValue <= 0.0)
   {
      Print("[SYM_PROFILE_FAIL] symbol=" + symbol +
            " | reason=TICKVALUE_ZERO | tickValue=" + DoubleToString(sp.tickValue, 6));
      failReason = "TICKVALUE_ZERO";
      return false;
   }

   if(sp.volumeMin <= 0.0 || sp.volumeStep <= 0.0)
   {
      Print("[SYM_PROFILE_FAIL] symbol=" + symbol +
            " | reason=INVALID_VOLUME_CONSTRAINTS" +
            " | volMin=" + DoubleToString(sp.volumeMin, 4) +
            " | volStep=" + DoubleToString(sp.volumeStep, 4));
      failReason = "INVALID_VOLUME_CONSTRAINTS";
      return false;
   }

   if(volume > 0.0 && entryPrice > 0.0 && stopLoss > 0.0)
   {
      double marginReq = 0.0;
      if(OrderCalcMargin((ENUM_ORDER_TYPE)orderType, symbol, volume, entryPrice, marginReq))
      {
         double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
         if(freeMargin > 0.0 && marginReq > freeMargin)
         {
            Print("[BROKER_MARGIN_FAIL] symbol=" + symbol +
                  " | requiredMargin=" + DoubleToString(marginReq, 2) +
                  " | freeMargin=" + DoubleToString(freeMargin, 2) +
                  " | shortfall=" + DoubleToString(marginReq - freeMargin, 2));
            failReason = "INSUFFICIENT_MARGIN";
            return false;
         }
         Print("[BROKER_MARGIN_OK] symbol=" + symbol +
               " | requiredMargin=" + DoubleToString(marginReq, 2) +
               " | freeMargin=" + DoubleToString(freeMargin, 2));
      }
      else
      {
         Print("[BROKER_MARGIN_FAIL] symbol=" + symbol +
               " | reason=OrderCalcMargin_FAILED" +
               " | err=" + IntegerToString(GetLastError()));
         failReason = "MARGIN_CALC_FAILED";
         return false;
      }

      double tickSzVal = sp.tickSize;
      double tickValVal = sp.tickValue;
      double slDistVal = MathAbs(entryPrice - stopLoss);
      double brokerLoss = 0.0;
      if(tickSzVal > 0.0 && tickValVal > 0.0 && slDistVal > 0.0)
      {
         brokerLoss = -((slDistVal / tickSzVal) * tickValVal * volume);
         Print("[LOT_CALCPROFIT] validate | sym=" + symbol +
               " | volume=" + DoubleToString(volume, 4) +
               " | entry=" + DoubleToString(entryPrice, _Digits) +
               " | sl=" + DoubleToString(stopLoss, _Digits) +
               " | slDist=" + DoubleToString(slDistVal, _Digits) +
               " | rawProfit=" + DoubleToString(brokerLoss, 2) +
               " | source=formula");
      }
      else
      {
         Print("[LOT_CALC_FAIL] Manual calc failed | sym=" + symbol +
               " | tickSz=" + DoubleToString(tickSzVal, 8) +
               " | tickVal=" + DoubleToString(tickValVal, 8) +
               " | slDist=" + DoubleToString(slDistVal, _Digits));
         failReason = "PROFIT_CALC_FAILED";
         return false;
      }

      double riskPct = 0.0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > 0.0 && brokerLoss < 0.0)
         riskPct = MathAbs(brokerLoss) / equity * 100.0;
      Print("[SYMBOL_RISK_MODEL_OK] symbol=" + symbol +
            " | riskPct=" + DoubleToString(riskPct, 2) + "%" +
            " | equity=" + DoubleToString(equity, 2) +
            " | leverage=" + DoubleToString(sp.accountLeverage, 1));
   }

   return true;
}

//+------------------------------------------------------------------+
//| SY_Initialize — Initialize symbol intelligence layer.           |
//| Builds profile, runs tradeability check.                         |
//+------------------------------------------------------------------+
bool SY_Initialize(string symbol)
{
   g_symProfileInitialized = false;
   SSymbolProfile sp = SY_RefreshProfile(symbol);

   Print("[SYM_INTELLIGENCE_INIT] symbol=" + symbol +
         " | calcMode=" + IntegerToString(sp.calcMode) +
         " | class=" + EnumToString(sp.classification) +
         " | valid=" + (sp.isValid ? "true" : "false"));

   if(!sp.isValid)
   {
      Print("[SYM_INTELLIGENCE_INIT] FAILED — symbol profile incomplete for " + symbol);
      return false;
   }

   // Run full tradeability check
   string tradeabilityReason = "";
   if(!SY_ValidateTradeability(symbol, tradeabilityReason))
   {
      Print("[SYM_INTELLIGENCE_INIT] TRADEABILITY_FAILED | reason=" + tradeabilityReason +
            " | symbol=" + symbol);
   }

   return true;
}

//+------------------------------------------------------------------+
//| SY_PrintProfile — Diagnostic dump of cached profile.            |
//+------------------------------------------------------------------+
void SY_PrintProfile()
{
   if(!g_symProfileInitialized)
   {
      Print("[SYM_PROFILE] Not initialized");
      return;
   }

   SSymbolProfile sp = g_symProfile;
   Print("[SYM_PROFILE] symbol=" + sp.symbol +
         " | calcMode=" + IntegerToString(sp.calcMode) +
         " | class=" + EnumToString(sp.classification) +
         " | digits=" + IntegerToString(sp.digits) +
         " | point=" + DoubleToString(sp.point, 8) +
         " | tickSize=" + DoubleToString(sp.tickSize, 8) +
         " | tickValue=" + DoubleToString(sp.tickValue, 8) +
         " | contractSize=" + DoubleToString(sp.contractSize, 2) +
         " | pipSize=" + DoubleToString(sp.pipSize, 8) +
         " | volMin=" + DoubleToString(sp.volumeMin, 4) +
         " | volMax=" + DoubleToString(sp.volumeMax, 4) +
         " | volStep=" + DoubleToString(sp.volumeStep, 4) +
         " | margin=" + sp.marginCurrency +
         " | profit=" + sp.profitCurrency +
         " | leverage=" + DoubleToString(sp.accountLeverage, 1) +
         " | valid=" + (sp.isValid ? "true" : "false"));
}

//+------------------------------------------------------------------+
//| SY_ValidateTradeability — Full broker-reality tradeability       |
//| check. Does NOT require an active profile for pre-init checks.   |
//| Emits [SYMBOL_TRADEABILITY_OK] or [SYMBOL_TRADEABILITY_FAIL]     |
//| with exact owning subsystem and rejection reason.                |
//+------------------------------------------------------------------+
bool SY_ValidateTradeability(
   string symbol,
   string &failReason     // out: exact reason if tradeability fails
)
{
   failReason = "";

   // 1. Terminal permission
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      failReason = "TERMINAL_TRADE_DISABLED";
      Print("[SYMBOL_TRADEABILITY_FAIL] symbol=" + symbol +
            " | reason=" + failReason + " | owner=Terminal");
      return false;
   }

   // 2. EA permission
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      failReason = "EA_TRADE_DISABLED";
      Print("[SYMBOL_TRADEABILITY_FAIL] symbol=" + symbol +
            " | reason=" + failReason + " | owner=MetaEditor");
      return false;
   }

   // 3. Account permission
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      failReason = "ACCOUNT_TRADE_DISABLED";
      Print("[SYMBOL_TRADEABILITY_FAIL] symbol=" + symbol +
            " | reason=" + failReason + " | owner=Broker");
      return false;
   }

   // 4. Symbol trade mode
   ENUM_SYMBOL_TRADE_MODE tmode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   if(tmode != SYMBOL_TRADE_MODE_FULL)
   {
      failReason = (tmode == SYMBOL_TRADE_MODE_DISABLED) ? "SYMBOL_TRADE_DISABLED" : "SYMBOL_TRADE_READONLY";
      Print("[SYMBOL_TRADEABILITY_FAIL] symbol=" + symbol +
            " | reason=" + failReason + " | tradeMode=" + IntegerToString(tmode) +
            " | owner=SymbolProperties");
      return false;
   }

   // 5. Filling mode available
   long fillingModes = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if(fillingModes == 0)
   {
      failReason = "NO_FILLING_MODE";
      Print("[SYMBOL_TRADEABILITY_FAIL] symbol=" + symbol +
            " | reason=" + failReason + " | owner=SymbolProperties");
      return false;
   }

   // 6. Ticker freshness (within 5 minutes)
   datetime lastTick = (datetime)SymbolInfoInteger(symbol, SYMBOL_TIME);
   if(TimeCurrent() - lastTick > 300)
   {
      failReason = "STALE_TICK_DATA";
      Print("[SYMBOL_TRADEABILITY_FAIL] symbol=" + symbol +
            " | reason=" + failReason + " | lastTickSecsAgo=" +
            IntegerToString(TimeCurrent() - lastTick) +
            " | owner=MarketWatch");
      return false;
   }

   // 7. Bid/Ask prices valid
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0 || ask <= bid)
   {
      failReason = "INVALID_BID_ASK";
      Print("[SYMBOL_TRADEABILITY_FAIL] symbol=" + symbol +
            " | reason=" + failReason + " | bid=" + DoubleToString(bid, 6) +
            " | ask=" + DoubleToString(ask, 6) + " | owner=MarketWatch");
      return false;
   }

   // 8. Contract size valid (only if we have a profile)
   SSymbolProfile sp = SY_GetProfile(symbol);
   if(sp.isValid)
   {
      if(sp.contractSize <= 0.0)
      {
         failReason = "INVALID_CONTRACT_SIZE";
         Print("[SYMBOL_TRADEABILITY_FAIL] symbol=" + symbol +
               " | reason=" + failReason + " | contractSize=" +
               DoubleToString(sp.contractSize, 4) + " | owner=SymbolIntelligence");
         return false;
      }

      if(sp.tickValue <= 0.0)
      {
         failReason = "TICKVALUE_ZERO";
         Print("[SYMBOL_TRADEABILITY_FAIL] symbol=" + symbol +
               " | reason=" + failReason + " | calcMode=" +
               IntegerToString(sp.calcMode) + " | owner=SymbolIntelligence");
         return false;
      }

      if(sp.tickSize <= 0.0)
      {
         failReason = "TICKSIZE_ZERO";
         Print("[SYMBOL_TRADEABILITY_FAIL] symbol=" + symbol +
               " | reason=" + failReason + " | owner=SymbolIntelligence");
         return false;
      }

      // 9. Spread sanity (class-aware)
      int spread = sp.spread;
      int maxSpread = 3000;
      if(sp.classification == SYM_CLASS_CRYPTO)
         maxSpread = 30000;
      else if(sp.classification == SYM_CLASS_SYNTHETIC)
         maxSpread = 50000;
      else if(sp.classification == SYM_CLASS_CFD_INDEX || sp.calcMode == SY_CALC_CFDINDEX)
         maxSpread = 10000;
      else if(sp.classification == SYM_CLASS_METAL_SPOT)
         maxSpread = 8000;
      else if(sp.calcMode == SY_CALC_CFDLEVERAGE)
         maxSpread = 8000;

      if(spread > maxSpread)
      {
         failReason = "SPREAD_TOO_WIDE";
         Print("[SYMBOL_TRADEABILITY_FAIL] symbol=" + symbol +
               " | reason=" + failReason + " | spread=" + IntegerToString(spread) +
               " | max=" + IntegerToString(maxSpread) +
               " | class=" + EnumToString(sp.classification) +
               " | owner=SpreadGate");
         return false;
      }
   }

   Print("[SYMBOL_TRADEABILITY_OK] symbol=" + symbol +
         " | calcMode=" + (sp.isValid ? IntegerToString(sp.calcMode) : "N/A") +
         " | bid=" + DoubleToString(bid, 6) +
         " | ask=" + DoubleToString(ask, 6) +
         " | spread=" + (sp.isValid ? IntegerToString(sp.spread) : "N/A") +
         " | fillingModes=" + IntegerToString(fillingModes) +
         " | owner=SymbolIntelligence");

   return true;
}

#endif // OMAK_SYMBOL_INTELLIGENCE_MQH
