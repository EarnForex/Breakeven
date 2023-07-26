#property link          "https://www.earnforex.com/metatrader-scripts/breakeven/"
#property version       "1.00"
#property strict
#property copyright     "EarnForex.com - 2023"
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
            double BE_price = NormalizeDouble(OrderOpenPrice() + extra_be_distance, digits);
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
            double BE_price = NormalizeDouble(OrderOpenPrice() - extra_be_distance, digits);
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
//+------------------------------------------------------------------+