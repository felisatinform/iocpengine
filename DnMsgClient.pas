{$I DnConfig.inc}
unit DnMsgClient;
interface
uses Classes, contnrs, SyncObjs, SysUtils,
      Winsock2, Windows, Math,
      DnMsgClientInfo, DnRtl;


const
  ClientTempStorageSize = 8192;
  MaxMessageSize = 1024 * 1024 * 10; //10Mb

type
  TOnClientErrorEvent = procedure (Sender: TObject; ErrorMessage: AnsiString) of object;
  TOnClientDataReceivedEvent = procedure (Sender: TObject; Stream: TStream) of object;
  TOnClientStreamSentEvent = procedure (Sender: TObject; Stream: TStream) of object;
  TOnClientAuthResultEvent = procedure (Sender: TObject; Res: Boolean; const Msg: AnsiString) of object;
  TOnClientListOfClientsEvent = procedure (Sender: TObject; ClientList: TObjectList) of object;


  TCommonMsgClientHandler = class;

  TCommonMsgClientState = (cmIdle, cmResolving, cmConnecting, cmOperable, cmDisconnecting);

  TStreamInfo = class
  protected
    FStream: TStream;
    FType: Word;
  public
    constructor Create(AStream: TStream; AType: Word);
    destructor Destroy; override;

    property Stream: TStream read FStream write FStream;
    property _Type: Word read FType write FType;
  end;

  TEventType = (etConnect, etDisconnect, etError, etReceiveData, etStreamSent, etClientList, etAuthResult);

  TEventInfo = class
  protected
    FStream: TStream;
    FType: TEventType;
    FClientList: TObjectList;
    FAuthResult: Boolean;
    FAuthMsg: AnsiString;

  public
    constructor Create;
    destructor Destroy; override;

    property _Type: TEventType read FType write FType;
    property Stream: TStream read FStream write FStream;
    property ClientList: TObjectList read FClientList write FClientList;
    property AuthResult: Boolean read FAuthResult write FAuthResult;
    property AuthMsg: AnsiString read FAuthMsg write FAuthMsg;
  end;


{$IFDEF USECONNECTFIBER}
  TCommonMsgClientAggregator = class;
{$ENDIF}

