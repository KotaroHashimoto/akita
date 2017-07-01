//+------------------------------------------------------------------+
//|                                               SuperProfit_EA.mq4 |
//|                           Copyright 2017, Palawan Software, Ltd. |
//|                             https://coconala.com/services/204383 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2017, Palawan Software, Ltd."
#property link      "https://coconala.com/services/204383"
#property description "Author: Kotaro Hashimoto <hasimoto.kotaro@gmail.com>"
#property version   "1.00"
#property strict

// この番号の口座番号のアカウントでなければ稼働しない
const int Account_Number = 12345678;

input string Comment = "Akita"; //[新規注文設定] コメント
input bool Email = True; //[Eメール設定] トレード通知ON/OFF
input int MagicNumber = 1; //[新規注文設定] マジックナンバー
input double EntryLot = 0.01; //[新規注文設定] 数量
input double Slippage = 10.0; //[新規注文設定] 最大価格誤差(Pips)
input double StopLoss = 0.0; //[新規注文設定] S/L:決済逆指値(Pips)
input double TakeProfit = 50.0; //[新規注文設定] T/P:決済指値(Pips)

input bool Compound = False; //[複利設定] 複利ロット計算 ON/OFF
input double BaseEquity = 100000; //[複利設定] 複利基準資金


enum Method {
  Simple = MODE_SMA,
  Exponential = MODE_EMA,
  Smoothed = MODE_SMMA,
  Linear_Weighted = MODE_LWMA,
};

enum APrice {
  Close_Price = PRICE_CLOSE,
  Open_Price = PRICE_OPEN,
  High_Price = PRICE_HIGH,
  Low_Price = PRICE_LOW,
  Median_Price = PRICE_MEDIAN,
  Typical_Price = PRICE_TYPICAL,
  Weighted_Price = PRICE_WEIGHTED,
};

enum PField {
  Low_High = STO_LOWHIGH,
  Close_Close = STO_CLOSECLOSE,
};

input int MA_Period = 200; //[Moving Average] 期間
input Method MA_Method = Exponential; //[Moving Average] 種別
input APrice MA_APrice = Close_Price; //[Moving Average] 適用価格
input double MA_Level = 30.0; //[Moving Average] レベル(Pips)

input bool StochFilter = True; //[Stochastic Oscillator] フィルタON/OFF
input int K_Period = 100; //[Stochastic Oscillator] %K期間
input int D_Period = 3; //[Stochastic Oscillator] %D期間
input int Slowing = 3; //[Stochastic Oscillator] スローイング
input Method SC_Method = Exponential; //[Stochastic Oscillator] 種別
input PField SC_PField = Close_Close; //[Stochastic Oscillator] 価格欄
input int BuyLevel = 10; //[Stochastic Oscillator] レベル(BUY)
input int SellLevel = 90; //[Stochastic Oscillator] レベル(SELL)

input bool FNampin = True; //[ナンピン設定][順張り] ON/OFF 
input double FNampinLot = 0.02; //[ナンピン設定][順張り] 数量
input double FNampinSpan = 100.0; //[ナンピン設定][順張り] 間隔(Pips)

input bool RNampin = True; //[ナンピン設定][逆張り] ON/OFF
input double RNampinLot = 0.02; //[ナンピン設定][逆張り] 数量(増分)
input double RNampinSpan = 300.0; //[ナンピン設定][逆張り] 間隔(Pips)

input double NampinStopLoss = -100000.0; //[ナンピン決済設定] S/L:損切決済合計Pips
input double NampinTakeProfit = 50.0; //[ナンピン決済設定] T/P:利確決済合計Pips


input bool Trail = True; //[トレール設定] ON/OFF
input double TrailStart = 30.0; //[トレール設定] トレール開始利益(Pips)
input double TrailSL = 15.0; //[トレール設定] トレール幅(Pips)

input bool SpreadFilter = True; //[スプレッドフィルタ設定] ON/OFF
input double AcceptableSpread = 5.0; //[スプレッドフィルタ設定] 許容スプレッド(Pips)


string thisSymbol;
double previousPrice;

double minLot;
double maxLot;
double lotStep;

int initialPosition;
int previousOrdersCount;
double previousProfit;

const string pipsLabel = "plabel";

datetime lastProfitTime;

