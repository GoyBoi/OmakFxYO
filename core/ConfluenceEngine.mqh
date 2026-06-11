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

#endif // OMAK_CONFLUENCEENGINE_MQH
