{$I DnConfig.inc}
unit DnTlsChannel;
interface
uses
  Classes, SysUtils, 
  DnConst, DnRtl, DnTcpChannel, DnDataQueue, DnTcpReactor, DnUtils,
  OpenSSLImport, OpenSSLUtils, WinSock2, Windows;

const
  TlsDecodedBufferSize = 16384;
  TlsIncomingBufferSize = 16384;

type
  TSslState = (SslNone, SslHandshake, SslFailed, SslOk, SslShutdown, SslClosed);

  EDnSslException = class(EDnException)
  public
    constructor Create(ErrorCode: Integer);
  end;

  TDnTlsChannel = class(TDnTcpChannel)
  protected
    // Markj channel as client/server
    FTlsClient: Boolean;

    // OpenSSL's BIO buffers
    FInputBio, FOutputBio: PBIO;

    // OpenSSL's SSL session context
    FSSL: Pointer;

    // Incoming application data
    FIncomingAppData: TDnDataQueue;

    // Outgoing application data
    FOutgoingAppData: TDnDataQueue;

    // Incoming network data
    FIncoming: TDnDataQueue;

    // Data to send to network extracted from OutputBio
    FOutgoing: TDnDataQueue;

    // Writing now
    FWriting: Boolean;

    // Current SSL channel state
    FSslState: TSslState;

    // Last SSL error
    FSslError: Integer;

    // Marks if OnConnected() event was sent for this channel
    FConnectedEventFired: Boolean;

    procedure InitSsl(SslCtx: Pointer);
    procedure FreeSsl();
    procedure HandleStateChain();
    procedure HandleReceivedSsl();
    procedure HandleHandshake();
    procedure HandleHandshakeError(ErrorCode: Integer);
    procedure HandleHandshakeSuccess();
    procedure HandleShutdown();

    property  ConnectedEventFired: Boolean read FConnectedEventFired write FConnectedEventFired;

  public
    constructor CreateClient(Reactor: TDnTcpReactor; const RemoteIp: AnsiString; RemotePort: Integer; SslCtx: Pointer);
    constructor CreateServer(Reactor: TDnTcpReactor; Socket: TSocket; Addr: TSockAddrIn; SslCtx: Pointer);

    destructor Destroy; override;

    // Processes via OpenSSL received data.
    procedure HandleReceived(Buffer: PByte; Size: Integer);

    // Checks if there is data generated by SSL to send and moves this data to OutgoingData
    procedure CheckDataToSend;

    // Prepares to handshake as client
    procedure ConnectedAsClient;

    // Prepares to handshake as server
    procedure ConnectedAsServer;

    // Initiates SSL shutdown
    procedure SslClose;

    // Marks if data are sending now on channel
    property Writing: Boolean read FWriting write FWriting;

    // Returns if handshake was ok
    property SslState: TSslState read FSslState;

    // Pointer to OpenSSL context
    property SSL: Pointer read FSSL write FSSL;

    // OpenSSL error code
    property SslError: Integer read FSslError;

    // OpenSSL input buffer
    property InputBio: PBIO read FInputBio write FOutputBio;

    // OpenSSL output buffer
    property OutputBio: PBIO read FOutputBio write FOutputBio;

    // Buffer for outgoing application data
    property OutgoingAppData: TDnDataQueue read FOutgoingAppData;

    // Buffer for incoming application data
    property IncomingAppData: TDnDataQueue read FIncomingAppData;

    // Data prepared to send to network
    property OutgoingData: TDnDataQueue read FOutgoing;

    // Data received from network
    property IncomingData: TDnDataQueue read FIncoming;
  end;

implementation

constructor EDnSslException.Create(ErrorCode: Integer);
var Buf: AnsiString;
begin
  inherited Create(ErrSsl, ErrorCode);

  SetLength(Buf, 512);
  OpenSSLImport.ERR_error_string(ErrorCode, @Buf[1]);
  SetLength(Buf, StrLen(PAnsiChar(@Buf[1])));
  FErrorMessage := String(Buf);
end;

constructor TDnTlsChannel.CreateClient(Reactor: TDnTcpReactor; const RemoteIp: AnsiString; RemotePort: Integer; SslCtx: Pointer);
begin
  inherited CreateEmpty(Reactor, RemoteIp, RemotePort);
  FTlsClient := True;
  InitSsl(SslCtx);
end;

