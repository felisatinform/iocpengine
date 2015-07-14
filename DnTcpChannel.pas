{$I DnConfig.inc}
unit DnTcpChannel;
interface
uses Winsock2, contnrs, Windows, Classes, SysUtils,
      DnRtl, DnTcpRequest, DnConst, DnAbstractExecutor, DnDataDecorator,
      DnDataQueue;

type

  //TDnRefType = (rtClientList, rtChannelList, rtReadIO, rtWriteIO, rtCloseIO, rtTimerEngine);
  TDnTcpChannel = class (TDnObject)
  protected
    // Easy-to-read remote peer address
    FRemoteIP:            AnsiString;
    FRemotePort:          Word;
    
    FRemoteAddr:          TSockAddrIn;
    FSocket:              TSocket;
    FReactor:             TObject;

    FReadQueue:           TObjectList;
    FWriteQueue:          TObjectList;
    FClosingRequest:      TDnTcpRequest;
    FConnectingRequest:   TDnTcpRequest;
    FRunGuard:            TDnMutex;

    FTracker:             Pointer;
    FCache:               RawByteString;
    FCustomData:          TObject;
    FFinishedIOCount:     Cardinal;

    //the specified timeout for this channel
    FTimeOut:             Cardinal;
    //FTimeOutObserver:     IDnTimerObserver;
    FTimeOutGuard:        TDnMutex;
    FClosing:             Boolean;
    FTimeOutExpired:      Boolean;
    FTimeOutAbort:        Boolean;
    FFirstTimeOutRequest: Boolean;
    FClient:              Boolean;
    FState:               Integer;
    FOwnsCustomData:      Boolean;
    FRefCount:            Integer;
    FTimeoutTact:         Cardinal;
    FLastIOTime:          Double;
    FDeletePosted:        Boolean;
    FOutgoingQueue:       TDnDataQueue;        


    procedure   SetTimeOut(Value: Cardinal);
    procedure   IssueTimeOutRequest(TimeOut: Cardinal; Request: TDnTcpRequest);
    procedure   InitChannel; virtual;
    function    GetRemoteAddrPtr: Pointer;
    procedure   IncrementIOCounter;
    function    GetIsFinished: Boolean;

  public
    constructor Create(Reactor: TObject; Sock: TSocket; RemoteAddr: TSockAddrIn);
    constructor CreateEmpty(Reactor: TObject; const RemoteIP: AnsiString; Port: Word); overload;
    constructor CreateEmpty(Reactor: TObject); overload;
    constructor CreateEmpty; overload;
    
    destructor  Destroy; override;

    procedure   CloseSocketHandle;
    procedure   StopTimeOutTracking;

    function    Add2Cache(Block: PAnsiChar; BlockSize: Cardinal): Cardinal;
    function    ExtractFromCache(Block: PAnsiChar; BlockSize: Cardinal): Cardinal;
    procedure   InsertToCache(Block: PAnsiChar; BlockSize: Cardinal);
    function    CacheHasData: Boolean;
    function    IsClosed: Boolean;
    procedure   ExecuteNext(Request: TDnTcpRequest);
    procedure   DeleteRequest(Request: TDnTcpRequest);
    procedure   HandleTimeoutMsg(Executor: TDnAbstractExecutor);
    procedure   DeleteNonActiveRequests;
    procedure   Lock;
    procedure   Unlock;

    class function    MatchingRequest(Context: Pointer): TDnTcpRequest;

    // IDnChannel interface implementation
    function  RemotePort: Word;
    function  RemoteAddr: AnsiString;
    function  RemoteHost: String;
    procedure SetCustomData(P: TObject);
    function  GetCustomData: TObject;
    procedure SetOwnsCustomData(Value: Boolean);
    function  GetOwnsCustomData: Boolean;
    function  IsClosing: Boolean;

    procedure InitClient(const RemoteIP: AnsiString; RemotePort: Word);

    // IDnIOTrackerHolder implementation
    function  IsBound: Boolean;
    procedure Bind(Tracker: Pointer);
    procedure Unbind(Tracker: Pointer);
    function  Tracker: Pointer;
    function  IsClient: Boolean;

    procedure RunRequest(Request: TDnTcpRequest);
    procedure SetNagle(Value: Boolean);

    procedure AddRef(_Type: TDnIORequestType; const Comment: String = '');
    procedure Release(_Type: TDnIORequestType; const Comment: String = '');
    procedure EnsureSending;

    property SocketHandle:      TSocket       read FSocket              write FSocket;
    property Reactor:           TObject       read FReactor             write FReactor;
    property TimeOut:           Cardinal      read FTimeOut             write SetTimeOut;
    property RemoteAddrPtr:     Pointer       read GetRemoteAddrPtr;
    property TimeOutExpired:    Boolean       read FTimeOutExpired;
    property Client:            Boolean       read FClient;
    property State:             Integer       read FState               write FState;
    property TimeoutTact:       Cardinal      read FTimeoutTact         write FTimeoutTact;
    property LastIOTime:        Double        read FLastIOTime          write FLastIOTime;
    property CustomData:        TObject       read GetCustomData        write SetCustomData;
    property OwnsCustomData:    Boolean       read FOwnsCustomData      write FOwnsCustomData;
    property IsFinished:        Boolean       read GetIsFinished;
    property Outgoing:          TDnDataQueue  read FOutgoingQueue;
  end;

