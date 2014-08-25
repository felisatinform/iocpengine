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
{$I DnConfig.inc}
unit DnTcpReactor;

interface

uses
  Windows, SysUtils, Classes, Contnrs,
  DnRtl, DnConst, DnSimpleExecutor,
  DnAbstractExecutor, DnAbstractLogger,
  DnTcpRequest, DnInterfaces, DnTcpChannel, DnTimerEngine, ComObj, ActiveX
{$ifdef ENABLE_STREAMSEC}
  , StreamSecII, TlsClass
{$endif}
  , WS2;

type
  TDnTcpReactor = class;

  TDnTcpReactorThread = class;
  TDnTcpTimeoutEvent = procedure(Context: TDnThreadContext;
    Channel: TDnTcpChannel) of object;
  TDnUserMessageEvent = procedure(Context: TDnThreadContext;
    Channel: TDnTcpChannel; SignalType: Integer; UserData: Pointer) of object;

  // Returns true if iterating is finished
  TDnProcessChannelMethod = function(Channel: TDnTcpChannel;
    UserData: Pointer): Boolean of object;

  TDnUserMessage = class
  protected
    FUserData: Pointer;
    FSignalType: Integer;
    FChannel: TDnTcpChannel;

  public
    constructor Create(UserData: Pointer; SignalType: Integer;
      Channel: TDnTcpChannel);
    destructor Destroy; override;

    property UserData: Pointer read FUserData;
    property SignalType: Integer read FSignalType;
    property Channel: TDnTcpChannel read FChannel;
  end;
{$IFDEF ROOTISCOMPONENT}

  TDnTcpReactor = class(TComponent, IDnTimerSupport)
{$ELSE}
    TDnTcpReactor = class(TDnObject, IDnTimerSupport)
{$ENDIF}
    protected FPort: THandle;

    FActive: Boolean;
{$IFDEF MANY_REACTOR_THREADS}
    FThreadList: TObjectList;
{$ELSE}
    FThread: TDnTcpReactorThread;
{$ENDIF}
    FChannelList: TObjectList;
    FGuard: TDnMutex;

    FLogger: TDnAbstractLogger;
    FLogLevel: TDnLogLevel;
    FExecutor: TDnAbstractExecutor;
    FTimer: TDnTimerEngine;
    FOnTimeout: TDnTcpTimeoutEvent;
    FOnUserMessage: TDnUserMessageEvent;
    FChannelPosted, FChannelFreed: Integer;
{$IFDEF MANY_REACTOR_THREADS}
    FThreadSize: Integer;
{$ENDIF}
{$IFDEF ENABLE_STREAMSEC}
    FStreamSec: TStreamSecII;
{$ENDIF}
    procedure SetActive(Value: Boolean);
    function TurnOn: Boolean; virtual;
    function TurnOff: Boolean; virtual;

    procedure Lock;
    procedure Unlock;
    procedure PostTimerMessage(Item: TObject);
    procedure DoTimeoutError(Context: TDnThreadContext; Channel: TDnTcpChannel);
    procedure DoUserMessage(UserMessage: TDnUserMessage);
{$IFDEF ROOTISCOMPONENT}
    procedure Notification(AComponent: TComponent; Operation: TOperation);
      override;
{$ENDIF}
  public
    constructor Create {$IFDEF ROOTISCOMPONENT}(AOwner: TComponent); override
    {$ENDIF};
    destructor Destroy; override;
    procedure PostChannel(Channel: TDnTcpChannel);
    procedure PostChannelError(Channel: TDnTcpChannel; Request: TDnTcpRequest);
    procedure PostDeleteSignal(Channel: TDnTcpChannel);
    procedure PostUserSignal(UserData: Pointer; SignalType: Integer;
      Channel: TDnTcpChannel);
    procedure RemoveChannel(Channel: TDnTcpChannel);
    function MakeChannel(const IPAddress: AnsiString;
      Port: Word): TDnTcpChannel; overload;
    function MakeChannel: TDnTcpChannel; overload;
    procedure FreeChannel(Channel: TDnTcpChannel);
    procedure SetTimeout(Channel: TDnTcpChannel; Value: Cardinal);
    procedure CloseChannels;
    procedure ProcessChannelList(Method: TDnProcessChannelMethod;
      UserData: Pointer);
    function GetChannelCount: Integer;
  published
    property Active: Boolean read FActive write SetActive;
    property Executor: TDnAbstractExecutor read FExecutor write FExecutor;
    property Logger: TDnAbstractLogger read FLogger write FLogger;
    property LogLevel: TDnLogLevel read FLogLevel write FLogLevel;
    property PortHandle: THandle read FPort;
{$IFDEF MANY_REACTOR_THREADS}
    property ThreadSize: Integer read FThreadSize write FThreadSize;
{$ENDIF}
    property OnTimeout: TDnTcpTimeoutEvent read FOnTimeout write FOnTimeout;
    property OnUserMessage
      : TDnUserMessageEvent read FOnUserMessage write FOnUserMessage;
  end;

  TDnTcpReactorThread = class(TDnThread)
  protected
    FReactor: TDnTcpReactor;
    procedure CreateContext; override;
    procedure DestroyContext; override;
    procedure ThreadRoutine; override;
    procedure DoRequest(Request: TDnTcpRequest; Channel: TDnTcpChannel);
    procedure DoClose(Channel: TDnTcpChannel; Request: TDnTcpRequest);
    procedure ParseIONotification(Transferred: Cardinal; Key: Cardinal;
      Overlapped: POverlapped);
    procedure ParseIOError(Transferred: Cardinal; Key: Cardinal;
      Overlapped: POverlapped);
    procedure LogMessage(S: String);
  public
    constructor Create(Reactor: TDnTcpReactor);
    destructor Destroy; override;
  end;

