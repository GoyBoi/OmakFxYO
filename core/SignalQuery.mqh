//+------------------------------------------------------------------+
 //|                                              SignalQuery.mqh |
 //|                                    Signal Query Interface Layer |
 //+------------------------------------------------------------------+
 #ifndef OMAK_SIGNALQUERY_MQH
 #define OMAK_SIGNALQUERY_MQH
 
 #property strict
 #property copyright "OMAK"
 #property version   "1.00"
 #property description "Signal Query Interface — Isolated from Main EA"
 
#include <OmakFxYO/core/CoreTypes.mqh>

//+------------------------------------------------------------------+
 //| Constants (must match main EA)                                  |
 //+------------------------------------------------------------------+
 // MAX_TOTAL_SIGNALS_PER_BRANCH, MAX_C2_SIGNALS_PER_BRANCH, MAX_C3_SIGNALS_PER_BRANCH
 // MAX_TOTAL_SIGNALS_PER_BRANCH defined in CoreTypes.mqh

//+------------------------------------------------------------------+
  //| Extern declarations — globals from main EA                       |
  //+------------------------------------------------------------------+
  struct SLockedSignal; // forward only — full definition in LockedSignal.mqh
 
   extern bool g_hasActiveSignal[];
   extern SLockedSignal g_activeSignal[];
 
  int GetSignalStoreIndex(ENUM_EXECUTION_BRANCH branch, ENUM_CLOSURE_TYPE closureType = CLOSURE_NONE);
  int GetMaxSignalsForClosureType(ENUM_CLOSURE_TYPE closureType);

 //+------------------------------------------------------------------+
 //| QUERY: Check if signal with closure type exists in branch               |
 //+------------------------------------------------------------------+
 // NOTE: This function must be called AFTER g_activeSignal[] is initialized
 // Use only from engines that run after main EA init
bool SQ_HasSignalType(ENUM_EXECUTION_BRANCH branch, ENUM_CLOSURE_TYPE closureType)
{
   int baseIdx = (branch == BRANCH_INTRADAY) ? 0 : MAX_TOTAL_SIGNALS_PER_BRANCH;
   for(int i = 0; i < MAX_TOTAL_SIGNALS_PER_BRANCH; i++)
   {
      if(g_hasActiveSignal[baseIdx + i])
      {
         if(g_activeSignal[baseIdx + i].closureType == closureType)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
 //| QUERY: Find signal slot by GUID + closure type                      |
 //+------------------------------------------------------------------+
 // Updated to search all C2/C3 slots
 int SQ_FindSignalSlot(ENUM_EXECUTION_BRANCH branch, ulong guid, ENUM_CLOSURE_TYPE closureType)
 {
    int branchBase = (branch == BRANCH_INTRADAY) ? 0 : MAX_TOTAL_SIGNALS_PER_BRANCH;
    // Search all slots (C2 + C3)
    for(int i = 0; i < MAX_TOTAL_SIGNALS_PER_BRANCH; i++)
    {
       int idx = branchBase + i;
       if(g_hasActiveSignal[idx] && g_activeSignal[idx].m_guid == guid)
          return idx;
    }
    return -1;
 }

 //+------------------------------------------------------------------+
 //| QUERY: Count active signals in branch                        |
 //+------------------------------------------------------------------+
 int SQ_CountSignals(ENUM_EXECUTION_BRANCH branch, ENUM_CLOSURE_TYPE closureType = CLOSURE_NONE)
 {
    // Updated to count C2 and C3 separately
    int branchBase = (branch == BRANCH_INTRADAY) ? 0 : MAX_TOTAL_SIGNALS_PER_BRANCH;
    int count = 0;
    int maxSlots = (closureType == CLOSURE_NONE) ? MAX_TOTAL_SIGNALS_PER_BRANCH :
                   GetMaxSignalsForClosureType(closureType);
    int baseIdx = (closureType == CLOSURE_NONE) ? branchBase :
                  GetSignalStoreIndex(branch, closureType);
    for(int i = 0; i < maxSlots; i++)
    {
       if(g_hasActiveSignal[baseIdx + i])
          count++;
    }
    return count;
 }

 //+------------------------------------------------------------------+
 //| QUERY: Find first available slot                           |
 //+------------------------------------------------------------------+
 int SQ_FindAvailableSlot(ENUM_EXECUTION_BRANCH branch, ENUM_CLOSURE_TYPE closureType = CLOSURE_NONE)
 {
    // Updated to work with C2/C3 separation
    int baseIdx = GetSignalStoreIndex(branch, closureType);
    int maxSlots = GetMaxSignalsForClosureType(closureType);
    for(int i = 0; i < maxSlots; i++)
   {
      if(!g_hasActiveSignal[baseIdx + i])
         return baseIdx + i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| INVALIDATE: Full cleanup of signal GUID from context + store      |
//| FIX B: Prevent stuck GUID recycling                              |
//+------------------------------------------------------------------+
 bool SQ_InvalidateSignal(ulong guid, ENUM_EXECUTION_BRANCH branch)
{
   int slot = SQ_FindSignalSlot(branch, guid, CLOSURE_NONE);
   if(slot >= 0)
   {
      g_hasActiveSignal[slot] = false;
      g_activeSignal[slot].Reset();
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| GetC2ExtremesForSignal — Retrieve C2 protected swing extremes    |
//| from the active signal store by GUID. Used as defensive fallback |
//| when stop_loss is missing at the Risk Gate for C3 signals.       |
//+------------------------------------------------------------------+
bool GetC2ExtremesForSignal(ulong guid, double &c2_low, double &c2_high)
{
   if(guid == 0)
      return false;

   for(int b = 0; b < 2; b++)
   {
      ENUM_EXECUTION_BRANCH branch = (b == 0) ? BRANCH_INTRADAY : BRANCH_SWING;
      int slot = SQ_FindSignalSlot(branch, guid, CLOSURE_NONE);
      if(slot >= 0)
      {
         c2_low = g_activeSignal[slot].c2_low;
         c2_high = g_activeSignal[slot].c2_high;
         if(c2_low > 0.0 || c2_high > 0.0)
            return true;
      }
   }
   return false;
}

#endif // OMAK_SIGNALQUERY_MQH