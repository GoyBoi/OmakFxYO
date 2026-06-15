//+------------------------------------------------------------------+
//|                                                        Router.mqh |
//|                           OmakFxYO — Sibling-Independent Router   |
//|                                                                  |
//| SINGLE ROUTING AUTHORITY — All C2/C3 stage advancement flows     |
//| through DispatchRegistry(). No duplicate paths exist.            |
//|                                                                  |
//| VERBATIM REPAIR: Sibling Independence Law (§III)                 |
//| C2 and C3 are dispatched through independent pools to prevent    |
//| cross-species contamination in shared memory.                    |
//+------------------------------------------------------------------+
#ifndef OMAK_ROUTER_MQH
#define OMAK_ROUTER_MQH

#property strict

#include <OmakFxYO/core/CoreTypes.mqh>
#include <OmakFxYO/core/LogGovernor.mqh>
#include <OmakFxYO/core/UniversalConfig.mqh>
#include <OmakFxYO/core/ClosureEngine.mqh>

//+------------------------------------------------------------------+
//| DispatchRegistry — Process one signal pool independently         |
//| Each species (C2/Anticipation, C3/Confirmation) owns its own     |
//| invalidation rules and target logic (§XXI).                      |
//| Pool is processed as an isolated pipeline — no cross-species     |
//| contamination is permitted.                                      |
//|                                                                  |
//| ctx provides branch context for metadata (poiWaitBarStart,       |
//| branchLockedSignal reference).                                    |
//+------------------------------------------------------------------+
void DispatchRegistry(SLockedSignal &pool[], int mode, BranchContext &ctx)
{
    for (int idx = 0; idx < MAX_SLOTS; idx++)
    {
        if (pool[idx].m_guid == 0 || pool[idx].stage == STAGE_NONE) continue;
        if (pool[idx].stage == STAGE_EXPIRED || pool[idx].isCommitted) continue;

        // ── ANTICIPATION MODE: Route C2 reversal signals ──
        if (mode == MODE_ANTICIPATION)
        {
            if (pool[idx].stage != STAGE_LOCKED) continue;
            if (pool[idx].closureType != CLOSURE_C2)
            {
                LogPrint("[FAMILY_GUARD] C2 lock blocked — slot belongs to Confirmation family | slot=" +
                         IntegerToString(idx) + " existing=" + EnumToString(pool[idx].closureType), LOG_LEVEL_ERROR);
                continue;
            }
            uint secondsSinceLock = (uint)(TimeCurrent() - pool[idx].lockTime);
            if (secondsSinceLock < (uint)PeriodSeconds(pool[idx].entryTF)) continue;
            if (!pool[idx].TransitionStage(STAGE_WAITING_FOR_POI)) continue;
            ENUM_TIMEFRAMES handoverTF = (ctx.branch == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;
            pool[idx].poiWaitBarStart = iBars(pool[idx].symbol, handoverTF);
            ctx.branchLockedSignal = pool[idx];
            LogPrint(StringFormat("[DISPATCH_C2] GUID=%I64u | LOCKED -> POI_WAIT | slot=%d", pool[idx].m_guid, idx), LOG_LEVEL_INFO);
        }

        // ── CONFIRMATION MODE: Route C3 continuation signals ──
        if (mode == MODE_CONFIRMATION)
        {
            if (pool[idx].stage != STAGE_AWAITING_C3_CLOSURE) continue;
            uint secondsSinceLock = (uint)(TimeCurrent() - pool[idx].lockTime);
            if (secondsSinceLock < (uint)PeriodSeconds(pool[idx].entryTF)) continue;
            if (!pool[idx].TransitionStage(STAGE_WAITING_FOR_POI)) continue;
            LogPrint(StringFormat("[DISPATCH_C3] GUID=%I64u | AWAITING_CLOSURE -> POI_WAIT | slot=%d", pool[idx].m_guid, idx), LOG_LEVEL_INFO);
        }
    }
}

//+------------------------------------------------------------------+
//| TickRouter — Independent dispatch for C2 and C3 signal pools     |
//|                                                                  |
//| C2 reversal trades and C3 continuation setups are scanned and    |
//| processed through entirely separate registries. A C2 reversal    |
//| trade must never block or clear the scanner window for a C3      |
//| continuation setup in the same expansion candle.                 |
//+------------------------------------------------------------------+
void TickRouter(BranchContext &ctx)
{
    DispatchRegistry(g_activeC2, MODE_ANTICIPATION, ctx);
    DispatchRegistry(g_activeC3, MODE_CONFIRMATION, ctx);
    DispatchC4Registry(g_activeC4, ctx);
}

//+------------------------------------------------------------------+
//| DispatchC4Registry — Route C4 continuation signals independently  |
//| C4 starts at STAGE_C4_WAITING and advances to STAGE_C4_DETECTED   |
//| after one entry TF bar. CISD evaluation occurs downstream in the  |
//| pipeline (ProcessPipelineSignal).                                 |
//+------------------------------------------------------------------+
void DispatchC4Registry(SLockedSignal &pool[], BranchContext &ctx)
{
    for (int idx = 0; idx < MAX_C4_SLOTS; idx++)
    {
        if (pool[idx].m_guid == 0 || pool[idx].stage == STAGE_NONE) continue;
        if (pool[idx].stage == STAGE_EXPIRED || pool[idx].isCommitted) continue;

        // C4: STAGE_C4_WAITING -> STAGE_C4_DETECTED after 1 bar
        if (pool[idx].stage == STAGE_C4_WAITING)
        {
            uint secondsSinceLock = (uint)(TimeCurrent() - pool[idx].lockTime);
            if (secondsSinceLock < (uint)PeriodSeconds(pool[idx].entryTF)) continue;
            if (!pool[idx].TransitionStage(STAGE_C4_DETECTED)) continue;
            LogPrint(StringFormat("[DISPATCH_C4] GUID=%I64u | C4_WAITING -> C4_DETECTED | slot=%d", pool[idx].m_guid, idx), LOG_LEVEL_DEBUG);
        }
    }
}

#endif // OMAK_ROUTER_MQH
