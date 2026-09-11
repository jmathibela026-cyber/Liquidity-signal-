//+------------------------------------------------------------------+
//|                                          LiquiditySignalEA.mq5    |
//|  Polls the local bridge server for signals from the Liquidity    |
//|  Signal app and auto-executes them with SL/TP attached.          |
//|                                                                    |
//|  SETUP:                                                            |
//|  1. Copy this file into MQL5/Experts/ in your MT5 data folder      |
//|     (File > Open Data Folder from within MT5), then recompile      |
//|     in MetaEditor.                                                 |
//|  2. Tools > Options > Expert Advisors > check "Allow WebRequest    |
//|     for listed URL" and add your bridge address, e.g.              |
//|     http://127.0.0.1:5000                                          |
//|  3. Drag this EA onto ANY chart (it trades whatever symbol the     |
//|     signal specifies, not just the chart it's attached to).        |
//|  4. Set the inputs below (BridgeURL, SharedSecret must match the   |
//|     bridge server and the browser app exactly).                    |
//|  5. Make sure AutoTrading (top toolbar) is enabled in MT5.         |
//|                                                                    |
//|  SAFETY: AllowLiveTrading defaults to false. On a REAL account,    |
//|  the EA will log a warning and refuse to trade until you           |
//|  deliberately set AllowLiveTrading = true. Always prove this out   |
//|  on a demo account first.                                          |
//+------------------------------------------------------------------+
#property copyright "Liquidity Signal"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Inputs
input string BridgeURL          = "http://127.0.0.1:5000"; // Bridge server base URL (no trailing slash)
input string SharedSecret       = "change-this-secret";     // Must match bridge_server.py and the app
input int    PollSeconds        = 5;                        // How often to check for a new signal
input double RiskPercent        = 1.0;                      // % of account balance risked per trade
input int    MagicNumber        = 20260911;                 // Identifies trades placed by this EA
input int    MaxSlippagePoints  = 30;                        // Max allowed slippage on entry
input bool   AllowLiveTrading   = false;                     // Must be true to trade on a REAL account
input bool   OneOpenTradeAtATime = true;                     // Skip new signals while a position from this EA is open

//--- Globals
CTrade  trade;
long    g_lastSignalId = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxSlippagePoints);
   EventSetTimer(MathMax(1, PollSeconds));
   Print("LiquiditySignalEA initialized. Polling ", BridgeURL, " every ", PollSeconds, "s.");

   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !AllowLiveTrading)
      Print("WARNING: This is a REAL account and AllowLiveTrading=false. "
            "The EA will poll for signals but will NOT place any trades until you "
            "explicitly set AllowLiveTrading=true. Test on demo first.");

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   PollBridge();
  }

//+------------------------------------------------------------------+
//| Very small JSON field extractor - good enough for this flat       |
//| response shape. Returns "" if the key is not found.                |
//+------------------------------------------------------------------+
string JsonGetString(const string &json, const string &key)
  {
   string pattern = "\"" + key + "\"";
   int pos = StringFind(json, pattern);
   if(pos < 0) return "";
   pos = StringFind(json, ":", pos);
   if(pos < 0) return "";
   pos++;
   // skip whitespace
   while(pos < StringLen(json) && (StringGetCharacter(json, pos) == ' ')) pos++;
   if(pos >= StringLen(json)) return "";

   if(StringGetCharacter(json, pos) == '"')
     {
      int start = pos + 1;
      int end = StringFind(json, "\"", start);
      if(end < 0) return "";
      return StringSubstr(json, start, end - start);
     }
   else if(StringGetCharacter(json, pos) == 'n') // null
     {
      return "";
     }
   else
     {
      int end = pos;
      while(end < StringLen(json))
        {
         ushort c = StringGetCharacter(json, end);
         if(c == ',' || c == '}' || c == ' ' || c == '\n' || c == '\r') break;
         end++;
        }
      return StringSubstr(json, pos, end - pos);
     }
  }

double JsonGetDouble(const string &json, const string &key)
  {
   string s = JsonGetString(json, key);
   if(s == "") return EMPTY_VALUE;
   return StringToDouble(s);
  }

long JsonGetLong(const string &json, const string &key)
  {
   string s = JsonGetString(json, key);
   if(s == "") return -1;
   return (long)StringToInteger(s);
  }

