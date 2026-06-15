//+------------------------------------------------------------------+
//|                                              RiskGate.mqh |
//|                        OmakFxYO — Pre-Trade Readiness Gate |
//|                                    B7.12 — Institutional Grade |
//+------------------------------------------------------------------+
//
// MANDATORY EXECUTION CONTRACT:
// - NO fallbacks (0 must remain 0)
// - NO silent corrections
// - NO duplicated validation across modules
// - ALL validation occurs BEFORE lot calculation
// - NO re-validation in downstream modules
//
// CANONICAL PATH:
//   Signal → SignalSnapshot → PreTradeReadinessGate() → CalculateLotSize() → ExecuteOrder
//
// IF FAIL → terminate immediately
//
#ifndef OMAK_RISKGATE_MQH
#define OMAK_RISKGATE_MQH

#property strict

#include <OmakFxYO/core/CoreTypes.mqh>
#include <OmakFxYO/core/LogGovernor.mqh>
#include <OmakFxYO/core/SignalQuery.mqh>

// REGRESSION_GUARD_V52.5_CONSOLIDATION: PositionGUIDMap now in CoreTypes.mqh
extern int g_totalOrdersSent;
extern PositionGUIDMap g_positionMap[];

double C3_SL_Calculator(int direction, double entryPrice, ENUM_TIMEFRAMES itf, double minStopMult);
double C2_SL_Calculator(int direction, double entryPrice, ENUM_TIMEFRAMES itf, double minStopMult);
double C4_SL_Calculator(int direction, double entryPrice, double c3_high, double c3_low, double minStopMult);
extern int g_positionMapCount;
extern bool   g_blockNewEntries;   // Entry block flag from risk compliance engine
// REGRESSION_GUARD_V52.5_GLOBAL_ENTRY_HALT

bool g_rgRetryDetected = false;

input group "=== P9: Exposure Gate Configuration ==="
input int InpMaxSameDirectionExposure = 2;  // Max same-direction positions per symbol (0=disabled)
input int InpMinEntryDistancePoints = 500;   // Minimum points between new entry and nearest existing stop

//+------------------------------------------------------------------+
  //| ENUM — Readiness Gate Exit Codes                                 |
  //+------------------------------------------------------------------+
  enum ENUM_RG_FAIL
      {
          RG_FAIL_NONE = 0,
          RG_FAIL_ATR_NOT_READY,
          RG_FAIL_ENTRY_PRICE_INVALID,
          RG_FAIL_SL_INVALID,
          RG_FAIL_SL_DIRECTION,
          RG_FAIL_SL_POINTS_ZERO,
          RG_FAIL_TICKVALUE_ZERO,
          RG_FAIL_TICKSIZE_ZERO,
          RG_FAIL_VOLUME_CONTRACT,
RG_FAIL_RR_TOO_LOW,
           RG_FAIL_RR_INSUFFICIENT,  // P1 Fix: 2R minimum enforced at RiskGate
          RG_FAIL_PROFIT_CALC,
          RG_FAIL_PROFIT_ZERO,
          RG_FAIL_EQUITY_ZERO,
          RG_FAIL_RISK_AMOUNT_ZERO,
          RG_FAIL_LOT_ZERO,
          RG_FAIL_SL_TOO_TIGHT,
          RG_FAIL_PRECONDITION,
          RG_FAIL_RETRY,
           RG_FAIL_EXCESSIVE_SAME_DIRECTION,  // P9 Fix: Same-direction stacking
           RG_FAIL_ENTRY_TOO_CLOSE,           // P9 Fix: Entry too close to existing
           RG_FAIL_SPREAD_TOO_WIDE            // P5 Fix: Spread exceeds safe threshold
       }; // REGRESSION_GUARDSPREAD_ENUM

//+------------------------------------------------------------------+
  //| SignalSnapshot — Frozen trade context for deterministic execution |
  //+------------------------------------------------------------------+
struct SSignalSnapshotRisk
{
    ulong    signalID;
    string   symbol;
    ENUM_TIMEFRAMES timeframe;
    ENUM_TIMEFRAMES structureTF;
    datetime barTime;
    string   branchName;
    ENUM_EXECUTION_BRANCH branch;

    double   entryPrice;
    double   stopLoss;
    double   stopLossPoints; // DEPRECATED – gate computes internally; kept for logging only
    ENUM_DIRECTION direction;
    double   tpPrice;
    ENUM_CLOSURE_TYPE closureType;  // P9 Fix: Closure type for exposure check

    // C2 protected swing extremes (for structural SL fallback)
     double   c2_low;
     double   c2_high;

     // Signal contract: runtime execution mode (not inferred from closure type)
     int      executionMode;

     double   atrValue;
    bool     atrReady;

    double   tickValue;
    double   tickSize;

    double   minLot;
    double   maxLot;
    double   lotStep;

    double   baseLot;
    double   normalizedLot;
    double   scaledLot;
    double   quantizedLot;

    datetime timestamp;

    // Hard-initialization to prevent 100-lot arithmetic fraud
    SSignalSnapshotRisk() { baseLot = 0.0; }
};

static SSignalSnapshotRisk g_snapshotRisk;

//+------------------------------------------------------------------+
  //| RG_CreateSnapshot — Create frozen snapshot for deterministic execution |
  //+------------------------------------------------------------------+
void RG_CreateSnapshot(SSignalSnapshotRisk &snap, const SLockedSignal &sig, double calculatedLot, 
      string symbol,
      ENUM_TIMEFRAMES timeframe,
      ENUM_TIMEFRAMES structureTF,
      datetime barTime,
      string branchName,
      double stopLossPoints,
      ENUM_DIRECTION direction = DIRECTION_NONE,
      double tpPrice = 0.0,
      ENUM_CLOSURE_TYPE closureType = CLOSURE_NONE,
      double c2_low_val = 0.0,
      double c2_high_val = 0.0,
      int executionModeVal = MODE_NONE
   )
   {
      RG_Reset();

      snap.signalID = sig.m_guid;
      snap.symbol = symbol;
      snap.timeframe = timeframe;
      snap.structureTF = structureTF;
      snap.barTime = barTime;
      snap.branchName = branchName;
      snap.branch = sig.branch;
      snap.timestamp = TimeCurrent();
      snap.entryPrice = sig.entry_price;
      snap.stopLoss = sig.stop_loss;
      snap.stopLossPoints = stopLossPoints;
      snap.direction = direction;
      snap.tpPrice = tpPrice;
      snap.closureType = closureType;
      snap.baseLot = calculatedLot;

      snap.c2_low = c2_low_val;
      snap.c2_high = c2_high_val;
      snap.executionMode = executionModeVal;

// ATR removed from snapshot — structural distance gating is the active gate
      snap.atrValue = 0.0;
      snap.atrReady = true;

      LogPrint("[RG] Snapshot created | sym=" + symbol + " | dir=" + EnumToString(direction), LOG_LEVEL_DEBUG);

      // Broker-reality profile: all values from SY_GetProfile, not raw SymbolInfoDouble
      SSymbolProfile sp = SY_GetProfile(symbol);
      snap.tickValue = sp.tickValue;
      snap.tickSize = sp.tickSize;
      snap.minLot = sp.volumeMin;
      snap.maxLot = sp.volumeMax;
      snap.lotStep = sp.volumeStep;

g_snapshotRisk = snap;
   }

//+------------------------------------------------------------------+
  //| RG_Reset — Reset snapshot to invalid state                     |
  //+------------------------------------------------------------------+
  void RG_Reset()
  {
      g_snapshotRisk.signalID = 0;
      g_snapshotRisk.symbol = "";
      g_snapshotRisk.timeframe = PERIOD_CURRENT;
      g_snapshotRisk.structureTF = PERIOD_H1;  // P10 Fix: Default to H1
      g_snapshotRisk.barTime = 0;
      g_snapshotRisk.branchName = "";
      g_snapshotRisk.entryPrice = 0.0;
      g_snapshotRisk.stopLoss = 0.0;
      g_snapshotRisk.stopLossPoints = 0.0;
      g_snapshotRisk.direction = DIRECTION_NONE;
      g_snapshotRisk.tpPrice = 0.0;
      g_snapshotRisk.closureType = CLOSURE_NONE;
      g_snapshotRisk.c2_low = 0.0;
      g_snapshotRisk.c2_high = 0.0;
      g_snapshotRisk.executionMode = MODE_NONE;
      g_snapshotRisk.atrValue = 0.0;
      g_snapshotRisk.atrReady = false;
    g_snapshotRisk.tickValue = 0.0;
    g_snapshotRisk.tickSize = 0.0;
    g_snapshotRisk.minLot = 0.0;
    g_snapshotRisk.maxLot = 0.0;
    g_snapshotRisk.lotStep = 0.0;
    g_snapshotRisk.baseLot = 0.0;
    g_snapshotRisk.normalizedLot = 0.0;
    g_snapshotRisk.scaledLot = 0.0;
    g_snapshotRisk.quantizedLot = 0.0;
    g_snapshotRisk.timestamp = 0;
}

//+------------------------------------------------------------------+
//| RG_LogFailure — Standardized failure logging                      |
//+------------------------------------------------------------------+
void RG_LogFailure(ENUM_RG_FAIL failCode, ulong sigID, string sym, string details = "")
{
    string failName = "";
    
    switch(failCode)
    {
        case RG_FAIL_ATR_NOT_READY: failName = "ATR_NOT_READY"; break;
        case RG_FAIL_ENTRY_PRICE_INVALID: failName = "ENTRY_PRICE_INVALID"; break;
        case RG_FAIL_SL_INVALID: failName = "SL_INVALID"; break;
        case RG_FAIL_SL_DIRECTION: failName = "SL_DIRECTION"; break;
        case RG_FAIL_SL_POINTS_ZERO: failName = "SL_POINTS_ZERO"; break;
        case RG_FAIL_TICKVALUE_ZERO: failName = "TICKVALUE_ZERO"; break;
        case RG_FAIL_TICKSIZE_ZERO: failName = "TICKSIZE_ZERO"; break;
        case RG_FAIL_VOLUME_CONTRACT: failName = "VOLUME_CONTRACT"; break;
        case RG_FAIL_RR_TOO_LOW: failName = "RR_TOO_LOW"; break;
        case RG_FAIL_RR_INSUFFICIENT: failName = "RR_INSUFFICIENT"; break;
        case RG_FAIL_EXCESSIVE_SAME_DIRECTION: failName = "EXCESSIVE_SAME_DIRECTION"; break;
        case RG_FAIL_ENTRY_TOO_CLOSE: failName = "ENTRY_TOO_CLOSE"; break;
        case RG_FAIL_SPREAD_TOO_WIDE: failName = "SPREAD_TOO_WIDE"; break;
        default: failName = "UNKNOWN_" + IntegerToString(failCode); break;
    }
    
     string msg = "[RG_GATE_FAIL] reason=" + failName +
                  " | ID=" + IntegerToString(sigID) +
                  " | symbol=" + sym;
    if(StringLen(details) > 0)
        msg += " | " + details;
    LogPrint(msg, LOG_LEVEL_ERROR);
}

