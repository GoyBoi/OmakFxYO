//+------------------------------------------------------------------+
//|                                              CoreTypes.mqh |
//|                                    OmakFxYO — Core Type Definitions |
//+------------------------------------------------------------------+
#ifndef OMAK_CORETYPES_MQH
#define OMAK_CORETYPES_MQH

//--- EA Version Identity (increment on every binary release)
#define OMAKFX_VERSION_MAJOR 1
#define OMAKFX_VERSION_MINOR 0
#define OMAKFX_VERSION_PATCH 0
#define OMAKFX_VERSION_BUILD 31
#define OMAKFX_VERSION_STR "1.0.0.31"

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Core type definitions for OmakFxYO"

//+------------------------------------------------------------------+
//| CONSTANTS                                                        |
//+------------------------------------------------------------------+
#ifndef MAX_C2_SIGNALS_PER_BRANCH
#define MAX_C2_SIGNALS_PER_BRANCH 3
#endif

#ifndef MAX_C3_SIGNALS_PER_BRANCH
#define MAX_C3_SIGNALS_PER_BRANCH 3
#endif

#define MAX_TOTAL_SIGNALS_PER_BRANCH (MAX_C2_SIGNALS_PER_BRANCH + MAX_C3_SIGNALS_PER_BRANCH)

//+------------------------------------------------------------------+
//| ENUM_DIRECTION — Trade Direction                                 |
//+------------------------------------------------------------------+
enum ENUM_DIRECTION
{
   DIRECTION_NONE = 0,
   DIRECTION_BUY,
   DIRECTION_SELL
};

//+------------------------------------------------------------------+
//| ENUM_CISD_TYPE — CISD Pattern Type                               |
//+------------------------------------------------------------------+
enum ENUM_CISD_TYPE
{
   CISD_TYPE_NONE = 0,
   CISD_TYPE_C2,
   CISD_TYPE_C3
};

//+------------------------------------------------------------------+
//| ENUM_WICK_TYPE — Wick Classification                             |
//+------------------------------------------------------------------+
enum ENUM_WICK_TYPE
{
   WICK_NONE = 0,
   WICK_SMALL,
   WICK_LARGE
};

//+------------------------------------------------------------------+
//| ENUM_EXECUTION_BRANCH — Execution Branch                         |
//+------------------------------------------------------------------+
enum ENUM_EXECUTION_BRANCH
{
   BRANCH_INTRADAY = 0,
   BRANCH_SWING    = 1
};

//+------------------------------------------------------------------+
//| ENUM_ACTIVE_BRANCH — User-facing branch selector                 |
//+------------------------------------------------------------------+
enum ENUM_ACTIVE_BRANCH
{
   BRANCH_A = 0,  // Maps to BRANCH_INTRADAY (D1/H1/M5)
   BRANCH_B = 1   // Maps to BRANCH_SWING   (W1/H4/M15)
};

//+------------------------------------------------------------------+
//| ENUM_SIGNAL_DIRECTION — Signal Direction                         |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_DIRECTION
{
   SIGNAL_NONE = 0,
   SIGNAL_BULLISH,
   SIGNAL_BEARISH,
   SIGNAL_NEUTRAL
};

//+------------------------------------------------------------------+
//| ENUM_FRACTAL_STATE — Candle Progression States                   |
//+------------------------------------------------------------------+
enum ENUM_FRACTAL_STATE
{
   FRACTAL_STATE_NONE = 0,
   FRACTAL_STATE_C1,
   FRACTAL_STATE_C2,
   FRACTAL_STATE_C3,
   FRACTAL_STATE_C4,
   FRACTAL_STATE_C3_CONTINUATION,
   FRACTAL_STATE_C3_DELAYED_REVERSAL,
   FRACTAL_STATE_WEAK
};

//+------------------------------------------------------------------+
//| LiquidityTier — Hierarchical Liquidity Classification            |
//+------------------------------------------------------------------+
enum LiquidityTier
{
   LT_NONE,
   LT_IRL,
   LT_ERL
};

//+------------------------------------------------------------------+
//| STradeSignal — Trade Signal Structure                            |
//+------------------------------------------------------------------+
struct STradeSignal
{
   ENUM_SIGNAL_DIRECTION direction;
   bool isValid;
   ENUM_CISD_TYPE cisdType;
   ENUM_WICK_TYPE wickType;
   ENUM_EXECUTION_BRANCH branch;

   void STradeSignal()
   {
      direction = SIGNAL_NONE;
      isValid = false;
      cisdType = CISD_TYPE_NONE;
      wickType = WICK_NONE;
      branch = BRANCH_INTRADAY;
   }
};