//+------------------------------------------------------------------+
void PollBridge()
  {
   string url = BridgeURL + "/signal/latest?after=" + IntegerToString(g_lastSignalId);
   string headers = "X-Signal-Secret: " + SharedSecret + "\r\n";
   char post[]; // empty for GET
   char result[];
   string result_headers;
   int timeout = 5000;

   ResetLastError();
   int status = WebRequest("GET", url, headers, timeout, post, result, result_headers);

   if(status == -1)
     {
      int err = GetLastError();
      if(err == 4060)
         Print("WebRequest blocked. Add ", BridgeURL,
               " to Tools > Options > Expert Advisors > Allow WebRequest for listed URL.");
      else
         Print("WebRequest failed, error ", err);
      return;
     }

   if(status != 200)
     {
      Print("Bridge returned HTTP ", status);
      return;
     }

   string json = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);

   long id = JsonGetLong(json, "id");
   string signal = JsonGetString(json, "signal");

   if(id <= 0 || signal == "" || id <= g_lastSignalId)
      return; // nothing new

   g_lastSignalId = id; // mark consumed even if we end up rejecting it below

   if(signal != "BUY" && signal != "SELL")
      return;

   string symbol      = JsonGetString(json, "symbol");
   double stopLoss     = JsonGetDouble(json, "stopLoss");
   double takeProfit   = JsonGetDouble(json, "takeProfit");
   string entrySetup   = JsonGetString(json, "entrySetupType");

   Print("New signal #", id, ": ", signal, " ", symbol,
         " SL=", stopLoss, " TP=", takeProfit,
         (entrySetup != "" ? " setup=" + entrySetup : ""));

   ExecuteSignal(signal, symbol, stopLoss, takeProfit);
  }

//+------------------------------------------------------------------+
void ExecuteSignal(string signal, string symbol, double stopLoss, double takeProfit)
  {
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !AllowLiveTrading)
     {
      Print("REJECTED: real account and AllowLiveTrading=false. Set the input to true to allow.");
      return;
     }

   if(symbol == "")
     {
      Print("REJECTED: no symbol in signal.");
      return;
     }

   if(!SymbolSelect(symbol, true))
     {
      Print("REJECTED: symbol '", symbol, "' not found/enabled in Market Watch. "
            "Check it matches your broker's exact symbol name (e.g. suffixes like EURUSD.a).");
      return;
     }

   if(stopLoss == EMPTY_VALUE || takeProfit == EMPTY_VALUE)
     {
      Print("REJECTED: missing stopLoss or takeProfit.");
      return;
     }

   if(OneOpenTradeAtATime && HasOpenPositionForThisEA())
     {
      Print("SKIPPED: an EA position is already open and OneOpenTradeAtATime=true.");
      return;
     }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
     {
      Print("REJECTED: could not get current tick for ", symbol);
      return;
     }

   double ask = tick.ask;
   double bid = tick.bid;
   ENUM_ORDER_TYPE orderType;
   double entryPrice;

   if(signal == "BUY")
     {
      orderType   = ORDER_TYPE_BUY;
      entryPrice  = ask;
      if(!(stopLoss < entryPrice && takeProfit > entryPrice))
        {
         Print("REJECTED: BUY levels don't make sense vs live price. "
               "entry=", entryPrice, " SL=", stopLoss, " TP=", takeProfit,
               " -- the screenshot may be stale or price has moved since analysis.");
         return;
        }
     }
   else // SELL
     {
      orderType   = ORDER_TYPE_SELL;
      entryPrice  = bid;
      if(!(stopLoss > entryPrice && takeProfit < entryPrice))
        {
         Print("REJECTED: SELL levels don't make sense vs live price. "
               "entry=", entryPrice, " SL=", stopLoss, " TP=", takeProfit,
               " -- the screenshot may be stale or price has moved since analysis.");
         return;
        }
     }

   double lots = CalculateLotSize(symbol, entryPrice, stopLoss);
   if(lots <= 0)
     {
      Print("REJECTED: computed lot size was zero (check RiskPercent, stop distance, symbol limits).");
      return;
     }

   bool sent;
   if(orderType == ORDER_TYPE_BUY)
      sent = trade.Buy(lots, symbol, 0.0, stopLoss, takeProfit, "LiquiditySignal");
   else
      sent = trade.Sell(lots, symbol, 0.0, stopLoss, takeProfit, "LiquiditySignal");

   if(sent)
      Print("EXECUTED: ", signal, " ", symbol, " lots=", lots,
            " SL=", stopLoss, " TP=", takeProfit,
            " retcode=", trade.ResultRetcode());
   else
      Print("ORDER FAILED: ", signal, " ", symbol,
            " retcode=", trade.ResultRetcode(), " (", trade.ResultRetcodeDescription(), ")");
  }

//+------------------------------------------------------------------+
bool HasOpenPositionForThisEA()
  {
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Position size from risk % of balance and the stop distance.       |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double entryPrice, double stopLoss)
  {
   double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount  = balance * (RiskPercent / 100.0);

   double tickSize    = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double volumeStep  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double volumeMin   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double volumeMax   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(tickSize <= 0 || tickValue <= 0)
     {
      Print("Could not read tick size/value for ", symbol, "; using volumeMin as fallback.");
      return volumeMin;
     }

   double stopDistance = MathAbs(entryPrice - stopLoss);
   if(stopDistance <= 0)
      return 0;

   double valuePerLot = (stopDistance / tickSize) * tickValue;
   if(valuePerLot <= 0)
      return 0;

   double lots = riskAmount / valuePerLot;

   // normalize to broker's step/min/max
   lots = MathFloor(lots / volumeStep) * volumeStep;
   if(lots < volumeMin) lots = volumeMin;
   if(lots > volumeMax) lots = volumeMax;

   return NormalizeDouble(lots, 2);
  }
//+------------------------------------------------------------------+
