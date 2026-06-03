//+------------------------------------------------------------------+
//| MarketTypeDetector.mqh                                           |
//|: Full implementation of market detection and profiling   |
//| Part of Omak FxYO — Universal Market Settings                    |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Market Type Enumeration                                          |
//+------------------------------------------------------------------+
enum ENUM_MARKET_TYPE
{
   MARKET_UNKNOWN = 0,
   MARKET_FOREX_MAJOR = 1,       // EURUSD, GBPUSD, USDJPY, etc.
   MARKET_FOREX_MINOR = 2,       // EURGBP, AUDNZD, etc.
   MARKET_FOREX_EXOTIC = 3,      // USDTRY, USDMXN, USDZAR, etc.
   MARKET_CRYPTO = 4,            // BTCUSD, ETHUSD, etc. (24/7)
   MARKET_INDEX = 5,             // US30, NAS100, SPX500, etc.
   MARKET_COMMODITY_METALS = 6,  // XAUUSD, XAGUSD
   MARKET_COMMODITY_ENERGY = 7,  // USOIL, UKOIL, GAS
   MARKET_SYNTHETIC = 8,         // Volatility indices (VIX, etc.)
   MARKET_FUTURES = 9            // Futures contracts
};

//+------------------------------------------------------------------+
//| Market Profile Structure                                         |
//+------------------------------------------------------------------+
/**
 * SMarketProfile
 *
 * Holds all detected and derived properties for a given symbol.
 * Populated by GetMarketProfile() which calls all detection functions.
 */
struct SMarketProfile
{
   ENUM_MARKET_TYPE  type;
   string            baseName;            // Normalized symbol name
   string            rawSymbol;           // Broker's symbol name
   string            prefix;              // Detected prefix (e.g., "m" for EURUSDm)
   string            suffix;              // Detected suffix (e.g., ".pro" for EURUSD.pro)
   bool              is24Hour;            // True if trades 24/7
   bool              isWeekendTradable;   // True if trades weekends
   int               typicalSpread;       // Typical spread in points
   int               sessionOpenHour;     // Server time session open
   int               sessionCloseHour;    // Server time session close
   bool              requiresVolume;      // Whether volume confirmation applies
   double            pointValue;          // Value per point in account currency
};

//+------------------------------------------------------------------+
//| DetectMarketType — Classify symbol into market category          |
//+------------------------------------------------------------------+
/**
 * DetectMarketType
 *
 * Uses SymbolInfoString properties and symbol name patterns to
 * classify the instrument into a known market type.
 *
 * Detection order:
 *   1. Check SYMBOL_CURRENCY_BASE and SYMBOL_DESCRIPTION
 *   2. Check symbol name patterns (XAU, BTC, OIL, etc.)
 *   3. Check description keywords (Index, Volatility, etc.)
 *   4. Fall back to FOREX_MAJOR for common pairs
 */
