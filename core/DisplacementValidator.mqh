//+------------------------------------------------------------------+
//|                                   DisplacementValidator.mqh |
//|                      OmakFxYO — Displacement Validator |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef OMAK_DISPLACEMENTVALIDATOR_MQH
#define OMAK_DISPLACEMENTVALIDATOR_MQH

#property strict
#property copyright "OMAK"
#property version   "1.00"
#property description "Displacement Validator — Strict Validation Module"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <OmakFxYO/core/CoreTypes.mqh>        // Base types
#include <OmakFxYO/core/ClosureEngine.mqh>    // displacement logic


//+------------------------------------------------------------------+
 //| SAFE DIVISION UTILITIES                                           |
 //+------------------------------------------------------------------+

double SafeDenominator(double value, string label)
  {
      if(fabs(value) < 1e-6 || !MathIsValidNumber(value))
      {
          LogPrint("[DV_GUARD] Division avoided | Den=" + label + "=" + DoubleToString(value, 8), LOG_LEVEL_DEBUG);
          return -1.0;
      }
      return value;
  }

double SafeDivide(double numerator, double denominator, string label, string context = "")
  {
      if(fabs(denominator) < 1e-6 || !MathIsValidNumber(denominator))
      {
          if(context != "")
              LogPrint("[DV_GUARD] Division avoided | " + context + " | Num=" + DoubleToString(numerator, 8) + " Den=" + label + "=" + DoubleToString(denominator, 8), LOG_LEVEL_DEBUG);
          else
              LogPrint("[DV_GUARD] Division avoided | Num=" + DoubleToString(numerator, 8) + " Den=" + label + "=" + DoubleToString(denominator, 8), LOG_LEVEL_DEBUG);
          return 0.0;
      }

      if(!MathIsValidNumber(numerator))
      {
          LogPrint("[DV_GUARD] Division avoided | Numerator=INVALID", LOG_LEVEL_DEBUG);
          return 0.0;
      }

      return numerator / denominator;
  }

 //+------------------------------------------------------------------+
 //| DISPLACEMENT SPECIFIC SAFE DIVISION HELPERS                      |
 //+------------------------------------------------------------------+

 double SafeBodyRangeDivide(double body, double range, string context = "")
 {
     return SafeDivide(body, range, "body/range", context);
 }

 double SafeWickRangeDivide(double wick, double range, string context = "")
 {
     return SafeDivide(wick, range, "wick/range", context);
 }

 double SafeDisplacementATRDivide(double displacement, double atr, string context = "")
 {
     return SafeDivide(displacement, atr, "displacement/ATR", context);
 }

 double SafeExpansionDivide(double currentRange, double prevRange, string context = "")
 {
     return SafeDivide(currentRange, prevRange, "rangeExpansion", context);
 }

//+------------------------------------------------------------------+
//| DisplacementConfig — Validator Configuration                     |
//+------------------------------------------------------------------+
/**
 * DisplacementConfig
 *
 * Configurable thresholds for displacement validation.
 * Based on input parameters with stricter defaults.
 */
struct DisplacementConfig
{
   double minBodyRatio;            // Minimum body ratio (default 0.3)
   double minRangeExpansion;       // Minimum range expansion vs prev bar (default 1.1)
   double closeToExtremeThreshold; // How close to extreme (default 0.7 = 70%)
   double minDisplacementStrength; // Minimum strength score (default 1.0)

   //+------------------------------------------------------------------+
   // | Reset — Set to default values                                  |
   //+------------------------------------------------------------------+
   void Reset()
   {
      minBodyRatio = 0.30;            // 30% minimum body-to-range ratio
      minRangeExpansion = 1.10;       // 10% expansion minimum
      closeToExtremeThreshold = 0.70; // Close within 70% of range
      minDisplacementStrength = 1.00; // 1.0x average body minimum
   }
};

//+------------------------------------------------------------------+
//| DisplacementOutput — Validation Result                           |
//+------------------------------------------------------------------+
/**
 * DisplacementOutput
 *
 * Contains displacement validation result and strength score.
 * DIRECTION-AGNOSTIC — only validates strength, not direction.
 */
