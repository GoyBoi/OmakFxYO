//+------------------------------------------------------------------+
//|                                        FractalNarrative.mqh |
//|                        OmakFxYO — Shared Fractal Narrative Context |
//|                                                                  |
//| C2, C3, and C4 are closure-family events within a shared fractal |
//| narrative anchored by C1. Continuation validity is state-based,   |
//| not candle-adjacency-based.                                       |
//+------------------------------------------------------------------+
#ifndef OMAK_FRACTAL_NARRATIVE_MQH
#define OMAK_FRACTAL_NARRATIVE_MQH

#include <OmakFxYO/core/CoreTypes.mqh>
#include <OmakFxYO/core/LogGovernor.mqh>

//+------------------------------------------------------------------+
//| ENUM_CONTINUATION_WINDOW — State of the continuation opportunity |
//+------------------------------------------------------------------+
enum ENUM_CONTINUATION_WINDOW
{
   CW_CLOSED = 0,     // No window active
   CW_OPEN,            // Continuation window is open (C1 anchor active)
   CW_C2_ISSUED,       // C2 event has been detected within this window
   CW_C3_ISSUED,       // C3 event has been detected
   CW_C4_ISSUED,       // C4 event has been detected
   CW_EXPIRED          // Window timed out or invalidated
};

//+------------------------------------------------------------------+
//| SClosureEvent — A single closure-family event within a narrative |
//| Each event shares the same C1 anchor but has its own identity.   |
//+------------------------------------------------------------------+
struct SClosureEvent
{
   ulong              eventGUID;         // Unique ID for this event
   ENUM_CLOSURE_TYPE  eventType;         // CLOSURE_C2, CLOSURE_C3, or CLOSURE_C4
   ENUM_DIRECTION     direction;         // BUY or SELL
   datetime           detectionTime;     // When the event was detected
   datetime           barTime;           // Bar time of the event candle
   double             c2_high;           // Always references the C2 candle high
   double             c2_low;            // Always references the C2 candle low
   double             c2_open;           // C2 candle open
   double             c2_close;          // C2 candle close
   double             event_high;        // High of this event's candle
   double             event_low;         // Low of this event's candle
   double             event_open;        // Open of this event's candle
   double             event_close;       // Close of this event's candle
   double             entry_price;       // Broker-real entry price
   double             stop_loss;         // Protected swing = C2 extreme
   double             equilibrium;       // Derived from C1 range
   double             c2_wick_ratio;     // Wick ratio of the C2 candle
   double             event_wick_ratio;  // Wick ratio of this event's candle
   bool               cisdConfirmed;     // CISD confirmed at detection time
   bool               m_upgradedFromC2;  // True if this C3/C4 upgraded from C2 fallback
   SSequenceLineage   lineage;           // Sequence identity
   int                barsSinceC1;       // How many bars between C1 close and this event

   void Reset()
   {
      eventGUID = 0;
      eventType = CLOSURE_NONE;
      direction = DIRECTION_NONE;
      detectionTime = 0;
      barTime = 0;
      c2_high = 0.0;
      c2_low = 0.0;
      c2_open = 0.0;
      c2_close = 0.0;
      event_high = 0.0;
      event_low = 0.0;
      event_open = 0.0;
      event_close = 0.0;
      entry_price = 0.0;
      stop_loss = 0.0;
      equilibrium = 0.0;
      c2_wick_ratio = 0.0;
      event_wick_ratio = 0.0;
      cisdConfirmed = false;
      m_upgradedFromC2 = false;
      lineage.Reset();
      barsSinceC1 = 0;
   }
};

//+------------------------------------------------------------------+
//| SFractalNarrative — Shared narrative context                     |
//|                                                                  |
//| A fractal narrative is born when a C1 anchor is identified.      |
//| It lives until the continuation window closes (by invalidation,  |
//| timeout, or CRT target). Within the window, C2, C3, and C4       |
//| events can occur — not necessarily on adjacent candles.          |
//+------------------------------------------------------------------+
struct SFractalNarrative
{
   // --- Narrative identity ---
   ulong              narrativeGUID;     // Unique ID for this narrative session
   ENUM_EXECUTION_BRANCH branchId;       // Branch that spawned this narrative
   ENUM_DIRECTION     narrativeDirection; // Overall direction (BUY or SELL)

   // --- C1 Anchor (single source of truth for the narrative) ---
   datetime           c1_barTime;
   double             c1_high;
   double             c1_low;
   double             c1_open;
   double             c1_close;