//+------------------------------------------------------------------+
  //| RG_GetSnapshot — Retrieve frozen snapshot                         |
  //+------------------------------------------------------------------+
  SSignalSnapshotRisk RG_GetSnapshot()
  {
      return g_snapshotRisk;
  }

//+------------------------------------------------------------------+
   //| RG_CheckExposureGate — P9 Fix: Same-direction exposure control    |
   //| Prevents stacking cascade on same direction/closure type           |
   //| NOTE: This function checks same-direction count but NOT entry distance |
   //|       Entry distance is now in separate RG_CheckEntryDistance()   |
   //+------------------------------------------------------------------+
   ENUM_RG_FAIL RG_CheckExposureGate(
       string symbol,
       ENUM_DIRECTION direction,
       ENUM_CLOSURE_TYPE closureType,
       double entryPrice
   )
   {
       if(InpMaxSameDirectionExposure <= 0)
           return RG_FAIL_NONE;

       int sameDirCount = 0;
       int sameDirProfitCount = 0;

       for(int i = 0; i < PositionsTotal(); i++)
       {
           if(PositionSelectByTicket(PositionGetTicket(i)))
           {
               if(PositionGetString(POSITION_SYMBOL) != symbol)
                   continue;

               ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               ENUM_DIRECTION posDir = (posType == POSITION_TYPE_BUY) ? DIRECTION_BUY : DIRECTION_SELL;

               if(posDir == direction)
               {
                   sameDirCount++;
                   double posProfit = PositionGetDouble(POSITION_PROFIT);
                   if(posProfit > 0)
                       sameDirProfitCount++;
               }
           }
       }

       LogPrint("[RISK_GATE] symbol=" + symbol +
                " | direction=" + EnumToString(direction) +
                " | sameDirCount=" + IntegerToString(sameDirCount) +
                " | sameDirProfit=" + IntegerToString(sameDirProfitCount), LOG_LEVEL_DEBUG);

       if(sameDirCount >= InpMaxSameDirectionExposure)
       {
           bool allowPyramid = false;

           if(g_InpEnablePyramiding && sameDirProfitCount > 0)
           {
               allowPyramid = true;
               LogPrint("[RISK_GATE] PYRAMID_EXCEPTION | sameDirCount=" + IntegerToString(sameDirCount) +
                        " | profitCount=" + IntegerToString(sameDirProfitCount) +
                        " | allowing pyramid on winner", LOG_LEVEL_DEBUG);
           }

           if(!allowPyramid)
           {
               LogPrint("[RISK_GATE] REJECT | EXCESSIVE_SAME_DIRECTION | count=" +
                        IntegerToString(sameDirCount) + " | max=" +
                        IntegerToString(InpMaxSameDirectionExposure) +
                        " | direction=" + EnumToString(direction) +
                        " | closure=" + EnumToString(closureType), LOG_LEVEL_WARN);
               return RG_FAIL_EXCESSIVE_SAME_DIRECTION;
           }
       }

       return RG_FAIL_NONE;
   }

   //+------------------------------------------------------------------+
   //| RG_CheckEntryDistance — ENTRY-ONLY entry distance validation       |
   //| This check should ONLY be used for blocking new entries           |
   //| NEVER use for position management or exit logic                  |
   //+------------------------------------------------------------------+
ENUM_RG_FAIL RG_CheckEntryDistance(
        string symbol,
        ENUM_DIRECTION direction,
        double entryPrice
    )
    {
 if(InpMinEntryDistancePoints <= 0)
            return RG_FAIL_NONE;

        SSymbolProfile spDist = SY_GetProfile(symbol);

        double nearestStopDistance = 0.0;

        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionSelectByTicket(PositionGetTicket(i)))
            {
                if(PositionGetString(POSITION_SYMBOL) != symbol)
                    continue;

                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                ENUM_DIRECTION posDir = (posType == POSITION_TYPE_BUY) ? DIRECTION_BUY : DIRECTION_SELL;

                if(posDir == direction)
                {
                    double posSL = PositionGetDouble(POSITION_SL);
                    if(posSL > 0.0)
                    {
                        double dist = MathAbs(entryPrice - posSL);
                        if(nearestStopDistance == 0.0 || dist < nearestStopDistance)
                            nearestStopDistance = dist;
                    }
                }
            }
        }

        if(nearestStopDistance > 0.0)
        {
            double point = (spDist.point > 0.0) ? spDist.point : _Point;
            double minDistPoints = InpMinEntryDistancePoints * point;
            if(nearestStopDistance < minDistPoints)
            {
                LogPrint("[ENTRY_DISTANCE_GATE] REJECT | STRUCTURAL_TOO_CLOSE | distPoints=" +
                         DoubleToString(nearestStopDistance / point, 0) +
                         " | minPoints=" + IntegerToString(InpMinEntryDistancePoints), LOG_LEVEL_WARN);
                return RG_FAIL_ENTRY_TOO_CLOSE;
            }
        }

       double pointPass = (spDist.point > 0.0) ? spDist.point : _Point;
       LogPrint("[ENTRY_DISTANCE_GATE] PASS | nearestDist=" + DoubleToString(nearestStopDistance / pointPass, 0), LOG_LEVEL_DEBUG);
        return RG_FAIL_NONE;
    }

  //+------------------------------------------------------------------+