struct DisplacementOutput
{
     bool isValid;               // Displacement valid (all rules pass)
     double strengthScore;       // 0.0 to 2.0+ scaled strength
     bool bodyRatioOk;           // Body ratio threshold met
     bool rangeExpansionOk;      // Range expansion threshold met
     bool closeToExtremeOk;      // Close near extreme threshold met
     datetime timestamp;         // When validation occurred
     int barCount;             // Number of bars in displacement leg (for dynamic expiry)

     //+------------------------------------------------------------------+
     // | Reset — Clear all fields to defaults                           |
     //+------------------------------------------------------------------+
     void Reset()
     {
        isValid = false;
        strengthScore = 0.0;
        bodyRatioOk = false;
        rangeExpansionOk = false;
        closeToExtremeOk = false;
        timestamp = 0;
        barCount = 0;
     }
};

//+------------------------------------------------------------------+
//| DisplacementContext — Persistent Validator Context                |
//+------------------------------------------------------------------+
/**
 * DisplacementContext
 *
 * Holds configuration and validation history.
 */
struct DisplacementContext
{
   DisplacementConfig config;            // Current configuration
   DisplacementOutput previous;       // Previous validation
   DisplacementOutput current;        // Current validation
   datetime lastValidTime;            // Last valid displacement
   int validCount;                    // Total valid displacements

   //+------------------------------------------------------------------+
   // | Reset — Clear all fields to defaults                           |
   //+------------------------------------------------------------------+
   void Reset()
   {
      config.Reset();
      previous.Reset();
      current.Reset();
      lastValidTime = 0;
      validCount = 0;
   }
};

//+------------------------------------------------------------------+
//| GLOBAL STATE — Displacement Validator Context                     |
//+------------------------------------------------------------------+
DisplacementContext g_dvContext;

//+------------------------------------------------------------------+
//| CORE LOGIC — DISPLACEMENT VALIDATION                             |
//+------------------------------------------------------------------+

/**
 * CalculateBodyRatio — Calculate body-to-range ratio
 *
 * @param open Open price
 * @param close Close price
 * @param high High price
 * @param low Low price
 * @return Body ratio (0.0 - 1.0)
 */
double CalculateBodyRatio(
    double open,
    double close,
    double high,
    double low
 )
{
     double body = MathAbs(close - open);
     double range = high - low;

     return SafeDivide(body, range, "candleRange", "CalculateBodyRatio");
}

/**
 * CalculateRangeExpansion — Calculate range expansion vs previous bar
 *
 * @param currentHigh Current bar high
 * @param currentLow Current bar low
 * @param prevHigh Previous bar high
 * @param prevLow Previous bar low
 * @return Range expansion ratio (1.0 = no expansion, >1.0 = expansion)
 */
double CalculateRangeExpansion(
    double currentHigh,
    double currentLow,
    double prevHigh,
    double prevLow
)
{
     double currentRange = currentHigh - currentLow;
     double prevRange = prevHigh - prevLow;

     return SafeDivide(currentRange, prevRange, "prevRange", "CalculateRangeExpansion");
}

/**
 * IsCloseToExtreme — Check if close is near high/low extreme
 *
 * BULLISH: Close in upper 30% of range (near high)
 * BEARISH: Close in lower 30% of range (near low)
 *
 * @param open Open price
 * @param close Close price
 * @param high High price
 * @param low Low price
 * @param threshold Threshold (0.7 = 70% toward extreme)
 * @return true if close is near extreme
 */
bool IsCloseToExtreme(
    double open,
    double close,
    double high,
    double low,
    double threshold
)
{
     double range = high - low;
     double rangeNormalized = SafeDivide(close - low, range, "extremeRange", "IsCloseToExtreme");
     
     if(rangeNormalized < 0)
        return false;

    // Bullish: close in upper portion (near high)
    bool bullishExtreme = (rangeNormalized >= threshold);

    // Bearish: close in lower portion (near low)
    bool bearishExtreme = (rangeNormalized <= (1.0 - threshold));

   // Direction-agnostic: either extreme is valid
   return (bullishExtreme || bearishExtreme);
}

