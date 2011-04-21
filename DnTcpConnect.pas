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
unit DnTcpConnect;
interface
uses
  Windows, Classes, Winsock2, SysUtils, Contnrs, Math,
  DnTcpReactor, DnRtl, DnAbstractExecutor, DnAbstractLogger,
  DnConst, DnTcpChannel, DnTcpRequest;

type
  IDnTcpConnectHandler = interface
  ['{8E98EE19-A73C-4981-90D3-F0D544ED8085}']
    procedure DoConnect(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                        const IP: AnsiString; Port: Word);
    procedure DoConnectError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                              ErrorCode: Cardinal);
  end;


  TDnTcpConnectRequest = class;
  TDnTcpConnectWatcherThread = class;
  
  TDnTcpConnectWatcher = class(TObject)
  protected
    FConnects:      TObjectList;
    FNewConnects:   TObjectList;
    FGuard:         TDnMutex;
    FThreadGuard:   TDnMutex;
    FReactor:       TDnTcpReactor;
    FExecutor:      TDnAbstractExecutor;
    FLogger:        TDnAbstractLogger;
    FLogLevel:      TDnLogLevel;
    FActive:        Boolean;
    FThread:        TDnTcpConnectWatcherThread;
    
    procedure   SetActive(Value: Boolean);
    function    TurnOn: Boolean;
    function    TurnOff: Boolean;
    procedure   ConnectFinished(Request: TDnTcpConnectRequest);
    procedure   AbortRequest(Request: TDnTcpConnectRequest);
    procedure   AbortRequests;

  public
    constructor Create;
    destructor  Destroy; override;
    procedure   MakeConnect(Channel: TDnTcpChannel; Key: Pointer; TimeOut: Cardinal;
                            Handler: IDnTcpConnectHandler);

    property    Reactor:    TDnTcpReactor read FReactor write FReactor;
    property    Executor:   TDnAbstractExecutor read FExecutor write FExecutor;
    property    Logger:     TDnAbstractLogger read FLogger write FLogger;
    property    LogLevel:   TDnLogLevel read FLogLevel write FLogLevel;
    property    Active:     Boolean read FActive write SetActive;
  end;

  TDnTcpConnectWatcherThread = class (TDnThread)
  protected
    FWatcher: TDnTcpConnectWatcher;
    procedure ThreadRoutine; override;
    procedure CreateContext; override;
    procedure DestroyContext; override;
  public
    constructor Create(Watcher: TDnTcpConnectWatcher);
    destructor Destroy; override;
  end;

  TDnTcpConnectRequest = class (TDnTcpRequest)
  protected
    FHandler:         IDnTcpConnectHandler;
    FConnectSignal:   THandle;
    FErrorCode:       Integer;
    FConnectWatcher:  TDnTcpConnectWatcher;
    FTimeOut:         Cardinal;
    FStartTick:       Cardinal;


  public
    constructor Create( Channel: TDnTcpChannel; Key: Pointer; TimeOut: Cardinal;
                        Handler: IDnTcpConnectHandler;
                        ConnectWatcher: TDnTcpConnectWatcher);
    destructor  Destroy; override;
    procedure   Execute; override;

    procedure   CallHandler(Context: TDnThreadContext); override;
    function    IsComplete: Boolean; override;
    function    IsPureSignal: Boolean; override;

    procedure   ReExecute; override;
    function    RequestType: TDnIORequestType; override;
    procedure   SetTransferred(Transferred: Cardinal); override;
  end;


implementation

constructor TDnTcpConnectWatcher.Create;
begin
  FConnects := Nil;
  FNewConnects := Nil;
  FReactor := Nil;
  FExecutor := Nil;
  FLogLevel := llMandatory;
  FLogger := Nil;
  FThread := Nil;
  FGuard := TDnMutex.Create;
  FThreadGuard := TDnMutex.Create;
end;

destructor  TDnTcpConnectWatcher.Destroy;
begin
  SetActive(False);
  FreeAndNil(FThreadGuard);
  FreeAndNil(FGuard);
  inherited Destroy;
end;

