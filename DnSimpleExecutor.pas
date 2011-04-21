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
unit DnSimpleExecutor;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  DnAbstractExecutor, DnAbstractLogger, DnRtl, DnTcpRequest;

type
  TDnSimpleExecutor = class(TDnAbstractExecutor)
  protected
    FContext:   TDnThreadContext;
    function    TurnOn: Boolean; override;
    function    TurnOff: Boolean; override;
  public
    {$IFDEF ROOTISCOMPONENT}
    constructor Create(AOwner: TComponent); override;
    {$ELSE}
    constructor Create;
    {$ENDIF}
    destructor  Destroy; override;
    function    PostEvent(Event: TDnTcpRequest): Boolean; override;
  end;

procedure Register;

implementation


constructor TDnSimpleExecutor.Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent){$ENDIF};
begin
  inherited Create{$IFDEF ROOTISCOMPONENT}(AOwner){$ENDIF};
  FLogger := Nil;
  FLogLevel := llMandatory;
  FActive := False;
  FOnCreateContext := Nil;
  FOnDestroyContext := Nil;
end;

function  TDnSimpleExecutor.TurnOn: Boolean;
begin
  FContext := Nil;
  if Assigned(FOnCreateContext) then
    FContext := FOnCreateContext(Nil);
  Result := True;
end;

function TDnSimpleExecutor.TurnOff: Boolean;
begin
  if Assigned(FOnDestroyContext) then
    FOnDestroyContext(FContext);
  FContext := Nil;
  Result := False;
end;

destructor TDnSimpleExecutor.Destroy;
begin
  inherited Destroy;
end;

function TDnSimpleExecutor.PostEvent(Event: TDnTcpRequest): Boolean;
begin
  try
    if Event <> Nil then
      Event.CallHandler(FContext)
    else
      OutputDebugString('Wrong event.');
  except
    on E: Exception do
      if Assigned(FLogger) then
        FLogger.LogMsg(FLogLevel, E.Message);
  end;

  if Event.IsPureSignal then
    Event.Free;
    
  Result := True;
end;


procedure Register;
begin
  {$IFDEF ROOTISCOMPONENT}
  RegisterComponents('DNet', [TDnSimpleExecutor]);
  {$ENDIF}
end;

end.

