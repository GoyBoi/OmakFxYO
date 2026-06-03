//+------------------------------------------------------------------+
//|                                            ExitEngine.mqh |
//|                     OmakFxYO — Centralized Structural Exit Engine |
//|                                                                  |
//| Constitution: All exits are structural, branch-aware, fill-aware, |
//| and emit required runtime markers. No ATR exits. No 1:1 fallback. |
//| No hardcoded M5-only logic. Every exit validates canonical data.  |
//+------------------------------------------------------------------+
#ifndef OMAK_EXITENGINE_MQH
#define OMAK_EXITENGINE_MQH

#property strict

#include <OmakFxYO/core/CoreTypes.mqh>
#include <OmakFxYO/core/StructuralStateEngine.mqh>
#include <OmakFxYO/core/DowTheoryEngine.mqh>
#include <OmakFxYO/core/PositionManager.mqh>

//+------------------------------------------------------------------+
//| EE_CanonicalMapData — Validate that PositionGUIDMap data        |
//| is structurally sound before trusting it for exit decisions.    |
//+------------------------------------------------------------------+
struct SECanonicalCheck
{
   bool   mapExists;          // Entry exists in map
   bool   guidValid;          // signalGUID != 0
   bool   directionValid;     // DIRECTION_BUY or DIRECTION_SELL
   bool   hasC1Data;          // c1_high > 0 && c1_low > 0
   bool   hasC2Data;          // c2_low > 0 || c2_high > 0
   bool   hasEntryPrice;      // entryPrice > 0 (fill price from deal)
   bool   allValid;           // All required fields present
   string failReason;

   void Reset()
   {
      mapExists = false;
      guidValid = false;
      directionValid = false;
      hasC1Data = false;
      hasC2Data = false;
      hasEntryPrice = false;
      allValid = false;
      failReason = "";
   }

   bool Evaluate(const PositionGUIDMap &map)
   {
      Reset();
      mapExists = true;
      guidValid = (map.signalGUID != 0);
      directionValid = (map.direction == DIRECTION_BUY || map.direction == DIRECTION_SELL);
      hasC1Data = (map.c1_high > 0.0 && map.c1_low > 0.0);
      hasC2Data = (map.c2_low > 0.0 || map.c2_high > 0.0);
      hasEntryPrice = (map.entryPrice > 0.0);

      // Structural exit requires: GUID + direction + C1 data + entry price
      if(!guidValid)
         failReason = "signalGUID is 0";
      else if(!directionValid)
         failReason = "direction is NONE";
      else if(!hasC1Data)
         failReason = "C1 data missing";
      else if(!hasEntryPrice)
         failReason = "entryPrice is 0 (fill not recorded)";
      else
         allValid = true;

      return allValid;
   }
};

//+------------------------------------------------------------------+
//| EE_CRTEvaluation — CRT Target Evaluation Result                 |
//+------------------------------------------------------------------+
enum ENUM_CRT_RESULT
{
   CRT_NONE = 0,
   CRT_TARGET_VALID,        // C1 extreme is valid and reachable
   CRT_TARGET_INVALID,      // C1 extreme is structurally invalid (e.g. <= entry for BUY)
   CRT_TARGET_ESCALATED     // C1 invalid, escalated to HTF swing extreme
};

struct SECRTResult
{
   ENUM_CRT_RESULT result;
   double          targetPrice;
   string          source;     // "C1_EXTREME" or "HTF_ESCALATION"
   string          branchLabel;
   bool            exitReady;  // true if current price has reached the target

   void Reset()
   {
      result = CRT_NONE;
      targetPrice = 0.0;
      source = "";
      branchLabel = "";
      exitReady = false;
   }
};

