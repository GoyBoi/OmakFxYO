//+------------------------------------------------------------------+
 //|                                          RiskManager.mqh |
 //|                                    OmakFxYO — Risk Manager |
 //+------------------------------------------------------------------+
 #property strict

 #ifndef OMAK_RISKMANAGER_MQH
 #define OMAK_RISKMANAGER_MQH

 #include <OmakFxYO/core/ModeResolver.mqh>
 #include <OmakFxYO/core/CoreTypes.mqh>
 #include <OmakFxYO/core/LogGovernor.mqh>
#include <OmakFxYO/core/RiskGate.mqh>
#include <OmakFxYO/core/RiskCore.mqh>

extern double g_symbolRiskFloor;
   extern double g_minSLPoints;
   extern ENUM_EXECUTION_BRANCH g_activeBranch;

  //+------------------------------------------------------------------+
 //| GetCurrencyConversionRate — Get conversion rate for currency pair |
 //+------------------------------------------------------------------+
 double GetCurrencyConversionRate(const string symbol)
 {
    string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
    string profitCurrency = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
    
    if(accountCurrency == profitCurrency)
       return 1.0;
    
    string directPair = accountCurrency + profitCurrency;
    if(SymbolInfoInteger(directPair, SYMBOL_SELECT) != 0)
    {
       double ask = SymbolInfoDouble(directPair, SYMBOL_ASK);
       if(ask > 0.0)
          return ask;
    }
    
    string inversePair = profitCurrency + accountCurrency;
    if(SymbolInfoInteger(inversePair, SYMBOL_SELECT) != 0)
    {
       double bid = SymbolInfoDouble(inversePair, SYMBOL_BID);
       if(bid > 0.0)
          return 1.0 / bid;
    }
    
    string symbolBase = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
    if(symbolBase != "" && symbolBase != profitCurrency)
    {
       string conversionPair = accountCurrency + symbolBase;
       if(SymbolInfoInteger(conversionPair, SYMBOL_SELECT) != 0)
       {
          double conversionRate = SymbolInfoDouble(conversionPair, SYMBOL_ASK);
          if(conversionRate > 0.0)
             return conversionRate;
       }
    }
    
    return -1.0;
 }

 //+------------------------------------------------------------------+
 //| ProjectedSLProfit — Manual risk calculation in account currency   |
 //| VERBATIM REPAIR: Universal Risk Sincerity (§V)                   |
 //| Bypasses 100x 'pips mode' inflation by calculating risk via      |
 //| (slDist / tickSize) * tickValue * lots — no OrderCalcProfit.     |
 //+------------------------------------------------------------------+
 double ProjectedSLProfit(
     const string symbol,
     double lots,
     double entryPrice,
     double slPrice,
     bool isBuy
 )
 {
     if(lots <= 0.0 || entryPrice <= 0.0 || slPrice <= 0.0)
         return 0.0;

     double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
     double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
     double slDist    = MathAbs(entryPrice - slPrice);

     if(tickValue <= 0.0 || tickSize <= 0.0 || slDist <= 0.0)
     {
         LogPrint("[PROFIT_PROJ_FAIL] Invalid params for manual calc | sym=" + symbol +
                  " | lots=" + DoubleToString(lots, 2) +
                  " | tickValue=" + DoubleToString(tickValue, 8) +
                  " | tickSize=" + DoubleToString(tickSize, 8) +
                  " | slDist=" + DoubleToString(slDist, _Digits), LOG_LEVEL_WARN);
         return 0.0;
     }

     double projectedLoss = (slDist / tickSize) * tickValue * lots;

     LogPrint("[LOT_CALCPROFIT] sym=" + symbol +
              " | lots=" + DoubleToString(lots, 2) +
              " | entry=" + DoubleToString(entryPrice, _Digits) +
              " | sl=" + DoubleToString(slPrice, _Digits) +
              " | slDist=" + DoubleToString(slDist, _Digits) +
              " | tickValue=" + DoubleToString(tickValue, 8) +
              " | tickSize=" + DoubleToString(tickSize, 8) +
              " | rawProfit=" + DoubleToString(projectedLoss, 2) +
              " | source=formula", LOG_LEVEL_DEBUG);

     return projectedLoss;
 }

