#ifndef BD_LEGACY_JOURNAL_T1727_MQH
#define BD_LEGACY_JOURNAL_T1727_MQH
// POD wire record for ordinary CLOSE/MODIFY. No MQL string is serialized as a struct.
struct SBDLegacyDiskT1727
{
   ushort symbol[128];
   ulong ticket,positionId,serverOrder,serverDeal,lastDeal;
   long nonce,owner,sentAt;
   uint requestId,retcode;
   int action,phase,cycle,command,policy,retries,countBefore;
   double volume,target,observed,before,sl,tp;
   bool serverFinal,orderDeleted,reconcileRequired;
};
bool LegacyDiskEncodeT1727(const PendingRequest &p,SBDLegacyDiskT1727 &r)
{
   ZeroMemory(r);
   if(StringLen(p.symbol)<1||StringLen(p.symbol)>=128||p.ticket==0||p.protectedPositionId==0||p.protectedNonce<=0)return false;
   if(p.commandType!=EXEC_CMD_LEGACY||(p.action!=INTENT_CLOSE_TICKET&&p.action!=INTENT_MODIFY_SLTP))return false;
   if(!Unit_FinitePure(p.volume)||p.volume<0||!Unit_FinitePure(p.targetVolume)||p.targetVolume<0||
      !Unit_FinitePure(p.observedVolume)||p.observedVolume<0||!Unit_PositivePure(p.positionVolumeBefore)||
      !Unit_FinitePure(p.sl)||p.sl<0||!Unit_FinitePure(p.tp)||p.tp<0)return false;
   if(StringToShortArray(p.symbol,r.symbol,0,WHOLE_ARRAY)!=StringLen(p.symbol)+1)return false;
   r.ticket=p.ticket;r.positionId=p.protectedPositionId;r.nonce=p.protectedNonce;
   r.serverOrder=p.serverOrder;r.serverDeal=p.serverDeal;r.lastDeal=p.lastObservedDeal;
   r.owner=p.ownerMagic;r.sentAt=(long)p.sentAt;r.requestId=p.requestId;r.retcode=p.requestRetcode;
   r.action=(int)p.action;r.phase=(int)p.phase;r.cycle=p.cycleKey;r.command=(int)p.commandType;r.policy=(int)p.reconcilePolicy;
   r.retries=p.retries;r.countBefore=p.positionCountBefore;r.volume=p.volume;r.target=p.targetVolume;
   r.observed=p.observedVolume;r.before=p.positionVolumeBefore;r.sl=p.sl;r.tp=p.tp;
   r.serverFinal=p.serverFinal;r.orderDeleted=p.orderDeleted;r.reconcileRequired=p.reconcileRequired;
   return true;
}
bool LegacyDiskDecodeT1727(const SBDLegacyDiskT1727 &r,PendingRequest &p)
{
   ZeroMemory(p);int n=0;while(n<128&&r.symbol[n]!=0)n++;
   if(n<1||n>=128||r.sentAt<0||r.retries<0||r.countBefore<0||r.policy!=(int)EXEC_RECONCILE_FAIL_CLOSED||
      r.phase<(int)PENDING_SENT||r.phase>(int)PENDING_REQUEST_ACCEPTED)return false;
   p.symbol=ShortArrayToString(r.symbol,0,n);p.ticket=r.ticket;p.protectedPositionId=r.positionId;p.protectedNonce=r.nonce;
   p.serverOrder=r.serverOrder;p.serverDeal=r.serverDeal;p.lastObservedDeal=r.lastDeal;p.ownerMagic=r.owner;
   p.sentAt=(datetime)r.sentAt;p.requestId=r.requestId;p.requestRetcode=r.retcode;p.action=(eIntent)r.action;
   p.phase=(ePendingPhase)r.phase;p.cycleKey=r.cycle;p.commandType=(eExecCommandType)r.command;
   p.reconcilePolicy=(eExecReconcilePolicy)r.policy;p.retries=r.retries;p.positionCountBefore=r.countBefore;
   p.volume=r.volume;p.targetVolume=r.target;p.observedVolume=r.observed;p.positionVolumeBefore=r.before;
   p.sl=r.sl;p.tp=r.tp;p.serverFinal=r.serverFinal;p.orderDeleted=r.orderDeleted;
   p.reconcileRequired=r.reconcileRequired;p.active=true;
   SBDLegacyDiskT1727 check;return LegacyDiskEncodeT1727(p,check);
}
bool LegacyDiskEqualT1727(const SBDLegacyDiskT1727 &a,const SBDLegacyDiskT1727 &b)
{
   for(int i=0;i<128;i++)if(a.symbol[i]!=b.symbol[i])return false;
   return a.ticket==b.ticket &&
      a.positionId==b.positionId &&
      a.serverOrder==b.serverOrder &&
      a.serverDeal==b.serverDeal &&
      a.lastDeal==b.lastDeal &&
      a.nonce==b.nonce &&
      a.owner==b.owner &&
      a.sentAt==b.sentAt &&
      a.requestId==b.requestId &&
      a.retcode==b.retcode &&
      a.action==b.action &&
      a.phase==b.phase &&
      a.cycle==b.cycle &&
      a.command==b.command &&
      a.policy==b.policy &&
      a.retries==b.retries &&
      a.countBefore==b.countBefore &&
      a.volume==b.volume &&
      a.target==b.target &&
      a.observed==b.observed &&
      a.before==b.before &&
      a.sl==b.sl &&
      a.tp==b.tp &&
      a.serverFinal==b.serverFinal &&
      a.orderDeleted==b.orderDeleted &&
      a.reconcileRequired==b.reconcileRequired;
}
#endif
