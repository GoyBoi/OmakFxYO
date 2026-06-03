//+------------------------------------------------------------------+
//| LogGovernor.mqh                                                  |
//| Omak FxYO — Centralized Log Governance System (v2)               |
//|                                                                  |
//| ROLE: Deterministic log emission preventing backtest explosion |
//|   - Per-tag throttle map (key=tag, value=lastEmitTime)          |
//|   - Signature-based deduplication (key=tag+signalID)            |
//|   - 5-second minimum throttle                                   |
//|   - Per-bar emission control (optional)                         |
//|   - Event-based: logs emit ONCE per event, NOT per tick        |
//|                                                                  |
//| USAGE: Include AFTER CoreTypes.mqh                              |
//+------------------------------------------------------------------+
#ifndef OMAK_LOGGOVERNOR_MQH
#define OMAK_LOGGOVERNOR_MQH

#include <OmakFxYO/core/CoreTypes.mqh>

//+------------------------------------------------------------------+
//| LOG CHANNELS — Categorize logs for filtering + analysis         |
//+------------------------------------------------------------------+
enum ENUM_LOG_CHANNEL
{
    LOG_CHANNEL_SYSTEM,      // Init, deinit, session changes
    LOG_CHANNEL_PIPELINE,   // Branch evaluation, mode resolution
    LOG_CHANNEL_SIGNAL,      // Closure signals, bias changes
    LOG_CHANNEL_EXECUTION,  // Trade execution, position management
    LOG_CHANNEL_RISK,       // Risk checks, lot sizing, margin
    LOG_CHANNEL_QUALITY,     // Quality gates, score validation
    LOG_CHANNEL_SPREAD       // Spread filtering
};

//+------------------------------------------------------------------+
//| LOG EVENT TYPES — For structured event logging                 |
//+------------------------------------------------------------------+
enum ENUM_LOG_EVENT_TYPE
{
    LOG_EVENT_TRADE_OPEN,        // Trade opened
    LOG_EVENT_TRADE_CLOSE,       // Trade closed
    LOG_EVENT_TRADE_MODIFY,      // SL/TP modified
    LOG_EVENT_SIGNAL_GENERATED,   // Signal detected
    LOG_EVENT_SIGNAL_BLOCKED,     // Signal blocked
    LOG_EVENT_MODE_CHANGE,       // Mode changed
    LOG_EVENT_BIAS_CHANGE,       // Bias changed
    LOG_EVENT_BRANCH_SWITCH,     // Branch switched
    LOG_EVENT_RISK_CHECK,         // Risk check result
    LOG_EVENT_ERROR,             // Error condition
    LOG_EVENT_INFO              // General info
};

//+------------------------------------------------------------------+
//| BUDGET LIMITS — Global log caps (configurable)                  |
//+------------------------------------------------------------------+
struct SLogBudgetConfig
{
    int maxLogsPerTick;       // Maximum logs per tick (default: 5)
    int maxLogsPerBar;         // Maximum logs per bar (default: 50)
    int maxLogsPerModule;      // Maximum logs per module per bar (default: 20)
    int maxLogsPerSession;     // Maximum logs per backtest session (default: 500000)

    int sampleFirstN;         // For INFO: only log first N identical (default: 3)
    int minThrottleMs;        // Minimum throttle between same tag (default: 5000ms)
    int debugThrottleMs;       // Debug log throttle ms (default: 500)
    int infoThrottleMs;        // Info log throttle ms (default: 2000)
    int warnThrottleMs;        // Warn log throttle ms (default: 5000)

    bool enableStructured;     // Enable JSON-structured output (default: false)
    bool enableTraceChannel;   // Enable TRACE channel (default: false for backtest)
    bool perBarControl;       // Enable per-bar emission control (default: true)

    void SetDefaults()
    {
        maxLogsPerTick = 5;
        maxLogsPerBar = 50;
        maxLogsPerModule = 20;
        maxLogsPerSession = 500000;  // Increased from 100K: sufficient for DEBUG logs across full backtest (e.g., 3+ months M5)

        sampleFirstN = 3;
        minThrottleMs = 5000;       // 5-second minimum throttle
        debugThrottleMs = 500;
        infoThrottleMs = 2000;
        warnThrottleMs = 5000;

        enableStructured = false;
        enableTraceChannel = false;
        perBarControl = true;
    }
};

