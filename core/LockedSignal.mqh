//+------------------------------------------------------------------+
//|                                              LockedSignal.mqh |
//|                                    OmakFxYO — Locked Signal Definition |
//+------------------------------------------------------------------+
#ifndef OMAK_LOCKEDSIGNAL_MQH
#define OMAK_LOCKEDSIGNAL_MQH

// NOTE: CoreTypes.mqh includes this file - do NOT include CoreTypes.mqh here
// SLineage, ENUM_SIGNAL_STAGE, SRiskProfile are already defined in CoreTypes.mqh before this include
// Forward declaration for SClosureSignal (defined after SLockedSignal in CoreTypes.mqh)
struct SClosureSignal;
#include <OmakFxYO/core/LogGovernor.mqh>

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Locked signal definition for OmakFxYO"

//+------------------------------------------------------------------+
//| CONSTITUTIONAL GUID LIMITS                                        |
//+------------------------------------------------------------------+
#define GUID_SENTINEL_MIN  4000000000
#define MAX_RETIRED_GUIDS  2048

// GUID re-use prevention: shared retired-GUID tracker (singleton at module scope)
static ulong g_retiredGUIDs[MAX_RETIRED_GUIDS];
static int g_retiredGUIDCount = 0;

void RetireGUID(ulong guid)
{
    if(guid == 0 || guid >= GUID_SENTINEL_MIN) return;
    for(int i = 0; i < g_retiredGUIDCount; i++)
    {
        if(g_retiredGUIDs[i] == guid) return; // already retired
    }
    if(g_retiredGUIDCount < MAX_RETIRED_GUIDS)
    {
        g_retiredGUIDs[g_retiredGUIDCount] = guid;
        g_retiredGUIDCount++;
    }
}

