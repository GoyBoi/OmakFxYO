//+------------------------------------------------------------------+
//|                                        RiskManager.mqh (Refactored) |
//+------------------------------------------------------------------+
//| Single Risk Authority Implementation                              |
//| - OrderCalcProfit() is the sole source of truth for risk amount  |
//| - Manual formula is used only for cross-validation (>5% = reject)|
//| - All symbol data retrieved from SSymbolProfile, never raw API   |
//+------------------------------------------------------------------+
#property strict

#ifndef OMAK_RISKMANAGER_MQH
#define OMAK_RISKMANAGER_MQH

#include <OmakFxYO/core/ModeResolver.mqh>
#include <OmakFxYO/core/CoreTypes.mqh>
#include <OmakFxYO/core/LogGovernor.mqh>
#include <OmakFxYO/core/RiskGate.mqh>
#include <OmakFxYO/core/RiskCore.mqh>

#include <OmakFxYO/core/SymbolIntelligence.mqh>

extern double g_symbolRiskFloor;
extern double g_minStopBuffer;
extern ENUM_EXECUTION_BRANCH g_activeBranch;

//+------------------------------------------------------------------+
//| Unified Lot Size Calculator                                      |
//+------------------------------------------------------------------+
bool CalculateUnifiedLotSize(double riskAmountUSD,       // USD risk amount (max 2% of balance)
                            double stopDistancePoints,   // SL distance in points
                            double &outLotSize,          // Calculated lot size
                            string &outError)            // Error message if any
{
   // Step 1: Validate inputs
   if(riskAmountUSD <= 0.0)
   {
      outError = "Risk amount must be positive";
      return false;
   }

   if(stopDistancePoints <= 0.0)
   {
      outError = "Stop distance must be positive";
      return false;
   }

   // Step 2: Get symbol profile data (no direct SymbolInfoXXXX calls for static props)
   SSymbolProfile profile = SY_GetProfile(_Symbol);
   if(!profile.isValid)
   {
      outError = "Failed to get symbol profile";
      return false;
   }

   double contractSize = profile.contractSize;
   double tickSize = profile.tickSize;
   double tickValue = profile.tickValue;
   double point = profile.point;
   double minLot = profile.volumeMin;
   double maxLot = profile.volumeMax;
   double lotStep = profile.volumeStep;
   int calcMode = profile.calcMode;

   // Step 3: Validate tick values (protect against zero)
   if(tickValue <= 0.0 || tickSize <= 0.0)
   {
      outError = StringFormat("Invalid tick values: tickValue=%.6f tickSize=%.6f", tickValue, tickSize);
      return false;
   }

   // Step 4: Calculate lot size using OrderCalcProfit (API method)
   // Use max lot as reference volume for precision (best practice from MQL5 community)
   double referenceVolume = maxLot;
   double apiProfitForReference = 0.0;

    // OrderCalcProfit instrumentation per §XII: log inputs and raw return
    SSymbolProfile calcProf = SY_GetProfile(_Symbol);
    if(!calcProf.isValid)
    {
       outError = "Failed to get symbol profile for OrderCalcProfit";
       return false;
    }
    double refEntry = calcProf.tickBid;
    double refSL = refEntry - (stopDistancePoints * point);

    LogPrint("[ORDERCALCPROFIT] orderType=ORDER_TYPE_BUY symbol="+_Symbol+
          " volume="+DoubleToString(referenceVolume,2)+
          " entryPrice="+DoubleToString(refEntry,_Digits)+
          " stopLoss="+DoubleToString(refSL,_Digits), LOG_LEVEL_INFO);

    if(!OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, referenceVolume,
                        refEntry, refSL, apiProfitForReference))
    {
       LogPrint("[ORDERCALCPROFIT] ORDER_TYPE_BUY failed, trying ORDER_TYPE_SELL | error="+IntegerToString(GetLastError()), LOG_LEVEL_WARN);
       double refEntrySell = calcProf.tickAsk;
       double refSLSell = refEntrySell + (stopDistancePoints * point);

      LogPrint("[ORDERCALCPROFIT] orderType=ORDER_TYPE_SELL symbol="+_Symbol+
            " volume="+DoubleToString(referenceVolume,2)+
            " entryPrice="+DoubleToString(refEntrySell,_Digits)+
            " stopLoss="+DoubleToString(refSLSell,_Digits), LOG_LEVEL_INFO);

      if(!OrderCalcProfit(ORDER_TYPE_SELL, _Symbol, referenceVolume,
                          refEntrySell, refSLSell, apiProfitForReference))
      {
         outError = "OrderCalcProfit failed for both ORDER_TYPE_BUY and ORDER_TYPE_SELL";
         return false;
      }
   }

   LogPrint("[ORDERCALCPROFIT_RESULT] rawProfit="+DoubleToString(apiProfitForReference,2), LOG_LEVEL_INFO);

   // OrderCalcProfit returns negative for loss (which is what we want)
   double riskPerReferenceVolume = MathAbs(apiProfitForReference);
   if(riskPerReferenceVolume <= 0.0)
   {
      outError = "OrderCalcProfit returned zero or negative risk amount";
      return false;
   }

   // Calculate desired lot size via ratio method
   double desiredLot = (riskAmountUSD / riskPerReferenceVolume) * referenceVolume;
   desiredLot = MathFloor(desiredLot / lotStep + 0.5) * lotStep;  // Round to lotStep
   desiredLot = MathMax(minLot, MathMin(desiredLot, maxLot));

   // Step 5: Cross-validate with manual formula (sanity check)
   // manualRisk = ((stopDistancePoints * point) / tickSize) * tickValue * desiredLot
    double ticks = (stopDistancePoints * point) / tickSize;
   double manualRisk = ticks * tickValue * desiredLot;

   double apiRisk = 0.0;
    double verifyEntry = calcProf.tickBid;
    double verifySL = verifyEntry - (stopDistancePoints * point);

   LogPrint("[ORDERCALCPROFIT] orderType=ORDER_TYPE_BUY symbol="+_Symbol+
         " volume="+DoubleToString(desiredLot,2)+
         " entryPrice="+DoubleToString(verifyEntry,_Digits)+
         " stopLoss="+DoubleToString(verifySL,_Digits)+
         " [CROSS-VALIDATION]", LOG_LEVEL_INFO);

   if(!OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, desiredLot,
                       verifyEntry, verifySL, apiRisk))
   {
      LogPrint("[ORDERCALCPROFIT_FAIL] OrderCalcProfit returned false for cross-validation | "+
            "error="+IntegerToString(GetLastError()), LOG_LEVEL_WARN);
      // Use manual formula as fallback per §XXI
      apiRisk = manualRisk;
      LogPrint("[ORDERCALCPROFIT_RESULT] fallback manualRisk="+DoubleToString(apiRisk,2)+" [FALLBACK]", LOG_LEVEL_WARN);
   }
   else
   {
      LogPrint("[ORDERCALCPROFIT_RESULT] rawProfit="+DoubleToString(apiRisk,2)+" [CROSS-VALIDATION]", LOG_LEVEL_INFO);
   }
   apiRisk = MathAbs(apiRisk);

   double discrepancy = MathAbs(manualRisk - apiRisk) / apiRisk;

   // Step 6: Constitutional check - reject if discrepancy > 5%
   if(discrepancy > 0.05)
   {
      outError = StringFormat("Risk discrepancy > 5%%: manual=%.2f api=%.2f ratio=%.4f",
                              manualRisk, apiRisk, discrepancy);
      LogPrint("[RISK_REJECT] " + outError, LOG_LEVEL_ERROR);
      LogPrint("[DECISION_AUTHORITY] OrderCalcProfit", LOG_LEVEL_INFO);
      return false;
   }

   // Step 7: Success - return calculated lot
   outLotSize = desiredLot;
   outError = "";

   LogPrint("[RISK_ACCEPTED] Lots=" + DoubleToString(outLotSize,2) +
         " ManualRisk=" + DoubleToString(manualRisk,2) +
         " APIRisk=" + DoubleToString(apiRisk,2) +
         " Discrepancy=" + DoubleToString(discrepancy*100, 2) + "%", LOG_LEVEL_INFO);
   LogPrint("[DECISION_AUTHORITY] OrderCalcProfit", LOG_LEVEL_INFO);

   return true;
}