//+------------------------------------------------------------------+
//| PER-TAG THROTTLE MAP — Tag-based throttle tracking              |
//+------------------------------------------------------------------+
struct SLogTagThrottle
{
    string tag;
    datetime lastEmitTime;
    int emitCount;
    datetime firstEmitTime;

    void Reset()
    {
        tag = "";
        lastEmitTime = 0;
        emitCount = 0;
        firstEmitTime = 0;
    }
};

#define MAX_TAG_THROTTLE_ENTRIES 64

struct SLogTagThrottleMap
{
    SLogTagThrottle entries[MAX_TAG_THROTTLE_ENTRIES];
    int count;

    void Reset()
    {
        for(int i = 0; i < MAX_TAG_THROTTLE_ENTRIES; i++)
            entries[i].Reset();
        count = 0;
    }

    datetime GetLastEmitTime(string tag)
    {
        for(int i = 0; i < count; i++)
            if(entries[i].tag == tag)
                return entries[i].lastEmitTime;
        return 0;
    }

    void SetLastEmitTime(string tag, datetime time)
    {
        for(int i = 0; i < count; i++)
        {
            if(entries[i].tag == tag)
            {
                entries[i].lastEmitTime = time;
                entries[i].emitCount++;
                return;
            }
        }
        if(count < MAX_TAG_THROTTLE_ENTRIES)
        {
            entries[count].tag = tag;
            entries[count].lastEmitTime = time;
            entries[count].emitCount = 1;
            entries[count].firstEmitTime = time;
            count++;
        }
    }

    int GetEmitCount(string tag)
    {
        for(int i = 0; i < count; i++)
            if(entries[i].tag == tag)
                return entries[i].emitCount;
        return 0;
    }
};

//+------------------------------------------------------------------+
//| SIGNATURE-BASED DEDUPLICATION — Tag + SignalID key               |
//+------------------------------------------------------------------+
struct SLogSignatureEntry
{
    string signature;          // tag + signalID combined
    datetime lastEmitTime;
    int emitCount;

    void Reset()
    {
        signature = "";
        lastEmitTime = 0;
        emitCount = 0;
    }
};

#define MAX_SIGNATURE_ENTRIES 128

struct SLogSignatureDedup
{
    SLogSignatureEntry entries[MAX_SIGNATURE_ENTRIES];
    int count;

    void Reset()
    {
        for(int i = 0; i < MAX_SIGNATURE_ENTRIES; i++)
            entries[i].Reset();
        count = 0;
    }

    bool ShouldEmit(string signature, datetime now, int minThrottleMs)
    {
        for(int i = 0; i < count; i++)
        {
            if(entries[i].signature == signature)
            {
                if(now - entries[i].lastEmitTime < minThrottleMs)
                    return false;
                return true;
            }
        }
        return true;
    }

    void RecordEmit(string signature, datetime now)
    {
        for(int i = 0; i < count; i++)
        {
            if(entries[i].signature == signature)
            {
                entries[i].lastEmitTime = now;
                entries[i].emitCount++;
                return;
            }
        }
        if(count < MAX_SIGNATURE_ENTRIES)
        {
            entries[count].signature = signature;
            entries[count].lastEmitTime = now;
            entries[count].emitCount = 1;
            count++;
        }
    }
};

//+------------------------------------------------------------------+
//| PER-BAR EMISSION CONTROL                                         |
//+------------------------------------------------------------------+
struct SLogPerBarControl
{
    datetime lastBarTime;
    int logsThisBar;
    int maxLogsPerBar;

    void Initialize()
    {
        lastBarTime = 0;
        logsThisBar = 0;
        maxLogsPerBar = 50;
    }

    bool CanEmit(datetime barTime)
    {
        if(barTime != lastBarTime)
        {
            lastBarTime = barTime;
            logsThisBar = 0;
        }
        return logsThisBar < maxLogsPerBar;
    }

    void RecordEmit()
    {
        logsThisBar++;
    }
};

//+------------------------------------------------------------------+
//| LOGGovernor's Internal State                                     |
//+------------------------------------------------------------------+
struct SLogGovernState
{
    datetime lastBarTime;
    int logsThisTick;
    int logsThisBar;
    int logsThisSession;

    int logsPerModule[];  // Per-module counts

    SLogBudgetConfig config;

