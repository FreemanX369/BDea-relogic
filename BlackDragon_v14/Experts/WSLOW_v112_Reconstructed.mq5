//+------------------------------------------------------------------+
//| WSLOW_v112_Reconstructed.mq5                                     |
//| Behavioral reconstruction from authorized WSLOW public v1.12 EX5 |
//| Evidence-locked: inputs, basket math, recovery sizing, TP/SL.     |
//| Signal core: isolated proxy pending runtime-memory recovery.       |
//+------------------------------------------------------------------+
#property strict
#property version   "1.12"
#property description "Behavioral reconstruction of WSLOW public v1.12"

#include <Trade/Trade.mqh>

CTrade trade;

input group "=== WFAST SLOW | GENERAL ===="
input ulong  InpMagic                  = 1231213;
input int    InpDirection              = 0;      // 0=BOTH, 1=BUY only, 2=SELL only
input bool   InpAllowOpeningNewBasket  = true;
input bool   InpAllowHedging           = true;

input group "=== TRADING SESSION ===="
input int    InpStartHour              = 0;
input int    InpStopHour               = 23;
input bool   InpAllowTradingOnHolidays = false;
input double InpMaximumSpreadPips      = 100.0;
input double InpMaximumSpreadPrice     = 1.0;
input double InpMaximumSlippagePips    = 100.0;

input group "=== SYMBOL / DISTANCE ===="
input int    InpDistanceMode           = 1;      // 0=pips, 1=price
input double InpTradeDistancePips      = 35.0;
input double InpTradeDistancePrice     = 5.0;
input int    InpMaximumTrades          = 9;

input group "=== LOT SIZE ===="
input int    InpLotMode                = 0;      // 0=fixed, 1=balance/divider scaled
input double InpFixedLot               = 0.01;
input double InpDynamicDivider         = 10000.0;
input double InpMaximumLot             = 100.0;

input group "=== TAKE PROFIT ===="
input double InpInitialTPPips          = 15.0;
input double InpInitialTPPrice         = 2.0;

input group "=== STOP LOSS ===="
input double InpGridSLPips             = 0.0;
input double InpGridSLPrice            = 0.0;
input double InpEmergencySLPips        = 1000.0;
input double InpEmergencySLPrice       = 150.0;

// Signal parameters were not exposed by the original EX5. Keep the proxy
// isolated here so recovered runtime semantics can replace only this module.
#define SIGNAL_TF        PERIOD_M15
#define SIGNAL_FAST      5
#define SIGNAL_SLOW      21
#define SIGNAL_ATR       14
#define SIGNAL_ATR_GATE  0.20

int      g_fast_handle = INVALID_HANDLE;
int      g_slow_handle = INVALID_HANDLE;
int      g_atr_handle  = INVALID_HANDLE;
datetime g_last_m15_bar = 0;

struct BasketState
{
   bool               active;
   ENUM_POSITION_TYPE type;
   int                count;
   double             total_lots;
   double             weighted_price;
   double             p1_price;
   long               p1_time_msc;
};

double NormalizePrice(const double price)
{
   return NormalizeDouble(price,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
}

double PipSize()
{
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   return point*((digits==3 || digits==5)?10.0:1.0);
}

double DistanceValue(const double pips,const double price)
{
   return (InpDistanceMode==1)?price:pips*PipSize();
}

double TradeDistance()
{
   return DistanceValue(InpTradeDistancePips,InpTradeDistancePrice);
}

double InitialTPDistance()
{
   return DistanceValue(InpInitialTPPips,InpInitialTPPrice);
}

double GridSLDistance()
{
   return DistanceValue(InpGridSLPips,InpGridSLPrice);
}

double EmergencySLDistance()
{
   return DistanceValue(InpEmergencySLPips,InpEmergencySLPrice);
}

double NormalizeLot(double lots)
{
   double minlot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxlot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) step=minlot;
   lots=MathMax(minlot,MathMin(MathMin(maxlot,InpMaximumLot),lots));
   lots=MathFloor(lots/step+1e-9)*step;
   int vd=2;
   if(step<0.01) vd=3;
   if(step<0.001) vd=4;
   return NormalizeDouble(lots,vd);
}

double BaseLot()
{
   double lot=InpFixedLot;
   if(InpLotMode!=0 && InpDynamicDivider>0.0)
      lot=InpFixedLot*(AccountInfoDouble(ACCOUNT_BALANCE)/InpDynamicDivider);
   return NormalizeLot(lot);
}

