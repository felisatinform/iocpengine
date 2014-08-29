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
unit DnTlsRequestor_StreamSec;
interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  WS2,
  DnConst, DnRtl, DnInterfaces, DnTcpReactor, DnTcpAbstractRequestor,
  DnTlsRequests_StreamSec, DnTcpRequests, DnTcpRequestor, DnTcpChannel, DnTcpRequest,
  DnAbstractLogger,
  StreamSecII, TlsClass, MpX509, Asn1,
  TlsInternalServer, SecComp, SecUtils;

type
  TDnCRequestFinished = procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer) of object;
  //TDnCRequestError = procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer; ErrorCode: Cardinal);
  TDnSResponseFinished = procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer) of object;
  //TDnSResponseError = procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer; ErrorCode: Cardinal);
  TDnTlsHandshakeResponse = procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer; Response: String) of object;
  TDnTlsCloseNotify = procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer) of object;
  TDnTlsCloseNotifyFinished = procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer) of object;
  TDnTlsHandshakeFinished = procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer) of object;
  
  TDnTlsRequestor = class(TDnTcpAbstractRequestor,
                          IDnTcpWriteHandler,
                          IDnTcpCloseHandler,
                          IDnTlsLineHandler,
                          IUnknown, IDnTlsCRequestHandler,
                          IDnTlsSResponseHandler,
                          IDnTlsReadHandler,
                          IDnTlsCloseNotifyHandler)
  protected
    //it is TLS specific events
    FTlsCRequestFinished:       TDnCRequestFinished;
    FTlsSResponseFinished:      TDnSResponseFinished;
    FTlsHandshakeResponse:      TDnTlsHandshakeResponse;
    FTlsCloseNotify:            TDnTlsCloseNotify;
    FTlsCloseNotifyFinished:    TDnTlsCloseNotifyFinished;
    FTlsHandshakeFinished:      TDnTlsHandshakeFinished;

    FTcpError:                  TDnTcpError;
    FTcpRead:                   TDnTcpRead;
    FTcpWrite:                  TDnTcpWrite;
    FTcpClose:                  TDnTcpClose;
    FTcpClientClose:            TDnTcpClientClose;
    FTcpLine:                   TDnTcpLine;

    //the references to external TLS components
    FTlsClient:       TSimpleTLSInternalServer;
    FTlsServer:       TSimpleTLSInternalServer;
    FClientPKR,
    FServerPKR:  TSsPrivateKeyRingComponent;
    //IDnTlsCRequestHandler = interface
    procedure DoTlsCRequestFinished(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
    procedure DoTlsCRequestError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);

    //IDnTlsSResponseHandler = interface
    procedure DoTlsSResponseFinished(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
    procedure DoTlsSResponseError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);

    //IDnTlsReadHandler = interface
    procedure DoHandshake(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                            Handshake: String);
    procedure DoRead(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  Buf: PChar; BufSize: Cardinal);
    procedure DoReadError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);
    procedure DoReadClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);


    //IDnTlsCloseNotifyHandler = interface
    procedure DoTlsCloseNotifyFinished(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
    procedure DoTlsCloseNotifyError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                    ErrorCode: Cardinal);

    //IDnTcpWriteHandler
    procedure DoWrite(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           Buf: PChar; BufSize: Cardinal);
    procedure DoWriteError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           ErrorCode: Cardinal);
    procedure DoWriteStream(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                      Stream: TStream);


    //IDnTcpCloseHandler
    procedure DoCloseError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           ErrorCode: Cardinal);
    procedure DoClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);

    //IDnTlsLineHandHandler
    procedure DoLineHandshake( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                        Response: String);
    procedure DoLine( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                      ReceivedLine: String; EolFound: Boolean );
    procedure DoLineError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           ErrorCode: Cardinal);
    procedure DoLineClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);


    procedure DoClientClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
    procedure DoError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                      ErrorCode: Cardinal);
    procedure DoTlsCloseNotify(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);

    procedure TLSServerPassword(Sender: TObject; Password: ISecretKey);
    procedure ClientChangeCipherSpec(Sender: TObject; Client: TCustomTLS_ContentLayer);
    procedure ServerChangeCipherSpec(Sender: TObject; Client: TCustomTLS_ContentLayer);
    procedure ServerIncomingAlert(Sender: TObject; Client: TCustomTLS_ContentLayer;
                              var Fatal: Boolean; AlertCode: Integer);
    procedure ServerOutgoingAlert(Sender: TObject; Client: TCustomTLS_ContentLayer;
                              var Fatal: Boolean; AlertCode: Integer);
    procedure ClientIncomingAlert(Sender: TObject; Client: TCustomTLS_ContentLayer;
                              var Fatal: Boolean; AlertCode: Integer);
    procedure ClientOutgoingAlert(Sender: TObject; Client: TCustomTLS_ContentLayer;
                              var Fatal: Boolean; AlertCode: Integer);

