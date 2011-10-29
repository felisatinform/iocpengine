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
unit DnTcpListener;

interface
uses  Classes, SysUtils, Winsock2, Windows,
      SyncObjs, DnConst, DnRtl,
      DnAbstractExecutor, DnAbstractLogger,
      DnTcpReactor, DnTcpChannel, DnTcpRequest;

type
  TDnClientTcpConnect = procedure (Context: TDnThreadContext; Channel: TDnTcpChannel) of object;
  TDnCreateTcpChannel = procedure (Context: TDnThreadContext; Socket: TSocket; Addr: TSockAddrIn;
      Reactor: TDnTcpReactor; var ChannelImpl: TDnTcpChannel) of object;
  TDnTcpListener = class;

  TDnTcpAcceptRequest = class(TDnTcpRequest)
  protected
    FListener:          TDnTcpListener;
    FAcceptSocket:      Winsock2.TSocket;
    FAcceptBuffer:      String;
    FAcceptReceived:    Cardinal;
    FLocalAddr,
    FRemoteAddr:        Winsock2.TSockAddrIn;
    FTransferred:       Cardinal;
    
  public
    constructor Create(Listener: TDnTcpListener);
    destructor Destroy; override;

    procedure Execute; override;
    function  IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;

    procedure CallHandler(Context: TDnThreadContext); override;

    procedure SetTransferred(Transferred: Cardinal); override;

  end;



  {$IFDEF ROOTISCOMPONENT}
  TDnTcpListener = class(TComponent)
  {$ELSE}
  TDnTcpListener = class(TDnObject)
  {$ENDIF}
  protected
    FActive:                Boolean;
    FNagle:                 Boolean;
    FSocket:                TSocket;
    FAddress:               AnsiString;
    FAddr:                  TSockAddrIn;
    FPort:                  Word;
    FBackLog:               Integer;
    FReactor:               TDnTcpReactor;
    FExecutor:              TDnAbstractExecutor;
    FLogger:                TDnAbstractLogger;
    FLogLevel:              TDnLogLevel;
    FKeepAlive:             Boolean;
    FOnClientConnect:       TDnClientTcpConnect;
    FOnCreateChannel:       TDnCreateTcpChannel;
    FGuard:                 TDnMutex;
    FRequest:               TDnTcpAcceptRequest;
    FRequestActive:         TDnSemaphore;
    FTurningOffSignal:      THandle;
    
    procedure SetAddress(Address: AnsiString);
    procedure SetActive(Value: Boolean);
    function  TurnOn: Boolean;
    function  TurnOff: Boolean;
    procedure CheckSocketError(Code: Cardinal; Msg: String);
    function  DoCreateChannel(Context: TDnThreadContext; Socket: TSocket;
                              Addr: TSockAddrIn): TDnTcpChannel;
    procedure DoClientConnect(Context: TDnThreadContext; Channel: TDnTcpChannel);
    procedure DoLogMessage(S: String);
    procedure QueueRequest;
    procedure RequestFinished;

    {$IFDEF ROOTISCOMPONENT}
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    {$ENDIF}
  public
    constructor Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent); override{$ENDIF};
    destructor  Destroy; override;

    //This method can be called after Active := False to ensure all IOCP activities are stopped for this listener object
    procedure WaitForShutdown(TimeoutInMilliseconds: Cardinal = INFINITE);

    //This method can be called after Active := False to poll if the listener is shutdowned
    //It should NOT be mixed with WaitForShutdown - both of them resets the Win32 event
    function  IsShutdowned: Boolean;

    procedure Lock;
    procedure Unlock;

  published
    property Active: Boolean read FActive write SetActive;
    property Port: Word read FPort write FPort;
    property Address: AnsiString read FAddress write SetAddress;

    property UseNagle: Boolean read FNagle write FNagle;
    property BackLog: Integer read FBackLog write FBackLog;
    property Reactor: TDnTcpReactor read FReactor write FReactor;
    property Executor: TDnAbstractExecutor read FExecutor write FExecutor;
    property Logger: TDnAbstractLogger read FLogger write FLogger;
    property LogLevel: TDnLogLevel read FLogLevel write FLogLevel;
    property KeepAlive: Boolean read FKeepAlive write FKeepAlive;
    property OnCreateChannel: TDnCreateTcpChannel read FOnCreateChannel write FOnCreateChannel;
    property OnIncoming: TDnClientTcpConnect read FOnClientConnect write FOnClientConnect;
  end;

