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
unit DnCallbackLogger;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  DnAbstractLogger, DnConst, DnRtl;

type
  TDnLogEvent = procedure (Level: TDnLogLevel; const Msg: String) of object;

  TDnCallbackLogger = class(TDnAbstractLogger)
  private
  protected
    FOnLog: TDnLogEvent;

    function TurnOn: Boolean; override;
    function TurnOff: Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure  LogMsg(Level: TDnLogLevel; const Msg: String); overload; override;
  published
    property OnLogMessage: TDnLogEvent read FOnLog write FOnLog;
  end;

procedure Register;

implementation

constructor TDnCallbackLogger.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOnLog := Nil;
end;

function TDnCallbackLogger.TurnOn: Boolean;
begin
  Result := True;
end;

function TDnCallbackLogger.TurnOff: Boolean;
begin
  Result := False;
end;

procedure  TDnCallbackLogger.LogMsg(Level: TDnLogLevel; const Msg: String);
begin
  if not FActive then
    raise EDnException.Create(ErrObjectNotActive, 0);
  if Assigned(FOnLog) then
  try
    if Level <= FLevel then
      FOnLog(Level, Self.FormatMessage(Msg));
  except
    ;
  end;
end;

destructor TDnCallbackLogger.Destroy;
begin
  inherited Destroy;
end;

procedure Register;
begin
  RegisterComponents('DNet', [TDnCallbackLogger]);
end;

end.
 