ENUM_MARKET_TYPE DetectMarketType(string symbol)
{
   if(symbol == "")
      return MARKET_UNKNOWN;

   string base = ExtractBaseName(symbol);
   string description = SymbolInfoString(symbol, SYMBOL_DESCRIPTION);
   string currencyBase = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string upperDesc = StrToUpper(description);
   string upperBase = StrToUpper(base);
   string upperSym = StrToUpper(symbol);

   // --- Crypto detection ---
   if(currencyBase == "BTC" || currencyBase == "ETH" || currencyBase == "XRP" ||
      currencyBase == "LTC" || currencyBase == "BCH" ||
      StringFind(upperDesc, "BITCOIN") >= 0 ||
      StringFind(upperDesc, "ETHEREUM") >= 0 ||
      StringFind(upperDesc, "CRYPTO") >= 0 ||
      StringFind(upperSym, "BTC") >= 0 ||
      StringFind(upperSym, "ETH") >= 0 ||
      StringFind(upperSym, "XBT") >= 0)
   {
      return MARKET_CRYPTO;
   }

   // --- Metals detection ---
   if(StringFind(upperBase, "XAU") >= 0 || StringFind(upperBase, "GOLD") >= 0 ||
      StringFind(upperDesc, "GOLD") >= 0 || StringFind(upperDesc, "XAU") >= 0)
   {
      return MARKET_COMMODITY_METALS;
   }
   if(StringFind(upperBase, "XAG") >= 0 || StringFind(upperBase, "SILVER") >= 0 ||
      StringFind(upperDesc, "SILVER") >= 0)
   {
      return MARKET_COMMODITY_METALS;
   }

   // --- Energy detection ---
   if(StringFind(upperBase, "OIL") >= 0 || StringFind(upperBase, "GAS") >= 0 ||
      StringFind(upperDesc, "OIL") >= 0 || StringFind(upperDesc, "BRENT") >= 0 ||
      StringFind(upperDesc, "NATURAL GAS") >= 0)
   {
      return MARKET_COMMODITY_ENERGY;
   }

   // --- Index detection ---
   if(StringFind(upperDesc, "INDEX") >= 0 || StringFind(upperDesc, "US30") >= 0 ||
      StringFind(upperDesc, "NAS") >= 0 || StringFind(upperDesc, "SPX") >= 0 ||
      StringFind(upperDesc, "DAX") >= 0 || StringFind(upperDesc, "UK100") >= 0 ||
      StringFind(upperBase, "US30") >= 0 || StringFind(upperBase, "NAS") >= 0 ||
      StringFind(upperSym, "US30") >= 0 || StringFind(upperSym, "NAS") >= 0 ||
      StringFind(upperSym, "SPX") >= 0 || StringFind(upperSym, "DAX") >= 0)
   {
      return MARKET_INDEX;
   }

   // --- Synthetic/Volatility detection ---
   if(StringFind(upperDesc, "VOLATILITY") >= 0 || StringFind(upperDesc, "VIX") >= 0 ||
      StringFind(upperDesc, "SYNTHETIC") >= 0 ||
      StringFind(upperBase, "VIX") >= 0 || StringFind(upperSym, "VIX") >= 0)
   {
      return MARKET_SYNTHETIC;
   }

   // --- Forex classification ---
   string majors[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "USDCAD", "NZDUSD"};
   for(int i = 0; i < ArraySize(majors); i++)
   {
      if(upperBase == majors[i])
         return MARKET_FOREX_MAJOR;
   }

   // Exotic: Contains TRY, ZAR, MXN, etc.
   if(StringFind(upperBase, "TRY") >= 0 || StringFind(upperBase, "ZAR") >= 0 ||
      StringFind(upperBase, "MXN") >= 0 || StringFind(upperBase, "RUB") >= 0 ||
      StringFind(upperBase, "PLN") >= 0 || StringFind(upperBase, "HUF") >= 0)
   {
      return MARKET_FOREX_EXOTIC;
   }

   // Default for remaining forex pairs
   return MARKET_FOREX_MINOR;
}

//+------------------------------------------------------------------+
//| ExtractBaseName — Strip prefix/suffix from symbol                |
//+------------------------------------------------------------------+
/**
 * ExtractBaseName
 *
 * Removes broker-specific prefixes and suffixes to get the
 * canonical symbol name (e.g., "mEURUSD.pro" → "EURUSD").
 *
 * Strategy:
 *   1. Remove common prefixes (m, c, x, p, pro, ecn, std, micro, mini)
 *   2. Remove common suffixes (.pro, .ecn, .std, m, c, micro, mini, .cash, .fut)
 */
string ExtractBaseName(string symbol)
{
   if(symbol == "")
      return "";

   string result = symbol;

   // Remove common prefixes
   string prefixes[] = {"m", "c", "x", "p", "pro", "ecn", "std", "micro", "mini"};
   for(int i = 0; i < ArraySize(prefixes); i++)
   {
      int len = StringLen(prefixes[i]);
      if(StringLen(result) > len && StringSubstr(result, 0, len) == prefixes[i])
      {
         result = StringSubstr(result, len);
         break;
      }
   }

   // Remove common suffixes
   string suffixes[] = {".pro", ".ecn", ".std", "m", "c", "micro", "mini", ".cash", ".fut"};
   for(int i = 0; i < ArraySize(suffixes); i++)
   {
      int sLen = StringLen(suffixes[i]);
      int rLen = StringLen(result);
      if(rLen > sLen)
      {
         int pos = StringFind(result, suffixes[i]);
         if(pos >= 0 && pos == rLen - sLen)
         {
            result = StringSubstr(result, 0, pos);
            break;
         }
      }
   }

   return result;
}

//+------------------------------------------------------------------+
//| DetectPrefix — Extract broker prefix from symbol                 |
//+------------------------------------------------------------------+
string DetectPrefix(string symbol, string baseName)
{
   if(baseName == "" || baseName == symbol)
      return "";

   int basePos = StringFind(symbol, baseName);
   if(basePos > 0)
      return StringSubstr(symbol, 0, basePos);

   return "";
}

//+------------------------------------------------------------------+
//| DetectSuffix — Extract broker suffix from symbol                 |
//+------------------------------------------------------------------+
string DetectSuffix(string symbol, string baseName)
{
   if(baseName == "" || baseName == symbol)
      return "";

   int basePos = StringFind(symbol, baseName);
   if(basePos < 0)
      return "";

   int suffixStart = basePos + StringLen(baseName);
   if(suffixStart < StringLen(symbol))
      return StringSubstr(symbol, suffixStart);

   return "";
}

