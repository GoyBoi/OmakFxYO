//+------------------------------------------------------------------+
//|                                     CampaignManager.mqh |
//|                     OmakFxYO — Campaign Manager |
//+------------------------------------------------------------------+
#ifndef OMAK_CAMPAIGNMANAGER_MQH
#define OMAK_CAMPAIGNMANAGER_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Campaign state machine — Lifecycle management only"

#property description "NO order execution, NO add execution, NO signal detection"

//+------------------------------------------------------------------+
//| INCLUDES — Reference Only                                     |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>          // ENUM_DIRECTION, ENUM_EXECUTION_BRANCH
#include <OmakFxYO/core/ClosureEngine.mqh>     // ENUM_CLOSURE_TYPE, SClosureSignal
#include <OmakFxYO/core/BranchRouter.mqh>     // GetBranchTimeframes
#include <OmakFxYO/core/BranchEvaluator.mqh>   // BranchContext
#include <OmakFxYO/core/BranchContextExt.mqh> // SBranchCampaignContext
#include <OmakFxYO/core/CampaignState.mqh>    // ENUM_CAMPAIGN_STATE
#include <OmakFxYO/core/CampaignData.mqh>     // SCampaign, SCampaignMetrics

//+------------------------------------------------------------------+
//| GLOBAL STATE — Isolated Per Branch                          |
//+------------------------------------------------------------------+

// Branch-specific campaign state (isolated — NO sharing)
SBranchCampaignContext g_branchACampaign;
SBranchCampaignContext g_branchBCampaign;

// Global campaign metrics
SCampaignMetrics g_campaignMetrics;

// Configuration (to be loaded from inputs)
SCampaignConfig g_campaignConfig;

//+------------------------------------------------------------------+
//| INITIALIZATION — CM_Initialize                              |
//+------------------------------------------------------------------+
/**
 * CM_Initialize
 *
 * Initialize campaign system. Call once on EA start.
 */
void CM_Initialize()
{
   g_branchACampaign.Reset();
   g_branchBCampaign.Reset();
   g_campaignMetrics.Reset();
   g_campaignConfig.Reset();

   // Configure default add conditions per branch
   g_branchACampaign.addConditions.Reset();
   g_branchBCampaign.addConditions.Reset();

   LogPrint("[CM] Campaign system initialized", LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| STATE ACCESS — CM_GetCampaignState                          |
//+------------------------------------------------------------------+

/**
 * CM_GetCampaignState
 *
 * Get current campaign state for a branch.
 */
ENUM_CAMPAIGN_STATE CM_GetCampaignState(ENUM_EXECUTION_BRANCH branch)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   return ctx.activeCampaign.state;
}

/**
 * GetBranchCampaignContext
 *
 * Get campaign context for branch (internal helper).
 */
SBranchCampaignContext *GetBranchCampaignContext(ENUM_EXECUTION_BRANCH branch)
{
   if(branch == BRANCH_INTRADAY)
      return &g_branchACampaign;
   else
      return &g_branchBCampaign;
}

/**
 * CM_GetActiveCampaign
 *
 * Get pointer to active campaign for branch.
 */
SCampaign* CM_GetActiveCampaign(ENUM_EXECUTION_BRANCH branch)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);

   if(ctx.activeCampaign.isActive)
      return &ctx.activeCampaign;

   return NULL;
}

//+------------------------------------------------------------------+
//| SIGNAL PROCESSING — CM_ProcessSignals                       |
//+------------------------------------------------------------------+

/**
 * CM_ProcessSignals
 *
 * Process incoming closure signals for campaign state updates.
 *
 * SIGNAL HANDLING RULE:
 *   IF no campaign:
 *     IF C2 OR C3 + HTF aligned → SEED
 *
 *   IF campaign exists:
 *     IF C3 + aligned → ADD evaluation pass
 *     IF C3 + opposite → new SEED override
 *     IF C2 → ignored (standalone only)
 *
 * NO EXECUTION — only state management.
 */
