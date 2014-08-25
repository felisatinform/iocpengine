// The contents of this file are used with permission, subject to
// the Mozilla Public License Version 1.1 (the "License"); you may
// not use this file except in compliance with the License. You may
// obtain a copy of the License at
// http://www.mozilla.org/MPL/MPL-1.1.html
//
// Software distributed under the License is distributed on an
// "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
// implied. See the License for the specific language governing
// rights and limitations under the License.
unit DnTimedCache;
interface
uses
  Classes,
  SysUtils,
  DnRtl,
  DnTimerEngine,
  DnAbstractLogger,
  DnAbstractExecutor,
  DnTcpChannel,
  DnSimpleExecutor,
  DnCallbackLogger;

type
  IDnCachedObject = interface
    ['{3CC8578E-0DA3-4100-AB20-21C594DF8EB3}']
    function ExpireDate: TDateTime;
    function CustomData: Pointer;
  end;

  IDnCachedObjectStrHash = interface(IDnCachedObject)
    ['{E0FB7309-FE1C-48d2-9454-70070316D6DA}']
    function GetStrHash: String;
  end;

  IDnCacheTimeOutHandler = interface
    ['{F7502C4B-1ECA-437a-B50E-2B0DE1C8F27C}']
    procedure ItemExpired(Obj: IDnCachedObject);
  end;

  TDnCacheStrHash = class (TDnObject)
  protected
    FTimer:     TDnTimerEngine;
    FList:      TStringList;
    FGuard:     TDnMutex;
    FExecutor:  TDnSimpleExecutor;
    FLogger:    TDnAbstractLogger;
    FHandler:   IDnCacheTimeOutHandler;

    procedure TimerExpired(Context: TDnThreadContext; Channel: TDnTcpChannel;
                            ExpiredTacts: Cardinal; Key: Pointer);
    procedure Lock;
    procedure Unlock;
  public
    constructor Create(Logger: TDnAbstractLogger; Handler: IDnCacheTimeOutHandler);
    destructor  Destroy; override;
    function    Find(Hash: String): IDnCachedObjectStrHash;    procedure   Append(Obj: IDnCachedObjectStrHash);
    procedure   Delete(Obj: IDnCachedObjectStrHash);
    property    Logger: TDnAbstractLogger read FLogger write FLogger;
  end;

implementation

procedure TDnCacheStrHash.Lock;
begin
  FGuard.Acquire;
end;

procedure TDnCacheStrHash.Unlock;
begin
  FGuard.Release;
end;

constructor TDnCacheStrHash.Create(Logger: TDnAbstractLogger; Handler: IDnCacheTimeOutHandler);
begin
  inherited Create;
  FTimer := TDnTimerEngine.Create;
  FList := TStringList.Create;
  FExecutor := TDnSimpleExecutor.Create(Nil);
  FGuard := TDnMutex.Create;
  FLogger := Logger;
  FExecutor.Active := True;

  FTimer.Active := True;
  FHandler := Handler;
end;

destructor TDnCacheStrHash.Destroy;
begin
  FreeAndNil(FTimer);
  FreeAndNil(FList);
  FreeAndNil(FExecutor);
  FreeAndNil(FGuard);
  inherited Destroy;
end;

procedure TDnCacheStrHash.TimerExpired(Context: TDnThreadContext; Channel: TDnTcpChannel;
                            ExpiredTacts: Cardinal; Key: Pointer);
var
    Obj: IDnCachedObjectStrHash;
begin
  Obj := IDnCachedObjectStrHash(Key);
  Self.Delete(Obj);
  FHandler.ItemExpired(Obj);
end;

function  TDnCacheStrHash.Find(Hash: String): IDnCachedObjectStrHash;
var Index: Integer;
begin
  try
    Lock;
    if FList.Find(Hash, Index) then
      Result := IDnCachedObjectStrHash(Pointer(FList.Objects[Index]))
    else
      Result := Nil;
  finally
    Unlock;
  end;
end;

procedure TDnCacheStrHash.Append(Obj: IDnCachedObjectStrHash);
var Remaining: TDateTime;
begin
  try
    Lock;
    Remaining := Obj.ExpireDate - Now;
    if  Remaining > 0 then
    begin //request timer event
      Obj._AddRef;
      FList.AddObject(Obj.GetStrHash(), Pointer(Obj));
      FTimer.RequestTimerNotify(Nil, Trunc(Remaining * 86400 + 0.5), Pointer(Obj));
    end else
    begin
      if Obj.ExpireDate = 0 then
      begin
        Obj._AddRef;
        FList.AddObject(Obj.GetStrHash(), Pointer(Obj));
      end;
    end;
  finally
    UnLock;
  end;
end;

procedure TDnCacheStrHash.Delete(Obj: IDnCachedObjectStrHash);
var Index: Integer;
begin
  try
    Lock;
    if FList.Find(Obj.GetStrHash(), Index) then
    begin
      Obj._Release;
      FList.Delete(Index);
    end;
  finally
    Unlock;
  end;
end;


end.