//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+

bool IsValidNumber(double value)
{
   return (value == value && MathAbs(value) < 1.0e30);
}

ulong CheckSum(string s)
{
   ulong h = 0;
   for(int i = 0; i < StringLen(s); i++)
      h = (h * 31) + (ulong)StringGetCharacter(s, i);
   return h;
}

double MathClamp(double value, double min, double max)
{
   if(value < min) return min;
   if(value > max) return max;
   return value;
}

double MathSafeDivide(double numerator, double denominator)
{
   if(denominator == 0) return 0;
   return numerator / denominator;
}

//+------------------------------------------------------------------+
//| Constants                                                        |
//+------------------------------------------------------------------+
#define SAFE_MAX_DOUBLE (1.0e10)
#define SAFE_MAX_POINTS (1000000)

//+------------------------------------------------------------------+
//| LOG LEVEL SYSTEM                                                 |
//+------------------------------------------------------------------+
enum ENUM_LOG_LEVEL
{
   LOG_LEVEL_DEBUG = 0,
   LOG_LEVEL_INFO  = 1,
   LOG_LEVEL_WARN  = 2,
   LOG_LEVEL_ERROR = 3
};

ENUM_LOG_LEVEL g_logLevel = LOG_LEVEL_INFO;

//+------------------------------------------------------------------+
//| SSE_CISDResult — CISD detection result with structural data      |
//| Used by SSE_DetectCISD in StructuralStateEngine.mqh to return    |
//| confirmation status plus the structural swing price for SL       |
//| anchoring. Defined here (before StructuralStateEngine.mqh) so    |
//| that all consumers (BranchEvaluator, ClosureEngine, ExitEngine)  |
//| have access without include-order dependencies.                  |
//+------------------------------------------------------------------+
struct SSE_CISDResult
{
    bool   confirmed;         // true if CISD confirmed
    double swingPrice;        // Protected swing price (low for buy, high for sell)
    double seriesOpen;        // Open price of the initiating candle of the delivery series
    int    swingIndex;        // Bar index of the swing point
    int    seriesStartIndex;  // Bar index of the initiating candle

    void Reset()
    {
        confirmed       = false;
        swingPrice      = 0.0;
        seriesOpen      = 0.0;
        swingIndex      = -1;
        seriesStartIndex = -1;
    }
};

//+------------------------------------------------------------------+
//| ENUM_CLOSURE_MODE — Closure Signal Decision Mode                 |
//+------------------------------------------------------------------+
enum ENUM_CLOSURE_MODE
{
   CLOSURE_MODE_ANTICIPATION = 1, // Match EntryMode (MODE_ANTICIPATION = 1)
   CLOSURE_MODE_CONFIRMATION = 2  // Match EntryMode (MODE_CONFIRMATION = 2)
};

//+------------------------------------------------------------------+
//| ModeDecision — Closure Mode Decision Result                       |
//+------------------------------------------------------------------+
struct ModeDecision
{
   ENUM_CLOSURE_MODE mode;
   int score;
   bool htfAligned;
   bool validLocation;
   bool structureContext;
   bool strongClosure;
};

//+------------------------------------------------------------------+
//| ENUM_CLOSURE_TYPE — Closure Type Enum                              |
//+------------------------------------------------------------------+
#ifndef ENUM_CLOSURE_TYPE_DEFINED
#define ENUM_CLOSURE_TYPE_DEFINED
enum ENUM_CLOSURE_TYPE
{
   CLOSURE_NONE = 0,
   CLOSURE_C2,
   CLOSURE_C3,
   CLOSURE_C4
};
#endif

//+------------------------------------------------------------------+
//| ENUM_HANDOVER_STATE — Handover Ownership State Machine            |
//+------------------------------------------------------------------+
enum ENUM_HANDOVER_STATE
{
   HANDOVER_NONE = 0,           // No handover active — Reset allowed
   HANDOVER_ACQUIRED,            // Exclusive ownership acquired by BranchEvaluator
   HANDOVER_TRANSFERRED,         // Ownership transferred to downstream subsystem
   HANDOVER_RELEASED,            // Ownership released — Reset allowed
   HANDOVER_FORCED_RELEASE       // Force-cleared after timeout — requires Reset
};

// Handover owner identifiers
#define HANDOVER_OWNER_NONE         0
#define HANDOVER_OWNER_BRANCH_EVAL  1
#define HANDOVER_OWNER_ORDER_MGR    2
#define HANDOVER_OWNER_EXEC_ENGINE  3

