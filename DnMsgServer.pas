{$I DnConfig.inc}
unit DnMsgServer;

interface
uses  Classes, SysUtils, SyncObjs, contnrs,
      DnRtl, DnTcpReactor, DnTcpListener, DnTcpRequestor,
      DnAbstractExecutor, DnSimpleExecutor, DnAbstractLogger,
      DnFileLogger, DnWinsockMgr, DnTcpChannel, DnFileCachedLogger,
      DnMsgClientInfo, DnTcpRequest, DnStringList;

const
  //The maximum message size expected by server
  MaxMessageSize = 128*1024*1024;

type
  //enumeration for read stages
  TClientReadStage = (rsHeader, rsBody);

  //Represents client in server class
  TClientRec = class(TMsgClientInfo)
  protected
    //the current state of read operation
    FReadStage: TClientReadStage;

    //the expected size (in bytes/octets) of message body
    FReadMsgSize: Cardinal;

    //the received message type
    FReadMsgType: Word; //0 is app.data, 1 is handshake, 2 is 'get clients', 3 is heartbeat msg

    //the corresponding TCP connection
    FChannel: TDnTcpChannel;

    //sending guard
    FSendGuard: TCriticalSection;

    //marks if all operation with client must be terminated
    FShutdown: Boolean;

    //marks this client is already delete from client list
    FRemoved: Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    property ReadStage: TClientReadStage read FReadStage write FReadStage;
    property ReadMsgSize: Cardinal read FReadMsgSize write FReadMsgSize;
    property ReadMsgType: Word read FReadMsgType write FReadMsgType;
    property Channel: TDnTcpChannel read FChannel write FChannel;
    property Shutdown: Boolean read FShutdown write FShutdown;
  end;

  //occurs when client is connected
  TOnClientConnectedEvent = procedure (Sender: TObject; ClientRec: TClientRec) of object;

  //occurs if UserAuthentication is True
  TOnClientAuthenticationEvent = procedure (Sender: TObject; ClientRec: TClientRec; var Authenticated: Boolean) of object;

  //occurs when new message is received
  TOnDataReceivedEvent = procedure (Sender: TObject; ClientRec: TClientRec; Stream: TStream) of object;

  //occurs when client disconnects
  TOnClientDisconnectedEvent = procedure (Sender: TObject; ClientRec: TClientRec) of object;

  //occurs on network error
  TOnErrorEvent = procedure (Sender: TObject; Client: TClientRec; ErrorMessage: string) of object;

  //occurs when stream is sent (written to socket buffer at least)
  TOnStreamSentEvent = procedure (Sender: TObject; Client: TClientRec; Stream: TStream) of object;

