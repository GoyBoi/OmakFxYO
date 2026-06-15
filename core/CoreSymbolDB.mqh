//+------------------------------------------------------------------+
//| CoreSymbolDB.mqh                                                 |
//| Central Symbol Profile Database                                  |
//| All static symbol data retrieved exclusively through CSymbolProfile|
//+------------------------------------------------------------------+
#property strict

#ifndef OMAK_CORE_SYMBOL_DB_MQH
#define OMAK_CORE_SYMBOL_DB_MQH

#include <OmakFxYO/core/SymbolIntelligence.mqh>

//+------------------------------------------------------------------+
//| CSymbolProfile — Wraps SSymbolProfile for method-based access   |
//+------------------------------------------------------------------+
class CSymbolProfile
{
private:
   SSymbolProfile m_profile;

public:
   CSymbolProfile()
   {
      m_profile.Reset();
   }

   bool Initialize(string symbol)
   {
      m_profile = SY_RefreshProfile(symbol);
      return m_profile.isValid;
   }

   void FromProfile(SSymbolProfile &src)
   {
      m_profile = src;
   }

   double TickSize() { return m_profile.tickSize; }
   double TickValue() { return m_profile.tickValue; }
   double ContractSize() { return m_profile.contractSize; }
   int CalcMode() { return m_profile.calcMode; }
   double LotMin() { return m_profile.volumeMin; }
   double LotMax() { return m_profile.volumeMax; }
   double LotStep() { return m_profile.volumeStep; }
   double Point() { return m_profile.point; }
   int Digits() { return m_profile.digits; }
   string Symbol() { return m_profile.symbol; }
   bool IsValid() { return m_profile.isValid; }

   SSymbolProfile GetRaw() { return m_profile; }
};

//+------------------------------------------------------------------+
//| SY_GetProfilePtr — Returns CSymbolProfile pointer (no conflict  |
//| with existing SY_GetProfile that returns SSymbolProfile)         |
//+------------------------------------------------------------------+
CSymbolProfile* SY_GetProfilePtr(string symbol)
{
   static CSymbolProfile* s_ptr = NULL;
   static string s_lastSymbol = "";
   static datetime s_lastRefresh = 0;

   if(s_ptr == NULL)
      s_ptr = new CSymbolProfile();

   if(symbol != s_lastSymbol || TimeCurrent() - s_lastRefresh > 3600)
   {
      if(!s_ptr.Initialize(symbol))
      {
         LogPrint("[SY_GETPROFILE_WARN] Failed to initialize profile for " + symbol, LOG_LEVEL_WARN);
      }
      s_lastSymbol = symbol;
      s_lastRefresh = TimeCurrent();
   }

   return s_ptr;
}

//+------------------------------------------------------------------+
//| ValidateProfileIntegrity — Ensures profile has valid data        |
//+------------------------------------------------------------------+
bool ValidateProfileIntegrity(string symbol)
{
   CSymbolProfile* profile = SY_GetProfilePtr(symbol);
   if(profile == NULL)
   {
      LogPrint("[PROFILE_ERROR] Failed to get profile for " + symbol, LOG_LEVEL_ERROR);
      return false;
   }

   double tickSize = profile.TickSize();
   double tickValue = profile.TickValue();
   double contractSize = profile.ContractSize();
   int calcMode = profile.CalcMode();

   if(tickSize <= 0.0)
   {
      LogPrint("[PROFILE_ERROR] tickSize=0 for " + symbol, LOG_LEVEL_ERROR);
      return false;
   }

   if(tickValue <= 0.0 && calcMode != SYMBOL_CALC_MODE_FOREX)
   {
      LogPrint("[PROFILE_WARNING] tickValue=0 for non-Forex symbol " + symbol, LOG_LEVEL_WARN);
   }

   if(contractSize <= 0.0)
   {
      LogPrint("[PROFILE_ERROR] contractSize=0 for " + symbol, LOG_LEVEL_ERROR);
      return false;
   }

   LogPrint("[PROFILE_VALID] " + symbol + " tickSize=" + DoubleToString(tickSize) +
         " tickValue=" + DoubleToString(tickValue) + " contractSize=" + DoubleToString(contractSize) +
         " calcMode=" + IntegerToString(calcMode), LOG_LEVEL_INFO);

   return true;
}

#endif
