//+------------------------------------------------------------------+
//|                                      AddExecutor.mqh |
//|                       OmakFxYO — Add Executor |
//+------------------------------------------------------------------+
#ifndef OMAK_ADDEXECUTOR_MQH
#define OMAK_ADDEXECUTOR_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "C3 pyramidal add execution — C3 to add conversion"

#property description "NO campaign creation, NO signal detection, NO HTF logic"

//+------------------------------------------------------------------+
//| INCLUDES — Reference Only                                     |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>          // ENUM_DIRECTION, ENUM_EXECUTION_BRANCH
#include <OmakFxYO/core/ClosureEngine.mqh>     // SClosureSignal, ENUM_CLOSURE_TYPE
#include <OmakFxYO/core/BranchContextExt.mqh> // SBranchCampaignContext
#include <OmakFxYO/core/CampaignState.mqh>    // ENUM_CAMPAIGN_STATE
#include <OmakFxYO/core/CampaignData.mqh>     // SCampaign, SAddInfo
#include <OmakFxYO/core/CampaignManager.mqh>  // CM_AddSwingLayer, etc.
// REGRESSION_GUARD_V52.5_ADD_RISKGATE_INCLUDE_REMOVED: Execution authority delegated externally
// RiskGate include removed — AddExecutor no longer calls ExecuteMarketOrder

extern bool   g_blockNewEntries;   // Entry block flag from risk compliance engine
// REGRESSION_GUARD_V52.5_ADD_BLOCK_ENTRIES

// Forward declarations for canonical swing detection (defined in PositionManager.mqh)
// REGRESSION_GUARD_V52.5_PSL_PSH_REUSE: Consolidated to single canonical implementation
bool PM_DetectPSL(string symbol, ENUM_TIMEFRAMES tf, double &pslLow);
bool PM_DetectPSH(string symbol, ENUM_TIMEFRAMES tf, double &pshHigh);

//+------------------------------------------------------------------+
//| INITIALIZATION — AE_Initialize                              |
//+------------------------------------------------------------------+

/**
 * AE_Initialize
 *
 * Initialize add executor.
 */
void AE_Initialize()
{
   LogPrint("[AE] Add Executor initialized", LOG_LEVEL_INFO);
}

//+------------------------------------------------------------------+
//| ADD CONDITION CHECK — AE_EvaluateAdd                        |
//+------------------------------------------------------------------+

/**
 * AE_EvaluateAdd
 *
 * Evaluate if C3 signal should become an add.
 *
 * CORE ADD LOGIC (STRICT):
 *
 * isAdd =
 *   campaignActive
 *   AND signalType == C3
 *   AND direction aligned
 *   AND HTF aligned
 *   AND profit >= MinProfitForAdd
 *   AND SL protected
 *   AND addCount < MaxAdds
 *   AND expansion >= MinAddExpansion
 *   AND structureBreak == TRUE
 *
 * Returns: true if add CAN be executed (NOT execution itself)
 */
bool AE_EvaluateAdd(
   ENUM_EXECUTION_BRANCH branch,
   SClosureSignal &signal,
   double currentProfitR,
   double priceExpansionR
)
{
   // MUST be C3 signal
   if(signal.type != CLOSURE_C3)
      return false;

   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;
   SAddConditions *cond = &ctx.addConditions;

   // === GATE 1: Campaign Active ===
   if(camp.state != CAMPAIGN_ACTIVE && camp.state != CAMPAIGN_ADDING)
      return false;

   // === GATE 2: C3 Signal ===
   // (already checked above)

   // === GATE 3: Direction Alignment ===
   ENUM_DIRECTION signalDir = signal.is_bullish ? DIRECTION_BUY : DIRECTION_SELL;
   if(signalDir != camp.direction)
      return false;

   // === GATE 4: HTF Alignment ===
   if(cond.htfAlignRequired && !camp.biasAligned)
      return false;

   // === GATE 5: Profit Requirement ===
   if(currentProfitR < cond.minProfitR)
      return false;

   // === GATE 6: SL Protection ===
   if(cond.slProtectedRequired && !camp.slProtected)
      return false;

   // === GATE 7: Add Count Limit ===
   if(camp.addCount >= cond.maxAdds)
      return false;

   // === GATE 8: Expansion Requirement ===
   if(priceExpansionR < cond.minExpansionR)
      return false;

   // === GATE 9: Structure Break ===
   if(cond.structureBreakRequired)
   {
      if(!AE_StructureBreakDetected(branch, signal, camp))
         return false;
   }

   // All gates passed
   return true;
}

