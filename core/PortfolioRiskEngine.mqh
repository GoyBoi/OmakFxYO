//+------------------------------------------------------------------+
 //| PortfolioRiskEngine.mqh                                           |
 //| Omak FxYO — Cross-Symbol Risk Normalization                      |
 //|                                                                  |
 //| ROLE: Aggregates exposure across ALL symbols and enforces        |
 //| portfolio-level risk limits. Sits BEFORE TradeGovernor checks.    |
 //| B4 INTEGRATION: Traceable Trade Lifecycle                        |
 //+------------------------------------------------------------------+
#ifndef OMAK_PORTFOLIORISKENGINE_MQH
#define OMAK_PORTFOLIORISKENGINE_MQH

#include <OmakFxYO/core/CoreTypes.mqh>



//+------------------------------------------------------------------+
//| Portfolio context — cross-symbol exposure snapshot               |
//+------------------------------------------------------------------+
struct SPortfolioContext
{
   double totalExposurePercent;
   int    totalPositions;
   double totalFloatingProfit;
};

//+------------------------------------------------------------------+
//| PR_BuildContext — Aggregate all open positions across symbols    |
//+------------------------------------------------------------------+
SPortfolioContext PR_BuildContext()
{
   SPortfolioContext ctx;
   ctx.totalExposurePercent = 0.0;
   ctx.totalPositions = 0;
   ctx.totalFloatingProfit = 0.0;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0)
      return ctx;

   int total = PositionsTotal();

   // Iterate backwards for safe position access
   for(int i = total - 1; i >= 0; i--)
   {
      if(i < 0 || i >= total)
         continue;
         
      string posSymbol = PositionGetSymbol(i);
      if(posSymbol == NULL || posSymbol == "")
         continue;

      ctx.totalPositions++;

      double volume = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double currentPrice = (posType == POSITION_TYPE_BUY)
                            ? SymbolInfoDouble(posSymbol, SYMBOL_BID)
                            : SymbolInfoDouble(posSymbol, SYMBOL_ASK);
      double point = SymbolInfoDouble(posSymbol, SYMBOL_POINT);

      if(point <= 0.0)
         continue;

      if(posType == POSITION_TYPE_BUY)
         ctx.totalFloatingProfit += (currentPrice - openPrice) * volume / point;
      else
         ctx.totalFloatingProfit += (openPrice - currentPrice) * volume / point;

      // Calculate risk per trade: R = |entry - SL|
      double stopDistance = 0.0;
      if(currentSL > 0.0)
         stopDistance = MathAbs(openPrice - currentSL);
      else
         stopDistance = point * 100; // Default 100 points if no SL
      
      // Calculate risk amount based on stop distance
      double tickValue = SymbolInfoDouble(posSymbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(posSymbol, SYMBOL_TRADE_TICK_SIZE);
      
      if(tickSize > 0.0 && tickValue > 0.0)
      {
         double riskAmount = (stopDistance / tickSize) * tickValue * volume;
         if(balance > 0.0)
            ctx.totalExposurePercent += (riskAmount / balance) * 100.0;
      }
   }

   LogDebug("[PORTFOLIO] Exposure=" + DoubleToString(ctx.totalExposurePercent, 2) + "% | Positions=" + IntegerToString(ctx.totalPositions));
   return ctx;
}

//+------------------------------------------------------------------+
//| PR_CanOpenNewTrade — Portfolio-level gate                        |
//+------------------------------------------------------------------+
bool PR_CanOpenNewTrade(SPortfolioContext &ctx)
{
   if(ctx.totalExposurePercent > 5.0)
      return false;

   if(ctx.totalPositions >= 4)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| PR_GetExposureSummary — Human-readable exposure report           |
//+------------------------------------------------------------------+
string PR_GetExposureSummary(const SPortfolioContext &ctx)
{
   return "Portfolio: " + IntegerToString(ctx.totalPositions) + " positions | " +
          "Exposure: " + DoubleToString(ctx.totalExposurePercent, 2) + "% | " +
          "Floating P/L: " + DoubleToString(ctx.totalFloatingProfit, 2);
}

#endif // OMAK_PORTFOLIORISKENGINE_MQH
