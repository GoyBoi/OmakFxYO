//+------------------------------------------------------------------+
//| GeometryEngine.mqh — Species-Specific Geometry (§V)             |
//| OmakFxYO — TTFM Fractal Execution Engine                         |
//| Defines distinct price logic for each entry species (C2, C3, C4)  |
//+------------------------------------------------------------------+
#ifndef OMAK_GEOMETRYENGINE_MQH
#define OMAK_GEOMETRYENGINE_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Species-Specific Geometry Engine for OmakFxYO"

// Calculate HTF Equilibrium (Anchor TF midpoint)
// Branch A anchor = D1, Branch B anchor = W1
double CalculateHTFEquilibrium(const string symbol, ENUM_EXECUTION_BRANCH branch)
{
    ENUM_TIMEFRAMES anchorTF = (branch == BRANCH_INTRADAY) ? PERIOD_D1 : PERIOD_W1;
    double htfHigh = iHigh(symbol, anchorTF, 0);
    double htfLow  = iLow(symbol, anchorTF, 0);
    if(htfHigh <= 0.0 || htfLow <= 0.0)
        return 0.0;
    return (htfHigh + htfLow) / 2.0;
}

// Get New Protected Swing extreme on Structure TF
double GetNewProtectedSwing(const string symbol, ENUM_EXECUTION_BRANCH branch, bool isLong)
{
    ENUM_TIMEFRAMES structTF = GetStructureTF(branch);
    if(isLong)
        return iLow(symbol, structTF, 1);   // Protected low for buy
    else
        return iHigh(symbol, structTF, 1);  // Protected high for sell
}

// VERBATIM REPAIR: Species-Specific Geometry (§V)
struct SExecutionGeometry { double sl; double tp; double riskDist; };

// C2: Reversal - Anchor to Manipulation Leg Extreme
SExecutionGeometry GetC2Geometry(const SLockedSignal &sig)
{
    SExecutionGeometry geo;
    geo.sl = GetManipulationLegExtreme(sig.symbol, sig.entryTF, (sig.direction == DIRECTION_BUY));
    geo.tp = CalculateHTFEquilibrium(sig.symbol, sig.branchId);
    geo.riskDist = MathAbs(sig.entry_price - geo.sl);
    return geo;
}

// C3: Continuation - Anchor to New Protected Swing
SExecutionGeometry GetC3Geometry(const SLockedSignal &sig)
{
    SExecutionGeometry geo;
    geo.sl = GetNewProtectedSwing(sig.symbol, sig.branchId, (sig.direction == DIRECTION_BUY));
    geo.tp = sig.htfExpansionObjective;
    geo.riskDist = MathAbs(sig.entry_price - geo.sl);
    return geo;
}

#endif // OMAK_GEOMETRYENGINE_MQH