{$IFDEF ROOTISCOMPONENT}
  TCommonMsgServer = class(TComponent)
{$ELSE}
  TCommonMsgServer = class
{$ENDIF}
  protected
    FOnClientConnected: TOnClientConnectedEvent;
    FOnClientDisconnected: TOnClientDisconnectedEvent;
    FOnClientAuthentication: TOnClientAuthenticationEvent;
    FOnDataReceived: TOnDataReceivedEvent;
    FOnError: TOnErrorEvent;
    FOnStreamSent: TOnStreamSentEvent;
    
    FReactor: TDnTcpReactor;
    FListener: TDnTcpListener;
    FExecutor: TDnAbstractExecutor;
    FLogger: TDnAbstractLogger;
    FRequestor: TDnTcpRequestor;
    FWinsock: TDnWinsockMgr;
    FPort: Word;
    FActive: Boolean;
    FClientList: TObjectList;
    FGuard: TCriticalSection;
    FTimeout: Cardinal;
    FShutdown: Boolean;
    //handlers
    procedure TcpListenerIncoming(Context: TDnThreadContext; Channel: TDnTcpChannel);
    procedure TcpRequestorTcpClose(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer);
    procedure TcpRequestorTcpError(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer; ErrorCode: Cardinal);
    procedure TcpRequestorTcpClientClose(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer);
    procedure TcpRequestorTcpRead(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          Buf: PAnsiChar; BufSize: Cardinal);
    procedure TcpRequestorTcpWrite(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          Buf: PAnsiChar; BufSize: Cardinal);
    procedure TcpRequestorTcpWriteStream(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          Stream: TStream);
    procedure HandleTimeout(Context: TDnThreadContext; Channel: TDnTcpChannel);
    procedure SetActive(AValue: Boolean);
    procedure DoDisconnected(Client: TClientRec);
    procedure DoConnected(Client: TClientRec);
    procedure DoDataReceived(Client: TClientRec; Buf: PAnsiChar; BufSize: Cardinal);
    procedure DoHandshake(Client: TClientRec; Buf: PAnsiChar; BufSize: Cardinal);
    procedure DoClientList(Client: TClientRec; Buf: PAnsiChar; BufSize: Cardinal);
    procedure DoHeartbeat(Client: TClientRec; Buf: PAnsiChar; BufSize: Cardinal);
    procedure DoError(Client: TClientRec; const Msg: String);
    procedure DoStreamSent(Client: TClientRec; Stream: TStream);
    procedure DoBufferSent(Client: TClientRec; Buf: PAnsiChar; BufSize: Cardinal);
    procedure SendHeader(Client: TClientRec; Len: Cardinal; _Type: Word = 0);
    procedure InternalSend(Client: TClientRec; Len: Cardinal; _Type: Word; Stream: TStream); overload;
    procedure InternalSend(Client: TClientRec; Len: Cardinal; _Type: Word; Buf: RawByteString); overload;
    procedure HandleHeaderRead(Channel: TDnTcpChannel; Client: TClientRec; Buf: PAnsiChar; BufSize: Cardinal);
    procedure HandleBodyRead(Channel: TDnTcpChannel; Client: TClientRec; Buf: PAnsiChar; BufSize: Cardinal);

  public
{$IFDEF ROOTISCOMPONENT}
    constructor Create(AOwner: TComponent); override;
{$ELSE}
    constructor Create;
{$ENDIF}
    destructor Destroy; override;

    procedure Open;
    procedure Close;

    procedure DisconnectAll;
    procedure DisconnectClient(AClientId: RawByteString); overload;
    procedure DisconnectClient(AClientIndex: Integer); overload;
    procedure DisconnectClient(AClient: TClientRec); overload;

    procedure SendStream(AStream: TStream; AClientId: RawByteString); overload;
    procedure SendStream(AStream: TStream; AClientIndex: Integer); overload;
    procedure SendString(AString: RawByteString; Client: TClientRec);
    procedure BroadcastStream(AStream: TStream);//send stream to all clients

    function GetClientByIndex(AClientIndex: Integer; var AClientRec: TClientRec): Boolean; //returns client's info by Index in Clients array
    function GetClientById(AClientId: RawByteString; var AClientRec: TClientRec): Boolean; //returns client's info by Id

    function GetClientId(AClientIndex: Integer): RawByteString; //returns client's Id by Index in Clients array. '' if not found.
    function GetClientIndex(AClientId: RawByteString): Integer; //returns client's Index in Clients array by Id. -1 if not found.
    function GetClientCount: Integer;
    procedure ShutdownListener;
  published
    property Active: Boolean read FActive write SetActive;
    property Port: Word read FPort write FPort;
    property Timeout: Cardinal read FTimeout write FTimeout;

    property OnClientConnected: TOnClientConnectedEvent read FOnClientConnected write FOnClientConnected;
    property OnClientDisconnected: TOnClientDisconnectedEvent read FOnClientDisconnected write FOnClientDisconnected;
    property OnClientAuthentication: TOnClientAuthenticationEvent read FOnClientAuthentication write FOnClientAuthentication;
    property OnDataReceived: TOnDataReceivedEvent read FOnDataReceived write FOnDataReceived;
    property OnError: TOnErrorEvent read FOnError write FOnError;
    property OnStreamSent: TOnStreamSentEvent read FOnStreamSent write FOnStreamSent;

  end;


implementation
type
  //The message header structure. Every message include this header.
  TMsgHeader = packed record
    MsgLen: Cardinal;
    MsgType: Word;
  end;

constructor TClientRec.Create;
begin
  inherited Create;

  FSendGuard := TCriticalSection.Create;
end;

destructor TClientRec.Destroy;
begin
  FreeAndNil(FSendGuard);
  inherited Destroy;
