unit msgtest;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, Contnrs, DnMsgClient, DnMsgServer, ExtCtrls;

type
  TFrmTest = class(TForm)
    BtServer: TButton;
    BtClient: TButton;
    TmrClient: TTimer;
    MmLog: TMemo;
    TmrSend: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure BtServerClick(Sender: TObject);
    procedure BtClientClick(Sender: TObject);
    procedure BtConnectClick(Sender: TObject);
    procedure BtDisconnectClick(Sender: TObject);
    procedure TmrClientTimer(Sender: TObject);
    procedure TmrSendTimer(Sender: TObject);
  private
    FServer: TCommonMsgServer;
    FClient: TCommonMsgClient;

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
    procedure Client_AuthResult (Sender: TObject; Res: Boolean; const Msg: AnsiString);
    procedure Client_ListOfClients (Sender: TObject; ClientList: TObjectList);

  public
  end;

var
  FrmTest: TFrmTest;

implementation

{$R *.dfm}

procedure TFrmTest.FormCreate(Sender: TObject);
begin
  FClient := TCommonMsgClient.Create(Nil);
  FServer := TCommonMsgServer.Create(Nil);
  FClient.HeartbeatInterval := 20;
  FClient.Handshake := True;
  FClient.Host := '127.0.0.1';
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
end;

procedure TFrmTest.LogServer(const S: String);
var Msg: String;
begin
  Msg := 'Server: ' + S;
  MmLog.Lines.Add('Server: ' + S);
  OutputDebugString(PWideChar(Msg));
end;

procedure TFrmTest.LogClient(const S: String);
var Msg: String;
begin
  Msg := 'Client: ' + S;
  MmLog.Lines.Add(Msg);
  OutputDebugString(PWideChar(Msg));
end;

procedure TFrmTest.Server_ClientConnected (Sender: TObject; ClientRec: TClientRec);
begin
  LogServer('client connected');
end;

procedure TFrmTest.Server_ClientAuthentication (Sender: TObject; ClientRec: TClientRec; var Authenticated: Boolean);
begin
  LogServer('client authenticated');
  Authenticated := True;
  FServer.SendString('test', ClientRec);
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

procedure TFrmTest.TmrClientTimer(Sender: TObject);
begin
  FClient.ProcessEvents;
  // FClient.SendString('TESTTESTTESTTESTTESTTESTTESTTESTESTTEST');
end;

procedure TFrmTest.TmrSendTimer(Sender: TObject);
begin
  FClient.SendString('TESTESTESTESTESTESTESTESTESTESTESTESTESTEST');
end;

procedure TFrmTest.Client_Connected (Sender: TObject);
begin
  LogClient('client connected to server');
end;

procedure TFrmTest.Client_Disconnected (Sender: TObject);
begin
  LogClient('client disconnected from server');
end;

procedure TFrmTest.Client_Error (Sender: TObject; ErrorMessage: AnsiString);
begin
  LogClient('client error ' + ErrorMessage);
end;

procedure TFrmTest.Client_DataReceived (Sender: TObject; Stream: TStream);
begin
  LogClient('received ' + IntToStr(Stream.Size) + ' bytes.');
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

    //TmrClient.Enabled := False;
    BtClient.Caption := 'Start client';
  end
  else
  begin
    FClient.Active := True;
    TmrClient.Enabled := True;
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
begin
  if FServer.Active then
  begin
    FServer.Active := False;
    BtServer.Caption := 'Start server';
  end
  else
  begin
    FServer.Active := True;
    BtServer.Caption := 'Stop server';
  end;
end;

procedure TFrmTest.Client_AuthResult (Sender: TObject; Res: Boolean; const Msg: AnsiString);
begin
  ;
end;

procedure TFrmTest.Client_ListOfClients (Sender: TObject; ClientList: TObjectList);
begin
  ;
end;

end.

