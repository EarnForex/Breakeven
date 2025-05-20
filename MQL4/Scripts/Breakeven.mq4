#property link          "https://www.earnforex.com/metatrader-scripts/breakeven/"
#property version       "1.01"
#property strict
#property copyright     "EarnForex.com - 2025"
#property description   "This script will set breakeven on all trades filtered according to your preferences."
#property description   ""
#property description   "WARNING: Use this software at your own risk."
#property description   "The creator of this script cannot be held responsible for any damage or loss."
#property description   ""
#property description   "Find More on EarnForex.com"
#property icon          "\\Files\\EF-Icon-64x64px.ico"
#property show_inputs

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
    
    int orders_total = OrdersTotal();
    for (int i = orders_total - 1; i >= 0; i--) // Going backwards in case one or more orders are closed during the cycle.
    {
        if (!OrderSelect(i, SELECT_BY_POS))
        {
            Print("ERROR - Unable to select the order - ", GetLastError());
            continue;
        }
        if (OrderProfit() <= 0) continue; // Unprofitable orders are always skipped.
        // Check if the order matches the filter and if not, skip the order and move to the next one.
        if ((OrderTypeFilter == ONLY_SELL) && (OrderType() == OP_BUY)) continue;
        if ((OrderTypeFilter == ONLY_BUY)  && (OrderType() == OP_SELL)) continue;
        if ((OnlyCurrentSymbol) && (OrderSymbol() != Symbol())) continue;
        if ((OnlyMagicNumber) && (OrderMagicNumber() != MagicNumber)) continue;
        if ((OnlyWithComment) && (StringCompare(OrderComment(), MatchingComment) != 0)) continue;

        double point = SymbolInfoDouble(OrderSymbol(), SYMBOL_POINT);
        // Compare doubles by calculating difference. If this difference is greater than Point / 2, the order's profit is below the MinimumProfit parameter.
        if ((MinimumProfit > 0) && ((double)MinimumProfit - MathAbs(OrderOpenPrice() - OrderClosePrice()) / point > point / 2)) continue;

        if (SymbolInfoInteger(OrderSymbol(), SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
        {
            Print("Trading is disabled for ", OrderSymbol(), ". Skipping.");
            continue;
        }

        double extra_be_distance = AdditionalProfit * point;
        int digits = (int)SymbolInfoInteger(OrderSymbol(), SYMBOL_DIGITS);
        double tick_size = MarketInfo(OrderSymbol(), MODE_TICKSIZE);
        if (tick_size > 0)
        {
            // Adjust for tick size granularity.
            extra_be_distance = NormalizeDouble(MathRound(extra_be_distance / tick_size) * tick_size, digits);
        }
        else
        {
            Print("Zero tick size for ", OrderSymbol(), ". Skipping.");
            continue;
        }
        
        if (OrderType() == OP_BUY)
        {
            double BE_price = OrderOpenPrice() + extra_be_distance;
            if (AdjustForSwapsCommission) BE_price += CalculateSwapsCommissionAdjustment();
            BE_price = NormalizeDouble(BE_price, digits);
            if ((SymbolInfoDouble(OrderSymbol(), SYMBOL_BID) >= BE_price) && (BE_price > OrderStopLoss())) // Only move to BE if the price is above the calculated BE price, and the current stop-loss is lower.
            {
                double prev_sl = OrderStopLoss(); // Remember old SL for reporting.
                // Write BE price to the SL field.
                if (!OrderModify(OrderTicket(), OrderOpenPrice(), BE_price, OrderTakeProfit(), OrderExpiration()))
                    Print("OrderModify Buy BE failed ", GetLastError(),  " for ", OrderSymbol());
                else
                    Print("Breakeven was applied to position - " + OrderSymbol() + " BUY-order #" + IntegerToString(OrderTicket()) + " Lotsize = ", OrderLots(), ", OpenPrice = " + DoubleToString(OrderOpenPrice(), digits) + ", Stop-Loss was moved from " + DoubleToString(prev_sl, digits) + ".");
            }
        }
        else if (OrderType() == OP_SELL)
        {
            double BE_price = OrderOpenPrice() - extra_be_distance;
            if (AdjustForSwapsCommission) BE_price -= CalculateSwapsCommissionAdjustment();
            BE_price = NormalizeDouble(BE_price, digits);
            if  ((SymbolInfoDouble(OrderSymbol(), SYMBOL_ASK) <= BE_price) && ((BE_price < OrderStopLoss()) || (OrderStopLoss() == 0))) // Only move to BE if the price below the calculated BE price, and the current stop-loss is higher (or zero).
            {
                double prev_sl = OrderStopLoss(); // Remember old SL for reporting.
                // Write BE price to the SL field.
                if (!OrderModify(OrderTicket(), OrderOpenPrice(), BE_price, OrderTakeProfit(), OrderExpiration()))
                    Print("OrderModify Buy BE failed ", GetLastError(),  " for ", OrderSymbol());
                else
                    Print("Breakeven was applied to position - " + OrderSymbol() + " SELL-order #" + IntegerToString(OrderTicket()) + " Lotsize = ", OrderLots(), ", OpenPrice = " + DoubleToString(OrderOpenPrice(), digits) + ", Stop-Loss was moved from " + DoubleToString(prev_sl, digits) + ".");
            }
        }
    }
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
    double money = -(OrderCommission() + OrderSwap());

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
    string cp = OrderSymbol();
    double UnitCost;

    int ProfitCalcMode = (int)MarketInfo(cp, MODE_PROFITCALCMODE);
    string ProfitCurrency = SymbolInfoString(cp, SYMBOL_CURRENCY_PROFIT);
    
    if (ProfitCurrency == "RUR") ProfitCurrency = "RUB";
    // If Symbol is CFD or futures but with different profit currency.
    if ((ProfitCalcMode == 1) || ((ProfitCalcMode == 2) && ((ProfitCurrency != AccCurrency))))
    {

        if (ProfitCalcMode == 2) UnitCost = MarketInfo(cp, MODE_TICKVALUE); // Futures, but will still have to be adjusted by CCC.
        else UnitCost = SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_SIZE) * SymbolInfoDouble(cp, SYMBOL_TRADE_CONTRACT_SIZE); // Apparently, it is more accurate than taking TICKVALUE directly in some cases.
        // If profit currency is different from account currency.
        if (ProfitCurrency != AccCurrency)
        {
            double CCC = CalculateAdjustment(ProfitCurrency, mode); // Valid only for loss calculation.
            // Adjust the unit cost.
            UnitCost *= CCC;
        }
    }
    else UnitCost = MarketInfo(cp, MODE_TICKVALUE); // Futures or Forex.
    double OnePoint = MarketInfo(cp, MODE_POINT);

    if (OnePoint != 0) return(UnitCost / OnePoint);
    return UnitCost; // Only in case of an error with MODE_POINT retrieval.
}

