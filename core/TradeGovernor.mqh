 //+------------------------------------------------------------------+
 //| TradeGovernor.mqh                                                 |
 //| Central trade authority — prevents duplicates, enforces cooldown  |
 //+------------------------------------------------------------------+
 #ifndef OMAK_TRADEGOVERNOR_MQH
 #define OMAK_TRADEGOVERNOR_MQH

 #include "CoreTypes.mqh"
 
 #include <OmakFxYO/core/LogGovernor.mqh>  // Centralized log governance

 #define MAX_RECENT_SIGNALS 5

  // Reference to EA's daily reset tracker (defined in OmakFxYO.mq5)
  extern datetime g_lastResetDay;

 //+------------------------------------------------------------------+
 //| Trade Governor State                                              |
 //+------------------------------------------------------------------+
struct STradeGovernorState
  {
   datetime          lastTradeTime;      // Timestamp of last executed trade
   ulong             lastSignalHash;     // Hash of last executed signal
   int               consecutiveLosses;  // Track consecutive losing trades
   double            dailyLoss;          // Cumulative loss for current day

   // Recent signal history (prevent re-entry after close)
   ulong             recentSignals[MAX_RECENT_SIGNALS];
   int               recentSignalCount;
   int               recentSignalIndex;
  };

// Global instance
STradeGovernorState g_tradeGovernor;

// Position state globals (moved from PositionManager to avoid circular include)
#define MAX_TRACKED_POSITIONS 10
struct SPositionState
{
   ulong    ticket;
   bool     tp1Done;
   bool     tp2Done;
   double   partialVolume;
   datetime entryTime;
   int      profitBars;
   double   highestProfitPts;
   datetime lastProfitBarCheck;
   bool     beTriggered;
   double   trailSwingLevel;      // Last trailed swing level (PSL low for buys, PSH high for sells)
   datetime lastTrailBarTime;     // Time of last entry-TF bar processed for structural trail
};
SPositionState g_positionStates[MAX_TRACKED_POSITIONS];
int g_positionStateCount = 0;

//+------------------------------------------------------------------+
//| GV Helper Functions — Account-wide naming + date tracking         |
//+------------------------------------------------------------------+

string GetGvLossName()
{
   ulong login = AccountInfoInteger(ACCOUNT_LOGIN);
   return "OMAK_DAILY_LOSS_" + IntegerToString(login);
}

string GetGvDateName()
{
   ulong login = AccountInfoInteger(ACCOUNT_LOGIN);
   return "OMAK_DAILY_LOSS_DATE_" + IntegerToString(login);
}

//+------------------------------------------------------------------+
//| Initialize recent signal history                                  |
 //+------------------------------------------------------------------+
void TG_Init(long magicNumber, string symbol)
{
   // Account-wide GV naming is handled by GetGvLossName() on demand
   
   g_tradeGovernor.recentSignalCount = 0;
     g_tradeGovernor.recentSignalIndex = 0;
     g_tradeGovernor.dailyLoss = 0.0;
     g_tradeGovernor.consecutiveLosses = 0;
     for(int i = 0; i < MAX_RECENT_SIGNALS; i++)
        g_tradeGovernor.recentSignals[i] = 0;
    }

//+------------------------------------------------------------------+
//| Check if signal exists in recent history                          |
//+------------------------------------------------------------------+
bool TG_IsSignalInHistory(ulong signalHash)
  {
   for(int i = 0; i < g_tradeGovernor.recentSignalCount; i++)
     {
      if(g_tradeGovernor.recentSignals[i] == signalHash && signalHash != 0)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Add signal to recent history (circular buffer)                    |
//+------------------------------------------------------------------+
void TG_AddSignalToHistory(ulong signalHash)
  {
   if(signalHash == 0)
      return;

   g_tradeGovernor.recentSignals[g_tradeGovernor.recentSignalIndex] = signalHash;
   g_tradeGovernor.recentSignalIndex = (g_tradeGovernor.recentSignalIndex + 1) % MAX_RECENT_SIGNALS;

   if(g_tradeGovernor.recentSignalCount < MAX_RECENT_SIGNALS)
      g_tradeGovernor.recentSignalCount++;
  }

//+------------------------------------------------------------------+
//| Check if a trade can be opened (no existing position)            |
//+------------------------------------------------------------------+
bool TG_CanOpenTrade(string symbol, long magic)
  {
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      if(PositionGetSymbol(i) != symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) == magic)
         return false;  // Position already exists for this symbol + magic
     }
   return true;
  }