constructor TDnTlsChannel.CreateServer(Reactor: TDnTcpReactor; Socket: TSocket; Addr: TSockAddrIn; SslCtx: Pointer);
begin
  inherited Create(Reactor, Socket, Addr);
  FTlsClient := False;
  InitSsl(SslCtx);
end;

procedure TDnTlsChannel.InitSsl(SslCtx: Pointer);
begin
  FSslState := SslNone;
  FSslError := 0;
  FWriting := False;
  FIncomingAppData := TDnDataQueue.Create(TlsDecodedBufferSize, TlsDecodedBufferSize);
  FOutgoingAppData := TDnDataQueue.Create(TlsDecodedBufferSize, TlsDecodedBufferSize);
  FIncoming := TDnDataQueue.Create(TlsIncomingBufferSize, TlsIncomingBufferSize);
  FOutgoing := TDnDataQueue.Create(TlsIncomingBufferSize, TlsIncomingBufferSize);

  // Make SSL context
  FSSL := OpenSSLImport.SSL_new(SslCtx);
  if not Assigned(FSSL) then
    raise EDnSslException.Create(OpenSSLImport.ERR_get_error());

  // Bring input output buffers for SSL
  FInputBio := OpenSSLImport.BIO_new(OpenSSLImport.BIO_s_mem);
  FOutputBio := OpenSSLImport.BIO_new(OpenSSLImport.BIO_s_mem);
  OpenSSLImport.SSL_set_bio(FSSL, FInputBio, FOutputBio);
end;

procedure TDnTlsChannel.FreeSsl;
begin
  // FInputBio and FOutputBio are linked into FSSL context - it owns buffers so no delete them
  FInputBio := Nil;
  FOutputBio := Nil;

  if Assigned(FSSL) then
  begin
    OpenSSLImport.SSL_free(FSSL);
    FSSL := Nil;
  end;

  FreeAndNil(FOutgoing);
  FreeAndNil(FIncoming);
  FreeAndNil(FIncomingAppData);
  FreeAndNil(FOutgoingAppData);
end;

procedure TDnTlsChannel.HandleStateChain();
begin
  case FSslState of
    SslHandshake:   HandleHandshake();
    SslNone:        ; // Do nothing here
    SslOk:          HandleReceivedSsl();
    SslShutdown:    HandleShutdown();
    SslClosed:      ; // Do nothing here
  end;

  CheckDataToSend();
end;

procedure TDnTlsChannel.HandleReceivedSsl();
var ResCode: Integer;
begin
  // See how much was received application data
  repeat
    // Ensure there is enough space in FDecoded buffer
    FIncomingAppData.EnsureCapacity(FIncomingAppData.Size + TlsDecodedBufferSize);

    // Decode data
    {$IFDEF Delphi2009AndUp}
    ResCode := OpenSSLImport.SSL_read(FSSL, FIncomingAppData.Memory + FIncomingAppData.Size, TlsDecodedBufferSize);
    {$ELSE}
    ResCode := OpenSSLImport.SSL_read(FSSL, PChar(FIncomingAppData.Memory) + FIncomingAppData.Size, TlsDecodedBufferSize);
    {$ENDIF}

    //OutputDebugString(PWideChar(WideString('SSL_read returned ' + IntToStr(ResCode))));
    if ResCode > 0 then
      FIncomingAppData.Size := FIncomingAppData.Size + ResCode;

  until ResCode <= 0;

  ResCode := OpenSSLImport.SSL_get_error(FSSL, ResCode);
  if (ResCode <> SSL_ERROR_WANT_READ) and (ResCode <> SSL_ERROR_WANT_WRITE) then
  begin
    if ResCode = SSL_ERROR_ZERO_RETURN then
    begin
      FSslError := 0;
      FSslState := SslClosed;
    end
    else
    begin
      FSslError := ResCode;
      FSslState := SslFailed;
    end;
  end;
end;

procedure TDnTlsChannel.HandleHandshake();
var ResCode: Integer;
begin
  // Try to perform handshake
  if FTlsClient then
    ResCode := OpenSSLImport.SSL_connect(FSSL)
  else
    ResCode := OpenSSLImport.SSL_accept(FSSL);

  case ResCode of
    -1: begin
          // See what is exact error code
          ResCode := SSL_get_error(FSsl, ResCode);
          case ResCode of
            SSL_ERROR_WANT_READ:  ; // Read is in progress always
            SSL_ERROR_WANT_WRITE: CheckDataToSend(); // It will produce data to OutgoingData queue
          else
            FSslState := SslFailed;
            FSslError := ResCode;
          end;
        end;
    0:  HandleHandshakeError(OpenSSLImport.SSL_get_error(FSsl, 0));
    1:  HandleHandshakeSuccess();
  end;
