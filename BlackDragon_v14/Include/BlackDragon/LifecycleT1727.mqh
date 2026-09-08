#ifndef BD_LIFECYCLE_T1727_MQH
#define BD_LIFECYCLE_T1727_MQH
#include "Diagnostics/AtomicSnapshot.mqh"

// T17.27: persist Core OPEN identity before transport. Unknown never means no effect.
struct SBDCoreIntentT1727
{
   long nonce,sentAt,intentBar;
   ulong serverOrder,serverDeal;
   uint requestId,retcode;
   int dir,dcaIndex;
   double volume,observedVolume;
   bool active,serverFinal;
};
bool CoreIntentValidT1727(const SBDCoreIntentT1727 &r,const int dir)
{
   return r.dir==dir && r.nonce>=0 && r.sentAt>=0 && r.intentBar>=0 && r.dcaIndex>=0 &&
      Unit_FinitePure(r.volume) && r.volume>=0 && Unit_FinitePure(r.observedVolume) &&
      r.observedVolume>=0 && (!r.active || (r.nonce>0 && r.volume>0));
}
class CCoreIntentStoreT1727
{
private:
   SBDCoreIntentT1727 m_r[2];
   string m_file;
   bool m_ok,m_persist;
   long m_sequence,m_nonce;
   bool Save()
   {
      if(!m_ok)return false;
      if(m_sequence<0||m_sequence>=9223372036854775806){m_ok=false;return false;}
      if(!m_persist)return true;
      SBDAtomicHeader h;BD_AtomicIdentity(h,17270001,1,1);
      h.records=2;h.sequence=m_sequence+1;
      int f=BD_AtomicBegin(m_file,h);if(f==INVALID_HANDLE){m_ok=false;return false;}
      bool ok=FileWriteLong(f,m_nonce)==sizeof(long);
      for(int d=0;d<2;d++)ok=CoreIntentValidT1727(m_r[d],d) && FileWriteStruct(f,m_r[d])==sizeof(SBDCoreIntentT1727) && ok;
      ok=BD_AtomicCommit(m_file,f,h,ok);
      if(ok)m_sequence=h.sequence;else m_ok=false;
      return ok;
   }
public:
   CCoreIntentStoreT1727():m_file(""),m_ok(true),m_persist(false),m_sequence(0),m_nonce(0)
   {for(int d=0;d<2;d++){ZeroMemory(m_r[d]);m_r[d].dir=d;}}
   bool Healthy()const{return m_ok;}
   bool Pending(const int dir)const{return dir>=0&&dir<2&&m_r[dir].active;}
   bool At(const int dir,SBDCoreIntentT1727 &r)const
   {if(dir<0||dir>1)return false;r=m_r[dir];return true;}
   bool Init(const bool persist)
   {
      m_persist=persist;m_ok=true;m_sequence=0;m_nonce=0;
      for(int d=0;d<2;d++){ZeroMemory(m_r[d]);m_r[d].dir=d;}
      m_file="BD_T1727_CORE_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+
             (string)BD_HashText(_Symbol)+"_"+(string)Magic+".bin";
      if(!persist || !FileIsExist(m_file))return true;
      SBDAtomicHeader h,want;BD_AtomicIdentity(want,17270001,1,1);
      int f=BD_AtomicOpen(m_file,want,h);if(f==INVALID_HANDLE){m_ok=false;return false;}
      bool ok=h.records==2 && h.payload==(long)sizeof(long)+2*(long)sizeof(SBDCoreIntentT1727);
      if(ok)m_nonce=FileReadLong(f);
      for(int d=0;ok&&d<2;d++)ok=FileReadStruct(f,m_r[d])==sizeof(SBDCoreIntentT1727) &&
         CoreIntentValidT1727(m_r[d],d) && m_r[d].nonce<=m_nonce;
      FileClose(f);m_sequence=h.sequence;m_ok=ok&&m_nonce>=0;return m_ok;
   }
   bool Prepare(const int dir,const double volume,const int index,const datetime bar,long &nonce)
   {
      nonce=0;if(!m_ok||dir<0||dir>1||Pending(dir)||m_nonce>=9223372036854775806)return false;
      SBDCoreIntentT1727 r;ZeroMemory(r);r.dir=dir;r.nonce=++m_nonce;
      r.sentAt=(long)TimeCurrent();r.intentBar=(long)bar;r.dcaIndex=index;r.volume=volume;r.active=true;
      if(!CoreIntentValidT1727(r,dir)){m_ok=false;return false;}
      m_r[dir]=r;if(!Save())return false;nonce=r.nonce;return true;
   }
   bool Update(const SBDCoreIntentT1727 &r)
   {
      int d=r.dir;if(!m_ok||d<0||d>1||!CoreIntentValidT1727(r,d)||
         !m_r[d].active||r.nonce!=m_r[d].nonce||r.volume!=m_r[d].volume||r.sentAt!=m_r[d].sentAt)return false;
      if(r.intentBar!=m_r[d].intentBar||r.dcaIndex!=m_r[d].dcaIndex)return false;
      if(r.requestId==m_r[d].requestId&&r.retcode==m_r[d].retcode&&r.serverOrder==m_r[d].serverOrder&&
         r.serverDeal==m_r[d].serverDeal&&r.observedVolume==m_r[d].observedVolume&&
         r.serverFinal==m_r[d].serverFinal&&r.active==m_r[d].active)return true;
      m_r[d]=r;return Save();
   }
   bool Finish(const int dir,const long nonce)
   {
      if(!m_ok||dir<0||dir>1||nonce<=0||m_r[dir].nonce!=nonce)return false;
      if(!m_r[dir].active)return true;
      m_r[dir].active=false;if(Save())return true;m_r[dir].active=true;return false;
   }
};