var
  GChannelList: TObjectList;
  GChannelListGuard: TDnMutex;

procedure ClearChannelList(Lst: TObjectList);

implementation
uses
  DnTcpReactor;
  
type
  TDnTcpTimeoutRequest = class(TDnTcpRequest)
  public
    constructor Create(Channel: TDnTcpChannel);
    destructor Destroy; override;

    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;
    procedure CallHandler(Context: TDnThreadContext); override;
    procedure SetTransferred(Transferred: Cardinal); override;
    function  IsPureSignal: Boolean; override;
  end;


constructor TDnTcpTimeoutRequest.Create(Channel: TDnTcpChannel);
begin
  inherited Create(Channel, Nil);
end;

destructor TDnTcpTimeoutRequest.Destroy;
begin
  inherited Destroy;
end;

function  TDnTcpTimeoutRequest.IsPureSignal: Boolean;
begin
  Result := True;
end;

procedure TDnTcpTImeoutRequest.ReExecute;
begin
end;

function  TDnTcpTimeoutRequest.RequestType: TDnIORequestType;
begin
  Result := rtTimeoutEvent;
end;

type
  THackReactor = class (TDnTcpReactor)
  end;

procedure TDnTcpTimeoutRequest.CallHandler(Context: TDnThreadContext);
begin
  THackReactor((FChannel as TDnTcpChannel).FReactor).DoTimeoutError(Context, FChannel as TDnTcpChannel);
end;

procedure TDnTcpTimeoutRequest.SetTransferred(Transferred: Cardinal);
begin
end;

procedure AddChannel(C: TDnTcpChannel); forward;
procedure RemoveChannel(C: TDnTcpChannel); forward;

//-------------- TDnTcpChannel ------------

procedure TDnTcpChannel.InitChannel;
begin
  if not Assigned(FRunGuard) then
    FRunGuard := TDnMutex.Create;
  if not Assigned(FOutgoingQueue) then
    FOutgoingQueue := TDnDataQueue.Create();
  FTracker := Nil;

  if not Assigned(FReadQueue) then
    FReadQueue := TObjectList.Create(False);
  if not Assigned(FWriteQueue) then
    FWriteQueue := TObjectList.Create(False);
  FClosingRequest := Nil;
  FConnectingRequest := Nil;
  FCustomData := Nil;
  SetLength(FCache, 0);
  FTimeOut := 0;
  if not Assigned(FTimeOutGuard) then
    FTimeOutGuard := TDnMutex.Create;
  FClosing := False;
  FFinishedIOCount := 0;
  FTimeOutExpired := False;
  FTimeOutAbort := False;
  FFirstTimeOutRequest := False;

  if GChannelList.Count = 0 then
    AddChannel(Self);