bool IsRetiredGUID(ulong guid)
{
    if(guid == 0) return true;
    for(int i = 0; i < g_retiredGUIDCount; i++)
    {
        if(g_retiredGUIDs[i] == guid) return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| PERSISTENT SIGNAL LOCK — State Machine across ticks              |
//+------------------------------------------------------------------+
struct SLockedSignal
{
      ENUM_SIGNAL_STAGE stage;    // FSM state — replaces isLocked
      ulong m_guid;              // Global unique identifier — SOLELY owned by LockedSignal. Assigned once at Lock.
      ENUM_EXECUTION_BRANCH branchId; // Branch ID (A or B) that generated this signal
ENUM_HANDOVER_STATE handoverState;  // Handover ownership state machine
       datetime handoverAcquiredTime; // Timestamp when handover was acquired (for timeout expiry)
       int handoverOwnerId;           // Subsystem that owns the handover (HANDOVER_OWNER_*)
       int illegalTransitionCount;  // Counts illegal stage transitions for ghost signal force-clear

       int retraceAttempts;        // Tracks C4 gate retries
       datetime lastAttemptTime;   // Last C4 gate attempt timestamp
 
      // C1 values
      double c1_high;
      double c1_low;
      double c1_close;
 
      // C2 values
      double c2_high;
      double c2_low;
      double c2_open;
      double c2_close;
      int c2_barIndex;
 
      // C3 values
      double c3_high;
      double c3_low;
      double c3_open;
      double c3_close;
 
      // Entry and direction
      double entry_price;
      double stop_loss;
      ENUM_DIRECTION direction;
      ENUM_CLOSURE_TYPE closureType; // C2 or C3
 
       // Timestamps
       datetime m_detectionTime; // Seeded when closure passes all filters (TTL anchor)
       datetime lockTime;
        datetime commitTime;      // FIX 1: When signal was committed (validated + ready)
        datetime stageEntryTime;  // REGRESSION_GUARD_C3_EXPIRY: When signal entered current stage (for stage-specific expiry)
        int poiWaitBarStart;      // Bar count when entered STAGE_WAITING_FOR_POI (for timeout)
   
    // Commitment flag
      bool isCommitted;           // FIX 1: TRUE after all validations passed
      bool isStored;              // FIX 3: TRUE after successfully bridged to global store
  
       // Risk metrics (calculated at lock time)
       double rr;  // Risk-reward ratio calculated once at signal lock
  
// Execution retry control
     int executionAttempts;        // Tracks execution retry attempts per signal
     datetime lastExecutionAttempt; // Last execution attempt timestamp
      bool retryCapReached;         // TRUE when MAX_EXECUTION_RETRIES exceeded
      int executionRetryCount;      // Persistent scan retry count (separate from executionAttempts)
      
// Per-signal log rate limiting
      datetime lastLogTime;         // Last time ANY log was written for this signal
      string lastLogMarker;          // Last marker written
      int logRepeatCount;          // How many times the same marker was repeated
      
      // Tick counter for safety valve against infinite loops
      int tickCount;                // Incremented every OnTick while locked
      int resolveLockedCount;      // Tracks STAGE_WAITING_FOR_POI ticks
      int maxTickCount;            // Safety valve (default 10000 ticks max)
     
     // Equilibrium (50% of C1 range) - TTrades POI
      double equilibrium;

// Execution mode stored at lock time (signal-bound)
       int executionMode;
       
// Anticipation flag: true for C2 Closure signals, false for C3 Closure
        bool isAnticipation;
       
       // Continuation lineage for signal chaining
       SLineage continuationLineage;
       
       // Risk profile (computed at execution time)
      SRiskProfile riskProfile;
      
      // Promotion lineage: if C2 promoted to C3 (or C3 to C4), stores prior sequence ID
      ulong promoteFromSequenceId;
      
      // Current closure stage in lifecycle
      ENUM_CLOSURE_TYPE originalClosureType;  // The type when signal was first created

// HTF T-Spot (structure-derived POI zone)
       double htfTSpotHigh;
       double htfTSpotLow;
       double htfTSpotMid;

      // T-Spot Zone for C3 POI mapping (HTF-derived zone boundaries)
      double tSpotMin;              // Zone lower bound (HTF Low for bullish, Equilibrium for bearish)
      double tSpotMax;              // Zone upper bound (Equilibrium for bullish, HTF High for bearish)
       
       // LTF Entry Zone (execution-derived tighter zone for C3)
       double ltfEntryHigh;
       double ltfEntryLow;
       double ltfEntryMid;

       // HTF CISD range for projection-based TP calculation
       double htfCISDRange;

       // RecalculateSignalForC3 fields
       string symbol;          // Trading symbol
       ENUM_EXECUTION_BRANCH branch; // Branch (used by RecalculateSignalForC3)
       double poi;             // Point of interest / POI price
       double sl;              // Stop loss
       double tp;             // Take profit

// POI caching (FIX 3: Per-bar cache to reduce log spam)
        datetime lastPOICalcTime;
        double lastPOIATR;
        double cachedBufferPrice;
        double cachedTSpotWidth;
        bool poiWarningLogged;

//+------------------------------------------------------------------+
//| P10 Fix: RG pass flag - prevents duplicate RG_GATE_PASS logs for same signal
//+------------------------------------------------------------------+
       bool passedRG;

// REGRESSION_GUARD_V52.5_SLOT_SYNC: Track reason for slot clearance
      ENUM_SIGNAL_STAGE slotClearedFor;  // STAGE_NONE = not cleared, other = cleared for this stage

// STAGE_READY protection fields
      bool hasFailedRG;          // TRUE when RG gate has failed (allows Reset)
      bool isStructurallyInvalid;  // TRUE when signal becomes structurally invalid (allows Reset)

        // Bias captured at lock time - used at commit to avoid stale global bias (stored as int: 0=NEUTRAL, 1=BULLISH, 2=BEARISH)
        int m_biasAtLock;

         // === SIGNAL CONTRACT FIELDS (Signal Contract Reconstruction) ===
         int structuralBias;           // BiasType: BIAS_BULLISH/BIAS_BEARISH/BIAS_NEUTRAL captured at lock
         int continuationState;        // 0=CONTINUATION_NONE, 1=CONTINUATION_ACTIVE, 2=CONTINUATION_EXPIRED
         int invalidationState;        // 0=INVALID_NONE, 1=INVALID_VALID, 2=INVALID_INVALIDATED

         // === EXECUTION TRUTH FIELDS (Execution Truth Separation) ===
         double candidateEntryPrice;   // Original entry price from signal detection (c4_open at Lock time)
         double requestedEntryPrice;   // Price sent to broker via OrderSend (0 until requested)
         double actualFillPrice;       // Fill price from broker/DEAL_PRICE (0 until filled)
         datetime fillTime;            // When the fill was confirmed
         int fillStatus;               // 0=FILL_NONE, 1=FILL_REQUESTED, 2=FILL_PARTIAL, 3=FILL_COMPLETE

         // === SETUP-LEVEL METADATA (shared by C2, C3, C4 within the same setup) ===
        datetime m_setupStartTime;          // bar time of C1 (start of setup)
        datetime m_setupHtfCandleStart;     // start time of the HTF candle containing C1
        double   m_setupInitialHigh;        // the "initial high" from C1
        double   m_setupInitialLow;         // the "initial low" from C1
        bool     m_setupIsBullish;          // direction of the setup

        // === C2-SPECIFIC METADATA ===
        datetime m_c2CommitBarTime;         // execution TF bar time when C2 Closure was committed
        bool     m_c2HadSmallWick;          // true if this C2 passed the wick size filter
        bool     m_c2ClosureConfirmed;      // true if C2 produced a reversal closure

// === C3-SPECIFIC METADATA ===
      datetime m_c3CommitBarTime;         // execution TF bar time when C3 Closure was committed
      ulong    m_c3ParentC2Guid;          // parent C2 signal GUID (for modal upgrade lineage)
      bool     m_upgradedFromC2;          // true if this C3 was upgraded from C2 (not standalone C3)
      bool     m_c3CisdConfirmed;         // true if CISD confirmed on LTF before C3 execution
      double   m_c3EntryHigh;            // C3 range high (for equilibrium calculation)
      double   m_c3EntryLow;             // C3 range low (for equilibrium calculation)
      double   m_c3Equilibrium;          // C3 50% equilibrium level

        //+------------------------------------------------------------------+
         //| HANDOVER LIFECYCLE — Ownership State Machine                    |
         //+------------------------------------------------------------------+
         bool IsHandoverActive()
         {
             return (handoverState == HANDOVER_ACQUIRED ||
                     handoverState == HANDOVER_TRANSFERRED);
         }

         bool AcquireHandover(int ownerId)
         {
             if(handoverState != HANDOVER_NONE && handoverState != HANDOVER_RELEASED)
             {
                 LogPrint("[HANDOVER_ACQUIRE_BLOCKED] state=" + IntegerToString(handoverState) +
                          " | ownerId=" + IntegerToString(ownerId) +
                          " | existingOwner=" + IntegerToString(handoverOwnerId), LOG_LEVEL_WARN);
                 return false;
             }
             handoverState = HANDOVER_ACQUIRED;
             handoverAcquiredTime = TimeCurrent();
             handoverOwnerId = ownerId;
             LogPrint("[HANDOVER_ACQUIRED] ownerId=" + IntegerToString(ownerId) +
                      " | GUID=" + IntegerToString(m_guid), LOG_LEVEL_INFO);
             return true;
         }

         bool TransferHandover(int newOwnerId)
         {
             if(handoverState != HANDOVER_ACQUIRED)
             {
                 LogPrint("[HANDOVER_TRANSFER_BLOCKED] state=" + IntegerToString(handoverState) +
                          " | fromOwner=" + IntegerToString(handoverOwnerId) +
                          " | toOwner=" + IntegerToString(newOwnerId), LOG_LEVEL_WARN);
                 return false;
             }
             int oldOwner = handoverOwnerId;
             handoverState = HANDOVER_TRANSFERRED;
             handoverOwnerId = newOwnerId;
             LogPrint("[HANDOVER_TRANSFERRED] fromOwner=" + IntegerToString(oldOwner) +
                      " | toOwner=" + IntegerToString(newOwnerId) +
                      " | GUID=" + IntegerToString(m_guid), LOG_LEVEL_INFO);
             return true;
         }

         bool ReleaseHandover()
         {
             if(handoverState == HANDOVER_NONE || handoverState == HANDOVER_RELEASED)
                 return false;
             int owner = handoverOwnerId;
             handoverState = HANDOVER_RELEASED;
             handoverAcquiredTime = 0;
             LogPrint("[HANDOVER_RELEASED] ownerId=" + IntegerToString(owner) +
                      " | GUID=" + IntegerToString(m_guid), LOG_LEVEL_INFO);
             return true;
         }

         bool ForceReleaseHandover(string reason)
         {
             if(handoverState == HANDOVER_NONE || handoverState == HANDOVER_RELEASED)
                 return false;
             int owner = handoverOwnerId;
             ENUM_HANDOVER_STATE oldState = handoverState;
             handoverState = HANDOVER_FORCED_RELEASE;
             handoverAcquiredTime = 0;
             LogPrint("[HANDOVER_FORCED_RELEASE] oldState=" + IntegerToString(oldState) +
                      " | ownerId=" + IntegerToString(owner) +
                      " | reason=" + reason +
                      " | GUID=" + IntegerToString(m_guid), LOG_LEVEL_WARN);
             return true;
         }

         //+------------------------------------------------------------------+
         //| SOLE GUID AUTHORITY — Monotonic generation, collision-free      |
         //+------------------------------------------------------------------+
         static ulong GenerateSignalGUID()
         {
             static ulong s_guidCounter = 0;
             s_guidCounter++;
             return ((ulong)TimeCurrent() * 1000000) + (s_guidCounter % 1000000);
         }

         static bool IsRetiredGUIDCheck(ulong guid) { return ::IsRetiredGUID(guid); }

        //+------------------------------------------------------------------+
         //| Reset — Reset signal to initial state                             |
         //+------------------------------------------------------------------+
         void Reset()
         {
// Handover State Machine Guard:
                 //   HANDOVER_ACQUIRED / HANDOVER_TRANSFERRED → block Reset
                 //   HANDOVER_RELEASED / HANDOVER_NONE → allow Reset
                 //   HANDOVER_FORCED_RELEASE → allow Reset (cleanup after force)
                 // TIMEOUT: Auto-expire handover after 5 seconds to prevent ghost cascade
                 if(IsHandoverActive())
                 {
                     if(handoverAcquiredTime > 0 && TimeCurrent() - handoverAcquiredTime < 5)
                     {
                         LogPrint("[STATE_GHOST_BLOCKED] Reset blocked by active handover" +
                                  " | state=" + IntegerToString(handoverState) +
                                  " | owner=" + IntegerToString(handoverOwnerId) +
                                  " | GUID=" + IntegerToString(m_guid), LOG_LEVEL_WARN);
                         return;
                     }
                     if(handoverAcquiredTime > 0)
                     {
                         LogPrint("[HANDOVER_TIMEOUT] Releasing stuck handover after 5s" +
                                  " | state=" + IntegerToString(handoverState) +
                                  " | owner=" + IntegerToString(handoverOwnerId) +
                                  " | GUID=" + IntegerToString(m_guid), LOG_LEVEL_WARN);
                         ForceReleaseHandover("RESET_TIMEOUT");
                     }
                 }

// STAGE_READY Protection — Block Reset unless RG failed or structural invalid
                  if(stage == STAGE_READY)
                  {
                      if(!hasFailedRG && !isStructurallyInvalid)
                      {
                          LogPrint("[STAGE_READY_PROTECTED] Reset blocked on protected READY signal | GUID=" + IntegerToString(m_guid), LOG_LEVEL_WARN);
                          return;
                      }
                  }

                 // Retire GUID before clearing to prevent reuse
                if(m_guid != 0 && m_guid < GUID_SENTINEL_MIN)
                {
                    RetireGUID(m_guid);
                }

                // FIX A: Strong reset using ZeroMemory to prevent stage corruption
               // CRITICAL: Full zeroing to catch garbage values (stage=14, 148887992, etc.)
               ZeroMemory(this);
                    
            TransitionStage(STAGE_NONE);
                m_guid = 0;
                branchId = (ENUM_EXECUTION_BRANCH)-1;  // Invalid sentinel
handoverState = HANDOVER_NONE;
                handoverAcquiredTime = 0;
                handoverOwnerId = HANDOVER_OWNER_NONE;
                illegalTransitionCount = 0;
               retraceAttempts = 0;
              lastAttemptTime = 0;
     
            c1_high = 0.0;
            c1_low = 0.0;
            c1_close = 0.0;
 
            c2_high = 0.0;
            c2_low = 0.0;
            c2_open = 0.0;
            c2_close = 0.0;
            c2_barIndex = 0;
    
            c3_high = 0.0;
            c3_low = 0.0;
            c3_open = 0.0;
            c3_close = 0.0;
    
            entry_price = 0.0;
            stop_loss = 0.0;
            direction = DIRECTION_NONE;
            closureType = CLOSURE_NONE;
            executionMode = MODE_NONE;  // FIX A: Explicitly set to MODE_NONE, not 0
              isAnticipation = false;
    
    m_detectionTime = 0;
              lockTime = 0;
               commitTime = 0;
               stageEntryTime = 0;  // REGRESSION_GUARD_C3_EXPIRY
               isCommitted = false;
               isStored = false;
              rr = 0.0;
equilibrium = 0.0;
             promoteFromSequenceId = 0;
             originalClosureType = CLOSURE_NONE;
             
             // HTF T-Spot reset
             htfTSpotHigh = 0.0;
             htfTSpotLow = 0.0;
             htfTSpotMid = 0.0;
             
              // LTF Entry Zone reset
              ltfEntryHigh = 0.0;
              ltfEntryLow = 0.0;
              ltfEntryMid = 0.0;
              
// HTF CISD Range reset
               htfCISDRange = 0.0;

               // RecalculateSignalForC3 fields reset
               symbol = "";
               branch = BRANCH_INTRADAY;
               poi = 0.0;
               sl = 0.0;
               tp = 0.0;

// POI cache reset
                 lastPOICalcTime = 0;
                 lastPOIATR = 0.0;
                 cachedBufferPrice = 0.0;
                 cachedTSpotWidth = 0.0;
                 poiWarningLogged = false;
              executionAttempts = 0;
              hasFailedRG = false;
              isStructurallyInvalid = false;
             lastExecutionAttempt = 0;
              retryCapReached = false;
              executionRetryCount = 0;
              
              // Tick counter reset
             tickCount = 0;
             resolveLockedCount = 0;
             maxTickCount = 10000;
             
LogPrint("[STATE_CLEARED] GUID=" + IntegerToString(m_guid) +
                 " | stage=" + EnumToString(stage) +
                 " | closure=" + EnumToString(closureType), LOG_LEVEL_INFO);

                // Setup-level metadata reset
                m_setupStartTime = 0;
                m_setupHtfCandleStart = 0;
                m_setupInitialHigh = 0.0;
                m_setupInitialLow = 0.0;
                m_setupIsBullish = false;

                // C2-specific metadata reset
                m_c2CommitBarTime = 0;
                m_c2HadSmallWick = false;
                m_c2ClosureConfirmed = false;

                 // C3-specific metadata reset
                 m_c3CommitBarTime = 0;
                 m_c3ParentC2Guid = 0;
                 m_c3CisdConfirmed = false;
                 m_c3EntryHigh = 0.0;
                 m_c3EntryLow = 0.0;
                 m_c3Equilibrium = 0.0;

                 // Signal contract fields reset
                  structuralBias = 0;
                  continuationState = 0;
                  invalidationState = 1;  // INVALID_VALID by default for new signals

                 // Execution truth fields reset
                 candidateEntryPrice = 0.0;
                 requestedEntryPrice = 0.0;
                 actualFillPrice = 0.0;
                 fillTime = 0;
                 fillStatus = 0;  // FILL_NONE
          }
        
        //+------------------------------------------------------------------+
        //| ValidateAndFixStage — FIX D: Sanitize garbage stage values        |
        //+------------------------------------------------------------------+
        void ValidateAndFixStage()
        {
            // Valid range: STAGE_NONE(0) to STAGE_EXPIRED(8)
            if(stage < STAGE_NONE || stage > STAGE_EXPIRED)
            {
                LogPrint("[STAGE_FIX] GUID=" + IntegerToString(m_guid) + 
                         " | bad_stage=" + IntegerToString(stage) + " (range 0-8) → STAGE_NONE", LOG_LEVEL_WARN);
                if(m_guid != 0 && m_guid < GUID_SENTINEL_MIN)
                {
                    RetireGUID(m_guid);
                }
                stage = STAGE_NONE;
                m_guid = 0;
            }
        }
        
         // [SIGNAL_CONTRACT] Reset signal only if NOT yet committed (safe rollback)
           void ResetIfUncommitted()
           {
              if(!isCommitted)
              {
                 LogPrint("[RESET_UNCOMMITTED] GUID=" + IntegerToString(m_guid) +
                          " | stage=" + EnumToString(stage) +
                          " | closure=" + EnumToString(closureType) +
                          " | reason=uncommitted reset", LOG_LEVEL_DEBUG);
                 Reset();
              }
              else
              {
                 LogPrint("[RESET_UNCOMMITTED] SKIP — signal already committed | GUID=" + IntegerToString(m_guid), LOG_LEVEL_DEBUG);
              }
           }

         // [EXECUTION_TRUTH] Returns true if actual fill price has been captured and reconciled
           bool IsFillReconciled()
          {
             return (fillStatus == 3 && actualFillPrice > 0.0);
          }
 
         // [EXECUTION_TRUTH] Returns the best available entry price (fill > requested > candidate)
          double GetBestEntryPrice()
          {
             if(actualFillPrice > 0.0) return actualFillPrice;
             if(requestedEntryPrice > 0.0) return requestedEntryPrice;
             return candidateEntryPrice;
          }

// [SIGNAL_CONTRACT] Validate all required contract fields are populated
           bool IsContractComplete()
           {
              if(m_guid == 0) return false;
              if(executionMode == MODE_NONE) return false;
              if(closureType == CLOSURE_NONE) return false;
              if(direction == DIRECTION_NONE) return false;
              if(entry_price <= 0.0) return false;
              if(stop_loss <= 0.0) return false;
 if(branchId == (ENUM_EXECUTION_BRANCH)-1) return false;
               return true;
            }

ulong GetGUID() { return m_guid; }

// Lock declaration - implementation in CoreTypes.mqh after SClosureSignal definition
             bool Lock(SClosureSignal &signal, int id, ENUM_EXECUTION_BRANCH execBranch, ENUM_TIMEFRAMES tf = PERIOD_CURRENT);

// FIX 1: Check if signal expired (48 hour max)
           bool IsExpired() const
          {
               if(commitTime == 0)
                  return false;
               int elapsed = (int)(TimeCurrent() - commitTime);
               if(elapsed >= 48 * 3600)
               {
                   LogPrint("[SIGNAL_EXPIRED] GUID=" + IntegerToString(m_guid) +
                            " | reason=TIMEOUT | elapsed=" + IntegerToString(elapsed) +
                            " | max=" + IntegerToString(48 * 3600), LOG_LEVEL_WARN);
                   return true;
               }
               return false;
          }
         
         // Retry control helpers
         
// Check if max execution retries have been reached
          bool IsRetryCapReached()
          {
               // Max 3 attempts allowed (initial + 2 retries = 3 total)
               // Attempt count of 3 or more means cap is reached
               return (executionAttempts >= 3 || retryCapReached);
          }
         
// Increment execution attempt counter and record timestamp
           void IncrementExecutionAttempt()
           {
                executionAttempts++;
                lastExecutionAttempt = TimeCurrent();
                if(executionAttempts >= 3)
                {
                     retryCapReached = true;
                }
           }
         
// Get number of remaining attempts
           int GetRemainingAttempts()
           {
                int remaining = 3 - executionAttempts;  // 3 total allowed
                return (remaining < 0) ? 0 : remaining;
           }
        
           // Stage transition with legal map — blocks illegal transitions
           // REGRESSION_GUARD_V54_3_P0_2
           void TransitionStage(ENUM_SIGNAL_STAGE newStage)
           {
               if(stage == newStage)
                  return;

               // ========================================================
               // LEGAL TRANSITION MAP — every edge enumerated explicitly
               // ========================================================
               bool legal = false;
               string reason = "";

               switch(stage)
               {
                   case STAGE_NONE:
                       legal = (newStage == STAGE_LOCKED ||
                                newStage == STAGE_AWAITING_C3_CLOSURE);
                       if(!legal) reason = "NONE -> " + EnumToString(newStage) + " illegal; must go to LOCKED or AWAITING_C3_CLOSURE";
                       break;

                   case STAGE_LOCKED:
                       legal = (newStage == STAGE_WAITING_FOR_POI ||
                                newStage == STAGE_EXPIRED);
                       if(!legal) reason = "LOCKED -> " + EnumToString(newStage) + " illegal; must go to WAITING_FOR_POI or EXPIRED";
                       break;

                   case STAGE_AWAITING_C2_CLOSURE:
                       legal = (newStage == STAGE_WAITING_FOR_POI ||
                                newStage == STAGE_EXPIRED);
                       if(!legal) reason = "AWAITING_C2 -> " + EnumToString(newStage) + " illegal; must go to WAITING_FOR_POI or EXPIRED";
                       break;

                   case STAGE_AWAITING_C3_CLOSURE:
                       legal = (newStage == STAGE_WAITING_FOR_POI ||
                                newStage == STAGE_EXPIRED);
                       if(!legal) reason = "AWAITING_C3 -> " + EnumToString(newStage) + " illegal; must go to WAITING_FOR_POI or EXPIRED";
                       break;

                   case STAGE_WAITING_FOR_POI:
                       legal = (newStage == STAGE_READY ||
                                newStage == STAGE_EXPIRED ||
                                newStage == STAGE_AWAITING_C3_CLOSURE ||
                                newStage == STAGE_WAITING_FOR_CISD);
                       if(!legal) reason = "WAITING_FOR_POI -> " + EnumToString(newStage) + " illegal; must go to READY, EXPIRED, AWAITING_C3, or WAITING_FOR_CISD";
                       break;

                   case STAGE_WAITING_FOR_CISD:
                       legal = (newStage == STAGE_READY ||
                                newStage == STAGE_EXPIRED);
                       if(!legal) reason = "WAITING_FOR_CISD -> " + EnumToString(newStage) + " illegal; must go to READY or EXPIRED";
                       break;

                   case STAGE_READY:
                       legal = (newStage == STAGE_EXECUTED ||
                                newStage == STAGE_EXPIRED);
                       if(!legal) reason = "READY -> " + EnumToString(newStage) + " illegal; must go to EXECUTED or EXPIRED";
                       break;

                   case STAGE_EXECUTED:
                       legal = false;
                       reason = "EXECUTED -> " + EnumToString(newStage) + " illegal; terminal state";
                       break;

                   case STAGE_EXPIRED:
                       legal = false;
                       reason = "EXPIRED -> " + EnumToString(newStage) + " illegal; terminal state";
                       break;

                   default:
                       legal = false;
                       reason = "Unknown stage " + IntegerToString(stage) + " -> " + EnumToString(newStage) + " illegal";
                       break;
               }

               datetime now = TimeCurrent();
               int minutesInOldStage = (stageEntryTime > 0) ? (int)((now - stageEntryTime) / 60) : 0;

                if(!legal)
                {
                    illegalTransitionCount++;
                    LogPrint(StringFormat("[STATE_ILLEGAL] GUID=%I64u %s -> %s (spent %d min in %s, illegalCount=%d) | %s",
                             m_guid, EnumToString(stage), EnumToString(newStage),
                             minutesInOldStage, EnumToString(stage), illegalTransitionCount, reason),
                             LOG_LEVEL_ERROR);
                    return;
                }

               LogPrint(StringFormat("[STATE_TRANSITION_OK] GUID=%I64u %s -> %s (spent %d min in %s)",
                        m_guid, EnumToString(stage), EnumToString(newStage),
                        minutesInOldStage, EnumToString(stage)),
                        LOG_LEVEL_INFO);
               stage = newStage;
               stageEntryTime = now;
           }

         // FIX 1: Mark as executed
          void MarkExecuted()
          {
               TransitionStage(STAGE_EXECUTED);
               isCommitted = false;
               // Don't reset executionAttempts - keep for audit trail
          }
        
           void Invalidate(string reason)
           {
                 ulong invalidGuid = m_guid;
 if(InpEnableTrace)
                   LGovPrint("[STATE_TRANSITION_OK] LOCKED_SIGNAL -> invalidated | guid=" + IntegerToString(m_guid) +
                             " | reason=" + reason, LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
                   executionAttempts = 0;
                   lastExecutionAttempt = 0;
                   retryCapReached = false;
                   Reset();
                 // Retire GUID after Reset clears it (Reset already retires, but explicit log here)
                 if(invalidGuid != 0 && invalidGuid < GUID_SENTINEL_MIN)
                 {
                     LogPrint("[GUID_RESET] guid=" + IntegerToString(invalidGuid) +
                              " | reason=invalidate_" + reason, LOG_LEVEL_DEBUG);
                 }
           }

           bool Commit()
           {
                if(m_guid == 0)
                   return false;
                isCommitted = true;
                commitTime = TimeCurrent();
                return true;
           }
};

//+------------------------------------------------------------------+
//| FIX 1: Commit signal - mark as validated and ready for execution |
//+------------------------------------------------------------------+
void CommitSignal(SLockedSignal &lockedSignal)
{
     if(lockedSignal.m_guid == 0)
        return;
     
    lockedSignal.isCommitted = true;
     lockedSignal.commitTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Per-signal helper methods (module-level functions, not member functions) |
//+------------------------------------------------------------------+

// FIX 1: Check if signal expired (48 hour max)
bool SignalIsExpired(const SLockedSignal &sig)
{
   if(sig.commitTime == 0)
      return false;
   int elapsed = (int)(TimeCurrent() - sig.commitTime);
   if(elapsed >= 48 * 3600)
   {
      LogPrint("[SIGNAL_EXPIRED] GUID=" + IntegerToString(sig.m_guid) +
               " | reason=TIMEOUT | elapsed=" + IntegerToString(elapsed) +
               " | max=" + IntegerToString(48 * 3600), LOG_LEVEL_WARN);
      return true;
   }
   return false;
}

// Check if max execution retries have been reached
bool SignalIsRetryCapReached(const SLockedSignal &sig)
{
   return (sig.executionAttempts >= 3 || sig.retryCapReached);
}

// Increment execution attempt counter on a signal
void IncrementSignalExecutionAttempt(SLockedSignal &sig)
{
   sig.executionAttempts++;
   sig.lastExecutionAttempt = TimeCurrent();
   if(sig.executionAttempts >= 3)
   {
      sig.retryCapReached = true;
   }
}

// Get number of remaining attempts
int GetSignalRemainingAttempts(const SLockedSignal &sig)
{
   int remaining = 3 - sig.executionAttempts;  // 3 total allowed
   return (remaining < 0) ? 0 : remaining;
}

// Forward declaration for Lock implementation (defined after SClosureSignal in CoreTypes.mqh)
bool SLockedSignal_Lock(SClosureSignal &signal, int id, ENUM_EXECUTION_BRANCH execBranch, ENUM_TIMEFRAMES tf);

//+------------------------------------------------------------------+
//| LEGACY GenerateSignalGUID — Redirects to sole-authority static   |
//| method on SLockedSignal. External callers should use              |
//| SLockedSignal::GenerateSignalGUID() directly for clarity.         |
//| Kept as thin wrapper for backward compatibility.                  |
//+------------------------------------------------------------------+
ulong GenerateSignalGUID(SClosureSignal &signal, ENUM_EXECUTION_BRANCH branch, ENUM_TIMEFRAMES tf)
{
    return SLockedSignal::GenerateSignalGUID();
}

#endif // OMAK_LOCKEDSIGNAL_MQH

//+------------------------------------------------------------------+
//| Lock Implementation — MUST be included AFTER SClosureSignal is     |
//| defined. CoreTypes.mqh includes LockedSignal.mqh, then defines     |
//| SClosureSignal, then includes this file again as implementation.   |
//+------------------------------------------------------------------+
#ifndef OMAK_LOCKEDSIGNAL_IMPL_MQH
#define OMAK_LOCKEDSIGNAL_IMPL_MQH
// Lock implementation is moved to CoreTypes.mqh after SClosureSignal definition
#endif // OMAK_LOCKEDSIGNAL_IMPL_MQH