/**
 * CalculateStrength — Calculate displacement strength score
 *
 * Scoring factors:
 *   - Body ratio contribution (0.0 - 1.0)
 *   - Range expansion contribution (0.0 - 1.0)
 *   - Close to extreme contribution (0.0 - 0.5)
 *
 * Total: 0.0 - 2.5+ (higher = stronger displacement)
 *
 * @param bodyRatio Body-to-range ratio
 * @param rangeExpansion Range expansion vs previous
 * @param closeToExtreme Close near extreme flag
 * @param config Displacement configuration
 * @return Strength score (0.0 - 2.5+)
 */
double CalculateStrength(
   double bodyRatio,
   double rangeExpansion,
   bool closeToExtreme,
   const DisplacementConfig &config
)
{
     double strength = 0.0;

     // Factor 1: Body ratio contribution (0.0 - 1.0)
     // Scaled: bodyRatio / minBodyRatio, capped at 1.0
     double bodyContrib = SafeDivide(bodyRatio, config.minBodyRatio, "minBodyRatio", "CalculateStrength");
     if(bodyContrib >= 0)
        strength += MathMin(bodyContrib, 1.0);

     // Factor 2: Range expansion contribution (0.0 - 1.0)
     // Scaled: (rangeExpansion - 1) / (minRangeExpansion - 1), capped at 1.0
     if(config.minRangeExpansion > 1.0)
     {
        double denom = config.minRangeExpansion - 1.0;
        double expContrib = SafeDivide(rangeExpansion - 1.0, denom, "rangeExpansionDenom", "CalculateStrength");
        if(expContrib >= 0)
        {
           expContrib = MathClamp(expContrib, 0.0, 1.0);
           strength += expContrib;
        }
     }
     else
     {
        // No expansion requirement
        if(rangeExpansion >= 1.0)
           strength += 1.0;
     }

    // Factor 3: Close to extreme contribution (0.0 - 0.5)
    if(closeToExtreme)
       strength += 0.5;

    return strength;
}

//+------------------------------------------------------------------+
//| MAIN VALIDATION FUNCTION                                         |
//+------------------------------------------------------------------+

/**
 * DV_Validate — Main displacement validation
 *
 * VALIDATION RULES (ALL must pass):
 *   1. BodyRatio >= minBodyRatio (configurable)
 *   2. RangeExpansion >= minRangeExpansion (configurable)
 *   3. Close near extreme (bullish = near high, bearish = near low)
 *
 * CRITICAL CONSTRAINTS:
 *   - Does NOT determine direction (direction-agnostic)
 *   - Only upgrades structure strength
 *   - Reusable across modules
 *
 * @param open Open price
 * @param close Close price
 * @param high High price
 * @param low Low price
 * @param prevHigh Previous bar high
 * @param prevLow Previous bar low
 * @param config Displacement configuration
 * @return DisplacementOutput with validation result
 */