//+------------------------------------------------------------------+
//| ENUM_SIGNAL_STAGE — Signal Lifecycle State (FSM)                  |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_STAGE
{
   STAGE_NONE = 0,
   STAGE_LOCKED,
   STAGE_AWAITING_C2_CLOSURE,
   STAGE_AWAITING_C3_CLOSURE,
   STAGE_WAITING_FOR_POI,
   STAGE_WAITING_FOR_CISD,
   STAGE_READY,
   STAGE_EXECUTED,
   STAGE_EXPIRED
};

//+------------------------------------------------------------------+
//| SRiskProfile — Risk parameters per entry mode                    |
//+------------------------------------------------------------------+
struct SRiskProfile
{
   double slMultiplier;
   double tpMultiplier;
   double positionSizeFactor;
   double maxSpreadFactor;
   int minRR;
   bool useTrailingStop;
   double trailingActivation;
   double trailingStep;
};

//+------------------------------------------------------------------+
//| SLineage — Per-type sequence identity (must be before LockedSignal)  |
//+------------------------------------------------------------------+
struct SLineage
{
   ulong sequenceId;
   ulong parentGuid;
   bool requiresContinuation;
};

//+------------------------------------------------------------------+
//| PERSISTENT SIGNAL LOCK — Global locked signal across ticks     |
//+------------------------------------------------------------------+
// Include LockedSignal for SLockedSignal definition
#include <OmakFxYO/core/LockedSignal.mqh>

//+------------------------------------------------------------------+
//| SClosureSignal — Legacy wrapper for backward compatibility      |
//+------------------------------------------------------------------+
struct SClosureSignal
{
   bool valid;
   ENUM_CLOSURE_TYPE type;
   bool is_bullish;
   double entry_price;
   double stop_loss;
   double c1_high;
   double c1_low;
   double c1_close;
   double c2_high;
   double c2_low;
   double c2_open;
   double c2_close;
   int c2_barIndex;
   double c3_high;
   double c3_low;
   double c3_open;
   double c3_close;
   double equilibrium;
   double c2_wick_ratio;
   double c3_wick_ratio;
   bool againstPriorLTFTrend;
   ENUM_FRACTAL_STATE fractalState;
   bool c2HasSmallWick;
   bool c2ClosureConfirmed;
   bool c3EngulfingC2;
   bool c3CisdRequired;
   bool m_upgradedFromC2;
   double confidence;
datetime m_detectionTime;
    ulong m_guid; // Provisional GUID generated at acceptance for traceable forensics
    datetime setupStartTime;
   datetime setupHtfCandleStart;
   double setupInitialHigh;
   double setupInitialLow;
   bool setupIsBullish;
bool expansionMode;           // TTFM Gate 2: true = expansion candle (dominant wick < 50%), false = reversal candle
 
    double tSpotMin;              // T-Spot zone lower bound (HTF Low for bullish, Equilibrium for bearish)
    double tSpotMax;              // T-Spot zone upper bound (Equilibrium for bullish, HTF High for bearish)
 
    void Reset()
   {
      valid = false;
      type = CLOSURE_NONE;
      is_bullish = false;
      entry_price = 0.0;
      stop_loss = 0.0;
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
      equilibrium = 0.0;
      c2_wick_ratio = 0.0;
      c3_wick_ratio = 0.0;
      againstPriorLTFTrend = false;
      fractalState = FRACTAL_STATE_NONE;
      c2HasSmallWick = false;
      c2ClosureConfirmed = false;
      c3EngulfingC2 = false;
      c3CisdRequired = false;
      m_upgradedFromC2 = false;
      confidence = 0.0;
m_detectionTime = 0;
       m_guid = 0; // Clear provisional GUID
       setupStartTime = 0;
      setupHtfCandleStart = 0;
setupInitialHigh = 0.0;
        setupInitialLow = 0.0;
        setupIsBullish = false;
        expansionMode = false;
        tSpotMin = 0.0;
        tSpotMax = 0.0;
     }

   SClosureSignal() { Reset(); }

   void MapFromLocked(int stage, int closureType, int direction,
                      double in_entry_price, double in_c2_high, double in_c2_low,
                      double in_c2_open, double in_c2_close, int in_c2_barIndex,
                      double in_c3_high, double in_c3_low, double in_c3_open, double in_c3_close)
   {
      valid = (stage != 0);
      type = (ENUM_CLOSURE_TYPE)closureType;
      is_bullish = (direction == 1);
      entry_price = in_entry_price;
      stop_loss = in_entry_price;
      c2_high = in_c2_high;
      c2_low = in_c2_low;
      c2_open = in_c2_open;
      c2_close = in_c2_close;
      c2_barIndex = in_c2_barIndex;
      c3_high = in_c3_high;
      c3_low = in_c3_low;
      c3_open = in_c3_open;
      c3_close = in_c3_close;
      c1_high = in_c2_high;
      c1_low = in_c2_low;
      c1_close = in_c2_close;
      equilibrium = (c1_high + c1_low) / 2.0;
      c2_wick_ratio = 0.0;
      c3_wick_ratio = 0.0;
      againstPriorLTFTrend = false;
      fractalState = FRACTAL_STATE_NONE;
   }
};

