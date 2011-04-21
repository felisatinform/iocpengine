unit GUIPart;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ComCtrls, DnRtl, DnAbstractLogger;

type
  TFrmGUI = class(TForm)
    Label1: TLabel;
    EdPort: TEdit;
    UDPort: TUpDown;
    Label2: TLabel;
    EdDocFolder: TEdit;
    BtStart: TButton;
    BtStop: TButton;
    procedure FormCreate(Sender: TObject);
    procedure BtStartClick(Sender: TObject);
    procedure BtStopClick(Sender: TObject);
  private
  public
    procedure ShowHeapStatus;
  end;

var
  FrmGUI: TFrmGUI;

implementation

uses HttpDemo;

{$R *.DFM}

procedure TFrmGUI.FormCreate(Sender: TObject);
begin
  BtStop.Enabled := False;
  //UDPort.Max := 65535;
  //UDPort.Min := 0;
  UDPort.Increment := 1;
end;

procedure TFrmGUI.BtStartClick(Sender: TObject);
begin
  try
    // Set HTTP listening port
    HttpProcessor.Server.Port := StrToInt(EdPort.Text);

    // Set document root
    HttpProcessor.DocumentPath := ExtractFilePath(ParamStr(0)) + EdDocFolder.Text;

    //update GUI
    BtStart.Enabled := False;
    BtStop.Enabled := True;
    EdPort.Enabled := False;
    UDPort.Enabled := False;
    EdDocFolder.Enabled := False;

    // Start server
    HttpProcessor.Server.Active := True;
  except
    on E: Exception do
      HttpProcessor.ServerLog(Self, TDnLogLevel(0), E.Message);
  end;
end;

procedure TFrmGUI.BtStopClick(Sender: TObject);
begin
  try
    // Stop HTTP server
    HttpProcessor.Server.Active := False;

    // Update GUI
    BtStart.Enabled := True;
    BtStop.Enabled := False;
    EdPort.Enabled := True;
    UDPort.Enabled := True;
    EdDocFolder.Enabled := True;
  except
    on E: Exception do
      HttpProcessor.ServerLog(Self, llCritical, E.Message);
  end;
end;

procedure TFrmGUI.ShowHeapStatus;
var
  HeapStatus: THeapStatus;
  Msg: String;
begin
  HeapStatus := GetHeapStatus;
  Msg :=  'Total: ' + IntToStr(HeapStatus.TotalAddrSpace) + #13#10 +
          'Uncommited:' + IntToStr(HeapStatus.TotalUncommitted) + #13#10 +
          'Commited:' + IntToStr(HeapStatus.TotalCommitted) + #13#10 +
          'Allocated:' + IntToStr(HeapStatus.TotalAllocated) + #13#10 +
          'Free:' + IntToStr(HeapStatus.TotalFree) + #13#10;
  Application.MessageBox(PChar(Msg), 'Info', 0); 
end;

end.