end;

{$IFDEF ROOTISCOMPONENT}
constructor TCommonMsgServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FClientList := TObjectList.Create(False);
  FGuard := TCriticalSection.Create;
end;
{$ELSE}
constructor TCommonMsgServer.Create;
begin
  inherited Create;

  FClientList := TObjectList.Create(False);
  FGuard := TCriticalSection.Create;
end;
{$ENDIF}

destructor TCommonMsgServer.Destroy;
begin
  if FReactor <> Nil then
    Close;

  FreeAndNil(FGuard);
  FreeAndNil(FClientList);
  inherited Destroy;
end;

procedure TCommonMsgServer.Open;
begin
  //create pieces of engine
  FShutdown := False;

{$IFDEF ROOTISCOMPONENT}
  FReactor := TDnTcpReactor.Create(Nil);
  FListener := TDnTcpListener.Create(Nil);
  FRequestor := TDnTcpRequestor.Create(Nil);
  FExecutor := TDnSimpleExecutor.Create(Nil);
  FLogger := TDnFileLogger.Create(Nil);
  FWinsock := TDnWinsockMgr.Create(Nil);
{$ELSE}
  FReactor := TDnTcpReactor.Create;
  FListener := TDnTcpListener.Create;
  FRequestor := TDnTcpRequestor.Create;
  FExecutor := TDnSimpleExecutor.Create;
  FLogger := TDnFileCachedLogger.Create;
  FWinsock := TDnWinsockMgr.Create;
{$ENDIF}
  //bind all together
  (FLogger as TDnFileLogger).FileName := 'HighApp.log';
  FLogger.MinLevel := llCritical;
  FReactor.Logger := FLogger;
  FReactor.Executor := FExecutor;
  FReactor.OnTimeout := HandleTimeout;
  FListener.Logger := FLogger;
  FListener.Executor := FExecutor;
  FListener.Reactor := FReactor;
  FRequestor.Logger := FLogger;
  FRequestor.Executor := FExecutor;
  FRequestor.Reactor := FReactor;
  FListener.OnIncoming := TcpListenerIncoming;
  FRequestor.OnError := TcpRequestorTcpError;
  FRequestor.OnClose := TcpRequestorTcpClose;
  FRequestor.OnClientClose := TcpRequestorTcpClientClose;
  FRequestor.OnRead := TcpRequestorTcpRead;
  FRequestor.OnWrite := TcpRequestorTcpWrite;
  FRequestor.OnWriteStream := TcpRequestorTcpWriteStream;
  
  //start
  FWinsock.Active := True;
  //FLogger.Active := True;
  FExecutor.Active := True;
  FReactor.Active := True;
  FRequestor.Active := True;
  FListener.Port := FPort;
  FListener.Active := True;

  FActive := True;
end;

procedure TCommonMsgServer.Close;
begin

  if FListener = Nil then
    Exit;
  FShutdown := True;

  if FListener.Active then
    FListener.Active := False;
  FListener.WaitForShutdown;

  DisconnectAll;

  //stop requestor - new requests will be ignored or exceptions raised
  FRequestor.Active := False;


  //stop reactor
  FReactor.Active := False;
  FExecutor.Active := False;
  FLogger.Active := False;
  FWinsock.Active := False;

  FreeAndNil(FListener);
  FreeAndNil(FReactor);
  FreeAndNil(FRequestor);
  FreeAndNil(FExecutor);
  FreeAndNil(FLogger);
  FreeAndNil(FWinsock);

  FActive := False;
end;


procedure TCommonMsgServer.TcpListenerIncoming(Context: TDnThreadContext; Channel: TDnTcpChannel);
var Client: TClientRec;
begin
  if FShutdown then
    Exit;

  //create new client object
  FGuard.Enter;
  try
    Client := TClientRec.Create;
    FClientList.Add(Client);

    //set 'read header' stage
    Client.ReadStage := rsHeader;

    //save client
    Channel.CustomData := Client;
    Channel.OwnsCustomData := True; //channel is responsible for destroying of clientrec

    //save the remote peer address
    Client.Address := Channel.RemoteAddr;

    //save the channel handle
    Client.Channel := Channel;

    Client.Channel.AddRef(rtClientList); //reference to the channel object

  finally
    FGuard.Leave;
  end;

  //call OnClientConnected event
  DoConnected(Client);

  //set timeout
  FReactor.SetTimeout(Channel, FTimeout);

  //read msg header
  FRequestor.ReadString(Channel, Client, sizeof(TMsgHeader));
