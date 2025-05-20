#property link          "https://www.earnforex.com/metatrader-scripts/breakeven/"
#property version       "1.01"
#property copyright     "EarnForex.com - 2025"
#property description   "This script will set breakeven on all trades filtered according to your preferences."
#property description   ""
#property description   "WARNING: Use this software at your own risk."
#property description   "The creator of this script cannot be held responsible for any damage or loss."
#property description   ""
#property description   "Find More on EarnForex.com"
#property icon          "\\Files\\EF-Icon-64x64px.ico"
#property script_show_inputs

#include <Trade/Trade.mqh>

enum ENUM_ORDER_TYPES
{
    ALL_ORDERS = 1, // ALL ORDERS
    ONLY_BUY = 2,   // BUY ONLY
    ONLY_SELL = 3   // SELL ONLY
};

input bool OnlyCurrentSymbol = false; // Only current chart's symbol
input ENUM_ORDER_TYPES OrderTypeFilter = ALL_ORDERS; // Type of orders to move SL to BE
input int MinimumProfit = 0;          // Minimum current profit in points to apply BE
input int AdditionalProfit = 0;       // Additional profit in points to add to BE
input bool OnlyMagicNumber = false;   // Only orders matching the magic number
input int MagicNumber = 0;            // Matching magic number
input bool OnlyWithComment = false;   // Only orders with the following comment
input string MatchingComment = "";    // Matching comment
input bool AdjustForSwapsCommission = false; // Adjust for swaps & commission?

void OnStart()
{
    if (!TerminalInfoInteger(TERMINAL_CONNECTED))
    {
        Print("Not connected to the trading server. Exiting.");
        return;
    }

    if ((!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) || (!MQLInfoInteger(MQL_TRADE_ALLOWED)))
    {
        Print("Autotrading is disable. Please enable. Exiting.");
        return;
    }

    CTrade *Trade;
    Trade = new CTrade;

    int positions_total = PositionsTotal();
    for (int i = positions_total - 1; i >= 0; i--) // Going backwards in case one or more positions are closed during the cycle.
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0)
        {
            Print("ERROR - Unable to select the position - ", GetLastError());
            continue;
        }
        
        if (PositionGetDouble(POSITION_PROFIT) <= 0) continue; // Unprofitable positions are always skipped.
        // Check if the position matches the filter and if not, skip the position and move to the next one.
        if ((OrderTypeFilter == ONLY_SELL) && (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)) continue;
        if ((OrderTypeFilter == ONLY_BUY)  && (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)) continue;
        if ((OnlyCurrentSymbol) && (PositionGetString(POSITION_SYMBOL) != Symbol())) continue;
        if ((OnlyMagicNumber) && (PositionGetInteger(POSITION_MAGIC) != MagicNumber)) continue;
        if ((OnlyWithComment) && (StringCompare(PositionGetString(POSITION_COMMENT), MatchingComment) != 0)) continue;

        double point = SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_POINT);
        // Compare doubles by calculating difference. If this difference is greater than Point / 2, the position's profit is below the MinimumProfit parameter.
        if ((MinimumProfit > 0) && ((double)MinimumProfit - MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - PositionGetDouble(POSITION_PRICE_CURRENT)) / point > point / 2)) continue;

        if (SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
        {
            Print("Trading is disabled for ", PositionGetString(POSITION_SYMBOL), ". Skipping.");
            continue;
        }

        double extra_be_distance = AdditionalProfit * point;
        int digits = (int)SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_DIGITS);
        double tick_size = SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_TRADE_TICK_SIZE);
        if (tick_size > 0)
        {
            // Adjust for tick size granularity.
            extra_be_distance = NormalizeDouble(MathRound(extra_be_distance / tick_size) * tick_size, digits);
        }
        else
        {
            Print("Zero tick size for ", PositionGetString(POSITION_SYMBOL), ". Skipping.");
            continue;
        }
        
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            double BE_price = PositionGetDouble(POSITION_PRICE_OPEN) + extra_be_distance;
            if (AdjustForSwapsCommission) BE_price += CalculateSwapsCommissionAdjustment();
            BE_price = NormalizeDouble(BE_price, digits);
            if ((SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_BID) >= BE_price) && (BE_price > PositionGetDouble(POSITION_SL))) // Only move to BE if the price is above the calculated BE price, and the current stop-loss is lower.
            {
                double prev_sl = PositionGetDouble(POSITION_SL); // Remember old SL for reporting.
                // Write BE price to the SL field.
                if (!Trade.PositionModify(ticket, BE_price, PositionGetDouble(POSITION_TP)))
                    Print("PositionModify Buy BE failed ", GetLastError(),  " for ", PositionGetString(POSITION_SYMBOL));
                else
                    Print("Breakeven was applied to position - " + PositionGetString(POSITION_SYMBOL) + " BUY #" + IntegerToString(ticket) + " Lotsize = ", PositionGetDouble(POSITION_VOLUME), ", OpenPrice = " + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), digits) + ", Stop-Loss was moved from " + DoubleToString(prev_sl, digits) + ".");
            }
        }
        else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            double BE_price = PositionGetDouble(POSITION_PRICE_OPEN) - extra_be_distance;
            if (AdjustForSwapsCommission) BE_price -= CalculateSwapsCommissionAdjustment();
            BE_price = NormalizeDouble(BE_price, digits);
            if  ((SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_ASK) <= BE_price) && ((BE_price < PositionGetDouble(POSITION_SL)) || (PositionGetDouble(POSITION_SL) == 0))) // Only move to BE if the price below the calculated BE price, and the current stop-loss is higher (or zero).
            {
                double prev_sl = PositionGetDouble(POSITION_SL); // Remember old SL for reporting.
                // Write BE price to the SL field.
                if (!Trade.PositionModify(ticket, BE_price, PositionGetDouble(POSITION_TP)))
                    Print("PositionModify Buy BE failed ", GetLastError(),  " for ", PositionGetString(POSITION_SYMBOL));
                else
                    Print("Breakeven was applied to position - " + PositionGetString(POSITION_SYMBOL) + " SELL #" + IntegerToString(ticket) + " Lotsize = ", PositionGetDouble(POSITION_VOLUME), ", OpenPrice = " + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), digits) + ", Stop-Loss was moved from " + DoubleToString(prev_sl, digits) + ".");
            }
        }
    }
    delete Trade;
    return;
}

