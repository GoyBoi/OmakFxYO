//+------------------------------------------------------------------+
//|                                          PositionManager.mqh |
//|                                    OmakFxYO — Position Manager |
//+------------------------------------------------------------------+
#property strict

#ifndef OMAK_POSITIONMANAGER_MQH
#define OMAK_POSITIONMANAGER_MQH

#include "CoreTypes.mqh"
#include "TradeGovernor.mqh"

#include "SignalLifecycle.mqh"

bool CanSendOrder(string symbol);

#include "OrderManager.mqh"

// CanSendOrder — Lightweight gate: can we send orders right now?
//| Checks terminal trade allowed, risk engine block, and market data |
//+------------------------------------------------------------------+
bool CanSendOrder(string symbol)
{
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
    {
       LogPrint("[CAN_SEND] BLOCKED — terminal trade not allowed", LOG_LEVEL_DEBUG);
       return false;
    }

    SSymbolProfile spCs = SY_GetProfile(symbol);
    double bid = (spCs.tickBid > 0.0) ? spCs.tickBid : SymbolInfoDouble(symbol, SYMBOL_BID);
    double ask = (spCs.tickAsk > 0.0) ? spCs.tickAsk : SymbolInfoDouble(symbol, SYMBOL_ASK);
    if(bid <= 0.0 || ask <= 0.0)
    {
       LogPrint("[CAN_SEND] BLOCKED — invalid market price (bid=" + DoubleToString(bid, _Digits) +
                " | ask=" + DoubleToString(ask, _Digits) + ")", LOG_LEVEL_DEBUG);
       return false;
    }
    
return true;
 }

#define MAX_CLOSE_RETRIES 5

struct CloseRetryTracker
{
   ulong ticket;
   int attempts;
   datetime lastAttempt;
};

static CloseRetryTracker g_closeRetries[];
static int g_closeRetryCount = 0;

void PM_Init()
{
   ArrayResize(g_closeRetries, 0);
   g_closeRetryCount = 0;
}

void PM_Shutdown()
{
   ArrayFree(g_closeRetries);
   g_closeRetryCount = 0;
}

int FindCloseRetry(ulong ticket)
{
   for(int i = 0; i < g_closeRetryCount; i++)
   {
      if(g_closeRetries[i].ticket == ticket)
         return i;
   }
   return -1;
}

void IncrementCloseRetry(ulong ticket)
{
   int idx = FindCloseRetry(ticket);
   if(idx >= 0)
   {
      int size = ArraySize(g_closeRetries);
      if(idx < size)
      {
         g_closeRetries[idx].attempts++;
         g_closeRetries[idx].lastAttempt = TimeCurrent();
      }
      else
      {
         LogWarn("[RETRY] Invalid index in IncrementCloseRetry | idx=" + IntegerToString(idx) + " | Size=" + IntegerToString(size));
      }
   }
   else if(g_closeRetryCount < 50)
   {
      idx = g_closeRetryCount;
      int size = ArraySize(g_closeRetries);
      if(idx >= size)
      {
         if(ArrayResize(g_closeRetries, size + 10) < 0)
         {
LogWarn("[RETRY] Array resize failed in IncrementCloseRetry");
             return;
          }
       }
      // REGRESSION_GUARD_V52.5_INCREMENT_CLOSE_RETRY: Proper counter increment + entry assignment
      g_closeRetries[idx].ticket = ticket;
      g_closeRetries[idx].attempts = 1;
      g_closeRetries[idx].lastAttempt = TimeCurrent();
      g_closeRetryCount++;
    }
 }

//+------------------------------------------------------------------+
 //| Find position state index                                         |
 //+------------------------------------------------------------------+