end;

procedure TCommonMsgServer.HandleHeaderRead(Channel: TDnTcpChannel; Client: TClientRec; Buf: PAnsiChar; BufSize: Cardinal);
var Header: TMsgHeader;
begin
  //check the size of received data - we can do it as read request reads ALL requested bytes
  if BufSize < sizeof(Header) then
  begin
    //Wrong size. Brutal close is initiated.
    FLogger.LogMsg(llCritical, Format('Wrong header size %u bytes', [BufSize]));

    //close the connection
    FRequestor.Close(Channel, Client, True);
  end
  else
  begin
    //copy the bytes to header structure
    Move(Buf^, Header, sizeof(Header));

    //if it exceeds the max size - reject it too
    if Header.MsgLen > MaxMessageSize then
    begin
      FLogger.LogMsg(llCritical, Format('Too big message size: %u with maximum %u', [Header.MsgLen, MaxMessageSize]));
      FRequestor.Close(Channel, Client, True);
    end
    else
    begin
      //save the message size
      Client.ReadMsgSize := Header.MsgLen;

      //save the message type
      Client.ReadMsgType := Header.MsgType;

      //transition to next stage
      Client.ReadStage := rsBody;

      //initiate reading of message
      if Header.MsgLen > 0 then
        FRequestor.ReadString(Channel, Client, header.MsgLen) //read the message body
      else
        HandleBodyRead(Channel, Client, Nil, 0);
    end;
  end;
end;

procedure TCommonMsgServer.HandleBodyRead(Channel: TDnTcpChannel; Client: TClientRec; Buf: PAnsiChar; BufSize: Cardinal);
begin
  if Client.ReadMsgSize <> BufSize then
  begin
    //we discovered that received msg body size is not the specified in header
    //log about it and close connection as wrong
    FLogger.LogMsg(llCritical, Format('Cannot read message. Received %u bytes, expected %u.', [BufSize, Client.ReadMsgSize]));
    FRequestor.Close(Channel, Client, True);
  end
  else
  begin
    //enclose handler call to try..except block
    try
      case Client.ReadMsgType of
        0: DoDataReceived(Client, Buf, BufSize);
        1: DoHandshake(Client, Buf, BufSize);
        2: DoClientList(Client, Buf, BufSize);
        3: DoHeartbeat(Client, Buf, BufSize);
      end;

      //transition to next read stage
      Client.ReadStage := rsHeader;

      //initiate reading
      FRequestor.ReadString(Channel, Client, sizeof(TMsgHeader));
    except
      on E: Exception do
        FLogger.LogMsg(llCritical, E.Message); //log any exception here
    end;
  end;
end;

procedure TCommonMsgServer.TcpRequestorTcpRead(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                            Buf: PAnsiChar; BufSize: Cardinal);
var Client: TClientRec;
begin
  if FShutdown then
    Exit;

  //reinterpret passed key as client object
  Client := TClientRec(Key);

  if Client.Shutdown then
    Exit;

  //check the read stage
  if Client.ReadStage = rsHeader then
    HandleHeaderRead(Channel, Client, Buf, BufSize)
  else
  if Client.ReadStage = rsBody then
    HandleBodyRead(Channel, Client, Buf, BufSize);
end;

procedure TCommonMsgServer.HandleTimeout(Context: TDnThreadContext; Channel: TDnTcpChannel);
begin
  //check for
  Self.DoError(TClientRec(Channel.CustomData), 'I/O timeouted.');
end;

procedure TCommonMsgServer.DoDataReceived(Client: TClientRec; Buf: PAnsiChar; BufSize: Cardinal);
var MS: TMemoryStream;
begin
  //if event handler is not zero
  if Assigned(FOnDataReceived) then
  begin
    //Copy all data to memory stream.
    //The best way would special TStream descendand with fixed size
    //that owns external memory block
    MS := TMemoryStream.Create;
    MS.Write(Buf^, BufSize);
    MS.Position := 0;
    try
      FOnDataReceived(Self, Client, MS);
    finally
      FreeAndNil(MS);
    end;
  end;
