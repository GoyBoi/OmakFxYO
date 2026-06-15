//═══════════════════════════════════════════════════════════════
//  Omak FxYO — Algorithmic Trading EA
//
//  Strategy:  TTrades Fractal Model + Dow Theory
//  Branch A (Intraday):  D1 → H1 → M5
//  Branch B (Swing):     W1 → H4 → M15
//  Modes:     Anticipation Mode | Confirmation Mode
//
//  Version:   1.0.0
//  Versioning: MAJOR.MINOR.PATCH
//    PATCH → bug fix, no logic change
//    MINOR → new feature or module added
//    MAJOR → architectural or strategy logic change
//═══════════════════════════════════════════════════════════════
#property copyright   "Omak FxYO"
#property link        ""
#property version     "1.00"
#property description "Omak FxYO — TTrades Fractal Model + Dow Theory"
#property description "Branch A: D1→H1→M5 | Branch B: W1→H4→M15"
#property description "Anticipation Mode | Confirmation Mode"
#property strict

//+------------------------------------------------------------------+
 //| SEQUENCE 1: TYPES & CORE                                          |
 //+------------------------------------------------------------------+
 #include <OmakFxYO/core/CoreTypes.mqh>    // All enums, structs, LiquidityTier, etc.

 //+------------------------------------------------------------------+
 //| SEQUENCE 2: RAW INPUT PARAMETERS (before macro activation)      |
 //+------------------------------------------------------------------+

 input ENUM_EXECUTION_BRANCH InpBranch = BRANCH_INTRADAY;  // BRANCH_INTRADAY=Branch A (D1/H1/M5), BRANCH_SWING=Branch B (D1/H4/M15)
input ENUM_ACTIVE_BRANCH InpActiveBranch = BRANCH_A;  // Active branch: A=Intraday(D1/H1/M5), B=Swing(W1/H4/M15)
 input double InpRiskPercent = 1.0;
input double InpMaxMinLotRiskPercent = 20.0; // Affordability bridge: max minLot risk % for symbol tradeability gating
input double InpMaxRiskDeviation = 0.25; // Max allowed risk deviation after lot adjustment (%)
    input double InpMinStopBuffer = 1.0;      // Minimum SL buffer as multiplier of broker's SYMBOL_TRADE_STOPS_LEVEL (0=use broker minimum)
  input int InpMaxPoiWaitBars = 10;         // Max bars to wait for POI touch before expiring (PROMPT_E3: was 5)
  input int    InpMagicNumber = 88001;
 input bool   InpEnableTrace = true;

 input bool   InpUsePipelineGate = true;  // Use pipeline as execution gate
 input ENUM_LOG_LEVEL InpLogLevel = LOG_LEVEL_INFO; // Log verbosity level
  input int InpMaxLogsPerSession = 1000000;  // Session log cap
  input int InpMaxLogsPerBar = 5000;          // Logs per bar cap (0 = unlimited)

// --- DISCIPLINE GATES ---
  input double InpMinFreeMarginRatio  = 1.5;   // Minimum free margin ratio (FreeMargin / MarginRequired)
  input double InpMaxDailyLossPercent = 5.0;             // Max daily loss % of balance before trading halts
  input double InpCatastrophicFloorPercent = 20.0;  // Static drawdown: % of initial deposit (hard floor)
   input double InpDynamicFloorPercent = 0.0;          // Secondary floor: % of 30-day peak equity (0 = disable)
   input int    InpMinTradeAgeMinutes = 60;            // No guard closure before this age
   input int    InpTradeCooldownSeconds = 60;           // Cooldown seconds after trade execution
   input bool   InpBlockNewEntriesOnDailyLoss = true;   // Block new entries when daily loss limit hit
input bool   InpGuardManualReset = false;            // Manual reset trigger for PERMANENT halt

// --- POSITION MANAGEMENT ---
  input double InpBE_R_Multiple = 1.0;    // Move SL to entry after X*R profit (1.0 = 1R)
  input int InpTrailingStart = 0;       // Start trailing after Y points profit (disabled)
  input int InpTrailingStep = 0;        // Trail SL by Z points (disabled)
  input int InpMinTradeAgeSeconds = 10; // Minimum age before any SL modification
  input int InpMaxTradeDurationDays = 5; // Emergency close after N days (0=disabled)

//--- True TTrades Enhancement Inputs (PHASE 3 - Enabled)
input bool   InpUseTrueTTradesMode = true;           // Enable true TTrades HTF-LTF alignment
input ENUM_TIMEFRAMES InpTradingStyle = PERIOD_H4;    // Trading style: H4=Swing, H1=Daytrade, M15=Scalp
input double InpMaxC2WickPercent = 0.6;               // Max C2 wick ratio (0.6 = 60%) — triggers "wait for C3"
input bool   InpUseVolumeConfirmation = false;        // [PHASE 3] Enable volume filter for C3
 input double InpMinVolumeExpansion = 120.0;           // Min volume % increase for C3 (100=baseline)
 



//--- Reversal alignment
input bool   InpAllowLTFLeadReversal = false;         // Allow LTF to signal before HTF reversal starts (aggressive)

//--- Kill Switch
input int    InpTradeGraceSeconds = 60;                // Grace period after trade opens before loss checks
input int    InpMaxConsecutiveLosses = 3;             // Max consecutive losses before trading halts
input int InpMaxSignalsPerBranch = 4;              // Max signals per branch (pyramiding limit - enhanced to 4)

//--- Pyramiding Parameters
input bool   InpEnablePyramiding = true;            // Enable pyramiding (scale into strong moves)
input int    InpMaxPyramidOrders = 2;               // Max additional pyramid orders per direction
input double InpPyramidAdditionalRiskPct = 50.0;   // Additional risk % per pyramid order (vs base trade)
input double InpPyramidRiskFactor = 0.70;           // Declining risk factor per pyramid layer (0.70 = 30% reduction per layer)

//--- PHASE 3: Mode-specific parameters
input double InpAnticipationRR = 2.0;           // Minimum R:R for Anticipation mode
input bool   InpAllowAnticipationReversals = true;      // Allow counter-D1 bias in Anticipation mode
input double InpRiskRewardRatio = 2.0;          // [FIX 5] TP multiplier (1.0=1:1, 2.0=1:2, 3.0=1:3)

//--- Mode-Aware Trade Management Inputs
input double InpBETriggerR_Anticipation = 0.75;   // Move to BE at 0.75R for Anticipation (C2)
input double InpBETriggerR_Confirmation = 1.50;     // Move to BE at 1.50R for Confirmation (C3)
input double InpPartialClosePct_Anticipation = 50.0; // Close 50% at TP1 for Anticipation
input double InpPartialClosePct_Confirmation = 33.0; // Close 33% at TP1 for Confirmation
input double InpTrailOffsetR_Anticipation = 0.50;   // Trail at 0.5R offset for Anticipation
input double InpTrailOffsetR_Confirmation = 1.00;    // Trail at 1.0R offset for Confirmation
input bool   InpHTF_TP_Extension = true;           // Extend TP when HTF bias aligns
input double InpHTF_TP_ExtensionMult = 1.50;       // Multiply TP by 1.5x when aligned

//--- PHASE 4: Volatility & Dynamic Slot parameters
input double InpVolatilityBuffer = 1.5;          // Volatility ratio buffer (1.5 = 50% above baseline)
input bool   InpUseDynamicSlots = true;             // Enable dynamic slot management
input bool   InpAutoExpireOldSignals = true;         // Auto-expire signals older than 24h

 input bool   InpAutoDetectMarketType = true;             // Auto detect market conditions

 //--- C2/C3 Closure Engine thresholds (centralized from ClosureEngine.mqh)
 input double InpAnticipation_Sensitivity = 0.8;         // C2 (Sweep) displacement for Anticipation mode
input double InpC2_SweepTolerancePoints = 0.0;         // Additional tolerance in points for C2 sweep (0=strict, 0.3=relaxed)
input bool   InpUseDisplacementEngine = true;          // master switch
input bool   UseFollowThroughForEntry = true;          // require FT for entry
input int    InpWarmupBars = 10;                       // [P1] Bars to skip at start (tester safety)

//--- Intraday Branch (Branch A): Structure TF = H1 | Entry TF = M5
 input double InpA_C2_WickThreshold          = 0.85;  // [A] Large wick filter (TTrades: >85% kills C2)
 input double InpA_C2_MinWickRatio           = 0.30;  // [A] Min rejection wick ratio
  input double InpA_C2_MinBodyRatio           = 0.20;  // [A] Min intent body ratio
  input double InpA_C2_DisplacementMultiplier = 0.8;   // [A] C2 displacement ATRE multiplier (was 1.0)
  input double InpA_C2_RangeExpansionFactor   = 1.0;   // [A] C2 range expansion (lenient for C2)
  input double InpA_C3_BodyMultiplier         = 1.0;   // [A] C3 engulf body multiplier
 input double InpA_C3_DisplacementMultiplier = 1.2;   // [A] C3 displacement vs avg body
 input double InpA_C3_RangeExpansionFactor   = 1.1;   // [A] C3 range vs prev range
input double InpA_RG_BufferPercent          = 0.03;  // [A] Midpoint buffer %
input double InpA_RG_MarketThreshold        = 0.010; // [A] Market order eligibility %
input double InpA_C2_POI_BufferPercent      = 0.015; // [A] C2 POI buffer (1.5% - wider for anticipation M5)
input double InpA_C3_POI_BufferPercent    = 0.008; // [A] C3 POI buffer (0.8% - tighter for confirmation M5)
input double InpMinBufferPoints          = 0.0;   // [A] Minimum buffer (0=auto-detect per symbol)
input int    InpA_LimitExpirationBars       = 4;     // [A] C4 limit expiry bars (M5)

 //--- Swing Branch (Branch B): Structure TF = H4 | Entry TF = M15
 input double InpB_C2_WickThreshold          = 0.85;  // [B] Large wick filter (TTrades: >85% kills C2)
 input double InpB_C2_MinWickRatio           = 0.25;  // [B] Min rejection wick ratio
  input double InpB_C2_MinBodyRatio           = 0.15;  // [B] Min intent body ratio
  input double InpB_C2_DisplacementMultiplier = 0.7;   // [B] C2 displacement ATRE multiplier
  input double InpB_C2_RangeExpansionFactor   = 1.0;   // [B] C2 range expansion (lenient for C2)
  input double InpB_C3_BodyMultiplier         = 0.9;   // [B] C3 engulf body multiplier
 input double InpB_C3_DisplacementMultiplier = 1.1;   // [B] C3 displacement vs avg body
 input double InpB_C3_RangeExpansionFactor   = 1.05;   // [B] C3 range vs prev range
input double InpB_RG_BufferPercent          = 0.04;  // [B] Midpoint buffer %
input double InpB_RG_MarketThreshold        = 0.012; // [B] Market order eligibility %
input double InpB_C2_POI_BufferPercent      = 0.015; // [B] C2 POI buffer (1.5% - wider for anticipation M15)
input double InpB_C3_POI_BufferPercent      = 0.008; // [B] C3 POI buffer (0.8% - tighter for confirmation M15)
input int    InpB_LimitExpirationBars       = 3;     // [B] C4 limit expiry bars (M15)

 //--- Tick Iterator (latency guard)
 input bool   InpUseTickIterator = false;              // Enable tick-by-tick processing

 //--- Execution Paradox: Limit Orders & Buffer
 input bool   InpUseLimitOrders = true;               // Use limit orders instead of market when price escapes

input int     InpMaxPOIWaitMinutes = 720;          // Max minutes to wait for POI (12 hours, PROMPT_E3: was 480)
input int     InpMaxReadyWaitMinutes = 240;        // Max minutes in STAGE_READY before expiry (4 hours, PROMPT_E3: was 120)
input int     InpMaxSignalAgeBars = 96;                // Max bars to wait before signal expires (PROMPT_E3: was 48)
input int     InpMaxPOIWaitBars = 48;                 // Max bars to wait for POI before expiry (PROMPT_E3: was 36)
input int     InpC2MaxPOIWaitBars = 180;           // Max bars for C2 POI wait — Anticipation (15 hours on M5, PROMPT_E3: was 120)
input int InpC3MaxPOIWaitBars = 360;           // Max bars for C3 POI wait — Confirmation (30 hours on M5, PROMPT_E3: was 240)
input int InpC3MaxPOIWaitMinutes = 720;       // Max minutes for C3 POI wait (12 hours, PROMPT_E3: was 480)
input int InpC3MaxReadyWaitMinutes = 720;     // Max minutes for C3 at STAGE_READY (12 hours, PROMPT_E3: was 480)
input int InpRGReadyRetryWindowMinutes = 120;  // Max minutes for RG retry in STAGE_READY before expiry (2 hours, PROMPT_E3: was 30)
input int InpC3RGReadyRetryWindowMinutes = 480; // Max minutes for C3 RG retry window (8 hours, PROMPT_E3: new)
// REGRESSION_GUARD_V52_5_C3_INPUTS
input int InpMaxCISDWaitMinutes = 120;         // 2 hours for CISD (PROMPT_E3: was 60)
input double  InpConfirmationRR = 2.0;             // C3 minimum RR (NEW)
input double InpC2NearMissPercent = 0.4;         // C2 near-miss threshold (% of buffer distance for fallback)
input bool   InpC2NearMissFallback = true;        // Enable C2 near-miss fallback to STAGE_READY

// Setup-level lifespan parameters
input int    InpSetupLifespanBars_Intraday = 24;   // 2 H1 candles on M5 (PROMPT_E3: was 12)
input int    InpSetupLifespanBars_Swing = 32;     // 2 H4 candles on M15 (PROMPT_E3: was 16)
input int    InpSetupGraceBars = 8;               // orange-state grace period (PROMPT_E3: was 4)

//--- Ongoing Tradeability & TF-Aware Grace 
input int    InpTradeabilityRecheckBars = 5;    // Recheck tradeability every N bars on entry TF (PROMPT_E4)
input int    InpGraceBarsAnticipation = 12;     // Grace bars for C2/Anticipation expiry (PROMPT_E4)
input int    InpGraceBarsConfirmation = 20;     // Grace bars for C3/Confirmation expiry (PROMPT_E4)

//--- Time-Sensitivity Filter (§XVIII — Optional, C2 Only)
input bool   InpEnableTimeFilter = false;       // Enable time-sensitivity filter for C2 (§XVIII)
input double InpTimeFilterThreshold = 0.75;     // C2 time filter threshold (0.5–0.95, default 75%)

//--- Structural Exit Parameters
input bool   InpExit_CRT_Target = true;           // CRT Full Target: close at C1 opposite extreme
input bool   InpExit_CISD_Reversal = true;        // CISD Reversal: close on opposite-direction CISD
input bool   InpExit_Dow_BOS = true;              // Dow BOS: close on HTF trend break

  //+------------------------------------------------------------------+
 //| SEQUENCE 3: GLOBAL VARIABLES (authoritative definitions)          |
 //+------------------------------------------------------------------+
ENUM_EXECUTION_BRANCH g_InpBranch = InpBranch;
int    g_InpMagicNumber = InpMagicNumber;
bool   g_InpEnableTrace = InpEnableTrace;
   bool   g_InpUseDisplacementEngine = InpUseDisplacementEngine;
int    g_InpMaxSignalsPerBranch = InpMaxSignalsPerBranch;
bool   g_InpUseTickIterator = InpUseTickIterator;
ENUM_LOG_LEVEL g_InpLogLevel = InpLogLevel;
bool   g_InpEnablePyramiding = InpEnablePyramiding;
int    g_InpMaxPyramidOrders = InpMaxPyramidOrders;
double g_InpPyramidAdditionalRiskPct = InpPyramidAdditionalRiskPct;
double g_InpPyramidRiskFactor = InpPyramidRiskFactor;

// Setup-level lifespan parameters
   int    g_InpSetupLifespanBars_Intraday = InpSetupLifespanBars_Intraday;
   int    g_InpSetupLifespanBars_Swing = InpSetupLifespanBars_Swing;
   int    g_InpSetupGraceBars = InpSetupGraceBars;
   int    g_InpRGReadyRetryWindowMinutes = InpRGReadyRetryWindowMinutes;
   int    g_InpC3RGReadyRetryWindowMinutes = InpC3RGReadyRetryWindowMinutes;

   // Ongoing tradeability & TF-aware grace (PROMPT_E4)
   int    g_InpTradeabilityRecheckBars = InpTradeabilityRecheckBars;
   int    g_InpGraceBarsAnticipation = InpGraceBarsAnticipation;
   int    g_InpGraceBarsConfirmation = InpGraceBarsConfirmation;
   datetime g_lastTradeabilityCheckBar[2];  // Per-branch last tradeability check bar

   // Time-sensitivity filter (C2 only, §XVIII)
   bool   g_InpEnableTimeFilter = InpEnableTimeFilter;
   double g_InpTimeFilterThreshold = InpTimeFilterThreshold;
   bool   g_symbolUntradeable;              // True when active symbol fails tradeability
   string g_symbolUntradeableReason;        // Reason for untradeable state
   string g_permanentSkipSymbols[];         // PERMANENT_SKIP list per AGENTS.md §XII
   int    g_permanentSkipCount;

   // First-bar warmup guard ---
 int g_warmupBarsCounted = 0;     // Runtime counter
bool g_warmupComplete = false;   // Flag

// Active branch runtime state (global for cross-file access)
ENUM_EXECUTION_BRANCH g_activeBranch = (InpActiveBranch == BRANCH_B) ? BRANCH_SWING : BRANCH_INTRADAY;
ENUM_ACTIVE_BRANCH g_activeBranchSelection = InpActiveBranch;

// C3 confirmation family is always active — no runtime suppression

// Branch A parameters
 double g_InpA_C2_WickThreshold = InpA_C2_WickThreshold;
 double g_InpA_C2_MinWickRatio = InpA_C2_MinWickRatio;
 double g_InpA_C2_MinBodyRatio = InpA_C2_MinBodyRatio;
 double g_InpA_C2_DisplacementMultiplier = InpA_C2_DisplacementMultiplier;
 double g_InpA_C2_RangeExpansionFactor = InpA_C2_RangeExpansionFactor;
 double g_InpA_C3_BodyMultiplier = InpA_C3_BodyMultiplier;
 double g_InpA_C3_DisplacementMultiplier = InpA_C3_DisplacementMultiplier;
double g_InpA_C3_RangeExpansionFactor = InpA_C3_RangeExpansionFactor;
   double g_InpA_RG_BufferPercent = InpA_RG_BufferPercent;
 double g_InpA_RG_MarketThreshold = InpA_RG_MarketThreshold;
 int    g_InpA_LimitExpirationBars = InpA_LimitExpirationBars;

// Branch B parameters
 double g_InpB_C2_WickThreshold = InpB_C2_WickThreshold;
 double g_InpB_C2_MinWickRatio = InpB_C2_MinWickRatio;
 double g_InpB_C2_MinBodyRatio = InpB_C2_MinBodyRatio;
 double g_InpB_C2_DisplacementMultiplier = InpB_C2_DisplacementMultiplier;
 double g_InpB_C2_RangeExpansionFactor = InpB_C2_RangeExpansionFactor;
 double g_InpB_C3_BodyMultiplier = InpB_C3_BodyMultiplier;
 double g_InpB_C3_DisplacementMultiplier = InpB_C3_DisplacementMultiplier;
 double g_InpB_C3_RangeExpansionFactor = InpB_C3_RangeExpansionFactor;
  double g_InpB_RG_BufferPercent = InpB_RG_BufferPercent;
 double g_InpB_RG_MarketThreshold = InpB_RG_MarketThreshold;
 int    g_InpB_LimitExpirationBars = InpB_LimitExpirationBars;

 // NOTE: Global variable initializers are set at declaration (Sequence 3)
 // to avoid illegal global-scope assignment statements. These run before
 // UniversalConfig.mqh macros (Sequence 4) redefine Inp* → g_Inp*.

 //+------------------------------------------------------------------+
 //| SEQUENCE 4: MACRO ACTIVATION (UniversalConfig turns on Inp* → g_Inp* mapping) |
 //+------------------------------------------------------------------+
 #include <OmakFxYO/core/UniversalConfig.mqh>

//+------------------------------------------------------------------+
//| FORWARD DECLARATIONS — Required by engine includes below         |
//+------------------------------------------------------------------+
bool CommitSignalToStore(SLockedSignal &signal, ENUM_EXECUTION_BRANCH branch, ENUM_CLOSURE_TYPE closureType = CLOSURE_NONE);
void ClearSignalByGUID(ENUM_EXECUTION_BRANCH branch, ulong guid, string reason);

// C3 POI/wait windows
int g_InpC3MaxPOIWaitBars;
int g_InpC3MaxPOIWaitMinutes;
int g_InpC3MaxReadyWaitMinutes;

//+------------------------------------------------------------------+
//| Pending GUID Link Queue — bridges OrderSend → OnTradeTransaction |
//| Keyed by MqlTradeResult.request_id                                |
//+------------------------------------------------------------------+
struct PendingGUIDLink
{
   uint   request_id;            // from MqlTradeResult.request_id
   ulong  guid;                  // pipeline GUID active at OrderSend time
   ENUM_EXECUTION_BRANCH branch; // Branch for TF-aware timeout (§XII)
   ulong  orderTicket;           // Broker order ticket for removal
   datetime created;             // timestamp for TTL cleanup
   
   void Reset()
   {
      request_id = 0;
      guid = 0;
      branch = BRANCH_INTRADAY;
      orderTicket = 0;
      created = 0;
   }
};
PendingGUIDLink g_pendingLinks[];      // dynamic array

//+------------------------------------------------------------------+
//| GetPendingOrderTimeoutSeconds - §XII Compliance                 |
//+------------------------------------------------------------------+
int GetPendingOrderTimeoutSeconds(ENUM_TIMEFRAMES entryTF)
{
   // Per §XII (Single-Clock Synchronization):
   // timeout = PeriodSeconds(entryTF) * 4
   switch(entryTF)
   {
      case PERIOD_M5:   return 300 * 4;   // 1200 seconds (20 minutes)
      case PERIOD_M15:  return 900 * 4;   // 3600 seconds (60 minutes)
      case PERIOD_M1:   return 60 * 4;    // 240 seconds (4 minutes)
      default:          return 300 * 4;   // Default to M5 timeout
   }
}

 //+------------------------------------------------------------------+
 //| SEQUENCE 5: ENGINE INCLUDES                                       |
 //+------------------------------------------------------------------+
 #include <OmakFxYO/core/LogGovernor.mqh>   // LogPrint macro (must follow CoreTypes)
 #include <OmakFxYO/core/BranchRouter.mqh>
 #include <OmakFxYO/core/BranchEvaluator.mqh>
 #include <OmakFxYO/core/ConfluenceEngine.mqh>
 #include <OmakFxYO/core/SpreadFilter.mqh>
 #include <OmakFxYO/core/StructuralStateEngine.mqh>
#include <OmakFxYO/core/LiquidityTierEngine.mqh>
#include <OmakFxYO/core/DisplacementValidator.mqh>
#include <OmakFxYO/core/BiasResolver.mqh>
#include <OmakFxYO/core/ModeResolver.mqh>
#include <OmakFxYO/core/MarketTypeDetector.mqh>
#include <OmakFxYO/core/Telemetry.mqh>
#include <OmakFxYO/core/RiskGate.mqh>
#include <OmakFxYO/core/RiskCore.mqh>
#include <OmakFxYO/core/RiskManager.mqh>
#include <OmakFxYO/core/OrderManager.mqh>
#include <OmakFxYO/core/TargetEngine.mqh>
#include <OmakFxYO/core/SessionManager.mqh>
#include <OmakFxYO/core/HolidayCalendar.mqh>
#include <OmakFxYO/core/ClosureEngine.mqh>
#include <OmakFxYO/core/DowTheoryEngine.mqh>
#include <OmakFxYO/core/VolumeAnalyzer.mqh>
#include <OmakFxYO/core/LiquidityEngine.mqh>
#include <OmakFxYO/core/ExecutionEngine.mqh>
#include <OmakFxYO/core/FractalState.mqh>
// REGRESSION_GUARD_V52.5_DEAD_CODE: MarketPhaseDetector removed (ENUM_MARKET_PHASE, SPhaseAlignment dead)
#include <OmakFxYO/core/C2WickFilter.mqh>
#include <OmakFxYO/core/TradeGovernor.mqh>
#include <OmakFxYO/core/SignalLifecycle.mqh>
// Forward declarations for ExitEngine access to PositionGUIDMap data
bool GetProtectedSwingByTicket(ulong ticket, double &c2_low, double &c2_high);
ulong GetGUIDFromPositionMap(ulong ticket);
ENUM_EXECUTION_BRANCH GetPositionBranchByTicket(ulong ticket);
void LogExitMarker(ulong guid, ENUM_EXIT_TYPE exitType, double pnl);
#include <OmakFxYO/core/PositionManager.mqh>
#include <OmakFxYO/core/ExitEngine.mqh>
#include <OmakFxYO/core/InstitutionalScaling.mqh>
#include <OmakFxYO/core/PortfolioRiskEngine.mqh>
#include <OmakFxYO/core/TradeContext.mqh>
#include <OmakFxYO/core/SymbolProfileManager.mqh>
#include <OmakFxYO/core/CoreSymbolDB.mqh>
#include <OmakFxYO/core/Determinism.mqh>
#include <OmakFxYO/core/CampaignManager.mqh>
#include <OmakFxYO/core/AddExecutor.mqh>
#include <OmakFxYO/core/GeometryEngine.mqh>
#include <OmakFxYO/core/Router.mqh>

//+------------------------------------------------------------------+
//| Check if MT5 tester is in "calculate profit in pips" mode        |
//+------------------------------------------------------------------+
bool IsTesterPipsMode()
{
   if(!MQLInfoInteger(MQL_TESTER))
      return false;

   double testLot = 1.0;
   double testEntry = 100.0;
   double testStop = 99.0;               // 1.0 price distance
   double apiRisk = 0.0;

   if(!OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, testLot, testEntry, testStop, apiRisk))
      return false;

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double manualRisk = (MathAbs(testEntry - testStop) / tickSize) * tickValue * testLot;

   double ratio = MathAbs(apiRisk) / manualRisk;
   // In pips mode, apiRisk is inflated by a factor of ~10-100x
   return (ratio > 5.0);
}

//+------------------------------------------------------------------+
//| EXECUTION BRANCH GLOBALS (authoritative)                         |
//+------------------------------------------------------------------+
SBranchTimeframes g_branchTF;
int g_totalSignalCommits = 0;  // Counts total commits to signal store (not unique GUIDs)
int g_totalSignalsExpired = 0;
int g_totalSignalsReady = 0;
int g_totalOrdersSent = 0;
  int g_totalDeals = 0;  // P5 Fix: Real-time deal counter
 double g_totalNetProfit = 0.0;  // P5 Fix: Real-time net profit accumulator
datetime g_lastResetDay = 0;

// Dynamic Risk Reduction — global state (Mission 9 fix)
double g_peakEquity = 0.0;
double g_effectiveRiskPercent = 1.0;

// DEPRECATED: g_orderGUIDMap removed — single canonical store is g_positionMap[]
// Order-to-GUID mapping now handled via PendingGUIDLink + g_positionMap[]
datetime g_dailyStartTime = 0;
double g_dailyStartBalance = 0.0;

// Symbol-agnostic risk floor (set in OnInit)
double g_symbolRiskFloor = 0.0;
double g_minStopBuffer = 1.0;  // Minimum SL buffer (stops level multiplier)

int g_maxPoiWaitBars = 5;           // Max bars to wait for POI touch

// Emergency close flag - set by catastrophic or daily loss halt
bool g_emergencyCloseTriggered = false;
bool g_emergencyClosePending = false;  // P24-R: Flag for retrying emergency close when market reopens
datetime g_emergencyCloseTime = 0;

// Day-start balance for daily loss tracking (resets each new day)
double g_dayStartBalance = 0.0;
// Day-start time for filtering today's deals (trade P&L only, excludes swap/commission)
datetime g_dayStartTime = 0;

// Initial equity at EA start for catastrophic stop-out
double g_firstEquity = 0.0;

// All-time highest equity ever seen (never reset)
double g_highestEquityEver = 0.0;
// Peak equity over trailing 30-day window
double g_peakEquity30Day = 0.0;
datetime g_peakEquity30DayTime = 0;

// Cooldown recovery state after catastrophic halt
datetime g_guardHaltTime = 0;
input int    InpGuardCooldownHours = 48;          // cooldown before recovery possible
input double InpGuardRecoveryEquityPct = 80.0;    // equity must recover to this % of g_peakEquity (0 = ignore)

bool   g_blockNewEntries = false; // True when daily realised loss limit reached

// Grace period tracking after trade opens
datetime g_lastTradeOpenTime = 0;
datetime g_lastOrderTime = 0;  // Timestamp of last ORDER_SENT for Account Guard grace period

// Position management frequency reduction
int g_tickCounter = 0;
int g_fegBlocked = 0;
datetime g_lastTickTime = 0;

// Tick price storage
double g_tickAsk = 0.0;
double g_tickBid = 0.0;
bool g_useTickPrices = false;

//+------------------------------------------------------------------+
//| UpdateDynamicRisk — Adjust risk based on equity curve           |
//+------------------------------------------------------------------+
double UpdateDynamicRisk(double baseRiskPercent)
{
    if(g_peakEquity == 0.0)
        g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(currentEquity > g_peakEquity)
        g_peakEquity = currentEquity;
    
    if(g_peakEquity <= 0.0)
        return baseRiskPercent;
    
    double drawdown = (g_peakEquity - currentEquity) / g_peakEquity;
    
    if(drawdown > 0.15)
        return baseRiskPercent * 0.5;
    else if(drawdown > 0.10)
        return baseRiskPercent * 0.75;
    else if(drawdown > 0.05)
        return baseRiskPercent * 0.9;
    
    return baseRiskPercent;
}

//+------------------------------------------------------------------+
//| OnTimer — Telemetry only (EquityGuardCheck runs from OnTick)     |
//+------------------------------------------------------------------+
void OnTimer()
{
    LogPrint("[ON_TIMER_TELEMETRY] Heartbeat | equity=" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2) +
             " | balance=" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2) +
             " | state=" + EnumToString(g_equityGuardState) +
             " | blocked=" + (g_blockNewEntries ? "true" : "false"), LOG_LEVEL_DEBUG);
}

//+------------------------------------------------------------------+
//| CalculateRealisedLossPct — Total P&L including floating equity   |
//| REGRESSION_GUARD_V54_3_P0_4  | Phase 1 P0 fix: +floating PnL     |
//+------------------------------------------------------------------+
double CalculateRealisedLossPct()
{
   double dayStartBalance = g_dayStartBalance;
   double closedPnL = 0.0;

   if(HistorySelect(g_dayStartTime, TimeCurrent()))
   {
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket <= 0) continue;

         datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
         if(dealTime < g_dayStartTime) continue;

         double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         closedPnL += profit;
      }
   }

   double floatingPnL = AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE);
   double totalPnL = closedPnL + floatingPnL;

   double lossPct = 0.0;
   if(dayStartBalance > 0.0 && totalPnL < 0.0)
      lossPct = (-totalPnL) / dayStartBalance * 100.0;

   return lossPct;
}

//+------------------------------------------------------------------+
//| LogSwapCommissionSummary — Track swap/commission separately       |
//| REGRESSION_GUARD_V54_3_P0_4                                       |
//+------------------------------------------------------------------+
void LogSwapCommissionSummary()
{
   double totalSwap = 0.0;
   double totalCommission = 0.0;

   if(HistorySelect(g_dayStartTime, TimeCurrent()))
   {
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket <= 0) continue;

         totalSwap += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
         totalCommission += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      }
   }

   LogInfo(StringFormat("[SWAP_COMM] swap=%.2f commission=%.2f total=%.2f",
            totalSwap, totalCommission, totalSwap + totalCommission));
}

//+------------------------------------------------------------------+
//| CheckDailyLossLimit — Gate new entries when trade P&L exceeds max|
//| REGRESSION_GUARD_V54_3_P0_4                                       |
//+------------------------------------------------------------------+
bool CheckDailyLossLimit()
{
   double lossPct = CalculateRealisedLossPct();

   static datetime s_lastDailyLossD1Bar = 0;
   datetime currentLossD1Bar = iTime(_Symbol, PERIOD_D1, 0);
   bool haltTriggered = false;

   if(lossPct >= InpMaxDailyLossPercent)
   {
      if(currentLossD1Bar != s_lastDailyLossD1Bar)
      {
         LogPrint("[ACCOUNT_GUARD] DAILY_LOSS_HALT | realisedLossPct=" + DoubleToString(lossPct,1) +
                  "% | max=" + DoubleToString(InpMaxDailyLossPercent,1) + "% | Blocking new entries", LOG_LEVEL_ERROR);
         s_lastDailyLossD1Bar = currentLossD1Bar;
      }
       if(InpBlockNewEntriesOnDailyLoss)
       {
          haltTriggered = true;
       }
   }
   else
   {
      if(currentLossD1Bar != s_lastDailyLossD1Bar)
      {
         LogPrint(StringFormat("[DAILY_LOSS_OK] Trade P&L loss=%.2f%% < max=%.2f%%",
                  lossPct, InpMaxDailyLossPercent), LOG_LEVEL_INFO);
         s_lastDailyLossD1Bar = currentLossD1Bar;
      }
   }

   return haltTriggered;
}

//+------------------------------------------------------------------+
//| CalculateCatastrophicFloor — Compute effective equity floor     |
//| Returns the max of hard floor (initial deposit %) and dynamic   |
//| floor (30-day peak %), matching the floor used in EquityGuard.  |
//+------------------------------------------------------------------+
double CalculateCatastrophicFloor()
{
   double hardFloor = g_firstEquity * (InpCatastrophicFloorPercent / 100.0);
   double dynFloor = (InpDynamicFloorPercent > 0) ?
                     g_peakEquity30Day * (InpDynamicFloorPercent / 100.0) : 0.0;
    return MathMax(hardFloor, dynFloor);
}
//+------------------------------------------------------------------+
//| SyncBlockNewEntries — Derive g_blockNewEntries from FSM state    |
//| REGRESSION_GUARD_V52_5_EQ_GUARD_REBUILD                          |
//+------------------------------------------------------------------+
void SyncBlockNewEntries()
{
    g_blockNewEntries = (g_equityGuardState >= EQUITY_GUARD_BREACHED);
}
//+------------------------------------------------------------------+
//| EquityGuardCheck — Account protection FSM (tick-level)           |
//| REGRESSION_GUARD_V52_5_EQ_GUARD_REBUILD                          |
//+------------------------------------------------------------------+
void EquityGuardCheck()
{
    LogPrint("[EQ_GUARD_TICK] equity=" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2) +
             " | balance=" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2), LOG_LEVEL_DEBUG);

    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    ENUM_EQUITY_GUARD_STATE newState = g_equityGuardState;

    // PERMANENT state: no self-recovery — requires manual reset via InpGuardManualReset
    if(g_equityGuardState == EQUITY_GUARD_PERMANENT)
    {
        static bool s_prevManualReset = false;
        if(InpGuardManualReset && !s_prevManualReset)
        {
            LogPrint("[EQ_PERMANENT_RESET] Manual reset triggered via InpGuardManualReset -> WARNING", LOG_LEVEL_WARN);
            g_equityGuardState = EQUITY_GUARD_WARNING;
            SyncBlockNewEntries();
            s_prevManualReset = InpGuardManualReset;
        }
        else
        {
            s_prevManualReset = InpGuardManualReset;
        }
        return;
    }

    // Update peak equity tracking
    if(currentEquity > g_peakEquity) g_peakEquity = currentEquity;
    if(currentEquity > g_highestEquityEver) g_highestEquityEver = currentEquity;
    if(currentEquity > g_peakEquity30Day)
    {
        g_peakEquity30Day = currentEquity;
        g_peakEquity30DayTime = TimeCurrent();
    }
    if(TimeCurrent() - g_peakEquity30DayTime > 30 * 86400)
    {
        g_peakEquity30Day = currentEquity;
        g_peakEquity30DayTime = TimeCurrent();
    }

    // Daily loss check (includes floating PnL)
    LogPrint("[EQ_FLOATING_DD] checking daily loss limit", LOG_LEVEL_DEBUG);
    if(CheckDailyLossLimit())
        newState = EQUITY_GUARD_BREACHED;

    // Catastrophic floor check
    double effectiveFloor = CalculateCatastrophicFloor();

    static datetime s_lastFloorCalcDay = 0;
    datetime today = iTime(_Symbol, PERIOD_D1, 0);
    if(today != s_lastFloorCalcDay)
    {
        s_lastFloorCalcDay = today;
        double calcHardFloor = g_firstEquity * (InpCatastrophicFloorPercent / 100.0);
        double calcDynFloor = (InpDynamicFloorPercent > 0) ?
                              g_peakEquity30Day * (InpDynamicFloorPercent / 100.0) : 0.0;
        LogPrint("[FLOOR_CALC] hardFloor=" + DoubleToString(calcHardFloor, 2) +
                 " | dynFloor=" + DoubleToString(calcDynFloor, 2) +
                 " | effective=" + DoubleToString(effectiveFloor, 2) +
                 ((effectiveFloor == calcHardFloor) ? " | binding=HARD" : " | binding=DYNAMIC"), LOG_LEVEL_INFO);
    }

    if(currentEquity < effectiveFloor)
    {
        g_guardHaltTime = TimeCurrent();
        LogPrint("[EQ_CATASTROPHIC_HALT] equity=" + DoubleToString(currentEquity,2) +
                 " < floor=" + DoubleToString(effectiveFloor,2) +
                 " | state=" + EnumToString(g_equityGuardState), LOG_LEVEL_ERROR);
        newState = EQUITY_GUARD_PERMANENT;
    }

    // Warning state (uses total P&L including floating)
    double lossPct = CalculateRealisedLossPct();
    if(newState == EQUITY_GUARD_NORMAL && lossPct >= InpMaxDailyLossPercent * 0.7)
        newState = EQUITY_GUARD_WARNING;
    else if(newState == EQUITY_GUARD_NORMAL && (g_equityGuardState == EQUITY_GUARD_BREACHED || g_equityGuardState == EQUITY_GUARD_WARNING))
        newState = EQUITY_GUARD_NORMAL;

    // State transition handling
    if(newState != g_equityGuardState)
    {
        ENUM_EQUITY_GUARD_STATE oldState = g_equityGuardState;
        g_equityGuardState = newState;

        // Validate transition legality for equity guard FSM
        bool legalTransition = false;
        switch(oldState)
        {
            case EQUITY_GUARD_NORMAL:
                legalTransition = (newState == EQUITY_GUARD_WARNING ||
                                   newState == EQUITY_GUARD_BREACHED ||
                                   newState == EQUITY_GUARD_PERMANENT);
                break;
            case EQUITY_GUARD_WARNING:
                legalTransition = (newState == EQUITY_GUARD_NORMAL ||
                                   newState == EQUITY_GUARD_BREACHED ||
                                   newState == EQUITY_GUARD_PERMANENT);
                break;
            case EQUITY_GUARD_BREACHED:
                legalTransition = (newState == EQUITY_GUARD_NORMAL ||
                                   newState == EQUITY_GUARD_PERMANENT);
                break;
            case EQUITY_GUARD_PERMANENT:
                legalTransition = (newState == EQUITY_GUARD_WARNING);  // Only via manual reset
                break;
        }

        if(!legalTransition)
        {
            LogPrint("[STATE_ILLEGAL] EQUITY_GUARD " + EnumToString(oldState) +
                     " -> " + EnumToString(newState) + " is illegal", LOG_LEVEL_ERROR);
        }

        switch(newState)
        {
            case EQUITY_GUARD_WARNING:
                LogPrint("[STATE_TRANSITION_OK] EQUITY_GUARD WARNING | dailyLoss=" +
                         DoubleToString(lossPct, 1) +
                         "% | Blocking new entries above 70% threshold", LOG_LEVEL_WARN);
                break;

            case EQUITY_GUARD_BREACHED:
                LogPrint("[STATE_TRANSITION_OK] EQUITY_GUARD BREACHED | dailyLoss=" +
                         DoubleToString(lossPct, 1) +
                         "% | Daily loss limit hit, blocking new entries", LOG_LEVEL_WARN);
                break;

            case EQUITY_GUARD_PERMANENT:
                LogPrint("[STATE_TRANSITION_OK] EQUITY_GUARD PERMANENT_HALT | EA permanently halted",
                         LOG_LEVEL_ERROR);
                CloseAllPositions("PERMANENT_HALT");
                break;

            case EQUITY_GUARD_NORMAL:
                LogPrint("[STATE_RECOVERED] EQUITY_GUARD NORMAL | equity=" +
                         DoubleToString(currentEquity, 2) +
                         " | resuming normal trading", LOG_LEVEL_INFO);
                break;
        }
    }

    // Phased recovery: restrict trading in deep drawdown within WARNING state
    if(g_equityGuardState == EQUITY_GUARD_WARNING)
    {
        double currentFloor = CalculateCatastrophicFloor();
        if(AccountInfoDouble(ACCOUNT_EQUITY) < currentFloor * 1.2)
        {
            g_maxTradesPerDay = 1;
            g_riskPercentOverride = 0.5;
            LogInfo(StringFormat("[ACCOUNT_RESTRICT] Deep drawdown while in WARNING | max 1 trade/day, 0.5%% risk | equity=%.2f floor=%.2f",
                     AccountInfoDouble(ACCOUNT_EQUITY), currentFloor));
        }
        else
        {
            if(g_maxTradesPerDay != 0 || g_riskPercentOverride != -1.0)
            {
                g_maxTradesPerDay = 0;
                g_riskPercentOverride = -1.0;
                LogInfo("[ACCOUNT_RESTRICT_RELEASE] Equity recovered above deep drawdown — restored normal risk parameters");
            }
        }
    }

    // Derive g_blockNewEntries from FSM state
    SyncBlockNewEntries();
}

//+------------------------------------------------------------------+
//| IsMarketOpen — Check if market is open for trading                |
//+------------------------------------------------------------------+
bool IsMarketOpen()
{
   // Check terminal-level trade allowance
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;
   // Check if symbol has valid market data (not closed)
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| CloseAllPositions — Emergency close all positions                |
//+------------------------------------------------------------------+
bool CloseAllPositions(string reason)
{
    LogPrint("[EQ_LIQUIDATION] CloseAllPositions triggered | reason=" + reason, LOG_LEVEL_WARN);
   // Do not attempt emergency close when market is closed
   if(!IsMarketOpen())
   {
      LogPrint("[RISK_GUARD] Attempted emergency close, but market is closed. Deferring.", LOG_LEVEL_INFO);
      return false;
   }

   int closedCount = 0;
   datetime now = TimeCurrent();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         if(sym == _Symbol || _Symbol == "")  // Close all or current symbol
         {
            // Safeguard: Do not close positions open less than 5 minutes (unless permanent halt)
            if(reason != "PERMANENT_HALT_20%" && reason != "PERMANENT_HALT")
            {
               datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
               if(now - openTime < 300)
               {
                  LogPrint("[CLOSE_SKIP] pos=" + IntegerToString(PositionGetTicket(i)) +
                           " | openTime=" + IntegerToString((int)openTime) +
                           " | reason=" + reason + " | AgeSecs=" + IntegerToString((int)(now - openTime)), LOG_LEVEL_INFO);
                  continue;
               }
            }
            ulong ticket = PositionGetTicket(i);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            ENUM_ORDER_TYPE orderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;

            MqlTradeRequest req = {};
            req.action = TRADE_ACTION_DEAL;
            req.symbol = sym;
            req.type = orderType;
            req.volume = PositionGetDouble(POSITION_VOLUME);
            req.position = ticket;
            req.price = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
            // REGRESSION_GUARD_DEVIATION: Dynamic point-scaled — works for all symbols
            double point = SymbolInfoDouble(sym, SYMBOL_POINT);
            req.deviation = (ulong)(point * 30);
            req.magic = InpMagicNumber;
            req.comment = StringFormat("GUID=%I64u|EmergencyClose|%s", PositionGetInteger(POSITION_MAGIC), reason);
            // REGRESSION_GUARD_FILLING: Dynamic filling per symbol
            ulong filling_mode = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
            ENUM_ORDER_TYPE_FILLING fill_type = ORDER_FILLING_RETURN;
            if((filling_mode & SYMBOL_FILLING_IOC) != 0) fill_type = ORDER_FILLING_IOC;
            else if((filling_mode & SYMBOL_FILLING_FOK) != 0) fill_type = ORDER_FILLING_FOK;
            req.type_filling = fill_type;

            MqlTradeResult res = {};
            if(OrderSend(req, res))
             {
                closedCount++;
                ulong eGuid = GetGUIDFromPositionMap(ticket);
                double ePnl = PositionGetDouble(POSITION_PROFIT);
                LogExitMarker(eGuid, EXIT_EMERGENCY_CLOSE, ePnl);
                LogPrint("[EMERGENCY_CLOSE] Closed pos=" + IntegerToString(ticket) +
                         " | reason=" + reason + " | sym=" + sym, LOG_LEVEL_ERROR);
             }
            else
            {
               LogPrint("[EMERGENCY_CLOSE_FAILED] pos=" + IntegerToString(ticket) +
                        " | err=" + IntegerToString(GetLastError()), LOG_LEVEL_ERROR);
            }
      }
    }
 }

   return (closedCount > 0);
}

// === OBSERVABILITY (B7.5) ===
int g_dupBlocked  = 0;
int g_lotCalls   = 0;
int g_traceCalls = 0;

//=== POI CACHE — Prevents per-tick POI recalculation (Fixes 4,002 POI logs) ===
struct POICache
{
   double atrValue;
   double bufferPrice;
   double tSpotLow;
   double tSpotHigh;
   datetime calcTime;
   int barIndex;
   bool isValid;
};
POICache g_poiCache[];

// === INCREMENTAL DEAL TRACKER ===
// Tracks deals AS THEY HAPPEN in OnTradeTransaction(), not at deinit when tester clears history.
// Mission 2 forensic fix: HistoryDealsTotal() returns 0 at deinit in tester.
struct DealTracker
{
   int    totalDeals;
   int    winningDeals;
   int    losingDeals;
   int    breakEvenDeals;
   double totalProfit;
   double totalLoss;
   double largestWin;
   double largestLoss;
   int    consecutiveWins;
   int    consecutiveLosses;
   int    maxConsecutiveWins;
   int    maxConsecutiveLosses;
   datetime firstDealTime;
   datetime lastDealTime;
};

DealTracker g_dealTracker = {};

 // C2 (Anticipation) performance tracking
int g_c2Wins = 0, g_c2Losses = 0, g_c2Breakeven = 0;
double g_c2TotalProfit = 0.0, g_c2LargestWin = 0.0, g_c2LargestLoss = 0.0;

// C3 (Confirmation) performance tracking
int g_c3Wins = 0, g_c3Losses = 0, g_c3Breakeven = 0;
double g_c3TotalProfit = 0.0, g_c3LargestWin = 0.0, g_c3LargestLoss = 0.0;

// PositionGUIDMap now defined in CoreTypes.mqh - canonical store for GUID-to-ticket mapping
PositionGUIDMap g_positionMap[];
int g_positionMapCount = 0;

// Static fallback for PositionGUIDMap when dynamic ArrayResize fails
#define MAX_STATIC_GUID_MAP 200
PositionGUIDMap g_staticPositionMap[MAX_STATIC_GUID_MAP];
int g_staticPositionMapCount = 0;
bool g_usingStaticPositionMap = false;

// (parallel arrays removed — canonical store is g_positionMap[] + g_staticPositionMap[])

//+------------------------------------------------------------------+
//| GetClosureTypeByGUID — Find closure type from signal store       |
//+------------------------------------------------------------------+
ENUM_CLOSURE_TYPE GetClosureTypeByGUID(ulong guid)
{
    if(guid == 0) return CLOSURE_NONE;
    for(int i = 0; i < MAX_SLOTS; i++)
    {
        if(g_activeC2[i].m_guid == guid) return g_activeC2[i].closureType;
        if(g_activeC3[i].m_guid == guid) return g_activeC3[i].closureType;
    }
    return CLOSURE_NONE;
}

//+------------------------------------------------------------------+
//| FindSignalByGUID — Find locked signal in store by GUID           |
//+------------------------------------------------------------------+
bool FindSignalByGUID(ulong guid, SLockedSignal &outSignal)
{
    if(guid == 0) return false;
    for(int i = 0; i < MAX_SLOTS; i++)
    {
        if(g_activeC2[i].m_guid == guid)
        {
            outSignal = g_activeC2[i];
            return true;
        }
        if(g_activeC3[i].m_guid == guid)
        {
            outSignal = g_activeC3[i];
            return true;
        }
    }
    return false;
}
// REGRESSION_GUARD_V54_3_FINDSIGNAL

//=== CLOSURE TRACKER — Position lifetime + closure stats ===
struct SPositionClosureTracker
{
    ulong ticket;
    datetime openTime;
    datetime closeTime;
    int closureCount;
    string lastClosureReason;
    bool timeoutClose;
};
SPositionClosureTracker g_closureTracker[];
int g_closureTrackerCount = 0;

//=== SIGNAL COOLDOWN REGISTRY (Prevent spam after expiry) ===
struct SLastSignalTime
{
    datetime c2;
    datetime c3;
};
SLastSignalTime g_lastSignalTime;

int g_cooldownBarsC2 = 5;  // Block new C2 for 5 bars after expiry
int g_cooldownBarsC3 = 3;  // Block new C3 for 3 bars after expiry

datetime g_lastTradeTimeC2 = 0; // Cooldown for C2
datetime g_lastTradeTimeC3 = 0; // Cooldown for C3

//+------------------------------------------------------------------+
 //| SIGNAL STORE — Per-branch signal storage (pyramiding support)    |
 //+------------------------------------------------------------------+
 // C2/C3 use separate isolated pools g_activeC2[] and g_activeC3[]
// defined in CoreTypes.mqh

//+------------------------------------------------------------------+
//| RETRY QUEUE — For market closed / trade disabled retry           |
//+------------------------------------------------------------------+
#define MAX_RETRY_QUEUE_SIZE 8
#define MAX_EXEC_RETRIES 20

struct SRetrySignal {
    ulong guid;
    datetime retryAfter;
    int retryCount;
    ENUM_EXECUTION_BRANCH branch;
    bool valid;
};

SRetrySignal g_retryQueue[MAX_RETRY_QUEUE_SIZE];

//+------------------------------------------------------------------+
//| AddToRetryQueue — Schedule signal for retry when market opens   |
//+------------------------------------------------------------------+
void AddToRetryQueue(ulong guid, ENUM_EXECUTION_BRANCH branch, datetime retryAfter)
{
    // Check if already in queue
    for(int i = 0; i < MAX_RETRY_QUEUE_SIZE; i++)
    {
        if(g_retryQueue[i].valid && g_retryQueue[i].guid == guid)
        {
            // Update retry time
            g_retryQueue[i].retryAfter = retryAfter;
            g_retryQueue[i].retryCount++;
                LogPrint(StringFormat("[RETRY_UPDATE] GUID=%I64u | retryAfter=%s | attempt=%d",
                   guid, TimeToString(retryAfter), g_retryQueue[i].retryCount), LOG_LEVEL_INFO);
            return;
        }
    }
    
    // Find empty slot
    for(int i = 0; i < MAX_RETRY_QUEUE_SIZE; i++)
    {
        if(!g_retryQueue[i].valid)
        {
            g_retryQueue[i].guid = guid;
            g_retryQueue[i].retryAfter = retryAfter;
            g_retryQueue[i].retryCount = 1;
            g_retryQueue[i].branch = branch;
            g_retryQueue[i].valid = true;
                LogPrint(StringFormat("[RETRY_SCHEDULED] GUID=%I64u | retryAfter=%s | branch=%d",
                   guid, TimeToString(retryAfter), branch), LOG_LEVEL_INFO);
            return;
        }
    }
    
    // Queue full - log warning
   LogPrint(StringFormat("[RETRY_QUEUE_FULL] Cannot schedule retry for GUID=%I64u", guid), LOG_LEVEL_WARN);
}

//+------------------------------------------------------------------+
//| RemoveFromRetryQueue — Remove signal from retry queue            |
//+------------------------------------------------------------------+
void RemoveFromRetryQueue(ulong guid)
{
    for(int i = 0; i < MAX_RETRY_QUEUE_SIZE; i++)
    {
        if(g_retryQueue[i].valid && g_retryQueue[i].guid == guid)
        {
            g_retryQueue[i].valid = false;
            g_retryQueue[i].guid = 0;
            g_retryQueue[i].retryAfter = 0;
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| ProcessRetryQueue — Check and retry pending signals             |
//+------------------------------------------------------------------+
void ProcessRetryQueue()
{
    datetime now = TimeCurrent();
    
    for(int i = 0; i < MAX_RETRY_QUEUE_SIZE; i++)
    {
        if(!g_retryQueue[i].valid) continue;
        
        // Check if max retries exceeded
        if(g_retryQueue[i].retryCount >= 3)
        {
                LogPrint(StringFormat("[RETRY_EXPIRED] GUID=%I64u | maxRetriesExceeded", g_retryQueue[i].guid), LOG_LEVEL_WARN);
            ClearSignalByGUID(g_retryQueue[i].branch, g_retryQueue[i].guid, "RETRY_EXPIRED");
            g_retryQueue[i].valid = false;
            continue;
        }
        
        // Check if it's time to retry
        if(now >= g_retryQueue[i].retryAfter)
        {
            // Check if market is now open
            string symbol = _Symbol;  // Use current symbol
            ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
            
            if(tradeMode == SYMBOL_TRADE_MODE_FULL)
            {
               LogPrint(StringFormat("[RETRY_ATTEMPT] GUID=%I64u | market now open, re-evaluating", g_retryQueue[i].guid), LOG_LEVEL_INFO);
                // Keep in queue - execution will happen in normal flow
                // The signal will be re-evaluated when execution is attempted
                g_retryQueue[i].valid = false;  // Remove from retry queue - signal will be retried normally
            }
            else
            {
                // Market still closed - reschedule
                datetime nextRetry = now + 60;  // Retry in 1 minute
                g_retryQueue[i].retryAfter = nextRetry;
                g_retryQueue[i].retryCount++;
               LogPrint(StringFormat("[RETRY_RESCHEDULED] GUID=%I64u | still closed, retryAt=%s", g_retryQueue[i].guid, TimeToString(nextRetry)), LOG_LEVEL_DEBUG);
            }
        }
    }
}

// Branch-specific limit order settings
bool g_useLimitOrdersBranchA = true;
bool g_useLimitOrdersBranchB = true;
int g_limitExpirationBars = 4;

//+------------------------------------------------------------------+
 //| GetSignalStoreIndex — Get base index within a C2 or C3 pool      |
 //| Returns the branch base offset within the pool array:            |
 //|   Branch A: 0, Branch B: MAX_C2_SIGNALS_PER_BRANCH (for C2)     |
 //|   or Branch B: MAX_C3_SIGNALS_PER_BRANCH (for C3).              |
 //| When closureType == CLOSURE_NONE, returns 0 (caller must not     |
 //| use this as a unified index — must iterate both pools instead). |
 //+------------------------------------------------------------------+
 int GetSignalStoreIndex(ENUM_EXECUTION_BRANCH branch, ENUM_CLOSURE_TYPE closureType = CLOSURE_NONE)
 {
     if(closureType == CLOSURE_C2)
         return (branch == BRANCH_INTRADAY) ? 0 : MAX_C2_SIGNALS_PER_BRANCH;
     else if(closureType == CLOSURE_C3 || closureType == CLOSURE_C4)
         return (branch == BRANCH_INTRADAY) ? 0 : MAX_C3_SIGNALS_PER_BRANCH;
     return 0;
 }

 //+------------------------------------------------------------------+
 //| GetMaxSignalsForClosureType — Get max slots for C2 or C3          |
 //+------------------------------------------------------------------+
 int GetMaxSignalsForClosureType(ENUM_CLOSURE_TYPE closureType)
 {
      if(closureType == CLOSURE_C2)
          return MAX_C2_SIGNALS_PER_BRANCH;
      else if(closureType == CLOSURE_C3 || closureType == CLOSURE_C4)
          return MAX_C3_SIGNALS_PER_BRANCH;
      return MAX_TOTAL_SIGNALS_PER_BRANCH;  // Fallback
 }

 //+------------------------------------------------------------------+
 //| CanCreateAdditionalSignal — Check if branch can accept new signal|
 //+------------------------------------------------------------------+
 // Updated to check C2 vs C3 separately
 bool CanCreateAdditionalSignal(ENUM_EXECUTION_BRANCH branch, ENUM_CLOSURE_TYPE closureType = CLOSURE_NONE)
 {
     int maxSlots = GetMaxSignalsForClosureType(closureType);
     int count = 0;
     if(closureType == CLOSURE_C2)
     {
         int baseIdx = GetSignalStoreIndex(branch, CLOSURE_C2);
         for(int i = 0; i < maxSlots; i++)
         {
             if(g_activeC2[baseIdx + i].m_guid != 0 && g_activeC2[baseIdx + i].stage != STAGE_NONE)
                 count++;
         }
     }
     else if(closureType == CLOSURE_C3 || closureType == CLOSURE_C4)
     {
         int baseIdx = GetSignalStoreIndex(branch, CLOSURE_C3);
         for(int i = 0; i < maxSlots; i++)
         {
             if(g_activeC3[baseIdx + i].m_guid != 0 && g_activeC3[baseIdx + i].stage != STAGE_NONE)
                 count++;
         }
     }
     else
     {
         int c2base = GetSignalStoreIndex(branch, CLOSURE_C2);
         int c3base = GetSignalStoreIndex(branch, CLOSURE_C3);
         int c2max = GetMaxSignalsForClosureType(CLOSURE_C2);
         int c3max = GetMaxSignalsForClosureType(CLOSURE_C3);
         for(int i = 0; i < c2max; i++)
         {
             if(g_activeC2[c2base + i].m_guid != 0 && g_activeC2[c2base + i].stage != STAGE_NONE)
                 count++;
         }
         for(int i = 0; i < c3max; i++)
         {
             if(g_activeC3[c3base + i].m_guid != 0 && g_activeC3[c3base + i].stage != STAGE_NONE)
                 count++;
         }
         maxSlots = c2max + c3max;
     }
     return (count < maxSlots);
 }

 //+------------------------------------------------------------------+
 //| ResetSignalStore — Clear all signals in branch                   |
 //+------------------------------------------------------------------+
 void ResetSignalStore(ENUM_EXECUTION_BRANCH branch)
 {
     int c2base = GetSignalStoreIndex(branch, CLOSURE_C2);
     int c3base = GetSignalStoreIndex(branch, CLOSURE_C3);
     for(int i = 0; i < MAX_C2_SIGNALS_PER_BRANCH; i++)
     {
         g_activeC2[c2base + i].Reset();
     }
     for(int i = 0; i < MAX_C3_SIGNALS_PER_BRANCH; i++)
     {
         g_activeC3[c3base + i].Reset();
     }
 }

//+------------------------------------------------------------------+
//| CommitSignalToStore — Commit a locked signal to the store        |
//+------------------------------------------------------------------+
// Updated to accept closure type and route to C2/C3 slots
bool CommitSignalToStore(SLockedSignal &signal, ENUM_EXECUTION_BRANCH branch, ENUM_CLOSURE_TYPE closureType = CLOSURE_NONE)
{
   if(signal.m_guid == 0)
       return false;

   // Use signal's closure type if not specified
   if(closureType == CLOSURE_NONE)
       closureType = signal.closureType;

   // C2 commit logging with distinct marker
   if(closureType == CLOSURE_C2)
   {
      LogPrint(StringFormat("[C2_COMMIT_ATTEMPT] GUID=%I64u | branch=%d", signal.m_guid, branch), LOG_LEVEL_DEBUG);
   }

    // Duplicate GUID check - reject if already stored, force regen on retry
    if(IsGuidInStoreSafe(signal.m_guid, branch))
    {
       LogPrint(StringFormat("[GUID_DUPLICATE_BLOCKED] Attempting regen | GUID=%I64u | branch=%d", signal.m_guid, branch), LOG_LEVEL_WARN);
       signal.m_guid = 0; // force regen in Lock on retry
       return false;
    }

   int baseIdx = GetSignalStoreIndex(branch, closureType);
   int maxSlotsLocal = GetMaxSignalsForClosureType(closureType);

   // FIRST: Attempt slot hygiene to reclaim stuck signals before rejecting
   int reclaimed = PerformSlotHygiene(branch, 1, closureType);

   // Find empty slot within C2/C3 pool
   int targetIdx = -1;
   if(closureType == CLOSURE_C2)
   {
      for(int i = 0; i < maxSlotsLocal; i++)
      {
          int idx = baseIdx + i;
          if(g_activeC2[idx].m_guid == 0 || g_activeC2[idx].stage == STAGE_NONE)
          {
              targetIdx = idx;
              break;
          }
      }
   }
   else
   {
      for(int i = 0; i < maxSlotsLocal; i++)
      {
          int idx = baseIdx + i;
          if(g_activeC3[idx].m_guid == 0 || g_activeC3[idx].stage == STAGE_NONE)
          {
              targetIdx = idx;
              break;
          }
      }
   }

   if(targetIdx == -1)
   {
       LogPrint("[COMMIT_REJECT] No slots available after hygiene pass | branch=" + 
                IntegerToString(branch) + " | GUID=" + IntegerToString(signal.m_guid), LOG_LEVEL_WARN);
       if(closureType == CLOSURE_C3)
          LogPrint("[C3_STORE_FAIL] reason=SLOTS_FULL_AFTER_HYGIENE | branch=" + IntegerToString(branch) +
                   " | GUID=" + IntegerToString(signal.m_guid), LOG_LEVEL_WARN);
       return false;
   }

   if(closureType == CLOSURE_C2)
   {
      if(g_activeC2[targetIdx].stage == STAGE_READY && !g_activeC2[targetIdx].hasFailedRG)
      {
         LogPrint("[STORE_HYGIENE_SAFE] Protected READY signal in target slot skipped | GUID=" + 
                  IntegerToString(g_activeC2[targetIdx].m_guid) + " | slot=" + IntegerToString(targetIdx), LOG_LEVEL_WARN);
         return false;
      }
      g_activeC2[targetIdx].Reset();
      g_activeC2[targetIdx] = signal;
   }
   else
   {
      if(g_activeC3[targetIdx].stage == STAGE_READY && !g_activeC3[targetIdx].hasFailedRG)
      {
         LogPrint("[STORE_HYGIENE_SAFE] Protected READY signal in target slot skipped | GUID=" + 
                  IntegerToString(g_activeC3[targetIdx].m_guid) + " | slot=" + IntegerToString(targetIdx), LOG_LEVEL_WARN);
         return false;
      }
      g_activeC3[targetIdx].Reset();
      g_activeC3[targetIdx] = signal;
   }
   g_poiCache[targetIdx].isValid = false;
   
   LogPrint(StringFormat("[SIGNAL_STORED] GUID=%I64u | branch=%d | slot=%d | pool=%s", signal.m_guid, branch, targetIdx, (closureType == CLOSURE_C2 ? "C2" : "C3")), LOG_LEVEL_INFO);
   LogPrint(StringFormat("[SLOT_DEEP_RESET] slot=%d | branch=%d | closureType=%s",
            targetIdx, branch, EnumToString(closureType)), LOG_LEVEL_DEBUG);
   
   g_totalSignalCommits++;
   
   return true;
}

//+------------------------------------------------------------------+
//| MEM_SANITIZED — Liveness-aware signal slot sanitization           |
//+------------------------------------------------------------------+
void MEM_SANITIZED(int idx) {
    if(idx >= MAX_SLOTS) return;
    // Prohibit sanitization of signals mid-execution (Fixes 48-Signal Gap)
    if(g_activeC2[idx].stage == STAGE_READY || g_activeC2[idx].isCommitted) return;
    if(g_activeC3[idx].stage == STAGE_READY || g_activeC3[idx].isCommitted) return;
    
    ZeroMemory(g_activeC2[idx]);
    g_activeC2[idx].stage = STAGE_NONE;
    ZeroMemory(g_activeC3[idx]);
    g_activeC3[idx].stage = STAGE_NONE;
}

//+------------------------------------------------------------------+
   //| ClearSignalByGUID — Nuclear scan: brute-force C2 and C3 pools   |
   //| Scans both g_activeC2[] and g_activeC3[] for the matching GUID |
   //+------------------------------------------------------------------+
void ClearSignalByGUID(ENUM_EXECUTION_BRANCH branch, ulong guid, string reason)
   {
      if(guid == 0) return;
      int c2Base = GetSignalStoreIndex(branch, CLOSURE_C2);
      int c3Base = GetSignalStoreIndex(branch, CLOSURE_C3);
      int c2Max = GetMaxSignalsForClosureType(CLOSURE_C2);
      int c3Max = GetMaxSignalsForClosureType(CLOSURE_C3);
      
      // Scan C2 pool
      for(int i = c2Base; i < c2Base + c2Max; i++)
      {
         if(g_activeC2[i].m_guid != guid) continue;
         SLockedSignal sig = g_activeC2[i];
         ENUM_CLOSURE_TYPE closureType = sig.closureType;

         if(StringFind(reason, "AFFORDABILITY") >= 0 ||
            StringFind(reason, "LOT_NOT_TRADEABLE") >= 0 ||
            StringFind(reason, "MINLOT") >= 0)
         {
            LogPrint("[PERMANENT_SKIP] GUID=" + IntegerToString(guid) + " | reason=" + reason + " | slot=C2[" + IntegerToString(i) + "]", LOG_LEVEL_WARN);
            if(sig.handoverState != HANDOVER_NONE && sig.handoverState != HANDOVER_RELEASED)
               g_activeC2[i].ForceReleaseHandover("PERMANENT_SKIP:" + reason);
            g_activeC2[i].slotClearedFor = STAGE_NONE;
            g_activeC2[i].Reset();
            g_poiCache[i].isValid = false;
            ClearCachedModeForGUID(guid);
            AddPermanentSkip(_Symbol, reason + " | GUID=" + IntegerToString(guid));
            LogPrint(StringFormat("[C2_SIGNAL_CLEARED] GUID=%I64u | reason=%s_PERMANENT_SKIP | slot=%d", guid, reason, i), LOG_LEVEL_INFO);
            return;
         }
         if(sig.executionAttempts > 8 || (sig.stage == STAGE_READY && sig.hasFailedRG))
         {
            LogPrint("[ZOMBIE_CLEARED] GUID=" + IntegerToString(guid) + " | idx=C2[" + IntegerToString(i) + "] | attempts=" + IntegerToString(sig.executionAttempts) + " | stage=" + EnumToString(sig.stage), LOG_LEVEL_WARN);
            if(sig.handoverState != HANDOVER_NONE && sig.handoverState != HANDOVER_RELEASED)
               g_activeC2[i].ForceReleaseHandover("ZOMBIE_CLEAR:" + reason);
            g_activeC2[i].slotClearedFor = STAGE_NONE;
            g_activeC2[i].Reset();
            ClearCachedModeForGUID(guid);
            LogPrint(StringFormat("[SIGNAL_CLEARED] GUID=%I64u | reason=%s_ZOMBIE | slot=C2[%d]", guid, reason, i), LOG_LEVEL_INFO);
            return;
         }
         if(sig.stage == STAGE_READY && !sig.hasFailedRG && !sig.isStructurallyInvalid)
         {
            LogPrint("[READY_CLEARED_BLOCKED] Protected READY signal skipped | GUID=" + IntegerToString(guid) + " | idx=C2[" + IntegerToString(i) + "]", LOG_LEVEL_WARN);
            continue;
         }
         g_activeC2[i].slotClearedFor = STAGE_NONE;
         g_activeC2[i].Reset();
         g_poiCache[i].isValid = false;
         ClearCachedModeForGUID(guid);
         LogPrint(StringFormat("[C2_SIGNAL_CLEARED] GUID=%I64u | reason=%s | slot=C2[%d]", guid, reason, i), LOG_LEVEL_INFO);
         return;
      }
      
      // Scan C3 pool
      for(int i = c3Base; i < c3Base + c3Max; i++)
      {
         if(g_activeC3[i].m_guid != guid) continue;
         SLockedSignal sig = g_activeC3[i];
         ENUM_CLOSURE_TYPE closureType = sig.closureType;

         if(StringFind(reason, "AFFORDABILITY") >= 0 ||
            StringFind(reason, "LOT_NOT_TRADEABLE") >= 0 ||
            StringFind(reason, "MINLOT") >= 0)
         {
            LogPrint("[PERMANENT_SKIP] GUID=" + IntegerToString(guid) + " | reason=" + reason + " | slot=C3[" + IntegerToString(i) + "]", LOG_LEVEL_WARN);
            if(sig.handoverState != HANDOVER_NONE && sig.handoverState != HANDOVER_RELEASED)
               g_activeC3[i].ForceReleaseHandover("PERMANENT_SKIP:" + reason);
            g_activeC3[i].slotClearedFor = STAGE_NONE;
            g_activeC3[i].Reset();
            g_poiCache[i].isValid = false;
            ClearCachedModeForGUID(guid);
            AddPermanentSkip(_Symbol, reason + " | GUID=" + IntegerToString(guid));
            LogPrint(StringFormat("[SIGNAL_CLEARED] GUID=%I64u | reason=%s_PERMANENT_SKIP | slot=C3[%d]", guid, reason, i), LOG_LEVEL_INFO);
            return;
         }
         if(sig.executionAttempts > 8 || (sig.stage == STAGE_READY && sig.hasFailedRG))
         {
            LogPrint("[ZOMBIE_CLEARED] GUID=" + IntegerToString(guid) + " | idx=C3[" + IntegerToString(i) + "] | attempts=" + IntegerToString(sig.executionAttempts) + " | stage=" + EnumToString(sig.stage), LOG_LEVEL_WARN);
            if(sig.handoverState != HANDOVER_NONE && sig.handoverState != HANDOVER_RELEASED)
               g_activeC3[i].ForceReleaseHandover("ZOMBIE_CLEAR:" + reason);
            g_activeC3[i].slotClearedFor = STAGE_NONE;
            g_activeC3[i].Reset();
            ClearCachedModeForGUID(guid);
            LogPrint(StringFormat("[SIGNAL_CLEARED] GUID=%I64u | reason=%s_ZOMBIE | slot=C3[%d]", guid, reason, i), LOG_LEVEL_INFO);
            return;
         }
         if(sig.stage == STAGE_READY && !sig.hasFailedRG && !sig.isStructurallyInvalid)
         {
            LogPrint("[READY_CLEARED_BLOCKED] Protected READY signal skipped | GUID=" + IntegerToString(guid) + " | idx=C3[" + IntegerToString(i) + "]", LOG_LEVEL_WARN);
            continue;
         }
         g_activeC3[i].slotClearedFor = STAGE_NONE;
         g_activeC3[i].Reset();
         g_poiCache[i].isValid = false;
         ClearCachedModeForGUID(guid);
         LogPrint(StringFormat("[SIGNAL_CLEARED] GUID=%I64u | reason=%s | slot=C3[%d]", guid, reason, i), LOG_LEVEL_INFO);
         return;
      }
   }

  //+------------------------------------------------------------------+
  //| ForceClearSignal — Nuclear signal cleanup using the handover      |
  //| state machine. Forces release before Reset to prevent ghost       |
  //| signals from persisting after repeated illegal transitions.       |
  //| poolIdx is the index into g_activeC2[] (if isC2=true) or         |
  //| g_activeC3[] (if isC2=false).                                    |
  //+------------------------------------------------------------------+
  void ForceClearSignal(int poolIdx, bool isC2, string reason)
  {
      if(poolIdx < 0 || poolIdx >= MAX_SLOTS)
          return;

      ulong guid;
      ENUM_CLOSURE_TYPE closureType;
      ENUM_SIGNAL_STAGE stage;

      if(isC2)
      {
          if(g_activeC2[poolIdx].m_guid == 0) return;
          guid = g_activeC2[poolIdx].m_guid;
          closureType = g_activeC2[poolIdx].closureType;
          stage = g_activeC2[poolIdx].stage;

          if(g_activeC2[poolIdx].executionAttempts > 8 ||
             (stage == STAGE_READY && g_activeC2[poolIdx].hasFailedRG))
          {
             LogPrint("[ZOMBIE_CLEARED] GUID=" + IntegerToString(guid) +
                      " | idx=C2[" + IntegerToString(poolIdx) + "]" +
                      " | attempts=" + IntegerToString(g_activeC2[poolIdx].executionAttempts) +
                      " | stage=" + EnumToString(stage), LOG_LEVEL_WARN);
             if(g_activeC2[poolIdx].handoverState != HANDOVER_NONE &&
                g_activeC2[poolIdx].handoverState != HANDOVER_RELEASED)
                g_activeC2[poolIdx].ForceReleaseHandover("ZOMBIE_CLEAR:" + reason);
             g_activeC2[poolIdx].Reset();
             g_poiCache[poolIdx].isValid = false;
             if(guid != 0)
             {
                ClearCachedModeForGUID(guid);
                LogPrint(StringFormat("[SIGNAL_FORCE_CLEARED] GUID=%I64u | reason=%s_ZOMBIE | idx=C2[%d]", guid, reason, poolIdx), LOG_LEVEL_WARN);
             }
             return;
          }
          if(stage == STAGE_READY && !g_activeC2[poolIdx].hasFailedRG && !g_activeC2[poolIdx].isStructurallyInvalid)
          {
             LogPrint("[READY_CLEARED_BLOCKED] Protected READY signal skipped | GUID=" + IntegerToString(guid) + " | idx=C2[" + IntegerToString(poolIdx) + "]", LOG_LEVEL_WARN);
             return;
          }
          if(g_activeC2[poolIdx].handoverState != HANDOVER_NONE &&
             g_activeC2[poolIdx].handoverState != HANDOVER_RELEASED)
             g_activeC2[poolIdx].ForceReleaseHandover("FORCE_CLEAR:" + reason);
          g_activeC2[poolIdx].Reset();
          g_poiCache[poolIdx].isValid = false;
          if(guid != 0)
          {
             ClearCachedModeForGUID(guid);
             LogPrint(StringFormat("[SIGNAL_FORCE_CLEARED] GUID=%I64u | reason=%s | idx=C2[%d] | closure=%s | stage=%s",
                      guid, reason, poolIdx, EnumToString(closureType), EnumToString(stage)), LOG_LEVEL_WARN);
          }
      }
      else
      {
          if(g_activeC3[poolIdx].m_guid == 0) return;
          guid = g_activeC3[poolIdx].m_guid;
          closureType = g_activeC3[poolIdx].closureType;
          stage = g_activeC3[poolIdx].stage;

          if(g_activeC3[poolIdx].executionAttempts > 8 ||
             (stage == STAGE_READY && g_activeC3[poolIdx].hasFailedRG))
          {
             LogPrint("[ZOMBIE_CLEARED] GUID=" + IntegerToString(guid) +
                      " | idx=C3[" + IntegerToString(poolIdx) + "]" +
                      " | attempts=" + IntegerToString(g_activeC3[poolIdx].executionAttempts) +
                      " | stage=" + EnumToString(stage), LOG_LEVEL_WARN);
             if(g_activeC3[poolIdx].handoverState != HANDOVER_NONE &&
                g_activeC3[poolIdx].handoverState != HANDOVER_RELEASED)
                g_activeC3[poolIdx].ForceReleaseHandover("ZOMBIE_CLEAR:" + reason);
             g_activeC3[poolIdx].Reset();
             g_poiCache[poolIdx].isValid = false;
             if(guid != 0)
             {
                ClearCachedModeForGUID(guid);
                LogPrint(StringFormat("[SIGNAL_FORCE_CLEARED] GUID=%I64u | reason=%s_ZOMBIE | idx=C3[%d]", guid, reason, poolIdx), LOG_LEVEL_WARN);
             }
             return;
          }
          if(stage == STAGE_READY && !g_activeC3[poolIdx].hasFailedRG && !g_activeC3[poolIdx].isStructurallyInvalid)
          {
             LogPrint("[READY_CLEARED_BLOCKED] Protected READY signal skipped | GUID=" + IntegerToString(guid) + " | idx=C3[" + IntegerToString(poolIdx) + "]", LOG_LEVEL_WARN);
             return;
          }
          if(g_activeC3[poolIdx].handoverState != HANDOVER_NONE &&
             g_activeC3[poolIdx].handoverState != HANDOVER_RELEASED)
             g_activeC3[poolIdx].ForceReleaseHandover("FORCE_CLEAR:" + reason);
          g_activeC3[poolIdx].Reset();
          g_poiCache[poolIdx].isValid = false;
          if(guid != 0)
          {
             ClearCachedModeForGUID(guid);
             LogPrint(StringFormat("[SIGNAL_FORCE_CLEARED] GUID=%I64u | reason=%s | idx=C3[%d] | closure=%s | stage=%s",
                      guid, reason, poolIdx, EnumToString(closureType), EnumToString(stage)), LOG_LEVEL_WARN);
          }
      }
  }

  //+------------------------------------------------------------------+
  //| CountActiveSignals — Count active signals in branch              |
  //+------------------------------------------------------------------+
 // Updated to count C2 and C3 separately
 int CountActiveSignals(ENUM_EXECUTION_BRANCH branch, ENUM_CLOSURE_TYPE closureType = CLOSURE_NONE)
 {
     int count = 0;
     if(closureType == CLOSURE_C2)
     {
         int baseIdx = GetSignalStoreIndex(branch, CLOSURE_C2);
         for(int i = 0; i < MAX_C2_SIGNALS_PER_BRANCH; i++)
         {
             if(g_activeC2[baseIdx + i].m_guid != 0 && g_activeC2[baseIdx + i].stage != STAGE_NONE)
                 count++;
         }
     }
     else if(closureType == CLOSURE_C3 || closureType == CLOSURE_C4)
     {
         int baseIdx = GetSignalStoreIndex(branch, CLOSURE_C3);
         for(int i = 0; i < MAX_C3_SIGNALS_PER_BRANCH; i++)
         {
             if(g_activeC3[baseIdx + i].m_guid != 0 && g_activeC3[baseIdx + i].stage != STAGE_NONE)
                 count++;
         }
     }
     else
     {
         int c2base = GetSignalStoreIndex(branch, CLOSURE_C2);
         int c3base = GetSignalStoreIndex(branch, CLOSURE_C3);
         for(int i = 0; i < MAX_C2_SIGNALS_PER_BRANCH; i++)
         {
             if(g_activeC2[c2base + i].m_guid != 0 && g_activeC2[c2base + i].stage != STAGE_NONE)
                 count++;
         }
         for(int i = 0; i < MAX_C3_SIGNALS_PER_BRANCH; i++)
         {
             if(g_activeC3[c3base + i].m_guid != 0 && g_activeC3[c3base + i].stage != STAGE_NONE)
                 count++;
         }
     }
     return count;
 }

 //+------------------------------------------------------------------+
 //| GetActiveSignal — Get first active signal from store            |
 //+------------------------------------------------------------------+
 // Updated to prefer C2 signals (shorter lifespan priority)
 bool GetActiveSignal(ENUM_EXECUTION_BRANCH branch, SLockedSignal &outSignal)
 {
     int c2BaseIdx = GetSignalStoreIndex(branch, CLOSURE_C2);
     for(int i = 0; i < MAX_C2_SIGNALS_PER_BRANCH; i++)
     {
         int idx = c2BaseIdx + i;
         if(g_activeC2[idx].m_guid != 0 && g_activeC2[idx].stage != STAGE_NONE)
         {
             outSignal = g_activeC2[idx];
             return true;
         }
     }

     int c3BaseIdx = GetSignalStoreIndex(branch, CLOSURE_C3);
     for(int i = 0; i < MAX_C3_SIGNALS_PER_BRANCH; i++)
     {
         int idx = c3BaseIdx + i;
         if(g_activeC3[idx].m_guid != 0 && g_activeC3[idx].stage != STAGE_NONE)
         {
             outSignal = g_activeC3[idx];
             return true;
         }
     }

     return false;
 }

//+------------------------------------------------------------------+
//| CalculateClosureTypeSL — SL based on closure type (C2 vs C3)    |
//+------------------------------------------------------------------+
double CalculateClosureTypeSL(const SLockedSignal &sig, string &outError)
{
    double entry = sig.entry_price;
    if(entry <= 0.0)
    {
       outError = "[SL_INVALID] entry_price <= 0";
       return 0.0;
    }
    double sl = 0.0;
   SSymbolProfile slProf = SY_GetProfile(_Symbol);
   double minStopLevel = (double)slProf.stopsLevel * slProf.point;
     double buffer = minStopLevel;

    // Intermediate Timeframe (ITF) Protected Swing per Law of Mechanical Risk §V
    ENUM_TIMEFRAMES _slAnchorTF = (sig.branchId == BRANCH_INTRADAY) ? PERIOD_H1 : PERIOD_H4;
    double baseSL = (sig.direction == DIRECTION_BUY)
                    ? iLow(_Symbol, _slAnchorTF, 1)
                    : iHigh(_Symbol, _slAnchorTF, 1);

    if(sig.direction == DIRECTION_BUY)
    {
        sl = baseSL - buffer;
        if(sl >= entry)
            sl = entry - buffer;
         if(sl >= entry)
         {
            outError = "[SL_DIRECTION_FAIL] BUY SL >= entry | SL=" + DoubleToString(sl, _Digits) + " | entry=" + DoubleToString(entry, _Digits);
            return 0.0;
         }
     }
     else
     {
         sl = baseSL + buffer;
         if(sl <= entry)
            sl = entry + buffer;
        if(sl <= entry)
        {
           outError = "[SL_DIRECTION_FAIL] SELL SL <= entry | SL=" + DoubleToString(sl, _Digits) + " | entry=" + DoubleToString(entry, _Digits);
           return 0.0;
        }
    }
    sl = NormalizeDouble(sl, _Digits);
    LogPrint("[SL_TRACE] " + EnumToString(sig.closureType) +
             (sig.direction == DIRECTION_BUY ? " BUY" : " SELL") +
             " | entry=" + DoubleToString(entry, _Digits) +
             " | sl=" + DoubleToString(sl, _Digits) +
             " | baseSL=" + DoubleToString(baseSL, _Digits) +
             " | anchorTF=" + EnumToString(_slAnchorTF) +
             " | buffer=" + DoubleToString(buffer, 1) +
             " | source=htf_anchor_extreme", LOG_LEVEL_INFO);

    return sl;
}
//+------------------------------------------------------------------+
//| CalculateProjectionTPs — TP1/TP2/TP3 based on R:R multiplier     |
//+------------------------------------------------------------------+
bool CalculateProjectionTPs(const SLockedSignal &sig, double stopLoss,
                           double &tp1, double &tp2, double &tp3, string &outError)
{
   double entry = sig.entry_price;
   if(entry <= 0.0 || stopLoss <= 0.0)
   {
      outError = "[TP_INVALID] entry or SL invalid";
      return false;
   }
   double risk = MathAbs(entry - stopLoss);
   if(risk <= 0.0)
   {
      outError = "[TP_INVALID] risk = 0";
      return false;
   }
   double mult1 = (sig.riskProfile.tpMultiplier > 0) ? sig.riskProfile.tpMultiplier : InpRiskRewardRatio;
   double mult2 = mult1 * 1.5;
   double mult3 = mult1 * 2.0;
   if(sig.direction == DIRECTION_BUY)
   {
      tp1 = NormalizeDouble(entry + risk * mult1, _Digits);
      tp2 = NormalizeDouble(entry + risk * mult2, _Digits);
      tp3 = NormalizeDouble(entry + risk * mult3, _Digits);
   }
   else
   {
      tp1 = NormalizeDouble(entry - risk * mult1, _Digits);
      tp2 = NormalizeDouble(entry - risk * mult2, _Digits);
      tp3 = NormalizeDouble(entry - risk * mult3, _Digits);
   }
   LogPrint("[TP_STRUCTURAL] " + EnumToString(sig.closureType) +
            " | risk=" + DoubleToString(risk, _Digits) +
            " | R:R=" + DoubleToString(mult1, 2) +
            " | tp1=" + DoubleToString(tp1, _Digits) +
            " | GUID=" + IntegerToString(sig.m_guid), LOG_LEVEL_INFO);
   outError = "";
   return true;
}

//+------------------------------------------------------------------+
//| GetRiskProfileForSignal — Get risk profile from signal mode      |
//+------------------------------------------------------------------+
SRiskProfile GetRiskProfileForSignal(const SLockedSignal &sig)
{
   return GetRiskProfile((EntryMode)sig.executionMode, _Symbol, 0.0);
}

//+------------------------------------------------------------------+
//| IsSignalOnCooldown — Check if new signal is blocked by cooldown |
//+------------------------------------------------------------------+
bool IsSignalOnCooldown(ENUM_CLOSURE_TYPE closureType, string symbol = "")
{
    datetime now = TimeCurrent();
    int cooldownSeconds = InpTradeCooldownSeconds;
    if(cooldownSeconds <= 0) cooldownSeconds = 60;

    datetime lastTime = (closureType == CLOSURE_C2) ? g_lastTradeTimeC2 : g_lastTradeTimeC3;

    if(lastTime > 0 && (now - lastTime) < cooldownSeconds)
    {
        int remaining = cooldownSeconds - (int)(now - lastTime);
        LogPrint("[COOLDOWN_BLOCK] closure=" + EnumToString(closureType) +
                " | remaining=" + IntegerToString(remaining) + "s" +
                " | symbol=" + symbol, LOG_LEVEL_DEBUG);
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| UpdateCooldownRegistry — Record signal expiry for cooldown       |
//+------------------------------------------------------------------+
void UpdateCooldownRegistry(ENUM_CLOSURE_TYPE closureType)
{
    datetime now = TimeCurrent();
    if(closureType == CLOSURE_C2)
        g_lastSignalTime.c2 = now;
    else if(closureType == CLOSURE_C3)
        g_lastSignalTime.c3 = now;
        
    LogPrint("[COOLDOWN_REGISTRY] Updated | closure=" + EnumToString(closureType) +
            " | time=" + TimeToString(now), LOG_LEVEL_DEBUG);
}

// Branch evaluation caching per bar
bool g_branchesEvaluated = false;
datetime g_lastBranchBar = 0;
BranchContext g_cachedCtx;
bool g_cachedCtxInitialized = false;

// SAFE CONTEXT ASSIGNMENT HELPER
void UpdateCachedContext(ENUM_EXECUTION_BRANCH branch)
{
   if(branch == BRANCH_INTRADAY)
   {
      g_cachedCtx = BE_GetBranchAContext();
   }
   else
   {
      g_cachedCtx = BE_GetBranchBContext();
   }
   g_cachedCtxInitialized = true;
}

//+------------------------------------------------------------------+
//| CLOSURE ENGINE HARDENING — Throttle Guard      |
//+------------------------------------------------------------------+
datetime g_lastClosureCheck = 0;
int g_closureCheckIntervalSec = 5;  // Minimum seconds between closure checks

bool ShouldRunClosureCheck()
{
    datetime now = TimeCurrent();
    if(now - g_lastClosureCheck < g_closureCheckIntervalSec)
        return false;
    g_lastClosureCheck = now;
    return true;
}

//+------------------------------------------------------------------+
//| Emergency Position Timeout — Hard close after N days            |
//+------------------------------------------------------------------+
void CheckEmergencyTimeout()
{
    if(InpMaxTradeDurationDays <= 0)
        return;  // Disabled

    int secondsPerDay = 86400;
    int maxHoldSeconds = InpMaxTradeDurationDays * secondsPerDay;
    datetime cutoff = TimeCurrent() - maxHoldSeconds;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(StringCompare(PositionGetString(POSITION_SYMBOL), _Symbol) != 0) continue;
        if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) continue;
        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ||
           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(openTime > 0 && openTime < cutoff)
            {
                ulong ticket = PositionGetTicket(i);
                double volume = PositionGetDouble(POSITION_VOLUME);
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                
                MqlTradeRequest req = {};
                MqlTradeResult res = {};
                req.action = TRADE_ACTION_DEAL;
                req.symbol = _Symbol;
                req.volume = volume;
                req.position = ticket;
                req.price = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                req.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
                req.comment = StringFormat("GUID=%I64u|EMERGENCY_TIMEOUT|%d", PositionGetInteger(POSITION_MAGIC), InpMaxTradeDurationDays);
                req.magic = (int)InpMagicNumber;
                // REGRESSION_GUARD_FILLING: Dynamic filling per symbol
                ulong filling_mode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
                ENUM_ORDER_TYPE_FILLING fill_type = ORDER_FILLING_RETURN;
                if((filling_mode & SYMBOL_FILLING_IOC) != 0) fill_type = ORDER_FILLING_IOC;
                else if((filling_mode & SYMBOL_FILLING_FOK) != 0) fill_type = ORDER_FILLING_FOK;
                req.type_filling = fill_type;

if(OrderSend(req, res))
                 {
                     LogPrint("[EMERGENCY_TIMEOUT] Closed ticket=" + IntegerToString(ticket) +
                              " | age_days=" + IntegerToString(InpMaxTradeDurationDays) +
                              " | result=" + IntegerToString(res.retcode), LOG_LEVEL_ERROR);
                     PM_OnPositionClose((int)ticket);
                     RegisterPositionClose(ticket, "TIMEOUT_" + IntegerToString(InpMaxTradeDurationDays) + "D");
                 }
             }
         }
     }
}

//+------------------------------------------------------------------+
//| GetCachedPOI — POI cache with new-bar and ATR-delta invalidation    |
//| Prevents per-tick recalculation (Fixes 4,002 POI logs in backtest)  |
//+------------------------------------------------------------------+
bool GetCachedPOI(int signalIdx, double currentATR, int currentBar,
                 double &outBuffer, double &outLow, double &outHigh)
{
   if(signalIdx < 0 || signalIdx >= MAX_SLOTS)
      return false;

   bool cacheIsValid = g_poiCache[signalIdx].isValid;
   int cachedBar = g_poiCache[signalIdx].barIndex;
   double cachedATR = g_poiCache[signalIdx].atrValue;
   datetime cachedTime = g_poiCache[signalIdx].calcTime;

bool needRecalc = !cacheIsValid ||
                      (currentBar != cachedBar) ||
                      (TimeCurrent() - cachedTime > 300);

   if(!needRecalc)
   {
      outBuffer = g_poiCache[signalIdx].bufferPrice;
      outLow = g_poiCache[signalIdx].tSpotLow;
      outHigh = g_poiCache[signalIdx].tSpotHigh;
      return true;
   }

   double bufferMult = 0.15;  // ATR removed — fixed 15% fraction
   SSymbolProfile poiProf = SY_GetProfile(_Symbol);
   double tickSize = poiProf.tickSize;
   if(tickSize == 0) tickSize = _Point;
   double dailyHigh = iHigh(_Symbol, PERIOD_D1, 0);
   double dailyLow  = iLow(_Symbol, PERIOD_D1, 0);
   double dailyRange = dailyHigh - dailyLow;
   if(dailyRange <= 0) dailyRange = 50 * _Point;
   double rawBuffer = MathMax(dailyRange * bufferMult, 50 * _Point);
   outBuffer = MathCeil(rawBuffer / tickSize) * tickSize;

   // Dual-registry: determine pool from signalIdx range
   double entry = 0.0;
   if(signalIdx < MAX_SLOTS)
   {
      if(g_activeC2[signalIdx].m_guid != 0)
         entry = g_activeC2[signalIdx].entry_price;
      else if(g_activeC3[signalIdx].m_guid != 0)
         entry = g_activeC3[signalIdx].entry_price;
   }
   outLow = entry - outBuffer;
   outHigh = entry + outBuffer;

   g_poiCache[signalIdx].atrValue = 0.0;  // ATR removed
   g_poiCache[signalIdx].bufferPrice = outBuffer;
   g_poiCache[signalIdx].tSpotLow = outLow;
   g_poiCache[signalIdx].tSpotHigh = outHigh;
   g_poiCache[signalIdx].calcTime = TimeCurrent();
   g_poiCache[signalIdx].barIndex = currentBar;
   g_poiCache[signalIdx].isValid = true;

   LogPrint("[POI_CALC] recalc | buffer=" + DoubleToString(outBuffer, 5) +
            " | tspot=[" + DoubleToString(outLow, _Digits) +
            "," + DoubleToString(outHigh, _Digits) + "]", LOG_LEVEL_DEBUG);
   return true;
}

//+------------------------------------------------------------------+
//| CheckSignalExpiryByTime — Stage-aware time-based signal expiry   |
//| STAGE_WAITING_FOR_POI: InpMaxPOIWaitMinutes from commitTime       |
//| STAGE_WAITING_FOR_CISD: InpMaxCISDWaitMinutes from stageEntryTime |
//| STAGE_READY: InpMaxReadyWaitMinutes from stageEntryTime            |
//|   C2: InpMaxReadyWaitMinutes   C3: InpC3MaxReadyWaitMinutes       |
//| REGRESSION_GUARD_V52_5_C3_TTL                                     |
//+------------------------------------------------------------------+
bool CheckSignalExpiryByTime(const SLockedSignal &sig)
{
   if(sig.m_guid == 0)
      return false;

   datetime now = TimeCurrent();

   switch(sig.stage)
   {
        case STAGE_WAITING_FOR_POI:
        {
           int minutesSinceCommit = (int)((now - sig.commitTime) / 60);
           int poiWaitLimit = (sig.closureType == CLOSURE_C3) ?
                              InpC3MaxPOIWaitMinutes :    // 480 min for C3
                              InpMaxPOIWaitMinutes;        // 240 min for C2

           if(minutesSinceCommit > poiWaitLimit)
           {
              LogPrint(StringFormat("[EXPIRY_POI] GUID=%I64u closure=%s age=%d min > limit=%d",
                       sig.m_guid, sig.closureType == CLOSURE_C3 ? "C3" : "C2",
                       minutesSinceCommit, poiWaitLimit), LOG_LEVEL_WARN);
              return true;
           }
           break;
        }

        case STAGE_WAITING_FOR_CISD:
        {
           int minutesSinceStageEntry = (int)((now - sig.stageEntryTime) / 60);
           if(minutesSinceStageEntry > InpMaxCISDWaitMinutes)
           {
              LogPrint(StringFormat("[EXPIRY_CISD_WAIT] GUID=%I64u stageAge=%d min > max=%d",
                       sig.m_guid, minutesSinceStageEntry, InpMaxCISDWaitMinutes), LOG_LEVEL_WARN);
             return true;
          }
          break;
       }

         case STAGE_READY:
         {
            int readyWaitLimit = (sig.closureType == CLOSURE_C3) ?
                                 InpC3MaxReadyWaitMinutes :    // C3: extended wait for HTF context alignment
                                 InpMaxReadyWaitMinutes;        // C2: standard READY wait

            int minutesSinceStageEntry = (int)((now - sig.stageEntryTime) / 60);
            if(minutesSinceStageEntry > readyWaitLimit)
            {
               LogPrint(StringFormat("[EXPIRY_READY] GUID=%I64u closure=%s stageAge=%d min > limit=%d "
                        "(commitAge=%d min)",
                        sig.m_guid,
                        sig.closureType == CLOSURE_C3 ? "C3" : "C2",
                        minutesSinceStageEntry, readyWaitLimit,
                        (int)((now - sig.commitTime) / 60)), LOG_LEVEL_WARN);
               return true;
            }
            break;
         }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Universal Signal Expiry & Slot Hygiene System                   |
//+------------------------------------------------------------------+
// TTFM-Aligned: Mode/closure-aware timeouts prevent immortal signals
// C2 (Anticipation) expires faster than C3 (Confirmation)

//+------------------------------------------------------------------+
//| GetSignalTimeoutBars - Mode/Closure-Aware Timeout Calculator     |
//+------------------------------------------------------------------+
/**
 * Returns the maximum bars to wait before signal expires.
 * DIFFERENTIATED:
 * - C2 (Anticipation): Shorter timeout (InpC2MaxPOIWaitBars)
 * - C3 (Confirmation): Longer timeout (InpC3MaxPOIWaitBars)
 * - MODE_CONFIRMATION: Even longer timeout for stronger signals
 * - STAGE_AWAITING_C3_CLOSURE: Uses C3 timeout even if originally C2
 */
int GetSignalTimeoutBars(const SLockedSignal &signal)
{
   ENUM_CLOSURE_TYPE closure = signal.closureType;
   ENUM_SIGNAL_STAGE stage = signal.stage;
   int mode = signal.executionMode;

   // REGRESSION_GUARD_TTL: Derive entry TF from branch for TF-aware TTL
   ENUM_TIMEFRAMES entryTf = (signal.branchId == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;

// TF-aware grace bars: M15 gets fewer grace bars than M5 (bar is 3x longer)
    int graceBars = 0;
    if(closure == CLOSURE_C2 || closure == CLOSURE_NONE)
    {
       graceBars = (entryTf == PERIOD_M15) ?
                    MathMax(2, InpGraceBarsAnticipation / 3) : InpGraceBarsAnticipation;
    }
    else if(closure == CLOSURE_C3 || closure == CLOSURE_C4)
    {
      graceBars = (entryTf == PERIOD_M15) ?
                   MathMax(3, InpGraceBarsConfirmation / 3) : InpGraceBarsConfirmation;
   }

   // Stage-specific timeouts
   if(stage == STAGE_AWAITING_C3_CLOSURE)
   {
      // Modal upgrade state: use C3 timeout (longer for confirmation quality)
        int bars = InpC3MaxPOIWaitBars + graceBars;
        if(entryTf == PERIOD_M15) bars = MathMax(4, bars / 3);
        return bars;
   }

      if(stage == STAGE_WAITING_FOR_POI || stage == STAGE_WAITING_FOR_CISD || stage == STAGE_READY)
     {
        int baseBars;
        // POI wait state / CISD wait state - use closure-type specific timeout
        if(closure == CLOSURE_C2)
        {
           // C2 (Anticipation): Shorter timeout - faster expiry + grace
           baseBars = InpC2MaxPOIWaitBars + graceBars;
        }
else if(closure == CLOSURE_C3 || closure == CLOSURE_C4)
        {
           // C3/C4 (Confirmation): Longer timeout - more patient + grace
            baseBars = InpC3MaxPOIWaitBars + graceBars;
        }
        else
        {
           // Unknown closure type - use C2 timeout as default (safer)
           baseBars = InpC2MaxPOIWaitBars + graceBars;
        }
         // REGRESSION_GUARD_V54_3: M15 bars = M5 bars / 3 (M15 candle is 3x M5)
         if(entryTf == PERIOD_M15)
            baseBars = MathMax(4, baseBars / 3);
         return baseBars;
      }

       // Early stages: Use extended timeout (PROMPT_E3: was /2)
       if(stage < STAGE_WAITING_FOR_POI)
      {
         int bars = (InpC2MaxPOIWaitBars + graceBars) / 3 * 2;  // 2/3 of C2 timeout for early stages (was 1/2)
         if(entryTf == PERIOD_M15) bars = MathMax(4, bars / 3);
        return bars;
     }

   // Post-READY stages (EXECUTED, etc.): No timeout needed
   return 0;
}

//+------------------------------------------------------------------+
//| IsSignalStuck - Check if signal is stuck in immortal state       |
//+------------------------------------------------------------------+
bool IsSignalStuck(const SLockedSignal &signal, string &stuckReason)
{
   stuckReason = "";
   ENUM_TIMEFRAMES entryTF = (signal.branchId == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;

// Check 2: Invalid GUID
   if(signal.m_guid == 0)
   {
      stuckReason = "INVALID_GUID";
      return true;
   }

    // Check 3: POI timeout with valid detectionTime
    if(signal.stage == STAGE_WAITING_FOR_POI && signal.m_detectionTime > 0)
    {
       int barsSinceDetection = (int)((TimeCurrent() - signal.m_detectionTime) / PeriodSeconds(entryTF));
       int maxBars = GetSignalTimeoutBars(signal);

       if(barsSinceDetection > maxBars)
       {
          stuckReason = "POI_TIMEOUT";
          return true;
       }
    }

    // Check 3b: CISD wait timeout with valid detectionTime
    if(signal.stage == STAGE_WAITING_FOR_CISD && signal.m_detectionTime > 0)
    {
       int barsSinceDetection = (int)((TimeCurrent() - signal.m_detectionTime) / PeriodSeconds(entryTF));
       int maxBars = GetSignalTimeoutBars(signal);

       if(barsSinceDetection > maxBars)
       {
          stuckReason = "CISD_TIMEOUT";
          return true;
       }
    }

    // Check 4: STAGE_WAITING_FOR_POI with ZERO detectionTime (never progressed)
    if(signal.stage == STAGE_WAITING_FOR_POI && signal.m_detectionTime == 0)
    {
       stuckReason = "POI_ZERO_DETECTIONTIME";
       return true;
    }

   // Check 5: Early stage stuck signals
   if(signal.stage < STAGE_WAITING_FOR_POI && signal.m_detectionTime > 0)
   {
      datetime cutoffTime = TimeCurrent() - (InpMaxPOIWaitBars * PeriodSeconds(entryTF));
      if(signal.m_detectionTime < cutoffTime)
      {
         stuckReason = "EARLY_STAGE_STUCK";
         return true;
      }
   }

   // Check 6: Global 48h timeout
   if(signal.IsExpired())
   {
      stuckReason = "48H_TIMEOUT";
      return true;
   }

   // Check 7: Zombie detection — excessive execution attempts
   if(signal.executionAttempts > 8)
   {
      stuckReason = "ZOMBIE_MAX_ATTEMPTS";
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| PerformSlotHygiene - Aggressive but Safe Slot Reclamation         |
//+------------------------------------------------------------------+
/**
 * Performs comprehensive slot hygiene to prevent immortal signals.
 * Returns the number of slots reclaimed.
 * 
 * Safety rules:
 * 1. Never reclaim slots that have active executions (STAGE_EXECUTED)
 * 2. Never reclaim more slots than needed for new signal
 * 3. Prioritize stuck signals over healthy ones
 * 4. Always log reclamation reason
 */
int PerformSlotHygiene(ENUM_EXECUTION_BRANCH branch, int neededSlots = 1, ENUM_CLOSURE_TYPE filterClosure = CLOSURE_NONE)
{
   int reclaimedCount = 0;
   int maxSignals = (filterClosure != CLOSURE_NONE) ? GetMaxSignalsForClosureType(filterClosure) : MAX_TOTAL_SIGNALS_PER_BRANCH;
   int baseIdx = GetSignalStoreIndex(branch, filterClosure);
   
   int stuckIndices[];
   ArrayResize(stuckIndices, 0);

   for(int i = 0; i < maxSignals; i++)
   {
      int poolSlot = baseIdx + i;
      int idx = poolSlot;
      bool slotActive;
      ENUM_CLOSURE_TYPE slotClosure;
      
      if(filterClosure == CLOSURE_C2 || filterClosure == CLOSURE_NONE)
      {
         slotActive = (g_activeC2[poolSlot].m_guid != 0 && g_activeC2[poolSlot].stage != STAGE_NONE);
         slotClosure = g_activeC2[poolSlot].closureType;
      }
      else
      {
         slotActive = (g_activeC3[poolSlot].m_guid != 0 && g_activeC3[poolSlot].stage != STAGE_NONE);
         slotClosure = g_activeC3[poolSlot].closureType;
      }
      
      if(!slotActive) continue;
      if(filterClosure != CLOSURE_NONE)
      {
         if(filterClosure == CLOSURE_C2 && slotClosure != CLOSURE_C2) continue;
         if((filterClosure == CLOSURE_C3 || filterClosure == CLOSURE_C4) && slotClosure != filterClosure) continue;
      }

      SLockedSignal signal = (filterClosure == CLOSURE_C2 || filterClosure == CLOSURE_NONE) ? g_activeC2[poolSlot] : g_activeC3[poolSlot];
      string stuckReason = "";

      if(IsSignalStuck(signal, stuckReason))
      {
         int sz = ArraySize(stuckIndices);
         ArrayResize(stuckIndices, sz + 1);
         stuckIndices[sz] = poolSlot;
      }
   }

   int signalsToReclaim = MathMin(ArraySize(stuckIndices), neededSlots);
   
   for(int i = 0; i < signalsToReclaim; i++)
   {
      int idx = stuckIndices[i];
      SLockedSignal signal;
      string stuckReason = "";
      
      bool foundInC2 = (filterClosure == CLOSURE_C2 || filterClosure == CLOSURE_NONE) && (g_activeC2[idx].m_guid != 0);
      bool foundInC3 = (filterClosure == CLOSURE_C3 || filterClosure == CLOSURE_C4) && (g_activeC3[idx].m_guid != 0);
      
      if(foundInC2)
         signal = g_activeC2[idx];
      else if(foundInC3)
         signal = g_activeC3[idx];
      else
         continue;

      if(IsSignalStuck(signal, stuckReason))
      {
         LogPrint(StringFormat("[SLOT_HYGIENE] RECLAIMING | slot=%d | GUID=%I64u | reason=%s | closure=%s | stage=%s",
                       idx, signal.m_guid, stuckReason, EnumToString(signal.closureType), EnumToString(signal.stage)), LOG_LEVEL_WARN);
         LogPrint(StringFormat("[SIGNAL_EXPIRED] GUID=%I64u | reason=%s | closure=%s", signal.m_guid, stuckReason, EnumToString(signal.closureType)), LOG_LEVEL_INFO);

         if(foundInC2)
         {
            if(signal.stage == STAGE_READY) g_activeC2[idx].hasFailedRG = true;
            g_activeC2[idx].Reset();
         }
         else
         {
            if(signal.stage == STAGE_READY) g_activeC3[idx].hasFailedRG = true;
            g_activeC3[idx].Reset();
         }
         reclaimedCount++;
      }
   }

   if(reclaimedCount < neededSlots)
   {
      datetime oldestTime = 0;
      int oldestIdx = -1;
      bool oldestIsC2 = true;

      for(int i = 0; i < maxSignals; i++)
      {
         int poolSlot = baseIdx + i;
         bool slotActive;
         SLockedSignal signal;
         bool slotIsC2;
         
         if(filterClosure == CLOSURE_C2 || filterClosure == CLOSURE_NONE)
         {
            slotActive = (g_activeC2[poolSlot].m_guid != 0 && g_activeC2[poolSlot].stage != STAGE_NONE);
            if(slotActive) signal = g_activeC2[poolSlot];
            slotIsC2 = true;
         }
         else
         {
            slotActive = (g_activeC3[poolSlot].m_guid != 0 && g_activeC3[poolSlot].stage != STAGE_NONE);
            if(slotActive) signal = g_activeC3[poolSlot];
            slotIsC2 = false;
         }
         
         if(!slotActive) continue;
         if(filterClosure != CLOSURE_NONE)
         {
            if(filterClosure == CLOSURE_C2 && signal.closureType != CLOSURE_C2) continue;
            if((filterClosure == CLOSURE_C3 || filterClosure == CLOSURE_C4) && signal.closureType != filterClosure) continue;
         }

         string stuckReason = "";
         if(IsSignalStuck(signal, stuckReason)) continue;
         if(signal.stage == STAGE_EXECUTED) continue;
         if(signal.stage == STAGE_READY && !signal.hasFailedRG) continue;

         if(oldestIdx == -1 || signal.lockTime < oldestTime)
         {
            oldestTime = signal.lockTime;
            oldestIdx = poolSlot;
            oldestIsC2 = slotIsC2;
         }
      }

      if(oldestIdx >= 0 && (reclaimedCount + neededSlots) > (maxSignals - ArraySize(stuckIndices)))
      {
         SLockedSignal signal = oldestIsC2 ? g_activeC2[oldestIdx] : g_activeC3[oldestIdx];
         LogPrint(StringFormat("[SLOT_HYGIENE] FORCE_RECLAIM_OLDEST | slot=%d | GUID=%I64u | age=%dmin | closure=%s",
                      oldestIdx, signal.m_guid, (int)(TimeCurrent() - signal.lockTime) / 60, EnumToString(signal.closureType)), LOG_LEVEL_WARN);
         LogPrint(StringFormat("[SIGNAL_OVERWRITTEN] oldGUID=%I64u | reason=SLOT_HYGIENE | closure=%s", signal.m_guid, EnumToString(signal.closureType)), LOG_LEVEL_INFO);

         if(oldestIsC2) g_activeC2[oldestIdx].Reset();
         else g_activeC3[oldestIdx].Reset();
         reclaimedCount++;
      }
   }

   if(reclaimedCount > 0)
   {
      LogPrint(StringFormat("[SLOT_HYGIENE] COMPLETE | branch=%d | reclaimed=%d | needed=%d", branch, reclaimedCount, neededSlots), LOG_LEVEL_INFO);
   }

   return reclaimedCount;
}

//+------------------------------------------------------------------+
//| CheckSignalExpiryEnhanced — Per-signal expiry with PeriodSeconds  |
//+------------------------------------------------------------------+
/**
 * VERBATIM REPAIR: Inv VII Task 6 Expiry — correct unit conversion.
 * Uses PeriodSeconds(entryTF) * barLimit for deterministic expiry.
 */
bool CheckSignalExpiryEnhanced(const SLockedSignal &sig)
{
   long secondsPerBar = PeriodSeconds(sig.entryTF);
    long expirySeconds = secondsPerBar * GetSignalTimeoutBars(sig);
    long ageInSeconds = (long)(TimeCurrent() - sig.lockTime);

   if(ageInSeconds > expirySeconds)
   {
      LogPrint(StringFormat("[SIGNAL_EXPIRY] Age:%d > Limit:%d sec", ageInSeconds, expirySeconds), LOG_LEVEL_WARN);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| CheckAndExpireSignals — Universal expiry scan per branch         |
//+------------------------------------------------------------------+
/**
 * Iterates all signals in a branch, applies CheckSignalExpiryEnhanced,
 * and cleans up expired signals. Wraps the per-signal expiry check.
 */
void CheckAndExpireSignals(ENUM_EXECUTION_BRANCH branch)
{
   int c2base = GetSignalStoreIndex(branch, CLOSURE_C2);
   int c3base = GetSignalStoreIndex(branch, CLOSURE_C3);
   int expiredCount = 0;

   for(int i = c2base; i < c2base + MAX_C2_SIGNALS_PER_BRANCH; i++)
   {
      if(g_activeC2[i].m_guid == 0 || g_activeC2[i].stage == STAGE_NONE) continue;

      SLockedSignal signal = g_activeC2[i];
      if(CheckSignalExpiryEnhanced(signal))
      {
         LogPrint(StringFormat("[SIGNAL_EXPIRED_ENHANCED] GUID=%I64u | closure=%s | mode=%d | stage=%s",
                  signal.m_guid, EnumToString(signal.closureType), signal.executionMode, EnumToString(signal.stage)), LOG_LEVEL_WARN);

         g_activeC2[i].Reset();
         expiredCount++;
      }
   }

   for(int i = c3base; i < c3base + MAX_C3_SIGNALS_PER_BRANCH; i++)
   {
      if(g_activeC3[i].m_guid == 0 || g_activeC3[i].stage == STAGE_NONE) continue;

      SLockedSignal signal = g_activeC3[i];
      if(CheckSignalExpiryEnhanced(signal))
      {
         LogPrint(StringFormat("[SIGNAL_EXPIRED_ENHANCED] GUID=%I64u | closure=%s | mode=%d | stage=%s",
                  signal.m_guid, EnumToString(signal.closureType), signal.executionMode, EnumToString(signal.stage)), LOG_LEVEL_WARN);

         g_activeC3[i].Reset();
         expiredCount++;
      }
   }

   if(expiredCount > 0)
      LogPrint(StringFormat("[EXPIRY_REPORT] branch=%d | expired=%d | remaining=%d", branch, expiredCount, CountActiveSignals(branch)), LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| PerformTTLSignalCleanup — Ruthless TTL garbage collection         |
//| Scans all slots: kills signals with m_detectionTime==0 as corrupt |
//| or exceeding InpMaxPoiWaitBars * entryTF period as TTL timeout.  |
//+------------------------------------------------------------------+
void PerformTTLSignalCleanup()
{
   datetime now = TimeCurrent();

   for(int i = 0; i < MAX_SLOTS; i++)
   {
      // Check C2 pool
      if(g_activeC2[i].m_guid != 0)
      {
         ulong guid = g_activeC2[i].m_guid;
         datetime detectionTime = g_activeC2[i].m_detectionTime;
         ENUM_TIMEFRAMES entryTF = (g_activeC2[i].branchId == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;

         if(detectionTime == 0)
         {
            LogPrint(StringFormat("[SIGNAL_CORRUPT] GUID=%I64u | reason=CORRUPT_NO_TIMESTAMP | idx=C2[%d]", guid, i), LOG_LEVEL_WARN);
            ENUM_EXECUTION_BRANCH signalBranch = (ENUM_EXECUTION_BRANCH)g_activeC2[i].branchId;
            ClearSignalByGUID(signalBranch, guid, "CORRUPT_NO_TIMESTAMP");
            continue;
         }

         int maxBars = GetSignalTimeoutBars(g_activeC2[i]);
         int ttlSeconds = (maxBars > 0) ? maxBars * (int)PeriodSeconds(entryTF) : 0;
         if(ttlSeconds > 0 && now - detectionTime > ttlSeconds)
         {
            if(g_activeC2[i].stage == STAGE_READY)
               g_activeC2[i].hasFailedRG = true;
            LogPrint(StringFormat("[SIGNAL_EXPIRED] GUID=%I64u | reason=TTL_TIMEOUT | idx=C2[%d] | age_sec=%d | closure=%s | maxBars=%d",
                     guid, i, (int)(now - detectionTime), EnumToString(g_activeC2[i].closureType), maxBars), LOG_LEVEL_WARN);
            ENUM_EXECUTION_BRANCH signalBranch = (ENUM_EXECUTION_BRANCH)g_activeC2[i].branchId;
            ClearSignalByGUID(signalBranch, guid, "TTL_TIMEOUT");
         }
      }

      // Check C3 pool
      if(g_activeC3[i].m_guid != 0)
      {
         ulong guid = g_activeC3[i].m_guid;
         datetime detectionTime = g_activeC3[i].m_detectionTime;
         ENUM_TIMEFRAMES entryTF = (g_activeC3[i].branchId == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;

         if(detectionTime == 0)
         {
            LogPrint(StringFormat("[SIGNAL_CORRUPT] GUID=%I64u | reason=CORRUPT_NO_TIMESTAMP | idx=C3[%d]", guid, i), LOG_LEVEL_WARN);
            ENUM_EXECUTION_BRANCH signalBranch = (ENUM_EXECUTION_BRANCH)g_activeC3[i].branchId;
            ClearSignalByGUID(signalBranch, guid, "CORRUPT_NO_TIMESTAMP");
            continue;
         }

         int maxBars = GetSignalTimeoutBars(g_activeC3[i]);
         int ttlSeconds = (maxBars > 0) ? maxBars * (int)PeriodSeconds(entryTF) : 0;
         if(ttlSeconds > 0 && now - detectionTime > ttlSeconds)
         {
            if(g_activeC3[i].stage == STAGE_READY)
               g_activeC3[i].hasFailedRG = true;
            LogPrint(StringFormat("[SIGNAL_EXPIRED] GUID=%I64u | reason=TTL_TIMEOUT | idx=C3[%d] | age_sec=%d | closure=%s | maxBars=%d",
                     guid, i, (int)(now - detectionTime), EnumToString(g_activeC3[i].closureType), maxBars), LOG_LEVEL_WARN);
            ENUM_EXECUTION_BRANCH signalBranch = (ENUM_EXECUTION_BRANCH)g_activeC3[i].branchId;
            ClearSignalByGUID(signalBranch, guid, "TTL_TIMEOUT");
         }
      }
   }

   // Clean stale pending links (TF-aware timeout per §XII)
   for(int i = ArraySize(g_pendingLinks) - 1; i >= 0; i--)
   {
      ENUM_TIMEFRAMES entryTF = GetEntryTF(g_pendingLinks[i].branch);
      int timeoutSec = GetPendingOrderTimeoutSeconds(entryTF);
      if(TimeCurrent() - g_pendingLinks[i].created > timeoutSec)
      {
         PrintFormat("[PENDING_LINK_CLEANUP] request_id=%d guid=%I64u age_sec=%d timeout_sec=%d",
                      g_pendingLinks[i].request_id,
                      g_pendingLinks[i].guid,
                      TimeCurrent() - g_pendingLinks[i].created,
                      timeoutSec);
         ArrayRemove(g_pendingLinks, i, 1);
      }
   }
}

//+------------------------------------------------------------------+
//| CheckPoiTimeout - Expire signals waiting too long for POI touch  |
//+------------------------------------------------------------------+
void CheckPoiTimeout(ENUM_EXECUTION_BRANCH branch)
{
    if(g_maxPoiWaitBars <= 0)
        return;

    int expiredCount = 0;
    ENUM_TIMEFRAMES _entryTfPoi = (branch == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;

    int c2base = GetSignalStoreIndex(branch, CLOSURE_C2);
    int c3base = GetSignalStoreIndex(branch, CLOSURE_C3);

    // Check C2 pool
    for(int i = c2base; i < c2base + MAX_C2_SIGNALS_PER_BRANCH; i++)
    {
        if(g_activeC2[i].m_guid == 0 || g_activeC2[i].stage == STAGE_NONE) continue;
        if(g_activeC2[i].stage != STAGE_WAITING_FOR_POI) continue;
        if(g_activeC2[i].m_detectionTime <= 0) continue;

        int secondsSinceDetection = (int)(TimeCurrent() - g_activeC2[i].m_detectionTime);
        int barsWaited = secondsSinceDetection / PeriodSeconds(_entryTfPoi);
        int warningThreshold = (int)(g_maxPoiWaitBars * 0.75);
        if(warningThreshold < 1) warningThreshold = 1;

        if(!g_activeC2[i].poiWarningLogged && barsWaited >= warningThreshold)
        {
           LogPrint(StringFormat("[POI_WARNING] GUID=%I64u | waitBars=%d | max=%d",
                  g_activeC2[i].m_guid, barsWaited, g_maxPoiWaitBars), LOG_LEVEL_WARN);
           g_activeC2[i].poiWarningLogged = true;
        }

        if(barsWaited > g_maxPoiWaitBars)
        {
            LogPrint(StringFormat("[SIGNAL_EXPIRED] GUID=%I64u | reason=POI_TIMEOUT | barsWaited=%d | maxBars=%d | closure=%s",
                     g_activeC2[i].m_guid, barsWaited, g_maxPoiWaitBars, EnumToString(g_activeC2[i].closureType)), LOG_LEVEL_WARN);
            g_activeC2[i].Reset();
            expiredCount++;
        }
    }

    // Check C3 pool
    for(int i = c3base; i < c3base + MAX_C3_SIGNALS_PER_BRANCH; i++)
    {
        if(g_activeC3[i].m_guid == 0 || g_activeC3[i].stage == STAGE_NONE) continue;
        if(g_activeC3[i].stage != STAGE_WAITING_FOR_POI) continue;
        if(g_activeC3[i].m_detectionTime <= 0) continue;

        int secondsSinceDetection = (int)(TimeCurrent() - g_activeC3[i].m_detectionTime);
        int barsWaited = secondsSinceDetection / PeriodSeconds(_entryTfPoi);
        int warningThreshold = (int)(g_maxPoiWaitBars * 0.75);
        if(warningThreshold < 1) warningThreshold = 1;

        if(!g_activeC3[i].poiWarningLogged && barsWaited >= warningThreshold)
        {
           LogPrint(StringFormat("[POI_WARNING] GUID=%I64u | waitBars=%d | max=%d",
                  g_activeC3[i].m_guid, barsWaited, g_maxPoiWaitBars), LOG_LEVEL_WARN);
           g_activeC3[i].poiWarningLogged = true;
        }

        if(barsWaited > g_maxPoiWaitBars)
        {
            LogPrint(StringFormat("[SIGNAL_EXPIRED] GUID=%I64u | reason=POI_TIMEOUT | barsWaited=%d | maxBars=%d | closure=%s",
                     g_activeC3[i].m_guid, barsWaited, g_maxPoiWaitBars, EnumToString(g_activeC3[i].closureType)), LOG_LEVEL_WARN);
            g_activeC3[i].Reset();
            expiredCount++;
        }
    }

    if(expiredCount > 0)
    {
        LogPrint("[POI_TIMEOUT_REPORT] branch=" + IntegerToString(branch) +
                 " | expired=" + IntegerToString(expiredCount), LOG_LEVEL_INFO);
    }
}

//+------------------------------------------------------------------+
//| CheckSetupLifespan - Setup-level lifespan and         |
//| invalidation per TTrades Pro+ specification                     |
//+------------------------------------------------------------------+
void CheckSetupLifespan(ENUM_EXECUTION_BRANCH branch)
{
    int invalidatedCount = 0;
    int expiredCount = 0;
    int orangeCount = 0;

    int maxBars = (branch == BRANCH_INTRADAY) ? g_InpSetupLifespanBars_Intraday : g_InpSetupLifespanBars_Swing;
    int graceBars = g_InpSetupGraceBars;

    int c2base = GetSignalStoreIndex(branch, CLOSURE_C2);
    int c3base = GetSignalStoreIndex(branch, CLOSURE_C3);

    ENUM_TIMEFRAMES htfBiasTF = (branch == BRANCH_INTRADAY) ? PERIOD_D1 : PERIOD_W1;
    ENUM_TIMEFRAMES structTF  = (branch == BRANCH_INTRADAY) ? PERIOD_H1 : PERIOD_H4;
    ENUM_TIMEFRAMES entryTF   = (branch == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;

    // Process C2 pool
    for(int i = c2base; i < c2base + MAX_C2_SIGNALS_PER_BRANCH; i++)
    {
        if(g_activeC2[i].m_guid == 0 || g_activeC2[i].stage == STAGE_NONE) continue;
        SLockedSignal signal = g_activeC2[i];
        if(signal.m_detectionTime == 0) continue;

        bool isC3Signal = (signal.closureType == CLOSURE_C3);
        string signalTypeLabel = isC3Signal ? "C3" : "C2";

        if(IsSetupStructurallyInvalid(signal))
        {
            LogPrint(StringFormat("[%s_SETUP_INVALIDATED] GUID=%I64u | reason=PRICE_RETURNED_TO_INITIAL_EXTREME | setupIsBullish=%s",
                     signalTypeLabel, signal.m_guid, (signal.m_setupIsBullish ? "YES" : "NO")), LOG_LEVEL_WARN);
            g_activeC2[i].isStructurallyInvalid = true;
            ClearSignalByGUID(branch, signal.m_guid, "SETUP_STRUCTURAL_INVALIDATION");
            invalidatedCount++;
            continue;
        }

        uint secondsElapsed = (uint)(TimeCurrent() - signal.m_detectionTime);
        uint barsInSetup = secondsElapsed / PeriodSeconds(signal.entryTF);

        if((int)barsInSetup > (maxBars + graceBars))
        {
            LogPrint("[C3_SETUP_EXPIRED] GUID: " + IntegerToString(signal.m_guid) + " | age=" + IntegerToString(barsInSetup), LOG_LEVEL_INFO);
            g_activeC2[i].hasFailedRG = true;
            ClearSignalByGUID(branch, signal.m_guid, "TTL_EXPIRED");
            continue;
        }

        if((int)barsInSetup > maxBars && !g_activeC2[i].m_orangeLogged)
        {
            LogPrint(StringFormat("[%s_SETUP_ORANGE] GUID=%I64u | barsInSetup=%d | maxBars=%d | Setup in consolidation state",
                     signalTypeLabel, signal.m_guid, barsInSetup, maxBars), LOG_LEVEL_INFO);
            g_activeC2[i].m_orangeLogged = true;
            orangeCount++;
        }

        if(g_activeC2[i].stage >= STAGE_READY) continue;
        if(ConfirmBranchCISD(_Symbol, structTF, branch))
        {
            if(!g_activeC2[i].TransitionStage(STAGE_WAITING_FOR_POI)) continue;
            LogPrint(StringFormat("[CISD_CONFIRMED] 3-Tier pass | GUID=%I64u | structTF=%s -> entryTF=%s",
                     g_activeC2[i].m_guid, EnumToString(structTF), EnumToString(entryTF)), LOG_LEVEL_INFO);
        }
    }

    // Process C3 pool
    for(int i = c3base; i < c3base + MAX_C3_SIGNALS_PER_BRANCH; i++)
    {
        if(g_activeC3[i].m_guid == 0 || g_activeC3[i].stage == STAGE_NONE) continue;
        SLockedSignal signal = g_activeC3[i];
        if(signal.m_detectionTime == 0) continue;

        bool isC3Signal = (signal.closureType == CLOSURE_C3);
        string signalTypeLabel = isC3Signal ? "C3" : "C2";

        if(IsSetupStructurallyInvalid(signal))
        {
            LogPrint(StringFormat("[%s_SETUP_INVALIDATED] GUID=%I64u | reason=PRICE_RETURNED_TO_INITIAL_EXTREME | setupIsBullish=%s",
                     signalTypeLabel, signal.m_guid, (signal.m_setupIsBullish ? "YES" : "NO")), LOG_LEVEL_WARN);
            g_activeC3[i].isStructurallyInvalid = true;
            ClearSignalByGUID(branch, signal.m_guid, "SETUP_STRUCTURAL_INVALIDATION");
            invalidatedCount++;
            continue;
        }

        uint secondsElapsed = (uint)(TimeCurrent() - signal.m_detectionTime);
        uint barsInSetup = secondsElapsed / PeriodSeconds(signal.entryTF);

        if((int)barsInSetup > (maxBars + graceBars))
        {
            LogPrint("[C3_SETUP_EXPIRED] GUID: " + IntegerToString(signal.m_guid) + " | age=" + IntegerToString(barsInSetup), LOG_LEVEL_INFO);
            g_activeC3[i].hasFailedRG = true;
            ClearSignalByGUID(branch, signal.m_guid, "TTL_EXPIRED");
            continue;
        }

        if((int)barsInSetup > maxBars && !g_activeC3[i].m_orangeLogged)
        {
            LogPrint(StringFormat("[%s_SETUP_ORANGE] GUID=%I64u | barsInSetup=%d | maxBars=%d | Setup in consolidation state",
                     signalTypeLabel, signal.m_guid, barsInSetup, maxBars), LOG_LEVEL_INFO);
            g_activeC3[i].m_orangeLogged = true;
            orangeCount++;
        }

        if(g_activeC3[i].stage >= STAGE_READY) continue;
        if(ConfirmBranchCISD(_Symbol, structTF, branch))
        {
            if(!g_activeC3[i].TransitionStage(STAGE_WAITING_FOR_POI)) continue;
            LogPrint(StringFormat("[CISD_CONFIRMED] 3-Tier pass | GUID=%I64u | structTF=%s -> entryTF=%s",
                     g_activeC3[i].m_guid, EnumToString(structTF), EnumToString(entryTF)), LOG_LEVEL_INFO);
        }
    }

    if(invalidatedCount > 0 || expiredCount > 0)
    {
      LogPrint(StringFormat("[SETUP_CLEANUP_REPORT] branch=%d | invalidated=%d | expired=%d | orange=%d",
          branch, invalidatedCount, expiredCount, orangeCount), LOG_LEVEL_INFO);
    }
}

//+------------------------------------------------------------------+
//| IsSymbolPermanentlySkipped — Check if symbol is on permanent-skip |
//| list per AGENTS.md §XII. Called by closure engine before          |
//| re-detecting a setup that was rejected for affordability.         |
//+------------------------------------------------------------------+
bool IsSymbolPermanentlySkipped(const string symbol)
{
   for(int i = 0; i < g_permanentSkipCount; i++)
   {
      if(g_permanentSkipSymbols[i] == symbol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| AddPermanentSkip — Add symbol to permanent-skip list              |
//| Records [PERMANENT_SKIP] marker per AGENTS.md §XII.              |
//+------------------------------------------------------------------+
void AddPermanentSkip(const string symbol, const string reason)
{
   // Check if already skipped
   if(IsSymbolPermanentlySkipped(symbol))
      return;

   ArrayResize(g_permanentSkipSymbols, g_permanentSkipCount + 1);
   g_permanentSkipSymbols[g_permanentSkipCount] = symbol;
   g_permanentSkipCount++;

   LogPrint("[PERMANENT_SKIP] symbol=" + symbol +
            " | reason=" + reason +
            " | totalSkipped=" + IntegerToString(g_permanentSkipCount), LOG_LEVEL_WARN);
}

//+------------------------------------------------------------------+
//| PerformTradeabilityCheck — Periodic affordability re-verification |
//| Runs at most once per InpTradeabilityRecheckBars bars on entry TF.|
//| Calls IsLotTradeable() with current equity and symbol profile to  |
//| detect when a symbol becomes unaffordable mid-session.            |
//|                                                                   |
//| Emits canonical markers:                                          |
//|   [TRADEABILITY_CHECK] — each periodic check                      |
//|   [TRADEABILITY_FAIL] — transition to untradeable                 |
//|   [TRADEABILITY_RECOVERED] — transition back to tradeable         |
//|   [PERMANENT_SKIP] — when session-permanent rejection occurs      |
//+------------------------------------------------------------------+
void PerformTradeabilityCheck(ENUM_EXECUTION_BRANCH branch)
{
   // Determine entry TF for this branch
   ENUM_TIMEFRAMES entryTF = (branch == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;
   int branchIdx = (branch == BRANCH_INTRADAY) ? 0 : 1;

   // Throttle: check at most once per InpTradeabilityRecheckBars bars
   datetime currentBarTime = iTime(_Symbol, entryTF, 0);
   if(currentBarTime == g_lastTradeabilityCheckBar[branchIdx])
      return;

   // Calculate bar count since last check
   if(g_lastTradeabilityCheckBar[branchIdx] > 0)
   {
      int barsSinceLastCheck = (int)((currentBarTime - g_lastTradeabilityCheckBar[branchIdx]) / PeriodSeconds(entryTF));
      if(barsSinceLastCheck < g_InpTradeabilityRecheckBars)
         return;
   }

   g_lastTradeabilityCheckBar[branchIdx] = currentBarTime;

   // Get current account and symbol data
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
   {
      LogPrint("[TRADEABILITY_CHECK] branch=" + IntegerToString(branch) +
               " | equity=0 | skip", LOG_LEVEL_DEBUG);
      return;
   }

   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(currentBid <= 0.0 || currentAsk <= 0.0)
   {
      LogPrint("[TRADEABILITY_CHECK] branch=" + IntegerToString(branch) +
               " | invalid prices bid=" + DoubleToString(currentBid) +
               " ask=" + DoubleToString(currentAsk), LOG_LEVEL_DEBUG);
      return;
   }

    bool wasUntradeable = g_symbolUntradeable;

    // VERBATIM REPAIR: Manual Currency Risk (§V)
    // Ensures risk is calculated in actual USD, bypassing 100x 'pips mode' inflation.
    SSymbolProfile tickProf = SY_GetProfile(_Symbol);
    double tickValue = tickProf.tickValue;
    double tickSize  = tickProf.tickSize;
    double minLot    = tickProf.volumeMin;

    ENUM_TIMEFRAMES structureTF = (branch == BRANCH_INTRADAY) ? PERIOD_H1 : PERIOD_H4;
    double itfHigh = iHigh(_Symbol, structureTF, 1);
    double itfLow  = iLow(_Symbol, structureTF, 1);

    double structuralSLDist = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_ASK) - itfLow, itfHigh - SymbolInfoDouble(_Symbol, SYMBOL_BID));

    if (structuralSLDist <= 0)
    {
       SSymbolProfile spSL = SY_GetProfile(_Symbol);
       long slMin = spSL.stopsLevel;
       if(slMin <= 0) slMin = 100;
       structuralSLDist = slMin * spSL.point * InpMinStopBuffer;
    }

    // Formula: (Price Distance / TickSize) * TickValue * Volume
    double minLotRisk = (structuralSLDist / tickSize) * tickValue * minLot;
    double riskPercent = (equity > 0) ? (minLotRisk / equity * 100.0) : 100.0;

    // VERBATIM REPAIR: The Affordability Bridge (§XIII)
    // Determines structural permission at a wider band (g_riskPercentAffordMin, e.g. 20%) while
    // sizing execution risk at a narrow band (g_riskPercentTrade, e.g. 1%).
    bool isTradeable = (riskPercent <= g_riskPercentAffordMin);

    g_symbolUntradeable = !isTradeable;

    if (g_symbolUntradeable)
    {
        if (!wasUntradeable)
        {
            g_symbolUntradeableReason = "AFFORDABILITY";
            LogPrint(StringFormat("[RISK_BLOCK] MinLot risk %.2f%% exceeds %.2f%% bridge. | %s",
                     riskPercent, g_riskPercentAffordMin, _Symbol), LOG_LEVEL_WARN);
        }
        else
        {
            LogPrint(StringFormat("[TRADEABILITY_CHECK] %s | Risk=%.2f%% | status=UNTRADEABLE",
                     _Symbol, riskPercent), LOG_LEVEL_DEBUG);
        }
    }
    else
    {
        if (wasUntradeable)
        {
            g_symbolUntradeableReason = "";
            LogPrint(StringFormat("[TRADEABILITY_RECOVERED] %s | equity=%.2f", _Symbol, equity), LOG_LEVEL_INFO);
        }
        else
        {
            LogPrint(StringFormat("[TRADEABILITY_CHECK] %s | Risk=%.2f%% | status=TRADEABLE",
                     _Symbol, riskPercent), LOG_LEVEL_DEBUG);
        }
    }
}

//+------------------------------------------------------------------+
//| GetSlotOccupancy - Report current slot usage for branch          |
//+------------------------------------------------------------------+
void GetSlotOccupancy(ENUM_EXECUTION_BRANCH branch, int &total, int &active, int &stuck)
{
   total = MAX_TOTAL_SIGNALS_PER_BRANCH;
   active = 0;
   stuck = 0;

   int c2base = GetSignalStoreIndex(branch, CLOSURE_C2);
   int c3base = GetSignalStoreIndex(branch, CLOSURE_C3);

   for(int i = c2base; i < c2base + MAX_C2_SIGNALS_PER_BRANCH; i++)
   {
      if(g_activeC2[i].m_guid != 0 && g_activeC2[i].stage != STAGE_NONE)
      {
         active++;
         string stuckReason = "";
         if(IsSignalStuck(g_activeC2[i], stuckReason))
            stuck++;
      }
   }
   for(int i = c3base; i < c3base + MAX_C3_SIGNALS_PER_BRANCH; i++)
   {
      if(g_activeC3[i].m_guid != 0 && g_activeC3[i].stage != STAGE_NONE)
      {
         active++;
         string stuckReason = "";
         if(IsSignalStuck(g_activeC3[i], stuckReason))
            stuck++;
      }
   }
}

//+------------------------------------------------------------------+
//| SetTickPrices - Tick price setter                                 |
//+------------------------------------------------------------------+
void SetTickPrices(double ask, double bid)
{
   g_tickAsk = ask;
   g_tickBid = bid;
   g_useTickPrices = true;
}

void ResetTickPrices()
{
   g_useTickPrices = false;
}

void GetCurrentPrices(double &ask, double &bid)
{
   if(InpUseTickIterator && g_useTickPrices)
   {
      ask = g_tickAsk;
      bid = g_tickBid;
   }
   else
   {
      ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
}

//+------------------------------------------------------------------+
//| CENTRALIZED LOGGING SYSTEM (PHASE 9 FINAL)                            |
//+------------------------------------------------------------------+
//| ALL logging centralized into ONE function - NO scattered Print() calls     |
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| MODE PREREQUISITE VALIDATION (TTrades + Dow Theory)               |
//+------------------------------------------------------------------+
// Validates that the current branch context meets the strict mode-specific
// entrance criteria. This is the canonical gate that enforces:
//   • D1 bias must be directional (NEUTRAL blocked for all modes)
//   • HTF structure must be tradeable (RANGE blocked)
//   • MODE_ANTICIPATION requires TRANSITION state + locked LTF C2/C3
//   • MODE_CONFIRMATION requires TREND state + LT_ERL liquidity
//
//+------------------------------------------------------------------+
//| MODE PREREQ Per-Bar Rate Limiting Helper                              |
//|                                                                  |
//| Logging is rate-limited, NOT execution. Function still runs every tick.        |
//+------------------------------------------------------------------+
static datetime s_prereqLastBar = 0;
static string  s_prereqLastMsg = "";

bool LogPrereqOncePerBar(const string reasonKey, const string fullMsg)
{
   if(!InpEnableTrace) return false;
   
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // New bar: reset suppression state
   if(currentBar != s_prereqLastBar)
   {
      s_prereqLastBar = currentBar;
      s_prereqLastMsg = "";
   }
   
   // Same bar, same reason: suppress duplicate log
   if(s_prereqLastMsg == reasonKey)
      return false;
   
   // First log for this reason on this bar
   s_prereqLastMsg = reasonKey;
   LogPrint(fullMsg, LOG_LEVEL_WARN);
   return true;
}

//
// Called BEFORE FinalExecutionGuard() to filter mode eligibility early.
//+------------------------------------------------------------------+
bool ValidateModePrerequisites(const BranchContext &ctx)
{
// ── UNIVERSAL BLOCK 1: Hierarchy of Truth — Dow Theory Decoupling ──────────────────
   // PRIMARY:   Structure TF (H1/H4) provides the "Immediate Environment"
   // SECONDARY: D1 provides the "Macro Consensus"
   // RULE: If Structure TF is BULLISH/BEARISH, the trade MUST proceed even if D1 is NEUTRAL
   
   // Get D1 bias (Macro Consensus)
   BiasType d1Bias = DailyClosureBias(_Symbol);
   ENUM_DIRECTION d1BiasDir = DIRECTION_NONE;
   if(d1Bias == BIAS_BULLISH) d1BiasDir = DIRECTION_BUY;
   else if(d1Bias == BIAS_BEARISH) d1BiasDir = DIRECTION_SELL;
   
   // Get Structure TF bias (Immediate Environment) — PRIMARY gate
   ENUM_TIMEFRAMES structureTF = ctx.structureTF;
   BiasOutput structureBias = BR_AnalyzeBias(_Symbol, structureTF);
   ENUM_DIRECTION structureBiasDir = DIRECTION_NONE;
   if(structureBias.bias == BIAS_BULLISH) structureBiasDir = DIRECTION_BUY;
   else if(structureBias.bias == BIAS_BEARISH) structureBiasDir = DIRECTION_SELL;
   
   // CASE 1: Structure TF is BULLISH/BEARISH → OVERRIDE D1 NEUTRAL
   if(d1Bias == BIAS_NEUTRAL && structureBiasDir != DIRECTION_NONE)
   {
      LogPrereqOncePerBar("BIAS_OVERRIDE", "[GATE] D1 NEUTRAL - Overriding with Structure TF Bias (" + EnumToString(structureBias.bias) + ")");
   }
   // CASE 2: Both neutral → total deadlock
   else if(d1Bias == BIAS_NEUTRAL && structureBiasDir == DIRECTION_NONE)
   {
      LogPrereqOncePerBar("FULL_NEUTRAL", "[MODE PREREQ] BLOCK: D1 + Structure TF both NEUTRAL");
      return false;
   }
   // CASE 3: Structure neutral but D1 directional → allow (use D1 as fallback)
   else if(structureBiasDir == DIRECTION_NONE && d1BiasDir != DIRECTION_NONE)
   {
      LogPrereqOncePerBar("STRUCT_NEUTRAL_D1_DIR", "[GATE] Structure TF neutral — using D1 Macro Consensus");
   }
   
   // Log D1/Structure TF bias divergence (info only, no block)
   if(d1BiasDir != DIRECTION_NONE && structureBiasDir != DIRECTION_NONE && d1BiasDir != structureBiasDir)
   {
      LogPrereqOncePerBar("BIAS_DIVERGENCE", "[MODE_DECOUPLE] D1 bias differs from " + EnumToString(structureTF) + 
          " structure — using " + EnumToString(structureTF) + " as PRIMARY (Dow Theory Secondary)");
   }

   // ── UNIVERSAL BLOCK 2: Range market — no tradeable structure ────────────
   // Per Dow Theory: sideways consolidation produces no directional signal.
   // SSE routing to STRATEGY_RANGE represents this condition.
   MarketStrategy htfStrategy = SSE_OutputToStrategy(ctx.sse);
   if(htfStrategy == STRATEGY_RANGE)
   {
      LogPrereqOncePerBar("RANGE", "[MODE PREREQ] BLOCK: SSE=RANGE - Dow Theory: no signal in consolidation");
      return false;
   }

// ── MODE-SPECIFIC VALIDATION ───────────────────────────────────────────
   // Use pre-computed d1Bias and structureBias from Hierarchy of Truth above
   
   if(ctx.mode.mode == MODE_ANTICIPATION)
   {
      // === TTRADES GATE: Structure TF bias must be established BEFORE H4 C2 can unlock Anticipation ===
      // Hierarchy of Truth: Structure TF is PRIMARY, D1 is SECONDARY
      // Block ONLY if Structure TF is neutral (primary environment has no direction)
if(structureBiasDir == DIRECTION_NONE)
       {
          LogPrereqOncePerBar("ANTI_STRUCT_NEUTRAL",
             "[ANTICIPATION_GATE] LOCK — Structure TF neutral, prerequisite missing");
          LogPrint("[MODE_PREREQ_FAIL] MODE_ANTICIPATION | REASON: Structure bias NONE", LOG_LEVEL_INFO);
          return false;
       }
      
      // D1 confirmation for audit trail (secondary)
      LogPrereqOncePerBar("ANTI_D1_CHECK",
         "[ANTICIPATION_GATE] UNLOCK — Structure=" + EnumToString(structureBias.bias) + " | D1=" + EnumToString(d1Bias));

      // Anticipation Prereq A: HTF must be in TRANSITION.
      // Price beyond C2 extreme, HTF candle still forming (not yet confirmed C2/C3).
if(htfStrategy != STRATEGY_TRANSITION)
        {
           string antiTransMsg = "[MODE PREREQ] ANTICIPATION BLOCK: SSE not TRANSITION (got " +
                             EnumToString(htfStrategy) + ") - Anticipation requires HTF in transition";
           LogPrereqOncePerBar("ANTI_TRANS", antiTransMsg);
           LogPrint("[MODE_PREREQ_FAIL] MODE_ANTICIPATION | REASON: HTF not TRANSITION | htfStrategy=" + EnumToString(htfStrategy), LOG_LEVEL_INFO);
           return false;
        }

        // OPTION A: Resolve active signal from store, not ctx
        SLockedSignal activeSignal;
        ZeroMemory(activeSignal);
        bool hasActiveSignal = false;
        int c2Base = (ctx.branch == BRANCH_INTRADAY) ? 0 : MAX_C2_SIGNALS_PER_BRANCH;
        int c3Base = (ctx.branch == BRANCH_INTRADAY) ? 0 : MAX_C3_SIGNALS_PER_BRANCH;
        for(int i = 0; i < MAX_C2_SIGNALS_PER_BRANCH; i++)
        {
            int poolIdx = c2Base + i;
            if(g_activeC2[poolIdx].m_guid != 0)
            {
                activeSignal = g_activeC2[poolIdx];
                hasActiveSignal = true;
                break;
            }
        }
        if(!hasActiveSignal)
        {
            for(int i = 0; i < MAX_C3_SIGNALS_PER_BRANCH; i++)
            {
                int poolIdx = c3Base + i;
                if(g_activeC3[poolIdx].m_guid != 0)
                {
                    activeSignal = g_activeC3[poolIdx];
                    hasActiveSignal = true;
                    break;
                }
            }
        }
        if(!hasActiveSignal)
        {
            LogPrereqOncePerBar("ANTI_NO_SIGNAL", "[MODE PREREQ] ANTICIPATION BLOCK: No active signal in store");
            return false;
        }

// Anticipation Prereq B: A valid LTF signal must be locked.
       // DECOUPLED: C2 (Sweep) triggers immediately on detection, C3 must wait for closure.
       // - C2 signals: Can pass at STAGE_LOCKED (immediate wick entry)
       // - C3 signals: Must reach STAGE_WAITING_FOR_POI or AWAITING_CLOSURE states
LogPrint("[DEBUG] Stage Check | Current Stage: " + EnumToString(activeSignal.stage) + " | ClosureType: " + EnumToString(activeSignal.closureType), LOG_LEVEL_DEBUG);

        bool isC2Signal = (activeSignal.closureType == CLOSURE_C2);
        bool isC3Signal = (activeSignal.closureType == CLOSURE_C3);
        bool hasValidStage = false;
        static ENUM_SIGNAL_STAGE s_lastLoggedAntiStage = STAGE_NONE;
        
if(isC2Signal)
        {
           // C2 (Sweep): Allow immediate trigger at any active stage (including STAGE_LOCKED)
hasValidStage = (activeSignal.stage == STAGE_LOCKED ||
                          activeSignal.stage == STAGE_AWAITING_C2_CLOSURE ||
                          activeSignal.stage == STAGE_WAITING_FOR_POI ||
                          activeSignal.stage == STAGE_READY);
        }
else if(isC3Signal)
        {
           // C3 (Displacement): Must wait for POI/closure confirmation
hasValidStage = (activeSignal.stage == STAGE_WAITING_FOR_POI ||
                          activeSignal.stage == STAGE_AWAITING_C3_CLOSURE);
        }
       
if(!hasValidStage)
        {
           string failReason = isC2Signal ? "C2 signal not at active stage" : "C3 signal not at POI/closure";
if(activeSignal.stage != s_lastLoggedAntiStage)
            {
               LogPrint("[MODE PREREQ] ANTICIPATION BLOCK: " + failReason + " | Stage=" + EnumToString(activeSignal.stage), LOG_LEVEL_INFO);
               s_lastLoggedAntiStage = activeSignal.stage;
            }
           return false;
        }

// Anticipation Prereq C: LTF signal direction must align with Structure TF Bias (PRIMARY)
      ENUM_DIRECTION lockedDir = activeSignal.direction;
      
      // Critical alignment: LTF must align with Structure TF (Dow Theory Secondary = immediate environment)
      if(lockedDir != structureBiasDir)
      {
         // PHASE 3: Check if reversals are allowed in Anticipation mode
         if(g_trueTTradesConfig.allowAnticipationReversals)
         {
            // Allow counter-structure entries (reversals) in Anticipation mode
            LogPrereqOncePerBar("ANTI_REVERSAL", "[PHASE 3] Anticipation reversal ALLOWED | Structure=" + EnumToString(structureBiasDir) + " | Signal=" + EnumToString(lockedDir));
         }
         else
         {
            LogPrereqOncePerBar("ANTI_DIR", "[MODE_DECOUPLE] " + EnumToString(structureTF)
                + " Structure intact (" + EnumToString(structureBias.bias) + "), decoupling from D1 Bias");
            return false;
         }
      }

      // PHASE 3: Check R:R requirement for Anticipation mode
      double signalRR = activeSignal.rr;
      double minRR = g_trueTTradesConfig.anticipationMinRR;
      if(signalRR < minRR)
      {
         LogPrereqOncePerBar("ANTI_RR", "[PHASE 3] Anticipation R:R below minimum | actual=" + DoubleToString(signalRR, 2) + " | required=" + DoubleToString(minRR, 2));
         LogPrint("[MODE_PREREQ_FAIL] MODE_ANTICIPATION | REASON: RR too low | actual=" + DoubleToString(signalRR, 2) + " | min=" + DoubleToString(minRR, 2), LOG_LEVEL_INFO);
         return false;
      }

      // LT_IRL liquidity is permitted for Anticipation (LF sweep inside HTF body).
      return true;
   }

if(ctx.mode.mode == MODE_CONFIRMATION)
   {
      // === TTRADES GATE: Hierarchy of Truth — Structure TF is PRIMARY for Confirmation Mode ===
      // Structure TF provides the immediate environment, D1 provides macro consensus
      // Block ONLY if Structure TF is neutral (primary environment has no direction)
if(structureBiasDir == DIRECTION_NONE)
       {
          LogPrereqOncePerBar("CONF_STRUCT_NEUTRAL",
             "[CONFIRMATION_GATE] LOCK — Structure TF neutral, prerequisite missing");
          LogPrint("[MODE_PREREQ_FAIL] MODE_CONFIRMATION | REASON: Structure bias NONE", LOG_LEVEL_INFO);
          return false;
       }

      // Log Confirmation mode activation with both biases
       LogPrereqOncePerBar("CONF_GATE",
          "[CONFIRMATION_GATE] UNLOCK — Structure=" + EnumToString(structureBias.bias) + " | D1=" + EnumToString(d1Bias));

      // Confirmation Prereq A: HTF must be TREND or TRANSITION (C2 or C3 closed).
if(htfStrategy != STRATEGY_TREND && htfStrategy != STRATEGY_TRANSITION)
       {
          string confTrendMsg = "[MODE PREREQ] CONFIRMATION BLOCK: SSE not TREND or TRANSITION (got " +
                           EnumToString(htfStrategy) + ")";
          LogPrereqOncePerBar("CONF_TREND", confTrendMsg);
          LogPrint("[MODE_PREREQ_FAIL] MODE_CONFIRMATION | REASON: HTF not TREND/TRANSITION | htfStrategy=" + EnumToString(htfStrategy), LOG_LEVEL_INFO);
          return false;
       }

// Confirmation Prereq B: Liquidity must be ERL (external liquidity swept).
      if(ctx.liquidity.tier != LT_ERL)
      {
         string confErlMsg = "[MODE PREREQ] CONFIRMATION BLOCK: Liquidity not ERL (got " +
                          EnumToString(ctx.liquidity.tier) + ") - Confirmation requires external liquidity";
         LogPrereqOncePerBar("CONF_ERL", confErlMsg);
         LogPrint("[MODE_PREREQ_FAIL] MODE_CONFIRMATION | REASON: Liquidity tier not LT_ERL | tier=" + EnumToString(ctx.liquidity.tier), LOG_LEVEL_INFO);
         return false;
      }
      
      // PHASE 3: Check R:R requirement for Confirmation mode
      double minRRConf = g_trueTTradesConfig.confirmationMinRR;
      bool hasValidRR = true;
      
      // Check signal RR if available
      int c2Base = (ctx.branch == BRANCH_INTRADAY) ? 0 : MAX_C2_SIGNALS_PER_BRANCH;
      int c3Base = (ctx.branch == BRANCH_INTRADAY) ? 0 : MAX_C3_SIGNALS_PER_BRANCH;
      bool rrFound = false;
      for(int i = 0; i < MAX_C2_SIGNALS_PER_BRANCH; i++)
      {
         int poolIdx = c2Base + i;
         if(g_activeC2[poolIdx].m_guid != 0)
         {
            rrFound = true;
            double signalRR = g_activeC2[poolIdx].rr;
            if(signalRR > 0 && signalRR < minRRConf)
            {
               hasValidRR = false;
               LogPrereqOncePerBar("CONF_RR", "[PHASE 3] Confirmation R:R below minimum | actual=" + DoubleToString(signalRR, 2) + " | required=" + DoubleToString(minRRConf, 2));
               break;
            }
         }
      }
      if(!rrFound)
      {
         for(int i = 0; i < MAX_C3_SIGNALS_PER_BRANCH; i++)
         {
            int poolIdx = c3Base + i;
            if(g_activeC3[poolIdx].m_guid != 0)
            {
               rrFound = true;
               double signalRR = g_activeC3[poolIdx].rr;
               if(signalRR > 0 && signalRR < minRRConf)
               {
                  hasValidRR = false;
                  LogPrereqOncePerBar("CONF_RR", "[PHASE 3] Confirmation R:R below minimum | actual=" + DoubleToString(signalRR, 2) + " | required=" + DoubleToString(minRRConf, 2));
                  break;
               }
            }
         }
      }
      if(!hasValidRR)
      {
         LogPrint("[MODE_PREREQ_FAIL] MODE_CONFIRMATION | REASON: RR too low", LOG_LEVEL_INFO);
         return false;
      }

      return true;
    }

    // FIXED: Soft fallback for MODE_NONE (Priority 5) — try to infer from locked signal
    // If mode is NONE but we have a valid signal locked, try to derive mode from signal properties
    if(ctx.mode.mode == MODE_NONE)
    {
        // Look for active signal in store
        SLockedSignal activeSignal;
        ZeroMemory(activeSignal);
        bool hasActive = false;
        int c2Base = (ctx.branch == BRANCH_INTRADAY) ? 0 : MAX_C2_SIGNALS_PER_BRANCH;
        int c3Base = (ctx.branch == BRANCH_INTRADAY) ? 0 : MAX_C3_SIGNALS_PER_BRANCH;
        for(int i = 0; i < MAX_C2_SIGNALS_PER_BRANCH; i++)
        {
            int poolIdx = c2Base + i;
            if(g_activeC2[poolIdx].m_guid != 0)
            {
                activeSignal = g_activeC2[poolIdx];
                hasActive = true;
                break;
            }
        }
        if(!hasActive)
        {
            for(int i = 0; i < MAX_C3_SIGNALS_PER_BRANCH; i++)
            {
                int poolIdx = c3Base + i;
                if(g_activeC3[poolIdx].m_guid != 0)
                {
                    activeSignal = g_activeC3[poolIdx];
                    hasActive = true;
                    break;
                }
            }
        }
        
        if(hasActive && activeSignal.closureType != CLOSURE_NONE)
        {
            static int s_fallbackLogCounter = 0;
            bool shouldLog = (++s_fallbackLogCounter % 50 == 1);  // Log every 50th occurrence
            
            // Check if we have a cached mode for this signal GUID first
            EntryMode cachedMode = GetCachedModeForGUID(activeSignal.m_guid);
            if(cachedMode != MODE_NONE)
            {
                // Use cached mode instead of re-deriving
                if(shouldLog)
                    LogPrint("[MODE_PREREQ_FALLBACK] Using cached mode for GUID=" + IntegerToString(activeSignal.m_guid), LOG_LEVEL_DEBUG);
                return true;
            }
            
            // Derive mode from closure type: C2 → ANTICIPATION, C3 → CONFIRMATION
            if(activeSignal.closureType == CLOSURE_C2)
            {
                SetCachedModeForGUID(activeSignal.m_guid, MODE_ANTICIPATION);  // Cache the derived mode
                if(shouldLog)
                    LogPrint("[MODE_PREREQ_FALLBACK] C2 closure detected - allow with ANTICIPATION", LOG_LEVEL_DEBUG);
                return true;  // Allow with inferred mode (caller will handle mode)
            }
            else if(activeSignal.closureType == CLOSURE_C3)
            {
                SetCachedModeForGUID(activeSignal.m_guid, MODE_CONFIRMATION);  // Cache the derived mode
                // FIXED: Avoid modifying potentially const struct
                ModeOutput tempMode = ctx.mode;
                tempMode.mode = MODE_CONFIRMATION;
                // Note: We don't assign back to ctx.mode to avoid const issues
                if(shouldLog)
                    LogPrint("[MODE_PREREQ_FALLBACK] C3 closure detected - allow with CONFIRMATION", LOG_LEVEL_DEBUG);
                return true;  // Allow with inferred mode
            }
        }
    }

    // MODE_NONE or unrecognised mode — block.
    string noneMsg = "[MODE PREREQ] BLOCK: Mode=" + EnumToString(ctx.mode.mode) + " - not tradeable";
    LogPrereqOncePerBar("MODE_NONE", noneMsg);
    return false;
}

//+------------------------------------------------------------------+
//| BuildRiskSnapshot — Quick snapshot builder for RiskGate compliance |
//+------------------------------------------------------------------+
SSignalSnapshotRisk BuildRiskSnapshot(
    SLockedSignal &signal,
    ENUM_EXECUTION_BRANCH branch,
    double stopLoss,
    double tpPrice,
    double calculatedLot = 0.0
)
{
    ENUM_TIMEFRAMES structTF = (branch == BRANCH_SWING) ? PERIOD_H4 : PERIOD_H1;
    ENUM_TIMEFRAMES entryTF = (branch == BRANCH_SWING) ? PERIOD_M15 : PERIOD_M5;
    SSignalSnapshotRisk snap;
    RG_CreateSnapshot(snap, signal, calculatedLot,
        _Symbol, entryTF, structTF, TimeCurrent(), "Branch" + IntegerToString(branch),
        MathAbs(signal.entry_price - stopLoss) / _Point,
        signal.direction, tpPrice, signal.closureType,
        signal.c2_low, signal.c2_high,
        signal.executionMode
    );
    return snap;
}
// REGRESSION_GUARDBUILD_RISK_SNAPSHOT

//+------------------------------------------------------------------+
//| FINAL EXECUTION GUARD — Routes to RiskGate before OrderSend      |
//+------------------------------------------------------------------+
//| Creates a risk snapshot and calls PreTradeReadinessGate as the     |
//| final compliance gate before any order is dispatched. Emits        |
//| [RG_GATE_PASS] / [RG_GATE_FAIL] lifecycle markers.                |
//| Symbol-agnostic: uses SymbolInfo* for all property access.         |
//+------------------------------------------------------------------+
bool FinalExecutionGuard(
    SLockedSignal &execSig,
    int signalIdx,
    ENUM_EXECUTION_BRANCH branch,
    double stopLoss,
    double tpPrice
)
{
    SSymbolProfile fegProf = SY_GetProfile(_Symbol);
    double slDist = MathAbs(execSig.entry_price - stopLoss) / fegProf.point;
    if(slDist <= 0.0)
    {
        LogPrint(StringFormat("[RG_GATE_FAIL] GUID=%I64u | reason=SL_DISTANCE_ZERO | step=FinalExecutionGuard",
                 execSig.m_guid), LOG_LEVEL_ERROR);
        return false;
    }

    ENUM_TIMEFRAMES structTF = (branch == BRANCH_SWING) ? PERIOD_H4 : PERIOD_H1;
    ENUM_TIMEFRAMES entryTF = (branch == BRANCH_SWING) ? PERIOD_M15 : PERIOD_M5;

    SSignalSnapshotRisk snap;
    RG_CreateSnapshot(snap, execSig, 0.0,
        _Symbol, entryTF, structTF, TimeCurrent(), "Branch" + IntegerToString(branch), slDist,
        execSig.direction, tpPrice, execSig.closureType,
        execSig.c2_low, execSig.c2_high,
        execSig.executionMode);

    ENUM_RG_FAIL rgResult = PreTradeReadinessGate(snap);
    if(rgResult != RG_FAIL_NONE)
    {
        LogPrint(StringFormat("[RG_GATE_FAIL] GUID=%I64u | reason=%s | step=FinalExecutionGuard",
                 execSig.m_guid, EnumToString(rgResult)), LOG_LEVEL_WARN);
        return false;
    }

    if(!execSig.passedRG)
    {
        execSig.passedRG = true;
        if(signalIdx >= 0 && signalIdx < MAX_SLOTS)
        {
            // Only write to the pool that owns this signal
            if (execSig.closureType == CLOSURE_C2) {
                g_activeC2[signalIdx].passedRG = true;
            } else if (execSig.closureType == CLOSURE_C3 || execSig.closureType == CLOSURE_C4) {
                g_activeC3[signalIdx].passedRG = true;
            }
        }
        LogPrint(StringFormat("[RG_GATE_PASS] GUID=%I64u | All criteria validated | step=FinalExecutionGuard",
                 execSig.m_guid), LOG_LEVEL_INFO);
    }
    // REGRESSION_GUARDFEG
    return true;
}

// VERBATIM REPAIR: RG_EvaluateExecutionGate — minLot affordability gate with synced SL
bool RG_EvaluateExecutionGate(SLockedSignal &signal, double activeRiskPct)
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity <= 0.0)
    {
        LogPrint(StringFormat("[RG_GATE_FAIL] GUID=%I64u | reason=EQUITY_ZERO | step=RG_EvaluateExecutionGate",
                 signal.m_guid), LOG_LEVEL_ERROR);
        return false;
    }
    SSymbolProfile spGate = SY_GetProfile(_Symbol);
    if(!spGate.isValid)
    {
        LogPrint(StringFormat("[RG_GATE_FAIL] GUID=%I64u | reason=INVALID_PROFILE | step=RG_EvaluateExecutionGate",
                 signal.m_guid), LOG_LEVEL_ERROR);
        return false;
    }
    double tickValue = spGate.tickValue;
    double tickSize  = spGate.tickSize;
    double checkMinLot = spGate.volumeMin;
    double maxRiskAmount = equity * (activeRiskPct / 100.0);
    double slDist = MathAbs(signal.entry_price - signal.stop_loss);
    double minLotRisk = (slDist / tickSize) * tickValue * checkMinLot;

    LogPrint(StringFormat("[RG_EVALUATE] GUID=%I64u | slDist=%.5f | minLotRisk=%.2f | budget=%.2f",
             signal.m_guid, slDist, minLotRisk, maxRiskAmount), LOG_LEVEL_DEBUG);

    if(minLotRisk > maxRiskAmount)
    {
        LogPrint(StringFormat("[RG_GATE_FAIL] GUID=%I64u | reason=RISK_EXCEEDS_BUDGET | risk=%.2f > budget=%.2f | step=RG_EvaluateExecutionGate",
                 signal.m_guid, minLotRisk, maxRiskAmount), LOG_LEVEL_WARN);
        return false;
    }
    LogPrint(StringFormat("[RG_GATE_PASS] GUID=%I64u | minLotRisk=%.2f <= budget=%.2f | step=RG_EvaluateExecutionGate",
             signal.m_guid, minLotRisk, maxRiskAmount), LOG_LEVEL_DEBUG);
    return true;
}

//+------------------------------------------------------------------+
//| TrackPositionOpen — Register position in closure tracker         |
//+------------------------------------------------------------------+
void TrackPositionOpen(ulong ticket, datetime openTime)
{
    if(ticket == 0) return;
    int idx = g_closureTrackerCount;
    ArrayResize(g_closureTracker, idx + 1);
    g_closureTracker[idx].ticket = ticket;
    g_closureTracker[idx].openTime = openTime;
    g_closureTracker[idx].closeTime = 0;
    g_closureTracker[idx].closureCount = 0;
    g_closureTracker[idx].lastClosureReason = "";
    g_closureTracker[idx].timeoutClose = false;
    g_closureTrackerCount++;
}

//+------------------------------------------------------------------+
//| TrackPositionClose — Register position close + reason            |
//+------------------------------------------------------------------+
void RegisterPositionClose(ulong ticket, string reason, bool timeoutClose = false)
{
    for(int i = 0; i < g_closureTrackerCount; i++)
    {
        if(g_closureTracker[i].ticket == ticket)
        {
            g_closureTracker[i].closeTime = TimeCurrent();
            g_closureTracker[i].closureCount++;
            g_closureTracker[i].lastClosureReason = reason;
            g_closureTracker[i].timeoutClose = timeoutClose;
            LogPrint("[CLOSURE_TRACK] ticket=" + IntegerToString(ticket) +
                     " | reason=" + reason +
                     " | timeout=" + (timeoutClose ? "YES" : "NO"), LOG_LEVEL_INFO);
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| CheckPositionTimeouts — Emergency close after N days             |
//+------------------------------------------------------------------+
void CheckPositionTimeouts(string symbol, long magic)
{
    if(InpMaxTradeDurationDays <= 0) return;

    static datetime s_lastTimeoutCheck = 0;
    datetime now = TimeCurrent();
    if(now - s_lastTimeoutCheck < 60) return;
    s_lastTimeoutCheck = now;

    datetime cutoff = now - (InpMaxTradeDurationDays * 86400);

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != magic) continue;

        datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
        if(openTime >= cutoff) continue;

        LogPrint("[EMERGENCY_TIMEOUT_CLOSE] ticket=" + IntegerToString(ticket) +
                 " | ageDays=" + IntegerToString(InpMaxTradeDurationDays) +
                 " | openTime=" + TimeToString(openTime), LOG_LEVEL_ERROR);

        PM_ClosePosition(ticket, symbol);
        RegisterPositionClose(ticket, "EMERGENCY_TIMEOUT", true);
    }
}

//+------------------------------------------------------------------+
//| LogPositionClosureDiagnostics — Throttled SL/TP check per pos   |
//+------------------------------------------------------------------+
void LogPositionClosureDiagnostics(string symbol, long magic)
{
    static datetime s_lastDiagLog = 0;
    datetime now = TimeCurrent();
    if(now - s_lastDiagLog < 60) return;
    s_lastDiagLog = now;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != magic) continue;

        double sl = PositionGetDouble(POSITION_SL);
        double tp = PositionGetDouble(POSITION_TP);
        double entry = PositionGetDouble(POSITION_PRICE_OPEN);
        datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

        LogPrint("[CLOSURE_CHECK] ticket=" + IntegerToString(ticket) +
                 " | entry=" + DoubleToString(entry, _Digits) +
                 " | sl=" + DoubleToString(sl, _Digits) +
                 " | tp=" + DoubleToString(tp, _Digits) +
                 " | open=" + TimeToString(openTime), LOG_LEVEL_DEBUG);
    }
}


//+------------------------------------------------------------------+
//| Context-aware execution gate                                     |
//+------------------------------------------------------------------+

// Equity Guard state machine — Risk Compliance Engine
// Equity Guard state machine variables
ENUM_EQUITY_GUARD_STATE g_equityGuardState = EQUITY_GUARD_NORMAL;
datetime g_guardLastCheckTime = 0;
int g_maxTradesPerDay = 0;           // 0 = unlimited (set >0 to cap daily trades)
double g_riskPercentOverride = -1.0; // -1 = use InpRiskPercent (set >0 to override)
// VERBATIM REPAIR: Safe-Load Affordability (§IV) — dual-role risk separation
double g_riskPercentTrade = 1.0;       // Execution risk budget (narrow, e.g. 1%)
double g_riskPercentAffordMin = 20.0;  // Structural affordability bridge (wide, e.g. 20%)
// REGRESSION_GUARD_V52_5_RECOVERY_THRESHOLD

// Volatility regime types — defined in SymbolClassVolatility.mqh
// ENUM_VOLATILITY_REGIME, ENUM_VOL_STATE, SVolatilityContext


//+------------------------------------------------------------------+
//| DUAL-REGISTRY SIGNAL ROUTING (§III.B)                             |
//| TickRouter(ctx) in core/Router.mqh is the single routing           |
//| authority. Dispatches g_activeC2 (MODE_ANTICIPATION) and           |
//| g_activeC3 (MODE_CONFIRMATION) independently.                     |
//+------------------------------------------------------------------+

// ProcessPipelineSignal — processes one signal slot (avoids MQL5 local ref limitation)
void ProcessPipelineSignal(SLockedSignal &sig,
                           int idx,
                           BranchContext &ctx,
                           datetime currentTick,
                           int &transitionsThisTick,
                           bool isC2Pool)
{
    if(sig.m_guid == 0 || sig.stage == STAGE_NONE) return;
    if(transitionsThisTick >= 10) return;
    
    ENUM_SIGNAL_STAGE oldStage = sig.stage;
    if(currentTick == sig.m_lastEvaluationTick && sig.stage == oldStage) return;
    string rgError;
    
    // === TIME-BASED EXPIRY ===
    SLockedSignal signal = sig;
    if(CheckSignalExpiryByTime(signal))
    {
        LogPrint("[PIPELINE_EXPIRE] GUID=" + IntegerToString(sig.m_guid) +
                 " | reason=TIME_BASED_EXPIRY | stage=" + EnumToString(sig.stage), LOG_LEVEL_WARN);
        if(!sig.TransitionStage(STAGE_EXPIRED))
        {
            LogPrint("[ZOMBIE_BLOCK] Time-based expiry blocked for expired signal | GUID=" + IntegerToString(sig.m_guid), LOG_LEVEL_WARN);
            return;
        }
        SL_TerminateSignal(sig.m_guid, SIGNAL_TERM_DROPPED, "TIME_BASED_EXPIRY");
        sig.Reset();
        g_poiCache[idx].isValid = false;
        return;
    }
    
    // === HARD-TIMEOUT HANDOVER RELEASE ===
    if(sig.handoverState == HANDOVER_ACQUIRED || sig.handoverState == HANDOVER_TRANSFERRED)
    {
        uint secondsSinceLock = (uint)(TimeCurrent() - sig.handoverAcquiredTime);
        uint timeoutSeconds = PeriodSeconds(sig.entryTF) * 4;
        if(secondsSinceLock > timeoutSeconds)
        {
            LogPrint("[HANDOVER_TIMEOUT] GUID=" + IntegerToString(sig.m_guid), LOG_LEVEL_WARN);
            sig.ReleaseHandover();
        }
    }
    
    // === FORCE CLEAR on repeated illegal transitions ===
    if(sig.illegalTransitionCount >= 3)
    {
        ulong forceGuid = sig.m_guid;
        LogPrint(StringFormat("[SIGNAL_FORCE_CLEARED] GUID=%I64u | reason=REPEATED_ILLEGAL_TRANSITIONS | count=%d | stage=%s",
                 forceGuid, sig.illegalTransitionCount, EnumToString(sig.stage)), LOG_LEVEL_ERROR);
        SL_TerminateSignal(forceGuid, SIGNAL_TERM_DROPPED, "REPEATED_ILLEGAL_TRANSITIONS");
        ForceClearSignal(idx, isC2Pool, "REPEATED_ILLEGAL_TRANSITIONS");
        return;
    }
    
    if(sig.stage == STAGE_WAITING_FOR_POI)
        sig.resolveLockedCount++;
    
    if(g_InpLogLevel <= LOG_LEVEL_DEBUG)
        LogPrint("[LOOP_TICK] Processing | stage=" + EnumToString(sig.stage), LOG_LEVEL_DEBUG);
    
    static ulong lastLoggedGUID = 0;
    if(sig.m_guid != 0 && sig.m_guid != lastLoggedGUID && sig.stage == STAGE_LOCKED)
    {
        LogPrint("[SIGNAL_ACTIVE] GUID=" + IntegerToString(sig.m_guid) +
                 " | stage=" + EnumToString(sig.stage), LOG_LEVEL_INFO);
        lastLoggedGUID = sig.m_guid;
    }
        
    if(oldStage != sig.stage)
    {
        transitionsThisTick++;
        LogPrint("[STAGE_TRANSITION] GUID=" + IntegerToString(sig.m_guid) +
                 " | oldStage=" + EnumToString(oldStage) +
                 " | newStage=" + EnumToString(sig.stage) +
                 " | totalTicks=" + IntegerToString(sig.tickCount) +
                 " | resolveTicks=" + IntegerToString(sig.resolveLockedCount), LOG_LEVEL_INFO);
    }
    
    // STEP 2: POI Touch Detection
    if(sig.stage == STAGE_WAITING_FOR_POI)
    {
        LogPrint(StringFormat("[POI_TRANSITION] GUID=%I64u | stage=%s | closure=%s | entry_price=%.5f | direction=%s | mode=%d | POI_touch_detection_START...",
                 sig.m_guid, EnumToString(sig.stage), EnumToString(sig.closureType),
                 sig.entry_price, EnumToString(sig.direction), sig.executionMode), LOG_LEVEL_DEBUG);
                 
        if(sig.closureType == CLOSURE_C2)
        {
            string corrSym = GetCorrelatedSymbol(_Symbol);
            ENUM_TIMEFRAMES smtTF = (sig.branchId == BRANCH_SWING) ? PERIOD_H4 : PERIOD_H1;
            bool smtPass = true;
            if(corrSym != "")
                smtPass = HasSMTDivergence(corrSym, smtTF, (sig.direction == DIRECTION_BUY));
            
            if(!smtPass)
            {
                LogPrint("[SMT_DIVERGENCE_FAIL] C2 blocked at CISD release | GUID=" +
                         IntegerToString(sig.m_guid) + " | corrSym=" + corrSym, LOG_LEVEL_INFO);
                return;
            }
            
            ENUM_TIMEFRAMES structTF = GetStructureTF(sig.branchId);
            if(!CheckHTFTimeSensitivity(structTF))
            {
                LogPrint("[TIME_FILTER_BLOCK] C2 blocked at CISD release | GUID=" +
                         IntegerToString(sig.m_guid) + " | structTF=" + EnumToString(structTF), LOG_LEVEL_INFO);
                return;
            }
            
            if(CheckC2CISD(sig))
            {
                ENUM_TIMEFRAMES structTfCisd = (sig.branchId == BRANCH_SWING) ? PERIOD_H4 : PERIOD_H1;
                if(!IsStructureTFAligned(sig.direction == DIRECTION_BUY, structTfCisd))
                {
                    LogPrint("[CISD_GATE_BLOCK] Structural alignment failed before STAGE_READY | GUID=" +
                             IntegerToString(sig.m_guid) + " | structTF=" + EnumToString(structTfCisd), LOG_LEVEL_INFO);
                    return;
                }
                
                if(sig.stage != STAGE_READY)
                {
                    if(!sig.TransitionStage(STAGE_READY)) return;
                    ctx.branchLockedSignal.TransitionStage(STAGE_READY);
                    g_totalSignalsReady++;
                    LogPrint(StringFormat("[CISD_CONFIRMED] GUID=%I64u | C2 release via CISD | dir=%s | structTF=%s | close=%.5f %s c2_extreme=%.5f",
                        sig.m_guid,
                        EnumToString(sig.direction),
                        EnumToString(GetStructureTF(sig.branchId)),
                        iClose(_Symbol, GetStructureTF(sig.branchId), 1),
                        (sig.direction == DIRECTION_BUY) ? ">" : "<",
                        (sig.direction == DIRECTION_BUY) ? sig.c2_high : sig.c2_low), LOG_LEVEL_INFO);
                }
                if(RG_EvaluateAndGate(sig, ctx.branch))
                {
                    if(!sig.TransitionStage(STAGE_READY)) return;
                    LogPrint("[C2_PROMOTED] GUID:" + IntegerToString(sig.m_guid) + " -> STAGE_READY", LOG_LEVEL_INFO);
                }
                else
                {
                    sig.hasFailedRG = true;
                    LogPrint("[READY_RETRY_PERSIST] RG failed - keeping READY for retry | GUID=" + IntegerToString(sig.m_guid) +
                             " | slot=" + IntegerToString(idx), LOG_LEVEL_DEBUG);
                }
                return;
            }
            
            // POI buffer calculation
            double signalRange = sig.c2_high - sig.c2_low;
            double signalMidpoint = (sig.c2_high + sig.c2_low) / 2.0;
            double dailyHigh = iHigh(_Symbol, PERIOD_D1, 0);
            double dailyLow  = iLow(_Symbol, PERIOD_D1, 0);
            double dailyRange = dailyHigh - dailyLow;
            double minBufferPrice = 0.30;
            if(_Digits == 5 || _Digits == 3)
                minBufferPrice = 0.00030;
            else if(_Digits == 2)
                minBufferPrice = 0.30;
            else if(_Digits == 1)
                minBufferPrice = 3.0;
            else if(_Digits == 0)
                minBufferPrice = 30.0;
            double bufferPrice = MathMax(dailyRange * 0.15, minBufferPrice);
            double bufferPriceFinal = bufferPrice;
            SSymbolProfile poiTickProf = SY_GetProfile(_Symbol);
            double bufferPointsFinal = bufferPriceFinal / poiTickProf.tickSize;
            long slMinPts = poiTickProf.stopsLevel;
            if(slMinPts <= 0) slMinPts = 100;
            double minBufferTicks = slMinPts * poiTickProf.point / poiTickProf.tickSize * InpMinStopBuffer;
            if(bufferPointsFinal < minBufferTicks) bufferPointsFinal = minBufferTicks;
            double tSpotWidth = bufferPriceFinal * 2.0;
            
            LogPrint("[POI_CALC] D1range=" + DoubleToString(dailyRange, 5) +
                    " | buffer=" + DoubleToString(bufferPriceFinal, 5) +
                    " | tSpotWidth=" + DoubleToString(tSpotWidth, 5), LOG_LEVEL_INFO);
            
            double sanityMax = dailyRange * 2.0;
            if(tSpotWidth > sanityMax && dailyRange > 0)
            {
                double cappedBuffer = dailyRange * 0.5;
                bufferPriceFinal = cappedBuffer;
                bufferPointsFinal = bufferPriceFinal / poiTickProf.tickSize;
                tSpotWidth = dailyRange;
                sig.htfTSpotHigh = signalMidpoint + (dailyRange * 0.5);
                sig.htfTSpotLow  = signalMidpoint - (dailyRange * 0.5);
            }
            else
            {
                sig.htfTSpotHigh = signalMidpoint + bufferPriceFinal;
                sig.htfTSpotLow  = signalMidpoint - bufferPriceFinal;
            }
            
            static datetime g_lastPoiLogBar[];
            ArrayResize(g_lastPoiLogBar, MathMax(ArraySize(g_lastPoiLogBar), idx+1));
            datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
            bool barChanged = (currentBar != g_lastPoiLogBar[idx]);
            if(barChanged)
            {
                g_lastPoiLogBar[idx] = currentBar;
            }
            
            if(sig.htfTSpotHigh == 0.0 || sig.htfTSpotLow == 0.0)
            {
                sig.htfTSpotMid = signalMidpoint;
                sig.htfTSpotHigh = signalMidpoint + bufferPriceFinal;
                sig.htfTSpotLow = signalMidpoint - bufferPriceFinal;
            }
            
            double bufferHigh = signalMidpoint + bufferPriceFinal;
            double bufferLow = signalMidpoint - bufferPriceFinal;
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            
            bool inTSpotBuy = (sig.direction == DIRECTION_BUY && ask >= bufferLow && ask <= bufferHigh);
            bool inTSpotSell = (sig.direction == DIRECTION_SELL && bid <= bufferHigh && bid >= bufferLow);
            bool poiTouched = inTSpotBuy || inTSpotSell;
            
            if(poiTouched && sig.stage != STAGE_READY)
            {
                string corrSymPOI = GetCorrelatedSymbol(_Symbol);
                ENUM_TIMEFRAMES smtTFPOI = (sig.branchId == BRANCH_SWING) ? PERIOD_H4 : PERIOD_H1;
                bool smtPassPOI = true;
                if(corrSymPOI != "")
                    smtPassPOI = HasSMTDivergence(corrSymPOI, smtTFPOI, (sig.direction == DIRECTION_BUY));
                
                if(!smtPassPOI)
                    return;
                
                ENUM_TIMEFRAMES structTFPOI = GetStructureTF(sig.branchId);
                if(!CheckHTFTimeSensitivity(structTFPOI))
                    return;
                
                ENUM_TIMEFRAMES structTfPoi = (sig.branchId == BRANCH_SWING) ? PERIOD_H4 : PERIOD_H1;
                if(!IsStructureTFAligned(sig.direction == DIRECTION_BUY, structTfPoi))
                    return;
                
                if(!sig.TransitionStage(STAGE_READY)) return;
                ctx.branchLockedSignal.TransitionStage(STAGE_READY);
                g_totalSignalsReady++;
                if(RG_EvaluateAndGate(sig, ctx.branch))
                {
                    if(!sig.TransitionStage(STAGE_READY)) return;
                }
                else
                {
                    sig.hasFailedRG = true;
                }
                return;
            }
        }
        else if(sig.closureType == CLOSURE_C3 && sig.stage == STAGE_WAITING_FOR_POI)
        {
            double zoneLow = MathMin(sig.tSpotMin, sig.tSpotMax);
            double zoneHigh = MathMax(sig.tSpotMin, sig.tSpotMax);
            
            if(zoneLow > 0.0 && zoneHigh > 0.0)
            {
                ENUM_TIMEFRAMES itfPeriod = (ctx.branch == BRANCH_INTRADAY) ? PERIOD_H1 : PERIOD_H4;
                SSE_CISDResult cisdGateResult = SSE_DetectCISD(_Symbol, itfPeriod, sig.direction, 20);
                if(!cisdGateResult.confirmed)
                    return;
                
                double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                bool inTSpotBuy  = (sig.direction == DIRECTION_BUY && ask >= zoneLow && ask <= zoneHigh);
                bool inTSpotSell = (sig.direction == DIRECTION_SELL && bid <= zoneHigh && bid >= zoneLow);
                bool priceInTSpot = inTSpotBuy || inTSpotSell;
                
                if(priceInTSpot)
                {
                    // ===== C3 PIPELINE ENTRY (REPLACEMENT) =====
                    if(sig.closureType == CLOSURE_C3)
                    {
                        // Map POI to get entry price
                        if(!EE_MapC3POI(sig))
                        {
                           LogPrint("[C3_PIPELINE] Failed to map POI for C3 signal GUID=" + IntegerToString(sig.m_guid), LOG_LEVEL_WARN);
                           return;
                        }
                        
                        // Assign SL using dedicated C3 calculator (no overwrite later)
                        if(sig.stop_loss <= 0.0)
                        {
                           double minStopMult = InpMinStopBuffer;  // Use input parameter
                           sig.stop_loss = C3_SL_Calculator(
                              (sig.direction == DIRECTION_BUY) ? 1 : -1,
                              sig.entry_price,
                              (sig.branch == BRANCH_INTRADAY) ? PERIOD_H1 : PERIOD_H4,
                              minStopMult
                           );
                        }
                        
                        // Transition to READY
                        sig.TransitionStage(STAGE_READY);
                        
                        // Evaluate gate
                        if(RG_EvaluateAndGate(sig, ctx.branch, rgError))
                        {
                           // Signal passed - store in C3 registry only
                           CommitSignalToStore(sig, ctx.branch, CLOSURE_C3);
                        }
                        else
                        {
                           LogPrint("[C3_PIPELINE] RG_GATE_FAIL: " + rgError, LOG_LEVEL_ERROR);
                           sig.TransitionStage(STAGE_EXPIRED);
                        }
                    }
                    // ===== END C3 PIPELINE =====
                }
            }
        }
    }
    
    // STEP 3: Immediate Order Execution for STAGE_READY
    if(sig.isCommitted && sig.stage == STAGE_READY)
    {
        if(IsSignalOnCooldown(sig.closureType, sig.symbol))
        {
            LogPrint("[SIGNAL_ON_COOLDOWN] GUID=" + IntegerToString(sig.m_guid) +
                     " type=" + EnumToString(sig.closureType) + " symbol=" + sig.symbol, LOG_LEVEL_DEBUG);
            return;
        }
        
        SLockedSignal execSig = sig;
        ENUM_EXECUTION_BRANCH execBranch = (ENUM_EXECUTION_BRANCH)execSig.branchId;
        
        SSymbolProfile ebProf = SY_GetProfile(_Symbol);
        long ebSl = ebProf.stopsLevel;
        if(ebSl <= 0) ebSl = 100;
        double entryBuffer = ebSl * ebProf.point * InpMinStopBuffer;
        if(execSig.direction == DIRECTION_BUY)
        {
            double minEntry = (execSig.closureType == CLOSURE_C3 && execSig.c3_low > 0)
                ? execSig.c3_low - entryBuffer : execSig.c2_low - entryBuffer;
            if(execSig.entry_price < minEntry)
            {
                sig.hasFailedRG = true;
                ClearSignalByGUID(execBranch, execSig.m_guid, "ENTRY_MISALIGNED");
                return;
            }
        }
        else if(execSig.direction == DIRECTION_SELL)
        {
            double maxEntry = (execSig.closureType == CLOSURE_C3 && execSig.c3_high > 0)
                ? execSig.c3_high + entryBuffer : execSig.c2_high + entryBuffer;
            if(execSig.entry_price > maxEntry)
            {
                sig.hasFailedRG = true;
                ClearSignalByGUID(execBranch, execSig.m_guid, "ENTRY_MISALIGNED");
                return;
            }
        }
        
        if(execSig.m_guid == 0 || execSig.stage != STAGE_READY)
        {
            LogPrint("[SIG_NOT_READY] GUID=" + IntegerToString(execSig.m_guid) +
                     " stage=" + IntegerToString(execSig.stage), LOG_LEVEL_DEBUG);
            return;
        }
        if(execSig.direction != DIRECTION_BUY && execSig.direction != DIRECTION_SELL)
        {
            LogPrint("[SIG_INVALID_DIRECTION] GUID=" + IntegerToString(execSig.m_guid) +
                     " dir=" + IntegerToString(execSig.direction), LOG_LEVEL_DEBUG);
            return;
        }
        bool warmupReady = IsWarmupComplete(g_branchTF);
        if(!warmupReady)
        {
            LogPrint("[WARMUP_NOT_READY] GUID=" + IntegerToString(execSig.m_guid), LOG_LEVEL_DEBUG);
            return;
        }
        
        int sigMode = execSig.executionMode;
        EntryMode mode = (sigMode == 1) ? MODE_ANTICIPATION : MODE_CONFIRMATION;
        execSig.riskProfile = GetRiskProfile(mode);
        string slCalcError = "";
        double stopLoss = 0.0;
        bool slValid = (execSig.stop_loss > 0.0 && execSig.stop_loss != execSig.entry_price);
        if (slValid) {
            stopLoss = execSig.stop_loss;
        } else {
            double minStopMult = InpMinStopBuffer;
            ENUM_TIMEFRAMES slItf = (execSig.branchId == BRANCH_INTRADAY) ? PERIOD_H1 : PERIOD_H4;
            switch (execSig.closureType) {
                case CLOSURE_C2:
                    stopLoss = C2_SL_Calculator(
                        (execSig.direction == DIRECTION_BUY) ? 1 : -1,
                        execSig.entry_price,
                        slItf,
                        minStopMult
                    );
                    break;
                case CLOSURE_C3:
                    stopLoss = C3_SL_Calculator(
                        (execSig.direction == DIRECTION_BUY) ? 1 : -1,
                        execSig.entry_price,
                        slItf,
                        minStopMult
                    );
                    break;
                case CLOSURE_C4:
                    stopLoss = C4_SL_Calculator(
                        (execSig.direction == DIRECTION_BUY) ? 1 : -1,
                        execSig.entry_price,
                        execSig.c3_high,
                        execSig.c3_low,
                        minStopMult
                    );
                    break;
                default:
                    stopLoss = CalculateClosureTypeSL(execSig, slCalcError);
                    break;
            }
            if (stopLoss <= 0.0 || stopLoss == execSig.entry_price) {
                LogPrint("[SL_FALLBACK_FAIL] GUID=" + IntegerToString(execSig.m_guid), LOG_LEVEL_ERROR);
                return;
            }
        }
        if (!slValid && stopLoss > 0.0 && stopLoss != execSig.entry_price) {
            execSig.stop_loss = stopLoss;
        }
        
        string tpCalcError = "";
        double tp1Price = 0.0, tp2Price = 0.0, tp3Price = 0.0;
        if(!CalculateProjectionTPs(execSig, stopLoss, tp1Price, tp2Price, tp3Price, tpCalcError))
        {
            sig.hasFailedRG = true;
            ClearSignalByGUID(ctx.branch, execSig.m_guid, "TP_INVALID_NO_FALLBACK");
            return;
        }
        
        sig.tp = tp1Price;
        execSig.tp = tp1Price;
        
        double slDistancePoints = MathAbs(execSig.entry_price - stopLoss) / _Point;
        if(slDistancePoints <= 0)
        {
            LogPrint("[SL_DISTANCE_ZERO] GUID=" + IntegerToString(execSig.m_guid) +
                     " entry=" + DoubleToString(execSig.entry_price) +
                     " sl=" + DoubleToString(stopLoss), LOG_LEVEL_ERROR);
            return;
        }
        
        // ===== SPECIES-AWARE SL ASSIGNMENT (NO BLANKET OVERWRITE) =====
        // Each species already has its SL assigned in its pipeline.
        // Only fallback if SL is invalid, and never overwrite a valid SL.
        
        if(EE_MapTSpotPOI(sig))
        {
            // Do NOT automatically overwrite SL with manipulation leg.
            // Instead, check if the current SL is valid.
            bool slValid = (execSig.stop_loss > 0.0 && execSig.stop_loss != execSig.entry_price);
            
            if(!slValid)
            {
                LogPrint("[SL_FALLBACK] Species=" + EnumToString(execSig.closureType) +
                      " had invalid SL, computing fresh...", LOG_LEVEL_WARN);
                
                double minStopMult = InpMinStopBuffer;  // Use your input parameter
                double newSL = 0.0;
                
                switch(execSig.closureType)
                {
                    case CLOSURE_C2:
                        newSL = C2_SL_Calculator(
                            (execSig.direction == DIRECTION_BUY) ? 1 : -1,
                            execSig.entry_price,
                            (execSig.branch == BRANCH_INTRADAY) ? PERIOD_H1 : PERIOD_H4,
                            minStopMult
                        );
                        break;
                        
                    case CLOSURE_C3:
                        newSL = C3_SL_Calculator(
                            (execSig.direction == DIRECTION_BUY) ? 1 : -1,
                            execSig.entry_price,
                            (execSig.branch == BRANCH_INTRADAY) ? PERIOD_H1 : PERIOD_H4,
                            minStopMult
                        );
                        break;
                        
                    case CLOSURE_C4:
                        newSL = C4_SL_Calculator(
                            (execSig.direction == DIRECTION_BUY) ? 1 : -1,
                            execSig.entry_price,
                            execSig.c3_high,
                            execSig.c3_low,
                            minStopMult
                        );
                        break;
                        
                    default:
                        LogPrint("[SL_FALLBACK] Unknown closureType, using CalculateClosureTypeSL", LOG_LEVEL_WARN);
                        newSL = CalculateClosureTypeSL(execSig, slCalcError);
                        break;
                }
                
                if(newSL > 0.0 && newSL != execSig.entry_price)
                {
                    sig.stop_loss = newSL;
                    execSig.stop_loss = newSL;
                    LogPrint("[SL_ASSIGNED] " + EnumToString(execSig.closureType) +
                          " newSL=" + DoubleToString(newSL), LOG_LEVEL_INFO);
                }
            }
            
            // Now synchronise internal structures (but do not overwrite the SL we just set)
            SyncInternalSL(execSig.stop_loss);
            SyncRefinedTargets(sig);
            execSig.tp = sig.tp;
        }
        // ===== END SPECIES-AWARE SL ASSIGNMENT =====
        
        if(execSig.stop_loss > 0.0)
        {
            stopLoss = execSig.stop_loss;
            slDistancePoints = MathAbs(execSig.entry_price - stopLoss) / _Point;
        }
        
        if(!FinalExecutionGuard(execSig, idx, ctx.branch, execSig.stop_loss, tp1Price))
        {
            sig.hasFailedRG = true;
            ClearSignalByGUID(ctx.branch, execSig.m_guid, "RG_FAIL_FEG");
            return;
        }
        
        if(execSig.closureType == CLOSURE_C2)
            g_lastTradeTimeC2 = TimeCurrent();
        else if(execSig.closureType == CLOSURE_C3)
            g_lastTradeTimeC3 = TimeCurrent();
        
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        SSymbolProfile spExecPre = SY_GetProfile(_Symbol);
        double tickValue = spExecPre.tickValue;
        double tickSize  = spExecPre.tickSize;
        
        double activeRiskPct = ResolveActiveRiskPct(execSig.executionMode, InpRiskPercent);
        if(!RG_EvaluateExecutionGate(execSig, activeRiskPct))
        {
            sig.hasFailedRG = true;
            ClearSignalByGUID(ctx.branch, execSig.m_guid, "RISK_MINLOT_REJECT");
            return;
        }
        double rawLot = CalculateRiskLot(execSig, execSig.riskProfile.positionSizeFactor);
        if(rawLot <= 0.0)
        {
            LogPrint("[LOT_CALC_FAILED] GUID=" + IntegerToString(execSig.m_guid) + " reason=rawLot<=0", LOG_LEVEL_ERROR);
            return;
        }
        
        double minLot  = spExecPre.volumeMin;
        double maxLot  = spExecPre.volumeMax;
        double lotStep = spExecPre.volumeStep;
        StabiliseLot(rawLot, minLot, maxLot, lotStep, _Symbol);
        double lot = rawLot;
        if(lot <= 0.0)
        {
            sig.hasFailedRG = true;
            ClearSignalByGUID(ctx.branch, execSig.m_guid, "LOT_ZERO_POST_STABILISATION");
            return;
        }
        
        ulong execGuid = execSig.m_guid;
        
        double pyramidLot = 0.0;
        bool isPyramidOrder = false;
        if(g_InpEnablePyramiding && InpMaxPyramidOrders > 0)
        {
            int pyramidCount = 0;
            for(int pi = PositionsTotal() - 1; pi >= 0; pi--)
            {
                string posSymbol = PositionGetSymbol(pi);
                if(posSymbol == "" || StringCompare(posSymbol, _Symbol) != 0) continue;
                if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) continue;
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                bool sameDirection = (execSig.direction == DIRECTION_BUY && posType == POSITION_TYPE_BUY) ||
                                     (execSig.direction == DIRECTION_SELL && posType == POSITION_TYPE_SELL);
                if(sameDirection) pyramidCount++;
            }
            if(pyramidCount > 0 && pyramidCount <= InpMaxPyramidOrders)
            {
                isPyramidOrder = true;
                double riskPct = InpRiskPercent * g_InpPyramidAdditionalRiskPct / 100.0;
                double pyramidLotRaw = CalculateRiskLot(execSig, riskPct);
                if(pyramidLotRaw > 0.0)
                {
                    double protectedSL = (execSig.direction == DIRECTION_BUY) ? execSig.c2_low : execSig.c2_high;
                    if(protectedSL > 0.0)
                        StabiliseLot(pyramidLotRaw, minLot, maxLot, lotStep, _Symbol);
                        pyramidLot = pyramidLotRaw;
                }
                if(pyramidLot <= 0.0) isPyramidOrder = false;
            }
        }
        if(isPyramidOrder && pyramidLot > 0)
            lot = pyramidLot;
        
        ENUM_RG_FAIL rgResult = PreTradeReadinessGate(
            BuildRiskSnapshot(execSig, ctx.branch, stopLoss, tp1Price, lot), false);
        if(rgResult != RG_FAIL_NONE)
        {
            sig.hasFailedRG = true;
            ClearSignalByGUID(ctx.branch, execGuid, "RG_GATE_FAIL");
            return;
        }
        
        if(!ValidateRiskGate(execSig, stopLoss, tp1Price))
        {
            sig.hasFailedRG = true;
            ClearSignalByGUID(ctx.branch, execGuid, "RISK_GATE_FAIL");
            return;
        }
        
        PreAllocateSignalGUIDEntry(execGuid,
           execSig.m_setupInitialHigh, execSig.m_setupInitialLow,
           execSig.c2_high, execSig.c2_low,
           ctx.branch, execSig.direction, execSig.closureType,
           execSig.entry_price);
        
        if(!PreTradeExecutionCheck(execGuid, execSig.entry_price, stopLoss, tp1Price, execSig.closureType))
        {
            sig.hasFailedRG = true;
            ClearSignalByGUID(ctx.branch, execGuid, "PRETRADE_EXECUTION_CHECK_FAILED");
            return;
        }
        
        sig.IncrementExecutionAttempt();
        SLockedSignal signalRef = sig;
        
        if(ExecutionGatePass(signalRef, ctx.branch, lot))
        {
            sig = signalRef;
            sig.executionAttempts = signalRef.executionAttempts;
            sig.MarkExecuted();
            // Slot remains active — cleanup deferred to OnTradeTransaction fill confirmation
            if(ctx.branch == BRANCH_INTRADAY)
               g_branchAContext.branchLockedSignal.Reset();
            else
               g_branchBContext.branchLockedSignal.Reset();
            return;
        }
        else
        {
            sig = signalRef;
            sig.executionAttempts = signalRef.executionAttempts;
            if(sig.IsRetryCapReached())
            {
                sig.hasFailedRG = true;
                ClearSignalByGUID(ctx.branch, execGuid, "MAX_RETRIES_EXCEEDED");
                if(ctx.branch == BRANCH_INTRADAY)
                   g_branchAContext.branchLockedSignal.Reset();
                else
                   g_branchBContext.branchLockedSignal.Reset();
            }
            return;
        }
    }
    
    sig.m_lastEvaluationTick = currentTick;
}

//+------------------------------------------------------------------+
//| ProcessPipelinePool — FSM state routing for one signal pool      |
//| Iterates pool[baseIdx..baseIdx+maxSlots) and processes all stages.|
//| Pool param is either g_activeC2 or g_activeC3 (passed by ref).   |
//+------------------------------------------------------------------+
void ProcessPipelinePool(SLockedSignal &pool[],
                         int baseIdx,
                         int maxSlots,
                         BranchContext &ctx,
                         datetime currentTick,
                         int &transitionsThisTick,
                         bool isC2Pool)
{
    for(int i = 0; i < maxSlots; i++)
    {
        int idx = baseIdx + i;
        ProcessPipelineSignal(pool[idx], idx, ctx, currentTick, transitionsThisTick, isC2Pool);
        pool[idx].m_lastEvaluationTick = currentTick;
    }
}

//+------------------------------------------------------------------+
//| ProcessPersistentScanPool — execute orphaned STAGE_READY signals  |
//| Iterates one pool for READY signals missed by the main pipeline. |
//+------------------------------------------------------------------+
void ProcessPersistentScanPool(SLockedSignal &pool[], int maxSlots, BranchContext &ctx)
{
    for(int si = 0; si < maxSlots; si++)
    {
        if(pool[si].m_guid == 0 || pool[si].stage != STAGE_READY) continue;
        
        ulong scanGuid = pool[si].m_guid;
        ENUM_EXECUTION_BRANCH sigBranch = pool[si].branchId;
        
        if(pool[si].executionAttempts > 8 || (pool[si].stage == STAGE_READY && pool[si].hasFailedRG))
        {
            if(pool[si].handoverState != HANDOVER_NONE && pool[si].handoverState != HANDOVER_RELEASED)
                pool[si].ForceReleaseHandover("ZOMBIE_CLEAR_PERSIST");
            pool[si].hasFailedRG = true;
            pool[si].Reset();
            continue;
        }
        
        int retryWindowMinutes = (pool[si].closureType == CLOSURE_C3) ?
                                 g_InpC3RGReadyRetryWindowMinutes : g_InpRGReadyRetryWindowMinutes;
        datetime now = TimeCurrent();
        int minutesSinceReady = (pool[si].stageEntryTime > 0) ?
                                (int)((now - pool[si].stageEntryTime) / 60) : 0;
        if(pool[si].hasFailedRG && minutesSinceReady > retryWindowMinutes)
        {
            pool[si].hasFailedRG = true;
            pool[si].Reset();
            continue;
        }
        
        if(g_symbolUntradeable) continue;
        if(IsSymbolPermanentlySkipped(_Symbol))
        {
            pool[si].hasFailedRG = true;
            pool[si].Reset();
            continue;
        }
        if(IsSignalOnCooldown(pool[si].closureType, _Symbol)) continue;
        
        SLockedSignal scanSignal = pool[si];
        
        if(!pool[si].hasFailedRG)
        {
            if(!RG_EvaluateAndGate(scanSignal, sigBranch))
            {
                pool[si].hasFailedRG = true;
                continue;
            }
        }
        
        if(pool[si].executionRetryCount >= MAX_EXEC_RETRIES)
        {
            pool[si].hasFailedRG = true;
            pool[si].Reset();
            continue;
        }
        
        SSymbolProfile spPersist = SY_GetProfile(_Symbol);
        double rawLotPersist = CalculateRiskLot(scanSignal, scanSignal.riskProfile.positionSizeFactor);
        StabiliseLot(rawLotPersist, spPersist.volumeMin, spPersist.volumeMax, spPersist.volumeStep, _Symbol);
        double persistLot = rawLotPersist;
        if(persistLot <= 0.0)
        {
            pool[si].hasFailedRG = true;
            pool[si].Reset();
            continue;
        }
        
        // Ensure TP is set before execution (safety net for signals promoted outside ProcessPipelineSignal)
        if(scanSignal.tp <= 0.0 && scanSignal.stop_loss > 0.0 && scanSignal.stop_loss != scanSignal.entry_price)
        {
            double tp1 = 0, tp2 = 0, tp3 = 0;
            string errMsg;
            if(CalculateProjectionTPs(scanSignal, scanSignal.stop_loss, tp1, tp2, tp3, errMsg))
            {
                scanSignal.tp = tp1;
                LogPrint("[TP_CALC_INLINE] GUID=" + IntegerToString(scanSignal.m_guid) + " tp=" + DoubleToString(tp1, _Digits), LOG_LEVEL_DEBUG);
            }
            else
            {
                LogPrint("[TP_CALC_FAIL] GUID=" + IntegerToString(scanSignal.m_guid) + " reason=" + errMsg, LOG_LEVEL_WARN);
                continue;
            }
        }
        if(ExecutionGatePass(scanSignal, sigBranch, persistLot))
        {
            pool[si] = scanSignal;
            pool[si].MarkExecuted();
            // Slot remains active — cleanup deferred to OnTradeTransaction fill confirmation
            continue;
        }
        else
        {
            pool[si] = scanSignal;
            pool[si].executionRetryCount++;
            continue;
        }
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
LogPrint("EA_BUILD|" + OMAKFX_VERSION_STR + "|" + (string)__DATE__ + "|" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), LOG_LEVEL_INFO);

// Initialize log governance system first
    LogGov_Init(InpLogLevel, false);  // traceEnabled=false for backtest
g_logGovernor.config.maxLogsPerSession = InpMaxLogsPerSession;
if(InpMaxLogsPerBar > 0)
{
    g_logGovernor.config.maxLogsPerBar = InpMaxLogsPerBar;
    LogGov_SetPerBarControl(true);
}
else
{
    LogGov_SetPerBarControl(false);
}

   // Initialize Symbol Profile Manager
   SPM_InitSymbolProfile(_Symbol);

   // Validate symbol profile before anything else
   if(!ValidateProfileIntegrity(_Symbol))
   {
      LogPrint("[INIT_FAIL] Symbol profile validation failed for " + _Symbol, LOG_LEVEL_ERROR);
      return INIT_PARAMETERS_INCORRECT;
   }

   // Initialize Symbol Intelligence Layer (calc-mode-aware, broker-reality)
   if(!SY_Initialize(_Symbol))
   {
      LogPrint("[INIT_FATAL] Symbol intelligence layer initialization failed for " +
               _Symbol, LOG_LEVEL_ERROR);
      return INIT_FAILED;
   }
   SY_PrintProfile();

// Initialize Trade Governor state
    TG_Init(InpMagicNumber, _Symbol);

// DEPRECATED: g_orderGUIDMap removed — single canonical store is g_positionMap[]
   // Order-to-GUID mapping now handled via PendingGUIDLink in OnTradeTransaction

// Initialize pending GUID link queue
// Initialize GUID position map
g_positionMapCount = 0;
ArrayResize(g_positionMap, 0);
g_staticPositionMapCount = 0;
g_usingStaticPositionMap = false;

// Store initial equity for catastrophic stop-out
g_firstEquity = AccountInfoDouble(ACCOUNT_BALANCE);
   g_peakEquity = g_firstEquity;
g_highestEquityEver = g_firstEquity;
g_peakEquity30Day = g_firstEquity;
g_peakEquity30DayTime = TimeCurrent();

// Wire limit-order runtime flag from input (branch-scoped)
      if(InpBranch == BRANCH_INTRADAY)
      {
         g_useLimitOrdersBranchA = InpUseLimitOrders;
         g_limitExpirationBars = InpA_LimitExpirationBars;
      }
      else
      {
         g_useLimitOrdersBranchB = InpUseLimitOrders;
         g_limitExpirationBars = InpB_LimitExpirationBars;
      }
      g_lastTradeabilityCheckBar[0] = 0;
      g_lastTradeabilityCheckBar[1] = 0;
      g_symbolUntradeable = false;
      g_symbolUntradeableReason = "";
      g_permanentSkipCount = 0;
      ArrayResize(g_permanentSkipSymbols, 0);

      // Treat the initial check as advisory telemetry only.
      {
         SSymbolProfile initProf = SY_GetProfile(_Symbol);
         if(initProf.isValid)
         {
            double riskFloor = initProf.volumeMin * initProf.tickValue;
            double eq = AccountInfoDouble(ACCOUNT_EQUITY);
            if(eq > 0.0)
            {
               double minRequiredFactor = (eq > 0.0) ? (riskFloor / eq * 100.0) : 0.0;
               if(minRequiredFactor > InpMaxMinLotRiskPercent)
               {
                  g_symbolUntradeable = true;
                  g_symbolUntradeableReason = "AFFORDABILITY";
                  LogPrint(StringFormat("[SYMBOL_UNTRADEABLE] reason=AFFORDABILITY minRequiredFactor=%.2f%% bridge=%.2f%%", minRequiredFactor, InpMaxMinLotRiskPercent), LOG_LEVEL_WARN);
               }
            }
         }
      }
      LogPrint("[INIT_ADVISORY] System initialized. Soft-gate active.", LOG_LEVEL_INFO);

      // VERBATIM REPAIR: Safe-Load Affordability (§IV)
      g_riskPercentTrade = InpRiskPercent;
      g_riskPercentAffordMin = InpMaxMinLotRiskPercent;
      LogPrint(StringFormat("[INIT_SAFE_LOAD] TradeRisk: %.2f%% | AffordBridge: %.2f%%", g_riskPercentTrade, g_riskPercentAffordMin), LOG_LEVEL_INFO);

      // === VOLUME MIN SAFETY GATE: Micro-asset hazard protection ===
      SSymbolProfile initProf = SY_GetProfile(_Symbol);
      double checkVolMin = initProf.volumeMin;
      if(checkVolMin <= 0.0)
      {
         LogPrint("[INIT_FATAL] Trading cannot proceed safely. SYMBOL_VOLUME_MIN returned 0.0 for " +
                  _Symbol + ". Terminal configuration or asset profile is missing.", LOG_LEVEL_ERROR);
         return INIT_FAILED;
      }

      g_minStopBuffer = InpMinStopBuffer;
      
      g_maxPoiWaitBars = InpMaxPoiWaitBars;

// Initialize Determinism Layer
     DET_Init();

    // Restore daily loss from Global Variable (persistence layer)
   GV_LoadLoss();

    // Initialize Campaign system and Add Executor
    CM_Initialize();
    AE_Initialize();

    //=== PEAK EQUITY INITIALIZATION (P0 Critical Fix) ===
    // Initialize g_peakEquity on test/live start to prevent phantom 18.7% DD
    double initEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double initBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double startRef = (initEquity > 0) ? initEquity : initBalance;
    if(startRef > 0)
    {
        g_peakEquity = startRef;
        LogPrint("[PEAK_EQUITY_INIT] OnInit | equity=" + DoubleToString(initEquity, 2) +
                 " | balance=" + DoubleToString(initBalance, 2) +
                 " | g_peakEquity=" + DoubleToString(g_peakEquity, 2), LOG_LEVEL_INFO);
    }

//--- Initialize True TTrades config with mode-specific parameters
   InitTrueTTradesConfig();
   ApplyTrueTTradesInputs(InpUseTrueTTradesMode,
                          InpTradingStyle,
                          InpMaxC2WickPercent,
                          InpUseVolumeConfirmation,
                          InpMinVolumeExpansion);

   // Update mode-specific parameters
   UpdateTrueTTradesModeParams(InpAnticipationRR, InpRiskRewardRatio, InpAllowAnticipationReversals);

   if(!ValidateTrueTTradesConfig())
   {
      LogPrint("[INIT] WARN: True TTrades config validation failed — disabling mode", LOG_LEVEL_WARN);
      g_trueTTradesConfig.enabled = false;
   }

   //--- Detect and log market profile
   if(InpAutoDetectMarketType)
   {
      SMarketProfile mktProfile = GetMarketProfile(_Symbol);
      LogPrint("[INIT] Market Type: " + GetMarketTypeName(mktProfile.type), LOG_LEVEL_INFO);
      LogPrint("[INIT] Base Name: " + mktProfile.baseName + " | Prefix: \"" + mktProfile.prefix + "\" | Suffix: \"" + mktProfile.suffix + "\"", LOG_LEVEL_INFO);
      LogPrint("[INIT] 24-Hour: " + (mktProfile.is24Hour ? "YES" : "NO") + " | Weekend: " + (mktProfile.isWeekendTradable ? "YES" : "NO") + " | Volume Filter: " + (mktProfile.requiresVolume ? "YES" : "NO"), LOG_LEVEL_INFO);
   }

   //--- Initialize session manager
   InitSessionManager(_Symbol);
   LogPrint("[INIT] Session Manager: " + GetSessionStatusMessage(), LOG_LEVEL_INFO);

LogPrint("[Omak FxYO v1.0.0] Initialised", LOG_LEVEL_INFO);

g_branchTF = GetBranchTimeframes(InpBranch);

      // PROMPT 7: Override Branch B anchor to W1 when BRANCH_B active
      if(InpActiveBranch == BRANCH_B)
      {
         g_branchTF.biasTF = PERIOD_W1;
      }

      BE_ResolveParams(InpBranch, g_branchParams);  // Resolve per-branch parameters

      // === DEEP SYNC GATE: Verify all HTF data is synchronized before any warmup ===
      // Prevent "Lazy Indicator" syndrome — EA won't run until MT5 confirms data ready
      ENUM_TIMEFRAMES syncTFs[] = {PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
      int maxWaitMs = 5000;  // 5 second timeout
      int waitIntervalMs = 100;
      int totalWaited = 0;
      bool allSynced = false;

      while(totalWaited < maxWaitMs && !allSynced)
      {
         allSynced = true;
         for(int i = 0; i < ArraySize(syncTFs); i++)
         {
            if(SeriesInfoInteger(_Symbol, syncTFs[i], SERIES_SYNCHRONIZED) != 1)
            {
               allSynced = false;
               break;
            }
         }
         if(!allSynced)
         {
            Sleep(waitIntervalMs);
            totalWaited += waitIntervalMs;
         }
      }

      if(!allSynced)
      {
         LogPrint("[INIT] WARN: Timeout waiting for full TF sync — " + IntegerToString(totalWaited) + "ms elapsed", LOG_LEVEL_WARN);
      }
      else
      {
         LogPrint("[INIT] All TFs synchronized | Waited=" + IntegerToString(totalWaited) + "ms", LOG_LEVEL_INFO);
      }

      // === ASYMMETRIC HISTORY: Request specific bar counts per timeframe ===
      // D1: 30 bars (~1.5 months), H4: 30 bars, H1: 50 bars, M15/M5: 150 bars (entry confluence)
      double asymClose[];
      ArraySetAsSeries(asymClose, true);

      CopyClose(_Symbol, PERIOD_D1, 0, 30, asymClose);
      CopyClose(_Symbol, PERIOD_H4, 0, 30, asymClose);
      CopyClose(_Symbol, PERIOD_H1, 0, 50, asymClose);
      CopyClose(_Symbol, PERIOD_M15, 0, 150, asymClose);
      CopyClose(_Symbol, PERIOD_M5, 0, 150, asymClose);

      LogPrint("[INIT] Asymmetric history requested: D1=30, H4=30, H1=50, M15=150, M5=150", LOG_LEVEL_DEBUG);

      BE_Initialize();

    // Ensure the per-branch state fields are zero-initialised:
     ZeroMemory(g_branchAContext.branchLockedSignal);
     ZeroMemory(g_branchBContext.branchLockedSignal);
     g_branchAContext.branchForceRefresh = false;
     g_branchBContext.branchForceRefresh = false;

// Full store reset (Prompt_E3): Reset() for every slot in both pools
for(int i = 0; i < MAX_SLOTS; i++)
{
    g_activeC2[i].Reset();
    g_activeC3[i].Reset();
}
LogPrint("[STORE_INIT] All slots reset on OnInit (Dual-Registry)", LOG_LEVEL_INFO);

// FIX 5: POI Cache — allocate cache for all signal slots
 ArrayResize(g_poiCache, MAX_SLOTS);

 for(int i = 0; i < ArraySize(g_poiCache); i++)
          g_poiCache[i].isValid = false;

      LogPrint("[INIT_A] g_poiCache[] allocated | size=" + IntegerToString(MAX_TOTAL_SIGNALS_PER_BRANCH * 2), LOG_LEVEL_INFO);

// === ATR PRE-WARM: Create GLOBAL handles ONCE + PRIMING BEFORE warmup ===
      // CRITICAL: Initialize global ATR handles for all TFs in OnInit() with retry logic
LogPrint("[INIT] ATR subsystem removed — structural distance gating active", LOG_LEVEL_INFO);

    // === DEEP WARMUP: Seed D1/H1/H4 structure from 250 historical bars ===
    // Deep warmup required for Dow Theory swing detection (HH/HL/LH/LL)
    int sseWarmupBars = 250;  // 250 bars for proper fractal detection
    ENUM_TIMEFRAMES structTF = (InpBranch == BRANCH_INTRADAY) ? PERIOD_H1 : PERIOD_H4;
    SSE_Warmup(_Symbol, PERIOD_D1, sseWarmupBars);
    BR_Warmup(_Symbol, structTF, PERIOD_D1, sseWarmupBars);

   // Initialize Spread Filter
   SpreadFilter_Initialize();

     // Initialize Position Manager
     PM_Init();

    g_logLevel = InpLogLevel;

    TEL_Initialize(true,
                  true,
                  true,
                  false);
   LogPrint("[INIT] Log level: " + EnumToString(InpLogLevel), LOG_LEVEL_INFO);

   LogPrint("[INIT] Pipeline active", LOG_LEVEL_INFO);
   LogPrint("[INIT] Branch: " + GetBranchName(InpBranch), LOG_LEVEL_INFO);
   LogPrint("[INIT] Timeframe Chain: " + GetBranchDescription(InpBranch), LOG_LEVEL_INFO);
   LogPrint("[INIT] Bias TF: " + TimeframeToString(g_branchTF.biasTF), LOG_LEVEL_INFO);
   LogPrint("[INIT] Structure TF: " + TimeframeToString(g_branchTF.structureTF), LOG_LEVEL_INFO);
LogPrint("[INIT] Entry TF: " + TimeframeToString(g_branchTF.entryTF), LOG_LEVEL_INFO);

// === DEEP HISTORY: Copy 250 bars for all branch TFs (was 4) ===
{
       double _dummy[];
       ArrayResize(_dummy, 250);

       CopyHigh(_Symbol, PERIOD_H1,  0, 250, _dummy);
       CopyHigh(_Symbol, PERIOD_M5,  0, 250, _dummy);
       CopyHigh(_Symbol, PERIOD_H4,  0, 250, _dummy);
       CopyHigh(_Symbol, PERIOD_M15, 0, 250, _dummy);
       CopyHigh(_Symbol, PERIOD_D1,  0, 250, _dummy);
    }

    // Deep Warmup CopyLow — required by DetectClosureSignal
    {
       double _low[];
       ArrayResize(_low, 250);

       CopyLow(_Symbol,  PERIOD_H1,  0, 250, _low);
       CopyLow(_Symbol,  PERIOD_M5,  0, 250, _low);
       CopyLow(_Symbol,  PERIOD_H4,  0, 250, _low);
       CopyLow(_Symbol,  PERIOD_M15, 0, 250, _low);
       CopyLow(_Symbol,  PERIOD_D1,  0, 250, _low);
    }

    // Deep Warmup CopyOpen — required by DetectClosureSignal
    {
       double _open[];
       ArrayResize(_open, 250);

       CopyOpen(_Symbol,  PERIOD_H1,  0, 250, _open);
       CopyOpen(_Symbol,  PERIOD_M5,  0, 250, _open);
       CopyOpen(_Symbol,  PERIOD_H4,  0, 250, _open);
       CopyOpen(_Symbol,  PERIOD_M15, 0, 250, _open);
       CopyOpen(_Symbol,  PERIOD_D1,  0, 250, _open);
    }

    // Deep Warmup CopyClose — required by DetectClosureSignal
    {
       double _close[];
       ArrayResize(_close, 250);

       CopyClose(_Symbol,  PERIOD_H1,  0, 250, _close);
       CopyClose(_Symbol,  PERIOD_M5,  0, 250, _close);
       CopyClose(_Symbol,  PERIOD_H4,  0, 250, _close);
       CopyClose(_Symbol,  PERIOD_M15, 0, 250, _close);
       CopyClose(_Symbol,  PERIOD_D1,  0, 250, _close);
    }

    // Deep Warmup CopyTime — required by DetectClosureSignal
    {
       datetime _time[];
       ArrayResize(_time, 250);

CopyTime(_Symbol,  PERIOD_H1,  0, 250, _time);
        CopyTime(_Symbol,  PERIOD_M5,  0, 250, _time);
        CopyTime(_Symbol,  PERIOD_H4,  0, 250, _time);
        CopyTime(_Symbol,  PERIOD_M15, 0, 250, _time);
        CopyTime(_Symbol,  PERIOD_D1,  0, 250, _time);
     }

    // PHASE 4: One-time diagnostic log for mode/ATR
    static bool initDiagLogged = false;
if(!initDiagLogged)
     {
         initDiagLogged = true;
         
         bool isTester = (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION));
         string modeStr = isTester ? "TESTER" : "LIVE";
         LogPrint("[INIT_DIAG] === SYSTEM DIAGNOSTIC ===", LOG_LEVEL_INFO);
         LogPrint("[INIT_DIAG] Mode=" + modeStr + " | Symbol=" + _Symbol + " | Branch=" + EnumToString(InpBranch), LOG_LEVEL_INFO);
         LogPrint("[INIT_DIAG] ATR subsystem removed — structural gating active", LOG_LEVEL_INFO);
         LogPrint("[INIT_DIAG] MaxSignalsPerBranch=" + IntegerToString(InpMaxSignalsPerBranch), LOG_LEVEL_INFO);
         LogPrint("[INIT_DIAG] MaxPOIWaitBars=" + IntegerToString(InpMaxPOIWaitBars), LOG_LEVEL_INFO);
         LogPrint("[INIT_DIAG] =========================", LOG_LEVEL_INFO);
     }

    EventSetTimer(1);

    if(IsTesterPipsMode())
    {
       Print("ERROR: Tester is in 'calculate profit in pips' mode. "
             "This EA requires deposit currency mode. Please change tester settings and restart.");
       return INIT_FAILED;
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
     LogPrint("[DEINIT] ATR subsystem removed", LOG_LEVEL_INFO);
     ResetSignalStore(BRANCH_INTRADAY);
     ResetSignalStore(BRANCH_SWING);
     PM_Shutdown();

// === EXECUTION SUMMARY V2 — uses incremental DealTracker (Mission 2 fix) ===
      // P5 Fix: Use real-time counters instead of recomputing from history
      int totalTrades = g_totalDeals;
      double winRate = (totalTrades > 0) ? ((double)g_dealTracker.winningDeals / (double)totalTrades * 100.0) : 0.0;
     double profitFactor = (g_dealTracker.totalLoss != 0) ? MathAbs(g_dealTracker.totalProfit / g_dealTracker.totalLoss) : 0.0;
     double avgWin = (g_dealTracker.winningDeals > 0) ? (g_dealTracker.totalProfit / g_dealTracker.winningDeals) : 0.0;
     double avgLoss = (g_dealTracker.losingDeals > 0) ? (g_dealTracker.totalLoss / g_dealTracker.losingDeals) : 0.0;
     string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);

LogPrint("[EXEC_SUMMARY] Commits=" + IntegerToString(g_totalSignalCommits) +
              " | Expired=" + IntegerToString(g_totalSignalsExpired) +
              " | Ready=" + IntegerToString(g_totalSignalsReady) +
              " | OrdersSent=" + IntegerToString(g_totalOrdersSent) +
              " | Deals=" + IntegerToString(totalTrades) +
              " | NetProfit=" + DoubleToString(g_totalNetProfit, 2) + " " + accountCurrency +
              " | WinRate=" + DoubleToString(winRate, 1) + "%" +
              " | Wins=" + IntegerToString(g_dealTracker.winningDeals) +
              " | Losses=" + IntegerToString(g_dealTracker.losingDeals) +
              " | BreakEven=" + IntegerToString(g_dealTracker.breakEvenDeals) +
              " | LargestWin=" + DoubleToString(g_dealTracker.largestWin, 2) +
              " | LargestLoss=" + DoubleToString(g_dealTracker.largestLoss, 2) +
              " | AvgWin=" + DoubleToString(avgWin, 2) +
              " | AvgLoss=" + DoubleToString(avgLoss, 2) +
              " | MaxConsecWins=" + IntegerToString(g_dealTracker.maxConsecutiveWins) +
              " | MaxConsecLosses=" + IntegerToString(g_dealTracker.maxConsecutiveLosses) +
              " | ProfitFactor=" + DoubleToString(profitFactor, 2),
              LOG_LEVEL_INFO);

      // C2 vs C3 breakdown
      int c2Total = g_c2Wins + g_c2Losses + g_c2Breakeven;
      int c3Total = g_c3Wins + g_c3Losses + g_c3Breakeven;
      double c2WinRate = (c2Total > 0) ? ((double)g_c2Wins / (double)c2Total * 100.0) : 0.0;
      double c3WinRate = (c3Total > 0) ? ((double)g_c3Wins / (double)c3Total * 100.0) : 0.0;
      double c2PF = (g_c2TotalProfit < 0 && g_c2LargestLoss != 0) ? MathAbs(g_c2TotalProfit / g_c2LargestLoss) : 0.0;
      double c3PF = (g_c3TotalProfit < 0 && g_c3LargestLoss != 0) ? MathAbs(g_c3TotalProfit / g_c3LargestLoss) : 0.0;
      
      LogPrint("[C2_PERF] Anticipation | Wins=" + IntegerToString(g_c2Wins) +
               " | Losses=" + IntegerToString(g_c2Losses) +
               " | Breakeven=" + IntegerToString(g_c2Breakeven) +
               " | Total=" + IntegerToString(c2Total) +
               " | WinRate=" + DoubleToString(c2WinRate, 1) + "%" +
               " | NetProfit=" + DoubleToString(g_c2TotalProfit, 2) +
               " | LargestWin=" + DoubleToString(g_c2LargestWin, 2) +
               " | LargestLoss=" + DoubleToString(g_c2LargestLoss, 2) +
               " | ProfitFactor=" + DoubleToString(c2PF, 2), LOG_LEVEL_INFO);
      
      LogPrint("[C3_PERF] Confirmation | Wins=" + IntegerToString(g_c3Wins) +
               " | Losses=" + IntegerToString(g_c3Losses) +
               " | Breakeven=" + IntegerToString(g_c3Breakeven) +
               " | Total=" + IntegerToString(c3Total) +
               " | WinRate=" + DoubleToString(c3WinRate, 1) + "%" +
               " | NetProfit=" + DoubleToString(g_c3TotalProfit, 2) +
               " | LargestWin=" + DoubleToString(g_c3LargestWin, 2) +
               " | LargestLoss=" + DoubleToString(g_c3LargestLoss, 2) +
               " | ProfitFactor=" + DoubleToString(c3PF, 2), LOG_LEVEL_INFO);

      LogInfo(StringFormat("[PERF_SUMMARY] C2: W=%d L=%d B=%d | C3: W=%d L=%d B=%d",
              g_c2Wins, g_c2Losses, g_c2Breakeven,
              g_c3Wins, g_c3Losses, g_c3Breakeven));

      int timeoutCloses = 0, normalCloses = 0;
      for(int i = 0; i < g_closureTrackerCount; i++)
      {
          if(g_closureTracker[i].timeoutClose) timeoutCloses++;
          else if(g_closureTracker[i].closeTime > 0) normalCloses++;
      }
      LogPrint("[CLOSURE_SUMMARY] Total=" + IntegerToString(g_closureTrackerCount) +
               " | Normal=" + IntegerToString(normalCloses) +
               " | Timeout=" + IntegerToString(timeoutCloses), LOG_LEVEL_INFO);

     LogPrint("[LOG_SUMMARY] " + LogGov_GetStats(), LOG_LEVEL_INFO);

     double linesPerSignal = (g_totalSignalCommits > 0) ?
         ((double)g_logGovernor.logsThisSession / (double)g_totalSignalCommits) : 0.0;
     LogPrint("[LOG_EFFICIENCY] LinesPerSignal=" + DoubleToString(linesPerSignal, 1), LOG_LEVEL_INFO);

     LogPrint(StringFormat("[OBS] Exec=%d | Dup=%d | Lot=%d | Trace=%d | FEG=%d",
         g_totalOrdersSent, g_dupBlocked, g_lotCalls, g_traceCalls, g_fegBlocked), LOG_LEVEL_INFO);

     LogPrint("[DEINIT] Omak FxYO stopped", LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| OnTrade — Deal tracking for real-time P&L monitoring            |
//+------------------------------------------------------------------+
void OnTrade()
{
   static int s_lastDeals = 0;
   int currentDeals = HistoryDealsTotal();
   
   if(currentDeals <= s_lastDeals)
      return;
   
   for(int i = s_lastDeals; i < currentDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket <= 0)
         continue;
      
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber)
         continue;
      
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      
      if(entryType == DEAL_ENTRY_IN || entryType == DEAL_ENTRY_INOUT)
      {
         LogPrint("[DEAL_IN] ticket=" + IntegerToString(ticket) +
                  " | profit=" + DoubleToString(profit, 2), LOG_LEVEL_INFO);
      }
      else if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY)
       {
          LogPrint("[DEAL_OUT] ticket=" + IntegerToString(ticket) +
                   " | profit=" + DoubleToString(profit, 2), LOG_LEVEL_INFO);

           ulong positionTicket = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
           if(positionTicket > 0)
           {
              int mapIdx = FindPositionMapEntryByTicket(positionTicket);
              if(mapIdx >= 0)
              {
                 PositionGUIDMap mapEntry;
                 if(GetPositionMapEntry(mapIdx, mapEntry))
                 {
                    OM_ClearSlot(mapEntry.signalGUID);
                    LogPrint("[SLOT_RELEASED] GUID=" + IntegerToString(mapEntry.signalGUID) +
                             " | reason=POSITION_CLOSED", LOG_LEVEL_INFO);
                 }
              }
           }
       }
   }
   
   s_lastDeals = currentDeals;
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS - Tick Price Management                        |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| PositionMapEntry — C1 pipeline handoff struct                     |
//+------------------------------------------------------------------+
struct PositionMapEntry
{
   ulong  position_ticket;
   ulong  signal_guid;
   double c1_high;
   double c1_low;
   double c2_high;
   double c2_low;
   double protected_swing;
};

//+------------------------------------------------------------------+
//| GetActivePipelineGUID — Returns the GUID of the currently active |
//| signal pipeline (branchLockedSignal from active branch).          |
//+------------------------------------------------------------------+
ulong GetActivePipelineGUID()
{
   if(g_activeBranch == BRANCH_INTRADAY)
      return g_branchAContext.branchLockedSignal.m_guid;
   if(g_activeBranch == BRANCH_SWING)
      return g_branchBContext.branchLockedSignal.m_guid;
   return 0;
}

//+------------------------------------------------------------------+
//| FindActiveSignalSlot — Searches C2/C3 pools for the slot       |
//| that holds the given GUID. Returns -1 if not found.              |
//+------------------------------------------------------------------+
int FindActiveSignalSlot(ulong guid)
{
   for(int i = 0; i < MAX_SLOTS; i++)
   {
      if(g_activeC2[i].m_guid == guid) return i;
      if(g_activeC3[i].m_guid == guid) return i + MAX_SLOTS;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| PreAllocateSignalGUIDEntry — Pre-allocate map slot by signal     |
//| GUID before position ticket exists (post-fill linking).           |
//| Called at STAGE_READY / EXECUTION_TRIGGERED so the GUID entry    |
//| survives signal slot clearing.                                     |
//| REGRESSION_GUARD: Find first empty slot instead of blind append, |
//| preventing off-by-two corruption.                                    |
//| entryPrice=0.0 until UpdatePositionGUIDMap sets actual filled     |
//| price from the deal.                                              |
//+------------------------------------------------------------------+
bool PreAllocateSignalGUIDEntry(ulong signalGUID, double c1High, double c1Low,
                                 double c2High, double c2Low,
                                 ENUM_EXECUTION_BRANCH branch, ENUM_DIRECTION dir,
                                 ENUM_CLOSURE_TYPE closureType, double entryPrice)
{
   // REGRESSION_GUARD_V58_P0_1
   if(signalGUID == 0)
      return false;

   // Already has a pre-allocated entry in dynamic map — update c2 if needed
   for(int i = 0; i < g_positionMapCount; i++)
   {
      if(g_positionMap[i].signalGUID == signalGUID)
      {
         if(c2High > 0.0 && g_positionMap[i].c2_high == 0.0)
            g_positionMap[i].c2_high = c2High;
         if(c2Low > 0.0 && g_positionMap[i].c2_low == 0.0)
            g_positionMap[i].c2_low = c2Low;
         return true;
      }
   }
   // Already in static fallback
   if(g_usingStaticPositionMap)
   {
      for(int i = 0; i < g_staticPositionMapCount; i++)
      {
         if(g_staticPositionMap[i].signalGUID == signalGUID)
         {
            if(c2High > 0.0 && g_staticPositionMap[i].c2_high == 0.0)
               g_staticPositionMap[i].c2_high = c2High;
            if(c2Low > 0.0 && g_staticPositionMap[i].c2_low == 0.0)
               g_staticPositionMap[i].c2_low = c2Low;
            return true;
         }
      }
   }

   // REGRESSION_GUARD_V58_P0_1: Find first empty slot before appending
   int slotIdx = -1;
   for(int i = 0; i < g_positionMapCount; i++)
   {
      if(g_positionMap[i].signalGUID == 0)
      {
         slotIdx = i;
         break;
      }
   }

   if(slotIdx < 0)
   {
      // No empty slot — append new
      slotIdx = g_positionMapCount;
      int newSize = ArrayResize(g_positionMap, slotIdx + 1, slotIdx + 50);
      if(newSize <= slotIdx)
      {
         int lastErr = GetLastError();
         LogPrint("[GUID_MAP_RSZ_FAIL] ArrayResize(" + IntegerToString(slotIdx) + "+1) | err=" +
                  IntegerToString(lastErr) + " | GUID=" + IntegerToString(signalGUID) +
                  " | fallback=static", LOG_LEVEL_ERROR);

         if(g_staticPositionMapCount >= MAX_STATIC_GUID_MAP)
         {
            LogPrint("[GUID_MAP_STATIC_FULL] GUID=" + IntegerToString(signalGUID), LOG_LEVEL_ERROR);
            return false;
         }
         int s = g_staticPositionMapCount;
         g_staticPositionMap[s].positionTicket = 0;
         g_staticPositionMap[s].signalGUID = signalGUID;
         g_staticPositionMap[s].c1_high = c1High;
         g_staticPositionMap[s].c1_low = c1Low;
         g_staticPositionMap[s].c2_high = c2High;
         g_staticPositionMap[s].c2_low = c2Low;
         g_staticPositionMap[s].branch = branch;
         g_staticPositionMap[s].direction = dir;
         g_staticPositionMap[s].closureType = closureType;
         // entryPrice=0.0 — filled by UpdatePositionGUIDMap on actual fill
         g_staticPositionMap[s].entryPrice = 0.0;
         g_staticPositionMap[s].entryTime = 0;
         // protectedSwing from signal if direction known
         if(dir == DIRECTION_BUY)
            g_staticPositionMap[s].protectedSwing = (c2Low > 0.0) ? c2Low : 0.0;
         else if(dir == DIRECTION_SELL)
            g_staticPositionMap[s].protectedSwing = (c2High > 0.0) ? c2High : 0.0;
         else
            g_staticPositionMap[s].protectedSwing = 0.0;
         g_staticPositionMapCount++;
         g_usingStaticPositionMap = true;
         LogPrint("[GUID_MAP_PREALLOC_STATIC] GUID=" + IntegerToString(signalGUID) +
                  " | slot=" + IntegerToString(s) +
                  " | c1_h=" + DoubleToString(c1High, 5) +
                  " | c1_l=" + DoubleToString(c1Low, 5) +
                  " | entry=0.0(will_fill)", LOG_LEVEL_INFO);
         return true;
      }
      // Appended — increment count
      g_positionMapCount++;
   }

   // Populate the slot (reused empty or newly appended)
   g_positionMap[slotIdx].positionTicket = 0;
   g_positionMap[slotIdx].signalGUID = signalGUID;
   g_positionMap[slotIdx].c1_high = c1High;
   g_positionMap[slotIdx].c1_low = c1Low;
   g_positionMap[slotIdx].c2_high = c2High;
   g_positionMap[slotIdx].c2_low = c2Low;
   g_positionMap[slotIdx].branch = branch;
   g_positionMap[slotIdx].direction = dir;
   g_positionMap[slotIdx].closureType = closureType;
   // entryPrice=0.0 — filled by UpdatePositionGUIDMap on actual fill
   g_positionMap[slotIdx].entryPrice = 0.0;
   g_positionMap[slotIdx].entryTime = 0;
   // protectedSwing from signal if direction known
   if(dir == DIRECTION_BUY)
      g_positionMap[slotIdx].protectedSwing = (c2Low > 0.0) ? c2Low : 0.0;
   else if(dir == DIRECTION_SELL)
      g_positionMap[slotIdx].protectedSwing = (c2High > 0.0) ? c2High : 0.0;
   else
      g_positionMap[slotIdx].protectedSwing = 0.0;

   LogPrint(StringFormat("[GUID_PREALLOC] slot=%d GUID=%I64u | c1_h=%.5f c1_l=%.5f c2_h=%.5f c2_l=%.5f",
            slotIdx, signalGUID, c1High, c1Low, c2High, c2Low), LOG_LEVEL_INFO);
   return true;
}

//+------------------------------------------------------------------+
//| LinkGUIDToTicket — Link a position ticket to a pre-allocated     |
//| GUID entry post-fill. Searches both dynamic and static maps.      |
//| Added protectedSwing parameter.           |
//+------------------------------------------------------------------+
bool LinkGUIDToTicket(ulong positionTicket, ulong signalGUID, double entryPrice, double protectedSwing = 0.0)
{
   if(signalGUID == 0 || positionTicket == 0)
      return false;

   for(int i = 0; i < g_positionMapCount; i++)
   {
      if(g_positionMap[i].signalGUID == signalGUID)
      {
         // Prevent duplicate attachment: if this GUID already attached to a different ticket, block
         if(g_positionMap[i].positionTicket != 0 && g_positionMap[i].positionTicket != positionTicket)
         {
            LogPrint(StringFormat("[GUID_DUPLICATE_BLOCKED] GUID=%I64u existingTicket=%I64u attempted=%I64u", g_positionMap[i].signalGUID, g_positionMap[i].positionTicket, positionTicket), LOG_LEVEL_WARN);
            return false;
         }
         g_positionMap[i].positionTicket = positionTicket;
         g_positionMap[i].entryPrice = entryPrice;
         if(protectedSwing > 0.0)
            g_positionMap[i].protectedSwing = protectedSwing;
         g_positionMap[i].entryTime = TimeCurrent();
         LogPrint(StringFormat("[GUID_ATTACH] GUID=%I64u | Ticket=%I64u | entry=%.5f | protectedSwing=%.5f", signalGUID, positionTicket, entryPrice, protectedSwing), LOG_LEVEL_INFO);
         // REGRESSION_GUARD_V52.5_PositionGUIDMap
         return true;
      }
   }

   if(g_usingStaticPositionMap)
   {
      for(int i = 0; i < g_staticPositionMapCount; i++)
      {
         if(g_staticPositionMap[i].signalGUID == signalGUID)
         {
            if(g_staticPositionMap[i].positionTicket != 0 && g_staticPositionMap[i].positionTicket != positionTicket)
            {
               LogPrint(StringFormat("[GUID_DUPLICATE_BLOCKED] GUID=%I64u existingTicket=%I64u attempted=%I64u", g_staticPositionMap[i].signalGUID, g_staticPositionMap[i].positionTicket, positionTicket), LOG_LEVEL_WARN);
               return false;
            }
            g_staticPositionMap[i].positionTicket = positionTicket;
            g_staticPositionMap[i].entryPrice = entryPrice;
            if(protectedSwing > 0.0)
               g_staticPositionMap[i].protectedSwing = protectedSwing;
            g_staticPositionMap[i].entryTime = TimeCurrent();
            LogPrint(StringFormat("[GUID_ATTACH] GUID=%I64u | Ticket=%I64u | entry=%.5f | protectedSwing=%.5f | src=static", signalGUID, positionTicket, entryPrice, protectedSwing), LOG_LEVEL_INFO);
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| FindPositionMapEntryByTicket — Searches both dynamic and static  |
//| maps. Returns combined index (< g_positionMapCount = dynamic,     |
//| >= g_positionMapCount = static). Returns -1 if not found.         |
//+------------------------------------------------------------------+
int FindPositionMapEntryByTicket(ulong positionTicket)
{
   for(int i = 0; i < g_positionMapCount; i++)
   {
      if(g_positionMap[i].positionTicket == positionTicket)
         return i;
   }
   if(g_usingStaticPositionMap)
   {
      for(int i = 0; i < g_staticPositionMapCount; i++)
      {
         if(g_staticPositionMap[i].positionTicket == positionTicket)
            return i + g_positionMapCount;
      }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| GetPositionMapEntry — Unified reader for both dynamic & static   |
//+------------------------------------------------------------------+
bool GetPositionMapEntry(int idx, PositionGUIDMap &outEntry)
{
   if(idx >= 0 && idx < g_positionMapCount)
   {
      outEntry = g_positionMap[idx];
      return true;
   }
   int staticIdx = idx - g_positionMapCount;
   if(g_usingStaticPositionMap && staticIdx >= 0 && staticIdx < g_staticPositionMapCount)
   {
      outEntry = g_staticPositionMap[staticIdx];
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| GetProtectedSwingByTicket — Returns c2_low/c2_high from GUIDMap  |
//| for the specified position ticket. Used by PM_ManageStructuralTrail|
//| to anchor trailing stop to the absolute C2 candle extreme.        |
//| Falls back to active signal slot data if map stores 0.0 due to    |
//| fast transaction race conditions.                                  |
//+------------------------------------------------------------------+
bool GetProtectedSwingByTicket(ulong ticket, double &c2_low, double &c2_high)
{
   int idx = FindPositionMapEntryByTicket(ticket);
   if(idx >= 0)
   {
      PositionGUIDMap entry;
      if(GetPositionMapEntry(idx, entry) && entry.signalGUID != 0)
      {
         c2_low = entry.c2_low;
         c2_high = entry.c2_high;
         // Fallback: if c2 values are 0.0 due to race condition, try reading
         // from the active signal slot where PreAllocateSignalGUIDEntry stored them
         if(c2_low == 0.0 || c2_high == 0.0)
         {
            int slotIndex = FindActiveSignalSlot(entry.signalGUID);
            if(slotIndex >= 0)
            {
               bool isC2 = (slotIndex < MAX_SLOTS);
               int poolIdx = (slotIndex < MAX_SLOTS) ? slotIndex : slotIndex - MAX_SLOTS;
               if(c2_low == 0.0)
                  c2_low = isC2 ? g_activeC2[poolIdx].c2_low : g_activeC3[poolIdx].c2_low;
               if(c2_high == 0.0)
                  c2_high = isC2 ? g_activeC2[poolIdx].c2_high : g_activeC3[poolIdx].c2_high;
               LogPrint("[SWING_FALLBACK] ticket=" + IntegerToString(ticket) +
                        " | c2_low=" + DoubleToString(c2_low, _Digits) +
                        " | c2_high=" + DoubleToString(c2_high, _Digits), LOG_LEVEL_DEBUG);
            }
         }
         if(c2_low > 0.0 || c2_high > 0.0)
            return true;
      }
   }

   LogPrint("[TRAIL_DIAG] No GUIDMap entry for ticket=" + IntegerToString(ticket) +
            " | legacyMap=" + (idx >= 0 ? "found" : "missing"), LOG_LEVEL_DEBUG);
   return false;
}

//+------------------------------------------------------------------+
//| GetPositionBranchByTicket — Returns the execution branch from the |
//| PositionGUIDMap for the specified position ticket.                |
//| Used by EE_ManageStructuralTrail for branch-aware position filter.|
//+------------------------------------------------------------------+
ENUM_EXECUTION_BRANCH GetPositionBranchByTicket(ulong ticket)
{
   int idx = FindPositionMapEntryByTicket(ticket);
   if(idx >= 0)
   {
      PositionGUIDMap entry;
      if(GetPositionMapEntry(idx, entry) && entry.signalGUID != 0)
         return entry.branch;
   }
   return BRANCH_INTRADAY;
}

//+------------------------------------------------------------------+
//| UpdatePositionGUIDMap — Appends a PositionMapEntry to the global |
//| position map for structural exit reference.                       |
//| Now tries GUID-based linking first, falls back to new allocation. |
//+------------------------------------------------------------------+
// REGRESSION_GUARD_V52.5_PositionGUIDMap
// REGRESSION_GUARD_ENTRYPRICE: Use actual filled entry price from deal, NOT protected_swing/SL
bool UpdatePositionGUIDMap(PositionMapEntry &entry)
{
   if(entry.signal_guid == 0)
   {
      LogPrint("[POS_MAP] Update skipped — signal_guid=0", LOG_LEVEL_WARN);
      return false;
   }

   // REGRESSION_GUARD_ENTRYPRICE: Resolve actual filled entry price from deal
   double actualEntryPrice = 0.0;

   // Primary: get entry price from position open price (most reliable)
   if(PositionSelectByTicket(entry.position_ticket))
      actualEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   // Fallback: signal slot entry price
      if(actualEntryPrice <= 0.0)
      {
         int sigSlot = FindActiveSignalSlot(entry.signal_guid);
         if(sigSlot >= 0)
         {
            int poolIdx = (sigSlot < MAX_SLOTS) ? sigSlot : sigSlot - MAX_SLOTS;
            actualEntryPrice = (sigSlot < MAX_SLOTS) ? g_activeC2[poolIdx].entry_price : g_activeC3[poolIdx].entry_price;
         }
      }
   // Final fallback: protected_swing (last resort — not ideal)
   if(actualEntryPrice <= 0.0)
   {
      LogPrint("[POS_MAP] WARNING: Could not resolve entryPrice for GUID=" +
               IntegerToString(entry.signal_guid) + " | using protected_swing as fallback",
               LOG_LEVEL_WARN);
      actualEntryPrice = entry.protected_swing;
   }

   // Try linking to a pre-allocated GUID entry first (with protectedSwing)
   if(LinkGUIDToTicket(entry.position_ticket, entry.signal_guid, actualEntryPrice, entry.protected_swing))
      return true;

   // No pre-allocated entry — allocate new one with safe resize
   int idx = g_positionMapCount;
   int newSize = ArrayResize(g_positionMap, idx + 1, idx + 50);
   if(newSize <= idx)
   {
      int lastErr = GetLastError();
      LogPrint("[POS_MAP_RSZ_FAIL] ArrayResize(" + IntegerToString(idx) + "+1) | err=" +
               IntegerToString(lastErr) + " | GUID=" + IntegerToString(entry.signal_guid) +
               " | fallback=static", LOG_LEVEL_ERROR);

      if(g_staticPositionMapCount >= MAX_STATIC_GUID_MAP)
      {
         LogPrint("[POS_MAP_STATIC_FULL] GUID=" + IntegerToString(entry.signal_guid), LOG_LEVEL_ERROR);
         return false;
      }
      int s = g_staticPositionMapCount;
      g_staticPositionMap[s].positionTicket = entry.position_ticket;
      g_staticPositionMap[s].signalGUID = entry.signal_guid;
      g_staticPositionMap[s].c1_high = entry.c1_high;
      g_staticPositionMap[s].c1_low = entry.c1_low;
      g_staticPositionMap[s].c2_high = entry.c2_high;
      g_staticPositionMap[s].c2_low = entry.c2_low;
      g_staticPositionMap[s].branch = g_activeBranch;
      g_staticPositionMap[s].direction = DIRECTION_NONE;
      g_staticPositionMap[s].closureType = CLOSURE_NONE;
      // REGRESSION_GUARD_ENTRYPRICE: Use actualEntryPrice, NOT protected_swing
      g_staticPositionMap[s].entryPrice = actualEntryPrice;
      g_staticPositionMap[s].protectedSwing = entry.protected_swing;
      g_staticPositionMap[s].entryTime = TimeCurrent();
      g_staticPositionMapCount++;
      g_usingStaticPositionMap = true;

      // REGRESSION_GUARD: Validate entryPrice != protectedSwing
      if(g_staticPositionMap[s].entryPrice == g_staticPositionMap[s].protectedSwing)
      {
         LogPrint("[REGRESSION_FAIL] entryPrice=protectedSwing for GUID=" +
                  IntegerToString(entry.signal_guid), LOG_LEVEL_ERROR);
      }

      LogPrint("[C1_MAP] GUID=" + IntegerToString(entry.signal_guid) +
               " | entry=" + DoubleToString(actualEntryPrice, 5) +
               " | protectedSwing=" + DoubleToString(entry.protected_swing, 5) +
               " | c1_h=" + DoubleToString(entry.c1_high, 5) +
               " | c1_l=" + DoubleToString(entry.c1_low, 5) +
               " | src=static", LOG_LEVEL_INFO);
      return true;
   }

   g_positionMap[idx].positionTicket = entry.position_ticket;
   g_positionMap[idx].signalGUID = entry.signal_guid;
   g_positionMap[idx].c1_high = entry.c1_high;
   g_positionMap[idx].c1_low = entry.c1_low;
   g_positionMap[idx].c2_high = entry.c2_high;
   g_positionMap[idx].c2_low = entry.c2_low;
   g_positionMap[idx].branch = g_activeBranch;
   g_positionMap[idx].direction = DIRECTION_NONE;
   g_positionMap[idx].closureType = CLOSURE_NONE;
   // Direction is set during pre-allocation; for post-fill-only entries,
   // we derive it from the signal's stored data if available
     int slot = FindActiveSignalSlot(entry.signal_guid);
     if(slot >= 0)
     {
        int poolIdx = (slot < MAX_SLOTS) ? slot : slot - MAX_SLOTS;
        if(slot < MAX_SLOTS)
        {
           g_positionMap[idx].direction = g_activeC2[poolIdx].direction;
           g_positionMap[idx].closureType = g_activeC2[poolIdx].closureType;
        }
        else
        {
           g_positionMap[idx].direction = g_activeC3[poolIdx].direction;
           g_positionMap[idx].closureType = g_activeC3[poolIdx].closureType;
        }
     }
   // REGRESSION_GUARD_ENTRYPRICE: Use actualEntryPrice, NOT protected_swing
   g_positionMap[idx].entryPrice = actualEntryPrice;
   g_positionMap[idx].protectedSwing = entry.protected_swing;
   g_positionMap[idx].entryTime = TimeCurrent();
   g_positionMapCount++;

   // REGRESSION_GUARD: Validate entryPrice != protectedSwing
   if(g_positionMap[idx].entryPrice == g_positionMap[idx].protectedSwing)
   {
      LogPrint("[REGRESSION_FAIL] entryPrice=protectedSwing for GUID=" +
               IntegerToString(entry.signal_guid), LOG_LEVEL_ERROR);
   }

   LogPrint("[C1_MAP] GUID=" + IntegerToString(entry.signal_guid) +
            " | entry=" + DoubleToString(actualEntryPrice, 5) +
            " | protectedSwing=" + DoubleToString(entry.protected_swing, 5) +
            " | c1_h=" + DoubleToString(entry.c1_high, 5) +
            " | c1_l=" + DoubleToString(entry.c1_low, 5) +
            " | src=dynamic", LOG_LEVEL_INFO);
   return true;
}

//+------------------------------------------------------------------+
//| GetC1HighForGUID — Read C1 high from pre-allocated map entry     |
//| Searches the existing position map (set by PreAllocateSignalGUID) |
//+------------------------------------------------------------------+
double GetC1HighForGUID(ulong guid)
{
   for(int i = 0; i < g_positionMapCount; i++)
   {
      if(g_positionMap[i].signalGUID == guid)
         return g_positionMap[i].c1_high;
   }
   if(g_usingStaticPositionMap)
   {
      for(int i = 0; i < g_staticPositionMapCount; i++)
      {
         if(g_staticPositionMap[i].signalGUID == guid)
            return g_staticPositionMap[i].c1_high;
      }
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| GetC1LowForGUID — Read C1 low from pre-allocated map entry       |
//+------------------------------------------------------------------+
double GetC1LowForGUID(ulong guid)
{
   for(int i = 0; i < g_positionMapCount; i++)
   {
      if(g_positionMap[i].signalGUID == guid)
         return g_positionMap[i].c1_low;
   }
   if(g_usingStaticPositionMap)
   {
      for(int i = 0; i < g_staticPositionMapCount; i++)
      {
         if(g_staticPositionMap[i].signalGUID == guid)
            return g_staticPositionMap[i].c1_low;
      }
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| GetC2HighForGUID — Read C2 high from pre-allocated map entry     |
//+------------------------------------------------------------------+
double GetC2HighForGUID(ulong guid)
{
   for(int i = 0; i < g_positionMapCount; i++)
   {
      if(g_positionMap[i].signalGUID == guid)
         return g_positionMap[i].c2_high;
   }
   if(g_usingStaticPositionMap)
   {
      for(int i = 0; i < g_staticPositionMapCount; i++)
      {
         if(g_staticPositionMap[i].signalGUID == guid)
            return g_staticPositionMap[i].c2_high;
      }
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| GetC2LowForGUID — Read C2 low from pre-allocated map entry       |
//+------------------------------------------------------------------+
double GetC2LowForGUID(ulong guid)
{
   for(int i = 0; i < g_positionMapCount; i++)
   {
      if(g_positionMap[i].signalGUID == guid)
         return g_positionMap[i].c2_low;
   }
   if(g_usingStaticPositionMap)
   {
      for(int i = 0; i < g_staticPositionMapCount; i++)
      {
         if(g_staticPositionMap[i].signalGUID == guid)
            return g_staticPositionMap[i].c2_low;
      }
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| UpdatePositionGUIDMap — Simplified ticket→GUID map population    |
//| Populates new parallel arrays + updates existing legacy map         |
//| c2_low/c2_high default to 0.0 — populated from pre-allocated        |
//| entry or from caller when available.                              |
//| REGRESSION_GUARD: Find by GUID first, use deal-level              |
//| entry price. No more position-index-based lookups.                |
//+------------------------------------------------------------------+
void UpdatePositionGUIDMap(ulong ticket, ulong guid, double c2_low = 0.0, double c2_high = 0.0, ulong dealTicket = 0)
{
   // REGRESSION_GUARD_V58_P0_1
   if(ticket == 0 || guid == 0)
      return;

   // REGRESSION_GUARD_V58_P0_1: Resolve actual filled entry price from deal
   double actualEntryPrice = 0.0;
   if(dealTicket > 0 && HistorySelect(0, TimeCurrent()))
      actualEntryPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   if(actualEntryPrice <= 0.0 && PositionSelectByTicket(ticket))
      actualEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   if(actualEntryPrice <= 0.0)
   {
      int sigSlot = FindActiveSignalSlot(guid);
      if(sigSlot >= 0)
      {
         int poolIdx = (sigSlot < MAX_SLOTS) ? sigSlot : sigSlot - MAX_SLOTS;
         actualEntryPrice = (sigSlot < MAX_SLOTS) ? g_activeC2[poolIdx].entry_price : g_activeC3[poolIdx].entry_price;
      }
   }
   if(actualEntryPrice <= 0.0)
   {
      LogPrint("[POS_MAP] WARNING: Could not resolve entryPrice for GUID=" +
               IntegerToString(guid) + " | ticket=" + IntegerToString(ticket), LOG_LEVEL_WARN);
   }

   // REGRESSION_GUARD_V58_P0_1: Update legacy map FIRST (search by GUID)
   int legacyIdx = -1;
   for(int i = 0; i < g_positionMapCount; i++)
   {
      if(g_positionMap[i].signalGUID == guid)
      {
         legacyIdx = i;
         break;
      }
   }
   if(legacyIdx >= 0)
   {
      // Prevent duplicate ticket assignment
      if(g_positionMap[legacyIdx].positionTicket != 0 && g_positionMap[legacyIdx].positionTicket != ticket)
      {
         LogPrint(StringFormat("[GUID_DUPLICATE_BLOCKED] GUID=%I64u existingTicket=%I64u attempted=%I64u", guid, g_positionMap[legacyIdx].positionTicket, ticket), LOG_LEVEL_WARN);
      }
      else
      {
         g_positionMap[legacyIdx].positionTicket = ticket;
         g_positionMap[legacyIdx].entryTime = TimeCurrent();
         if(c2_low > 0.0) g_positionMap[legacyIdx].c2_low = c2_low;
         if(c2_high > 0.0) g_positionMap[legacyIdx].c2_high = c2_high;
         if(actualEntryPrice > 0.0)
         {
            g_positionMap[legacyIdx].entryPrice = actualEntryPrice;
            if(g_positionMap[legacyIdx].direction == DIRECTION_BUY)
               g_positionMap[legacyIdx].protectedSwing = g_positionMap[legacyIdx].c2_low;
            else if(g_positionMap[legacyIdx].direction == DIRECTION_SELL)
               g_positionMap[legacyIdx].protectedSwing = g_positionMap[legacyIdx].c2_high;
            if(g_positionMap[legacyIdx].entryPrice == g_positionMap[legacyIdx].protectedSwing)
            {
               LogPrint("[REGRESSION_FAIL] entryPrice=protectedSwing for GUID=" + IntegerToString(guid), LOG_LEVEL_ERROR);
            }
            LogPrint(StringFormat("[GUID_STORE_WRITE] GUID=%I64u | entry=%.5f | protectedSwing=%.5f | src=guid_legacy", guid, actualEntryPrice, g_positionMap[legacyIdx].protectedSwing), LOG_LEVEL_INFO);
         }
      }
   }

   // Also update static fallback if no legacy entry found
   if(g_usingStaticPositionMap && legacyIdx < 0)
   {
      for(int i = 0; i < g_staticPositionMapCount; i++)
      {
         if(g_staticPositionMap[i].signalGUID == guid)
         {
            if(g_staticPositionMap[i].positionTicket != 0 && g_staticPositionMap[i].positionTicket != ticket)
            {
               LogPrint(StringFormat("[GUID_DUPLICATE_BLOCKED] GUID=%I64u existingTicket=%I64u attempted=%I64u", guid, g_staticPositionMap[i].positionTicket, ticket), LOG_LEVEL_WARN);
            }
            else
            {
               g_staticPositionMap[i].positionTicket = ticket;
               g_staticPositionMap[i].entryTime = TimeCurrent();
               if(c2_low > 0.0) g_staticPositionMap[i].c2_low = c2_low;
               if(c2_high > 0.0) g_staticPositionMap[i].c2_high = c2_high;
               if(actualEntryPrice > 0.0)
               {
                  g_staticPositionMap[i].entryPrice = actualEntryPrice;
                  if(g_staticPositionMap[i].direction == DIRECTION_BUY)
                     g_staticPositionMap[i].protectedSwing = g_staticPositionMap[i].c2_low;
                  else if(g_staticPositionMap[i].direction == DIRECTION_SELL)
                     g_staticPositionMap[i].protectedSwing = g_staticPositionMap[i].c2_high;
                  if(g_staticPositionMap[i].entryPrice == g_staticPositionMap[i].protectedSwing)
                  {
                     LogPrint("[REGRESSION_FAIL] entryPrice=protectedSwing for GUID=" + IntegerToString(guid), LOG_LEVEL_ERROR);
                  }
                  LogPrint(StringFormat("[GUID_STORE_WRITE] GUID=%I64u | entry=%.5f | protectedSwing=%.5f | src=static_guid", guid, actualEntryPrice, g_staticPositionMap[i].protectedSwing), LOG_LEVEL_INFO);
               }
            }
            break;
         }
      }
   }

   // NOTE: Parallel arrays removed. Canonical store is g_positionMap[] and g_staticPositionMap[].
   // Emit a write marker for observability
   LogPrint(StringFormat("[GUID_STORE_WRITE] GUID=%I64u | ticket=%I64u | c2_low=%.5f | c2_high=%.5f", guid, ticket, c2_low, c2_high), LOG_LEVEL_DEBUG);
}

//+------------------------------------------------------------------+
//| GetGUIDFromPositionMap — Lookup GUID by ticket from parallel map  |
//+------------------------------------------------------------------+
// REGRESSION_GUARD_V52.5_PositionGUIDMap
ulong GetGUIDFromPositionMap(ulong ticket)
{
   // Lookup in canonical position map first
   for(int i = 0; i < g_positionMapCount; i++)
   {
      if(g_positionMap[i].positionTicket == ticket)
         return g_positionMap[i].signalGUID;
   }
   // Fallback to static map
   if(g_usingStaticPositionMap)
   {
      for(int i = 0; i < g_staticPositionMapCount; i++)
      {
         if(g_staticPositionMap[i].positionTicket == ticket)
            return g_staticPositionMap[i].signalGUID;
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| RemovePositionMapEntry — Remove ticket from parallel map          |
//+------------------------------------------------------------------+
// REGRESSION_GUARD_V52.5_PositionGUIDMap
void RemovePositionMapEntry(ulong ticket)
{
   if(ticket == 0)
      return;
   // Remove from dynamic map
   for(int i = g_positionMapCount - 1; i >= 0; i--)
   {
      if(g_positionMap[i].positionTicket == ticket)
      {
         LogPrint(StringFormat("[GUID_RELEASE] GUID=%I64u | ticket=%I64u | src=dynamic", g_positionMap[i].signalGUID, ticket), LOG_LEVEL_INFO);
         // clear the slot: keep the signalGUID for historical telemetry but zero the ticket
         g_positionMap[i].positionTicket = 0;
         g_positionMap[i].entryTime = 0;
         g_positionMap[i].entryPrice = 0.0;
         g_positionMap[i].protectedSwing = 0.0;
         g_positionMap[i].c2_low = 0.0;
         g_positionMap[i].c2_high = 0.0;
         return;
      }
   }
   // Remove from static fallback
   if(g_usingStaticPositionMap)
   {
      for(int i = g_staticPositionMapCount - 1; i >= 0; i--)
      {
         if(g_staticPositionMap[i].positionTicket == ticket)
         {
            LogPrint(StringFormat("[GUID_RELEASE] GUID=%I64u | ticket=%I64u | src=static", g_staticPositionMap[i].signalGUID, ticket), LOG_LEVEL_INFO);
            g_staticPositionMap[i].positionTicket = 0;
            g_staticPositionMap[i].entryTime = 0;
            g_staticPositionMap[i].entryPrice = 0.0;
            g_staticPositionMap[i].protectedSwing = 0.0;
            g_staticPositionMap[i].c2_low = 0.0;
            g_staticPositionMap[i].c2_high = 0.0;
            return;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| GetC1HighForPosition — Get C1 high from parallel map by ticket   |
//+------------------------------------------------------------------+
double GetC1HighForPosition(ulong ticket)
{
   if(ticket == 0) return 0.0;
   ulong guid = GetGUIDFromPositionMap(ticket);
   if(guid == 0) return 0.0;
   return GetC1HighForGUID(guid);
}

//+------------------------------------------------------------------+
//| GetC1LowForPosition — Get C1 low from parallel map by ticket     |
//+------------------------------------------------------------------+
double GetC1LowForPosition(ulong ticket)
{
   if(ticket == 0) return 0.0;
   ulong guid = GetGUIDFromPositionMap(ticket);
   if(guid == 0) return 0.0;
   return GetC1LowForGUID(guid);
}

//+------------------------------------------------------------------+
//| GetC2HighForPosition — Get C2 high from parallel map by ticket   |
//+------------------------------------------------------------------+
double GetC2HighForPosition(ulong ticket)
{
   if(ticket == 0) return 0.0;
   ulong guid = GetGUIDFromPositionMap(ticket);
   if(guid == 0) return 0.0;
   return GetC2HighForGUID(guid);
}

//+------------------------------------------------------------------+
//| GetC2LowForPosition — Get C2 low from parallel map by ticket     |
//+------------------------------------------------------------------+
double GetC2LowForPosition(ulong ticket)
{
   if(ticket == 0) return 0.0;
   ulong guid = GetGUIDFromPositionMap(ticket);
   if(guid == 0) return 0.0;
   return GetC2LowForGUID(guid);
}

//+------------------------------------------------------------------+
//| HasC1Map — Check if C1_MAP exists for a GUID                     |
//+------------------------------------------------------------------+
bool HasC1Map(ulong guid)
{
   // REGRESSION_GUARD_C1MAP_V57_1
   for(int i = 0; i < g_positionMapCount; i++)
   {
      if(g_positionMap[i].signalGUID == guid && g_positionMap[i].positionTicket > 0)
         return true;
   }
   if(g_usingStaticPositionMap)
   {
      for(int i = 0; i < g_staticPositionMapCount; i++)
      {
         if(g_staticPositionMap[i].signalGUID == guid && g_staticPositionMap[i].positionTicket > 0)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| GetPositionGUIDMapByGUID — Find position map entry by GUID       |
//| Searches both dynamic and static maps. REGRESSION_GUARD_V58_P0_1 |
//+------------------------------------------------------------------+
bool GetPositionGUIDMapByGUID(ulong guid, PositionGUIDMap &map)
{
   // REGRESSION_GUARD_V58_P0_1
   if(guid == 0)
      return false;

   for(int i = 0; i < g_positionMapCount; i++)
   {
      if(g_positionMap[i].signalGUID == guid)
      {
         map = g_positionMap[i];
         return true;
      }
   }
   if(g_usingStaticPositionMap)
   {
      for(int i = 0; i < g_staticPositionMapCount; i++)
      {
         if(g_staticPositionMap[i].signalGUID == guid)
         {
            map = g_staticPositionMap[i];
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| CreateEmergencyC1Map — Emergency C1_MAP from signal data          |
//+------------------------------------------------------------------+
void CreateEmergencyC1Map(ulong guid, long positionTicket, ulong dealTicket)
{
   // REGRESSION_GUARD_C1MAP_V57_1

   LogPrint("[C1_MAP_EMERGENCY] Creating emergency C1_MAP for GUID=" +
            IntegerToString(guid) + " pos=" + IntegerToString((int)positionTicket), LOG_LEVEL_WARN);

   // Find signal data
   SLockedSignal sig;
   bool found = false;

   for(int i = 0; i < MAX_SLOTS; i++)
   {
      if(g_activeC2[i].m_guid == guid)
      {
         sig = g_activeC2[i];
         found = true;
         break;
      }
      if(g_activeC3[i].m_guid == guid)
      {
         sig = g_activeC3[i];
         found = true;
         break;
      }
   }

   if(!found)
   {
      // Also check canonical maps for cached C1/C2 data
      for(int i = 0; i < g_positionMapCount; i++)
      {
         if(g_positionMap[i].signalGUID == guid)
         {
            found = true;
            break;
         }
      }
      if(!found && g_usingStaticPositionMap)
      {
         for(int i = 0; i < g_staticPositionMapCount; i++)
         {
            if(g_staticPositionMap[i].signalGUID == guid)
            {
               found = true;
               break;
            }
         }
      }
   }

   if(!found)
   {
      LogPrint("[C1_MAP_EMERGENCY_FAIL] Cannot find signal for GUID=" +
               IntegerToString(guid), LOG_LEVEL_ERROR);
      return;
   }

   // Get actual entry price from position
   double actualEntryPrice = 0.0;
   if(positionTicket > 0 && PositionSelectByTicket((ulong)positionTicket))
      actualEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   if(actualEntryPrice <= 0.0)
      actualEntryPrice = sig.entry_price;

   // Try to link existing pre-allocated entry first
   bool linked = false;

   for(int i = 0; i < g_positionMapCount; i++)
   {
      if(g_positionMap[i].signalGUID == guid && g_positionMap[i].positionTicket == 0)
      {
         g_positionMap[i].positionTicket = (ulong)positionTicket;
         g_positionMap[i].entryPrice = actualEntryPrice;
         g_positionMap[i].protectedSwing = sig.stop_loss;
         g_positionMap[i].entryTime = TimeCurrent();
         if(sig.c1_high > 0.0) g_positionMap[i].c1_high = sig.c1_high;
         if(sig.c1_low > 0.0) g_positionMap[i].c1_low = sig.c1_low;
         if(sig.c2_high > 0.0) g_positionMap[i].c2_high = sig.c2_high;
         if(sig.c2_low > 0.0) g_positionMap[i].c2_low = sig.c2_low;
         g_positionMap[i].direction = sig.direction;
         g_positionMap[i].branch = (ENUM_EXECUTION_BRANCH)sig.branch;
         g_positionMap[i].closureType = sig.closureType;
         linked = true;
         break;
      }
   }

   if(!linked && g_usingStaticPositionMap)
   {
      for(int i = 0; i < g_staticPositionMapCount; i++)
      {
         if(g_staticPositionMap[i].signalGUID == guid && g_staticPositionMap[i].positionTicket == 0)
         {
            g_staticPositionMap[i].positionTicket = (ulong)positionTicket;
            g_staticPositionMap[i].entryPrice = actualEntryPrice;
            g_staticPositionMap[i].protectedSwing = sig.stop_loss;
            g_staticPositionMap[i].entryTime = TimeCurrent();
            if(sig.c1_high > 0.0) g_staticPositionMap[i].c1_high = sig.c1_high;
            if(sig.c1_low > 0.0) g_staticPositionMap[i].c1_low = sig.c1_low;
            if(sig.c2_high > 0.0) g_staticPositionMap[i].c2_high = sig.c2_high;
            if(sig.c2_low > 0.0) g_staticPositionMap[i].c2_low = sig.c2_low;
            g_staticPositionMap[i].direction = sig.direction;
            g_staticPositionMap[i].branch = (ENUM_EXECUTION_BRANCH)sig.branch;
            g_staticPositionMap[i].closureType = sig.closureType;
            linked = true;
            break;
         }
      }
   }

   if(!linked)
   {
      // Create new entry in dynamic map
      int idx = g_positionMapCount;
      int newSize = ArrayResize(g_positionMap, idx + 1, idx + 50);
      if(newSize > idx)
      {
         g_positionMap[idx].positionTicket = (ulong)positionTicket;
         g_positionMap[idx].signalGUID = guid;
         g_positionMap[idx].entryPrice = actualEntryPrice;
         g_positionMap[idx].protectedSwing = sig.stop_loss;
         g_positionMap[idx].entryTime = TimeCurrent();
         g_positionMap[idx].c1_high = sig.c1_high;
         g_positionMap[idx].c1_low = sig.c1_low;
         g_positionMap[idx].c2_high = sig.c2_high;
         g_positionMap[idx].c2_low = sig.c2_low;
         g_positionMap[idx].direction = sig.direction;
         g_positionMap[idx].branch = (ENUM_EXECUTION_BRANCH)sig.branch;
         g_positionMap[idx].closureType = sig.closureType;
         g_positionMapCount++;
         linked = true;
      }
      else
      {
         // Static fallback
         if(g_staticPositionMapCount < MAX_STATIC_GUID_MAP)
         {
            int s = g_staticPositionMapCount;
            g_staticPositionMap[s].positionTicket = (ulong)positionTicket;
            g_staticPositionMap[s].signalGUID = guid;
            g_staticPositionMap[s].entryPrice = actualEntryPrice;
            g_staticPositionMap[s].protectedSwing = sig.stop_loss;
            g_staticPositionMap[s].entryTime = TimeCurrent();
            g_staticPositionMap[s].c1_high = sig.c1_high;
            g_staticPositionMap[s].c1_low = sig.c1_low;
            g_staticPositionMap[s].c2_high = sig.c2_high;
            g_staticPositionMap[s].c2_low = sig.c2_low;
            g_staticPositionMap[s].direction = sig.direction;
            g_staticPositionMap[s].branch = (ENUM_EXECUTION_BRANCH)sig.branch;
            g_staticPositionMap[s].closureType = sig.closureType;
            g_staticPositionMapCount++;
            g_usingStaticPositionMap = true;
            linked = true;
         }
      }
   }

   if(linked)
   {
      LogPrint("[C1_MAP_EMERGENCY_CREATED] GUID=" + IntegerToString(guid) +
               " | entry=" + DoubleToString(actualEntryPrice, 5) +
               " | protectedSwing=" + DoubleToString(sig.stop_loss, 5) +
               " | c1_h=" + DoubleToString(sig.c1_high, 5) +
               " | c1_l=" + DoubleToString(sig.c1_low, 5) +
               " | c2_h=" + DoubleToString(sig.c2_high, 5) +
               " | c2_l=" + DoubleToString(sig.c2_low, 5), LOG_LEVEL_INFO);
   }
}

//+------------------------------------------------------------------+
//| VerifyOpenPositionMaps — Ensure every open position has C1_MAP   |
//+------------------------------------------------------------------+
void VerifyOpenPositionMaps()
{
   // REGRESSION_GUARD_C1MAP_VERIFY_V57_1

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket <= 0) continue;

      ulong guid = GetGUIDFromPositionMap(posTicket);
      if(guid == 0) continue;

      if(!HasC1Map(guid))
      {
         LogPrint("[REGRESSION_FAIL] Open position " + IntegerToString((int)posTicket) +
                  " has NO C1_MAP for GUID=" + IntegerToString(guid), LOG_LEVEL_ERROR);

         CreateEmergencyC1Map(guid, (long)posTicket, 0);
      }
   }
}

//+------------------------------------------------------------------+
//| UpdatePerformanceCounters — Increment C2/C3 win/loss/breakeven   |
//+------------------------------------------------------------------+
void UpdatePerformanceCounters(ulong guid, double pnl)
{
    if(guid == 0) return;
    SLockedSignal sig;
    if(FindSignalByGUID(guid, sig))
    {
        if(sig.closureType == CLOSURE_C2)
        {
            if(pnl > 0.0) g_c2Wins++;
            else if(pnl < 0.0) g_c2Losses++;
            else g_c2Breakeven++;
        }
        else if(sig.closureType == CLOSURE_C3)
        {
            if(pnl > 0.0) g_c3Wins++;
            else if(pnl < 0.0) g_c3Losses++;
            else g_c3Breakeven++;
        }

        LogInfo(StringFormat("[PERF_UPDATE] %s PnL=%.2f | C2: W=%d L=%d B=%d | C3: W=%d L=%d B=%d",
                sig.closureType == CLOSURE_C2 ? "C2" : "C3",
                pnl, g_c2Wins, g_c2Losses, g_c2Breakeven,
                g_c3Wins, g_c3Losses, g_c3Breakeven));
    }
    else
    {
        // GUID not found in signal store — use position map fallback
        for(int i = 0; i < g_positionMapCount; i++)
        {
            if(g_positionMap[i].signalGUID == guid)
            {
                if(g_positionMap[i].closureType == CLOSURE_C2)
                {
                    if(pnl > 0.0) g_c2Wins++;
                    else if(pnl < 0.0) g_c2Losses++;
                    else g_c2Breakeven++;
                }
                else if(g_positionMap[i].closureType == CLOSURE_C3)
                {
                    if(pnl > 0.0) g_c3Wins++;
                    else if(pnl < 0.0) g_c3Losses++;
                    else g_c3Breakeven++;
                }
                LogInfo(StringFormat("[PERF_UPDATE] %s (map) PnL=%.2f | C2: W=%d L=%d B=%d | C3: W=%d L=%d B=%d",
                        g_positionMap[i].closureType == CLOSURE_C2 ? "C2" : "C3",
                        pnl, g_c2Wins, g_c2Losses, g_c2Breakeven,
                        g_c3Wins, g_c3Losses, g_c3Breakeven));
                break;
            }
        }
    }
}
 // REGRESSION_GUARD_V54_3_PERFCOUNTERS

//+------------------------------------------------------------------+
//| ResolveGUIDByRequest — Map request_id to pipeline GUID            |
//| VERBATIM REPAIR: Finding 1 - GUID Identity Bridge                 |
//+------------------------------------------------------------------+
ulong ResolveGUIDByRequest(uint request_id)
{
   if(request_id == 0) return 0;
   for(int i = ArraySize(g_pendingLinks) - 1; i >= 0; i--)
   {
      if(g_pendingLinks[i].request_id == request_id)
      {
         ulong guid = g_pendingLinks[i].guid;
         ArrayRemove(g_pendingLinks, i, 1);
         PrintFormat("[GUID_BRIDGE_RESOLVED] request_id=%u -> GUID=%I64u", request_id, guid);
         return guid;
      }
   }
   return 0;
}

void OnTradeTransaction(
   const MqlTradeTransaction& trans,
   const MqlTradeRequest& request,
   const MqlTradeResult& result
)
{
   // --- BLOCK 1: Capture GUID from TRADE_TRANSACTION_REQUEST (live/demo path) ---
    // Peek only — do NOT ArrayRemove. DEAL_ADD's ResolveGUIDByRequest owns consumption.
    static ulong s_pendingGuid = 0;
    static ENUM_EXECUTION_BRANCH s_pendingBranch = BRANCH_INTRADAY;
    if(trans.type == TRADE_TRANSACTION_REQUEST)
    {
       for(int i = ArraySize(g_pendingLinks) - 1; i >= 0; i--)
       {
          if(g_pendingLinks[i].request_id == result.request_id)
          {
             s_pendingGuid = g_pendingLinks[i].guid;
             s_pendingBranch = g_pendingLinks[i].branch;
             PrintFormat("[PENDING_GUID_CAPTURED] request_id=%u guid=%I64u branch=%d", result.request_id, s_pendingGuid, s_pendingBranch);
             break;
          }
       }
      // Stale cleanup — TF-aware timeout per §XII
      for(int i = ArraySize(g_pendingLinks) - 1; i >= 0; i--)
      {
         ENUM_TIMEFRAMES entryTF = GetEntryTF(g_pendingLinks[i].branch);
         int timeoutSec = GetPendingOrderTimeoutSeconds(entryTF);
         if(TimeCurrent() - g_pendingLinks[i].created > timeoutSec)
         {
            PrintFormat("[PENDING_LINK_TRANSACTION_CLEANUP] request_id=%d guid=%I64u age_sec=%d timeout_sec=%d",
                         g_pendingLinks[i].request_id,
                         g_pendingLinks[i].guid,
                         TimeCurrent() - g_pendingLinks[i].created,
                         timeoutSec);
            ArrayRemove(g_pendingLinks, i, 1);
         }
      }
   }

    // --- BLOCK 2: Populate PositionGUIDMap on position open/close ---
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
       // ── UNIVERSAL DEAL_TRACK: Log for ALL deal types (IN, OUT, INOUT) ──
       // Uses HistorySelect for robustness — fires regardless of HistoryDealSelect
       // so broker-triggered exits (trailing SL, SL) are never invisible.
       // REGRESSION_GUARD_V54_3_P0_3
       ulong dealTicket = trans.deal;
       double dealPrice = 0.0;
       double dealVolume = 0.0;
       double dealProfit = 0.0;
       ENUM_DEAL_ENTRY dealEntryType = DEAL_ENTRY_IN;
       if(HistorySelect(0, TimeCurrent()))
       {
          dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
          dealVolume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
          dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
          dealEntryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
       }
       ulong dealGuid = GetGUIDFromPositionMap(trans.position);
       LogInfo(StringFormat("[DEAL_TRACK] ticket=%I64u pos=%I64u guid=%I64u entry=%s price=%.2f vol=%.2f profit=%.2f",
                dealTicket, trans.position, dealGuid,
                dealEntryType == DEAL_ENTRY_IN ? "IN" :
                dealEntryType == DEAL_ENTRY_OUT ? "OUT" :
                dealEntryType == DEAL_ENTRY_INOUT ? "INOUT" : "STATE",
                dealPrice, dealVolume, dealProfit));

       // Update performance counters for closing deals (broker-triggered SL/trailing)
       if((dealEntryType == DEAL_ENTRY_OUT || dealEntryType == DEAL_ENTRY_INOUT) && dealGuid != 0)
          UpdatePerformanceCounters(dealGuid, dealProfit);

        if(HistoryDealSelect(trans.deal))
        {
           long dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

             // ── DEAL_ENTRY_OUT: Release slot, emit exit marker, clean up ──
             if(dealEntry == DEAL_ENTRY_OUT && trans.position > 0)
             {
                 // Slot/map cleanup only (DEAL_TRACK and UpdatePerformanceCounters
                 // are handled by the universal block above)
                 ulong closedGuid = GetGUIDFromPositionMap(trans.position);
                 if(closedGuid != 0)
                 {
                    LogExitMarker(closedGuid, EXIT_SL_HIT, dealProfit);
                    OM_ClearSlot(closedGuid);
                    PrintFormat("[SLOT_RELEASED] DEAL_ENTRY_OUT position=%I64u guid=%I64u deal=%I64u",
                                trans.position, closedGuid, trans.deal);
                    RemovePositionMapEntry(trans.position);
                 }
               else
               {
                  PrintFormat("[WARNING] DEAL_ENTRY_OUT position=%I64u has no GUID in map", trans.position);
                  g_positionSlot.Reset();
                  PrintFormat("[SLOT] Force reset via DEAL_ENTRY_OUT fallback position=%I64u (unmapped close)", trans.position);
               }
            }

          // ── DEAL_ENTRY_IN: Populate map using best available GUID source ──
         // Priority 1: s_pendingGuid from TRADE_TRANSACTION_REQUEST (live/demo)
         // Priority 2: Fresh GUID fallback (tester fallback)
         if(dealEntry == DEAL_ENTRY_IN)
         {
            ulong positionTicket = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
            string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);

            if(symbol == _Symbol && positionTicket > 0)
            {
               // VERBATIM REPAIR: Finding 1 - GUID Identity Bridge (direct request_id resolution)
               ulong assignedGUID = ResolveGUIDByRequest(result.request_id);
               if(assignedGUID == 0 && s_pendingGuid != 0)
               {
                  assignedGUID = s_pendingGuid;
                  s_pendingGuid = 0;
               }
               // Restore identity truth — map position to resolved GUID
               if(assignedGUID != 0)
               {
                  PrintFormat("[GUID_POSITION_MAP] pos=%I64u -> GUID=%I64u (src=bridge)", trans.position, assignedGUID);
               }

               // Secure fallback: allocate a fresh, unique GUID via sole authority
               if(assignedGUID == 0)
               {
                  assignedGUID = SLockedSignal::GenerateSignalGUID();
                  PrintFormat("[SECURE_GUID_FALLBACK] Fresh GUID=%I64u created for position=%I64u",
                              assignedGUID, positionTicket);
               }

if(assignedGUID != 0)
                  {
                     // REGRESSION_GUARD_V58_P0_1: Fetch c2 values from pre-allocated map entry
                     double current_c2_low = GetC2LowForGUID(assignedGUID);
                     double current_c2_high = GetC2HighForGUID(assignedGUID);
                     // Pass dealTicket for entry price extraction from the deal
                     UpdatePositionGUIDMap(positionTicket, assignedGUID, current_c2_low, current_c2_high, trans.deal);

                      // [ENTRY_TRUTH] Reconcile fill price back to the originating signal
                      {
                         double dealFillPrice = 0.0;
                         if(HistorySelect(0, TimeCurrent()))
                            dealFillPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
                         bool reconciled = false;
                         for(int txS = 0; txS < MAX_SLOTS; txS++)
                         {
                            // Check C2 pool
                             if(g_activeC2[txS].m_guid == assignedGUID)
                             {
                                g_activeC2[txS].actualFillPrice = dealFillPrice;
                                g_activeC2[txS].fillStatus = 3;
                                g_activeC2[txS].fillTime = TimeCurrent();
                                g_activeC2[txS].positionTicket = positionTicket;
                               if(g_activeC2[txS].entry_price != dealFillPrice)
                               {
                                  LogPrint("[ENTRY_TRUTH_RECONCILED] GUID=" + IntegerToString(assignedGUID) +
                                           " | oldEntry=" + DoubleToString(g_activeC2[txS].entry_price, _Digits) +
                                           " | fillPrice=" + DoubleToString(dealFillPrice, _Digits) +
                                           " | candidatePrice=" + DoubleToString(g_activeC2[txS].candidateEntryPrice, _Digits) +
                                           " | requestedPrice=" + DoubleToString(g_activeC2[txS].requestedEntryPrice, _Digits), LOG_LEVEL_INFO);
                                  g_activeC2[txS].entry_price = dealFillPrice;
                               }
                               reconciled = true;
                               break;
                            }
                            // Check C3 pool
                             if(g_activeC3[txS].m_guid == assignedGUID)
                             {
                                g_activeC3[txS].actualFillPrice = dealFillPrice;
                                g_activeC3[txS].fillStatus = 3;
                                g_activeC3[txS].fillTime = TimeCurrent();
                                g_activeC3[txS].positionTicket = positionTicket;
                               if(g_activeC3[txS].entry_price != dealFillPrice)
                               {
                                  LogPrint("[ENTRY_TRUTH_RECONCILED] GUID=" + IntegerToString(assignedGUID) +
                                           " | oldEntry=" + DoubleToString(g_activeC3[txS].entry_price, _Digits) +
                                           " | fillPrice=" + DoubleToString(dealFillPrice, _Digits) +
                                           " | candidatePrice=" + DoubleToString(g_activeC3[txS].candidateEntryPrice, _Digits) +
                                           " | requestedPrice=" + DoubleToString(g_activeC3[txS].requestedEntryPrice, _Digits), LOG_LEVEL_INFO);
                                  g_activeC3[txS].entry_price = dealFillPrice;
                               }
                               reconciled = true;
                               break;
                            }
                         }
                          if(!reconciled && dealFillPrice > 0.0)
                          {
                             LogPrint("[ENTRY_TRUTH_INVALID] GUID=" + IntegerToString(assignedGUID) +
                                      " | no active signal slot found | dealPrice=" + DoubleToString(dealFillPrice, _Digits), LOG_LEVEL_WARN);
                          }
                          else if(reconciled)
                          {
                             LogPrint("[FILL_CONFIRMED] GUID=" + IntegerToString(assignedGUID) +
                                      " positionTicket=" + IntegerToString(positionTicket) +
                                      " fillPrice=" + DoubleToString(dealFillPrice, _Digits), LOG_LEVEL_INFO);
                             ClearSignalByGUID(s_pendingBranch, assignedGUID, "FILL_CONFIRMED");
                          }
                       }

                       LogPrint("[TRADE_TX_SYNCED] pos=" + IntegerToString(positionTicket) +
                               " | GUID=" + IntegerToString(assignedGUID) +
                               " | deal=" + IntegerToString(trans.deal), LOG_LEVEL_INFO);

                      // REGRESSION_GUARD_V58_P0_1: Verify mapping by GUID (NOT by position index)
                     PositionGUIDMap verifiedMap;
                     if(GetPositionGUIDMapByGUID(assignedGUID, verifiedMap))
                    {
                       PrintFormat("[POS_MAP_VERIFIED] pos=%I64u guid=%I64u entry=%.5f "
                                   "c1_h=%.5f c1_l=%.5f c2_h=%.5f c2_l=%.5f",
                                   positionTicket, assignedGUID, verifiedMap.entryPrice,
                                   verifiedMap.c1_high, verifiedMap.c1_low,
                                   verifiedMap.c2_high, verifiedMap.c2_low);

                       // CRITICAL: Verify GUID matches — detect off-by-two corruption
                       if(verifiedMap.signalGUID != assignedGUID)
                       {
                          LogError(StringFormat("[REGRESSION_FAIL] GUID mismatch! "
                              "expected=%I64u got=%I64u pos=%I64u",
                              assignedGUID, verifiedMap.signalGUID, positionTicket));
                       }
                    }
                    else
                    {
                       LogPrint("[POS_MAP_MISSING] GUID=" + IntegerToString(assignedGUID) +
                                " has no C1_MAP — emergency creating", LOG_LEVEL_WARN);
                       CreateEmergencyC1Map(assignedGUID, (long)positionTicket, trans.deal);
                    }

                      s_pendingGuid = 0;
                      s_pendingBranch = BRANCH_INTRADAY; // Wipe both trackers to prevent stale state
                  }
               else
               {
                  LogPrint("[C1_MAP_NO_GUID] Ticket=" + IntegerToString(positionTicket) +
                           " | No GUID available (queue empty, no pre-alloc)", LOG_LEVEL_WARN);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Warmup gate — ensure sufficient bars on all timeframes           |
//+------------------------------------------------------------------+
// DYNAMIC: Uses SBranchTimeframes to validate only branch-relevant TFs
bool IsWarmupComplete(const SBranchTimeframes &tf)
{
   // PHASE 3: Detect tester mode for relaxed warmup
   bool isTester = (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION));
   
   // Relaxed thresholds for tester (allow faster start in backtest)
   int d1MinBars = isTester ? 10 : 30;
   int structMinBars = isTester ? 10 : ((tf.structureTF == PERIOD_H4) ? 60 : 25);
   int entryMinBars = isTester ? 20 : ((tf.entryTF == PERIOD_M15) ? 120 : 120);
   
   // Global D1 check (required by all branches)
   int barsD1  = iBars(_Symbol, PERIOD_D1);
   bool d1Ready = (barsD1 >= d1MinBars);

   // Dynamic structure TF check — uses tf.structureTF (H1 for Intraday, H4 for Swing)
   int barsStruct = iBars(_Symbol, tf.structureTF);
   bool structReady = (barsStruct >= structMinBars);

   // Dynamic entry TF check — uses tf.entryTF (M5 for Intraday, M15 for Swing)
   int barsEntry = iBars(_Symbol, tf.entryTF);
   bool entryReady = (barsEntry >= entryMinBars);

   bool allReady = d1Ready && structReady && entryReady;

   // Convert TFR to string (PeriodToString doesn't exist in MQL5)
   string structTFName = (tf.structureTF == PERIOD_H4) ? "H4" : (tf.structureTF == PERIOD_H1) ? "H1" : "M15";
   string entryTFName = (tf.entryTF == PERIOD_M15) ? "M15" : "M5";

   if(!allReady)
   {
      static datetime lastBarTime = 0;
      datetime currentBar = iTime(_Symbol, tf.entryTF, 0);
      if(currentBar != lastBarTime)
      {
         lastBarTime = currentBar;
         if(g_logLevel <= LOG_LEVEL_INFO)
            LogPrint(StringFormat("[WARMUP] D1:%d/30 %s:%d/%d %s:%d/%d — waiting",
                        barsD1, structTFName, barsStruct, structMinBars,
                        entryTFName, barsEntry, entryMinBars), LOG_LEVEL_INFO);
      }
   }
   else
   {
      static bool warmupLogged = false;
      if(!warmupLogged)
      {
         warmupLogged = true;
         if(g_logLevel <= LOG_LEVEL_INFO)
            LogPrint("[WARMUP] Complete — pipeline active", LOG_LEVEL_INFO);
      }
   }

// Global D1 staleness check (all branches require this) — NON-BLOCKING
    // PHASE 3: Relaxed threshold for tester
    datetime mostRecentD1 = iTime(_Symbol, PERIOD_D1, 1);
    datetime serverNow    = TimeCurrent();
    int d1AgeSeconds = (int)(serverNow - mostRecentD1);
    int d1AgeDays    = d1AgeSeconds / 86400;
    
    // Relaxed for tester (allow 7 days instead of 3)
    int d1StaleThreshold = isTester ? 7 : 3;

    if(d1AgeDays > d1StaleThreshold)
    {
       static datetime lastStaleLog = 0;
       if(serverNow - lastStaleLog > 3600)
       {
          lastStaleLog = serverNow;
          LogPrint("[DATA_STALE] D1 last bar is " + IntegerToString(d1AgeDays) + " days old. Operating in degraded mode.", LOG_LEVEL_WARN);
       }
       // NON-BLOCKING: continue with degraded mode instead of failing warmup
    }

    // DYNAMIC: Structure TF staleness check — respects tf.structureTF — NON-BLOCKING
    // PHASE 3: Relaxed threshold for tester
    datetime mostRecentStruct = iTime(_Symbol, tf.structureTF, 1);
    int structAgeHours = (int)(serverNow - mostRecentStruct) / 3600;

    // Weekend-aware threshold: Monday allows 60 hours, weekdays allow 12 hours
    // Relaxed for tester (allow 120h instead of 60h on Monday, 24h instead of 12h on weekdays)
    MqlDateTime dtNow;
    TimeToStruct(serverNow, dtNow);
    int maxAllowedAge = isTester ? 
        ((dtNow.day_of_week == 1) ? 120 : 24) : 
        ((dtNow.day_of_week == 1) ? 60 : 12);

    // Rate-limited logging: once per 5 minutes max to prevent log spam
    static datetime lastStructStaleLog = 0;

    if(structAgeHours > maxAllowedAge)
    {
       if(serverNow - lastStructStaleLog > 300)  // Log at most once per 5 minutes
       {
          lastStructStaleLog = serverNow;
          string staleMsg = "[DATA_STALE] " + structTFName + " last bar is " + IntegerToString(structAgeHours) + " hours old. Max allowed: " + IntegerToString(maxAllowedAge) + "h (day " + IntegerToString(dtNow.day_of_week) + "). Operating in degraded mode.";
          LogPrint(staleMsg, LOG_LEVEL_WARN);
       }
       // NON-BLOCKING: continue with degraded mode instead of failing warmup
    }

    return allReady;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
/**
 * ValidateRiskGate — Hard pre-execution Risk Compliance validation.
 *
 * Independent 2R verification that fires immediately before OrderSend.
 * Cannot be bypassed by stale passedRG flags.
 *
 * Returns: true if 2R target is structurally viable, false to block.
 */
bool ValidateRiskGate(const SLockedSignal &signal, double stopLoss, double tpPrice)
{
    if(signal.m_guid == 0 || signal.entry_price <= 0.0 || stopLoss <= 0.0)
    {
      LogPrint(StringFormat("[RG_GATE_FAIL] INVALID_PARAMS | GUID=%I64u | entry=%.5f | sl=%.5f",
          signal.m_guid, signal.entry_price, stopLoss), LOG_LEVEL_ERROR);
        return false;
    }

    double risk = MathAbs(signal.entry_price - stopLoss);
    if(risk <= 0.0)
    {
      LogPrint(StringFormat("[RG_GATE_FAIL] ZERO_RISK | GUID=%I64u", signal.m_guid), LOG_LEVEL_ERROR);
        return false;
    }

    double reward = (tpPrice > 0.0) ? MathAbs(tpPrice - signal.entry_price) : 0.0;
    double rr_ratio = (reward > 0.0) ? (reward / risk) : 0.0;

    double minRR = (signal.closureType == CLOSURE_C3)
        ? g_trueTTradesConfig.confirmationMinRR
        : g_trueTTradesConfig.anticipationMinRR;
    if(minRR <= 0.0) minRR = 2.0;

    LogPrint(StringFormat("[RG_GATE_CALC] GUID=%I64u entry=%.5f sl=%.5f tp=%.5f slDist=%.5f tpDist=%.5f RR=%.2f minRR=%.2f closure=%s",
        signal.m_guid, signal.entry_price, stopLoss, tpPrice, risk, reward, rr_ratio, minRR,
        EnumToString(signal.closureType)), LOG_LEVEL_INFO);

    if(rr_ratio < minRR - 0.00001)
    {
      LogPrint(StringFormat("[RG_GATE_FAIL] INSUFFICIENT_RR | GUID=%I64u | RR=%.2f < minRR=%.2f | closure=%s",
          signal.m_guid, rr_ratio, minRR, EnumToString(signal.closureType)), LOG_LEVEL_WARN);
      LogPrint(StringFormat("[RISK_2R_VIOLATION] GUID=%I64u | RR=%.2f | minRR=%.2f | closure=%s | entry=%.5f | sl=%.5f",
          signal.m_guid, rr_ratio, minRR, EnumToString(signal.closureType), signal.entry_price, stopLoss), LOG_LEVEL_WARN);
        return false;
    }

   LogPrint(StringFormat("[RG_GATE_PASS] GUID=%I64u | RR=%.2f >= %.2f | closure=%s",
          signal.m_guid, rr_ratio, minRR, EnumToString(signal.closureType)), LOG_LEVEL_INFO);
    return true;
}
// REGRESSION_GUARD_V57_3

/**
 * OnTick() — Pipeline execution with optional tick iterator
 *
 * PHASE 5: When InpUseTickIterator is enabled, processes all missed ticks
 * to eliminate micro-move slippage.
 *
 * Pipeline: SSE → Liquidity → Displacement → Bias → Mode → Execution
*/
void OnTick()
{
    // VERBATIM REPAIR: Permanent Skip Recovery (§II)
    EvaluateSkipRecovery(_Symbol);

    // === FIRST: TTL-based signal cleanup before any evaluation ===
    PerformTTLSignalCleanup();

    // REGRESSION_GUARD_C1MAP_V57_1: Periodic C1_MAP verification for open positions
    static datetime s_lastMapCheck = 0;
    datetime nowMapCheck = TimeCurrent();
    if(nowMapCheck - s_lastMapCheck > 60)
    {
        VerifyOpenPositionMaps();
        s_lastMapCheck = nowMapCheck;
    }

    datetime now = TimeCurrent();
    
    //=== PROCESS RETRY QUEUE (market closed / trade disabled recovery) ===
    static datetime s_lastRetryCheck = 0;
    if(now - s_lastRetryCheck >= 30)  // Check every 30 seconds to avoid excessive calls
    {
        s_lastRetryCheck = now;
        ProcessRetryQueue();
    }
    
    // ===== PENDING ORDER STALE CHECK (TF-AWARE per §XII) =====
    // §XII: timeout = PeriodSeconds(entryTF) * 4
    // Check pending orders every 30 seconds (check interval, not timeout)
    static datetime s_lastPendingConfirmCheck = 0;
    if(now - s_lastPendingConfirmCheck >= 30)
    {
        s_lastPendingConfirmCheck = now;
        for(int pi = 0; pi < ArraySize(g_pendingLinks); pi++)
        {
            if(g_pendingLinks[pi].guid == 0)
                continue;
            ENUM_TIMEFRAMES entryTF = GetEntryTF(g_pendingLinks[pi].branch);
            int timeoutSeconds = GetPendingOrderTimeoutSeconds(entryTF);
            int ageSeconds = (int)(TimeCurrent() - g_pendingLinks[pi].created);
            if(ageSeconds > timeoutSeconds)
            {
                PrintFormat("[PENDING_STALE] GUID=%I64u | age_sec=%d | timeout_sec=%d (entryTF=%s) — removing",
                            g_pendingLinks[pi].guid, ageSeconds, timeoutSeconds,
                            entryTF == PERIOD_M5 ? "M5" : "M15");
                if(g_pendingLinks[pi].orderTicket > 0)
                {
                    MqlTradeRequest req = {};
                    MqlTradeResult res = {};
                    req.action = TRADE_ACTION_REMOVE;
                    req.order = g_pendingLinks[pi].orderTicket;
                    if(!OrderSend(req, res))
                    {
                        LogPrint("[PENDING_REMOVE_FAIL] ticket=" + IntegerToString(g_pendingLinks[pi].orderTicket) +
                                 " | error=" + IntegerToString(GetLastError()), LOG_LEVEL_WARN);
                    }
                }
                g_pendingLinks[pi].Reset();
            }
        }
    }
    // ===== END PENDING ORDER STALE CHECK =====

    //=== P24-R: Emergency close retry on market reopen ===
    if(g_emergencyClosePending)
    {
        // Check if market is now open
        ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
        if(tradeMode == SYMBOL_TRADE_MODE_FULL)
        {
            // Attempt emergency close
            bool closeSuccess = CloseAllPositions("EMERGENCY_RETRY");
            if(closeSuccess)
            {
                g_emergencyClosePending = false;
                g_emergencyCloseTriggered = false; // reset emergency state
                LogPrint("[ACCOUNT_GUARD] Emergency close succeeded on market reopen", LOG_LEVEL_INFO);
            }
            else
            {
                // If close fails again (e.g., market closed again or other error), keep pending and let next tick retry
                LogPrint("[ACCOUNT_GUARD] Emergency close retry failed, will retry on next tick", LOG_LEVEL_ERROR);
            }
        }
        // else: market still closed, wait for next tick
    }
    
    //=== FIRST-TICK PEAK EQUITY DEFENSIVE GUARD ===
    // If OnInit failed or test started mid-day, ensure g_peakEquity is valid
    static bool s_peakEquityFirstTickGuard = false;
    if(!s_peakEquityFirstTickGuard)
    {
        double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double refEquity = (currentEquity > 0) ? currentEquity : currentBalance;
        if(g_peakEquity <= 0.0 || g_peakEquity < refEquity)
        {
            g_peakEquity = refEquity;
            LogPrint("[PEAK_EQUITY_INIT] FirstTick | g_peakEquity=" + DoubleToString(g_peakEquity, 2) +
                     " | equity=" + DoubleToString(currentEquity, 2), LOG_LEVEL_INFO);
        }
        s_peakEquityFirstTickGuard = true;
    }



    // === P9 FIX: Check POI timeout for signals waiting too long ===
    CheckPoiTimeout(BRANCH_INTRADAY);
    CheckPoiTimeout(BRANCH_SWING);

    // === Check setup-level lifespan and invalidation ===
    CheckSetupLifespan(BRANCH_INTRADAY);
    CheckSetupLifespan(BRANCH_SWING);

    // === PROMPT_E4: Ongoing periodic tradeability re-verification ===
    // Runs at most once per InpTradeabilityRecheckBars on entry TF
    g_symbolUntradeable = false; // Reset the blockade
    PerformTradeabilityCheck(g_activeBranch); // Refresh status with REAL-TIME structure

// === EQUITY GUARD GATE — Run on every tick (P0 Phase 1 fix: was OnTimer-only) ===
    // REGRESSION_GUARD_P0_PHASE1_ON_TICK_RISK
    EquityGuardCheck();  // risk FSM state transitions + catastrophic floor

    // === DAILY RESET: High-water mark + day-start balance ===
    // Runs even when PERMANENT so state can be logged
    static datetime s_lastDayStart = 0;
    datetime currentDayStart = iTime(_Symbol, PERIOD_D1, 0);
    if(currentDayStart != s_lastDayStart)
    {
        s_lastDayStart = currentDayStart;
        g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        g_dayStartTime = TimeCurrent();
        if(g_equityGuardState >= EQUITY_GUARD_PERMANENT)
        {
            LogPrint("[STATE_TRANSITION_FAIL] NEW_DAY while PERMANENT — maintaining halt until manual reset", LOG_LEVEL_WARN);
        }
        else
        {
            ENUM_EQUITY_GUARD_STATE prevGuard = g_equityGuardState;
            g_equityGuardState = EQUITY_GUARD_NORMAL;
            if(prevGuard != EQUITY_GUARD_NORMAL)
            {
                LogPrint("[STATE_RECOVERED] EQUITY_GUARD NORMAL (daily reset) | prev=" +
                         EnumToString(prevGuard), LOG_LEVEL_INFO);
            }
        }
        SyncBlockNewEntries();
        LogPrint("[ACCOUNT_GUARD] NEW_DAY | dayStartBalance=" + DoubleToString(g_dayStartBalance, 2) +
                 " | state=" + EnumToString(g_equityGuardState) +
                 " | blocked=" + (g_blockNewEntries ? "true" : "false"), LOG_LEVEL_INFO);
    }

    if(g_equityGuardState == EQUITY_GUARD_PERMANENT)
        return;

    // On same day, gate new entries if daily loss was hit
    if(g_blockNewEntries)
    {
        static datetime s_lastEntryBlockedBar = 0;
        datetime currentEntryD1Bar = iTime(_Symbol, PERIOD_D1, 0);
        if(currentEntryD1Bar != s_lastEntryBlockedBar)
        {
            LogPrint("[EQ_ENTRY_BLOCK] g_blockNewEntries=true | daily loss limit hit", LOG_LEVEL_INFO);
            s_lastEntryBlockedBar = currentEntryD1Bar;
        }
        return;
    }

    // PHASE 4: Conditional Heartbeat - reduce log spam, only log on significant events
    static datetime s_lastHeartbeat = 0;
    static int s_tickCount = 0;
    static datetime s_lastSignificantEvent = 0;
    s_tickCount++;

    // P8 Fix: Throttled ONTICK logging - only on branch change or every 1000 ticks
    static ENUM_EXECUTION_BRANCH s_lastLoggedBranch = BRANCH_INTRADAY;
    static int s_ontickCounter = 0;

    s_ontickCounter++;

    bool shouldLogOntick = false;
    ENUM_EXECUTION_BRANCH currentBranch = g_activeBranch;

    // Log on: branch change, or every 1000 ticks (heartbeat)
    if(currentBranch != s_lastLoggedBranch)
    {
        shouldLogOntick = true;
        s_lastLoggedBranch = currentBranch;
    }
    else if(s_ontickCounter % 1000 == 0)
    {
        shouldLogOntick = true;
    }

    if(shouldLogOntick)
    {
        int totalSignals = CountActiveSignals(BRANCH_INTRADAY) + CountActiveSignals(BRANCH_SWING);
        double floatingPnL = AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE);
        LogPrint("[FLOATING_PNL] floatingPnL=" + DoubleToString(floatingPnL, 2) +
                 " | equity=" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) +
                 " | balance=" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2), LOG_LEVEL_DEBUG);
        LogPrint("[ONTICK_STATE] branch=" + IntegerToString(currentBranch) + 
                 " | tickCount=" + IntegerToString(s_ontickCounter) +
                 " | signalsActive=" + IntegerToString(totalSignals) +
                 " | guardState=" + EnumToString(g_equityGuardState) +
                 " | blockEntries=" + (g_blockNewEntries ? "true" : "false"), LOG_LEVEL_DEBUG);
    }
    
   // PHASE 4: Event-driven heartbeat - only log on actual events, not ticks
   // Events: state change, new signal, error condition
   // Base heartbeat at 5 minutes for observability if no events
   bool logHeartbeat = false;
   string eventType = "";
   
    // Check for state changes in signals (event-driven) — dual-registry pools
    static ENUM_SIGNAL_STAGE s_lastStageC2[MAX_SLOTS] = {};
    static ENUM_SIGNAL_STAGE s_lastStageC3[MAX_SLOTS] = {};
    for(int i = 0; i < MAX_SLOTS; i++)
    {
       if(g_activeC2[i].m_guid != 0 && g_activeC2[i].stage != STAGE_NONE)
       {
          ENUM_SIGNAL_STAGE stage = g_activeC2[i].stage;
          if(s_lastStageC2[i] != STAGE_NONE && s_lastStageC2[i] != stage)
          {
             eventType = "STAGE_CHG";
             logHeartbeat = true;
          }
          s_lastStageC2[i] = stage;
       }
       if(g_activeC3[i].m_guid != 0 && g_activeC3[i].stage != STAGE_NONE)
       {
          ENUM_SIGNAL_STAGE stage = g_activeC3[i].stage;
          if(s_lastStageC3[i] != STAGE_NONE && s_lastStageC3[i] != stage)
          {
             eventType = "STAGE_CHG";
             logHeartbeat = true;
          }
          s_lastStageC3[i] = stage;
       }
    }
   
   // Log if event occurred in last 60 seconds OR no significant event in 5 minutes
   if(now - s_lastSignificantEvent >= 60 || (now - s_lastHeartbeat >= 300))
   {
      if(logHeartbeat)
      {
         s_lastSignificantEvent = now;
         LogPrint("[EVENT] " + eventType + " | TickCount=" + IntegerToString(s_tickCount), LOG_LEVEL_DEBUG);
      }
      
      // Base heartbeat: 5 min if no events (observability)
      if(now - s_lastHeartbeat >= 300)
      {
         LogPrint("[HEARTBEAT] Engine Pulse | Time=" + TimeToString(now) +
                  " | TickCount=" + IntegerToString(s_tickCount) +
                  " | Symbol=" + _Symbol, LOG_LEVEL_DEBUG);  // Reduced to DEBUG
         s_lastHeartbeat = now;
         s_tickCount = 0;
      }
}
    g_tickCounter++;

    // --- P1 FIX: Bar-count warmup guard (before existing warmup) ---
    if(!g_warmupComplete)
    {
        g_warmupBarsCounted++;
        if(g_warmupBarsCounted < InpWarmupBars)
        {
            if(g_warmupBarsCounted == 1)
                LogPrint("[WARMUP] Skipping first " + IntegerToString(InpWarmupBars) +
                         " bars | Current=" + IntegerToString(g_warmupBarsCounted), LOG_LEVEL_INFO);
            return;
        }
        g_warmupComplete = true;
        LogPrint("[WARMUP] Bar-count complete. Pipeline active.", LOG_LEVEL_INFO);
    }

    // FIX C: Warmup check - skip heavy logic until warmup complete, but allow heartbeat
    static bool s_warmupLogged = false;
    if(!IsWarmupComplete(g_branchTF))
   {
       if(!s_warmupLogged && now - s_lastHeartbeat >= 60)
       {
           LogPrint("[WARMUP] Waiting for bars | D1=" + IntegerToString(Bars(_Symbol, PERIOD_D1)) + 
                    " | H1=" + IntegerToString(Bars(_Symbol, PERIOD_H1)) + 
                    " | M5=" + IntegerToString(Bars(_Symbol, PERIOD_M5)), LOG_LEVEL_INFO);
           s_warmupLogged = true;
       }
       // Allow heartbeat to continue, but skip pipeline execution
       return;
   }
   else
   {
if(!s_warmupLogged)
        {
            LogPrint("[WARMUP_COMPLETE] All timeframes ready | D1=" + IntegerToString(Bars(_Symbol, PERIOD_D1)) + 
                     " | H1=" + IntegerToString(Bars(_Symbol, PERIOD_H1)) + 
                     " | M5=" + IntegerToString(Bars(_Symbol, PERIOD_M5)), LOG_LEVEL_INFO);
            s_warmupLogged = true;
        }
    }

    //=== POSITION CLOSURE HARDENING — Timeout + Diagnostics ===
    CheckPositionTimeouts(_Symbol, InpMagicNumber);
    LogPositionClosureDiagnostics(_Symbol, InpMagicNumber);
    
    // Emergency timeout check (hard close after N days)
    CheckEmergencyTimeout();



// FLOW_GATE: Removed — ATR subsystem no longer active

// ═══════════════════════════════════════════════════════════════════════
// PIPELINE: 5-GATE EXECUTION (HTF→MTF→LTF→RISK→EXECUTE)
     // ═══════════════════════════════════════════════════════

// ATR system gate removed — pipeline proceeds without ATR gating

// VERBATIM REPAIR: Replace 'if(g_symbolUntradeable) return;' with soft gate
    bool g_pipelineSkipDetection = g_symbolUntradeable;

// Only wrap the detection/branch evaluation block
    if(!g_pipelineSkipDetection)
    {
        datetime currentBar = iTime(_Symbol, g_branchTF.structureTF, 0);
        if(currentBar != g_lastBranchBar || !g_cachedCtxInitialized)
        {
           BE_EvaluateAllBranches(_Symbol, InpBranch);
           g_lastBranchBar = currentBar;
           g_branchesEvaluated = true;
           UpdateCachedContext(InpBranch);
        }
    }

// RESTORE PIPELINE: Allow C2/C3 Routers and Execution Scan to run regardless of affordability
// This ensures STAGE_READY signals can still execute.

// FIX 2: Soft Gate for uninitialized context (AFTER first evaluation)
// CONTINUITY: Log degraded state but do NOT return — C2/C3 Routers and Execution Scan
// must run every tick regardless of detection readiness (§III Pipeline Continuity).
    if(!g_cachedCtxInitialized)
    {
       LogPrint("[CTX] Pipeline degraded — g_cachedCtx not initialized yet", LOG_LEVEL_DEBUG);
    }

// STEP 1: HTF Check - SSE Strategy validation
// CONTINUITY: Allow pipeline to proceed — C2/C3 Routers still process existing signals
    if(!g_branchesEvaluated)
    {
        LogPrint("[BRANCH] Pipeline degraded — Not yet evaluated", LOG_LEVEL_DEBUG);
    }

// FIX 6: First-tick execution guard (AFTER context initialized)
datetime currentTick = TimeCurrent();
bool isSameTick = (currentTick == g_lastTickTime && g_cachedCtxInitialized);

// Always update timestamp
g_lastTickTime = currentTick;

// DO NOT RETURN — allow pipeline to proceed

// STEP 2: Warmup check - DEGRADED MODE (FIX 3: soft gate)
    bool warmupReady = IsWarmupComplete(g_branchTF);
    if(!warmupReady)
    {
       LogPrint("[WARMUP] Degraded mode — continuing without full readiness", LOG_LEVEL_INFO);
       // DO NOT RETURN — allow pipeline to run in degraded mode
    }

      // ═══════════════════════════════════════════════════════
      // [FSM ROUTER] STATE ROUTING AT THE FRONT DOOR
      // ═══════════════════════════════════════════════════════
// FIX 1: SAFE CONTEXT ASSIGNMENT (AFTER BRANCH EVAL)
    BranchContext ctx = g_cachedCtx;

// ===== EXECUTION SCAN FIRST — STAGE_READY signals execute before expiry =====
        {
            int c2MaxPersist = GetMaxSignalsForClosureType(CLOSURE_C2);
            ProcessPersistentScanPool(g_activeC2, c2MaxPersist, ctx);
        }
        {
            int c3MaxPersist = GetMaxSignalsForClosureType(CLOSURE_C3);
            ProcessPersistentScanPool(g_activeC3, c3MaxPersist, ctx);
        }

// ===== THEN EXPIRE SIGNALS =====
    static datetime s_lastExpiryCheck = 0;
    if(now - s_lastExpiryCheck >= 60)
    {
        CheckAndExpireSignals(BRANCH_INTRADAY);
        CheckAndExpireSignals(BRANCH_SWING);
        s_lastExpiryCheck = now;
    }
    PerformTTLSignalCleanup();

// ===== THEN PIPELINE PROCESSING =====
// Route FSM state transitions BEFORE any structural/bias/displacement logic
     datetime ctxBarTime = iTime(_Symbol, ctx.structureTF, 0);

      // Idempotence guard: update bar-time stamp AFTER FSM router checks
      static datetime s_lastCheckedBarTime = 0;

// Invoke dual-registry routers — isolated pools processed independently
       TickRouter(ctx);

      // Idempotence guard: update bar-time stamp AFTER FSM router checks
      if(ctxBarTime != s_lastCheckedBarTime)
         s_lastCheckedBarTime = ctxBarTime;

// Tick transition throttle: max 10 stage changes per tick
        static int s_transitionsThisTick = 0;
        static datetime s_lastTickTime = 0;
        if(TimeCurrent() != s_lastTickTime)
        {
            s_lastTickTime = TimeCurrent();
            s_transitionsThisTick = 0;
        }

// ── DUAL-REGISTRY FSM PIPELINE (§III.B) ──
// Process C2 and C3 pools independently to prevent cross-contamination
        {
            int c2Base = GetSignalStoreIndex(ctx.branch, CLOSURE_C2);
            int c2Max = GetMaxSignalsForClosureType(CLOSURE_C2);
            ProcessPipelinePool(g_activeC2, c2Base, c2Max, ctx, currentTick, s_transitionsThisTick, true);
        }
        {
            int c3Base = GetSignalStoreIndex(ctx.branch, CLOSURE_C3);
            int c3Max = GetMaxSignalsForClosureType(CLOSURE_C3);
            ProcessPipelinePool(g_activeC3, c3Base, c3Max, ctx, currentTick, s_transitionsThisTick, false);
        }



    MonitorTPLevels();

    // REGRESSION_GUARD_TRAIL: Both branches — Intraday (A) and Swing (B)
    if(PositionsTotal() > 0)
    {
        EE_ManageStructuralTrail(BRANCH_INTRADAY);  // Branch A — M5 entry TF
        EE_ManageStructuralTrail(BRANCH_SWING);     // Branch B — M15 entry TF
    }

    // Swing-based pyramiding add check (once per entry TF bar)
    // AE_CheckSwingAdd is evaluation-only — execution delegated to OrderManager/RiskGate
    if(PositionsTotal() > 0 && g_InpEnablePyramiding)
    {
        ENUM_TIMEFRAMES activeEntryTf = (g_activeBranch == BRANCH_INTRADAY) ? PERIOD_M5 : PERIOD_M15;
        ENUM_DIRECTION addDirection = DIRECTION_NONE;
        double addLot = 0.0, addPrice = 0.0, addSL = 0.0, expansionR = 0.0;
        if(AE_CheckSwingAdd(g_activeBranch, activeEntryTf, addDirection, addLot, addPrice, addSL, expansionR))
        {
            ulong outTicket = 0;
            string failReason = "";
            // REGRESSION_GUARD_V52.5_ADD_EXECUTION_DELEGATED: Execution through RiskGate canonical path
            if(ExecuteMarketOrder(0, _Symbol, (addDirection == DIRECTION_BUY), addLot, addSL, 0.0, InpMagicNumber, outTicket, failReason))
            {
                CM_AddSwingLayer(g_activeBranch, (int)outTicket, addPrice, addLot, 0.0, expansionR);
                LogPrint("[PYRAMID_ADD] Order sent | Ticket=" + IntegerToString(outTicket) +
                         " | Lot=" + DoubleToString(addLot, 2) +
                         " | Price=" + DoubleToString(addPrice, _Digits) +
                         " | SL=" + DoubleToString(addSL, _Digits), LOG_LEVEL_INFO);
            }
            else
            {
                LogPrint("[PYRAMID_ADD] Order failed | Branch=" + EnumToString(g_activeBranch) +
                         " | reason=" + failReason, LOG_LEVEL_WARN);
            }
        }
    }

    // Structural exits — centralized via ExitEngine
    // CRT target: every tick (price level). CISD/Dow BOS: per bar (structural).
    // REGRESSION_GUARD_V52.5_STRUCTURAL_EXIT_DETERMINISM
    if(PositionsTotal() > 0)
    {
        LogPrint("[EXIT_GATE] Structural exit evaluation | positions=" + IntegerToString(PositionsTotal()), LOG_LEVEL_DEBUG);

        static datetime s_lastCisdBarA = 0;
        static datetime s_lastCisdBarB = 0;
        static datetime s_lastDowBarA  = 0;
        static datetime s_lastDowBarB  = 0;

        datetime barM5  = iTime(_Symbol, PERIOD_M5,  0);
        datetime barM15 = iTime(_Symbol, PERIOD_M15, 0);
        datetime barH1  = iTime(_Symbol, PERIOD_H1,  0);
        datetime barH4  = iTime(_Symbol, PERIOD_H4,  0);

        bool newBarM5  = (barM5  != s_lastCisdBarA);
        bool newBarM15 = (barM15 != s_lastCisdBarB);
        bool newBarH1  = (barH1  != s_lastDowBarA);
        bool newBarH4  = (barH4  != s_lastDowBarB);

        if(newBarM5)  s_lastCisdBarA = barM5;
        if(newBarM15) s_lastCisdBarB = barM15;
        if(newBarH1)  s_lastDowBarA  = barH1;
        if(newBarH4)  s_lastDowBarB  = barH4;

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket))
                continue;

            int mapIdx = FindPositionMapEntryByTicket(ticket);
            if(mapIdx < 0)
            {
                LogPrint("[EXIT_NOMAP] Ticket=" + IntegerToString(ticket) +
                         " | no PositionGUIDMap entry found", LOG_LEVEL_DEBUG);
                continue;
            }

            PositionGUIDMap mapEntry;
            if(!GetPositionMapEntry(mapIdx, mapEntry))
                continue;

            LogPrint("[EXIT_DATA_CHECK] Ticket=" + IntegerToString(ticket) +
                     " | C1_H=" + DoubleToString(mapEntry.c1_high, _Digits) +
                     " | C1_L=" + DoubleToString(mapEntry.c1_low, _Digits), LOG_LEVEL_INFO);

            if(mapEntry.signalGUID == 0 || mapEntry.direction == DIRECTION_NONE)
                continue;

            bool newCISDBar = (mapEntry.branch == BRANCH_INTRADAY) ? newBarM5 : newBarM15;
            bool newBOSBar  = (mapEntry.branch == BRANCH_INTRADAY) ? newBarH1 : newBarH4;

            // ExitEngine evaluates CRT (every tick), Dow BOS (per HTF bar), CISD (per LTF bar)
            // with canonical data validation and runtime markers
            if(EE_EvaluateAndExit(ticket, mapEntry, InpExit_CRT_Target, InpExit_CISD_Reversal,
                                  InpExit_Dow_BOS, newCISDBar, newBOSBar))
            {
                continue;
            }
        }
    }

    LogPrint("[HEARTBEAT_END] OnTick complete", LOG_LEVEL_DEBUG);
}

//+------------------------------------------------------------------+
//| LogExitMarker — Log standardized exit marker with GUID and PnL   |
//+------------------------------------------------------------------+
void LogExitMarker(ulong guid, ENUM_EXIT_TYPE exitType, double pnl)
{
   switch(exitType)
   {
      case EXIT_CRT_TARGET:
         LogInfo(StringFormat("[EXIT_CRT_TARGET] GUID=%I64u PnL=%.2f", guid, pnl));
         break;
      case EXIT_CISD_REVERSAL:
         LogInfo(StringFormat("[EXIT_CISD_REVERSAL] GUID=%I64u PnL=%.2f", guid, pnl));
         break;
      case EXIT_DOW_BOS:
         LogInfo(StringFormat("[EXIT_DOW_BOS] GUID=%I64u PnL=%.2f", guid, pnl));
         break;
      case EXIT_TRAILING_STOP:
         LogInfo(StringFormat("[EXIT_TRAIL_STOP] GUID=%I64u PnL=%.2f", guid, pnl));
         break;
      case EXIT_SL_HIT:
         LogInfo(StringFormat("[EXIT_SL_HIT] GUID=%I64u PnL=%.2f", guid, pnl));
         break;
      case EXIT_EMERGENCY_CLOSE:
         LogInfo(StringFormat("[EXIT_EMERGENCY_CLOSE] GUID=%I64u PnL=%.2f", guid, pnl));
         break;
   }
}
//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+

