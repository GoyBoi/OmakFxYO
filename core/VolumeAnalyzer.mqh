//+------------------------------------------------------------------+
//| VolumeAnalyzer.mqh                                               |
//|: Analyze volume for C3 confirmation                      |
//| Part of Omak FxYO — True TTrades Enhancement Framework           |
//+------------------------------------------------------------------+
#ifndef OMAK_VOLUMEANALYZER_MQH
#define OMAK_VOLUMEANALYZER_MQH

#property strict

#include <OmakFxYO/core/CoreTypes.mqh>  // STrueTTradesConfig, g_trueTTradesConfig
#include <OmakFxYO/core/MarketTypeDetector.mqh>

//+------------------------------------------------------------------+
//| Volume Analysis Structure                                        |
//+------------------------------------------------------------------+
/**
 * SVolumeAnalysis
 *
 * Holds volume metrics for a specific bar on a specific timeframe.
 * Used by C3 confirmation logic to validate institutional participation.
 */
struct SVolumeAnalysis
{
   bool               isValid;
   double             currentVolume;
   double             averageVolume;       // Average of last N bars (excluding current)
   double             expansionRatio;      // current / average
   bool               isExpanding;         // expansionRatio >= threshold
   bool               isDeclining;         // expansionRatio < 0.8
   bool               dataAvailable;       // False if CopyTickVolume fails
   string             analysisMessage;
};

//+------------------------------------------------------------------+
//| AnalyzeVolume — Get volume analysis for specified TF and bar     |
//+------------------------------------------------------------------+
/**
 * AnalyzeVolume
 *
 * Analyzes tick volume for the given bar index on the specified
 * timeframe. Compares current volume against a moving average
 * of the lookback window.
 *
 * @param tf        Timeframe to analyze
 * @param barIndex  Bar index (0 = current forming, 1 = last closed, etc.)
 * @param lookback  Number of bars for average calculation
 * @return SVolumeAnalysis with volume metrics
 */
SVolumeAnalysis AnalyzeVolume(ENUM_TIMEFRAMES tf, int barIndex = 1, int lookback = 10)
{
   SVolumeAnalysis result;
   result.isValid = false;
   result.currentVolume = 0.0;
   result.averageVolume = 0.0;
   result.expansionRatio = 0.0;
   result.isExpanding = false;
   result.isDeclining = false;
   result.dataAvailable = false;
   result.analysisMessage = "";

   // Check if volume is available for this symbol
   if(!SymbolInfoInteger(_Symbol, SYMBOL_VOLUME))
   {
      result.analysisMessage = "Volume not available for this symbol";
      return result;
   }

   // Get volume data
   long volumes[];
   ArraySetAsSeries(volumes, true);

   int needed = lookback + 1;
   if(CopyTickVolume(_Symbol, tf, 0, needed, volumes) < needed)
   {
      result.analysisMessage = "Failed to copy volume data (need " + IntegerToString(needed) + ")";
      return result;
   }

   result.dataAvailable = true;
   result.currentVolume = (double)volumes[barIndex];

   // Calculate average (excluding the bar being analyzed)
   double sum = 0.0;
   int count = 0;
   for(int i = barIndex + 1; i < needed; i++)
   {
      sum += (double)volumes[i];
      count++;
   }

   if(count > 0)
      result.averageVolume = sum / count;

   if(result.averageVolume > 0.0)
   {
      result.expansionRatio = result.currentVolume / result.averageVolume;
      result.isExpanding = (result.expansionRatio >= 1.2);  // Default 20% increase
      result.isDeclining = (result.expansionRatio < 0.8);
      result.isValid = true;
      result.analysisMessage = "Vol: " + DoubleToString(result.currentVolume, 0) +
                               " | Avg: " + DoubleToString(result.averageVolume, 0) +
                               " | Ratio: " + DoubleToString(result.expansionRatio, 2);
   }
   else
   {
      result.analysisMessage = "Average volume is zero";
   }

   return result;
}

//+------------------------------------------------------------------+
//| HasC3VolumeConfirmation — Check if C3 has volume expansion       |
//+------------------------------------------------------------------+
/**
 * HasC3VolumeConfirmation
 *
 * Returns true if C3 bar shows volume expansion above the
 * configured threshold. If volume confirmation is not enabled
 * via config, or the market type doesn't require it, returns true.
 *
 * @param tf  Structure timeframe (where C3 forms)
 * @return true if volume confirms C3, or if not required
 */
bool HasC3VolumeConfirmation(ENUM_TIMEFRAMES tf)
{
   // Not required by config → pass
   if(!g_trueTTradesConfig.useVolumeConfirmation)
      return true;

   // Not applicable for this market type → pass
   SMarketProfile profile = GetMarketProfile(_Symbol);
   if(!profile.requiresVolume)
      return true;

   // Analyze bar 1 (last closed bar = C3)
   SVolumeAnalysis vol = AnalyzeVolume(tf, 1, 10);

   if(!vol.isValid)
   {
      LogPrint("[VOLUME] Analysis failed: " + vol.analysisMessage, LOG_LEVEL_WARN);
      return false;  // If we can't analyze, be conservative
   }

   // Use configured threshold
   double threshold = g_trueTTradesConfig.minVolumeExpansion;
   vol.isExpanding = (vol.expansionRatio >= threshold);

   return vol.isExpanding;
}

//+------------------------------------------------------------------+
//| GetVolumeExpansionRatio — Quick access to current expansion      |
//+------------------------------------------------------------------+
double GetVolumeExpansionRatio(ENUM_TIMEFRAMES tf, int barIndex = 1)
{
   SVolumeAnalysis vol = AnalyzeVolume(tf, barIndex, 10);
   return vol.isValid ? vol.expansionRatio : 0.0;
}

//+------------------------------------------------------------------+
//| GetVolumeString — Human-readable volume summary                  |
//+------------------------------------------------------------------+
string GetVolumeString(ENUM_TIMEFRAMES tf, int barIndex = 1)
{
   SVolumeAnalysis vol = AnalyzeVolume(tf, barIndex, 10);
   return vol.analysisMessage;
}

#endif // OMAK_VOLUMEANALYZER_MQH