end;

procedure TCommonMsgServer.TcpRequestorTcpClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
var Client: TClientRec;
begin
(*  if FShutdown then
    Exit; *)

  //find client record for this channel and remove
  Client := TClientRec(Key);
  FGuard.Enter;
  try
    if Client.Channel <> Nil then
    begin
      //remove channel from reactor's list (not the actual unbinding from IOCP)
      FReactor.RemoveChannel(Client.Channel);

      //dereference the TDnTcpChannel object
      Client.Channel.Release(rtClientList);

      //zero pointer
      Client.Channel := Nil;
    end;
    if not Client.FRemoved then
    begin
      //raise event
      DoDisconnected(Client);

      //remove client from the list
      FClientList.Remove(Client); //the TClientRec object will be freed here

      //mark client as finished
      Client.FRemoved := True;
    end;
  finally
    FGuard.Leave;
  end;
end;

procedure TCommonMsgServer.TcpRequestorTcpError(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer; ErrorCode: Cardinal);
begin
  if FShutdown then
    Exit;
    
  if ErrorCode <> 10038 then
  try
    FRequestor.Close(Channel, Channel.CustomData, True);
  except
    FLogger.LogMsg(llCritical, 'Failed to enqueue close command.');
  end;
end;

procedure TCommonMsgServer.TcpRequestorTcpClientClose(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer);
begin
  if FShutdown then
    Exit;

  try
    FRequestor.Close(Channel, Key, True);
  except
    FLogger.LogMsg(llCritical, 'Failed to enqueue close command.');
  end;
end;

procedure TCommonMsgServer.DisconnectAll;
var i: Integer;
    Client: TClientRec;
begin
  //iterate all client records and issue close for all of them
  FGuard.Enter;
  try
  for i:=0 to FClientList.Count-1 do
    begin
      Client := FClientList[i] as TClientRec;
      Client.Shutdown := True;
      FRequestor.Close(Client.Channel, Client, True); //brutal close is used
    end;
  finally
    FGuard.Leave;
  end;
end;

procedure TCommonMsgServer.DisconnectClient(AClientId: RawByteString);
var Client: TClientRec;
begin
  if GetClientById(AClientId, Client) then
    DisconnectClient(Client);
end;

procedure TCommonMsgServer.DisconnectClient(AClientIndex: Integer);
var Client: TClientRec;
begin
  if GetClientByIndex(AClientIndex, Client) then
    DisconnectClient(Client);
end;

procedure TCommonMsgServer.DisconnectClient(AClient: TClientRec);
begin
  AClient.Shutdown := True;
  FRequestor.Close(AClient.Channel, AClient, True);
end;

procedure TCommonMsgServer.SendStream(AStream: TStream; AClientId: RawByteString);
var Client: TClientRec;
begin
  //find client record and send stream
  if GetClientById(AClientId, Client) then
    InternalSend(Client, AStream.Size, 0, AStream);
end;


procedure TCommonMsgServer.SendStream(AStream: TStream; AClientIndex: Integer);
var Client: TClientRec;
begin
  //find client record and send stream
  if GetClientByIndex(AClientIndex, Client) then
    InternalSend(Client, AStream.Size, 0, AStream);
end;

procedure TCommonMsgServer.SendHeader(Client: TClientRec; Len: Cardinal; _Type: Word = 0);
var Header: TMsgHeader;
    HeaderS: RawByteString;
begin
  Header.MsgLen := Len;
  Header.MsgType := _Type;
  SetString(HeaderS, PAnsiChar(@Header), sizeof(Header));
  FRequestor.WriteString(Client.Channel, Pointer(_Type * 2), HeaderS);
end;

procedure TCommonMsgServer.SendString(AString: RawByteString; Client: TClientRec);
begin
  InternalSend(Client, Length(AString), 0, AString);
end;

procedure TCommonMsgServer.BroadcastStream(AStream: TStream);//send stream to all clients
var i: Integer;
    Client: TClientRec;
    S: RawByteString;
    WasRead: Integer;