   // --- Continuation window ---
   ENUM_CONTINUATION_WINDOW windowState;
   datetime           windowOpenTime;    // When the window was opened
   datetime           windowCloseTime;   // When the window was closed
   int                windowMaxBars;     // Max bars the window stays open
   int                barsElapsed;       // Bars elapsed since window opened
   string             windowCloseReason; // Why the window closed

   // --- Closure events within this narrative ---
   SClosureEvent      c2Event;           // Most recent C2 event (max 1 per narrative)
   SClosureEvent      c3Event;           // Most recent C3 event
   SClosureEvent      c4Event;           // Most recent C4 event
   int                c2EventCount;      // Total C2 events in this narrative
   int                c3EventCount;      // Total C3 events
   int                c4EventCount;      // Total C4 events

   // --- CISD state ---
   bool               cisdConfirmed;     // CISD confirmed within this narrative
   datetime           cisdTime;          // When CISD was confirmed
   ENUM_DIRECTION     cisdDirection;     // Direction of the CISD

   // --- Structural tracking ---
   double             protectedSwingHigh; // C2 high (bearish SL anchor)
   double             protectedSwingLow;  // C2 low (bullish SL anchor)
   bool               crtTargetHit;       // CRT full target achieved
   bool               isExpired;          // Narrative has expired
   bool               isComplete;         // Narrative is complete (no more events)

   // --- Deferred C2 continuation (wick-rejected but structure survives) ---
   bool               c2Deferred;          // C2 was wick-rejected but structure is still valid
   ulong              deferredC2Guid;      // GUID of the deferred C2 candidate
   double             deferredC2High;      // C2 high at deferred time
   double             deferredC2Low;       // C2 low at deferred time
   double             deferredC2Open;      // C2 open at deferred time
   double             deferredC2Close;     // C2 close at deferred time
   datetime           deferredC2Time;      // When the deferral was registered
   double             deferredC2WickRatio; // Wick ratio at deferral time

   // --- Private state ---
   bool               narrativeActive;   // True between creation and expiry

   void Reset()
   {
      narrativeGUID = 0;
      branchId = BRANCH_INTRADAY;
      narrativeDirection = DIRECTION_NONE;

      c1_barTime = 0;
      c1_high = 0.0;
      c1_low = 0.0;
      c1_open = 0.0;
      c1_close = 0.0;

      windowState = CW_CLOSED;
      windowOpenTime = 0;
      windowCloseTime = 0;
      windowMaxBars = 50;
      barsElapsed = 0;
      windowCloseReason = "";

      c2Event.Reset();
      c3Event.Reset();
      c4Event.Reset();
      c2EventCount = 0;
      c3EventCount = 0;
      c4EventCount = 0;

      cisdConfirmed = false;
      cisdTime = 0;
      cisdDirection = DIRECTION_NONE;

      protectedSwingHigh = 0.0;
      protectedSwingLow = 0.0;
      crtTargetHit = false;
      isExpired = false;
      isComplete = false;

      narrativeActive = false;

      // Deferred C2 fields
      c2Deferred = false;
      deferredC2Guid = 0;
      deferredC2High = 0.0;
      deferredC2Low = 0.0;
      deferredC2Open = 0.0;
      deferredC2Close = 0.0;
      deferredC2Time = 0;
      deferredC2WickRatio = 0.0;
   }

