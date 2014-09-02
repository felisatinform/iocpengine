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
unit DnTlsBox;
interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  WS2,
  DnConst, DnRtl, DnInterfaces, DnAbstractExecutor, DnTcpReactor, DnTcpAbstractRequestor,
  DnTcpRequests, DnTcpRequestor, DnTcpChannel, DnTcpRequest,
  DnAbstractLogger, DnTlsChannel, DnTcpConnecter, DnTcpListener, DnWinsockMgr,
  DnSimpleExecutor, DnFileLogger,
  OpenSSLImport, OpenSSLUtils;

type
  TDnTlsDataAvailable = procedure (Sender: TObject; Channel: TDnTlsChannel) of object;
  TDnTlsDataWritten = procedure (Sender: TObject; Channel: TDnTlsChannel; Length: Integer) of object;
  TDnTlsError = procedure (Sender: TObject; Channel: TDnTlsChannel; ErrorCode: Integer) of object;
  TDnTlsClosed = procedure (Sender: TObject; Channel: TDnTlsChannel) of object;
  TDnTlsConnected = procedure (Sender: TObject; Channel: TDnTlsChannel) of object;

  TDnTlsBox = class(TComponent)
  protected
    FTlsDataAvailable:          TDnTlsDataAvailable;
    FTlsDataWritten:            TDnTlsDataWritten;
    FTlsError:                  TDnTlsError;
    FTlsClosed:                 TDnTlsClosed;
    FTlsConnected:              TDnTlsConnected;

    FRequestor:                 TDnTcpRequestor;
    FConnecter:                 TDnTcpConnecter;
    FReactor:                   TDnTcpReactor;
    FListener:                  TDnTcpListener;
    FWinsockMgr:                TDnWinsockMgr;
    FExecutor:                  TDnAbstractExecutor;
    FLogger:                    TDnAbstractLogger;

    FShutdown:                  Boolean; // Marks if box is shutdowning now
    FTimeout:                   Integer; // I/O timeout in seconds
    FListenerPort:              Integer; // Listener port number. Zero means no listening.
    FActive:                    Boolean; // Marks if box is operating now
    FClientCert:                TX509Certificate;
    FRootCertificatePath:       String;
    FSslCtx:                    Pointer;

    procedure TcpRequestorTcpClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
    procedure TcpRequestorTcpError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer; ErrorCode: Cardinal);
    procedure TcpRequestorTcpClientClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
    procedure TcpRequestorTcpRead(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer; Buf: PByte; BufSize: Cardinal);
    procedure TcpRequestorTcpWrite(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer; Buf: PByte; BufSize: Cardinal);
    procedure TcpRequestorTcpWriteStream(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer; Stream: TStream);
    procedure TcpConnecterConnect (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer; const IP: AnsiString; Port: Word);
    procedure TcpConnecterError (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer; ErrorCode: Cardinal);
    procedure TcpListenerChannel (Context: TDnThreadContext; Socket: TSocket; Addr: TSockAddrIn;
      Reactor: TDnTcpReactor; var ChannelImpl: TDnTcpChannel);
    procedure TcpListenerIncoming(Context: TDnThreadContext; Channel: TDnTcpChannel);

    procedure HandleTimeout(Context: TDnThreadContext; Channel: TDnTcpChannel);

    function  GetActive: Boolean;
    procedure SetActive(Value: Boolean);

    procedure DoError(Channel: TDnTlsChannel; ErrorCode: Integer);
    procedure DoClose(Channel: TDnTlsChannel);
    procedure DoDataAvailable(Channel: TDnTlsChannel);
    procedure DoConnected(Channel: TDnTlsChannel);

    procedure HandleTransmitting(Channel: TDnTlsChannel);

    {$ifdef SSL_ACCEPT_ANY_CERTIFICATE}
    class function SslCertVerify(N: Integer; X509CertStore: pX509_STORE_CTX): Integer; cdecl;
    {$endif}
    class procedure SslInfoNotify(SSL: Pointer; Where: Integer; Ret: Integer); cdecl;

  public
    class procedure InitOpenSSL;
    
    constructor   Create(AOwner: TComponent); override;
    destructor    Destroy; override;

    procedure     Open;
    procedure     Close; overload;
    procedure     LoadRootCert(const FileName: String);
    procedure     LoadClientCert(const FileName: String; const Password: RawByteString);
    function      MakeChannel(const RemoteIp: AnsiString; Port: Integer): TDnTlsChannel;
    procedure     Connect(Channel: TDnTlsChannel; const IP: AnsiString; RemotePort: Integer);
    procedure     Pump(Channel: TDnTlsChannel);
    procedure     Write(Channel: TDnTlsChannel; const Buf: RawByteString);
    procedure     Close(Channel: TDnTlsChannel; Brutal: Boolean = False); overload;

  published
    property      OnData:          TDnTlsDataAvailable      read FTlsDataAvailable        write FTlsDataAvailable;
    property      OnWritten:       TDnTlsDataWritten        read FTlsDataWritten          write FTlsDataWritten;
    property      OnClose:         TDnTlsClosed             read FTlsClosed               write FTlsClosed;
    property      OnError:         TDnTlsError              read FTlsError                write FTlsError;
    property      OnConnected:     TDnTlsConnected          read FTlsConnected            write FTlsConnected;

    property      TimeoutIO:       Integer                  read FTimeout                 write FTimeout;
    property      Active:          Boolean                  read GetActive                write SetActive;
    property      ListenerPort:    Integer                  read FListenerPort            write FListenerPort;
  end;


procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('DNet', [TDnTlsBox]);
end;

//----------------------------------------------------------------------------

class procedure TDnTlsBox.InitOpenSSL;
begin
  OpenSSLUtils.AppStartup;
end;

function SslWhereToString(Where: Integer): String;
var R: String;
begin
  if (Where and SSL_CB_LOOP) <> 0 then
    R := R + 'Loop ';
  if (Where and SSL_CB_EXIT) <> 0 then
    R := R + 'Exit ';
  if (Where and SSL_CB_READ) <> 0 then
    R := R + 'Read ';
  if (Where and SSL_CB_WRITE) <> 0 then
    R := R + 'Write ';
  if (Where and SSL_CB_ALERT) <> 0 then
    R := R + 'Alert ';

  if (Where and SSL_CB_HANDSHAKE_START) <> 0 then
    R := R + 'Handshake start ';
  if (Where and SSL_CB_HANDSHAKE_DONE) <> 0 then
    R := R + 'Handshake stop ';

  Result := R;
end;

function SslStateToString(State: Integer): String;
var R: String;
begin
  if (State and SSL_ST_CONNECT) <> 0 then
    R := 'Connect ';
  if (State and SSL_ST_MASK) <> 0 then
    R := R + 'Mask ';
  if (State and SSL_ST_BEFORE) <> 0 then
    R := R + 'Before ';
  if (State and SSL_ST_OK) <> 0 then
    R := R + 'Ok ';
  if (State and SSL_ST_RENEGOTIATE) <> 0 then
    R := R + 'Renegotiate ';

  Result := R;
end;

constructor TDnTlsBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FTlsDataAvailable := Nil;
  FTlsDataWritten := Nil;
  FTlsError := Nil;
  FTlsClosed := Nil;
  FTlsConnected := Nil;

  FWinsockMgr := TDnWinsockMgr.Create(Nil);
  FWinsockMgr.Active := True;
  FLogger := TDnFileLogger.Create(Nil);
  FExecutor := TDnSimpleExecutor.Create(Nil);
  FReactor := TDnTcpReactor.Create(Nil);
  FConnecter := TDnTcpConnecter.Create(Nil);
  FRequestor := TDnTcpRequestor.Create(Nil);
  if FListenerPort <> 0 then
    FListener := TDnTcpListener.Create(Nil);

  (FLogger as TDnFileLogger).FileName := 'TlsBox.log';
  FLogger.MinLevel := llCritical;
  FReactor.Logger := FLogger;
  FReactor.Executor := FExecutor;
  FReactor.OnTimeout := HandleTimeout;
  if Assigned(FListener) then
  begin
    FListener.Logger := FLogger;
    FListener.Executor := FExecutor;
    FListener.Reactor := FReactor;
    FListener.OnIncoming := TcpListenerIncoming;
  end;

  FRequestor.Logger := FLogger;
  FRequestor.Executor := FExecutor;
  FRequestor.Reactor := FReactor;
  FRequestor.OnError := TcpRequestorTcpError;
  FRequestor.OnClose := TcpRequestorTcpClose;
  FRequestor.OnClientClose := TcpRequestorTcpClientClose;
  FRequestor.OnRead := TcpRequestorTcpRead;
  FRequestor.OnWrite := TcpRequestorTcpWrite;
  FRequestor.OnWriteStream := TcpRequestorTcpWriteStream;
  FConnecter.OnConnect := TcpConnecterConnect;
  FConnecter.OnError := TcpConnecterError;
  FConnecter.Reactor := FReactor;
  FConnecter.Logger := FLogger;
  FConnecter.Executor := FExecutor;