void CM_ProcessSignals(
   ENUM_EXECUTION_BRANCH branch,
   SClosureSignal &signal,
   ENUM_DIRECTION htfBias
)
{
   if(!g_campaignConfig.pyramidingEnabled)
      return;

   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;

   // Track signal
   bool isC2 = (signal.type == CLOSURE_C2);
   bool isC3 = (signal.type == CLOSURE_C3);

   if(isC2)
   {
      ctx.lastC2SignalTime = signal.setupStartTime;
      ctx.lastSignalType = CLOSURE_C2;
      ctx.lastSignalPrice = signal.entry_price;
      g_campaignMetrics.c2Total++;
   }
   else if(isC3)
   {
      ctx.lastC3SignalTime = signal.setupStartTime;
      ctx.lastSignalType = CLOSURE_C3;
      ctx.lastSignalPrice = signal.entry_price;
      g_campaignMetrics.c3Total++;
   }
   else
   {
      // Not a campaign signal
      return;
   }

   // Check HTF alignment
   bool signalDir = signal.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;
   bool aligned = (signalDir == htfBias);

   // === NO CAMPAIGN EXISTS ===
   if(camp.state == CAMPAIGN_NONE || camp.state == CAMPAIGN_TERMINATED)
   {
      if(!aligned && g_campaignConfig.requireHTFAlign)
      {
         // Not aligned — skip for campaign, could be standalone
         if(isC3)
            g_campaignMetrics.c3SkippedNotAligned++;
         return;
      }

      // Start new campaign
      ENUM_CAMPAIGN_SIGNAL_TYPE sigType = isC2 ? CAMPAIGN_SIGNAL_C2 : CAMPAIGN_SIGNAL_C3;
      CM_StartCampaign(branch, signal, htfBias, aligned, sigType);
      return;
   }

   // === CAMPAIGN EXISTS ===
   if(isC3)
   {
      if(aligned)
      {
         // C3 aligned — mark as ADD candidate (NOT execution)
         // Evaluation will happen in AddExecutor
         ctx.canAdd = true;
      }
      else
      {
         // C3 opposite direction — start new campaign override
         ctx.canAdd = false;
         CM_TerminateCampaign(branch, "C3_OPPOSITE_NEW_SEED");

         ENUM_CAMPAIGN_SIGNAL_TYPE sigType = CAMPAIGN_SIGNAL_C3;
         CM_StartCampaign(branch, signal, htfBias, false, sigType);
      }
   }
   // C2 during campaign — ignore for add logic
   // (C2 can only start standalone, not adds)
}

//+------------------------------------------------------------------+
//| CAMPAIGN LIFECYCLE — CM_StartCampaign                      |
//+------------------------------------------------------------------+

/**
 * CM_StartCampaign
 *
 * Start a new campaign from seed signal.
 *
 * Only state management — NO order execution.
 */
void CM_StartCampaign(
   ENUM_EXECUTION_BRANCH branch,
   SClosureSignal &signal,
   ENUM_DIRECTION htfBias,
   bool aligned,
   ENUM_CAMPAIGN_SIGNAL_TYPE signalOrigin
)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;
   BranchConfig cfg = GetBranchConfig(branch);

   // Reset campaign
   camp.Reset();

   // Identity
   camp.branch = branch;
   camp.campaignId = ctx.campaignId + 1;
   camp.state = CAMPAIGN_SEED;
   camp.signalOrigin = signalOrigin;

   // Direction and TF
   camp.direction = signal.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;
   camp.campaignTF = cfg.structure;
   camp.entryTF = cfg.entry;

   // Seed signal
   camp.seedSignal.signalTime = signal.setupStartTime;
   camp.seedSignal.signalType = signal.type;
   camp.seedSignal.direction = camp.direction;
   camp.seedSignal.price = signal.entry_price;
   camp.seedSignal.confidence = signal.confidence;
   camp.seedSignal.htfAligned = aligned;
   camp.seedSignal.branch = branch;

