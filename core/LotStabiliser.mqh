//+------------------------------------------------------------------+
//|                                        LotStabiliser.mqh        |
//|                                    OmakFxYO — Lot Stabiliser |
//+------------------------------------------------------------------+
#ifndef OMAK_LOTSTABILISER_MQH
#define OMAK_LOTSTABILISER_MQH

double StabiliseLot(double rawLot, double minLot, double maxLot, double step, string symbol = "")
{
    double before = rawLot;

    if(rawLot <= 0.0)
    {
        LogPrint("[LOT_STABILISER] Raw lot <=0 | symbol="+symbol, LOG_LEVEL_WARN);
        return 0.0;
    }

    double lot = rawLot;

    if(step > 0.0)
        lot = MathFloor(lot / step + 0.5) * step;

    if(lot <= 0.0)
    {
        LogPrint("[LOT_STABILISER] Lot rounded to zero | raw=" + DoubleToString(rawLot, 5) +
                 " | step=" + DoubleToString(step, 5) + " | symbol=" + symbol, LOG_LEVEL_WARN);
        return 0.0;
    }

    if(lot > maxLot)
    {
        LogPrint("[LOT_STABILISER] Above maxLot | " + DoubleToString(lot, 5) + " > " +
                 DoubleToString(maxLot, 5) + " | symbol=" + symbol, LOG_LEVEL_WARN);
        lot = maxLot;
    }

    if(MathAbs(before - lot) > 0.00001)
        LogPrint("[LOT_STABILISER] Adjusted | before=" + DoubleToString(before, 5) +
                 " | after=" + DoubleToString(lot, 5) + " | symbol=" + symbol, LOG_LEVEL_INFO);

    // Derive precision from step to support brokers with non-standard step sizes (e.g., 0.001)
    int precision = 2;
    double stepTemp = step;
    while(stepTemp < 1.0 && precision < 8)
    {
        stepTemp *= 10.0;
        precision++;
    }

    LogPrint("[LOT_STABILISER] FINAL lot=" + DoubleToString(lot, precision) + " | raw=" + DoubleToString(rawLot, 5) +
             " | min=" + DoubleToString(minLot, precision) + " | step=" + DoubleToString(step, precision) + " | symbol=" + symbol,
             LOG_LEVEL_DEBUG);
    return NormalizeDouble(lot, precision);
} // REGRESSION_GUARD_V52.5_STABILISER_LOT — no upward minLot force; returns 0.0 on zero/negative

//+------------------------------------------------------------------+
//| IsLotTradeable — Check if broker minimum is affordable            |
//| Uses OrderCalcProfit() for broker-real risk projection (not       |
//| simplified slPoints*tickValue) to support all calc modes:         |
//| forex, crypto, synthetic, index CFDs, cent/micro/nano accounts.   |
//| Returns true if minLot risk is within account risk budget.        |
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

    // Use OrderCalcProfit for broker-real loss projection when we have prices
    if(entryPrice > 0.0 && slPrice > 0.0 && symbol != "")
    {
        ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        double profit = 0.0;
        if(OrderCalcProfit(orderType, symbol, minLot, entryPrice, slPrice, profit))
        {
            minRisk = MathAbs(profit);
        }
        else
        {
            // OrderCalcProfit failed — fall back to simplified formula
            if(slPoints > 0.0 && tickValue > 0.0)
                minRisk = minLot * slPoints * tickValue;
            else
                return false;
        }
    }
    else
    {
        // No prices available — use simplified formula as approximate check
        if(slPoints <= 0.0 || tickValue <= 0.0)
            return false;
        minRisk = minLot * slPoints * tickValue;
    }

    if(minRisk <= 0.0)
       return false;

    if(minRisk <= riskAmount)
    {
       LogPrint("[RISK_TRADEABLE] minLotRisk=" + DoubleToString(minRisk, 2) +
                " <= riskAmount=" + DoubleToString(riskAmount, 4) +
                " | symbol=" + symbol +
                " | method=" + (entryPrice > 0.0 ? "OrderCalcProfit" : "formula"),
                LOG_LEVEL_DEBUG);
       return true;
    }

    string methodStr = (entryPrice > 0.0 && slPrice > 0.0 && symbol != "") ? "OrderCalcProfit" : "formula";
    LogPrint("[RISK_NOT_TRADEABLE] minLot risk=" + DoubleToString(minRisk, 2) +
             " exceeds allocated risk=" + DoubleToString(riskAmount, 4) +
             " | symbol=" + symbol +
             " | method=" + methodStr, LOG_LEVEL_WARN);
    return false;
}

#endif