begin
  //copy the content of stream to string buffer
  SetLength(S, AStream.Size);
  WasRead := AStream.Read(S[1], AStream.Size);

  //Therefore I should handle the case WasRead <> AStream.Size
  //However it requires the more precise specification.

  //lock the list
  FGuard.Enter;
  try
    for i := 0 to FClientList.COunt-1 do
    begin
      //extract pointer to TClientRec object
      Client := FClientList[i] as TClientRec;

      InternalSend(Client, Length(S), 0, S);
    end;
  finally
    FGuard.Leave;
  end;
end;

//returns client's info by Index in Clients array
function TCommonMsgServer.GetClientByIndex(AClientIndex: Integer; var AClientRec: TClientRec): Boolean;
begin
  //lock the list of client
  FGuard.Enter;
  try
    if FClientList.Count > AClientIndex then
    begin
      AClientRec := FClientList[AClientIndex] as TClientRec;
      Result := True;
    end
    else
      Result := False;
  finally
    FGuard.Leave;
  end;
end;

function TCommonMsgServer.GetClientById(AClientId: RawByteString; var AClientRec: TClientRec): Boolean; //returns client's info by Id
var i: Integer;
    Client: TClientRec;
begin
  Result := False;
  FGuard.Enter;
  try
    //It is a place for future optimization - it is non optimal way to search the client by plain iterating...
    for i:=0 to FClientList.Count-1 do
    begin
      Client := FClientList[i] As TClientRec;
      if Client.ID = AClientID then
      begin
        AClientRec := Client;
        Result := True;
        Break;
      end;
    end;
  finally
    FGuard.Leave;
  end;
end;

function TCommonMsgServer.GetClientId(AClientIndex: Integer): RawByteString; //returns client's Id by Index in Clients array. '' if not found.
begin
  Result := '';
  FGuard.Enter;
  try
    Result := (FClientList[AClientIndex] as TClientRec).ID;
  finally
    FGuard.Leave;
  end;
end;

function TCommonMsgServer.GetClientIndex(AClientId: RawByteString): Integer; //returns client's Index in Clients array by Id. -1 if not found.
var i: Integer;
    Client: TClientRec;
begin
  Result := -1;
  FGuard.Enter;
  try
    for i := 0 to FClientList.Count-1 do
    begin
      Client := FClientList[i] As TClientRec;
      if Client.ID = AClientID then
      begin
        Result := I;
        Break;
      end;
    end;
  finally
    FGuard.Leave;
  end;
end;

procedure TCommonMsgServer.SetActive(AValue: Boolean);
begin
  if FActive <> AValue then
  begin
    if FActive then
      Close
    else
      Open;
  end;
end;

procedure TCommonMsgServer.DoDisconnected(Client: TClientRec);
begin
  if Assigned(FOnClientDisconnected) then
  try
    FOnClientDisconnected(Self, Client);
  except
    on E: Exception do
      FLogger.LogMsg(llCritical, E.Message);
  end;
end;

procedure TCommonMsgServer.DoConnected(Client: TClientRec);
begin
  if Assigned(FOnClientConnected) then
  try
    FOnClientConnected(Self, Client);
  except
    on E: Exception do
      FLogger.LogMsg(llCritical, E.Message);
  end;
end;

const
  AuthOkStr = 'TAuthenticated ok';
  AuthFailedStr  = 'FAuthentication failed.';
  
procedure TCommonMsgServer.DoHandshake(Client: TClientRec; Buf: PAnsiChar; BufSize: Cardinal);
var
    S: RawByteString;
    AuthOk: Boolean;
begin
  //extract client data from incoming string
  //find the appropriate client rec in FClientList
  SetString(S, Buf, BufSize);
  try
    Client.SerializeFrom(S);
        
  except
    on E: Exception do
    begin
      DoError(Client, E.Message);
      Exit;
    end;
  end;

  //call OnClientAuthentication event
  AuthOk := False;
  if Assigned(FOnClientAuthentication) then
  try
    FOnClientAuthentication(Self, Client, AuthOk);
  except
  end;

  if AuthOk then
    InternalSend(Client, Length(AuthOkStr), 1, AuthOkStr)
  else
    InternalSend(Client, Length(AuthFailedStr), 1, AuthFailedStr);