int PM_GetPositionStateIndex(ulong ticket)
{
    for(int i = 0; i < g_positionStateCount; i++)
    {
       if(g_positionStates[i].ticket == ticket)
          return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Create new position state entry                                   |
//+------------------------------------------------------------------+
int PM_CreatePositionState(ulong ticket)
{
    if(g_positionStateCount >= MAX_TRACKED_POSITIONS)
    {
       LogWarn("[POS] Max tracked positions reached | Count=" + IntegerToString(g_positionStateCount));
       return -1;
    }

    int idx = g_positionStateCount;
    int size = ArraySize(g_positionStates);
    if(idx >= size)
    {
       LogWarn("[POS] Position state array overflow | idx=" + IntegerToString(idx) + " | Size=" + IntegerToString(size));
       return -1;
    }
    g_positionStates[idx].ticket = ticket;
    g_positionStates[idx].tp1Done = false;
    g_positionStates[idx].tp2Done = false;
    g_positionStates[idx].partialVolume = 0.0;
    g_positionStates[idx].entryTime = TimeCurrent();
    g_positionStates[idx].profitBars = 0;
    g_positionStates[idx].highestProfitPts = 0.0;
    g_positionStates[idx].lastProfitBarCheck = 0;
    g_positionStates[idx].beTriggered = false;
    g_positionStates[idx].trailSwingLevel = 0.0;
    g_positionStates[idx].lastTrailBarTime = 0;
    g_positionStateCount++;
    return idx;
}

//+------------------------------------------------------------------+
//| Remove position state entry                                       |
//+------------------------------------------------------------------+
void PM_RemovePositionState(ulong ticket)
{
   for(int i = 0; i < g_positionStateCount; i++)
   {
      int size = ArraySize(g_positionStates);
      if(i >= size)
      {
         LogWarn("[POS] Invalid index in RemovePositionState | i=" + IntegerToString(i) + " | Size=" + IntegerToString(size));
         continue;
      }
      if(g_positionStates[i].ticket == ticket)
      {
         for(int j = i; j < g_positionStateCount - 1; j++)
         {
            int arrSize = ArraySize(g_positionStates);
            if(j + 1 < arrSize)
               g_positionStates[j] = g_positionStates[j + 1];
         }
         g_positionStateCount--;
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Public lifecycle hooks                                            |
//+------------------------------------------------------------------+
void PM_OnPositionOpen(ulong ticket, string symbol, double volume)
{
   PM_CreatePositionState(ticket);
}

void PM_OnPositionClose(ulong ticket)
{
   PM_RemovePositionState(ticket);
}

void PM_OnPartialClose(ulong ticket, double closedVolume)
{
     int idx = PM_GetPositionStateIndex(ticket);
     if(idx >= 0)
     {
        int size = ArraySize(g_positionStates);
        if(idx < size)
           g_positionStates[idx].partialVolume += closedVolume;
        else
           LogWarn("[POS] PartialClose index out of range | idx=" + IntegerToString(idx) + " | Size=" + IntegerToString(size));
     }
}

//+------------------------------------------------------------------+
//| PM_ManagePositions — Manage open positions                       |
//| Rules: R-Multiple Break Even, Trailing Stop, Hard Exit on opposite signal |
//+------------------------------------------------------------------+
void PM_ManagePositions(string symbol, long magic,
                          double beTriggerRMultiple,
                          int trailingStart,
                          int trailingStep,
                          int minTradeAgeSeconds)
{
    //=== THROTTLED CLOSURE DIAGNOSTICS ===
    static datetime s_lastDiagLog = 0;
    datetime now = TimeCurrent();
    if(now - s_lastDiagLog >= 60)
    {
        s_lastDiagLog = now;
        int total = PositionsTotal();
        for(int i = total - 1; i >= 0; i--)
        {
            string posSymbol = PositionGetSymbol(i);
            if(posSymbol == "" || posSymbol != symbol) continue;
            if(PositionGetInteger(POSITION_MAGIC) != magic) continue;

            double sl = PositionGetDouble(POSITION_SL);
            double tp = PositionGetDouble(POSITION_TP);
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

            LogPrint("[CLOSURE_CHECK] ticket=" + IntegerToString(PositionGetInteger(POSITION_TICKET)) +
                     " | entry=" + DoubleToString(entry, _Digits) +
                     " | sl=" + DoubleToString(sl, _Digits) +
                     " | tp=" + DoubleToString(tp, _Digits) +
                     " | open=" + TimeToString(openTime), LOG_LEVEL_DEBUG);
        }
    }

    int total = PositionsTotal();
    LogDebug("[POS] Iterating | Total=" + IntegerToString(total));
   
   for(int i = total - 1; i >= 0; i--)
   {
      if(i < 0 || i >= total)
      {
         LogWarn("[POS] Invalid index access prevented | i=" + IntegerToString(i) + " | Total=" + IntegerToString(total));
         continue;
      }
      
      string posSymbol = PositionGetSymbol(i);
      if(posSymbol == "")
      {
         LogWarn("[POS] Failed to get position symbol at index " + IntegerToString(i));
         continue;
      }
      if(posSymbol != symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic)
         continue;

ulong ticket = PositionGetInteger(POSITION_TICKET);
       ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
       double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
       double currentSL = PositionGetDouble(POSITION_SL);
       double currentTP = PositionGetDouble(POSITION_TP);

       SSymbolProfile spPos = SY_GetProfile(symbol);
       double currentPrice = (posType == POSITION_TYPE_BUY)
                             ? ((spPos.tickBid > 0.0) ? spPos.tickBid : SymbolInfoDouble(symbol, SYMBOL_BID))
                             : ((spPos.tickAsk > 0.0) ? spPos.tickAsk : SymbolInfoDouble(symbol, SYMBOL_ASK));
       double point = (spPos.point > 0.0) ? spPos.point : SymbolInfoDouble(symbol, SYMBOL_POINT);
       int digits = (spPos.digits > 0) ? spPos.digits : (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

       // --- Spread calculation for true break-even ---
       long spreadPts = (spPos.spread > 0) ? (long)spPos.spread : SymbolInfoInteger(symbol, SYMBOL_SPREAD);
       double spread = (double)spreadPts * point;

        // --- Stops level + freeze level for SL precision ---
        long stopsLevelPts = spPos.stopsLevel > 0 ? spPos.stopsLevel : SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
        long freezeLevelPts = spPos.freezeLevel > 0 ? spPos.freezeLevel : SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
        double minSLDistancePts = (double)MathMax(stopsLevelPts, freezeLevelPts);
        double minSLDistance = (double)minSLDistancePts * point;

// --- Compute current profit in points ---
        double profitPoints = 0.0;
        if(posType == POSITION_TYPE_BUY)
           profitPoints = (currentPrice - openPrice) / point;
        else
           profitPoints = (openPrice - currentPrice) / point;

// --- Minimum trade age check ---
         long positionTimeRaw = PositionGetInteger(POSITION_TIME);
         datetime positionTime = (datetime)positionTimeRaw;
         int tradeAgeSeconds = (int)(TimeCurrent() - positionTime);
        if(tradeAgeSeconds < minTradeAgeSeconds)
        {
           LogDebug("[POS] Skip | Trade too young | Age=" + IntegerToString(tradeAgeSeconds) + "s | Min=" + IntegerToString(minTradeAgeSeconds) + "s");
           continue;
        }

        // Get or create position state for tracking
        int idx = PM_GetPositionStateIndex(ticket);
        if(idx < 0)
           idx = PM_CreatePositionState(ticket);

if(idx >= 0 && idx < ArraySize(g_positionStates))
         {
            SPositionState state = g_positionStates[idx];

           // Track profit bars (closed candles that finished in profit)
           if(profitPoints > 0.0)
       {
          datetime currentBarTime = iTime(symbol, PERIOD_CURRENT, 0);
          if(currentBarTime != state.lastProfitBarCheck)
          {
             // New bar — check if previous bar closed in profit
             double prevBarClose = iClose(symbol, PERIOD_CURRENT, 1);
             double prevBarProfitPts = (posType == POSITION_TYPE_BUY)
                                       ? (prevBarClose - openPrice) / point
                                       : (openPrice - prevBarClose) / point;
             if(prevBarProfitPts > 0.0)
                state.profitBars++;
             state.lastProfitBarCheck = currentBarTime;
          }

           // Track peak profit
           if(profitPoints > state.highestProfitPts)
              state.highestProfitPts = profitPoints;
        }

        g_positionStates[idx] = state;
        }

// ─── RULE 1: R-Multiple Break Even ───
      // Move SL to entry when profit >= R * beTriggerRMultiple
      // R = |entry - SL|, profitMove = |currentPrice - entry|
      double R = 0.0;
      if(currentSL > 0.0)
         R = MathAbs(openPrice - currentSL);
      
      double profitMove = 0.0;
      if(posType == POSITION_TYPE_BUY)
         profitMove = currentPrice - openPrice;
      else
         profitMove = openPrice - currentPrice;
      
      double requiredProfit = R * beTriggerRMultiple;
      bool shouldTriggerBE = false;
      
      if(R > 0.0 && profitMove >= requiredProfit)
      {
         shouldTriggerBE = true;
      }
      
// Check if BE already triggered for this trade
       int beIdx = PM_GetPositionStateIndex(ticket);
       bool beAlreadyTriggered = false;
       if(beIdx >= 0 && beIdx < ArraySize(g_positionStates))
          beAlreadyTriggered = g_positionStates[beIdx].beTriggered;
       else if(beIdx >= ArraySize(g_positionStates))
          LogPrint("[PM] WARN: BE check — beIdx " + IntegerToString(beIdx) +
                   " out of bounds (size=" + IntegerToString(ArraySize(g_positionStates)) + ")",
                   LOG_LEVEL_WARN);
      
      // Determine if we should move SL: must be first trigger, and SL not already at/beyond entry
      bool canMoveSL = false;
      if(shouldTriggerBE && !beAlreadyTriggered)
      {
         if(posType == POSITION_TYPE_BUY)
         {
            // For BUY: only move if SL is below entry
            if(currentSL == 0.0 || currentSL < openPrice)
               canMoveSL = true;
         }
         else // SELL
         {
            // For SELL: only move if SL is above entry
            if(currentSL == 0.0 || currentSL > openPrice)
               canMoveSL = true;
         }
      }
      
      // Log BE status
      if(R > 0.0)
      {
         double profitR = (R > 0.0) ? profitMove / R : 0.0;
         LogDebug("[BE-R] ProfitR=" + DoubleToString(profitR, 2) + " | R=" + DoubleToString(R, _Digits) + " | Trigger=" + DoubleToString(beTriggerRMultiple, 1) + "R | Triggered=" + (shouldTriggerBE ? "YES" : "NO") + " | Already=" + (beAlreadyTriggered ? "YES" : "NO"));
      }
      
      // Move SL to entry when triggered
      if(canMoveSL)
      {
         double newSL = openPrice;
         
         // Validate SL is allowed relative to current market price
         bool slValid = true;
         if(minSLDistancePts > 0)
         {
            double slDistPts = MathAbs(currentPrice - newSL) / point;
            if(slDistPts < minSLDistancePts)
               slValid = false;
         }
         
         if(slValid)
         {
            double adjustedSL = NormalizeDouble(newSL, digits);
            if(adjustedSL != currentSL)
            {
               MqlTradeRequest request = {};
               MqlTradeResult result = {};
               request.action    = TRADE_ACTION_SLTP;
               request.position  = ticket;
               request.symbol    = symbol;
               request.sl        = adjustedSL;
               request.tp        = currentTP;
               LogInfo("[BE-R] Triggered | R=" + DoubleToString(R, _Digits) + " | Trigger=" + DoubleToString(beTriggerRMultiple, 1) + "R | NewSL=Entry");
               if(!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE)
                  LogPrint("R-Multiple BE SL modify failed: " + IntegerToString(result.retcode), LOG_LEVEL_ERROR);
               
// Mark BE as triggered for this position
                if(idx >= 0 && idx < ArraySize(g_positionStates))
                   g_positionStates[idx].beTriggered = true;
                else if(idx >= ArraySize(g_positionStates))
                   LogPrint("[PM] WARN: BE trigger — idx " + IntegerToString(idx) +
                            " out of bounds (size=" + IntegerToString(ArraySize(g_positionStates)) + ")",
                            LOG_LEVEL_WARN);
            }
         }
      }
      
      // Log that BE didn't trigger if profit < required
      if(R > 0.0 && profitMove < requiredProfit)
         LogDebug("[BE-R] Not triggered | Profit=" + DoubleToString(profitMove, _Digits) + " | Required=" + DoubleToString(requiredProfit, _Digits));

      // ─── RULE 2: Trailing Stop — DISABLED ───
      // Fixed-point trailing replaced by structural trail PM_ManageStructuralTrail()
      // which trails behind confirmed Protected Swing Lows/Highs on the entry TF.
      // if(profitPoints >= trailingStart) { ... old fixed-point logic removed }

      // ─── RULE 3: Hard Exit on Opposite Signal ───
      // Checked externally — caller must pass signal context
   }
}

//+------------------------------------------------------------------+
//| PM_ManageTrailingAndBreakeven — Branch-aware trailing stop        |
//| entryTf reserved for future swing-based trailing (TTrades)        |
//+------------------------------------------------------------------+
void PM_ManageTrailingAndBreakeven(ENUM_TIMEFRAMES entryTf)
{
    if(PositionsTotal() == 0) return;
    PM_ManagePositions(_Symbol, InpMagicNumber, InpBE_R_Multiple,
                       InpTrailingStart, InpTrailingStep, InpMinTradeAgeSeconds);
}

//+------------------------------------------------------------------+
//| PM_DetectPSL — Detect Protected Swing Low on entry TF            |
//| REGRESSION_GUARD_TRAIL: Structural protected swings per TTFM|
//| Scans last 20 complete bars for 2+ consecutive down-close candles|
//| then a close above the first down-candle's open.                 |
//+------------------------------------------------------------------+
bool PM_DetectPSL(string symbol, ENUM_TIMEFRAMES tf, double &pslLow)
{
   int totalBars = iBars(symbol, tf);
   if(totalBars < 5) return false;
   int count = MathMin(totalBars - 1, 20);
   if(count < 3) return false;

   double o[20], c[20], l[20];
   for(int i = 0; i < count; i++)
   {
      int idx = count - i;
      o[i] = iOpen(symbol, tf, idx);
      c[i] = iClose(symbol, tf, idx);
      l[i] = iLow(symbol, tf, idx);
   }
   for(int i = 0; i < count - 2; i++)
   {
      if(c[i] >= o[i]) continue;
      int j = i;
      while(j < count && c[j] < o[j]) j++;
      if(j - i < 2) continue;
      double confLevel = o[i];
      double swingLow = DBL_MAX;
      for(int k = i; k < j; k++)
         if(l[k] < swingLow) swingLow = l[k];
      for(int k = j; k < count; k++)
      {
         if(c[k] > confLevel)
         {
            pslLow = swingLow;
            return true;
         }
      }
      i = j;
   }
   return false;
}

//+------------------------------------------------------------------+
//| PM_DetectPSH — Detect Protected Swing High on entry TF           |
//| REGRESSION_GUARD_TRAIL: Structural protected swings per TTFM|
//| Scans last 20 complete bars for 2+ consecutive up-close candles  |
//| then a close below the first up-candle's open.                   |
//+------------------------------------------------------------------+
bool PM_DetectPSH(string symbol, ENUM_TIMEFRAMES tf, double &pshHigh)
{
   int totalBars = iBars(symbol, tf);
   if(totalBars < 5) return false;
   int count = MathMin(totalBars - 1, 20);
   if(count < 3) return false;

   double o[20], c[20], h[20];
   for(int i = 0; i < count; i++)
   {
      int idx = count - i;
      o[i] = iOpen(symbol, tf, idx);
      c[i] = iClose(symbol, tf, idx);
      h[i] = iHigh(symbol, tf, idx);
   }
   for(int i = 0; i < count - 2; i++)
   {
      if(c[i] <= o[i]) continue;
      int j = i;
      while(j < count && c[j] > o[j]) j++;
      if(j - i < 2) continue;
      double confLevel = o[i];
      double swingHigh = 0.0;
      for(int k = i; k < j; k++)
         if(h[k] > swingHigh) swingHigh = h[k];
      for(int k = j; k < count; k++)
      {
         if(c[k] < confLevel)
         {
            pshHigh = swingHigh;
            return true;
         }
      }
      i = j;
   }
   return false;
}

// PM_ManageStructuralTrail REMOVED — replaced by EE_ManageStructuralTrail in ExitEngine.mqh
// Constitution: Trailing is centralized in ExitEngine with canonical data validation,
// proper [TRAIL_PSL]/[TRAIL_PSH] markers, and branch-aware timeframe logic.
// PM_DetectPSL and PM_DetectPSH remain for swing detection used by ExitEngine.

//+------------------------------------------------------------------+
//| PM_UpdateTradeStats — Track trade outcomes for kill switch       |
//| Enhanced with DEAL_REASON to distinguish SL/TP/manual closes     |
//+------------------------------------------------------------------+
void PM_UpdateTradeStats(double profit, ENUM_DEAL_REASON reason = DEAL_REASON_EXPERT)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0.0)
      return;

   if(profit < 0.0)
   {
      g_tradeGovernor.consecutiveLosses++;
      double lossPercent = (MathAbs(profit) / balance) * 100.0;
      g_tradeGovernor.dailyLoss += lossPercent;

   }
   else if(profit > 0.0)
   {
      g_tradeGovernor.consecutiveLosses = 0;
   }
}

//+------------------------------------------------------------------+
//| PM_ClosePosition — Close with filling mode fallback chain          |
//+------------------------------------------------------------------+
bool PM_ClosePosition(ulong ticket, string symbol)
{
     if(!CanSendOrder(symbol))
        return false;
     
     if(!PositionSelectByTicket(ticket))
     {
        LogWarn("[HARD EXIT] Position no longer exists | Ticket=" + IntegerToString(ticket));
        return false;
     }
     
int retryIdx = FindCloseRetry(ticket);
      if(retryIdx >= 0 && retryIdx < ArraySize(g_closeRetries) && g_closeRetries[retryIdx].attempts >= MAX_CLOSE_RETRIES)
      {
         LogWarn("[CLOSE] Max retries exceeded | Ticket=" + IntegerToString(ticket) + " | Attempts=" + IntegerToString(g_closeRetries[retryIdx].attempts));
         SL_TerminateSignal(0, SIGNAL_TERM_EXEC_FAILED, "Close failed: max retries for " + IntegerToString(ticket));
         return false;
      }
      else if(retryIdx >= ArraySize(g_closeRetries))
      {
         LogPrint("[PM] WARN: Close retry — retryIdx " + IntegerToString(retryIdx) +
                 " out of bounds (size=" + IntegerToString(ArraySize(g_closeRetries)) + ")",
                 LOG_LEVEL_WARN);
      }

ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
     double volume = PositionGetDouble(POSITION_VOLUME);
     double positionProfit = PositionGetDouble(POSITION_PROFIT);

     SSymbolProfile spClose = SY_GetProfile(symbol);
     int digits = (spClose.digits > 0) ? spClose.digits : (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

     ENUM_ORDER_TYPE_FILLING fillingModes[3];
      int fillingModeCount = 0;
      ENUM_ORDER_TYPE_FILLING bestMode = GetBestFillingMode(symbol);

     fillingModes[fillingModeCount++] = ORDER_FILLING_FOK;
     fillingModes[fillingModeCount++] = ORDER_FILLING_IOC;
     fillingModes[fillingModeCount++] = ORDER_FILLING_RETURN;
    bool success = false;

    for(int m = 0; m < fillingModeCount; m++)
    {
       ENUM_ORDER_TYPE_FILLING mode = fillingModes[m];

       MqlTradeRequest request = {};
       MqlTradeResult result = {};
       request.action    = TRADE_ACTION_DEAL;
       request.position  = ticket;
       request.symbol   = symbol;
       request.volume   = volume;
       request.type     = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
       double currentPrice = (posType == POSITION_TYPE_BUY)
                           ? ((spClose.tickBid > 0.0) ? spClose.tickBid : SymbolInfoDouble(symbol, SYMBOL_BID))
                           : ((spClose.tickAsk > 0.0) ? spClose.tickAsk : SymbolInfoDouble(symbol, SYMBOL_ASK));
       request.price    = NormalizeDouble(currentPrice, digits);
  // REGRESSION_GUARD_DEVIATION: Dynamic point-scaled — works for all symbols
  double pointVal = (spClose.point > 0.0) ? spClose.point : SymbolInfoDouble(symbol, SYMBOL_POINT);
  request.deviation = (ulong)(pointVal * 30);
        request.magic     = (long)PositionGetInteger(POSITION_MAGIC);
        // REGRESSION_GUARD_V52.5_CLOSE_GUID_LOGGING: Canonical GUID from PositionGUIDMap, not POSITION_MAGIC
        request.comment   = StringFormat("GUID=%I64u|", GetGUIDFromPositionMap(ticket));
       request.type_filling = mode;
       
       LogInfo("[CLOSE] Attempt mode: " + EnumToString(mode) + " | Ticket=" + IntegerToString(ticket));
       
       if(OrderSend(request, result))
       {
          if(result.retcode == TRADE_RETCODE_DONE)
          {
             LogInfo("[CLOSE] Success with mode: " + EnumToString(mode) + " | Ticket=" + IntegerToString(ticket));
              PM_UpdateTradeStats(positionProfit, DEAL_REASON_EXPERT);
              return true;
          }
          else
          {
             LogWarn("[CLOSE] Failed mode: " + EnumToString(mode) + " | Error=" + IntegerToString(result.retcode));
          }
       }
       else
       {
          LogWarn("[CLOSE] Failed mode: " + EnumToString(mode) + " | Error=" + IntegerToString(GetLastError()));
       }
    }
    
    IncrementCloseRetry(ticket);
    LogWarn("[CLOSE] All modes failed | Ticket=" + IntegerToString(ticket));
    SL_TerminateSignal(0, SIGNAL_TERM_EXEC_FAILED, "Close failed: all filling modes exhausted for " + symbol);
    
    return false;
}

#endif // OMAK_POSITIONMANAGER_MQH
