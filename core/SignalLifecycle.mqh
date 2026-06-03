//+------------------------------------------------------------------+
//|                                           SignalLifecycle.mqh   |
//|                           Omak FxYO — Signal Lifecycle Engine    |
//|                                                                  |
//| FSM State Machine: Every signal tracks its stage from           |
//| STAGE_LOCKED → STAGE_WAITING_FOR_POI → STAGE_READY →           |
//| STAGE_EXECUTED/STAGE_EXPIRED.                                   |
//|                                                                  |
//| This module is wired to SLockedSignal.stage field.              |
//+------------------------------------------------------------------+
#ifndef OMAK_SIGNAL_LIFECYCLE_MQH
#define OMAK_SIGNAL_LIFECYCLE_MQH

// Note: ENUM_SIGNAL_STAGE is defined in CoreTypes.mqh
// (STAGE_NONE, STAGE_LOCKED, STAGE_WAITING_FOR_POI,
//  STAGE_READY, STAGE_EXECUTED, STAGE_EXPIRED)
// This file uses the same enum values.

//+------------------------------------------------------------------+
 //| ENUM_SIGNAL_TERMINUS — Terminal States (for kill-switch logging) |
 //+------------------------------------------------------------------+
 enum ENUM_SIGNAL_TERMINUS
 {
     SIGNAL_TERM_UNKNOWN = 0,
     SIGNAL_TERM_EXECUTED,
     SIGNAL_TERM_BLOCKED_MODE,
     SIGNAL_TERM_BLOCKED_STRUCTURE,
     SIGNAL_TERM_BLOCKED_BE_A,
     SIGNAL_TERM_BLOCKED_BE_B,
     SIGNAL_TERM_BLOCKED_GUARD,
     SIGNAL_TERM_BLOCKED_BIAS,
     SIGNAL_TERM_BLOCKED_VOLUME,
     SIGNAL_TERM_EXEC_FAILED,
     SIGNAL_TERM_DROPPED,
     TERM_CRITICAL_DRAWDOWN,
     SIGNAL_TERM_POI_EXPIRED_BUY,
     SIGNAL_TERM_POI_EXPIRED_SELL
 };

