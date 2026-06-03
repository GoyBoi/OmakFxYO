//+------------------------------------------------------------------+
//|                                     BranchContextExt.mqh |
//|                    OmakFxYO — BranchContext Extensions |
//+------------------------------------------------------------------+
#ifndef OMAK_BRANCHCONTEXTEXT_MQH
#define OMAK_BRANCHCONTEXTEXT_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "BranchContext campaign extensions — No logic"

//+------------------------------------------------------------------+
//| INCLUDES — Reference Only                                     |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>       // ENUM_DIRECTION, ENUM_EXECUTION_BRANCH
#include <OmakFxYO/core/ClosureEngine.mqh>    // ENUM_CLOSURE_TYPE
#include <OmakFxYO/core/CampaignData.mqh>  // SCampaign, SAddConditions

//+------------------------------------------------------------------+
//| SBranchCampaignContext — Branch Campaign Extension   |
//+------------------------------------------------------------------+
// This struct is included in BranchContext for campaign support
// (ADD-ON fields, does not replace existing BranchContext)

class SBranchCampaignContext
{
public:
   // Campaign identity
   int campaignId;                    // Active campaign ID (0 = none)
   SCampaign activeCampaign;            // Active campaign for this branch

   // Last signal tracking (for add detection)
   datetime lastC2SignalTime;         // Last C2 signal time
   datetime lastC3SignalTime;        // Last C3 signal time
   ENUM_CLOSURE_TYPE lastSignalType; // Last signal type
   double lastSignalPrice;           // Last signal price

   // Add evaluation state
   bool canAdd;                       // Add conditions currently met
   double expansionSinceAddR;          // Expansion since last add (R)
   datetime lastAddCheckTime;       // Last add evaluation time

   // Add conditions (per branch config)
   SAddConditions addConditions;     // Add parameters

   void Reset()
   {
      campaignId = 0;
      activeCampaign.Reset();

      lastC2SignalTime = 0;
      lastC3SignalTime = 0;
      lastSignalType = CLOSURE_NONE;
      lastSignalPrice = 0.0;

      canAdd = false;
      expansionSinceAddR = 0.0;
      lastAddCheckTime = 0;

      addConditions.Reset();
   }
};

//+------------------------------------------------------------------+
//| END OF FILE                                                  |
//+------------------------------------------------------------------+
#endif // OMAK_BRANCHCONTEXTEXT_MQH