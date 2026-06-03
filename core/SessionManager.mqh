//+------------------------------------------------------------------+
//| SessionManager.mqh                                               |
//|: Session awareness, weekend detection, trading hours     |
//| Part of Omak FxYO — Universal Market Settings                    |
//+------------------------------------------------------------------+
#property strict

#include <OmakFxYO/core/MarketTypeDetector.mqh>
#include <OmakFxYO/core/HolidayCalendar.mqh>
#include <OmakFxYO/core/LogGovernor.mqh>         // Unified logging with governance

//+------------------------------------------------------------------+
//| Session Status Structure                                         |
//+------------------------------------------------------------------+
/**
 * SSessionStatus
 *
 * Holds the current session state and trading permission flags.
 * Updated each tick by UpdateSessionStatus().
 */
struct SSessionStatus
{
   bool              isTradingAllowed;     // Can we trade right now?
   bool              isWeekend;            // Is it weekend?
   bool              isHoliday;            // Is it a holiday?
   bool              isGapPeriod;          // Just opened (gap risk)
   int               minutesSinceOpen;     // Minutes since session open
   int               minutesToClose;       // Minutes until session close
   string            statusMessage;        // Human-readable status
};

//+------------------------------------------------------------------+
//| Global session manager state                                     |
//+------------------------------------------------------------------+
SMarketProfile  g_marketProfile;
SSessionStatus  g_sessionStatus;

// State-change tracking for throttled logging
static bool        s_prevGapState = false;
static string      s_lastLoggedSessionState = "";
static datetime    s_lastSessionLogTime = 0;

// Configurable trace interval (seconds) — default 300 (5 minutes)
// Set via SetSessionTraceInterval() from main EA if needed
static int s_sessionTraceIntervalSeconds = 300;

//+------------------------------------------------------------------+
//| SetSessionTraceInterval — Configure periodic logging interval    |
//+------------------------------------------------------------------+
void SetSessionTraceInterval(int seconds)
{
    if(seconds > 0)
        s_sessionTraceIntervalSeconds = seconds;
}

//+------------------------------------------------------------------+
//| InitSessionManager — Initialize with symbol profile              |
//+------------------------------------------------------------------+
/**
 * InitSessionManager
 *
 * Call from OnInit(). Detects the market profile for the given
 * symbol and initializes the session status.
 */
void InitSessionManager(string symbol)
{
    g_marketProfile = GetMarketProfile(symbol);
    UpdateSessionStatus();

    // Initialize tracking state
    s_lastLoggedSessionState = "";
    s_lastSessionLogTime = 0;
}

//+------------------------------------------------------------------+
//| UpdateSessionStatus — Refresh session state (call in OnTick)     |
//+------------------------------------------------------------------+
/**
 * UpdateSessionStatus
 *
 * Evaluates current time against market profile and holiday calendar
 * to determine if trading is allowed.
 *
 * Call this at the very beginning of OnTick(), before any pipeline
 * evaluation or trade logic.
 */
