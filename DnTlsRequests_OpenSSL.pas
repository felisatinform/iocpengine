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
unit DnTlsRequests_OpenSSL;
interface
uses
  Classes, SysUtils, Windows, WinSock2,
  DnTcpReactor, DnConst, DnInterfaces, DnRtl, DnTcpRequests, DnTcpRequest,
  DnTcpChannel, DnTlsChannel,
  OpenSSLImport, OpenSSLUtils
  ;

type
  IDnTlsCRequestHandler = interface
  ['{8c23ed7b-563d-4bc3-b2b6-449aa97ec7d3}']
    procedure DoTlsCRequestFinished(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
    procedure DoTlsCRequestError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);
  end;

  IDnTlsSResponseHandler = interface
  ['{242a8776-de9f-4cda-842e-8ccd42ae91bf}']
    procedure DoTlsSResponseFinished(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
    procedure DoTlsSResponseError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);
  end;

  IDnTlsCloseNotifyHandler = interface
    ['{62348456-b668-4355-8e4c-10cea3a9f49a}']
    procedure DoTlsCloseNotifyFinished(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
    procedure DoTlsCloseNotifyError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                    ErrorCode: Cardinal);
  end;

  IDnTlsReadHandler = interface
  ['{09cfa4fd-7117-49dc-8a2c-4d86039c72f6}']
    procedure DoHandshake(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                            Handshake: RawByteString);
    procedure DoRead(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  Buf: PAnsiChar; BufSize: Cardinal);
    procedure DoReadError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);
    procedure DoReadClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
  end;

  IDnTlsLineHandler = interface
  ['{AB1279A4-BBC9-11d5-BDB9-0000212296FE}']
    procedure DoLineHandshake(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                            Handshake: RawByteString);
    procedure DoLine( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                      ReceivedLine: RawByteString; EolFound: Boolean );
    procedure DoLineError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          ErrorCode: Cardinal);
    procedure DoLineClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
  end;
  TDnTlsHandshakeState = (tlsNone, tlsCreateRequest, tlsCreateResponse, tlsSendRequest, tlsReadResponse, tlsReadRequest, tlsSendResponse);

  (* This class represents client TLS handshake request *)
  TDnTlsCRequest = class (TDnTcpRequest)
  protected
    FWSABuf:        WSABUF;
    FFlags:         Cardinal;
    FHandler:       IDnTlsCRequestHandler;
    {$ifdef USE_STREAMSEC2}
    FTlsServer:     TSimpleTLSInternalServer;
    {$endif}
    FRequestStream: TMemoryStream;
    FWritten:       Cardinal;
    FState:         TDnTlsHandshakeState;
    FTlsErrorCode:  Integer;
    
    procedure     SetTransferred(Transferred: Cardinal); override;
    procedure     SendRequestStream(ChannelImpl: TDnTcpChannel);

    //IDnIORequest
    procedure Execute; override;
    function  IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;

    //IDnIOResponse
    procedure CallHandler(Context: TDnThreadContext); override;

  public
    {$ifdef USE_STREAMSEC2}
    constructor Create(Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTlsCRequestHandler;
      TlsServer: TSimpleTLSInternalServer);
    {$endif}
    {$ifdef USE_OPENSSL}
    {$endif}
    destructor  Destroy; override;
  end;

  (* This class represents server handshake response - it just writes the next raw data to channel *)
  TDnTlsSResponse = class (TDnTcpRequest)
  protected
    FWSABuf:              WSABUF;
    FFlags:               Cardinal;
    {$ifdef USE_STREAMSEC2}
    FTLSServer:           TSimpleTLSInternalServer;
    {$endif}
    FHandler:             IDnTlsSResponseHandler;
    FWritten:             Cardinal;
    FRequestStream,
    FResponseStream:      TMemoryStream;
    FTlsErrorCode:        Integer;
    
    procedure     SetTransferred(Transferred: Cardinal); override;
    procedure     SendResponseStream(ChannelImpl: TDnTcpChannel);

    //IDnIORequest
    procedure Execute; override;
    function  IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;

    //IDnIOResponse
    procedure CallHandler(Context: TDnThreadContext); override;

  public
    {$ifdef USE_STREAMSEC2}
    constructor CreateFromString(Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTlsSResponseHandler;
      TLSServer: TSimpleTLSInternalServer; Response: RawByteString);
    {$endif}
    destructor Destroy; override;
  end;

  TFRState = (tlsReadHeader,  tlsReadData);
  //This request reads the TLS record
  TDnTlsFragmentRequest = class (TDnTcpRequest)
  protected
    FWSABuf:  WSABUF;
    FRead:    Cardinal;
    FFlags:   Cardinal;
    FRecvStream: TMemoryStream;
    FBuffer:  RawByteString;
    FState:   TFRState;
    FRecordSize: Word;
    FClosed:  Boolean;
    procedure SetTransferred(Transferred: Cardinal); override;

    //IDnIORequest
    procedure Execute; override;
    function IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;

    //IDnIOResponse
    procedure CallHandler(Context: TDnThreadContext); override;
    procedure Reset;
  public
    constructor Create( Channel: TDnTcpChannel; Key: Pointer);
    destructor Destroy; override;
    
  end;


  
  TDnTlsCloseRequest = class (TDnTcpRequest)
  protected
    FWSABuf:      WSABUF;
    FTempBuffer:  RawByteString;
    FRead:        Cardinal;
    FFlags:       Cardinal;
    FHandler:     IDnTcpCloseHandler;
    FBrutal:      Boolean;
    procedure     SetTransferred(Transferred: Cardinal); override;

    //IDnIORequest
    procedure Execute; override;
    function  IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;

    //IDnIOResponse
    procedure CallHandler(Context: TDnThreadContext); override;

  public
    constructor Create(Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTcpCloseHandler;
                        Brutal: Boolean = False);
    destructor  Destroy; override;
  end;

  TDnTlsReadRequest = class (TDnTcpRequest)
  protected
    FWSABuf:  WSABUF;
    FRead:    Cardinal;
    FToRead:  Cardinal;
    FFlags:   Cardinal;
    FHandler: IDnTlsReadHandler;
    FMustAll: Boolean;
    FStrBuf:  RawByteString;

    FResponseStream,
    FDataStream,
    FRecvStream: TMemoryStream;

    // TLS error code
    FTlsErrorCode: Integer;

    // Number of read application octets (after TLSDecode)
    FTlsRead: Integer;

    // Marks if IOCP is simulated due to read from cache
    FCacheRead: Boolean;

    procedure SetTransferred(Transferred: Cardinal); override;

    // IDnIORequest
    procedure Execute; override;
    function IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;

    // IDnIOResponse
    procedure CallHandler(Context: TDnThreadContext); override;
  public
    constructor Create( Channel: TDnTcpChannel; Key: Pointer;
                        Handler: IDnTlsReadHandler; Buf: PAnsiChar;
                        BufSize: Cardinal; MustAll:  Boolean);

    constructor CreateString( Channel:  TDnTcpChannel; Key: Pointer;
                        Handler: IDnTlsReadHandler; BufSize: Integer;
                        MustAll:  Boolean);
    destructor Destroy; override;
    procedure Init( Channel: TDnTcpChannel; Key: Pointer;
                    Handler: IDnTlsReadHandler; Buf: PAnsiChar;
                    BufSize: Cardinal; MustAll: Boolean);

  end;

  TDnTlsWriteRequest = class (TDnTcpRequest)
  protected
    FWSABuf:        WSABUF;
    FFlags:         Cardinal;
    FHandler:       IDnTcpWriteHandler;
    FWriteStream,
    FDataStream:    TMemoryStream;
    FTlsErrorCode:  Integer;
    FWritten:       Cardinal;

    procedure SetTransferred(Transferred: Cardinal); override;
    procedure Execute; override;
    function  IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;

    procedure CallHandler(Context: TDnThreadContext); override;
  public
    constructor CreateString( Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTcpWriteHandler;
                        Buf: RawByteString); overload;
    destructor Destroy; override;
  end;



