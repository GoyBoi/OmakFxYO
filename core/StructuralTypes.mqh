//+------------------------------------------------------------------+
//|                                        StructuralTypes.mqh |
//|                        OmakFxYO — Shared Structural Type Definitions |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_STRUCTURALTYPES_MQH
#define OMAK_STRUCTURALTYPES_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Shared structural type definitions — extracted from StructuralStateEngine"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>       // Base types

//+------------------------------------------------------------------+
//| MarketStructureState — Primary Structure Enum                    |
//+------------------------------------------------------------------+
/**
 * MarketStructureState
 *
 * Central authority for market structure state.
 * Combines swing sequence (HH/HL or LL/LH) with displacement confirmation.
 *
 * STATES:
 *   MSS_BULLISH_STRONG — HH+HL sequence WITH displacement confirmed
 *   MSS_BULLISH_WEAK   — HH+HL sequence WITHOUT displacement
 *   MSS_BEARISH_STRONG — LL+LH sequence WITH displacement confirmed
 *   MSS_BEARISH_WEAK   — LL+LH sequence WITHOUT displacement
 *   MSS_RANGE          — No valid sequence (choppy/ranging)
 *
 * STATE TRANSITIONS:
 *   - STRONG → WEAK: Displacement fades
 *   - *_STRONG → RANGE: Structure broken without confirmation
 *   - RANGE → *_STRONG: New structure with displacement
 */
enum MarketStructureState
{
    MSS_UNINITIALIZED = -1,  // No swing data yet — pipeline not ready
    MSS_BULLISH_STRONG = 0,  // HH+HL with displacement confirmed
    MSS_BULLISH_WEAK,       // HH+HL without displacement
    MSS_BEARISH_STRONG,     // LL+LH with displacement confirmed
    MSS_BEARISH_WEAK,       // LL+LH without displacement
    MSS_RANGE              // No valid sequence (choppy/ranging)
};

enum MarketStrategy
{
    STRATEGY_TREND,        // Strong structure with displacement (HH+HL or LL+LH with confirmation)
    STRATEGY_RANGE,        // No valid sequence (choppy/ranging)
    STRATEGY_TRANSITION   // Weak structure, awaiting HTF confirmation
};

//+------------------------------------------------------------------+
//| SSE_Output — Output Data Structure                                |
//+------------------------------------------------------------------+
/**
 * SSE_Output
 *
 * Contains the evaluated market structure state and metadata.
 * This is the SINGLE SOURCE OF TRUTH for structure state.
 */
struct SSE_Output
{
    MarketStructureState state;       // Current structure state
    MarketStrategy strategy;         // Strategy router (TREND/RANGE/TRANSITION)
    bool externalBreak;               // External swing broken
    bool displacementConfirmed;       // Displacement validates break
    datetime lastUpdateTime;          // When state was computed
    ENUM_TIMEFRAMES timeframe;        // Timeframe analyzed

    //+------------------------------------------------------------------+
    //| Reset — Clear all fields to defaults                            |
    //+------------------------------------------------------------------+
    void Reset()
    {
       state = MSS_UNINITIALIZED;
       strategy = STRATEGY_RANGE;
       externalBreak = false;
       displacementConfirmed = false;
       lastUpdateTime = 0;
       timeframe = PERIOD_CURRENT;
    }
};

//+------------------------------------------------------------------+
//| STRATEGY RESOLUTION — Pure functions on SSE state                |
//+------------------------------------------------------------------+

/**
 * SSE_GetStrategy — Convert state to strategy router
 *
 * Maps SSE state to hierarchical strategy:
 *   - STRONG state → TREND (confirmation present)
 *   - RANGE state → RANGE
 *   - WEAK state → TRANSITION (awaiting confirmation)
 *
 * @param sseState SSE market structure state
 * @return MarketStrategy
 */
MarketStrategy SSE_GetStrategy(MarketStructureState sseState)
{
    if(sseState == MSS_BULLISH_STRONG || sseState == MSS_BEARISH_STRONG)
    {
        return STRATEGY_TREND;        // Confirmation Mode
    }
    else if(sseState == MSS_RANGE)
    {
        return g_trueTTradesConfig.allowRangeAsTransition ? STRATEGY_TRANSITION : STRATEGY_RANGE;
    }
    else
    {
        return STRATEGY_TRANSITION;   // WEAK states = Anticipation
    }
}

/**
 * SSE_OutputToStrategy — Get strategy from SSE output
 *
 * @param sse SSE output
 * @return MarketStrategy
 */
MarketStrategy SSE_OutputToStrategy(const SSE_Output &sse)
{
    return SSE_GetStrategy(sse.state);
}

// REGRESSION_GUARD_V52_5_STRUCTURAL_TYPES

#endif // OMAK_STRUCTURALTYPES_MQH
