//+------------------------------------------------------------------+
//|                                           TradeContext.mqh       |
//|                                      OmakFxYO — Trade Context |
//+------------------------------------------------------------------+
#ifndef OMAK_TRADECONTEXT_MQH
#define OMAK_TRADECONTEXT_MQH

#include <OmakFxYO/core/CoreTypes.mqh>
#include <OmakFxYO/core/BranchRouter.mqh>  // For SBranchTimeframes
#include <OmakFxYO/core/SymbolIntelligence.mqh>  // For SY_GetProfile

// Forward declaration for global defined in OmakFxYO.mq5
extern SBranchTimeframes g_branchTF;

struct STradeContext
{
    int    tradeId;
    string signalId;

    double baseLot;
    double currentLot;

    string stage;
    bool   isActive;
    bool   isExecuted;
    bool   isFailed;

    double minLot;
    double maxLot;
    double step;

    string symbol;
    ENUM_SIGNAL_DIRECTION direction;
    double stopLoss;
    double takeProfit;

    datetime createdAt;
    datetime executedAt;
};

static STradeContext g_trade;
static int g_globalTradeId = 0;
static bool g_tradeInitialized = false;

int TC_GetNextTradeId()
{
    return g_globalTradeId + 1;
}

void TC_CommitTradeId()
{
    if(g_trade.currentLot <= 0.0)
        return;

    SSymbolProfile spCommit = SY_GetProfile(g_trade.symbol);
    double minLot = spCommit.volumeMin;
    if(minLot <= 0.0)
        return;

    if(g_trade.currentLot >= minLot)
    {
        g_globalTradeId++;
        g_trade.tradeId = g_globalTradeId;
    }
}

void TC_InitTrade(string p_signalId, string symbol, ENUM_SIGNAL_DIRECTION direction)
{
    ZeroMemory(g_trade);
    g_trade.signalId = p_signalId;
    g_trade.tradeId = TC_GetNextTradeId();
    g_trade.symbol = symbol;
    g_trade.direction = direction;

    SSymbolProfile spCtx = SY_GetProfile(symbol);
    g_trade.minLot = spCtx.volumeMin;
    g_trade.maxLot = spCtx.volumeMax;
    g_trade.step = spCtx.volumeStep;

    // CONTRACT: invalid constraints produce invalid context - no fallbacks
    if(g_trade.minLot <= 0.0 || g_trade.step <= 0.0)
    {
        g_trade.isActive = false;
        LogPrint(StringFormat("[TC_INIT_FAIL] Symbol=%s | minLot=%.5f | step=%.5f | Reason=INVALID_VOLUME_CONSTRAINTS",
                    symbol,
                    g_trade.minLot,
                    g_trade.step), LOG_LEVEL_ERROR);
        return;
    }

    g_trade.baseLot = 0.0;
    g_trade.currentLot = 0.0;
    g_trade.stage = "INIT";
    g_trade.isActive = true;
    g_trade.isExecuted = false;
    g_trade.isFailed = false;
    g_trade.stopLoss = 0.0;
    g_trade.takeProfit = 0.0;
    g_trade.createdAt = TimeCurrent();
    g_trade.executedAt = 0;

    g_tradeInitialized = true;

    TraceLot("INIT");
}

bool TC_SetStage(string newStage)
{
    if(!g_tradeInitialized || !g_trade.isActive)
        return false;

    g_trade.stage = newStage;
    return true;
}

void TC_SetBaseLot(double lot)
{
    if(!g_tradeInitialized)
        return;

    g_trade.baseLot = lot;
    g_trade.currentLot = lot;
}

void TC_SetSnapshotConstraints(double minLot, double maxLot, double lotStep)
{
    if(!g_tradeInitialized)
        return;

    g_trade.minLot = minLot;
    g_trade.maxLot = maxLot;
    g_trade.step = lotStep;
}

void TC_SetCurrentLot(double lot)
{
    if(!g_tradeInitialized)
        return;

    g_trade.currentLot = lot;
}

void TC_SetSLTP(double sl, double tp)
{
    if(!g_tradeInitialized)
        return;

    g_trade.stopLoss = sl;
    g_trade.takeProfit = tp;
}

void TraceLot(string stage)
{
   if(!g_tradeInitialized)
      return;

   // Align with execution timeframe (CRITICAL FIX)
   datetime currentBar = iTime(_Symbol, g_branchTF.entryTF, 0);

   // Per-bar + per-stage suppression
   static datetime s_lastBar = 0;
   static string   s_lastStage = "";
   static string   s_lastSignal = "";

   if(currentBar == s_lastBar &&
      stage == s_lastStage &&
      g_trade.signalId == s_lastSignal)
      return;

   s_lastBar   = currentBar;
   s_lastStage = stage;
   s_lastSignal = g_trade.signalId;

LogPrint("[LOT_DIAG] ID=" + IntegerToString(g_trade.tradeId) +
          " SIGNAL=" + g_trade.signalId +
          " STAGE=" + stage +
          " LOT=" + DoubleToString(g_trade.currentLot, 4) +
          " BASE=" + DoubleToString(g_trade.baseLot, 4), LOG_LEVEL_DEBUG);
}

bool TC_IsValid()
{
    return g_tradeInitialized && g_trade.isActive && !g_trade.isFailed;
}

bool TC_LockExecuted()
{
    if(!g_tradeInitialized)
        return false;

    g_trade.isExecuted = true;
    g_trade.stage = "EXECUTED";
    g_trade.executedAt = TimeCurrent();

    TraceLot("LOCKED");

    return true;
}

bool TC_IsExecuted()
{
    return g_tradeInitialized && g_trade.isExecuted;
}

void TC_MarkFailed(string failStage)
{
    if(!g_tradeInitialized)
        return;

    g_trade.stage = "FAILED_" + failStage;
    g_trade.isActive = false;
    g_trade.isFailed = true;

    LogPrint("[TRADE_FAIL] ID=" + IntegerToString(g_trade.tradeId) +
          " STAGE=" + g_trade.stage +
          " LOT=" + DoubleToString(g_trade.currentLot, 4), LOG_LEVEL_WARN);

    g_tradeInitialized = false;
}

void TC_Reset()
{
    ZeroMemory(g_trade);
    g_trade.isActive   = false;
    g_trade.isFailed   = false;
    g_trade.isExecuted = false;
    g_tradeInitialized = false;
}

int TC_GetTradeId()
{
    return g_trade.tradeId;
}

double TC_GetCurrentLot()
{
    return g_trade.currentLot;
}

double TC_GetMinLot()
{
    return g_trade.minLot;
}

double TC_GetMaxLot()
{
    return g_trade.maxLot;
}

double TC_GetStep()
{
    return g_trade.step;
}

string TC_GetSymbol()
{
    return g_trade.symbol;
}

ENUM_SIGNAL_DIRECTION TC_GetDirection()
{
    return g_trade.direction;
}

double TC_GetSL()
{
    return g_trade.stopLoss;
}

double TC_GetTP()
{
    return g_trade.takeProfit;
}

#endif