end;

procedure TDnTlsChannel.HandleShutdown;
var ResCode: Integer;
begin
  ResCode := OpenSSLImport.SSL_shutdown(FSSL);
  if ResCode = 0 then
    ResCode := OpenSSLImport.SSL_shutdown(FSSL); // 2nd call is needed because bidirectional shutdown is performed by default

  case ResCode of
    0:  FSslState := SslClosed;
    1:  FSslState := SslClosed;
    -1: begin
          ResCode := OpenSSLImport.SSL_get_error(FSSL, -1);
          if (ResCode <> SSL_ERROR_WANT_READ) and (ResCode <> SSL_ERROR_WANT_WRITE) then
          begin
            FSslState := SslFailed;
            FSslError := ResCode;
          end;
        end;
  end;
end;

procedure TDnTlsChannel.HandleHandshakeError(ErrorCode: Integer);
begin
  FSslState := SslFailed;
  FSslError := ErrorCode;
end;

procedure TDnTlsChannel.HandleHandshakeSuccess();
begin
  FSslState := SslOk;
end;

destructor TDnTlsChannel.Destroy;
begin
  FreeSsl();
  inherited Destroy();
end;

procedure TDnTlsChannel.ConnectedAsClient;
var ResCode: Integer;
begin
  FSslState := SslHandshake;
  FTlsClient := True;
  HandleStateChain();
end;

procedure TDnTlsChannel.ConnectedAsServer;
var ResCode: Integer;
begin
  FSslState := SslHandshake;
  FTlsClient := False;
  HandleStateChain();
end;

procedure TDnTlsChannel.SslClose;
var ResCode: Integer;
begin
  if FSslState = SslOk then
  begin
    FSslState := SslShutdown;
    HandleStateChain();
  end;
end;
procedure TDnTlsChannel.HandleReceived(Buffer: PByte; Size: Integer);
var
    ResCode: Integer;
begin
  //OutputDebugString(PWideChar(WideString('Read ' + IntToStr(Size) + ' bytes.')));

  // Send received data to OpenSSL associated buffer
  if OpenSSLImport.BIO_write(FInputBio, Buffer, Size) < 1 then
  begin
    FSslState := SslFailed;
    FSslError := OpenSSLImport.ERR_get_error();
    raise EDnSslException.Create(FSslError);
  end;

  HandleStateChain();
  //OutputDebugString(PWideChar(WideString('State: ' + IntToStr(Integer(FSslState)))));
end;

procedure TDnTlsChannel.CheckDataToSend;
var ResCode: Integer;
begin
  // See if there is outgoing application data
  case FSslState of
    SslNone:        ; // Nothing to do - no connection attempt even
    SslHandshake:   ; // Handshake in progress - no reason to send app data;
    SslShutdown:    ; // Shutdown in progress, no app data
    SslFailed:      ; // SSL protocol was not able to handshake, no sending
    SslClosed:      ; // Connection is closed or closing - no reason to send app data
    SslOk:
      // See if there application data to send
      if FOutgoingAppData.Size > 0 then
      begin
        repeat
        ResCode := OpenSSLImport.SSL_write(FSSL, FOutgoingAppData.Memory, FOutgoingAppData.Size);
        if ResCode > 0 then
          FOutgoingAppData.Delete(ResCode);
      until (ResCode <= 0) or (FOutgoingAppData.Size = 0);
      end;

  end;

  // See if there is sense to send service or encrypted app data
  repeat
    // Ensure outgoing encrypted data buffer has enough space
    FOutgoing.EnsureCapacity(FOutgoing.Size + TlsIncomingBufferSize);

    // Copy to buffer
    {$IFDEF Delphi2009AndUp}
    ResCode := OpenSSLImport.BIO_read(FOutputBio, FOutgoing.Memory + FOutgoing.Size, TlsIncomingBufferSize);
    {$ELSE}
    ResCode := OpenSSLImport.BIO_read(FOutputBio, PChar(FOutgoing.Memory) + FOutgoing.Size, TlsIncomingBufferSize);
    {$ENDIF}
    // Increment size of buffer
    if ResCode > 0 then
    begin
      FOutgoing.Size := FOutgoing.Size + ResCode;
    end;
  until ResCode <= 0;
end;



end.
