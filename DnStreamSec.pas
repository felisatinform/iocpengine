{$I DnConfig.inc}
unit DnStreamSec;
interface
uses
  Classes, Math, SysUtils,
  DnDataDecorator
{$IFDEF ENABLE_STREAMSEC}
  ,MpX509, TlsInternalServer, SecComp, StreamSecII, SecUtils, TlsLayer, TlsClass, MpYarrow
{$ENDIF}
  ;

{$IFDEF ENABLE_STREAMSEC}
type
  TDnTlsDecorator = class(TDnDataDecorator)
  protected
    FTlsServer:       TSimpleTLSInternalServer;
    FClient:          Boolean;
    FTLSErrorCode:    Integer;
    FRawData,
    FAppData:         TMemoryStream;
    
    function      GetState: TDnDecoratorState; override;
    function      GetErrorCode: Cardinal; override;
    function      GetErrorMsg: String; override;

  public
    constructor   Create(Client: Boolean; TLSServer: TSimpleTLSInternalServer);
    destructor    Destroy; override;

    procedure     Connect; override;
    procedure     SendData(BufPtr: Pointer; BufSize: Integer); override;
    procedure     ReceiveData(BufPtr: Pointer; BufSize: Integer); override;
    procedure     Close; override;

    function      ExtractRawData(MaxSize: Cardinal = $FFFFFFFF): AnsiString; override;
    function      ExtractAppData(MaxSize: Cardinal = $FFFFFFFF): AnsiString; override;
    function      AppDataSize: Cardinal; override;
    function      RawDataSize: Cardinal; override;
    function      ObjectSize: Integer; override;

    procedure     TestSetup;

  end;
{$ENDIF}

implementation

{$IFDEF ENABLE_STREAMSEC}
constructor TDnTlsDecorator.Create(Client: Boolean; TLSServer: TSimpleTLSInternalServer);
begin
  inherited Create;
  FTlsServer := TLSServer;
  FClient := Client;
  FTLSErrorCode := 0;
end;

destructor TDnTlsDecorator.Destroy;
begin
  inherited Destroy;
end;

function TDnTlsDecorator.GetState: TDnDecoratorState;
begin
  if FTLSErrorCode <> 0 then
    Result := ddFailed
  else
    Result := ddOk;
end;

function TDnTlsDecorator.GetErrorCode: Cardinal;
begin
  Result := FTLSErrorCode;
end;

function TDnTlsDecorator.GetErrorMsg: String;
begin
  Result := Format('TLS error with code %d', [FTLSErrorCode]);
end;

procedure TDnTlsDecorator.TestSetup;
begin
  if FClient then
    FTLSServer.LoadRootCertsFromFile('root.cer')
  else
  begin
    FTLSServer.LoadPrivateKeyRingFromFile('user.pkr', Nil);
    FTLSServer.LoadRootCertsFromFile('root.cer');
    FTLSServer.LoadMyCertsFromFile('test.cer');
    FTLSServer.Options.KeyAgreementRSA := prPrefer;
    FTLSServer.Options.KeyAgreementDHE := prNotAllowed;
    FTLSServer.Options.SignatureAnon := prNotAllowed;
    FTLSServer.Options.EphemeralRSAKeySize := 0;
    FTLSServer.Options.Export40Bit := prNotAllowed;
    FTLSServer.Options.Export56Bit := prNotAllowed;
    FTLSServer.TLSSetupServer;
  end;
end;

procedure TDnTlsDecorator.Connect;
begin
  FTLSServer.TLSConnect(Self, FRawData, @FTLSErrorCode);
end;

procedure     TDnTlsDecorator.SendData(BufPtr: Pointer; BufSize: Integer);
var Data: TMemoryStream;
begin
  Data := TMemoryStream.Create;
  Data.Write(PChar(BufPtr)^, BufSize);
  Data.Position := 0;  
  FTLSServer.TLSEncodeData(Self, Data, FRawData, @FTLSErrorCode);
  Data.Free;
end;

procedure     TDnTlsDecorator.ReceiveData(BufPtr: Pointer; BufSize: Integer);
var Data: TMemoryStream;
begin
  Data := TMemoryStream.Create;
  Data.Write(PChar(BufPtr)^, BufSize);
  Data.Position := 0;
  FTLSServer.TLSDecodeData(Self, Data, FAppData, FRawData, @FTLSErrorCode);
  Data.Free;
end;

procedure     TDnTlsDecorator.Close;
begin
  FTLSServer.TLSClose(Self, FRawData, @FTLSErrorCode);
end;

function    TDnTlsDecorator.ExtractRawData(MaxSize: Cardinal = $FFFFFFFF): AnsiString;
var Avail: Int64;
begin
  Avail := Min(MaxSize, FRawData.Size);
  SetLength(Result, Avail);
  FRawData.ReadBuffer(Result[1], Avail);
end;

function    TDnTlsDecorator.ExtractAppData(MaxSize: Cardinal = $FFFFFFFF): AnsiString;
var Avail: Int64;
begin
  Avail := Min(MaxSize, FAppData.Size);
  SetLength(Result, Avail);
  FAppData.ReadBuffer(Result[1], Avail);
end;

function    TDnTlsDecorator.AppDataSize: Cardinal;
begin
  Result := FAppData.Size;
end;

function    TDnTlsDecorator.RawDataSize: Cardinal;
begin
  Result := FRawData.Size;
end;

function TDnTlsDecorator.ObjectSize: Integer;
begin
  Result := InstanceSize + FRawData.Size + FAppData.Size + FTlsServer.InstanceSize;
end;

{$ENDIF}

end.
