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


  int GetSignalStoreIndex(ENUM_EXECUTION_BRANCH branch, ENUM_CLOSURE_TYPE closureType = CLOSURE_NONE);
  int GetMaxSignalsForClosureType(ENUM_CLOSURE_TYPE closureType);

 //+------------------------------------------------------------------+
 //| QUERY: Check if signal with closure type exists in branch               |
 //+------------------------------------------------------------------+
 // NOTE: This function must be called AFTER g_activeSignal[] is initialized
 // Use only from engines that run after main EA init
bool SQ_HasSignalType(ENUM_EXECUTION_BRANCH branch, ENUM_CLOSURE_TYPE closureType)
{
   if(closureType == CLOSURE_C2)
   {
      int baseIdx = (branch == BRANCH_INTRADAY) ? 0 : MAX_C2_SIGNALS_PER_BRANCH;
      for(int i = baseIdx; i < baseIdx + MAX_C2_SIGNALS_PER_BRANCH; i++)
      {
         if(g_activeC2[i].m_guid != 0 && g_activeC2[i].closureType == closureType)
            return true;
      }
   }
   else if(closureType == CLOSURE_C3 || closureType == CLOSURE_C4)
   {
      int baseIdx = (branch == BRANCH_INTRADAY) ? 0 : MAX_C3_SIGNALS_PER_BRANCH;
      for(int i = baseIdx; i < baseIdx + MAX_C3_SIGNALS_PER_BRANCH; i++)
      {
         if(g_activeC3[i].m_guid != 0 && g_activeC3[i].closureType == closureType)
            return true;
      }
   }
   else
   {
      int c2base = (branch == BRANCH_INTRADAY) ? 0 : MAX_C2_SIGNALS_PER_BRANCH;
      int c3base = (branch == BRANCH_INTRADAY) ? 0 : MAX_C3_SIGNALS_PER_BRANCH;
      for(int i = c2base; i < c2base + MAX_C2_SIGNALS_PER_BRANCH; i++)
      {
         if(g_activeC2[i].m_guid != 0 && g_activeC2[i].closureType == closureType)
            return true;
      }
      for(int i = c3base; i < c3base + MAX_C3_SIGNALS_PER_BRANCH; i++)
      {
         if(g_activeC3[i].m_guid != 0 && g_activeC3[i].closureType == closureType)
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
    int c2base = (branch == BRANCH_INTRADAY) ? 0 : MAX_C2_SIGNALS_PER_BRANCH;
    int c3base = (branch == BRANCH_INTRADAY) ? 0 : MAX_C3_SIGNALS_PER_BRANCH;
    if(closureType == CLOSURE_C2)
    {
       for(int i = c2base; i < c2base + MAX_C2_SIGNALS_PER_BRANCH; i++)
       {
          if(g_activeC2[i].m_guid == guid) return i;
       }
    }
    else if(closureType == CLOSURE_C3 || closureType == CLOSURE_C4)
    {
       for(int i = c3base; i < c3base + MAX_C3_SIGNALS_PER_BRANCH; i++)
       {
          if(g_activeC3[i].m_guid == guid) return i;
       }
    }
    else
    {
       for(int i = c2base; i < c2base + MAX_C2_SIGNALS_PER_BRANCH; i++)
       {
          if(g_activeC2[i].m_guid == guid) return i;
       }
       for(int i = c3base; i < c3base + MAX_C3_SIGNALS_PER_BRANCH; i++)
       {
          if(g_activeC3[i].m_guid == guid) return i;
       }
    }
    return -1;
 }

 //+------------------------------------------------------------------+
 //| QUERY: Count active signals in branch                        |
 //+------------------------------------------------------------------+
 int SQ_CountSignals(ENUM_EXECUTION_BRANCH branch, ENUM_CLOSURE_TYPE closureType = CLOSURE_NONE)
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
 //| QUERY: Find first available slot                           |
 //+------------------------------------------------------------------+
 int SQ_FindAvailableSlot(ENUM_EXECUTION_BRANCH branch, ENUM_CLOSURE_TYPE closureType = CLOSURE_NONE)
 {
    if(closureType == CLOSURE_C2)
    {
       int baseIdx = GetSignalStoreIndex(branch, CLOSURE_C2);
       for(int i = 0; i < MAX_C2_SIGNALS_PER_BRANCH; i++)
       {
          if(g_activeC2[baseIdx + i].m_guid == 0 || g_activeC2[baseIdx + i].stage == STAGE_NONE)
             return baseIdx + i;
       }
    }
    else if(closureType == CLOSURE_C3 || closureType == CLOSURE_C4)
    {
       int baseIdx = GetSignalStoreIndex(branch, CLOSURE_C3);
       for(int i = 0; i < MAX_C3_SIGNALS_PER_BRANCH; i++)
       {
          if(g_activeC3[baseIdx + i].m_guid == 0 || g_activeC3[baseIdx + i].stage == STAGE_NONE)
             return baseIdx + i;
       }
    }
    else
    {
       int c2base = GetSignalStoreIndex(branch, CLOSURE_C2);
       for(int i = 0; i < MAX_C2_SIGNALS_PER_BRANCH; i++)
       {
          if(g_activeC2[c2base + i].m_guid == 0 || g_activeC2[c2base + i].stage == STAGE_NONE)
             return c2base + i;
       }
       int c3base = GetSignalStoreIndex(branch, CLOSURE_C3);
       for(int i = 0; i < MAX_C3_SIGNALS_PER_BRANCH; i++)
       {
          if(g_activeC3[c3base + i].m_guid == 0 || g_activeC3[c3base + i].stage == STAGE_NONE)
             return c3base + i;
       }
    }
   return -1;
 }

//+------------------------------------------------------------------+
//| INVALIDATE: Full cleanup of signal GUID from context + store      |
//| FIX B: Prevent stuck GUID recycling                              |
//+------------------------------------------------------------------+
 bool SQ_InvalidateSignal(ulong guid, ENUM_EXECUTION_BRANCH branch)
{
   int c2base = GetSignalStoreIndex(branch, CLOSURE_C2);
   int c3base = GetSignalStoreIndex(branch, CLOSURE_C3);
   for(int i = c2base; i < c2base + MAX_C2_SIGNALS_PER_BRANCH; i++)
   {
      if(g_activeC2[i].m_guid == guid)
      {
         g_activeC2[i].Reset();
         return true;
      }
   }
   for(int i = c3base; i < c3base + MAX_C3_SIGNALS_PER_BRANCH; i++)
   {
      if(g_activeC3[i].m_guid == guid)
      {
         g_activeC3[i].Reset();
         return true;
      }
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
         int c2base = (branch == BRANCH_INTRADAY) ? 0 : MAX_C2_SIGNALS_PER_BRANCH;
         int c3base = (branch == BRANCH_INTRADAY) ? 0 : MAX_C3_SIGNALS_PER_BRANCH;
         bool inC2Range = (slot >= c2base && slot < c2base + MAX_C2_SIGNALS_PER_BRANCH);
         int poolIdx = inC2Range ? slot : slot - c2base;
         c2_low = inC2Range ? g_activeC2[poolIdx].c2_low : g_activeC3[poolIdx].c2_low;
         c2_high = inC2Range ? g_activeC2[poolIdx].c2_high : g_activeC3[poolIdx].c2_high;
         if(c2_low > 0.0 || c2_high > 0.0)
            return true;
      }
   }
   return false;
}

#endif // OMAK_SIGNALQUERY_MQH