end;

constructor TDnTcpChannel.Create(Reactor: TObject; Sock: TSocket; RemoteAddr: TSockAddrIn);
begin
  inherited Create;

  FRunGuard := TDnMutex.Create;
  FReactor := Reactor;
  FSocket := Sock;
  FRemoteAddr := RemoteAddr;

  InitChannel;
end;

//{$O-}
constructor TDnTcpChannel.CreateEmpty(Reactor: TObject; const RemoteIP: AnsiString;
                                      Port: Word(*; const IPInterface: String*) );
begin
  inherited Create;
  FRunGuard := TDnMutex.Create;
  FReactor := Reactor;
  FSocket := Winsock2.WSASocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, Nil, 0, WSA_FLAG_OVERLAPPED);
  if FSocket = INVALID_SOCKET then
    raise EDnWindowsException.Create(WSAGetLastError());

  InitClient(RemoteIP, Port);
end;

constructor TDnTcpChannel.CreateEmpty(Reactor: TObject);
begin
  inherited Create;
  FRunGuard := TDnMutex.Create;
  FReactor := Reactor;

  InitChannel;
end;

constructor TDnTcpChannel.CreateEmpty;
begin
  inherited Create;
  FSocket := Winsock2.INVALID_SOCKET;

  InitChannel;
end;

procedure TDnTcpChannel.InitClient(const RemoteIP: AnsiString; RemotePort: Word);
begin
  FRemoteIP := RemoteIP;
  FRemotePort := RemotePort;
  
  FillChar(FRemoteAddr, 0, SizeOf(FRemoteAddr));
  FRemoteAddr.sin_addr.S_addr := Winsock2.inet_addr(PAnsiChar(RemoteIP));
  FRemoteAddr.sin_port := htons(RemotePort);
  FRemoteAddr.sin_family := AF_INET;
  FClient := True;
  FSocket := Winsock2.WSASocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, Nil, 0, WSA_FLAG_OVERLAPPED);

  InitChannel;
end;

//{$O+}

function TDnTcpChannel.GetRemoteAddrPtr: Pointer;
begin
  Result := @FRemoteAddr;
end;

procedure TDnTcpChannel.IncrementIOCounter;
begin
  FTimeOutGuard.Acquire;
  Inc(FFinishedIOCount);
  FTimeOutGuard.Release;
end;

procedure TDnTcpChannel.IssueTimeOutRequest(TimeOut: Cardinal; Request: TDnTcpRequest);
begin
(*  FTimeOutGuard.Acquire;
  FTimeOutObserver := Nil;
  FTimeOutObserver := FReactor.FTimer.RequestTimerNotify(Self, TimeOut, Pointer(FFinishedIOCount));
  FTimeOutGuard.Release; *)
end;


procedure TDnTcpChannel.SetCustomData(P: TObject);
begin
  FCustomData := P;
end;

function TDnTcpChannel.GetCustomData: TObject;
begin
  Result := FCustomData;
end;

procedure TDnTcpChannel.SetOwnsCustomData(Value: Boolean);
begin
  FOwnsCustomData := Value;
end;

function TDnTcpChannel.GetOwnsCustomData: Boolean;
begin
  Result := FOwnsCustomData;
end;

procedure TDnTcpChannel.SetTimeOut(Value: Cardinal);
begin
  if FTimeOut = 0 then
    FTimeOut := Value
  else
    raise EDnException.Create(ErrCannotSetTimeOutTwice, 0);
end;


function TDnTcpChannel.Add2Cache(Block: PAnsiChar; BlockSize: Cardinal): Cardinal;
var CacheLen: Cardinal;
begin
  if BlockSize <> 0 then
  begin
    CacheLen := Length(FCache);
    SetLength(FCache, CacheLen + BlockSize);
    Move(Block^, FCache[CacheLen+1], BlockSize);
    Result := Length(FCache);
  end else
    Result := 0;