implementation
var
  CRLFZero:PAnsiChar = #13#10#0;


//----------------------------------------------------------------------------


//----------------------------------------------------------------------------

//----------------------------------------------------------------------------

constructor TDnTlsCloseRequest.Create(Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTcpCloseHandler; Brutal: Boolean);
begin
  inherited Create(Channel, Key);
  FHandler := Handler;
  SetLength(FTempBuffer, 1024);
  FWSABuf.len := 1024;
  FWSABuf.buf := @FTempBuffer[1];
  FBrutal := Brutal;
end;

function TDnTlsCloseRequest.RequestType: TDnIORequestType;
begin
  if FBrutal then
    Result := rtBrutalClose
  else
    Result := rtClose;
end;

procedure TDnTlsCloseRequest.SetTransferred(Transferred: Cardinal);
begin
  FRead := Transferred;
  FWSABuf.buf := PByte(PAnsiChar(FTempBuffer));
  FWSABuf.len := 1024;
end;

procedure TDnTlsCloseRequest.Execute;
var ResCode: Integer;
    ChannelImpl: TDnTcpChannel;
begin
  inherited Execute;
  ChannelImpl := TDnTcpChannel(FChannel);
  WinSock2.shutdown(ChannelImpl.SocketHandle, SD_SEND); //disable sending
  InterlockedIncrement(PendingRequests);
  if not FBrutal then
  begin
    FRead := 0;
    ResCode := WinSock2.WSARecv(ChannelImpl.SocketHandle, @FWSABuf, 1,  FRead, FFlags, @FContext, Nil);
    if ResCode <> 0 then
    begin
      ResCode := WSAGetLastError;
      if ResCode <> WSA_IO_PENDING then
        Self.PostError(ResCode, 0);
    end;
  end else
    PostQueuedCompletionStatus(TDnTcpReactor(ChannelImpl.Reactor).PortHandle, 0,
                                NativeUInt(Pointer(ChannelImpl)), @FContext);