procedure   TDnTcpConnectWatcher.SetActive(Value: Boolean);
begin
  FGuard.Acquire;
  try
    if not FActive and Value then
      FActive := TurnOn
    else if FActive and not Value then
      FActive := TurnOff;
  finally
    FGuard.Release;
  end;
end;

function TDnTcpConnectWatcher.TurnOn: Boolean;
begin
  if (FReactor = Nil) or (FLogger = Nil) or (FExecutor = Nil) then
    raise EDnException.Create(ErrInvalidConfig, 0, 'TDnTcpConnectWatcher');
  FConnects := TObjectList.Create(False);
  FNewConnects := TObjectList.Create(False);
  //FGuard := TDnMutex.Create;
  FThread := TDnTcpConnectWatcherThread.Create(Self);
  FThread.Resume;
  Result := True;
end;

function TDnTcpConnectWatcher.TurnOff: Boolean;
begin
  AbortRequests;

  if not FExecutor.Active then
  begin
    if Assigned(FConnects) then
      FConnects.OwnsObjects := True;
    if Assigned(FNewConnects) then
      FNewConnects.OwnsObjects := True;
  end;

  if Assigned(FConnects) then
    FreeAndNil(FConnects);
  if Assigned(FNewConnects) then
    FreeAndNil(FNewConnects);

  //FreeAndNil(FGuard);

  Result := False;
end;

procedure TDnTcpConnectWatcher.ConnectFinished(Request: TDnTcpConnectRequest);
var ChannelImpl: TDnTcpChannel;
    networkEvents: TWSANetworkEvents;
begin
  if Request = Nil then
    raise EDnException.Create(ErrInvalidParameter, 0, 'TDnTcpConnectWatcher.ConnectFinished');

  //extract channel pointer
  ChannelImpl := TDnTcpChannel(Request.Channel);

  //check for timeout
  if (Request.FTimeOut <> 0) and (CurrentTimeFromLaunch() - Request.FStartTick > Request.FTimeOut) then
  begin
    //set error code
    Request.FErrorCode := WSAETIMEDOUT;

    //unbind from WSAEventSelect
    WSAEventSelect(ChannelImpl.SocketHandle, Request.FConnectSignal, 0);

    //call the error handler
    FExecutor.PostEvent(Request);
  end
  else
  begin
    //check if error occured
    if (Winsock2.WSAEnumNetworkEvents(ChannelImpl.SocketHandle, Request.FConnectSignal,
                                @networkEvents) = SOCKET_ERROR) then
      Request.FErrorCode := WSAGetLastError
    else
      Request.FErrorCode := networkEvents.iErrorCode[FD_CONNECT_BIT];

    //unbind from WSAEventSelect
    WSAEventSelect(ChannelImpl.SocketHandle, Request.FConnectSignal, 0);

    //if connection successful - add it to reactor
    if (Request.FErrorCode = 0) or (Request.FErrorCode = WSAETIMEDOUT) then
    begin
      FReactor.PostChannel(ChannelImpl);
    end;

    //call handler
    FExecutor.PostEvent(Request);
  end;
end;

procedure TDnTcpConnectWatcher.MakeConnect(Channel: TDnTcpChannel; Key: Pointer;
    TimeOut: Cardinal; Handler: IDnTcpConnectHandler);
var ConnectRequest: TDnTcpConnectRequest;
begin
  //OutputDebugString('MakeConnect is called.');
  FGuard.Acquire;
  try
    //create request object
    ConnectRequest := TDnTcpConnectRequest.Create(Channel, Key, TimeOut, Handler, Self);

    //run it
    ConnectRequest.Execute;

    //increase the global counter of pending requests
    InterlockedIncrement(PendingRequests);

    //check if connect is finished
    if ConnectRequest.FErrorCode <> WSAEWOULDBLOCK then
    begin

      //check if it is ok
      if ConnectRequest.FErrorCode = 0 then
        FReactor.PostChannel(Channel); //bind new channel to IOCP //channel is already added
      FExecutor.PostEvent(ConnectRequest); //post event to executor
    end
    else
    begin
      //add to connect watcher's socket list

      ConnectRequest.FErrorCode := 0;
      FThreadGuard.Acquire;
      try
        FNewConnects.Add(ConnectRequest);
      finally
        FThreadGuard.Release;
      end;
    end;
  finally
    FGuard.Release;
  end;