//+------------------------------------------------------------------+
//| IsValidC3Setup — C3-specific validation per Constitution §III    |
//| Constitutional minimums: entry price validity only.              |
//| Removed strict C2 body engulf — C3 is continuation confirmation, |
//| not mandatory engulf (Continuations PDF, Audit 72).              |
//| Direction consistency, CISD, and D1 alignment handled upstream.   |
//+------------------------------------------------------------------+
bool IsValidC3Setup(const SClosureSignal &signal)
 {
    if(signal.type != CLOSURE_C3)
       return false;

    // Per AGENTS.md §XVI Gate 4: T-Spot zone must be valid (entry_price already mapped before Lock per §II)
    if(signal.tSpotMin <= 0.0 || signal.tSpotMax <= 0.0 || signal.tSpotMin >= signal.tSpotMax)
    {
       LogPrint("[C3_LOCK_FAILED] Invalid T-Spot zone | tSpotMin=" + DoubleToString(signal.tSpotMin, _Digits) +
                " tSpotMax=" + DoubleToString(signal.tSpotMax, _Digits), LOG_LEVEL_WARN);
       return false;
    }

    LogPrint("[C3_TSPOT_VALID] | tSpotMin=" + DoubleToString(signal.tSpotMin, _Digits) +
             " | tSpotMax=" + DoubleToString(signal.tSpotMax, _Digits) +
             " | direction=" + (signal.is_bullish ? "BUY" : "SELL"), LOG_LEVEL_INFO);
    return true;
 }