{$IFDEF ROOTISCOMPONENT}
  TCommonMsgClient = class(TComponent)
{$ELSE}
  TCommonMsgClient = class
{$ENDIF}
  protected
    FPort: Word;
    FHost: AnsiString;
    FID: AnsiString;
    FPassword: AnsiString;
    FUser: AnsiString;
    FVersion: AnsiString;
    FActive: Boolean;
    FHandshake: Boolean;
    FHeartbeatInterval: Cardinal;
    FGuard: TCriticalSection;
    FEventGuard: TCriticalSection;
    FStreamList: TObjectList;
    FThread: TCommonMsgClientHandler;
    FSocket: TSocket;
    FThreadFinished,
    FClientListArrived: TEvent;
    FState: TCommonMsgClientState;
    FSocketSignal: TEvent;
    FStateSignal: TEvent;
{$IFDEF USECONNECTFIBER}
    FAggregator: TCommonMsgClientAggregator;
{$ENDIF}
    FTempStorage,
    FWriteTempStorage,
    FHeaderData,
    FParsedData: PAnsiChar;

    FOnConnected: TNotifyEvent;
    FOnDisconnected: TNotifyEvent;
    FOnStreamSent: TOnClientStreamSentEvent;
    FOnAuthResult: TOnClientAuthResultEvent;
    FOnClientList: TOnClientListOfClientsEvent;
    FOnError: TOnClientErrorEvent;
    FOnDataReceived: TOnClientDataReceivedEvent;
    FLastSent: Double;
    FMarshallWindow: HWND;
    FMarshallMsg: Integer;
    FEventList: TObjectList;
    FDataSignal: THandle;

    procedure SetActive(AValue: Boolean);
    procedure PostClientConnect;
    procedure DoClientConnect;
    procedure PostClientDisconnect;
    procedure DoClientDisconnect;
    procedure PostClientError(Msg: AnsiString);
    procedure DoClientError(Msg: AnsiString);
    procedure PostClientListData(ClientList: TObjectList);
    procedure DoClientListData(ClientList: TObjectList);
    procedure PostAuthResult(R: Boolean; Data: RawByteString);
    procedure DoAuthResult(R: Boolean; Data: RawByteString);
    procedure PostClientData(Stream: TStream);
    procedure DoClientData(Stream: TStream);
    procedure DoStreamSent(Stream: TStream);
    procedure QueueEvent(EI: TEventInfo);
    procedure DestroySocket;
    procedure CreateSocket;

    procedure PostStreamSent(SI: TStreamInfo);
    function  PopStreamForSending: TStreamInfo;
    procedure DeleteStream(SI: TStreamInfo);
    procedure PostHandshakeRequest;
    procedure PostHeartbeatMsg;

  public
{$IFDEF ROOTISCOMPONENT}
    constructor Create(AOwner: TComponent); override;
{$ELSE}
    constructor Create;
{$ENDIF}
    destructor Destroy; override;
    procedure Init;

    // The application developer should call this method
    // If uses the marshalling of events to main thread
    procedure ProcessEvents;

    // Initiates connecting to specified Host:Port server
    procedure Connect;

    // Disconnects
    procedure Disconnect;

    // Initiates stream sending to server
    procedure SendStream(AStream: TStream);

    // Initiates string sending to server
    procedure SendString(AValue: AnsiString; AType: Word = 0);

    // Fetches the list of clients from server
    procedure GetClientsListFromServer;

    // Waits for client disconnection
    function WaitForDisconnect(Timeout: Cardinal): Boolean;

    // Waits for client list from server
    function WaitForClientList(Timeout: Cardinal): Boolean;

    // Properties
{$IFDEF USECONNECTFIBER}
    property Aggregator: TCommonMsgClientAggregator read FAggregator write FAggregator;
{$ENDIF}
    // Property for use in mass tests
    property LastSent: Double read FLastSent write FLastSent;

    property Port: Word read FPort write FPort;
    property Host: AnsiString read FHost write FHost;

    property ID: AnsiString read FID write FID;
    property User: AnsiString read FUser write FUser;
    property Password: AnsiString read FPassword write FPassword;
    property Version: AnsiString read FVersion write FVersion;

    property Active: Boolean read FActive write SetActive;

    // Events
    property OnConnected: TNotifyEvent read FOnConnected write FOnConnected;
    property OnDisconnected: TNotifyEvent read FOnDisconnected write FOnDisconnected;

    // This event happens when stream specified in SendStream written to socket fully.
    property OnStreamSent: TOnClientStreamSentEvent read FOnStreamSent write FOnStreamSent;


    property OnError: TOnClientErrorEvent read FOnError write FOnError;

    // This event happens on receiving the message from server.
    // Please be aware - the corresponding stream object will be freed on exit from
    // handler.
    property OnDataReceived: TOnClientDataReceivedEvent read FOnDataReceived write FOnDataReceived;

    // This event happens if Handshake property is set to true.
    // Its parameters informs the developer about server authentication result.
    // If it failed - OnError event happens also.
    property OnAuthResult: TOnClientAuthResultEvent read FOnAuthResult write FOnAuthResult;

    // This event raises on receiving of list of connected clients from server.
    // Please be aware - the ClientList object will be freed on exit from handler.
    // This list represents the collection of TMsgClientInfo objects
    property OnClientList: TOnClientListOfClientsEvent read FOnClientList write FOnClientList;

    // It determines if user data are sent to server and authentication handlers
    // called on both server and client sides.
    property Handshake: Boolean read FHandshake write FHandshake;

    // It is heartbeat messages interval.
    // If there is no new messages in send queue - the new heartbeat message will be posted
    // each HeartbeatInterval/2 seconds. So server will be happy and not detect the
    // disconnection.
    // The nonzero value also causes to check the receiving stream for timeout like server it
    // does. So it unexpected server shutdown will be handled in proper way.
    property HeartbeatInterval: Cardinal read FHeartbeatInterval write FHeartbeatInterval;

    // It sets the window handle used for optional event marshalling
    property MarshallWindow: HWND read FMarshallWindow write FMarshallWindow;
    property MarshallMsg: Integer read FMarshallMsg write FMarshallMsg;
  end;

  TClientReadStage = (crHeader, crBody, crReadAll);
  // The message header structure. Every message include this header.

  TMsgHeader = packed record
    MsgLen: Cardinal;
    MsgType: Word;
  end;

  TCommonMsgClientHandler = class(TThread)
  protected
    // Pointer to owner TCommonMsgClient
    FClient: TCommonMsgClient;
    FCanWrite: Boolean;

    //the remote peer IP address
    FSockAddr: TSockAddrIn;

    //the temporary storage for send operation
    FWriteTempStorage,

    //the temporary storage for recv operation
    FTempStorage,

    //the temporary storage for parsing received data
    FParsedData,

    //the temporary buffer for parsing header
    FHeaderData: PAnsiChar;

    //the message receiving stage - header or body
    FReadStage: TClientReadStage;

    //Winsock's buffer description
    FWSABuf: WSABuf;

    //the amount of bytes written during last WSASend
    FWritten,

    //the amount of bytes in write temp storage
    FToSend,

    //the amount of bytes read to FTempStorage
    FRecvd,

    // The received message body
    FBodyParsed: Cardinal;

    // Stream that is sending now
    FStreamInfo: TStreamInfo;

    //the header for current receiving message
    FRecvHeader: TMsgHeader;
    FHeaderRead: Integer;

    // The time of last received message
    FLastHeartbeat,

    // Timestamp of last sent data
    FLastSentHeartbeat: Double;

    //File stream for logging
    FLog: TFileStream;

    FClientList: TObjectList;

    // Socket was connected ok
    FWasConnected: Boolean;

    procedure LogMsg(S: AnsiString);
    function  InternalConnect: Cardinal;

    // Handles the logic in cmResolving state - it resolves host name to IP
    procedure HandleResolving;
    procedure HandleConnecting;
    procedure HandleDisconnecting;
    procedure HandleOperable;
    procedure HandleIdle;

    // Handles the login in cmConnecting stage - it checks the result of WSAConnect and raises error if neccessary
    procedure HandleConnected(ErrorCode: Integer);

    // Handle the socket ready to write
    procedure HandleWrite(ErrorCode: Cardinal);

    // Handle the socket ready to read
    procedure HandleRead(ErrorCode: Cardinal);

    // Handle when socket signal is returned in exceptfds set
    procedure HandleError;

    // Initiates new WSARecv to read remaining data from closing socket.
    // But it may fail - the False will be returned for this case.
    function InternalRead: Boolean;

    // Checks the result of WSARecv and handles them
    procedure InternalReadFinish(ErrorCode: Integer);

    // Initiates graceful socket close
    procedure InternalClose;


    procedure ProcessHandshakeData(S: PAnsiChar; Len: Cardinal);  //handshake response
    procedure ProcessClientListData(S: PAnsiChar; Len: Cardinal; Final: Boolean); //client list
    procedure ProcessClientData(S: PAnsiChar; Len: Cardinal);
    procedure DoHeartbeatData(S: PAnsiChar);  //heartbeat response

    procedure ParseData(WasRead: Integer);
    procedure DoHandlers(S: PAnsiChar);
    procedure InternalDisconnect;

{$IFNDEF USECONNECTFIBER}
    procedure Execute; override;
    procedure Stop;
{$ELSE}
    procedure Terminate;
    property Terminated: Boolean read FTerminated write FTerminated;
{$ENDIF}
    procedure InternalExecute;
    procedure InternalFinish;
    procedure BindSocketToEvents;

  public
    constructor Create(Client: TCommonMsgClient);
    destructor Destroy; override;
  end;

{$IFDEF USECONNECTFIBER}
  TCommonMsgClientAggregator = class(TThread)
  private
    FThreadList: TObjectList;
    FGuard: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    function  AllocFiber(Client: TCommonMsgClient): TCommonMsgClientHandler;
    procedure Execute; override;
  end;
{$ENDIF}

{$ifdef Debug_IOCP}
procedure Setup;

procedure Teardown;
{$endif}

implementation

{$ifdef Debug_IOCP}
uses
   logging
  ,logSupport
  ;

var
 log : TabsLog;

{$endif}

const
  WAIT_OBJECT_1 = WAIT_OBJECT_0+1;
  WAIT_OBJECT_2 = WAIT_OBJECT_0+2;

constructor TStreamInfo.Create(AStream: TStream; AType: Word);
begin
  inherited Create;
  FStream := AStream;
  FType := AType;
  // OutputDebugString('TStreamInfo.Create');
end;

destructor TStreamInfo.Destroy;
begin
  // OutputDebugString('TStreamInfo.Destroy');
  FreeAndNil(FStream);
  inherited Destroy;
