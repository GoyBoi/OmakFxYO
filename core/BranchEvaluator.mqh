//+------------------------------------------------------------------+
//|                                        BranchEvaluator.mqh |
//|                        OmakFxYO — Branch Evaluator |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_BRANCHEVALUATOR_MQH
#define OMAK_BRANCHEVALUATOR_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Branch Evaluator — Independent Branch Pipeline Execution"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>           // Base types, ENUM_EXECUTION_BRANCH
#include <OmakFxYO/core/BranchRouter.mqh>        // Branch TF routing
#include <OmakFxYO/core/ClosureEngine.mqh>       // Closure signals
#include <OmakFxYO/core/StructuralStateEngine.mqh>    // P09-A
#include <OmakFxYO/core/LiquidityTierEngine.mqh>      // P09-B
#include <OmakFxYO/core/DisplacementValidator.mqh>    // P09-C
#include <OmakFxYO/core/BiasResolver.mqh>             // P09-D
#include <OmakFxYO/core/ModeResolver.mqh>             // P09-E
#include <OmakFxYO/core/LogGovernor.mqh>         // Log governance (NEW)
#include <OmakFxYO/core/SpreadFilter.mqh>        // DetectSymbolClass for ATR normalization
#include <OmakFxYO/core/UniversalConfig.mqh>    // Symbol-class volatility config
#include <OmakFxYO/core/SymbolClassVolatility.mqh> // Symbol-class ATR multipliers
#include <OmakFxYO/core/FractalNarrative.mqh>   // Fractal narrative (v52.5+)

//+------------------------------------------------------------------+
//| SCISDResult — CISD Detection Result                            |
//+------------------------------------------------------------------+
struct SCISDResult
{
   bool confirmed;
   datetime cisd_time;
   double cisd_close;
   double creation_open;
   ENUM_DIRECTION direction;

   void Reset()
   {
      confirmed = false;
      cisd_time = 0;
      cisd_close = 0.0;
      creation_open = 0.0;
      direction = DIRECTION_NONE;
   }
};

//+------------------------------------------------------------------+
//| DetectLTFCISD — Detect LTF CISD within HTF candle window         |
//+------------------------------------------------------------------+
bool DetectLTFCISD(
    ENUM_TIMEFRAMES ltfPeriod,
    datetime htfCandleOpen,
    datetime htfCandleClose,
    ENUM_DIRECTION swingDirection,
    SCISDResult &result
)
{
   result.Reset();

   if(htfCandleOpen >= htfCandleClose || htfCandleOpen == 0)
      return false;

   string symbol = _Symbol;
   int maxBars = 20;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int copied = CopyRates(symbol, ltfPeriod, 0, maxBars, rates);
   if(copied < 2)
      return false;

   int creationIdx = -1;
   double creationPrice = 0.0;

   if(swingDirection == DIRECTION_SELL)
   {
      double highestHigh = -1.0;
      for(int i = 0; i < copied; i++)
      {
         if(rates[i].time >= htfCandleOpen && rates[i].time < htfCandleClose)
         {
            if(rates[i].high > highestHigh)
            {
               highestHigh = rates[i].high;
               creationIdx = i;
               creationPrice = rates[i].open;
            }
         }
      }

      if(creationIdx < 0)
         return false;

      for(int i = creationIdx + 1; i < copied; i++)
      {
         if(rates[i].time >= htfCandleOpen && rates[i].time < htfCandleClose)
         {
            if(rates[i].close < creationPrice)
            {
               result.confirmed = true;
               result.cisd_time = rates[i].time;
               result.cisd_close = rates[i].close;
               result.creation_open = creationPrice;
               result.direction = DIRECTION_SELL;
               return true;
            }
         }
      }
   }
   else if(swingDirection == DIRECTION_BUY)
   {
      double lowestLow = DBL_MAX;
      for(int i = 0; i < copied; i++)
      {
         if(rates[i].time >= htfCandleOpen && rates[i].time < htfCandleClose)
         {
            if(rates[i].low < lowestLow)
            {
               lowestLow = rates[i].low;
               creationIdx = i;
               creationPrice = rates[i].open;
            }
         }
      }

      if(creationIdx < 0)
         return false;

      for(int i = creationIdx + 1; i < copied; i++)
      {
         if(rates[i].time >= htfCandleOpen && rates[i].time < htfCandleClose)
         {
            if(rates[i].close > creationPrice)
            {
               result.confirmed = true;
               result.cisd_time = rates[i].time;
               result.cisd_close = rates[i].close;
               result.creation_open = creationPrice;
               result.direction = DIRECTION_BUY;
               return true;
            }
         }
      }
   }

   return false;
}

// SSetupState moved to ClosureEngine.mqh

// BranchContext moved to ClosureEngine.mqh

//+------------------------------------------------------------------+
//| BranchResult — Branch Evaluation Result                          |
//+------------------------------------------------------------------+
/**
 * BranchResult
 *
 * Contains final evaluation result for a branch.
 */
struct BranchResult
{
    bool isBranchActive;    // Pipeline survives (NOT dependent on displacement)
    bool hasSignalReady;    // Closure detected (Locking is permitted)
    bool valid;             // Legacy compatibility (Mapped to isBranchActive)
    bool displacementValid; // Displacement quality (FOR INFO, NOT A GATE)
    ENUM_DIRECTION direction;
    EntryMode mode;
    double confidence;
    string rationale;
    datetime timestamp;

    void Reset()
    {
        isBranchActive = false;
        hasSignalReady = false;
        valid = false;
        displacementValid = false;
        direction = DIRECTION_NONE;
        mode = MODE_NONE;
        confidence = 0.0;
        rationale = "";
        timestamp = 0;
    }
};

//+------------------------------------------------------------------+
 //| ResetBranchContext — Clear signals but preserve upgrade state |
 //+------------------------------------------------------------------+
 void ResetBranchContext(BranchContext &ctx)
 {
     // FIX B: Invalidate from store before clearing context
     ulong oldGuid = ctx.branchLockedSignal.m_guid;
     
     LogPrint("[RESET_CTX] Clearing branch signal state | branch=" + IntegerToString(ctx.branch), LOG_LEVEL_DEBUG);

     if(oldGuid != 0)
     {
        LogPrint("[RESET_CTX] GUID cleared: " + IntegerToString(oldGuid), LOG_LEVEL_DEBUG);
        // FIX B: Full cleanup across store + context
        SQ_InvalidateSignal(oldGuid, ctx.branch);
     }

     ctx.branchLockedSignal.Reset();
     ctx.branchLockedSignal.TransitionStage(STAGE_NONE);
     ctx.branchLockedSignal.m_guid = 0;  // Explicit GUID clear - prevent stale references

     SC2StateReset(ctx.c2State);
     SC3StateReset(ctx.c3State);

    ctx.mode.hasClosure = false;
    ctx.mode.mode = MODE_NONE;
    ctx.cachedMode = MODE_NONE;

    ctx.lastProcessedSignalId = 0;
    ctx.lastProcessedBarTime = 0;
}

//+------------------------------------------------------------------+
//| GLOBAL STATE — Branch Contexts (ISOLATED)                      |
//+------------------------------------------------------------------+
// CRITICAL: Each branch has its OWN context — NO sharing
BranchContext g_branchAContext;  // Branch A (Intraday: D1→H1→M5)
BranchContext g_branchBContext;  // Branch B (Swing: D1→H4→M15)
SBranchResolvedParams g_branchParams;  // Branch-resolved parameters

// g_activeBranch is now global in OmakFxYO.mq5

// Fractal narrative arrays (v52.5+)
SFractalNarrative g_branchANarratives[MAX_NARRATIVES_PER_BRANCH];
SFractalNarrative g_branchBNarratives[MAX_NARRATIVES_PER_BRANCH];

//+------------------------------------------------------------------+
//| HELPER — Get Branch Tag for Logging                              |
//+------------------------------------------------------------------+
string BE_GetBranchTag()
{
   return (g_activeBranch == BRANCH_INTRADAY) ? "[BRANCH=A]" : "[BRANCH=B]";
}

string BE_GetBranchTagEx(ENUM_EXECUTION_BRANCH branch)
{
   return (branch == BRANCH_INTRADAY) ? "[BRANCH=A]" : "[BRANCH=B]";
}

//+------------------------------------------------------------------+
//| CORE LOGIC — BRANCH PIPELINE EXECUTION                           |
//+------------------------------------------------------------------+

/**
 * ConfigureBranchContext — Configure branch-specific context
 *
 * Sets up branch with correct TFs and clears all state.
 *
 * @param ctx BranchContext to configure
 * @param branch Branch identifier
 */
void ConfigureBranchContext(BranchContext &ctx, ENUM_EXECUTION_BRANCH branch)
{
    // Reset ALL state (critical for isolation)
    ctx.Reset();

    // Sentinel: force structure detection on first tick
    ctx.lastStructureBarTime = 1;
    ctx.lastEntryBarTime     = 1;

// Set branch identification
  ctx.branch = branch;

     // Get branch-specific TFs from BranchRouter
     BranchConfig cfg = GetBranchConfig(branch);
     ctx.structureTF = cfg.structure;
     ctx.entryTF = cfg.entry;

  // Initialize fractal narratives for this branch (v52.5+)
  if(branch == BRANCH_INTRADAY)
  {
for(int n = 0; n < MAX_NARRATIVES_PER_BRANCH; n++)
         g_branchANarratives[n].Reset();
   }
   else
   {
      for(int n = 0; n < MAX_NARRATIVES_PER_BRANCH; n++)
         g_branchBNarratives[n].Reset();
   }
}