//+------------------------------------------------------------------+
//| SLockedSignal::Lock — Implementation (defined after SClosureSignal) |
//+------------------------------------------------------------------+
bool SLockedSignal::Lock(SClosureSignal &signal, int id, ENUM_EXECUTION_BRANCH execBranch, ENUM_TIMEFRAMES tf)
{
   // VERBATIM REPAIR: Zombie Guard & Lock Integrity (§III)
   // Hard-reject terminal signals
   if(this.stage == STAGE_EXPIRED)
   {
       LogPrint("[ZOMBIE_BLOCK] Lock rejected — signal is EXPIRED | GUID=" + IntegerToString(this.m_guid), LOG_LEVEL_ERROR);
       return false;
   }

   // [LOCK_CALL] Log before any processing
   LogPrint("[LOCK_CALL] stage=" + EnumToString(stage) + " guid_before=" + IntegerToString(m_guid), LOG_LEVEL_INFO);

// Validate signal before locking
    if(StringLen(_Symbol) == 0 || tf == 0)
       return false;

    // ═══════════════════════════════════════════════════════════════
    // CONSTITUTIONAL GUID OWNERSHIP — LockedSignal is sole authority
    // ═══════════════════════════════════════════════════════════════
    // Sole authority — ignore provisional, always generate fresh
    this.m_guid = 0;
    this.m_guid = GenerateSignalGUID();

    LogPrint("[GUID_ASSIGNED] sole_authority | GUID=" + IntegerToString(this.m_guid) +
             " | closure=" + EnumToString(signal.type), LOG_LEVEL_INFO);

// [ENTRY_PRICE_VALIDATION] — Per §II Law of Synchronous Mapping
// NO signal may be locked with entry_price=0.0. Mapping must occur before Lock.
       if(signal.entry_price <= 0)
       {
          LogPrint("[ENTRY_CANDIDATE_INVALID] entry_price=0 blocked at Lock | GUID=" + IntegerToString(m_guid) +
                   " | type=" + EnumToString(signal.type), LOG_LEVEL_ERROR);
          return false;
       }

       // [C3_VALIDATE] C3-specific validation per Constitution §XVI
       // Required at Lock: T-Spot zone validity (entry_price already mapped via EE_MapC3POI before Lock per §II)
       if(signal.type == CLOSURE_C3)
       {
          if(!IsValidC3Setup(signal))
          {
             LogPrint("[C3_LOCK_FAILED] IsValidC3Setup rejected | GUID=" + IntegerToString(m_guid) +
                      " | tSpotMin=" + DoubleToString(signal.tSpotMin, _Digits) +
                      " | tSpotMax=" + DoubleToString(signal.tSpotMax, _Digits), LOG_LEVEL_WARN);
             return false;
          }
          TransitionStage(STAGE_AWAITING_C3_CLOSURE);
       }
      else if(signal.type == CLOSURE_C4)
      {
         // C4 validation: must have c3 reference data
         if(signal.c3_high <= 0.0 || signal.c3_low <= 0.0)
         {
            LogPrint("[C4_LOCK_FAILED] Missing C3 reference data | GUID=" + IntegerToString(m_guid), LOG_LEVEL_WARN);
            return false;
         }
         TransitionStage(STAGE_AWAITING_C3_CLOSURE);
      }
      else
      {
         TransitionStage(STAGE_LOCKED);
      }

    // P8 Fix: Removed duplicate [SIGNAL_LOCKED] - detailed log happens in ClosureEngine (C2/C3)
    branchId = execBranch;
    this.branch = execBranch;
    entryTF = tf;
    symbol = _Symbol;
   retraceAttempts = 0;
   lastAttemptTime = 0;

   c2_high = signal.c2_high;
   c2_low = signal.c2_low;
   c2_open = signal.c2_open;
   c2_close = signal.c2_close;
   c2_barIndex = signal.c2_barIndex;

   c3_high = signal.c3_high;
   c3_low = signal.c3_low;
   c3_open = signal.c3_open;
   c3_close = signal.c3_close;

   entry_price = signal.entry_price;
   candidateEntryPrice = signal.entry_price; // [ENTRY_TRUTH] Preserve candidate at lock time
   stop_loss = signal.stop_loss;
   LogPrint("[SL_TRACE] Lock COPY | guid=" + IntegerToString(m_guid) +
           " sl=" + DoubleToString(stop_loss, _Digits) +
           " from_signal.sl=" + DoubleToString(signal.stop_loss, _Digits), LOG_LEVEL_DEBUG);
   direction = signal.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;
   closureType = signal.type;

    // Detection timestamp carry-over (may already be seeded by EvaluateC2Closure/C3Closure)
    m_detectionTime = (signal.m_detectionTime > 0) ? signal.m_detectionTime : TimeCurrent();

    // Setup-level metadata
    // The setup starts with C1, so setup metadata is derived from C1 data
    m_setupStartTime = signal.setupStartTime > 0 ? signal.setupStartTime : TimeCurrent();
   m_setupHtfCandleStart = signal.setupHtfCandleStart > 0 ? signal.setupHtfCandleStart : TimeCurrent();
   m_setupInitialHigh = signal.setupInitialHigh > 0.0 ? signal.setupInitialHigh : signal.c1_high;
   m_setupInitialLow = signal.setupInitialLow > 0.0 ? signal.setupInitialLow : signal.c1_low;
   m_setupIsBullish = signal.setupIsBullish;

// C2-specific metadata
    m_c2CommitBarTime = TimeCurrent();
    m_c2HadSmallWick = signal.c2HasSmallWick;
    m_c2ClosureConfirmed = signal.c2ClosureConfirmed;

    // C3-specific metadata (only if C3 pipeline active)
    if(signal.type == CLOSURE_C3)
    {
        m_c3CommitBarTime = TimeCurrent();
        m_c3EntryHigh = signal.c3_high;
        m_c3EntryLow = signal.c3_low;
        m_c3Equilibrium = (signal.c3_high + signal.c3_low) / 2.0;
m_c3CisdConfirmed = false; // Will be set true after CISD check on LTF
         m_c3ParentC2Guid = 0; // Will be set during modal upgrade
         tSpotMin = signal.tSpotMin;
         tSpotMax = signal.tSpotMax;
    }

    ENUM_TIMEFRAMES structTF = (tf == PERIOD_CURRENT) ? _Period : tf;
    lockTime = iTime(_Symbol, structTF, 0);

    double c1Range = signal.c2_high - signal.c2_low;
    equilibrium = (c1Range > 0.0) ? signal.c2_low + (c1Range * 0.5) : 0.0;

   double slDistance = MathAbs(signal.entry_price - signal.stop_loss);
    double tpDistance = slDistance;
    rr = (slDistance > 0.0) ? (tpDistance / slDistance) : 0.0;

// Initialize execution retry control
    executionAttempts = 0;
    lastExecutionAttempt = 0;
    retryCapReached = false;

    // Initialize tick counters
    tickCount = 0;
    resolveLockedCount = 0;
    maxTickCount = 10000;

    // [MODE_ASSIGNED] Assign mode deterministically per Constitution
    // C2 → MODE_ANTICIPATION, C3/C4 → MODE_CONFIRMATION
    if(signal.type == CLOSURE_C2)
    {
       LogPrint("[STATE_MUTATION] owner=LockedSignal | field=executionMode | old=" + IntegerToString(executionMode) +
                " | new=" + IntegerToString(MODE_ANTICIPATION) + " | reason=C2_ANTICIPATION", LOG_LEVEL_DEBUG);
       executionMode = MODE_ANTICIPATION;
    }
    else if(signal.type == CLOSURE_C3 || signal.type == CLOSURE_C4)
    {
       LogPrint("[STATE_MUTATION] owner=LockedSignal | field=executionMode | old=" + IntegerToString(executionMode) +
                " | new=" + IntegerToString(MODE_CONFIRMATION) + " | reason=C3/C4_CONFIRMATION", LOG_LEVEL_DEBUG);
       executionMode = MODE_CONFIRMATION;
    }
    else
    {
       LogPrint("[STATE_MUTATION] owner=LockedSignal | field=executionMode | old=" + IntegerToString(executionMode) +
                " | new=" + IntegerToString(MODE_NONE) + " | reason=UNKNOWN_CLOSURE", LOG_LEVEL_ERROR);
       executionMode = MODE_NONE; // Should never happen — reject below
    }

    // Initialize risk profile (prevents garbage slMultiplier in CalculateClosureTypeSL)
    SRiskProfile profile;
    if(executionMode == MODE_CONFIRMATION)
    {
       profile.slMultiplier = 1.0;
       profile.tpMultiplier = 2.0;
       profile.positionSizeFactor = 1.0;
       profile.maxSpreadFactor = 1.5;
       profile.minRR = 2;
       profile.useTrailingStop = true;
       profile.trailingActivation = 1.5;
       profile.trailingStep = 0.5;
    }
    else
    {
       profile.slMultiplier = 1.5;
       profile.tpMultiplier = 3.0;
       profile.positionSizeFactor = 0.75;
       profile.maxSpreadFactor = 2.0;
       profile.minRR = 3;
       profile.useTrailingStop = false;
       profile.trailingActivation = 2.0;
       profile.trailingStep = 0.5;
    }
    riskProfile = profile;

    // Assign contract fields at lock time
    structuralBias = signal.againstPriorLTFTrend ? 2 : (signal.is_bullish ? 1 : 0);
    continuationState = 1; // CONTINUATION_ACTIVE by default
    invalidationState = 1; // INVALID_VALID

    // [ENTRY_CANDIDATE_SET] Log entry candidate price
    LogPrint("[ENTRY_CANDIDATE_SET] GUID=" + IntegerToString(m_guid) +
            " | entry_candidate=" + DoubleToString(entry_price, _Digits) +
            " | protected_swing=" + DoubleToString(stop_loss, _Digits) +
            " | executionMode=" + IntegerToString(executionMode), LOG_LEVEL_INFO);

    // [SIGNAL_CONTRACT_OK] Validate complete contract
    if(!IsContractComplete())
    {
       LogPrint("[SIGNAL_CONTRACT_FAIL] GUID=" + IntegerToString(m_guid) +
                " | reason=INCOMPLETE_CONTRACT | executionMode=" + IntegerToString(executionMode) +
                " | closureType=" + EnumToString(closureType) +
                " | entry_price=" + DoubleToString(entry_price, _Digits), LOG_LEVEL_ERROR);
       return false;
    }

    // [LOCKED_SIGNAL_COMPLETE] Signal locked with full contract
    LogPrint(StringFormat("[LOCKED_SIGNAL_COMPLETE] GUID=%I64u | closure=%s | direction=%s | stage=%s | mode=%d",
            m_guid, EnumToString(signal.type), (signal.is_bullish ? "BUY" : "SELL"),
            EnumToString(stage), executionMode), LOG_LEVEL_INFO);

    // Runtime assertion: illegal locked states
    if(executionMode == MODE_NONE)
    {
       LogPrint("[CONSTITUTIONAL_FAILURE] MODE_NONE at lock time | GUID=" + IntegerToString(m_guid) +
                " | closureType=" + EnumToString(closureType), LOG_LEVEL_ERROR);
    }
    if(closureType == CLOSURE_NONE)
    {
       LogPrint("[CONSTITUTIONAL_FAILURE] CLOSURE_NONE at lock time | GUID=" + IntegerToString(m_guid), LOG_LEVEL_ERROR);
    }
    if(entry_price <= 0.0)
    {
       LogPrint("[ENTRY_CANDIDATE_INVALID] entry_price=0 at lock time | GUID=" + IntegerToString(m_guid), LOG_LEVEL_ERROR);
    }
    if(m_guid == 0)
    {
       LogPrint("[SIGNAL_CONTRACT_FAIL] GUID=0 at lock time", LOG_LEVEL_ERROR);
    }

    return true;
}