end;

constructor TEventInfo.Create;
begin
  inherited Create;
end;

destructor TEventInfo.Destroy;
var Msg: String;
begin
  //OutputDebugString(PChar('TEventInfo.Destroy for type ' + IntToStr(Ord(FType))));
  {$ifdef Debug_IOCP}
  Log.LogDebug('TEventInfo.Destroy for type ' + IntToStr(Ord(FType)));
  {$endif}
  if FClientList <> Nil then
    FreeAndNil(FClientList);
  if FStream <> Nil then
  begin
    (*Msg := 'Free stream with size ' + IntToStr(FStream.Size);
    OutputDebugString(PChar(Msg));*)
    FreeAndNil(FStream);
  end;
  inherited Destroy;
end;

{$IFDEF ROOTISCOMPONENT}

constructor TCommonMsgClient.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Init;
end;

{$ELSE}

constructor TCommonMsgClient.Create;
begin
  inherited Create;
  Init;
end;
{$ENDIF}

destructor TCommonMsgClient.Destroy;
begin
  Disconnect;

  // Stop thread
  FGuard.Enter;
  try
    if Assigned(FThread) then
    begin
      FThread.Terminate;
      FStateSignal.SetEvent;
      FThread.WaitFor;
      FreeAndNil(FThread);
    end;
    FActive := False;
  finally
    FGuard.Leave;
  end;

  FreeAndNil(FEventList);
  FreeAndNil(FClientListArrived);
  FreeAndNil(FThreadFinished);
  Windows.CloseHandle(FDataSignal);
  FreeAndNil(FSocketSignal);
  FreeAndNil(FStateSignal);
  FreeAndNil(FStreamList);
  FreeAndNil(FGuard);
  FreeAndNil(FEventGuard);
  FreeMem(FParsedData);
  FreeMem(FWriteTempStorage);
  FreeMem(FHeaderData);
  FreeMem(FTempStorage);
  if FSocket <> INVALID_SOCKET then
    DestroySocket();
    
  Winsock2.WSACleanup();
  inherited Destroy;
end;

procedure TCommonMsgClient.Init;
var WSAData: Winsock2.TWSAData;
begin
  // Load Winsock libraries
  Winsock2.WSAStartup(MakeWord(2,0), WSAData);

  FGuard := TCriticalSection.Create;
  FEventGuard := TCriticalSection.Create;
  FStreamList := TObjectList.Create(True);
  FDataSignal := Windows.CreateSemaphore(Nil, 0, $7FFFFFFF, Nil);
  FThreadFinished := TEvent.Create(Nil, False, False, '');
  FClientListArrived := TEvent.Create(Nil, False, False, '');
  FEventList := TObjectList.Create(True);
  //FMarshallMsg := Windows.WM_USER + 100;
  FMarshallWindow := 0;
  FState := cmIdle;
  FSocket := Winsock2.INVALID_SOCKET;
  {$IFDEF USECONNECTFIBER}
  FLastSent := 0;
{$ENDIF}
  GetMem(FTempStorage, ClientTempStorageSize);
  GetMem(FWriteTempStorage, ClientTempStorageSize);
  GetMem(FHeaderData, sizeof(TMsgHeader));
  GetMem(FParsedData, MaxMessageSize);
  FSocketSignal := TEvent.Create(Nil, False, False, '');
  FStateSignal := TEvent.Create(nil, False, False, '');
end;

procedure TCommonMsgClient.SetActive(AValue: Boolean);
begin
  if FActive <> AValue then
  begin
    if FActive then
      Disconnect
    else
      Connect;
  end;
end;

procedure TCommonMsgClient.ProcessEvents;
var EventInfo: TEventInfo;
begin
  EventInfo := Nil;

  FEventGuard.Enter;
  try
    while FEventList.Count > 0 do
    begin
      try
        //get event list
        EventInfo := FEventList.Extract(FEventList[0]) as TEventInfo;
        FEventGuard.Leave;
        
       {$ifndef Debug_IOCP}
        case EventInfo._Type of
          etConnect:      begin (*OutputDebugString('Client connect.'); *) DoClientConnect; end;
          etDisconnect:   begin (*OutputDebugString('Client disconnect.'); *)DoClientDisconnect; end;
          etReceiveData:  begin (* OutputDebugString('Receive data.'); *) DoClientData(EventInfo.Stream); end;
          etStreamSent:   begin (* OutputDebugString('Stream sent.'); *) DoStreamSent(EventInfo.Stream); end;
          etError:        begin (* OutputDebugString('Client error.'); *) DoClientError(EventInfo.AuthMsg); end;
          etClientList:   begin (* OutputDebugString('Client list.'); *) DoClientListData(EventInfo.ClientList); end;
          etAuthResult:   begin (* OutputDebugString('Auth result.'); *)DoAuthResult(EventInfo.AuthResult, EventInfo.AuthMsg); end;
        end;
       {$else}
        case EventInfo._Type of
          etConnect:      begin Log.LogDebug('Client connect.');  DoClientConnect; end;
          etDisconnect:   begin Log.LogDebug('Client disconnect.'); DoClientDisconnect; end;
          etReceiveData:  begin Log.LogDebug('Receive data.');  DoClientData(EventInfo.Stream); end;
          etStreamSent:   begin Log.LogDebug('Stream sent.');  DoStreamSent(EventInfo.Stream); end;
          etError:        begin Log.LogDebug('Client error.');  DoClientError(EventInfo.AuthMsg); end;
          etClientList:   begin Log.LogDebug('Client list.');  DoClientListData(EventInfo.ClientList); end;
          etAuthResult:   begin Log.LogDebug('Auth result.'); DoAuthResult(EventInfo.AuthResult, EventInfo.AuthMsg); end;
        end;
       {$endif}
      except
      end;

      EventInfo.Free;
      FEventGuard.Enter;
    end;
  except
    FEventGuard.Enter;
  end;
  FEventGuard.Leave;
end;


procedure TCommonMsgClient.Connect;
begin
  // Mark component as active
  FActive := True;

  // Signal to thread
  FStateSignal.SetEvent;

  if not Assigned(FThread) then
    FThread := TCommonMsgClientHandler.Create(Self);
end;

procedure TCommonMsgClient.Disconnect;
begin
  // Signal thread to close existing connection
  FActive := False;
  FStateSignal.SetEvent;
end;