end;

procedure TDnTcpChannel.InsertToCache(Block: PAnsiChar; BlockSize: Cardinal);
var CacheLen : Cardinal;
begin
  if (Block<>Nil) and (BlockSize <> 0) then
  begin
    CacheLen := Length(FCache);
    SetLength(FCache, CacheLen + BlockSize);
    if CacheLen <> 0 then
      Move(FCache[1], FCache[1+BlockSize], CacheLen);
    Move(Block^, FCache[1], BlockSize);
  end;
end;


function TDnTcpChannel.ExtractFromCache(Block: PAnsiChar; BlockSize: Cardinal): Cardinal;
var CacheLen: Cardinal;
begin
  CacheLen := Length(FCache);
  if CacheLen < BlockSize then
  begin
    if CacheLen > 0 Then
    begin
      Move(FCache[1], Block^, CacheLen);
      SetLength(FCache, 0);
    end;
    Result := CacheLen;
  end else
  begin
    Move(FCache[1], Block^, BlockSize);
    Delete(FCache, 1, BlockSize);
    Result := BlockSize;
  end;
end;

function TDnTcpChannel.CacheHasData: Boolean;
begin
  Result := Length(FCache) <> 0;
end;

//Stop/cancel the timeout tracking activity. It should be called only 1 time.
//There isn't a back way - you can't start timeout tracking again.
procedure TDnTcpChannel.StopTimeOutTracking;
begin
(*  if FTimeOutObserver <> Nil then
  begin
    FTimeOutAbort := True;
    FTimeOutObserver.Cancel;
    FTimeOutObserver := Nil;
  end; *)
end;

function TDnTcpChannel.IsClosing: Boolean;
begin
  Result := FClosingRequest <> Nil;
end;

procedure TDnTcpChannel.RunRequest(Request: TDnTcpRequest);
var RT: TDnIORequestType;
begin
  FRunGuard.Acquire;
  try
    if IsClosed or IsClosing then
    begin
      Request.Free;
      Exit;
    end;

    RT := Request.RequestType();

      case RT of
        rtClose:    begin
                      if FClosingRequest <> Nil then
                      begin
                        Request.Free;
                        Exit;
                      end;
                      
                      FClosingRequest := Request;
                      if (FReadQueue.Count = 0) and (FWriteQueue.Count = 0) and
                          (FConnectingRequest = Nil) then
                      begin
                        Request.Execute;
                        FClosing := True;
                        DeleteNonActiveRequests;
                      end;

                    end;
        rtBrutalClose:
                    begin
                      if FClosingRequest = Nil then
                      begin
                        FClosingRequest := Request;
                        Request.Execute;
                        FClosing := True;
                      end
                      else
                      begin
                        Request.Free;
                        Exit;
                      end;
                    end;

        rtConnect:  begin
                      FConnectingRequest := Request;
                      Request.Execute;
                    end;

        rtRead:     if (FReadQueue.Add(Request) = 0) and (FConnectingRequest = Nil) then
                      Request.Execute;

        rtWrite:    if (FWriteQueue.Add(Request) = 0) and (FConnectingRequest = Nil) then
                      Request.Execute;
      end;

    finally
      FRunGuard.Release;
    end;
end;

procedure TDnTcpChannel.Bind(Tracker: Pointer);
begin
  FTracker := Tracker;
end;

procedure TDnTcpChannel.Unbind;
begin
  FTracker := Nil;
end;

function TDnTcpChannel.Tracker: Pointer;
begin
  Result := FTracker;
end;

function  TDnTcpChannel.IsClient: Boolean;
begin
  Result := Self.Client;
end;

function  TDnTcpChannel.IsBound: Boolean;
begin
  Result := FTracker <> Nil;
end;

function TDnTcpChannel.RemotePort: Word;
begin
  Result := ntohs(FRemoteAddr.sin_port);
end;

function TDnTcpChannel.RemoteAddr: AnsiString;
begin
  Result := StrPas(inet_ntoa(FRemoteAddr.sin_addr));
