//+------------------------------------------------------------------+
//|                                          OrderManager.mqh |
//|                                    OmakFxYO — Order Manager |
//+------------------------------------------------------------------+
#ifndef OMAK_ORDERMANAGER_MQH
#define OMAK_ORDERMANAGER_MQH

#property strict

#include <OmakFxYO/core/CoreTypes.mqh>
#include <OmakFxYO/core/ModeResolver.mqh>      // EntryMode enum and MODE_* constants
#include <OmakFxYO/core/SignalLifecycle.mqh>
#include <OmakFxYO/core/LogGovernor.mqh>
#include <OmakFxYO/core/LotStabiliser.mqh>
#include <OmakFxYO/core/TradeContext.mqh>
#include <OmakFxYO/core/SpreadFilter.mqh>  // ENUM_SYMBOL_CLASS for asset type detection
#include <OmakFxYO/core/RiskGate.mqh>      // P2 Fix: RG_ValidateAndAdjustStops
#include <Trade\Trade.mqh>

extern int g_totalOrdersSent;  // P5 Fix: Order counter from main file
extern ENUM_EQUITY_GUARD_STATE g_equityGuardState;  // Risk compliance guard state
extern bool g_blockNewEntries;  // Entry block flag from risk engine
// REGRESSION_GUARD_LOT: InpRiskPercent declared as input in OmakFxYO.mq5 — globally visible

//+------------------------------------------------------------------+
//| SLOT MANAGEMENT — Master + Scale-in Coexistence                  |
//+------------------------------------------------------------------+
enum ENUM_POSITION_SLOT
{
   SLOT_NONE = 0,              // No active position
   SLOT_MASTER = 1,           // BACKWARD COMPAT: Primary position (C2 entry) — use SLOT_C2_MASTER
   SLOT_SCALE_IN = 2,         // BACKWARD COMPAT: Pyramid add (C3 entry) without Master — use SLOT_C3_MASTER
   SLOT_MASTER_WITH_SCALEIN = 3, // BACKWARD COMPAT: Both Master and Scale-in active — use SLOT_C2_WITH_SCALEIN
   SLOT_C2_MASTER = 4,        // C2 position active, no scale-ins (STANDALONE)
   SLOT_C3_MASTER = 5,        // C3 position active, no scale-ins (STANDALONE)
   SLOT_C2_WITH_SCALEIN = 6,  // C2 campaign with active scale-ins
   SLOT_C3_WITH_SCALEIN = 7   // C3 campaign with active scale-ins
};

struct SPositionSlot
{
   ENUM_POSITION_SLOT slot;
   ulong masterGuid;
   ulong scaleInGuid;
   datetime masterOpenTime;
   datetime scaleInOpenTime;
   ENUM_CLOSURE_TYPE masterType;
   ENUM_CLOSURE_TYPE scaleInType;

   void Reset()
   {
      slot = SLOT_NONE;
      masterGuid = 0;
      scaleInGuid = 0;
      masterOpenTime = 0;
      scaleInOpenTime = 0;
      masterType = CLOSURE_NONE;
      scaleInType = CLOSURE_NONE;
   }
};

SPositionSlot g_positionSlot;

CTrade g_partialTrade;