procedure Register;
{$IFDEF Debug_IOCP}
procedure Setup;

procedure Teardown;
{$ENDIF}

implementation

{$IFDEF Debug_IOCP}

uses
  logging, logSupport;

var
  log: TabsLog;
{$ENDIF}

var
  ParseIONotificationCount: Integer;

  // ------------------- TDnUserMessage ----------------------------------------------

constructor TDnUserMessage.Create(UserData: Pointer; SignalType: Integer;
  Channel: TDnTcpChannel);
begin
  inherited Create;
  FUserData := UserData;
  FSignalType := SignalType;
  FChannel := Channel;
end;

destructor TDnUserMessage.Destroy;
begin
  inherited Destroy;
end;

// ------------------------------------------------------------------------------

// -----------------------------------------------------------------------------

constructor TDnTcpReactor.Create {$IFDEF ROOTISCOMPONENT}(AOwner: TComponent)
{$ENDIF};
begin
  inherited Create {$IFDEF ROOTISCOMPONENT}(AOwner){$ENDIF};
  FPort := 0;
  FActive := False;
  FGuard := TDnMutex.Create;
  FChannelList := TObjectList.Create(False);
  FExecutor := Nil;
  FTimer := Nil;
  FLogger := Nil;
  FLogLevel := llMandatory;
{$IFDEF ENABLE_STREAMSEC}
  FStreamSec := TStreamSecII.Create(Nil);
{$ENDIF}

  FThreadSize := 4;

end;

destructor TDnTcpReactor.Destroy;
begin
  if FActive then
    SetActive(False);
{$IFDEF ENABLE_STREAMSEC}
  FreeAndNil(FStreamSec);
{$ENDIF}
  FreeAndNil(FGuard);
  FreeAndNil(FChannelList);
  inherited Destroy;
end;

function TDnTcpReactor.GetChannelCount: Integer;
begin
  FGuard.Acquire;
  try
    if Assigned(FChannelList) then
      Result := FChannelList.Count
    else
      Result := 0;
  finally
    FGuard.Release;
  end;
end;

procedure TDnTcpReactor.Lock;
begin
  FGuard.Acquire;
end;

procedure TDnTcpReactor.Unlock;
begin
  FGuard.Release;
end;
{$IFDEF ROOTISCOMPONENT}

procedure TDnTcpReactor.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  if Operation = opRemove then
  begin
    if AComponent = FLogger then
      FLogger := Nil
    else if AComponent = FExecutor then
      FExecutor := Nil;
  end;
