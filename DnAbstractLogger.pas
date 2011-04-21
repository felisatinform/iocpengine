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
unit DnAbstractLogger;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  DnConst, DnRtl;

const
  SLogItemDelimiter = ' : ';

type

  //Great thanks 
  TDnLogLevel = ( llMandatory,      
                  llCritical,
                  llSerious,
                  llImportant,
                  llPriority,
                  llInformation,
                  llLowLevel );


  {$IFDEF ROOTISCOMPONENT}
  TDnAbstractLogger = class(TComponent)
  {$ELSE}
  TDnAbstractLogger = class(TObject)
  {$ENDIF}
  protected
    FShowProcessId,
    FShowThreadId,
    FShowDateTime:          Boolean;
    FLevel:                 TDnLogLevel;
    FActive:                Boolean;
    FDateTimeFormat,
    FInternalTimeFormat,
    FInternalDateFormat:    String;
    FProcessIdWidth,
    FThreadIdWidth:         Byte;

    procedure SetActive(Value: Boolean);
    procedure SetDateTimeFormat(Value: String);
    procedure SetProcessIdWidth(Value: Byte);
    procedure SetThreadIdWidth(Value: Byte);
    
    function  FormatMessage(const Msg: String): String;
    function  TurnOn: Boolean; virtual; abstract;
    function  TurnOff: Boolean; virtual; abstract;

  public
    constructor Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent); override{$ENDIF};
    destructor Destroy; override;

    procedure  LogMsg(Level: TDnLogLevel; const Msg: String); overload; virtual; abstract;
    
  published
    property ShowProcessId: Boolean read FShowProcessId write FShowProcessId;
    property ProcessIdWidth: Byte read FProcessIdWidth write SetProcessIdWidth;
    property ShowThreadId: Boolean read FShowThreadId write FShowThreadId;
    property ThreadIdWidth: Byte read FThreadIdWidth write SetThreadIdWidth;
    property ShowDateTime: Boolean read FShowDateTime write FShowDateTime;
    property DateTimeFormat: String read FDateTimeFormat write SetDateTimeFormat;
    property MinLevel: TDnLogLevel read FLevel write FLevel;
    property Active: Boolean read FActive write SetActive;
  end;

//procedure Register;

implementation


constructor TDnAbstractLogger.Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent){$ENDIF};
begin
  inherited Create{$IFDEF ROOTISCOMPONENT}(AOwner){$ENDIF};
  FLevel := llMandatory;
  FShowProcessId := False; FProcessIdWidth := 5;
  FShowThreadId := False; FThreadIdWidth := 5;
  FShowDateTime := False;
  FProcessIdWidth := 5; FThreadIdWidth := 5;
  Self.SetDateTimeFormat('ss.nn.hh mm.dd.yyyy');
end;

destructor TDnAbstractLogger.Destroy;
begin
  inherited Destroy;
end;

procedure TDnAbstractLogger.SetDateTimeFormat(Value: String);
begin
  FDateTimeFormat := Value;
end;

procedure TDnAbstractLogger.SetProcessIdWidth(Value: Byte);
begin
  if Value < 3 then
    raise EDnException.Create(ErrInvalidParameter, 0);
  FProcessIdWidth := Value;
end;

procedure TDnAbstractLogger.SetThreadIdWidth(Value: Byte);
begin
  if Value < 3 then
    raise EDnException.Create(ErrInvalidParameter, 0);
  FThreadIdWidth := Value;
end;

procedure TDnAbstractLogger.SetActive(Value: Boolean);
begin
  if FActive and not Value then
    FActive := TurnOff
  else if not FActive and Value then
    FActive := TurnOn;
end;


function AppendToWidth(S: String; Len: Integer): String;
var OldLen: Integer;
begin
  OldLen := Length(S);
  if OldLen < Len then
  begin
    SetLength(Result, Len - OldLen);
    FillChar(Result[1], Len - OldLen, 32);
    Result := Result + S;
  end
  else
    Result := S;
end;

function TDnAbstractLogger.FormatMessage(const Msg: String): String;
var ProcessID: String;
    ThreadID: String;
begin
  if FShowDateTime then
    Result := IntToStr(Windows.GetTickCount()) + SLogItemDelimiter;
  

  if FShowProcessId then
    ProcessID := AppendToWidth(IntToStr(GetCurrentProcessID()), ProcessIDWidth) + SLogItemDelimiter
  else
    ProcessID := '';

  if FShowThreadId then
    ThreadID := AppendToWidth(IntToStr(GetCurrentThreadID()), ThreadIDWidth) + SLogItemDelimiter
  else
    ThreadID := '';

  Result := Result + ProcessID + ThreadID;
  Result := Result + Msg;
end;

end.
 