DisplacementOutput DV_Validate(
     string symbol,
     double open,
     double close,
     double high,
     double low,
     double prevHigh,
     double prevLow,
     const DisplacementConfig &config,
     ENUM_TIMEFRAMES forTF = PERIOD_CURRENT
  )
{
     DisplacementOutput output;
     ZeroMemory(output);
     output.Reset();
     output.timestamp = TimeCurrent();

     // ─── STEP 0: STRUCTURAL RANGE CALCULATION ───
double c2Range = high - low;
     double atr = 0.0;
     double swingRange = 0.0;
     double structuralRange = 0.0;
     
// ATR removed — use C2 range as structural range
      structuralRange = c2Range;
      if(structuralRange <= 0 || !MathIsValidNumber(structuralRange))
      {
         LogWarn("[DISPLACEMENT] State=INVALID | Reason=STRUCTURAL_RANGE_INVALID | C2Range=" + DoubleToString(c2Range, 5));
         output.isValid = false;
         return output;
      }

    // ─── STEP 1: Calculate metrics ───
    double bodyRatio = CalculateBodyRatio(open, close, high, low);
    double rangeExpansion = CalculateRangeExpansion(high, low, prevHigh, prevLow);
    bool closeToExtreme = IsCloseToExtreme(open, close, high, low, config.closeToExtremeThreshold);

    // ─── STEP 2: Validate individual rules ───
    output.bodyRatioOk = (bodyRatio >= config.minBodyRatio);
    output.rangeExpansionOk = (rangeExpansion >= config.minRangeExpansion);
    output.closeToExtremeOk = closeToExtreme;

// ─── STEP 3: Calculate strength score ───
     output.strengthScore = CalculateStrength(bodyRatio, rangeExpansion, closeToExtreme, config);

     // ─── STEP 4: Calculate bar count for dynamic expiry ───
     output.barCount = (int)((c2Range > 0.0) ? (c2Range / structuralRange) * 10.0 : 5.0);
     output.barCount = (int)MathClamp((double)output.barCount, 3.0, 20.0);

     // ─── STEP 5: Determine validity (ALL rules must pass) ───
    output.isValid = (output.bodyRatioOk &&
                      output.rangeExpansionOk &&
                      output.closeToExtremeOk &&
                      output.strengthScore >= config.minDisplacementStrength);

    // ─── STEP 5: Logging ───
    if(output.isValid)
    {
       LogInfo("[DISPLACEMENT] State=VALID | Strength=" + DoubleToString(output.strengthScore, 2) + 
                " | BodyRatio=" + DoubleToString(bodyRatio, 3) + " | RangeExp=" + DoubleToString(rangeExpansion, 2));
    }
    else
    {
       string reason = "";
       if(!output.bodyRatioOk) reason += "BodyRatio_LOW ";
       if(!output.rangeExpansionOk) reason += "RangeExp_LOW ";
       if(!output.closeToExtremeOk) reason += "CloseToExtreme_FAIL ";
       if(output.strengthScore < config.minDisplacementStrength) reason += "Strength_LOW ";
       
       LogWarn("[DISPLACEMENT] State=INVALID | Reason=" + reason + 
                " | C2Range=" + DoubleToString(c2Range, 5) + 
                " | ATR=" + DoubleToString(atr, 5) + 
                " | StructuralRange=" + DoubleToString(structuralRange, 5));
    }

    return output;
}

//+------------------------------------------------------------------+
//| MAIN ENGINE FUNCTIONS                                            |
//+------------------------------------------------------------------+

/**
 * DV_Initialize — Initialize Displacement Validator
 *
 * Call during EA initialization.
 * Resets global context and sets configuration.
 *
 * @param config Optional custom configuration (uses defaults if NULL)
 * @return true on success
 */
bool DV_Initialize(const DisplacementConfig &config)
{
   g_dvContext.Reset();

   // Use custom config if provided
   g_dvContext.config = config;

   if(g_logLevel <= LOG_LEVEL_DEBUG)
   {
LogPrint("[DV] Displacement Validator initialized", LOG_LEVEL_DEBUG);
    LogPrint("[DV] MinBodyRatio=" + DoubleToString(g_dvContext.config.minBodyRatio, 2) +
                " | MinRangeExpansion=" + DoubleToString(g_dvContext.config.minRangeExpansion, 2) +
                " | CloseThreshold=" + DoubleToString(g_dvContext.config.closeToExtremeThreshold, 2), LOG_LEVEL_DEBUG);
   }

   return true;
}

/**
 * DV_Initialize — Initialize validator with default configuration
 *
 * Overload with no parameters — uses default DisplacementConfig.
 * Call during EA initialization.
 * Resets global context and sets configuration.
 *
 * @return true on success
 */
bool DV_Initialize()
{
   g_dvContext.Reset();
   g_dvContext.config.Reset();
   if(g_logLevel <= LOG_LEVEL_DEBUG)
   {
   LogPrint("[DV] Displacement Validator initialized (defaults)", LOG_LEVEL_DEBUG);
   }
   return true;
}

/**
 * DV_Compute — Compute displacement validation
 *
 * MAIN ENTRY POINT for displacement validation.
 * Stateless per tick — recomputes cleanly from input data.
 *
 * @param symbol Trading symbol
 * @param open Open price
 * @param close Close price
 * @param high High price
 * @param low Low price
 * @param prevHigh Previous bar high
 * @param prevLow Previous bar low
 * @return DisplacementOutput with validation result
 */