//+------------------------------------------------------------------+
//| STRUCTURE BREAK DETECTION — AE_StructureBreakDetected          |
//+------------------------------------------------------------------+

/**
 * AE_StructureBreakDetected
 *
 * Detect if structure break occurred after last add.
 *
 * LOGIC:
 *   BUY: Price made higher high after last add
 *   SELL: Price made lower low after last add
 *
 * Uses last add price as reference.
 */
bool AE_StructureBreakDetected(
   ENUM_EXECUTION_BRANCH branch,
   SClosureSignal &signal,
   SCampaign *camp
)
{
   double lastRefPrice = camp.seedPrice;

   // If adds exist, use last add price
   if(camp.addCount > 0)
   {
      SAddInfo *lastAdd = &camp.adds[camp.addCount];
      lastRefPrice = lastAdd.price;
   }

   double currentPrice = signal.entry_price;

   // structureBreak logic
   if(camp.direction == DIRECTION_BUY)
   {
      // Higher high (BUY campaign)
      return (currentPrice > lastRefPrice);
   }
   else if(camp.direction == DIRECTION_SELL)
   {
      // Lower low (SELL campaign)
      return (currentPrice < lastRefPrice);
   }

   return false;
}

//+------------------------------------------------------------------+
//| EXPANSION VALIDATION — AE_ValidateExpansion                 |
//+------------------------------------------------------------------+

/**
 * AE_ValidateExpansion
 *
 * Validate price expansion meets minimum requirement.
 *
 * Returns expansion in R units.
 */
double AE_ValidateExpansion(
   ENUM_EXECUTION_BRANCH branch,
   double currentPrice
)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;

   if(!camp.isActive || camp.seedPrice == 0.0)
      return 0.0;

   double lastRefPrice = camp.seedPrice;

   if(camp.addCount > 0)
   {
      lastRefPrice = camp.adds[camp.addCount].price;
   }

   // Calculate expansion
   double priceDiff = MathAbs(currentPrice - lastRefPrice);
   double expansionR = 0.0;

   // Convert to R (assuming camp.seedSL holds R stop)
   if(camp.seedSL > 0)
   {
      // R = price difference / stop distance
      double stopDist = MathAbs(camp.seedPrice - camp.seedSL);
      if(stopDist > 0)
         expansionR = priceDiff / stopDist;
   }

   return expansionR;
}

//+------------------------------------------------------------------+
//| ADD COUNT — AE_GetAddCount                                   |
//+------------------------------------------------------------------+

/**
 * AE_GetAddCount
 *
 * Get current add count for campaign.
 */
int AE_GetAddCount(ENUM_EXECUTION_BRANCH branch)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   return ctx.activeCampaign.addCount;
}

//+------------------------------------------------------------------+
//| EXECUTION PARAMETERS — AE_GetAddParameters                    |
//+------------------------------------------------------------------+

/**
 * AE_GetAddParameters
 *
 * Get lot size for add order.
 *
 * LOT RULE:
 *   Add lot = seedLot * addLotMultiplier
 *   (from SAddConditions)
 */
double AE_GetAddLot(ENUM_EXECUTION_BRANCH branch)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;
   SAddConditions *cond = &ctx.addConditions;

   return camp.seedLot * cond.addLotMultiplier;
}