// Deferred virtual exits are durable intent, not a second trading executor.
class CDeferredExitStoreT1727
{
private:
   int m_kind[2];
   int m_guard;
   string m_file;
   bool m_ok,m_persist;
   long m_sequence;
   bool Save()
   {
      if(!m_ok)return false;if(m_sequence<0||m_sequence>=9223372036854775806){m_ok=false;return false;}if(!m_persist)return true;
      SBDAtomicHeader h;BD_AtomicIdentity(h,17270002,2,BD_UNIT_POLICY_REV);
      h.records=3;h.sequence=m_sequence+1;
      int f=BD_AtomicBegin(m_file,h);if(f==INVALID_HANDLE){m_ok=false;return false;}
      bool ok=FileWriteInteger(f,m_kind[0],INT_VALUE)==sizeof(int) && FileWriteInteger(f,m_kind[1],INT_VALUE)==sizeof(int) && FileWriteInteger(f,m_guard,INT_VALUE)==sizeof(int);
      ok=BD_AtomicCommit(m_file,f,h,ok);if(ok)m_sequence=h.sequence;else m_ok=false;return ok;
   }
public:
   CDeferredExitStoreT1727():m_file(""),m_ok(true),m_persist(false),m_sequence(0)
   {m_kind[0]=EXIT_NONE;m_kind[1]=EXIT_NONE;m_guard=0;}
   bool Healthy()const{return m_ok;}
   int Kind(const int d)const{return d>=0&&d<2?m_kind[d]:EXIT_NONE;}
   bool Init(const bool persist)
   {
      m_ok=true;m_persist=persist;m_sequence=0;m_kind[0]=EXIT_NONE;m_kind[1]=EXIT_NONE;m_guard=0;
      m_file="BD_T1727_EXIT_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+
             (string)BD_HashText(_Symbol)+"_"+(string)Magic+".bin";
      if(!persist||!FileIsExist(m_file))return true;
      SBDAtomicHeader h,want;BD_AtomicIdentity(want,17270002,2,BD_UNIT_POLICY_REV);
      int f=BD_AtomicOpen(m_file,want,h);if(f==INVALID_HANDLE){m_ok=false;return false;}
      bool ok=h.records==3 && h.payload==3*(long)sizeof(int);
      if(ok)for(int d=0;d<2;d++){m_kind[d]=FileReadInteger(f,INT_VALUE);ok=ok&&(m_kind[d]==EXIT_NONE||m_kind[d]==EXIT_TP||m_kind[d]==EXIT_SL||m_kind[d]==EXIT_TRAIL);}
      if(ok){m_guard=FileReadInteger(f,INT_VALUE);ok=m_guard>=0&&m_guard<=5;}
      FileClose(f);m_sequence=h.sequence;m_ok=ok;return ok;
   }
   int Guard()const{return m_guard;}
   bool SetGuard(const int action)
   {if(!m_ok||action<0||action>5)return false;if(m_guard==action)return true;m_guard=action;return Save();}
   bool Set(const int d,const int kind)
   {
      if(!m_ok||d<0||d>1||!(kind==EXIT_NONE||kind==EXIT_TP||kind==EXIT_SL||kind==EXIT_TRAIL))return false;
      if(m_kind[d]==kind)return true;m_kind[d]=kind;return Save();
   }
};
#endif
