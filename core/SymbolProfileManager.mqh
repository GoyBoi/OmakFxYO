//+------------------------------------------------------------------+
//|                                    SymbolProfileManager.mqh |
//|                                    Universal Symbol Profile |
//+------------------------------------------------------------------+
#property strict

#ifndef OMAK_SYMBOLPROFILE_MANAGER_MQH
#define OMAK_SYMBOLPROFILE_MANAGER_MQH

#include <OmakFxYO/core/CoreTypes.mqh>
#include <OmakFxYO/core/LogGovernor.mqh>
#include <OmakFxYO/core/SymbolIntelligence.mqh>  // SSymbolProfile + SY_* functions

static SSymbolProfile g_symbolProfile;

bool SPM_InitSymbolProfile(const string symbol)
{
    // Delegate ALL broker profile building to SymbolIntelligence layer
    SSymbolProfile profile = SY_BuildProfile(symbol);
    // preserve SY_BuildProfile's validity decision

    if(profile.volumeMin <= 0.0)
    {
       LogPrint("[SYMBOL_PROFILE] WARNING: SYMBOL_VOLUME_MIN returned 0.0 — trading cannot proceed safely", LOG_LEVEL_WARN);
       profile.volumeMin = 0.0;
    }

    profile.spread = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);

    // Derive classification-boolean helpers from authoritative SymbolIntelligence classification
    ENUM_SYM_CLASSIFICATION cl = profile.classification;
    profile.isSynthetic = (cl == SYM_CLASS_SYNTHETIC);
    profile.isCrypto    = (cl == SYM_CLASS_CRYPTO);
    profile.isMetal     = (cl == SYM_CLASS_METAL_SPOT);
    profile.isForex     = (cl == SYM_CLASS_FOREX_MAJOR || cl == SYM_CLASS_FOREX_MINOR || cl == SYM_CLASS_FOREX_EXOTIC);

    profile.sessionsExist = SPM_CheckSessionsExist(symbol);
    if(profile.sessionsExist)
    {
        SPM_ComputeNextSessionTimes(symbol, profile);
    }

    g_symbolProfile = profile;

    LogPrint("[SYM_CLASSIFIED] symbol=" + symbol + " | class=" + EnumToString(cl) + " | owner=SPM_InitSymbolProfile", LOG_LEVEL_INFO);
    LogPrint("[SYMBOL_PROFILE] class=" + EnumToString(cl) +
             " | ticksize=" + DoubleToString(profile.tickSize, 8) +
             " | tickvalue=" + DoubleToString(profile.tickValue, 8) +
             " | point=" + DoubleToString(profile.point, 8) +
             " | contract=" + DoubleToString(profile.contractSize, 4) +
             " | volMin=" + DoubleToString(profile.volumeMin, 4) +
             " | volMax=" + DoubleToString(profile.volumeMax, 4) +
             " | volStep=" + DoubleToString(profile.volumeStep, 4) +
             " | digits=" + IntegerToString(profile.digits) +
             " | spread=" + IntegerToString(profile.spread) +
             " | sessions=" + (profile.sessionsExist ? "YES" : "NO (24/7)") +
             " | sym=" + symbol +
             " | calcMode=" + IntegerToString(profile.calcMode) +
             " | marginCurrency=" + profile.marginCurrency +
             " | profitCurrency=" + profile.profitCurrency,
             LOG_LEVEL_INFO);

    return true;
}

bool SPM_CheckSessionsExist(const string symbol)
{
    MqlDateTime dt = {};
    TimeCurrent(dt);

    datetime mondayStart = StringToTime(IntegerToString(dt.year) + "." +
                                       IntegerToString(dt.mon) + "." +
                                       IntegerToString(dt.day) + " 00:00");

    for(int day = 0; day < 7; day++)
    {
        datetime checkDate = mondayStart + (day * 86400);
        for(uint session = 0; session < 10; session++)
        {
            datetime from = 0, to = 0;
            if(SymbolInfoSessionTrade(symbol, MONDAY, session, from, to))
            {
                return true;
            }
        }
    }
    return false;
}

void SPM_ComputeNextSessionTimes(const string symbol, SSymbolProfile &profile)
{
    MqlDateTime dt = {};
    TimeCurrent(dt);

    datetime now = TimeCurrent();
    datetime todayStart = StringToTime(IntegerToString(dt.year) + "." +
                                      IntegerToString(dt.mon) + "." +
                                      IntegerToString(dt.day) + " 00:00");

    ENUM_DAY_OF_WEEK startDay = (dt.day_of_week == 0) ? MONDAY : (ENUM_DAY_OF_WEEK)(dt.day_of_week);

    for(int dayOffset = 0; dayOffset < 7; dayOffset++)
    {
        datetime checkDate = todayStart + (dayOffset * 86400);
        ENUM_DAY_OF_WEEK checkDay = (startDay + dayOffset > SUNDAY) ? MONDAY : (ENUM_DAY_OF_WEEK)((startDay + dayOffset) % 8);
        if(checkDay == 0) checkDay = MONDAY;

        bool foundOpen = false;
        for(uint session = 0; session < 10; session++)
        {
            datetime from = 0, to = 0;
            if(SymbolInfoSessionTrade(symbol, checkDay, session, from, to))
            {
                if(!foundOpen && from > now)
                {
                    profile.nextSessionOpen = from;
                    foundOpen = true;
                }
                if(foundOpen)
                {
                    profile.nextSessionClose = to;
                    return;
                }
            }
        }
    }
}

SSymbolProfile SPM_GetProfile()
{
    return g_symbolProfile;
}

bool SPM_IsSessionOpen()
{
    if(!g_symbolProfile.sessionsExist)
        return true;

    datetime now = TimeCurrent();
    if(g_symbolProfile.nextSessionOpen > 0 && now >= g_symbolProfile.nextSessionOpen &&
       now <= g_symbolProfile.nextSessionClose)
    {
        return true;
    }

    for(int day = 0; day < 7; day++)
    {
        ENUM_DAY_OF_WEEK checkDay = (day == 0) ? MONDAY : (ENUM_DAY_OF_WEEK)(day);
        for(uint session = 0; session < 10; session++)
        {
            datetime from = 0, to = 0;
            if(SymbolInfoSessionTrade(g_symbolProfile.symbol, checkDay, session, from, to))
            {
                if(now >= from && now < to)
                    return true;
            }
        }
    }

    MqlDateTime dtNow = {};
    TimeCurrent(dtNow);
    ENUM_DAY_OF_WEEK currDay = (dtNow.day_of_week == 0) ? MONDAY : (ENUM_DAY_OF_WEEK)dtNow.day_of_week;
    datetime currTime = TimeCurrent();

    for(uint session = 0; session < 10; session++)
    {
        datetime from = 0, to = 0;
        if(SymbolInfoSessionTrade(g_symbolProfile.symbol, currDay, session, from, to))
        {
            if(currTime >= from && currTime < to)
                return true;
        }
    }

    return false;
}

bool SPM_Is24HourSymbol()
{
    return !g_symbolProfile.sessionsExist || g_symbolProfile.isSynthetic || g_symbolProfile.isCrypto;
}

// REGRESSION_GUARD_V52.5_SPM_LOT_DELETED — SPM_CalculateLotSize and SPM_CalculateMinSLPoints removed (dead code)
#endif // OMAK_SYMBOLPROFILE_MANAGER_MQH