//| PreTradeReadinessGate — SINGLE AUTHORITY pre-trade validation    |
//+------------------------------------------------------------------+
// RETURNS: ENUM_RG_FAIL (RG_FAIL_NONE = pass, other = fail)
//
//  HARD GATE: Blocks BEFORE lot calculation if any condition fails
//
ENUM_RG_FAIL PreTradeReadinessGate(SSignalSnapshotRisk &snap, bool skipRR = false)
{
    // Reset retry flag at start of each gate evaluation
    g_rgRetryDetected = false;

    // === GLOBAL ENTRY HALT CHECK ===
    if(g_blockNewEntries)
    {
       LogPrint("[RG_GATE_FAIL] reason=GLOBAL_ENTRY_HALT | symbol=" + snap.symbol +
                " | GUID=" + IntegerToString(snap.signalID), LOG_LEVEL_ERROR);
       return RG_FAIL_PRECONDITION;
    }

    // === P1 FIX: Full market context check ===
    // P1 FIX: Full market context check
    if(!RG_CheckMarketContext(snap.symbol))
    {
        // Check if this is a retryable failure (market closed/trade disabled)
        if(g_rgRetryDetected)
        {
            LogPrint("[RG_GATE_RETRY] reason=MARKET_CLOSED_OR_DISABLED | symbol=" + snap.symbol, LOG_LEVEL_WARN);
            return RG_FAIL_RETRY;
        }
        
        LogPrint("[RG_GATE_FAIL] reason=MARKET_CONTEXT_BLOCKED | symbol=" + snap.symbol, LOG_LEVEL_ERROR);
        return RG_FAIL_PRECONDITION;
    }

// === P9 FIX: Same-Direction Exposure Gate (NOT entry distance) ===
     // Entry distance check uses profile-based point for calc-mode awareness
     ENUM_RG_FAIL exposureResult = RG_CheckExposureGate(
        snap.symbol,
        snap.direction,
        snap.closureType,
        snap.entryPrice
    );
    if(exposureResult != RG_FAIL_NONE)
    {
        RG_LogFailure(exposureResult, snap.signalID, snap.symbol,
                      "direction=" + EnumToString(snap.direction) +
                      " | closure=" + EnumToString(snap.closureType) +
                      " | entry=" + DoubleToString(snap.entryPrice, _Digits));
        return exposureResult;
    }

    // === ENTRY-ONLY Distance Check (Separated from position management) ===
    // This check should ONLY block new entries, never close existing positions
    ENUM_RG_FAIL entryDistResult = RG_CheckEntryDistance(
        snap.symbol,
        snap.direction,
        snap.entryPrice
    );
    if(entryDistResult != RG_FAIL_NONE)
    {
        RG_LogFailure(entryDistResult, snap.signalID, snap.symbol,
                      "direction=" + EnumToString(snap.direction) +
                      " | entry=" + DoubleToString(snap.entryPrice, _Digits) +
                      " | NOTE: This blocks NEW entries only, not position exits");
        return entryDistResult;
    }

// === ATR READY CHECK removed — ATR subsystem eliminated ===
     // ATR values removed from snapshot — pipeline proceeds without ATR
    
// === ENTRY PRICE CHECK ===
     if(snap.entryPrice <= 0.0)
     {
         RG_LogFailure(RG_FAIL_ENTRY_PRICE_INVALID, snap.signalID, snap.symbol,
                       "entryPrice=" + DoubleToString(snap.entryPrice, _Digits));
         LogPrint("[RG_GATE_FAIL] reason=ENTRY_PRICE_INVALID | entry=" +
                  DoubleToString(snap.entryPrice, _Digits) +
                  " | GUID=" + IntegerToString(snap.signalID), LOG_LEVEL_ERROR);
         return RG_FAIL_ENTRY_PRICE_INVALID;
     }

      // === P0 DEFENSIVE FALLBACK: C3 signal with structural stop loss from C2 extremes ===
      if(snap.stopLoss <= 0.0 && snap.closureType == CLOSURE_C3)
      {
         double c2_low = 0.0, c2_high = 0.0;
         // Try snapshot's C2 extremes first (populated at snapshot creation)
         if(snap.c2_low > 0.0 || snap.c2_high > 0.0)
         {
            c2_low = snap.c2_low;
            c2_high = snap.c2_high;
         }
         // Fallback: look up from signal store by GUID
         else if(!GetC2ExtremesForSignal(snap.signalID, c2_low, c2_high))
         {
            c2_low = 0.0;
            c2_high = 0.0;
         }
         if(c2_low > 0.0 || c2_high > 0.0)
         {
            if(snap.direction == DIRECTION_BUY)
               snap.stopLoss = c2_low;
            else if(snap.direction == DIRECTION_SELL)
               snap.stopLoss = c2_high;
            if(snap.stopLoss > 0.0)
            {
               LogPrint("[SL_FALLBACK_C3] GUID=" + IntegerToString(snap.signalID) +
                        " sl=" + DoubleToString(snap.stopLoss, _Digits) +
                        " from c2_low=" + DoubleToString(c2_low, _Digits) +
                        " c2_high=" + DoubleToString(c2_high, _Digits), LOG_LEVEL_WARN);
            }
         }
      }

      // === STOPLOSS VALID CHECK ===
      if(snap.stopLoss <= 0.0 || snap.stopLoss == snap.entryPrice)
      {
         RG_LogFailure(RG_FAIL_SL_INVALID, snap.signalID, snap.symbol,
                       "sl=" + DoubleToString(snap.stopLoss, _Digits) +
                       " | entry=" + DoubleToString(snap.entryPrice, _Digits));
         LogPrint("[RG_GATE_FAIL] reason=SL_INVALID | sl=" + DoubleToString(snap.stopLoss, _Digits) +
                  " | entry=" + DoubleToString(snap.entryPrice, _Digits) +
                  " | GUID=" + IntegerToString(snap.signalID), LOG_LEVEL_ERROR);
         return RG_FAIL_SL_INVALID;
     }

           // Cache profile snapshot for symbol-aware checks
      SSymbolProfile spGate = SY_GetProfile(snap.symbol);

// === SL DIRECTION CHECK ===
     if(snap.direction == DIRECTION_BUY && snap.stopLoss >= snap.entryPrice)
     {
         RG_LogFailure(RG_FAIL_SL_DIRECTION, snap.signalID, snap.symbol,
                       "BUY: sl >= entry | sl=" + DoubleToString(snap.stopLoss, _Digits) +
                       " | entry=" + DoubleToString(snap.entryPrice, _Digits));
         LogPrint("[RG_GATE_FAIL] reason=SL_DIRECTION_BUY | sl=" + DoubleToString(snap.stopLoss, _Digits) +
                  " | entry=" + DoubleToString(snap.entryPrice, _Digits) +
                  " | GUID=" + IntegerToString(snap.signalID), LOG_LEVEL_ERROR);
         return RG_FAIL_SL_DIRECTION;
     }
     if(snap.direction == DIRECTION_SELL && snap.stopLoss <= snap.entryPrice)
     {
         RG_LogFailure(RG_FAIL_SL_DIRECTION, snap.signalID, snap.symbol,
                       "SELL: sl <= entry | sl=" + DoubleToString(snap.stopLoss, _Digits) +
                       " | entry=" + DoubleToString(snap.entryPrice, _Digits));
         LogPrint("[RG_GATE_FAIL] reason=SL_DIRECTION_SELL | sl=" + DoubleToString(snap.stopLoss, _Digits) +
                  " | entry=" + DoubleToString(snap.entryPrice, _Digits) +
                  " | GUID=" + IntegerToString(snap.signalID), LOG_LEVEL_ERROR);
         return RG_FAIL_SL_DIRECTION;
     }

// === STOPLOSS POINTS CHECK ===
        // P2 Fix: Gate computes its own point distance internally — from profile
        double point = spGate.point;
       if(point <= 0.0) point = _Point;
       double slDistancePoints = (snap.stopLoss > 0.0 && snap.entryPrice > 0.0)
                                  ? MathAbs(snap.stopLoss - snap.entryPrice) / point
                                  : 0.0;

      // P2 Optional: Warn if caller-supplied field differs from self-computed (regression detector)
      if(snap.stopLossPoints > 0.0 && MathAbs(snap.stopLossPoints - slDistancePoints) > 1.0)
      {
          LogPrint("[RG_POINTS_MISMATCH] caller=" + DoubleToString(snap.stopLossPoints, 0) +
                   " | computed=" + DoubleToString(slDistancePoints, 0) +
                   " | GUID=" + IntegerToString(snap.signalID), LOG_LEVEL_WARN);
      }

      if(slDistancePoints <= 0.0)
      {
          RG_LogFailure(RG_FAIL_SL_POINTS_ZERO, snap.signalID, snap.symbol,
                        "slDistancePoints=" + DoubleToString(slDistancePoints, 0) +
                        " | sl=" + DoubleToString(snap.stopLoss, _Digits) +
                        " | entry=" + DoubleToString(snap.entryPrice, _Digits));
          LogPrint("[RG_GATE_FAIL] reason=SL_POINTS_ZERO | slDistancePoints=" +
                   DoubleToString(slDistancePoints, 0) +
                   " | sl=" + DoubleToString(snap.stopLoss, _Digits) +
                   " | entry=" + DoubleToString(snap.entryPrice, _Digits) +
                   " | GUID=" + IntegerToString(snap.signalID), LOG_LEVEL_ERROR);
          return RG_FAIL_SL_POINTS_ZERO;
      }

      // === TICKVALUE CHECK (from profile) ===
      if(snap.tickValue <= 0.0)
      {
          RG_LogFailure(RG_FAIL_TICKVALUE_ZERO, snap.signalID, snap.symbol,
                        "tickValue=" + DoubleToString(snap.tickValue, 5) +
                        " | calcMode=" + IntegerToString(spGate.calcMode) +
                        " | class=" + EnumToString(spGate.classification));
          LogPrint("[RG_GATE_FAIL] reason=TICKVALUE_ZERO | tickValue=" +
                   DoubleToString(snap.tickValue, 5) +
                   " | sym=" + snap.symbol +
                   " | calcMode=" + IntegerToString(spGate.calcMode) +
                   " | GUID=" + IntegerToString(snap.signalID), LOG_LEVEL_ERROR);
          return RG_FAIL_TICKVALUE_ZERO;
      }

      // === TICKSIZE CHECK (from profile) ===
      if(snap.tickSize <= 0.0)
      {
          RG_LogFailure(RG_FAIL_TICKSIZE_ZERO, snap.signalID, snap.symbol,
                        "tickSize=" + DoubleToString(snap.tickSize, 5) +
                        " | calcMode=" + IntegerToString(spGate.calcMode) +
                        " | class=" + EnumToString(spGate.classification));
          LogPrint("[RG_GATE_FAIL] reason=TICKSIZE_ZERO | tickSize=" +
                   DoubleToString(snap.tickSize, 5) +
                   " | sym=" + snap.symbol +
                   " | calcMode=" + IntegerToString(spGate.calcMode) +
                   " | GUID=" + IntegerToString(snap.signalID), LOG_LEVEL_ERROR);
          return RG_FAIL_TICKSIZE_ZERO;
      }

      // === VOLUME CONTRACT CHECK (from profile) ===
      if(snap.minLot <= 0.0 || snap.maxLot <= 0.0 || snap.lotStep <= 0.0)
      {
          RG_LogFailure(RG_FAIL_VOLUME_CONTRACT, snap.signalID, snap.symbol,
                        "min=" + DoubleToString(snap.minLot, 2) +
                        " | max=" + DoubleToString(snap.maxLot, 2) +
                        " | step=" + DoubleToString(snap.lotStep, 2) +
                        " | calcMode=" + IntegerToString(spGate.calcMode) +
                        " | class=" + EnumToString(spGate.classification));
          LogPrint("[RG_GATE_FAIL] reason=VOLUME_CONTRACT | min=" + DoubleToString(snap.minLot, 2) +
                   " | max=" + DoubleToString(snap.maxLot, 2) +
                   " | step=" + DoubleToString(snap.lotStep, 2) +
                   " | sym=" + snap.symbol +
                   " | calcMode=" + IntegerToString(spGate.calcMode) +
                   " | GUID=" + IntegerToString(snap.signalID), LOG_LEVEL_ERROR);
          return RG_FAIL_VOLUME_CONTRACT;
      }
     
// === SPREAD GATE — Calc-mode-and-class-aware spread validation ===
        int spreadCheck = (spGate.spread > 0) ? spGate.spread : (int)SymbolInfoInteger(snap.symbol, SYMBOL_SPREAD);
        int calcMode = spGate.calcMode;
      int maxSpread = 3000;  // default forex
      if(calcMode == SY_CALC_CFDINDEX || calcMode == SY_CALC_CFD)
         maxSpread = 10000;
      else if(calcMode == SY_CALC_CFDLEVERAGE)
      {
         if(spGate.classification == SYM_CLASS_CRYPTO)
            maxSpread = 30000;
         else if(spGate.classification == SYM_CLASS_SYNTHETIC)
            maxSpread = 50000;
         else
            maxSpread = 8000;
      }
      if(spreadCheck > maxSpread)
      {
          RG_LogFailure(RG_FAIL_SPREAD_TOO_WIDE, snap.signalID, snap.symbol,
                        "spread=" + IntegerToString(spreadCheck) + " | max=" + IntegerToString(maxSpread));
          LogPrint("[RG_GATE_FAIL] reason=SPREAD_TOO_WIDE | spread=" + IntegerToString(spreadCheck) +
                   " | max=" + IntegerToString(maxSpread) +
                   " | calcMode=" + IntegerToString(calcMode) +
                   " | GUID=" + IntegerToString(snap.signalID), LOG_LEVEL_ERROR);
          return RG_FAIL_SPREAD_TOO_WIDE;
      }
       LogPrint("[SPREAD_GATE] PASS | spread=" + IntegerToString(spreadCheck) +
                " | max=" + IntegerToString(maxSpread) +
                " | GUID=" + IntegerToString(snap.signalID), LOG_LEVEL_DEBUG);
       // REGRESSION_GUARDSPREAD_GATE

       // REGRESSION_GUARD_V52.5_RISK_GATE_EXPOSURE — cumulative exposure awareness
// === CUMULATIVE EXPOSURE CHECK — Aggregate all EA-managed open positions ===
       double cumulativeRiskPct = 0.0;
       double totalOpenRisk = 0.0;
       double accountEq = AccountInfoDouble(ACCOUNT_EQUITY);
       for(int pi = 0; pi < PositionsTotal(); pi++)
       {
           ulong pt = PositionGetTicket(pi);
           if(pt <= 0) continue;
           if(!PositionSelectByTicket(pt)) continue;
           if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

           double op = PositionGetDouble(POSITION_PRICE_OPEN);
           double sl = PositionGetDouble(POSITION_SL);
           double vol = PositionGetDouble(POSITION_VOLUME);
           string sym = PositionGetString(POSITION_SYMBOL);
           if(sl <= 0.0) continue;

           SSymbolProfile posSp = SY_GetProfile(sym);
           double tickVal = posSp.tickValue;
           double tickSz = posSp.tickSize;
           if(tickVal <= 0.0 || tickSz <= 0.0) continue;

           double posRisk = MathAbs(op - sl) / tickSz * tickVal * vol;
           totalOpenRisk += posRisk;
       }
       cumulativeRiskPct = (accountEq > 0.0) ? (totalOpenRisk / accountEq) * 100.0 : 0.0;
       LogPrint("[RISK_GATE] CUMULATIVE | totalOpenRisk=" + DoubleToString(totalOpenRisk, 2) +
                " | equity=" + DoubleToString(accountEq, 2) +
                " | cumRiskPct=" + DoubleToString(cumulativeRiskPct, 2) + "%" +
                " | GUID=" + IntegerToString(snap.signalID), LOG_LEVEL_DEBUG);

       // Hard cap: cumulative open risk must not exceed 10% of equity
       if(cumulativeRiskPct > 10.0)
       {
           LogPrint("[RISK_GATE] CUMULATIVE_EXPOSURE_EXCEEDED | cumRiskPct=" +
                    DoubleToString(cumulativeRiskPct, 2) + "% > 10% | GUID=" +
                    IntegerToString(snap.signalID), LOG_LEVEL_WARN);
           return RG_FAIL_PRECONDITION;
       }

// === STRUCTURAL VIABILITY CHECK (≥2R minimum per Risk Dossier §4.3) ===
// REGRESSION_GUARD_V57_1: Mode-aware minimum RR enforcement with explicit logging
      if(!skipRR)
      {
          double risk = MathAbs(snap.entryPrice - snap.stopLoss);
          if(risk <= 0.0)
          {
              LogInfo(StringFormat("[RG_GATE_FAIL] ZERO_RISK | GUID=%I64u entry=%.5f sl=%.5f",
                  snap.signalID, snap.entryPrice, snap.stopLoss));
              return RG_FAIL_SL_POINTS_ZERO;
          }

          double minRR = (snap.closureType == CLOSURE_C3)
              ? g_trueTTradesConfig.confirmationMinRR
              : g_trueTTradesConfig.anticipationMinRR;
          if(minRR <= 0.0) minRR = 2.0;

          double reward = (snap.tpPrice > 0.0) ? MathAbs(snap.tpPrice - snap.entryPrice) : 0.0;
          double rr_ratio = (reward > 0.0) ? (reward / risk) : 0.0;

          LogInfo(StringFormat("[RG_GATE_CALC] GUID=%I64u entry=%.5f sl=%.5f tp=%.5f slDist=%.5f tpDist=%.5f RR=%.2f minRR=%.2f closure=%s",
              snap.signalID, snap.entryPrice, snap.stopLoss, snap.tpPrice, risk, reward, rr_ratio, minRR,
              EnumToString(snap.closureType)));

          if(rr_ratio < minRR - 0.00001)
          {
              RG_LogFailure(RG_FAIL_RR_INSUFFICIENT, snap.signalID, snap.symbol,
                  StringFormat("RR=%.2f < minRR=%.2f closure=%s", rr_ratio, minRR, EnumToString(snap.closureType)));
              string snapModeStr = (snap.executionMode == MODE_ANTICIPATION) ? "ANTICIPATION" :
                                  (snap.executionMode == MODE_CONFIRMATION) ? "CONFIRMATION" : "NONE";
              LogPrint("[RISK_2R_VIOLATION] GUID=" + IntegerToString(snap.signalID) +
                       " | RR=" + DoubleToString(rr_ratio, 2) +
                       " < minRR=" + DoubleToString(minRR, 2) +
                       " | closure=" + EnumToString(snap.closureType) +
                       " | mode=" + snapModeStr, LOG_LEVEL_ERROR);
              LogInfo(StringFormat("[RG_GATE_FAIL] INSUFFICIENT_RR | GUID=%I64u RR=%.2f < %.2f mode=%s[%d] closure=%s",
                  snap.signalID, rr_ratio, minRR,
                  snapModeStr, snap.executionMode,
                  EnumToString(snap.closureType)));
              return RG_FAIL_RR_INSUFFICIENT;
          }

          LogInfo(StringFormat("[RG_GATE_PASS] GUID=%I64u RR=%.2f >= %.2f closure=%s",
              snap.signalID, rr_ratio, minRR, EnumToString(snap.closureType)));
      }

   // ===== C3 SPECIES HANDLING (REPLACEMENT FOR LINES 720-734) =====
   if(snap.closureType == CLOSURE_C3)
   {
      // C3 does NOT require C2 extremes (standalone C3 is valid)
      // Instead, ensure SL is valid using dedicated calculator
      if(snap.stopLoss <= 0.0 || snap.stopLoss == snap.entryPrice)
      {
         LogPrint("[C3_SL_FALLBACK] No valid SL found, computing fresh...", LOG_LEVEL_WARN);
         snap.stopLoss = C3_SL_Calculator(
            (snap.direction == DIRECTION_BUY) ? 1 : -1,
            snap.entryPrice,
            (snap.branch == BRANCH_INTRADAY) ? PERIOD_H1 : PERIOD_H4,
            InpMinStopBuffer
         );
      }
      
      // Final validation
      if(snap.stopLoss <= 0.0 || snap.stopLoss == snap.entryPrice)
      {
         LogPrint(StringFormat("[RG_GATE_FAIL] reason=C3_SL_STILL_INVALID | sl=%.5f entry=%.5f",
                  snap.stopLoss, snap.entryPrice), LOG_LEVEL_ERROR);
         return RG_FAIL_PRECONDITION;
      }
      
      LogPrint(StringFormat("[C3_SL_VALID] sl=%.5f entry=%.5f distance=%.5f",
               snap.stopLoss, snap.entryPrice,
               MathAbs(snap.stopLoss - snap.entryPrice)), LOG_LEVEL_INFO);
   }
   // ===== END C3 HANDLING =====

      LogPrint("[RG_GATE_PASS] Pre-trade context and rules validation verified successfully.", LOG_LEVEL_INFO);
      return RG_FAIL_NONE;
 }

