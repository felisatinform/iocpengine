program SimpleHttpServer;

uses
  FastMM4,
  Forms,
  GUIPart in 'GUIPart.pas' {FrmGUI},
  FolderSelectPart in 'FolderSelectPart.pas' {FrmFolderSelect},
  HttpDemo in 'HttpDemo.pas' {HttpProcessor: TDataModule};

{$R *.RES}

begin
  Application.Initialize;
  Application.CreateForm(TFrmGUI, FrmGUI);
  Application.CreateForm(THttpProcessor, HttpProcessor);
  Application.Run;
end.