procedure TCommonMsgClient.SendStream(AStream: TStream);
var Msg: String;
begin
  FGuard.Enter;
  try
    (*Msg := 'Sending stream with size ' + IntToStr(AStream.Size);
    OutputDebugString(PChar(Msg));*)
    FStreamList.Add(TStreamInfo.Create(AStream, 0));
    ReleaseSemaphore(FDataSignal, 1, Nil);
  finally
    FGuard.Leave;
  end;
end;

procedure TCommonMsgClient.SendString(AValue: AnsiString; AType: Word = 0);
var MS: TMemoryStream;
    Msg: String;
begin
  MS := TMemoryStream.Create;
  MS.Write(AValue[1], Length(AValue)); MS.Position := 0;
  (*Msg := 'Sending stream with size ' + IntToStr(MS.Size);
  OutputDebugString(PChar(Msg));*)

  FGuard.Enter;
  try
    FStreamList.Add(TStreamInfo.Create(MS, AType));
    ReleaseSemaphore(FDataSignal, 1, Nil);
  finally
    FGuard.Leave;
  end;
end;

procedure TCommonMsgClient.GetClientsListFromServer;
begin
  SendString('', 2);
end;

// Waits for client disconnection
function TCommonMsgClient.WaitForDisconnect(Timeout: Cardinal): Boolean;
begin
  Result := Self.FThreadFinished.WaitFor(Timeout) = wrSignaled;
end;

function TCommonMsgClient.WaitForClientList(Timeout: Cardinal): Boolean;
begin
  Result := Self.FClientListArrived.WaitFor(Timeout) = wrSignaled;
end;

procedure TCommonMsgClient.PostStreamSent(SI: TStreamInfo);
var EI: TEventInfo;
    Stream: TStream;
    ResCode: Integer;
    Msg: String;
begin
  FGuard.Enter;
  try
    //ResCode := FStreamList.Remove(SI);

    // Detach stream from StreamInfo object
    Stream := SI.Stream;
    SI.Stream := Nil;

    // Remove StreamInfo object
    FStreamList.Remove(SI);

    // Post event
    if FMarshallWindow <> 0 then
    begin
      EI := TEventInfo.Create;
      EI._Type := etStreamSent;
      EI.Stream := Stream;
      QueueEvent(EI);
    end
    else
    begin
      DoStreamSent(Stream);
      (*Msg := 'Free stream with size ' + IntToStr(Stream.Size);
      OutputDebugString(PChar(Msg));*)
      FreeAndNil(Stream);
    end;
  finally
    FGuard.Leave;
  end;
end;

procedure TCommonMsgClient.DoStreamSent(Stream: TStream);
begin
  if Assigned(FOnStreamSent) then
  try
    FOnStreamSent(Self, Stream);
  except
  end;
end;

procedure TCommonMsgClient.PostClientConnect;
var EI: TEventInfo;
begin
  if FMarshallWindow <> 0 then
  begin
    EI := TEventInfo.Create; EI._Type := etConnect;
    QueueEvent(EI);
  end
  else
    DoClientConnect;
end;

procedure TCommonMsgClient.DoClientConnect;
begin
  if Assigned(FOnConnected) then
  try
    FOnConnected(Self);
  except
  end;
end;

procedure TCommonMsgClient.PostClientDisconnect;
var EI: TEventInfo;
begin
  if FMarshallWindow <> 0 then
  begin
    EI := TEventInfo.Create; EI._Type := etDisconnect;
    QueueEvent(EI);
  end
  else
    DoClientDisconnect();
end;

procedure TCommonMsgClient.DoClientDisconnect;
begin
  if Assigned(FOnDisconnected) then
  try
    FOnDisconnected(Self);
  except
  end;
end;

procedure TCommonMsgClient.PostClientError(Msg: AnsiString);
var EI: TEventInfo;
begin
  if FMarshallWindow <> 0 then
  begin
    EI := TEventInfo.Create;
    EI._Type := etError; EI.AuthMsg := Msg;
    QueueEvent(EI);
  end
  else
    DoClientError(Msg);
end;

procedure TCommonMsgClient.DoClientError(Msg: AnsiString);
begin
  if Assigned(FOnError) then
  try
    FOnError(Self, Msg);
  except
  end;
end;

procedure TCommonMsgClient.PostAuthResult(R: Boolean; Data: RawByteString);
var EI: TEventInfo;
begin
  if FMarshallWindow <> 0 then
  begin
    EI := TEventInfo.Create;
    EI._Type := etAuthResult; EI.AuthResult := R; EI.AuthMsg := Data;
    QueueEvent(EI);
  end
  else
    DoAuthResult(R, Data);
end;

procedure TCommonMsgClient.DoAuthResult(R: Boolean; Data: RawByteString);
begin
  if Assigned(FOnAuthResult) then
  try
    FOnAuthResult(Self, R, Data);
  except
  end;
end;

procedure TCommonMsgClient.PostClientData(Stream: TStream);
var EI: TEventInfo;
begin
  if FMarshallWindow <> 0 then
  begin
    EI := TEventInfo.Create;
    EI._Type := etReceiveData; EI.Stream := Stream;
    QueueEvent(EI);
  end
  else
  begin
    DoClientData(Stream);
    if Stream <> Nil then
      Stream.Free;
  end;
end;

procedure TCommonMsgClient.DoClientData(Stream: TStream);
begin
  if Assigned(FOnDataReceived) then
  try
    FOnDataReceived(Self, Stream);
  except
  end;
end;


procedure TCommonMsgClient.PostClientListData(ClientList: TObjectList);
var EI: TEventInfo;
begin
  if FMarshallWindow <> 0 then
  begin
    EI := TEventInfo.Create;
    EI._Type := etClientList; EI.ClientList := ClientList;
    QueueEvent(EI);
  end
  else
  begin
    DoClientListData(ClientList);
    ClientList.Free;
  end;
end;

procedure TCommonMsgClient.DoClientListData(ClientList: TObjectList);
begin
  if Assigned(FOnClientList) then
  try
    FOnClientList(Self, ClientList);
  finally
  end;
end;

procedure TCommonMsgClient.QueueEvent(EI: TEventInfo);
begin
  FEventGuard.Enter;
  try
    FEventList.Add(EI);
  finally
    FEventGuard.Leave;
  end;
  Windows.PostMessage(FMarshallWindow, FMarshallMsg, Integer(Pointer(Self)), 0);
end;