/**
 * AE_GetAddPrice
 *
 * Get entry price for add.
 * Uses current market price or signal price.
 */
double AE_GetAddPrice(ENUM_EXECUTION_BRANCH branch, SClosureSignal &signal)
{
   return signal.entry_price;
}

/**
 * AE_GetAddSL
 *
 * Get stop loss for add.
 * Typically same as seed SL (aggregate SL model).
 */
double AE_GetAddSL(ENUM_EXECUTION_BRANCH branch)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   return ctx.activeCampaign.campaignSL;
}

//+------------------------------------------------------------------+
//| EXECUTION PLACEHOLDER — AE_ExecuteAdd                       |
//+------------------------------------------------------------------+

/**
 * AE_ExecuteAdd
 *
 * Execute add order.
 *
 * EXECUTION RULE:
 *   - Creates NEW order (hedging model)
 *   - Assigns campaign ID
 *   - Assigns branch magic number
 *   - Assigns add index
 *   - Updates campaign via CampaignManager
 *
 * NOTE: This is a PLACEHOLDER.
 * Actual OrderSend MUST be in OrderManager.
 */
bool AE_ExecuteAdd(
   ENUM_EXECUTION_BRANCH branch,
   SClosureSignal &signal,
   double currentProfitR,
   double expansionR,
   int &ticket
)
{
   // Evaluate first
   if(!AE_EvaluateAdd(branch, signal, currentProfitR, expansionR))
      return false;

   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;
   SAddConditions *cond = &ctx.addConditions;

   // Get execution parameters
   double addLot = AE_GetAddLot(branch);
   double addPrice = AE_GetAddPrice(branch, signal);
   double addSL = AE_GetAddSL(branch);

   // NOTE: Actual order execution happens in OrderManager
   // This function prepares parameters and records success

   // Record add in campaign (will be called by OrderManager post-execution)
   // CM_RecordAdd will be called AFTER OrderManager confirms fill

   // Set flag for OrderManager to process
   // (actual execution through OrderManager.ExecuteTrade with isAdd=true)

   ticket = 0; // Will be filled by OrderManager

LogPrint("[AE] Add APPROVED | Branch=" + EnumToString(branch) + " | ID=" + IntegerToString(camp.campaignId) +
          " | Add#=" + IntegerToString(camp.addCount + 1) + " | Price=" + DoubleToString(addPrice, _Digits) +
          " | Lot=" + DoubleToString(addLot, 2) + " | ExpansionR=" + DoubleToString(expansionR, 2), LOG_LEVEL_INFO);

   return true;
}

// AE_DetectPSL/PSH removed — consolidated to canonical PM_DetectPSL/PSH in PositionManager.mqh
// REGRESSION_GUARD_V52.5_PSL_PSH_REUSE: No duplicate swing detection; single canonical source

//+------------------------------------------------------------------+
//| SWING CONDITION — AE_HasNewProtectedSwing                     |
//+------------------------------------------------------------------+

/**
 * AE_HasNewProtectedSwing
 *
 * Check if a new confirmed Protected Swing has formed on the entry TF
 * since the last pyramid layer was added.
 *
 * For BUY campaigns: detects new Protected Swing Low (PSL).
 * For SELL campaigns: detects new Protected Swing High (PSH).
 *
 * Compares swing time with the campaign's lastSwingTime to ensure
 * the swing is newer than the last add.
 */
