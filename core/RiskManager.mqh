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

extern double g_symbolRiskFloor;
   extern double g_minSLPoints;

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
 //| ProjectedSLProfit — OrderCalcProfit() validation of SL risk      |
 //| Returns projected loss in account currency. Returns 0.0 on        |
 //| failure. Uses ORDER_TYPE_BUY/SELL based on direction.            |
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

     ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

     double profit = 0.0;
     if(!OrderCalcProfit(orderType, symbol, lots, entryPrice, slPrice, profit))
     {
         LogPrint("[PROFIT_PROJ_FAIL] OrderCalcProfit failed | sym=" + symbol +
                  " | lots=" + DoubleToString(lots, 2) +
                  " | entry=" + DoubleToString(entryPrice, _Digits) +
                  " | sl=" + DoubleToString(slPrice, _Digits), LOG_LEVEL_WARN);
         return 0.0;
     }

      LogPrint("[LOT_CALCPROFIT] sym=" + symbol +
               " | orderType=" + IntegerToString(orderType) +
               " | lots=" + DoubleToString(lots, 2) +
               " | entry=" + DoubleToString(entryPrice, _Digits) +
               " | sl=" + DoubleToString(slPrice, _Digits) +
               " | rawProfit=" + DoubleToString(profit, 2) +
               " | source=OrderCalcProfit", LOG_LEVEL_DEBUG);
      double projectedLoss = MathAbs(profit);

     return projectedLoss;
 }