procedure Register;

function AcceptEx(sListenSocket, sAcceptSocket: TSocket; lpOutputBuffer: Pointer; dwReceiveDataLength, dwLocalAddressLength, dwRemoteAddressLength: DWORD; var lpdwBytesReceived: DWORD;  lpOverlapped: POverlapped): BOOL; stdcall;
procedure GetAcceptExSockaddrs(lpOutputBuffer: Pointer; dwReceiveDataLength, dwLocalAddressLength, dwRemoteAddressLength: DWORD;  var LocalSockaddr: PSockAddr; var LocalSockaddrLength: Integer;  var RemoteSockaddr: PSockAddr; var RemoteSockaddrLength: Integer); stdcall;

implementation
function  AcceptEx;               external 'mswsock.dll' name 'AcceptEx';
procedure GetAcceptExSockaddrs;   external 'mswsock.dll' name 'GetAcceptExSockaddrs';

//------------------ TDnTcpAcceptRequest-------------------------

constructor TDnTcpAcceptRequest.Create(Listener: TDnTcpListener);
begin
  inherited Create(Nil, Nil);

  //allocate buffer for remote address
  SetLength(FAcceptBuffer, 64);

  FListener := Listener;
end;

destructor TDnTcpAcceptRequest.Destroy;
begin
  inherited Destroy;
end;

procedure TDnTcpAcceptRequest.Execute;
begin
  inherited Execute;
  
  //create socket for future channel
  FAcceptSocket := Winsock2.WSASocketA(AF_INET, SOCK_STREAM, 0, Nil, 0, WSA_FLAG_OVERLAPPED);
  if FAcceptSocket = INVALID_SOCKET then
    raise EDnException.Create(ErrWin32Error, WSAGetLastError(), 'WSASocket');

  //run acceptex query
  if AcceptEx(FListener.FSocket, FAcceptSocket, @FAcceptBuffer[1], 0, sizeof(TSockAddrIn)+16,
              sizeof(TSockAddrIn)+16, FAcceptReceived, POverlapped(@Self.FContext)) = FALSE then
  begin
    if WSAGetLastError() <> ERROR_IO_PENDING then
      raise EDnException.Create(ErrWin32Error, WSAGetLastError(), 'AcceptEx');
  end;
end;

procedure TDnTcpAcceptRequest.CallHandler(Context: TDnThreadContext);
var Channel: TDnTcpChannel;
    ResCode, LocalAddrLen, RemoteAddrLen: Integer;
    LocalAddrP, RemoteAddrP: PSockAddr;
begin
  FListener.Lock;
  try
    //extract remote address
    //OutputDebugString('Firing AcceptEx event');
    if FErrorCode = 0 then
    begin
      LocalAddrLen := Sizeof(TSockAddrIn); RemoteAddrLen := Sizeof(TSockAddrIn);

      //UPDATE_ACCEPT_CONTEXT
      ResCode := Winsock2.setsockopt(FAcceptSocket, SOL_SOCKET, SO_UPDATE_ACCEPT_CONTEXT, PChar(@FListener.FSocket), sizeof(FListener.FSocket));
      if ResCode <> 0 then
        FListener.FLogger.LogMsg(llMandatory, Format('setSockOpt with SO_UPDATE_ACCEPT_CONTEXT is failed. Error code is %d.', [Winsock2.WSAGetLastError()]));
         
      //extract addresses
      GetAcceptExSockaddrs(@FAcceptBuffer[1], 0, sizeof(TSockAddrIn)+16,
          sizeof(TSockAddrIn)+16, LocalAddrP, LocalAddrLen,
          RemoteAddrP, RemoteAddrLen); //}//there was a good idea but it is not working so just KISS :)

      FLocalAddr := LocalAddrP^;
      FRemoteAddr := RemoteAddrP^;

      Channel := FListener.DoCreateChannel(Context, FAcceptSocket, FRemoteAddr);

      //post channel to reactor
      FListener.FReactor.PostChannel(Channel);

      //fire event for new connection
      FListener.DoClientConnect(Context, Channel);
    end
    else
      if Assigned(FListener.FLogger) then
        FListener.FLogger.LogMsg(llCritical, 'Failed to AcceptEx. Error code is ' + IntToStr(FErrorCode));

    FListener.RequestFinished;

    //re-execute the request if it is possible
    if not FListener.FActive then
    begin
      //we are in shutdown process
      Windows.SetEvent(FListener.FTurningOffSignal);

      //exit from procedure
      Exit;
    end;

    FTransferred := 0;
    FErrorCode := 0;
    FAcceptSocket := INVALID_SOCKET;

    FListener.QueueRequest;
  finally
    FListener.Unlock;
  end;