end;

procedure TDnTlsCloseRequest.ReExecute;
begin
  Execute;
end;

function TDnTlsCloseRequest.IsComplete: Boolean;
var ChannelImpl: TDnTcpChannel;
begin
  inherited IsComplete;
  ChannelImpl := TDnTcpChannel(FChannel);
  Result := (FRead = 0) or (FErrorCode <> 0);
  if Result then
  begin
    ChannelImpl.CloseSocketHandle;
  end;
end;

procedure TDnTlsCloseRequest.CallHandler(Context: TDnThreadContext);
var ChannelImpl: TDnTcpChannel;
begin
  try
    ChannelImpl := TDnTcpChannel(FChannel);
    if FErrorCode <> 0 then
      FHandler.DoCloseError(Context, TDnTcpChannel(FChannel), FKey, FErrorCode)
    else
      FHandler.DoClose(Context, TDnTcpChannel(FChannel), FKey);
    ChannelImpl.CloseSocketHandle;
    //drop channel
    TDnTcpReactor(ChannelImpl.Reactor).RemoveChannel(TDnTcpChannel(FChannel));
  finally
    //InterlockedDecrement(PendingRequests);
  end;
end;


destructor  TDnTlsCloseRequest.Destroy;
begin
  FHandler := Nil;
  inherited Destroy;
end;
//-------------------------------------------------------------------------------------------------

constructor TDnTlsReadRequest.Create( Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTlsReadHandler; Buf: PAnsiChar;
                                      BufSize: Cardinal; MustAll: Boolean);
begin
  inherited Create(Channel, Key);
  SetLength(FStrBuf, 0);
  Init(Channel, Key, Handler, Buf, BufSize, MustAll);
end;

constructor TDnTlsReadRequest.CreateString( Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTlsReadHandler; BufSize: Integer;
                                      MustAll: Boolean);
begin
  inherited Create(Channel, Key);
  SetLength(FStrBuf, BufSize);
  Init(Channel, Key, Handler, @FStrBuf[1], Length(FStrBuf), MustAll);