//+------------------------------------------------------------------+
//| TG_CanScale — Check if a second position is allowed              |
//| Rules: Max 2 positions, first must be profitable, same direction |
//|        new signal hash must differ from last                      |
//| Intelligence Layer v3: volatility gate, exposure cap             |
//+------------------------------------------------------------------+
bool TG_CanScale(string symbol, long magic, ENUM_DIRECTION newDirection, ulong newSignalHash)
  {
   int posCount = 0;
   bool firstInProfit = false;
   bool sameDirection = false;
   double totalExposure = 0.0;

   // --- Scaling delay: track profit bar count for existing positions ---
   int minProfitBars = 2;  // Require 2 closed candles in profit before scaling
   bool hasEnoughProfitBars = false;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionGetSymbol(i) != symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic)
         continue;

      posCount++;
      if(posCount > 2)
         return false;  // Already at max 2 positions

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      totalExposure += volume;

      // Check if existing position is in profit
      double currentPrice = (posType == POSITION_TYPE_BUY)
                            ? SymbolInfoDouble(symbol, SYMBOL_BID)
                            : SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(posType == POSITION_TYPE_BUY && currentPrice > openPrice)
         firstInProfit = true;
      else if(posType == POSITION_TYPE_SELL && currentPrice < openPrice)
         firstInProfit = true;

      // Check direction alignment
      if((posType == POSITION_TYPE_BUY && newDirection == DIRECTION_BUY) ||
         (posType == POSITION_TYPE_SELL && newDirection == DIRECTION_SELL))
         sameDirection = true;

      // --- Scaling delay: check profit bar count from position state ---
      // Find matching position state to read profitBars count
      ulong posTicket = PositionGetInteger(POSITION_TICKET);
      for(int j = 0; j < g_positionStateCount; j++)
        {
         if(g_positionStates[j].ticket == posTicket)
           {
            if(g_positionStates[j].profitBars >= minProfitBars)
               hasEnoughProfitBars = true;
            break;
           }
        }
     }

   // Must have at least 1 existing position to scale
   if(posCount < 1)
      return false;

   // All base conditions must be met
   if(!firstInProfit)
      return false;
   if(!sameDirection)
      return false;
   if(newSignalHash == g_tradeGovernor.lastSignalHash && newSignalHash != 0)
      return false;  // Same signal hash — not a new setup

   // ═══════════════════════════════════════════════════════════
   // SCALING DELAY — Require minimum profit bars before scaling
   // Prevents instant scaling after a single profitable spike.
   // At least 2 closed candles must finish in profit.
   // ═══════════════════════════════════════════════════════════
   if(!hasEnoughProfitBars)
      return false;

   // ═══════════════════════════════════════════════════════════
   // INTELLIGENCE LAYER v3 — Additional gating checks
   // ═══════════════════════════════════════════════════════════

// Volatility gate removed — ATR subsystem eliminated

   // Exposure cap: dynamic based on equity + recent drawdown
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(equity > 0.0 && balance > 0.0)
   {
      double drawdown = (balance - equity) / balance;
      if(drawdown > 0.03)  // >3% drawdown — reduce scaling allowance
         return false;
   }

   // Consecutive loss protection: no scaling on losing streak
   if(g_tradeGovernor.consecutiveLosses >= 2)
      return false;

   return true;
  }

//+------------------------------------------------------------------+
//| Check if signal is duplicate of last executed signal              |
//+------------------------------------------------------------------+
bool TG_IsDuplicateSignal(ulong signalHash)
  {
   return(signalHash == g_tradeGovernor.lastSignalHash && g_tradeGovernor.lastSignalHash != 0);
  }

//+------------------------------------------------------------------+
//| Check if cooldown period is still active                          |
//+------------------------------------------------------------------+
bool TG_IsCooldownActive(int cooldownSeconds)
  {
   if(g_tradeGovernor.lastTradeTime == 0)
      return false;  // No trade yet, no cooldown
   return((TimeCurrent() - g_tradeGovernor.lastTradeTime) < cooldownSeconds);
  }

//+------------------------------------------------------------------+
 //| Register a trade (update governor state)                          |
 //+------------------------------------------------------------------+
 void TG_RegisterTrade(ulong signalHash)
    {
     g_tradeGovernor.lastTradeTime = TimeCurrent();
     g_tradeGovernor.lastSignalHash = signalHash;
     TG_AddSignalToHistory(signalHash);
    }

 //+------------------------------------------------------------------+
 //| GV_SyncLoss — Sync daily loss to Global Variable (Persistence)    |
 //| Called on every DEAL_ENTRY_OUT (position close) to persist state  |
 //+------------------------------------------------------------------+