// VERBATIM REPAIR: Pass-Through Lock (§IV)
bool SLockedSignal::Lock(double scannerMin, double scannerMax) {
    this.m_guid = GenerateSignalGUID();
    LogPrint("[GUID_ASSIGNED] pass-through | GUID=" + IntegerToString(this.m_guid), LOG_LEVEL_INFO);
    if(this.entry_price <= 0.0) {
        LogPrint("[ENTRY_CANDIDATE_INVALID] pass-through Lock blocked | GUID=" + IntegerToString(this.m_guid), LOG_LEVEL_ERROR);
        return false;
    }
    this.candidateEntryPrice = this.entry_price;
    this.requestedEntryPrice = this.entry_price;
    this.tSpotMin = scannerMin;
    this.tSpotMax = scannerMax;
    if(this.m_detectionTime <= 0)
        this.m_detectionTime = TimeCurrent();
    this.stage = STAGE_LOCKED;
    return (this.tSpotMax > 0); 
}

//+------------------------------------------------------------------+
//| Per-branch resolved runtime parameters                           |
//+------------------------------------------------------------------+
struct SBranchResolvedParams
{
   double c2WickThreshold;
   double c2MinWickRatio;
   double c2MinBodyRatio;
   double c2DisplacementMultiplier;
   double c2RangeExpansionFactor;
   double c3BodyMultiplier;
   double c3DisplacementMultiplier;
   double c3RangeExpansionFactor;
   double rgBufferPercent;
   double rgMarketThreshold;
   double c2POIBufferPercent;
   double c3POIBufferPercent;
   int limitExpirationBars;
};