//+------------------------------------------------------------------+
//| SL_StageToString — Convert stage enum to readable string        |
//+------------------------------------------------------------------+
string SL_StageToString(ENUM_SIGNAL_STAGE stage)
{
    switch(stage)
    {
        case STAGE_NONE:                return "NONE";
        case STAGE_LOCKED:              return "LOCKED";
        case STAGE_AWAITING_C2_CLOSURE: return "AWAITING_C2";
        case STAGE_AWAITING_C3_CLOSURE: return "AWAITING_C3";
        case STAGE_WAITING_FOR_POI:    return "WAITING_FOR_POI";
        case STAGE_WAITING_FOR_CISD:   return "WAITING_FOR_CISD";
        case STAGE_READY:              return "READY";
        case STAGE_EXECUTED:           return "EXECUTED";
        case STAGE_EXPIRED:            return "EXPIRED";
        default:                     return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| SL_TerminateSignal — Mark signal as terminated with logging    |
//+------------------------------------------------------------------+
void SL_TerminateSignal(ulong sigId, ENUM_SIGNAL_TERMINUS term, string reason, ulong ticket = 0)
{
    string termStr = "";
    switch(term)
    {
        case SIGNAL_TERM_EXECUTED:          termStr = "EXECUTED";          break;
        case SIGNAL_TERM_BLOCKED_MODE:      termStr = "BLOCKED_MODE";      break;
        case SIGNAL_TERM_BLOCKED_STRUCTURE: termStr = "BLOCKED_STRUCTURE"; break;
        case SIGNAL_TERM_BLOCKED_BE_A:       termStr = "BLOCKED_BE_A";     break;
        case SIGNAL_TERM_BLOCKED_BE_B:       termStr = "BLOCKED_BE_B";     break;
        case SIGNAL_TERM_BLOCKED_GUARD:      termStr = "BLOCKED_GUARD";    break;
        case SIGNAL_TERM_BLOCKED_BIAS:       termStr = "BLOCKED_BIAS";     break;
        case SIGNAL_TERM_BLOCKED_VOLUME:    termStr = "BLOCKED_VOLUME";   break;
        case SIGNAL_TERM_EXEC_FAILED:        termStr = "EXEC_FAILED";      break;
        case SIGNAL_TERM_DROPPED:            termStr = "DROPPED";          break;
        case TERM_CRITICAL_DRAWDOWN:          termStr = "CRITICAL_DRAWDOWN"; break;
        case SIGNAL_TERM_POI_EXPIRED_BUY:     termStr = "POI_EXPIRED_BUY";  break;
        case SIGNAL_TERM_POI_EXPIRED_SELL:   termStr = "POI_EXPIRED_SELL"; break;
        default:                              termStr = "UNKNOWN";          break;
    }

    string msg = "[SL_TERMINATE] GUID:" + IntegerToString(sigId) +
                 " | Terminus:" + termStr +
                 " | Reason:" + reason;
    if(ticket > 0)
        msg += " | Ticket:" + IntegerToString(ticket);

    LogPrint(msg, LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| SL_LogStageChange — Log signal stage change (deduplicated)      |
//+------------------------------------------------------------------+
void SL_LogStageChange(ulong sigId, ENUM_SIGNAL_STAGE stage, string result, string details = "")
{
    static ulong s_lastSigId = 0;
    static ENUM_SIGNAL_STAGE s_lastStage = STAGE_NONE;
    static datetime s_lastLogTime = 0;

    if(sigId == s_lastSigId && stage == s_lastStage)
        return;

    datetime now = TimeCurrent();
    if(now - s_lastLogTime < 2 && sigId == s_lastSigId)
        return;

    s_lastSigId = sigId;
    s_lastStage = stage;
    s_lastLogTime = now;

    string stageStr = SL_StageToString(stage);
    string msg = "[SL_STAGE] GUID:" + IntegerToString(sigId) +
                 " | Stage:" + stageStr +
                 " | Result:" + result;
    if(details != "")
        msg += " | " + details;

    LogPrint(msg, LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| SL_LogCurrentSignal — Debug: print full signal state             |
//+------------------------------------------------------------------+
void SL_LogCurrentSignal(const SLockedSignal &sig)
{
    string msg = "[SL_STATE] GUID:" + IntegerToString(sig.m_guid) +
                 " | Stage:" + SL_StageToString(sig.stage) +
                 " | Dir:" + EnumToString(sig.direction) +
                 " | Closure:" + EnumToString(sig.closureType) +
                 " | Attempts:" + IntegerToString(sig.retraceAttempts) +
                 " | EQ:" + DoubleToString(sig.equilibrium, _Digits) +
                 " | LockTime:" + TimeToString(sig.lockTime);
LogPrint(msg, LOG_LEVEL_INFO);
 }

 //+------------------------------------------------------------------+
 //| Buffered Structural Watchdog — Price-Based POI Invalidation           |
 //| Replaces 3-bar temporal limit with spread-aware price check          |
 //+------------------------------------------------------------------+
 /**
  * CheckStructuralInvalidation
  *
  * Monitors signals in STAGE_WAITING_FOR_POI and terminates them
  * if price violates the structural boundary with a spread buffer.
  *
  * BUY: expires if BID < (c2_low - buffer)
  * SELL: expires if ASK > (c2_high + buffer)
  *
  * @param signal - The locked signal to check
  * @param bufferPoints - Invalidation buffer in points (default from spread * 2)
  * @return true if signal was invalidated, false otherwise
  */
 bool CheckStructuralInvalidation(SLockedSignal &signal, int bufferPoints = 0)
 {
    if(signal.stage != STAGE_WAITING_FOR_POI)
        return false;

    if(signal.m_guid == 0)
        return false;
    
    if(signal.c2_low <= 0.0 || signal.c2_high <= 0.0)
        return false;

    SSymbolProfile spSL = SY_GetProfile(_Symbol);
    double point = spSL.point > 0.0 ? spSL.point : SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = spSL.digits > 0 ? spSL.digits : (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    int spread = (int)spSL.spread;
    if(spread <= 0) spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    int effectiveBuffer = bufferPoints;
    
    if(effectiveBuffer <= 0)
       effectiveBuffer = spread * 2;
    
    if(effectiveBuffer <= 0)
       effectiveBuffer = 20;
    
    double bufferPrice = point * effectiveBuffer;

    double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bidPrice = NormalizeDouble(currentBid, digits);
    double askPrice = NormalizeDouble(currentAsk, digits);

    bool invalidated = false;
    ENUM_SIGNAL_TERMINUS termType = SIGNAL_TERM_UNKNOWN;
    string reason = "";
    double limitLevel = 0.0;
    double currentPrice = 0.0;

    if(signal.direction == DIRECTION_BUY)
    {
       limitLevel = signal.c2_low - bufferPrice;
       currentPrice = bidPrice;
       
       if(bidPrice < limitLevel)
       {
          invalidated = true;
          termType = SIGNAL_TERM_POI_EXPIRED_BUY;
          reason = "BID_BELOW_C2_LOW";
       }
    }
    else if(signal.direction == DIRECTION_SELL)
    {
       limitLevel = signal.c2_high + bufferPrice;
       currentPrice = askPrice;
       
       if(askPrice > limitLevel)
       {
          invalidated = true;
          termType = SIGNAL_TERM_POI_EXPIRED_SELL;
          reason = "ASK_ABOVE_C2_HIGH";
       }
    }

if(invalidated)
    {
          LogPrint("[PIPELINE_KILL] GUID:" + IntegerToString(signal.m_guid) +
                " | Reason:" + reason +
                " | Price:" + DoubleToString(currentPrice, digits) +
                " | Limit:" + DoubleToString(limitLevel, digits) +
                " | Buffer:" + IntegerToString(effectiveBuffer) + "pts",
                LOG_LEVEL_INFO);
          
          signal.TransitionStage(STAGE_EXPIRED);
          SL_TerminateSignal(signal.m_guid, termType, reason, 0);
          // REMOVED: signal.Reset() — would create ghost state by immediately
          // overwriting STAGE_EXPIRED with STAGE_NONE via Reset() -> TransitionStage(STAGE_NONE).
          // The signal is now at its terminal lifecycle stage. Cleanup is the caller's responsibility.
         
         return true;
      }

    return false;
 }

 //+------------------------------------------------------------------+
 //| ProcessTickInvalidation — Call on every tick for POI signals     |
//+------------------------------------------------------------------+
  void ProcessTickInvalidation(SLockedSignal &signal, int bufferPoints = 0)
  {
     CheckStructuralInvalidation(signal, bufferPoints);
  }

  
//+------------------------------------------------------------------+
//| SL_CheckNarrativeContinuationValid — Validate continuation       |
//| window is still alive for a signal (especially C4 from deferred |
//| C2). Returns true if the narrative continuation window remains  |
//| valid, false if it has expired.                                  |
//|                                                                  |
//| Continuation is NARRATIVE STATE, not candle-count rule.          |
//| A deferred C2 continuation remains valid as long as the          |
//| narrative window is open or deferred, regardless of bar count.   |
//+------------------------------------------------------------------+
bool SL_CheckNarrativeContinuationValid(
   bool isActiveNarrative,
   bool isWindowOpenOrDeferred
)
{
   // If the narrative is inactive, continuation is dead
   if(!isActiveNarrative)
      return false;
   
   // If the window is open or deferred, continuation is still valid
   if(isWindowOpenOrDeferred)
      return true;
   
   // Window closed and no deferred state — continuation expired
   return false;
}

//+------------------------------------------------------------------+
//| SL_CheckDeferredContinuationTTL — Check if a deferred            |
//| continuation candidate's TTL has expired.                         |
//|                                                                  |
//| Deferred C2 candidates wait for price to return to POI.          |
//| Unlike the structural invalidation (price-based), this checks    |
//| the deferred window's temporal health: if the narrative has      |
//| moved past its deferred window or the window was closed without  |
//| continuation, the TTL has expired.                               |
//|                                                                  |
//| NOTE: This is NOT a hard bar limit — it checks narrative state.  |
//| Continuation is narrative state, not a candle-count rule.        |
//+------------------------------------------------------------------+
bool SL_CheckDeferredContinuationTTL(
   bool isWindowOpenOrDeferred,
   bool narrativeActive
)
{
   // Deferred continuation is alive if:
   // 1) The narrative is still active, AND
   // 2) The window is still open or has a deferred C2 candidate
   if(!narrativeActive)
      return false;  // Narrative died — continuation expired
   
   if(!isWindowOpenOrDeferred)
      return false;  // Window closed without deferred — continuation expired
   
   return true;  // Continuation still valid
}

//+------------------------------------------------------------------+
//| SL_IsDeferredContinuationSignal — Check if a signal originated  |
//| from a deferred continuation path.                               |
//|                                                                  |
//| Deferred continuation signals (e.g., C4 from deferred C2) have  |
//| extended lifecycle tolerance. They should not be prematurely     |
//| killed by TTL logic meant for active (non-deferred) signals.     |
//+------------------------------------------------------------------+
bool SL_IsDeferredContinuationSignal(
   ulong signalGuid,
   bool deferredC2Active
)
{
   // A signal is a deferred continuation signal if:
   // - There's an active deferred C2 candidate in the narrative
   // - The signal itself originated from that deferred state
   if(signalGuid == 0)
      return false;
   
   return deferredC2Active;
}

#endif // OMAK_SIGNAL_LIFECYCLE_MQH