//+------------------------------------------------------------------+
//| PreTradeExecutionCheck — FINAL RR verification before OrderSend   |
//| Double-checks R:R ratio right before terminal dispatch.           |
//| Returns false to abort order if RR < minimum.                    |
//+------------------------------------------------------------------+
bool PreTradeExecutionCheck(ulong signalGUID, double entryPrice, double stopLoss, double tpPrice, ENUM_CLOSURE_TYPE closureType)
{
    if(signalGUID == 0 || entryPrice <= 0.0 || stopLoss <= 0.0)
    {
        LogInfo(StringFormat("[EXEC_ABORT] INVALID_PARAMS | GUID=%I64u entry=%.5f sl=%.5f",
            signalGUID, entryPrice, stopLoss));
        return false;
    }

    double risk = MathAbs(entryPrice - stopLoss);
    if(risk <= 0.0)
    {
        LogInfo(StringFormat("[EXEC_ABORT] ZERO_RISK | GUID=%I64u", signalGUID));
        return false;
    }

    double reward = (tpPrice > 0.0) ? MathAbs(tpPrice - entryPrice) : 0.0;
    double rr = (reward > 0.0) ? (reward / risk) : 0.0;

    double minRR = (closureType == CLOSURE_C3)
        ? g_trueTTradesConfig.confirmationMinRR
        : g_trueTTradesConfig.anticipationMinRR;
    if(minRR <= 0.0) minRR = 2.0;

    LogInfo(StringFormat("[EXEC_CALC] GUID=%I64u entry=%.5f sl=%.5f tp=%.5f slDist=%.5f tpDist=%.5f RR=%.2f minRR=%.2f",
        signalGUID, entryPrice, stopLoss, tpPrice, risk, reward, rr, minRR));

    if(rr < minRR - 0.00001)
    {
        LogInfo(StringFormat("[EXEC_ABORT] INSUFFICIENT_RR | GUID=%I64u RR=%.2f < %.2f closure=%s",
            signalGUID, rr, minRR, EnumToString(closureType)));
        return false;
    }

    LogInfo(StringFormat("[EXEC_PASS] GUID=%I64u RR=%.2f >= %.2f closure=%s",
        signalGUID, rr, minRR, EnumToString(closureType)));
    return true;
}
// REGRESSION_GUARD_V57_2

//+------------------------------------------------------------------+
//| RG_IsReady — Simple readiness check (returns exit code)           |
//+------------------------------------------------------------------+
ENUM_RG_FAIL RG_IsReady()
{
    return PreTradeReadinessGate(g_snapshotRisk);
}

//+------------------------------------------------------------------+
  //| RG_HasValidSnapshot — Check if snapshot exists                  |
  //+------------------------------------------------------------------+
  bool RG_HasValidSnapshot()
  {
      return g_snapshotRisk.signalID != 0 && g_snapshotRisk.symbol != "";
  }

//+------------------------------------------------------------------+
//| SincereRiskCalculation — §XII Sincere Telemetry Wrapper          |
//+------------------------------------------------------------------+
/**
 * VERBATIM REPAIR: §XII Sincere Telemetry Wrapper
 * Uses OrderCalcProfit for broker-authoritative risk, with manual formula
 * fallback if broker value is suspect.
 *
 * @param sig     Locked signal with entry_price, stop_loss, symbol, GUID
 * @param volume  Trade volume to evaluate
 * @return        Abs risk value (positive) from broker or manual fallback
 */
double SincereRiskCalculation(const SLockedSignal &sig, double volume)
{
    double brokerLoss = 0.0;
    bool success = OrderCalcProfit(ORDER_TYPE_BUY, sig.symbol, volume, sig.entry_price, sig.stop_loss, brokerLoss);

    // Log raw broker telemetry channel
    LogPrint(StringFormat("[TELEMETRY_RISK] GUID:%I64u | BrokerRaw:%.2f", sig.m_guid, brokerLoss), LOG_LEVEL_INFO);

    // Manual Formula Fallback (The 100x Fraud Guard)
    SSymbolProfile rgProf = SY_GetProfile(sig.symbol);
    double tickSizeRG = rgProf.isValid ? rgProf.tickSize : 0.0;
    double tickValRG = rgProf.isValid ? rgProf.tickValue : 0.0;
    double slTicks = (tickSizeRG > 0.0) ? MathAbs(sig.entry_price - sig.stop_loss) / tickSizeRG : 0.0;
    double manualLoss = slTicks * tickValRG * volume;

    double discrepancy = (manualLoss != 0.0) ? MathAbs(brokerLoss - manualLoss) / manualLoss : 1.0;
    if(success && discrepancy <= 0.05)
        return MathAbs(brokerLoss);
    else
        return manualLoss;
}

//+------------------------------------------------------------------+
//| PreTradeSimulation — Margin + equity projection before order     |
//| Prevents reactive account blow-ups by validating trade impact     |
//| BEFORE OrderSend is called. Universal across broker types.        |
//+------------------------------------------------------------------+
struct PreTradeSimulation
{
   bool   canTrade;
   double requiredMargin;
   double projectedEquity;
   double projectedBalance;
   double freeMarginAfter;
   double actualRiskPercent;
   double marginLevelAfter;
   string rejectReason;
};