//+------------------------------------------------------------------+
//| AdjustStopsToValidDistance — Local overload (double& sl/tp)       |
//| Uses stopsLevel + freezeLevel + spread as minimum safe distance   |
//+------------------------------------------------------------------+
bool AdjustStopsToValidDistance(double &sl, double &tp, ENUM_ORDER_TYPE orderType, string symbol, double entryPrice = 0.0)
{
     if(symbol == "")
        symbol = _Symbol;

     SSymbolProfile spOm = SY_GetProfile(symbol);
     int digits = spOm.digits > 0 ? spOm.digits : (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
     int stopsLevel = (int)spOm.stopsLevel;
     int freezeLevel = (int)spOm.freezeLevel;
     double point = spOm.point;

     int minLevel = MathMax(stopsLevel, freezeLevel);
     double minDistance = minLevel * point;

     int spread = (int)spOm.spread;
     double spreadPoints = spread * point;
     double safeDistance = MathMax(minDistance, spreadPoints + point);

     if(entryPrice <= 0.0)
     {
        double bidPrice = (spOm.tickBid > 0.0) ? spOm.tickBid : SymbolInfoDouble(symbol, SYMBOL_BID);
        double askPrice = (spOm.tickAsk > 0.0) ? spOm.tickAsk : SymbolInfoDouble(symbol, SYMBOL_ASK);
        entryPrice = (orderType == ORDER_TYPE_BUY) ? askPrice : bidPrice;
     }
     entryPrice = NormalizeDouble(entryPrice, digits);

    LogPrint("[STOP_ADJUST] ENTRY_SIDE_CHECK | entry=" + DoubleToString(entryPrice, digits) +
             " | SL=" + DoubleToString(sl, digits) + " | TP=" + DoubleToString(tp, digits) +
             " | stops=" + IntegerToString(stopsLevel) + " | freeze=" + IntegerToString(freezeLevel) +
             " | spread=" + IntegerToString(spread) + " | safeDist=" + DoubleToString(safeDistance, 5), LOG_LEVEL_WARN);

    bool adjusted = false;
    if(sl > 0)
    {
       if(orderType == ORDER_TYPE_BUY)
       {
          double minSL = entryPrice - safeDistance;
          if(sl > minSL)
          {
             LogPrint("[STOP_ADJUST] BUY SL=" + DoubleToString(sl, digits) + " >= min=" + DoubleToString(minSL, digits) + " — adjusting down", LOG_LEVEL_WARN);
             sl = NormalizeDouble(minSL, digits);
             adjusted = true;
          }
          if(sl >= entryPrice)
          {
             LogError("[STOP_ADJUST] BUY SL still >= entry after adjustment | SL=" + DoubleToString(sl, digits) + " | entry=" + DoubleToString(entryPrice, digits));
             return false;
          }
       }
       else
       {
          double minSL = entryPrice + safeDistance;
          if(sl < minSL)
          {
             LogPrint("[STOP_ADJUST] SELL SL=" + DoubleToString(sl, digits) + " <= min=" + DoubleToString(minSL, digits) + " — adjusting up", LOG_LEVEL_WARN);
             sl = NormalizeDouble(minSL, digits);
             adjusted = true;
          }
          if(sl <= entryPrice)
          {
             LogError("[STOP_ADJUST] SELL SL still <= entry after adjustment | SL=" + DoubleToString(sl, digits) + " | entry=" + DoubleToString(entryPrice, digits));
             return false;
          }
       }
    }

    if(tp > 0)
    {
       if(orderType == ORDER_TYPE_BUY)
       {
          double minTP = entryPrice + safeDistance;
          if(tp < minTP)
          {
             tp = NormalizeDouble(minTP, digits);
             adjusted = true;
          }
       }
       else
       {
          double minTP = entryPrice - safeDistance;
          if(tp > minTP)
          {
             tp = NormalizeDouble(minTP, digits);
             adjusted = true;
          }
       }
    }

    if(sl > 0 && tp > 0)
    {
       if(orderType == ORDER_TYPE_BUY && sl >= tp)
       {
          LogPrint("[STOP_ADJUST] BUY SL >= TP after adjustment — invalid", LOG_LEVEL_ERROR);
          return false;
       }
       if(orderType == ORDER_TYPE_SELL && sl <= tp)
       {
          LogPrint("[STOP_ADJUST] SELL SL <= TP after adjustment — invalid", LOG_LEVEL_ERROR);
          return false;
       }
    }

    return true;
}

//+------------------------------------------------------------------+
//| ExecutePartialClose — Scale-out portion of position              |
//+------------------------------------------------------------------+
bool ExecutePartialClose(ulong positionTicket, double closePercent,
                         bool moveSLToBE, string &outError)
{
   if(!PositionSelectByTicket(positionTicket))
   {
      outError = "[PARTIAL_CLOSE_FAIL] Position not found | ticket=" + IntegerToString(positionTicket);
      return false;
   }
   
double currentVolume = PositionGetDouble(POSITION_VOLUME);
    double closeVolume = NormalizeDouble(currentVolume * closePercent, 2);
    SSymbolProfile spPartial = SY_GetProfile(_Symbol);
    double lotStep = spPartial.volumeStep;
    closeVolume = MathFloor(closeVolume / lotStep) * lotStep;
   
   if(closeVolume <= 0 || closeVolume > currentVolume)
   {
      outError = "[PARTIAL_CLOSE_FAIL] Invalid volume";
      return false;
   }
   
   if(!g_partialTrade.PositionClosePartial(positionTicket, closeVolume, 10))
   {
      outError = "[PARTIAL_CLOSE_FAIL] Trade failed | retcode=" +
                IntegerToString(g_partialTrade.ResultRetcode());
      return false;
   }
   
   LogPrint("[PARTIAL_CLOSE_OK] ticket=" + IntegerToString(positionTicket) +
            " | closed=" + DoubleToString(closeVolume, 2) +
            " | percent=" + DoubleToString(closePercent * 100, 0) + "%",
            LOG_LEVEL_INFO);
   
   if(moveSLToBE)
   {
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      MqlTradeRequest beRequest = {};
      MqlTradeResult beResult = {};
      beRequest.action = TRADE_ACTION_SLTP;
      beRequest.position = positionTicket;
      beRequest.symbol = _Symbol;
      beRequest.sl = NormalizeDouble(entryPrice, _Digits);
      beRequest.tp = PositionGetDouble(POSITION_TP);
      
      if(OrderSend(beRequest, beResult))
         LogPrint("[BE_OK] SL moved to breakeven | entry=" +
                  DoubleToString(entryPrice, _Digits), LOG_LEVEL_INFO);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| MonitorTPLevels — Mode-aware scale-out at TP levels              |
//| Anticipation (C2): 50% at TP1, BE at 0.75R                        |
//| Confirmation (C3): 33% at TP1, BE at 1.50R                        |
//+------------------------------------------------------------------+
void MonitorTPLevels()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      ulong posMagic = (ulong)PositionGetInteger(POSITION_MAGIC);

      // Determine mode from signal store
      int posMode = MODE_NONE;
      for(int s = 0; s < MAX_TOTAL_SIGNALS_PER_BRANCH; s++)
      {
         if(g_hasActiveSignal[s] && g_activeSignal[s].m_guid == posMagic)
         {
            posMode = g_activeSignal[s].executionMode;
            break;
         }
      }

      double beTriggerR = (posMode == MODE_ANTICIPATION) ? InpBETriggerR_Anticipation : InpBETriggerR_Confirmation;
      double partialPct = (posMode == MODE_ANTICIPATION) ? (InpPartialClosePct_Anticipation / 100.0) : (InpPartialClosePct_Confirmation / 100.0);
      string modeStr = (posMode == MODE_ANTICIPATION) ? "ANTICIPATION" : "CONFIRMATION";

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double riskPoints = 0.0;

      // Calculate risk points for R calculation
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(posType == POSITION_TYPE_BUY)
         riskPoints = entry - currentSL;
      else
         riskPoints = currentSL - entry;

      if(riskPoints <= 0) continue;

      double currentPrice = (posType == POSITION_TYPE_BUY) ?
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // Calculate current profit in R
      double profitR = 0.0;
      if(posType == POSITION_TYPE_BUY)
         profitR = (currentPrice - entry) / riskPoints;
      else
         profitR = (entry - currentPrice) / riskPoints;

      // Check if we need to move to breakeven
      bool beMoved = (posType == POSITION_TYPE_BUY && currentSL >= entry) ||
                      (posType == POSITION_TYPE_SELL && currentSL <= entry);

      if(!beMoved && profitR >= beTriggerR)
      {
         // Move SL to breakeven
         double newSL = NormalizeDouble(entry, _Digits);
         MqlTradeRequest modReq = {};
         MqlTradeResult modRes = {};
         modReq.action = TRADE_ACTION_SLTP;
         modReq.position = ticket;
         modReq.symbol = _Symbol;
         modReq.sl = newSL;
          // REGRESSION_GUARD_DEVIATION: Dynamic point-scaled — works for all symbols
          modReq.deviation = (ulong)(SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 30);
         modReq.magic = (int)posMagic;
         modReq.comment = "MonitorTP|BE";

         if(OrderSend(modReq, modRes))
         {
            LogPrint("[MONITOR_TP] BE moved | ticket=" + IntegerToString(ticket) + " | mode=" + modeStr + " | profitR=" + DoubleToString(profitR, 2) + " | beTriggerR=" + DoubleToString(beTriggerR, 2), LOG_LEVEL_INFO);
         }
      }

      // Check TP hit for partial close
      double tp = PositionGetDouble(POSITION_TP);
      bool tpHit = false;
      if(posType == POSITION_TYPE_BUY)
         tpHit = (currentPrice >= tp);
      else
         tpHit = (currentPrice <= tp);

      if(tpHit)
      {
         string error = "";
         ExecutePartialClose(ticket, partialPct, true, error);
         LogPrint("[MONITOR_TP] Partial close | ticket=" + IntegerToString(ticket) + " | mode=" + modeStr + " | pct=" + DoubleToString(partialPct * 100, 1) + "%", LOG_LEVEL_INFO);
      }
   }
}

//+------------------------------------------------------------------+
//| SYMBOLETIC/CRYPTO P/L CALCULATION — Production Grade            |
//+------------------------------------------------------------------+

/**
 * OM_GetTickSize — Get tick size for symbol
 *
 * @param symbol Symbol name
 * @return Tick size (price precision)
 */
double OM_GetTickSize(const string symbol)
{
    SSymbolProfile spTick = SY_GetProfile(symbol);
    if(spTick.tickSize > 0.0)
        return spTick.tickSize;
    return (spTick.point > 0.0) ? spTick.point : 0.00001;
}

/**
 * OM_GetTickValue — Get tick value for symbol (in account currency)
 *
 * @param symbol Symbol name
 * @return Tick value per lot
 */
double OM_GetTickValue(const string symbol)
{
    SSymbolProfile spTickVal = SY_GetProfile(symbol);
    if(spTickVal.tickValue > 0.0)
        return spTickVal.tickValue;
    return 0.0; // No fallback - explicit failure
}

/**
 * OM_CalculateProfit — Calculate profit in account currency using TickSize/TickValue
 *
 * Production-grade accuracy for Vix75 and Crypto.
 *
 * @param symbol Symbol name
 * @param direction DIRECTION_BUY or DIRECTION_SELL
 * @param entryPrice Entry price
 * @param currentPrice Current market price
 * @param lot Lot size
 * @return Profit in account currency
 */
double OM_CalculateProfit(const string symbol, ENUM_DIRECTION direction,
                         double entryPrice, double currentPrice, double lot)
{
   double tickSize = OM_GetTickSize(symbol);
   double tickValue = OM_GetTickValue(symbol);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(tickSize <= 0.0 || tickValue <= 0.0 || point <= 0.0)
   {
      LogPrint("[PROFIT] Invalid tick data | tickSize=" + DoubleToString(tickSize, 8) +
                " | tickValue=" + DoubleToString(tickValue, 8), LOG_LEVEL_WARN);
      return 0.0;
   }

   double priceDiff;
   if(direction == DIRECTION_BUY)
      priceDiff = currentPrice - entryPrice;
   else
      priceDiff = entryPrice - currentPrice;

   double tickDiff = priceDiff / tickSize;
   double profit = tickDiff * tickValue * lot;

   ENUM_SYMBOL_CLASS symbolClass = DetectSymbolClass(symbol);
   LogPrint("[PROFIT] " + EnumToString(symbolClass) + " | entry=" + DoubleToString(entryPrice, _Digits) +
            " | current=" + DoubleToString(currentPrice, _Digits) +
            " | tickDiff=" + DoubleToString(tickDiff, 2) +
            " | profit=" + DoubleToString(profit, 2), LOG_LEVEL_DEBUG);

   return profit;
}

/**
 * OM_IsMasterSlotOpen — Check if Master (C2) slot is occupied
 *
 * @return true if Master position exists
 */
bool OM_IsMasterSlotOpen()
{
   return (g_positionSlot.slot == SLOT_C2_MASTER || 
           g_positionSlot.slot == SLOT_C2_WITH_SCALEIN ||
           g_positionSlot.slot == SLOT_C3_MASTER || 
           g_positionSlot.slot == SLOT_C3_WITH_SCALEIN);
}

bool OM_IsScaleInSlotOpen()
{
    // Updated for new slot enum
    // BACKWARD COMPAT: SLOT_MASTER_WITH_SCALEIN -> SLOT_C2_WITH_SCALEIN
    return (g_positionSlot.slot == SLOT_C2_WITH_SCALEIN ||
            g_positionSlot.slot == SLOT_C3_WITH_SCALEIN);
}

/**
 * OM_CanOpenMasterSlot — Check if Master slot can be opened
 *
 * Allows C2 Master position if:
 * - No existing Master position, OR
 * - Existing is a Scale-in (different closure type allowed)
 *
 * @param closureType CLOSURE_C2 for Master entry
 * @return true if Master slot available
 */
bool OM_CanOpenMasterSlot(ENUM_CLOSURE_TYPE closureType)
{
   if(closureType == CLOSURE_C2)
   {
      return (g_positionSlot.slot != SLOT_C2_MASTER && 
              g_positionSlot.slot != SLOT_C2_WITH_SCALEIN);
   }
   else if(closureType == CLOSURE_C3)
   {
      return (g_positionSlot.slot != SLOT_C3_MASTER && 
              g_positionSlot.slot != SLOT_C3_WITH_SCALEIN);
   }
   LogPrint("[SLOT] Master blocked | unknown closure=" + EnumToString(closureType), LOG_LEVEL_DEBUG);
   return false;
}

/**
 * OM_CanOpenScaleInSlot — Check if Scale-in slot can be opened
 *
 * Allows C3 Scale-in if Master (C2) already exists AND
 * Dow Theory Trend is confirmed (same direction).
 *
 * @param closureType CLOSURE_C3 for Scale-in entry
 * @param direction Trade direction
 * @return true if Scale-in slot available
 */
bool OM_CanOpenScaleInSlot(ENUM_CLOSURE_TYPE closureType, ENUM_DIRECTION direction)
{
   if(closureType != CLOSURE_C3)
      return false;

   return (g_positionSlot.slot == SLOT_C2_MASTER ||
           g_positionSlot.slot == SLOT_C2_WITH_SCALEIN ||
           g_positionSlot.slot == SLOT_C3_MASTER ||
           g_positionSlot.slot == SLOT_C3_WITH_SCALEIN);
}

/**
 * OM_AssignSlot — Assign position to slot (Master or Scale-in)
 *
 * @param closureType CLOSURE_C2 (Master) or CLOSURE_C3 (Scale-in)
 * @param guid Signal GUID
 */
void OM_AssignSlot(ENUM_CLOSURE_TYPE closureType, ulong guid)
{
   if(closureType == CLOSURE_C2)
   {
      if(g_positionSlot.slot == SLOT_C3_MASTER || g_positionSlot.slot == SLOT_C3_WITH_SCALEIN)
      {
         g_positionSlot.slot = SLOT_C3_WITH_SCALEIN;
      }
      else
      {
         g_positionSlot.slot = SLOT_C2_MASTER;
      }
      g_positionSlot.masterGuid = guid;
      g_positionSlot.masterOpenTime = TimeCurrent();
      g_positionSlot.masterType = CLOSURE_C2;
      LogPrint(StringFormat("[SLOT] C2 assigned | GUID=%I64u | slot=%s", guid, EnumToString(g_positionSlot.slot)), LOG_LEVEL_INFO);
   }
   else if(closureType == CLOSURE_C3)
   {
      if(g_positionSlot.slot == SLOT_C2_MASTER || g_positionSlot.slot == SLOT_C2_WITH_SCALEIN)
      {
         g_positionSlot.slot = SLOT_C2_WITH_SCALEIN;
      }
      else if(g_positionSlot.slot == SLOT_C3_MASTER)
      {
         g_positionSlot.slot = SLOT_C3_WITH_SCALEIN;
      }
      else
      {
         g_positionSlot.slot = SLOT_C3_MASTER;
      }
      g_positionSlot.scaleInGuid = guid;
      g_positionSlot.scaleInOpenTime = TimeCurrent();
      g_positionSlot.scaleInType = CLOSURE_C3;
      LogPrint(StringFormat("[SLOT] C3 assigned | GUID=%I64u | slot=%s", guid, EnumToString(g_positionSlot.slot)), LOG_LEVEL_INFO);
   }
}

/**
 * OM_ClearSlot — Clear position slot
 *
 * @param guid GUID of position being closed (matches slot GUID)
 */
void OM_ClearSlot(ulong guid)
{
   if(PositionsTotal() == 0)
   {
         if(g_positionSlot.slot != SLOT_NONE)
         {
            g_positionSlot.Reset();
            LogPrint("[SLOT] Force reset (PositionsTotal == 0)", LOG_LEVEL_WARN);
         }
       return;
   }

   if(g_positionSlot.masterGuid == guid)
   {
      if(g_positionSlot.scaleInGuid != 0)
      {
         if(g_positionSlot.scaleInType == CLOSURE_C3)
         {
            g_positionSlot.slot = SLOT_C3_MASTER;
         }
         else
         {
            g_positionSlot.slot = SLOT_C2_MASTER;
         }
         g_positionSlot.masterGuid = g_positionSlot.scaleInGuid;
         g_positionSlot.masterOpenTime = g_positionSlot.scaleInOpenTime;
         g_positionSlot.masterType = g_positionSlot.scaleInType;
         g_positionSlot.scaleInGuid = 0;
         g_positionSlot.scaleInOpenTime = 0;
         g_positionSlot.scaleInType = CLOSURE_NONE;
         LogPrint("[SLOT] Master closed, promoted Scale-in to Master", LOG_LEVEL_INFO);
      }
      else
      {
         g_positionSlot.Reset();
         LogPrint("[SLOT] All positions closed", LOG_LEVEL_INFO);
      }
   }
   else if(g_positionSlot.scaleInGuid == guid)
   {
      if(g_positionSlot.masterGuid != 0)
      {
         if(g_positionSlot.masterType == CLOSURE_C2)
         {
            g_positionSlot.slot = SLOT_C2_MASTER;
         }
         else
         {
            g_positionSlot.slot = SLOT_C3_MASTER;
         }
         g_positionSlot.scaleInGuid = 0;
         g_positionSlot.scaleInOpenTime = 0;
         g_positionSlot.scaleInType = CLOSURE_NONE;
         LogPrint("[SLOT] Scale-in closed, Master remains", LOG_LEVEL_INFO);
      }
      else
      {
         g_positionSlot.Reset();
         LogPrint("[SLOT] All positions closed", LOG_LEVEL_INFO);
      }
   }
}

//+------------------------------------------------------------------+
//| Global Execution Variables                                        |
//+------------------------------------------------------------------+
ulong   g_current_signal_guid = 0;
int     g_retry_count = 0;
ulong   g_signal_start_time = 0;
datetime g_last_request_time = 0;

#define MAX_SIGNAL_RETRIES       2
#define SIGNAL_TIMEOUT_MS        30000  // 30 second timeout

//+------------------------------------------------------------------+
//| Real Execution Gate                                              |
//+------------------------------------------------------------------+
/**
 * ExecutionGatePass — Validates all pre-execution conditions
 *
 * Gate Location: Immediately before OrderSend in ExecuteOrder()
 *                Immediately before execution attempt in OmakFxYO.mq5
 *
 * Checks (all must pass):
 *   1. signal.stage == STAGE_READY
 *   2. signal.isCommitted == true
 *   3. RG_GATE has already passed (caller responsibility)
 *   4. OrderCheck has already passed (caller responsibility)
 *   5. signal is not expired
 *   6. signal is not already executed
 *   7. signal has valid execution mode / context
 *
 * Branch Safety: Uses signal-specific GUID and branch context,
 *                no cross-contamination between Branch A and B.
 */

//+------------------------------------------------------------------+
//| IsValidStopLoss — Direction-aware SL validation before OrderSend  |
//+------------------------------------------------------------------+
bool IsValidStopLoss(double entryPrice, double sl, ENUM_SIGNAL_DIRECTION direction)
{
    if(entryPrice <= 0.0 || sl <= 0.0 || direction == SIGNAL_NONE)
       return false;
    
    if(direction == SIGNAL_BULLISH && sl >= entryPrice)
    {
       LogError("[RG_PRECHECK] BUY SL >= entry | sl=" + DoubleToString(sl, _Digits) + " | entry=" + DoubleToString(entryPrice, _Digits));
       return false;
    }
    if(direction == SIGNAL_BEARISH && sl <= entryPrice)
    {
       LogError("[RG_PRECHECK] SELL SL <= entry | sl=" + DoubleToString(sl, _Digits) + " | entry=" + DoubleToString(entryPrice, _Digits));
       return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| GetRetcodeDescription — Convert MQL5 trade return code to string  |
//+------------------------------------------------------------------+
string GetRetcodeDescription(uint retcode)
{
   switch(retcode)
   {
      case TRADE_RETCODE_REQUOTE:          return "REQUOTE";
      case TRADE_RETCODE_REJECT:           return "REJECT";
      case TRADE_RETCODE_CANCEL:           return "CANCEL";
      case TRADE_RETCODE_PLACED:           return "PLACED";
      case TRADE_RETCODE_DONE:             return "DONE";
      case TRADE_RETCODE_DONE_PARTIAL:     return "DONE_PARTIAL";
      case TRADE_RETCODE_ERROR:            return "ERROR";
      case TRADE_RETCODE_TIMEOUT:          return "TIMEOUT";
      case TRADE_RETCODE_INVALID:          return "INVALID";
      case TRADE_RETCODE_INVALID_VOLUME:   return "INVALID_VOLUME";
      case TRADE_RETCODE_INVALID_PRICE:    return "INVALID_PRICE";
      case TRADE_RETCODE_INVALID_STOPS:    return "INVALID_STOPS";
      case TRADE_RETCODE_TRADE_DISABLED:   return "TRADE_DISABLED";
      case TRADE_RETCODE_MARKET_CLOSED:    return "MARKET_CLOSED";
      case TRADE_RETCODE_NO_MONEY:         return "NO_MONEY";
      case TRADE_RETCODE_PRICE_CHANGED:    return "PRICE_CHANGED";
      case TRADE_RETCODE_PRICE_OFF:        return "PRICE_OFF";
      case TRADE_RETCODE_INVALID_EXPIRATION: return "INVALID_EXPIRATION";
      case TRADE_RETCODE_ORDER_CHANGED:    return "ORDER_CHANGED";
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return "TOO_MANY_REQUESTS";
      case TRADE_RETCODE_NO_CHANGES:       return "NO_CHANGES";
      case TRADE_RETCODE_SERVER_DISABLES_AT: return "SERVER_DISABLES_AT";
      case TRADE_RETCODE_CLIENT_DISABLES_AT: return "CLIENT_DISABLES_AT";
      case TRADE_RETCODE_LOCKED:           return "LOCKED";
      case TRADE_RETCODE_FROZEN:           return "FROZEN";
      case TRADE_RETCODE_INVALID_FILL:     return "INVALID_FILL";
      case TRADE_RETCODE_CONNECTION:       return "CONNECTION";
      case TRADE_RETCODE_ONLY_REAL:        return "ONLY_REAL";
      case TRADE_RETCODE_LIMIT_ORDERS:     return "LIMIT_ORDERS";
      case TRADE_RETCODE_LIMIT_VOLUME:     return "LIMIT_VOLUME";
      case TRADE_RETCODE_INVALID_ORDER:    return "INVALID_ORDER";
      case TRADE_RETCODE_POSITION_CLOSED:  return "POSITION_CLOSED";
      case 10038:                          return "INVALID_CLOSE_VOLUME";
      case 10039:                          return "CLOSE_ORDER_EXIST";
      case TRADE_RETCODE_LIMIT_POSITIONS:  return "LIMIT_POSITIONS";
      case TRADE_RETCODE_HEDGE_PROHIBITED: return "HEDGE_PROHIBITED";
      default:                             return "UNKNOWN(" + IntegerToString(retcode) + ")";
   }
}

//+------------------------------------------------------------------+
//| ExecutionGatePass — Final pre-execution validation gate           |
//+------------------------------------------------------------------+
bool ExecutionGatePass(SLockedSignal &signal, ENUM_EXECUTION_BRANCH branch)
{
    // === PHASE 4: Enhanced Execution Gate Entrance Telemetry ===
    string modeStr = (signal.executionMode == MODE_ANTICIPATION) ? "ANTICIPATION" :
                    (signal.executionMode == MODE_CONFIRMATION) ? "CONFIRMATION" : "NONE";
    
    // [EXEC_TRIGGER] Execution gate triggered
    LogPrint("[EXEC_TRIGGER] GUID=" + IntegerToString(signal.m_guid) +
             " | closure=" + EnumToString(signal.closureType) +
             " | candidateEntry=" + DoubleToString(signal.candidateEntryPrice, _Digits) +
             " | stopLoss=" + DoubleToString(signal.stop_loss, _Digits), LOG_LEVEL_INFO);

    // Log incoming state at the final gate to confirm if the Store is holding the data
    LGovPrint("[EXEC_GATE] ENTER | guid=" + IntegerToString(signal.m_guid) +
             " | mode=" + modeStr + "[" + IntegerToString(signal.executionMode) + "]" +
             " | closure=" + EnumToString(signal.closureType) +
             " | stage=" + EnumToString(signal.stage) +
             " | isCommitted=" + (signal.isCommitted ? "TRUE" : "FALSE") +
             " | entry_price=" + DoubleToString(signal.entry_price, _Digits),
             LOG_LEVEL_INFO);
    
    Print("[GATE_ENTRY] GUID:", signal.m_guid, " | Mode:", modeStr, " | Closure:", EnumToString(signal.closureType), " | Stage:", EnumToString(signal.stage));

    // [RG_GATE] At RG gate evaluation entry
    LogPrint("[RG_GATE] Evaluating | GUID=" + IntegerToString(signal.m_guid) +
             " | stage=" + EnumToString(signal.stage) +
             " | mode=" + modeStr, LOG_LEVEL_DEBUG);

    // REGRESSION GUARD: Log EXECUTION_GATE mode evaluation
    LogPrint("[EXEC_GATE_EVAL] GUID:" + IntegerToString(signal.m_guid) +
            " | executionMode=" + modeStr + "[" + IntegerToString(signal.executionMode) + "]" +
            " | closure=" + EnumToString(signal.closureType) +
            " | stage=" + EnumToString(signal.stage), LOG_LEVEL_DEBUG);

    // Declare local execution variables (compilation fix — undeclared identifiers)
    // REGRESSION_GUARD_V52.5_ORDERMANAGER_LOCALS
    double minLot = 0.0, maxLot = 0.0, lotStep = 0.0;
    string symbol = _Symbol;
    double lot = 0.0;
    double entryPrice = signal.entry_price;
    double stopLoss = signal.stop_loss;
    double takeProfit = signal.tp;
    ENUM_SIGNAL_DIRECTION direction = (signal.direction == DIRECTION_BUY) ? SIGNAL_BULLISH :
                                      (signal.direction == DIRECTION_SELL) ? SIGNAL_BEARISH : SIGNAL_NONE;
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    MqlTradeRequest request = {};

    // REGRESSION INVARIANT: Mode must not be zero after lock
    if(signal.stage == STAGE_READY && signal.executionMode == MODE_NONE)
    {
        LogPrint("[ASSERTION_FAIL] INVARIANT_BROKEN: Mode=MODE_NONE on READY signal | GUID:" + IntegerToString(signal.m_guid), LOG_LEVEL_ERROR);
    }

    // REGRESSION INVARIANT: entry_price must be valid at execution gate
    if(signal.entry_price <= 0.0)
    {
        LogPrint("[ASSERTION_FAIL] INVARIANT_BROKEN: entry_price=0 at EXECUTION_GATE | GUID:" + IntegerToString(signal.m_guid), LOG_LEVEL_ERROR);
    }

    // STRICT VALIDATION: Source of truth enforcement
    if(signal.m_guid == 0 || !signal.isCommitted)
    {
        LogPrint("[EXEC_GATE_FAIL] reason=INVALID_SIGNAL_STATE | guid=" + IntegerToString(signal.m_guid), LOG_LEVEL_ERROR);
        return false;
    }

    bool execResult = true;

    // Gate 1: Signal stage must be READY
    if(signal.stage != STAGE_READY)
    {
        LogPrint("[EXEC_GATE_FAIL] reason=STAGE_NOT_READY | guid=" + IntegerToString(signal.m_guid) +
                " | stage=" + EnumToString(signal.stage), LOG_LEVEL_ERROR);
        execResult = false;
    }
    else
    // Gate 2: Signal must be committed
    if(!signal.isCommitted)
    {
        LogPrint("[EXEC_GATE_FAIL] reason=NOT_COMMITTED | guid=" + IntegerToString(signal.m_guid), LOG_LEVEL_ERROR);
        execResult = false;
    }
    else
    // Gate 3: Signal must not be expired
    if(signal.IsExpired())
    {
        LogPrint("[EXEC_GATE_FAIL] reason=SIGNAL_EXPIRED | guid=" + IntegerToString(signal.m_guid), LOG_LEVEL_ERROR);
        execResult = false;
    }
    else
    // Gate 4: Signal must not be already executed
    if(signal.stage == STAGE_EXECUTED)
    {
        LogPrint("[EXEC_GATE_FAIL] reason=ALREADY_EXECUTED | guid=" + IntegerToString(signal.m_guid), LOG_LEVEL_ERROR);
        execResult = false;
    }
    else
    // Gate 5: Retry cap check - prevent excessive execution attempts
    if(signal.IsRetryCapReached())
    {
        LogPrint("[EXEC_GATE_FAIL] reason=RETRY_CAP_REACHED | guid=" + IntegerToString(signal.m_guid) +
                " | attempts=" + IntegerToString(signal.executionAttempts), LOG_LEVEL_ERROR);
        execResult = false;
    }
    else
    // Gate 6: Signal direction must be valid (BUY or SELL)
    if(signal.direction != DIRECTION_BUY && signal.direction != DIRECTION_SELL)
    {
        LogPrint("[EXEC_GATE_FAIL] reason=INVALID_DIRECTION | guid=" + IntegerToString(signal.m_guid) +
                " | dir=" + EnumToString(signal.direction), LOG_LEVEL_ERROR);
        execResult = false;
    }
    else
    // Gate 7: Execution mode must be valid (not MODE_NONE)
    // FIXED: Enhanced diagnostics + mode inference as last resort
    // [MODE_BLOCKED] Signal rejected - executionMode not set by pipeline
    // Mode must be resolved by ModeResolver before reaching OrderManager
    if(signal.executionMode == MODE_NONE)
    {
        // Mode was not set by the pipeline - reject signal, do not infer from closureType
        string modeDebug = "[EXEC_GATE_FAIL] reason=MODE_NOT_RESOLVED | guid=" + IntegerToString(signal.m_guid)
                         + " | stage=" + EnumToString(signal.stage)
                         + " | closure=" + EnumToString(signal.closureType)
                         + " | committed=" + (signal.isCommitted ? "Y" : "N")
                         + " | entry=" + DoubleToString(signal.entry_price, _Digits)
                         + " | sl=" + DoubleToString(signal.stop_loss, _Digits);
        LogPrint(modeDebug, LOG_LEVEL_WARN);
        execResult = false;
    }
    else
    {
        // Fallback to snapshot values - gate already validated these
SSignalSnapshotRisk snap = RG_GetSnapshot();
    minLot = snap.minLot;
    maxLot = snap.maxLot;
    lotStep = snap.lotStep;
    lot = snap.baseLot; // REGRESSION_GUARD_V52.5_SNAPSHOT_LOT
    }

    // Snapshot validation: values must be valid (validated at gate)
    if(minLot <= 0.0 || lotStep <= 0.0 || maxLot <= 0.0)
    {
        Print("[SNAPSHOT_FALLBACK] Invalid snapshot — querying profile");
        SSymbolProfile spSnap = SY_GetProfile(symbol);
        minLot = spSnap.volumeMin;
        maxLot = spSnap.volumeMax;
        lotStep = spSnap.volumeStep;
        
        Print("[SNAPSHOT_FALLBACK] minLot=", DoubleToString(minLot, 4),
              " maxLot=", DoubleToString(maxLot, 4),
              " step=", DoubleToString(lotStep, 4),
              " tickVal=", DoubleToString(spSnap.tickValue, 6),
              " tickSz=", DoubleToString(spSnap.tickSize, 6));
        
        // If still invalid after live query, then hard fail with RISK_FLOOR_BLOCK
        if(minLot <= 0.0)
        {
            LogPrint("[RISK_FLOOR_BLOCK] GUID=" + IntegerToString(signal.m_guid) +
                     " | reason=SNAPSHOT_MINLOT_ZERO" +
                     " | equity=" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) +
                     " | calculatedLot=0.0" +
                     " | rejectionOwner=OrderManager.ExecutionGatePass" +
                     " | minLot=" + DoubleToString(minLot, 4) +
                     " | maxLot=" + DoubleToString(maxLot, 4) +
                     " | step=" + DoubleToString(lotStep, 4), LOG_LEVEL_ERROR);
            LogError("[ORDER] INVALID_SNAPSHOT_CTX | minLot=" + DoubleToString(minLot, 4) + " maxLot=" + DoubleToString(maxLot, 4) + " step=" + DoubleToString(lotStep, 4));
            if(TC_IsValid())
                TC_MarkFailed("SNAPSHOT_INVALID");
            return false;
        }
    }

    // CONTRACT: invalid lot must remain invalid - NO upward clamp
    if(lot < minLot || lot <= 0.0)
    {
        LogPrint("[RISK_FLOOR_BLOCK] GUID=" + IntegerToString(signal.m_guid) +
                 " | reason=LOT_BELOW_MINLOT_PRE_STAB" +
                 " | lot=" + DoubleToString(lot, 8) +
                 " | minLot=" + DoubleToString(minLot, 8) +
                 " | closure=" + EnumToString(signal.closureType), LOG_LEVEL_WARN);
        LogPrint("[RISK_NOT_TRADEABLE] lot=" + DoubleToString(lot, 8) + " < minLot=" + DoubleToString(minLot, 8) +
                 " | maxLot=" + DoubleToString(maxLot, 8) +
                 " | step=" + DoubleToString(lotStep, 8) +
                 " | equity=" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) +
                 " | entry=" + DoubleToString(entryPrice, _Digits) +
                 " | sl=" + DoubleToString(stopLoss, _Digits) +
                 " | closure=" + EnumToString(signal.closureType), LOG_LEVEL_WARN);
        LogWarn("[ORDER] LOT_REJECTED | LOT=" + DoubleToString(lot, 8) + " MIN=" + DoubleToString(minLot, 8));
        return false;
    }

    LogPrint("[RISK_TRADEABLE] lot=" + DoubleToString(lot, 8) + " >= minLot=" + DoubleToString(minLot, 8), LOG_LEVEL_DEBUG);

    // STABILISATION GATE — enforce cap only and align to step
    lot = StabiliseLot(lot, minLot, maxLot, lotStep, symbol);

    // Post-stabilisation minLot check — StabiliseLot can round below minLot
    if(lot <= 0.0 || lot < minLot)
    {
        LogPrint("[RISK_FLOOR_BLOCK] GUID=" + IntegerToString(signal.m_guid) +
                 " | reason=LOT_BELOW_MINLOT_POST_STAB" +
                 " | lot=" + DoubleToString(lot, 8) +
                 " | minLot=" + DoubleToString(minLot, 8) +
                 " | closure=" + EnumToString(signal.closureType), LOG_LEVEL_WARN);
        LogPrint("[RISK_NOT_TRADEABLE] Post-stab lot=" + DoubleToString(lot, 8) +
                 " < minLot=" + DoubleToString(minLot, 8) +
                 " | maxLot=" + DoubleToString(maxLot, 8) +
                 " | step=" + DoubleToString(lotStep, 8) +
                 " | equity=" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) +
                 " | entry=" + DoubleToString(entryPrice, _Digits) +
                 " | sl=" + DoubleToString(stopLoss, _Digits), LOG_LEVEL_WARN);
        LogWarn("[ORDER] LOT_REJECTED | POST_STAB | LOT=" + DoubleToString(lot, 8) + " MIN=" + DoubleToString(minLot, 8));
        return false;
    }

    if(TC_IsValid())
    {
        TraceLot("FINAL");
    }

// Validate SL distance against BOTH stopsLevel and freezeLevel (from profile)
    SSymbolProfile spExec = SY_GetProfile(symbol);
    double slDistance = 0.0;
    if(stopLoss > 0.0 && entryPrice > 0.0)
       slDistance = MathAbs(entryPrice - stopLoss);

    long stopsLevel = spExec.stopsLevel;
    long freezeLevel = spExec.freezeLevel;
    int minLevel = (int)MathMax(stopsLevel, freezeLevel);
    double minSLDistance = minLevel * spExec.point;
    double safeMinDistance = minSLDistance + spExec.point;

    if(slDistance > 0.0 && slDistance < safeMinDistance)
    {
LogPrint("[EXEC_ORDER] SL dist=" + DoubleToString(slDistance, 5) + " below safe min=" + DoubleToString(safeMinDistance, 5) + " (stops=" + IntegerToString(stopsLevel) + ", freeze=" + IntegerToString(freezeLevel) + ") — adjusting...", LOG_LEVEL_WARN);

        ENUM_ORDER_TYPE orderType = (direction == SIGNAL_BULLISH) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        AdjustStopsToValidDistance(stopLoss, takeProfit, orderType, symbol, entryPrice);
        request.sl = stopLoss;
        request.tp = takeProfit;
        LogPrint("[EXEC_ORDER] Stops adjusted | SL=" + DoubleToString(stopLoss, 5) + " | TP=" + DoubleToString(takeProfit, 5), LOG_LEVEL_INFO);
    }

request.volume = lot;

    string fillingStr = "";
    if(request.type_filling == ORDER_FILLING_FOK) fillingStr = "FOK";
    else if(request.type_filling == ORDER_FILLING_IOC) fillingStr = "IOC";
    else fillingStr = "UNKNOWN";

    LogInfo("[EXEC] Status=READY | Symbol=" + symbol + " | Filling=" + fillingStr +
            " | Lot=" + DoubleToString(lot, 8) + " | SL=" + DoubleToString(stopLoss, digits) +
            " | TP=" + DoubleToString(takeProfit, digits));

    // PHASE 6: OrderCheck pre-flight (MANDATORY per B7.8 contract)
    string fillingModeStr = "N/A";
    if(!MQLInfoInteger(MQL_TESTER))
    {
    MqlTradeCheckResult check;
    if(!OrderCheck(request, check))
    {
        // CRITICAL: check.retcode may be garbage if OrderCheck() itself failed - use GetLastError()
        uint lastErr = GetLastError();
        uint correctedRetcode = (check.retcode > 0) ? check.retcode : lastErr;
        // If still 0, force to generic failure code to avoid misleading "success" code
        if(correctedRetcode == 0) correctedRetcode = 10000;
        LogPrint("[EXEC_ORDER_FAIL] reason=ORDERCHECK_FAIL | guid=" + IntegerToString(g_current_signal_guid) +
                " | retcode=" + IntegerToString(correctedRetcode), LOG_LEVEL_INFO);
        LogError("[ORDER_CHECK_FAIL] GUID=" + IntegerToString(g_current_signal_guid) +
                " | Status=FAIL" +
                " | CorrectedCode=" + IntegerToString(correctedRetcode) +
                " | RawRetcode=" + IntegerToString(check.retcode) +
                " | LastError=" + IntegerToString(lastErr) +
                " | Volume=" + DoubleToString(request.volume, 8) +
                " | Price=" + DoubleToString(request.price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                " | SL=" + DoubleToString(request.sl, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                " | TP=" + DoubleToString(request.tp, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)));
        if(TC_IsValid())
            TC_MarkFailed("ORDERCHECK_FAIL");
        return false;
    }

    // Compute corrected retcode for all subsequent logic
    uint correctedRetcode = check.retcode;
    if(correctedRetcode == 0) correctedRetcode = 10000;
    
    // Standardized execution log for OrderCheck rejection
    fillingModeStr = (request.type_filling == ORDER_FILLING_FOK) ? "FOK" : "IOC";
    LogError("[ORDER_CHECK_REJECT] GUID=" + IntegerToString(g_current_signal_guid) +
            " | Status=FAIL" +
            " | CorrectedCode=" + IntegerToString(correctedRetcode) +
            " | Desc=" + GetRetcodeDescription(correctedRetcode) +
            " | FillingAttempted=" + fillingModeStr +
            " | BrokerModes=" + GetBrokerFillingModes(symbol) +
            " | Volume=" + DoubleToString(request.volume, 8) +
            " | Price=" + DoubleToString(request.price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
            " | SL=" + DoubleToString(request.sl, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
            " | TP=" + DoubleToString(request.tp, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)));
    
    // === ROBUSTNESS MATRIX: Extended retcode handling ===
    // OPERATES ON CORRECTED CODE variable, not raw struct field
    switch(correctedRetcode)
    {
        case TRADE_RETCODE_DONE:        // 10009 — OrderCheck passed, proceed to send
            break;
        case TRADE_RETCODE_INVALID_FILL:
        {
            ENUM_ORDER_TYPE_FILLING altFilling = (request.type_filling == ORDER_FILLING_FOK) ? ORDER_FILLING_IOC : ORDER_FILLING_FOK;
            string altModeStr = (altFilling == ORDER_FILLING_FOK) ? "FOK" : "IOC";
            LogWarn("[ORDER_CHECK_RETRY] GUID=" + IntegerToString(g_current_signal_guid) +
                   " | Switching from " + fillingModeStr + " to " + altModeStr);
            request.type_filling = altFilling;
            
            MqlTradeCheckResult check2;
            if(OrderCheck(request, check2) && check2.retcode == TRADE_RETCODE_DONE)
            {
               LogInfo("[ORDER_CHECK_RETRY] GUID=" + IntegerToString(g_current_signal_guid) + " | Success with alternate filling mode");
               request.type_filling = altFilling;
            }
            else
            {
               string altModeStr2 = (request.type_filling == ORDER_FILLING_FOK) ? "FOK" : "IOC";
               uint correctedRetcode2 = check2.retcode;
               if(correctedRetcode2 == 0) correctedRetcode2 = 10000;
               LogError("[ORDER_CHECK_RETRY] GUID=" + IntegerToString(g_current_signal_guid) +
                       " | Alternate mode(" + altModeStr2 + ") also failed: CorrectedCode=" + IntegerToString(correctedRetcode2) +
                       " | Desc=" + GetRetcodeDescription(correctedRetcode2) +
                       " | Volume=" + DoubleToString(request.volume, 8) +
                       " | Price=" + DoubleToString(request.price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                       " | SL=" + DoubleToString(request.sl, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                       " | TP=" + DoubleToString(request.tp, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)));
               if(TC_IsValid())
                   TC_MarkFailed("ORDERCHECK_REJECT");
               return false;
            }
            break;
        }
        
        case 10006:  // NO_CONNECTION - network issue, retry once after brief pause
        {
            // CAP RETRIES: Check if we've exceeded retry limit for this signal
            g_retry_count++;
            if(g_retry_count > MAX_SIGNAL_RETRIES)
            {
                LogError("[ORDER_CHECK_REJECT] GUID=" + IntegerToString(g_current_signal_guid) +
                        " | Code=" + IntegerToString(correctedRetcode) +
                        " | Desc=NO_CONNECTION | RETRY_LIMIT_EXCEEDED (max=" + IntegerToString(MAX_SIGNAL_RETRIES) + ")");
                if(TC_IsValid())
                    TC_MarkFailed("ORDERCHECK_RETRY_LIMIT");
                g_retry_count = 0; // Reset for next signal
                return false;
            }
            // Signal timeout check
            if(g_signal_start_time > 0 && (GetTickCount() - g_signal_start_time) > SIGNAL_TIMEOUT_MS)
            {
                LogError("[ORDER_CHECK_REJECT] GUID=" + IntegerToString(g_current_signal_guid) +
                        " | Code=" + IntegerToString(correctedRetcode) +
                        " | Desc=NO_CONNECTION | SIGNAL_TIMEOUT_EXCEEDED");
                if(TC_IsValid())
                    TC_MarkFailed("ORDERCHECK_TIMEOUT");
                g_retry_count = 0;
                return false;
            }
            LogWarn("[ORDER_CHECK_RETRY] GUID=" + IntegerToString(g_current_signal_guid) +
                   " | Retry: NO_CONNECTION (10006) - network pause | Attempt=" + IntegerToString(g_retry_count));
            Sleep(500);  // 500ms network pause
            
            // Retry OrderCheck once
            MqlTradeCheckResult checkNet;
            if(OrderCheck(request, checkNet) && checkNet.retcode == TRADE_RETCODE_DONE)
            {
               LogInfo("[ORDER_CHECK_RETRY] GUID=" + IntegerToString(g_current_signal_guid) + " | Success after network recovery");
               g_retry_count = 0;
            }
            else
            {
               uint correctedNetRetcode = checkNet.retcode;
               if(correctedNetRetcode == 0) correctedNetRetcode = 10000;
               LogError("[ORDER_CHECK_UNRECOVERABLE] GUID=" + IntegerToString(g_current_signal_guid) +
                       " | CorrectedCode=" + IntegerToString(correctedNetRetcode) +
                       " | Desc=NO_CONNECTION | Network retry exhausted | Volume=" + DoubleToString(request.volume, 8) +
                       " | Price=" + DoubleToString(request.price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                       " | SL=" + DoubleToString(request.sl, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                       " | TP=" + DoubleToString(request.tp, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)));
               if(TC_IsValid())
                   TC_MarkFailed("ORDERCHECK_FAIL");
               g_retry_count = 0;
               return false;
            }
            break;
        }
        
        case 10027:  // AUTO_TRADING_DISABLED - terminal broker setting issue
        {
            LogError("[ORDER_CHECK_CRITICAL] GUID=" + IntegerToString(g_current_signal_guid) +
                    " | CorrectedCode=" + IntegerToString(correctedRetcode) +
                    " | Desc=AUTO_TRADING_DISABLED | broker settings issue - NOT a code bug");
            if(TC_IsValid())
                TC_MarkFailed("BROKER_SETTING");
            g_retry_count = 0;
            return false;
        }

        case 10011:  // INVALID_STOPS - attempt recovery via stop adjustment
        {
            LogWarn("[ORDER_CHECK_10011] GUID=" + IntegerToString(g_current_signal_guid) +
                    " | Attempting stop adjustment recovery...");

            double adjSL = request.sl;
            double adjTP = request.tp;
            if(AdjustStopsToValidDistance(adjSL, adjTP, request.type, request.symbol, request.price))
            {
               request.sl = adjSL;
               request.tp = adjTP;

               MqlTradeCheckResult checkAdj;
               ZeroMemory(checkAdj);
               if(OrderCheck(request, checkAdj))
               {
                  LogPrint("[ORDER_CHECK_10011] OrderCheck passed after stop adjustment. Retrying OrderSend...", LOG_LEVEL_INFO);
                  break;
               }
               else
               {
                  uint adjRetcode = checkAdj.retcode;
                  if(adjRetcode == 0) adjRetcode = 10000;
                  LogError("[ORDER_CHECK_10011] OrderCheck still fails after adjustment: " +
                           IntegerToString(adjRetcode) + " (" + checkAdj.comment + ")");
                  if(TC_IsValid())
                     TC_MarkFailed("ORDERCHECK_ADJUST_FAILED");
                  return false;
               }
            }
            else
            {
               LogError("[ORDER_CHECK_10011] AdjustStopsToValidDistance failed — cannot recover");
               if(TC_IsValid())
                  TC_MarkFailed("STOP_ADJUST_UNRECOVERABLE");
               return false;
            }
        }

        case 10016:  // INVALID_VOLUME_LIMIT - may also indicate stop distance issue
        {
            LogWarn("[ORDER_CHECK_10016] GUID=" + IntegerToString(g_current_signal_guid) +
                    " | Attempting stop adjustment recovery...");

            double adjSL = request.sl;
            double adjTP = request.tp;
            if(AdjustStopsToValidDistance(adjSL, adjTP, request.type, request.symbol, request.price))
            {
               request.sl = adjSL;
               request.tp = adjTP;

               MqlTradeCheckResult checkAdj;
               ZeroMemory(checkAdj);
               if(OrderCheck(request, checkAdj))
               {
                  LogPrint("[ORDER_CHECK_10016] OrderCheck passed after stop adjustment. Retrying OrderSend...", LOG_LEVEL_INFO);
                  break;
               }
                else
                {
                   uint adjRetcode = checkAdj.retcode;
                   if(adjRetcode == 0) adjRetcode = 10000;
                   LogError("[ORDER_CHECK_10016] OrderCheck still fails after adjustment: " +
                            IntegerToString(adjRetcode) + " (" + checkAdj.comment + ")");

                   int digits = (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS);
                   double point = SymbolInfoDouble(request.symbol, SYMBOL_POINT);
                   int stopsLevel = (int)SymbolInfoInteger(request.symbol, SYMBOL_TRADE_STOPS_LEVEL);
                   int freezeLevel = (int)SymbolInfoInteger(request.symbol, SYMBOL_TRADE_FREEZE_LEVEL);
                   int minLevel = MathMax(stopsLevel, freezeLevel);
                   double expandedDist = minLevel * point * 1.5;
                   request.sl = NormalizeDouble((request.type == ORDER_TYPE_BUY) ? request.price - expandedDist : request.price + expandedDist, digits);
                   request.tp = NormalizeDouble((request.type == ORDER_TYPE_BUY) ? request.price + expandedDist : request.price - expandedDist, digits);
                   LogPrint("[ORDER_CHECK_10016] RETRY with expanded buffer | dist=" + DoubleToString(expandedDist, digits) + " | SL=" + DoubleToString(request.sl, digits), LOG_LEVEL_WARN);

                   MqlTradeCheckResult checkRetry;
                   ZeroMemory(checkRetry);
                   if(OrderCheck(request, checkRetry))
                   {
                      LogPrint("[ORDER_CHECK_10016] OrderCheck passed after buffer expansion. Retrying...", LOG_LEVEL_INFO);
                   }
                   else
                   {
                      if(TC_IsValid())
                         TC_MarkFailed("ORDERCHECK_ADJUST_FAILED");
                      return false;
                   }
                }
             }
             else
             {
                LogError("[ORDER_CHECK_10016] AdjustStopsToValidDistance failed — cannot recover");
                if(TC_IsValid())
                   TC_MarkFailed("STOP_ADJUST_UNRECOVERABLE");
                return false;
             }
         }

        default:
        {
            if(correctedRetcode == 10000)
            {
                LogError("[ORDER_CHECK_ABORT] GUID=" + IntegerToString(g_current_signal_guid) +
                        " | Retcode=10000 | No server connection in tester — aborting signal");
                ClearSignalByGUID(g_activeBranch, g_current_signal_guid, "RETCODE_10000_ABORT");
                return false;
            }
            // Unhandled retcode - log with GUID for forensic tracking
            LogError("[ORDER_CHECK_UNHANDLED] GUID=" + IntegerToString(g_current_signal_guid) +
                    " | CorrectedCode=" + IntegerToString(correctedRetcode) +
                    " | Desc=" + GetRetcodeDescription(correctedRetcode) +
                    " | Filling=" + fillingModeStr +
                    " | Volume=" + DoubleToString(request.volume, 8) +
                    " | Price=" + DoubleToString(request.price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                    " | SL=" + DoubleToString(request.sl, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                    " | TP=" + DoubleToString(request.tp, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)));
            if(TC_IsValid())
                TC_MarkFailed("ORDERCHECK_REJECT");
            g_retry_count = 0;
            return false;
        }
    }
    }

   // First execution attempt — strong pre-send SL/TP validation
        {
            int d = (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS);
            double ep = request.price;
            LogPrint("[PRE_SEND] GUID=" + IntegerToString(g_current_signal_guid) +
                     " | ENTRY=" + DoubleToString(ep, d) +
                     " | SL=" + DoubleToString(request.sl, d) +
                     " | TP=" + DoubleToString(request.tp, d) +
                     " | TYPE=" + EnumToString(request.type) +
                     " | VOL=" + DoubleToString(request.volume, 2), LOG_LEVEL_INFO);
            if(request.type == ORDER_TYPE_BUY && request.sl > 0 && request.sl >= ep)
            {
               LogError("[EXEC_GATE_FAIL] SL_DIRECTION_INVALID | Dir=" + EnumToString(direction) +
                        " | Entry=" + DoubleToString(ep, 5) +
                        " | SL=" + DoubleToString(request.sl, 5));
               return false;
            }
            if(request.type == ORDER_TYPE_SELL && request.sl > 0 && request.sl <= ep)
            {
               LogError("[EXEC_GATE_FAIL] SL_DIRECTION_INVALID | Dir=" + EnumToString(direction) +
                        " | Entry=" + DoubleToString(ep, 5) +
                        " | SL=" + DoubleToString(request.sl, 5));
               return false;
            }
        }

        // P2 Fix: Validate stops immediately before send
        string guidStr = IntegerToString(g_current_signal_guid);
        if(!RG_ValidateAndAdjustStops(request.symbol, request.type, request.sl, request.tp, request.price, guidStr))
        {
            LogPrint("[EXEC_REJECTED] GUID=" + guidStr + " | Reason=STOP_VALIDATION_FAILED", LOG_LEVEL_WARN);
            LogWarn("[ORDER_SEND_ABORT] GUID=" + guidStr + " | Reason=STOP_VALIDATION_FAILED");
            return false;
        }

        // P2 Fix: OrderCheck before OrderSend
        if(!MQLInfoInteger(MQL_TESTER))
        {
        MqlTradeCheckResult checkResult = {};
        if(!OrderCheck(request, checkResult))
        {
            LogPrint("[EXEC_REJECTED] GUID=" + guidStr + " | Reason=ORDERCHECK_FAIL | retcode=" + IntegerToString(checkResult.retcode), LOG_LEVEL_WARN);
            LogWarn("[ORDER_CHECK_FAIL] GUID=" + guidStr + " | retcode=" + IntegerToString(checkResult.retcode) +
                    " | comment=" + checkResult.comment);
            if(checkResult.retcode == 10016)
            {
                RG_ValidateAndAdjustStops(request.symbol, request.type, request.sl, request.tp, request.price, guidStr);
                if(!OrderCheck(request, checkResult))
                {
                    LogPrint("[EXEC_REJECTED] GUID=" + guidStr + " | Reason=STOP_ADJUST_UNRECOVERABLE", LOG_LEVEL_WARN);
                    LogWarn("[ORDER_CHECK_FAIL_2ND] GUID=" + guidStr + " | Aborting order");
                    return false;
                }
                LogPrint("[ORDER_CHECK_10016] OrderCheck passed after stop adjustment. Retrying OrderSend...", LOG_LEVEL_INFO);
            }
            else
            {
                return false;
            }
        }
        }

        // REGRESSION_GUARD_FILL: Prevent ghosts — fully symbol/broker agnostic
        if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        {
            LogPrint("[EXEC_REJECTED] GUID=" + IntegerToString(g_current_signal_guid) + " | Reason=TRADE_DISABLED", LOG_LEVEL_WARN);
            LogPrint("[ORDER_FILL_FAIL] Trade not allowed - market closed or restricted | GUID=" + IntegerToString(g_current_signal_guid), LOG_LEVEL_ERROR);
            if(g_current_signal_guid != 0)
               OM_ClearSlot(g_current_signal_guid);
            if(TC_IsValid())
               TC_MarkFailed("TRADE_NOT_ALLOWED");
            return false;
        }

        // [ORDER_REQUESTED] Capture requested price before send
        signal.requestedEntryPrice = entryPrice;
        signal.fillStatus = 1;  // FILL_REQUESTED
        LogPrint("[ORDER_REQUESTED] GUID=" + IntegerToString(signal.m_guid) +
                 " | requestedEntry=" + DoubleToString(entryPrice, _Digits) +
                 " | lot=" + DoubleToString(request.volume, 2), LOG_LEVEL_INFO);

        // REGRESSION_GUARD_V54_3: Retry loop for NOT_ENOUGH_MONEY — reduce lot by 50%
         int orderRetryCount = 0;
         const int orderMaxRetries = 3;
         bool sent = false;
         bool orderSuccess = false;
         MqlTradeResult result = {};

         while(orderRetryCount < orderMaxRetries)
         {
             sent = OrderSend(request, result);

            PrintFormat("[ORDER_FILL_ATTEMPT] GUID=%I64u symbol=%s retcode=%u deal=%I64u fill_type=%d deviation=%d attempt=%d",
                        g_current_signal_guid, request.symbol, result.retcode, result.deal,
                        request.type_filling, request.deviation, orderRetryCount);

            if(sent && (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL || result.retcode == TRADE_RETCODE_PLACED))
            {
                LogPrint("[ORDER_SUBMITTED] GUID=" + IntegerToString(g_current_signal_guid) +
                          " | Ticket=" + IntegerToString(result.order) +
                          " | RequestID=" + IntegerToString(result.request_id), LOG_LEVEL_INFO);

                PrintFormat("[ORDER_FILL_SUCCESS] GUID=%I64u ticket=%I64u deal=%I64u price=%.5f",
                            g_current_signal_guid, result.order, result.deal, result.price);

                g_totalOrdersSent++;
                g_lastTradeOpenTime = TimeCurrent();

                ulong execGuid = g_current_signal_guid;
                if(execGuid != 0 && result.request_id > 0)
                {
                   int idx = ArraySize(g_pendingLinks);
                   ArrayResize(g_pendingLinks, idx + 1, idx + 10);
                   g_pendingLinks[idx].request_id = result.request_id;
                   g_pendingLinks[idx].guid       = execGuid;
                   g_pendingLinks[idx].created    = TimeCurrent();
                   PrintFormat("[PENDING_LINK] request_id=%u guid=%I64u", result.request_id, execGuid);
                }

                LogInfo("[EXEC_RESULT] GUID=" + IntegerToString(g_current_signal_guid) +
                        " | Status=SUCCESS" +
                        " | Ticket=" + IntegerToString(result.order) +
                        " | Deal=" + IntegerToString(result.deal) +
                        " | Filling=" + (request.type_filling == ORDER_FILLING_IOC ? "IOC" : request.type_filling == ORDER_FILLING_FOK ? "FOK" : "RETURN") +
                        " | Volume=" + DoubleToString(result.price > 0 ? request.volume : request.volume, 8) +
                        " | Price=" + DoubleToString(result.price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                        " | SL=" + DoubleToString(request.sl, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                        " | TP=" + DoubleToString(request.tp, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)));

                LogPrint("[ORDER_FILLED] GUID=" + IntegerToString(g_current_signal_guid) +
                          " | Ticket=" + IntegerToString(result.order) +
                          " | Deal=" + IntegerToString(result.deal) +
                          " | FillPrice=" + DoubleToString(result.price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)), LOG_LEVEL_INFO);

                // [ENTRY_TRUTH] Set fill price on the signal — actual broker fill becomes the truth
                signal.actualFillPrice = result.price;
                signal.fillStatus = 3;  // FILL_COMPLETE
                signal.fillTime = TimeCurrent();
                signal.entry_price = result.price;  // Override signal entry with actual fill price
                LogPrint("[ORDER_FILLED] GUID=" + IntegerToString(g_current_signal_guid) +
                          " | fillPrice=" + DoubleToString(result.price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                          " | requestedPrice=" + DoubleToString(entryPrice, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                          " | entryTruthReconciled=true", LOG_LEVEL_INFO);

                LogPrint("[FILL_PRICE_SYNCED] GUID=" + IntegerToString(g_current_signal_guid) +
                          " | FilledPrice=" + DoubleToString(result.price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                          " | RequestedPrice=" + DoubleToString(request.price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)), LOG_LEVEL_INFO);

                if(TC_IsValid())
                    TC_LockExecuted();

                if(request.sl > 0 && request.tp > 0)
                {
                    if((request.type == ORDER_TYPE_BUY && request.sl >= request.tp) ||
                       (request.type == ORDER_TYPE_SELL && request.sl <= request.tp))
                    {
                        LogPrint("[STOP_ADJUST] SL/TP relationship invalid after fill — order may be at risk", LOG_LEVEL_ERROR);
                    }
                }

                orderSuccess = true;
                break;
            }

            // NOT_ENOUGH_MONEY — clean rejection, no lot reduction (prohibited by AGENTS.md §VI)
            if(result.retcode == 10019)
            {
                LogPrint("[RISK_NO_MONEY_REJECT] NOT_ENOUGH_MONEY | lot=" + DoubleToString(request.volume, 2) +
                         " | symbol=" + request.symbol +
                         " | GUID=" + IntegerToString(g_current_signal_guid), LOG_LEVEL_ERROR);
                break;
            }

            // Non-retryable error or retries exhausted
            break;
        }

        if(orderSuccess)
            return true;

        // Final failure - terminate signal
        PrintFormat("[ORDER_FILL_FAIL] GUID=%I64u reason=%u retcode_desc=%s",
                    g_current_signal_guid, result.retcode, GetRetcodeDescription(result.retcode));
        LogError("[EXEC_RESULT] GUID=" + IntegerToString(g_current_signal_guid) +
                " | Status=FAILED" +
                " | Retcode=" + IntegerToString(result.retcode) +
                " | Desc=" + GetRetcodeDescription(result.retcode) +
                " | Error=" + IntegerToString(GetLastError()) +
                " | Volume=" + DoubleToString(request.volume, 8) +
                " | Price=" + DoubleToString(request.price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                " | SL=" + DoubleToString(request.sl, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                " | TP=" + DoubleToString(request.tp, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)));

        LogPrint("[ORDER_FAILED] GUID=" + IntegerToString(g_current_signal_guid) +
                  " | Retcode=" + IntegerToString(result.retcode) +
                  " | Desc=" + GetRetcodeDescription(result.retcode), LOG_LEVEL_ERROR);

        if(g_current_signal_guid != 0)
        {
            LogPrint("[SLOT] ROLLBACK on failure | GUID=" + IntegerToString(g_current_signal_guid), LOG_LEVEL_DEBUG);
            OM_ClearSlot(g_current_signal_guid);
        }

        if(TC_IsValid())
            TC_MarkFailed("EXEC_FAILED");

        SL_TerminateSignal(g_current_signal_guid, SIGNAL_TERM_EXEC_FAILED,
                        "Execution failed: " + GetRetcodeDescription(result.retcode), 0);

        return false;
    }

//+------------------------------------------------------------------+
 //| ExecuteLimitOrder — Execute a pending limit order at specified price  |
 //+------------------------------------------------------------------+
 bool ExecuteLimitOrder(
     const string symbol,
     ENUM_SIGNAL_DIRECTION direction,
     double lot,
     double limitPrice,
     double stopLoss,
     double takeProfit,
     int magicNumber,
     ulong signalGuid = 0)
 {
    g_current_signal_guid = signalGuid;
    if(!CanSendOrder(symbol))
    {
        if(TC_IsValid())
            TC_MarkFailed("ORDER_THROTTLE");
        return false;
    }

    if(TC_IsExecuted())
    {
        LogPrint("[EXEC] Trade already executed, rejecting duplicate", LOG_LEVEL_DEBUG);
        return false;
    }

    // REGRESSION_GUARD_FILL: Dynamic filling — prefer IOC, fallback RETURN
    ulong filling_mode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
    ENUM_ORDER_TYPE_FILLING selectedFilling = ORDER_FILLING_RETURN;
    if((filling_mode & SYMBOL_FILLING_IOC) != 0)
       selectedFilling = ORDER_FILLING_IOC;
    else if((filling_mode & SYMBOL_FILLING_FOK) != 0)
       selectedFilling = ORDER_FILLING_FOK;

    MqlTradeRequest request = {};
    MqlTradeResult result = {};
     request.type_filling = selectedFilling;
     // REGRESSION_GUARD_DEVIATION: Dynamic point-scaled — works for all symbols
     request.deviation = (ulong)(SymbolInfoDouble(symbol, SYMBOL_POINT) * 30);

    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    request.price = NormalizeDouble(limitPrice, digits);
    request.sl = NormalizeDouble(stopLoss, digits);
    request.tp = NormalizeDouble(takeProfit, digits);

request.action = TRADE_ACTION_PENDING;
      request.symbol = symbol;
      request.type = (direction == SIGNAL_BULLISH) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
      request.magic = magicNumber;
      request.type_time = ORDER_TIME_GTC;

      SSymbolProfile spLot = SY_GetProfile(symbol);
      double minLot = spLot.volumeMin;
      double maxLot = spLot.volumeMax;
      double lotStep = spLot.volumeStep;

      lot = StabiliseLot(lot, minLot, maxLot, lotStep, symbol);
     
      if(lot < minLot || lot <= 0.0)
      {
         LogWarn("[LIMIT_ORDER] GUID=" + IntegerToString(g_current_signal_guid) +
               " | LOT_REJECTED | LOT=" + DoubleToString(lot, 8) + " MIN=" + DoubleToString(minLot, 8));
         return false;
      }

      request.volume = lot;

      // [ORDER_REQUESTED] Capture requested price before send
      {
         for(int loPre = 0; loPre < ArraySize(g_activeSignal); loPre++)
         {
            if(g_hasActiveSignal[loPre] && g_activeSignal[loPre].m_guid == g_current_signal_guid)
            {
               g_activeSignal[loPre].requestedEntryPrice = limitPrice;
               g_activeSignal[loPre].fillStatus = 1;  // FILL_REQUESTED
               LogPrint("[ORDER_REQUESTED] GUID=" + IntegerToString(g_current_signal_guid) +
                        " | requestedEntry=" + DoubleToString(limitPrice, _Digits) +
                        " | type=LIMIT", LOG_LEVEL_INFO);
               break;
            }
         }
      }

    LogInfo("[LIMIT_ORDER] Status=READY | Symbol=" + symbol + 
            " | Type=" + (direction == SIGNAL_BULLISH ? "BUY_LIMIT" : "SELL_LIMIT") +
            " | Price=" + DoubleToString(limitPrice, digits) +
            " | Lot=" + DoubleToString(lot, 8));

    if(!MQLInfoInteger(MQL_TESTER))
    {
        MqlTradeCheckResult check;
        if(!OrderCheck(request, check))
        {
            uint lastErr = GetLastError();
            uint correctedRetcode = (check.retcode > 0) ? check.retcode : lastErr;
            if(correctedRetcode == 0) correctedRetcode = 10000;
            LogError("[LIMIT_ORDER_CHECK_FAIL] GUID=" + IntegerToString(g_current_signal_guid) +
                    " | Status=FAIL" +
                    " | CorrectedCode=" + IntegerToString(correctedRetcode) +
                    " | RawRetcode=" + IntegerToString(check.retcode) +
                    " | FuncResult=OrderCheck(FALSE) | LastError=" + IntegerToString(lastErr) +
                    " | Volume=" + DoubleToString(request.volume, 8) +
                    " | Price=" + DoubleToString(request.price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                    " | SL=" + DoubleToString(request.sl, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                    " | TP=" + DoubleToString(request.tp, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)));
            if(TC_IsValid())
                TC_MarkFailed("ORDERCHECK_FAIL");
            return false;
        }

        uint correctedRetcode = check.retcode;
        if(correctedRetcode == 0) correctedRetcode = 10000;
        if(correctedRetcode != TRADE_RETCODE_DONE)
        {
            LogWarn("[LIMIT_ORDER_REJECT] GUID=" + IntegerToString(g_current_signal_guid) +
                  " | Status=FAIL" +
                  " | CorrectedCode=" + IntegerToString(correctedRetcode) +
                  " | Desc=" + GetRetcodeDescription(correctedRetcode) +
                  " | Volume=" + DoubleToString(request.volume, 8) +
                  " | Price=" + DoubleToString(request.price, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                  " | SL=" + DoubleToString(request.sl, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)) +
                  " | TP=" + DoubleToString(request.tp, (int)SymbolInfoInteger(request.symbol, SYMBOL_DIGITS)));
            if(TC_IsValid())
                TC_MarkFailed("ORDERCHECK_REJECT");
            return false;
        }
    }

    // REGRESSION_GUARD_FILL: Prevent ghosts — fully symbol/broker agnostic
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
    {
        LogPrint("[LIMIT_ORDER_FILL_FAIL] Trade not allowed - market closed or restricted | GUID=" + IntegerToString(g_current_signal_guid), LOG_LEVEL_ERROR);
        if(TC_IsValid())
            TC_MarkFailed("TRADE_NOT_ALLOWED");
        return false;
    }

    bool sent = OrderSend(request, result);

    PrintFormat("[LIMIT_ORDER_FILL_ATTEMPT] GUID=%I64u symbol=%s retcode=%u deal=%I64u fill_type=%d deviation=%d",
                g_current_signal_guid, request.symbol, result.retcode, result.deal,
                request.type_filling, request.deviation);

    if(sent && (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED))
    {
        PrintFormat("[LIMIT_ORDER_FILL_SUCCESS] GUID=%I64u ticket=%I64u deal=%I64u price=%.5f",
                    g_current_signal_guid, result.order, result.deal, result.price);

        // [ENTRY_TRUTH] Set fill price on the signal (via g_activeSignal store)
        for(int loS = 0; loS < ArraySize(g_activeSignal); loS++)
        {
           if(g_hasActiveSignal[loS] && g_activeSignal[loS].m_guid == g_current_signal_guid)
           {
              g_activeSignal[loS].requestedEntryPrice = limitPrice;
              g_activeSignal[loS].actualFillPrice = result.price;
              g_activeSignal[loS].fillStatus = 3;  // FILL_COMPLETE
              g_activeSignal[loS].fillTime = TimeCurrent();
              g_activeSignal[loS].entry_price = result.price;
              LogPrint("[ORDER_FILLED] GUID=" + IntegerToString(g_current_signal_guid) +
                       " | fillPrice=" + DoubleToString(result.price, _Digits) +
                       " | requestedPrice=" + DoubleToString(limitPrice, _Digits) +
                       " | entryTruthReconciled=true", LOG_LEVEL_INFO);
              break;
           }
        }

        g_totalOrdersSent++;  // P5 Fix: Increment order counter on success
        LogPrint("[ORDER_SENT_OK] GUID=" + IntegerToString(g_current_signal_guid) +
                 " | ticket=" + IntegerToString(result.order) +
                 " | totalSent=" + IntegerToString(g_totalOrdersSent), LOG_LEVEL_INFO);
        LogInfo("[LIMIT_ORDER] GUID=" + IntegerToString(g_current_signal_guid) +
              " | Status=SUCCESS | Ticket=" + IntegerToString(result.order));
        return true;
    }

    PrintFormat("[LIMIT_ORDER_FILL_FAIL] GUID=%I64u reason=%u retcode_desc=%s",
                g_current_signal_guid, result.retcode, GetRetcodeDescription(result.retcode));
    LogError("[LIMIT_ORDER] GUID=" + IntegerToString(g_current_signal_guid) +
            " | Status=FAILED | Retcode=" + IntegerToString(result.retcode) +
            " | Error=" + IntegerToString(GetLastError()));
    return false;
}

//+------------------------------------------------------------------+
//| GetBrokerFillingModes — Get broker-allowed filling modes as string  |
//+------------------------------------------------------------------+
string GetBrokerFillingModes(string symbol)
{
   int filling = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   string result = "";
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      result += "FOK";
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
   {
      if(StringLen(result) > 0) result += "|";
      result += "IOC";
   }
   // RETURN is the default when no filling mode bits are set (filling == 0)
   if(filling == 0)
   {
      if(StringLen(result) > 0) result += "|";
      result += "RETURN";
   }
   if(StringLen(result) == 0) result = "NONE";
   return result;
}

//+------------------------------------------------------------------+
//| GetBestFillingMode — Get broker-allowed filling mode for symbol      |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetBestFillingMode(string symbol)
{
   int filling = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   
   return ORDER_FILLING_RETURN;
}

#endif // OMAK_ORDERMANAGER_MQH