procedure TCommonMsgClient.DestroySocket;
begin
  if FSocket <> Winsock2.INVALID_SOCKET then
  begin
    Winsock2.shutdown(FSocket, 2);
    Winsock2.closesocket(FSocket);
    FSocket := Winsock2.INVALID_SOCKET;
  end;
end;

procedure TCommonMsgClient.CreateSocket;
var NonBlock: Cardinal;
begin
  // Create socket
  FSocket := Winsock2.WSASocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, Nil, 0, 0);
  if FSocket = INVALID_SOCKET then
    raise Exception.Create(Format('Cannot create the socket. Error code is %u', [Winsock2.WSAGetLastError()]));

  FSocketSignal.ResetEvent;

  // Put to WSAWait state
  if Winsock2.WSAEventSelect(FSocket, FSocketSignal.Handle, FD_CONNECT) = SOCKET_ERROR then
    raise Exception.Create(Format('Cannot associate socket with event. Error code is %u', [Winsock2.WSAGetLastError()]));
end;

function TCommonMsgClient.PopStreamForSending: TStreamInfo;
begin
  Result := Nil;
  FGuard.Enter;
  try
    if FStreamList.Count > 0 then
      Result := FStreamList[0] as TStreamInfo;
  finally
    FGuard.Leave;
  end;
end;

procedure  TCommonMsgClient.DeleteStream(SI: TStreamInfo);
begin
  FGuard.Enter;
  try
    FStreamList.Remove(SI);
  finally
    FGuard.Leave;
  end;
end;

procedure TCommonMsgClient.PostHandshakeRequest;
var MS: TMemoryStream;
    CI: TMsgClientInfo;
    S: RawByteString;
begin
  MS := TMemoryStream.Create;
  CI := TMsgClientInfo.Create;
  CI.ID := FID;
  CI.User := FUser;
  CI.Password := FPassword;
  CI.Version := FVersion;
  S := CI.SerializeTo;
  MS.Write(S[1], Length(S));
  MS.Position := 0;
  FGuard.Enter;
  try
    FStreamList.Add(TStreamInfo.Create(MS, 1));
    ReleaseSemaphore(FDataSignal, 1, Nil);
  finally
    FGuard.Leave;
    FreeAndNil(CI);
  end;

end;

//----------------------------- TCommonMsgClientThread ------------------
{$IFDEF USECONNECTFIBER}
constructor TCommonMsgClientHandler.Create(Client: TCommonMsgClient);
begin
  inherited Create;
{$ELSE}
constructor TCommonMsgClientHandler.Create(Client: TCommonMsgClient);
begin
  inherited Create(True);
{$ENDIF}
  FClient := Client;
  FClientList := TObjectList.Create(True);
  FTempStorage := FClient.FTempStorage;
  FWriteTempStorage := FClient.FWriteTempStorage;
  FHeaderData := FClient.FHeaderData;
  FParsedData := FClient.FParsedData;

{$IFNDEF USECONNECTFIBER}
  Resume;
{$ENDIF}
end;


destructor TCommonMsgClientHandler.Destroy;
begin
  //FreeAndNil(FStreamInfo);
  FreeAndNil(FClientList);
{$IFNDEF USECONNECTFIBER}
  FreeAndNil(FLog);
{$ENDIF}

  inherited Destroy;
end;

function TCommonMsgClientHandler.InternalConnect: Cardinal;
begin
  Result := Winsock2.connect(FClient.FSocket, @FSockAddr, sizeof(FSockAddr));
end;

procedure TCommonMsgClientHandler.InternalExecute;
begin
  if FClient.FActive and (FClient.FState = cmIdle) then
    FClient.FState := cmResolving
  else
  if not FClient.FActive and (FClient.FState <> cmIdle) then
    FClient.FState := cmDisconnecting;

  case FClient.FState of
    cmResolving:        HandleResolving();
    cmConnecting:       HandleConnecting();
    cmDisconnecting:    HandleDisconnecting();
    cmIdle:             HandleIdle();
    cmOperable:         HandleOperable();
  end;
end;

procedure TCommonMsgClientHandler.InternalFinish;
begin
  FClient.FActive := False;
  if FClient.FState > cmConnecting then
    InternalDisconnect;
end;

procedure TCommonMsgClientHandler.BindSocketToEvents;
begin
  if Assigned(FStreamInfo) and not FCanWrite then
    WSAEventSelect(FClient.FSocket, FClient.FSocketSignal.Handle, FD_READ + FD_WRITE + FD_CLOSE)
  else
    WSAEventSelect(FClient.FSocket, FClient.FSocketSignal.Handle, FD_READ + FD_CLOSE);
end;

{$IFNDEF USECONNECTFIBER}
procedure TCommonMsgClientHandler.Execute;
begin

  while not Terminated do
    InternalExecute;

  InternalFinish;
end;

procedure TCommonMsgClientHandler.Stop;
begin
  Terminate;
end;
{$ENDIF}

procedure TCommonMsgClientHandler.HandleResolving;
var HostEnt: Winsock2.PHostEnt;
    ResCode: Integer;
    PA: PAnsiChar;
begin
  // Try to convert to IP address

  // Zero all bytes of IP address
  Fillchar(FSockAddr, sizeof(FSockAddr), 0);

  FSockAddr.sin_family := Winsock2.AF_INET;
  FSockAddr.sin_port := Winsock2.htons(FClient.Port);

  // Try to convert
  FSockAddr.sin_addr.S_addr := Winsock2.inet_addr(PAnsiChar(FClient.FHost));
  if FSockAddr.sin_addr.S_addr = INADDR_NONE then
  begin //lookup need
    HostEnt := Winsock2.GetHostByName(PAnsiChar(FClient.FHost));
    if HostEnt <> Nil then
    begin
      if HostEnt^.h_addrtype = AF_INET then
      begin
        //copy resulting IP address
        PA := PAnsiChar(HostEnt^.h_addr_list^);
        FSockAddr.sin_addr.S_un_b.s_b1 := Ord(pa[0]);
        FSockAddr.sin_addr.S_un_b.s_b2 := Ord(pa[1]);
        FSockAddr.sin_addr.S_un_b.s_b3 := Ord(pa[2]);
        FSockAddr.sin_addr.S_un_b.s_b4 := Ord(pa[3]);
      end;
    end;
  end;

  if FSockAddr.sin_addr.S_addr = INADDR_NONE then
  begin
    // Signal about error and exit from thread
    FClient.PostClientError('Cannot resolve host address.');

    // Switch to disconnect stage
    FClient.FState := cmDisconnecting;
  end
  else
  begin
    // Transition to connecting state
    FClient.FState := cmConnecting;

    // Initialize connecting
    if FClient.FSocket = INVALID_SOCKET then
      FClient.CreateSocket;

    ResCode := InternalConnect;

    // Check for result code
    if ResCode = SOCKET_ERROR then
    begin
      ResCode := Winsock2.WSAGetLastError();
      if ResCode <> WSAEWOULDBLOCK then
        FClient.PostClientError(AnsiString(Format('Cannot connect. Result code is %u', [ResCode])));
    end;
  end;
