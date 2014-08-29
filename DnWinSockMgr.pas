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
unit DnWinSockMgr;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  WS2,
  DnRtl, DnConst;

type
  TDnWinSockMgr = class (TComponent)
  protected
    FWSAData: TWSAData;
    FNeedUnload: Boolean;
    FActive: Boolean;

    procedure SetActive(Value: Boolean);
  public
    constructor Create (AOwner: TComponent); override;
    destructor  Destroy; override;

  published
    property Active: Boolean read FActive write SetActive;
  end;

procedure Register;

implementation

constructor TDnWinsockMgr.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActive := False;
  FNeedUnload := False;
end;

destructor TDnWinsockMgr.Destroy;
begin
  if FActive then
    SetActive(False);
  inherited Destroy;
end;

procedure TDnWinsockMgr.SetActive(Value: Boolean);
begin
  if not FActive and Value then
  begin
    if not CheckRunningNT4 then
      raise EDnException.Create(ErrRequiresNT4, 0);
    FNeedUnload := WS2.WSAStartup(MakeWord(2,2), FWSAData) = 0;
    FActive := True;
  end else
  if FActive and not Value then
  begin
    if FNeedUnload then
      WS2.WSACleanup();
    FNeedUnload := False;
    FActive := False;
  end;
end;

procedure Register;
begin
  RegisterComponents('DNet', [TDnWinSockMgr]);
end;

end.
