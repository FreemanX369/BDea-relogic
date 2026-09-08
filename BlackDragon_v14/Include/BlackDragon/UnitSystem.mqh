//+------------------------------------------------------------------+
//| UnitSystem.mqh — canonical price/pip/tick conversion policy      |
//| Invariants: pure helpers only; no symbol lookup or trade calls.  |
//+------------------------------------------------------------------+
#ifndef BD_UNIT_SYSTEM_MQH
#define BD_UNIT_SYSTEM_MQH

#ifndef BD_POINTS_PER_PIP
#define BD_POINTS_PER_PIP 10
#endif

enum eUnitSystemMode
{
   unit_LEGACY_COMPAT = 0, // Giữ nguyên nghĩa point chuẩn của file .set cũ
   unit_PIP_UNIFIED   = 1  // Mọi input khoảng cách chung được hiểu là pip
};

struct SUnitProfile
{
   bool   isGold;
   int    digits;
   double point;
   double tickSize;
   double pipSize;
   double legacyPointSize;
};

// T17.27: EMPTY_VALUE/NaN/Inf are not usable prices or units.
bool Unit_FinitePure(const double v)
{ return v==v && v<1.7976931348623157e308 && v>-1.7976931348623157e308; }

bool Unit_PositivePure(const double v)
{ return Unit_FinitePure(v) && v>0.0; }

bool Unit_PriceOnTickPure(const double price,const double tick,const bool up,double &out)
{
   out=0.0;
   if(!Unit_FinitePure(price) || price<0.0 || !Unit_PositivePure(tick))return false;
   if(price==0.0)return true;
   double units=price/tick;
   if(!Unit_FinitePure(units) || units>9007199254740991.0)return false;
   out=(up?MathCeil(units-1e-9):MathFloor(units+1e-9))*tick;
   return Unit_PositivePure(out);
}

// Keep nearest for valid legacy sizes; only floor when a hard cap is crossed.
double Unit_CappedVolumePure(const double raw,const double cap,const double vMin,
                              const double vMax,const double step)
{
   if(!Unit_PositivePure(raw)||!Unit_PositivePure(cap)||!Unit_PositivePure(vMin)||
      !Unit_PositivePure(vMax)||!Unit_PositivePure(step)||vMax<vMin)return 0.0;
   double upper=MathMin(cap,vMax);
   if(upper<vMin)return 0.0;
   double units=raw/step;
   if(!Unit_FinitePure(units)||units>9007199254740991.0)return 0.0;
   double lot=MathFloor(units+0.5)*step;
   if(lot<vMin)lot=MathCeil(vMin/step-1e-9)*step;
   if(lot>upper)
   {
      double capped=MathFloor(upper/step+1e-9);
      lot=MathRound(capped*step*1e8)/1e8;
      if(lot>upper)lot=MathRound((capped-1.0)*step*1e8)/1e8;
   }
   lot=MathRound(lot*1e8)/1e8;
   if(!Unit_PositivePure(lot)||lot<vMin||lot>upper)return 0.0;
   return lot;
}

int Unit_LegacyPointScalePure(const bool isGold,const double point,const bool autoGoldPip)
{
   if(!autoGoldPip || !isGold)return 1;
   if(!Unit_PositivePure(point))return 0;
   double raw=0.01/point;
   if(!Unit_FinitePure(raw)||raw>2147483647.0)return 0;
   int scale=(int)MathRound(raw);
   return scale<1?1:scale;
}

double Unit_PipSizePure(const bool isGold, const double point, const int digits)
{
   if(point <= 0.0) return 0.0;
   if(isGold) return 0.10;
   return (digits == 3 || digits == 5) ? point * 10.0 : point;
}

double Unit_LegacyPointSizePure(const bool isGold, const double point,
                                const bool autoGoldPip)
{
   if(point <= 0.0) return 0.0;
   return point * (double)Unit_LegacyPointScalePure(isGold, point, autoGoldPip);
}

bool Unit_BuildProfilePure(const bool isGold,const double point,const int digits,
                           const double tickSize,const bool autoGoldPip,
                           SUnitProfile &out,string &why)
{
   why="";out.isGold=isGold;out.digits=digits;out.point=point;out.tickSize=tickSize;
   out.pipSize=0.0;out.legacyPointSize=0.0;
   if(!Unit_PositivePure(point)){why="invalid SYMBOL_POINT";return false;}
   if(!Unit_PositivePure(tickSize)){why="invalid SYMBOL_TRADE_TICK_SIZE";return false;}
   if(digits<0||digits>8){why="unsupported digits";return false;}
   if(Unit_LegacyPointScalePure(isGold,point,autoGoldPip)<=0){why="legacy scale overflow";return false;}
   out.pipSize=Unit_PipSizePure(isGold,point,digits);
   out.legacyPointSize=Unit_LegacyPointSizePure(isGold,point,autoGoldPip);
   if(!Unit_PositivePure(out.pipSize)||!Unit_PositivePure(out.legacyPointSize))
   {why="invalid derived unit profile";return false;}
   return true;
}

double Unit_ConfigDistancePricePure(const double value,
                                    const eUnitSystemMode mode,
                                    const double legacyPointSize,
                                    const double pipSize)
{
   return value * (mode == unit_PIP_UNIFIED ? pipSize : legacyPointSize);
}

double Unit_DcaDistancePricePure(const double pips,
                                 const eUnitSystemMode mode,
                                 const double legacyPointSize,
                                 const double pipSize)
{
   double unitPrice = mode == unit_PIP_UNIFIED
      ? pipSize : legacyPointSize * (double)BD_POINTS_PER_PIP;
   return pips * unitPrice;
}

double Unit_PipsToPricePure(const double pips, const double pipSize)
{
   return pips * pipSize;
}

long Unit_PriceToTicksPure(const double price,const double tickSize)
{
   if(!Unit_FinitePure(price)||!Unit_PositivePure(tickSize))return 0;
   double ticks=price/tickSize;
   if(!Unit_FinitePure(ticks)||MathAbs(ticks)>9007199254740991.0)return 0;
   return (long)MathRound(ticks);
}

ulong Unit_PriceToBrokerPointsCeilPure(const double price,const double point)
{
   if(!Unit_FinitePure(price)||price<=0.0||!Unit_PositivePure(point))return 0;
   double points=price/point;
   if(!Unit_FinitePure(points)||points>9007199254740991.0)return 0;
   return (ulong)MathCeil(points-1e-9);
}

double Unit_CostShiftPricePure(const double costMoney, const double totalLots,
                               const double tickValue, const double tickSize)
{
   if(totalLots <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0) return 0.0;
   return costMoney / (tickValue * totalLots) * tickSize;
}

string Unit_ModeName(const eUnitSystemMode mode)
{
   return mode == unit_PIP_UNIFIED ? "PIP_UNIFIED" : "LEGACY_COMPAT";
}

#endif // BD_UNIT_SYSTEM_MQH
