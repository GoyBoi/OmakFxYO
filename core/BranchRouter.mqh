//+------------------------------------------------------------------+
//|                                          BranchRouter.mqh |
//|                           OmakFxYO — Branch Router |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_BRANCHROUTER_MQH
#define OMAK_BRANCHROUTER_MQH

#property strict

#property copyright "OMAK"
#property version   "1.00"
#property description "Branch Router — Branch A & B Timeframe Enforcement"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>    // ENUM_EXECUTION_BRANCH
#include <OmakFxYO/core/LogGovernor.mqh>  // LogPrint macro
#include <OmakFxYO/core/UniversalConfig.mqh>  // Inp* → g_Inp* macros

//+------------------------------------------------------------------+
//| SBranchTimeframes — Branch Timeframe Chain                       |
//+------------------------------------------------------------------+
/**
 * SBranchTimeframes
 * 
 * Contains the complete 3-TF chain for each branch.
 * 
 * Branch A (Intraday):
 *   D1 (Bias) → H1 (Structure) → M5 (Entry)
 * 
 * Branch B (Swing):
 *   W1 (Bias) → H4 (Structure) → M15 (Entry)
 */
struct BranchConfig
{
   ENUM_TIMEFRAMES bias;
   ENUM_TIMEFRAMES structure;
   ENUM_TIMEFRAMES entry;
};

struct SBranchTimeframes
{
    ENUM_TIMEFRAMES biasTF;
    ENUM_TIMEFRAMES structureTF;
    ENUM_TIMEFRAMES entryTF;
    
    void SBranchTimeframes()
    {
       Reset();
    }
    
    void Reset()
    {
       // Default to Branch B (Swing) config — safe neutral default
       biasTF = PERIOD_D1;
       structureTF = PERIOD_H4;
       entryTF = PERIOD_M15;
    }
};

//+------------------------------------------------------------------+
//| BRANCH ROUTING — 3-TF CHAIN                                      |
//+------------------------------------------------------------------+

/**
 * GetBranchTimeframes — Get complete 3-TF chain for branch
 *
 * Branch A (Intraday):  D1 (Bias) → H1 (Structure) → M5 (Entry)
 * Branch B (Swing):    D1 (Bias) → H4 (Structure) → M15 (Entry)
 *
 * NOTE: biasTF is fixed to D1 (daily) for both branches to maintain
 * consistent top-down bias alignment (Dow Theory). StructureTF differs.
 *
 * @param branch Branch type (INTRADAY or SWING)
 * @return SBranchTimeframes with bias/structure/entry TFs
 */
SBranchTimeframes GetBranchTimeframes(ENUM_EXECUTION_BRANCH branch)
{
    SBranchTimeframes tf;

    if(branch == BRANCH_INTRADAY)
    {
        tf.biasTF = PERIOD_D1;      // Branch A: Daily bias
        tf.structureTF = PERIOD_H1; // Intraday structure on H1
        tf.entryTF = PERIOD_M5;     // Entry on M5
    }
    else // BRANCH_SWING
    {
        tf.biasTF = PERIOD_D1;      // Branch B: Daily bias
        tf.structureTF = PERIOD_H4; // Swing structure on H4
        tf.entryTF = PERIOD_M15;    // Entry on M15
    }

    return tf;
}

/**
 * GetBranchConfig — Get branch configuration (centralized source)
 *
 * @param branch Branch type
 * @return BranchConfig with bias/structure/entry TFs
 */
BranchConfig GetBranchConfig(ENUM_EXECUTION_BRANCH branch)
{
    BranchConfig cfg;

    if(branch == BRANCH_INTRADAY)
    {
       cfg.bias = PERIOD_D1;      // Branch A: Daily bias (Dow Theory alignment)
       cfg.structure = PERIOD_H1;
       cfg.entry = PERIOD_M5;
    }
    else if(branch == BRANCH_SWING)
     {
        cfg.bias      = PERIOD_D1;      // Branch B: Daily bias (Dow Theory alignment)
        cfg.structure = PERIOD_H4;
        cfg.entry     = PERIOD_M15;
     }
     else
     {
        LGovPrint("[BR] CRITICAL: GetBranchConfig() invalid branch=" +
                  IntegerToString((int)branch), LOG_LEVEL_DEBUG);
        // Return Branch A config as safe fallback (D1 bias per constitution)
        cfg.bias      = PERIOD_D1;
        cfg.structure = PERIOD_H1;
        cfg.entry     = PERIOD_M5;
     }

    return cfg;
}

