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
unit DnTcpConnecter;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  Winsock2,
  DnConst, DnRtl, DnTcpReactor, DnTcpAbstractRequestor, DnTcpConnect, DnTcpChannel;

type
  TDnTcpConnect = procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                        const IP: AnsiString; Port: Word) of object;
  TDnTcpConnectError = procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                              ErrorCode: Cardinal) of object;

  TDnTcpConnecter = class (TDnTcpAbstractRequestor,
                            IDnTcpConnectHandler,
                            IUnknown)
  protected
    FTcpConnect:        TDnTcpConnect;
    FTcpError:          TDnTcpConnectError;
    FWatcher:           TDnTcpConnectWatcher;
    //IDnTcpConnectHandler
    procedure DoConnect(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                        const IPAddr: AnsiString; Port: Word);
    procedure DoConnectError(Context: TDnThreadContext; Channel: TDnTcpChannel;
                Key: Pointer; ErrorCode: Cardinal);

    function TurnOn: Boolean; override;
    function TurnOff: Boolean; override;
  public
    constructor Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent);override{$ENDIF};
    destructor  Destroy; override;
    procedure   Connect(Channel: TDnTcpChannel; Key: Pointer; TimeOut: Cardinal);
  published
    property OnConnect: TDnTcpConnect read FTcpConnect write FTcpConnect;
    property OnError:   TDnTcpConnectError read FTcpError write FTcpError;
  end;


procedure Register;

implementation

procedure Register;
begin
  {$IFDEF ROOTISCOMPONENT}
  RegisterComponents('DNet', [TDnTcpConnecter]);
  {$ENDIF}
end;

//----------------------------------------------------------------------------
constructor TDnTcpConnecter.Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent){$ENDIF};
begin
  inherited Create{$IFDEF ROOTISCOMPONENT}(AOwner){$ENDIF};
  FTcpConnect := Nil;
  FTcpError := Nil;
  FWatcher := Nil;
end;

destructor TDnTcpConnecter.Destroy;
begin
  SetActive(False);
  inherited Destroy;
end;

function TDnTcpConnecter.TurnOn: Boolean;
begin
  FWatcher := TDnTcpConnectWatcher.Create;
  FWatcher.Reactor := FReactor;
  FWatcher.Logger := FLogger;
  FWatcher.LogLevel := FLogLevel;
  FWatcher.Executor := FExecutor;
  FWatcher.Active := True;
  Result := True;
end;

function TDnTcpConnecter.TurnOff: Boolean;
begin
  FWatcher.Active := False;
  FreeAndNil(FWatcher);
  Result := False;
end;

procedure TDnTcpConnecter.Connect(Channel: TDnTcpChannel; Key: Pointer; TimeOut: Cardinal);
begin
  FWatcher.MakeConnect(Channel, Key, TimeOut, Self);
end;

procedure TDnTcpConnecter.DoConnect(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
  const IPAddr: AnsiString; Port: Word);
begin
  try
    if Assigned(FTcpConnect) then
      FTcpConnect(Context, Channel, Key, IPAddr, Port);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTcpConnecter.DoConnectError(Context: TDnThreadContext; Channel: TDnTcpChannel;
                Key: Pointer; ErrorCode: Cardinal);
begin
  try
    if Assigned(FTcpError) then
      FTcpError(Context, Channel, Key, ErrorCode);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;

  //channel will be removed from reactor if it was add before
  FReactor.RemoveChannel(Channel);
end;


end.
