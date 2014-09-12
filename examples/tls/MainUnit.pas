unit MainUnit;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, SyncObjs,
  DnTlsBox, DnTlsChannel, DnRtl;

type
  TFrmMain = class(TForm)
    Label1: TLabel;
    EdHostIp: TEdit;
    BtStartClient: TButton;
    MmLog: TMemo;
    Label2: TLabel;
    EdServerPortNumber: TEdit;
    BtStartServer: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure BtStartClientClick(Sender: TObject);
    procedure BtStartServerClick(Sender: TObject);

  private
    FTlsClient, FTlsServer: TDnTlsBox;
    FLogGuard: TCriticalSection;

    procedure Log(const S: String);
    procedure ServerTlsDataAvailable(Sender: TObject; Channel: TDnTlsChannel);
    procedure ServerTlsError(Sender: TObject; Channel: TDnTlsChannel; ErrorCode: Integer);
    procedure ServerTlsClose(Sender: TObject; Channel: TDnTlsChannel);
    procedure ServerTlsConnected(Sender: TObject; Channel: TDnTlsChannel);

    procedure ClientTlsDataAvailable(Sender: TObject; Channel: TDnTlsChannel);
    procedure ClientTlsError(Sender: TObject; Channel: TDnTlsChannel; ErrorCode: Integer);
    procedure ClientTlsClose(Sender: TObject; Channel: TDnTlsChannel);
    procedure ClientTlsConnected(Sender: TObject; Channel: TDnTlsChannel);

  public
    { Public declarations }
  end;

var
  FrmMain: TFrmMain;

implementation

{$R *.dfm}

procedure TFrmMain.BtStartClientClick(Sender: TObject);
var Ip: String; Port, P: Integer;
begin
  if FTlsClient.Active then
  begin
    BtStartClient.Caption := 'Start client';
    FTlsClient.Active := False;
  end
  else
  begin
    BtStartClient.Caption := 'Stop client';
    FTlsClient.Active := True;
    P := Pos(':', Self.EdHostIp.Text);
    if P = 0 then
    begin
      Ip := Self.EdHostIp.Text;
      Port := 443;
    end
    else
    begin
      Ip := Copy(Self.EdHostIp.Text, 1, P - 1);
      Port := StrToIntDef(Copy(Self.EdHostIp.Text, P+1, Length(Self.EdHostIp.Text) - P), 443);
    end;
    Log('Connecting to ' + IP + ':' + IntToStr(Port));
    try
      FTlsClient.Connect(FTlsClient.MakeChannel(AnsiString(IP), Port));
    except
      on E: EDnException do
        Log('Connect failed with code ' + IntToStr(E.ErrorCode) + ' subcode ' + IntToStr(E.ErrorSubCode) + ' message ' + E.ErrorMessage);
    end;
  end;
end;

procedure TFrmMain.FormCreate(Sender: TObject);
var P: String;
begin
  TDnTlsBox.InitOpenSSL;
  FLogGuard := TCriticalSection.Create();

  // Bring TLS server
  FTlsServer := TDnTlsBox.Create(Nil);
  FTlsServer.OnData := ServerTlsDataAvailable;
  FTlsServer.OnClose := ServerTlsClose;
  FTlsServer.OnError := ServerTlsError;
  FTlsServer.OnConnected := ServerTlsConnected;

  // TLS client
  FTlsClient := TDnTlsBox.Create(Nil);
  FTlsClient.OnData := ClientTlsDataAvailable;
  FTlsClient.OnClose := ClientTlsClose;
  FTlsClient.OnError := ClientTlsError;
  FTlsClient.OnConnected := ClientTlsConnected;

  // Locate certificates
  P := ExtractFilePath(Application.ExeName);

  P := P + 'certs\';
  FTlsServer.LoadCert(P + 'self-ssl.key', P + 'self-ssl.crt', 'password');
end;

procedure TFrmMain.FormDestroy(Sender: TObject);
begin
  FTlsClient.Active := False;
  FTlsClient.Free;
  FTlsServer.Active := False;
  FTlsServer.Free;
  FLogGuard.Free;
end;

procedure TFrmMain.Log(const S: String);
begin
  FLogGuard.Enter;
  try
    MmLog.Lines.Add(S);
  finally
    FLogGuard.Leave;
  end;
end;


procedure TFrmMain.ServerTlsDataAvailable(Sender: TObject; Channel: TDnTlsChannel);
var Content: RawByteString;
begin
  Log('Server: TLS data available');
  Content := Channel.IncomingAppData.ReadBlock(Channel.IncomingAppData.Size);
  Log(String(Content));
  FTlsServer.Write(Channel, '<html>HAHA</html>');
end;

procedure TFrmMain.ServerTlsError(Sender: TObject; Channel: TDnTlsChannel; ErrorCode: Integer);
begin
  Log('Server: TLS connection data error ' + IntToStr(ErrorCode));
  FTlsServer.Close(Channel, True);
end;

procedure TFrmMain.ServerTlsClose(Sender: TObject; Channel: TDnTlsChannel);
begin
  Log('Server: TLS connection closed');
end;

procedure TFrmMain.ServerTlsConnected(Sender: TObject; Channel: TDnTlsChannel);
begin
  Log('Server: TLS connected');
  FTlsServer.Write(Channel, 'HELLO MAN');
end;

procedure TFrmMain.ClientTlsDataAvailable(Sender: TObject; Channel: TDnTlsChannel);
var Content: RawByteString;
begin
  Log('Client: TLS data available');

  Content := Channel.IncomingAppData.ReadBlock(Channel.IncomingAppData.Size);
  Log('Client: ' + String(Content));
  FTlsClient.Close(Channel);
end;

procedure TFrmMain.ClientTlsError(Sender: TObject; Channel: TDnTlsChannel; ErrorCode: Integer);
begin
  Log('Client: TLS connection data error ' + IntToStr(ErrorCode));
  FTlsClient.Close(Channel, True);
end;

procedure TFrmMain.BtStartServerClick(Sender: TObject);
begin
  if FTlsServer.Active then
  begin
    BtStartServer.Caption := 'Start server';
    FTlsServer.Active := False;
  end
  else
  begin
    BtStartServer.Caption := 'Stop server';
    FTlsServer.ListenerPort := StrToInt(EdServerPortNumber.Text);
    FTlsServer.Active := True;
  end;
end;

procedure TFrmMain.ClientTlsClose(Sender: TObject; Channel: TDnTlsChannel);
begin
  Log('Client: TLS connection closed');
end;

procedure TFrmMain.ClientTlsConnected(Sender: TObject; Channel: TDnTlsChannel);
var Buf: RawByteString;
begin
  Log('Client: TLS connected');
  // Test with HTTPS server
  FTlsClient.Write(Channel, 'GET /index.html HTTP/1.1' + #13#10 + 'Host: voipobjects.com' + #13#10#13#10);
end;


end.