// HTF Bias
    camp.htfBias = htfBias;
    camp.biasAligned = aligned;

    // Calculate campaign TP from entry/SL using risk reward ratio
    double riskDistance = MathAbs(signal.entry_price - signal.stop_loss);
    if(riskDistance > 0)
    {
       double tpDistance = riskDistance * InpRiskRewardRatio;
       if(camp.direction == DIRECTION_BUY)
          camp.campaignTP = signal.entry_price + tpDistance;
       else
          camp.campaignTP = signal.entry_price - tpDistance;
       camp.campaignTP = NormalizeDouble(camp.campaignTP, _Digits);
    }
    else
    {
       camp.campaignTP = 0.0;
    }

    // Set campaign SL from seed
    camp.campaignSL = signal.stop_loss;

    // Timing
   camp.startTime = TimeCurrent();
   camp.lastUpdateTime = TimeCurrent();
   camp.isActive = true;

   // Set campaign ID in context
   ctx.campaignId = camp.campaignId;

   // Update metrics
   if(signalOrigin == CAMPAIGN_SIGNAL_C2)
      g_campaignMetrics.c2Executed++;
   else if(signalOrigin == CAMPAIGN_SIGNAL_C3)
      g_campaignMetrics.c3Executed++;

   g_campaignMetrics.campaignsStarted++;
   if(branch == BRANCH_INTRADAY)
      g_campaignMetrics.branchA_campaignsStarted++;
   else
      g_campaignMetrics.branchB_campaignsStarted++;

   if(g_campaignMetrics.firstCampaignTime == 0)
      g_campaignMetrics.firstCampaignTime = TimeCurrent();
   g_campaignMetrics.lastCampaignTime = TimeCurrent();