end;


function  TDnTcpAcceptRequest.IsComplete: Boolean;
begin
  Result := True;
end;

procedure TDnTcpAcceptRequest.ReExecute;
begin
  Execute;
end;

function  TDnTcpAcceptRequest.RequestType: TDnIORequestType;
begin
  Result := rtAccept;
end;

procedure TDnTcpAcceptRequest.SetTransferred(Transferred: Cardinal);
begin
  FAcceptReceived := 0;
end;


{$IFDEF ROOTISCOMPONENT}
constructor TDnTcpListener.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
{$ELSE}
constructor TDnTcpListener.Create;
begin
  inherited Create;
{$ENDIF}
  Self._AddRef;
  FActive := False;
  FPort := 7080;
  FAddress := '0.0.0.0';
  FOnCreateChannel := Nil;
  FOnClientConnect := Nil;
  FKeepAlive := False;
  FNagle := True;
  FSocket := INVALID_SOCKET;
  FBackLog := 5;
  FLogger := Nil;
  FLogLevel := llMandatory;
  FReactor := Nil;
  FExecutor := Nil;
  FGuard := TDnMutex.Create;
  FRequestActive := TDnSemaphore.Create(1, 1);
  FTurningOffSignal := Windows.CreateEvent(Nil, True, False, Nil);
end;

destructor TDnTcpListener.Destroy;
begin
  if not FActive then
    Exit;

  if Active then
    Active := False;

  //wait while acceptex query will finish
  Windows.WaitForSingleObject(FTurningOffSignal, INFINITE);

  FreeAndNil(FRequest);
  FreeAndNil(FRequestActive);
  Windows.CloseHandle(FTurningOffSignal);
  FreeAndNil(FGuard);

  inherited Destroy;
end;

procedure TDnTcpListener.WaitForShutdown(TimeoutInMilliseconds: Cardinal);
begin
  Windows.WaitForSingleObject(FTurningOffSignal, TimeoutInMilliseconds);
end;

function  TDnTcpListener.IsShutdowned: Boolean;
begin
  Result := Windows.WaitForSingleObject(FTurningOffSignal, 0) = WAIT_OBJECT_0;
end;

{$IFDEF ROOTISCOMPONENT}
procedure TDnTcpListener.Notification(AComponent: TComponent; Operation: TOperation);
begin
  if Operation = opRemove then
  begin
    if AComponent = FExecutor then
      FExecutor := Nil
    else
    if AComponent = FLogger then
      FLogger := Nil
    else
    if AComponent = FReactor then
      FReactor := Nil;
  end;
end;
{$ENDIF}

procedure TDnTcpListener.DoLogMessage(S: String);
begin
  if FLogger<>Nil then
  try
    FLogger.LogMsg(FLogLevel, S);
  except
    ;
  end;
end;

procedure TDnTcpListener.CheckSocketError(Code: Cardinal; Msg: String);
begin
  if (FLogger <> Nil) and (Code = INVALID_SOCKET) then
  try
    FLogger.LogMsg(FLogLevel, Msg);
  except
    ; //suppress exception
  end
end;

procedure TDnTcpListener.SetActive(Value: Boolean);
begin
  Lock;
  try
    if not FActive and Value then
      FActive := TurnOn
    else if FActive and not Value then
      FActive := TurnOff;
  finally
    Unlock;
  end;
