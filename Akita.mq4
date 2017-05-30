//+------------------------------------------------------------------+
//|                                                        Akita.mq4 |
//|                           Copyright 2017, Palawan Software, Ltd. |
//|                             https://coconala.com/services/204383 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2017, Palawan Software, Ltd."
#property link      "https://coconala.com/services/204383"
#property description "Author: Kotaro Hashimoto <hasimoto.kotaro@gmail.com>"
#property version   "1.00"
#property strict

input string Comment = "Akita"; //[新規注文設定] コメント
input int MagicNumber = 777; //[新規注文設定] マジックナンバー
input double EntryLot = 0.1; //[新規注文設定] 数量
input double Slippage = 3.0; //[新規注文設定] 最大価格誤差(Pips)
input double StopLoss = 0.0; //[新規注文設定] S/L:決済逆指値(Pips)
input double TakeProfit = 30.0; //[新規注文設定] T/P:決済指値(Pips)


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

input int MA_Period = 100; //[Moving Average] 期間
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
input double FNampinSpan = 31.0; //[ナンピン設定][順張り] 間隔(Pips)

input bool RNampin = True; //[ナンピン設定][逆張り] ON/OFF
input double RNampinLot = 0.02; //[ナンピン設定][逆張り] 数量(増分)
input double RNampinSpan = 30.0; //[ナンピン設定][逆張り] 間隔(Pips)

input bool Trail = True; //[トレール設定] ON/OFF
input double TrailStart = 7.0; //[トレール設定] トレール開始利益(Pips)
input double TrailSL = 1.5; //[トレール設定] トレール幅(Pips)

input bool SpreadFilter = True; //[スプレッドフィルタ設定] ON/OFF
input double AcceptableSpread = 3.0; //[スプレッドフィルタ設定] 許容スプレッド(Pips)


string thisSymbol;
double previousPrice;

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
  
  for(int i = 0; i < OrdersTotal(); i++) {
    if(OrderSelect(i, SELECT_BY_POS)) {
      if(!StringCompare(OrderSymbol(), thisSymbol) && OrderMagicNumber() == MagicNumber) {
        count ++;
      }
    }
  }

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

  thisSymbol = Symbol();
  previousPrice = (Ask + Bid) / 2.0;
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
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
              bool mod = OrderModify(OrderTicket(), OrderOpenPrice(), Bid - (Point * 10.0 * TrailSL), 0, 0);
            }
          }
          else {
            if(Point * 10.0 * TrailSL < Bid - OrderStopLoss()) {
              bool mod = OrderModify(OrderTicket(), OrderOpenPrice(), Bid - (Point * 10.0 * TrailSL), 0, 0);
            }
          }
        }
        
        if(OrderType() == OP_SELL) {
          if(OrderStopLoss() == 0){
            if(TrailStart * 10.0 * Point < OrderOpenPrice() - Ask) {
              bool mod = OrderModify(OrderTicket(), OrderOpenPrice(), Ask + (Point * 10.0 * TrailSL), 0, 0);
            }
          }
          else {
            if(Point * 10.0 * TrailSL < OrderStopLoss() - Ask) {
              bool mod = OrderModify(OrderTicket(), OrderOpenPrice(), Ask + (Point * 10.0 * TrailSL), 0, 0);
            }
          }
        }
      }
    }
  }  
}


//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---

  int signal = getSignal();
  previousPrice = (Ask + Bid) / 2.0;

  if(0 < getOrdersTotal()) {
    trail();
  }
  
  else {
    if(SpreadFilter) {
      if(AcceptableSpread * 10.0 < MarketInfo(Symbol(), MODE_SPREAD)) {
        Print("no entry in unacceptable spread: ", 10.0 * MarketInfo(Symbol(), MODE_SPREAD));
        return;
      }
    }
    
    if(signal == OP_BUY) {    
      int ticket = OrderSend(Symbol(), OP_BUY, EntryLot, NormalizeDouble(Ask, Digits), int(Slippage * 10.0), sltp(Ask, -10.0 * StopLoss * Point), sltp(Ask, 10.0 * TakeProfit * Point), Comment, MagicNumber);
    }
    else if(signal == OP_SELL) {
      int ticket = OrderSend(Symbol(), OP_SELL, EntryLot, NormalizeDouble(Bid, Digits), int(Slippage * 10.0), sltp(Bid, 10.0 * StopLoss * Point), sltp(Bid, -10.0 * TakeProfit * Point), Comment, MagicNumber);
    }
  }   
}
//+------------------------------------------------------------------+

