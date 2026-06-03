//+------------------------------------------------------------------+
//|                                      Telemetry.mqh |
//|                      OmakFxYO Telemetry |
//+------------------------------------------------------------------+
#ifndef OMAK_TELEMETRY_MQH
#define OMAK_TELEMETRY_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"

// Minimal telemetry state - only used by TEL_Initialize
struct TelemetryContext
{
   bool enabled;
   bool logStateChanges;
   bool logTradeDecisions;
   bool logBranchEvaluations;
   int totalLogs;
   int stateChangeCount;
   int tradeDecisionCount;
   datetime lastLogTime;

   void Reset()
   {
      enabled = true;
      logStateChanges = true;
      logTradeDecisions = true;
      logBranchEvaluations = true;
      totalLogs = 0;
      stateChangeCount = 0;
      tradeDecisionCount = 0;
      lastLogTime = 0;
   }
};

TelemetryContext g_telContext;

//+------------------------------------------------------------------+
//| TEL_Initialize — Initialize Telemetry                               |
//+------------------------------------------------------------------+
bool TEL_Initialize(
   bool enabled = true,
   bool logStateChanges = true,
   bool logTradeDecisions = true,
   bool logBranchEvaluations = true
)
{
   g_telContext.Reset();
   g_telContext.enabled = enabled;
   g_telContext.logStateChanges = logStateChanges;
   g_telContext.logTradeDecisions = logTradeDecisions;
   g_telContext.logBranchEvaluations = logBranchEvaluations;

   LogPrint("[ANALYSIS] Telemetry initialized", LOG_LEVEL_INFO);
   return true;
}

#endif // OMAK_TELEMETRY_MQH