LogPrint("[CM] Campaign STARTED | Branch=" + EnumToString(branch) + " | ID=" + IntegerToString(camp.campaignId) +
           " | Signal=" + (signalOrigin == CAMPAIGN_SIGNAL_C2 ? "C2" : "C3") +
           " | Direction=" + (camp.direction == DIRECTION_BUY ? "BUY" : "SELL") +
           " | Aligned=" + (aligned ? "TRUE" : "FALSE") +
           " | TP=" + DoubleToString(camp.campaignTP, _Digits) +
           " | SL=" + DoubleToString(camp.campaignSL, _Digits), LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| STATE TRANSITION — CM_TransitionToActive                      |
//+------------------------------------------------------------------+

/**
 * CM_TransitionToActive
 *
 * Transition from SEED to ACTIVE when position filled.
 * Called AFTER OrderManager confirms execution.
 */
void CM_TransitionToActive(
   ENUM_EXECUTION_BRANCH branch,
   int ticket,
   double price,
   double lot,
   double sl
)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;

   if(camp.state != CAMPAIGN_SEED)
   {
      LogPrint("[CM] Warning: Transition to ACTIVE from non-SEED state | State=" + EnumToString(camp.state), LOG_LEVEL_WARN);
      return;
   }

   // Record position details
   camp.seedTicket = ticket;
   camp.seedPrice = price;
   camp.seedLot = lot;
   camp.seedSL = sl;

   camp.totalVolume = lot;
   camp.avgPrice = price;
   camp.campaignSL = sl;

   // Transition state
   camp.state = CAMPAIGN_ACTIVE;
   camp.lastUpdateTime = TimeCurrent();

LogPrint("[CM] Campaign ACTIVE | Branch=" + EnumToString(branch) + " | ID=" + IntegerToString(camp.campaignId) +
          " | Ticket=" + IntegerToString(ticket) + " | Price=" + DoubleToString(price, _Digits) + " | Lot=" + DoubleToString(lot, 2), LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| ADD STATE MANAGEMENT — CM_TransitionToAdding                   |
//+------------------------------------------------------------------+

/**
 * CM_TransitionToAdding
 *
 * Transition to ADDING when first add executes.
 */
void CM_TransitionToAdding(ENUM_EXECUTION_BRANCH branch)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;

   if(camp.state != CAMPAIGN_ACTIVE && camp.state != CAMPAIGN_ADDING)
   {
      return;
   }

   camp.state = CAMPAIGN_ADDING;
   camp.lastUpdateTime = TimeCurrent();
   camp.lastAddTime = TimeCurrent();

   LogPrint("[CM] Campaign ADDING | Branch=" + EnumToString(branch) + " | ID=" + IntegerToString(camp.campaignId), LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| PROTECTED STATE — CM_TransitionToProtected                    |
//+------------------------------------------------------------------+

/**
 * CM_TransitionToProtected
 *
 * Transition to PROTECTED when profit threshold reached.
 */
void CM_TransitionToProtected(ENUM_EXECUTION_BRANCH branch)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;

   if(camp.state != CAMPAIGN_ACTIVE && camp.state != CAMPAIGN_ADDING)
   {
      return;
   }

   camp.state = CAMPAIGN_PROTECTED;
   camp.slProtected = true;
   camp.protectedTime = TimeCurrent();
   camp.lastUpdateTime = TimeCurrent();

   LogPrint("[CM] Campaign PROTECTED | Branch=" + EnumToString(branch) + " | ID=" + IntegerToString(camp.campaignId), LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| TERMINATION — CM_TerminateCampaign                           |
//+------------------------------------------------------------------+

/**
 * CM_TerminateCampaign
 *
 * Terminate campaign.
 */
void CM_TerminateCampaign(ENUM_EXECUTION_BRANCH branch, string reason)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;

   if(camp.state == CAMPAIGN_NONE || camp.state == CAMPAIGN_TERMINATED)
      return;

   // Record final metrics
   if(camp.currentProfitR > 0)
   {
      g_campaignMetrics.campaignsCompleted++;
      if(branch == BRANCH_INTRADAY)
         g_campaignMetrics.branchA_campaignsCompleted++;
      else
         g_campaignMetrics.branchB_campaignsCompleted++;
   }
   else
   {
      g_campaignMetrics.campaignsFailed++;
   }

   // Update efficiency
   if(g_campaignMetrics.avgProfitPerCampaign > 0)
   {
      g_campaignMetrics.stackEfficiency = camp.profitFromAddsR / g_campaignMetrics.avgProfitPerCampaign;
   }

   // Transition state
   ENUM_CAMPAIGN_STATE prevState = camp.state;
   camp.state = CAMPAIGN_TERMINATED;
   camp.isActive = false;
   camp.lastUpdateTime = TimeCurrent();

LogPrint("[CM] Campaign TERMINATED | Branch=" + EnumToString(branch) + " | ID=" + IntegerToString(camp.campaignId) +
          " | Reason=" + reason + " | ProfitR=" + DoubleToString(camp.currentProfitR, 2) +
          " | Adds=" + IntegerToString(camp.addCount), LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| ADD EVALUATION — CM_IsAddAllowed                              |
//+------------------------------------------------------------------+

/**
 * CM_IsAddAllowed
 *
 * Check if add conditions are met for campaign.
 *
 * CRITICAL: This EVALUATES conditions, does NOT execute.
 * Actual execution happens in AddExecutor.
 */
bool CM_IsAddAllowed(ENUM_EXECUTION_BRANCH branch)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;
   SAddConditions *cond = &ctx.addConditions;

   // Must be in ACTIVE or ADDING state
   if(camp.state != CAMPAIGN_ACTIVE && camp.state != CAMPAIGN_ADDING)
      return false;

   // Check add count limit
   if(camp.addCount >= cond.maxAdds)
      return false;

   // Check profit requirement
   if(camp.currentProfitR < cond.minProfitR)
      return false;

   // Check SL protection
   if(cond.slProtectedRequired && !camp.slProtected)
      return false;

   // Check HTF alignment
   if(cond.htfAlignRequired && !camp.biasAligned)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| ADD RECORDING — CM_RecordAdd                                 |
//+------------------------------------------------------------------+

/**
 * CM_RecordAdd
 *
 * Record executed add order in campaign.
 */
void CM_RecordAdd(
   ENUM_EXECUTION_BRANCH branch,
   int ticket,
   double price,
   double lot,
   double expansionR
)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;

   if(camp.addCount >= 4)
   {
      LogPrint("[CM] Error: Max adds reached", LOG_LEVEL_ERROR);
      return;
   }

   int idx = camp.addCount + 1;
   SAddInfo *add = &camp.adds[idx];

   add.addTime = TimeCurrent();
   add.ticket = ticket;
   add.price = price;
   add.lot = lot;
   add.profitAtAdd = camp.currentProfitR;
   add.expansionR = expansionR;
   add.slProtected = camp.slProtected;
   add.addIndex = idx;

   camp.addCount = idx;
   camp.totalVolume += lot;
   camp.lastAddTime = TimeCurrent();
   camp.lastUpdateTime = TimeCurrent();

   // Update metrics
   g_campaignMetrics.addsTotal++;
   if(branch == BRANCH_INTRADAY)
      g_campaignMetrics.branchA_adds++;
   else
      g_campaignMetrics.branchB_adds++;

   // Update expansion average
   camp.avgExpansionR = (camp.avgExpansionR * (camp.addCount - 1) + expansionR) / camp.addCount;

   // Transition to ADDING if first add
   if(camp.state == CAMPAIGN_ACTIVE)
      CM_TransitionToAdding(branch);

LogPrint("[CM] Add RECORDED | Branch=" + EnumToString(branch) + " | ID=" + IntegerToString(camp.campaignId) +
          " | Add#=" + IntegerToString(idx) + " | Ticket=" + IntegerToString(ticket) + " | Price=" + DoubleToString(price, _Digits), LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| SWING ADD RECORDING — CM_AddSwingLayer                        |
//+------------------------------------------------------------------+

/**
 * CM_AddSwingLayer
 *
 * Record a swing-based pyramid add (no signal GUID).
 * Stores the swing price and time for future swing detection.
 */
void CM_AddSwingLayer(
   ENUM_EXECUTION_BRANCH branch,
   int ticket,
   double price,
   double lot,
   double swingPrice,
   double expansionR
)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;

   if(camp.addCount >= 4)
   {
      LogPrint("[CM] Error: Max adds reached for swing layer", LOG_LEVEL_ERROR);
      return;
   }

   int idx = camp.addCount + 1;
   SAddInfo *add = &camp.adds[idx];

   add.addTime = TimeCurrent();
   add.ticket = ticket;
   add.price = price;
   add.lot = lot;
   add.profitAtAdd = camp.currentProfitR;
   add.expansionR = expansionR;
   add.slProtected = camp.slProtected;
   add.addIndex = idx;

   camp.addCount = idx;
   camp.totalVolume += lot;
   camp.lastAddTime = TimeCurrent();
   camp.lastUpdateTime = TimeCurrent();

   // Record swing level for future comparison
   camp.lastSwingPrice = swingPrice;
   camp.lastSwingTime = TimeCurrent();

   // Update metrics
   g_campaignMetrics.addsTotal++;
   if(branch == BRANCH_INTRADAY)
      g_campaignMetrics.branchA_adds++;
   else
      g_campaignMetrics.branchB_adds++;

   // Update expansion average
   camp.avgExpansionR = (camp.avgExpansionR * (camp.addCount - 1) + expansionR) / camp.addCount;

   // Transition to ADDING if first add
   if(camp.state == CAMPAIGN_ACTIVE)
      CM_TransitionToAdding(branch);

   LogPrint("[PYRAMID_ADD] Branch=" + EnumToString(branch) + " | ID=" + IntegerToString(camp.campaignId) +
            " | Add#=" + IntegerToString(idx) + " | Ticket=" + IntegerToString(ticket) +
            " | Price=" + DoubleToString(price, _Digits) +
            " | Swing=" + DoubleToString(swingPrice, _Digits) +
            " | Lot=" + DoubleToString(lot, 2) +
            " | ExpansionR=" + DoubleToString(expansionR, 2), LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| PROFIT UPDATE — CM_UpdateProfit                              |
//+------------------------------------------------------------------+

/**
 * CM_UpdateProfit
 *
 * Update campaign profit tracking.
 */
void CM_UpdateProfit(ENUM_EXECUTION_BRANCH branch, double profitR)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;

   if(!camp.isActive)
      return;

   camp.currentProfitR = profitR;

   // Track peak
   if(profitR > camp.peakProfitR)
      camp.peakProfitR = profitR;

   // Check protected threshold
   SAddConditions *cond = &ctx.addConditions;
   if(!camp.slProtected && profitR >= cond.protectedThresholdR)
   {
      CM_TransitionToProtected(branch);
   }

   camp.lastUpdateTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| METRICS ACCESS — CM_GetCampaignMetrics                        |
//+------------------------------------------------------------------+

/**
 * CM_GetCampaignMetrics
 *
 * Get global campaign metrics.
 */
SCampaignMetrics CM_GetCampaignMetrics()
{
   return g_campaignMetrics;
}

/**
 * CM_CalculateStackEfficiency
 *
 * Calculate stack efficiency (profit from adds / total profit).
 */
double CM_CalculateStackEfficiency()
{
   double totalProfit = g_campaignMetrics.avgProfitPerCampaign * g_campaignMetrics.campaignsCompleted;

   if(totalProfit <= 0)
      return 0.0;

   return g_campaignMetrics.stackEfficiency;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                  |
//+------------------------------------------------------------------+
#endif // OMAK_CAMPAIGNMANAGER_MQH