end;

procedure TDnTlsReadRequest.Init(Channel: TDnTcpChannel; Key: Pointer;
                                  Handler: IDnTlsReadHandler; Buf: PAnsiChar;
                                  BufSize: Cardinal; MustAll: Boolean);
begin
  // Prepare WSABuf record to receive data
  FWSABuf.Len := BufSize;
  FWSABuf.Buf := PByte(Buf);

  // Set read octets counter to zero
  FRead := 0;

  // Save the maximum number of octets to read
  FToRead := BufSize;

  // WSARecv flags
  FFlags := 0;

  // Save the pointer to buffer start
  FStartBuffer := @Buf;

  // Save the handler
  FHandler := Handler;

  // Save the mark if all specified data must be read
  FMustAll := MustAll;

  // Create TLS streams
  FResponseStream := TMemoryStream.Create;
  FDataStream := TMemoryStream.Create;
  FRecvStream := TMemoryStream.Create;
end;

destructor TDnTlsReadRequest.Destroy;
begin
  FHandler := Nil;
  FreeAndNil(FRecvStream);
  FreeAndNil(FDataStream);
  FreeAndNil(FResponseStream);

  inherited Destroy;
end;

function  TDnTlsReadRequest.RequestType: TDnIORequestType;
begin
  Result := rtRead;
end;

procedure TDnTlsReadRequest.SetTransferred(Transferred: Cardinal);
var S: RawByteString;
    L: Integer;
    DecodedAvailable: Integer;
begin
  L := 0;

  if Transferred <> 0 then
  begin
    TDnTlsChannel(FChannel).HandleReceived(FWSABuf.Buf, Transferred);


    // Send received data to OpenSSL
    OpenSSLImport.BIO_write(TDnTlsChannel(FChannel).InputBio, );

    // Read data from OpenSSL
    SetLength(S, 8192);

    DecodedAvailable := OpenSSLImport.SSL_read(TDnTlsChannel(FChannel).SSL, @S[1], Length(S));

    //check if we response to send
    if FResponseStream.Size > 0 then
    begin
      //move to the begin of response stream
      FResponseStream.Position := 0;

      //extract the data to string buffer
      SetString(S, PAnsiChar(FResponseStream.Memory), FResponseStream.Size);

      //clear response stream
      FResponseStream.Clear;

      //call handler
      FHandler.DoHandshake(Nil, TDnTcpChannel(FChannel), FKey, S);
    end;
  end;

  FRead := Transferred;
  FTlsRead := FDataStream.Size - L;
end;

procedure TDnTlsReadRequest.Execute;
var ChannelImpl: TDnTcpChannel;
    ResCode: Integer;
begin
  inherited Execute;
  ChannelImpl := TDnTcpChannel(FChannel);
  AddRef;

  // Check the channel read cache
  FRead := ChannelImpl.ExtractFromCache(PAnsiChar(FWSABuf.buf), FToRead);

  // Increment pending requests count
  InterlockedIncrement(PendingRequests);

  if FRead = FToRead then // If all data are read?
  begin
    PostQueuedCompletionStatus(TDnTcpReactor(ChannelImpl.Reactor).PortHandle, FRead,
                                NativeUInt(Pointer(ChannelImpl)), @FContext);
    FCacheRead := True;
  end
  else
  begin //not read yet...
    Inc(FWSABuf.buf, FRead);
    Dec(FWSABuf.len, FRead);
    ResCode := WinSock2.WSARecv(ChannelImpl.SocketHandle, @FWSABuf, 1,  FRead, FFlags, @FContext, Nil);
    //ResCode := Integer(ReadFileEx(ChannelImpl.SocketHandle, @FWSABuf, FRead, @FContext, Nil));
    if ResCode <> 0 then
    begin
      ResCode := WSAGetLastError;
      if ResCode <> WSA_IO_PENDING then
        Self.PostError(ResCode, FRead)
      else
        ;
    end;
  end;
end;