   //+------------------------------------------------------------------+
   //| Initialise — Create a new narrative from C1 anchor               |
   //+------------------------------------------------------------------+
   bool Initialise(
      ENUM_EXECUTION_BRANCH branch,
      ENUM_DIRECTION direction,
      double in_c1_high,
      double in_c1_low,
      double in_c1_open,
      double in_c1_close,
      datetime in_c1_barTime,
      int maxBars = 50
   )
   {
      Reset();
      narrativeGUID = (ulong)TimeCurrent() ^ (ulong)GetTickCount64();
      branchId = branch;
      narrativeDirection = direction;

      c1_high = in_c1_high;
      c1_low = in_c1_low;
      c1_open = in_c1_open;
      c1_close = in_c1_close;
      c1_barTime = in_c1_barTime;

      windowState = CW_OPEN;
      windowOpenTime = TimeCurrent();
      windowMaxBars = maxBars;
      barsElapsed = 0;
      narrativeActive = true;

      if(InpEnableTrace)
         LGovPrint("[FRACTAL_CTX_CREATED] GUID=" + IntegerToString(narrativeGUID) +
                   " | branch=" + IntegerToString(branch) +
                   " | dir=" + EnumToString(direction) +
                   " | c1_high=" + DoubleToString(c1_high, _Digits) +
                   " | c1_low=" + DoubleToString(c1_low, _Digits) +
                   " | c1_bar=" + TimeToString(c1_barTime), LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
      return true;
   }

   //+------------------------------------------------------------------+
   //| RegisterDeferredC2Candidate — Store wick-rejected C2 as deferred |
   //| continuation candidate. The narrative stays open for future C3/C4 |
   //| even though the C2 did not produce a lockable signal.             |
   //+------------------------------------------------------------------+
   bool RegisterDeferredC2Candidate(
      ulong c2Guid,
      double in_c2_high,
      double in_c2_low,
      double in_c2_open,
      double in_c2_close,
      double in_c2WickRatio
   )
   {
      if(!narrativeActive || isExpired)
         return false;
      if(c2EventCount >= 3 && c2Deferred)
         return false;

      c2Deferred = true;
      deferredC2Guid = c2Guid;
      deferredC2High = in_c2_high;
      deferredC2Low = in_c2_low;
      deferredC2Open = in_c2_open;
      deferredC2Close = in_c2_close;
      deferredC2Time = TimeCurrent();
      deferredC2WickRatio = in_c2WickRatio;

      // Keep window as CW_OPEN (not CW_C2_ISSUED) — the C2 was not locked
      if(windowState == CW_CLOSED || windowState == CW_EXPIRED)
         OpenContinuationWindow();

      if(InpEnableTrace)
         LGovPrint("[C2_DEFERRED] narrativeGUID=" + IntegerToString(narrativeGUID) +
                   " | deferredC2Guid=" + IntegerToString(c2Guid) +
                   " | wickRatio=" + DoubleToString(in_c2WickRatio * 100, 1) + "%" +
                   " | c2_high=" + DoubleToString(in_c2_high, _Digits) +
                   " | c2_low=" + DoubleToString(in_c2_low, _Digits),
                   LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
      return true;
   }

   //+------------------------------------------------------------------+
   //| IsWindowOpenOrDeferred — Check if window is active or has        |
   //| a deferred C2 candidate available for continuation               |
   //+------------------------------------------------------------------+
   bool IsWindowOpenOrDeferred() const
   {
      if(IsWindowOpen())
         return true;
      // Deferred continuation: window may be CLOSED but we have a deferred C2
      return (c2Deferred && !isExpired && narrativeActive);
   }

   //+------------------------------------------------------------------+
   //| ClearDeferredC2 — Clear the deferred C2 candidate flag          |
   //+------------------------------------------------------------------+
   void ClearDeferredC2()
   {
      c2Deferred = false;
      deferredC2Guid = 0;
      deferredC2High = 0.0;
      deferredC2Low = 0.0;
      deferredC2Open = 0.0;
      deferredC2Close = 0.0;
      deferredC2Time = 0;
      deferredC2WickRatio = 0.0;
   }

   //+------------------------------------------------------------------+
   //| OpenContinuationWindow — Re-open window after a C2 event         |
   //+------------------------------------------------------------------+
   void OpenContinuationWindow()
   {
      if(windowState == CW_CLOSED || windowState == CW_EXPIRED)
      {
         ENUM_CONTINUATION_WINDOW oldState = windowState;
         windowState = CW_OPEN;
         windowOpenTime = TimeCurrent();
         windowCloseTime = 0;
         barsElapsed = 0;
         if(oldState == CW_EXPIRED)
         {
            LGovPrint("[STATE_RECOVERED] CONTINUATION_WINDOW " + EnumToString(oldState) +
                      " -> OPEN | narrativeGUID=" + IntegerToString(narrativeGUID),
                      LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
         }
         else
         {
            LGovPrint("[STATE_TRANSITION_OK] CONTINUATION_WINDOW " + EnumToString(oldState) +
                      " -> OPEN | narrativeGUID=" + IntegerToString(narrativeGUID),
                      LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| CloseContinuationWindow — Close the window (no more events)      |
   //+------------------------------------------------------------------+
   void CloseContinuationWindow(string reason)
   {
      if(windowState != CW_CLOSED && windowState != CW_EXPIRED)
      {
         ENUM_CONTINUATION_WINDOW oldState = windowState;
         windowState = CW_CLOSED;
         windowCloseTime = TimeCurrent();
         windowCloseReason = reason;
         LGovPrint("[STATE_TRANSITION_OK] CONTINUATION_WINDOW " + EnumToString(oldState) +
                   " -> CLOSED | narrativeGUID=" + IntegerToString(narrativeGUID) +
                   " | reason=" + reason, LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
      }
   }

   //+------------------------------------------------------------------+
   //| IsWindowOpen — Check if continuation window is active            |
   //+------------------------------------------------------------------+
   bool IsWindowOpen() const
   {
      return (windowState == CW_OPEN ||
              windowState == CW_C2_ISSUED ||
              windowState == CW_C3_ISSUED);
   }

   //+------------------------------------------------------------------+
   //| RegisterC2Event — Record a C2 closure event in this narrative   |
   //+------------------------------------------------------------------+
   bool RegisterC2Event(const SClosureEvent &event)
   {
      if(!narrativeActive || isExpired)
      {
         LGovPrint("[STATE_ILLEGAL] CONTINUATION_WINDOW RegisterC2Event blocked — narrative inactive/expired | narrativeGUID=" + IntegerToString(narrativeGUID), LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
         return false;
      }
      if(c2EventCount >= 3)  // Max 3 C2 events per narrative
      {
         LGovPrint("[STATE_ILLEGAL] CONTINUATION_WINDOW RegisterC2Event blocked — max C2 events reached | narrativeGUID=" + IntegerToString(narrativeGUID), LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
         return false;
      }

      if(!IsWindowOpen())
      {
         LGovPrint("[STATE_ILLEGAL] CONTINUATION_WINDOW RegisterC2Event blocked — window not open | narrativeGUID=" + IntegerToString(narrativeGUID), LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
         return false;
      }

      ENUM_CONTINUATION_WINDOW oldState = windowState;
      c2Event = event;
      c2EventCount++;
      windowState = CW_C2_ISSUED;
      protectedSwingLow = event.c2_low;
      protectedSwingHigh = event.c2_high;

      LGovPrint("[STATE_TRANSITION_OK] CONTINUATION_WINDOW " + EnumToString(oldState) +
                " -> CW_C2_ISSUED | narrativeGUID=" + IntegerToString(narrativeGUID) +
                " | eventGUID=" + IntegerToString(event.eventGUID) +
                " | dir=" + EnumToString(event.direction) +
                " | totalC2=" + IntegerToString(c2EventCount),
                LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
      return true;
   }

   //+------------------------------------------------------------------+
   //| RegisterC3Event — Record a C3 continuation event                 |
   //| C3 does not require adjacency to C2. It only requires the        |
   //| continuation window to be open and CISD to be confirmed.         |
   //+------------------------------------------------------------------+
   bool RegisterC3Event(const SClosureEvent &event)
   {
      if(!narrativeActive || isExpired)
      {
         LGovPrint("[STATE_ILLEGAL] CONTINUATION_WINDOW RegisterC3Event blocked — narrative inactive/expired | narrativeGUID=" + IntegerToString(narrativeGUID), LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
         return false;
      }
      if(!IsWindowOpen())
      {
         LGovPrint("[STATE_ILLEGAL] CONTINUATION_WINDOW RegisterC3Event blocked — window not open | narrativeGUID=" + IntegerToString(narrativeGUID), LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
         return false;
      }
      if(c3EventCount >= 3)  // Max 3 C3 events per narrative
      {
         LGovPrint("[STATE_ILLEGAL] CONTINUATION_WINDOW RegisterC3Event blocked — max C3 events reached | narrativeGUID=" + IntegerToString(narrativeGUID), LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
         return false;
      }
      if(windowState != CW_OPEN && windowState != CW_C2_ISSUED)
      {
         LGovPrint("[STATE_ILLEGAL] CONTINUATION_WINDOW RegisterC3Event blocked — cannot transition from " + EnumToString(windowState) + " | narrativeGUID=" + IntegerToString(narrativeGUID), LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
         return false;
      }

      ENUM_CONTINUATION_WINDOW oldState = windowState;
      c3Event = event;
      c3EventCount++;
      windowState = CW_C3_ISSUED;

      LGovPrint("[STATE_TRANSITION_OK] CONTINUATION_WINDOW " + EnumToString(oldState) +
                " -> CW_C3_ISSUED | narrativeGUID=" + IntegerToString(narrativeGUID) +
                " | eventGUID=" + IntegerToString(event.eventGUID) +
                " | dir=" + EnumToString(event.direction) +
                " | cisdConfirmed=" + (event.cisdConfirmed ? "YES" : "NO") +
                " | totalC3=" + IntegerToString(c3EventCount),
                LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
      return true;
   }

   //+------------------------------------------------------------------+
   //| RegisterC4Event — Record a C4 continuation event                 |
   //| C4 is continuous trend expansion after C3 validation.            |
   //+------------------------------------------------------------------+
   bool RegisterC4Event(const SClosureEvent &event)
   {
      if(!narrativeActive || isExpired)
      {
         LGovPrint("[STATE_ILLEGAL] CONTINUATION_WINDOW RegisterC4Event blocked — narrative inactive/expired | narrativeGUID=" + IntegerToString(narrativeGUID), LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
         return false;
      }
      if(!IsWindowOpen())
      {
         LGovPrint("[STATE_ILLEGAL] CONTINUATION_WINDOW RegisterC4Event blocked — window not open | narrativeGUID=" + IntegerToString(narrativeGUID), LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
         return false;
      }
      // C4 requires C3 — C4 is an expansion event within a C3 narrative
      if(c3EventCount == 0 && c4EventCount == 0)
      {
         LGovPrint("[STATE_ILLEGAL] CONTINUATION_WINDOW RegisterC4Event blocked — no C3 | narrativeGUID=" + IntegerToString(narrativeGUID), LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
         return false;
      }
      if(c4EventCount >= 3)  // Max 3 C4 events per narrative
      {
         LGovPrint("[STATE_ILLEGAL] CONTINUATION_WINDOW RegisterC4Event blocked — max C4 events reached | narrativeGUID=" + IntegerToString(narrativeGUID), LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
         return false;
      }
      if(windowState != CW_C3_ISSUED)
      {
         LGovPrint("[STATE_ILLEGAL] CONTINUATION_WINDOW RegisterC4Event blocked — invalid transition from " + EnumToString(windowState) + " | narrativeGUID=" + IntegerToString(narrativeGUID), LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
         return false;
      }

      ENUM_CONTINUATION_WINDOW oldState = windowState;
      c4Event = event;
      c4EventCount++;
      windowState = CW_C4_ISSUED;

      LGovPrint("[STATE_TRANSITION_OK] CONTINUATION_WINDOW " + EnumToString(oldState) +
                " -> CW_C4_ISSUED | narrativeGUID=" + IntegerToString(narrativeGUID) +
                " | eventGUID=" + IntegerToString(event.eventGUID) +
                " | dir=" + EnumToString(event.direction) +
                " | totalC4=" + IntegerToString(c4EventCount),
                LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
      return true;
   }

   //+------------------------------------------------------------------+
   //| SetCISD — Record CISD confirmation for this narrative            |
   //+------------------------------------------------------------------+
   void SetCISD(ENUM_DIRECTION dir)
   {
      cisdConfirmed = true;
      cisdTime = TimeCurrent();
      cisdDirection = dir;
      if(InpEnableTrace)
         LGovPrint("[CISD_CONFIRMATION] narrativeGUID=" + IntegerToString(narrativeGUID) +
                   " | dir=" + EnumToString(dir), LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
   }

   //+------------------------------------------------------------------+
   //| Expire — Mark the narrative as expired                           |
   //+------------------------------------------------------------------+
   void Expire(string reason)
   {
      if(isExpired)
      {
         LGovPrint("[STATE_ILLEGAL] CONTINUATION_WINDOW Expire blocked — already expired | narrativeGUID=" + IntegerToString(narrativeGUID), LOG_LEVEL_WARN, LOG_CHANNEL_SIGNAL);
         return;
      }
      ENUM_CONTINUATION_WINDOW oldWindowState = windowState;
      isExpired = true;
      narrativeActive = false;
      windowState = CW_EXPIRED;
      windowCloseTime = TimeCurrent();
      windowCloseReason = reason;
      LGovPrint("[STATE_TRANSITION_OK] CONTINUATION_WINDOW " + EnumToString(oldWindowState) +
                " -> CW_EXPIRED | narrativeGUID=" + IntegerToString(narrativeGUID) +
                " | reason=" + reason, LOG_LEVEL_INFO, LOG_CHANNEL_SIGNAL);
   }

   //+------------------------------------------------------------------+
   //| UpdateBarsElapsed — Call every bar to track window age           |
   //+------------------------------------------------------------------+
   void UpdateBarsElapsed(int barsSinceAnchor)
   {
      barsElapsed = barsSinceAnchor;
      if(windowMaxBars > 0 && barsElapsed > windowMaxBars)
         CloseContinuationWindow("max_bars_elapsed");
   }

   //+------------------------------------------------------------------+
   //| BuildClosureEvent — Factory: build SClosureEvent from raw data   |
   //+------------------------------------------------------------------+
   static SClosureEvent BuildEvent(
      ENUM_CLOSURE_TYPE eventType,
      ENUM_DIRECTION dir,
      double in_c2_high,
      double in_c2_low,
      double in_c2_open,
      double in_c2_close,
      double in_event_high,
      double in_event_low,
      double in_event_open,
      double in_event_close,
      double in_entry_price,
      double in_stop_loss,
      double in_c2_wick_ratio,
      double in_event_wick_ratio,
      bool in_cisdConfirmed,
      bool in_upgradedFromC2,
      int in_barsSinceC1,
      const SSequenceLineage &in_lineage
   )
   {
      SClosureEvent event;
      event.Reset();
      event.eventGUID = (ulong)TimeCurrent() ^ (ulong)GetTickCount64();
      event.eventType = eventType;
      event.direction = dir;
      event.detectionTime = TimeCurrent();
      event.c2_high = in_c2_high;
      event.c2_low = in_c2_low;
      event.c2_open = in_c2_open;
      event.c2_close = in_c2_close;
      event.event_high = in_event_high;
      event.event_low = in_event_low;
      event.event_open = in_event_open;
      event.event_close = in_event_close;
      event.entry_price = in_entry_price;
      event.stop_loss = in_stop_loss;
      event.c2_wick_ratio = in_c2_wick_ratio;
      event.event_wick_ratio = in_event_wick_ratio;
      event.cisdConfirmed = in_cisdConfirmed;
      event.m_upgradedFromC2 = in_upgradedFromC2;
      event.barsSinceC1 = in_barsSinceC1;
      event.lineage = in_lineage;
      return event;
   }
};

//+------------------------------------------------------------------+
//| Global narrative array (per-branch)                              |
//+------------------------------------------------------------------+
#define MAX_NARRATIVES_PER_BRANCH 3

// Note: g_branchANarratives and g_branchBNarratives are defined in BranchEvaluator.mqh

//+------------------------------------------------------------------+
//| FN_FindActiveNarrative — Find the active narrative for a branch  |
//+------------------------------------------------------------------+
int FN_FindActiveNarrative(SFractalNarrative &narratives[], ENUM_EXECUTION_BRANCH branch)
{
   for(int i = 0; i < ArraySize(narratives); i++)
   {
      if(narratives[i].narrativeActive && narratives[i].branchId == branch && !narratives[i].isExpired)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| FN_FindOrCreateNarrative — Find active or create new narrative   |
//+------------------------------------------------------------------+
int FN_FindOrCreateNarrative(
   SFractalNarrative &narratives[],
   ENUM_EXECUTION_BRANCH branch,
   ENUM_DIRECTION direction,
   double c1_high,
   double c1_low,
   double c1_open,
   double c1_close,
   datetime c1_barTime
)
{
   int idx = FN_FindActiveNarrative(narratives, branch);
   if(idx >= 0)
      return idx;

   // Create new narrative
   for(int i = 0; i < ArraySize(narratives); i++)
   {
      if(!narratives[i].narrativeActive || narratives[i].isExpired)
      {
         narratives[i].Initialise(branch, direction, c1_high, c1_low, c1_open, c1_close, c1_barTime);
         return i;
      }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| FN_CloseNarrative — Expire a narrative by index                  |
//+------------------------------------------------------------------+
void FN_CloseNarrative(SFractalNarrative &narratives[], int idx, string reason)
{
   if(idx >= 0 && idx < ArraySize(narratives))
   {
      narratives[idx].Expire(reason);
   }
}

//+------------------------------------------------------------------+
//| FN_GetActiveNarrativeCount — Count active narratives             |
//+------------------------------------------------------------------+
int FN_GetActiveNarrativeCount(SFractalNarrative &narratives[])
{
   int count = 0;
   for(int i = 0; i < ArraySize(narratives); i++)
   {
      if(narratives[i].narrativeActive && !narratives[i].isExpired)
         count++;
   }
   return count;
}

// REGRESSION_GUARD_V52.5_FRACTAL_NARRATIVE

#endif // OMAK_FRACTAL_NARRATIVE_MQH