end;

procedure TCommonMsgClientHandler.HandleConnecting;
var Signals: array[0..1] of Cardinal;
    ResCode, Timeout: Cardinal;
    Events: TWSANetworkEvents;
begin
  Signals[0] := FClient.FStateSignal.Handle;
  Signals[1] := FClient.FSocketSignal.Handle;
  if FClient.HeartbeatInterval > 0 then
    Timeout := FClient.HeartbeatInterval * 1000
  else
    Timeout := Windows.INFINITE;

  ResCode := WaitForMultipleObjects(2, @Signals, False, Timeout);
  case ResCode of
    WAIT_OBJECT_0:    exit;
    WAIT_OBJECT_1:    begin
                        // Check network events
                        WSAEnumNetworkEvents(FClient.FSocket, FClient.FSocketSignal.Handle, @Events);
                        HandleConnected(Events.iErrorCode[FD_CONNECT_BIT]);
                      end;

    WAIT_TIMEOUT:     HandleConnected(WSAETIMEDOUT);
  end;
end;

procedure TCommonMsgClientHandler.HandleDisconnecting;
begin
  if (FClient.FSocket <> INVALID_SOCKET) and FWasConnected then
    Winsock2.shutdown(FClient.FSocket, 2);
  InternalDisconnect;
end;

procedure TCommonMsgClientHandler.HandleIdle;
begin
  WaitForSingleObject(FClient.FStateSignal.Handle, INFINITE);
end;

procedure TCommonMsgClientHandler.HandleOperable;
var
  ResCode, Interval: Cardinal; ErrCode, ErrCodeSize: Integer;
  SignalArray: array[0..2] of THandle;
  Events: TWSANetworkEvents;
begin
  // Prepare array of events
  SignalArray[0] := FClient.FStateSignal.Handle;   // Change thread state
  SignalArray[1] := FClient.FSocketSignal.Handle;  // I/O event
  SignalArray[2] := FClient.FDataSignal;            // New data signal

  // Find timeout value
  if FClient.FHeartbeatInterval <> 0 then
    Interval := Trunc(FClient.FHeartbeatInterval * 1000 / 3)
  else
    Interval := INFINITE;


  ResCode := $FFFFFFFF;
  if not Assigned(FStreamInfo) and (FClient.FStreamList.Count = 0) then
  begin
    // No data to send now -> so check for FDataSignal too.
    //OutputDebugString('WFMO_1');
    ResCode := Windows.WaitForMultipleObjects(3, @SignalArray, False, Interval);
  end
  else
  if not FCanWrite then
  begin
    // We have data to send now, and we couldnt send in previous attempt
    ResCode := Windows.WaitForMultipleObjects(2, @SignalArray, False, Interval)
  end
  else
  begin
    // There is data to write, so we just check if stop signal is signalled
    ResCode := Windows.WaitForSingleObject(FClient.FStateSignal.Handle, 0); // Check for
  end;

  case ResCode of
    WAIT_OBJECT_0:      exit; // State is changed
    WAIT_OBJECT_1:      begin // Smth new on socket
                          // Check network events
                          WSAEnumNetworkEvents(FClient.FSocket, FClient.FSocketSignal.Handle, @Events);
                          if (Events.lNetworkEvents and FD_READ) <> 0 then
                            HandleRead(Events.iErrorCode[FD_READ_BIT]); // Now we can read from socket

                          FCanWrite := FCanWrite or ((Events.lNetworkEvents and FD_WRITE) <> 0);

                          if FCanWrite then
                            HandleWrite(Events.iErrorCode[FD_WRITE_BIT]); // Now we can write to socket

                          // Connection is closing ?
                          if (Events.lNetworkEvents and FD_CLOSE) <> 0 then
                            FClient.FState := cmDisconnecting;
                        end;

    WAIT_OBJECT_2:      begin // Outgoing data in queue
                          // Get next stream for sending
                          FStreamInfo := FClient.PopStreamForSending;

                          // Prepare receive FD_WRITE notifications
                          BindSocketToEvents();
                        end;

    WAIT_TIMEOUT:       begin
                          if (Assigned(FStreamInfo) or (FClient.FStreamList.Count <> 0)) and FCanWrite then
                            HandleWrite(0)
                          else
                          if FClient.FHeartbeatInterval > 0 then
                          begin
                            if (Now - FLastHeartbeat) * 86400 > FClient.FHeartbeatInterval then
                              FClient.PostClientError('I/O timeouted')
                            else
                              FClient.PostHeartbeatMsg();
                          end;
                        end;
  end;
end;

procedure TCommonMsgClientHandler.HandleConnected(ErrorCode: Integer);
var i: Integer;
begin
  if ErrorCode <> 0 then
  begin
    FClient.PostClientError(AnsiString(Format('Cannot connect to server due to network error %u', [ErrorCode])));
    FClient.FState := cmDisconnecting;
  end
  else
  begin
    FWasConnected := True;

    BindSocketToEvents();

    // Save the time of connection
    FLastSentHeartbeat := Now;

    if FClient.FHandshake then
      FClient.PostHandshakeRequest;

    // Post Connected event
    FClient.PostClientConnect;

    // Save the time of connection
    FLastHeartbeat := Now;

    // Transition to cmOperable state
    FCanWrite := True;
    FClient.FState := cmOperable;
  end;
end;

procedure TCommonMsgClientHandler.InternalDisconnect;
begin
  //if FWasConnected then
  begin
    FClient.DestroySocket;
    FWasConnected := False;
  end;

  FClient.FState := cmIdle;
  FClient.FActive := False;
  FClient.PostClientDisconnect;
end;