//+------------------------------------------------------------------+
//| Is24HourMarket — Check if market trades 24/7                     |
//+------------------------------------------------------------------+
bool Is24HourMarket(ENUM_MARKET_TYPE type)
{
   return (type == MARKET_CRYPTO || type == MARKET_SYNTHETIC);
}

//+------------------------------------------------------------------+
//| IsWeekendTradable — Check if market trades on weekends           |
//+------------------------------------------------------------------+
bool IsWeekendTradable(ENUM_MARKET_TYPE type)
{
   return (type == MARKET_CRYPTO || type == MARKET_SYNTHETIC);
}

//+------------------------------------------------------------------+
//| RequiresVolumeConfirmation — Check if volume filter applies      |
//+------------------------------------------------------------------+
/**
 * RequiresVolumeConfirmation
 *
 * Volume confirmation applies to all except crypto (often has
 * unreliable volume) and synthetics (synthetic volume).
 */
bool RequiresVolumeConfirmation(ENUM_MARKET_TYPE type)
{
   return (type != MARKET_CRYPTO && type != MARKET_SYNTHETIC);
}

//+------------------------------------------------------------------+
//| GetMarketProfile — Full profile for a symbol                     |
//+------------------------------------------------------------------+
/**
 * GetMarketProfile
 *
 * Populates and returns a complete SMarketProfile for the given
 * symbol by calling all detection functions.
 */
SMarketProfile GetMarketProfile(string symbol)
{
   SMarketProfile profile;
   ZeroMemory(profile);

   profile.rawSymbol = symbol;
   profile.baseName = ExtractBaseName(symbol);
   profile.type = DetectMarketType(symbol);
   profile.prefix = DetectPrefix(symbol, profile.baseName);
   profile.suffix = DetectSuffix(symbol, profile.baseName);
   profile.is24Hour = Is24HourMarket(profile.type);
   profile.isWeekendTradable = IsWeekendTradable(profile.type);
   profile.requiresVolume = RequiresVolumeConfirmation(profile.type);

   // Set session hours based on market type
   switch(profile.type)
   {
      case MARKET_FOREX_MAJOR:
      case MARKET_FOREX_MINOR:
      case MARKET_FOREX_EXOTIC:
         profile.sessionOpenHour = 0;    // Sunday 5 PM EST = Monday 0 GMT
         profile.sessionCloseHour = 21;  // Friday 5 PM EST = Friday 21 GMT
         break;
      case MARKET_CRYPTO:
      case MARKET_SYNTHETIC:
         profile.sessionOpenHour = 0;    // 24/7
         profile.sessionCloseHour = 24;  // Never closes
         break;
      case MARKET_INDEX:
      case MARKET_COMMODITY_METALS:
      case MARKET_COMMODITY_ENERGY:
         profile.sessionOpenHour = 9;    // Approximate exchange hours
         profile.sessionCloseHour = 17;  // Approximate exchange hours
         break;
      default:
         profile.sessionOpenHour = 0;
         profile.sessionCloseHour = 24;
         break;
   }

   profile.typicalSpread = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   profile.pointValue = SymbolInfoDouble(symbol, SYMBOL_POINT);

   return profile;
}

//+------------------------------------------------------------------+
//| StrToUpper — Helper function                                  |
//+------------------------------------------------------------------+
string StrToUpper(string src)
{
   string result = "";
   int len = StringLen(src);
   for(int i = 0; i < len; i++)
   {
      ushort ch = StringGetCharacter(src, i);
      // ASCII uppercase conversion (A-Z: 65-90, a-z: 97-122)
      if(ch >= 97 && ch <= 122)
         ch = ch - 32;
      result += ShortToString(ch);
   }
   return result;
}

//+------------------------------------------------------------------+
//| StringIsAlpha — Check if character is alphabetic                 |
//+------------------------------------------------------------------+
bool StringIsAlpha(string ch)
{
   if(StringLen(ch) != 1)
      return false;
   ushort c = StringGetCharacter(ch, 0);
   return ((c >= 65 && c <= 90) || (c >= 97 && c <= 122));
}

//+------------------------------------------------------------------+
//| GetMarketTypeName — Convert market type to readable string       |
//+------------------------------------------------------------------+
string GetMarketTypeName(ENUM_MARKET_TYPE type)
{
   switch(type)
   {
      case MARKET_FOREX_MAJOR:      return "Forex Major";
      case MARKET_FOREX_MINOR:      return "Forex Minor";
      case MARKET_FOREX_EXOTIC:     return "Forex Exotic";
      case MARKET_CRYPTO:           return "Crypto";
      case MARKET_INDEX:            return "Index";
      case MARKET_COMMODITY_METALS: return "Commodity (Metals)";
      case MARKET_COMMODITY_ENERGY: return "Commodity (Energy)";
      case MARKET_SYNTHETIC:        return "Synthetic";
      case MARKET_FUTURES:          return "Futures";
      default:                      return "Unknown";
   }
}
