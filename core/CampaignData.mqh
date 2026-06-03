//+------------------------------------------------------------------+
//|                                        CampaignData.mqh |
//|                    OmakFxYO — Campaign Data Structures |
//+------------------------------------------------------------------+
#ifndef OMAK_CAMPAIGNDATA_MQH
#define OMAK_CAMPAIGNDATA_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Campaign data structures — Pure data only, no logic"

//+------------------------------------------------------------------+
//| INCLUDES — Reference Only                                     |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>          // ENUM_DIRECTION, ENUM_EXECUTION_BRANCH
#include <OmakFxYO/core/ClosureEngine.mqh>       // ENUM_CLOSURE_TYPE
#include <OmakFxYO/core/CampaignState.mqh>       // ENUM_CAMPAIGN_STATE, ENUM_CAMPAIGN_SIGNAL_TYPE

//+------------------------------------------------------------------+
//| SCampaignSignal — Seed Signal Container                   |
//+------------------------------------------------------------------+
class SCampaignSignal
{
public:
   datetime signalTime;              // When signal detected
   ENUM_CLOSURE_TYPE signalType;     // CLOSURE_C2 or CLOSURE_C3
   ENUM_DIRECTION direction;        // BUY or SELL
   double price;                   // Signal price level
   double confidence;              // Signal confidence (0.0-1.0)
   bool htfAligned;                // HTF bias alignment
   ENUM_EXECUTION_BRANCH branch;   // Branch origin

   void Reset()
   {
      signalTime = 0;
      signalType = CLOSURE_NONE;
      direction = DIRECTION_NONE;
      price = 0.0;
      confidence = 0.0;
      htfAligned = false;
      branch = BRANCH_INTRADAY;
   }
};

//+------------------------------------------------------------------+
//| SAddInfo — Individual Add Order Info                      |
//+------------------------------------------------------------------+
class SAddInfo
{
public:
   datetime addTime;               // When add executed
   int ticket;                     // Order ticket
   double price;                  // Add entry price
   double lot;                     // Add lot size
   double profitAtAdd;             // Campaign profit at add time
   double expansionR;             // Expansion from prior add (in R)
   bool slProtected;               // SL was protected at add time
   int addIndex;                  // Add number (1, 2, 3...)

   void Reset()
   {
      addTime = 0;
      ticket = 0;
      price = 0.0;
      lot = 0.0;
      profitAtAdd = 0.0;
      expansionR = 0.0;
      slProtected = false;
      addIndex = 0;
   }
};

//+------------------------------------------------------------------+
//| SCampaign — Full Campaign Container                       |
//+------------------------------------------------------------------+
class SCampaign
{
public:
   // Identity
   ENUM_EXECUTION_BRANCH branch;         // BRANCH_INTRADAY or BRANCH_SWING
   int campaignId;                       // Unique campaign ID
   ENUM_CAMPAIGN_STATE state;          // Current state
   ENUM_CAMPAIGN_SIGNAL_TYPE signalOrigin; // Seed signal origin

   // Direction and TF
   ENUM_DIRECTION direction;             // BUY or SELL
   ENUM_TIMEFRAMES campaignTF;          // Structure TF (H4/H1)
   ENUM_TIMEFRAMES entryTF;             // Entry TF (M15/M5)

   // Seed signal
   SCampaignSignal seedSignal;         // Original seed signal

   // HTF Bias
   ENUM_DIRECTION htfBias;            // D1/H4 bias direction
   bool biasAligned;                  // Current alignment status

   // Position tracking
   int seedTicket;                   // Seed order ticket
   double seedLot;                   // Seed lot size
   double seedPrice;                 // Seed entry price
   double seedSL;                   // Seed stop loss

   // Aggregate position
   double totalVolume;               // Total lot (seed + adds)
   double avgPrice;                 // Average entry price
   double campaignSL;                // Aggregate stop loss
   double campaignTP;                // Aggregate take profit

   // Add tracking
   SAddInfo adds[4];                // Array of adds (max 3 + index 0 unused)
   int addCount;                    // Number of adds executed

   // Swing tracking for pyramiding
   double lastSwingPrice;           // Last confirmed swing price used for add
   datetime lastSwingTime;          // When the last add swing was confirmed

   // Profit tracking
   double currentProfitPoints;         // Current profit in points
   double currentProfitR;           // Current profit in R
   double peakProfitR;              // Peak profit reached

   // Timing
   datetime startTime;              // Campaign start time
   datetime lastAddTime;            // Last add time
   datetime lastUpdateTime;         // Last state update

   // State flags
   bool slProtected;               // SL moved to breakeven
   datetime protectedTime;          // When SL protected
   bool isActive;                  // TRUE if campaign active

   // Metrics
   double totalProfitR;            // Total profit earned (R)
   double profitFromAddsR;         // Profit from adds only (R)
   double avgExpansionR;           // Average expansion between adds