(*    procedure BeforeImportTLSCert(Sender: TObject; Cert: TASN1Struct;
                var ExplicitTrust: Boolean; var AllowExpired: Boolean); *)
  public
    constructor Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent);override{$ENDIF};
    destructor Destroy; override;

    procedure     TestSetup(const CertPath: String; Password: WideString);
    procedure     ClientHandshakeRequest(Channel: TDnTcpChannel; Key: Pointer);
    procedure     ServerHandshakeResponse(Channel: TDnTcpChannel; Key: Pointer; Response: String);

    procedure     Read(Channel: TDnTcpChannel; Key: Pointer; Buf: PChar; BufSize: Cardinal);
    procedure     ReadString(Channel: TDnTcpChannel; Key: Pointer; Size: Integer);
    procedure     RawRead(Channel: TDnTcpChannel; Key: Pointer; Buf: PChar; MaxSize: Cardinal);
    procedure     WriteString(Channel: TDnTcpChannel; Key: Pointer; Buf: String);
    procedure     CloseNotify(Channel: TDnTcpChannel; Key: Pointer);
    procedure     Close(Channel: TDnTcpChannel; Key: Pointer; Brutal: Boolean = False);
    procedure     ReadLine(Channel: TDnTcpChannel; Key: Pointer; MaxSize: Cardinal);
  published

    property      OnRead:                     TDnTcpRead                read FTcpRead                 write FTcpRead;
    property      OnWrite:                    TDnTcpWrite               read FTcpWrite                write FTcpWrite;
    property      OnClose:                    TDnTcpClose               read FTcpClose                write FTcpClose;
    property      OnError:                    TDnTcpError               read FTcpError                write FTcpError;
    property      OnLineRead:                 TDnTcpLine                read FTcpLine                 write FTcpLine;
    property      OnClientClose:              TDnTcpClientClose         read FTcpClientClose          write FTcpClientClose;
    property      OnTlsCRequestFinished:      TDnCRequestFinished       read FTlsCRequestFinished     write FTlsCRequestFinished;
    property      OnTlsSResponseFinished:     TDnSResponseFinished      read FTlsSResponseFinished    write FTlsSResponseFinished;
    property      OnTlsHandshakeResponse:     TDnTlsHandshakeResponse   read FTlsHandshakeResponse    write FTlsHandshakeResponse;
    property      OnTlsCloseNotify:           TDnTlsCloseNotify         read FTlsCloseNotify          write FTlsCloseNotify;
    property      OnTlsCloseNotifyFinished:   TDnTlsCloseNotifyFinished read FTlsCloseNotifyFinished  write FTlsCloseNotifyFinished;
    property      OnTlsHandshakeFinished:     TDnTlsHandshakeFinished   read FTlsHandshakeFinished    write FTlsHandshakeFinished;

    property TlsClient: TSimpleTLSInternalServer read FTlsClient write FTlsClient;
    property TlsServer: TSimpleTLSInternalServer read FTlsServer write FTlsServer;
  end;


procedure Register;

implementation

procedure Register;
begin
  {$IFDEF ROOTISCOMPONENT}
  RegisterComponents('DNet', [TDnTlsRequestor]);
  {$ENDIF}
end;

//----------------------------------------------------------------------------

