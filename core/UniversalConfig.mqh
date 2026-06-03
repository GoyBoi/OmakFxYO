//+------------------------------------------------------------------+
 //| UniversalConfig.mqh                                              |
 //| Macro-Only Mapping Layer — Maps Inp* to g_Inp* globals           |
 //+------------------------------------------------------------------+
#ifndef OMAK_UNIVERSALCONFIG_MQH
#define OMAK_UNIVERSALCONFIG_MQH

#ifndef OMAK_INPUT_MACROS_DEFINED
#define OMAK_INPUT_MACROS_DEFINED

#define InpBranch                    g_InpBranch
#define InpMagicNumber               g_InpMagicNumber
#define InpEnableTrace               g_InpEnableTrace
#define InpUseDisplacementEngine     g_InpUseDisplacementEngine
#define InpMaxSignalsPerBranch       g_InpMaxSignalsPerBranch
#define InpUseTickIterator           g_InpUseTickIterator
#define InpLogLevel                  g_InpLogLevel

// Branch A parameters
#define InpA_C2_WickThreshold        g_InpA_C2_WickThreshold
#define InpA_C2_MinWickRatio         g_InpA_C2_MinWickRatio
#define InpA_C2_MinBodyRatio         g_InpA_C2_MinBodyRatio
#define InpA_C3_BodyMultiplier       g_InpA_C3_BodyMultiplier
#define InpA_C3_DisplacementMultiplier g_InpA_C3_DisplacementMultiplier
  #define InpA_C3_RangeExpansionFactor g_InpA_C3_RangeExpansionFactor
  #define InpA_RG_BufferPercent        g_InpA_RG_BufferPercent
#define InpA_RG_MarketThreshold      g_InpA_RG_MarketThreshold
#define InpA_LimitExpirationBars     g_InpA_LimitExpirationBars

 // Branch B parameters
 #define InpB_C2_WickThreshold        g_InpB_C2_WickThreshold
 #define InpB_C2_MinWickRatio         g_InpB_C2_MinWickRatio
 #define InpB_C2_MinBodyRatio         g_InpB_C2_MinBodyRatio
 #define InpB_C3_BodyMultiplier       g_InpB_C3_BodyMultiplier
 #define InpB_C3_DisplacementMultiplier g_InpB_C3_DisplacementMultiplier
  #define InpB_C3_RangeExpansionFactor g_InpB_C3_RangeExpansionFactor
  #define InpB_RG_BufferPercent        g_InpB_RG_BufferPercent
 #define InpB_RG_MarketThreshold      g_InpB_RG_MarketThreshold
 #define InpB_LimitExpirationBars     g_InpB_LimitExpirationBars

#endif // OMAK_INPUT_MACROS_DEFINED

#endif // OMAK_UNIVERSALCONFIG_MQH