end;

procedure TDnTlsBox.TcpListenerIncoming(Context: TDnThreadContext; Channel: TDnTcpChannel);
var TlsChannel: TDnTlsChannel;
begin
  if FShutdown then
    Exit;

  // Set timeout
  FReactor.SetTimeout(Channel, FTimeout);

  TlsChannel := TDnTlsChannel(Channel);
  TlsChannel.ConnectedAsServer();
end;

procedure TDnTlsBox.TcpRequestorTcpRead(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                            Buf: PByte; BufSize: Cardinal);
var TlsChannel: TDnTlsChannel;
    Code: Integer; State: Integer;
begin
  if FShutdown then
    Exit;

  TlsChannel := TDnTlsChannel(Channel);
  Code := TlsChannel.HandleReceived(Buf, BufSize);

  // Check state of SSL session
  State := OpenSSLImport.SSL_state(TlsChannel.SSL);
  OutputDebugString(PWideChar(WideString(SslStateToString(State))));

  if TlsChannel.Connected then
  begin
    DoConnected(TlsChannel);
  end;

  if TlsChannel.IncomingAppData.Size > 0 then
    DoDataAvailable(TlsChannel);

  // See final return code
  case Code of
  OpenSSLImport.SSL_ERROR_ZERO_RETURN: // Connection was closed
    begin
      Close(TlsChannel);
      DoClose(TlsChannel);
    end;

  OpenSSLImport.SSL_ERROR_WANT_READ: // More network data required to decode
    ;// Do nothing here; reading will be resumed anyway;

  OpenSSLImport.SSL_ERROR_WANT_WRITE: // Need to send smth - renegotiation can be in progress
    HandleTransmitting(TlsChannel);
  end;

  if not TlsChannel.IsClosed and not TlsChannel.IsClosing then
    FRequestor.RawRead(TlsChannel, Nil, TlsChannel.IncomingData.Memory, TlsChannel.IncomingData.Capacity);
end;

procedure TDnTlsBox.HandleTimeout(Context: TDnThreadContext; Channel: TDnTcpChannel);
begin
  // Notify about error
  DoError(TDnTlsChannel(Channel), -1);
end;

procedure TDnTlsBox.TcpRequestorTcpClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  // Notify about close
  DoClose(TDnTlsChannel(Channel));
end;

procedure TDnTlsBox.TcpRequestorTcpError(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer; ErrorCode: Cardinal);
begin
  if FShutdown then
    Exit;

  DoError(TDnTlsChannel(Channel), ErrorCode);
end;

procedure TDnTlsBox.TcpRequestorTcpClientClose(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer);
begin
  if FShutdown then
    Exit;

  Close(TDnTlsChannel(Channel), True);
end;

procedure TDnTlsBox.TcpRequestorTcpWrite(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          Buf: PByte; BufSize: Cardinal);
var TlsChannel: TDnTlsChannel;
begin
  // Memory buffer was used
  TlsChannel := TDnTlsChannel(Channel);

  // Delete sent data
  TlsChannel.OutgoingData.Delete(BufSize);

  // Sending is finished
  TlsChannel.Writing := False;

  // Restart sending if needed
  HandleTransmitting(TlsChannel);
end;

procedure TDnTlsBox.TcpRequestorTcpWriteStream(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          Stream: TStream);
begin
  // Stream was sent
  // This type of Write() API is not used in TLS box