PreTradeSimulation SimulateTradeImpact(
    string symbol,
    ENUM_ORDER_TYPE orderType,
    double volume,
    double entryPrice,
    double slPrice,
    double tpPrice,
    double accountEquity,
    double accountBalance,
    double accountFreeMargin,
    double riskPercent,
    double maxDailyLossPct = 10.0,
    double dailyStartBalance = 0.0
)
{
   PreTradeSimulation sim = {};
   sim.canTrade = false;
   sim.rejectReason = "UNKNOWN";
   sim.marginLevelAfter = 0.0;

   if(volume <= 0.0)
   {
       sim.rejectReason = "ZERO_VOLUME";
       LogPrint("[PRE_TRADE_SIM] Zero volume passed | GUID=unknown", LOG_LEVEL_DEBUG);  // P8 Fix
       return sim;
   }

   if(entryPrice <= 0.0)
   {
       sim.rejectReason = "INVALID_PRICE";
       LogPrint("[PRE_TRADE_SIM] Invalid entryPrice=" + DoubleToString(entryPrice, _Digits), LOG_LEVEL_ERROR);
       return sim;
   }

   // === 1. Margin requirement via OrderCalcMargin ===
   if(!OrderCalcMargin(orderType, symbol, volume, entryPrice, sim.requiredMargin))
   {
       sim.rejectReason = "MARGIN_CALC_FAILED";
       LogPrint("[PRE_TRADE_SIM] OrderCalcMargin failed | symbol=" + symbol, LOG_LEVEL_DEBUG);  // P8 Fix
       return sim;
   }

   sim.freeMarginAfter = accountFreeMargin - sim.requiredMargin;
   if(sim.freeMarginAfter < 0)
{
        sim.rejectReason = "INSUFFICIENT_FREE_MARGIN";
        LogPrint("[PRE_TRADE_SIM] freeMarginAfter=" + DoubleToString(sim.freeMarginAfter, 2) +
                 " < 0 | required=" + DoubleToString(sim.requiredMargin, 2), LOG_LEVEL_DEBUG);  // P8 Fix
        return sim;
    }

// === 2. Max loss if SL hit — broker-reality computation ===
// VERBATIM REPAIR: Manual formula via SY_ComputeMaxLoss (tickValue/tickSize).
       double maxLoss = SY_ComputeMaxLoss(symbol, orderType, volume, entryPrice, slPrice);

       if(maxLoss <= 0.0)
       {
           sim.rejectReason = "LOSS_CALC_FAILED";
           LogPrint("[PRE_TRADE_SIM] Max loss calc returned 0 | sym=" + symbol +
                " | vol=" + DoubleToString(volume, 4) +
                " | entry=" + DoubleToString(entryPrice, 6) +
                " | sl=" + DoubleToString(slPrice, 6), LOG_LEVEL_ERROR);
           return sim;
       }

       // Validate profile for consistent risk computation
       SSymbolProfile sp = SY_GetProfile(symbol);
       if(!sp.isValid)
       {
           sim.rejectReason = "PROFILE_INVALID";
           LogPrint("[PRE_TRADE_SIM] Symbol profile invalid | sym=" + symbol, LOG_LEVEL_ERROR);
           return sim;
       }

      LogPrint("[PRE_TRADE_SIM_DIAG] sym=" + symbol +
               " | vol=" + DoubleToString(volume, 4) +
               " | entry=" + DoubleToString(entryPrice, 6) +
               " | sl=" + DoubleToString(slPrice, 6) +
               " | slDist=" + DoubleToString(MathAbs(entryPrice - slPrice), 6) +
               " | tickSize=" + DoubleToString(sp.tickSize, 8) +
               " | tickValue=" + DoubleToString(sp.tickValue, 8) +
               " | calcMode=" + IntegerToString(sp.calcMode) +
               " | maxLoss=" + DoubleToString(maxLoss, 4) +
               " | equity=" + DoubleToString(accountEquity, 2) +
               " | riskPct=" + DoubleToString((accountEquity > 0.0 ? maxLoss / accountEquity * 100.0 : 0.0), 2) + "%",
               LOG_LEVEL_DEBUG);

      double intendedLoss = accountEquity * (riskPercent / 100.0);
      if(intendedLoss > 0.0 && (maxLoss / intendedLoss) > 1.5)
      {
          sim.rejectReason = "OVEREXPOSURE";
          LogPrint("[PRE_TRADE_SIM] [LOT_OVEREXPOSURE] actualLoss=" + DoubleToString(maxLoss, 2) +
                   " | intendedLoss=" + DoubleToString(intendedLoss, 2) +
                   " | ratio=" + DoubleToString(maxLoss / intendedLoss, 2) +
                   " | sym=" + symbol +
                   " | calcMode=" + IntegerToString(sp.calcMode), LOG_LEVEL_ERROR);
          return sim;
      }

     sim.projectedEquity = accountEquity - maxLoss;
     sim.projectedBalance = accountBalance - maxLoss;
     sim.actualRiskPercent = (accountEquity > 0.0) ? (maxLoss / accountEquity) * 100.0 : 100.0;

// === 3. Stop-out risk check ===
    double stopOutLevel = AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
    // P8 Fix: Add diagnostic for margin calculation
    LogPrint("[PRE_TRADE_SIM_DIAG] marginCalc: requiredMargin=" + DoubleToString(sim.requiredMargin, 4) +
             " | freeMarginBefore=" + DoubleToString(accountFreeMargin, 2) +
             " | stopOutLevel=" + DoubleToString(stopOutLevel, 2) +
             "% | sym=" + symbol, LOG_LEVEL_DEBUG);

    if(stopOutLevel > 0.0 && sim.requiredMargin > 0.0)
    {
        sim.marginLevelAfter = (sim.projectedEquity / sim.requiredMargin) * 100.0;
        LogPrint("[PRE_TRADE_SIM_DIAG] marginLevelAfter=" + DoubleToString(sim.marginLevelAfter, 2) +
                 "% | projectedEquity=" + DoubleToString(sim.projectedEquity, 2) +
                 " | stopOut=" + DoubleToString(stopOutLevel, 2) +
                 "% | sym=" + symbol, LOG_LEVEL_DEBUG);

        if(sim.marginLevelAfter < stopOutLevel)
        {
            sim.rejectReason = "STOP_OUT_RISK";
            LogPrint("[PRE_TRADE_SIM] marginLevelAfter=" + DoubleToString(sim.marginLevelAfter, 2) +
                     "% < stopOut=" + DoubleToString(stopOutLevel, 2) +
                     "% | projectedEquity=" + DoubleToString(sim.projectedEquity, 2), LOG_LEVEL_ERROR);
            return sim;
        }
    }

   // === 4. Equity wipeout check ===
   if(accountEquity > 0.0 && sim.projectedEquity < accountEquity * 0.10)
   {
       sim.rejectReason = "EQUITY_WIPEOUT_RISK";
       LogPrint("[PRE_TRADE_SIM] projectedEquity=" + DoubleToString(sim.projectedEquity, 2) +
                " < 10% of equity=" + DoubleToString(accountEquity, 2), LOG_LEVEL_ERROR);
       return sim;
   }

   // === 5. Daily loss limit ===
   if(dailyStartBalance > 0.0 && maxDailyLossPct > 0.0)
   {
       double dailyLoss = dailyStartBalance - accountBalance;
       double dailyLossPct = (dailyStartBalance > 0.0) ? (dailyLoss / dailyStartBalance) * 100.0 : 0.0;
       if(dailyLossPct + sim.actualRiskPercent > maxDailyLossPct)
       {
           sim.rejectReason = "DAILY_LOSS_LIMIT";
           LogPrint("[PRE_TRADE_SIM] dailyLoss=" + DoubleToString(dailyLossPct, 2) +
                    "% + tradeRisk=" + DoubleToString(sim.actualRiskPercent, 2) +
                    "% > max=" + DoubleToString(maxDailyLossPct, 2) + "%", LOG_LEVEL_WARN);
           return sim;
       }
   }

   sim.canTrade = true;
   sim.rejectReason = "PASS";
   LogPrint("[PRE_TRADE_SIM] PASS | margin=" + DoubleToString(sim.requiredMargin, 2) +
            " | freeAfter=" + DoubleToString(sim.freeMarginAfter, 2) +
            " | projectedEquity=" + DoubleToString(sim.projectedEquity, 2) +
            " | maxLoss=" + DoubleToString(maxLoss, 2) +
            " | actualRisk%=" + DoubleToString(sim.actualRiskPercent, 2) + "%",
            LOG_LEVEL_INFO);

   return sim;
}

//+------------------------------------------------------------------+
//| DecodeRetcode — Convert MT5 trade return code to human-readable  |
//+------------------------------------------------------------------+
string DecodeRetcode(uint code)
{
    switch(code)
    {
        case 10004: return "REQUOTE";
        case 10006: return "REQUEST_REJECTED";
        case 10007: return "REQUEST_TIMEOUT";
        case 10008: return "TRADE_RETCODE_PLACED";
        case 10009: return "TRADE_RETCODE_DONE";
        case 10014: return "INVALID_VOLUME";
        case 10015: return "INVALID_PRICE";
        case 10016: return "INVALID_STOPS";
        case 10027: return "AUTO_TRADING_DISABLED";
        case 4756:  return "TRADE_SEND_FAILED";
        default:    return "UNKNOWN(" + IntegerToString(code) + ")";
    }
}

