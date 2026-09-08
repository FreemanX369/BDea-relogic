// T17.27: active-window horizon; bounded refresh; sorted interval union.
#ifndef BD_NEWSCALENDAR_MQH
#define BD_NEWSCALENDAR_MQH
#include "Config.mqh"
#include "Logger.mqh"
struct SNewsWindow { datetime from; datetime to; };
class CNewsCalendar
{
private:
   SNewsWindow m_windows[];
   datetime m_lastRefresh;
   bool m_hasData,m_configValid;
   string m_currencies[2];
   bool AddWindow(const datetime time,const int beforeMin,const int afterMin)
   {
      if(beforeMin<0||afterMin<0||time<0)return false;
      int n=ArraySize(m_windows);if(ArrayResize(m_windows,n+1,128)!=n+1)return false;
      m_windows[n].from=(datetime)(time-(long)beforeMin*60);
      m_windows[n].to=(datetime)(time+(long)afterMin*60);
      return m_windows[n].from<=m_windows[n].to;
   }
   bool MergeWindows()
   {
      int n=ArraySize(m_windows);if(n<2)return true;
      SNewsWindow tmp[];if(ArrayResize(tmp,n)!=n)return false;
      for(int width=1;width<n;)
      {
         for(int left=0;left<n;left+=2*width)
         {
            int mid=(int)MathMin(left+width,n),end=(int)MathMin(left+2*width,n),i=left,j=mid;
            for(int k=left;k<end;k++)
            {
               bool take=i<mid&&(j>=end||m_windows[i].from<=m_windows[j].from);
               tmp[k]=m_windows[take?i++:j++];
            }
         }
         for(int i=0;i<n;i++)m_windows[i]=tmp[i];
         if(width>n/2)break;width*=2;
      }
      int out=0;
      for(int i=1;i<n;i++)
      {
         if(m_windows[i].from<=m_windows[out].to)
            m_windows[out].to=(datetime)MathMax(m_windows[out].to,m_windows[i].to);
         else m_windows[++out]=m_windows[i];
      }
      return ArrayResize(m_windows,out+1)==out+1;
   }
public:
   CNewsCalendar():m_lastRefresh(0),m_hasData(false),m_configValid(true){}
   void Init()
   {
      m_lastRefresh=0;m_hasData=false;ArrayResize(m_windows,0);
      m_configValid=(!Imp3High||(b3_>=0&&a3_>=0)) &&
                    (!Imp2Med||(b2_>=0&&a2_>=0)) && (!Imp1Low||(b1_>=0&&a1_>=0));
      m_currencies[0]=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE);
      m_currencies[1]=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT);
   }
   // Only OnTimer refreshes broker calendar; OnTick performs binary lookup.
   void Refresh()
   {
      if(!Flag_Use_News)return;
      datetime now=TimeCurrent();
      if(m_lastRefresh!=0&&now>=m_lastRefresh&&now-m_lastRefresh<BD_NEWS_REFRESH_SEC)return;
      m_lastRefresh=now;m_hasData=false;ArrayResize(m_windows,0);
      if(!m_configValid)return;
      long before=0,after=0;
      if(Imp3High){before=(long)MathMax(before,b3_);after=(long)MathMax(after,a3_);}
      if(Imp2Med){before=(long)MathMax(before,b2_);after=(long)MathMax(after,a2_);}
      if(Imp1Low){before=(long)MathMax(before,b1_);after=(long)MathMax(after,a1_);}
      long back=(long)MathMax(2*3600,after*60+BD_NEWS_REFRESH_SEC);
      long ahead=(long)MathMax(48*3600,before*60+BD_NEWS_REFRESH_SEC);
      if(now<0 || ahead>32535215999 || now>32535215999-ahead)
      {m_configValid=false;return;}
      datetime from=(datetime)(now>back?now-back:0),to=(datetime)(now+ahead);
      MqlCalendarValue values[];bool complete=true;
      for(int c=0;c<2;c++)
      {
         if(c==1&&m_currencies[1]==m_currencies[0])break;
         int total=CalendarValueHistory(values,from,to,NULL,m_currencies[c]);
         if(total<0){complete=false;continue;}
         if(total==0)continue;
         m_hasData=true;
         for(int i=0;i<total;i++)
         {
            MqlCalendarEvent ev;
            if(!CalendarEventById(values[i].event_id,ev)){complete=false;continue;}
            if(ev.importance==CALENDAR_IMPORTANCE_HIGH&&Imp3High)complete=AddWindow(values[i].time,b3_,a3_)&&complete;
            if(ev.importance==CALENDAR_IMPORTANCE_MODERATE&&Imp2Med)complete=AddWindow(values[i].time,b2_,a2_)&&complete;
            if(ev.importance==CALENDAR_IMPORTANCE_LOW&&Imp1Low)complete=AddWindow(values[i].time,b1_,a1_)&&complete;
         }
      }
      if(!MergeWindows())complete=false;
      m_hasData=m_hasData&&complete;
      Log_Info("News","T17.27 calendar union refreshed: "+(string)ArraySize(m_windows)+" windows");
   }
   bool AllowsNewOrders(const datetime now)
   {
      if(!Flag_Use_News)return true;
      if(!m_configValid)return false;
      if(!m_hasData||m_lastRefresh==0||now<m_lastRefresh||now-m_lastRefresh>=BD_NEWS_REFRESH_SEC)
         return NewsFailMode==news_fail_TradeOn;
      int lo=0,hi=ArraySize(m_windows);
      while(lo<hi)
      {int mid=lo+(hi-lo)/2;if(m_windows[mid].from<=now)lo=mid+1;else hi=mid;}
      return lo==0||now>m_windows[lo-1].to;
   }
};
#endif