end;

function TDnTcpChannel.RemoteHost: String;
begin
  Result := StrPas(gethostbyaddr(@FRemoteAddr.sin_addr, SizeOf(FRemoteAddr),AF_INET)^.h_name);
end;

procedure TDnTcpChannel.CloseSocketHandle;
begin
  //stop timeouts
  FRunGuard.Acquire;
  try
    if FSocket <> INVALID_SOCKET then
    begin
      Winsock2.shutdown(FSocket, SD_SEND);
      Winsock2.closesocket(FSocket);
      FSocket := INVALID_SOCKET;
    end;
  finally
    FRunGuard.Release;
  end;
end;

class function TDnTcpChannel.MatchingRequest(Context: Pointer): TDnTcpRequest;
var PContext: PDnReqContext;
begin
  PContext := PDnReqContext(Context);
  Result := TDnTcpRequest(PContext^.FRequest);
end;

function TDnTcpChannel.IsClosed: Boolean;
begin
  Result := FSocket = Winsock2.INVALID_SOCKET;
end;

procedure TDnTcpChannel.SetNagle(Value: Boolean);
var Temp: LongBool;
begin
  Temp := Value;
  Winsock2.setsockopt(FSocket, IPPROTO_TCP, TCP_NODELAY, PAnsiChar(@Temp), SizeOf(Temp));
end;

procedure TDnTcpChannel.DeleteRequest(Request: TDnTcpRequest);
var F: Boolean;
begin
  F := False;
  
  if FClosingRequest = Request then
  begin
    FClosingRequest := Nil;
    F := True;
  end
  else
  if FReadQueue.IndexOf(Request) >= 0 then
  begin
    FReadQueue.Extract(Request);
    F := True;
  end
  else
  if FWriteQueue.IndexOf(Request) >= 0 then
  begin
    FWriteQueue.Extract(Request);
    F := True;
  end
  else
  if FConnectingRequest = Request then
  begin
    FConnectingRequest := Nil;
    F := True;
  end;

  Request.Free;

end;

procedure TDnTcpChannel.ExecuteNext(Request: TDnTcpRequest);
var RT: TDnIORequestType;
begin
  try
    FRunGuard.Acquire;

    //save request type
    RT := Request.RequestType;

    //free the request object
    DeleteRequest(Request);

    //schedule next request
    //the first priority is close request
    if (FClosingRequest <> Nil) and not FClosing then
    begin
      //execute closing request
      FClosingRequest.Execute;

      //mark channel as closing
      FClosing := True;

      //drop non active requests
      DeleteNonActiveRequests;
    end else
    begin
      if not FClosing then
      begin

      case RT of
        rtRead:     begin
                      if FReadQueue.Count <> 0 then
                        (FReadQueue[0] as TDnTcpRequest).Execute;
                    end;
        rtWrite:    begin
                      if FWriteQueue.Count <> 0 then
                        TDnTcpRequest(FWriteQueue[0]).Execute;
                    end;
        rtConnect:  begin
                      if FReadQueue.Count <> 0 then
                        (FReadQueue[0] as TDnTcpRequest).Execute;
                      if FWriteQueue.Count <> 0 then
                        (FWriteQueue[0] as TDnTcpRequest).Execute;
                    end;

      end;

      end;
    end;

  finally
    FRunGuard.Release;
  end;
end;

destructor TDnTcpChannel.Destroy;
begin
  FRunGuard.Acquire;
  FRunGuard.Release;

    FreeAndNil(FOutgoingQueue);
    FreeAndNil(FRunGuard);
    FreeAndNil(FTimeOutGuard);
    FreeAndNil(FReadQueue);
    FreeAndNil(FWriteQueue);
    if FClosingRequest <> Nil then
      FClosingRequest := Nil;

    if FOwnsCustomData and Assigned(FCustomData) then
      FreeAndNil(FCustomData);

    RemoveChannel(Self);

  inherited Destroy;
end;