   void Reset()
   {
      branch = BRANCH_INTRADAY;
      campaignId = 0;
      state = CAMPAIGN_NONE;
      signalOrigin = CAMPAIGN_SIGNAL_NONE;

      direction = DIRECTION_NONE;
      campaignTF = PERIOD_H4;
      entryTF = PERIOD_M15;

      seedSignal.Reset();

      htfBias = DIRECTION_NONE;
      biasAligned = false;

      seedTicket = 0;
      seedLot = 0.0;
      seedPrice = 0.0;
      seedSL = 0.0;

      totalVolume = 0.0;
      avgPrice = 0.0;
      campaignSL = 0.0;
      campaignTP = 0.0;

      addCount = 0;
      lastSwingPrice = 0.0;
      lastSwingTime = 0;
      for(int i = 0; i < 4; i++)
         adds[i].Reset();

      currentProfitPoints = 0.0;
      currentProfitR = 0.0;
      peakProfitR = 0.0;

      startTime = 0;
      lastAddTime = 0;
      lastUpdateTime = 0;

      slProtected = false;
      protectedTime = 0;
      isActive = false;

      totalProfitR = 0.0;
      profitFromAddsR = 0.0;
      avgExpansionR = 0.0;
   }
};

//+------------------------------------------------------------------+
//| SCampaignMetrics — Global Campaign Metrics                  |
//+------------------------------------------------------------------+
class SCampaignMetrics
{
public:
   // Global counters
   int campaignsStarted;          // Total campaigns started
   int campaignsCompleted;       // Campaigns completed (TERMINATED with profit)
   int campaignsFailed;          // Campaigns failed (SL hit)
   int campaignsTerminatedManual; // Manual terminations

   // C2 signals
   int c2Total;                 // Total C2 signals detected
   int c2Executed;               // C2 executed as campaign seed
   int c2Standalone;            // C2 standalone (no campaign)

   // C3 signals
   int c3Total;                // Total C3 signals detected
   int c3Executed;              // C3 executed (seed or add)
   int c3Standalone;           // C3 standalone campaigns
   int c3SkippedNotAligned;     // C3 skipped (not aligned)

   // Add tracking
   int addsTotal;               // Total adds executed
   int addsInProfit;            // Adds that closed in profit
   int addsOutOfProfit;          // Adds that closed at loss
   double avgAddsPerCampaign;   // Average adds per campaign

   // Efficiency
   double stackEfficiency;     // profitFromAddsR / totalProfitR
   double avgProfitPerCampaign;  // Average profit per campaign

   // Timing
   datetime firstCampaignTime;
   datetime lastCampaignTime;

   // Branch-specific metrics
   int branchA_campaignsStarted;
   int branchA_campaignsCompleted;
   int branchA_adds;
   int branchB_campaignsStarted;
   int branchB_campaignsCompleted;
   int branchB_adds;

   void Reset()
   {
      campaignsStarted = 0;
      campaignsCompleted = 0;
      campaignsFailed = 0;
      campaignsTerminatedManual = 0;

      c2Total = 0;
      c2Executed = 0;
      c2Standalone = 0;

      c3Total = 0;
      c3Executed = 0;
      c3Standalone = 0;
      c3SkippedNotAligned = 0;

      addsTotal = 0;
      addsInProfit = 0;
      addsOutOfProfit = 0;
      avgAddsPerCampaign = 0.0;

      stackEfficiency = 0.0;
      avgProfitPerCampaign = 0.0;

      firstCampaignTime = 0;
      lastCampaignTime = 0;

      branchA_campaignsStarted = 0;
      branchA_campaignsCompleted = 0;
      branchA_adds = 0;
      branchB_campaignsStarted = 0;
      branchB_campaignsCompleted = 0;
      branchB_adds = 0;
   }
};

//+------------------------------------------------------------------+
//| SAddConditions — Configuration Container              |
//+------------------------------------------------------------------+
class SAddConditions
{
public:
   double minProfitR;              // Minimum profit in R (default: 1.0)
   bool slProtectedRequired;        // SL must be protected (default: true)
   int maxAdds;                    // Maximum adds (default: 3)
   double minExpansionR;            // Min expansion in R (default: 0.5)
   bool structureBreakRequired;     // Structure break required (default: true)
   bool htfAlignRequired;          // HTF alignment required (default: true)
   double protectedThresholdR;       // Profit to move SL (default: 2.0)
   double protectedBufferR;          // SL buffer in R (default: 0.5)
   double addLotMultiplier;        // Add lot vs seed (default: 1.0)

   void Reset()
   {
      minProfitR = 1.0;
      slProtectedRequired = true;
      maxAdds = 3;
      minExpansionR = 0.5;
      structureBreakRequired = true;
      htfAlignRequired = true;
      protectedThresholdR = 2.0;
      protectedBufferR = 0.5;
      addLotMultiplier = 1.0;
   }
};

//+------------------------------------------------------------------+
//| SCampaignConfig — Global Campaign Configuration         |
//+------------------------------------------------------------------+
class SCampaignConfig
{
public:
   bool pyramidingEnabled;           // Enable pyramiding (default: true)
   bool standaloneEnabled;           // Enable standalone C3 (default: true)
   int maxCampaignsPerBranch;        // Max active campaigns (default: 1)
   int campaignTimeoutBars;        // Campaign timeout (0 = none)
   double standaloneLotReduction;   // Standalone lot reduction (default: 0.5)
   bool requireHTFAlign;           // Require HTF alignment (default: true)

   void Reset()
   {
      pyramidingEnabled = true;
      standaloneEnabled = true;
      maxCampaignsPerBranch = 1;
      campaignTimeoutBars = 0;
      standaloneLotReduction = 0.5;
      requireHTFAlign = true;
   }
};

//+------------------------------------------------------------------+
//| END OF FILE                                                  |
//+------------------------------------------------------------------+
#endif // OMAK_CAMPAIGNDATA_MQH