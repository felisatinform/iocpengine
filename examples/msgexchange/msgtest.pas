unit msgtest;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, Contnrs, DnMsgClient, DnMsgServer, DnRtl, ExtCtrls, SyncObjs;

type
  TFrmTest = class(TForm)
    BtServer: TButton;
    BtClient: TButton;
    MmLog: TMemo;
    TmrSend: TTimer;
    TmrLog: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure BtServerClick(Sender: TObject);
    procedure BtClientClick(Sender: TObject);
    procedure BtConnectClick(Sender: TObject);
    procedure BtDisconnectClick(Sender: TObject);
    procedure TmrSendTimer(Sender: TObject);
    procedure TmrLogTimer(Sender: TObject);
    procedure FormDestroy(Sender: TObject);

  private
    FServer: TCommonMsgServer;
    FClient: TCommonMsgClient;
    FLog: TStringList;
    FLogGuard: TCriticalSection;

    procedure LogServer(const S: String);
    procedure LogClient(const S: String);

    // Server handlers
    procedure Server_ClientConnected (Sender: TObject; ClientRec: TClientRec);
    procedure Server_ClientAuthentication (Sender: TObject; ClientRec: TClientRec; var Authenticated: Boolean);
    procedure Server_DataReceived (Sender: TObject; ClientRec: TClientRec; Stream: TStream);
    procedure Server_ClientDisconnectedEvent (Sender: TObject; ClientRec: TClientRec);
    procedure Server_Error (Sender: TObject; Client: TClientRec; ErrorMessage: string);
    procedure Server_StreamSent (Sender: TObject; Client: TClientRec; Stream: TStream);

    // Client handlers
    procedure Client_Connected (Sender: TObject);
    procedure Client_Disconnected (Sender: TObject);
    procedure Client_Error (Sender: TObject; ErrorMessage: AnsiString);
    procedure Client_DataReceived (Sender: TObject; Stream: TStream);
    procedure Client_StreamSent (Sender: TObject; Stream: TStream);
    procedure Client_AuthResult (Sender: TObject; Res: Boolean; const Msg: RawByteString);
    procedure Client_ListOfClients (Sender: TObject; ClientList: TObjectList);

  public
  end;

var
  FrmTest: TFrmTest;

implementation

{$R *.dfm}

procedure TFrmTest.FormCreate(Sender: TObject);
begin
  FLog := TStringList.Create();
  FLogGuard := TCriticalSection.Create();

  FClient := TCommonMsgClient.Create(Nil);
  FServer := TCommonMsgServer.Create(Nil);
  FClient.HeartbeatInterval := 20;
  FClient.Handshake := True;
  FClient.Host := '127.0.0.1';
  //FClient.Host := '127.0.0.1';
  FClient.Port := 8083;
  FClient.OnConnected := Self.Client_Connected;
  FClient.OnDisconnected := Self.Client_Disconnected;
  FClient.OnStreamSent := Self.Client_StreamSent;
  FClient.OnError := Self.Client_Error;
  FClient.OnDataReceived := Self.Client_DataReceived;
  FClient.OnStreamSent := Self.Client_StreamSent;
  FClient.OnAuthResult := Self.Client_AuthResult;
  FClient.OnClientList := Self.Client_ListOfClients;
  FClient.MarshallWindow := Self.Handle;

  FServer.Port := 8083;
  FServer.OnClientConnected := Self.Server_ClientConnected;
  FServer.OnClientDisconnected := Self.Server_ClientDisconnectedEvent;
  FServer.OnClientAuthentication := Self.Server_ClientAuthentication;
  FServer.OnDataReceived := Self.Server_DataReceived;
  FServer.OnError := Self.Server_Error;
  FServer.OnStreamSent := Self.Server_StreamSent;

  TmrLog.Enabled := True;
end;

procedure TFrmTest.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FClient);
  FreeAndNil(FServer);
  FreeAndNil(FLog);
  FreeAndNil(FLogGuard);
end;

procedure TFrmTest.LogServer(const S: String);
var Msg: String;
begin
  Msg := 'Server: ' + S;
  FLog.Add(Msg);
  //OutputDebugString(PWideChar(Msg));
end;

procedure TFrmTest.LogClient(const S: String);
var Msg: String;
begin
  Msg := 'Client: ' + S;
  FLog.Add(Msg);
  //OutputDebugString(PWideChar(Msg));
end;

procedure TFrmTest.Server_ClientConnected (Sender: TObject; ClientRec: TClientRec);
begin
  LogServer('client connected');
  FServer.SendString('test', ClientRec);
end;