end;

procedure TDnTlsBox.TcpConnecterConnect (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer; const IP: AnsiString; Port: Word);
var TlsChannel: TDnTlsChannel;
begin
  if FShutdown then
    Exit;

  TlsChannel := TDnTlsChannel(Channel);
  TlsChannel.ConnectedAsClient();

  // Start reading
  FRequestor.RawRead(TlsChannel, Nil, TlsChannel.IncomingData.Memory, TlsChannel.IncomingData.Capacity);

  //Pump(TlsChannel);

  // Start reading
  //FRequestor.Read(Channel, Nil, TlsChannel.IncomingData.Memory, TlsChannel.IncomingData.Capacity);

  // Ensure everything is written
  HandleTransmitting(TlsChannel);
end;

procedure TDnTlsBox.TcpConnecterError (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer; ErrorCode: Cardinal);
begin
  DoError(TDnTlsChannel(Channel), ErrorCode);
end;

procedure TDnTlsBox.TcpListenerChannel (Context: TDnThreadContext; Socket: TSocket; Addr: TSockAddrIn;
      Reactor: TDnTcpReactor; var ChannelImpl: TDnTcpChannel);
begin
  ChannelImpl := TDnTlsChannel.CreateServer(Reactor, Socket, Addr, FSslCtx);
end;

destructor TDnTlsBox.Destroy;
begin
  Active := False;
  FreeAndNil(FConnecter);
  FreeAndNil(FListener);
  FreeAndNil(FRequestor);
  FreeAndNil(FReactor);
  FreeAndNil(FLogger);
  FreeAndNil(FExecutor);

  FreeAndNil(FClientCert);
  inherited Destroy;
end;

procedure TDnTlsBox.Open;
var ResCode: Integer;
begin
  FActive := True;

  FSslCtx := OpenSSLImport.SSL_CTX_new(OpenSSLImport.SSLv23_method());
  if not Assigned(FSslCtx) then
    raise EDnSslException.Create(OpenSSLImport.ERR_get_error());

  // Set state change callback
  OpenSSLImport.SSL_CTX_set_info_callback(FSslCtx, @TDnTlsBox.SslInfoNotify);

  // Set root certificate
  if Length(FRootCertificatePath) > 0 then
  begin
    ResCode := OpenSSLImport.SSL_CTX_load_verify_locations(FSslCtx, PAnsiChar(AnsiString(FRootCertificatePath)), Nil);
    if ResCode <> 1 then
      raise EDnSslException.Create(OpenSSLImport.ERR_get_error());
  end;

  // Set client certificate
  if Assigned(FClientCert) then
  begin
    ResCode := OpenSSLImport.SSL_CTX_use_certificate(FSslCtx, FClientCert.X509);
    if ResCode <> 1 then
      raise EDnSslException.Create(OpenSSLImport.ERR_get_error());
  end;

  FWinsockMgr.Active := True;
  FExecutor.Active := True;
  FReactor.Active := True;
  FRequestor.Active := True;
  if FListenerPort <> 0 then
  begin
    FListener.Port := FListenerPort;
    FListener.Active := True;
  end;
  FConnecter.Active := True;
end;

procedure TDnTlsBox.Close;
begin
  FActive := False;
  FShutdown := True;

  if Assigned(FListener) then
  begin
    if FListener.Active then
    begin
      FListener.Active := False;
      FListener.WaitForShutdown(5000);
    end;
  end;

  FConnecter.Active := False;
  // Stop requestor - new requests will be ignored or exceptions raised
  FRequestor.Active := False;

  // Stop reactor
  FReactor.Active := False;
  FExecutor.Active := False;
  FLogger.Active := False;

  if Assigned(FSslCtx) then
  begin
    OpenSSLImport.SSL_CTX_free(FSslCtx);
    FSslCtx := Nil;
  end;
end;

procedure TDnTlsBox.LoadRootCert(const FileName: String);
begin
  if not FileExists(FileName) then
    raise EDnException.Create('No root certificate');
  FRootCertificatePath := Filename;
end;