function TDnTlsReadRequest.IsComplete: Boolean;
begin
  inherited IsComplete;

  // Is error occured?
  if (FErrorCode <> 0) or (FTlsErrorCode <> 0) then
    Result := True
  else
  if FCacheRead then // If all data were fetched from decoded data cache
  begin
    Result := True; //then read operation is finished
  end
  else              //well, we check the result of true WSARecv - not simulated
  if FMustAll then
  begin
    // Did we read&decode enough data?
    Result := FDataStream.Size >= FToRead;

    // Can we put the extra data to cache?
    if FToRead < FDataStream.Size then
      TDnTcpChannel(FChannel).Add2Cache(PAnsiChar(FDataStream.Memory) + FToRead, FDataStream.Size - FToRead);

    // Copy data to result buffer
    Move(PAnsiChar(FDataStream.Memory)^, FWSABuf.buf^, FToRead);
  end
  else
  if FRead > 0 then
  begin
    Result := True;
  end
  else
    Result := True; //close notification got

  if (FRead = 0) or (FErrorCode <> 0) or (FTlsErrorCode <> 0) then
    TDnTcpChannel(FChannel).StopTimeOutTracking;
end;

procedure TDnTlsReadRequest.ReExecute;
begin
//  Dec(FWSABuf.len, FRead);
//  Inc(FWSABuf.buf, FRead);
  FRead := 0;
  Execute;
end;

procedure TDnTlsReadRequest.CallHandler(Context: TDnThreadContext);
begin
  try
    if (FErrorCode = 0) and (FTlsErrorCode = 0) and (FRead <> 0) then
      FHandler.DoRead(Context, TDnTcpChannel(FChannel), FKey, FStartBuffer, FToRead - FWSABuf.len)
    else
    if FRead = 0 then
      FHandler.DoReadClose(Context, TDnTcpChannel(FChannel), FKey)
    else
      FHandler.DoReadError(Context, TDnTcpChannel(FChannel), FKey, FErrorCode);
  finally
    //InterlockedDecrement(RequestsPending);
  end;
end;
//-----------------------------------------------------------------------------


constructor TDnTlsWriteRequest.CreateString(Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTcpWriteHandler; Buf: String;
                                      TlsServer: TSimpleTLSInternalServer);
begin
  inherited Create(Channel, Key);

  FDataStream := TMemoryStream.Create;
  FDataStream.Write(Buf[1], Length(Buf));
  FDataStream.Position := 0;
  FWriteStream := TMemoryStream.Create;
  TlsServer.TLSEncodeData(TDnTcpChannel(FChannel), FDataStream, FWriteStream, @FErrorCode);
  FWriteStream.Position := 0;
  
  FWSABuf.Len := FWriteStream.Size;
  FWSABuf.Buf := FWriteStream.Memory;
  FFlags := 0;
  FHandler := Handler;
  FTlsServer := TlsServer;
end;

destructor TDnTlsWriteRequest.Destroy;
begin
  FreeAndNil(FDataStream);
  FreeAndNil(FWriteStream);

  FHandler := Nil;
  inherited Destroy;
end;

function TDnTlsWriteRequest.RequestType: TDnIORequestType;
begin
  Result := rtWrite;
end;

procedure TDnTlsWriteRequest.SetTransferred(Transferred: Cardinal);
begin
  FWriteStream.Position := FWriteStream.Position + Transferred;
  FWSABuf.buf := PAnsiChar(FWriteStream.Memory) + Transferred;
  FWSABuf.len := FWriteStream.Size - FWriteStream.Position;
end;

procedure TDnTlsWriteRequest.Execute;
var ResCode: Integer;
    ChannelImpl: TDnTcpChannel;
    P: Integer;
begin
  inherited Execute;

  //find channel implementation
  ChannelImpl := TDnTcpChannel(FChannel);

  //increase the number of pending requests
  InterlockedIncrement(PendingRequests);

  ResCode := WinSock2.WSASend(ChannelImpl.SocketHandle, @FWSABuf , 1, FWritten, 0, @FContext, Nil);
  if ResCode = 0 then
  begin //WSASend completed immediately
    ;
  end else
  begin
    ResCode := WSAGetLastError;
    if (ResCode <> WSA_IO_PENDING)  then
      Self.PostError(ResCode, 0);
  end;