void drawLabel() {

  ObjectCreate(0, pipsLabel, OBJ_LABEL, 0, 0, 0);
  ObjectSetInteger(0, pipsLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
  ObjectSet(pipsLabel, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
  ObjectSetInteger(0, pipsLabel, OBJPROP_SELECTABLE, false);

  ObjectSetText(pipsLabel, "", 16, "Arial", clrYellow);
}

void getEnvelope(double& bottom, double& upper) {

  double ma = iMA(Symbol(), PERIOD_CURRENT, MA_Period, 0, ENUM_MA_METHOD(MA_Method), ENUM_APPLIED_PRICE(MA_APrice), 1);
  double d = MA_Level * Point * 10.0;
  bottom = ma - d;
  upper = ma + d;
}


int detStochastic() {

  double ml = iStochastic(Symbol(), NULL, K_Period, D_Period, Slowing, ENUM_MA_METHOD(SC_Method), ENUM_STO_PRICE(SC_PField), 0, 1);
  double sl = iStochastic(Symbol(), NULL, K_Period, D_Period, Slowing, ENUM_MA_METHOD(SC_Method), ENUM_STO_PRICE(SC_PField), 1, 1);

  if(ml < BuyLevel && sl < BuyLevel) {
    return OP_BUY;
  }
  else if(SellLevel < ml && SellLevel < sl) {
    return OP_SELL;
  }
  else {
    return -1;
  }
}


int getOrdersTotal() {

  int count = 0;
  double profit = 0.0;
  
  for(int i = 0; i < OrdersTotal(); i++) {
    if(OrderSelect(i, SELECT_BY_POS)) {
      if(!StringCompare(OrderSymbol(), thisSymbol) && OrderMagicNumber() == MagicNumber) {
        count ++;
        profit += OrderProfit();
      }
    }
  }
  
  if(0 <= previousOrdersCount && Email) {
    if(count < previousOrdersCount) {
      string sbj = "Closed " + Symbol() + " (" + DoubleToStr(Bid, Digits) + "), Equity:" + DoubleToStr(AccountEquity());
      string msg = "Closed " + Symbol() + " positions at " + DoubleToStr(Bid, Digits) + " - " + DoubleToStr(Ask, Digits) + ", " + TimeToStr(TimeLocal()) + ", " + AccountServer() + ", Equity:" + DoubleToStr(AccountEquity());
      bool mail = SendMail(sbj, msg);
      Print(sbj, msg);
    }
    else if(previousOrdersCount < count) {
      string sbj = "Opened " + Symbol() + " (" + DoubleToStr(Bid, Digits) + "), Equity:" + DoubleToStr(AccountEquity());
      string msg = "Opened " + Symbol() + " positions at " + DoubleToStr(Bid, Digits) + " - " + DoubleToStr(Ask, Digits) + ", " + TimeToStr(TimeLocal()) + ", " + AccountServer() + ", Equity:" + DoubleToStr(AccountEquity());
      bool mail = SendMail(sbj, msg);
      Print(sbj, msg);
    }
    
    if(previousProfit <= 0.0 && 0.0 < profit) {
      if(600 < TimeLocal() - lastProfitTime) {
        string sbj = "Profit: +" + DoubleToStr(profit) + ", Equity:" + DoubleToStr(AccountEquity());
        string msg = IntegerToString(count) + " positions, " + Symbol() + " at " + DoubleToStr(Bid, Digits) + " - " + DoubleToStr(Ask, Digits) + ", " + TimeToStr(TimeLocal()) + ", " + AccountServer() + ", Equity:" + DoubleToStr(AccountEquity());
        bool mail = SendMail(sbj, msg);
        Print(sbj, msg);      
      }
      lastProfitTime = TimeLocal();
    }
  }

  previousOrdersCount = count;
  previousProfit = profit;
  return count;
}


int getSignal() {

  double price = (Ask + Bid) / 2.0;
  double bottom, upper;
  
  getEnvelope(bottom, upper);
  
  if(bottom < price && price < upper) {
    if(previousPrice < bottom) {
    
      if(StochFilter) {
        if(detStochastic() == OP_BUY) {
          return OP_BUY;
        }
        else {
          return -1;
        }
      }
      else {
        return OP_BUY;
      }
    }
    
    else if(upper < previousPrice) {
    
      if(StochFilter) {
        if(detStochastic() == OP_SELL) {
          return OP_SELL;
        }
        else {
          return -1;
        }
      }
      else {
        return OP_SELL;
      }
    }
  }
  
  return -1;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---

  minLot = MarketInfo(Symbol(), MODE_MINLOT);
  maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
  lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
  
  thisSymbol = Symbol();
  previousPrice = (Ask + Bid) / 2.0;
  initialPosition = -1;
  
  previousOrdersCount = -1;
  previousProfit = -1.0;
  
  lastProfitTime = TimeLocal();
  
  drawLabel();
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---

  ObjectDelete(0, pipsLabel);
   
  }
  
  
double sltp(double price, double delta) {

  if(delta == 0.0) {
    return 0.0;
  }
  else {
    return NormalizeDouble(price + delta, Digits);
  }
}

void trail() {

  if(!Trail) {
    return;
  }

  for(int i = 0; i < OrdersTotal(); i++) {
    if(OrderSelect(i, SELECT_BY_POS)) {
      if(!StringCompare(OrderSymbol(), thisSymbol) && OrderMagicNumber() == MagicNumber) {
      
        if(OrderType() == OP_BUY) {
          if(OrderStopLoss() == 0){
            if(TrailStart * 10.0 * Point < Bid - OrderOpenPrice()) {
              bool mod = OrderModify(OrderTicket(), OrderOpenPrice(), sltp(Bid, -1.0 *Point * 10.0 * TrailSL), 0, 0);
            }
          }
          else {
            if(Point * 10.0 * TrailSL < Bid - OrderStopLoss()) {
              bool mod = OrderModify(OrderTicket(), OrderOpenPrice(), sltp(Bid, -1.0 * Point * 10.0 * TrailSL), 0, 0);
            }
          }
        }
        
        if(OrderType() == OP_SELL) {
          if(OrderStopLoss() == 0){
            if(TrailStart * 10.0 * Point < OrderOpenPrice() - Ask) {
              bool mod = OrderModify(OrderTicket(), OrderOpenPrice(), sltp(Ask, Point * 10.0 * TrailSL), 0, 0);
            }
          }
          else {
            if(Point * 10.0 * TrailSL < OrderStopLoss() - Ask) {
              bool mod = OrderModify(OrderTicket(), OrderOpenPrice(), sltp(Ask, Point * 10.0 * TrailSL), 0, 0);
            }
          }
        }
      }
    }
  }  
}


double getHighLow(double& highestShortPrice, double& lowestLongPrice, double& highestShortLot, double& lowestLongLot, 
                  double& highestLongPrice, double& lowestShortPrice) {

  double pf = 0;

  highestShortPrice = 0;
  lowestLongPrice = 1000000;

  highestLongPrice = 0;
  lowestShortPrice = 1000000;

  for(int i = 0; i < OrdersTotal(); i++) {  
    if(OrderSelect(i, SELECT_BY_POS)) {
      if(!StringCompare(OrderSymbol(), thisSymbol) && OrderMagicNumber() == MagicNumber) {
      
        if(OrderType() == OP_BUY) {
          if(OrderOpenPrice() < lowestLongPrice) {
            lowestLongPrice = OrderOpenPrice();
            lowestLongLot = OrderLots();
          }
          if(highestLongPrice < OrderOpenPrice()) {
            highestLongPrice = OrderOpenPrice();
          }
          if(initialPosition == -1 && OrderLots() == EntryLot) {
            initialPosition = OP_BUY;
          }
          
          pf += Bid - OrderOpenPrice();
        }
        else if(OrderType() == OP_SELL) {
          if(highestShortPrice < OrderOpenPrice()) {
            highestShortPrice = OrderOpenPrice();
            highestShortLot = OrderLots();
          }
          if(OrderOpenPrice() < lowestShortPrice) {
            lowestShortPrice = OrderOpenPrice();
          }
          if(initialPosition == -1 && OrderLots() == EntryLot) {
            initialPosition = OP_SELL;
          }

          pf += OrderOpenPrice() - Ask;
        }
      }
    }  
  }
  
  if(lowestShortPrice == 1000000) {
    lowestShortPrice = lowestLongPrice - (Ask - Bid);
  }
  if(highestLongPrice == 0) {
    highestLongPrice = highestShortPrice + (Ask - Bid);
  }
  
  return pf / (Point * 10.0);
}

void closeAll() {

  for(int i = 0; i < OrdersTotal(); i++) {
    if(OrderSelect(i, SELECT_BY_POS)) {
      if(!StringCompare(OrderSymbol(), thisSymbol) && OrderMagicNumber() == MagicNumber) {
        if(OrderType() == OP_BUY) {
          if(!OrderClose(OrderTicket(), OrderLots(), NormalizeDouble(Bid, Digits), 3)) {
            Print("Error on closing long order: ", GetLastError());
          }
          else {
            i = -1;
          }
        }
        else if(OrderType() == OP_SELL) {
          if(!OrderClose(OrderTicket(), OrderLots(), NormalizeDouble(Ask, Digits), 3)) {
            Print("Error on closing short order: ", GetLastError());
          }
          else {
            i = -1;
          }
        }
      }
    }
  }
}


void nampin() {

  if(!FNampin && !RNampin) {
    return;
  }
  
  double highestShortPrice;
  double lowestLongPrice;
  double highestShortLot;
  double lowestLongLot;
  
  double highestLongPrice;
  double lowestShortPrice;

  double pips = getHighLow(highestShortPrice, lowestLongPrice, highestShortLot, lowestLongLot, 
                           highestLongPrice, lowestShortPrice);
  
  string lbl = DoubleToString(pips, 1) + " pips";
  if(0 < pips) {
    lbl = "+" + lbl;
  }
  ObjectSetText(pipsLabel, "Total: " + lbl, 16, "Arial", clrYellow);
  
  if(pips < NampinStopLoss || NampinTakeProfit < pips) {
    closeAll();
  }

  if(RNampin) {
    if(initialPosition == OP_BUY) {
      if(Ask + RNampinSpan * 10.0 * Point < lowestLongPrice) {
        double lot = lowestLongLot + RNampinLot;
        int ticket = OrderSend(Symbol(), OP_BUY, roundLot(lot), NormalizeDouble(Ask, Digits), int(Slippage * 10.0), 0, 0, Comment, MagicNumber, 0, clrMagenta);
      }
    }
    else if(initialPosition == OP_SELL) {
      if(highestShortPrice + RNampinSpan * 10.0 * Point < Bid) {
        double lot = highestShortLot + RNampinLot;
        int ticket = OrderSend(Symbol(), OP_SELL, roundLot(lot), NormalizeDouble(Bid, Digits), int(Slippage * 10.0), 0, 0, Comment, MagicNumber, 0, clrCyan);
      }
    }
  }  

  if(FNampin) {
  
    if(initialPosition == OP_BUY) {
      if(Bid + FNampinSpan * 10.0 * Point < lowestShortPrice) {
        int ticket = OrderSend(Symbol(), OP_SELL, roundLot(FNampinLot), NormalizeDouble(Bid, Digits), int(Slippage * 10.0), 0, 0, Comment, MagicNumber, 0, clrCyan);
      }
    }
    else if(initialPosition == OP_SELL) {
      if(highestLongPrice < Ask - FNampinSpan * 10.0 * Point) {
        int ticket = OrderSend(Symbol(), OP_BUY, roundLot(FNampinLot), NormalizeDouble(Ask, Digits), int(Slippage * 10.0), 0, 0, Comment, MagicNumber, 0, clrMagenta);
      }
    }
  }
}


double roundLot(double lot) {

  if(Compound) {
    lot *= AccountEquity() / BaseEquity;
  }

  lot = MathRound(lot / lotStep) * lotStep;
  
  if(maxLot < lot) {
    lot = maxLot;
  }
  else if(lot < minLot) {
    lot = 0.0;
  }

  return lot;
}


//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---

  if(AccountNumber() != Account_Number) {
    Print("Account Number mismatch. No operation.: ", Account_Number);
    return;
  }

  int signal = getSignal();
  previousPrice = (Ask + Bid) / 2.0;

  if(0 < getOrdersTotal()) {
    trail();
    nampin();
  }
  
  else {
    ObjectSetText(pipsLabel, "", 16, "Arial", clrYellow);
  
    initialPosition = -1;
  
    if(SpreadFilter) {
      if(AcceptableSpread * 10.0 < MarketInfo(Symbol(), MODE_SPREAD)) {
        Print("no entry in unacceptable spread: ", 10.0 * MarketInfo(Symbol(), MODE_SPREAD));
        return;
      }
    }
    
    if(signal == OP_BUY) {    
      int ticket = OrderSend(Symbol(), OP_BUY, roundLot(EntryLot), NormalizeDouble(Ask, Digits), int(Slippage * 10.0), sltp(Ask, -10.0 * StopLoss * Point), sltp(Ask, 10.0 * TakeProfit * Point), Comment, MagicNumber, 0, clrMagenta);
      initialPosition = OP_BUY;
    }
    else if(signal == OP_SELL) {
      int ticket = OrderSend(Symbol(), OP_SELL, roundLot(EntryLot), NormalizeDouble(Bid, Digits), int(Slippage * 10.0), sltp(Bid, 10.0 * StopLoss * Point), sltp(Bid, -10.0 * TakeProfit * Point), Comment, MagicNumber, 0, clrCyan);
      initialPosition = OP_SELL;
    }
  }   
}
//+------------------------------------------------------------------+
