//+------------------------------------------------------------------+
//|                                          Determinism.mqh        |
//|                                    OmakFxYO — Determinism Layer |
//+------------------------------------------------------------------+
#ifndef OMAK_DETERMINISM_MQH
#define OMAK_DETERMINISM_MQH

#include <OmakFxYO/core/CoreTypes.mqh>
#include <OmakFxYO/core/TradeContext.mqh>
#include <OmakFxYO/core/LogGovernor.mqh>
#include <OmakFxYO/core/SymbolIntelligence.mqh>  // For SY_GetProfile

static int g_executionSeed = 0;
static bool g_determinismInitialized = false;

void DET_Init()
{
    if(g_determinismInitialized)
        return;
    
    string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);
    long accountLogin = AccountInfoInteger(ACCOUNT_LOGIN);
    
    g_executionSeed = (int)accountLogin;
    
    for(int i = 0; i < StringLen(accountCurrency); i++)
    {
        ushort ch = StringGetCharacter(accountCurrency, i);
        g_executionSeed = g_executionSeed * 31 + (int)ch;
    }
    
    long serverTime = TimeCurrent();
    g_executionSeed = g_executionSeed ^ ((int)(serverTime / 86400));
    
g_determinismInitialized = true;
     
     LogPrint("[DETERMINISM] Initialized | Seed=" + IntegerToString(g_executionSeed), LOG_LEVEL_INFO);
}

int DET_GetSeed()
{
    if(!g_determinismInitialized)
        DET_Init();
    
    return g_executionSeed;
}

int DET_HashString(string str)
{
    int hash = 0;
    
    for(int i = 0; i < StringLen(str); i++)
    {
        ushort ch = StringGetCharacter(str, i);
        hash = hash * 31 + (int)ch;
    }
    
    return hash;
}

int DET_HashValues(double v1, double v2, double v3)
{
    int h1 = (int)(v1 * 1000000.0);
    int h2 = (int)(v2 * 1000000.0);
    int h3 = (int)(v3 * 1000000.0);
    
    return (h1 * 73856093) ^ (h2 * 19349663) ^ (h3 * 83492791);
}

int DET_DeterministicValue(string signalId, int extraSeed = 0)
{
    if(!g_determinismInitialized)
        DET_Init();
    
    int signalHash = DET_HashString(signalId);
    int seed = g_executionSeed + extraSeed;
    
    return signalHash ^ seed;
}

bool DET_IsStageExpected(string expectedStage)
{
    if(!TC_IsValid())
        return false;
    
    return (g_trade.stage == expectedStage);
}

bool DET_ValidateStageOrder(string targetStage, string expectedCurrentStage)
{
    if(!TC_IsValid())
        return false;
    
    // STAGE JUMP: Allow READY -> EXECUTION for fast C3 triggers on M5/M15
    if(targetStage == "EXECUTION" && (g_trade.stage == "READY" || g_trade.stage == "VALIDATION"))
    {
        return true;
    }
    
    if(expectedCurrentStage != "")
     {
         if(g_trade.stage != expectedCurrentStage)
         {
             LogPrint("[DETERMINISM] Stage order violation | Expected=" + expectedCurrentStage + 
                   " Got=" + g_trade.stage, LOG_LEVEL_DEBUG);
             return false;
         }
     }
    
    return true;
}

double DET_QuantizeLot(double lot, string symbol)
{
    if(lot <= 0.0)
        return 0.0;
    
    SSymbolProfile spDet = SY_GetProfile(symbol);
    double step = spDet.volumeStep;
    if(step <= 0.0)
    {
        LogPrint("[DET_QUANTIZE_FAIL] volumeStep invalid | symbol=" + symbol +
                 " | step=" + DoubleToString(step, 6), LOG_LEVEL_WARN);
        return 0.0;
    }
    
    int digits = 0;
    double stepTemp = step;
    while(stepTemp < 1.0 && digits < 8)
    {
        stepTemp *= 10.0;
        digits++;
    }
    if(digits < 0)
        digits = 0;
    
    LogPrint("[DET_QUANTIZE] lot=" + DoubleToString(lot, 6) +
             " | step=" + DoubleToString(step, 6) +
             " | digits=" + IntegerToString(digits), LOG_LEVEL_DEBUG);
    
    return NormalizeDouble(MathFloor(lot / step) * step, digits);
}

double DET_QuantizePrice(double price, string symbol)
{
    SSymbolProfile spPrice = SY_GetProfile(symbol);
    int digits = spPrice.digits;
    if(digits <= 0)
        digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    if(digits <= 0)
        digits = 5;
    return NormalizeDouble(price, digits);
}

string DET_GetExpectedStage(string currentStage)
{
    if(currentStage == "INIT")
        return "BASE";
    if(currentStage == "BASE")
        return "PORTFOLIO";
    if(currentStage == "PORTFOLIO")
        return "SCALING";
    if(currentStage == "SCALING")
        return "VALIDATION";
    if(currentStage == "VALIDATION")
        return "EXECUTION";
    if(currentStage == "EXECUTION")
        return "LOCKED";
    
    return "";
}

bool DET_AdvanceStage(string nextStage)
{
    if(!TC_IsValid())
        return false;
    
if(!DET_ValidateStageOrder(nextStage, DET_GetExpectedStage(g_trade.stage)))
     {
         LogPrint("[DETERMINISM] Cannot advance to " + nextStage + 
               " from " + g_trade.stage, LOG_LEVEL_DEBUG);
         return false;
     }
     
     TC_SetStage(nextStage);
     return true;
}

void DET_LogSnapshot(string additionalInfo = "")
{
     if(!TC_IsValid())
     {
         LogPrint("[EXEC_SNAPSHOT] Context not initialized", LOG_LEVEL_DEBUG);
         return;
     }
    
    LogPrint("[EXEC_SNAPSHOT] SEED=" + IntegerToString(g_executionSeed) +
           " ID=" + IntegerToString(g_trade.tradeId) +
           " SIGNAL=" + g_trade.signalId +
           " STAGE=" + g_trade.stage +
           " LOT=" + DoubleToString(g_trade.currentLot, 4) +
           " BASE=" + DoubleToString(g_trade.baseLot, 4) +
           " " + additionalInfo, LOG_LEVEL_DEBUG);
}

bool DET_IsExecutedLocked()
{
    if(!TC_IsValid())
        return false;
    
    if(TC_IsExecuted())
        return true;
    
    return (g_trade.stage == "LOCKED" || g_trade.stage == "EXECUTED");
}

void DET_EnsureImmutable()
{
    if(!TC_IsValid())
        return;
    
if(DET_IsExecutedLocked())
     {
         LogPrint("[DETERMINISM] WARNING: Attempted modification after execution lock | Stage=" + g_trade.stage, LOG_LEVEL_WARN);
     }
}

#endif