function TCommonMsgClientHandler.InternalRead: Boolean;
var ResCode: Integer;
begin
  Result := True;

  // Assign WSA buffers
  FWSABuf.buf := @FTempStorage[1]; FWSABuf.len := ClientTempStorageSize;

  // Try to read
  ResCode := Winsock2.recv(FClient.FSocket, FTempStorage[1], ClientTempStorageSize, 0);

  // Check for errors
  if ResCode = SOCKET_ERROR then
  begin
    ResCode := Winsock2.WSAGetLastError();
    if ResCode <> WSAEWOULDBLOCK then
    begin
      if FReadStage = crReadAll then
        Result := False
      else
        FClient.PostClientError(AnsiString(Format('WSARecv failed. Error code is %u', [ResCode])));
    end;
  end;
end;

procedure TCommonMsgClientHandler.InternalReadFinish(ErrorCode: Integer);
begin
  if ErrorCode <> 0 then
  begin
    FClient.PostClientError(AnsiString(Format('WSARecv failed. Error code is %u', [WSAGetLastError()])));
    Exit;
  end;

  if FReadStage = crReadAll then
    InternalRead;
end;

procedure TCommonMsgClientHandler.InternalClose;
begin
  // Shutdown and closesocket. All read operations are finished now (FD_CLOSE guarantees it)
  Winsock2.shutdown(FClient.FSocket, 2);
  Winsock2.closesocket(FClient.FSocket);

  // Mark socket as invalid
  FClient.FSocket := INVALID_SOCKET;
end;

procedure TCommonMsgClientHandler.HandleWrite(ErrorCode: Cardinal);
var ResCode: Integer;
    Header: TMsgHeader;
    SI: TStreamInfo;
begin
  // Ensure we have stream for sending
  if FStreamInfo = Nil then
    FStreamInfo := FClient.PopStreamForSending;

  if FStreamInfo = Nil then
  begin
    // Unsubscribe from FD_WRITE
    BindSocketToEvents();

    // And exit
    Exit;
  end;

  // Copy data from stream for writing if needed
  if FToSend = 0 then // Copy data from stream to temporary buffer
  begin
    // Prepend data with header
    Header.MsgLen := FStreamInfo.FStream.Size;
    Header.MsgType := FStreamInfo._Type; //application data

    // Copy header to send buffer
    Move(Header, FWriteTempStorage^, sizeof(Header));

    // Copy the message itself if possible
    FToSend := FStreamInfo.Stream.Read((FWriteTempStorage + sizeof(Header))^, Math.Min(FStreamInfo.Stream.Size, ClientTempStorageSize-sizeof(Header)));
    FToSend := FToSend + sizeof(Header);
  end;


  ResCode := 0;
  if FWritten < FToSend then
  begin
    ResCode := Winsock2.send(FClient.FSocket, (FWriteTempStorage + FWritten)^, FToSend - FWritten, 0); // Use send buffer
    FLastSentHeartBeat := Now;

    if ResCode = SOCKET_ERROR then
    begin
      if Winsock2.WSAGetLastError() = WSAEWOULDBLOCK then
        FCanWrite := False
      else
        FClient.PostClientError(AnsiString(Format('Winsock2.send() failed. Error code is %u', [WSAGetLastError()])));

      // Bind to FD_WRITE
      if not FCanWrite then
        BindSocketToEvents();

      // Leave the method
      Exit;
    end;
  end;

  FWritten := FWritten + ResCode;

  // Check if all temp buffer is sent
  if FToSend = FWritten then
  begin
    // None to send now
    FToSend := 0;

    // None is sent
    FWritten := 0;

    // Check if full stream is sent
    if FStreamInfo.Stream.Position = FStreamInfo.Stream.Size then
    begin
      //OutputDebugString('Stream sent');
      if FStreamInfo._Type = 0 then
        FClient.PostStreamSent(FStreamInfo)
      else
        FClient.DeleteStream(FStreamInfo);
      FStreamInfo := Nil;
      BindSocketToEvents();
    end
    else
      FToSend := FStreamInfo.Stream.Read(FWriteTempStorage^, Math.Min(FStreamInfo.Stream.Size, ClientTempStorageSize));
  end;
end;

procedure TCommonMsgClientHandler.HandleRead(ErrorCode: Cardinal);
var
  ResCode: Integer;
begin
  if ErrorCode <> 0 then
  begin
    FClient.PostClientError(AnsiString(Format('Cannot recv. Error code is %u', [ErrorCode])));
    Exit;
  end;
  // Save the time of last received message
  FLastHeartbeat := Now;

  // Well, read is guaranteed to success
  ResCode := Winsock2.recv(FClient.FSocket, FTempStorage^, ClientTempStorageSize, 0);
  if ResCode = SOCKET_ERROR then
    FClient.PostClientError(AnsiString(Format('Cannot recv. Error code is %u', [WSAGetLastError()])))
  else
  if ResCode > 0 then
    ParseData(ResCode)
  else
    FClient.FState := cmDisconnecting; //remote peer called shutdown/closesocket
end;

procedure TCommonMsgClientHandler.DoHandlers(S: PAnsiChar);
begin
  case FRecvHeader.MsgType of
    0: ProcessClientData(S, FRecvHeader.MsgLen);     //application data
    1: ProcessHandshakeData(S, FRecvHeader.MsgLen);  //handshake response
    2: ProcessClientListData(S, FRecvHeader.MsgLen, False); //client list
    3: DoHeartbeatData(S);  //heartbeat response
    4: ProcessClientListData(S, FRecvHeader.MsgLen, True); //final client list
  end;
end;