end;
{$ENDIF}

procedure TDnTcpReactor.SetActive(Value: Boolean);
begin
  if not FActive and Value then
    FActive := TurnOn
  else if FActive and not Value then
    FActive := TurnOff;
end;

function TDnTcpReactor.MakeChannel(const IPAddress: AnsiString;
  Port: Word): TDnTcpChannel;
begin
  Result := TDnTcpChannel.CreateEmpty(Self, IPAddress, Port);
end;

function TDnTcpReactor.MakeChannel: TDnTcpChannel;
begin
  Result := TDnTcpChannel.CreateEmpty(Self);
end;

procedure TDnTcpReactor.FreeChannel(Channel: TDnTcpChannel);
begin
  Channel.Free;
end;

procedure TDnTcpReactor.SetTimeout(Channel: TDnTcpChannel; Value: Cardinal);
begin
  Channel.Lock;
  try
    // save timeout value
    Channel.TimeOut := Value;

    // request the timer notify
    if Value <> 0 then
      FTimer.RequestTimerNotify(Channel, Value, Nil);
  finally
    Channel.Unlock;
  end;
end;

procedure TDnTcpReactor.RemoveChannel(Channel: TDnTcpChannel);
begin
  if Channel.IsClosed then
  begin
{$IFDEF Debug_IOCP}
    log.EnterMethod(lvDebug, Self, 'RemoveChannel--Closed');
{$ENDIF}
    FGuard.Acquire;
    try
      if FChannelList.Extract(Channel) <> Nil then
      begin
        // remove from a timeout timer
        FTimer.CancelNotify(Channel);

        // dereference from channel list
        Channel.Release(rtChannelList);
      end;
    finally
      FGuard.Release;
{$IFDEF Debug_IOCP}
      log.LeaveMethod(lvDebug, Self, 'RemoveChannel');
{$ENDIF}
    end;
  end;
end;

procedure TDnTcpReactor.PostTimerMessage(Item: TObject);
var
  Ch: TDnTcpChannel;
begin
  Ch := Item as TDnTcpChannel;
  PostQueuedCompletionStatus(FPort, $FFFFFFFE, 0, Pointer(Ch));
end;

function TDnTcpReactor.TurnOn: Boolean;
var
  TempSocket: TSocket;
  i: Integer;
begin
  FChannelFreed := 0;
  FChannelPosted := 0;


  TempSocket := WS2.socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
  if TempSocket = WS2.INVALID_SOCKET then
    raise EDnException.Create(ErrWin32Error, WSAGetLastError(), 'Socket');

  FPort := CreateIOCompletionPort(TempSocket, 0, 0, 1);
  if FPort = 0 then
  begin
    WS2.closesocket(TempSocket);
    raise EDnException.Create(ErrWin32Error, GetLastError(),
      'CreateIOCompletionPort');
  end;
  WS2.closesocket(TempSocket);

  FTimer := TDnTimerEngine.Create;
  FTimer.TimerSink := Self;
  FTimer.Active := True;
{$IFDEF MANY_REACTOR_THREADS}
  FThreadList := TObjectList.Create(True);
  for i := 0 to FThreadSize - 1 do
    FThreadList.Add(TDnTcpReactorThread.Create(Self));
{$ELSE}
  FThread := TDnTcpReactorThread.Create(Self);
{$ENDIF}
  Result := True;
end;

procedure TDnTcpReactor.CloseChannels;
begin
  FGuard.Acquire;
  try
    ClearChannelList(FChannelList);
  finally
    FGuard.Release;
  end;
end;

procedure TDnTcpReactor.ProcessChannelList(Method: TDnProcessChannelMethod;
  UserData: Pointer);
var
  i: Integer;
begin
  Lock;
  try
    for i := 0 to FChannelList.Count - 1 do
      if (Method(TDnTcpChannel(FChannelList[i]), UserData)) then
        Break;
  finally
    Unlock;
  end;
end;

function TDnTcpReactor.TurnOff: Boolean;
var
  i, WaitRes: Integer;
  HandleArray: PWOHandleArray;

