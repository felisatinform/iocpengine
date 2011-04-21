program MsgTestPrj;

uses
  Forms,
  msgtest in 'msgtest.pas' {FrmTest};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFrmTest, FrmTest);
  Application.Run;
end.