/**
 * GetBiasTF — Get bias timeframe for branch
 *
 * FIXED v55.1: Both branches use D1 for bias alignment per the constitution.
 *   "D1 bias alignment mandatory. Branches A/B mutually exclusive."
 *   The D1 bias provides the mechanical daily candle rule (Dow Theory)
 *   that gates both branches. StructureTF and EntryTF are what differ.
 *
 * Branch A (Intraday): D1 (Bias) → H1 (Structure) → M5 (Entry)
 * Branch B (Swing):    D1 (Bias) → H4 (Structure) → M15 (Entry)
 *
 * @param branch Branch type
 * @return Bias timeframe (D1 for both branches)
 */
ENUM_TIMEFRAMES GetBiasTF(ENUM_EXECUTION_BRANCH branch)
{
    return PERIOD_D1;   // Both branches: D1 bias (Dow Theory alignment)
}

/**
 * GetStructureTF — Get structure timeframe for branch
 *
 * Branch A: H4
 * Branch B: H1
 *
 * @param branch Branch type
 * @return Structure timeframe
 */
ENUM_TIMEFRAMES GetStructureTF(ENUM_EXECUTION_BRANCH branch)
{
    if(branch == BRANCH_INTRADAY)
       return PERIOD_H1;
    else
       return PERIOD_H4;
}

/**
 * GetEntryTF — Get entry timeframe for branch
 *
 * Branch A: M15
 * Branch B: M5
 *
 * @param branch Branch type
 * @return Entry timeframe
 */
ENUM_TIMEFRAMES GetEntryTF(ENUM_EXECUTION_BRANCH branch)
{
    if(branch == BRANCH_INTRADAY)
       return PERIOD_M5;
    else
       return PERIOD_M15;
}

//+------------------------------------------------------------------+
//| TIMEFRAME VALIDATION                                             |
//+------------------------------------------------------------------+

/**
 * IsValidBranchTimeframe — Validate timeframe belongs to branch
 * 
 * Prevents timeframe mixing between branches.
 * 
 * @param tf Timeframe to validate
 * @param branch Branch type
 * @return true if timeframe belongs to branch
 */
bool IsValidBranchTimeframe(ENUM_TIMEFRAMES tf, ENUM_EXECUTION_BRANCH branch)
{
   SBranchTimeframes branchTF = GetBranchTimeframes(branch);
   
   return (tf == branchTF.biasTF || 
           tf == branchTF.structureTF || 
           tf == branchTF.entryTF);
}

/**
 * IsEntryTF — Check if timeframe is entry TF for branch
 * 
 * @param tf Timeframe to check
 * @param branch Branch type
 * @return true if entry TF
 */
bool IsEntryTF(ENUM_TIMEFRAMES tf, ENUM_EXECUTION_BRANCH branch)
{
   return (tf == GetEntryTF(branch));
}

/**
 * IsStructureTF — Check if timeframe is structure TF for branch
 * 
 * @param tf Timeframe to check
 * @param branch Branch type
 * @return true if structure TF
 */
bool IsStructureTF(ENUM_TIMEFRAMES tf, ENUM_EXECUTION_BRANCH branch)
{
   return (tf == GetStructureTF(branch));
}

/**
 * IsBiasTF — Check if timeframe is bias TF for branch
 * 
 * @param tf Timeframe to check
 * @param branch Branch type
 * @return true if bias TF
 */
bool IsBiasTF(ENUM_TIMEFRAMES tf, ENUM_EXECUTION_BRANCH branch)
{
   return (tf == GetBiasTF(branch));
}

/**
 * ValidateNoTimeframeMixing — Ensure no mixing between branches
 * 
 * @param tf1 First timeframe
 * @param tf2 Second timeframe
 * @return true if both belong to same branch
 */
