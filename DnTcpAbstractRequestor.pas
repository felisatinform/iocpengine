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
unit DnTcpAbstractRequestor;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  DnTcpReactor, DnAbstractLogger, DnAbstractExecutor,
  DnConst, DnRtl;

type
  
  {$IFDEF ROOTISCOMPONENT}
  TDnTcpAbstractRequestor = class(TComponent)
  {$ELSE}
  TDnTcpAbstractRequestor = class(TDnObject)
  {$ENDIF}
  protected
    FReactor:   TDnTcpReactor;
    FLogLevel:  TDnLogLevel;
    FLogger:    TDnAbstractLogger;
    FActive:    Boolean;
    FExecutor:  TDnAbstractExecutor;
    
    {$IFDEF ROOTISCOMPONENT}
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    {$ENDIF}
    function TurnOn: Boolean; virtual;
    function TurnOff: Boolean; virtual;
    procedure SetActive(Value: Boolean);
    function CheckAvail: Boolean;
  public
    constructor Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent);override{$ENDIF};
    destructor  Destroy; override;
    procedure   PostLogMessage(Msg: String);
  published
    property Reactor:   TDnTcpReactor read FReactor write FReactor;
    property LogLevel:  TDnLogLevel read FLogLevel write FLogLevel;
    property Logger:    TDnAbstractLogger read FLogger write FLogger;
    property Executor:  TDnAbstractExecutor read FExecutor write FExecutor;
    property Active:    Boolean read FActive write SetActive;
  end;

implementation

constructor TDnTcpAbstractRequestor.Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent){$ENDIF};
begin
  inherited Create{$IFDEF ROOTISCOMPONENT}(AOwner){$ENDIF};
  FReactor := Nil;
  FLogger := Nil;
  FExecutor := Nil;
  FLogLevel := llMandatory;
end;

destructor  TDnTcpAbstractRequestor.Destroy;
begin
  inherited Destroy;
end;

function TDnTcpAbstractRequestor.TurnOn: Boolean;
begin
  Result := True;
end;

function TDnTcpAbstractRequestor.TurnOff: Boolean;
begin
  Result := False;
end;

procedure TDnTcpAbstractRequestor.SetActive(Value: Boolean);
begin
  if FActive and not Value then
    FActive := TurnOff
  else
  if not FActive and Value then
    FActive := TurnOn;
end;

function TDnTcpAbstractRequestor.CheckAvail: Boolean;
begin
{$IFNDEF SILENTNONACTIVE}
  if not FActive then
    raise EDnException.Create(ErrObjectNotActive, 0);
{$ENDIF}
  Result := FActive;    
end;

{$IFDEF ROOTISCOMPONENT}
procedure TDnTcpAbstractRequestor.Notification(AComponent: TComponent; Operation: TOperation);
begin
  if (AComponent = FReactor) and (Operation = opRemove) then
    FReactor := Nil;
  if (AComponent = FLogger) and (Operation = opRemove) then
    FLogger := Nil;
end;
{$ENDIF}

procedure TDnTcpAbstractRequestor.PostLogMessage(Msg: String);
begin
  try
    if FLogger <> Nil then
      FLogger.LogMsg(FLogLevel, Msg);
  except
    ;
  end;
end;

end.
 