begin
  GetMem(HandleArray, FThreadList.Count * sizeof(THandle));
  try
    CloseChannels;
    FTimer.Active := False;

    // wait while all channels will be terminated
    while FChannelList.Count > 0 do
      Windows.Sleep(100);

    // mark thread as finished
{$IFDEF MANY_REACTOR_THREADS}
    for i := 0 to FThreadList.Count - 1 do
      TThread(FThreadList[i]).Terminate;

    while FThreadList.Count > 0 do
    begin
      // post exit signal
      PostQueuedCompletionStatus(FPort, 0, 0, Nil);

      // create handle array
      for i := 0 to FThreadList.Count - 1 do
        HandleArray^[i] := TThread(FThreadList[i]).Handle;

      // wait for any thread exiting - at least 1 should exit
      WaitRes := Windows.WaitForMultipleObjects(FThreadList.Count, HandleArray,
        False, INFINITE);

      if (WaitRes >= WAIT_OBJECT_0) and
        (WaitRes < WAIT_OBJECT_0 + FThreadList.Count) then
        FThreadList.Delete(WaitRes - WAIT_OBJECT_0)
      else
        WaitRes := WaitRes;

    end;

    FThreadList.Free;
    FThreadList := Nil;
{$ELSE}
    FThread.Terminate;

    // send signal to terminate
    PostQueuedCompletionStatus(FPort, 0, 0, Nil);

    // wait for thread termination
    FThread.WaitFor;

    // free thread object
    FThread.Free;
    FThread := Nil;
{$ENDIF}
    // close IOCP
    Windows.CloseHandle(FPort);
    FPort := INVALID_HANDLE_VALUE;

    // free timer
    FGuard.Acquire;
    try
      FreeAndNil(FTimer);
      FExecutor.Active := False;
    finally
      FGuard.Release;
    end;

    Result := False;
  finally
    FreeMem(HandleArray);
  end;
end;

procedure TDnTcpReactor.PostChannel(Channel: TDnTcpChannel);
var
  ChannelIndex: Integer;
begin
{$IFDEF Debug_IOCP}
  log.EnterMethod(lvDebug, Self, 'PostChannel');
{$ENDIF}
  // bind to IOCP
  FGuard.Acquire;
  try
    // check at first if such channel exists already
    if CreateIOCompletionPort(Channel.SocketHandle, FPort, Cardinal(Pointer(Channel)), 1) = 0 then
      raise EDnException.Create(ErrWin32Error, GetLastError(), 'CreateIOCompletionPort');

    // check at first if such channel object is already in
    ChannelIndex := FChannelList.IndexOf(Channel);

    if ChannelIndex = -1 then
    begin
      // grab the channel
      Channel.AddRef(rtChannelList);

      // add to list
      FChannelList.Add(Channel);

      // increase counter of posted channels
      InterlockedIncrement(FChannelPosted);
    end;
  finally
    FGuard.Release;
{$IFDEF Debug_IOCP}
    log.LeaveMethod(lvDebug, Self, 'PostChannel');
{$ENDIF}
  end;
end;

procedure TDnTcpReactor.PostChannelError(Channel: TDnTcpChannel;
  Request: TDnTcpRequest);
begin
  Request.ErrorCode := WSAGetLastError;

  // PostQueuedCompletionStatus(FPort,
  FExecutor.PostEvent(Request);
end;

// -------------------------------------------------------------------------
constructor TDnTcpReactorThread.Create(Reactor: TDnTcpReactor);
begin
  inherited Create;
  FReactor := Reactor;
  FreeOnTerminate := False;
  Self.Run;
end;

destructor TDnTcpReactorThread.Destroy;
begin
  // queue 0/0/0 signal
  // PostQueuedCompletionStatus(FReactor.FPort, 0, 0, Nil);

  // Terminate;

  inherited Destroy;
end;

procedure TDnTcpReactorThread.CreateContext;
begin
  FContext := Nil;
  SetCurrentContext(Nil);
end;

procedure TDnTcpReactorThread.DestroyContext;
begin ;
end;