//+------------------------------------------------------------------+
//| STrueTTradesConfig — True TTrades Mode Configuration            |
//+------------------------------------------------------------------+
struct STrueTTradesConfig
{
   bool enabled;
   double maxC2WickPercent;
   double displacementThresholdTrending;
   double displacementThresholdNonTrending;
   double anticipationDisplacementMin;
   bool useVolumeConfirmation;
   double minVolumeExpansion;
   bool allowRangeAsTransition;
   double anticipationMinRR;
   double confirmationMinRR;
   bool allowAnticipationReversals;
};

STrueTTradesConfig g_trueTTradesConfig;

void InitTrueTTradesConfig()
{
   g_trueTTradesConfig.enabled = true;
   g_trueTTradesConfig.maxC2WickPercent = 0.6;
   g_trueTTradesConfig.displacementThresholdTrending = 1.0;
   g_trueTTradesConfig.displacementThresholdNonTrending = 1.2;
   g_trueTTradesConfig.anticipationDisplacementMin = 0.40;
   g_trueTTradesConfig.useVolumeConfirmation = false;
   g_trueTTradesConfig.minVolumeExpansion = 120.0;
   g_trueTTradesConfig.allowRangeAsTransition = true;
   g_trueTTradesConfig.anticipationMinRR = 2.0;
   g_trueTTradesConfig.confirmationMinRR = 2.0;
   g_trueTTradesConfig.allowAnticipationReversals = true;
}

void ApplyTrueTTradesInputs(bool useTTMode, ENUM_TIMEFRAMES style, double maxC2Wick, bool useVol, double minVol)
{
   g_trueTTradesConfig.enabled = useTTMode;
   g_trueTTradesConfig.maxC2WickPercent = maxC2Wick;
   g_trueTTradesConfig.useVolumeConfirmation = useVol;
   g_trueTTradesConfig.minVolumeExpansion = minVol;
   g_trueTTradesConfig.anticipationMinRR = InpAnticipationRR;
   g_trueTTradesConfig.confirmationMinRR = InpConfirmationRR;
   g_trueTTradesConfig.allowAnticipationReversals = InpAllowAnticipationReversals;
}

void UpdateTrueTTradesModeParams(double antiRR, double confRR, bool allowReversals)
{
   g_trueTTradesConfig.anticipationMinRR = antiRR;
   g_trueTTradesConfig.confirmationMinRR = confRR;
   g_trueTTradesConfig.allowAnticipationReversals = allowReversals;
}

bool ValidateTrueTTradesConfig()
{
   return true;
}

//+------------------------------------------------------------------+
//| OrderGUIDPair — Order ticket to signal GUID mapping             |
//+------------------------------------------------------------------+
struct OrderGUIDPair
{
   ulong ticket;
   ulong guid;
};

//+------------------------------------------------------------------+
//| GetPipSize — Calc-mode-aware pip size.                           |
//+------------------------------------------------------------------+
double GetPipSize(string symbol)
{
   return SY_GetPipSize(symbol);
}