procedure TFrmTest.Server_ClientAuthentication (Sender: TObject; ClientRec: TClientRec; var Authenticated: Boolean);
var Request: AnsiString;
begin
  LogServer('client authenticated');
  Authenticated := True;
  SetLength(Request, 2048);
  FillChar(Request[1], 2048, 123);
  FServer.SendString(Request, ClientRec);
  //FServer.SendString('test', ClientRec);
end;

procedure TFrmTest.Server_DataReceived (Sender: TObject; ClientRec: TClientRec; Stream: TStream);
begin
  LogServer('received ' + IntToStr(Stream.Size) + ' bytes');
  Stream.Position := 0;
  FServer.SendString('TTTTTTTTTTTTT', ClientRec);
end;

procedure TFrmTest.Server_ClientDisconnectedEvent (Sender: TObject; ClientRec: TClientRec);
begin
  LogServer('client disconnected');
end;

procedure TFrmTest.Server_Error (Sender: TObject; Client: TClientRec; ErrorMessage: string);
begin
  LogServer('error ' + ErrorMessage);
end;

procedure TFrmTest.Server_StreamSent (Sender: TObject; Client: TClientRec; Stream: TStream);
begin
  LogServer('sent ' + IntToStr(Stream.Size) + ' bytes');
end;

procedure TFrmTest.TmrLogTimer(Sender: TObject);
var i: integer;
begin
  FLogGuard.Enter;
  try
    MmLog.Lines.AddStrings(FLog);
    FLog.Clear;
    (*if MmLog.Lines.Count > 200 then
    for i:=0 to 99 do
      MmLog.Lines.Delete(0);*)
  finally
    FLogGuard.Leave;
  end;

  if Assigned(FClient) then
  begin
    if FClient.MarshallWindow <> 0 then
      FClient.ProcessEvents;

    if FClient.Active then
      BtClient.Caption := 'Stop client'
    else
      BtClient.Caption := 'Start client';
  end;
end;

procedure TFrmTest.TmrSendTimer(Sender: TObject);
var Msg: AnsiString;
begin
  SetLength(Msg, 4096);
  if FClient.Active then
    FClient.SendString(Msg);
  //FClient.SendString('TESTESTESTESTESTESTTESTESTESTESTESTESTTESTESTESTESTESTESTTESTESTESTESTESTESTTESTESTESTESTESTESTTESTESTESTESTESTESTTESTESTESTESTESTESTTESTESTESTESTESTESTTESTESTESTESTESTESTTESTESTESTESTESTESTTESTESTESTESTESTESTTESTESTESTESTESTEST');
end;

procedure TFrmTest.Client_Connected (Sender: TObject);
begin
  LogClient('client connected to server');
end;

procedure TFrmTest.Client_Disconnected (Sender: TObject);
begin
  LogClient('client disconnected from server');
  FClient.Connect;
end;

procedure TFrmTest.Client_Error (Sender: TObject; ErrorMessage: AnsiString);
begin
  LogClient('client error ' + String(ErrorMessage));
end;

procedure TFrmTest.Client_DataReceived (Sender: TObject; Stream: TStream);
var Response: AnsiString;
begin
  LogClient('Received ' + IntToStr(Stream.Size) + ' bytes.');
  (*
  SetLength(Response, 256);

  // SetLength(Response, 1024*1024*2);
  FillChar(Response[1], Length(Response), 23);
  FClient.SendString(Response);
  *)
end;

procedure TFrmTest.Client_StreamSent (Sender: TObject; Stream: TStream);
begin
  LogClient('sent ' + IntToStr(Stream.Size) + ' bytes.');
end;

procedure TFrmTest.BtClientClick(Sender: TObject);
begin
  if FClient.Active then
  begin
    TmrSend.Enabled := False;
    FClient.Active := False;
    BtClient.Caption := 'Start client';
  end
  else
  begin
    FClient.Active := True;
    TmrSend.Enabled := True;
    BtClient.Caption := 'Stop client';
  end;
end;

procedure TFrmTest.BtConnectClick(Sender: TObject);
begin
  FClient.Connect;
end;

procedure TFrmTest.BtDisconnectClick(Sender: TObject);
begin
  FClient.Disconnect;
end;

procedure TFrmTest.BtServerClick(Sender: TObject);
var
  I: Integer;
begin
  if FServer.Active then
  begin
    FServer.DisconnectAll;
    Sleep(500);
    FServer.Active := False;
    BtServer.Caption := 'Start server';
  end
  else
  begin
    FServer.Active := True;
    BtServer.Caption := 'Stop server';
  end;
end;

procedure TFrmTest.Client_AuthResult (Sender: TObject; Res: Boolean; const Msg: RawByteString);
begin
  ;
end;

procedure TFrmTest.Client_ListOfClients (Sender: TObject; ClientList: TObjectList);
begin
  ;
end;

end.