void GV_SyncLoss()
{
   SyncGovernorToGlobal(g_tradeGovernor.dailyLoss);
}

 //+------------------------------------------------------------------+
 //| SyncGovernorToGlobal — Sync entire governor state to GV           |
 //| Called during Hard Kill to persist final state                    |
 //+------------------------------------------------------------------+
void SyncGovernorToGlobal()
{
   // Forward to parameterized version with current daily loss
   SyncGovernorToGlobal(g_tradeGovernor.dailyLoss);
}

//+------------------------------------------------------------------+
//| SyncGovernorToGlobal(double loss) — Persist loss + date + logging |
//+------------------------------------------------------------------+
void SyncGovernorToGlobal(double loss)
{
   string name = GetGvLossName();
   if(GlobalVariableSet(name, loss))
   {
      LogInfo("[GOV] Synced daily loss to GV: " + DoubleToString(loss, 2));
   }
   else
   {
      LogInfo("[GOV] ERROR: Failed to set GV for daily loss sync");
   }
   // Also persist current trading date (broker session)
   string dateName = GetGvDateName();
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int dateInt = now.year*10000 + now.mon*100 + now.day;
   GlobalVariableSet(dateName, (double)dateInt);
   // Synchronize the daily reset tracker to avoid wiping restored state on first tick
   g_lastResetDay = (datetime)now.day;
}

//+------------------------------------------------------------------+
//| GV_LoadLoss — Load daily loss from Global Variable on Init       |
 //| Called in OnInit to restore state after terminal restart          |
 //+------------------------------------------------------------------+
void GV_LoadLoss()
{
   string lossName = GetGvLossName();
   string dateName = GetGvDateName();

   // Compute current broker date as integer YYYYMMDD
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int currentDateInt = now.year*10000 + now.mon*100 + now.day;

   bool valid = false;
   double storedLoss = 0.0;

   // Check if both date and loss GVs exist and date matches today
   if(GlobalVariableCheck(dateName))
   {
      double storedDateVal = GlobalVariableGet(dateName);
      int storedDateInt = (int)storedDateVal;
      if(storedDateInt == currentDateInt)
      {
         // Date matches, now check loss
         if(GlobalVariableCheck(lossName))
         {
            storedLoss = GlobalVariableGet(lossName);
            if(storedLoss >= 0.0 && storedLoss <= 100.0)
            {
               g_tradeGovernor.dailyLoss = storedLoss;
               LogInfo("[GOV] Global State Recovered: Daily Loss = " + DoubleToString(storedLoss, 2) + "% for today");
               valid = true;
            }
            else
            {
               LogInfo("[GOV] Invalid GV loss value - Reset daily loss to 0.0");
            }
         }
         else
         {
            LogInfo("[GOV] Loss GV missing for today - Reset daily loss to 0.0");
         }
      }
      else
      {
         LogInfo("[GOV] Stored date mismatch: stored=" + IntegerToString(storedDateInt) + " current=" + IntegerToString(currentDateInt) + " - Reset daily loss");
      }
   }
   else
   {
      LogInfo("[GOV] No date GV found - Starting fresh daily session");
   }

   if(!valid)
   {
      g_tradeGovernor.dailyLoss = 0.0;
      // Write today's date GV to mark initialization
      GlobalVariableSet(dateName, (double)currentDateInt);
   }
   // In all cases, update the daily reset tracker to prevent immediate reset by OnTick
   g_lastResetDay = (datetime)now.day;
}

 //+------------------------------------------------------------------+
 //| TG_RecordDailyLoss — Record loss and persist to GV               |
 //| Called on position close to update daily loss                     |
 //+------------------------------------------------------------------+
 void TG_RecordDailyLoss(double profit)
    {
     if(profit < 0.0)
       {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        if(balance > 0.0)
          {
           double lossPercent = MathAbs(profit) / balance * 100.0;
           g_tradeGovernor.dailyLoss += lossPercent;
           
           // Update consecutive losses counter
           g_tradeGovernor.consecutiveLosses++;
           
           // Sync to GV for persistence
           GV_SyncLoss();
          }
       }
     else
       {
        // Reset consecutive losses on profitable trade
        g_tradeGovernor.consecutiveLosses = 0;
       }
    }
#endif // OMAK_TRADEGOVERNOR_MQH
