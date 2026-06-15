//+------------------------------------------------------------------+
//|                                        ConfluenceEngine.mqh |
//|                         OmakFxYO — Confluence Engine |
//+------------------------------------------------------------------+
#ifndef OMAK_CONFLUENCEENGINE_MQH
#define OMAK_CONFLUENCEENGINE_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Confluence Engine — SMT Divergence Gate (C2 Only)"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>

//+------------------------------------------------------------------+
//| HasSMTDivergence — SMT Divergence Gate (C2 Only)                |
//+------------------------------------------------------------------+
/**
 * Checks SMT Divergence between the primary symbol and a correlated symbol.
 *
 * SMT Divergence: The correlated asset sweeps a low/high while the primary
 * asset fails to confirm the same sweep. This indicates institutional
 * divergence and validates a C2 reversal setup.
 *
 * Applies only to C2 (MODE_ANTICIPATION). Not required for C3/C4.
 *
 * @param corrSym   Correlated symbol (e.g., "XAGUSD" for "XAUUSD")
 * @param tf        Timeframe to evaluate (typically Structure TF)
 * @param bullish   true = bullish divergence check, false = bearish
 *
 * @return true if SMT Divergence detected, false otherwise
 */
bool HasSMTDivergence(string corrSym, ENUM_TIMEFRAMES tf, bool bullish)
{
   double primLow  = iLow(_Symbol, tf, 1);
   double corrLow  = iLow(corrSym, tf, 1);
   double primPrevLow = iLow(_Symbol, tf, 2);
   double corrPrevLow = iLow(corrSym, tf, 2);

   double primHigh = iHigh(_Symbol, tf, 1);
   double corrHigh = iHigh(corrSym, tf, 1);
   double primPrevHigh = iHigh(_Symbol, tf, 2);
   double corrPrevHigh = iHigh(corrSym, tf, 2);

   if(bullish)
   {
      // Primary asset sweeps Low, Correlated asset fails to confirm
      if(primLow < primPrevLow && corrLow > corrPrevLow)
      {
         LogPrint("[SMT_DIVERGENCE_PASS] BULLISH | " + _Symbol +
                   " low=" + DoubleToString(primLow, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
                   " < prevLow=" + DoubleToString(primPrevLow, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
                   " | " + corrSym +
                   " low=" + DoubleToString(corrLow, (int)SymbolInfoInteger(corrSym, SYMBOL_DIGITS)) +
                   " > prevLow=" + DoubleToString(corrPrevLow, (int)SymbolInfoInteger(corrSym, SYMBOL_DIGITS)), LOG_LEVEL_INFO);
          return true;
      }
   }
   else
   {
      // Primary asset sweeps High, Correlated asset fails to confirm
      if(primHigh > primPrevHigh && corrHigh < corrPrevHigh)
      {
         LogPrint("[SMT_DIVERGENCE_PASS] BEARISH | " + _Symbol +
                   " high=" + DoubleToString(primHigh, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
                   " > prevHigh=" + DoubleToString(primPrevHigh, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) +
                   " | " + corrSym +
                   " high=" + DoubleToString(corrHigh, (int)SymbolInfoInteger(corrSym, SYMBOL_DIGITS)) +
                   " < prevHigh=" + DoubleToString(corrPrevHigh, (int)SymbolInfoInteger(corrSym, SYMBOL_DIGITS)), LOG_LEVEL_INFO);
          return true;
      }
   }

   LogPrint("[SMT_DIVERGENCE_FAIL] " + (bullish ? "BULLISH" : "BEARISH") +
             " | " + _Symbol + " / " + corrSym + " — no divergence detected", LOG_LEVEL_INFO);
   return false;
}

//+------------------------------------------------------------------+
//| GetCorrelatedSymbol — SMT correlated asset lookup                |
//+------------------------------------------------------------------+
/**
 * AGENTS.md §XVIII: Returns the SMT-correlated symbol for a given primary symbol.
 * If the symbol has no defined correlated pair (e.g., Vix75), returns "".
 * This allows SMT to act as a soft confluence check — symbols without
 * correlations automatically pass the SMT gate.
 *
 * Correlated pairs:
 *   EURUSD ↔ GBPUSD
 *   USDJPY ↔ USDCHF
 *   XAUUSD ↔ XAGUSD
 *
 * @param primarySymbol The symbol to find a correlate for
 * @return Correlated symbol, or "" if none exists
 */
string GetCorrelatedSymbol(string primarySymbol)
{
   string sym = primarySymbol;
   StringToUpper(sym);

   // Generic base-pair matching: strip broker suffixes (micro, mini, .m, etc.)
   // by checking if the input contains any known base pair.
   struct SPairMap { string base; string correlate; };
   SPairMap pairs[] = {
      {"EURUSD", "GBPUSD"},
      {"GBPUSD", "EURUSD"},
      {"USDJPY", "USDCHF"},
      {"USDCHF", "USDJPY"},
      {"XAUUSD", "XAGUSD"},
      {"XAGUSD", "XAUUSD"}
   };

   for(int i = 0; i < ArraySize(pairs); i++)
   {
      if(StringFind(sym, pairs[i].base) >= 0)
         return pairs[i].correlate;
   }

   return "";
}

//+------------------------------------------------------------------+
//| IsSMTApplicable — Checks if symbol has a valid SMT correlated pair |
//+------------------------------------------------------------------+
/**
 * Returns true if the symbol has a defined correlated pair, false otherwise.
 * When false, SMT divergence should be treated as neutral/not required.
 */
bool IsSMTApplicable(string symbol)
{
   return (GetCorrelatedSymbol(symbol) != "");
}

//+------------------------------------------------------------------+
//| TIERED REVERSAL QUALITY GATE — C2                                     |
//+------------------------------------------------------------------+
/**
 * Implements tiered confirmation logic for C2:
 * - Correlated assets require SMT divergence (Gate 3).
 * - Solo assets (crypto/synthetics) must prove aggressive displacement
 *   via a swift V-shaped recovery (1–3 candles) through the opening price.
 *
 * Law: Solo assets must displace through the C1 range boundary
 * within ≤3 structure TF candles, with displacement > 2× spread.
 */

//+------------------------------------------------------------------+
//| IsAssetCorrelated — Whether symbol has a known SMT correlate    |
//+------------------------------------------------------------------+
bool IsAssetCorrelated(string symbol)
{
   return IsSMTApplicable(symbol);
}

//+------------------------------------------------------------------+
//| SMT_CheckDivergence — Wraps HasSMTDivergence for signal context |
//+------------------------------------------------------------------+
bool SMT_CheckDivergence(const SLockedSignal &sig)
{
   ENUM_TIMEFRAMES stf  = GetStructureTF(sig.branchId);
   bool            bullish = (sig.direction == DIRECTION_BUY);
   string          corrSym = GetCorrelatedSymbol(sig.symbol);

   return HasSMTDivergence(corrSym, stf, bullish);
}

//+------------------------------------------------------------------+
//| GetCISDRecoveryTime — Bars from C2 sweep to C1 range recovery   |
//+------------------------------------------------------------------+
/**
 * Uses m_detectionTime (seeded at signal detection) to locate the C2 bar
 * on the Structure TF via iBarShift, then counts forward to recovery.
 * This is deterministic and avoids fragile price-scanning heuristics.
 * Falls back to lockTime if detectionTime is not set.
 */
int GetCISDRecoveryTime(const SLockedSignal &sig)
{
   ENUM_TIMEFRAMES stf  = GetStructureTF(sig.branchId);
   string          sym  = sig.symbol;
   bool            bull = (sig.direction == DIRECTION_BUY);
   double          target = bull ? sig.c1_low : sig.c1_high;

   datetime anchorTime = sig.m_detectionTime;
   if(anchorTime <= 0) anchorTime = sig.lockTime;
   if(anchorTime <= 0) return 999;

   int c2Bar = iBarShift(sym, stf, anchorTime);
   if(c2Bar < 0) return 999;

   // If C2 bar already closed inside C1 range, recovery was instant
   double c2Close = iClose(sym, stf, c2Bar);
   bool c2Recovered = bull ? (c2Close >= target) : (c2Close <= target);
   if(c2Recovered) return 0;

   // Count bars forward (lower index = newer) until recovery
   for(int i = c2Bar - 1; i >= 0; i--)
   {
      double cls = iClose(sym, stf, i);
      if(bull && cls >= target)
         return (c2Bar - i);
      if(!bull && cls <= target)
         return (c2Bar - i);
   }

   return 999;
}

//+------------------------------------------------------------------+
//| GetDisplacementStrength — Distance from C2 extreme to C1 edge  |
//+------------------------------------------------------------------+
double GetDisplacementStrength(const SLockedSignal &sig)
{
   if(sig.direction == DIRECTION_BUY)
      return MathAbs(sig.c2_low - sig.c1_low);
   else
      return MathAbs(sig.c2_high - sig.c1_high);
}

//+------------------------------------------------------------------+
//| ValidateC2ReversalSincerity — Tiered Reversal Quality Gate       |
//+------------------------------------------------------------------+
/**
 * VERBATIM REPAIR: Task 3 — Tiered Reversal Quality Gate (C2)
 *
 * Correlated assets → SMT divergence gate.
 * Solo assets      → aggressive V-Shape displacement gate.
 */
bool ValidateC2ReversalSincerity(const SLockedSignal &sig)
{
    bool isCorrelated = IsAssetCorrelated(sig.symbol);

    if(isCorrelated)
    {
        return SMT_CheckDivergence(sig);
    }

    // Solo Asset Law: Aggressive Displacement
    int    barsToRecover = GetCISDRecoveryTime(sig);
    double displacement  = GetDisplacementStrength(sig);
    double spread        = sig.m_spreadAtLock;

    if(barsToRecover <= 3 && displacement > (spread * 2.0))
    {
        LogPrint("[C2_VSHAPE_PASS] Solo asset V-Shape confirmed | GUID:" + IntegerToString(sig.m_guid) +
                 " | barsToRecover=" + IntegerToString(barsToRecover) +
                 " | displacement=" + DoubleToString(displacement, (int)SymbolInfoInteger(sig.symbol, SYMBOL_DIGITS)) +
                 " | spread=" + DoubleToString(spread, (int)SymbolInfoInteger(sig.symbol, SYMBOL_DIGITS)), LOG_LEVEL_INFO);
        return true;
    }

    LogPrint("[C2_REJECT] Solo asset slow recovery | GUID:" + IntegerToString(sig.m_guid) +
             " | barsToRecover=" + IntegerToString(barsToRecover) +
             " | displacement=" + DoubleToString(displacement, (int)SymbolInfoInteger(sig.symbol, SYMBOL_DIGITS)) +
             " | spread=" + DoubleToString(spread, (int)SymbolInfoInteger(sig.symbol, SYMBOL_DIGITS)), LOG_LEVEL_WARN);
    return false;
}

#endif // OMAK_CONFLUENCEENGINE_MQH