void UpdateSessionStatus()
{
    datetime now = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(now, dt);

    int currentHour = dt.hour;
    int currentMin = dt.min;
    int currentDay = dt.day_of_week;  // 0=Sunday, 5=Friday, 6=Saturday

    // Reset status
    g_sessionStatus.isTradingAllowed = true;
    g_sessionStatus.isWeekend = false;
    g_sessionStatus.isHoliday = false;
    g_sessionStatus.isGapPeriod = false;
    g_sessionStatus.minutesSinceOpen = 0;
    g_sessionStatus.minutesToClose = 0;
    g_sessionStatus.statusMessage = "Trading allowed";

    // --- Weekend detection ---
    // Friday after cutoff hour
    bool fridayCutoff = (currentDay == 5 && currentHour >= 16); // Default 16:00
    // Saturday (all day)
    bool saturday = (currentDay == 6);
    // Sunday before market open (before 22:00 server time)
    bool sundayBeforeOpen = (currentDay == 0 && currentHour < 22);

    g_sessionStatus.isWeekend = fridayCutoff || saturday || sundayBeforeOpen;

    // For 24/7 markets, weekend is always false
    if(g_marketProfile.is24Hour)
    {
       g_sessionStatus.isWeekend = false;
    }

    // --- Holiday detection ---
    g_sessionStatus.isHoliday = IsMarketHoliday(now, g_marketProfile.type);

    // --- Gap period detection ---
    // Sunday 22:00 open → gap period for first N minutes
    if(currentDay == 0 && currentHour == 22)
    {
       // Monday start delay (configurable via input, default 30 min)
       g_sessionStatus.isGapPeriod = (currentMin < 30);
    }
    else if(currentDay >= 1 && currentDay <= 4) // Mon-Thu
    {
       // First 5 minutes of session open
       g_sessionStatus.isGapPeriod = (currentHour == g_marketProfile.sessionOpenHour &&
                                      currentMin < 5);
    }
    else
    {
       g_sessionStatus.isGapPeriod = false;
    }

    // --- STEP 2 & 3: Trace GAP entry/exit based on state transition ---
    bool currentGapState = g_sessionStatus.isGapPeriod;
    if(currentGapState && !s_prevGapState)
    {
        // GAP ENTRY — use LogTrace for consistency
        LogTrace("[SESSION_EVENT] ENTER_GAP Time=" + TimeToString(TimeCurrent()), LOG_LEVEL_INFO, LOG_CHANNEL_SYSTEM);
    }
    else if(!currentGapState && s_prevGapState)
    {
        // GAP EXIT — trace the condition that caused exit
        // Determine which exit condition was met
        string exitCondition = "Unknown";
        if(currentDay == 0 && currentHour == 22)
        {
            exitCondition = "Sunday22_Exit: currentMin>=" + IntegerToString(currentMin);
        }
        else if(currentDay >= 1 && currentDay <= 4)
        {
            if(currentHour == g_marketProfile.sessionOpenHour)
            {
                exitCondition = "Open5min_Exit: currentMin>=" + IntegerToString(currentMin);
            }
            else if(currentHour > g_marketProfile.sessionOpenHour)
            {
                exitCondition = "PostOpen: hour>openHour";
            }
            else
            {
                exitCondition = "PreOpen: hour<openHour";
            }
        }
        else
        {
            exitCondition = "Non-trading-day: day=" + IntegerToString(currentDay);
        }

        LogTrace("[SESSION_CHECK] "
            + "GapCondition=FALSE"
            + " | Time=" + TimeToString(TimeCurrent())
            + " | Reason=" + exitCondition,
            LOG_LEVEL_INFO, LOG_CHANNEL_SYSTEM
        );
    }

     // Update previous state for next tick
     s_prevGapState = currentGapState;

     // --- Periodic + state-change session logging via LogGovernor ---
     // Throttled to avoid log spam; logs only on transitions or interval expiry
     string currentSessionState = g_sessionStatus.isGapPeriod ? "GAP" :
                                   g_sessionStatus.isWeekend ? "WEEKEND" :
                                   g_sessionStatus.isHoliday ? "HOLIDAY" :
                                   g_sessionStatus.isTradingAllowed ? "ACTIVE" : "BLOCKED";

     // 'now' already declared at function top (line 89) — reuse it
     bool timeToLog = (now - s_lastSessionLogTime) >= s_sessionTraceIntervalSeconds;
     bool stateChanged = (currentSessionState != s_lastLoggedSessionState);

     if(timeToLog || stateChanged)
     {
         LogTrace("[SESSION_STATE] Current=" + currentSessionState
                  + " | IsTrading=" + (g_sessionStatus.isTradingAllowed ? "TRUE" : "FALSE"),
                  LOG_LEVEL_INFO, LOG_CHANNEL_SYSTEM);
         s_lastLoggedSessionState = currentSessionState;
         s_lastSessionLogTime = now;
     }

    // --- Trading permission checks (priority order) ---

    // 1. Weekend trading disabled
    if(!g_sessionStatus.isWeekend && g_sessionStatus.isHoliday)
    {
       g_sessionStatus.isTradingAllowed = false;
       string hName = GetHolidayName(now, g_marketProfile.type);
       if(hName != "")
          g_sessionStatus.statusMessage = "Holiday (" + hName + ") — trading disabled";
       else
          g_sessionStatus.statusMessage = "Holiday — trading disabled";
    }
    // 2. Gap period — wait for stabilization
    else if(g_sessionStatus.isGapPeriod)
    {
       g_sessionStatus.isTradingAllowed = false;
       g_sessionStatus.statusMessage = "Gap period — waiting for stabilization";
    }
    // 3. Friday cutoff — weekend approaching
    else if(fridayCutoff)
    {
       g_sessionStatus.isTradingAllowed = false;
       g_sessionStatus.statusMessage = "Friday cutoff — weekend approaching";
    }

    // --- Throttled block reason logging (once per state change) ---
    // Log SESSION_BLOCK only when trading becomes disallowed AND state changes
    static bool s_prevTradingAllowed = true; // Assume initially allowed
    bool currentlyBlocked = !g_sessionStatus.isTradingAllowed;

    if(currentlyBlocked && s_prevTradingAllowed)
    {
        // Just became blocked — log the reason
        LogTrace("[SESSION_BLOCK] Reason=" + g_sessionStatus.statusMessage,
                 LOG_LEVEL_INFO, LOG_CHANNEL_SYSTEM);
    }

    s_prevTradingAllowed = g_sessionStatus.isTradingAllowed;

   // --- Calculate session timing ---
   if(g_marketProfile.sessionOpenHour < g_marketProfile.sessionCloseHour)
   {
      // Normal session (same day open and close)
      int openMinutes = g_marketProfile.sessionOpenHour * 60;
      int closeMinutes = g_marketProfile.sessionCloseHour * 60;
      int currentMinutes = currentHour * 60 + currentMin;

      if(currentMinutes >= openMinutes)
         g_sessionStatus.minutesSinceOpen = currentMinutes - openMinutes;
      if(currentMinutes < closeMinutes)
         g_sessionStatus.minutesToClose = closeMinutes - currentMinutes;
   }
   else
   {
      // Overnight session (e.g., 24/7 markets)
      g_sessionStatus.minutesSinceOpen = currentHour * 60 + currentMin;
      g_sessionStatus.minutesToClose = (24 * 60) - g_sessionStatus.minutesSinceOpen;
   }
}

//+------------------------------------------------------------------+
//| CanTradeNow — Quick check for trading permission                 |
//| DEAD: Never called in codebase — retained as forward declaration |
//+------------------------------------------------------------------+
// bool CanTradeNow() { return g_sessionStatus.isTradingAllowed; }

//+------------------------------------------------------------------+
//| GetSessionStatusMessage — Human-readable status                  |
//+------------------------------------------------------------------+
string GetSessionStatusMessage()
{
   return g_sessionStatus.statusMessage;
}

//+------------------------------------------------------------------+
//| GetMarketProfileRef — Return reference to current market profile |
//+------------------------------------------------------------------+
SMarketProfile GetMarketProfileRef()
{
   return g_marketProfile;
}
