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
unit DnFileLogger;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  SyncObjs,
  DnAbstractLogger, DnConst, DnRtl;

type
  TDnFileLogger = class(TDnAbstractLogger)
  private
  protected
    FFileName:    String;
    FFile:        TextFile;
    FRewriteLog:  Boolean;
    FGuard:       TDnMutex;

    procedure SetFileName(Value: String);
    function TurnOn: Boolean; override;
    function TurnOff: Boolean; override;
  public
    {$IFDEF ROOTISCOMPONENT}
    constructor Create(AOwner: TComponent); override;
    {$ELSE}
    constructor Create;
    {$ENDIF}
    destructor Destroy; override;
    procedure  LogMsg(Level: TDnLogLevel; const Msg: String); override;
  published
    { Published declarations }
    property FileName: String read FFileName write SetFileName;
    property RewriteLog: Boolean read FRewriteLog write FRewriteLog;
  end;

procedure Register;

implementation

{$IFDEF ROOTISCOMPONENT}
constructor TDnFileLogger.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
{$ELSE}
constructor TDnFileLogger.Create;
begin
  inherited Create;
{$ENDIF}
  FRewriteLog := False;
  FGuard := TDnMutex.Create;
  //FShowProcessId := True;
  //FShowThreadId := True;
  FShowDateTime := True;
end;

destructor TDnFileLogger.Destroy;
begin
  FGuard.Free;
  inherited Destroy;
end;

function TDnFileLogger.TurnOn: Boolean;
begin
  try
    AssignFile(FFile, FFileName);
    if not FRewriteLog then
    begin
      if not FileExists(FFileName) then
        Rewrite(FFile)
      else
        Append(FFile);
    end
    else
      Rewrite(FFile);
  finally
    ;
  end;
  Result := True;
end;

function TDnFileLogger.TurnOff: Boolean;
begin
  CloseFile(FFile);
  Result := False;
end;

procedure TDnFileLogger.SetFileName(Value: String);
begin
  if FActive then
    raise EDnException.Create(ErrObjectIsActive, 0);
  FFileName := Value;
end;

procedure TDnFileLogger.LogMsg(Level: TDnLogLevel; const Msg: String);
begin
  if not FActive then
    Exit;

  FGuard.Acquire;
  try
    if Level <= FLevel then
    begin
      WriteLn(FFile, FormatMessage(Msg));
      Flush(FFile);
    end;
  finally
    FGuard.Release;
  end;
end;

procedure Register;
begin
  {$IFDEF ROOTISCOMPONENT}
  //RegisterComponents('DNet', [TDnFileLogger]);
  {$ENDIF}
end;

end.