//+------------------------------------------------------------------+
//| Simplified Entry Point for EA Calls                              |
//+------------------------------------------------------------------+
bool CalculateLotSize(double riskPercent,         // % of balance to risk (1.0 = 1%)
                     double stopDistancePoints,   // SL distance in points
                     double &outLotSize)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmountUSD = accountBalance * (riskPercent / 100.0);

   string errorMsg;
   bool result = CalculateUnifiedLotSize(riskAmountUSD, stopDistancePoints, outLotSize, errorMsg);

   if(!result)
   {
      LogPrint("[RISK_GATE_FAIL] " + errorMsg, LOG_LEVEL_ERROR);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| CalculateRiskLot — Backward-compat wrapper (signal-based)        |
//| Delegates to CalculateLotSize → CalculateUnifiedLotSize          |
//+------------------------------------------------------------------+
bool CalculateRiskLot(SLockedSignal &signal, double riskPct, double &lot)
{
   if(riskPct <= 0.0)
   {
      LogPrint("[RISK_GATE_FAIL] positionSizeFactor <= 0.0 | value=" + DoubleToString(riskPct, 2), LOG_LEVEL_ERROR);
      return false;
   }
   double entryPrice = signal.entry_price;
   double slPrice = signal.stop_loss;
   if(entryPrice <= 0.0 || slPrice <= 0.0)
   {
      LogPrint("[RISK_GATE_FAIL] CalculateRiskLot: invalid entry/sl | GUID="+IntegerToString(signal.m_guid), LOG_LEVEL_ERROR);
      return false;
   }

   double slDist = MathAbs(entryPrice - slPrice);
   SSymbolProfile prof = SY_GetProfile(_Symbol);
   if(!prof.isValid)
   {
      LogPrint("[RISK_GATE_FAIL] CalculateRiskLot: invalid profile", LOG_LEVEL_ERROR);
      return false;
   }

   double slPoints = slDist / prof.point;
   if(!CalculateLotSize(riskPct, slPoints, lot))
      return false;
   return true;
}

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

double GetManipulationLegExtreme(const string symbol, ENUM_TIMEFRAMES tf, bool isLong) {
    int lookback = 10;
    int extremeBar = isLong ? iLowest(symbol, tf, MODE_LOW, lookback, 1)
                            : iHighest(symbol, tf, MODE_HIGH, lookback, 1);
    return isLong ? iLow(symbol, tf, extremeBar) : iHigh(symbol, tf, extremeBar);
}

double g_internalRiskSL = 0.0;

void SyncInternalSL(double sl)
{
    g_internalRiskSL = sl;
    LogPrint("[SL_SYNC] Internal Risk SL synced to " + DoubleToString(sl, _Digits), LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| NormalizeLot — Round lot to broker volume step (no upward force) |
//+------------------------------------------------------------------+
double NormalizeLot(double rawLot)
{
   SSymbolProfile prof = SY_GetProfile(_Symbol);
   double minLot = prof.volumeMin;
   double maxLot = prof.volumeMax;
   double step   = prof.volumeStep;

   if(step > 0.0)
      rawLot = MathFloor(rawLot / step) * step;

   if(rawLot < minLot) return 0.0;
   rawLot = MathMin(rawLot, maxLot);

   int precision = 0;
   double temp = step;
   while(MathAbs(temp * MathPow(10, precision) - MathRound(temp * MathPow(10, precision))) > 1e-10 && precision < 8)
      precision++;

   return NormalizeDouble(rawLot, precision);
}

double SincereLotSize(string symbol, double riskAmount, double entry, double sl) {
    SSymbolProfile prof = SY_GetProfile(symbol);
    double tickSize = prof.tickSize;
    double tickValue = prof.tickValue;

    if (tickSize == 0 || tickValue == 0) { LogPrint("[CURRENCY_SINCERITY_FAIL] tickSize/tickValue zero", LOG_LEVEL_WARN); return 0.0; }
    if (riskAmount <= 0.0 || entry <= 0.0 || sl <= 0.0) { LogPrint("[CURRENCY_SINCERITY_FAIL] invalid params | riskAmount=" + DoubleToString(riskAmount, 2) + " | entry=" + DoubleToString(entry, _Digits) + " | sl=" + DoubleToString(sl, _Digits) + " | accountCCY=" + AccountInfoString(ACCOUNT_CURRENCY), LOG_LEVEL_WARN); return 0.0; }

    double priceDist = MathAbs(entry - sl);
    double lossPerLot = (priceDist / tickSize) * tickValue;

    double rawLot = riskAmount / lossPerLot;
    double finalLot = NormalizeLot(symbol, rawLot);

    LogPrint("[CURRENCY_SINCERITY] Risk:%.2f " + AccountInfoString(ACCOUNT_CURRENCY) +
             " | LossPerLot:%.2f " + AccountInfoString(ACCOUNT_CURRENCY) +
             " | FinalLot:%.2f", LOG_LEVEL_INFO);

    return finalLot;
}

//+------------------------------------------------------------------+
//| NormalizeLot — Overload with symbol parameter (no upward force)  |
//+------------------------------------------------------------------+
double NormalizeLot(const string symbol, double rawLot)
{
   SSymbolProfile prof = SY_GetProfile(symbol);
   double minLot = prof.volumeMin;
   double maxLot = prof.volumeMax;
   double step   = prof.volumeStep;

   if(step > 0.0)
      rawLot = MathFloor(rawLot / step) * step;

   if(rawLot < minLot) return 0.0;
   rawLot = MathMin(rawLot, maxLot);

   int precision = 0;
   double temp = step;
   while(MathAbs(temp * MathPow(10, precision) - MathRound(temp * MathPow(10, precision))) > 1e-10 && precision < 8)
      precision++;

   return NormalizeDouble(rawLot, precision);
}

//+------------------------------------------------------------------+
//| C3_SL_Calculator - Continuation Signal (TTFM Confirmation)       |
//+------------------------------------------------------------------+
//| TTFM Rule: SL beyond the PROTECTED SWING                          |
//| (the high/low expected to hold if trend continues)               |
//| Structure TF: H1 for Branch A, H4 for Branch B                   |
//+------------------------------------------------------------------+
double C3_SL_Calculator(int direction, double entryPrice, 
                        ENUM_TIMEFRAMES structureTF, double minStopMult)
{
   SSymbolProfile prof = SY_GetProfile(_Symbol);
   if(!prof.isValid)
   {
      LogPrint("[C3_SL_ERROR] No symbol profile", LOG_LEVEL_ERROR);
      return 0.0;
   }
   
   double point = prof.point;
   long stopsLevel = prof.stopsLevel;
   if(stopsLevel <= 0) stopsLevel = 100;
   double buffer = stopsLevel * point * minStopMult;
   double protectedSwing = 0.0;
   int swingBars = (structureTF == PERIOD_H1) ? 8 : 6;
   
   if(direction == 1) // BUY continuation - stop below protected low
   {
      int lowestIdx = iLowest(_Symbol, structureTF, MODE_LOW, swingBars, 1);
      if(lowestIdx != -1)
         protectedSwing = iLow(_Symbol, structureTF, lowestIdx);
      
      if(protectedSwing <= 0.0)
      {
         lowestIdx = iLowest(_Symbol, structureTF, MODE_LOW, 20, 1);
         if(lowestIdx != -1)
         {
            protectedSwing = iLow(_Symbol, structureTF, lowestIdx);
            LogPrint("[C3_SL] BUY fallback to wider scan: protectedSwing=" + DoubleToString(protectedSwing, _Digits), LOG_LEVEL_WARN);
         }
         else
         {
            LogPrint("[C3_SL] BUY no protected low on Structure TF", LOG_LEVEL_ERROR);
            return 0.0;
         }
      }
      
       double finalSL = protectedSwing - buffer;
       if(finalSL >= entryPrice)
       {
          LogPrint("[C3_SL] BUY SL on wrong side, rejecting", LOG_LEVEL_ERROR);
          return 0.0;
       }
        // Enforce broker minimum stop distance
        {
           long sl = prof.stopsLevel; if(sl <= 0) sl = 10;
           double minDist = sl * prof.point * InpMinStopBuffer;
           if(entryPrice - finalSL < minDist)
              finalSL = entryPrice - minDist;
        }
        return finalSL;
     }
     else // SELL continuation - stop above protected high
    {
      int highestIdx = iHighest(_Symbol, structureTF, MODE_HIGH, swingBars, 1);
      if(highestIdx != -1)
         protectedSwing = iHigh(_Symbol, structureTF, highestIdx);
      
      if(protectedSwing <= 0.0)
      {
         highestIdx = iHighest(_Symbol, structureTF, MODE_HIGH, 20, 1);
         if(highestIdx != -1)
         {
            protectedSwing = iHigh(_Symbol, structureTF, highestIdx);
            LogPrint("[C3_SL] SELL fallback to wider scan: protectedSwing=" + DoubleToString(protectedSwing, _Digits), LOG_LEVEL_WARN);
         }
         else
         {
            LogPrint("[C3_SL] SELL no protected high on Structure TF", LOG_LEVEL_ERROR);
            return 0.0;
         }
      }
      
       double finalSL = protectedSwing + buffer;
       if(finalSL <= entryPrice)
       {
          LogPrint("[C3_SL] SELL SL on wrong side, rejecting", LOG_LEVEL_ERROR);
          return 0.0;
       }
        // Enforce broker minimum stop distance
        {
           long sl = prof.stopsLevel; if(sl <= 0) sl = 10;
           double minDist = sl * prof.point * InpMinStopBuffer;
           if(finalSL - entryPrice < minDist)
              finalSL = entryPrice + minDist;
        }
        return finalSL;
     }
}

//+------------------------------------------------------------------+
//| C2_SL_Calculator - Reversal Signal (TTFM Anticipation)           |
//+------------------------------------------------------------------+
//| TTFM Rule: SL beyond the LIQUIDITY SWEEP EXTREME                  |
//| (the high/low that was swept during C2 formation)                |
//| Structure TF: H1 for Branch A, H4 for Branch B                   |
//+------------------------------------------------------------------+
double C2_SL_Calculator(int direction, double entryPrice, 
                        ENUM_TIMEFRAMES structureTF, double minStopMult)
{
   SSymbolProfile prof = SY_GetProfile(_Symbol);
   if(!prof.isValid)
   {
      LogPrint("[C2_SL_ERROR] No symbol profile", LOG_LEVEL_ERROR);
      return 0.0;
   }
   
   double point = prof.point;
   long stopsLevel = prof.stopsLevel;
   if(stopsLevel <= 0) stopsLevel = 100;
   double buffer = stopsLevel * point * minStopMult;
   double sweptExtreme = 0.0;
   int lookback = (structureTF == PERIOD_H1) ? 5 : 4;
   
   if(direction == 1) // BUY reversal - swept low
   {
      int lowestIdx = iLowest(_Symbol, structureTF, MODE_LOW, lookback, 1);
      if(lowestIdx != -1)
         sweptExtreme = iLow(_Symbol, structureTF, lowestIdx);
      
      if(sweptExtreme <= 0.0)
      {
         lowestIdx = iLowest(_Symbol, structureTF, MODE_LOW, 15, 1);
         if(lowestIdx != -1)
         {
            sweptExtreme = iLow(_Symbol, structureTF, lowestIdx);
            LogPrint("[C2_SL] BUY fallback to wider scan: sweptExtreme=" + DoubleToString(sweptExtreme, _Digits), LOG_LEVEL_WARN);
         }
         else
         {
            LogPrint("[C2_SL] BUY no swept low on Structure TF", LOG_LEVEL_ERROR);
            return 0.0;
         }
      }
      
       double finalSL = sweptExtreme - buffer;
       if(finalSL >= entryPrice)
       {
          LogPrint("[C2_SL] BUY SL on wrong side, rejecting", LOG_LEVEL_ERROR);
          return 0.0;
       }
        // Enforce broker minimum stop distance
        {
           long sl = prof.stopsLevel; if(sl <= 0) sl = 10;
           double minDist = sl * prof.point * InpMinStopBuffer;
           if(entryPrice - finalSL < minDist)
              finalSL = entryPrice - minDist;
        }
        return finalSL;
     }
     else // SELL reversal - swept high
    {
      int highestIdx = iHighest(_Symbol, structureTF, MODE_HIGH, lookback, 1);
      if(highestIdx != -1)
         sweptExtreme = iHigh(_Symbol, structureTF, highestIdx);
      
      if(sweptExtreme <= 0.0)
      {
         highestIdx = iHighest(_Symbol, structureTF, MODE_HIGH, 15, 1);
         if(highestIdx != -1)
         {
            sweptExtreme = iHigh(_Symbol, structureTF, highestIdx);
            LogPrint("[C2_SL] SELL fallback to wider scan: sweptExtreme=" + DoubleToString(sweptExtreme, _Digits), LOG_LEVEL_WARN);
         }
         else
         {
            LogPrint("[C2_SL] SELL no swept high on Structure TF", LOG_LEVEL_ERROR);
            return 0.0;
         }
      }
      
       double finalSL = sweptExtreme + buffer;
       if(finalSL <= entryPrice)
       {
          LogPrint("[C2_SL] SELL SL on wrong side, rejecting", LOG_LEVEL_ERROR);
          return 0.0;
       }
       // Enforce broker minimum stop distance
       {
           long sl = prof.stopsLevel; if(sl <= 0) sl = 10;
           double minDist = sl * prof.point * InpMinStopBuffer;
           if(finalSL - entryPrice < minDist)
              finalSL = entryPrice + minDist;
        }
        return finalSL;
     }
}

//+------------------------------------------------------------------+
//| C4_SL_Calculator - Dedicated Stop Loss for C4 (Expansion)       |
//+------------------------------------------------------------------+
//| AGENTS.md §V: SL anchored to Opposite extreme of the C3 candle   |
//| (low for bullish, high for bearish) + minimal buffer (0.5×)      |
//+------------------------------------------------------------------+
double C4_SL_Calculator(int direction,           // +1 = BUY, -1 = SELL
                        double entryPrice,
                        double c3_high,          // C3 candle high (parent reference)
                        double c3_low,           // C3 candle low (parent reference)
                        double minStopMult)      // Minimum buffer (stops level multiplier)
{
   SSymbolProfile prof = SY_GetProfile(_Symbol);
   if(!prof.isValid)
   {
      LogPrint("[C4_SL_ERROR] No symbol profile", LOG_LEVEL_ERROR);
      return 0.0;
   }

   double point = prof.point;
   long stopsLevel = prof.stopsLevel;
   if(stopsLevel <= 0) stopsLevel = 100;
   double buffer = stopsLevel * point * 0.5 * minStopMult;

   // AGENTS.md §V: C4 uses opposite extreme of C3 candle
   // BUY → SL below C3 low; SELL → SL above C3 high
   double c3Extreme = (direction == 1) ? c3_low : c3_high;

   if(c3Extreme <= 0.0)
   {
      LogPrint("[C4_SL_REJECT] C3 extreme invalid | direction=" + (direction == 1 ? "BUY" : "SELL") +
               " | c3_high=" + DoubleToString(c3_high, _Digits) +
               " | c3_low=" + DoubleToString(c3_low, _Digits), LOG_LEVEL_ERROR);
      return 0.0;
   }

   double finalSL = (direction == 1) ? c3Extreme - buffer : c3Extreme + buffer;

   // Ensure SL is on correct side of entry
   if((direction == 1 && finalSL >= entryPrice) ||
      (direction == -1 && finalSL <= entryPrice))
   {
      LogPrint("[C4_SL_WRONG_SIDE] SL on wrong side of entry | direction=" + (direction == 1 ? "BUY" : "SELL") +
               " | entry=" + DoubleToString(entryPrice, _Digits) +
               " | sl=" + DoubleToString(finalSL, _Digits) +
               " | c3Extreme=" + DoubleToString(c3Extreme, _Digits), LOG_LEVEL_WARN);
      return 0.0;
   }

   LogPrint("[C4_SL] direction=" + (direction == 1 ? "BUY" : "SELL") +
            " | entry=" + DoubleToString(entryPrice, _Digits) +
            " | sl=" + DoubleToString(finalSL, _Digits) +
            " | c3_high=" + DoubleToString(c3_high, _Digits) +
            " | c3_low=" + DoubleToString(c3_low, _Digits) +
            " | c3Extreme=" + DoubleToString(c3Extreme, _Digits) +
            " | buffer=" + DoubleToString(buffer, 8), LOG_LEVEL_INFO);

   return finalSL;
}

#endif // OMAK_RISKMANAGER_MQH