enum mode_of_operation
{
    Risk,
    Reward
};

string AccCurrency;
double CalculateSwapsCommissionAdjustment()
{
    // Commission is usually a negative value.
    // Swaps can be positive and negative. A positive swap means that we got extra money.
    // When the minus sign below gets applied to a negative value (incurred commission/swap losses), it makes a positive value in currency to compensate by moving the SL favorably from the breakeven point.
    double money = -(CalculateCommission() + PositionGetDouble(POSITION_SWAP));

    if (money == 0) return 0; // Nothing to compensate.
    AccCurrency = AccountInfoString(ACCOUNT_CURRENCY);
    mode_of_operation mode = Risk;
    if (money < 0) mode = Reward;
    double point_value = CalculatePointVolue(mode);

    if (point_value != 0) return money / point_value;
    else return 0; // Zero point value. Avoiding division by zero.
}

double CalculatePointVolue(mode_of_operation mode)
{
    string cp = PositionGetString(POSITION_SYMBOL);
    double UnitCost = CalculateUnitCost(cp, mode);
    double OnePoint = SymbolInfoDouble(cp, SYMBOL_POINT);
    return(UnitCost / OnePoint);
}

//+----------------------------------------------------------------------+
//| Returns unit cost either for Risk or for Reward mode.                |
//+----------------------------------------------------------------------+
double CalculateUnitCost(const string cp, const mode_of_operation mode)
{
    ENUM_SYMBOL_CALC_MODE CalcMode = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(cp, SYMBOL_TRADE_CALC_MODE);

    // No-Forex.
    if ((CalcMode != SYMBOL_CALC_MODE_FOREX) && (CalcMode != SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE) && (CalcMode != SYMBOL_CALC_MODE_FUTURES) && (CalcMode != SYMBOL_CALC_MODE_EXCH_FUTURES) && (CalcMode != SYMBOL_CALC_MODE_EXCH_FUTURES_FORTS))
    {
        double TickSize = SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_SIZE);
        double UnitCost = TickSize * SymbolInfoDouble(cp, SYMBOL_TRADE_CONTRACT_SIZE);
        string ProfitCurrency = SymbolInfoString(cp, SYMBOL_CURRENCY_PROFIT);
        if (ProfitCurrency == "RUR") ProfitCurrency = "RUB";

        // If profit currency is different from account currency.
        if (ProfitCurrency != AccCurrency)
        {
            return(UnitCost * CalculateAdjustment(ProfitCurrency, mode));
        }
        return UnitCost;
    }
    // With Forex instruments, tick value already equals 1 unit cost.
    else
    {
        if (mode == Risk) return SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_VALUE_LOSS);
        else return SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_VALUE_PROFIT);
    }
}

