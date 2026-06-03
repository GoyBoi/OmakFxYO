//+------------------------------------------------------------------+
//|                                        CampaignState.mqh |
//|                     OmakFxYO — Campaign State Enums |
//+------------------------------------------------------------------+
#ifndef OMAK_CAMPAIGNSTATE_MQH
#define OMAK_CAMPAIGNSTATE_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Campaign state enum definitions — No logic"

//+------------------------------------------------------------------+
//| INCLUDES — Reference Only, No Duplicate Definitions            |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>       // ENUM_DIRECTION, ENUM_EXECUTION_BRANCH
#include <OmakFxYO/core/ClosureEngine.mqh>    // ENUM_CLOSURE_TYPE (reference only)

//+------------------------------------------------------------------+
//| ENUM_CAMPAIGN_STATE — Campaign Lifecycle States                 |
//+------------------------------------------------------------------+
enum ENUM_CAMPAIGN_STATE
{
   CAMPAIGN_NONE = 0,        // No active campaign
   CAMPAIGN_SEED,             // Seed signal detected, waiting execution
   CAMPAIGN_ACTIVE,           // Position running, no adds yet
   CAMPAIGN_ADDING,          // Pyramiding phase — adds in progress
   CAMPAIGN_PROTECTED,       // SL moved to breakeven + buffer
   CAMPAIGN_TERMINATED       // Ended (TP/SL/manual close)
};

//+------------------------------------------------------------------+
//| ENUM_CAMPAIGN_SIGNAL_TYPE — Campaign Signal Origin          |
//+------------------------------------------------------------------+
enum ENUM_CAMPAIGN_SIGNAL_TYPE
{
   CAMPAIGN_SIGNAL_NONE = 0,   // No signal
   CAMPAIGN_SIGNAL_C2,        // Seed from C2
   CAMPAIGN_SIGNAL_C3,        // Seed from C3
   CAMPAIGN_SIGNAL_ADD         // Signal for add
};

//+------------------------------------------------------------------+
//| Helper Functions — String Conversion Only                     |
//+------------------------------------------------------------------+

string GetCampaignStateString(ENUM_CAMPAIGN_STATE state)
{
   switch(state)
   {
      case CAMPAIGN_NONE:       return "NONE";
      case CAMPAIGN_SEED:    return "SEED";
      case CAMPAIGN_ACTIVE:  return "ACTIVE";
      case CAMPAIGN_ADDING:  return "ADDING";
      case CAMPAIGN_PROTECTED: return "PROTECTED";
      case CAMPAIGN_TERMINATED: return "TERMINATED";
      default:               return "UNKNOWN";
   }
}

string GetCampaignSignalTypeString(ENUM_CAMPAIGN_SIGNAL_TYPE signalType)
{
   switch(signalType)
   {
      case CAMPAIGN_SIGNAL_NONE:   return "NONE";
      case CAMPAIGN_SIGNAL_C2:    return "C2";
      case CAMPAIGN_SIGNAL_C3:   return "C3";
      case CAMPAIGN_SIGNAL_ADD:   return "ADD";
      default:                   return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| END OF FILE                                                  |
//+------------------------------------------------------------------+
#endif // OMAK_CAMPAIGNSTATE_MQH