end;

function TDnTlsWriteRequest.IsComplete: Boolean;
begin
  inherited IsComplete;
  Result := (FWriteStream.Position = FWriteStream.Size) or (FErrorCode <> 0) or (FTlsErrorCode <> 0);
end;

procedure TDnTlsWriteRequest.ReExecute;
begin
  Execute;
end;

procedure TDnTlsWriteRequest.CallHandler(Context: TDnThreadContext);
begin
  if FErrorCode = 0 then
    FHandler.DoWrite(Context, TDnTcpChannel(FChannel), FKey, FStartBuffer, FWritten)
  else
    FHandler.DoWriteError(Context, TDnTcpChannel(FChannel), FKey, FErrorCode);
end;
//----------------------------------------------------------------------------

constructor TDnTlsFragmentRequest.Create(Channel: TDnTcpChannel; Key: Pointer);
begin
  inherited Create(Channel, Key);

  SetLength(FBuffer, 8192);

  FWSABuf.Buf := @FBuffer[1];
  FWSABuf.Len := Length(FBuffer);
  FRead := 0;
  FFlags := 0;
  FRecvStream := TMemoryStream.Create;
  FState := tlsReadHeader;
end;

destructor TDnTlsFragmentRequest.Destroy;
begin
  FreeAndNil(FRecvStream);
  inherited Destroy;
end;

procedure TDnTlsFragmentRequest.Reset;
begin
  FState := tlsReadHeader;
  FRecvStream.Clear;
  //FResponseStream.Clear;
  //FDataStream.Clear;
end;

function  TDnTlsFragmentRequest.RequestType: TDnIORequestType;
begin
  Result := rtRead;
end;


procedure TDnTlsFragmentRequest.Execute;
var ChannelImpl: TDnTcpChannel;
    ResCode: Integer;
begin
  inherited Execute;

  //get the channel object
  ChannelImpl := TDnTcpChannel(FChannel);

  //inc pending requests count
  InterlockedIncrement(PendingRequests);

  //setup the receiving buffer to get the remaining part of header
  FWSABuf.buf := @FBuffer[1];
  if FState = tlsReadHeader then
    FWSABuf.len := 5 - FRecvStream.Size
  else
    FWSABuf.len := FRecordSize - (FRecvStream.Size - 5);

  FRead := 0;
  ResCode := WinSock2.WSARecv(ChannelImpl.SocketHandle, @FWSABuf, 1,  FRead, FFlags, @FContext, Nil);

  if ResCode <> 0 then
  begin
    ResCode := WSAGetLastError;
    if ResCode <> WSA_IO_PENDING then
      Self.PostError(ResCode, FRead)
    else
      ;
  end;

end;

procedure TDnTlsFragmentRequest.SetTransferred(Transferred: Cardinal);
var RecordSize: Word;
begin
  FClosed := Transferred = 0;
  if Transferred > 0 then
  begin
    //save the received data to FRecvStream
    FRecvStream.Write(FBuffer[1], Transferred);

    if FState = tlsReadHeader then
    begin
      if FRecvStream.Size = 5 then
      begin
        //transition to state "receive TLS data"
        FState := tlsReadData;

        //read the TLS data size
        FRecvStream.Position := 3;
        FRecvStream.Read(FRecordSize, sizeof(FRecordSize));
        FRecordSize := ntohs(FRecordSize);
      end;
    end;
  end;


end;

function TDnTlsFragmentRequest.IsComplete;
begin
  Result := ((FState = tlsReadData) and (FRecordSize = FRecvStream.Size-5)) or (FErrorCode <> 0) or FClosed;
end;

procedure TDnTlsFragmentRequest.ReExecute;
begin
  Execute;
end;

//IDnIOResponse
procedure TDnTlsFragmentRequest.CallHandler(Context: TDnThreadContext);
begin
end;


//----------------------------------------------------------------------------
end.