procedure TDnTlsBox.LoadClientCert(const FileName: String; const Password: RawByteString);
begin
  FreeAndNil(FClientCert);
  try
    FClientCert := TX509Certificate.Create();
    FClientCert.LoadFromFile(Filename, OpenSSLUtils.PKCS12, PAnsiChar(@Password[1]));
  finally
    FreeAndNil(FClientCert);
  end;
end;

function TDnTlsBox.GetActive: Boolean;
begin
  Result := FActive;
end;

procedure TDnTlsBox.SetActive(Value: Boolean);
begin
  if Active <> Value then
  begin
    if Active then
      Close
    else
      Open;
  end;
end;

procedure TDnTlsBox.DoError(Channel: TDnTlsChannel; ErrorCode: Integer);
begin
  if Assigned(FTlsError) then
  try
    FTlsError(Self, Channel, ErrorCode);
  except
  end;
end;

procedure TDnTlsBox.DoClose(Channel: TDnTlsChannel);
begin
  if Assigned(FTlsClosed) then
  try
    FTlsClosed(Self, Channel);
  except
  end;
end;

procedure TDnTlsBox.DoDataAvailable(Channel: TDnTlsChannel);
begin
  if Assigned(FTlsDataAvailable) then
  try
    FTlsDataAvailable(Self, Channel);
  except
  end;
end;

procedure TDnTlsBox.DoConnected(Channel: TDnTlsChannel);
begin
  if Assigned(FTlsConnected) then
  try
    FTlsConnected(Self, Channel);
  except
  end;
end;

procedure TDnTlsBox.HandleTransmitting(Channel: TDnTlsChannel);
begin
  // See if channel is already sending
  if Channel.Writing then
    Exit;

  // See if there is outgoing application data
  Channel.CheckDataToSend();

  // If there is outgoing encrypted data
  if Channel.OutgoingData.Size > 0 then
  begin
    // Mark channel as sending
    Channel.Writing := True;

    // Start sending
    FRequestor.Write(Channel, Nil, Channel.OutgoingData.Memory, Channel.OutgoingData.Size);
  end
  else
    Channel.Writing := False;
end;

{$ifdef SSL_ACCEPT_ANY_CERTIFICATE}
class function TDnTlsBox.SslCertVerify(N: Integer; X509CertStore: pX509_STORE_CTX): Integer; cdecl;
begin
  Result := 1;
end;
{$endif}


class procedure TDnTlsBox.SslInfoNotify(SSL: Pointer; Where: Integer; Ret: Integer); cdecl;
var Msg: WideString;
begin
  Msg := 'Where: ' + IntToStr(Where) + ' ' + SslWhereToString(Where) + ' ret: ' + IntToStr(Ret);
  OutputDebugString(PWideChar(Msg));
end;

function TDnTlsBox.MakeChannel(const RemoteIp: AnsiString; Port: Integer): TDnTlsChannel;
var ResCode: Integer;
begin
  Result := TDnTlsChannel.CreateClient(FReactor, RemoteIp, Port, FSslCtx);

  {$ifdef SSL_ACCEPT_ANY_CERTIFICATE}
  OpenSSLImport.SSL_set_verify(Result.SSL, OpenSSLImport.SSL_VERIFY_PEER, @TDnTlsBox.SslCertVerify);
  {$endif}
end;

procedure TDnTlsBox.Connect(Channel: TDnTlsChannel; const IP: AnsiString; RemotePort: Integer);
begin
  // Open TCP connection at first
  FConnecter.Connect(Channel, Nil, Self.FTimeout);
end;

procedure TDnTlsBox.Close(Channel: TDnTlsChannel; Brutal: Boolean);
begin
end;

procedure TDnTlsBox.Pump(Channel: TDnTlsChannel);
begin
  // Track I/O on channel
  FReactor.PostChannel(Channel);

  // Start reading
  FRequestor.RawRead(Channel, Nil, Channel.IncomingData.Memory, Channel.IncomingData.Capacity);
end;

procedure TDnTlsBox.Write(Channel: TDnTlsChannel; const Buf: RawByteString);
begin
  // Put data to outgoing application data queue and ask to encode it and send
  Channel.OutgoingAppData.AppendString(Buf);

  // Ensure data are sending
  HandleTransmitting(Channel);
end;

end.