procedure TDnTcpChannel.AddRef(_Type: TDnIORequestType; const Comment: String = '');
var DebugMsg: String;
begin
  FRunGuard.Acquire;
  try
    FRefCount := FRefCount + 1;
    DebugMsg := Format('+  %.10d | Ref. count is %.10d. The type of operation is %s. The comment is %s',
      [NativeUInt(Pointer(Self)), FRefCount, GDnIORequestType[Integer(_Type)], Comment]);
    //OutputDebugString(PChar(DebugMsg));
  finally
    FRunGuard.Release;
  end;
end;

procedure TDnTcpChannel.Release(_Type: TDnIORequestType; const Comment: String = '');
var DebugMsg: String;
begin
  FRunGuard.Acquire;
  try
    FRefCount := FRefCount - 1;

    DebugMsg := Format('-  %.10d | Ref. count is %.10d. The type of operation is %s. The comment is %s', [NativeUInt(Pointer(Self)),
      FRefCount, GDnIORequestType[Integer(_Type)], Comment]);

    //OutputDebugString(PChar(DebugMsg));
    if FRefCount <= 0 then
    begin
      if not FDeletePosted then
      begin
        TDnTcpReactor(FReactor).PostDeleteSignal(Self);
        FDeletePosted := True;
      end
      else
        DebugBreak;
    end else
    if FRefCount < 0 then
      DebugBreak;

  finally
    FRunGuard.Release;
  end;
end;

procedure TDnTcpChannel.EnsureSending;
begin
end;

procedure TDnTcpChannel.HandleTimeoutMsg(Executor: TDnAbstractExecutor);
var Request: TDnTcpTimeoutRequest;
begin
  if (Trunc(Now - Self.LastIOTime * 86400 + 0.5) > Self.Timeout) and
     (Self.Timeout > 0) then
  begin
    Request := TDnTcpTimeoutRequest.Create(Self);
    Executor.PostEvent(Request);
  end
  else
  begin //repost the timer query
    (FReactor as TDnTcpReactor).SetTimeout(Self, FTimeout);
  end;
end;

function TDnTcpChannel.GetIsFinished: Boolean;
begin
  FRunGuard.Acquire;
  try
    Result := FRefCount = 0;
  finally
    FRunGuard.Release;
  end;
end;

procedure TDnTcpChannel.DeleteNonActiveRequests;
var i, RC, WC: Integer; C: TDnTcpRequest;
begin
  RC := FReadQueue.Count; WC := FWriteQueue.Count;
  for i:=RC-1 downto 0 do
  begin
    C := TDnTcpRequest(FReadQueue[i]);
    if not C.Running then
    begin
      FReadQueue.Delete(i);
      C.Free;
    end;
  end;

  for i:=WC-1 downto 0 do
  begin
    C := TDnTcpRequest(FWriteQueue[i]);
    if not C.Running then
    begin
      FWriteQueue.Delete(i);
      C.Free;
    end;
  end;
end;

procedure   TDnTcpChannel.Lock;
begin
  FRunGuard.Acquire;
end;

procedure   TDnTcpChannel.Unlock;
begin
  FRunGuard.Release;
end;

procedure ClearChannelList(Lst: TObjectList);
var
  i: Integer;
begin
  if not Assigned(Lst) then
    exit;
  for i:= 0 to Lst.Count-1 do
    TDnTcpChannel(Lst[i]).Release(rtChannelList);
  Lst.Clear;
end;

procedure AddChannel(C: TDnTcpChannel);
begin
  GChannelListGuard.Acquire;
  try
    GChannelList.Add(C);
  finally
    GChannelListGuard.Release;
  end;
end;

procedure RemoveChannel(C: TDnTcpChannel);
begin
  GChannelListGuard.Acquire;
  try
    GChannelList.Extract(C);
  finally
    GChannelListGuard.Release;
  end;
end;


initialization
  GChannelList := TObjectList.Create(False);
  GChannelListGuard := TDnMutex.Create;
finalization
  FreeAndNil(GChannelList);
  FreeAndNil(GChannelListGuard);
end.