bool AE_HasNewProtectedSwing(
   ENUM_EXECUTION_BRANCH branch,
   ENUM_DIRECTION direction,
   ENUM_TIMEFRAMES entryTf,
   double &swingPrice
)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;

   double detectedPrice = 0.0;
   bool found = false;

   if(direction == DIRECTION_BUY)
   {
      found = PM_DetectPSL(_Symbol, entryTf, detectedPrice);
   }
   else if(direction == DIRECTION_SELL)
   {
      found = PM_DetectPSH(_Symbol, entryTf, detectedPrice);
   }

   if(!found)
      return false;

   // Must be a NEW swing: swing bar time must be after last recorded swing time
   // Scan from bar 1 (most recent closed bar) backwards to find when this swing formed
   for(int bar = 1; bar < 20; bar++)
   {
      if(direction == DIRECTION_BUY)
      {
         double barLow = iLow(_Symbol, entryTf, bar);
         if(MathAbs(barLow - detectedPrice) <= _Point)
         {
            datetime swingBarTime = iTime(_Symbol, entryTf, bar);
            if(swingBarTime <= camp.lastSwingTime)
               return false;
            break;
         }
      }
      else
      {
         double barHigh = iHigh(_Symbol, entryTf, bar);
         if(MathAbs(barHigh - detectedPrice) <= _Point)
         {
            datetime swingBarTime = iTime(_Symbol, entryTf, bar);
            if(swingBarTime <= camp.lastSwingTime)
               return false;
            break;
         }
      }
   }

   swingPrice = detectedPrice;
   return true;
}

//+------------------------------------------------------------------+
//| SWING ADD EVALUATION — AE_EvaluateSwingAdd                    |
//+------------------------------------------------------------------+

/**
 * AE_EvaluateSwingAdd
 *
 * Evaluate if a swing-based add is valid for an active campaign.
 *
 * GATES:
 *   1. Campaign is ACTIVE or ADDING
 *   2. Direction matches campaign
 *   3. HTF alignment (if required)
 *   4. Profit >= minProfitR
 *   5. SL protected (if required)
 *   6. Add count < max
 *   7. HasNewProtectedSwing
 *   8. Expansion >= minExpansionR
 */
bool AE_EvaluateSwingAdd(
   ENUM_EXECUTION_BRANCH branch,
   ENUM_DIRECTION direction,
   ENUM_TIMEFRAMES entryTf,
   double currentProfitR
)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;
   SAddConditions *cond = &ctx.addConditions;

   // === GATE 1: Campaign Active ===
   if(camp.state != CAMPAIGN_ACTIVE && camp.state != CAMPAIGN_ADDING)
      return false;

   // === GATE 2: Direction Alignment ===
   if(direction != camp.direction)
      return false;

   // === GATE 3: HTF Alignment ===
   if(cond.htfAlignRequired && !camp.biasAligned)
      return false;

   // === GATE 4: Profit Requirement ===
   if(currentProfitR < cond.minProfitR)
      return false;

   // === GATE 5: SL Protection ===
   if(cond.slProtectedRequired && !camp.slProtected)
      return false;

   // === GATE 6: Add Count Limit ===
   if(camp.addCount >= cond.maxAdds)
      return false;

   // === GATE 7: Protected Swing ===
   double swingPrice = 0.0;
   if(!AE_HasNewProtectedSwing(branch, direction, entryTf, swingPrice))
   {
      LogPrint("[PYRAMID_SWING_WAIT] Branch=" + EnumToString(branch) +
               " | Dir=" + (direction == DIRECTION_BUY ? "BUY" : "SELL") +
               " | campaignID=" + IntegerToString(camp.campaignId) +
               " | addCount=" + IntegerToString(camp.addCount), LOG_LEVEL_DEBUG);
      return false;
   }

   // Calculate expansion from last add/seed to swing price
   double lastRefPrice = (camp.addCount > 0) ? camp.adds[camp.addCount].price : camp.seedPrice;
   double priceDiff = MathAbs(swingPrice - lastRefPrice);
   double expansionR = 0.0;
   if(camp.seedSL > 0)
   {
      double stopDist = MathAbs(camp.seedPrice - camp.seedSL);
      if(stopDist > 0)
         expansionR = priceDiff / stopDist;
   }

   // === GATE 8: Expansion Requirement ===
   if(expansionR < cond.minExpansionR)
   {
      LogPrint("[PYRAMID_SWING_WAIT] Expansion too small | Branch=" + EnumToString(branch) +
               " | expansionR=" + DoubleToString(expansionR, 2) +
               " | min=" + DoubleToString(cond.minExpansionR, 2), LOG_LEVEL_DEBUG);
      return false;
   }

   // All gates passed
   return true;
}