//+------------------------------------------------------------------+
//| RM_ComputeEntryTFSL — Compute Manipulation Leg SL on Entry TF   |
//|                                                                  |
//| VERBATIM REPAIR: Manipulation Leg SL (§V)                       |
//| Finds the local extreme of the leg that swept liquidity on the   |
//| Entry TF (M5/M15) in the window immediately preceding CISD.      |
//| Returns the stop loss price.                                     |
//+------------------------------------------------------------------+
double RM_ComputeEntryTFSL(const string symbol, ENUM_EXECUTION_BRANCH branch, bool isBuy, double entryPrice)
{
   ENUM_TIMEFRAMES entryTF = (branch == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;
   int manipBars = 10;
   double manipExtreme = (isBuy)
      ? iLow(symbol, entryTF, iLowest(symbol, entryTF, MODE_LOW, manipBars, 1))
      : iHigh(symbol, entryTF, iHighest(symbol, entryTF, MODE_HIGH, manipBars, 1));

   if(manipExtreme <= 0.0)
      return 0.0;

   double buffer = InpMinSLPoints * SymbolInfoDouble(symbol, SYMBOL_POINT);
   double sl = (isBuy) ? manipExtreme - buffer : manipExtreme + buffer;

   LogPrint("[SL_MANIP_LEG] " + (isBuy ? "BUY" : "SELL") +
            " | entryTF=" + EnumToString(entryTF) +
            " | manipExtreme=" + DoubleToString(manipExtreme, _Digits) +
            " | entry=" + DoubleToString(entryPrice, _Digits) +
            " | dist=" + DoubleToString(MathAbs(entryPrice - manipExtreme), _Digits) +
            " | sl=" + DoubleToString(sl, _Digits), LOG_LEVEL_INFO);
   return sl;
}

// VERBATIM REPAIR: Manipulation-Leg SL & Persistence Sync (§2)
double GetManipulationLegExtreme(const string symbol, ENUM_TIMEFRAMES tf, bool isLong) {
    int lookback = 10;
    int extremeBar = isLong ? iLowest(symbol, tf, MODE_LOW, lookback, 1)
                            : iHighest(symbol, tf, MODE_HIGH, lookback, 1);
    return isLong ? iLow(symbol, tf, extremeBar) : iHigh(symbol, tf, extremeBar);
}

// VERBATIM REPAIR: Synchronous Sequence (§I) — Internal Risk SL tracking
double g_internalRiskSL = 0.0;

void SyncInternalSL(double sl)
{
    g_internalRiskSL = sl;
    LogPrint("[SL_SYNC] Internal Risk SL synced to " + DoubleToString(sl, _Digits), LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
   //| Detect Symbol Minimum Risk Capability — ITF-anchored, Enum-safe  |
   //| Structural SL via ITF swings (H1/H4), OrderCalcProfit.          |
   //+------------------------------------------------------------------+
   double DetectSymbolRiskFloor(const string symbol, ENUM_EXECUTION_BRANCH branch, bool isBuy = true)
   {
        // VERBATIM REPAIR: LTF Manipulation Leg SL (§V)
        // Law: Invalidation must sit on the leg that swept liquidity on the Entry TF.
        ENUM_TIMEFRAMES entryTF = (branch == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;
        int manipulationBars = 10; // Scan window for the leg preceding CISD
        double manipulationExtreme = (isBuy) ? iLow(symbol, entryTF, iLowest(symbol, entryTF, MODE_LOW, manipulationBars, 1)) 
                                             : iHigh(symbol, entryTF, iHighest(symbol, entryTF, MODE_HIGH, manipulationBars, 1));

        double currentPrice = (isBuy) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
        double structuralSLDist = MathAbs(currentPrice - manipulationExtreme);

        // Idempotence Guard: Ensure SL is at least broker minimum
        if (structuralSLDist <= 0) structuralSLDist = InpMinSLPoints * SymbolInfoDouble(symbol, SYMBOL_POINT);

        // VERBATIM REPAIR: Manual Risk Calculation (§V)
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        double minLot    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

        double minLotRisk = (structuralSLDist / tickSize) * tickValue * minLot;
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double riskPercent = (equity > 0) ? (minLotRisk / equity * 100.0) : 100.0;

       // VERBATIM REPAIR: The Affordability Bridge (§XIII)
        // Determines structural permission at a wider band (g_riskPercentAffordMin, e.g. 20%) while
        // sizing execution risk at a narrow band (g_riskPercentTrade, e.g. 1%).
        bool isTradeable = (riskPercent <= g_riskPercentAffordMin);
        g_symbolUntradeable = !isTradeable;

        string rm_status = StringFormat("[RISK_FLOOR] %s | Risk=%.2f%% > Bridge=%.2f%% | Status=%s",
                 symbol, riskPercent, g_riskPercentAffordMin, g_symbolUntradeable ? "UNTRADEABLE" : "TRADEABLE");
        LogPrint(rm_status, g_symbolUntradeable ? LOG_LEVEL_WARN : LOG_LEVEL_INFO);
       return minLotRisk;
   }

  //+------------------------------------------------------------------+
  //| CalculateLotSize — Contract-Aware Universal Lot Calculator        |
  //| Universal: Standard, Micro, Cent, Nano, Synthetic, Crypto,        |
  //| Index CFDs, VIX75, GOLDmicro — no instrument hardcoding.          |
  //| Uses OrderCalcProfit() as ground truth for exposure validation.   |
  //+------------------------------------------------------------------+
 double CalculateLotSize(
     double accountEquity,
     double riskPercent,
     double slPoints,
     double tickValue,
     double tickSize,
     const string symbol,
     double entryPrice,
     double slPrice,
     bool isBuy,
     ENUM_RG_FAIL &outFailCode
 )
{
        outFailCode = RG_FAIL_NONE;

        if(slPoints > 0 && g_minSLPoints > 0 && slPoints < g_minSLPoints)
        {
            LogPrint("[RISK_FLOOR_BLOCK] reason=SL_TOO_TIGHT | slPoints=" + DoubleToString(slPoints, 2) +
                     " | minSLPoints=" + DoubleToString(g_minSLPoints, 2) +
                     " | symbol=" + symbol, LOG_LEVEL_WARN);
            LogPrint("[LOT_CALC_FAIL] slPoints=" + DoubleToString(slPoints, 2) +
                      " < minSLPoints=" + DoubleToString(g_minSLPoints, 2) +
                      " | symbol=" + symbol,
                      LOG_LEVEL_WARN);
            outFailCode = RG_FAIL_SL_TOO_TIGHT;
            return 0.0;
        }

  // Broker-reality profile — single source for all symbol metadata
      SSymbolProfile spLot = SY_GetProfile(symbol);
      if(!spLot.isValid)
      {
          LogPrint("[RISK_FLOOR_BLOCK] reason=INVALID_SYMBOL_PROFILE | symbol=" + symbol +
                   " | calcMode=" + IntegerToString(spLot.calcMode), LOG_LEVEL_ERROR);
           LogPrint("[LOT_CALC_FAIL] Invalid symbol profile for " + symbol, LOG_LEVEL_ERROR);
          outFailCode = RG_FAIL_VOLUME_CONTRACT;
          return 0.0;
      }

   LogPrint("[LOT_DIAG] equity=" + DoubleToString(accountEquity, 2) +
                  " | risk%=" + DoubleToString(riskPercent, 4) +
                  " | slPoints=" + DoubleToString(slPoints, 2) +
                  " | tickValue=" + DoubleToString(tickValue, 8) +
                  " | tickSize=" + DoubleToString(tickSize, 8) +
                  " | symbol=" + symbol,
                  LOG_LEVEL_DEBUG);

       LogPrint("[LOT_DIAG] symbol=" + symbol +
                " | class=" + EnumToString(spLot.classification) +
                " | calcMode=" + IntegerToString(spLot.calcMode) +
                " | contractSize=" + DoubleToString(spLot.contractSize, 4) +
                " | tickValue=" + DoubleToString(spLot.tickValue, 8) +
                " | tickSize=" + DoubleToString(spLot.tickSize, 8) +
                " | volumeMin=" + DoubleToString(spLot.volumeMin, 4) +
                " | volumeMax=" + DoubleToString(spLot.volumeMax, 4) +
                " | volumeStep=" + DoubleToString(spLot.volumeStep, 4) +
                " | digits=" + IntegerToString(spLot.digits),
                LOG_LEVEL_INFO);

      double contractSize = spLot.contractSize;
      if(contractSize <= 0.0)
      {
           contractSize = 1.0;
           LogPrint("[LOT_DIAG] contractSize=0.0 → defaulting to 1.0 | sym=" + symbol, LOG_LEVEL_WARN);
      }

      if(tickValue <= 0.0)
      {
          tickValue = spLot.tickValue;
          if(tickValue <= 0.0)
          {
              LogPrint("[RISK_FLOOR_BLOCK] reason=TICKVALUE_ZERO | symbol=" + symbol +
                       " | calcMode=" + IntegerToString(spLot.calcMode), LOG_LEVEL_ERROR);
               LogPrint("[LOT_CALC_FAIL] Fresh tickValue=0.0 | sym=" + symbol +
                        " | calcMode=" + IntegerToString(spLot.calcMode), LOG_LEVEL_ERROR);
              outFailCode = RG_FAIL_TICKVALUE_ZERO;
              return 0.0;
          }
      }

      if(tickSize <= 0.0)
      {
          tickSize = spLot.tickSize;
          if(tickSize <= 0.0)
          {
              LogPrint("[RISK_FLOOR_BLOCK] reason=TICKSIZE_ZERO | symbol=" + symbol +
                       " | calcMode=" + IntegerToString(spLot.calcMode), LOG_LEVEL_ERROR);
               LogPrint("[LOT_CALC_FAIL] Fresh tickSize=0.0 | sym=" + symbol +
                        " | calcMode=" + IntegerToString(spLot.calcMode), LOG_LEVEL_ERROR);
              outFailCode = RG_FAIL_TICKSIZE_ZERO;
              return 0.0;
          }
      }

      double minLot = spLot.volumeMin;
      double maxLot = spLot.volumeMax;
      double lotStep = spLot.volumeStep;

      if(minLot <= 0.0 || lotStep <= 0.0)
      {
          LogPrint("[RISK_FLOOR_BLOCK] reason=VOLUME_CONTRACT_INVALID | minLot=" + DoubleToString(minLot, 4) +
                   " | lotStep=" + DoubleToString(lotStep, 4) +
                   " | symbol=" + symbol, LOG_LEVEL_ERROR);
           LogPrint("[LOT_CALC_FAIL] Volume contract invalid | minLot=" + DoubleToString(minLot, 4) +
                    " | lotStep=" + DoubleToString(lotStep, 4) +
                    " | symbol=" + symbol, LOG_LEVEL_ERROR);
          outFailCode = RG_FAIL_VOLUME_CONTRACT;
          return 0.0;
      }

      if(accountEquity <= 0.0)
      {
          LogPrint("[RISK_FLOOR_BLOCK] reason=EQUITY_ZERO | equity=" + DoubleToString(accountEquity, 2) +
                   " | symbol=" + symbol, LOG_LEVEL_ERROR);
           LogPrint("[LOT_CALC_FAIL] Equity=" + DoubleToString(accountEquity, 2) + " <= 0", LOG_LEVEL_ERROR);
          outFailCode = RG_FAIL_EQUITY_ZERO;
          return 0.0;
      }

if(slPoints <= 0.0)
       {
            LogPrint("[RISK_FLOOR_BLOCK] reason=SL_POINTS_ZERO | slPoints=" + DoubleToString(slPoints, 2) +
                     " | symbol=" + symbol, LOG_LEVEL_ERROR);
            LogPrint("[LOT_CALC_FAIL] slPoints=" + DoubleToString(slPoints, 2) + " <= 0", LOG_LEVEL_ERROR);
            outFailCode = RG_FAIL_SL_POINTS_ZERO;
            return 0.0;
        }

        // Pre-check: IsLotTradeable — is the broker minimum affordable at this stop distance?
        if(!IsLotTradeable(slPoints, tickValue, minLot,
                           accountEquity, riskPercent, symbol,
                           entryPrice, slPrice, isBuy))
        {
            LogPrint("[RISK_FLOOR_BLOCK] reason=ISLOT_NOT_TRADEABLE | minLot=" + DoubleToString(minLot, 4) +
                     " | slPoints=" + DoubleToString(slPoints, 2) +
                     " | equity=" + DoubleToString(accountEquity, 2) +
                     " | riskPct=" + DoubleToString(riskPercent, 4) +
                     " | symbol=" + symbol, LOG_LEVEL_WARN);
            LogPrint("[RISK_MINLOT_REJECT] CalculateLotSize IsLotTradeable failed | " +
                     "minLot=" + DoubleToString(minLot, 4) +
                     " | slPoints=" + DoubleToString(slPoints, 2) +
                     " | equity=" + DoubleToString(accountEquity, 2) +
                     " | riskPct=" + DoubleToString(riskPercent, 4) +
                     " | symbol=" + symbol, LOG_LEVEL_WARN);
            outFailCode = RG_FAIL_LOT_ZERO;
            return 0.0;
        }

         // Part A: Contract-size-aware lot calculation as primary method
        double pointValue = 0.0;
        double contractSizeRaw = spLot.contractSize;
        if(contractSizeRaw <= 0.0) contractSizeRaw = 1.0;
        if(tickValue > 0.0 && tickSize > 0.0)
        {
            pointValue = (tickValue / tickSize) * contractSizeRaw;
        }

       double formulaLot = 0.0;
       if(pointValue > 0.0 && slPoints > 0.0)
       {
           formulaLot = (accountEquity * (riskPercent / 100.0)) / (slPoints * pointValue);
           LogPrint("[LOT_CALCPROFIT] formula path | contractSize=" + DoubleToString(contractSizeRaw, 2) +
                     " | pointValue=" + DoubleToString(pointValue, 8) +
                     " | formulaLot=" + DoubleToString(formulaLot, 6) +
                     " | source=formula",
                     LOG_LEVEL_DEBUG);
       }

      double riskAmount = accountEquity * (riskPercent / 100.0);
     if(riskAmount <= 0.0)
     {
          LogPrint("[RISK_FLOOR_BLOCK] reason=RISK_AMOUNT_ZERO | riskAmount=" + DoubleToString(riskAmount, 4) +
                   " | equity=" + DoubleToString(accountEquity, 2) +
                   " | riskPct=" + DoubleToString(riskPercent, 4) +
                   " | symbol=" + symbol, LOG_LEVEL_ERROR);
            LogPrint("[LOT_CALC_FAIL] riskAmount=" + DoubleToString(riskAmount, 4) + " <= 0", LOG_LEVEL_ERROR);
          outFailCode = RG_FAIL_RISK_AMOUNT_ZERO;
          return 0.0;
      }

        maxLot = spLot.volumeMax;

      if(entryPrice <= 0.0 || slPrice <= 0.0)
      {
          LogPrint("[RISK_FLOOR_BLOCK] reason=ENTRY_OR_SL_INVALID | entryPrice=" + DoubleToString(entryPrice, _Digits) +
                   " | slPrice=" + DoubleToString(slPrice, _Digits) +
                   " | symbol=" + symbol, LOG_LEVEL_ERROR);
           LogPrint("[LOT_CALC_FAIL] entryPrice=" + DoubleToString(entryPrice, _Digits) +
                     " or slPrice=" + DoubleToString(slPrice, _Digits) + " invalid", LOG_LEVEL_ERROR);
          outFailCode = RG_FAIL_PROFIT_CALC;
          return 0.0;
      }

      // VERBATIM REPAIR: Universal Risk Sincerity (§V)
      // Manual formula bypasses 100x 'pips mode' inflation from OrderCalcProfit.
      double slDist = MathAbs(entryPrice - slPrice);
      double lossPerLot = (slDist / tickSize) * tickValue;

      if(lossPerLot <= 0.0)
      {
          LogPrint("[RISK_FLOOR_BLOCK] reason=LOSS_PER_LOT_ZERO | lossPerLot=" + DoubleToString(lossPerLot, 5) +
                   " | slDist=" + DoubleToString(slDist, _Digits) +
                   " | tickSize=" + DoubleToString(tickSize, 8) +
                   " | tickValue=" + DoubleToString(tickValue, 8) +
                   " | symbol=" + symbol, LOG_LEVEL_ERROR);
          outFailCode = RG_FAIL_PROFIT_CALC;
          return 0.0;
      }

      double rawLot = riskAmount / lossPerLot;

      LogPrint("[LOT_DIAG] manual formula | slDist=" + DoubleToString(slDist, _Digits) +
               " | tickSize=" + DoubleToString(tickSize, 8) +
               " | tickValue=" + DoubleToString(tickValue, 8) +
               " | lossPerLot=" + DoubleToString(lossPerLot, 4) +
               " | rawLot=" + DoubleToString(rawLot, 6) +
               " | riskAmount=" + DoubleToString(riskAmount, 2),
               LOG_LEVEL_DEBUG);

        if(rawLot <= 0.0)
        {
            LogPrint("[RISK_FLOOR_BLOCK] reason=RAW_LOT_ZERO | rawLot=" + DoubleToString(rawLot, 6) +
                     " | slPoints=" + DoubleToString(slPoints, 2) +
                     " | riskAmount=" + DoubleToString(riskAmount, 2) +
                     " | lossPerLot=" + DoubleToString(lossPerLot, 4) +
                     " | symbol=" + symbol, LOG_LEVEL_ERROR);
            LogPrint("[LOT_CALC_FAIL] rawLot=" + DoubleToString(rawLot, 6) +
                     " <= 0 | symbol=" + symbol, LOG_LEVEL_ERROR);
            outFailCode = RG_FAIL_LOT_ZERO;
            return 0.0;
        }

        if(rawLot < minLot)
        {
            LogPrint("[RISK_FLOOR_BLOCK] reason=RAW_LOT_BELOW_MIN | rawLot=" + DoubleToString(rawLot, 6) +
                     " | minLot=" + DoubleToString(minLot, 4) +
                     " | symbol=" + symbol, LOG_LEVEL_WARN);
            LogPrint("[RISK_MINLOT_REJECT] CalculateLotSize | rawLot=" + DoubleToString(rawLot, 6) +
                     " < minLot=" + DoubleToString(minLot, 4) +
                     " | symbol=" + symbol + " — rejecting (no upward force to minLot)",
                     LOG_LEVEL_WARN);
            outFailCode = RG_FAIL_LOT_ZERO;
            return 0.0;
        }

        // VERBATIM REPAIR: Manual verification via tickValue/tickSize formula
        double verifyLoss = (slDist / tickSize) * tickValue * rawLot;
        double overexposureRatio = verifyLoss / riskAmount;
        if(overexposureRatio > 1.5)
        {
            LogPrint("[RISK_FLOOR_BLOCK] reason=OVEREXPOSURE | verifyLoss=" + DoubleToString(verifyLoss, 2) +
                     " | intendedRisk=" + DoubleToString(riskAmount, 2) +
                     " | ratio=" + DoubleToString(overexposureRatio, 2) +
                     " | symbol=" + symbol, LOG_LEVEL_ERROR);
            outFailCode = RG_FAIL_LOT_ZERO;
            return 0.0;
        }

double finalLot = rawLot;

       // P3 Fix: Normalize to lotStep BEFORE clamping (round to nearest)
       finalLot = MathFloor(finalLot / lotStep + 0.5) * lotStep;

        // Cap at maxLot only — no upward minLot forcing
        finalLot = MathMin(maxLot, finalLot);

        // Explicit minLot rejection — never resize upward
        if(finalLot < minLot)
        {
            LogPrint("[RISK_FLOOR_BLOCK] reason=FINAL_LOT_BELOW_MIN | finalLot=" + DoubleToString(finalLot, 4) +
                     " | minLot=" + DoubleToString(minLot, 4) +
                     " | symbol=" + symbol, LOG_LEVEL_WARN);
            // REGRESSION_GUARD_V52.5_RISK_MGR_MINLOT
            outFailCode = RG_FAIL_LOT_ZERO;
            return 0.0;
        }

        // P3 Fix: Non-standard contract size logging (all broker types)
       if(spLot.contractSize > 0 && spLot.contractSize != 100000.0)
       {
           LogPrint("[LOT_DIAG] Non-standard contract | sym=" + symbol +
                    " | class=" + EnumToString(spLot.classification) +
                    " | calcMode=" + IntegerToString(spLot.calcMode) +
                    " | contract=" + DoubleToString(spLot.contractSize, 2) +
                    " | raw=" + DoubleToString(rawLot, 5) +
                    " | final=" + DoubleToString(finalLot, 5), LOG_LEVEL_DEBUG);
       }

        // P3 Fix: Zero lot protection — return failure (no upward force to minLot)
        if(finalLot <= 0)
        {
            LogPrint("[RISK_FLOOR_BLOCK] reason=LOT_ZERO_AFTER_NORM | finalLot=" + DoubleToString(finalLot, 4) +
                     " | minLot=" + DoubleToString(minLot, 4) +
                     " | lotStep=" + DoubleToString(lotStep, 4) +
                     " | symbol=" + symbol, LOG_LEVEL_WARN);
            LogPrint("[LOT_DIAG] Zero lot after norm | symbol=" + symbol, LOG_LEVEL_WARN);
            outFailCode = RG_FAIL_LOT_ZERO;
            return 0.0;
        }

        // P3 Fix: Risk cap - never exceed 5% of account per single trade — uses manual formula
       double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
       if(entryPrice > 0 && slPrice > 0 && MathAbs(entryPrice - slPrice) > 0 && spLot.contractSize > 0)
       {
           double slDistCap = MathAbs(entryPrice - slPrice);
           double lossPerLotCheck = (slDistCap / tickSize) * tickValue;
           if(lossPerLotCheck > 0)
           {
               double maxRiskLot = (accountBalance * 0.05) / lossPerLotCheck;
               if(finalLot > maxRiskLot && maxRiskLot > minLot)
               {
LogPrint("[LOT_CAP] Risk cap applied (manual formula) | old=" + DoubleToString(finalLot, 5) +
                              " | capped=" + DoubleToString(maxRiskLot, 5), LOG_LEVEL_DEBUG);
                       finalLot = MathFloor(maxRiskLot / lotStep + 0.5) * lotStep;
                   }
               }
            }

        LogPrint("[LOT_OK] finalLot=" + DoubleToString(finalLot, 4) +
                   " | min=" + DoubleToString(minLot, 4) +
                   " | max=" + DoubleToString(maxLot, 4) +
                   " | step=" + DoubleToString(lotStep, 4),
                   LOG_LEVEL_INFO);

      if(finalLot <= 0.0)
      {
           LogPrint("[RISK_FLOOR_BLOCK] reason=FINAL_LOT_ZERO | finalLot=" + DoubleToString(finalLot, 6) +
                    " | minLot=" + DoubleToString(minLot, 4) +
                    " | symbol=" + symbol, LOG_LEVEL_ERROR);
           LogPrint("[LOT_CALC_FAIL] finalLot=" + DoubleToString(finalLot, 6) +
                     " <= 0 | symbol=" + symbol, LOG_LEVEL_ERROR);
           outFailCode = RG_FAIL_LOT_ZERO;
           return 0.0;
      }

       LogPrint("[LOT_OK] finalLot=" + DoubleToString(finalLot, 4) +
                 " | symbol=" + symbol, LOG_LEVEL_INFO);

         int lotPrecision = 0;
         double stepVal = lotStep;
         while(MathAbs(stepVal * MathPow(10, lotPrecision) - MathRound(stepVal * MathPow(10, lotPrecision))) > 1e-10 && lotPrecision < 8)
             lotPrecision++;
         return NormalizeDouble(finalLot, lotPrecision);
   }

//+------------------------------------------------------------------+
//| CalculateRiskLot — Manual lot sizing via tickValue/tickSize      |
//| VERBATIM REPAIR: Universal Risk Sincerity (§V)                   |
//| Replaces OrderCalcProfit (100x inflation in pips mode) with      |
//| manual formula: risk / ((slDist/tickSize) * tickValue).          |
//+------------------------------------------------------------------+
double CalculateRiskLot(SLockedSignal &signal, double riskPct = 1.0)
{
    ulong guid = signal.m_guid;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity <= 0.0)
    {
        LogPrint("[LOT_CALC_FAIL] Equity <= 0 | GUID=" + IntegerToString(guid), LOG_LEVEL_ERROR);
        return 0.0;
    }

    double activeRiskPct = ResolveActiveRiskPct(signal.executionMode, InpRiskPercent);
    double riskAmount = equity * (activeRiskPct / 100.0);
    if(riskAmount <= 0.0)
    {
        LogPrint("[LOT_CALC_FAIL] riskAmount <= 0 | equity=" + DoubleToString(equity, 2) +
                 " | riskPct=" + DoubleToString(activeRiskPct, 4) +
                 " | GUID=" + IntegerToString(guid), LOG_LEVEL_ERROR);
        return 0.0;
    }

    double entryPrice = signal.entry_price;
    double slPrice = signal.stop_loss;
    double slDist = MathAbs(entryPrice - slPrice);
    if(slDist <= 0.0)
    {
        LogPrint("[LOT_CALC_FAIL] Zero SL distance | GUID=" + IntegerToString(guid) +
                 " | entry=" + DoubleToString(entryPrice, _Digits) +
                 " | sl=" + DoubleToString(slPrice, _Digits), LOG_LEVEL_ERROR);
        return 0.0;
    }

    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tickValue <= 0.0 || tickSize <= 0.0)
    {
        LogPrint("[LOT_CALC_FAIL] Invalid tickValue/tickSize | GUID=" + IntegerToString(guid) +
                 " | tickValue=" + DoubleToString(tickValue, 8) +
                 " | tickSize=" + DoubleToString(tickSize, 8), LOG_LEVEL_ERROR);
        return 0.0;
    }

    double lossPerLot = (slDist / tickSize) * tickValue;
    if(lossPerLot <= 0.0)
    {
        LogPrint("[LOT_CALC_FAIL] lossPerLot <= 0 | GUID=" + IntegerToString(guid) +
                 " | lossPerLot=" + DoubleToString(lossPerLot, 5), LOG_LEVEL_ERROR);
        return 0.0;
    }

    double desiredLot = riskAmount / lossPerLot;

    // === OrderCalcProfit API validation ===
    double apiProfit = 0.0;
    ENUM_ORDER_TYPE orderType = (signal.direction == DIRECTION_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

    if(OrderCalcProfit(orderType, _Symbol, desiredLot, entryPrice, slPrice, apiProfit))
    {
        double apiRisk = MathAbs(apiProfit);
        double mismatchRatio = apiRisk / riskAmount;

        LogPrint("[LOT_API_CHECK] GUID=" + IntegerToString(guid) +
                 " | formulaRisk=" + DoubleToString(lossPerLot * desiredLot, 2) +
                 " | apiRisk=" + DoubleToString(apiRisk, 2) +
                 " | ratio=" + DoubleToString(mismatchRatio, 4) +
                 " | desiredLot=" + DoubleToString(desiredLot, 4), LOG_LEVEL_INFO);

        if(mismatchRatio > 1.10 || mismatchRatio < 0.90)
        {
            desiredLot = riskAmount / (apiRisk / desiredLot);

            LogPrint("[LOT_RECALC_API] GUID=" + IntegerToString(guid) +
                     " | Original=" + DoubleToString(riskAmount / lossPerLot, 4) +
                     " | API-Corrected=" + DoubleToString(desiredLot, 4) +
                     " | apiRisk=" + DoubleToString(apiRisk, 2), LOG_LEVEL_INFO);
        }
    }
    else
    {
        LogPrint("[LOT_API_FAIL] OrderCalcProfit failed | GUID=" + IntegerToString(guid) +
                 " | Error=" + IntegerToString(GetLastError()), LOG_LEVEL_WARN);
    }

    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    if(step > 0.0)
        desiredLot = MathFloor(desiredLot / step) * step;
    desiredLot = MathMax(desiredLot, minLot);

    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    if(maxLot > 0.0 && desiredLot > maxLot)
    {
        LogPrint("[LOT_CAP] Capping to maxLot | desired=" + DoubleToString(desiredLot, 4) +
                 " | maxLot=" + DoubleToString(maxLot, 4) +
                 " | GUID=" + IntegerToString(guid), LOG_LEVEL_DEBUG);
        desiredLot = maxLot;
    }

    // VERBATIM REPAIR: Manual verification
    double verifyLoss = (slDist / tickSize) * tickValue * desiredLot;
    if(verifyLoss > riskAmount * 1.2)
    {
        LogPrint("[RISK_FLOOR_BLOCK] GUID=" + IntegerToString(guid) +
                 " | projectedRisk=" + DoubleToString(verifyLoss, 2) +
                 " | exceedsBudget=" + DoubleToString(riskAmount, 2) +
                 " | ratio=" + DoubleToString(verifyLoss / riskAmount, 2) +
                 " | desiredLot=" + DoubleToString(desiredLot, 4) +
                 " | source=formula", LOG_LEVEL_WARN);
        return 0.0;
    }
    LogPrint("[LOT_VERIFY] GUID=" + IntegerToString(guid) +
             " | desiredLot=" + DoubleToString(desiredLot, 4) +
             " | verifyLoss=" + DoubleToString(verifyLoss, 2) +
             " | riskAmount=" + DoubleToString(riskAmount, 2) +
             " | ratio=" + DoubleToString(verifyLoss / riskAmount, 2) +
             " | source=formula", LOG_LEVEL_INFO);

    LogPrint("[LOT_OK] GUID=" + IntegerToString(guid) +
             " | lot=" + DoubleToString(desiredLot, 4) +
             " | equity=" + DoubleToString(equity, 2) +
             " | riskPct=" + DoubleToString(riskPct, 4) +
             " | riskAmount=" + DoubleToString(riskAmount, 2) +
             " | minLot=" + DoubleToString(minLot, 4) +
             " | source=formula", LOG_LEVEL_INFO);

    return desiredLot;
}

//+------------------------------------------------------------------+
//| NormalizeLot — Round lot to broker volume step                  |
//+------------------------------------------------------------------+
double NormalizeLot(double rawLot)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step > 0.0)
      rawLot = MathFloor(rawLot / step) * step;

   rawLot = MathMax(rawLot, minLot);
   rawLot = MathMin(rawLot, maxLot);

   int precision = 0;
   double temp = step;
   while(MathAbs(temp * MathPow(10, precision) - MathRound(temp * MathPow(10, precision))) > 1e-10 && precision < 8)
      precision++;

   return NormalizeDouble(rawLot, precision);
}

//+------------------------------------------------------------------+
//| CalculateAgnosticLot — Universal structural lot sizing (manual)  |
//| VERBATIM REPAIR: Universal Risk Sincerity (§V)                   |
//| Uses tickValue/tickSize formula instead of OrderCalcProfit to    |
//| avoid 100x inflation in tester pips mode.                        |
//+------------------------------------------------------------------+
double CalculateAgnosticLot(double entry, double sl, double riskPct)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double slDist    = MathAbs(entry - sl);

   if(tickValue <= 0.0 || tickSize <= 0.0 || slDist <= 0.0)
   {
      LogPrint("[LOT_CALC_FAIL] Agnostic: invalid params | tickValue=" +
               DoubleToString(tickValue, 8) + " | tickSize=" + DoubleToString(tickSize, 8) +
               " | slDist=" + DoubleToString(slDist, _Digits), LOG_LEVEL_ERROR);
      return 0.0;
   }

   double lossPerMinLot = (slDist / tickSize) * tickValue * minLot;

   double maxLoss = AccountInfoDouble(ACCOUNT_EQUITY) * (riskPct / 100.0);
   double calculatedLot = (maxLoss / lossPerMinLot) * minLot;

   LogPrint("[LOT_CALCPROFIT] Agnostic | sym=" + _Symbol +
            " | entry=" + DoubleToString(entry, _Digits) +
            " | sl=" + DoubleToString(sl, _Digits) +
            " | minLot=" + DoubleToString(minLot, 4) +
            " | lossPerMinLot=" + DoubleToString(lossPerMinLot, 2) +
            " | maxLoss=" + DoubleToString(maxLoss, 2) +
            " | calculatedLot=" + DoubleToString(calculatedLot, 6) +
            " | source=formula", LOG_LEVEL_INFO);

   return NormalizeLot(calculatedLot);
}

#endif // OMAK_RISKMANAGER_MQH