//+-----------------------------------------------------------------------------------+
//| Calculates necessary adjustments for cases when ProfitCurrency != AccountCurrency.|
//| ReferenceSymbol changes every time because each symbol has its own RS.            |
//+-----------------------------------------------------------------------------------+
#define FOREX_SYMBOLS_ONLY 0
#define NONFOREX_SYMBOLS_ONLY 1
double CalculateAdjustment(const string profit_currency, const mode_of_operation calc_mode)
{
    string ref_symbol = NULL, add_ref_symbol = NULL;
    bool ref_mode = false, add_ref_mode = false;
    double add_coefficient = 1; // Might be necessary for correction coefficient calculation if two pairs are used for profit currency to account currency conversion. This is handled differently in MT5 version.

    if (ref_symbol == NULL) // Either first run or non-current symbol.
    {
        ref_symbol = GetSymbolByCurrencies(profit_currency, AccCurrency, FOREX_SYMBOLS_ONLY);
        if (ref_symbol == NULL) ref_symbol = GetSymbolByCurrencies(profit_currency, AccCurrency, NONFOREX_SYMBOLS_ONLY);
        ref_mode = true;
        // Failed.
        if (ref_symbol == NULL)
        {
            // Reversing currencies.
            ref_symbol = GetSymbolByCurrencies(AccCurrency, profit_currency, FOREX_SYMBOLS_ONLY);
            if (ref_symbol == NULL) ref_symbol = GetSymbolByCurrencies(AccCurrency, profit_currency, NONFOREX_SYMBOLS_ONLY);
            ref_mode = false;
        }
        if (ref_symbol == NULL)
        {
            if ((!FindDoubleReferenceSymbol("USD", profit_currency, ref_symbol, ref_mode, add_ref_symbol, add_ref_mode))  // USD should work in 99.9% of cases.
             && (!FindDoubleReferenceSymbol("EUR", profit_currency, ref_symbol, ref_mode, add_ref_symbol, add_ref_mode))  // For very rare cases.
             && (!FindDoubleReferenceSymbol("GBP", profit_currency, ref_symbol, ref_mode, add_ref_symbol, add_ref_mode))  // For extremely rare cases.
             && (!FindDoubleReferenceSymbol("JPY", profit_currency, ref_symbol, ref_mode, add_ref_symbol, add_ref_mode))) // For extremely rare cases.
            {
                Print("Adjustment calculation critical failure. Failed both simple and two-pair conversion methods.");
                return 1;
            }
        }
    }
    if (add_ref_symbol != NULL) // If two reference pairs are used.
    {
        // Calculate just the additional symbol's coefficient and then use it in final return's multiplication.
        MqlTick tick;
        SymbolInfoTick(add_ref_symbol, tick);
        add_coefficient = GetCurrencyCorrectionCoefficient(tick, calc_mode, add_ref_mode);
    }
    MqlTick tick;
    SymbolInfoTick(ref_symbol, tick);
    return GetCurrencyCorrectionCoefficient(tick, calc_mode, ref_mode) * add_coefficient;
}