//+------------------------------------------------------------------+
//| DECLINING LOT — AE_GetSwingAddLot                             |
//+------------------------------------------------------------------+

/**
 * AE_GetSwingAddLot
 *
 * Compute add lot size with declining risk factor.
 *
 * FORMULA:
 *   baseRiskAmount = equity * InpRiskPercent / 100.0
 *   layerRiskAmount = baseRiskAmount * pow(InpPyramidRiskFactor, currentLayerCount)
 *   addLot = layerRiskAmount / (slDistance * tickValue / tickSize)
 *
 * The declining factor means:
 *   Layer 1: 70% of base
 *   Layer 2: 49% of base (0.70^2)
 *   Layer 3: 34% of base (0.70^3)
 */
double AE_GetSwingAddLot(ENUM_EXECUTION_BRANCH branch)
{
   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      equity = AccountInfoDouble(ACCOUNT_BALANCE);
   if(equity <= 0.0)
      return 0.0;

   // Base risk amount for ONE full-risk trade
   double baseRiskAmount = equity * InpRiskPercent / 100.0;

   // Declining factor for this layer (0-indexed: first add = layer 1)
   int layer = camp.addCount + 1;  // 1, 2, 3...
   double factor = MathPow(g_InpPyramidRiskFactor, layer);
   double layerRiskAmount = baseRiskAmount * factor;

   // Use protected swing anchor for SL distance — Constitutional §4.2
   double slDistance = MathAbs(camp.seedPrice - camp.campaignSL);
   if(slDistance <= 0.0)
      return 0.0;

   SSymbolProfile spAdd = SY_GetProfile(_Symbol);
   if(!spAdd.isValid)
      return 0.0;

   // VERBATIM REPAIR: Manual tickValue/tickSize formula — no OrderCalcProfit
   double slDistAdd = MathAbs(camp.seedPrice - camp.campaignSL);
   double lossPerLot = (slDistAdd / spAdd.tickSize) * spAdd.tickValue;
   if(lossPerLot <= 0.0)
   {
       LogPrint("[LOT_CALC_FAIL] Manual formula -> lossPerLot <= 0 | sym=" + _Symbol +
                " | slDist=" + DoubleToString(slDistAdd, _Digits) +
                " | tickSize=" + DoubleToString(spAdd.tickSize, 8) +
                " | tickValue=" + DoubleToString(spAdd.tickValue, 8), LOG_LEVEL_WARN);
       return 0.0;
   }

   double lot = layerRiskAmount / lossPerLot;

   // Clamp to min/max lot from profile — no upward forcing
   double minLot = spAdd.volumeMin;
   double maxLot = spAdd.volumeMax;
   double lotStep = spAdd.volumeStep;

   if(lot <= 0.0)
   {
       LogPrint("[AE_LOT] Lot <= 0 | sym=" + _Symbol, LOG_LEVEL_DEBUG);
       return 0.0;
   }

    // IsLotTradeable check — same rules as primary entries
    if(!IsLotTradeable(slDistance / spAdd.point, spAdd.tickValue, minLot,
                        equity, InpRiskPercent, _Symbol,
                        camp.seedPrice, camp.campaignSL, camp.direction == DIRECTION_BUY))
   {
       LogPrint("[RISK_GATE] AE_GetSwingAddLot IsLotTradeable failed" +
                " | minLot=" + DoubleToString(minLot, 4) +
                " | sym=" + _Symbol, LOG_LEVEL_WARN);
       return 0.0;
   }

    if(lot < minLot)
     {
        LogPrint("[AE_LOT] Lot=" + DoubleToString(lot, 4) +
                 " < minLot=" + DoubleToString(minLot, 4) +
                 " | sym=" + _Symbol + " — rejecting (no upward force)", LOG_LEVEL_WARN);
        return 0.0;
     }
     if(lot > maxLot) lot = maxLot;

    // Margin feasibility check — same as primary entry path
    double marginRequired = 0.0;
    ENUM_ORDER_TYPE orderType = (camp.direction == DIRECTION_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    if(!OrderCalcMargin(orderType, _Symbol, lot, camp.seedPrice, marginRequired))
    {
        LogPrint("[AE_LOT] OrderCalcMargin failed | sym=" + _Symbol, LOG_LEVEL_WARN);
        return 0.0;
    }
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    if(freeMargin - marginRequired < 0.0)
    {
        LogPrint("[AE_LOT] Insufficient margin | required=" + DoubleToString(marginRequired, 2) +
                 " | free=" + DoubleToString(freeMargin, 2) +
                 " | sym=" + _Symbol, LOG_LEVEL_WARN);
        return 0.0;
    }

   // Round to lot step
   if(lotStep > 0.0)
      lot = MathFloor(lot / lotStep) * lotStep;

   if(lot <= 0.0 || lot < minLot)
   {
       LogPrint("[AE_LOT] Lot zero or below minLot after step | sym=" + _Symbol, LOG_LEVEL_WARN);
       return 0.0;
   }

   return NormalizeDouble(lot, 2);
}

// AE_SendSwingAddOrder REMOVED: Execution authority delegated externally (OmakFxYO.mq5 call site)
// REGRESSION_GUARD_V52.5_NO_EXECUTION_AUTHORITY: AddExecutor is evaluation-only

//+------------------------------------------------------------------+
//| MAIN ENTRY — AE_CheckSwingAdd (called from OnTick)             |
//+------------------------------------------------------------------+

/**
 * AE_CheckSwingAdd
 *
 * Main entry point for swing-based pyramiding evaluation.
 * Called from OnTick (once per new bar on entry TF).
 *
 * EVALUATION-ONLY: Returns true with output params if add is approved.
 * Execution authority delegated externally to OmakFxYO.mq5 call site.
 *
 * Flow:
 *   1. Check pyramiding enabled
 *   2. Check campaign active
 *   3. Evaluate swing add conditions
 *   4. Calculate lot with declining factor
 *   5. Check portfolio heat cap
 *   6. Return approved parameters for external execution
 */
bool AE_CheckSwingAdd(
   ENUM_EXECUTION_BRANCH branch,
   ENUM_TIMEFRAMES entryTf,
   ENUM_DIRECTION &outDirection,
   double &outLot,
   double &outPrice,
   double &outSL,
   double &outExpansionR
)
{
   outDirection = DIRECTION_NONE;
   outLot = 0.0;
   outPrice = 0.0;
   outSL = 0.0;
   outExpansionR = 0.0;

   // Only run once per new bar on entry TF
   static datetime s_lastCheckBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, entryTf, 0);
   if(currentBarTime == s_lastCheckBarTime) return false;
   s_lastCheckBarTime = currentBarTime;

   // Gate: global entry halt from risk compliance engine
   if(g_blockNewEntries)
   {
      LogPrint("[RISK_GATE] PYRAMID_BLOCKED | g_blockNewEntries=true | Branch=" + EnumToString(branch), LOG_LEVEL_WARN);
      return false;
   }

   // Gate: pyramiding must be enabled
   if(!g_InpEnablePyramiding)
      return false;

   // Gate: must have positions
   if(PositionsTotal() == 0)
      return false;

   SBranchCampaignContext *ctx = GetBranchCampaignContext(branch);
   SCampaign *camp = &ctx.activeCampaign;

   // Gate: campaign must be active or adding
   if(camp.state != CAMPAIGN_ACTIVE && camp.state != CAMPAIGN_ADDING)
      return false;

   ENUM_DIRECTION direction = camp.direction;

   // Evaluate swing add conditions
   if(!AE_EvaluateSwingAdd(branch, direction, entryTf, camp.currentProfitR))
      return false;

   // Calculate declining lot
   double addLot = AE_GetSwingAddLot(branch);
   if(addLot <= 0.0)
   {
      LogPrint("[PYRAMID_ADD] Invalid lot | Branch=" + EnumToString(branch), LOG_LEVEL_WARN);
      return false;
   }

SSymbolProfile spAdd2 = SY_GetProfile(_Symbol);
    if(!spAdd2.isValid)
       return false;

    // Check portfolio heat cap via IsPyramidHeatCapSafe — uses OrderCalcProfit accuracy
    double currentPrice = (direction == DIRECTION_BUY) ?
       ((spAdd2.tickAsk > 0.0) ? spAdd2.tickAsk : SymbolInfoDouble(_Symbol, SYMBOL_ASK))
       : ((spAdd2.tickBid > 0.0) ? spAdd2.tickBid : SymbolInfoDouble(_Symbol, SYMBOL_BID));
    double addSL = camp.campaignSL;
    // VERBATIM REPAIR: Manual formula — no OrderCalcProfit (avoids 100x pips mode inflation)
    double riskAmount = MathAbs(currentPrice - addSL) * addLot * spAdd2.tickValue;
    LogPrint("[LOT_CALCPROFIT] pyramid heat | sym=" + _Symbol +
             " | volume=" + DoubleToString(addLot, 4) +
             " | entry=" + DoubleToString(currentPrice, _Digits) +
             " | sl=" + DoubleToString(addSL, _Digits) +
             " | rawProfit=" + DoubleToString(riskAmount, 2) +
             " | source=formula", LOG_LEVEL_DEBUG);

   if(!IsPyramidHeatCapSafe(riskAmount))
   {
      LogPrint("[RISK_GATE] PYRAMID_HEAT_CAP_BLOCKED | risk=" + DoubleToString(riskAmount, 2) +
                " | Branch=" + EnumToString(branch), LOG_LEVEL_WARN);
      return false;
   }

   // Compute expansion from last add/seed to current price
   double lastRefPrice = (camp.addCount > 0) ? camp.adds[camp.addCount].price : camp.seedPrice;
   double priceDiff = MathAbs(currentPrice - lastRefPrice);
   double expansionR = 0.0;
   if(camp.seedSL > 0)
   {
      double stopDist = MathAbs(camp.seedPrice - camp.seedSL);
      if(stopDist > 0)
         expansionR = priceDiff / stopDist;
   }

   // All gates passed — set output params for external execution
   outDirection = direction;
   outLot = addLot;
   outPrice = currentPrice;
   outSL = addSL;
   outExpansionR = expansionR;

   LogPrint("[AE] Add APPROVED | Branch=" + EnumToString(branch) +
            " | Add#=" + IntegerToString(camp.addCount + 1) +
            " | Price=" + DoubleToString(currentPrice, _Digits) +
            " | Lot=" + DoubleToString(addLot, 2) +
            " | ExpansionR=" + DoubleToString(expansionR, 2), LOG_LEVEL_INFO);

   return true;
}

//+------------------------------------------------------------------+
//| HELPER — GetReferenceOnly                                      |
//+------------------------------------------------------------------+

/**
 * GetBranchCampaignContext — Reference only
 * (defined in CampaignManager.mqh)
 */
SBranchCampaignContext *GetBranchCampaignContext(ENUM_EXECUTION_BRANCH branch);

//+------------------------------------------------------------------+
//| END OF FILE                                                  |
//+------------------------------------------------------------------+
#endif // OMAK_ADDEXECUTOR_MQH