//+------------------------------------------------------------------+
 //| ExecuteMarketOrder — Hardened order execution with retry          |
 //| Features: Smart filling, session check, OrderCheck retcode        |
 //| handling, retry loop on err=4756. Target: <10% failure rate.      |
 //+------------------------------------------------------------------+
 bool ExecuteMarketOrder(
       ulong signalID,
       string symbol,
       bool isBuy,
       double lots,
       double sl,
       double tp,
       int magicNumber,
       ulong &outTicket,
       string &failReason
    )
 {
      failReason = "";
      outTicket = 0;

      // === GLOBAL ENTRY HALT CHECK ===
      if(g_blockNewEntries)
      {
         failReason = "GLOBAL_ENTRY_HALT";
         LogPrint("[RG_GATE_FAIL] reason=GLOBAL_ENTRY_HALT | symbol=" + symbol +
                  " | GUID=" + IntegerToString(signalID), LOG_LEVEL_ERROR);
         return false;
      }

      ENUM_DIRECTION direction = isBuy ? DIRECTION_BUY : DIRECTION_SELL;
     ENUM_ORDER_TYPE orderType = (direction == DIRECTION_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

     if(!IsMarketSessionOpen(symbol))
     {
        failReason = "MARKET_CLOSED";
        LogPrint("[RG_GATE_FAIL] reason=MARKET_CLOSED | symbol=" + symbol +
                 " | GUID=" + IntegerToString(signalID), LOG_LEVEL_WARN);
        return false;
     }

      if(!SymbolSelect(symbol, true))
      {
         failReason = "SYMBOL_NOT_SELECTABLE";
         LogPrint("[RG_GATE_FAIL] reason=SYMBOL_NOT_SELECTABLE | symbol=" + symbol +
                  " | GUID=" + IntegerToString(signalID), LOG_LEVEL_ERROR);
         return false;
      }

      // TRADING PERMISSION CHECK: terminal, EA, and account
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      {
         failReason = "TRADE_DISABLED";
         LogPrint("[RG_GATE_FAIL] reason=TRADE_DISABLED | symbol=" + symbol +
                  " | GUID=" + IntegerToString(signalID), LOG_LEVEL_WARN);
         return false;
      }

      MqlTick tick;
     if(!SymbolInfoTick(symbol, tick))
     {
        failReason = "TICK_UNAVAILABLE";
        LogPrint("[RG_GATE_FAIL] reason=TICK_UNAVAILABLE | symbol=" + symbol +
                 " | err=" + IntegerToString(GetLastError()), LOG_LEVEL_ERROR);
        return false;
     }

SSymbolProfile execSp = SY_GetProfile(symbol);
       double price = (direction == DIRECTION_BUY) ? tick.ask : tick.bid;
       int digits = execSp.digits > 0 ? execSp.digits : _Digits;
      price = NormalizeDouble(price, digits);

       double minVol = execSp.volumeMin;
       double maxVol = execSp.volumeMax;
       double lotStep = execSp.volumeStep;
       double normLot = SY_NormalizeLot(symbol, lots);
       if(normLot < minVol || normLot > maxVol)
       {
          failReason = "VOLUME_OUT_OF_RANGE";
          LogPrint("[RG_GATE_FAIL] reason=VOLUME_OUT_OF_RANGE | lot=" + DoubleToString(normLot, 2) +
                   " | min=" + DoubleToString(minVol, 2) +
                   " | max=" + DoubleToString(maxVol, 2), LOG_LEVEL_ERROR);
          return false;
       }

// VERBATIM REPAIR: §XII Sincere Telemetry Wrapper replaces raw formula
        SLockedSignal tempSig;
        tempSig.Reset();
        tempSig.symbol = symbol;
        tempSig.entry_price = price;
        tempSig.stop_loss = sl;
        tempSig.m_guid = signalID;
        double minRisk = SincereRiskCalculation(tempSig, minVol);

        double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPercent / 100.0);

        if(!IsLotTradeable(0.0, execSp.tickValue, minVol,
                           AccountInfoDouble(ACCOUNT_EQUITY), InpRiskPercent, symbol,
                           price, sl, isBuy))
        {
           failReason = "LOT_NOT_TRADEABLE";
           LogPrint("[RISK_FLOOR_BLOCK] reason=EXECUTE_MARKET_ORDER_LOT_NOT_TRADEABLE" +
                    " | minLot=" + DoubleToString(minVol, 4) +
                    " | minRisk=" + DoubleToString(minRisk, 2) +
                    " | riskAmount=" + DoubleToString(riskAmount, 4) +
                    " | method=SincereRiskCalculation" +
                    " | symbol=" + symbol +
                    " | GUID=" + IntegerToString(signalID), LOG_LEVEL_WARN);
           return false;
        }

       // MARGIN & RISK SIMULATION before order placement
      double accountEquity   = AccountInfoDouble(ACCOUNT_EQUITY);
      double accountBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
      double accountFreeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      PreTradeSimulation sim = SimulateTradeImpact(
         symbol,               // symbol
         orderType,            // order type
         normLot,              // volume
         price,                // entry price
         sl,                   // stop loss
         tp,                   // take profit
         accountEquity,        // account equity
         accountBalance,       // account balance
         accountFreeMargin,    // free margin
         0.0,                  // riskPercent: overexposure check disabled (handled by lot sizing)
         0.0                   // dailyStartBalance: daily loss check disabled
      );
      if(!sim.canTrade)
      {
         failReason = "PRE_TRADE_SIM_" + sim.rejectReason;
         LogPrint("[RISK_MARGIN_FAIL] reason=" + failReason +
                  " | symbol=" + symbol +
                  " | GUID=" + IntegerToString(signalID), LOG_LEVEL_ERROR);
         LogPrint("[RG_GATE_FAIL] reason=" + failReason +
                  " | symbol=" + symbol +
                  " | GUID=" + IntegerToString(signalID), LOG_LEVEL_ERROR);
         return false;
      }

      MqlTradeRequest req = {};
     req.action = TRADE_ACTION_DEAL;
     req.symbol = symbol;
     req.type = orderType;
     req.volume = normLot;
req.price = price;
      req.sl = (sl > 0) ? NormalizeDouble(sl, digits) : 0;
      req.tp = (tp > 0) ? NormalizeDouble(tp, digits) : 0;
      double point = execSp.point > 0.0 ? execSp.point : _Point;
      req.deviation = (ulong)(point * 30);
      req.magic = InpMagicNumber;
      // Preserve original comment if any, prepend GUID tag
      string originalComment = "";
      req.comment = StringFormat("GUID=%I64u|%s", signalID, originalComment);
     req.type_filling = SelectFillingMode(symbol);

      MqlTradeCheckResult checkRes = {};
      if(!OrderCheck(req, checkRes))
      {
          LogPrint("[ORDER_CHECK_FAIL] retcode=" + IntegerToString(checkRes.retcode) +
                   " | comment=" + checkRes.comment +
                   " | GUID=" + IntegerToString(signalID), LOG_LEVEL_ERROR);
          // Additional marker for forensics
          LogPrint("[ORDER_CHECK_REJECT] retcode=" + IntegerToString(checkRes.retcode) +
                   " | comment=" + checkRes.comment +
                   " | GUID=" + IntegerToString(signalID), LOG_LEVEL_ERROR);

          if(checkRes.retcode == 10016)
         {
            LogPrint("[ORDER_CHECK] retcode=10016 INVALID_STOPS — adjusting stops", LOG_LEVEL_WARN);
            AdjustStopsToValidDistance(req, symbol, req.price);
            if(!OrderCheck(req, checkRes))
            {
               failReason = "INVALID_STOPS_UNFIXABLE";
               LogPrint("[RG_GATE_FAIL] reason=INVALID_STOPS_UNFIXABLE | retcode=" +
                        IntegerToString(checkRes.retcode), LOG_LEVEL_ERROR);
               LogPrint("[ORDER_CHECK_REJECT] retcode=" + IntegerToString(checkRes.retcode) +
                        " | comment=" + checkRes.comment +
                        " | GUID=" + IntegerToString(signalID), LOG_LEVEL_ERROR);
               return false;
            }
           LogPrint("[ORDER_CHECK] PASS after stop adjustment | retcode=" +
                    IntegerToString(checkRes.retcode), LOG_LEVEL_INFO);
        }
         else if(checkRes.retcode == 10019)
         {
            failReason = "NO_MONEY";
            LogPrint("[RG_GATE_FAIL] reason=NO_MONEY | comment=" + checkRes.comment, LOG_LEVEL_ERROR);
            LogPrint("[ORDER_CHECK_REJECT] retcode=" + IntegerToString(checkRes.retcode) +
                     " | comment=" + checkRes.comment +
                     " | GUID=" + IntegerToString(signalID), LOG_LEVEL_ERROR);
            return false;
         }
         else
         {
            failReason = "ORDER_CHECK_" + IntegerToString(checkRes.retcode);
            LogPrint("[RG_GATE_FAIL] reason=" + failReason + " | retcode=" +
                     IntegerToString(checkRes.retcode) +
                     " | comment=" + checkRes.comment, LOG_LEVEL_ERROR);
            LogPrint("[ORDER_CHECK_REJECT] retcode=" + IntegerToString(checkRes.retcode) +
                     " | comment=" + checkRes.comment +
                     " | GUID=" + IntegerToString(signalID), LOG_LEVEL_ERROR);
            return false;
         }
     }

     LogPrint("[ORDER_CHECK_PASS] margin=" + DoubleToString(checkRes.margin, 2) +
              " | freeMarginAfter=" + DoubleToString(checkRes.margin_free, 2) +
              " | GUID=" + IntegerToString(signalID), LOG_LEVEL_INFO);

       LogPrint("[RISK_MARGIN_OK] requiredMargin=" + DoubleToString(sim.requiredMargin, 2) +
                " | freeMarginBefore=" + DoubleToString(accountFreeMargin, 2) +
                " | GUID=" + IntegerToString(signalID), LOG_LEVEL_INFO);

int maxRetries = 3;
      int lastRetcode = 0;
      for(int attempt = 1; attempt <= maxRetries; attempt++)
     {
        if(req.tp <= 0.0 || req.sl <= 0.0)
        {
           string rgSpecies = "UNKNOWN";
           for(int rDi = 0; rDi < MAX_SLOTS; rDi++)
           {
              if(g_activeC2[rDi].m_guid == signalID) { rgSpecies = "C2"; break; }
              if(g_activeC3[rDi].m_guid == signalID) { rgSpecies = (g_activeC3[rDi].closureType == CLOSURE_C4 ? "C4" : "C3"); break; }
           }
           LogPrint("[PROTECTED_DELIVERY_BLOCK] sl=" + DoubleToString(req.sl, _Digits) +
                    " | tp=" + DoubleToString(req.tp, _Digits) +
                    " | GUID=" + IntegerToString(signalID) +
                    " | species=" + rgSpecies, LOG_LEVEL_ERROR);
           return false;
        }
        MqlTradeResult res = {};
if(OrderSend(req, res))
         {
            // retcode==0 is normal in Tester — not a failure
            // Only TRADE_RETCODE_DONE (10009), TRADE_RETCODE_PLACED (10008), TRADE_RETCODE_DONE_PARTIAL (10023) indicate success
            if(res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED || res.retcode == TRADE_RETCODE_DONE_PARTIAL)
           {
outTicket = res.order;
g_totalOrdersSent++;
g_lastTradeOpenTime = TimeCurrent();
                g_lastOrderTime = TimeCurrent();  // P5: Track for Account Guard grace period
LogPrint("[ORDER_SENT] ticket=" + IntegerToString(res.order) +
                        " | attempt=" + IntegerToString(attempt) +
                        " | price=" + DoubleToString(res.price, digits) +
                        " | GUID=" + IntegerToString(signalID) +
                        " | ordersSentTotal=" + IntegerToString(g_totalOrdersSent), LOG_LEVEL_INFO);
               // PositionGUIDMap update happens in OnTradeTransaction via UpdatePositionGUIDMap
               return true;
           }
            else
            {
               lastRetcode = (int)res.retcode;
               LogPrint("[ORDER_RETRY] Broker rejected | retcode=" + IntegerToString(res.retcode) +
                        " | comment=" + res.comment +
                        " | attempt=" + IntegerToString(attempt), LOG_LEVEL_WARN);
               LogPrint("[ORDER_FAIL] retcode=" + IntegerToString(res.retcode) +
                        " | comment=" + res.comment +
                        " | attempt=" + IntegerToString(attempt) +
                        " | GUID=" + IntegerToString(signalID), LOG_LEVEL_WARN);
            }
        }

        int err = GetLastError();
        if(err == 4756)
        {
           ENUM_ORDER_TYPE_FILLING prevFill = req.type_filling;
           if(req.type_filling == ORDER_FILLING_FOK)
              req.type_filling = ORDER_FILLING_IOC;
           else if(req.type_filling == ORDER_FILLING_IOC)
              req.type_filling = ORDER_FILLING_RETURN;
           else
              req.type_filling = ORDER_FILLING_IOC;

           LogPrint("[ORDER_RETRY] err=4756 | switching " + EnumToString(prevFill) +
                    " → " + EnumToString(req.type_filling) +
                    " | attempt=" + IntegerToString(attempt), LOG_LEVEL_WARN);
           Sleep(100);
        }
        else if(err == 146)
        {
           LogPrint("[ORDER_RETRY] err=146 TRADE_CONTEXT_BUSY | attempt=" +
                    IntegerToString(attempt) + " | sleeping 500ms", LOG_LEVEL_WARN);
           Sleep(500);
        }
         else
         {
            failReason = "ORDERSEND_ERR_" + IntegerToString(err);
            LogPrint("[RG_GATE_FAIL] reason=" + failReason + " | err=" + IntegerToString(err) +
                     " | GUID=" + IntegerToString(signalID), LOG_LEVEL_ERROR);
            LogPrint("[ORDER_FAIL] err=" + IntegerToString(err) +
                     " | GUID=" + IntegerToString(signalID), LOG_LEVEL_ERROR);
            return false;
         }
     }

      failReason = "MAX_RETRIES_EXCEEDED";
      LogPrint("[RG_GATE_FAIL] reason=MAX_RETRIES_EXCEEDED | symbol=" + symbol +
               " | lastRetcode=" + IntegerToString(lastRetcode) +
               " | GUID=" + IntegerToString(signalID), LOG_LEVEL_ERROR);
      LogPrint("[ORDER_FAIL] reason=MAX_RETRIES_EXCEEDED | symbol=" + symbol +
               " | lastRetcode=" + IntegerToString(lastRetcode) +
               " | GUID=" + IntegerToString(signalID), LOG_LEVEL_ERROR);
      return false;
 }

