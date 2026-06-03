//+------------------------------------------------------------------+
//| HolidayCalendar.mqh                                              |
//|: Comprehensive holiday calendar for major markets        |
//| Part of Omak FxYO — Universal Market Settings                    |
//+------------------------------------------------------------------+
#ifndef OMAK_HOLIDAYCALENDAR_MQH
#define OMAK_HOLIDAYCALENDAR_MQH

#property strict

#include <OmakFxYO/core/MarketTypeDetector.mqh>

//+------------------------------------------------------------------+
//| Holiday Definition Structure                                     |
//+------------------------------------------------------------------+
/**
 * SHoliday
 *
 * Defines a market holiday with flexible scheduling.
 *
 * Fixed date:    day > 0, dayOfWeek = -1, weekOfMonth = -1
 * Floating:      day = -1, dayOfWeek = 0-6, weekOfMonth = 1-4
 * Last weekday:  day = -1, dayOfWeek = 0-6, weekOfMonth = -1
 */
struct SHoliday
{
   int               month;             // 1-12
   int               day;               // 1-31 (or -1 for floating)
   int               dayOfWeek;         // 0-6 (0=Sun, 6=Sat; -1 for fixed)
   int               weekOfMonth;       // 1-4 (or -1 for fixed, -1 = last occurrence)
   string            name;              // Holiday name
   bool              affectsForex;      // Does this affect forex?
   bool              affectsCrypto;     // Does this affect crypto?
   bool              affectsIndices;    // Does this affect indices?
   int               closeHour;         // Early close hour (24 = no early close)
};

//+------------------------------------------------------------------+
//| 2026 Holiday Calendar                                            |
//+------------------------------------------------------------------+
/**
 * g_holidays2026
 *
 * Major market holidays for 2026. Expand for other years as needed.
 *
 * Floating holiday rules:
 *   weekOfMonth = 1-4  → Nth occurrence of dayOfWeek in month
 *   weekOfMonth = -1   → Last occurrence of dayOfWeek in month
 *   day = -1           → Not a fixed-date holiday
 */
SHoliday g_holidays2026[] = {
   // New Year's Day (Jan 1)
   {1, 1, -1, -1, "New Year's Day", true, false, true, 24},
   // Martin Luther King Jr. Day (3rd Monday of January)
   {1, -1, 1, 3, "MLK Day", true, false, true, 24},
   // Presidents Day (3rd Monday of February)
   {2, -1, 1, 3, "Presidents Day", true, false, true, 24},
   // Good Friday (Apr 3, 2026 — floating, approximated)
   {4, 3, -1, -1, "Good Friday", true, false, true, 12},
   // Memorial Day (last Monday of May)
   {5, -1, 1, -1, "Memorial Day", true, false, true, 24},
   // Juneteenth (Jun 19)
   {6, 19, -1, -1, "Juneteenth", true, false, true, 24},
   // Independence Day (Jul 4)
   {7, 4, -1, -1, "Independence Day", true, false, true, 24},
   // Labor Day (1st Monday of September)
   {9, -1, 1, 1, "Labor Day", true, false, true, 24},
   // Thanksgiving (4th Thursday of November)
   {11, -1, 4, 4, "Thanksgiving", true, false, true, 13},
   // Christmas Day (Dec 25)
   {12, 25, -1, -1, "Christmas Day", true, false, true, 24}
};

//+------------------------------------------------------------------+
//| DoesHolidayAffectMarket — Check if holiday impacts market type   |
//+------------------------------------------------------------------+
/**
 * DoesHolidayAffectMarket
 *
 * Returns true if the given holiday affects the specified market type.
 * Crypto is generally unaffected by traditional holidays.
 */
bool DoesHolidayAffectMarket(const SHoliday &h, ENUM_MARKET_TYPE marketType)
{
   switch(marketType)
   {
      case MARKET_CRYPTO:
         return h.affectsCrypto;
      case MARKET_INDEX:
         return h.affectsIndices;
      case MARKET_FUTURES:
         return h.affectsIndices; // Futures follow exchange calendars
      default:
         return h.affectsForex;
   }
}