//+-----------------------------------------------------------------------------------+
//| Calculates necessary adjustments for cases when GivenCurrency != AccountCurrency. |
//| Used in two cases: profit adjustment and margin adjustment.                       |
//+-----------------------------------------------------------------------------------+
double CalculateAdjustment(const string ProfitCurrency, const mode_of_operation mode)
{
    string ReferenceSymbol = GetSymbolByCurrencies(ProfitCurrency, AccCurrency);
    bool ReferenceSymbolMode = true;
    // Failed.
    if (ReferenceSymbol == NULL)
    {
        // Reversing currencies.
        ReferenceSymbol = GetSymbolByCurrencies(AccCurrency, ProfitCurrency);
        ReferenceSymbolMode = false;
    }
    // Everything failed.
    if (ReferenceSymbol == NULL)
    {
        Print("Error! Cannot detect proper currency pair for adjustment calculation: ", ProfitCurrency, ", ", AccCurrency, ".");
        ReferenceSymbol = Symbol();
        return 1;
    }
    MqlTick tick;
    SymbolInfoTick(ReferenceSymbol, tick);
    return GetCurrencyCorrectionCoefficient(tick, mode, ReferenceSymbolMode);
}

//+---------------------------------------------------------------------------+
//| Returns a currency pair with specified base currency and profit currency. |
//+---------------------------------------------------------------------------+
string GetSymbolByCurrencies(string base_currency, string profit_currency)
{
    // Cycle through all symbols.
    for (int s = 0; s < SymbolsTotal(false); s++)
    {
        // Get symbol name by number.
        string symbolname = SymbolName(s, false);

        // Skip non-Forex pairs.
        if ((SymbolInfoInteger(symbolname, SYMBOL_TRADE_CALC_MODE) != SYMBOL_CALC_MODE_FOREX) && (SymbolInfoInteger(symbolname, SYMBOL_TRADE_CALC_MODE) != SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE)) continue;

        // Get its base currency.
        string b_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_BASE);
        if (b_cur == "RUR") b_cur = "RUB";

        // Get its profit currency.
        string p_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_PROFIT);
        if (p_cur == "RUR") p_cur = "RUB";
        
        // If the currency pair matches both currencies, select it in Market Watch and return its name.
        if ((b_cur == base_currency) && (p_cur == profit_currency))
        {
            // Select if necessary.
            if (!(bool)SymbolInfoInteger(symbolname, SYMBOL_SELECT)) SymbolSelect(symbolname, true);

            return symbolname;
        }
    }
    return NULL;
}

//+------------------------------------------------------------------+
//| Get profit correction coefficient based on profit currency,      |
//| calculation mode (profit or loss), reference pair mode (reverse  |
//| or direct), and current prices.                                  |
//+------------------------------------------------------------------+
double GetCurrencyCorrectionCoefficient(MqlTick &tick, const mode_of_operation mode, const bool ReferenceSymbolMode)
{
    if ((tick.ask == 0) || (tick.bid == 0)) return -1; // Data is not yet ready.
    if (mode == Risk)
    {
        // Reverse quote.
        if (ReferenceSymbolMode)
        {
            // Using Buy price for reverse quote.
            return tick.ask;
        }
        // Direct quote.
        else
        {
            // Using Sell price for direct quote.
            return(1 / tick.bid);
        }
    }
    else if (mode == Reward)
    {
        // Reverse quote.
        if (ReferenceSymbolMode)
        {
            // Using Sell price for reverse quote.
            return tick.bid;
        }
        // Direct quote.
        else
        {
            // Using Buy price for direct quote.
            return(1 / tick.ask);
        }
    }
    return -1;
}

double CalculateCommission()
{
    double commission_sum = 0;
    if (!HistorySelectByPosition(PositionGetInteger(POSITION_IDENTIFIER)))
    {
        Print("HistorySelectByPosition failed: ", GetLastError());
        return 0;
    }
    int deals_total = HistoryDealsTotal();
    for (int i = 0; i < deals_total; i++)
    {
        ulong deal_ticket = HistoryDealGetTicket(i);
        if (deal_ticket == 0)
        {
            Print("HistoryDealGetTicket failed: ", GetLastError());
            continue;
        }
        if ((HistoryDealGetInteger(deal_ticket, DEAL_TYPE) != DEAL_TYPE_BUY) && (HistoryDealGetInteger(deal_ticket, DEAL_TYPE) != DEAL_TYPE_SELL)) continue; // Wrong kinds of deals.
        if (HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue; // Only entry deals.
        commission_sum += HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
    }
    return commission_sum;
}
//+------------------------------------------------------------------+