    void Initialize()
    {
        lastBarTime = 0;
        logsThisTick = 0;
        logsThisBar = 0;
        logsThisSession = 0;
        config.SetDefaults();

        ArrayResize(logsPerModule, 64);
        ArrayFill(logsPerModule, 0, 64, 0);
    }

    void OnNewBar(datetime barTime)
    {
        if(barTime != lastBarTime)
        {
            lastBarTime = barTime;
            logsThisBar = 0;
            ArrayFill(logsPerModule, 0, 64, 0);
        }
    }

    void OnNewTick()
    {
        logsThisTick = 0;
    }
};

// Global log governor state
SLogGovernState g_logGovernor;
SLogTagThrottleMap g_tagThrottleMap;
SLogSignatureDedup g_signatureDedup;
SLogPerBarControl g_perBarControl;

//+------------------------------------------------------------------+
//| Log Hash — Simple hash for deduplication                         |
//+------------------------------------------------------------------+
ulong LogGov_HashString(const string msg)
{
    ulong hash = 5381;
    int len = StringLen(msg);
    for(int i = 0; i < len; i++)
    {
        ushort ch = StringGetCharacter(msg, i);
        hash = ((hash << 5) + hash) + ch;
    }
    return hash;
}

//+------------------------------------------------------------------+
//| LogGov_ExtractTag — Extract tag from log message                |
//|                                                                  |
//| Extracts the [TAG] portion from message for throttle tracking   |
//+------------------------------------------------------------------+
string LogGov_ExtractTag(const string msg)
{
    int start = StringFind(msg, "[");
    if(start < 0) return "UNKNOWN";
    
    int end = StringFind(msg, "]", start);
    if(end < 0) return "UNKNOWN";
    
    return StringSubstr(msg, start + 1, end - start - 1);
}