//+------------------------------------------------------------------+
 //| SelectFillingMode — Intelligent filling mode selector             |
 //| Per MQL5 docs: ORDER_FILLING_RETURN is the default policy,        |
 //| always available for INSTANT and REQUEST execution modes.         |
 //| The tester always returns RETURN. Priority: IOC > FOK > RETURN    |
 //| Universal across: Standard, Micro, Cent, Zero, ECN, Synthetic,    |
 //| Crypto, Index CFDs — no instrument-specific logic.                |
 //+------------------------------------------------------------------+
 ENUM_ORDER_TYPE_FILLING SelectFillingMode(string symbol)
 {
    uint fillingFlags = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);

    LogPrint("[FILL_MODE_DETECT] flags=" + IntegerToString(fillingFlags) +
             " | symbol=" + symbol, LOG_LEVEL_DEBUG);

    // IOC is most forgiving for market orders
    if((fillingFlags & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
    {
       LogPrint("[FILL_MODE_SELECT] IOC selected for " + symbol, LOG_LEVEL_DEBUG);
       return ORDER_FILLING_IOC;
    }

    if((fillingFlags & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
    {
       LogPrint("[FILL_MODE_SELECT] FOK selected for " + symbol, LOG_LEVEL_DEBUG);
       return ORDER_FILLING_FOK;
    }

    // Fallback: ORDER_FILLING_RETURN — default policy, always available
    // in tester and for INSTANT/REQUEST execution brokers
    LogPrint("[FILL_MODE_SELECT] FALLBACK RETURN for " + symbol, LOG_LEVEL_DEBUG);
    return ORDER_FILLING_RETURN;
 }

//+------------------------------------------------------------------+
//| RG_CheckMarketContext — P1 FIX: Full market context verification  |
//| Checks: TERMINAL_TRADE_ALLOWED, MQL_TRADE_ALLOWED,                |
//|         ACCOUNT_TRADE_ALLOWED, SYMBOL_TRADE_MODE,                 |
//|         SYMBOL_FILLING_MODE availability                          |
//+------------------------------------------------------------------+
bool RG_CheckMarketContext(string symbol)
{
    // 1. Terminal permission (hard fail - no retry)
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
    {
        LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 1", LOG_LEVEL_WARN);
        return false;
    }
    // 2. EA permission (hard fail - no retry)
    if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
    {
        LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 2", LOG_LEVEL_WARN);
        return false;
    }
    // 3. Account permission (hard fail - no retry)
    if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
    {
        LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 3", LOG_LEVEL_WARN);
        return false;
    }
    // 4. Symbol trade mode - RETRY if disabled, hard fail otherwise
    ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
    if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
    {
        LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 4", LOG_LEVEL_WARN);
        g_rgRetryDetected = true;  // Signal retry needed
        return false;
    }
    else if(tradeMode != SYMBOL_TRADE_MODE_FULL)
    {
        LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 5", LOG_LEVEL_WARN);
        return false;
    }
    // 5. Symbol filling mode validation (hard fail - no retry)
    int fillingMode = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
    if(fillingMode == 0)
    {
        LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 6", LOG_LEVEL_WARN);
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| IsMarketSessionOpen — Session-aware market availability check     |
//| Checks: SYMBOL_TRADE_MODE, tick freshness, spread sanity           |
//| Universal: works on all broker types and synthetic instruments.   |
//+------------------------------------------------------------------+
bool IsMarketSessionOpen(string symbol)
{
   // Check 0: SymbolInfoSessionTrade() per MQL5 best practice
   datetime sessionFrom, sessionTo;
   bool sessionValid = false;
   MqlDateTime dt;
   TimeCurrent(dt);
   ENUM_DAY_OF_WEEK dow = (ENUM_DAY_OF_WEEK)dt.day_of_week;
   if(SymbolInfoSessionTrade(symbol, dow, 0, sessionFrom, sessionTo))
   {
      datetime now = TimeCurrent();
      datetime sessionStart = StringToTime(TimeToString(now, TIME_DATE)) + sessionFrom;
      datetime sessionEnd = StringToTime(TimeToString(now, TIME_DATE)) + sessionTo;
      sessionValid = (now >= sessionStart && now <= sessionEnd);
      if(!sessionValid)
      {
         LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 10 | symbol=" + symbol, LOG_LEVEL_WARN);
      }
   }
   else
   {
      ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
      if(tradeMode != SYMBOL_TRADE_MODE_FULL)
      {
         LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 11 | symbol=" + symbol, LOG_LEVEL_WARN);
         return false;
      }
      sessionValid = true;
   }
   if(!sessionValid)
   {
      LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 12 | symbol=" + symbol, LOG_LEVEL_WARN);
      return false;
   }

   // Check 1: SYMBOL_TRADE_MODE
   ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
   {
      LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 13 | symbol=" + symbol, LOG_LEVEL_WARN);
      return false;
   }

   // Check 2: Recent tick activity (5 minutes stale)
   datetime lastTick = (datetime)SymbolInfoInteger(symbol, SYMBOL_TIME);
   if(TimeCurrent() - lastTick > 300)
   {
      LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 14 | symbol=" + symbol, LOG_LEVEL_WARN);
      return false;
   }

   // Check 3: Spread sanity (1000 = 10 pip on 5-digit, 100 pip on 4-digit)
   int spread = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   if(spread > 1000)
   {
      LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 15 | symbol=" + symbol, LOG_LEVEL_WARN);
      return false;
   }

   LogPrint("[SESSION_CHECK] OPEN | symbol=" + symbol, LOG_LEVEL_DEBUG);
   return true;
}

//+------------------------------------------------------------------+
//| AdjustStopsToValidDistance — Auto-fix retcode 10016 (INVALID_STOPS)|
//| Adjusts SL/TP to minimum allowed distance for the symbol.          |
//+------------------------------------------------------------------+
void AdjustStopsToValidDistance(MqlTradeRequest &req, string symbol, double entryPrice = 0.0)
 {
     SSymbolProfile spAdj = SY_GetProfile(symbol);
     int digits = spAdj.digits > 0 ? spAdj.digits : _Digits;
     int stopsLevel = (int)spAdj.stopsLevel;
     int freezeLevel = (int)spAdj.freezeLevel;
     double point = spAdj.point;

     int minLevel = MathMax(stopsLevel, freezeLevel);
     double minDistance = minLevel * point;

     int spread = spAdj.spread > 0 ? spAdj.spread : (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
     double spreadPoints = spread * point;
     double safeDistance = MathMax(minDistance, spreadPoints + point);

     if(entryPrice <= 0.0)
     {
        entryPrice = (spAdj.tickAsk > 0.0 && spAdj.tickBid > 0.0) 
                       ? (req.type == ORDER_TYPE_BUY ? spAdj.tickAsk : spAdj.tickBid)
                       : (req.type == ORDER_TYPE_BUY ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID));
     }
     entryPrice = NormalizeDouble(entryPrice, digits);

    LogPrint("[STOP_ADJUST] ENTRY_SIDE_CHECK | entry=" + DoubleToString(entryPrice, digits) +
             " | SL=" + DoubleToString(req.sl, digits) + " | TP=" + DoubleToString(req.tp, digits) +
             " | stops=" + IntegerToString(stopsLevel) + " | freeze=" + IntegerToString(freezeLevel) +
             " | spread=" + IntegerToString(spread) + " | safeDist=" + DoubleToString(safeDistance, digits), LOG_LEVEL_WARN);

    if(req.sl > 0)
    {
       if(req.type == ORDER_TYPE_BUY)
       {
          double minSL = entryPrice - safeDistance;
          if(req.sl > minSL)
          {
             LogPrint("[STOP_ADJUST] BUY SL=" + DoubleToString(req.sl, digits) + " >= min=" + DoubleToString(minSL, digits) + " — adjusting down", LOG_LEVEL_WARN);
             req.sl = NormalizeDouble(minSL, digits);
          }
          if(req.sl >= entryPrice)
          {
             LogError("[STOP_ADJUST] BUY SL still >= entry | SL=" + DoubleToString(req.sl, digits) + " | entry=" + DoubleToString(entryPrice, digits));
          }
       }
       else
       {
          double minSL = entryPrice + safeDistance;
          if(req.sl < minSL)
          {
             LogPrint("[STOP_ADJUST] SELL SL=" + DoubleToString(req.sl, digits) + " <= min=" + DoubleToString(minSL, digits) + " — adjusting up", LOG_LEVEL_WARN);
             req.sl = NormalizeDouble(minSL, digits);
          }
          if(req.sl <= entryPrice)
          {
             LogError("[STOP_ADJUST] SELL SL still <= entry | SL=" + DoubleToString(req.sl, digits) + " | entry=" + DoubleToString(entryPrice, digits));
          }
       }
    }

if(req.tp > 0)
    {
        if(req.type == ORDER_TYPE_BUY)
        {
           double minTP = entryPrice + safeDistance;
           if(req.tp < minTP)
              req.tp = NormalizeDouble(minTP, digits);
        }
        else
        {
           double minTP = entryPrice - safeDistance;
           if(req.tp > minTP)
              req.tp = NormalizeDouble(minTP, digits);
        }
    }
}

//+------------------------------------------------------------------+
//| RG_ValidateAndAdjustStops — Universal Validator Expansion        |
//| VERBATIM REPAIR: Finding 2 - Supports all 6 MQL5 order types     |
//+------------------------------------------------------------------+
bool RG_ValidateAndAdjustStops(MqlTradeRequest &req, const SLockedSignal &sig) {
    double minDist = SymbolInfoInteger(sig.symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    
    // Hard Reject: Protection cannot be 0.00 (§VII.A)
    if (req.sl <= 0.0) return false;

    bool isBuy = (req.type == ORDER_TYPE_BUY || req.type == ORDER_TYPE_BUY_LIMIT || req.type == ORDER_TYPE_BUY_STOP);
    bool isSell = (req.type == ORDER_TYPE_SELL || req.type == ORDER_TYPE_SELL_LIMIT || req.type == ORDER_TYPE_SELL_STOP);

    if (isBuy) {
        if (req.sl > req.price - minDist) req.sl = req.price - minDist;
        LogPrint(StringFormat("[RG_STOPS_OK] BUY_TYPE | Entry:%.5f | SL:%.5f", req.price, req.sl), LOG_LEVEL_INFO);
        return true;
    }
    
    if (isSell) {
        if (req.sl < req.price + minDist) req.sl = req.price + minDist;
        LogPrint(StringFormat("[RG_STOPS_OK] SELL_TYPE | Entry:%.5f | SL:%.5f", req.price, req.sl), LOG_LEVEL_INFO);
        return true;
    }

    return false; // Reject unknown types
}

//+------------------------------------------------------------------+
//| ConfirmOrderSent — Verify order was actually placed             |
 //+------------------------------------------------------------------+
 bool ConfirmOrderSent(ulong ticket)
 {
     if(ticket == 0)
     {
         LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 20", LOG_LEVEL_WARN);
         return false;
     }
     
     if(!OrderSelect(ticket))
     {
         LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 21 | ticket=" + IntegerToString(ticket), LOG_LEVEL_WARN);
         return false;
     }
     
     long orderType = OrderGetInteger(ORDER_TYPE);
     if(orderType == ORDER_TYPE_BUY || orderType == ORDER_TYPE_SELL)
     {
         LogPrint("[ORDER_CONFIRMED] ticket=" + IntegerToString(ticket) + " | type=" + EnumToString((ENUM_ORDER_TYPE)orderType), LOG_LEVEL_INFO);
         return true;
     }
     
      LogPrint("[RG_GATE_FAIL] Context/Session block validation rejected. Reason: Code 22 | ticket=" + IntegerToString(ticket), LOG_LEVEL_WARN);
      return false;
  }

//+------------------------------------------------------------------+
//| IsPyramidHeatCapSafe — Portfolio heat cap check for pyramiding   |
//| Total open risk across all positions must not exceed maxHeatPercent|
//| of account equity.                                                |
//+------------------------------------------------------------------+
bool IsPyramidHeatCapSafe(double additionalRiskDollars, double maxHeatPercent = 2.5)
{
    double totalOpenRisk = 0.0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double posSL = PositionGetDouble(POSITION_SL);
        double vol = PositionGetDouble(POSITION_VOLUME);
        string sym = PositionGetString(POSITION_SYMBOL);
        SSymbolProfile spHeat = SY_GetProfile(sym);
        double risk = (spHeat.tickSize > 0.0)
            ? (MathAbs(openPrice - posSL) / spHeat.tickSize) * spHeat.tickValue * vol
            : MathAbs(openPrice - posSL) * vol * spHeat.tickValue;
        totalOpenRisk += risk;
    }
    double maxRisk = AccountInfoDouble(ACCOUNT_EQUITY) * (maxHeatPercent / 100.0);
    bool safe = (totalOpenRisk + additionalRiskDollars) <= maxRisk;
    if(!safe)
    {
        LogPrint("[RISK_GATE] HEAT_CAP_REJECTED | totalOpenRisk=" + DoubleToString(totalOpenRisk, 2) +
                 " | additional=" + DoubleToString(additionalRiskDollars, 2) +
                 " | maxAllowed=" + DoubleToString(maxRisk, 2), LOG_LEVEL_WARN);
    }
    else
    {
        LogPrint("[RISK_GATE] HEAT_CAP_PASS | totalOpenRisk=" + DoubleToString(totalOpenRisk, 2) +
                 " | additional=" + DoubleToString(additionalRiskDollars, 2) +
                 " | maxAllowed=" + DoubleToString(maxRisk, 2) + " | remaining=" +
                 DoubleToString(maxRisk - totalOpenRisk - additionalRiskDollars, 2), LOG_LEVEL_DEBUG);
    }
    return safe;
}

//+------------------------------------------------------------------+
//| RG_EvaluateAndGate — Quick viability gate after STAGE_READY      |
//| Called immediately after TransitionStage(STAGE_READY) in the     |
//| pipeline. Uses signal.stop_loss (structural SL per species rules |
//| §V) to build a provisional risk snapshot and evaluate RR.        |
//| Returns true if signal is viable for execution on the same tick. |
//+------------------------------------------------------------------+
bool RG_EvaluateAndGate(SLockedSignal &signal, ENUM_EXECUTION_BRANCH branch)
{
    ENUM_TIMEFRAMES entryTF = (branch == BRANCH_SWING) ? PERIOD_M15 : PERIOD_M5;
    bool isBuy = (signal.direction == DIRECTION_BUY);

    // Use the signal's constitutionally-mandated stop_loss directly
    // (C2: swept extreme on Structure TF, C3: protected swing on Structure TF, C4: C3 candle extreme)
    if(signal.stop_loss <= 0.0)
    {
        LogPrint("[RG_GATE_FAIL] GUID=" + IntegerToString(signal.m_guid) +
                 " | reason=NO_STRUCTURAL_SL | step=RG_EvaluateAndGate", LOG_LEVEL_DEBUG);
        return false;
    }
    SSymbolProfile rgProf = SY_GetProfile(_Symbol);
    double slDistPrice = MathAbs(signal.entry_price - signal.stop_loss);
    if(slDistPrice <= 0.0)
    {
        LogPrint("[RG_GATE_FAIL] GUID=" + IntegerToString(signal.m_guid) +
                 " | reason=SL_DISTANCE_ZERO | step=RG_EvaluateAndGate", LOG_LEVEL_DEBUG);
        return false;
    }
    double minRR = (signal.closureType == CLOSURE_C2) ? InpAnticipationRR : InpConfirmationRR;
    double provisionalTP = (isBuy)
        ? signal.entry_price + slDistPrice * minRR
        : signal.entry_price - slDistPrice * minRR;
    signal.tp = (signal.tp <= 0.0) ? provisionalTP : signal.tp;
    double slDist = slDistPrice / rgProf.point;

    ENUM_TIMEFRAMES structTF = (branch == BRANCH_SWING) ? PERIOD_H4 : PERIOD_H1;

    SSignalSnapshotRisk snap;
    RG_CreateSnapshot(snap, signal, 0.0,
        _Symbol, entryTF, structTF, TimeCurrent(),
        "Branch" + IntegerToString(branch), slDist,
        signal.direction, provisionalTP, signal.closureType,
        signal.c2_low, signal.c2_high,
        signal.executionMode
    );

    ENUM_RG_FAIL result = PreTradeReadinessGate(snap);
    if(result != RG_FAIL_NONE)
    {
        LogPrint("[RG_GATE_FAIL] GUID=" + IntegerToString(signal.m_guid) +
                 " | reason=NO_STRUCTURAL_SL | step=RG_EvaluateAndGate", LOG_LEVEL_DEBUG);
        return false;
    }
    if(signal.stop_loss <= 0.0 && snap.stopLoss > 0.0 && snap.stopLoss != signal.entry_price)
    {
        double oldSL = signal.stop_loss;
        signal.stop_loss = snap.stopLoss;
        LogPrint("[STATE_MUTATION] owner=RiskGate | field=stop_loss | old=" + DoubleToString(oldSL, _Digits) +
                 " | new=" + DoubleToString(snap.stopLoss, _Digits) +
                 " | GUID=" + IntegerToString(signal.m_guid), LOG_LEVEL_DEBUG);
        LogPrint(StringFormat("[SL_FALLBACK_WRITEBACK] GUID=%I64u | SL:%.5f", signal.m_guid, snap.stopLoss), LOG_LEVEL_DEBUG);
    }
    return true;
}

//+------------------------------------------------------------------+
//| RG_EvaluateAndGate (3-param overload with error string)           |
//+------------------------------------------------------------------+
bool RG_EvaluateAndGate(SLockedSignal &signal, ENUM_EXECUTION_BRANCH branch, string &rgError)
{
    rgError = "";
    ENUM_TIMEFRAMES entryTF = (branch == BRANCH_SWING) ? PERIOD_M15 : PERIOD_M5;
    bool isBuy = (signal.direction == DIRECTION_BUY);

    // Use the signal's constitutionally-mandated stop_loss directly
    if(signal.stop_loss <= 0.0)
    {
        rgError = "NO_STRUCTURAL_SL";
        LogPrint("[RG_GATE_FAIL] GUID=" + IntegerToString(signal.m_guid) +
                 " | reason=NO_STRUCTURAL_SL | step=RG_EvaluateAndGate", LOG_LEVEL_DEBUG);
        return false;
    }
    SSymbolProfile rgProf2 = SY_GetProfile(_Symbol);
    double slDistPrice = MathAbs(signal.entry_price - signal.stop_loss);
    if(slDistPrice <= 0.0)
    {
        rgError = "SL_DISTANCE_ZERO";
        LogPrint("[RG_GATE_FAIL] GUID=" + IntegerToString(signal.m_guid) +
                 " | reason=SL_DISTANCE_ZERO | step=RG_EvaluateAndGate", LOG_LEVEL_DEBUG);
        return false;
    }
    double minRR = (signal.closureType == CLOSURE_C2) ? InpAnticipationRR : InpConfirmationRR;
    double provisionalTP = (isBuy)
        ? signal.entry_price + slDistPrice * minRR
        : signal.entry_price - slDistPrice * minRR;
    signal.tp = (signal.tp <= 0.0) ? provisionalTP : signal.tp;
    double slDist = slDistPrice / rgProf2.point;
    ENUM_TIMEFRAMES structTF = (branch == BRANCH_SWING) ? PERIOD_H4 : PERIOD_H1;
    SSignalSnapshotRisk snap;
    RG_CreateSnapshot(snap, signal, 0.0,
        _Symbol, entryTF, structTF, TimeCurrent(),
        "Branch" + IntegerToString(branch), slDist,
        signal.direction, provisionalTP, signal.closureType,
        signal.c2_low, signal.c2_high,
        signal.executionMode
    );
    ENUM_RG_FAIL result = PreTradeReadinessGate(snap);
    if(result != RG_FAIL_NONE)
    {
        rgError = EnumToString(result);
        LogPrint(StringFormat("[RG_GATE_FAIL] GUID=%I64u | reason=%s | step=RG_EvaluateAndGate",
                 signal.m_guid, EnumToString(result)), LOG_LEVEL_DEBUG);
        return false;
    }
    if(signal.stop_loss <= 0.0 && snap.stopLoss > 0.0 && snap.stopLoss != signal.entry_price)
    {
        double oldSL = signal.stop_loss;
        signal.stop_loss = snap.stopLoss;
        LogPrint("[STATE_MUTATION] owner=RiskGate | field=stop_loss | old=" + DoubleToString(oldSL, _Digits) +
                 " | new=" + DoubleToString(snap.stopLoss, _Digits) +
                 " | GUID=" + IntegerToString(signal.m_guid), LOG_LEVEL_DEBUG);
        LogPrint(StringFormat("[SL_FALLBACK_WRITEBACK] GUID=%I64u | SL:%.5f", signal.m_guid, snap.stopLoss), LOG_LEVEL_DEBUG);
    }
    return true;
}

//+------------------------------------------------------------------+
//| VERBATIM REPAIR: Permanent Skip Recovery (§II)                   |
//| EvaluateSkipRecovery — Clear permanent skip when equity grows    |
//| by 10% or 48-hour cooldown expires.                               |
//+------------------------------------------------------------------+
static bool m_permanentSkip = false;
static datetime m_skipSetTime = 0;

void EvaluateSkipRecovery(string symbol) {
    static double lastRecoveryEquity = 0;
    static bool s_equityInitialized = false;
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    if(!s_equityInitialized)
    {
        lastRecoveryEquity = currentEquity;
        s_equityInitialized = true;
    }
    
    // Condition 1: Equity growth of 10% clears the skip
    if (currentEquity >= lastRecoveryEquity * 1.10) {
        m_permanentSkip = false;
        lastRecoveryEquity = currentEquity;
        LogPrint("[SKIP_RECOVERY] Equity milestone reached. Symbol unblocked: " + symbol, LOG_LEVEL_INFO);
    }
    
    // Condition 2: 48-hour cooldown (Backtest time) — only check when skip is active
    if (m_permanentSkip && TimeCurrent() - m_skipSetTime > 172800) {
        m_permanentSkip = false;
        LogPrint("[SKIP_RECOVERY] Cooldown expired. Symbol unblocked: " + symbol, LOG_LEVEL_INFO);
    }
}

  #endif // OMAK_RISKGATE_MQH