DisplacementOutput DV_Compute(
    string symbol,
    double open,
    double close,
    double high,
    double low,
    double prevHigh,
    double prevLow
)
{
    // Validate using current config
    DisplacementOutput output = DV_Validate(
       symbol, open, close, high, low,
       prevHigh, prevLow,
       g_dvContext.config
    );

   // Update global context
   g_dvContext.previous = g_dvContext.current;
   g_dvContext.current = output;

   // Track valid displacements
   if(output.isValid)
   {
      g_dvContext.validCount++;
      g_dvContext.lastValidTime = output.timestamp;
   }

   return output;
}

/**
 * DV_GetCurrentOutput — Get current cached output
 *
 * Returns the most recently computed output without recomputation.
 *
 * @return DisplacementOutput current output
 */
DisplacementOutput DV_GetCurrentOutput()
{
   return g_dvContext.current;
}

/**
 * DV_GetCurrentConfig — Get current configuration
 *
 * @return DisplacementConfig current configuration
 */
DisplacementConfig DV_GetCurrentConfig()
{
   return g_dvContext.config;
}

/**
 * DV_UpdateConfig — Update validator configuration
 *
 * @param config New configuration
 * @return true on success
 */
bool DV_UpdateConfig(const DisplacementConfig &config)
{
   g_dvContext.config = config;
   if(g_logLevel <= LOG_LEVEL_DEBUG)
   {
LogPrint("[DV] Configuration updated | MinBodyRatio=" + DoubleToString(config.minBodyRatio, 2) +
                " | MinRangeExpansion=" + DoubleToString(config.minRangeExpansion, 2), LOG_LEVEL_DEBUG);
   }
   return true;
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS — DISPLACEMENT INTEGRATION                           |
//+------------------------------------------------------------------+

/**
 * DV_FromDisplacement — Validate using candle data
 *
 * Convenience function to validate displacement from
 * candle data structures.
 *
 * @param symbol Trading symbol
 * @param c3_open C3 candle open
 * @param c3_close C3 candle close
 * @param c3_high C3 candle high
 * @param c3_low C3 candle low
 * @param c2_high C2 candle high
 * @param c2_low C2 candle low
 * @return DisplacementOutput with validation result
 */
DisplacementOutput DV_FromDisplacement(
    string symbol,
    double c3_open,
    double c3_close,
    double c3_high,
    double c3_low,
    double c2_high,
    double c2_low
)
{
    return DV_Compute(symbol, c3_open, c3_close, c3_high, c3_low, c2_high, c2_low);
}

/**
 * DV_ValidateFromClosureSignal — Validate from SClosureSignal
 *
 * Convenience function to validate displacement from existing
 * closure signal.
 *
 * @param symbol Trading symbol
 * @param signal SClosureSignal from ClosureEngine
 * @return DisplacementOutput with validation result
 */
DisplacementOutput DV_ValidateFromClosureSignal(string symbol, const SClosureSignal &signal)
{
   DisplacementOutput output;
   ZeroMemory(output);
   output.Reset();

   if(!signal.valid)
      return output;

   // Use C3 data if available and runtime C3 pipeline is enabled
   if(signal.type == CLOSURE_C3 && signal.c3_high > 0)
   {
      output = DV_FromDisplacement(
         symbol,
         signal.c3_open, signal.c3_close,
         signal.c3_high, signal.c3_low,
         signal.c2_high, signal.c2_low
      );
   }
   // Use C2 data as fallback
   else if(signal.c2_high > 0)
   {
      // For C2, we need previous bar data which isn't in the signal
      // Return simplified validation
      output.bodyRatioOk = true; // Assume OK for C2
      output.rangeExpansionOk = true;
      output.closeToExtremeOk = true;
      output.strengthScore = 1.0;
      output.isValid = false; // C2 not validated for displacement
   }

   return output;
}

//+------------------------------------------------------------------+
//| VALIDATION HELPERS                                               |
//+------------------------------------------------------------------+

/**
 * DV_IsValid — Quick validity check
 *
 * @param output DisplacementOutput to check
 * @return true if displacement is valid
 */
bool DV_IsValid(const DisplacementOutput &output)
{
   return output.isValid;
}

/**
 * DV_IsStrong — Check if displacement is strong
 *
 * @param output DisplacementOutput to check
 * @param threshold Strength threshold (default 1.5)
 * @return true if strength exceeds threshold
 */
bool DV_IsStrong(const DisplacementOutput &output, double threshold = 1.5)
{
   return (output.isValid && output.strengthScore >= threshold);
}

/**
 * DV_GetStrengthString — Convert strength to descriptive string
 *
 * @param strength Strength score
 * @return Descriptive string
 */
string DV_GetStrengthString(double strength)
{
   if(strength >= 2.0)
      return "VERY STRONG";
   else if(strength >= 1.5)
      return "STRONG";
   else if(strength >= 1.0)
      return "MODERATE";
   else if(strength >= 0.5)
      return "WEAK";
   else
      return "NONE";
}

//+------------------------------------------------------------------+
//| LOGGING & TELEMETRY                                              |
//+------------------------------------------------------------------+

/**
 * DV_LogValidation — Log validation result
 *
 * @param output DisplacementOutput to log
 */
void DV_LogValidation(const DisplacementOutput &output)
{
   // NO DIRECT LOGGING - data captured in centralized snapshot
}

/**
 * DV_LogConfig — Log current configuration
 *
 * @param config DisplacementConfig to log
 */
void DV_LogConfig(const DisplacementConfig &config)
{
   // NO DIRECT LOGGING - data captured in centralized snapshot
}

//+------------------------------------------------------------------+
//| ANALYSIS HELPER — Full Displacement Analysis                     |
//+------------------------------------------------------------------+

/**
 * DV_AnalyzeDisplacement — Complete displacement analysis
 *
 * High-level function that performs full analysis from symbol/TF.
 *
 * @param symbol Symbol to analyze
 * @param tf Timeframe to analyze
 * @return DisplacementOutput with complete analysis
 */
DisplacementOutput DV_AnalyzeDisplacement(
   const string symbol,
   ENUM_TIMEFRAMES tf
)
{
   DisplacementOutput output;
   ZeroMemory(output);
   output.Reset();

   string sym = (symbol == "" || symbol == NULL) ? _Symbol : symbol;
   ENUM_TIMEFRAMES timeframe = (tf == PERIOD_CURRENT) ? PERIOD_CURRENT : tf;

   // Copy OHLC data (current + previous bar)
   datetime times[];
   double opens[];
   double highs[];
   double lows[];
   double closes[];

   ArraySetAsSeries(times, true);
   ArraySetAsSeries(opens, true);
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);

int copied = CopyHigh(sym, timeframe, 0, 2, highs);
    if(copied == 1)
    {
       output.isValid = true;
       LogPrint("[DV] Marginal Data Detected (1 bar) - Allowing validation for startup", LOG_LEVEL_DEBUG);
    }
    else if(copied < 2)
    {
       DV_LogValidation(output);
       return output;
    }

    copied = CopyLow(sym, timeframe, 0, 2, lows);
    if(copied < 2)
    {
       DV_LogValidation(output);
       return output;
    }

    copied = CopyOpen(sym, timeframe, 0, 2, opens);
    if(copied < 2)
    {
       DV_LogValidation(output);
       return output;
    }

    copied = CopyClose(sym, timeframe, 0, 2, closes);
    if(copied < 2)
    {
       DV_LogValidation(output);
       return output;
    }

// Extract bar data
    // Index 0 = current bar, Index 1 = previous bar
    double curr_open = opens[0];
    double curr_close = closes[0];
    double curr_high = highs[0];
    double curr_low = lows[0];

double prev_high = highs[1];
     double prev_low = lows[1];

     // Zero-candle guard: bar 0 not yet formed
     double candleRange = highs[0] - lows[0];
     if(candleRange < _Point * 2)
     {
        DisplacementOutput empty;
        ZeroMemory(empty);
        empty.isValid = false;
        empty.strengthScore = 0.0;
        return empty;
     }

     // Compute validation
    output = DV_Compute(sym, curr_open, curr_close, curr_high, curr_low, prev_high, prev_low);

   // Log if valid
   if(output.isValid)
   {
      DV_LogValidation(output);
   }

   return output;
}

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+

#endif // OMAK_DISPLACEMENTVALIDATOR_MQH