procedure TCommonMsgClientHandler.ParseData(WasRead: Integer);
var i, ToCopy: Integer;
begin
  //EmptyString := '';
  //LogMsg(AnsiString('Parsing ' + IntToStr(WasRead) + ' bytes:'));

  i := 0;
  while i < WasRead do
  begin

    if FReadStage = crHeader then
    begin
      // Find how much bytes we should copy
      ToCopy := Math.Min(sizeof(TMsgHeader) - FHeaderRead, WasRead - I);
      if ToCopy = 0 Then
        Exit;

      // Copy them
      Move((FTempStorage + i)^, (FHeaderData + FHeaderRead)^, ToCopy);

      // Increase counter of copied header bytes
      Inc(FHeaderRead, ToCopy);

      // Increase counter of processed bytes
      Inc(I, ToCopy);

      // Did we copy all bytes?
      if FHeaderRead = sizeof(TMsgHeader) then
      begin
        // "parse" header
        Move(FHeaderData^, FRecvHeader, sizeof(FRecvHeader));

        // Reset header bytes counter
        FHeaderRead := 0;

        (*LogMsg('Header is finished on ' + IntToStr(i));
        LogMsg('Msg length is ' + IntToStr(FRecvHeader.MsgLen));
        LogMsg('Msg type is ' + IntToStr(FRecvHeader.MsgType)); *)

        // Reset the counter of message data bytes
        FBodyParsed := 0;

        // Move to next stage & reset variables
        if FRecvHeader.MsgLen = 0  then
          DoHandlers(Nil)
        else
          FReadStage := crBody; //transition to reading message data stage
      end;
    end;

    if FReadStage = crBody then
    begin
      // If all buffer is processed
      if I = WasRead Then
        Exit;

      // Check how much data we can move to parsed data?
      // It is determined as minimum from 2 values:
      // - the size of received nonprocessed data
      // - the size of required data for message body
      ToCopy := Min(WasRead - I, FRecvHeader.MsgLen - FBodyParsed);

      if FBodyParsed + ToCopy > MaxMessageSize then
        DebugBreak;

      // Copy body
      Move((FTempStorage + i)^, (FParsedData + FBodyParsed)^, ToCopy);

      // Increase counters
      Inc(I, ToCopy);
      Inc(FBodyParsed, ToCopy);

      // LogMsg('Parsed ' + IntToStr(FBodyParsed));

      if FBodyParsed = FRecvHeader.MsgLen then
      begin
        //LogMsg('Message is parsed ok. Calling event.');
        DoHandlers(FParsedData);

        FBodyParsed := 0;

        //LogMsg('Transition to header parsing.');
        // Move to read header stage
        FReadStage := crHeader;
      end;

    end;

  end; //of while
end;

procedure TCommonMsgClientHandler.ProcessHandshakeData(S: PAnsiChar; Len: Cardinal);  //handshake response
var R: Boolean;
    Data: RawByteString;
begin
  if S = Nil then
    FClient.PostClientError('Protocol failed.')
  else
  begin
    R := S[0] = 'T';
    SetString(Data, S + 1, Len-1);
    // if R then
    FClient.PostAuthResult(R, Data)
    // else
    //  FClient.PostClientError(Data);
  end;
end;

procedure TCommonMsgClientHandler.ProcessClientListData(S: PAnsiChar; Len: Cardinal; Final: Boolean); //client list
var SC: RawByteString;
    CI: TMsgClientInfo;
    CL: TObjectList;
begin
  SetString(SC, S, Len);

  while Length(SC) > 0 do
  begin
    CI := TMsgClientInfo.Create;
    try
      CI.SerializeFrom(SC);
    except
      on E: Exception do
      begin
        FClient.PostClientError(AnsiString(E.Message));
        Exit;
      end;
    end;
    FClientList.Add(CI);
  end;

  if Final then
  begin
    CL := FClientList;
    FClientList := TObjectList.Create(True);
    FClient.PostClientListData(CL);
  end;

end;

procedure TCommonMsgClientHandler.DoHeartbeatData(S: PAnsiChar);  //heartbeat response
begin
  //nothing for now. Just to not get timeout.
end;

procedure TCommonMsgClientHandler.ProcessClientData(S: PAnsiChar; Len: Cardinal);
var MS: TStream;
    EI: TEventInfo;
begin
  If S <> Nil then
  begin
    MS := TStringStream.Create('');
    MS.Write(S^, Len); MS.Position := 0;
  end
  else
    MS := Nil;

  FClient.PostClientData(MS);
end;


procedure TCommonMsgClient.PostHeartbeatMsg;
var MS: TMemoryStream;
begin
  // If heartbeat'ing is specified and there is no stream in sendlist
  FGuard.Enter;
  try
    MS := TMemoryStream.Create;
    FStreamList.Add(TStreamInfo.Create(MS, 3));
    ReleaseSemaphore(FDataSignal, 1, Nil);
  finally
    FGuard.Leave;
  end;
end;


procedure TCommonMsgClientHandler.HandleError;
begin
  FClient.PostClientError(AnsiString(Format('Network error occured. Error code is %u', [Winsock2.WSAGetLastError()])));
end;

procedure TCommonMsgClientHandler.LogMsg(S: AnsiString);
begin
  {$ifdef Debug_IOCP}
  Log.LogDebug(s);
  {$endif}
  //OutputDebugString(PChar(S));
  (*S := S + #13#10;
  if FLog <> Nil then
    FLog.WriteBuffer(S[1], Length(S));*)
end;

{$IFDEF USECONNECTFIBER}
procedure TCommonMsgClientHandler.Terminate;
begin
  FTerminated := True;
end;
{$ENDIF}

{$IFDEF USECONNECTFIBER}
//--------------------------------------------------------
constructor TCommonMsgClientAggregator.Create;
begin
  inherited Create(True);
  FThreadList := TObjectList.Create(True);
  FGuard := TCriticalSection.Create;
  Resume;
end;

destructor TCommonMsgClientAggregator.Destroy;
begin
  Terminate;
  WaitFor;
  FreeAndNil(FThreadList);
  FreeAndNil(FGuard);

  inherited Destroy;
end;

function TCommonMsgClientAggregator.AllocFiber(Client: TCommonMsgClient): TCommonMsgClientHandler;
begin
  Result := TCommonMsgClientHandler.Create(Client, 0);
  FGuard.Enter;
  try
    FThreadList.Add(Result);
  finally
    FGuard.Leave;
  end;
end;

procedure TCommonMsgClientAggregator.Execute;
var i: Integer;
    Thr: TCommonMsgClientHandler;
begin
  while not Terminated do
  try
    FGuard.Enter;
    i := 0;

    while i < FThreadList.Count do
    begin
      Thr := FThreadList[i] as TCommonMsgClientHandler;

      if not Thr.Terminated then
        Thr.InternalExecute;

      if Thr.Terminated then
      begin
        Thr.InternalFinish;
        FThreadList.Remove(Thr);
      end
      else
       Inc(i);
    end;

    Sleep(1); //to avoid 100% CPU
  finally
    FGuard.Leave;
  end;

  try
    FGuard.Enter;
    for i:=0 to FThreadList.Count-1 do
    begin
      Thr := FThreadList[i] as TCommonMsgClientHandler;
      Thr.Terminate;
      Thr.InternalFinish;
    end;
    FThreadList.Clear;
  finally
    FGuard.Leave;
  end;
end;

{$ENDIF}

{$ifdef Debug_IOCP}

procedure Setup;
begin
  RegisterLogArea(Log,'IOCP.MsgClient');
end;

procedure Teardown;
begin
  Log := nil
end;
{$endif}

end.