//+------------------------------------------------------------------+
//| LogGov_ShouldEmit — Core decision function (v2)                 |
//|                                                                  |
//| Event-based: ensures logs emit ONCE per event, NOT per tick    |
//+------------------------------------------------------------------+
bool LogGov_ShouldEmit(const ENUM_LOG_LEVEL level, const ENUM_LOG_CHANNEL channel,
                       const string msg, const string signalID = "")
{
    SLogBudgetConfig cfg = g_logGovernor.config;
    datetime now = TimeCurrent();

    // ERRORs always pass (always emit critical errors)
    if(level == LOG_LEVEL_ERROR)
        return true;

    // TRACE channel: disabled in backtest by default
    if(channel == LOG_CHANNEL_QUALITY && !cfg.enableTraceChannel)
        return false;

    // Budget: per-session cap
    if(g_logGovernor.logsThisSession >= cfg.maxLogsPerSession)
        return false;

    // Budget: per-tick cap
    if(level == LOG_LEVEL_DEBUG && g_logGovernor.logsThisTick >= cfg.maxLogsPerTick)
        return false;

    // Per-bar emission control (optional)
    if(cfg.perBarControl)
    {
        datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
        if(!g_perBarControl.CanEmit(barTime))
            return false;
    }

    // Level-based filtering: WARN/ERROR always pass level check
    if(level >= g_logLevel)
        return true;

    // === PER-TAG THROTTLE MAP ===
    string tag = LogGov_ExtractTag(msg);
    datetime lastEmit = g_tagThrottleMap.GetLastEmitTime(tag);
    
    // Check minimum throttle (5 seconds default)
    if(now - lastEmit < cfg.minThrottleMs)
        return false;

    // === SIGNATURE-BASED DEDUPLICATION ===
    // Key = tag + signalID (for signal-specific deduplication)
    if(signalID != "")
    {
        string signature = tag + ":" + signalID;
        if(!g_signatureDedup.ShouldEmit(signature, now, cfg.minThrottleMs))
            return false;
    }

    // === LEVEL-BASED ADDITIONAL THROTTLE ===
    int throttleMs = cfg.debugThrottleMs;
    if(level == LOG_LEVEL_INFO)
        throttleMs = cfg.infoThrottleMs;
    else if(level == LOG_LEVEL_WARN)
        throttleMs = cfg.warnThrottleMs;

    // Use the larger of minThrottleMs or level-based throttleMs
    int effectiveThrottle = MathMax(cfg.minThrottleMs, throttleMs);

    // INFO sampling: limit to first N identical messages
    if(level == LOG_LEVEL_INFO && lastEmit > 0)
    {
        int emitCount = g_tagThrottleMap.GetEmitCount(tag);
        if(emitCount >= cfg.sampleFirstN)
            return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| LogGov_Record — Record a log emission (v2)                      |
//+------------------------------------------------------------------+
void LogGov_Record(const ENUM_LOG_LEVEL level, const string msg, const string signalID = "")
{
    g_logGovernor.logsThisTick++;
    g_logGovernor.logsThisBar++;
    g_logGovernor.logsThisSession++;

    datetime now = TimeCurrent();

    // Record per-tag throttle
    string tag = LogGov_ExtractTag(msg);
    g_tagThrottleMap.SetLastEmitTime(tag, now);

    // Record signature deduplication
    if(signalID != "")
    {
        string signature = tag + ":" + signalID;
        g_signatureDedup.RecordEmit(signature, now);
    }

    // Record per-bar emission
    if(g_logGovernor.config.perBarControl)
    {
        datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
        g_perBarControl.RecordEmit();
    }
}

//+------------------------------------------------------------------+
//| LGovPrint — Primary log function with full governance (v2)     |
//|                                                                  |
//| Parameters:                                                     |
//|   msg       — log message                                       |
//|   level     — severity: LOG_LEVEL_DEBUG/INFO/WARN/ERROR         |
//|   channel   — category: LOG_CHANNEL_SYSTEM/PIPELINE/etc        |
//|   signalID  — optional signal ID for signature-based dedup     |
//+------------------------------------------------------------------+
void LGovPrint(const string msg, ENUM_LOG_LEVEL level, ENUM_LOG_CHANNEL channel,
               const string signalID = "")
{
    if(!LogGov_ShouldEmit(level, channel, msg, signalID))
        return;

    Print(msg);
    LogGov_Record(level, msg, signalID);
}

//+------------------------------------------------------------------+
//| LGovPrint — Overload without channel (defaults to SYSTEM)       |
//+------------------------------------------------------------------+
void LGovPrint(const string msg, ENUM_LOG_LEVEL level)
{
    LGovPrint(msg, level, LOG_CHANNEL_SYSTEM, "");
}

//+------------------------------------------------------------------+
//| LGovPrint — Overload with signalID for deduplication           |
//+------------------------------------------------------------------+
void LGovPrint(const string msg, ENUM_LOG_LEVEL level, const string signalID)
{
    LGovPrint(msg, level, LOG_CHANNEL_SYSTEM, signalID);
}

//+------------------------------------------------------------------+
//| Convenience macros                                              |
//+------------------------------------------------------------------+
#define LogDebug(msg)           LGovPrint(msg, LOG_LEVEL_DEBUG, LOG_CHANNEL_SYSTEM)
#define LogInfo(msg)            LGovPrint(msg, LOG_LEVEL_INFO, LOG_CHANNEL_SYSTEM)
#define LogWarn(msg)            LGovPrint(msg, LOG_LEVEL_WARN, LOG_CHANNEL_SYSTEM)
#define LogError(msg)           LGovPrint(msg, LOG_LEVEL_ERROR, LOG_CHANNEL_SYSTEM)
#define LogPrint(msg, lvl)      LGovPrint(msg, lvl, LOG_CHANNEL_SYSTEM)

// Signal-aware logging macros
#define LogDebugS(msg, sig)     LGovPrint(msg, LOG_LEVEL_DEBUG, LOG_CHANNEL_SYSTEM, sig)
#define LogInfoS(msg, sig)      LGovPrint(msg, LOG_LEVEL_INFO, LOG_CHANNEL_SYSTEM, sig)
#define LogWarnS(msg, sig)      LGovPrint(msg, LOG_LEVEL_WARN, LOG_CHANNEL_SYSTEM, sig)

//+------------------------------------------------------------------+
//| LogGov_SetBudget — Configure budget limits                       |
//+------------------------------------------------------------------+
void LogGov_SetBudget(int maxPerTick, int maxPerBar, int maxPerSession)
{
    g_logGovernor.config.maxLogsPerTick = maxPerTick;
    g_logGovernor.config.maxLogsPerBar = maxPerBar;
    g_logGovernor.config.maxLogsPerSession = maxPerSession;
    g_perBarControl.maxLogsPerBar = maxPerBar;
}

//+------------------------------------------------------------------+
//| LogGov_SetThrottle — Configure throttle settings                |
//+------------------------------------------------------------------+
void LogGov_SetThrottle(int minThrottleMs, int debugMs = 500, int infoMs = 2000, int warnMs = 5000)
{
    g_logGovernor.config.minThrottleMs = minThrottleMs;
    g_logGovernor.config.debugThrottleMs = debugMs;
    g_logGovernor.config.infoThrottleMs = infoMs;
    g_logGovernor.config.warnThrottleMs = warnMs;
}

//+------------------------------------------------------------------+
//| LogGov_SetPerBarControl — Enable/disable per-bar control       |
//+------------------------------------------------------------------+
void LogGov_SetPerBarControl(bool enabled)
{
    g_logGovernor.config.perBarControl = enabled;
    if(enabled)
        g_perBarControl.Initialize();
}

//+------------------------------------------------------------------+
//| LogGov_SetLevel — Set global log level                          |
//+------------------------------------------------------------------+
void LogGov_SetLevel(ENUM_LOG_LEVEL level)
{
    g_logLevel = level;
}

//+------------------------------------------------------------------+
//| LogGov_Init — Initialize on EA init                              |
//+------------------------------------------------------------------+
void LogGov_Init(ENUM_LOG_LEVEL level, bool traceEnabled = false)
{
    g_logGovernor.Initialize();
    g_logGovernor.config.enableTraceChannel = traceEnabled;
    
    g_tagThrottleMap.Reset();
    g_signatureDedup.Reset();
    g_perBarControl.Initialize();
    g_perBarControl.maxLogsPerBar = g_logGovernor.config.maxLogsPerBar;
    
    g_logLevel = level;
}

//+------------------------------------------------------------------+
//| LogGov_OnBar — Call on new bar for budget reset                 |
//+------------------------------------------------------------------+
void LogGov_OnBar(datetime barTime)
{
    g_logGovernor.OnNewBar(barTime);
    g_perBarControl.lastBarTime = barTime;
    g_perBarControl.logsThisBar = 0;
}

//+------------------------------------------------------------------+
//| LogGov_OnTick — Call on new tick for tick-budget reset           |
//+------------------------------------------------------------------+
void LogGov_OnTick()
{
    g_logGovernor.OnNewTick();
}

//+------------------------------------------------------------------+
//| LogGov_ResetThrottle — Reset throttle maps (for testing)        |
//+------------------------------------------------------------------+
void LogGov_ResetThrottle()
{
    g_tagThrottleMap.Reset();
    g_signatureDedup.Reset();
}

//+------------------------------------------------------------------+
//| LogGov_GetStats — Get current log stats for debugging           |
//+------------------------------------------------------------------+
string LogGov_GetStats()
{
    return StringFormat("[LOG] Session=%d/%d Bar=%d/%d Tick=%d/%d Tags=%d Sigs=%d",
        g_logGovernor.logsThisSession, g_logGovernor.config.maxLogsPerSession,
        g_logGovernor.logsThisBar, g_logGovernor.config.maxLogsPerBar,
        g_logGovernor.logsThisTick, g_logGovernor.config.maxLogsPerTick,
        g_tagThrottleMap.count, g_signatureDedup.count);
}

//+------------------------------------------------------------------+
//| LOG EVENT STRUCT — Structured event for forensic logging        |
//+------------------------------------------------------------------+
struct SLogEvent
{
    datetime timestamp;
    ENUM_LOG_CHANNEL channel;
    ENUM_LOG_EVENT_TYPE eventType;
    string module;
    string message;
    double numericContext;    // Price, volume, etc.
    int tradeTicket;          // Associated trade ticket (0 if none)

    void Reset()
    {
        timestamp = TimeCurrent();
        channel = LOG_CHANNEL_SYSTEM;
        eventType = LOG_EVENT_INFO;
        module = "";
        message = "";
        numericContext = 0.0;
        tradeTicket = 0;
    }

    string ToString()
    {
        string typeStr = "INFO";
        if(eventType == LOG_EVENT_TRADE_OPEN) typeStr = "OPEN";
        else if(eventType == LOG_EVENT_TRADE_CLOSE) typeStr = "CLOSE";
        else if(eventType == LOG_EVENT_TRADE_MODIFY) typeStr = "MODIFY";
        else if(eventType == LOG_EVENT_SIGNAL_GENERATED) typeStr = "SIG_GEN";
        else if(eventType == LOG_EVENT_SIGNAL_BLOCKED) typeStr = "SIG_BLK";
        else if(eventType == LOG_EVENT_MODE_CHANGE) typeStr = "MODE";
        else if(eventType == LOG_EVENT_BIAS_CHANGE) typeStr = "BIAS";
        else if(eventType == LOG_EVENT_BRANCH_SWITCH) typeStr = "BRANCH";
        else if(eventType == LOG_EVENT_RISK_CHECK) typeStr = "RISK";
        else if(eventType == LOG_EVENT_ERROR) typeStr = "ERROR";

        return StringFormat("[%s] %s | %s | %s | %s",
            TimeToString(timestamp, TIME_SECONDS),
            typeStr,
            module,
            message,
            numericContext > 0 ? DoubleToString(numericContext, _Digits) : "");
    }
};

//+------------------------------------------------------------------+
//| LogTrace — Unified log API with level + channel (v2)            |
//|                                                                  |
//| Parameters:                                                     |
//|   message  — log message                                        |
//|   level    — severity: LOG_LEVEL_DEBUG/INFO/WARN/ERROR           |
//|   channel  — category: LOG_CHANNEL_SYSTEM/PIPELINE/etc         |
//|   signalID — optional signal ID for signature-based dedup      |
//|                                                                  |
//| Returns: true if logged, false if dropped by governance         |
//+------------------------------------------------------------------+
bool LogTrace(const string message, ENUM_LOG_LEVEL level, ENUM_LOG_CHANNEL channel,
              const string signalID = "")
{
    if(!LogGov_ShouldEmit(level, channel, message, signalID))
        return false;

    Print(message);
    LogGov_Record(level, message, signalID);
    return true;
}

//+------------------------------------------------------------------+
//| LogTrace — Simplified log API (channel defaults to SYSTEM)     |
//+------------------------------------------------------------------+
bool LogTrace(const string message, ENUM_LOG_LEVEL level)
{
    return LogTrace(message, level, LOG_CHANNEL_SYSTEM, "");
}

//+------------------------------------------------------------------+
//| LogTrace — Simplified with signalID                             |
//+------------------------------------------------------------------+
bool LogTrace(const string message, ENUM_LOG_LEVEL level, const string signalID)
{
    return LogTrace(message, level, LOG_CHANNEL_SYSTEM, signalID);
}

//+------------------------------------------------------------------+
//| ShouldLog — Query if a log would be emitted (no emission)        |
//|                                                                  |
//| Use this to conditionally execute expensive string building.    |
//+------------------------------------------------------------------+
bool ShouldLog(ENUM_LOG_LEVEL level, ENUM_LOG_CHANNEL channel)
{
    return LogGov_ShouldEmit(level, channel, "", "");
}

//+------------------------------------------------------------------+
//| ShouldLog — Simplified query                                     |
//+------------------------------------------------------------------+
bool ShouldLog(ENUM_LOG_LEVEL level)
{
    return ShouldLog(level, LOG_CHANNEL_SYSTEM);
}

//+------------------------------------------------------------------+
//| RegisterLogEvent — Log a structured event                        |
//|                                                                  |
//| Parameters:                                                     |
//|   event    — SLogEvent with all fields populated               |
//|   signalID — optional signal ID for deduplication              |
//|                                                                  |
//| Returns: true if logged, false if dropped                       |
//+------------------------------------------------------------------+
bool RegisterLogEvent(SLogEvent &event, const string signalID = "")
{
    ENUM_LOG_LEVEL severity = LOG_LEVEL_INFO;
    if(event.eventType == LOG_EVENT_ERROR || event.eventType == LOG_EVENT_RISK_CHECK)
        severity = LOG_LEVEL_WARN;
    
    if(!LogGov_ShouldEmit(severity, event.channel, event.message, signalID))
        return false;

    Print(event.ToString());
    LogGov_Record(severity, event.message, signalID);
    return true;
}

//+------------------------------------------------------------------+
//| FlushLogBuffer — Flush pending events at end of bar/session      |
//|                                                                  |
//| Call this on bar close to dump accumulated events.             |
//+------------------------------------------------------------------+
void FlushLogBuffer()
{
    // Per-bar control auto-resets, but we can log stats if needed
    string stats = LogGov_GetStats();
    Print("[LOG] Flush: ", stats);
}

//+------------------------------------------------------------------+
//| Backwards compatibility aliases                                  |
//+------------------------------------------------------------------+
// All existing APIs preserved - see macros above (lines 94-101)

#endif // OMAK_LOGGOVERNOR_MQH