double LevelLot(const int level)
{
   double base=BaseLot();
   if(level<=2) return base;
   return NormalizeLot(base*MathPow(2.0,level-2));
}

bool IsOurPosition(const ulong ticket)
{
   if(ticket==0 || !PositionSelectByTicket(ticket)) return false;
   if(PositionGetString(POSITION_SYMBOL)!=_Symbol) return false;
   return (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic;
}

bool ReadBasket(BasketState &b)
{
   b.active=false;
   b.count=0;
   b.total_lots=0.0;
   b.weighted_price=0.0;
   b.p1_price=0.0;
   b.p1_time_msc=LONG_MAX;
   b.type=POSITION_TYPE_BUY;

   double weighted_sum=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!IsOurPosition(ticket)) continue;

      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double lots=PositionGetDouble(POSITION_VOLUME);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      long tmsc=(long)PositionGetInteger(POSITION_TIME_MSC);

      if(!b.active)
      {
         b.active=true;
         b.type=type;
      }
      if(type!=b.type) continue;

      b.count++;
      b.total_lots+=lots;
      weighted_sum+=open*lots;
      if(tmsc<b.p1_time_msc)
      {
         b.p1_time_msc=tmsc;
         b.p1_price=open;
      }
   }

   if(!b.active || b.count<=0 || b.total_lots<=0.0)
   {
      b.active=false;
      return false;
   }
   b.weighted_price=weighted_sum/b.total_lots;
   return true;
}

bool NewM15Bar()
{
   datetime t=iTime(_Symbol,SIGNAL_TF,0);
   if(t<=0 || t==g_last_m15_bar) return false;
   g_last_m15_bar=t;
   return true;
}

bool SessionAllowed()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   if(dt.day_of_week==0 || dt.day_of_week==6) return false;

   if(InpStartHour<=InpStopHour)
   {
      if(dt.hour<InpStartHour || dt.hour>InpStopHour) return false;
   }
   else
   {
      if(dt.hour>InpStopHour && dt.hour<InpStartHour) return false;
   }
   return true;
}

bool SpreadAllowed()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;
   double spread=tick.ask-tick.bid;
   if(InpMaximumSpreadPrice>0.0 && spread>InpMaximumSpreadPrice) return false;
   double pip=PipSize();
   if(InpMaximumSpreadPips>0.0 && pip>0.0 && spread/pip>InpMaximumSpreadPips) return false;
   return true;
}

bool DirectionAllowed(const ENUM_POSITION_TYPE type)
{
   if(InpDirection==0) return true;
   if(InpDirection==1) return type==POSITION_TYPE_BUY;
   if(InpDirection==2) return type==POSITION_TYPE_SELL;
   return false;
}

int SignalCore()
{
   double fast[1],slow[1],atr[1];
   if(CopyBuffer(g_fast_handle,0,1,1,fast)!=1) return 0;
   if(CopyBuffer(g_slow_handle,0,1,1,slow)!=1) return 0;
   if(CopyBuffer(g_atr_handle ,0,1,1,atr )!=1) return 0;
   if(atr[0]<=0.0) return 0;

   double delta=fast[0]-slow[0];
   double gate=atr[0]*SIGNAL_ATR_GATE;
   if(delta<=-gate) return +1;
   if(delta>= gate) return -1;
   return 0;
}

double BasketTP(const BasketState &b)
{
   double target_cash_distance=BaseLot()*InitialTPDistance();
   double distance=target_cash_distance/b.total_lots;
   if(b.type==POSITION_TYPE_BUY) return NormalizePrice(b.weighted_price+distance);
   return NormalizePrice(b.weighted_price-distance);
}

double BasketSL(const BasketState &b)
{
   double grid=GridSLDistance();
   double emergency=EmergencySLDistance();
   double d=0.0;

   if(grid>0.0 && emergency>0.0) d=MathMin(grid,emergency);
   else if(grid>0.0) d=grid;
   else d=emergency;
   if(d<=0.0) return 0.0;

   if(b.type==POSITION_TYPE_BUY) return NormalizePrice(b.p1_price-d);
   return NormalizePrice(b.p1_price+d);
}

bool ApplyBasketProtection()
{
   BasketState b;
   if(!ReadBasket(b)) return true;

   double tp=BasketTP(b);
   double sl=BasketSL(b);
   bool ok=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!IsOurPosition(ticket)) continue;
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type!=b.type) continue;
      if(!trade.PositionModify(ticket,sl,tp))
      {
         PrintFormat("[WFAST SLOW] MODIFY FAIL ticket=%I64u ret=%u %s",
                     ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
         ok=false;
      }
   }
   return ok;
}

