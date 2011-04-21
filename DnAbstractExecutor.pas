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
unit DnAbstractExecutor;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  DnRtl, DnAbstractLogger, DnTcpRequest;

type
  TDnCreateContext = function(Thread: TDnThread): TDnThreadContext of object;
  TDnDestroyContext = procedure (Context: TDnThreadContext) of object;
  
  
  {$IFDEF ROOTISCOMPONENT}
  TDnAbstractExecutor = class(TComponent)
  {$ELSE}
  TDnAbstractExecutor = class(TObject)
  {$ENDIF}
  protected
    FLogger:            TDnAbstractLogger;
    FLogLevel:          TDnLogLevel;
    FOnCreateContext:   TDnCreateContext;
    FOnDestroyContext:  TDnDestroyContext;
    FActive:            Boolean;
    
    {$IFDEF ROOTISCOMPONENT}
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    {$ENDIF}
    function  TurnOn: Boolean; virtual; abstract;
    function  TurnOff: Boolean; virtual; abstract;
    procedure SetActive(Value: Boolean);
  public
    constructor Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent); override{$ENDIF};
    destructor  Destroy; override;
    function    PostEvent(Event: TDnTcpRequest): Boolean; virtual; abstract;
  published
    property OnCreateContext: TDnCreateContext read FOnCreateContext
      write FOnCreateContext;
    property OnDestroyContext: TDnDestroyContext read FOnDestroyContext
      write FOnDestroyContext;
    property Logger: TDnAbstractLogger read FLogger write FLogger;
    property LogLevel: TDnLogLevel read FLogLevel write FLogLevel;
    property Active: Boolean read FActive write SetActive;
 end;

implementation

constructor TDnAbstractExecutor.Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent){$ENDIF};
begin
  inherited Create{$IFDEF ROOTISCOMPONENT}(AOwner){$ENDIF};

  FOnCreateContext := Nil;
  FOnDestroyContext := Nil;
  FActive := False;
end;

{$IFDEF ROOTISCOMPONENT}
procedure TDnAbstractExecutor.Notification(AComponent: TComponent; Operation: TOperation);
begin
  if (AComponent = FLogger) and (Operation = opRemove) then
    FLogger := Nil;
end;
{$ENDIF}

destructor  TDnAbstractExecutor.Destroy;
begin
  if FActive then
    SetActive(False);
  inherited Destroy;
end;

procedure TDnAbstractExecutor.SetActive(Value: Boolean);
begin
  if not FActive and Value then
    FActive := TurnOn
  else
  if FActive and not Value then
    FActive := TurnOff; 
end;


end.
 
