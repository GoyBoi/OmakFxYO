//+------------------------------------------------------------------+
//|                                        ClosureState.mqh         |
//|                                              State Structs Only  |
//+------------------------------------------------------------------+
#ifndef OMAK_CLOSURESTATE_MQH
#define OMAK_CLOSURESTATE_MQH

// Forward declarations - these types are defined in CoreTypes.mqh
// ENUM_SIGNAL_STAGE and SLineage are available when this file is included by LockedSignal.mqh

//+------------------------------------------------------------------+
//| SC2State — Per-branch C2 signal state                           |
//+------------------------------------------------------------------+
struct SC2State
{
   bool isNew;
   bool didC2Sweep;
   datetime lastC2Time;
   ulong lastC2GUID;
   ENUM_SIGNAL_STAGE stage;
   double c2EntryPrice;
   bool hasSignal;
   bool valid;
   SLineage lineage;
   bool deferredActive;
   ulong deferredC2Guid;
   datetime deferredTime;
};

//+------------------------------------------------------------------+
//| SC3State — Per-branch C3 signal state                            |
//| C3 is always active                                              |
//+------------------------------------------------------------------+
struct SC3State
{
    bool isNew;
    bool didC3Sweep;
    datetime lastC3Time;
    ulong lastC3GUID;
    ENUM_SIGNAL_STAGE stage;
    double c3EntryPrice;
    bool hasSignal;
    bool valid;
    SLineage lineage;
};

//+------------------------------------------------------------------+
//| SC4State — Per-branch C4 continuation state                      |
//+------------------------------------------------------------------+
struct SC4State
{
    bool isNew;
    bool didC4Expand;        // True if C4 shows continuous expansion
    datetime lastC4Time;
    ulong lastC4GUID;
    ulong parentC3GUID;      // Parent C3 signal that validated this C4
    ENUM_SIGNAL_STAGE stage;
    double c4EntryPrice;
    double c4High;            // C4 candle high
    double c4Low;             // C4 candle low
    double c4Open;
    double c4Close;
    double c4WickRatio;
    bool hasSignal;
    bool valid;
    double c2_high;           // Protected swing reference
    double c2_low;            // Protected swing reference
    SLineage lineage;
    bool m_upgradedFromC3;    // True if this C4 upgraded from C3
    double c4_high;           // Alias for c4High (protected swing reference storage)
    double c4_low;            // Alias for c4Low (protected swing reference storage)
    double c4_close;          // Alias for c4Close
};

//+------------------------------------------------------------------+
//| SC2State Methods                                                  |
//+------------------------------------------------------------------+
void SC2StateReset(SC2State &s)
{
    s.isNew = false;
    s.didC2Sweep = false;
    s.lastC2Time = 0;
    s.lastC2GUID = 0;
    s.stage = STAGE_NONE;
    s.c2EntryPrice = 0.0;
    s.hasSignal = false;
    s.valid = false;
    s.lineage.sequenceId = 0;
    s.lineage.parentGuid = 0;
    s.lineage.requiresContinuation = false;
    s.deferredActive = false;
    s.deferredC2Guid = 0;
    s.deferredTime = 0;
}

bool SC2StateIsActive(const SC2State &s)
{
    return (s.stage != STAGE_NONE) || s.deferredActive;
}

//+------------------------------------------------------------------+
//| SC3State Methods                                                  |
//+------------------------------------------------------------------+
void SC3StateReset(SC3State &s)
{
    s.isNew = false;
    s.didC3Sweep = false;
    s.lastC3Time = 0;
    s.lastC3GUID = 0;
    s.stage = STAGE_NONE;
    s.c3EntryPrice = 0.0;
    s.hasSignal = false;
    s.valid = false;
    s.lineage.sequenceId = 0;
    s.lineage.parentGuid = 0;
    s.lineage.requiresContinuation = false;
}

bool SC3StateIsActive(const SC3State &s)
{
    return (s.stage != STAGE_NONE);
}

//+------------------------------------------------------------------+
//| SC4State Methods                                                  |
//+------------------------------------------------------------------+
void SC4StateReset(SC4State &s)
{
    s.isNew = false;
    s.didC4Expand = false;
    s.lastC4Time = 0;
    s.lastC4GUID = 0;
    s.parentC3GUID = 0;
    s.stage = STAGE_NONE;
    s.c4EntryPrice = 0.0;
    s.c4High = 0.0;
    s.c4Low = 0.0;
    s.c4Open = 0.0;
    s.c4Close = 0.0;
    s.c4WickRatio = 0.0;
    s.hasSignal = false;
    s.valid = false;
    s.c2_high = 0.0;
    s.c2_low = 0.0;
    s.lineage.sequenceId = 0;
    s.lineage.parentGuid = 0;
    s.lineage.requiresContinuation = false;
    s.m_upgradedFromC3 = false;
    s.c4_high = 0.0;
    s.c4_low = 0.0;
    s.c4_close = 0.0;
}

bool SC4StateIsActive(const SC4State &s)
{
    return (s.stage != STAGE_NONE);
}

#endif // OMAK_CLOSURESTATE_MQH