//+------------------------------------------------------------------+
//| EE_EvaluateCRTTarget — Evaluate CRT target for a position         |
//|                                                                  |
//| Requirements per Constitution:                                    |
//| - CRT target must be structurally valid or explicitly rejected    |
//| - No silent 1:1 fallback                                         |
//| - Uses actual fill price (mapEntry.entryPrice)                   |
//| - Emits [CRT_TARGET_VALID], [CRT_TARGET_INVALID],               |
//|   [CRT_TARGET_ESCALATED] markers                                 |
//+------------------------------------------------------------------+
bool EE_EvaluateCRTTarget(const PositionGUIDMap &mapEntry, SECRTResult &outResult)
{
   outResult.Reset();

   if(mapEntry.c1_high <= 0.0 || mapEntry.c1_low <= 0.0)
   {
      outResult.result = CRT_TARGET_INVALID;
      PrintFormat("[CRT_TARGET_INVALID] GUID=%I64u reason=NULL_C1_VALUES c1_high=%.5f c1_low=%.5f",
                  mapEntry.signalGUID, mapEntry.c1_high, mapEntry.c1_low);
      return false;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   ENUM_TIMEFRAMES htf = (mapEntry.branch == BRANCH_INTRADAY) ? PERIOD_H1 : PERIOD_H4;
   string branchLabel = (mapEntry.branch == BRANCH_INTRADAY) ? "A" : "B";

   if(mapEntry.direction == DIRECTION_BUY)
   {
      // Primary CRT target: c1_high must be above entry
      if(mapEntry.c1_high > mapEntry.entryPrice)
      {
         outResult.targetPrice = mapEntry.c1_high;
         outResult.source = "C1_EXTREME";
         outResult.branchLabel = branchLabel;
         outResult.result = CRT_TARGET_VALID;
         outResult.exitReady = (bid >= mapEntry.c1_high);

         PrintFormat("[CRT_TARGET_VALID] GUID=%I64u BUY c1_high=%.5f entry=%.5f bid=%.5f ready=%s branch=%s",
                     mapEntry.signalGUID, mapEntry.c1_high, mapEntry.entryPrice, bid,
                     outResult.exitReady ? "YES" : "NO", branchLabel);
         return true;
      }

      // C1 extreme invalid — escalate to HTF swing high
      double highs[];
      ArraySetAsSeries(highs, true);
      int copied = CopyHigh(_Symbol, htf, 0, 50, highs);
      if(copied > 5)
      {
         for(int i = 5; i < copied - 2; i++)
         {
            if(highs[i] > highs[i-1] && highs[i] > highs[i-2] &&
               highs[i] > highs[i+1] && highs[i] > highs[i+2] &&
               highs[i] > mapEntry.entryPrice)
            {
               outResult.targetPrice = highs[i];
               outResult.source = "HTF_ESCALATION";
               outResult.branchLabel = branchLabel;
               outResult.result = CRT_TARGET_ESCALATED;
               outResult.exitReady = (bid >= highs[i]);

               PrintFormat("[CRT_TARGET_ESCALATED] GUID=%I64u BUY c1_high=%.5f<=entry escalated_to=%.5f on %s ready=%s branch=%s",
                           mapEntry.signalGUID, mapEntry.c1_high, highs[i], EnumToString(htf),
                           outResult.exitReady ? "YES" : "NO", branchLabel);
               return true;
            }
         }
      }

      // No valid target found — explicit rejection
      outResult.result = CRT_TARGET_INVALID;
      outResult.branchLabel = branchLabel;
      PrintFormat("[CRT_TARGET_INVALID] GUID=%I64u BUY c1_high=%.5f entry=%.5f no HTF swing above entry branch=%s",
                  mapEntry.signalGUID, mapEntry.c1_high, mapEntry.entryPrice, branchLabel);
      return false;
   }
   else if(mapEntry.direction == DIRECTION_SELL)
   {
      // Primary CRT target: c1_low must be below entry
      if(mapEntry.c1_low < mapEntry.entryPrice)
      {
         outResult.targetPrice = mapEntry.c1_low;
         outResult.source = "C1_EXTREME";
         outResult.branchLabel = branchLabel;
         outResult.result = CRT_TARGET_VALID;
         outResult.exitReady = (ask <= mapEntry.c1_low);

         PrintFormat("[CRT_TARGET_VALID] GUID=%I64u SELL c1_low=%.5f entry=%.5f ask=%.5f ready=%s branch=%s",
                     mapEntry.signalGUID, mapEntry.c1_low, mapEntry.entryPrice, ask,
                     outResult.exitReady ? "YES" : "NO", branchLabel);
         return true;
      }

      // C1 extreme invalid — escalate to HTF swing low
      double lows[];
      ArraySetAsSeries(lows, true);
      int copied = CopyLow(_Symbol, htf, 0, 50, lows);
      if(copied > 5)
      {
         for(int i = 5; i < copied - 2; i++)
         {
            if(lows[i] < lows[i-1] && lows[i] < lows[i-2] &&
               lows[i] < lows[i+1] && lows[i] < lows[i+2] &&
               lows[i] < mapEntry.entryPrice)
            {
               outResult.targetPrice = lows[i];
               outResult.source = "HTF_ESCALATION";
               outResult.branchLabel = branchLabel;
               outResult.result = CRT_TARGET_ESCALATED;
               outResult.exitReady = (ask <= lows[i]);

               PrintFormat("[CRT_TARGET_ESCALATED] GUID=%I64u SELL c1_low=%.5f>=entry escalated_to=%.5f on %s ready=%s branch=%s",
                           mapEntry.signalGUID, mapEntry.c1_low, lows[i], EnumToString(htf),
                           outResult.exitReady ? "YES" : "NO", branchLabel);
               return true;
            }
         }
      }

      // No valid target found — explicit rejection
      outResult.result = CRT_TARGET_INVALID;
      outResult.branchLabel = branchLabel;
      PrintFormat("[CRT_TARGET_INVALID] GUID=%I64u SELL c1_low=%.5f entry=%.5f no HTF swing below entry branch=%s",
                  mapEntry.signalGUID, mapEntry.c1_low, mapEntry.entryPrice, branchLabel);
      return false;
   }

   outResult.result = CRT_TARGET_INVALID;
   PrintFormat("[CRT_TARGET_INVALID] GUID=%I64u reason=INVALID_DIRECTION dir=%d",
               mapEntry.signalGUID, mapEntry.direction);
   return false;
}

//+------------------------------------------------------------------+
//| EE_EvaluateCISDReversal — Evaluate CISD reversal exit            |
//|                                                                  |
//| Branch-aware timeframe:                                          |
//|   Branch A (Intraday): M5                                       |
//|   Branch B (Swing):    M15                                      |
//|                                                                  |
//| Returns: true if opposite-direction CISD detected on LTF         |
//| Emits:  [EXIT_CISD_REVERSAL] marker                              |
//+------------------------------------------------------------------+
bool EE_EvaluateCISDReversal(ulong guid, ENUM_DIRECTION positionDir, ENUM_EXECUTION_BRANCH branch)
{
   ENUM_TIMEFRAMES ltf = (branch == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;
   ENUM_DIRECTION targetDir = (positionDir == DIRECTION_BUY) ? DIRECTION_SELL : DIRECTION_BUY;

   bool reversalDetected = SSE_DetectCISD(_Symbol, ltf, targetDir);

   if(reversalDetected)
   {
      string dirStr = (positionDir == DIRECTION_BUY) ? "BUY" : "SELL";
      PrintFormat("[EXIT_CISD_REVERSAL] GUID=%I64u position=%s detected opposite CISD on %s branch=%s",
                  guid, dirStr, EnumToString(ltf),
                  (branch == BRANCH_INTRADAY) ? "A" : "B");
   }

   return reversalDetected;
}

//+------------------------------------------------------------------+
//| EE_EvaluateDowBOS — Evaluate Dow BOS exit                        |
//|                                                                  |
//| Must be event-based (new CHoCH per bar), not merely trend-state. |
//| Branch-aware timeframe:                                          |
//|   Branch A (Intraday): H1                                       |
//|   Branch B (Swing):    H4                                       |
//|                                                                  |
//| Returns: true if new CHoCH event detected on HTF                |
//| Emits:  [EXIT_DOW_BOS] marker                                    |
//+------------------------------------------------------------------+
bool EE_EvaluateDowBOS(ulong guid, ENUM_DIRECTION positionDir, ENUM_EXECUTION_BRANCH branch)
{
   ENUM_TIMEFRAMES htf = (branch == BRANCH_INTRADAY) ? PERIOD_H1 : PERIOD_H4;

   // Event-based: detect CHoCH (Change of Character) — trend reversal event
   static datetime s_lastChochA = 0;
   static datetime s_lastChochB = 0;

   SDowTheoryContext dtCtx = AnalyzeStructure(_Symbol, htf);
   if(dtCtx.lastEvent != EVENT_CHoCH)
      return false;

   datetime currentBarTime = iTime(_Symbol, htf, 0);
   datetime lastChoch = (branch == BRANCH_INTRADAY) ? s_lastChochA : s_lastChochB;

   if(currentBarTime > lastChoch)
   {
      if(branch == BRANCH_INTRADAY)
         s_lastChochA = currentBarTime;
      else
         s_lastChochB = currentBarTime;
      string dirStr = (positionDir == DIRECTION_BUY) ? "BUY" : "SELL";
      PrintFormat("[EXIT_DOW_BOS] GUID=%I64u position=%s new CHoCH on %s branch=%s",
                  guid, dirStr, EnumToString(htf),
                  (branch == BRANCH_INTRADAY) ? "A" : "B");
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| EE_ManageStructuralTrail — Branch-aware trailing behind          |
//| confirmed Protected Swing levels on entry TF.                   |
//|                                                                  |
//| Per Constitution:                                                |
//|   - Takes ENUM_EXECUTION_BRANCH (BRANCH_INTRADAY or BRANCH_SWING)|
//|   - Only processes positions belonging to the given branch       |
//|   - Anchored to C2 extreme (c2_low for BUY, c2_high for SELL)  |
//|   - Only activates when canonical map data exists               |
//|   - No ATR-based trailing                                       |
//|   - Emits [TRAIL_PSL] / [TRAIL_PSH] markers                    |
//+------------------------------------------------------------------+
void EE_ManageStructuralTrail(ENUM_EXECUTION_BRANCH branch)
{
   if(PositionsTotal() == 0)
      return;

   ENUM_TIMEFRAMES entryTf = (branch == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;
   string branchLabel = (branch == BRANCH_INTRADAY) ? "A" : "B";
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minBuffer = stopsLevel * point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      // Branch filter: only process positions belonging to this branch
      if(GetPositionBranchByTicket(ticket) != branch)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // Canonical data check: must have valid protected swing from GUIDMap
      double c2_low = 0.0, c2_high = 0.0;
      if(!GetProtectedSwingByTicket(ticket, c2_low, c2_high))
      {
         PrintFormat("[TRAIL_SKIP] ticket=%I64u branch=%s reason=NO_CANONICAL_DATA", ticket, branchLabel);
         continue;
      }

      if(posType == POSITION_TYPE_BUY)
      {
         if(c2_low <= 0.0)
         {
            LogPrint("[TRAIL_SKIP] BUY c2_low=0 | ticket=" + IntegerToString(ticket) +
                     " | branch=" + branchLabel, LOG_LEVEL_DEBUG);
            continue;
         }

         double swingLow = 0.0;
         if(!PM_DetectPSL(_Symbol, entryTf, swingLow))
            continue;

         if(swingLow <= currentSL + point)
            continue;

         double newSL = swingLow;
         if(newSL < c2_low + point)
            newSL = c2_low + point;

         double slFromPrice = bid - newSL;
         if(slFromPrice < minBuffer)
            newSL = NormalizeDouble(bid - minBuffer, digits);
         if(newSL < c2_low + point)
            newSL = c2_low + point;

         if(newSL <= currentSL + point || newSL <= entryPrice + point)
            continue;

         MqlTradeRequest req = {};
         MqlTradeResult res = {};
         req.action = TRADE_ACTION_SLTP;
         req.position = ticket;
         req.symbol = _Symbol;
         req.sl = NormalizeDouble(newSL, digits);
         req.tp = currentTP;
         req.magic = InpMagicNumber;

         if(OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
         {
            ulong guid = GetGUIDFromPositionMap(ticket);
            PrintFormat("[TRAIL_PSL] GUID=%I64u new_sl=%.5f swing=%.5f c2_low=%.5f branch=%s",
                        guid, newSL, swingLow, c2_low, branchLabel);
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         if(c2_high <= 0.0)
         {
            LogPrint("[TRAIL_SKIP] SELL c2_high=0 | ticket=" + IntegerToString(ticket) +
                     " | branch=" + branchLabel, LOG_LEVEL_DEBUG);
            continue;
         }

         double swingHigh = 0.0;
         if(!PM_DetectPSH(_Symbol, entryTf, swingHigh))
            continue;

         if(swingHigh >= currentSL - point)
            continue;

         double newSL = swingHigh;
         if(newSL > c2_high - point)
            newSL = c2_high - point;

         double slFromPrice = newSL - ask;
         if(slFromPrice < minBuffer)
            newSL = NormalizeDouble(ask + minBuffer, digits);
         if(newSL > c2_high - point)
            newSL = c2_high - point;

         if(newSL >= currentSL - point || newSL >= entryPrice - point)
            continue;

         MqlTradeRequest req = {};
         MqlTradeResult res = {};
         req.action = TRADE_ACTION_SLTP;
         req.position = ticket;
         req.symbol = _Symbol;
         req.sl = NormalizeDouble(newSL, digits);
         req.tp = currentTP;
         req.magic = InpMagicNumber;

         if(OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
         {
            ulong guid = GetGUIDFromPositionMap(ticket);
            PrintFormat("[TRAIL_PSH] GUID=%I64u new_sl=%.5f swing=%.5f c2_high=%.5f branch=%s",
                        guid, newSL, swingHigh, c2_high, branchLabel);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| EE_ClosePositionAndLog — Close position and emit exit marker     |
//| Wraps PM_ClosePosition with standardized logging and slot release |
//+------------------------------------------------------------------+
void EE_ClosePositionAndLog(ulong ticket, ulong guid, ENUM_EXIT_TYPE exitType)
{
   if(!PositionSelectByTicket(ticket))
   {
      LogPrint("[EXIT_FAIL] Position not found | ticket=" + IntegerToString(ticket), LOG_LEVEL_WARN);
      return;
   }

   if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
      return;

   double pnl = PositionGetDouble(POSITION_PROFIT);

   if(PM_ClosePosition(ticket, _Symbol))
   {
      LogExitMarker(guid, exitType, pnl);
      OM_ClearSlot(guid);

      string exitStr = "";
      switch(exitType)
      {
         case EXIT_CRT_TARGET:     exitStr = "CRT_TARGET";     break;
         case EXIT_CISD_REVERSAL:  exitStr = "CISD_REVERSAL";  break;
         case EXIT_DOW_BOS:        exitStr = "DOW_BOS";        break;
         case EXIT_TRAILING_STOP:  exitStr = "TRAILING_STOP";   break;
         case EXIT_SL_HIT:         exitStr = "SL_HIT";         break;
         case EXIT_EMERGENCY_CLOSE: exitStr = "EMERGENCY_CLOSE"; break;
         default:                  exitStr = "UNKNOWN";         break;
      }

      PrintFormat("[SLOT_RELEASED] ManagedExit=%s position=%I64u guid=%I64u pnl=%.2f",
                  exitStr, ticket, guid, pnl);
   }
   else
   {
      LogPrint("[EXIT_FAIL] PM_ClosePosition failed | ticket=" + IntegerToString(ticket) +
               " | exitType=" + EnumToString(exitType), LOG_LEVEL_WARN);
   }
}

//+------------------------------------------------------------------+
//| EE_EvaluateAndExit — Full exit evaluation for a single position   |
//|                                                                  |
//| Returns: true if position was closed (exit executed)             |
//| Emits required runtime markers for CRT, CISD, BOS, blocked       |
//+------------------------------------------------------------------+
bool EE_EvaluateAndExit(ulong ticket, const PositionGUIDMap &mapEntry,
                        bool allowCRT, bool allowCISD, bool allowBOS,
                        bool newCISDBar, bool newBOSBar)
{
   if(mapEntry.signalGUID == 0 || mapEntry.direction == DIRECTION_NONE)
      return false;

   SECanonicalCheck canonicalCheck;
   if(!canonicalCheck.Evaluate(mapEntry))
   {
      PrintFormat("[EXIT_BLOCKED_NO_VALID_TARGET] GUID=%I64u reason=ORPHANED_MAP_DATA fail=%s ticket=%I64u",
                  mapEntry.signalGUID, canonicalCheck.failReason, ticket);
      return false;
   }

   // (1) CRT Full Target — every tick (price level)
   if(allowCRT)
   {
      SECRTResult crtResult;
      if(EE_EvaluateCRTTarget(mapEntry, crtResult))
      {
         if(crtResult.exitReady)
         {
            EE_ClosePositionAndLog(ticket, mapEntry.signalGUID, EXIT_CRT_TARGET);
            return true;
         }
      }
   }

   // (2) Dow BOS — once per HTF bar (higher priority than CISD)
   if(allowBOS && newBOSBar)
   {
      if(EE_EvaluateDowBOS(mapEntry.signalGUID, mapEntry.direction, mapEntry.branch))
      {
         EE_ClosePositionAndLog(ticket, mapEntry.signalGUID, EXIT_DOW_BOS);
         return true;
      }
   }

   // (3) CISD Reversal — once per LTF bar
   if(allowCISD && newCISDBar)
   {
      if(EE_EvaluateCISDReversal(mapEntry.signalGUID, mapEntry.direction, mapEntry.branch))
      {
         EE_ClosePositionAndLog(ticket, mapEntry.signalGUID, EXIT_CISD_REVERSAL);
         return true;
      }
   }

   return false;
}

#endif // OMAK_EXITENGINE_MQH
