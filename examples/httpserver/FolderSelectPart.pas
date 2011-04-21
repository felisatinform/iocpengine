unit FolderSelectPart;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  ComCtrls;

type
  TFrmFolderSelect = class(TForm)
    TVFolder: TTreeView;
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  FrmFolderSelect: TFrmFolderSelect;

implementation

{$R *.DFM}

end.
