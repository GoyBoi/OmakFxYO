//+------------------------------------------------------------------+
//| InstitutionalScaling.mqh                                          |
//| Omak FxYO — Exposure Control & Capital Alignment                 |
//|                                                                  |
//| B3 RE-ARCHITECTURE: Execution-Aware Scaling Engine              |
//| B4 INTEGRATION: Traceable Trade Lifecycle                        |
//+------------------------------------------------------------------+
#ifndef OMAK_INSTITUTIONALSCALING_MQH
#define OMAK_INSTITUTIONALSCALING_MQH

#include <OmakFxYO/core/CoreTypes.mqh>

#include <OmakFxYO/core/PositionManager.mqh>
#include <OmakFxYO/core/TradeContext.mqh>

#define MAX_LOT_REDUCTION 0.40

struct SScalingContext
{
    int    currentPositions;
    double totalLots;
    double avgEntryPrice;
    double floatingProfit;
    double riskExposurePercent;
    bool   isInProfit;
    bool   isProtected;
    bool   canScale;
    int    minProfitBars;
};

SScalingContext IS_BuildContext(string symbol, int magic)
{
    SScalingContext ctx;
    ctx.currentPositions = 0;
    ctx.totalLots = 0.0;
    ctx.avgEntryPrice = 0.0;
    ctx.floatingProfit = 0.0;
    ctx.riskExposurePercent = 0.0;
    ctx.isInProfit = false;
    ctx.isProtected = true;
    ctx.canScale = false;
    ctx.minProfitBars = 0;

   double totalVolumePrice = 0.0;
   double totalVolume = 0.0;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   bool allProtected = true;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(PositionGetSymbol(i) != symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic)
         continue;

      ctx.currentPositions++;

ulong ticket = PositionGetInteger(POSITION_TICKET);
       int idx = PM_GetPositionStateIndex(ticket);
       if(idx >= 0 && g_positionStates[idx].profitBars < ctx.minProfitBars)
          ctx.minProfitBars = g_positionStates[idx].profitBars;

       double volume = PositionGetDouble(POSITION_VOLUME);
       double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
       double currentSL = PositionGetDouble(POSITION_SL);
       ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      totalVolumePrice += volume * openPrice;
      totalVolume += volume;

SSymbolProfile spCtx = SY_GetProfile(symbol);
       double currentPrice = (posType == POSITION_TYPE_BUY) ? spCtx.tickBid : spCtx.tickAsk;
       double point = spCtx.point;
       double spread = spCtx.spread * point;

     if(posType == POSITION_TYPE_BUY)
     {
        ctx.floatingProfit += (currentPrice - openPrice) * volume / point;
        if(currentSL < openPrice + spread)
           allProtected = false;
     }
     else
     {
        ctx.floatingProfit += (openPrice - currentPrice) * volume / point;
        if(currentSL > openPrice - spread)
           allProtected = false;
     }
   }

   if(totalVolume > 0.0)
      ctx.avgEntryPrice = totalVolumePrice / totalVolume;

   ctx.totalLots = totalVolume;
   ctx.isInProfit = (ctx.floatingProfit > 0.0);
   ctx.isProtected = allProtected;

    if(balance > 0.0 && totalVolume > 0.0)
    {
       SSymbolProfile spIs = SY_GetProfile(symbol);
       double notionalValue = totalVolume * spIs.tickValue * (1.0 / spIs.tickSize) * spIs.point * spIs.contractSize;
       ctx.riskExposurePercent = (notionalValue / balance) * 100.0;
    }

   return ctx;
}

bool IS_CanScale(SScalingContext &ctx)
{
    if(ctx.currentPositions >= 2)
       return false;

    if(!ctx.isInProfit)
       return false;

    if(!ctx.isProtected)
       return false;

    if(ctx.riskExposurePercent > 2.5)
       return false;

    if(ctx.minProfitBars < 2)
       return false;

    return true;
}

double GetVolatilityMultiplier(string symbol, ENUM_TIMEFRAMES tf)
{
    // ATR removed — use fixed multiplier independent of volatility regime
    return 0.9;
}

double GetPositionMultiplier(SScalingContext &ctx)
{
    if(ctx.currentPositions == 0)
       return 1.0;

    if(ctx.currentPositions == 1)
       return 0.6;

    return 0.4;
}

