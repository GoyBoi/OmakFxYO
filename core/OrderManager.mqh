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
      for(int s = 0; s < MAX_SLOTS; s++)
      {
         if(g_activeC2[s].m_guid == posMagic)
         {
            posMode = g_activeC2[s].executionMode;
            break;
         }
         if(g_activeC3[s].m_guid == posMagic)
         {
            posMode = g_activeC3[s].executionMode;
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
//| ResolveRiskPctForBranch — Mode-aware risk percentage resolution   |
//+------------------------------------------------------------------+
double ResolveRiskPctForBranch(const int mode, double baseRisk, ENUM_EXECUTION_BRANCH branch) {
    double modeFactor = (mode == MODE_ANTICIPATION) ? 0.6 : 1.0;
    return baseRisk * modeFactor; 
}

//+------------------------------------------------------------------+
//| DetermineOrderType — Mode-based order type selection (§V)        |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE DetermineOrderType(const SLockedSignal &sig)
{
    if(sig.executionMode == MODE_ANTICIPATION)
    {
        if(sig.direction == DIRECTION_BUY)
        {
            double ask = SymbolInfoDouble(sig.symbol, SYMBOL_ASK);
            return (sig.entry_price >= ask) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_BUY_LIMIT;
        }
        else
        {
            double bid = SymbolInfoDouble(sig.symbol, SYMBOL_BID);
            return (sig.entry_price <= bid) ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_SELL_LIMIT;
        }
    }
    else
    {
        return (sig.direction == DIRECTION_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    }
}

//+------------------------------------------------------------------+
//| ExecutionGatePass — Final pre-execution validation gate           |
//| VERBATIM REPAIR: Findings 1 & 3 - Protected Delivery & GUID      |
//+------------------------------------------------------------------+
bool ExecutionGatePass(SLockedSignal &signal, ENUM_EXECUTION_BRANCH branch, double lot) {
    g_current_signal_guid = signal.m_guid;
    LogPrint(StringFormat("[EXEC_GATE] ENTER | GUID:%I64u | Mode:%s | lot:%.2f", signal.m_guid, MR_ModeToString((EntryMode)signal.executionMode), lot), LOG_LEVEL_INFO);

    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    string sym   = signal.symbol;
    int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
    double bid   = SymbolInfoDouble(sym, SYMBOL_BID);
    double ask   = SymbolInfoDouble(sym, SYMBOL_ASK);
    ulong  fill  = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
    
    request.action   = (signal.executionMode == MODE_ANTICIPATION) ? TRADE_ACTION_PENDING : TRADE_ACTION_DEAL;
    request.symbol   = sym;
    request.volume   = NormalizeDouble(lot, 2);
    request.magic    = InpMagicNumber;
    request.deviation = (signal.executionMode == MODE_CONFIRMATION) ? 10 : 0;
    request.type_filling = ((fill & SYMBOL_FILLING_FOK) != 0) ? ORDER_FILLING_FOK :
                           ((fill & SYMBOL_FILLING_IOC) != 0) ? ORDER_FILLING_IOC :
                           ORDER_FILLING_RETURN;
    
    request.type = DetermineOrderType(signal);
    
    request.price = NormalizeDouble(signal.entry_price, digits);
    request.sl    = NormalizeDouble(signal.stop_loss, digits);
    request.tp    = NormalizeDouble(signal.tp, digits);
    
    // §XII: Set TF-aware expiration for pending orders
    if(request.action == TRADE_ACTION_PENDING)
    {
       request.type_time = ORDER_TIME_SPECIFIED;
       request.expiration = TimeCurrent() + GetPendingOrderTimeoutSeconds(GetEntryTF(signal.branchId));
    }
    
    if(!RG_ValidateAndAdjustStops(request, signal)) {
        LogPrint(StringFormat("[RG_STOPS_REJECT] GUID:%I64u | SL:%.5f", signal.m_guid, request.sl), LOG_LEVEL_ERROR);
        return false;
    }
    
    MqlTradeCheckResult checkResult = {};
    if(!OrderCheck(request, checkResult)) {
        LogPrint(StringFormat("[ORDERCHECK_FAIL] GUID:%I64u | retcode=%d | comment=%s",
                 signal.m_guid, checkResult.retcode, checkResult.comment), LOG_LEVEL_ERROR);
        return false;
    }
    
    // Acquire handover ownership before order send
    if(!signal.AcquireHandover(HANDOVER_OWNER_ORDER_MGR))
    {
        LogPrint("[HANDOVER_ACQUIRE_FAIL] GUID=" + IntegerToString(signal.m_guid), LOG_LEVEL_ERROR);
        return false;
    }
    
    string execSpecies = (signal.closureType == CLOSURE_C2 ? "C2" :
                          signal.closureType == CLOSURE_C3 ? "C3" :
                          signal.closureType == CLOSURE_C4 ? "C4" : "UNKNOWN");
    string execDir     = (signal.direction == DIRECTION_BUY ? "BUY" :
                          signal.direction == DIRECTION_SELL ? "SELL" : "NONE");
    LogPrint("[EXEC_TRIGGER] GUID=" + IntegerToString(signal.m_guid) +
             " | species=" + execSpecies +
             " | direction=" + execDir +
             " | entry=" + DoubleToString(signal.entry_price, digits) +
             " | sl=" + DoubleToString(signal.stop_loss, digits) +
             " | tp=" + DoubleToString(signal.tp, digits), LOG_LEVEL_INFO);

    if(request.tp <= 0.0 || request.sl <= 0.0)
    {
       LogPrint("[PROTECTED_DELIVERY_BLOCK] sl=" + DoubleToString(request.sl, _Digits) +
                " | tp=" + DoubleToString(request.tp, _Digits) +
                " | GUID=" + IntegerToString(signal.m_guid) +
                " | species=" + execSpecies, LOG_LEVEL_ERROR);
       return false;
    }

    if(!IsMarketOpen())
    {
        LogPrint("[MARKET_CLOSED] Order not sent – outside trading hours | GUID=" +
                 IntegerToString(signal.m_guid), LOG_LEVEL_WARN);
        return false;
    }

    int retryCount = 0;
    bool orderSent = false;
    while(retryCount < 3 && !orderSent)
    {
        if(OrderSend(request, result))
            orderSent = true;
        else
        {
            retryCount++;
            if(retryCount < 3)
            {
                LogPrint(StringFormat("[ORDER_RETRY] GUID:%I64u | attempt:%d | Error:%d",
                         signal.m_guid, retryCount, GetLastError()), LOG_LEVEL_WARN);
            }
        }
    }
    if(!orderSent)
    {
        LogPrint(StringFormat("[ORDER_FAILED] GUID:%I64u | Error:%d | retries:%d",
                 signal.m_guid, GetLastError(), retryCount), LOG_LEVEL_ERROR);
        return false;
    }
    
    // VERBATIM REPAIR: Finding 1 - GUID Identity Bridge
    {
        int linkIdx = ArraySize(g_pendingLinks);
        ArrayResize(g_pendingLinks, linkIdx + 1);
        g_pendingLinks[linkIdx].request_id = result.request_id;
        g_pendingLinks[linkIdx].guid = signal.m_guid;
        g_pendingLinks[linkIdx].branch = signal.branchId;
        g_pendingLinks[linkIdx].orderTicket = result.order;
        g_pendingLinks[linkIdx].created = TimeCurrent();
        LogPrint(StringFormat("[GUID_BRIDGE_SET] ID:%u -> GUID:%I64u branch=%s", result.request_id, signal.m_guid,
                 signal.branchId == BRANCH_INTRADAY ? "A" : "B"), LOG_LEVEL_INFO);
    }
    
    g_totalOrdersSent++;
    LogPrint("[ORDER_SENT] GUID=" + IntegerToString(signal.m_guid) +
             " | type=" + EnumToString(request.type) +
             " | price=" + DoubleToString(request.price, digits) +
             " | sl=" + DoubleToString(request.sl, digits) +
             " | tp=" + DoubleToString(request.tp, digits) +
             " | vol=" + DoubleToString(request.volume, 2) +
             " | totalSent=" + IntegerToString(g_totalOrdersSent), LOG_LEVEL_INFO);
    
    return true;
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
      // §XII: TF-aware expiration for limit orders
      {
         ENUM_EXECUTION_BRANCH limBranch = BRANCH_INTRADAY;
         for(int si = 0; si < MAX_SLOTS; si++)
         {
            if(g_activeC2[si].m_guid == g_current_signal_guid)
            {
               limBranch = g_activeC2[si].branchId;
               break;
            }
            if(g_activeC3[si].m_guid == g_current_signal_guid)
            {
               limBranch = g_activeC3[si].branchId;
               break;
            }
         }
         request.type_time = ORDER_TIME_SPECIFIED;
         request.expiration = TimeCurrent() + GetPendingOrderTimeoutSeconds(GetEntryTF(limBranch));
      }

      SSymbolProfile spLot = SY_GetProfile(symbol);
      double minLot = spLot.volumeMin;
      double maxLot = spLot.volumeMax;
      double lotStep = spLot.volumeStep;

      StabiliseLot(lot, minLot, maxLot, lotStep, symbol);
      // lot already modified in-place by reference; no assignment needed
     
      if(lot < minLot || lot <= 0.0)
      {
         LogWarn("[LIMIT_ORDER] GUID=" + IntegerToString(g_current_signal_guid) +
               " | LOT_REJECTED | LOT=" + DoubleToString(lot, 8) + " MIN=" + DoubleToString(minLot, 8));
         return false;
      }

      request.volume = lot;

      // [ORDER_REQUESTED] Capture requested price before send
      {
         for(int loPre = 0; loPre < MAX_SLOTS; loPre++)
         {
            if(g_activeC2[loPre].m_guid == g_current_signal_guid)
            {
               g_activeC2[loPre].requestedEntryPrice = limitPrice;
               g_activeC2[loPre].fillStatus = 1;
               break;
            }
            if(g_activeC3[loPre].m_guid == g_current_signal_guid)
            {
               g_activeC3[loPre].requestedEntryPrice = limitPrice;
               g_activeC3[loPre].fillStatus = 1;
               break;
            }
         }
         LogPrint("[ORDER_REQUESTED] GUID=" + IntegerToString(g_current_signal_guid) +
                  " | requestedEntry=" + DoubleToString(limitPrice, digits) +
                  " | type=LIMIT", LOG_LEVEL_INFO);
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

    {
        ENUM_CLOSURE_TYPE execCt = CLOSURE_NONE;
        for(int eCt = 0; eCt < MAX_SLOTS; eCt++)
        {
           if(g_activeC2[eCt].m_guid == g_current_signal_guid) { execCt = g_activeC2[eCt].closureType; break; }
           if(g_activeC3[eCt].m_guid == g_current_signal_guid) { execCt = g_activeC3[eCt].closureType; break; }
        }
        string loSpecies = (execCt == CLOSURE_C2 ? "C2" :
                            execCt == CLOSURE_C3 ? "C3" :
                            execCt == CLOSURE_C4 ? "C4" : "UNKNOWN");
        string loDir     = (direction == SIGNAL_BULLISH ? "BUY" :
                            direction == SIGNAL_BEARISH ? "SELL" : "NONE");
        LogPrint("[EXEC_TRIGGER] GUID=" + IntegerToString(g_current_signal_guid) +
                 " | species=" + loSpecies +
                 " | direction=" + loDir +
                 " | entry=" + DoubleToString(limitPrice, digits) +
                 " | sl=" + DoubleToString(stopLoss, digits) +
                 " | tp=" + DoubleToString(takeProfit, digits), LOG_LEVEL_INFO);
    }

    if(request.tp <= 0.0 || request.sl <= 0.0)
    {
       string loSpecies2 = (g_current_signal_guid > 0) ? "UNKNOWN" : "UNKNOWN";
       for(int pDi = 0; pDi < MAX_SLOTS; pDi++)
       {
          if(g_activeC2[pDi].m_guid == g_current_signal_guid) { loSpecies2 = "C2"; break; }
          if(g_activeC3[pDi].m_guid == g_current_signal_guid) { loSpecies2 = (g_activeC3[pDi].closureType == CLOSURE_C4 ? "C4" : "C3"); break; }
       }
       LogPrint("[PROTECTED_DELIVERY_BLOCK] sl=" + DoubleToString(request.sl, _Digits) +
                " | tp=" + DoubleToString(request.tp, _Digits) +
                " | GUID=" + IntegerToString(g_current_signal_guid) +
                " | species=" + loSpecies2, LOG_LEVEL_ERROR);
       return false;
    }

    bool sent = OrderSend(request, result);

    LogPrint(StringFormat("[LIMIT_ORDER_FILL_ATTEMPT] GUID=%I64u symbol=%s retcode=%u deal=%I64u fill_type=%d deviation=%d",
                g_current_signal_guid, request.symbol, result.retcode, result.deal,
                request.type_filling, request.deviation), LOG_LEVEL_INFO);

    if(sent && (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED))
    {
        LogPrint("[LIMIT_ORDER_FILL_SUCCESS] GUID=" + IntegerToString(g_current_signal_guid) +
                 " | ticket=" + IntegerToString(result.order) +
                 " | deal=" + IntegerToString(result.deal) +
                 " | price=" + DoubleToString(result.price, digits), LOG_LEVEL_INFO);

        // VERBATIM REPAIR: GUID Identity Bridge (limit order path)
        {
            int linkIdx = ArraySize(g_pendingLinks);
            ArrayResize(g_pendingLinks, linkIdx + 1);
            g_pendingLinks[linkIdx].request_id = result.request_id;
            g_pendingLinks[linkIdx].guid = g_current_signal_guid;
        g_pendingLinks[linkIdx].orderTicket = (request.action == TRADE_ACTION_PENDING) ? result.order : 0;
            g_pendingLinks[linkIdx].created = TimeCurrent();
            {
               ENUM_EXECUTION_BRANCH linkBranch = BRANCH_INTRADAY;
               for(int si = 0; si < MAX_SLOTS; si++)
               {
                  if(g_activeC2[si].m_guid == g_current_signal_guid)
                  {
                     linkBranch = g_activeC2[si].branchId;
                     break;
                  }
                  if(g_activeC3[si].m_guid == g_current_signal_guid)
                  {
                     linkBranch = g_activeC3[si].branchId;
                     break;
                  }
               }
               g_pendingLinks[linkIdx].branch = linkBranch;
            }
            LogPrint(StringFormat("[GUID_BRIDGE_SET] ID:%u -> GUID:%I64u", result.request_id, g_current_signal_guid), LOG_LEVEL_INFO);
        }

        // [ENTRY_TRUTH] Set fill price on the signal (via store)
        for(int loS = 0; loS < MAX_SLOTS; loS++)
        {
           if(g_activeC2[loS].m_guid == g_current_signal_guid)
           {
              g_activeC2[loS].requestedEntryPrice = limitPrice;
              g_activeC2[loS].actualFillPrice = result.price;
              g_activeC2[loS].fillStatus = 3;
              g_activeC2[loS].fillTime = TimeCurrent();
              g_activeC2[loS].entry_price = result.price;
               LogPrint("[ORDER_FILLED] GUID=" + IntegerToString(g_current_signal_guid) +
                        " | fillPrice=" + DoubleToString(result.price, digits) +
                        " | requestedPrice=" + DoubleToString(limitPrice, digits) +
                        " | entryTruthReconciled=true", LOG_LEVEL_INFO);
               break;
            }
            if(g_activeC3[loS].m_guid == g_current_signal_guid)
            {
               g_activeC3[loS].requestedEntryPrice = limitPrice;
               g_activeC3[loS].actualFillPrice = result.price;
               g_activeC3[loS].fillStatus = 3;
               g_activeC3[loS].fillTime = TimeCurrent();
               g_activeC3[loS].entry_price = result.price;
               LogPrint("[ORDER_FILLED] GUID=" + IntegerToString(g_current_signal_guid) +
                        " | fillPrice=" + DoubleToString(result.price, digits) +
                        " | requestedPrice=" + DoubleToString(limitPrice, digits) +
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

    LogPrint(StringFormat("[LIMIT_ORDER_FILL_FAIL] GUID=%I64u reason=%u retcode_desc=%s",
                g_current_signal_guid, result.retcode, GetRetcodeDescription(result.retcode)), LOG_LEVEL_ERROR);
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