//+------------------------------------------------------------------+
//| ENUM_EXIT_TYPE — Exit classification for LogExitMarker           |
//+------------------------------------------------------------------+
enum ENUM_EXIT_TYPE
{
   EXIT_CRT_TARGET,
   EXIT_CISD_REVERSAL,
   EXIT_DOW_BOS,
   EXIT_TRAILING_STOP,
   EXIT_SL_HIT,
   EXIT_EMERGENCY_CLOSE
};

//+------------------------------------------------------------------+
//| ENUM_EQUITY_GUARD_STATE — Risk compliance engine state machine   |
//+------------------------------------------------------------------+
enum ENUM_EQUITY_GUARD_STATE
{
   EQUITY_GUARD_NORMAL,
   EQUITY_GUARD_WARNING,
   EQUITY_GUARD_BREACHED,
   EQUITY_GUARD_PERMANENT
};

//+------------------------------------------------------------------+
//| Symbol Intelligence Layer (calc-mode-aware, broker-reality)      |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/SymbolIntelligence.mqh>

//+------------------------------------------------------------------+
//| SSequenceLineage — Closure sequence identity (v52.5+)            |
//+------------------------------------------------------------------+
struct SSequenceLineage
{
   ulong sequenceId;
   datetime anchorBarTime;
   datetime originBarTime;
   datetime detectionTime;
   ENUM_CLOSURE_TYPE closureKind;
   ENUM_EXECUTION_BRANCH branchId;
   string invalidationReason;
   ENUM_SIGNAL_STAGE stage;

   void Reset()
   {
      sequenceId = 0;
      anchorBarTime = 0;
      originBarTime = 0;
      detectionTime = 0;
      closureKind = CLOSURE_NONE;
      branchId = BRANCH_INTRADAY;
      invalidationReason = "";
      stage = STAGE_NONE;
   }
};

//+------------------------------------------------------------------+
//| SContinuationContext — Structural narrative persistence object    |
//+------------------------------------------------------------------+
struct SContinuationContext
{
   ulong narrativeGuid;
   ulong c2ReferenceGuid;
   datetime lockTime;
   double protectedSwingLow;
   double protectedSwingHigh;
   ENUM_DIRECTION direction;
   bool c2Confirmed;
   bool c3Attempted;
   bool c3Confirmed;
   datetime lastEvaluationTime;
   int evaluationCount;
   bool invalidated;
   string invalidationReason;

   void Initialize(ulong guid, double sl, double sh, ENUM_DIRECTION dir)
   {
      narrativeGuid = guid;
      c2ReferenceGuid = guid;
      lockTime = TimeCurrent();
      protectedSwingLow = sl;
      protectedSwingHigh = sh;
      direction = dir;
      c2Confirmed = true;
      c3Attempted = false;
      c3Confirmed = false;
      lastEvaluationTime = lockTime;
      evaluationCount = 0;
      invalidated = false;
      invalidationReason = "";
   }

   bool IsValid() const { return !invalidated && narrativeGuid != 0; }
   void Invalidate(string reason) { invalidated = true; invalidationReason = reason; }
};

//+------------------------------------------------------------------+
//| PositionGUIDMap — Position ticket + signal GUID mapping            |
//+------------------------------------------------------------------+
struct PositionGUIDMap
{
   ulong positionTicket;
   ulong signalGUID;
   double entryPrice;
   double protectedSwing;
   datetime entryTime;
   ENUM_DIRECTION direction;
   ENUM_CLOSURE_TYPE closureType;
   double c1_high;
   double c1_low;
   double c2_high;
   double c2_low;
   ENUM_EXECUTION_BRANCH branch;
};

//+------------------------------------------------------------------+
//| Global Continuation Tracking Arrays                              |
//+------------------------------------------------------------------+
#define MAX_ACTIVE_NARRATIVES 10
SContinuationContext g_continuationContexts[MAX_ACTIVE_NARRATIVES];
int g_continuationContextCount = 0;

//+------------------------------------------------------------------+
//| ClosureState — Per-branch C2/C3/C4 state (included AFTER SLockedSignal) |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/ClosureState.mqh>

//+------------------------------------------------------------------+
//| IsSignalLiveForNextTick — Liveness check before MEM_SANITIZED     |
//+------------------------------------------------------------------+
bool IsSignalLiveForNextTick(const SLockedSignal &sig) {
    // A signal is live if it is READY to execute or has already started attempts
    if (sig.stage == STAGE_READY || sig.executionAttempts > 0) return true;
    return false;
}

#endif // OMAK_CORETYPES_MQH