constructor TDnTlsRequestor.Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent){$ENDIF};
begin
  inherited Create{$IFDEF ROOTISCOMPONENT}(AOwner){$ENDIF};
  FTcpRead := Nil;
  FTcpWrite := Nil;
  FTcpError := Nil;
  FTcpClose := Nil;
  FTcpLine := Nil;
  FTcpClientClose := Nil;
  FServerPKR := TSsPrivateKeyRingComponent.Create(Nil);
  with FServerPKR do
  begin
    AllowPlainTextKeys := True;
    CacheKeyInterfaces := False;
    DefaultHashAlgorithm := haSHA1;
    SessionKeyLifeSpan := 0.020833333333333330;
    OnAdminPassword := TlsServerPassword;
    OnPassword := TlsServerPassword;
  end;
  FTlsServer := TSimpleTLSInternalServer.Create(Nil);
  with FTlsServer do
  begin
    ClientOrServer := cosServerSide;
    PrivateKeyRing := FServerPKR;
    OnTLSChangeCipherSpec := ServerChangeCipherSpec;
    OnTLSIncomingAlert := ServerIncomingAlert;
    OnTLSOutgoingAlert := ServerOutgoingAlert;
  end;

  FClientPKR := TSsPrivateKeyRingComponent.Create(Nil);
  with FClientPKR do
  begin
    AllowPlainTextKeys := True;
    CacheKeyInterfaces := False;
    DefaultHashAlgorithm := haSHA1;
    SessionKeyLifeSpan := 0.020833333333333330;
    OnAdminPassword := TlsServerPassword;
    OnPassword := TlsServerPassword;
  end;
  FTlsClient := TSimpleTLSInternalServer.Create(Nil);
  with FTlsClient do
  begin
    ClientOrServer := cosClientSide;
    PrivateKeyRing := FClientPKR;
    OnTLSChangeCipherSpec := ServerChangeCipherSpec;
    OnTLSIncomingAlert := ServerIncomingAlert;
    OnTLSOutgoingAlert := ServerOutgoingAlert;
  end;

end;

destructor TDnTlsRequestor.Destroy;
begin
  FTlsServer.Free;
  FTlsClient.Free;
  FServerPKR.Free;
  FClientPKR.Free;
  inherited Destroy;
end;

procedure  TDnTlsRequestor.TestSetup(const CertPath: String; Password: WideString);
begin
  with FTLSServer do
  begin
    LoadRootCertsFromFile('root.cer');
    ImportFromPFX('server.pfx', TSecretKey.CreateBMPStr(PWideChar(Password)));
    Options.SignatureRSA := prPrefer;
    Options.KeyAgreementRSA := prPrefer;
    Options.KeyAgreementDHE := prNotAllowed;
    Options.RequestClientCertificate := False;
    Options.RequireClientCertificate := False;
    TLSSetupServer;
  end;

  with FTLSClient do
  begin
    LoadRootCertsFromFile('root.cer');
    //ImportFromPFX('client.pfx', TSecretKey.CreateBMPStr(PWideChar(Password)));
    Options.SignatureRSA := prPrefer;
    Options.SignatureRSA := prPrefer;
    Options.KeyAgreementRSA := prPrefer;
    Options.KeyAgreementDHE := prNotAllowed;
    Options.VerifyServerName := [];
    TLSSetupServer;
  end;
end;


procedure TDnTlsRequestor.ClientHandshakeRequest(Channel: TDnTcpChannel; Key: Pointer);
var Request: TDnTcpRequest;
begin
  CheckAvail;
  if Channel.IsClient then
  begin
    Request := TDnTlsCRequest.Create(Channel, Key, Self, FTlsClient);
    Channel.RunRequest(Request);
  end
  else
    raise Exception.Create('Attempt to run TLS client request on non-client channel.');
end;



procedure TDnTlsRequestor.ServerHandshakeResponse(Channel: TDnTcpChannel; Key: Pointer; Response: String);
var
  Request : TDnTcpRequest;
begin
  CheckAvail;

  Request := TDnTlsSResponse.CreateFromString(Channel, Key, Self, FTlsServer, Response);
  Channel.RunRequest(Request);
end;

procedure TDnTlsRequestor.Read(Channel: TDnTcpChannel; Key: Pointer; Buf: PChar;
                              BufSize: Cardinal);
var Request: TDnTcpRequest;
begin
  CheckAvail;
  if Channel.IsClient then
    Request := TDnTlsReadRequest.Create(Channel, Key, Self, Buf, BufSize, True, FTlsClient)
  else
    Request := TDnTlsReadRequest.Create(Channel, Key, Self, Buf, BufSize, True, FTlsServer);

  Channel.RunRequest(Request);
end;

procedure TDnTlsRequestor.ReadString(Channel: TDnTcpChannel; Key: Pointer; Size: Integer);
var Request: TDnTcpRequest;
begin
  CheckAvail;
  if Channel.IsClient then
    Request := TDnTlsReadRequest.CreateString(Channel, Key, Self, Size, True, FTlsClient)
  else
    Request := TDnTlsReadRequest.CreateString(Channel, Key, Self, Size, True, FTlsServer);
    
  Channel.RunRequest(Request);
end;

procedure TDnTlsRequestor.RawRead(Channel: TDnTcpChannel; Key: Pointer; Buf: PChar; MaxSize: Cardinal);
var Request: TDnTcpRequest;
begin
  CheckAvail;
  if Channel.IsClient then
    Request := TDnTlsReadRequest.Create(Channel, Key, Self, Buf, MaxSize, False, FTlsClient)
  else
    Request := TDnTlsReadRequest.Create(Channel, Key, Self, Buf, MaxSize, False, FTlsServer);

  Channel.RunRequest(Request);