end;

procedure TCommonMsgServer.DoClientList(Client: TClientRec; Buf: PAnsiChar; BufSize: Cardinal);
var i: Integer;
    CR: TClientRec;
    S: RawByteString;
    SL: TDnStringList;
begin
  //lock the list
  FGuard.Enter;
  try
    //iterate list and build the message
    SL := TDnStringList.Create;

    for i:=0 to FClientList.Count-1 do
    begin
      //extract client record
      CR := FClientList[i] as TClientRec;

      //serialize it
      S := S + CR.SerializeTo;

      //check for its length
      if (Length(S) >= 4000) and (i < FClientList.Count-1) then
      begin
        SL.Add(S);
        s := '';
      end;
    end;
  finally
    FGuard.Leave;
  end;

  SL.Add(S);
  for i:=0 to SL.Count-1 do
    if i < SL.Count-1 then
      InternalSend(Client, Length(SL[i]), 2, SL[i])
    else
      InternalSend(Client, Length(SL[i]), 4, SL[i]);
  FreeAndNil(SL);
end;

procedure TCommonMsgServer.DoHeartbeat(Client: TClientRec; Buf: PAnsiChar; BufSize: Cardinal);
begin
  InternalSend(Client, 0, 3, '');
end;

procedure TCommonMsgServer.DoError(Client: TClientRec; const Msg: String);
begin
  if FActive and Assigned(Self.FOnError) then
  try
    FOnError(Self, Client, Msg);
  except
  end;
end;

procedure TCommonMsgServer.InternalSend(Client: TClientRec; Len: Cardinal; _Type: Word; Stream: TStream);
begin
  Client.FSendGuard.Enter;
  try
    SendHeader(Client, Len, _Type);
    FRequestor.WriteStream(Client.Channel, Pointer((_Type * 2 ) + 1), Stream);
  finally
    Client.FSendGuard.Leave;
  end;
end;

procedure TCommonMsgServer.InternalSend(Client: TClientRec; Len: Cardinal; _Type: Word; Buf: RawByteString);
begin
  Client.FSendGuard.Enter;
  try
    SendHeader(Client, Len, _Type);
    FRequestor.WriteString(Client.Channel, Pointer((_Type * 2 ) + 1), Buf);
  finally
    Client.FSendGuard.Leave;
  end;
end;

procedure TCommonMsgServer.DoStreamSent(Client: TClientRec; Stream: TStream);
begin
  if Assigned(FOnStreamSent) then
  try
    FOnStreamSent(Self, Client, Stream);
  except
    on E: Exception do
      FLogger.LogMsg(llCritical, E.Message);
  end;
end;

procedure TCommonMsgServer.DoBufferSent(Client: TClientRec; Buf: PAnsiChar; BufSize: Cardinal);
var MS: TMemoryStream;
begin
  if Assigned(FOnStreamSent) then
  try
    MS := TMemoryStream.Create;
    MS.Write(Buf^, BufSize);
    MS.Position := 0;
    FOnStreamSent(Self, Client, MS);
  except
    on E: Exception do
      FLogger.LogMsg(llCritical, E.Message);
  end;
  FreeAndNil(MS);
end;

procedure TCommonMsgServer.TcpRequestorTcpWrite(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          Buf: PAnsiChar; BufSize: Cardinal);
var TypeR: Cardinal;
begin
  TypeR := Cardinal(Key);
  if (TypeR mod 2 = 1) and (TypeR div 2 = 0)  then
    DoBufferSent(TClientRec(Channel.CustomData), Buf, BufSize);
end;

procedure TCommonMsgServer.TcpRequestorTcpWriteStream(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          Stream: TStream);
var TypeR: Cardinal;
begin
  TypeR := Cardinal(Key);
  if (TypeR mod 2 = 1) and (TypeR div 2 = 0) then
    DoStreamSent(TClientRec(Channel.CustomData), Stream);
end;

function TCommonMsgServer.GetClientCount: Integer;
begin
  Result := FClientList.Count;
end;

procedure TCommonMsgServer.ShutdownListener;
begin
  if FListener <> Nil then
    FListener.Active := False;
end;
    

end.