double SafeScaleLot(
     double baseLot,
     double minLot,
     double maxLot,
     double step,
     double volatilityMultiplier,
     double positionMultiplier,
     string symbol,
     bool isSignalValid   // NEW PARAM — true if C2/C3 valid
 )
 {
    SSymbolProfile spIs = SY_GetProfile(symbol);

    if(baseLot <= 0.0)
       return 0.0;

    if(minLot <= 0.0)
       return 0.0;

    if(maxLot <= 0.0)
       return 0.0;

    if(step <= 0.0)
       return 0.0;

    double portfolioFactor = positionMultiplier;
    double volatilityFactor = volatilityMultiplier;

    double predictedLot = baseLot * portfolioFactor * volatilityFactor;

    // SIGNAL STRANGULATION FIX: If isSignalValid && predictedLot < minLot,
    // do NOT force minLot — this caused the $18.80 blow-up on small accounts.
    // Return 0.0 to skip the trade, matching CalculateLotSize() behavior.
    if(isSignalValid && predictedLot < minLot)
    {
        LogPrint("[IS_MISMATCH] predictedLot=" + DoubleToString(predictedLot, 6) +
                 " < minLot=" + DoubleToString(minLot, 4) +
                 " | isSignalValid=true — SKIPPING trade (account too small)",
                 LOG_LEVEL_WARN);
        return 0.0;
    }

if(predictedLot < minLot)
     {
         double marginRequired = minLot * spIs.marginInitial;
         double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

        if(freeMargin >= marginRequired)
        {
           LogPrint("[IS_MISMATCH] predictedLot=" + DoubleToString(predictedLot, 6) +
                    " < minLot " + DoubleToString(minLot, 4) +
                    " — SKIPPING (margin OK but risk mismatch)",
                    LOG_LEVEL_WARN);
           return 0.0;
        }

        LogPrint("[IS_MISMATCH] predictedLot=" + DoubleToString(predictedLot, 6) +
                 " < minLot " + DoubleToString(minLot, 4) +
                 " — INSUFFICIENT MARGIN (need " + DoubleToString(marginRequired, 2) +
                 ", have " + DoubleToString(freeMargin, 2) + ")",
                 LOG_LEVEL_WARN);
        return 0.0;
    }

    if(predictedLot > maxLot)
       predictedLot = maxLot;

    if(step > 0.0)
       predictedLot = MathFloor(predictedLot / step) * step;

    double loss = (baseLot - predictedLot) / baseLot;
    if(loss > MAX_LOT_REDUCTION)
    {
        predictedLot = baseLot * (1.0 - MAX_LOT_REDUCTION);
        
        if(step > 0.0)
           predictedLot = MathFloor(predictedLot / step) * step;
    }

double notionalValue = predictedLot * spIs.tickValue * (1.0 / spIs.tickSize) * spIs.point * spIs.contractSize;

     double equity = AccountInfoDouble(ACCOUNT_EQUITY);
     if(equity > 0.0)
     {
         double exposureRatio = (notionalValue / equity) * 100.0;
         LogPrint("[IS_EXPOSURE] sym=" + symbol +
                  " | predictedLot=" + DoubleToString(predictedLot, 4) +
                  " | contractSize=" + DoubleToString(spIs.contractSize, 4) +
                  " | notionalValue=" + DoubleToString(notionalValue, 2) +
                  " | equity=" + DoubleToString(equity, 2) +
                  " | exposure%=" + DoubleToString(exposureRatio, 2) + "%",
                  LOG_LEVEL_DEBUG);
     }

    predictedLot = MathMin(predictedLot, maxLot);

    return predictedLot;
}

double IS_GetScaledLot(double baseLot, SScalingContext &ctx,
                       string symbol, ENUM_TIMEFRAMES tf, double minLot,
                       bool isSignalValid)   // NEW: signal validity (C2/C3 or entry trigger)
{
    // === TASK 3: NO FALLBACKS ===
    // Invalid lot remains invalid - no minLot fallback repair
    if(baseLot <= 0.0)
    {
        if(TC_IsValid())
        {
            TC_SetStage("SCALING");
            TraceLot("SCALED_ZEROBASE");
        }
        return 0.0;
    }

    if(!TC_IsValid())
    {
        LogPrint("[IS] Trade context invalid for scaling", LOG_LEVEL_DEBUG);
        return 0.0;
    }

    TC_SetStage("SCALING");

    SSymbolProfile spIs3 = SY_GetProfile(symbol);
    double maxLot = spIs3.volumeMax;
    double step = spIs3.volumeStep;
    
    if(maxLot <= 0.0 || step <= 0.0)
       return 0.0;

    double volatilityFactor = GetVolatilityMultiplier(symbol, tf);
    double positionFactor = GetPositionMultiplier(ctx);

    double scaledLot = SafeScaleLot(baseLot, minLot, maxLot, step,
                                     volatilityFactor, positionFactor,
                                     symbol, isSignalValid);  // PASS FLAG

    TraceLot("SCALED");

    return scaledLot;
}

#endif