end;

(*procedure TDnTlsRequestor.Write(Channel: TDnTcpChannel; Key: Pointer; Buf: PChar; BufSize: Cardinal);
var Request: TDnTcpRequest;
begin
  CheckAvail;
  if Channel.IsClient then
    Request := TDnTlsWriteRequest.Create(Channel, Key, Self, Buf, BufSize, FTlsClient)
  else
    Request := TDnTlsWriteRequest.Create(Channel, Key, Self, Buf, BufSize, FTlsServer);

  Channel.RunRequest(Request);
end;*)

procedure TDnTlsRequestor.WriteString(Channel: TDnTcpChannel; Key: Pointer; Buf: String);
var Request: TDnTcpRequest;
begin
  CheckAvail;
  if Channel.IsClient then
    Request := TDnTlsWriteRequest.CreateString(Channel, Key, Self, Buf, FTlsClient)
  else
    Request := TDnTlsWriteRequest.CreateString(Channel, Key, Self, Buf, FTlsServer);

  Channel.RunRequest(Request);
end;

procedure TDnTlsRequestor.CloseNotify(Channel: TDnTcpChannel; Key: Pointer);
var Request: TDnTcpRequest;
begin
  CheckAvail;
  if Channel.IsClient then
    Request := TDnTlsCloseNotifyRequest.Create(Channel, Key, Self, FTlsClient)
  else
    Request := TDnTlsCloseNotifyRequest.Create(Channel, Key, Self, FTlsServer);

  Channel.RunRequest(Request);
end;

procedure TDnTlsRequestor.Close(Channel: TDnTcpChannel; Key: Pointer; Brutal: Boolean);
var Request: TDnTcpRequest;
begin
  CheckAvail;
  Request := TDnTlsCloseRequest.Create(Channel, Key, Self, Brutal);
  Channel.RunRequest(Request);
end;

procedure TDnTlsRequestor.ReadLine(Channel: TDnTcpChannel; Key: Pointer; MaxSize: Cardinal);
var Request: TDnTcpRequest;
begin
  CheckAvail;
  if Channel.IsClient then
    Request := TDnTlsLineRequest.Create(Channel, Key, Self, MaxSize, FTlsClient)
  else
    Request := TDnTlsLineRequest.Create(Channel, Key, Self, MaxSize, FTlsServer);

  Channel.RunRequest(Request);
end;

procedure TDnTlsRequestor.DoTlsCRequestFinished(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  try
    if Assigned(Self.FTlsCRequestFinished) then
      Self.FTlsCRequestFinished(Context, Channel, Key);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTlsRequestor.DoTlsCRequestError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                            ErrorCode: Cardinal);
begin
  try
    if Assigned(Self.FTcpError) then
      Self.FTcpError(Context, Channel, Key, ErrorCode);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTlsRequestor.DoTlsSResponseFinished(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  try
    if Assigned(Self.FTlsSResponseFinished) then
      Self.FTlsSResponseFinished(Context, Channel, Key);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTlsRequestor.DoTlsSResponseError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);
begin
  Self.DoError(Context, Channel, Key, ErrorCode);
end;

procedure TDnTlsRequestor.DoHandshake(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                            Handshake: String);
begin
  try
    if Assigned(Self.FTlsHandshakeResponse) then
      Self.FTlsHandshakeResponse(Context, Channel, Key, Handshake);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTlsRequestor.DoRead( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  Buf: PChar; BufSize: Cardinal);
begin
  try
    if Assigned(FTcpRead) then
      FTcpRead(Context, Channel, Key, Buf, BufSize);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTlsRequestor.DoReadError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                      ErrorCode: Cardinal);
begin
  Self.DoError(Context, Channel, Key, ErrorCode);
end;

procedure TDnTlsRequestor.DoReadClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  Self.DoClientClose(Context, Channel, Key);
end;

procedure TDnTlsRequestor.DoTlsCloseNotifyFinished(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  try
    if Assigned(FTlsCloseNotifyFinished) then
      FTlsCloseNotifyFinished(Context, Channel, Key);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;

end;

procedure TDnTlsRequestor.DoTlsCloseNotifyError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                    ErrorCode: Cardinal);
begin
  Self.DoError(Context, Channel, Key, ErrorCode);
end;