bool ValidateNoTimeframeMixing(ENUM_TIMEFRAMES tf1, ENUM_TIMEFRAMES tf2)
{
   // Check if both belong to Branch A
   bool both_A = IsValidBranchTimeframe(tf1, BRANCH_INTRADAY) && 
                 IsValidBranchTimeframe(tf2, BRANCH_INTRADAY);
   
   // Check if both belong to Branch B
   bool both_B = IsValidBranchTimeframe(tf1, BRANCH_SWING) && 
                 IsValidBranchTimeframe(tf2, BRANCH_SWING);
   
   return (both_A || both_B);
}

//+------------------------------------------------------------------+
//| BRANCH LABELS                                                    |
//+------------------------------------------------------------------+

/**
 * GetBranchName — Get human-readable branch name
 * 
 * @param branch Branch type
 * @return Branch name
 */
string GetBranchName(ENUM_EXECUTION_BRANCH branch)
{
    if(branch == BRANCH_INTRADAY)
       return "Branch A (Intraday)";
    else
       return "Branch B (Swing)";
}

/**
 * GetBranchDescription — Get branch description with TF chain
 * 
 * @param branch Branch type
 * @return Description string
 */
string GetBranchDescription(ENUM_EXECUTION_BRANCH branch)
{
   SBranchTimeframes tf = GetBranchTimeframes(branch);
   
   string bias_str = TimeframeToString(tf.biasTF);
   string struct_str = TimeframeToString(tf.structureTF);
   string entry_str = TimeframeToString(tf.entryTF);
   
   if(branch == BRANCH_INTRADAY)
      return StringFormat("Branch A: %s → %s → %s", bias_str, struct_str, entry_str);
   else
      return StringFormat("Branch B: %s → %s → %s", bias_str, struct_str, entry_str);
}

/**
 * TimeframeToString — Convert ENUM_TIMEFRAMES to string
 * 
 * @param tf Timeframe enum
 * @return String representation
 */
string TimeframeToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| LOGGING                                                          |
//+------------------------------------------------------------------+

/**
 * LogBranchConfiguration — Log branch configuration
 * 
 * @param branch Branch type
 */
void LogBranchConfiguration(ENUM_EXECUTION_BRANCH branch)
{
   string contextMarker = (branch == BRANCH_INTRADAY) ? "BRANCH_A_CONTEXT" : "BRANCH_B_CONTEXT";
   LogPrint("[" + contextMarker + "] Configuration: " + GetBranchName(branch), LOG_LEVEL_INFO);
   LogPrint("[" + contextMarker + "] Timeframe Chain: " + GetBranchDescription(branch), LOG_LEVEL_INFO);
   LogPrint("[" + contextMarker + "] Bias TF: " + TimeframeToString(GetBiasTF(branch)), LOG_LEVEL_INFO);
   LogPrint("[" + contextMarker + "] Structure TF: " + TimeframeToString(GetStructureTF(branch)), LOG_LEVEL_INFO);
   LogPrint("[" + contextMarker + "] Entry TF: " + TimeframeToString(GetEntryTF(branch)), LOG_LEVEL_INFO);
}

/**
 * LogTimeframeUsage — Log timeframe usage for validation
 * 
 * @param function_name Function name
 * @param used_tf Timeframe used
 * @param expected_tf Expected timeframe
 * @param branch Branch type
 */
void LogTimeframeUsage(string function_name, 
                       ENUM_TIMEFRAMES used_tf, 
                       ENUM_TIMEFRAMES expected_tf,
                       ENUM_EXECUTION_BRANCH branch)
{
   if(used_tf != expected_tf)
   {
LogPrint("[BRANCH] WARNING: Timeframe mismatch in " + function_name, LOG_LEVEL_WARN);
       LogPrint("[BRANCH] Used: " + TimeframeToString(used_tf) + 
             " | Expected: " + TimeframeToString(expected_tf), LOG_LEVEL_WARN);
       LogPrint("[BRANCH] Branch: " + GetBranchName(branch), LOG_LEVEL_WARN);
   }
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+

#endif // OMAK_BRANCHROUTER_MQH
