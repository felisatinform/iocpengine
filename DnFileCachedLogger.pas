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
unit DnFileCachedLogger;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  DnFileLogger, DnAbstractLogger, DnRtl, DnConst;

type
  TDnFCLThread = class;

  TDnFileCachedLogger = class(TDnFileLogger)
  private
    { Private declarations }
  protected
    FThread: TDnFCLThread;
    FFlushInterval: Cardinal;
    FFlushSize: Cardinal;
    FLogList: TStringList;
    FTimerRestart: TDnEvent;
    FCountBytes: Cardinal;
    FTerminateSignal: TDnEvent;

    function TurnOn: Boolean; override;
    function TurnOff: Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure  LogMsg(Level: TDnLogLevel; const Msg: String); override;
  published
    property  FlushInterval: Cardinal read FFlushInterval write FFlushInterval;
    property  FlushSize: Cardinal read FFlushSize write FFlushSize;
  end;

  TDnFCLThread = class (TThread)
  protected
    FLogger: TDnFileCachedLogger;
    procedure Execute; override;
  public
    constructor Create (Logger: TDnFileCachedLogger);
    destructor Destroy; override;
  end;
  
procedure Register;

implementation

constructor TDnFileCachedLogger.Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent){$ENDIF};
begin
  inherited Create(AOwner);
  FFlushInterval := 5000; //5 seconds
  FFlushSize := 1024 * 100; //100 KB
  FCountBytes := 0;

end;

destructor TDnFileCachedLogger.Destroy;
begin
  inherited Destroy;
end;

function TDnFileCachedLogger.TurnOn: Boolean;
begin
  Result := inherited TurnOn;
  FLogList := TStringList.Create;
  FTimerRestart := TDnEvent.Create;
  FTerminateSignal := TDnEvent.Create;
  FThread := TDnFCLThread.Create(Self);
end;

function TDnFileCachedLogger.TurnOff: Boolean;
var
    PartialLog: String;
begin

  FreeAndNil(FThread);
  FreeAndNil(FTimerRestart);
  FreeAndNil(FTerminateSignal);

  PartialLog := FLogList.Text;
  Write(FFile, PartialLog);
    
  FreeAndNil(FLogList);
  FCountBytes := 0;
  Result := inherited TurnOff;
end;

procedure  TDnFileCachedLogger.LogMsg(Level: TDnLogLevel; const Msg: String);
var FullMsg: String;
    PartialLog: String;
begin
  if not FActive then
    Exit;

  FGuard.Acquire;
  try
    if Level <= FLevel then
    begin
      FullMsg := FormatMessage(Msg);
      FLogList.Add(FullMsg);
      Inc(FCountBytes, Length(FullMsg)+1);
      //check FlushSize limitation
      If FCountBytes >= FFlushSize then
      begin
        PartialLog := FLogList.Text;
        Write(FFile, PartialLog);
        Flush(FFile);
        FTimerRestart.SetEvent;
        FCountBytes := 0;
      end;
    end;
  finally
    FGuard.Release;
  end;
end;

constructor TDnFCLThread.Create (Logger: TDnFileCachedLogger);
begin
  inherited Create(True);
  if not Assigned(Logger) then
    raise EDnException.Create(ErrInvalidConfig, 0);
  FLogger := Logger;
  FreeOnTerminate := False;
  Resume;
end;

destructor TDnFCLThread.Destroy;
begin
  FLogger.FTerminateSignal.SetEvent;
  inherited Destroy;
end;

procedure TDnFCLThread.Execute;
var Handles: array [0..1] of THandle;
    ResCode: Cardinal;
    PartialLog: String;
begin
  Handles[0] := FLogger.FTimerRestart.Handle;
  Handles[1] := FLogger.FTerminateSignal.Handle;
  while not Terminated do
  begin
    ResCode := WaitForMultipleObjects(2, @Handles, False, FLogger.FFlushInterval);
    if ResCode = WAIT_TIMEOUT then
    begin
      FLogger.FGuard.Acquire;
      try
        PartialLog := FLogger.FLogList.Text;
        Write(FLogger.FFile, PartialLog);
        Flush(FLogger.FFile);
        FLogger.FTimerRestart.Pulse;
        FLogger.FCountBytes := 0;
      except
        ;//suppress exceptions - logger MUST work in any cases
      end;
      FLogger.FGuard.Release;
    end else
    if ResCode = WAIT_OBJECT_0+1 then
    begin
      Exit;
    end else
    if ResCode <> WAIT_OBJECT_0 then
      Exit;
  end;
end;

procedure Register;
begin
  RegisterComponents('DNet', [TDnFileCachedLogger]);
end;

end.
