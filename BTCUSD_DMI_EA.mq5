//+------------------------------------------------------------------+
//|                                                BTCUSD_DMI_EA.mq5 |
//|                              Copyright 2025, Bitcoin DMI Trader  |
//|                                       https://www.example.com    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Bitcoin DMI Trader"
#property link      "https://www.example.com"
#property version   "1.00"
#property description "Bitcoin DMI Trading EA with ADX-based lot sizing"

//--- Include necessary libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- Global objects
CTrade trade;
CPositionInfo position;
CAccountInfo account;

//--- Input parameters
input group "=== DMI Settings ==="
input int InpDMIPeriod = 14;                    // DMI Period (5-50)
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15; // Trading Timeframe

input group "=== Lot Size Settings ==="
input double InpLotMultiplier = 1.0;            // Lot Size Multiplier (0.1-10.0)

input group "=== Risk Management ==="
input double InpRiskPercent = 2.0;              // Risk per Trade % (0.5-5.0)
input int InpStopLossIntervals = 2;             // Stop Loss Intervals (1-5)
input int InpDailyStopLossLimit = 3;            // Daily Stop Loss Limit (1-10)
input int InpTradingPauseHours = 12;            // Trading Pause Hours (1-24)

input group "=== Trading Direction ==="
input bool InpAllowBuy = true;                  // Allow Buy Trades
input bool InpAllowSell = true;                 // Allow Sell Trades

input group "=== Display Settings ==="
input bool InpShowPanel = true;                 // Show Information Panel
input bool InpShowLabels = true;                // Show Entry/Exit Labels
input color InpPanelColor = clrNavy;            // Panel Background Color
input color InpTextColor = clrWhite;            // Panel Text Color

//--- Global variables
int dmi_handle;
double plus_di[], minus_di[], adx[];
datetime last_bar_time;
double entry_adx_value;
int entry_adx_interval;
double entry_lot_size;
datetime entry_time;
int daily_stop_loss_count;
datetime last_stop_loss_date;
datetime trading_pause_until;
bool is_trading_paused;
long chart_id;
int total_trade_count;
int daily_trade_count;

//--- ADX interval constants
const int ADX_INTERVALS = 10;
const double ADX_INTERVAL_SIZE = 10.0;

//--- Position tracking
enum EA_POSITION_TYPE
{
    EA_POSITION_NONE,
    EA_POSITION_LONG,
    EA_POSITION_SHORT
};