procedure TDnTcpReactorThread.LogMessage(S: String);
begin
  if FReactor.FLogger <> Nil then
    try
      FReactor.FLogger.LogMsg(FReactor.FLogLevel, S);
    except
      ; // if logger failed - just ignore
    end;
end;

procedure TDnTcpReactorThread.DoRequest(Request: TDnTcpRequest;
  Channel: TDnTcpChannel);
begin
  // fire event
  if Assigned(FReactor.FExecutor) then
    FReactor.FExecutor.PostEvent(Request);

  // run next request
  Channel.ExecuteNext(Request);
end;

procedure TDnTcpReactorThread.DoClose(Channel: TDnTcpChannel;
  Request: TDnTcpRequest);
begin
end;

procedure TDnTcpReactorThread.ParseIONotification(Transferred: Cardinal;
  Key: Cardinal; Overlapped: POverlapped);
var
  Channel: TDnTcpChannel;
  Request: TDnTcpRequest;
  ReqContext: PDnReqContext;
  UserMessage: TDnUserMessage;
begin
  If Overlapped = Nil then
    Exit;

  InterlockedIncrement(ParseIONotificationCount);

  if Transferred = $FFFFFFFF then // delete signal
  begin // got delete message
    // extract the pointer to channel
    Channel := TDnTcpChannel(TObject(Overlapped));
{$IFDEF Debug_IOCP}
    log.LogDebug('Delete signal');
{$ENDIF}
    // free the channel
    Channel.Free;

    // increase the counter
    InterlockedIncrement(FReactor.FChannelFreed);
  end
  else if Transferred = $FFFFFFFE then // timer expired notify
  begin
    Channel := TDnTcpChannel(TObject(Overlapped));
{$IFDEF Debug_IOCP}
    log.LogDebug('timer expired notify');
{$ENDIF}
    if not Channel.IsClosed then
      Channel.HandleTimeoutMsg(FReactor.FExecutor);

    Channel.Release(rtTimerEngine);
  end
  else if Transferred = $FFFFFFFD then // user message coming
  begin
    UserMessage := TDnUserMessage(TObject(Overlapped));
{$IFDEF Debug_IOCP}
    log.LogDebug('user message coming');
{$ENDIF}
    FReactor.DoUserMessage(UserMessage);
    UserMessage.Channel.Release(rtUserMessage);
  end
  else
  begin
{$IFDEF Debug_IOCP}
    log.LogDebug('user message other');
{$ENDIF}
    // get the pointer to request's context
    ReqContext := PDnReqContext(Overlapped);

    // get the pointer to request object
    Request := TDnTcpChannel.MatchingRequest(Overlapped);

    // signal about finished IOCP request
    Request.Release;

    // check if it is accept request
    if Request.RequestType = rtAccept then
    begin
{$IFDEF Debug_IOCP}
      log.LogDebug('rtAccept: update %d transferred bytes', [Transferred]);
{$ENDIF}
      // update transferred bytes
      Request.SetTransferred(Transferred);

      // post event
      FReactor.FExecutor.PostEvent(Request);
    end
    else
    begin
      // extract the channel pointer
      Channel := TDnTcpChannel(Request.Channel);
{$IFDEF Debug_IOCP}
      log.LogDebug('rtOther: update %d transferred bytes', [Transferred]);
{$ENDIF}
      // update the amount of transferred bytes
      Request.SetTransferred(Transferred);

      // update timeout record
      if Request.RequestType = rtRead then
      begin
{$IFDEF Debug_IOCP}
        log.LogDebug('rtRead: setting TimeoutTact');
{$ENDIF}
        Channel.TimeoutTact := FReactor.FTimer.CurrentTact + Channel.TimeOut;
      end;
      if not Request.IsComplete then
        Request.ReExecute
      else
        DoRequest(Request, Channel);
    end;
  end;
end;

procedure TDnTcpReactorThread.ParseIOError(Transferred: Cardinal;
  Key: Cardinal; Overlapped: POverlapped);
var
  Channel: TDnTcpChannel;
  Request: TDnTcpRequest;
  ReqContext: PDnReqContext;
