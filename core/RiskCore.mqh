//+------------------------------------------------------------------+
//|                                              RiskCore.mqh |
//|                                    OmakFxYO — Unified Risk Authority |
//+------------------------------------------------------------------+
#property strict

#ifndef OMAK_RISKCORE_MQH
#define OMAK_RISKCORE_MQH

#include <OmakFxYO/core/ModeResolver.mqh>

//+------------------------------------------------------------------+
//| ResolveActiveRiskPct — Mode-adjusted risk percentage              |
//| Unified Risk Authority (§VII): Both affordability gating and      |
//| execution sizing use the same mode-adjusted percentage to         |
//| prevent budget discrepancy between pre-check and lot calculator.  |
//| ANTICIPATION=60% of base, CONFIRMATION=100% of base.             |
//+------------------------------------------------------------------+
double ResolveActiveRiskPct(const int mode, double baseRisk) {
    double modeFactor = (mode == MODE_ANTICIPATION) ? 0.6 : 1.0;
    return baseRisk * modeFactor;
}

#endif