bool OpenLeg(const ENUM_POSITION_TYPE type,const int level)
{
   double lots=LevelLot(level);
   if(lots<=0.0) return false;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   double pip=PipSize();
   int dev=(pip>0.0)?(int)MathRound(InpMaximumSlippagePips*pip/_Point):0;
   trade.SetDeviationInPoints((ulong)MathMax(0,dev));

   bool ok=false;
   if(type==POSITION_TYPE_BUY)
      ok=trade.Buy(lots,_Symbol,0.0,0.0,0.0,StringFormat("WFAST SLOW P%d",level));
   else
      ok=trade.Sell(lots,_Symbol,0.0,0.0,0.0,StringFormat("WFAST SLOW P%d",level));

   if(!ok)
   {
      PrintFormat("[WFAST SLOW] OPEN FAIL P%d lots=%.2f ret=%u %s",
                  level,lots,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      return false;
   }

   double px=trade.ResultPrice();
   PrintFormat("[WFAST SLOW] OPEN %s P%d lots=%.2f price=%.3f",
               type==POSITION_TYPE_BUY?"BUY":"SELL",level,lots,px);
   ApplyBasketProtection();
   return true;
}

bool RecoveryTriggered(const BasketState &b,const int next_level)
{
   if(next_level<2) return false;
   double distance=TradeDistance();
   if(distance<=0.0) return false;
   double threshold;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;

   if(b.type==POSITION_TYPE_BUY)
   {
      threshold=b.p1_price-distance*(next_level-1);
      return tick.ask<=threshold;
   }
   threshold=b.p1_price+distance*(next_level-1);
   return tick.bid>=threshold;
}

void ProcessNewM15Bar()
{
   if(!SessionAllowed() || !SpreadAllowed()) return;

   BasketState b;
   if(ReadBasket(b))
   {
      if(b.count>=InpMaximumTrades) return;
      int next=b.count+1;
      if(RecoveryTriggered(b,next))
      {
         PrintFormat("[WFAST SLOW] Recovery level triggered: P%d lots=%.2f",next,LevelLot(next));
         OpenLeg(b.type,next);
      }
      return;
   }

   if(!InpAllowOpeningNewBasket) return;
   int sig=SignalCore();
   if(sig>0 && DirectionAllowed(POSITION_TYPE_BUY)) OpenLeg(POSITION_TYPE_BUY,1);
   if(sig<0 && DirectionAllowed(POSITION_TYPE_SELL)) OpenLeg(POSITION_TYPE_SELL,1);
}

int OnInit()
{
   if(InpMaximumTrades<1 || InpFixedLot<=0.0 || TradeDistance()<=0.0)
      return INIT_PARAMETERS_INCORRECT;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_fast_handle=iMA(_Symbol,SIGNAL_TF,SIGNAL_FAST,0,MODE_LWMA,PRICE_CLOSE);
   g_slow_handle=iMA(_Symbol,SIGNAL_TF,SIGNAL_SLOW,0,MODE_LWMA,PRICE_CLOSE);
   g_atr_handle =iATR(_Symbol,SIGNAL_TF,SIGNAL_ATR);
   if(g_fast_handle==INVALID_HANDLE || g_slow_handle==INVALID_HANDLE || g_atr_handle==INVALID_HANDLE)
      return INIT_FAILED;

   Print("====================================================");
   Print(" WFAST SLOW PUBLIC v1.12 reconstruction initialized");
   Print(" Symbol: ",_Symbol);
   Print(" Direction: ",InpDirection==0?"BOTH":(InpDirection==1?"BUY":"SELL"));
   Print(" Max trades: ",InpMaximumTrades);
   Print(" P1 lot: ",DoubleToString(BaseLot(),2));
   Print(" Adaptive core: RECONSTRUCTED PROXY");
   Print("====================================================");

   ApplyBasketProtection();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_fast_handle!=INVALID_HANDLE) IndicatorRelease(g_fast_handle);
   if(g_slow_handle!=INVALID_HANDLE) IndicatorRelease(g_slow_handle);
   if(g_atr_handle !=INVALID_HANDLE) IndicatorRelease(g_atr_handle);
}

void OnTick()
{
   if(NewM15Bar()) ProcessNewM15Bar();
}