end;

procedure TDnTcpConnectWatcher.AbortRequest(Request: TDnTcpConnectRequest);
var ChannelImpl: TDnTcpChannel;
begin
  Request.FErrorCode := WSAECONNABORTED;
  if FReactor.Active then
  begin
    ChannelImpl := Request.Channel as TDnTcpChannel;
    ChannelImpl.AddRef(rtChannelList);
    FReactor.PostChannel(ChannelImpl);
  end;
  if FExecutor.Active then
    FExecutor.PostEvent(Request);
end;

procedure TDnTcpConnectWatcher.AbortRequests;
var i: Integer;
begin
  FGuard.Acquire;
  FreeAndNil(FThread);
  for i:=0 to FConnects.Count-1 do
    AbortRequest(TDnTcpConnectRequest(FConnects[i]));
  for i:=0 to FNewConnects.Count-1 do
    AbortRequest(TDnTcpConnectRequest(FNewConnects[i]));
  FGuard.Release;
end;

//-------------------------------------------------------------------------------
//-------------------------------------------------------------------------------
var InitConn: Integer;

constructor TDnTcpConnectWatcherThread.Create(Watcher: TDnTcpConnectWatcher);
begin
  inherited Create;
  if Watcher = Nil then
    raise EDnException.Create(ErrInvalidParameter, 0, 'TDnTcpConnectWatcherThread.Create');
  FWatcher := Watcher;

  InitConn := 0;
end;

destructor TDnTcpConnectWatcherThread.Destroy;
begin
  inherited Destroy;
end;

procedure TDnTcpConnectWatcherThread.CreateContext;
begin
end;

procedure TDnTcpConnectWatcherThread.DestroyContext;
begin
end;

procedure TDnTcpConnectWatcherThread.ThreadRoutine;
var ResCode, i, ConnCount, ConnIndex: Integer;
    ConnectHandles: array[0..63] of THandle;
    Request: TDnTcpConnectRequest;
begin
  ConnIndex := 0;
  while not Terminated do
  begin
    //did we check all connections?
    if ConnIndex < FWatcher.FConnects.Count then
    begin//check a new connects

      //fill events array - up to 63 socket handles

      //now we should check next 'ConnCount' sockets.
      //Find their count.
      ConnCount := FWatcher.FConnects.Count - ConnIndex;

      //limit its number by 63
      ConnCount := Math.Min(ConnCount, 63);

      //save the index of first identified socket
      i := ConnIndex;

      //iterate all chosen sockets
      while i <= ConnIndex+ConnCount-1 do
      begin
        //get the pointer to connect request object
        Request := TDnTcpConnectRequest(FWatcher.FConnects[i]);

        //check for timeout
        if (Request.FTimeOut <> 0) and (CurrentTimeFromLaunch() - Request.FStartTick > Request.FTimeOut) then
        begin
          //remove connect request from list
          FWatcher.FConnects.Delete(i);

          //debug message about timeouted connection
          OutputDebugString('Connection timeouted.');
          
          //notify about finished connection
          FWatcher.ConnectFinished(Request);
        end;

        //save event handle
        ConnectHandles[i-ConnIndex] := TDnTcpConnectRequest(FWatcher.FConnects[i]).FConnectSignal;

        //move to the next request
        Inc(i);
      end;

      //check events array for fired event
      ResCode := WSAWaitForMultipleEvents(ConnCount, @ConnectHandles, False, 0, False);
      if (ResCode >= WSA_WAIT_EVENT_0) and (ResCode < WSA_WAIT_EVENT_0 + ConnCount) then
      begin //have connection
        //the connection is established or failed - we've got event signaled

        //get the request object
        Request := TDnTcpConnectRequest(FWatcher.FConnects[ConnIndex+ResCode-WSA_WAIT_EVENT_0]);

        //remove it from the list
        FWatcher.FConnects.Delete(ConnIndex+ResCode-WSA_WAIT_EVENT_0);

        Inc(InitConn);

        //OutputDebugString('Connection finished.');
        FWatcher.ConnectFinished(request);

      end else
        Inc(ConnIndex, ConnCount); //move to next connection objects
    end else
    begin
      ConnIndex := 0;
      Windows.Sleep(1);
    end;

    //check for new requests
    FWatcher.FThreadGuard.Acquire;
    if FWatcher.FNewConnects.Count > 0 then
    begin
      for i:=0 to FWatcher.FNewConnects.Count-1 do
      begin
        //OutputDebugString('New connect request is add.');
        FWatcher.FConnects.Add(FWatcher.FNewConnects[i]);
      end;

      FWatcher.FNewConnects.Clear;
    end;
    FWatcher.FThreadGuard.Release;
  end;