EA_POSITION_TYPE current_position_type = EA_POSITION_NONE;
double current_position_volume = 0.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Validate input parameters
    if(!ValidateInputs())
    {
        Print("Invalid input parameters!");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // Initialize DMI indicator
    dmi_handle = iADX(Symbol(), InpTimeframe, InpDMIPeriod);
    if(dmi_handle == INVALID_HANDLE)
    {
        Print("Failed to create DMI indicator handle");
        return INIT_FAILED;
    }
    
    // Initialize arrays
    ArraySetAsSeries(plus_di, true);
    ArraySetAsSeries(minus_di, true);
    ArraySetAsSeries(adx, true);
    
    // Initialize global variables
    last_bar_time = 0;
    entry_adx_value = 0;
    entry_adx_interval = 0;
    entry_lot_size = 0;
    entry_time = 0;
    daily_stop_loss_count = 0;
    last_stop_loss_date = 0;
    trading_pause_until = 0;
    is_trading_paused = false;
    chart_id = ChartID();
    total_trade_count = 0;
    daily_trade_count = 0;
    
    // Set up chart display
    if(InpShowPanel)
        CreateInfoPanel();
    
    Print("BTCUSD DMI EA initialized successfully");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handle
    if(dmi_handle != INVALID_HANDLE)
        IndicatorRelease(dmi_handle);
    
    // Remove chart objects
    RemoveChartObjects();
    
    Print("BTCUSD DMI EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new bar
    datetime current_bar_time = iTime(Symbol(), InpTimeframe, 0);
    if(current_bar_time == last_bar_time)
        return;
    
    last_bar_time = current_bar_time;
    
    // Update position info
    UpdatePositionInfo();
    
    // Check trading pause
    if(CheckTradingPause())
        return;
    
    // Get DMI values
    if(!GetDMIValues())
        return;
    
    // Check for crossover signals
    CheckCrossoverSignals();
    
    // Manage existing positions
    ManagePositions();
    
    // Update display
    if(InpShowPanel)
        UpdateInfoPanel();
}

//+------------------------------------------------------------------+
//| Validate input parameters                                       |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
    if(InpDMIPeriod < 5 || InpDMIPeriod > 50)
    {
        Print("DMI Period must be between 5 and 50");
        return false;
    }
    
    if(InpLotMultiplier < 0.1 || InpLotMultiplier > 10.0)
    {
        Print("Lot Multiplier must be between 0.1 and 10.0");
        return false;
    }
    
    if(InpRiskPercent < 0.5 || InpRiskPercent > 5.0)
    {
        Print("Risk Percent must be between 0.5 and 5.0");
        return false;
    }
    
    if(InpStopLossIntervals < 1 || InpStopLossIntervals > 5)
    {
        Print("Stop Loss Intervals must be between 1 and 5");
        return false;
    }
    
    if(InpDailyStopLossLimit < 1 || InpDailyStopLossLimit > 10)
    {
        Print("Daily Stop Loss Limit must be between 1 and 10");
        return false;
    }
    
    if(InpTradingPauseHours < 1 || InpTradingPauseHours > 24)
    {
        Print("Trading Pause Hours must be between 1 and 24");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Get DMI indicator values                                        |
//+------------------------------------------------------------------+
bool GetDMIValues()
{
    if(CopyBuffer(dmi_handle, 0, 0, 3, plus_di) < 3)
        return false;
    if(CopyBuffer(dmi_handle, 1, 0, 3, minus_di) < 3)
        return false;
    if(CopyBuffer(dmi_handle, 2, 0, 3, adx) < 3)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on ADX interval                       |
//+------------------------------------------------------------------+
double CalculateLotSize(double adx_value)
{
    int interval = GetADXInterval(adx_value);
    
    // Lot sizes: highest ADX interval (90-100) = 0.01 lots, increasing by 0.01 per lower interval
    // Interval 9 (90-100): 0.01, Interval 8 (80-90): 0.02, ..., Interval 0 (0-10): 0.10
    double base_lot = 0.01 * (10 - interval);  // 10-9=1 -> 0.01, 10-8=2 -> 0.02, ..., 10-0=10 -> 0.10
    
    // Apply multiplier
    double lot_size = base_lot * InpLotMultiplier;
    
    // Normalize lot size
    double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    
    lot_size = MathMax(lot_size, min_lot);
    lot_size = MathMin(lot_size, max_lot);
    lot_size = NormalizeDouble(lot_size / lot_step, 0) * lot_step;
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Get ADX interval (0-9 for intervals 0-10, 10-20, ..., 90-100) |
//+------------------------------------------------------------------+
int GetADXInterval(double adx_value)
{
    int interval = (int)MathFloor(adx_value / ADX_INTERVAL_SIZE);
    return MathMin(interval, ADX_INTERVALS - 1);
}

//+------------------------------------------------------------------+
//| Check for crossover signals                                     |
//+------------------------------------------------------------------+
void CheckCrossoverSignals()
{
    // Check for +DI crossing above -DI (Buy signal)
    // EVERY crossover must trigger entry
    if(InpAllowBuy && plus_di[1] > minus_di[1] && plus_di[2] <= minus_di[2])
    {
        // Close any existing position first (regardless of direction)
        if(current_position_type != EA_POSITION_NONE)
        {
            string close_label = (current_position_type == EA_POSITION_LONG) ? "平多" : "平空";
            ClosePosition(close_label);
        }
        
        // Always open new long position after crossover
        double lot_size = CalculateLotSize(adx[1]);
        if(OpenPosition(ORDER_TYPE_BUY, lot_size))
        {
            entry_adx_value = adx[1];
            entry_adx_interval = GetADXInterval(adx[1]);
            entry_lot_size = lot_size;
            entry_time = TimeCurrent();
            current_position_type = EA_POSITION_LONG;
            current_position_volume = lot_size;
            
            if(InpShowLabels)
                CreateTradeLabel("开多", clrLime);
                
            Print("Buy signal: +DI crossed above -DI. ADX: ", adx[1], " Interval: ", entry_adx_interval, " Lot: ", lot_size);
        }
    }
    // Check for -DI crossing above +DI (Sell signal)  
    // EVERY crossover must trigger entry
    else if(InpAllowSell && minus_di[1] > plus_di[1] && minus_di[2] <= plus_di[2])
    {
        // Close any existing position first (regardless of direction)
        if(current_position_type != EA_POSITION_NONE)
        {
            string close_label = (current_position_type == EA_POSITION_LONG) ? "平多" : "平空";
            ClosePosition(close_label);
        }
        
        // Always open new short position after crossover
        double lot_size = CalculateLotSize(adx[1]);
        if(OpenPosition(ORDER_TYPE_SELL, lot_size))
        {
            entry_adx_value = adx[1];
            entry_adx_interval = GetADXInterval(adx[1]);
            entry_lot_size = lot_size;
            entry_time = TimeCurrent();
            current_position_type = EA_POSITION_SHORT;
            current_position_volume = lot_size;
            
            if(InpShowLabels)
                CreateTradeLabel("开空", clrRed);
                
            Print("Sell signal: -DI crossed above +DI. ADX: ", adx[1], " Interval: ", entry_adx_interval, " Lot: ", lot_size);
        }
    }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                       |
//+------------------------------------------------------------------+
void ManagePositions()
{
    if(current_position_type == EA_POSITION_NONE)
        return;
    
    int current_adx_interval = GetADXInterval(adx[1]);
    
    // Check for position reduction (ADX rises above entry interval)
    // Reduce by 0.01 lots for each interval ADX rises above entry interval
    if(current_adx_interval > entry_adx_interval)
    {
        int intervals_risen = current_adx_interval - entry_adx_interval;
        double total_reduction_needed = 0.01 * intervals_risen * InpLotMultiplier;
        
        // Calculate how much we've already reduced (if any)
        double already_reduced = entry_lot_size - current_position_volume;
        double additional_reduction = total_reduction_needed - already_reduced;
        
        if(additional_reduction > 0)
        {
            // Normalize reduction volume
            double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
            additional_reduction = NormalizeDouble(additional_reduction / lot_step, 0) * lot_step;
            
            if(additional_reduction > 0 && additional_reduction < current_position_volume)
            {
                ReducePosition(additional_reduction);
                Print("Position reduced: ADX rose to interval ", current_adx_interval, 
                      " (from entry interval ", entry_adx_interval, "). Reduced by: ", additional_reduction);
            }
        }
    }
    
    // Check for full position close (ADX falls N intervals or more below entry)
    // Stop-loss triggered when ADX falls N intervals below entry interval
    if(current_adx_interval <= (entry_adx_interval - InpStopLossIntervals))
    {
        string close_label = (current_position_type == EA_POSITION_LONG) ? "平多" : "平空";
        ClosePosition(close_label);
        
        // Count as stop loss
        CountStopLoss();
        
        Print("Stop-loss triggered: ADX fell to interval ", current_adx_interval, 
              " (", InpStopLossIntervals, " intervals below entry interval ", entry_adx_interval, ")");
    }
}

//+------------------------------------------------------------------+
//| Open a new position                                             |
//+------------------------------------------------------------------+
bool OpenPosition(ENUM_ORDER_TYPE order_type, double volume)
{
    // Calculate risk-based position size
    double risk_volume = CalculateRiskBasedVolume();
    volume = MathMin(volume, risk_volume);
    
    bool result = false;
    if(order_type == ORDER_TYPE_BUY)
    {
        result = trade.Buy(volume, Symbol());
    }
    else if(order_type == ORDER_TYPE_SELL)
    {
        result = trade.Sell(volume, Symbol());
    }
    
    if(result)
    {
        Print("Position opened: ", EnumToString(order_type), " Volume: ", volume);
        
        // Update trade counters
        total_trade_count++;
        UpdateDailyTradeCount();
    }
    else
    {
        Print("Failed to open position: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Close current position                                          |
//+------------------------------------------------------------------+
void ClosePosition(string label)
{
    if(current_position_type == EA_POSITION_NONE)
        return;
    
    bool result = false;
    if(current_position_type == EA_POSITION_LONG)
    {
        result = trade.Sell(current_position_volume, Symbol());
    }
    else if(current_position_type == EA_POSITION_SHORT)
    {
        result = trade.Buy(current_position_volume, Symbol());
    }
    
    if(result)
    {
        Print("Position closed: ", label, " Volume: ", current_position_volume);
        
        if(InpShowLabels)
            CreateTradeLabel(label, clrYellow);
        
        // Reset position tracking
        current_position_type = EA_POSITION_NONE;
        current_position_volume = 0.0;
        entry_adx_value = 0;
        entry_adx_interval = 0;
        entry_lot_size = 0;
        entry_time = 0;
    }
    else
    {
        Print("Failed to close position: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Reduce position size                                            |
//+------------------------------------------------------------------+
void ReducePosition(double reduction_volume)
{
    if(current_position_volume <= reduction_volume)
        return;
    
    bool result = false;
    if(current_position_type == EA_POSITION_LONG)
    {
        result = trade.Sell(reduction_volume, Symbol());
    }
    else if(current_position_type == EA_POSITION_SHORT)
    {
        result = trade.Buy(reduction_volume, Symbol());
    }
    
    if(result)
    {
        current_position_volume -= reduction_volume;
        Print("Position reduced by: ", reduction_volume, " New volume: ", current_position_volume);
        
        if(InpShowLabels)
            CreateTradeLabel("减仓", clrOrange);
    }
    else
    {
        Print("Failed to reduce position: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Calculate risk-based volume                                     |
//+------------------------------------------------------------------+
double CalculateRiskBasedVolume()
{
    double balance = account.Balance();
    double risk_amount = balance * InpRiskPercent / 100.0;
    
    // Simplified risk calculation - in real implementation, 
    // you might want to use stop loss distance
    double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    
    if(tick_value == 0 || tick_size == 0)
        return SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    
    // Assume 100 ticks risk per trade
    double volume = risk_amount / (tick_value * 100);
    
    // Normalize volume
    double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    
    volume = MathMax(volume, min_lot);
    volume = MathMin(volume, max_lot);
    volume = NormalizeDouble(volume / lot_step, 0) * lot_step;
    
    return volume;
}

//+------------------------------------------------------------------+
//| Update position information                                     |
//+------------------------------------------------------------------+
void UpdatePositionInfo()
{
    // This function updates the current position tracking
    // based on actual MT5 positions
    if(PositionSelect(Symbol()))
    {
        long pos_type = PositionGetInteger(POSITION_TYPE);
        double pos_volume = PositionGetDouble(POSITION_VOLUME);
        
        if(pos_type == POSITION_TYPE_BUY)
        {
            current_position_type = EA_POSITION_LONG;
            current_position_volume = pos_volume;
        }
        else if(pos_type == POSITION_TYPE_SELL)
        {
            current_position_type = EA_POSITION_SHORT;
            current_position_volume = pos_volume;
        }
    }
    else
    {
        current_position_type = EA_POSITION_NONE;
        current_position_volume = 0.0;
    }
}

//+------------------------------------------------------------------+
//| Update daily trade count                                        |
//+------------------------------------------------------------------+
void UpdateDailyTradeCount()
{
    static datetime last_trade_date = 0;
    datetime current_date = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    
    if(last_trade_date != current_date)
    {
        daily_trade_count = 0;
        last_trade_date = current_date;
    }
    
    daily_trade_count++;
}

//+------------------------------------------------------------------+
//| Count stop loss and check daily limit                          |
//+------------------------------------------------------------------+
void CountStopLoss()
{
    datetime current_date = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    
    if(last_stop_loss_date != current_date)
    {
        daily_stop_loss_count = 0;
        last_stop_loss_date = current_date;
    }
    
    daily_stop_loss_count++;
    
    if(daily_stop_loss_count >= InpDailyStopLossLimit)
    {
        trading_pause_until = TimeCurrent() + InpTradingPauseHours * 3600;
        is_trading_paused = true;
        Print("Daily stop loss limit reached. Trading paused until: ", TimeToString(trading_pause_until));
    }
}

//+------------------------------------------------------------------+
//| Check if trading is paused                                      |
//+------------------------------------------------------------------+
bool CheckTradingPause()
{
    if(is_trading_paused)
    {
        if(TimeCurrent() >= trading_pause_until)
        {
            is_trading_paused = false;
            Print("Trading pause ended. Resuming trading.");
            return false;
        }
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Create trade label on chart                                     |
//+------------------------------------------------------------------+
void CreateTradeLabel(string text, color label_color)
{
    string label_name = "TradeLabel_" + IntegerToString(TimeCurrent());
    
    double current_close = iClose(Symbol(), InpTimeframe, 0);
    if(ObjectCreate(chart_id, label_name, OBJ_TEXT, 0, TimeCurrent(), current_close))
    {
        ObjectSetString(chart_id, label_name, OBJPROP_TEXT, text);
        ObjectSetInteger(chart_id, label_name, OBJPROP_COLOR, label_color);
        ObjectSetInteger(chart_id, label_name, OBJPROP_FONTSIZE, 10);
        ObjectSetString(chart_id, label_name, OBJPROP_FONT, "Arial");
        ObjectSetInteger(chart_id, label_name, OBJPROP_ANCHOR, ANCHOR_LOWER);
    }
}

//+------------------------------------------------------------------+
//| Create information panel                                        |
//+------------------------------------------------------------------+
void CreateInfoPanel()
{
    string panel_name = "InfoPanel";
    
    if(ObjectCreate(chart_id, panel_name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
    {
        ObjectSetInteger(chart_id, panel_name, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(chart_id, panel_name, OBJPROP_YDISTANCE, 10);
        ObjectSetInteger(chart_id, panel_name, OBJPROP_XSIZE, 300);
        ObjectSetInteger(chart_id, panel_name, OBJPROP_YSIZE, 200);
        ObjectSetInteger(chart_id, panel_name, OBJPROP_BGCOLOR, InpPanelColor);
        ObjectSetInteger(chart_id, panel_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(chart_id, panel_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    }
}

//+------------------------------------------------------------------+
//| Update information panel                                        |
//+------------------------------------------------------------------+
void UpdateInfoPanel()
{
    string info_text = "";
    
    // EA Settings
    info_text += "=== BTCUSD DMI EA ===\n";
    info_text += "DMI Period: " + IntegerToString(InpDMIPeriod) + "\n";
    info_text += "Timeframe: " + EnumToString(InpTimeframe) + "\n";
    info_text += "Lot Multiplier: " + DoubleToString(InpLotMultiplier, 2) + "\n";
    info_text += "\n";
    
    // Current DMI Values
    info_text += "=== DMI Values ===\n";
    info_text += "+DI: " + DoubleToString(plus_di[1], 2) + "\n";
    info_text += "-DI: " + DoubleToString(minus_di[1], 2) + "\n";
    info_text += "ADX: " + DoubleToString(adx[1], 2) + "\n";
    info_text += "ADX Interval: " + IntegerToString(GetADXInterval(adx[1])) + "\n";
    info_text += "\n";
    
    // Position Info
    info_text += "=== Position Info ===\n";
    if(current_position_type != EA_POSITION_NONE)
    {
        string pos_type = (current_position_type == EA_POSITION_LONG) ? "Long" : "Short";
        info_text += "Position: " + pos_type + "\n";
        info_text += "Volume: " + DoubleToString(current_position_volume, 2) + "\n";
        info_text += "Entry ADX: " + DoubleToString(entry_adx_value, 2) + "\n";
        info_text += "Entry Time: " + TimeToString(entry_time, TIME_MINUTES) + "\n";
        
        if(PositionSelect(Symbol()))
        {
            double profit = PositionGetDouble(POSITION_PROFIT);
            info_text += "P&L: $" + DoubleToString(profit, 2) + "\n";
        }
    }
    else
    {
        info_text += "Position: None\n";
    }
    info_text += "\n";
    
    // Trade Statistics
    info_text += "=== Trade Statistics ===\n";
    info_text += "Daily Trades: " + IntegerToString(daily_trade_count) + "\n";
    info_text += "Total Trades: " + IntegerToString(total_trade_count) + "\n";
    info_text += "Daily SL Count: " + IntegerToString(daily_stop_loss_count) + "/" + IntegerToString(InpDailyStopLossLimit) + "\n";
    info_text += "\n";
    
    // Risk Management
    info_text += "=== Risk Management ===\n";
    if(is_trading_paused)
    {
        info_text += "Trading Paused Until: " + TimeToString(trading_pause_until, TIME_MINUTES) + "\n";
    }
    else
    {
        info_text += "Trading Status: Active\n";
    }
    
    // Create or update text label
    string label_name = "InfoText";
    if(ObjectFind(chart_id, label_name) < 0)
    {
        ObjectCreate(chart_id, label_name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(chart_id, label_name, OBJPROP_XDISTANCE, 15);
        ObjectSetInteger(chart_id, label_name, OBJPROP_YDISTANCE, 15);
        ObjectSetInteger(chart_id, label_name, OBJPROP_COLOR, InpTextColor);
        ObjectSetInteger(chart_id, label_name, OBJPROP_FONTSIZE, 8);
        ObjectSetString(chart_id, label_name, OBJPROP_FONT, "Courier New");
        ObjectSetInteger(chart_id, label_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    }
    
    ObjectSetString(chart_id, label_name, OBJPROP_TEXT, info_text);
}

//+------------------------------------------------------------------+
//| Remove all chart objects                                        |
//+------------------------------------------------------------------+
void RemoveChartObjects()
{
    ObjectDelete(chart_id, "InfoPanel");
    ObjectDelete(chart_id, "InfoText");
    
    // Remove trade labels
    int total_objects = ObjectsTotal(chart_id);
    for(int i = total_objects - 1; i >= 0; i--)
    {
        string obj_name = ObjectName(chart_id, i);
        if(StringFind(obj_name, "TradeLabel_") >= 0)
        {
            ObjectDelete(chart_id, obj_name);
        }
    }
}

//+------------------------------------------------------------------+