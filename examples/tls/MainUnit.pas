unit MainUnit;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, SyncObjs,
  DnTlsBox, DnTlsChannel, DnRtl,
  pbKroll.Common.KxProto.MessagesMessages;

type
  TFrmMain = class(TForm)
    Label1: TLabel;
    EdHostIp: TEdit;
    BtConnect: TButton;
    MmLog: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure BtConnectClick(Sender: TObject);
  private
    FTlsBox: TDnTlsBox;
    FLogGuard: TCriticalSection;

    procedure Log(const S: String);

    procedure TlsDataAvailable(Sender: TObject; Channel: TDnTlsChannel);
    procedure TlsWritten(Sender: TObject; Channel: TDnTlsChannel; Written: Integer);
    procedure TlsError(Sender: TObject; Channel: TDnTlsChannel; ErrorCode: Integer);
    procedure TlsClose(Sender: TObject; Channel: TDnTlsChannel);
    procedure TlsConnected(Sender: TObject; Channel: TDnTlsChannel);
  public
    { Public declarations }
  end;

var
  FrmMain: TFrmMain;

implementation

{$R *.dfm}

procedure TFrmMain.BtConnectClick(Sender: TObject);
var Ip: String; Port, P: Integer;
    PingRequest: TPingRequestRecord;
    Buffer: RawByteString;
    Encoded: Integer;
    Dump: TFileStream;
begin
  // Test encoding
  PingRequestRecordInit(PingRequest);
  PingRequest.Value := 'Test';
  PingRequest.ValueBytes := #1#2#3;
  SetLength(Buffer, 1024);
  Encoded := pbEncodeValuePingRequestRecord(Buffer[1], Length(Buffer), PingRequest);
  SetLength(Buffer, Encoded);
  PingRequestRecordFinalise(PingRequest);
  Dump := TFileStream.Create('ProtoDump.bin', fmCreate + fmOpenWrite);
  Dump.WriteBuffer(Buffer[1], Length(Buffer));
  Dump.Free;
  //FTlsBox.Write(Channel, 'GET /index.html HTTP/1.1' + #13#10 + 'Host: voipobjects.com' + #13#10#13#10);

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
    FTlsBox.Connect(FTlsBox.MakeChannel(AnsiString(IP), Port), AnsiString(IP), Port);
  except
    on E: EDnException do
      Log('Connect failed with code ' + IntToStr(E.ErrorCode) + ' subcode ' + IntToStr(E.ErrorSubCode) + ' message ' + E.ErrorMessage);
  end;
end;

procedure TFrmMain.FormCreate(Sender: TObject);
var P: String;
begin
  TDnTlsBox.InitOpenSSL;
  FLogGuard := TCriticalSection.Create();
  FTlsBox := TDnTlsBox.Create(Nil);
  FTlsBox.OnData := TlsDataAvailable;
  FTlsBox.OnWritten := TlsWritten;
  FTlsBox.OnClose := TlsClose;
  FTlsBox.OnError := TlsError;
  FTlsBox.OnConnected := TlsConnected;

  // Locate certificates
  P := ExtractFilePath(Application.ExeName);
  //FTlsBox.LoadRootCert(P + 'server.crt');
  //Self.EdHostIp.Text := '37.139.30.183:443';
  FTlsBox.LoadRootCert(P + 'amjay.pem');
  FTlsBox.LoadClientCert(P + 'privatekey.pem', P + 'publicCert.pem', 'password');
  FTlsBox.Active := True;
end;

procedure TFrmMain.FormDestroy(Sender: TObject);
begin
  FTlsBox.Free;
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

procedure TFrmMain.TlsDataAvailable(Sender: TObject; Channel: TDnTlsChannel);
var Content: RawByteString;
begin
  Log('TLS data available');
  Content := Channel.IncomingAppData.ReadBlock(Channel.IncomingAppData.Size);
  Log(Content);
  FTlsBox.Close(Channel);
end;

procedure TFrmMain.TlsWritten(Sender: TObject; Channel: TDnTlsChannel; Written: Integer);
begin
  Log('TLS data written');
end;

procedure TFrmMain.TlsError(Sender: TObject; Channel: TDnTlsChannel; ErrorCode: Integer);
begin
  Log('TLS data error ' + IntToStr(ErrorCode));
  FTlsBox.Close(Channel, True);
end;

procedure TFrmMain.TlsClose(Sender: TObject; Channel: TDnTlsChannel);
begin
  Log('TLS closed');
end;

procedure TFrmMain.TlsConnected(Sender: TObject; Channel: TDnTlsChannel);
var PingRequest: TPingRequestRecord;
    Buffer: RawByteString;
    Encoded: Integer;
begin
  Log('TLS connected');

  PingRequestRecordInit(PingRequest);
  SetLength(Buffer, 1024);
  Encoded := pbEncodeValuePingRequestRecord(Buffer[1], Length(Buffer), PingRequest);
  SetLength(Buffer, Encoded);
  FTlsBox.Write(Channel, Buffer);
  PingRequestRecordFinalise(PingRequest);

  //FTlsBox.Write(Channel, 'GET /index.html HTTP/1.1' + #13#10 + 'Host: voipobjects.com' + #13#10#13#10);
end;

end.