//+------------------------------------------------------------------+
//| GetDaysInMonth — Helper for floating holiday calculation         |
//+------------------------------------------------------------------+
int GetDaysInMonth(int month, int year)
{
   switch(month)
   {
      case 1:  return 31;
      case 2:  // Leap year check
         if((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0))
            return 29;
         return 28;
      case 3:  return 31;
      case 4:  return 30;
      case 5:  return 31;
      case 6:  return 30;
      case 7:  return 31;
      case 8:  return 31;
      case 9:  return 30;
      case 10: return 31;
      case 11: return 30;
      case 12: return 31;
      default: return 31;
   }
}

//+------------------------------------------------------------------+
//| IsMarketHoliday — Check if a date is a market holiday            |
//+------------------------------------------------------------------+
/**
 * IsMarketHoliday
 *
 * Checks the holiday calendar to determine if the given datetime
 * falls on a market holiday for the specified market type.
 *
 * Supports both fixed-date and floating holidays (e.g., "3rd Monday").
 */
bool IsMarketHoliday(datetime time, ENUM_MARKET_TYPE marketType)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);

   int year = dt.year;
   // Use 2026 calendar by default — expand for other years as needed
   // For now, we use the 2026 calendar for all years (approximation)

   for(int i = 0; i < ArraySize(g_holidays2026); i++)
   {
      SHoliday h = g_holidays2026[i];

      // Check if this holiday affects the market type
      if(!DoesHolidayAffectMarket(h, marketType))
         continue;

      // Fixed date holidays
      if(h.day > 0 && h.month == dt.mon && h.day == dt.day)
      {
         return true;
      }

      // Floating holidays (day of week + week of month)
      if(h.day == -1 && h.month == dt.mon && h.dayOfWeek == dt.day_of_week)
      {
         // Calculate week of month
         int weekOfMonth = (dt.day - 1) / 7 + 1;

         if(h.weekOfMonth > 0 && weekOfMonth == h.weekOfMonth)
         {
            return true;
         }

         // Last occurrence of this weekday in the month
         if(h.weekOfMonth == -1)
         {
            int daysInMonth = GetDaysInMonth(dt.mon, year);
            int lastDayOfWeek = dt.day;
            while(lastDayOfWeek + 7 <= daysInMonth)
            {
               lastDayOfWeek += 7;
            }
            if(dt.day == lastDayOfWeek)
            {
               return true;
            }
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| GetHolidayName — Return name of holiday if today is a holiday    |
//+------------------------------------------------------------------+
string GetHolidayName(datetime time, ENUM_MARKET_TYPE marketType)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);

   for(int i = 0; i < ArraySize(g_holidays2026); i++)
   {
      SHoliday h = g_holidays2026[i];

      if(!DoesHolidayAffectMarket(h, marketType))
         continue;

      // Fixed date
      if(h.day > 0 && h.month == dt.mon && h.day == dt.day)
         return h.name;

// Floating
       if(h.day == -1 && h.month == dt.mon && h.dayOfWeek == dt.day_of_week)
       {
          int weekOfMonth = (dt.day - 1) / 7 + 1;
          if(h.weekOfMonth > 0 && weekOfMonth == h.weekOfMonth)
             return h.name;

          if(h.weekOfMonth == -1)
          {
             int daysInMonth = GetDaysInMonth(dt.mon, dt.year);
             int lastDayOfWeek = dt.day;
             while(lastDayOfWeek + 7 <= daysInMonth)
                lastDayOfWeek += 7;
             if(dt.day == lastDayOfWeek)
                return h.name;
          }
       }
    }
 
   return "";
 }

//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+
// REGRESSION_GUARD_V52.5_HOLIDAYCALENDAR: Removed dead GetEarlyCloseHour
#endif // OMAK_HOLIDAYCALENDAR_MQH