//+---------------------------------------------------------------------------+
//| Returns a currency pair with specified base currency and profit currency. |
//+---------------------------------------------------------------------------+
string GetSymbolByCurrencies(const string base_currency, const string profit_currency, const uint symbol_type)
{
    // Cycle through all symbols.
    for (int s = 0; s < SymbolsTotal(false); s++)
    {
        // Get symbol name by number.
        string symbolname = SymbolName(s, false);
        string b_cur;

        // Normal case - Forex pairs:
        if (MarketInfo(symbolname, MODE_PROFITCALCMODE) == 0)
        {
            if (symbol_type == NONFOREX_SYMBOLS_ONLY) continue; // Avoid checking symbols of a wrong type.
            // Get its base currency.
            b_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_BASE);
        }
        else // Weird case for brokers that set conversion pairs as CFDs.
        {
            if (symbol_type == FOREX_SYMBOLS_ONLY) continue; // Avoid checking symbols of a wrong type.
            // Get its base currency as the initial three letters - prone to huge errors!
            b_cur = StringSubstr(symbolname, 0, 3);
        }

        // Get its profit currency.
        string p_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_PROFIT);

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

//+----------------------------------------------------------------------------+
//| Finds reference symbols using 2-pair method.                               |
//| Results are returned via reference parameters.                             |
//| Returns true if found the pairs, false otherwise.                          |
//+----------------------------------------------------------------------------+
bool FindDoubleReferenceSymbol(const string cross_currency, const string profit_currency, string &ref_symbol, bool &ref_mode, string &add_ref_symbol, bool &add_ref_mode)
{
    // A hypothetical example for better understanding:
    // The trader buys CAD/CHF.
    // account_currency is known = SEK.
    // cross_currency = USD.
    // profit_currency = CHF.
    // I.e., we have to buy dollars with francs (using the Ask price) and then sell those for SEKs (using the Bid price).

    ref_symbol = GetSymbolByCurrencies(cross_currency, AccCurrency, FOREX_SYMBOLS_ONLY); 
    if (ref_symbol == NULL) ref_symbol = GetSymbolByCurrencies(cross_currency, AccCurrency, NONFOREX_SYMBOLS_ONLY);
    ref_mode = true; // If found, we've got USD/SEK.

    // Failed.
    if (ref_symbol == NULL)
    {
        // Reversing currencies.
        ref_symbol = GetSymbolByCurrencies(AccCurrency, cross_currency, FOREX_SYMBOLS_ONLY);
        if (ref_symbol == NULL) ref_symbol = GetSymbolByCurrencies(AccCurrency, cross_currency, NONFOREX_SYMBOLS_ONLY);
        ref_mode = false; // If found, we've got SEK/USD.
    }
    if (ref_symbol == NULL)
    {
        Print("Error. Couldn't detect proper currency pair for 2-pair adjustment calculation. Cross currency: ", cross_currency, ". Account currency: ", AccCurrency, ".");
        return false;
    }

    add_ref_symbol = GetSymbolByCurrencies(cross_currency, profit_currency, FOREX_SYMBOLS_ONLY); 
    if (add_ref_symbol == NULL) add_ref_symbol = GetSymbolByCurrencies(cross_currency, profit_currency, NONFOREX_SYMBOLS_ONLY);
    add_ref_mode = false; // If found, we've got USD/CHF. Notice that mode is swapped for cross/profit compared to cross/acc, because it is used in the opposite way.

    // Failed.
    if (add_ref_symbol == NULL)
    {
        // Reversing currencies.
        add_ref_symbol = GetSymbolByCurrencies(profit_currency, cross_currency, FOREX_SYMBOLS_ONLY);
        if (add_ref_symbol == NULL) add_ref_symbol = GetSymbolByCurrencies(profit_currency, cross_currency, NONFOREX_SYMBOLS_ONLY);
        add_ref_mode = true; // If found, we've got CHF/USD. Notice that mode is swapped for profit/cross compared to acc/cross, because it is used in the opposite way.
    }
    if (add_ref_symbol == NULL)
    {
        Print("Error. Couldn't detect proper currency pair for 2-pair adjustment calculation. Cross currency: ", cross_currency, ". Chart's pair currency: ", profit_currency, ".");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Get profit correction coefficient based on current prices.       |
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
//+------------------------------------------------------------------+