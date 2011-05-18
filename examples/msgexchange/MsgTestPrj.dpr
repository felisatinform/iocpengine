program MsgTestPrj;

uses
  //FastMM4,
  //Denomo,
  Forms,
  msgtest in 'msgtest.pas' {FrmTest};

{$R *.res}

begin
  Application.Initialize;
  //Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFrmTest, FrmTest);
  Application.Run;
end.