end;


//-------------------------------------------------------------------------------
//-------------------------------------------------------------------------------

constructor TDnTcpConnectRequest.Create(Channel: TDnTcpChannel; Key: Pointer; TimeOut: Cardinal;
                                        Handler: IDnTcpConnectHandler;
                                        ConnectWatcher: TDnTcpConnectWatcher);
begin
  //check the incoming parameters
  inherited Create(Channel, Key);

  if (Channel = Nil) or (Handler = Nil) or (ConnectWatcher = Nil) then
    raise EDnException.Create(ErrInvalidParameter, 0, 'TDnTcpConnectRequest.Create');
  FChannel := Channel;
  FKey := Key;
  FHandler := Handler;
  FConnectSignal := WSACreateEvent();
  FConnectWatcher := ConnectWatcher;
  FRefCount := 0;
  FErrorCode := 0;
  FTimeOut := TimeOut;
  FStartTick := 0;

end;


procedure TDnTcpConnectRequest.Execute;
var ChannelImpl: TDnTcpChannel;
    ResCode: Integer;
begin
  ChannelImpl := TDnTcpChannel(FChannel);

  //save the start time of connection
  FStartTick := CurrentTimeFromLaunch();

  //associate the request with Win32 event handle
  Winsock2.WSAEventSelect(ChannelImpl.SocketHandle, FConnectSignal, FD_CONNECT);

  //initiate connection
  ResCode := WSAConnect(ChannelImpl.SocketHandle, ChannelImpl.RemoteAddrPtr,
          SizeOf(TSockAddrIn), Nil, Nil, Nil, Nil);

  //check if connection returned the error code
  if ResCode <> 0 then
    FErrorCode := WSAGetLastError;
end;

procedure TDnTcpConnectRequest.CallHandler(Context: TDnThreadContext);
var ChannelImpl: TDnTcpChannel;
begin
  ChannelImpl := TDnTcpChannel(FChannel);
  
  if FErrorCode = 0 then
    FHandler.DoConnect(Context, ChannelImpl, FKey, ChannelImpl.RemoteAddr,
      ChannelImpl.RemotePort)
  else
  if FErrorCode <> WSAEWOULDBLOCK then
  begin
    ChannelImpl.CloseSocketHandle;
    FHandler.DoConnectError(Context, ChannelImpl, FKey, FErrorCode);
    
  end;
end;

function TDnTcpConnectRequest.IsComplete: Boolean;
begin
  Result := FErrorCode <> WSA_IO_PENDING;
end;

// It is one-time request. It is not reused so the event runner can delete it.
function    TDnTcpConnectRequest.IsPureSignal: Boolean;
begin
  Result := True;
end;

procedure   TDnTcpConnectRequest.ReExecute;
begin
  ;
end;

function    TDnTcpConnectRequest.RequestType: TDnIORequestType;
begin
  Result := rtWrite;
end;

procedure   TDnTcpConnectRequest.SetTransferred(Transferred: Cardinal);
begin
  ;
end;

destructor  TDnTcpConnectRequest.Destroy;
begin
  if FConnectSignal <> 0 then
  begin
    Winsock2.WSACloseEvent(FConnectSignal);
    FConnectSignal := 0;
  end;
  inherited Destroy;
end;

end.