end;

function TDnTcpListener.TurnOn: Boolean;
var TempBool: LongBool;
begin
  FActive := True;
  
  //create listening socket
  FSocket := Winsock2.WSASocket(AF_INET, SOCK_STREAM, 0, Nil, 0, WSA_FLAG_OVERLAPPED);
  if FSocket = INVALID_SOCKET then
    raise EDnException.Create(ErrWin32Error, WSAGetLastError(), 'WSASocket');
  FillChar(FAddr, SizeOf(FAddr), 0);
  FAddr.sin_family := AF_INET;
  FAddr.sin_port := Winsock2.htons(FPort);
  FAddr.sin_addr.S_addr := inet_addr(PAnsiChar(FAddress));

  //associate with completion port
  CreateIOCompletionPort(FSocket, FReactor.PortHandle, 0, 1);

  //Set SO_REUSEADDR
  TempBool := True;
  SetSockOpt(FSocket, SOL_SOCKET, SO_REUSEADDR, PChar(@TempBool), SizeOf(TempBool));

  //bind socket
  if Bind(FSocket, @FAddr, sizeof(FAddr)) = -1 then
    raise EDnException.Create(ErrWin32Error, WSAGetLastError, Format('Bind failed. Port is %d', [FPort]));

  if Winsock2.Listen(FSocket, FBackLog) = -1 then
    raise EDnException.Create(ErrWin32Error, WSAGetLastError(), Format('Listen failed. Port is %d.', [FPort]));

  
  //queue AcceptEx request
  QueueRequest;

  Result := True;
end;

procedure TDnTcpListener.QueueRequest;
begin
  //OutputDebugString('Running the next AcceptEx request.');
  FRequestActive.Wait;

  if FRequest = Nil then
    FRequest := TDnTcpAcceptRequest.Create(Self);

  FRequest.Execute;
end;

procedure TDnTcpListener.Lock;
begin
  FGuard.Acquire;
end;

procedure TDnTcpListener.Unlock;
begin
  if assigned(FGuard) then
    FGuard.Release
  else
   FLogger.LogMsg(llMandatory,'FGuard is nil');
end;

procedure TDnTcpListener.RequestFinished;
begin
  FRequestActive.Release;
end;

function  TDnTcpListener.DoCreateChannel(Context: TDnThreadContext; Socket: TSocket; Addr: TSockAddrIn): TDnTcpChannel;
var SockObj: TDnTcpChannel;
begin
  SockObj := Nil;
  try
    if Assigned(FOnCreateChannel) then
      FOnCreateChannel(Context, Socket, Addr, FReactor, SockObj);
  except
    on E: Exception do
          begin
            DoLogMessage(E.Message);
            SockObj := Nil;
          end;
  end;
  if not Assigned(SockObj) then
    SockObj := TDnTcpChannel.Create(FReactor, Socket, Addr);

  Result := SockObj;
end;

procedure TDnTcpListener.DoClientConnect(Context: TDnThreadContext; Channel: TDnTcpChannel);
begin
  if Assigned(FOnClientConnect) then
  try
    FOnClientConnect(Context, Channel);
  except
    on E: Exception do
      DoLogMessage(E.Message);
  end;
end;

function TDnTcpListener.TurnOff: Boolean;
var Sock: TSocket;
begin
  FActive := False;
  if FSocket <> INVALID_SOCKET then
  begin
    Sock := FSocket; FSocket := INVALID_SOCKET;
    Winsock2.Shutdown(Sock, SD_BOTH); //yes, I known that SD_BOTH is bad idea... But this is LISTENING socket :)
    Winsock2.CloseSocket(Sock);
  end;
  Result := False;
end;

procedure TDnTcpListener.SetAddress(Address: AnsiString);
var addr: Cardinal;
begin
  addr := inet_addr(PAnsiChar(Address));
  if addr <> INADDR_NONE then
  begin
    FAddress := Address;
  end;
end;



//------------------------------------------------------------------------------



procedure Register;
begin
  {$IFDEF ROOTISCOMPONENT}
  RegisterComponents('DNet', [TDnTcpListener]);
  {$ENDIF}
end;

end.