procedure TDnTlsRequestor.DoWrite(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  Buf: PChar; BufSize: Cardinal);
begin
  try
    if Assigned(FTcpWrite) then
      FTcpWrite(Context, Channel, Key, Buf, BufSize);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTlsRequestor.DoWriteStream(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                          Stream: TStream);
begin
  Assert(False, 'Not implemented.');
end;
procedure TDnTlsRequestor.DoWriteError( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                        ErrorCode: Cardinal );
begin
  Self.DoError(Context, Channel, Key, ErrorCode);
end;

procedure TDnTlsRequestor.DoError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);
begin
  try
    if Assigned(FTcpError) then
      FTcpError(Context, Channel, Key, ErrorCode);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTlsRequestor.DoTlsCloseNotify(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);
begin
  try
    if Assigned(FTLSCloseNotify) then
      DoTLSCloseNotify(Context, Channel, Key, ErrorCode);
  except
    on E: Exception do
      PostLogMessage(E.Message);
  end;
end;

procedure TDnTlsRequestor.TLSServerPassword(Sender: TObject; Password: ISecretKey);
begin
  Password.SetLength(3);
  Password.SetKeyStrAt('abc',0);
end;

procedure TDnTlsRequestor.ClientChangeCipherSpec(Sender: TObject; Client: TCustomTLS_ContentLayer);
begin
  //handshake is finished
end;

procedure TDnTlsRequestor.ServerChangeCipherSpec(Sender: TObject; Client: TCustomTLS_ContentLayer);
begin
  if Assigned(FTlsHandshakeFinished) then
  try
    FTlsHandshakeFinished(Nil, TDnTcpChannel(Client.UserData), Nil);
  except
    on E: Exception do
      if Assigned(FLogger) then
        FLogger.LogMsg(llCritical, 'OnTLSHandshakeFinished handler raised an exception. ' + E.Message);
  end;
end;

procedure TDnTlsRequestor.ServerIncomingAlert(Sender: TObject; Client: TCustomTLS_ContentLayer;
                              var Fatal: Boolean; AlertCode: Integer);
begin
  if Fatal and (AlertCode = 0) then
    DoTlsCloseNotify(Nil, TDnTcpChannel(Client.UserData), Nil, AlertCode)
  else
  if Fatal then
    DoError(Nil, TDnTcpChannel(Client.UserData), Nil, AlertCode);
end;

procedure TDnTlsRequestor.ServerOutgoingAlert(Sender: TObject; Client: TCustomTLS_ContentLayer;
                              var Fatal: Boolean; AlertCode: Integer);
begin
  if Fatal then
    DoError(Nil, TDnTcpChannel(Client.UserData), Nil, AlertCode);
end;

procedure TDnTlsRequestor.ClientIncomingAlert(Sender: TObject; Client: TCustomTLS_ContentLayer;
                              var Fatal: Boolean; AlertCode: Integer);
begin
  if Fatal and (AlertCode = 0) then
    DoTlsCloseNotify(Nil, TDnTcpChannel(Client.UserData), Nil, AlertCode)
  else
  if Fatal then
    DoError(Nil, TDnTcpChannel(Client.UserData), Nil, AlertCode);
end;

procedure TDnTlsRequestor.ClientOutgoingAlert(Sender: TObject; Client: TCustomTLS_ContentLayer;
                              var Fatal: Boolean; AlertCode: Integer);
begin
  if Fatal then
    DoError(Nil, TDnTcpChannel(Client.UserData), Nil, AlertCode);
end;

procedure TDnTlsRequestor.DoClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  try
    if Assigned(FTcpClose) then
      FTcpClose(Context, Channel, Key);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTlsRequestor.DoCloseError( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                        ErrorCode: Cardinal );
begin
  Self.DoError(Context, Channel, Key, ErrorCode);
end;

procedure TDnTlsRequestor.DoClientClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  try
    if Assigned(FTcpClientClose) then
      FTcpClientClose(Context, Channel, Key);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTlsRequestor.DoLineHandshake( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                        Response: String);
begin
  DoHandshake(Context, Channel, Key, Response);
end;

procedure TDnTlsRequestor.DoLine( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ReceivedLine: String; EolFound: Boolean );
begin
  try
    if Assigned(FTcpLine) then
      FTcpLine(Context, Channel, Key, ReceivedLine, EolFound);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTlsRequestor.DoLineClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  Self.DoClientClose(Context, Channel, Key);
end;

procedure TDnTlsRequestor.DoLineError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                      ErrorCode: Cardinal );
begin
  Self.DoError(Context, Channel, Key, ErrorCode);
end;

end.
