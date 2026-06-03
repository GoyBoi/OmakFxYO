//+------------------------------------------------------------------+
//|                                        SymbolClassVolatility.mqh |
//|                        OmakFxYO — Symbol Class Volatility Config |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_SYMBOLCLASSVOLATILITY_MQH
#define OMAK_SYMBOLCLASSVOLATILITY_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Symbol class volatility multipliers — passive filter only"

#include <OmakFxYO/core/CoreTypes.mqh>
#include <OmakFxYO/core/SpreadFilter.mqh>

//+------------------------------------------------------------------+
//| SSymbolClassVolatility — Per-symbol-class ATR multiplier         |
//|                                                                  |
//| NOTE: This is a PASSIVE FILTER only.                             |
//| These multipliers do NOT influence trend direction or structure. |
//| They are tolerance bounds for structural validity only.          |
//+------------------------------------------------------------------+
struct SSymbolClassVolatility
{
    double maxATRMultiplier;  // Maximum ATR ratio allowed for this class

    void Reset()
    {
        maxATRMultiplier = 2.0;
    }
};

//+------------------------------------------------------------------+
//| GetVolatilityConfig — Return per-symbol-class multiplier         |
//|                                                                  |
//| Default Multipliers (structure-aware tolerance bounds only):     |
//|   Forex      → 2.0                                               |
//|   Metals     → 2.5                                               |
//|   Indices    → 1.8                                               |
//|   Crypto     → 3.0                                               |
//|   Synthetic  → 1.2                                               |
//|   Default    → 2.0                                               |
//|                                                                  |
//| This is a PASSIVE filter. It does NOT:                           |
//|   - Influence trend direction                                    |
//|   - Interact with ATR engine                                     |
//|   - Modify structure logic                                       |
//+------------------------------------------------------------------+
SSymbolClassVolatility GetVolatilityConfig(const string symbol)
{
    SSymbolClassVolatility config;
    config.Reset();

    ENUM_SYMBOL_CLASS symbolClass = DetectSymbolClass(symbol);

    switch(symbolClass)
    {
        case CLASS_FOREX:
            config.maxATRMultiplier = 2.0;   // Forex tolerance
            break;
        case CLASS_METAL:
            config.maxATRMultiplier = 2.5;   // Metals tolerance
            break;
        case CLASS_INDEX:
            config.maxATRMultiplier = 1.8;   // Indices tolerance
            break;
        case CLASS_CRYPTO:
            config.maxATRMultiplier = 3.0;   // Crypto tolerance
            break;
        case CLASS_SYNTHETIC:
            config.maxATRMultiplier = 1.2;   // Synthetic tolerance
            break;
        default:
            config.maxATRMultiplier = 2.0;   // Default tolerance
            break;
    }

    return config;
}

#endif // OMAK_SYMBOLCLASSVOLATILITY_MQH
