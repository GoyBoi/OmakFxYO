//+------------------------------------------------------------------+
//|                                          LotStabiliser.mqh       |
//+------------------------------------------------------------------+
//| Final lot normalization and broker compliance                    |
//+------------------------------------------------------------------+
#property strict

#ifndef OMAK_LOTSTABILISER_MQH
#define OMAK_LOTSTABILISER_MQH

#include <OmakFxYO/core/RiskManager.mqh>

//+------------------------------------------------------------------+
//| StabiliseLot - Ensures final lot meets broker requirements      |
//+------------------------------------------------------------------+
bool StabiliseLot(double &lot, string &errorMsg)
{
   SSymbolProfile profile = SY_GetProfile(_Symbol);
   if(!profile.isValid)
   {
      errorMsg = "Failed to get symbol profile";
      return false;
   }

   double minLot = profile.volumeMin;
   double maxLot = profile.volumeMax;
   double lotStep = profile.volumeStep;

   // Check minimum
   if(lot < minLot)
   {
      if(minLot > 0)
      {
         lot = minLot;
          LogPrint("[LOT_STABILISER] Adjusted to min lot: " + DoubleToString(minLot), LOG_LEVEL_INFO);
      }
      else
      {
         errorMsg = "Minimum lot is zero";
         return false;
      }
   }

   // Check maximum
   if(lot > maxLot)
   {
      lot = maxLot;
       LogPrint("[LOT_STABILISER] Adjusted to max lot: " + DoubleToString(maxLot), LOG_LEVEL_INFO);
   }

   // Normalize to step
   lot = MathFloor(lot / lotStep + 0.5) * lotStep;
   lot = NormalizeDouble(lot, 2);

   // Final verification
   if(!IsLotTradeable(lot, errorMsg))
   {
      return false;
   }

   errorMsg = "";
   return true;
}

//+------------------------------------------------------------------+
//| IsLotTradeable - Verify broker can accept this lot (broker compliance)
//+------------------------------------------------------------------+
bool IsLotTradeable(double lot, string &errorMsg)
{
   SSymbolProfile profile = SY_GetProfile(_Symbol);
   if(!profile.isValid)
   {
      errorMsg = "Failed to get symbol profile";
      return false;
   }

   double minLot = profile.volumeMin;
   double maxLot = profile.volumeMax;
   double lotStep = profile.volumeStep;

   if(lot < minLot - 1e-10)
   {
      errorMsg = StringFormat("Lot %.2f below minimum %.2f", lot, minLot);
      return false;
   }

   if(lot > maxLot + 1e-10)
   {
      errorMsg = StringFormat("Lot %.2f above maximum %.2f", lot, maxLot);
      return false;
   }

   double remainder = fmod(lot, lotStep);
   if(remainder > 1e-10 && (lotStep - remainder) > 1e-10)
   {
      errorMsg = StringFormat("Lot %.6f not a multiple of lot step %.6f", lot, lotStep);
      return false;
   }

   errorMsg = "";
   return true;
}

//+------------------------------------------------------------------+
//| StabiliseLot - Backward-compat 5-param overload (Prompt_P1 legacy) |
//+------------------------------------------------------------------+
bool StabiliseLot(double &lot, double minLot, double maxLot, double lotStep, const string symbol)
{
   if(lot < minLot)
   {
      if(minLot > 0)
         lot = minLot;
      else
         return false;
   }
   if(lot > maxLot)
      lot = maxLot;
   lot = MathFloor(lot / lotStep + 0.5) * lotStep;
   lot = NormalizeDouble(lot, 2);
   string errMsg = "";
   return IsLotTradeable(lot, errMsg);
}

//+------------------------------------------------------------------+
//| IsLotTradeable - Affordability check (backward-compat overload)  |
//| Uses OrderCalcProfit as authority; falls back to manual formula  |
//| only on OrderCalcProfit failure.                                  |
//+------------------------------------------------------------------+
bool IsLotTradeable(double slPoints, double tickValue, double minLot,
                    double accountEquity, double riskPercent, const string symbol,
                    double entryPrice = 0.0, double slPrice = 0.0, bool isBuy = true)
{
   if(minLot <= 0.0 || accountEquity <= 0.0 || riskPercent <= 0.0)
      return false;

   double riskAmount = accountEquity * (riskPercent / 100.0);
   if(riskAmount <= 0.0)
      return false;

   double minRisk = 0.0;

   // OrderCalcProfit as authority per new paradigm
   if(entryPrice > 0.0 && slPrice > 0.0)
   {
      ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double apiProfit = 0.0;
      if(OrderCalcProfit(orderType, symbol, minLot, entryPrice, slPrice, apiProfit))
      {
         minRisk = MathAbs(apiProfit);
          LogPrint("[ORDERCALCPROFIT] orderType="+EnumToString(orderType)+
                " symbol="+symbol+" volume="+DoubleToString(minLot,2)+
                " entryPrice="+DoubleToString(entryPrice,_Digits)+
                " stopLoss="+DoubleToString(slPrice,_Digits)+
                " rawProfit="+DoubleToString(apiProfit,2)+
                " [ISLOT_TRADEABLE]", LOG_LEVEL_INFO);
      }
      else
      {
         SSymbolProfile lsProf = SY_GetProfile(symbol);
         double tickSize = lsProf.isValid ? lsProf.tickSize : 0.0;
         double slDist = MathAbs(entryPrice - slPrice);
         if(tickSize > 0.0)
            minRisk = (slDist / tickSize) * tickValue * minLot;
         else
            return false;
          LogPrint("[ORDERCALCPROFIT_FAIL] OrderCalcProfit failed for IsLotTradeable, using formula fallback | rawProfit="+DoubleToString(minRisk,2), LOG_LEVEL_WARN);
      }
   }
   else
   {
      if(slPoints <= 0.0 || tickValue <= 0.0)
         return false;
       SSymbolProfile lsProf2 = SY_GetProfile(symbol);
       double tickSizeLS = lsProf2.isValid ? lsProf2.tickSize : 0.0;
       double pointLS = lsProf2.isValid ? lsProf2.point : 0.0;
       if(tickSizeLS > 0.0 && pointLS > 0.0)
          minRisk = minLot * (slPoints * pointLS / tickSizeLS) * tickValue;
      else
         return false;
   }

   if(minRisk <= 0.0)
      return false;

   if(minRisk <= riskAmount)
   {
      LogPrint("[RISK_TRADEABLE] minLotRisk="+DoubleToString(minRisk,2)+
               " <= riskAmount="+DoubleToString(riskAmount,4)+
               " | symbol="+symbol+" | method=OrderCalcProfit", LOG_LEVEL_DEBUG);
      return true;
   }

   LogPrint("[RISK_NOT_TRADEABLE] minLot risk="+DoubleToString(minRisk,2)+
            " exceeds allocated risk="+DoubleToString(riskAmount,4)+
            " | symbol="+symbol+" | method=OrderCalcProfit", LOG_LEVEL_WARN);
   return false;
}

#endif