//+------------------------------------------------------------------+
  //| Detect Symbol Minimum Risk Capability                             |
   //| Returns: minimum $ risk for 1 minLot at the given test SL distance |
   //| testSLPoints should reflect the max expected structural SL for    |
   //| the symbol (e.g., ~250pt not minimum 50pt). Call once in OnInit().|
   //+------------------------------------------------------------------+
    double DetectSymbolRiskFloor(const string symbol, double testSLPoints = 250.0)
   {
       SSymbolProfile spFloor = SY_GetProfile(symbol);
       if(!spFloor.isValid)
       {
           LogPrint("[RISK_FLOOR] Invalid profile for " + symbol, LOG_LEVEL_ERROR);
           return -1.0;
       }

double minLot = spFloor.volumeMin;
        double maxLot = spFloor.volumeMax;
        if(minLot <= 0.0 || maxLot <= 0.0)
        {
            LogPrint("[RISK_FLOOR] Invalid lot limits | minLot=" + DoubleToString(minLot, 4) +
                     " | maxLot=" + DoubleToString(maxLot, 4) + " | sym=" + symbol, LOG_LEVEL_ERROR);
            return -1.0;
        }

        double testPrice = (spFloor.tickBid > 0.0) ? spFloor.tickBid : ((spFloor.tickAsk > 0.0) ? spFloor.tickAsk : SymbolInfoDouble(symbol, SYMBOL_BID));
        if(testPrice <= 0.0) testPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
        if(testPrice <= 0.0)
        {
            LogPrint("[RISK_FLOOR] Invalid price for " + symbol, LOG_LEVEL_ERROR);
            return -1.0;
        }

       // Use minLot for the OrderCalcProfit test (not 1.0 lot — which may exceed maxLot for some instruments)
       double testSL = testPrice - (testSLPoints * spFloor.point);
       double profit = 0.0;

       if(!OrderCalcProfit(ORDER_TYPE_BUY, symbol, minLot, testPrice, testSL, profit))
       {
           LogPrint("[RISK_FLOOR] OrderCalcProfit failed for minLot=" + DoubleToString(minLot, 4) +
                    " test | sym=" + symbol, LOG_LEVEL_ERROR);
           return -1.0;
       }

        double lossForMinLotAtTestSL = MathAbs(profit);

        LogPrint("[RISK_FLOOR] symbol=" + symbol +
                 " | calcMode=" + IntegerToString(spFloor.calcMode) +
                 " | class=" + EnumToString(spFloor.classification) +
                 " | minLot=" + DoubleToString(minLot, 4) +
                 " | testSL=" + DoubleToString(testSLPoints, 0) + "pt" +
                 " | minLotRiskAtTestSL=$" + DoubleToString(lossForMinLotAtTestSL, 2),
                 LOG_LEVEL_WARN);

        return lossForMinLotAtTestSL;
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

      double profit = 0;
      ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

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

      if(!OrderCalcProfit(orderType, symbol, maxLot, entryPrice, slPrice, profit))
      {
          LogPrint("[RISK_FLOOR_BLOCK] reason=ORDER_CALC_PROFIT_FAILED | symbol=" + symbol +
                   " | maxLot=" + DoubleToString(maxLot, 2) +
                   " | entry=" + DoubleToString(entryPrice, _Digits) +
                   " | sl=" + DoubleToString(slPrice, _Digits), LOG_LEVEL_ERROR);
           LogPrint("[LOT_CALC_FAIL] OrderCalcProfit failed | sym=" + symbol, LOG_LEVEL_ERROR);
          outFailCode = RG_FAIL_PROFIT_CALC;
          return 0.0;
      }

      if(profit == 0)
      {
          LogPrint("[RISK_FLOOR_BLOCK] reason=ORDER_CALC_PROFIT_ZERO | symbol=" + symbol +
                   " | maxLot=" + DoubleToString(maxLot, 2) +
                   " | entry=" + DoubleToString(entryPrice, _Digits) +
                   " | sl=" + DoubleToString(slPrice, _Digits), LOG_LEVEL_ERROR);
           LogPrint("[LOT_CALC_FAIL] OrderCalcProfit returned zero | sym=" + symbol, LOG_LEVEL_ERROR);
          outFailCode = RG_FAIL_PROFIT_ZERO;
          return 0.0;
      }

       LogPrint("[LOT_CALCPROFIT] maxLot | sym=" + symbol +
                " | orderType=" + IntegerToString(orderType) +
                " | volume=" + DoubleToString(maxLot, 2) +
                " | entry=" + DoubleToString(entryPrice, _Digits) +
                " | sl=" + DoubleToString(slPrice, _Digits) +
                " | rawProfit=" + DoubleToString(profit, 2) +
                " | source=OrderCalcProfit", LOG_LEVEL_DEBUG);
       double lossPerMaxLot = MathAbs(profit);
       
        if(lossPerMaxLot <= 0.0)
       {
           LogPrint("[RISK_FLOOR_BLOCK] reason=LOSS_PER_MAXLOT_ZERO | lossPerMaxLot=" + DoubleToString(lossPerMaxLot, 2) +
                    " | maxLot=" + DoubleToString(maxLot, 2) +
                    " | entry=" + DoubleToString(entryPrice, _Digits) +
                    " | sl=" + DoubleToString(slPrice, _Digits) +
                    " | symbol=" + symbol, LOG_LEVEL_ERROR);
           LogPrint(StringFormat("[LOT_CALC_FAIL] OrderCalcProfit returned %.2f for maxLot %.2f — profit calculation failed. entry=%.5f, sl=%.5f, orderType=%s",
                    lossPerMaxLot, maxLot, entryPrice, slPrice,
                    EnumToString(orderType)), LOG_LEVEL_ERROR);
          outFailCode = RG_FAIL_PROFIT_CALC;
          return 0.0;
      }
      
      double lossPerLot = lossPerMaxLot / maxLot;
      
       if(lossPerLot <= 0.0)
       {
           LogPrint("[RISK_FLOOR_BLOCK] reason=LOSS_PER_LOT_ZERO | lossPerLot=" + DoubleToString(lossPerLot, 5) +
                    " | maxLot=" + DoubleToString(maxLot, 2) +
                    " | lossPerMaxLot=" + DoubleToString(lossPerMaxLot, 2) +
                    " | symbol=" + symbol, LOG_LEVEL_ERROR);
           LogPrint(StringFormat("[LOT_CALC_FAIL] lossPerLot %.5f <= 0 (division error) — returning 0.0. maxLot=%.2f, lossPerMaxLot=%.2f, entry=%.5f, sl=%.5f",
                    lossPerLot, maxLot, lossPerMaxLot, entryPrice, slPrice), LOG_LEVEL_ERROR);
          outFailCode = RG_FAIL_PROFIT_CALC;
          return 0.0;
      }
      
      double rawLot = riskAmount / lossPerLot;

      LogPrint("[LOT_DIAG] OrderCalcProfit method | maxLot=" + DoubleToString(maxLot, 2) +
               " | lossPerMaxLot=" + DoubleToString(lossPerMaxLot, 2) +
               " | lossPerLot=" + DoubleToString(lossPerLot, 4) +
               " | rawLot=" + DoubleToString(rawLot, 6) +
               " | riskAmount=" + DoubleToString(riskAmount, 2),
               LOG_LEVEL_DEBUG);  // P8 Fix: Reduced to DEBUG

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

       double verifyProfit = 0;
       if(OrderCalcProfit(orderType, symbol, rawLot, entryPrice, slPrice, verifyProfit))
       {
           LogPrint("[LOT_CALCPROFIT] verify | sym=" + symbol +
                    " | orderType=" + IntegerToString(orderType) +
                    " | volume=" + DoubleToString(rawLot, 6) +
                    " | entry=" + DoubleToString(entryPrice, _Digits) +
                    " | sl=" + DoubleToString(slPrice, _Digits) +
                    " | rawProfit=" + DoubleToString(verifyProfit, 2) +
                    " | source=OrderCalcProfit", LOG_LEVEL_DEBUG);
           double verifyLoss = MathAbs(verifyProfit);
           double overexposureRatio = verifyLoss / riskAmount;
           if(overexposureRatio > 1.5)
           {
               LogPrint("[RISK_FLOOR_BLOCK] reason=OVEREXPOSURE | verifyLoss=" + DoubleToString(verifyLoss, 2) +
                        " | intendedRisk=" + DoubleToString(riskAmount, 2) +
                        " | ratio=" + DoubleToString(overexposureRatio, 2) +
                        " | symbol=" + symbol, LOG_LEVEL_ERROR);
                LogPrint("[LOT_CALC_FAIL] OVEREXPOSURE | verifyLoss=" + DoubleToString(verifyLoss, 2) +
                         " | intendedRisk=" + DoubleToString(riskAmount, 2) +
                         " | ratio=" + DoubleToString(overexposureRatio, 2) +
                         " | symbol=" + symbol, LOG_LEVEL_ERROR);
               outFailCode = RG_FAIL_LOT_ZERO;
               return 0.0;
           }
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

        // P3 Fix: Risk cap - never exceed 5% of account per single trade — uses OrderCalcProfit for truth
       double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
       if(entryPrice > 0 && slPrice > 0 && MathAbs(entryPrice - slPrice) > 0 && spLot.contractSize > 0)
       {
           double lossPerMaxLotCheck = 0.0;
           if(OrderCalcProfit(orderType, symbol, maxLot, entryPrice, slPrice, lossPerMaxLotCheck))
           {
               LogPrint("[LOT_CALCPROFIT] risk cap | sym=" + symbol +
                        " | orderType=" + IntegerToString(orderType) +
                        " | volume=" + DoubleToString(maxLot, 2) +
                        " | entry=" + DoubleToString(entryPrice, _Digits) +
                        " | sl=" + DoubleToString(slPrice, _Digits) +
                        " | rawProfit=" + DoubleToString(lossPerMaxLotCheck, 2) +
                        " | source=OrderCalcProfit", LOG_LEVEL_DEBUG);
               double lossPerLotCheck = MathAbs(lossPerMaxLotCheck) / maxLot;
               if(lossPerLotCheck > 0)
               {
                   double maxRiskLot = (accountBalance * 0.05) / lossPerLotCheck;
                   if(finalLot > maxRiskLot && maxRiskLot > minLot)
                   {
LogPrint("[LOT_CAP] Risk cap applied | old=" + DoubleToString(finalLot, 5) +
                              " | capped=" + DoubleToString(maxRiskLot, 5), LOG_LEVEL_DEBUG);
                       finalLot = MathFloor(maxRiskLot / lotStep + 0.5) * lotStep;
                   }
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
//| CalculateRiskLot — Authoritative lot sizing using OrderCalcProfit|
//| Trusts broker OrderCalcProfit as ground truth for all calc modes: |
//| forex, crypto, synthetic, index CFDs, cent/micro/nano accounts.  |
//| No simplified formula fallback — only OrderCalcProfit.           |
//| Logs all inputs/outputs per AGENTS.md §XI (OrderCalcProfit       |
//| Instrumentation).                                                 |
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

    double riskAmount = equity * (riskPct / 100.0);
    if(riskAmount <= 0.0)
    {
        LogPrint("[LOT_CALC_FAIL] riskAmount <= 0 | equity=" + DoubleToString(equity, 2) +
                 " | riskPct=" + DoubleToString(riskPct, 4) +
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

    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    if(minLot <= 0.0)
    {
        LogPrint("[LOT_CALC_FAIL] minLot <= 0 | GUID=" + IntegerToString(guid), LOG_LEVEL_ERROR);
        return 0.0;
    }

    ENUM_ORDER_TYPE orderType = (signal.direction == DIRECTION_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    double projectedLoss = 0.0;

    if(!OrderCalcProfit(orderType, _Symbol, minLot, entryPrice, slPrice, projectedLoss))
    {
        LogPrint("[LOT_CALC_FAIL] OrderCalcProfit API failed | GUID=" + IntegerToString(guid) +
                 " | orderType=" + IntegerToString(orderType) +
                 " | symbol=" + _Symbol +
                 " | minLot=" + DoubleToString(minLot, 4) +
                 " | entryPrice=" + DoubleToString(entryPrice, _Digits) +
                 " | stopLoss=" + DoubleToString(slPrice, _Digits), LOG_LEVEL_ERROR);
        return 0.0;
    }

    double absLoss = MathAbs(projectedLoss);
    LogPrint("[LOT_CALCPROFIT] GUID=" + IntegerToString(guid) +
             " | orderType=" + IntegerToString(orderType) +
             " | symbol=" + _Symbol +
             " | minLot=" + DoubleToString(minLot, 4) +
             " | entryPrice=" + DoubleToString(entryPrice, _Digits) +
             " | stopLoss=" + DoubleToString(slPrice, _Digits) +
             " | rawProfit=" + DoubleToString(projectedLoss, 2) +
             " | projectedLoss=" + DoubleToString(absLoss, 2) +
             " | slDist=" + DoubleToString(slDist, _Digits) +
             " | source=OrderCalcProfit", LOG_LEVEL_INFO);

    if(absLoss <= 0.0)
    {
        LogPrint("[LOT_CALC_FAIL] OrderCalcProfit returned zero loss | GUID=" + IntegerToString(guid), LOG_LEVEL_ERROR);
        return 0.0;
    }

    double desiredLot = (riskAmount / absLoss) * minLot;

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

    double verifyLoss = 0.0;
    if(OrderCalcProfit(orderType, _Symbol, desiredLot, entryPrice, slPrice, verifyLoss))
    {
        double verifyAbs = MathAbs(verifyLoss);
        if(verifyAbs > riskAmount * 1.2)
        {
            LogPrint("[RISK_FLOOR_BLOCK] GUID=" + IntegerToString(guid) +
                     " | projectedRisk=" + DoubleToString(verifyAbs, 2) +
                     " | exceedsBudget=" + DoubleToString(riskAmount, 2) +
                     " | ratio=" + DoubleToString(verifyAbs / riskAmount, 2) +
                     " | desiredLot=" + DoubleToString(desiredLot, 4) +
                     " | source=OrderCalcProfit", LOG_LEVEL_WARN);
            return 0.0;
        }
        LogPrint("[LOT_VERIFY] GUID=" + IntegerToString(guid) +
                 " | desiredLot=" + DoubleToString(desiredLot, 4) +
                 " | verifyLoss=" + DoubleToString(verifyAbs, 2) +
                 " | riskAmount=" + DoubleToString(riskAmount, 2) +
                 " | ratio=" + DoubleToString(verifyAbs / riskAmount, 2) +
                 " | source=OrderCalcProfit", LOG_LEVEL_INFO);
    }
    else
    {
        LogPrint("[LOT_VERIFY_FAIL] OrderCalcProfit verification failed | GUID=" + IntegerToString(guid) +
                 " | desiredLot=" + DoubleToString(desiredLot, 4), LOG_LEVEL_WARN);
    }

    LogPrint("[LOT_OK] GUID=" + IntegerToString(guid) +
             " | lot=" + DoubleToString(desiredLot, 4) +
             " | equity=" + DoubleToString(equity, 2) +
             " | riskPct=" + DoubleToString(riskPct, 4) +
             " | riskAmount=" + DoubleToString(riskAmount, 2) +
             " | minLot=" + DoubleToString(minLot, 4) +
             " | source=OrderCalcProfit", LOG_LEVEL_INFO);

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
//| CalculateAgnosticLot — Universal structural lot sizing           |
//| Uses OrderCalcProfit for any instrument type:                    |
//| Standard, Micro, Cent, Nano, Synthetic, Crypto, Index CFDs.     |
//| Stop distance is structural (protected swing), NOT fixed pts.   |
//+------------------------------------------------------------------+
double CalculateAgnosticLot(double entry, double sl, double riskPct)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double lossPerMinLot = 0.0;
   bool calcProfitOk = OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, minLot, entry, sl, lossPerMinLot);

   if(!calcProfitOk)
     {
      double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double slPoints = MathAbs(entry - sl) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      lossPerMinLot = slPoints * tickVal * minLot;
      LogPrint("[LOT_CALCPROFIT] OrderCalcProfit failed | using formula | slPts=" +
               DoubleToString(slPoints, 1) +
               " | tickVal=" + DoubleToString(tickVal, 6) +
               " | formulaLoss=" + DoubleToString(lossPerMinLot, 2) +
               " | decision=formula", LOG_LEVEL_WARN);
     }
   else
     {
      LogPrint("[LOT_CALCPROFIT] OrderCalcProfit ok | rawReturn=" +
               DoubleToString(lossPerMinLot, 2) +
               " | decision=OrderCalcProfit", LOG_LEVEL_DEBUG);
     }

   double maxLoss = AccountInfoDouble(ACCOUNT_EQUITY) * (riskPct / 100.0);
   double calculatedLot = (maxLoss / MathAbs(lossPerMinLot)) * minLot;

   LogPrint("[LOT_CALCPROFIT] Agnostic | sym=" + _Symbol +
            " | entry=" + DoubleToString(entry, _Digits) +
            " | sl=" + DoubleToString(sl, _Digits) +
            " | minLot=" + DoubleToString(minLot, 4) +
            " | lossPerMinLot=" + DoubleToString(lossPerMinLot, 2) +
            " | maxLoss=" + DoubleToString(maxLoss, 2) +
            " | calculatedLot=" + DoubleToString(calculatedLot, 6) +
            " | source=OrderCalcProfit", LOG_LEVEL_INFO);

   return NormalizeLot(calculatedLot);
}

#endif // OMAK_RISKMANAGER_MQH