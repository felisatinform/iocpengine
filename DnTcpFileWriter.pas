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
unit DnTcpFileWriter;
interface
uses  Classes, Windows, Winsock2, SysUtils,
      DnRtl, DnConst, DnInterfaces, DnTcpAbstractRequestor,
      DnTcpReactor, DnTcpWriteFile, DnTcpChannel;
type

  TDnTcpFileWritten =     procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                FileName: String; Written: Int64) of object;
  TDnTcpFileWriteError =  procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                ErrorCode: Cardinal ) of object;

  TDnTcpFileWriter = class (TDnTcpAbstractRequestor, IDnTcpWriteFileHandler)
  protected
    FFileWritten: TDnTcpFileWritten;
    FFileWriteError: TDnTcpFileWriteError;
    procedure DoWriteFile(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          const FileName: String; Written: Int64); virtual;
    procedure DoWriteFileError( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                ErrorCode: Cardinal ); virtual;
  public
    constructor Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent);override{$ENDIF};
    destructor  Destroy; override;
    procedure   RequestFileWrite(Channel: TDnTcpChannel; Key: Pointer; const FileName: String;
                                  StartPos, FinishPos: Int64); overload;
    procedure   RequestFileWrite(Channel: TDnTcpChannel; Key: Pointer; const FileName: String;
                                  StartPos: Int64 = 0); overload;
  published
    property  OnFileWritten: TDnTcpFileWritten read FFileWritten write FFileWritten;
    property  OnFileWriteError: TDnTcpFileWriteError  read FFileWriteError write FFileWriteError;        
  end;
  
procedure Register;

implementation

procedure Register;
begin
  {$IFDEF ROOTISCOMPONENT}
  RegisterComponents('DNet', [TDnTcpFileWriter]);
  {$ENDIF}
end;

constructor TDnTcpFileWriter.Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent){$ENDIF};
begin
  inherited Create{$IFDEF ROOTISCOMPONENT}(AOwner){$ENDIF};
  FFileWritten := Nil;
  FFileWriteError := Nil;
end;

destructor  TDnTcpFileWriter.Destroy;
begin
  inherited Destroy;
end;

procedure TDnTcpFileWriter.DoWriteFile(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          const FileName: String; Written: Int64);
begin
  try
    if Assigned(FFileWritten) then
      FFileWritten(Context, Channel, Key, FileName, Written);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTcpFileWriter.DoWriteFileError( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                ErrorCode: Cardinal );
begin
  try
    if Assigned(FFileWriteError) then
      FFileWriteError(Context, Channel, Key, ErrorCode);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTcpFileWriter.RequestFileWrite(Channel: TDnTcpChannel; Key: Pointer; const FileName: String;
          StartPos, FinishPos: Int64);
var Request: TDnTcpWriteFileRequest;
begin
  CheckAvail;
  Request := TDnTcpWriteFileRequest.Create(Channel, Key, Self, FileName, StartPos, FinishPos);
  Channel.RunRequest(Request);
end;

procedure TDnTcpFileWriter.RequestFileWrite(Channel: TDnTcpChannel; Key: Pointer; const FileName: String;
    StartPos: Int64 = 0);
var FinishPos: Int64;
begin
  if FileExists(FileName) then
    FinishPos := GetFileSize64(FileName)-1
  else
    FinishPos := 0;
  Self.RequestFileWrite(Channel, Key, FileName, StartPos, FinishPos);
end;

end.