begin
  ReqContext := PDnReqContext(Overlapped);

  Request := TDnTcpChannel.MatchingRequest(Overlapped);
  Request.Release;

  if Request.RequestType = rtAccept then
  begin
    Request.CatchError;
    FReactor.FExecutor.PostEvent(Request);
  end
  else
  begin
    Channel := TDnTcpChannel(Request.Channel);

    Request.CatchError;

    DoRequest(Request, Channel);
  end;
end;

procedure TDnTcpReactorThread.ThreadRoutine;
var
  Transferred: Cardinal;
  {$if CompilerVersion <= 22}
  Key: Cardinal;
  {$else}
  Key: NativeUInt;
  {$ifend}
  Overlapped: POverlapped;
  ResCode: LongBool;
begin
  ComObj.CoInitializeEx(Nil, 0);

  SetCurrentContext(Nil);
  while not Terminated do
  begin
    ResCode := GetQueuedCompletionStatus(FReactor.FPort, Transferred, Key,
      Overlapped, 10);
    if Terminated then
      Exit;
    if ResCode then
    begin
      // FReactor.Logger.LogMsg(llCritical, 'Transferred: ' + IntToStr(Transferred) + ', key: ' + IntToStr(Key) + ', Overlapped: ' + IntToStr(Cardinal(Overlapped)));
    end;

    if ResCode then
    begin
      if (Transferred = 0) and (Key = 0) and (Overlapped = Nil) then
        Exit // signal to terminate thread
      else
      begin ; // notify channel
        ParseIONotification(Transferred, Key, Overlapped);
      end;
    end
    else // error trapped
    begin
      if Overlapped = Nil then
        // win32 kernel error or timeout? just ignore it 8)
      else
      begin ; // IO error
        // OutputDebugString('GetQueuedCompletionStatus returned error.');
{$IFDEF Debug_IOCP}
        log.LogError('GetQueuedCompletionStatus returned error.');
{$ENDIF}
        ParseIOError(Transferred, Key, Overlapped);
      end;
    end;
  end;
  CoUninitialize;
end;

procedure TDnTcpReactor.DoTimeoutError(Context: TDnThreadContext;
  Channel: TDnTcpChannel);
begin
  if Assigned(FOnTimeout) and FActive then
    try
      FOnTimeout(Context, Channel);
    except
      on E: Exception do
        if FLogger <> Nil then
          FLogger.LogMsg(llCritical,
            'OnTimeout handler raised an error. ' + E.Message);
    end;
end;

procedure TDnTcpReactor.DoUserMessage(UserMessage: TDnUserMessage);
begin
  if Assigned(FOnUserMessage) and FActive then
    try
      FOnUserMessage(Nil, UserMessage.Channel, UserMessage.SignalType,
        UserMessage.UserData);
    except
      on E: Exception do
        if FLogger <> Nil then
          FLogger.LogMsg(llCritical,
            'OnUserMessage handler raised an error. ' + E.Message);
    end;
end;

procedure TDnTcpReactor.PostDeleteSignal(Channel: TDnTcpChannel);
begin
  // FTimer.CancelNotify(Channel);
  PostQueuedCompletionStatus(FPort, $FFFFFFFF, 0, Pointer(Channel));
end;

procedure TDnTcpReactor.PostUserSignal(UserData: Pointer; SignalType: Integer;
  Channel: TDnTcpChannel);
var
  UserMessage: TDnUserMessage;
begin
  UserMessage := TDnUserMessage.Create(UserData, SignalType, Channel);
  Channel.AddRef(rtUserMessage);
  PostQueuedCompletionStatus(FPort, $FFFFFFFD, 0, Pointer(UserMessage));
end;
// -------------------------------------------------------------------------
{$IFDEF Debug_IOCP}

procedure Setup;
begin
  RegisterLogArea(log, 'IOCP.TcpReactor');
end;

procedure Teardown;
begin
  log := nil
end;
{$ENDIF}

procedure Register;
begin
{$IFDEF ROOTISCOMPONENT}
  RegisterComponents('DNet', [TDnTcpReactor]);
{$ENDIF}
end;

initialization

ParseIONotificationCount := 0;

end.
