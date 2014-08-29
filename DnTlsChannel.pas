unit DnTlsChannel;
interface
uses
  Classes, SysUtils,
  DnConst, DnRtl, DnTcpChannel, DnDataQueue,
  OpenSSLImport, OpenSSLUtils;

const
  TlsDecodedBufferSize = 16384;
  TlsIncomingBufferSize = 16384;

type
  TDnTlsChannel = class(TDnTcpChannel)
  protected
    // OpenSSL's BIO buffers
    FInputBio, FOutputBio: PBIO;

    // OpenSSL's SSL_CTX structure
    FSSL_CTX: Pointer;

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

    procedure InitChannel; override;

  public
    destructor Destroy; override;

    // Processes via OpenSSL received data. Returns length of available application data.
    function HandleReceived(Buffer: PByte; Size: Integer): Integer;

    // Checks if there is data generated by SSL to send and moves this data to OutgoingData
    procedure CheckDataToSend;

    procedure ConnectedAsClient;
    procedure ConnectedAsServer;

    property Writing: Boolean read FWriting write FWriting;
    property SSL: Pointer read FSSL write FSSL;
    property InputBio: PBIO read FInputBio write FOutputBio;
    property OutputBio: PBIO read FOutputBio write FOutputBio;

    property OutgoingAppData: TDnDataQueue read FOutgoingAppData;
    property IncomingAppData: TDnDataQueue read FIncomingAppData;
    property OutgoingData: TDnDataQueue read FOutgoing;
    property IncomingData: TDnDataQueue read FIncoming;
  end;

implementation

procedure TDnTlsChannel.InitChannel;
begin
  FWriting := False;
  FIncomingAppData := TDnDataQueue.Create(TlsDecodedBufferSize, TlsDecodedBufferSize);
  FOutgoingAppData := TDnDataQueue.Create(TlsDecodedBufferSize, TlsDecodedBufferSize);
  FIncoming := TDnDataQueue.Create(TlsIncomingBufferSize, TlsIncomingBufferSize);
  FOutgoing := TDnDataQueue.Create(TlsIncomingBufferSize, TlsIncomingBufferSize);

  FSSL_CTX := OpenSSLImport.SSL_CTX_new(OpenSSLImport.SSLv23_method());
  if not Assigned(FSSL_CTX) then
    raise EDnException.Create(ErrSSL, OpenSSLImport.ERR_get_error());
  FSSL := OpenSSLImport.SSL_new(FSSL_CTX);
  if not Assigned(FSSL) then
    raise EDnException.Create(ErrSSL, OpenSSLImport.ERR_get_error());

  FInputBio := OpenSSLImport.BIO_new(OpenSSLImport.BIO_s_mem);
  FOutputBio := OpenSSLImport.BIO_new(OpenSSLImport.BIO_s_mem);
  OpenSSLImport.SSL_set_bio(FSSL, FInputBio, FOutputBio);
end;

destructor TDnTlsChannel.Destroy;
begin
  // FInputBio and FOutputBio are linked into FSSL context - it owns buffers so no delete them
  FInputBio := Nil;
  FOutputBio := Nil;

  if Assigned(FSSL) then
  begin
    OpenSSLImport.SSL_free(FSSL);
    FSSL := Nil;
  end;

  if Assigned(FSSL_CTX) then
  begin
    OpenSSLImport.SSL_CTX_free(FSSL_CTX);
    FSSL_CTX := Nil;
  end;
  FreeAndNil(FOutgoing);
  FreeAndNil(FIncoming);
  FreeAndNil(FIncomingAppData);
  FreeAndNil(FOutgoingAppData);

  inherited Destroy;
end;

procedure TDnTlsChannel.ConnectedAsClient;
var ResCode: Integer;
begin
  ResCode := OpenSSLImport.SSL_connect(FSSL);
end;

procedure TDnTlsChannel.ConnectedAsServer;
var ResCode: Integer;
begin
  ResCode := OpenSSLImport.SSL_accept(FSSL);
end;

function TDnTlsChannel.HandleReceived(Buffer: PByte; Size: Integer): Integer;
var
    ResCode: Integer;
begin
  // Send received data to OpenSSL associated buffer
  if OpenSSLImport.BIO_write(FInputBio, Buffer, Size) < 1 then
    raise EDnException.Create(ErrSsl, OpenSSLImport.ERR_get_error);

  // See how much was received application data
  repeat
    // Ensure there is enough space in FDecoded buffer
    FIncomingAppData.EnsureCapacity(FIncomingAppData.Size + TlsDecodedBufferSize);

    // Decode data
    ResCode := OpenSSLImport.SSL_read(FSSL, FIncomingAppData.Memory + FIncomingAppData.Size, TlsDecodedBufferSize);

    if ResCode > 0 then
      FIncomingAppData.Size := FIncomingAppData.Size + ResCode;

  until ResCode <= 0;

  Result := OpenSSLImport.SSL_get_error(FSSL, ResCode);
end;

procedure TDnTlsChannel.CheckDataToSend;
var ResCode: Integer;
begin
  // See if there is outgoing application data
  if FOutgoingAppData.Size > 0 then
  begin
    repeat
      ResCode := OpenSSLImport.SSL_write(FSSL, FOutgoingAppData.Memory, FOutgoingAppData.Size);
      if ResCode > 0 then
        FOutgoingAppData.Delete(ResCode);
    until ResCode <= 0;
  end;

  repeat
    // Ensure outgoing encrypted data buffer has enough space
    FOutgoing.EnsureCapacity(FOutgoing.Size + TlsIncomingBufferSize);

    // Copy to buffer
    ResCode := OpenSSLImport.BIO_read(FOutputBio, FOutgoing.Memory + FOutgoing.Size, TlsIncomingBufferSize);

    // Increment size of buffer
    if ResCode > 0 then
      FOutgoing.Size := FOutgoing.Size + ResCode;
  until ResCode <= 0;
end;



end.