//+------------------------------------------------------------------+
//| HELPER: Check if GUID already exists in store (INLINE VERSION)  |
//+------------------------------------------------------------------+
bool IsGuidInStoreSafe(ulong guid, ENUM_EXECUTION_BRANCH branch)
{
    if(guid == 0) return false;
    
    // Base index: 0 for Branch A, MAX_TOTAL_SIGNALS_PER_BRANCH for Branch B
    int baseIdx = (branch == BRANCH_INTRADAY) ? 0 : MAX_TOTAL_SIGNALS_PER_BRANCH; 
    
    for(int i = 0; i < MAX_TOTAL_SIGNALS_PER_BRANCH; i++)
    {
        if(g_hasActiveSignal[baseIdx + i] && g_activeSignal[baseIdx + i].m_guid == guid)
            return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| HELPER: Bool to string for logging                               |
//+------------------------------------------------------------------+
string BoolToString(bool value)
{
    return value ? "true" : "false";
}

 /**
  * ExecuteBranchPipeline — Execute full pipeline for branch
 *
 * EXECUTION FLOW (per branch, ISOLATED):
 *   Step 1: Run SSE on structure TF
 *   Step 2: Run Liquidity Engine on structure TF
 *   Step 3: Run Displacement Validator on structure TF
 *   Step 4: Run Bias Resolver (uses SSE + Liquidity + Displacement)
 *   Step 5: Run Mode Resolver (uses all above + closure signal)
 *   Step 6: Package results
 *
 * CRITICAL: NO shared state between branches.
 *
 * @param ctx BranchContext with configuration
 * @param symbol Symbol to evaluate
 * @return BranchResult with evaluation result
 */
BranchResult ExecuteBranchPipeline(BranchContext &ctx, const string symbol)
{
   BranchResult result;
   ZeroMemory(result);
   result.Reset();

   // NO DIRECT LOGGING - State tracked only for deduplication, no Print() calls
   static ENUM_EXECUTION_BRANCH s_lastBranch = BRANCH_INTRADAY;
   static MarketStructureState s_lastSSE = MSS_RANGE;
   static LiquidityTier s_lastLTE = LT_NONE;
   static BiasOutput s_lastBias;
   static bool s_lastClosureValid = false;
   static bool s_lastEntryValid = false;
s_lastBias.bias = BIAS_NEUTRAL;

 // ═══════════════════════════════════════════════════════════════════════
 // SAFETY GUARDS — Placed FIRST before any pipeline execution
 // ═══════════════════════════════════════════════════════════════════════
    
    // BAR GUARD: Check bars available on structureTF BEFORE any analysis
    int _bars_available = Bars(symbol, ctx.structureTF);
    if(_bars_available < 50)
    {
       LGovPrint("[BE] Insufficient bars on structureTF=" +
                 EnumToString(ctx.structureTF) +
                 " | bars=" + IntegerToString(_bars_available) +
                 " | skipping", LOG_LEVEL_DEBUG, LOG_CHANNEL_PIPELINE);
       result.isBranchActive = false;
       result.valid = false;
       return result;
    }
    
    datetime currentStructureBarTime = iTime(symbol, ctx.structureTF, 0);
    if(currentStructureBarTime == 0)
    {
       LGovPrint("[BE] iTime() returned 0 for structureTF=" +
                 EnumToString(ctx.structureTF) + " | skipping",
                 LOG_LEVEL_DEBUG);
       result.isBranchActive = false;
       result.valid = false;
       return result;
    }

  // ═══════════════════════════════════════════════════════════════════════
  // PIPELINE EXECUTION — NOW SAFE: Guards passed
 // ═══════════════════════════════════════════════════════════════════════
     // Hybrid SSE Force-Refresh: pass forceRefreshStructure flag for mid-bar fractal closures
 ctx.sse = SSE_AnalyzeStructure(symbol, ctx.structureTF, ctx.branchForceRefresh);
      ctx.branchForceRefresh = false;
      ctx.liquidity = LTE_AnalyzeLiquidity(symbol, ctx.structureTF, ctx.sse.state);

      // == DISPLACEMENT ==
      // ATR ready — safe to call DV
      ctx.displacement = DV_AnalyzeDisplacement(symbol, ctx.structureTF);
     
     // === PHASE 9 FIX: Timeframe Bias Decoupling ===
    // Branch A (Intraday): Use H1 as primary bias, fallback to D1 if H1 is RANGE
    // Branch B (Swing): Use H4 as primary bias, fallback to D1 if H4 is RANGE
   if(ctx.branch == BRANCH_INTRADAY)
      ctx.bias = BR_ResolveForTimeframe(symbol, PERIOD_H1, PERIOD_D1);
   else
      ctx.bias = BR_ResolveForTimeframe(symbol, PERIOD_H4, PERIOD_D1);

// Permanent audit trail of cascade configuration
    string biasSourceStr = (ctx.bias.timestamp > 0) ? ctx.bias.source : "N/A";
LogPrint("[BRANCH_CFG] Branch=" + IntegerToString(ctx.branch) +
" | BiasSource=" + biasSourceStr +
             " | StructTF=" + IntegerToString(ctx.structureTF) +
             " | EntryTF=" + IntegerToString(ctx.entryTF),
             LOG_LEVEL_INFO);

LogPrint(
   "[CTX_CHECK] cached.branch=" + IntegerToString(g_cachedCtx.branch),
   LOG_LEVEL_DEBUG
);

// INTERNAL PIPELINE GUARD — Second fail-safe if global OnTick gate is bypassed
bool isWarmedUp = g_sseContext.displacementWarmedUp;
datetime lastWarmup = g_sseContext.warmupTimestamp;

// --- DISPLACEMENT SOFT-GATE: Allow pipeline to proceed, mark quality ---
   bool displacementQualityHigh = true;
   if(!ctx.displacement.isValid)
   {
      if(g_sseContext.displacementWarmedUp)
      {
         // Validated via historical warmup persistence
         ctx.displacement.isValid = true;
      }
      else
      {
         // Soft-Gate: Allow pipeline to proceed, but flag low quality
         // OrderManager can later reduce lot size for non-warmed-up signals
         LogPrint("[BE] WARN — displacement.isValid=false | Pipeline proceeding with degraded quality", LOG_LEVEL_WARN);
         displacementQualityHigh = false;
         result.displacementValid = false;
      }
   }
   else
   {
      result.displacementValid = true;
   }

// ═══════════════════════════════════════════════════════════════════════
// Decoupled buffers to prevent 99.9% rejection
    // ═══════════════════════════════════════════════════════════════════════
    // Create two LOCAL buffers to prevent collision on same tick
    // SAFETY: Always initialize with Reset() to prevent ghost signals
    SLockedSignal structureLocked;
    structureLocked.Reset();
    SLockedSignal entryLocked;
    entryLocked.Reset();

    // SAFETY: Add detection loop with safety iteration counter
    int maxDetectionAttempts = 100;
    int detectionAttempt = 0;

// Structure refresh tracking (uses currentStructureBarTime from top guards)
     bool structureRefreshed = false;
   if(currentStructureBarTime != ctx.lastStructureBarTime)
    {
        // New structure bar detected - refresh context
        ctx.lastStructureBarTime = currentStructureBarTime;
        structureRefreshed = true;
        LogPrint("[STRUCTURE_REFRESH] New " + EnumToString(ctx.structureTF) + " bar detected | Time=" + TimeToString(currentStructureBarTime), LOG_LEVEL_DEBUG);
        
        // Run structure detection only on NEW bar (prevents per-tick CPU spike)
        LGovPrint("[PIPELINE_RUN] Structure detection executing | structureRefreshed=" + BoolToString(structureRefreshed), LOG_LEVEL_DEBUG, LOG_CHANNEL_PIPELINE);
        
        DetectClosureSignal(symbol, ctx.structureTF, ctx.structureSignal, structureLocked);
                  // [MODE_ASSIGNED] Mode assigned deterministically at Lock time per Constitution
                  // C2→MODE_ANTICIPATION, C3→MODE_CONFIRMATION

                  // [CONTINUATION_DEFERRED_SYNC] Sync narrative deferred state to branch context
                  {
                     int activeNarrIdx = (ctx.branch == BRANCH_INTRADAY)
                        ? FN_FindActiveNarrative(g_branchANarratives, ctx.branch)
                        : FN_FindActiveNarrative(g_branchBNarratives, ctx.branch);
                     if(activeNarrIdx >= 0)
                     {
                        bool syncIsBranchA = (ctx.branch == BRANCH_INTRADAY);
                        int syncIdx = activeNarrIdx;
                        bool narC2Deferred = syncIsBranchA ? g_branchANarratives[syncIdx].c2Deferred : g_branchBNarratives[syncIdx].c2Deferred;
                        ulong narDeferredGuid = syncIsBranchA ? g_branchANarratives[syncIdx].deferredC2Guid : g_branchBNarratives[syncIdx].deferredC2Guid;
                        datetime narDeferredTime = syncIsBranchA ? g_branchANarratives[syncIdx].deferredC2Time : g_branchBNarratives[syncIdx].deferredC2Time;
                        ulong narGUID = syncIsBranchA ? g_branchANarratives[syncIdx].narrativeGUID : g_branchBNarratives[syncIdx].narrativeGUID;

                        if(narC2Deferred && !ctx.c2State.deferredActive)
                        {
                           ctx.c2State.deferredActive = true;
                           ctx.c2State.deferredC2Guid = narDeferredGuid;
                           ctx.c2State.deferredTime = narDeferredTime;
                           LogPrint("[C2_CONTINUATION_CANDIDATE] Deferred synced to branch | " +
                                    "narrativeGUID=" + IntegerToString(narGUID) +
                                    " | deferredC2Guid=" + IntegerToString(narDeferredGuid), LOG_LEVEL_DEBUG);
                        }
                        else if(!narC2Deferred && ctx.c2State.deferredActive)
                        {
                           ctx.c2State.deferredActive = false;
                           ctx.c2State.deferredC2Guid = 0;
                           ctx.c2State.deferredTime = 0;
                           LogPrint("[CONTINUATION_DEFERRED_EXPIRED] Cleared from branch context | " +
                                    "narrativeGUID=" + IntegerToString(narGUID), LOG_LEVEL_DEBUG);
                        }
                     }
                     else if(ctx.c2State.deferredActive)
                     {
                        ctx.c2State.deferredActive = false;
                        ctx.c2State.deferredC2Guid = 0;
                        ctx.c2State.deferredTime = 0;
                     }
                  }
                
         // Handle structure signal commitment
        if(structureLocked.isCommitted && !structureLocked.isStored)
        {
           // Check stage validity first
           if(structureLocked.stage != STAGE_READY && 
              structureLocked.stage != STAGE_WAITING_FOR_POI &&
              structureLocked.stage != STAGE_LOCKED)
           {
              LogPrint("[STRUCTURE_REJECT] REASON: INVALID_STAGE | GUID:" + IntegerToString(structureLocked.m_guid) +
                      " | stage=" + EnumToString(structureLocked.stage), LOG_LEVEL_WARN);
           }
           // Check if GUID already exists in store
           else if(IsGuidInStoreSafe(structureLocked.m_guid, ctx.branch))
           {
              LogPrint("[STRUCTURE_REJECT] REASON: GUID_ALREADY_EXISTS | GUID:" + IntegerToString(structureLocked.m_guid), LOG_LEVEL_WARN);
           }
// Try to commit
             else if(CommitSignalToStore(structureLocked, ctx.branch))
             {
                structureLocked.isStored = true;
                LogPrint("[STRUCTURE_COMMIT] GUID:" + IntegerToString(structureLocked.m_guid) +
                        " | ClosureType:" + EnumToString(structureLocked.closureType), LOG_LEVEL_INFO);

                // === C4 STATE SYNC ===
                // If this is a C4 closure, sync SC4State with closure reference values
                if(structureLocked.closureType == CLOSURE_C4)
                {
                   ctx.c4State.c4_high = structureLocked.c2_high;
                   ctx.c4State.c4_low = structureLocked.c2_low;
                   ctx.c4State.c4_close = structureLocked.c2_close;
                   ctx.c4State.lineage.sequenceId = structureLocked.m_guid;
                   ctx.c4State.lineage.parentGuid = (structureLocked.continuationLineage.requiresContinuation ? structureLocked.continuationLineage.parentGuid : 0);
                   LogPrint("[SC4_STATE_SYNC] Structure TF | GUID=" + IntegerToString(structureLocked.m_guid) +
                           " | c4_high=" + DoubleToString(ctx.c4State.c4_high, _Digits) +
                           " | c4_low=" + DoubleToString(ctx.c4State.c4_low, _Digits), LOG_LEVEL_DEBUG);
                 }
              }
            else
            {
               LogPrint("[STRUCTURE_REJECT] REASON: SLOTS_FULL_FOR_BRANCH | GUID:" + IntegerToString(structureLocked.m_guid), LOG_LEVEL_WARN);
            }
        }
// Log non-committed signals for visibility
         else if(structureLocked.m_guid != 0)
         {
            LogPrint("[STRUCTURE_SKIP] GUID:" + IntegerToString(structureLocked.m_guid) +
                    " | isCommitted=" + BoolToString(structureLocked.isCommitted) +
                    " | isStored=" + BoolToString(structureLocked.isStored), LOG_LEVEL_DEBUG);
         }
      }

      // === DEADLOCK FIX: Entry TF detection runs on new bar only ===
      // Entry updates only on new bar - duplicate prevention handled by isStored flag
      datetime currentEntryBarTime = iTime(symbol, ctx.entryTF, 0);
      if(currentEntryBarTime == 0)
      {
         LGovPrint("[BE] iTime() returned 0 for entryTF=" +
                  EnumToString(ctx.entryTF) + " | skipping",
                  LOG_LEVEL_DEBUG);
         return result;
      }
     
      bool entryRefreshed = false;
      if(currentEntryBarTime != ctx.lastEntryBarTime)
      {
         ctx.lastEntryBarTime = currentEntryBarTime;
         entryRefreshed = true;
         LogPrint("[ENTRY_REFRESH] New " + EnumToString(ctx.entryTF) + " bar detected | Time=" + TimeToString(currentEntryBarTime), LOG_LEVEL_DEBUG);
         
         // Run entry detection only on NEW entry bar
         LogPrint("[PIPELINE_RUN] Entry detection executing | entryRefreshed=" + BoolToString(entryRefreshed), LOG_LEVEL_DEBUG);
         
         DetectClosureSignal(symbol, ctx.entryTF, ctx.entrySignal, entryLocked);
                   // [MODE_ASSIGNED] Mode assigned deterministically at Lock time per Constitution

                   // [CONTINUATION_DEFERRED_SYNC] Sync narrative deferred state (entry TF)
                  {
                     int activeNarrIdx = (ctx.branch == BRANCH_INTRADAY)
                        ? FN_FindActiveNarrative(g_branchANarratives, ctx.branch)
                        : FN_FindActiveNarrative(g_branchBNarratives, ctx.branch);
                     if(activeNarrIdx >= 0)
                     {
                        bool syncIsBranchA = (ctx.branch == BRANCH_INTRADAY);
                        int syncIdx = activeNarrIdx;
                        bool narC2Deferred = syncIsBranchA ? g_branchANarratives[syncIdx].c2Deferred : g_branchBNarratives[syncIdx].c2Deferred;
                        ulong narDeferredGuid = syncIsBranchA ? g_branchANarratives[syncIdx].deferredC2Guid : g_branchBNarratives[syncIdx].deferredC2Guid;
                        datetime narDeferredTime = syncIsBranchA ? g_branchANarratives[syncIdx].deferredC2Time : g_branchBNarratives[syncIdx].deferredC2Time;

                        if(narC2Deferred && !ctx.c2State.deferredActive)
                        {
                           ctx.c2State.deferredActive = true;
                           ctx.c2State.deferredC2Guid = narDeferredGuid;
                           ctx.c2State.deferredTime = narDeferredTime;
                        }
                        else if(!narC2Deferred && ctx.c2State.deferredActive)
                        {
                           ctx.c2State.deferredActive = false;
                           ctx.c2State.deferredC2Guid = 0;
                           ctx.c2State.deferredTime = 0;
                        }
                     }
                     else if(ctx.c2State.deferredActive)
                     {
                        ctx.c2State.deferredActive = false;
                        ctx.c2State.deferredC2Guid = 0;
                        ctx.c2State.deferredTime = 0;
                     }
                  }
                
         // Handle entry signal commitment
        if(entryLocked.isCommitted && !entryLocked.isStored)
        {
           // Check stage validity first
           if(entryLocked.stage != STAGE_READY && 
              entryLocked.stage != STAGE_WAITING_FOR_POI &&
              entryLocked.stage != STAGE_LOCKED)
           {
              LogPrint("[ENTRY_REJECT] REASON: INVALID_STAGE | GUID:" + IntegerToString(entryLocked.m_guid) +
                      " | stage=" + EnumToString(entryLocked.stage), LOG_LEVEL_WARN);
           }
           // Check if GUID already exists in store
           else if(IsGuidInStoreSafe(entryLocked.m_guid, ctx.branch))
           {
              LogPrint("[ENTRY_REJECT] REASON: GUID_ALREADY_EXISTS | GUID:" + IntegerToString(entryLocked.m_guid), LOG_LEVEL_WARN);
           }
// Try to commit
            else if(CommitSignalToStore(entryLocked, ctx.branch))
            {
               entryLocked.isStored = true;
               LogPrint("[ENTRY_COMMIT] GUID:" + IntegerToString(entryLocked.m_guid) +
                       " | ClosureType:" + EnumToString(entryLocked.closureType), LOG_LEVEL_INFO);


               // === C4 STATE SYNC ===
               // If this is a C4 closure, sync SC4State with closure reference values
               if(entryLocked.closureType == CLOSURE_C4)
               {
                  ctx.c4State.c4_high = entryLocked.c2_high;
                  ctx.c4State.c4_low = entryLocked.c2_low;
                  ctx.c4State.c4_close = entryLocked.c2_close;
                  ctx.c4State.lineage.sequenceId = entryLocked.m_guid;
                  ctx.c4State.lineage.parentGuid = (entryLocked.continuationLineage.requiresContinuation ? entryLocked.continuationLineage.parentGuid : 0);
                  LogPrint("[SC4_STATE_SYNC] Entry TF | GUID=" + IntegerToString(entryLocked.m_guid) +
                          " | c4_high=" + DoubleToString(ctx.c4State.c4_high, _Digits) +
                          " | c4_low=" + DoubleToString(ctx.c4State.c4_low, _Digits), LOG_LEVEL_DEBUG);
                }
             }
           else
           {
              LogPrint("[ENTRY_REJECT] REASON: SLOTS_FULL_FOR_BRANCH | GUID:" + IntegerToString(entryLocked.m_guid), LOG_LEVEL_WARN);
           }
        }
// Log non-committed signals for visibility
         else if(entryLocked.m_guid != 0)
         {
            LogPrint("[ENTRY_SKIP] GUID:" + IntegerToString(entryLocked.m_guid) +
                    " | isCommitted=" + BoolToString(entryLocked.isCommitted) +
                    " | isStored=" + BoolToString(entryLocked.isStored), LOG_LEVEL_DEBUG);
         }

      // =================================================================
      // POPULATE SETUP STATE FROM DETECTED SIGNALS (continuous execution)
      // =================================================================
     // FIX D: Sanitize garbage stage before checking
     ctx.branchLockedSignal.ValidateAndFixStage();
     
     // If we have a valid locked signal and no setup is active, create one
     if(ctx.branchLockedSignal.stage != STAGE_NONE && ctx.branchLockedSignal.m_guid != 0)
     {
        if(!ctx.setupState.isActive)  // Create new setup if none exists
        {
            ctx.setupState.isActive = true;
            ctx.setupState.isConfirmed = true;
            ctx.setupState.sequenceId = ctx.branchLockedSignal.m_guid;
            ctx.setupState.closureKind = ctx.branchLockedSignal.closureType;
            ctx.setupState.anchorBarTime = ctx.branchLockedSignal.lockTime;
            ctx.setupState.lastUpdateTime = TimeCurrent();
            ctx.setupState.lastActionTime = ctx.branchLockedSignal.commitTime;
            
            LogPrint("[SETUP_CREATED] SeqId=" + IntegerToString(ctx.setupState.sequenceId) +
                    " | Kind=" + EnumToString(ctx.setupState.closureKind), LOG_LEVEL_INFO);
        }
        else
        {
            // Update existing setup timestamp
            ctx.setupState.lastUpdateTime = TimeCurrent();
        }
     }
     
     // =================================================================
     // SETUP PERSISTENCE VS REFRESH LOGIC
     // =================================================================
     // Check if setup already exists and is still valid
     bool setupIsStale = false;
     if(ctx.setupState.isActive && ctx.setupState.isConfirmed && !ctx.setupState.isInvalidated && !ctx.setupState.isExpired)
     {
        // Setup is valid - no need to re-detect, just ensure continuity
        setupIsStale = false;
        
        // Update last evaluation time (persists setup)
        ctx.setupState.lastUpdateTime = TimeCurrent();
        
        // Log persistence for debugging
        if(g_logLevel <= LOG_LEVEL_DEBUG)
           LogPrint("[SETUP_PERSIST] Active | Kind=" + EnumToString(ctx.setupState.closureKind) +
                   " | SeqId=" + IntegerToString(ctx.setupState.sequenceId), LOG_LEVEL_DEBUG);
     }
     else
     {
        // Setup not active or invalidated - will detect fresh in structure refresh below
        setupIsStale = true;
     }
     
     // =================================================================
     // DERIVED CLOSURE CHECKS — Preserves type identity (replaces merger)
     // =================================================================
     // C2 has an active sequence if valid and has lineage with non-zero ID
     bool c2Active = false;
     if(ctx.c2State.valid && ctx.c2State.lineage.sequenceId != 0)
        c2Active = true;
     
     // C3 has an active sequence if valid and has lineage with non-zero ID
     bool c3Active = false;
     if(ctx.c3State.valid && ctx.c3State.lineage.sequenceId != 0)
        c3Active = true;
     
     // Both are derived from separate states, no merger
     // Legacy support: check structureSignal/entrySignal if new states not populated
     if(!c2Active && ctx.structureSignal.valid && ctx.structureSignal.type == CLOSURE_C2)
        c2Active = true;
     if(!c3Active && ctx.structureSignal.valid && ctx.structureSignal.type == CLOSURE_C3)
        c3Active = true;
     
// Use derived checks that preserve identity instead of merged boolean
      // Mode resolution proceeds if EITHER is active OR setup is valid (continuous execution)
      // FIXED: More robust active check during modal upgrades (Enhancement E5)
      bool c2OrC3Active = 
          (SC2StateIsActive(ctx.c2State) && ctx.c2State.lineage.sequenceId != 0) ||
          (SC3StateIsActive(ctx.c3State) && ctx.c3State.lineage.sequenceId != 0) ||
          (ctx.branchLockedSignal.stage != STAGE_NONE && ctx.branchLockedSignal.m_guid != 0) ||
          SC4StateIsActive(ctx.c4State);
     
     // Make available for later use in closureValid references
     bool closureHasC2 = c2Active;
     bool closureHasC3 = c3Active;
     bool closureHasSetup = ctx.setupState.IsValidForExecution();
     
// FIX D: Sanitize garbage stage before lifecycle check
     ctx.branchLockedSignal.ValidateAndFixStage();
     
     // SIGNAL LIFECYCLE FIX: Expire signals stuck in WAITING_FOR_POI too long
     // If signal has been waiting > maxBars without progressing, reset it
     if(ctx.branchLockedSignal.stage == STAGE_WAITING_FOR_POI ||
       ctx.branchLockedSignal.stage == STAGE_AWAITING_C3_CLOSURE)
    {
        datetime currentEntryBar = iTime(symbol, ctx.entryTF, 0);
        int barsWaiting = 0;
        if(ctx.branchLockedSignal.lockTime > 0 && currentEntryBar > ctx.branchLockedSignal.lockTime)
        {
            // Calculate bars since lock (approximate)
            int tfSeconds = (int)PeriodSeconds(ctx.entryTF);
            barsWaiting = (int)((currentEntryBar - ctx.branchLockedSignal.lockTime) / tfSeconds);
        }

// PHASE 2 FIX: Differentiate expiration by closure type
       // C2 = anticipation mode (wider timeout)
       // C3 = confirmation mode (shorter timeout but can be delayed)
       // C4 = continuation (follows C3's TTL)
       // REGRESSION_GUARD_V52.5_TTL: Continuation window = 40 bars max
       int expireBars = 14400;  // Default large value
       if(ctx.branchLockedSignal.closureType == CLOSURE_C2)
          expireBars = g_branchParams.limitExpirationBars * 2;
       else if(ctx.branchLockedSignal.closureType == CLOSURE_C3 || ctx.branchLockedSignal.closureType == CLOSURE_C4)
          expireBars = g_branchParams.limitExpirationBars;  // 40 bars for continuation

       if(barsWaiting >= expireBars)
       {
           LogPrint("[SIGNAL_EXPIRED] GUID:" + IntegerToString(ctx.branchLockedSignal.m_guid) +
                   " | stage=" + EnumToString(ctx.branchLockedSignal.stage) +
                   " | barsWaiting=" + IntegerToString(barsWaiting) +
                   " | expireBars=" + IntegerToString(expireBars) +
                   " | closureType=" + EnumToString(ctx.branchLockedSignal.closureType) +
                   " | REASON: timeout in POI",
                   LOG_LEVEL_WARN);
           
       // REGRESSION_GUARD_C3: Dynamic TTL — C3/C4 get ~2500s, C2 gets 4h max
           if(ctx.branchLockedSignal.commitTime > 0)
           {
               int secondsInPOI = (int)(TimeCurrent() - ctx.branchLockedSignal.commitTime);
               int maxPOISeconds = (ctx.branchLockedSignal.closureType == CLOSURE_C3 || ctx.branchLockedSignal.closureType == CLOSURE_C4) ? 2500 : 14400;
               if((ctx.branchLockedSignal.closureType == CLOSURE_C3 || ctx.branchLockedSignal.closureType == CLOSURE_C4))
                  LogPrint("[CONTINUATION_TTL] Dynamic TTL | maxPOISeconds=" + IntegerToString(maxPOISeconds) +
                          " | GUID=" + IntegerToString(ctx.branchLockedSignal.m_guid), LOG_LEVEL_DEBUG);
               
               if(secondsInPOI > maxPOISeconds)
               {
                   LogPrint("[SIGNAL_EXPIRED_TIME] GUID:" + IntegerToString(ctx.branchLockedSignal.m_guid) +
                           " | secondsInPOI=" + IntegerToString(secondsInPOI) +
                           " | maxSeconds=" + IntegerToString(maxPOISeconds) +
                           " | REASON: time_timeout_in_POI",
                           LOG_LEVEL_WARN);
               }
           }

// Reset signal to allow new closures
              ctx.branchLockedSignal.TransitionStage(STAGE_NONE);
              ctx.branchLockedSignal.m_guid = 0;
              ctx.branchLockedSignal.entry_price = 0.0;
              ctx.branchLockedSignal.closureType = CLOSURE_NONE;
              ctx.branchLockedSignal.direction = DIRECTION_NONE;
              ctx.branchLockedSignal.isCommitted = false;
              ctx.branchLockedSignal.isStored = false;
              // [STATE_MUTATION] executionMode NOT reset here - signal must go through Lock() for new mode assignment
              // Setting to -1 sentinel prevents MODE_NONE contamination in expired signal logging
             
             // Also clear setup state on signal expiry
             if(ctx.setupState.sequenceId == ctx.branchLockedSignal.m_guid)
                ctx.setupState.MarkExpired();
         }
     }
     
     // =================================================================
     // EXPIRATION CHECK FOR SETUP STATE
     // =================================================================
     // Check if setup has expired (48 hour max)
     if(ctx.setupState.isActive && ctx.setupState.lastActionTime > 0)
     {
        if(TimeCurrent() - ctx.setupState.lastActionTime > 48 * 3600)
        {
           LogPrint("[SETUP_EXPIRED] SeqId=" + IntegerToString(ctx.setupState.sequenceId) +
                   " | Age=" + IntegerToString((int)(TimeCurrent() - ctx.setupState.lastActionTime) / 3600) + "h",
                   LOG_LEVEL_WARN);
           ctx.setupState.MarkExpired();
        }
     }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 5b: Run Mode Resolver — ONLY AFTER Closure Detection
    // ═══════════════════════════════════════════════════════════════════════
    // Prepare mode input (branch-specific, NO sharing)
    ModeInput modeInput;
    modeInput.bias = ctx.bias;
    modeInput.liquidity = ctx.liquidity;
    modeInput.sse = ctx.sse;
    modeInput.displacement = ctx.displacement;
    modeInput.entrySignal = ctx.entrySignal;

    // Build True TTrades input from live pipeline data
    STrueTTradesInput ttInput;
    ttInput.Reset();

    // HTF fractal stage — derived from structure TF closure signal
    ttInput.htfStage = ctx.structureSignal.valid
                       ? ctx.structureSignal.fractalState
                       : FRACTAL_STATE_NONE;

    // LTF fractal stage — derived from entry TF closure signal
    ttInput.ltfStage = ctx.entrySignal.valid
                       ? ctx.entrySignal.fractalState
                       : FRACTAL_STATE_NONE;

    // Intended direction — from closure signal sweep direction
    ENUM_DIRECTION sweepDir = DIRECTION_NONE;
    if(ctx.structureSignal.valid)
       sweepDir = ctx.structureSignal.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;
    else if(ctx.entrySignal.valid)
       sweepDir = ctx.entrySignal.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;

    // Store HTF candle times for CISD detection
    if(ctx.structureSignal.valid && ctx.structureSignal.fractalState != FRACTAL_STATE_NONE)
    {
       datetime currentHtfTime = iTime(symbol, ctx.structureTF, 0);
       if(currentHtfTime > 0)
       {
          int htfPeriodSeconds = (int)PeriodSeconds(ctx.structureTF);
          ctx.htfCandleOpenTime = currentHtfTime;
          ctx.htfCandleCloseTime = currentHtfTime + htfPeriodSeconds;
       }
    }

    // True LTF CISD detection — replace proxy with actual CISD check
    SCISDResult cisd_result;
    ZeroMemory(cisd_result);
    if(ctx.structureSignal.valid && ctx.entrySignal.valid)
    {
       ttInput.ltfCISDConfirmed = DetectLTFCISD(
          ctx.entryTF,
          ctx.htfCandleOpenTime,
          ctx.htfCandleCloseTime,
          sweepDir,
          cisd_result
       );

       if(ttInput.ltfCISDConfirmed)
          LogPrint("[CISD] CONFIRMED | Dir=" + EnumToString(sweepDir)
                   + " | CreationOpen=" + DoubleToString(cisd_result.creation_open, _Digits)
                   + " | ConfirmClose=" + DoubleToString(cisd_result.cisd_close, _Digits)
                   + " | Time=" + TimeToString(cisd_result.cisd_time), LOG_LEVEL_DEBUG);
       else
          LogPrint("[CISD] FAIL — No LTF close through creation candle open within HTF window"
                   + " | HTFOpen=" + TimeToString(ctx.htfCandleOpenTime)
                   + " | HTFClose=" + TimeToString(ctx.htfCandleCloseTime), LOG_LEVEL_DEBUG);
    }
    else
    {
       ttInput.ltfCISDConfirmed = false;
    }

    // HTF C2 wick valid — structure TF wick ratio within config threshold
    ttInput.htfC2WickValid = (ctx.structureSignal.valid &&
                              ctx.structureSignal.c2_wick_ratio > 0.0 &&
                              ctx.structureSignal.c2_wick_ratio <= g_trueTTradesConfig.maxC2WickPercent);

    // Volume confirmed — default true until VolumeAnalyzer is wired
    ttInput.volumeConfirmed = true;

    // Intended direction from sweep direction
    ttInput.intendedDirection = sweepDir;

    // HTF candle state for mode resolution
    ttInput.htfCandleState = ctx.structureSignal.fractalState;

    // Store HTF period seconds for mode resolution
    ttInput.htfPeriodSeconds = (int)PeriodSeconds(ctx.structureTF);

    // === PHASE 9 FIX: D1 Bias Pass-Through ===
    // D1 bias is now resolved in BR_ResolveForTimeframe() and available in ctx.bias
    ttInput.d1Bias = ctx.bias.bias;

    if(g_logLevel <= LOG_LEVEL_DEBUG)
    {
       LogPrint("[MODE_INPUT] Bias=" + EnumToString(ctx.bias.bias) +
                " | SSE=" + EnumToString(ctx.sse.state) +
                " | Lt=" + EnumToString(ctx.liquidity.tier) +
                " | Disp=" + (ctx.displacement.isValid ? "VALID" : "INVALID") +
                " | Dir=" + EnumToString(ttInput.intendedDirection),
                LOG_LEVEL_DEBUG);
    }

// === DEADLOCK FIX: Mode resolution with proper caching ===
    // Runs every tick - uses cached mode if available
    datetime currentBarTime = iTime(symbol, ctx.entryTF, 0);
    bool modeResolved = false;

    // FIXED: Use locked signal's original closure for mode resolution (Forensic Priority 1)
    SLockedSignal activeSignal;
    ZeroMemory(activeSignal);
    bool hasActiveSignal = false;
    int baseIdx = GetSignalStoreIndex(ctx.branch);
    for(int i = 0; i < MAX_TOTAL_SIGNALS_PER_BRANCH; i++)
    {
        int idx = baseIdx + i;
        if(g_hasActiveSignal[idx] && g_activeSignal[idx].m_guid != 0)
        {
            activeSignal = g_activeSignal[idx];
            hasActiveSignal = true;
            break;
        }
    }

    if(hasActiveSignal && 
       (activeSignal.stage == STAGE_WAITING_FOR_POI || 
        activeSignal.stage == STAGE_AWAITING_C3_CLOSURE ||
        activeSignal.stage == STAGE_READY ||
        activeSignal.stage == STAGE_AWAITING_C2_CLOSURE))
    {
        // Use the ORIGINAL closure that created the locked signal
        SClosureSignal signalClosure;
        signalClosure.valid = true;
        signalClosure.type = activeSignal.closureType;
        signalClosure.is_bullish = (activeSignal.direction == DIRECTION_BUY);

        // Map closure type to fractal state (v52.5+: C4 added)
        if(activeSignal.closureType == CLOSURE_C2)
           signalClosure.fractalState = FRACTAL_STATE_C2;
        else if(activeSignal.closureType == CLOSURE_C4)
           signalClosure.fractalState = FRACTAL_STATE_C4;
        else
           signalClosure.fractalState = FRACTAL_STATE_C3;
        
// Override current detection with locked signal data
         modeInput.entrySignal = signalClosure;
         
         // Log locked signal mode resolution (rate-limited by LogGovernor)
         LogPrint("[MODE_RESOLVE_LOCKED] GUID=" + IntegerToString(activeSignal.m_guid) +
                  " | closure=" + EnumToString(activeSignal.closureType) +
                  " | stage=" + EnumToString(activeSignal.stage), LOG_LEVEL_INFO);
    }

    if(c2OrC3Active)  // Now uses derived identity-preserving check
   {
        if(currentBarTime != ctx.lastModeBarTime)
        {
            // New bar - re-evaluate mode
            ctx.mode = MR_Resolve(modeInput, ttInput);
            ctx.cachedMode = ctx.mode.mode;
            ctx.lastModeBarTime = currentBarTime;
            modeResolved = true;
            LogPrint("[MODE_RESOLVED] New bar | Mode=" + MR_ModeToString(ctx.mode.mode), LOG_LEVEL_DEBUG);
        }
       else if(ctx.cachedMode != MODE_NONE)
       {
           // Same bar + cached mode - use cached
           ctx.mode.mode = ctx.cachedMode;
           ctx.mode.hasClosure = true;
           modeResolved = true;
       }
       else
       {
           // Same bar + no cached - try anyway
           ctx.mode = MR_Resolve(modeInput, ttInput);
           ctx.cachedMode = ctx.mode.mode;
           modeResolved = true;
       }
       
// [MODE_SYNC] Log mode mismatches as warnings (no mutation)
          // Mode is set at Lock time per Constitution (C2→ANTICIPATION, C3→CONFIRMATION)
          // BranchEvaluator does NOT own executionMode - log discrepancy for forensics only
          if(ctx.mode.mode != MODE_NONE && ctx.cachedMode != MODE_NONE)
          {
              int updateBaseIdx = GetSignalStoreIndex(ctx.branch);
              for(int si = 0; si < MAX_TOTAL_SIGNALS_PER_BRANCH; si++)
              {
                  int sidx = updateBaseIdx + si;
                  if(g_hasActiveSignal[sidx] && g_activeSignal[sidx].executionMode != ctx.mode.mode)
                  {
                      LogPrint("[MODE_DISCREPANCY] Mode mismatch detected | GUID=" + IntegerToString(g_activeSignal[sidx].m_guid) +
                               " | signal.executionMode=" + IntegerToString(g_activeSignal[sidx].executionMode) +
                               " | ctx.mode.mode=" + IntegerToString(ctx.mode.mode) +
                               " | owner=LockedSignal (read-only)", LOG_LEVEL_WARN);
                  }
              }
          }
       

         // [SIGNAL_CONTRACT] Log runtime execution mode from signal's actual state
         if(hasActiveSignal)
         {
            string runtimeModeStr = (activeSignal.executionMode == MODE_ANTICIPATION) ? "ANTICIPATION" :
                                   (activeSignal.executionMode == MODE_CONFIRMATION) ? "CONFIRMATION" : "NONE";
            LogPrint("[MODE_RUNTIME] GUID=" + IntegerToString(activeSignal.m_guid) +
                     " | executionMode=" + runtimeModeStr + "[" + IntegerToString(activeSignal.executionMode) + "]" +
                     " | closure=" + EnumToString(activeSignal.closureType), LOG_LEVEL_DEBUG);
            PrintFormat("[C2_MODE] %s upgraded=%s", runtimeModeStr, IsC2UpgradedToC3(activeSignal.m_guid)?"true":"false");
            
            // [BRANCH_MODE_MISMATCH] Runtime check: log if executionMode contradicts closure type
            if(activeSignal.executionMode != MODE_NONE)
            {
             if(activeSignal.closureType == CLOSURE_C2 && activeSignal.executionMode == MODE_CONFIRMATION)
               {
                  LogPrint("[BRANCH_MODE_MISMATCH] ExecutionMode contradicts closure type per Constitution | GUID=" + IntegerToString(activeSignal.m_guid) +
                           " | executionMode=" + runtimeModeStr + " | closure=" + EnumToString(activeSignal.closureType), LOG_LEVEL_WARN);
               }
            }
         }

        // --- DOW THEORY ALIGNMENT: Explicit Bias validation even with low displacement ---
        // Even if displacementValid=false, C2/C3 closures can still execute if HTF Bias aligns
        // This ensures standalone C2/C3 logic is NOT blocked by displacement quality
        bool htfBiasAligned = (ctx.bias.bias == BIAS_BULLISH && ctx.structureSignal.is_bullish) ||
                              (ctx.bias.bias == BIAS_BEARISH && !ctx.structureSignal.is_bullish) ||
                              (ctx.bias.bias == BIAS_NEUTRAL && ctx.structureSignal.valid);

        bool closureHasBiasAlignment = false;
      if(SC2StateIsActive(ctx.c2State) || SC3StateIsActive(ctx.c3State))
      {
        closureHasBiasAlignment = htfBiasAligned;

            // REGRESSION_GUARD_C3_BIAS: Log C3-specific bias alignment in pipeline
            if(SC3StateIsActive(ctx.c3State) && htfBiasAligned)
            {
               LogPrint("[C3_BIAS_ALIGN_PASS] Pipeline | C3 closure aligns with HTF bias" +
                        " | bias=" + EnumToString(ctx.bias.bias) +
                        " | signal=" + (ctx.structureSignal.is_bullish ? "BULL" : "BEAR"),
                        LOG_LEVEL_INFO);
            }

            if(!result.displacementValid && htfBiasAligned)
            {
               // Low displacement quality but Dow Theory alignment present
               LogPrint("[BE] DOW THEORY ALIGNMENT | displacementValid=FALSE but HTF Bias aligns | C2/C3 allowed",
                        LOG_LEVEL_INFO);
               result.displacementValid = true;  // Upgrade: Bias alignment compensates for displacement
            }
           else if(!result.displacementValid && !htfBiasAligned)
           {
              LogPrint("[BE] DOW THEORY WARNING | displacementValid=FALSE + NO HTF Bias alignment | Mode may be blocked",
                       LOG_LEVEL_WARN);
           }
        }
    }
    else
   {
       // No closure - use cached mode if available
       if(ctx.cachedMode != MODE_NONE && currentBarTime == ctx.lastModeBarTime)
       {
           ctx.mode.mode = ctx.cachedMode;
           ctx.mode.hasClosure = true;
       }
       else
       {
           ctx.mode.mode = MODE_NONE;
           ctx.mode.hasClosure = false;
       }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // TOP-DOWN CONTEXT GATE (Three-tier structural validation)
    // Runs after mode resolution — checks every store signal for this branch.
    // ═══════════════════════════════════════════════════════════════════════
    // Tier 1: D1 bias (mechanical daily candle rule)
    // Tier 2: HTF confirmation (CISD or C2/C3 closure on structure TF)
    // Tier 3: LTF CISD at POI (entry TF delivery confirmation)
    if(ctx.branch == BRANCH_INTRADAY || ctx.branch == BRANCH_SWING)
    {
        ValidateTopDownContext(ctx, symbol);
    }

// ═══════════════════════════════════════════════════════════════════════
     // STEP 7: Package results
     // ═══════════════════════════════════════════════════════════════════════
     // FIX 5: PIPELINE VISIBILITY
     LogTrace("[PIPELINE] Entered ExecuteBranchPipeline()", LOG_LEVEL_DEBUG, LOG_CHANNEL_PIPELINE);

    // === DISPLACEMENT GATE DECOUPLING FIX ===
    // Branch ALWAYS remains ACTIVE (pipeline survives regardless of displacement)
    // Displacement is now a QUALITY FILTER, not a pipeline kill switch
    // Signal becomes READY only when closure is actually detected
    result.isBranchActive = true;  // Pipeline always survives
    result.displacementValid = ctx.displacement.isValid;  // Quality score for downstream
    result.hasSignalReady = ctx.mode.hasClosure;
    result.valid = result.isBranchActive;  // Legacy compatibility
    result.mode = ctx.mode.mode;
    result.timestamp = TimeCurrent();

    // Determine direction
    if(ctx.bias.bias == BIAS_BULLISH)
    {
       result.direction = DIRECTION_BUY;
    }
    else if(ctx.bias.bias == BIAS_BEARISH)
    {
       result.direction = DIRECTION_SELL;
    }
    else if(ctx.mode.mode == MODE_ANTICIPATION && ctx.entrySignal.valid)
    {
        result.direction = ctx.entrySignal.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;
    }
    else
    {
       result.direction = DIRECTION_NONE;
       // === PIPELINE SURVIVAL FIX: Don't invalidate branch if no direction
       // isBranchActive already set from displacement above
    }

    // FIX 5: PIPELINE VISIBILITY (exit logging)
    LogTrace("[PIPELINE] Exit — Branch Active=" + (string)result.isBranchActive, LOG_LEVEL_DEBUG, LOG_CHANNEL_PIPELINE);

     // Calculate confidence (0.0-1.0)
     double confidence = 0.0;
     double rawScore = 0.0;

     // === PIPELINE SURVIVAL FIX: Calculate confidence if branch is active ===
     if(result.isBranchActive)
     {
       confidence = ctx.bias.strengthScore;
       rawScore = confidence;

       if(ctx.mode.mode == MODE_CONFIRMATION)
          confidence += 0.2;
       else if(ctx.mode.mode == MODE_ANTICIPATION)
          confidence += 0.1;

       if(ctx.structureSignal.valid && ctx.entrySignal.valid)
          confidence += 0.1;

       confidence = MathClamp(confidence, 0.0, 1.0);
    }

    result.confidence = confidence;

// --- BRANCH_DEBUG LOGGING ---
if(ShouldLog(LOG_LEVEL_DEBUG, LOG_CHANNEL_PIPELINE))
      {
         string bias = BR_BiasToString(ctx.bias.bias);
         // Use derived identity checks instead of merged boolean
         string c2Status = c2Active ? "C2_ACTIVE" : "C2_NONE";
         string c3Status = c3Active ? "C3_ACTIVE" : "C3_NONE";
         string closureStatus = c2Active || c3Active ? "HAS_CLOSURE" : "NONE";
         string liquidityTier = LTE_TierToString(ctx.liquidity.tier);
         LogTrace("BRANCH_DEBUG " + BE_GetBranchTagEx(ctx.branch) + " | Closure=" + closureStatus +
                  " | " + c2Status + " | " + c3Status +
                  " | Bias=" + bias + " | Liquidity=" + liquidityTier, LOG_LEVEL_DEBUG, LOG_CHANNEL_PIPELINE);
      }

    // Generate rationale
    result.rationale = "[BRANCH " + GetBranchName(ctx.branch) + "] " +
                       "Mode=" + MR_ModeToString(ctx.mode.mode) +
                       " | Bias=" + BR_BiasToString(ctx.bias.bias) +
                       " | SSE=" + SSE_StateToString(ctx.sse.state) +
                       " | Liquidity=" + LTE_TierToString(ctx.liquidity.tier);

    // Mark branch as evaluated
    ctx.evaluationTime = result.timestamp;
    ctx.isEvaluated = true;

    return result;
    }
    return result;
}

//+------------------------------------------------------------------+
//| MAIN ENGINE FUNCTIONS                                            |
//+------------------------------------------------------------------+
// REGRESSION_GUARD_V52.5_SIGNAL_CONSOLIDATION: ExecuteSignalBranch removed
// Signal commitment now happens ONLY in detection loop via CommitSignalToStore
// Single ownership model: g_activeSignal[] is the sole signal store

/**
 * BE_Initialize — Initialize Branch Evaluator
 *
 * Call during EA initialization.
 * Configures both branches with isolated contexts.
 *
 * @return true on success
 */
bool BE_Initialize()
{
    // Configure Branch A (Intraday: D1→H1→M5)
    ConfigureBranchContext(g_branchAContext, BRANCH_INTRADAY);

    // Configure Branch B (Swing: D1→H4→M15)
    ConfigureBranchContext(g_branchBContext, BRANCH_SWING);

    return true;
}

/**
 * BE_EvaluateBranch — Evaluate single branch (isolated pipeline)
 *
 * MAIN ENTRY POINT for branch evaluation.
 * Runs full pipeline independently for the specified branch.
 *
 * @param branch Branch to evaluate (BRANCH_INTRADAY or BRANCH_SWING)
 * @param symbol Symbol to evaluate
 * @return BranchResult with evaluation result
 */
BranchResult BE_EvaluateBranch(ENUM_EXECUTION_BRANCH branch, const string symbol)
{
   // Execute branch pipeline (ISOLATED)
   if(branch == BRANCH_INTRADAY)
   {
      return ExecuteBranchPipeline(g_branchAContext, symbol);
   }
else if(branch == BRANCH_SWING)
    {
       return ExecuteBranchPipeline(g_branchBContext, symbol);
    }
    else
    {
       LogTrace("[BE] ERROR: Invalid branch specified", LOG_LEVEL_ERROR, LOG_CHANNEL_PIPELINE);
       BranchResult invalid;
       ZeroMemory(invalid);
       invalid.Reset();
       return invalid;
    }
}

/**
 * BE_ResolveParams — Resolve branch-specific runtime parameters from inputs
 *
 * @param branch Branch identifier (BRANCH_INTRADAY or BRANCH_SWING)
 * @param out Output structure to populate
 */
void BE_ResolveParams(ENUM_EXECUTION_BRANCH branch, SBranchResolvedParams &out)
{
   if(branch == BRANCH_INTRADAY)
   {
      out.c2WickThreshold          = InpA_C2_WickThreshold;
      out.c2MinWickRatio           = InpA_C2_MinWickRatio;
      out.c2MinBodyRatio           = InpA_C2_MinBodyRatio;
      out.c2DisplacementMultiplier = InpA_C2_DisplacementMultiplier;
      out.c2RangeExpansionFactor   = InpA_C2_RangeExpansionFactor;
      out.c3BodyMultiplier         = InpA_C3_BodyMultiplier;
      out.c3DisplacementMultiplier = InpA_C3_DisplacementMultiplier;
      out.c3RangeExpansionFactor   = InpA_C3_RangeExpansionFactor;
      out.rgBufferPercent          = InpA_RG_BufferPercent;
      out.rgMarketThreshold        = InpA_RG_MarketThreshold;
      out.c2POIBufferPercent      = InpA_C2_POI_BufferPercent;
      out.c3POIBufferPercent      = InpA_C3_POI_BufferPercent;
      out.limitExpirationBars      = InpA_LimitExpirationBars;
   }
   else // BRANCH_SWING
   {
      out.c2WickThreshold          = InpB_C2_WickThreshold;
      out.c2MinWickRatio           = InpB_C2_MinWickRatio;
      out.c2MinBodyRatio           = InpB_C2_MinBodyRatio;
      out.c2DisplacementMultiplier = InpB_C2_DisplacementMultiplier;
      out.c2RangeExpansionFactor   = InpB_C2_RangeExpansionFactor;
      out.c3BodyMultiplier         = InpB_C3_BodyMultiplier;
      out.c3DisplacementMultiplier = InpB_C3_DisplacementMultiplier;
      out.c3RangeExpansionFactor   = InpB_C3_RangeExpansionFactor;
      out.rgBufferPercent          = InpB_RG_BufferPercent;
      out.rgMarketThreshold        = InpB_RG_MarketThreshold;
      out.c2POIBufferPercent      = InpB_C2_POI_BufferPercent;
      out.c3POIBufferPercent      = InpB_C3_POI_BufferPercent;
      out.limitExpirationBars      = InpB_LimitExpirationBars;
   }
}

/**
 * BE_EvaluateAllBranches — Evaluate branch(s) based on activeBranch
 *
 * @param symbol Symbol to evaluate
 * @param activeBranch Branch to evaluate (BRANCH_INTRADAY or BRANCH_SWING)
 * @return true if at least one branch produced valid result
 */
bool BE_EvaluateAllBranches(const string symbol, ENUM_EXECUTION_BRANCH activeBranch)
{
     // Set active branch for logging enforcement
     g_activeBranch = activeBranch;

     bool evaluateA = (activeBranch == BRANCH_INTRADAY);
     bool evaluateB = (activeBranch == BRANCH_SWING);

     BranchResult resultA;
     resultA.valid = false;
     BranchResult resultB;
     resultB.valid = false;

     if(evaluateA)
        resultA = BE_EvaluateBranch(BRANCH_INTRADAY, symbol);

     if(evaluateB)
        resultB = BE_EvaluateBranch(BRANCH_SWING, symbol);

 if(g_logLevel <= LOG_LEVEL_INFO)
     {
         // === PIPELINE SURVIVAL FIX: Use isBranchActive for logging ===
         string aStr = evaluateA ? (resultA.isBranchActive ? "OK" : "FAIL") : "SKIP";
          string bStr = evaluateB ? (resultB.isBranchActive ? "OK" : "FAIL") : "SKIP";
          string summary = "[BE] " + BE_GetBranchTag() + " A=" + aStr + " B=" + bStr;
         LogTrace(summary, LOG_LEVEL_INFO, LOG_CHANNEL_PIPELINE);
     }

// FIX: Set branches evaluated flag only if at least one branch ran
     g_branchesEvaluated = (evaluateA || evaluateB);

 // === PIPELINE SURVIVAL FIX: Return isBranchActive, not closure-dependent valid ===
if(activeBranch == BRANCH_INTRADAY)
     return resultA.isBranchActive;
   if(activeBranch == BRANCH_SWING)
      return resultB.isBranchActive;
   
   // Should never reach here — only BRANCH_INTRADAY or BRANCH_SWING valid
   LGovPrint("[BE] CRITICAL: Unrecognized branch value=" +
             IntegerToString((int)activeBranch), LOG_LEVEL_DEBUG);
   return false;
}

/**
 * BE_GetBranchAContext — Get Branch A context
 *
 * @return BranchContext for Branch A (Intraday: D1→H1→M5)
 */
BranchContext BE_GetBranchAContext()
{
    return g_branchAContext;
}

/**
 * BE_GetBranchBContext — Get Branch B context
 *
 * @return BranchContext for Branch B (Swing: D1→H4→M15)
 */
BranchContext BE_GetBranchBContext()
{
    return g_branchBContext;
}

/**
 * BE_ShouldTradeBranchA — Check if Branch A should trade
 *
 * @return true if Branch A has valid signal
 */
bool BE_ShouldTradeBranchA()
{
    BranchContext ctx = g_branchAContext;
    return ctx.isEvaluated && (ctx.bias.bias != BIAS_NEUTRAL);
}

/**
 * BE_ShouldTradeBranchB — Check if Branch B should trade
 *
 * @return true if Branch B has valid signal
 */
bool BE_ShouldTradeBranchB()
{
    BranchContext ctx = g_branchBContext;
    return ctx.isEvaluated && (ctx.bias.bias != BIAS_NEUTRAL);
}

/**
 * BE_GetSafeSignalGUID — Get signal GUID only when result is valid for execution
 *
 * GUID HANDOVER: Only returns GUID if BOTH result.valid AND result.isBranchActive
 * are TRUE. This ensures OrderManager only receives valid signal IDs.
 *
 * @param branch Branch to get GUID from
 * @param result BranchResult with validation status
 * @return Signal GUID if safe to handoff, 0 otherwise
 */
ulong BE_GetSafeSignalGUID(ENUM_EXECUTION_BRANCH branch, const BranchResult &result)
{
   // GUID Handoff Validation: Both conditions must be TRUE
   if(!result.valid || !result.isBranchActive)
   {
      LogPrint("[GUID_HANDOFF] BLOCKED | valid=" + BoolToString(result.valid) +
               " | isBranchActive=" + BoolToString(result.isBranchActive), LOG_LEVEL_DEBUG);
      return 0;
   }

   // Bypass MQL5 struct reference limitations by reading globals directly
   ulong targetGuid = 0;
   
   if(branch == BRANCH_INTRADAY)
   {
      targetGuid = g_branchAContext.branchLockedSignal.m_guid;
   }
   else
   {
      targetGuid = g_branchBContext.branchLockedSignal.m_guid;
   }

   // Validate the retrieved GUID
   if(targetGuid == 0)
   {
      LogPrint("[GUID_HANDOFF] WARNING | GUID is 0 despite valid result", LOG_LEVEL_WARN);
   }

   LogPrint("[GUID_HANDOFF] ALLOWED | GUID=" + IntegerToString(targetGuid), LOG_LEVEL_DEBUG);
   return targetGuid;
}

/**
 * BE_GetBranchResult — Get branch result from context
 *
 * @param ctx BranchContext
 * @return BranchResult
 */
BranchResult BE_GetBranchResult(const BranchContext &ctx)
{
     BranchResult result;
     ZeroMemory(result);
     result.Reset();

     if(!ctx.isEvaluated)
        return result;

     // === PIPELINE SURVIVAL FIX: Use displacement for status ===
     result.isBranchActive = true;  // Pipeline always survives (consistent with ExecuteBranchPipeline)
     result.hasSignalReady = ctx.mode.hasClosure;
     result.valid = result.isBranchActive;
     result.mode = ctx.mode.mode;
     result.timestamp = ctx.evaluationTime;

   // Determine direction from bias
   if(ctx.bias.bias == BIAS_BULLISH)
   {
      result.direction = DIRECTION_BUY;
   }
   else if(ctx.bias.bias == BIAS_BEARISH)
   {
      result.direction = DIRECTION_SELL;
   }
   else
   {
      result.direction = DIRECTION_NONE;
      // Don't invalidate branch if no direction - keep active
   }

   // Calculate confidence
   double confidence = ctx.bias.strengthScore;
   double rawScore = confidence;

   if(ctx.mode.mode == MODE_CONFIRMATION)
      confidence += 0.2;
   else if(ctx.mode.mode == MODE_ANTICIPATION)
      confidence += 0.1;

if(ctx.structureSignal.valid && ctx.entrySignal.valid)
       confidence += 0.1;

    result.confidence = MathClamp(confidence, 0.0, 1.0);

 // --- BRANCH_DEBUG LOGGING (BE_GetBranchResult) ---
     // Use derived identity checks
     bool c2ActiveForResult = SC2StateIsActive(ctx.c2State);
     bool c3ActiveForResult = SC3StateIsActive(ctx.c3State);
     bool hasClosureForResult = c2ActiveForResult || c3ActiveForResult;
     bool hasBothForResult = c2ActiveForResult && c3ActiveForResult;
     string structureSignal = SSE_StateToString(ctx.sse.state);
    if(ShouldLog(LOG_LEVEL_DEBUG, LOG_CHANNEL_PIPELINE))
      {
         string bias = BR_BiasToString(ctx.bias.bias);
         string c2s = c2ActiveForResult ? "C2" : "NONE";
         string c3s = c3ActiveForResult ? "C3" : "NONE";
         string closureStr = hasBothForResult ? "C2+C3" : (hasClosureForResult ? (c2ActiveForResult ? c2s : c3s) : "NONE");
         string liquidityTier = LTE_TierToString(ctx.liquidity.tier);
         LogTrace("BRANCH_DEBUG " + BE_GetBranchTagEx(ctx.branch) + " | Closure=" + closureStr +
                  " | Bias=" + bias + " | Liquidity=" + liquidityTier, LOG_LEVEL_DEBUG, LOG_CHANNEL_PIPELINE);
      }

    result.rationale = "[BRANCH " + GetBranchName(ctx.branch) + "] " +
                      "Mode=" + MR_ModeToString(ctx.mode.mode);

   return result;
}

//+------------------------------------------------------------------+
//| BRANCH COMPARISON (OPTIONAL)                                     |
//+------------------------------------------------------------------+

/**
 * BE_CompareBranches — Compare branch results
 *
 * @param symbol Symbol (for logging)
 * @return string Comparison summary
 */
string BE_CompareBranches(const string symbol)
{
   BranchContext ctxA = BE_GetBranchAContext();
   BranchContext ctxB = BE_GetBranchBContext();

   string comparison = "";

   comparison += "BRANCH COMPARISON FOR " + symbol + "\n";
   comparison += "═══════════════════════════════════════\n";

   // Branch A summary
   comparison += "Branch A (Intraday | H4 → M15):\n";
   comparison += "  SSE: " + SSE_StateToString(ctxA.sse.state) + "\n";
   comparison += "  Bias: " + BR_BiasToString(ctxA.bias.bias) + "\n";
   comparison += "  Mode: " + MR_ModeToString(ctxA.mode.mode) + "\n";
   comparison += "  Valid: " + (ctxA.isEvaluated && ctxA.branchLockedSignal.stage != STAGE_NONE ? "YES" : "NO") + "\n";

   comparison += "\n";

   // Branch B summary
   comparison += "Branch B (Swing | H1 → M5):\n";
   comparison += "  SSE: " + SSE_StateToString(ctxB.sse.state) + "\n";
   comparison += "  Bias: " + BR_BiasToString(ctxB.bias.bias) + "\n";
   comparison += "  Mode: " + MR_ModeToString(ctxB.mode.mode) + "\n";
   comparison += "  Valid: " + (ctxB.isEvaluated && ctxB.branchLockedSignal.stage != STAGE_NONE ? "YES" : "NO") + "\n";

   comparison += "\n";

   // Cross-branch analysis
   comparison += "Cross-Branch Analysis:\n";

   // Check for bias alignment
   if(ctxA.bias.bias == ctxB.bias.bias && ctxA.bias.bias != BIAS_NEUTRAL)
   {
      comparison += "  ✓ Bias ALIGNED: " + BR_BiasToString(ctxA.bias.bias) + "\n";
   }
   else if(ctxA.bias.bias != ctxB.bias.bias)
   {
      comparison += "  ✗ Bias DIVERGENT: A=" + BR_BiasToString(ctxA.bias.bias) +
                    " | B=" + BR_BiasToString(ctxB.bias.bias) + "\n";
   }
   else
   {
      comparison += "  - Bias NEUTRAL on both branches\n";
   }

   // Check for mode alignment
   if(ctxA.mode.mode == ctxB.mode.mode && ctxA.mode.mode != MODE_NONE)
   {
      comparison += "  ✓ Mode ALIGNED: " + MR_ModeToString(ctxA.mode.mode) + "\n";
   }
   else if(ctxA.mode.mode != ctxB.mode.mode)
   {
      comparison += "  - Mode DIVERGENT: A=" + MR_ModeToString(ctxA.mode.mode) +
                    " | B=" + MR_ModeToString(ctxB.mode.mode) + "\n";
   }

   return comparison;
}

//+------------------------------------------------------------------+
//| TOP-DOWN CONTEXT GATE                                            |
//| Three-tier structural validation before execution                 |
//| Tier 1: D1 bias (mechanical daily candle rule)                   |
//| Tier 2: HTF confirmation (CISD or C2/C3 closure on structure TF) |
//| Tier 3: LTF CISD at POI (entry TF delivery confirmation)        |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| SContextTracker — Telemetry for top-down context gate exposure   |
//+------------------------------------------------------------------+
struct SContextTracker
{
   BiasType   d1Bias;
   bool       htfCisdConfirmed;
   bool       ltfCisdConfirmed;
   int        activeTier;

   void Reset()
   {
      d1Bias = BIAS_NEUTRAL;
      htfCisdConfirmed = false;
      ltfCisdConfirmed = false;
      activeTier = 0;
   }

   SContextTracker() { Reset(); }
};

SContextTracker g_contextTracker;

/**
 * ValidateTopDownContext — Three-tier top-down context gate
 *
 * Verifies the full top-down context before any signal executes:
 *   Tier 1 — D1 bias derived from the mechanical daily candle rule.
 *            Full gate for Confirmation mode; informational for Anticipation.
 *   Tier 2 — HTF must show confirming CISD or C2/C3 closure in bias direction.
 *            If missing, the signal is rejected immediately.
 *   Tier 3 — LTF must show a CISD at the POI in the signal direction.
 *            If not yet present, signal transitions to STAGE_WAITING_FOR_CISD.
 *
 * @param ctx BranchContext with evaluated signals
 * @param symbol Trading symbol
 * @return true if all three tiers pass, false otherwise
 */
bool ValidateTopDownContext(BranchContext &ctx, const string symbol)
{
    ENUM_EXECUTION_BRANCH branch = ctx.branch;
    int baseIdx = GetSignalStoreIndex(branch);

    for(int i = 0; i < MAX_TOTAL_SIGNALS_PER_BRANCH; i++)
    {
        int idx = baseIdx + i;
        if(!g_hasActiveSignal[idx])
            continue;

        SLockedSignal sig = g_activeSignal[idx];

        // Skip expired/executed signals, or signals already past the gate
        if(sig.stage == STAGE_EXECUTED || sig.stage == STAGE_EXPIRED || sig.stage == STAGE_NONE)
            continue;

        // Skip signals already in READY state (already passed all gates)
        if(sig.stage == STAGE_READY)
            continue;

        // Determine trade direction from signal
        ENUM_DIRECTION signalDir = sig.direction;
        if(signalDir == DIRECTION_NONE)
            continue;

        bool isBullish = (signalDir == DIRECTION_BUY);

        // REGRESSION_GUARD_STAGE_FSM: Explicit tier-tracking booleans for top-down gate
        bool tier1Pass = false;
        bool tier2Pass = false;
        bool tier3Pass = false;

        // ═══════════════════════════════════════════════════════════════
        // TIER 1 — D1 Bias Check
        // REGRESSION_GUARD_C3: C3-upgraded signals take independent C3 gate path
        // ═══════════════════════════════════════════════════════════════
        BiasType d1Bias = DailyClosureBias(symbol);
        bool tier1ModeCheck = true;

        // Confirmation mode (C3): D1 bias alignment is REQUIRED
        // REGRESSION_GUARD_C3: closureType already set to CLOSURE_C3 for upgraded signals
      if((sig.closureType == CLOSURE_C3) || ctx.mode.mode == MODE_CONFIRMATION)
        {
            LogPrint("[C3_CONTEXT] GUID=" + IntegerToString(sig.m_guid) +
                     " checking D1 bias=" + EnumToString(d1Bias) +
                     " signal_dir=" + (isBullish ? "BUY" : "SELL"), LOG_LEVEL_INFO);

            tier1ModeCheck = (isBullish && d1Bias == BIAS_BULLISH) ||
                             (!isBullish && d1Bias == BIAS_BEARISH);

            if(!tier1ModeCheck)
            {
                LogPrint("[C3_REJECT] D1_BIAS_MISMATCH | GUID=" + IntegerToString(sig.m_guid) +
                         " D1=" + EnumToString(d1Bias) +
                         " signal=" + (isBullish ? "BUY" : "SELL"), LOG_LEVEL_WARN);
                g_activeSignal[idx].TransitionStage(STAGE_EXPIRED);
                LogPrint("[CONTEXT_EXPIRED] GUID=" + IntegerToString(sig.m_guid) +
                         " | reason=C3_Tier1_FAIL | signal=" + (isBullish ? "BULL" : "BEAR"), LOG_LEVEL_INFO);
                continue;
            }

            // REGRESSION_GUARD_C3_BIAS: Log when C3 passes D1 bias alignment
            LogPrint("[C3_BIAS_ALIGN_PASS] GUID=" + IntegerToString(sig.m_guid) +
                     " | signal=" + (isBullish ? "BULL" : "BEAR") +
                     " | d1Bias=" + EnumToString(d1Bias) +
                     " | Tier1 C3 confirmation bias check passed", LOG_LEVEL_INFO);
        }
        else
        {
            // Anticipation mode (C2): D1 bias is informational only
            LogPrint("[CONTEXT] Tier1_INFO | GUID=" + IntegerToString(sig.m_guid) +
                     " | C2 Anticipation | signal=" + (isBullish ? "BULL" : "BEAR") +
                     " | d1Bias=" + EnumToString(d1Bias), LOG_LEVEL_INFO);
        }

        LogPrint("[CONTEXT] Tier1_PASS | GUID=" + IntegerToString(sig.m_guid) +
                 " | d1Bias=" + EnumToString(d1Bias) +
                 " | signal=" + (isBullish ? "BULL" : "BEAR"), LOG_LEVEL_INFO);
        tier1Pass = true;

        // ═══════════════════════════════════════════════════════════════
        // TIER 2 — HTF Confirmation Check
        // ═══════════════════════════════════════════════════════════════
        ENUM_TIMEFRAMES htfTf = ctx.structureTF;
        bool htfCisd = SSE_DetectCISD(symbol, htfTf, signalDir, 20);
        bool htfClosureAligned = false;

        // Also check the structure signal for alignment
        if(ctx.structureSignal.valid)
        {
            htfClosureAligned = (isBullish && ctx.structureSignal.is_bullish) ||
                                (!isBullish && !ctx.structureSignal.is_bullish);
        }

      if(sig.closureType == CLOSURE_C3)
        {
            LogPrint("[C3_CONTEXT] GUID=" + IntegerToString(sig.m_guid) +
                     " HTF_CISD=" + (htfCisd ? "PASS" : "WAIT"), LOG_LEVEL_INFO);

            if(htfCisd)
                LogPrint(StringFormat("[CISD_CONFIRMED] C3 context gate | GUID=%I64u | HTF_CISD=CONFIRMED", sig.m_guid), LOG_LEVEL_INFO);
        }

        if(!htfCisd && !htfClosureAligned)
        {
            if(sig.closureType == CLOSURE_C3)
            {
                LogPrint("[C3_REJECT] HTF_CONFIRMATION_MISSING | GUID=" + IntegerToString(sig.m_guid) +
                         " | htfTf=" + EnumToString(htfTf), LOG_LEVEL_WARN);
                g_activeSignal[idx].TransitionStage(STAGE_WAITING_FOR_CISD);
                LogPrint("[CONTEXT_EXPIRED] GUID=" + IntegerToString(sig.m_guid) +
                         " | reason=C3_Tier2_WAIT | htfTf=" + EnumToString(htfTf), LOG_LEVEL_INFO);
                continue;
            }
            LogPrint("[CONTEXT] Tier2_FAIL | GUID=" + IntegerToString(sig.m_guid) +
                     " | HTF_CONFIRMATION_MISSING" +
                     " | htfTf=" + EnumToString(htfTf) +
                     " | cisd=" + (htfCisd ? "T" : "F") +
                     " | closureAligned=" + (htfClosureAligned ? "T" : "F") +
                     " | action=REJECTED", LOG_LEVEL_WARN);
            g_activeSignal[idx].TransitionStage(STAGE_EXPIRED);
            LogPrint("[CONTEXT_EXPIRED] GUID=" + IntegerToString(sig.m_guid) +
                     " | reason=Tier2_FAIL | htfTf=" + EnumToString(htfTf), LOG_LEVEL_INFO);
            continue;
        }

        LogPrint("[CONTEXT] Tier2_PASS | GUID=" + IntegerToString(sig.m_guid) +
                 " | htfTf=" + EnumToString(htfTf) +
                 " | cisd=" + (htfCisd ? "T" : "F") +
                 " | closure=" + (htfClosureAligned ? "T" : "F"), LOG_LEVEL_INFO);
        tier2Pass = true;

        // ═══════════════════════════════════════════════════════════════
        // TIER 3 — LTF CISD at POI
        // ═══════════════════════════════════════════════════════════════
        ENUM_TIMEFRAMES entryTf = ctx.entryTF;
        bool ltfCisd = SSE_DetectCISD(symbol, entryTf, signalDir, 15);

      if(sig.closureType == CLOSURE_C3)
      {
         LogPrint("[C3_CONTEXT] GUID=" + IntegerToString(sig.m_guid) +
                " LTF_CISD=" + (ltfCisd ? "PASS" : "WAIT"), LOG_LEVEL_INFO);
      }

        if(!ltfCisd)
        {
            LogPrint("[CONTEXT] Tier3_WAIT | GUID=" + IntegerToString(sig.m_guid) +
                     " | LTF CISD not yet present" +
                     " | entryTf=" + EnumToString(entryTf) +
                     " | signal=" + (isBullish ? "BULL" : "BEAR") +
                     " | stage=STAGE_WAITING_FOR_CISD", LOG_LEVEL_INFO);

            // Signal must wait for LTF CISD
            g_activeSignal[idx].TransitionStage(STAGE_WAITING_FOR_CISD);
            continue;
        }

        LogPrint("[CONTEXT] Tier3_PASS | GUID=" + IntegerToString(sig.m_guid) +
                 " | LTF CISD confirmed on " + EnumToString(entryTf) +
                 " | stage=" + EnumToString(sig.stage), LOG_LEVEL_INFO);
        tier3Pass = true;

        // ═══════════════════════════════════════════════════════════════
        // ALL THREE TIERS PASSED
        // ═══════════════════════════════════════════════════════════════
        // REGRESSION_GUARD_STAGE_FSM: Branch-aware transition per TTFM top-down
      bool isC3 = (sig.closureType == CLOSURE_C3);
        if((g_activeSignal[idx].stage == STAGE_WAITING_FOR_POI || g_activeSignal[idx].stage == STAGE_WAITING_FOR_CISD)
           && tier1Pass && tier2Pass && tier3Pass)
        {
            g_activeSignal[idx].TransitionStage(STAGE_READY);
            PrintFormat("[STAGE_READY] GUID=%I64u branch=%s closure=%s", sig.m_guid,
                        (branch==BRANCH_INTRADAY)?"A (D1-H1-M5)":"B (D1-H4-M15)",
                        GetClosureTypeString(sig.closureType));

            if(sig.closureType == CLOSURE_C3)
            {
               LogPrint("[C3_READY] GUID=" + IntegerToString(sig.m_guid) +
                      " all context aligned -> STAGE_READY", LOG_LEVEL_INFO);
            }
        }

        LogPrint("[CONTEXT] TOP_DOWN_CONTEXT_PASS | GUID=" + IntegerToString(sig.m_guid) +
                 " | All three tiers confirmed | branch=" + (branch == BRANCH_INTRADAY ? "A" : "B"), LOG_LEVEL_INFO);

        // Populate context tracker for telemetry exposure
        g_contextTracker.d1Bias = d1Bias;
        g_contextTracker.htfCisdConfirmed = htfCisd;
        g_contextTracker.ltfCisdConfirmed = ltfCisd;
        g_contextTracker.activeTier = 3;

        if(htfCisd)
            LogPrint(StringFormat("[CISD_CONFIRMED] C3 top-down gate | GUID=%I64u | HTF_CISD=CONFIRMED", sig.m_guid), LOG_LEVEL_INFO);
    }

    // Tier gate telemetry exposure
    string d1BiasStr = (g_contextTracker.d1Bias == BIAS_BULLISH) ? "BULLISH" : ((g_contextTracker.d1Bias == BIAS_BEARISH) ? "BEARISH" : "ORDERFLOW_FLUID");
    string htfCisdStr = g_contextTracker.htfCisdConfirmed ? "CONFIRMED" : "WAITING_STRUCT_SHIFT";
    string ltfCisdStr = g_contextTracker.ltfCisdConfirmed ? "ALIGN_VALID" : "NO_ALIGNMENT";

    LogPrint("[CONTEXT] Top-Down Gate Passed | D1_BIAS=" + d1BiasStr + " | HTF_CISD=" + htfCisdStr + " | LTF_CISD=" + ltfCisdStr + " | Active Tier=" + IntegerToString(g_contextTracker.activeTier), LOG_LEVEL_INFO);

    // REGRESSION_GUARD_V52_5_C3_CONTEXT: C3-specific markers added
    return true;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+

#endif // OMAK_BRANCHEVALUATOR_MQH
