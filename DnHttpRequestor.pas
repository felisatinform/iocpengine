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
unit DnHttpRequestor;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  DnRtl, DnInterfaces, DnTcpReactor, DnTcpRequests,
  DnTcpAbstractRequestor, DnHttpRequest, DnTcpChannel;

type
  TDnHttpHeader = procedure ( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                              Received: RawByteString; EOMFound: Boolean) of object;
  TDnHttpError = procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                            ErrorCode: Cardinal) of object;
  TDnHttpClose = procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer) of object;

  TDnHttpRequestor = class(TDnTcpAbstractRequestor, IDnHttpHeaderHandler, IUnknown)
  private

  protected
    FHttpHeader:  TDnHttpHeader;
    FHttpError:   TDnHttpError;
    FHttpClose:   TDnHttpClose;

    //IDnTcpLineHandler
    procedure DoLine( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                      ReceivedLine: RawByteString; EolFound: Boolean );
    procedure DoLineError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           ErrorCode: Cardinal);
    procedure DoLineClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
  public
    constructor Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent); override{$ENDIF};
    destructor Destroy; override;
    procedure ReadHttpHeader(Channel: TDnTcpChannel; Key: Pointer; MaxSize: Cardinal);
  published
    property  OnHttpHeader: TDnHttpHeader read FHttpHeader write FHttpHeader;
    property  OnTcpError:   TDnHttpError read FHttpError write FHttpError;
    property  OnTcpClientClose:  TDnHttpClose  read FHttpClose write FHttpClose;
  end;

procedure Register;

implementation

constructor TDnHttpRequestor.Create{$IFDEF ROOTISCOMPONENT}(AOwner: TComponent){$ENDIF};
begin
  inherited Create{$IFDEF ROOTISCOMPONENT}(AOwner){$ENDIF};
  FHttpHeader := Nil;
  FHttpError := Nil;
  FHttpClose := Nil;

end;

destructor TDnHttpRequestor.Destroy;
begin
  inherited Destroy;
end;


procedure TDnHttpRequestor.DoLine(  Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                    ReceivedLine: RawByteString; EolFound: Boolean );
begin
  try
    if Assigned(FHttpHeader) then
      FHttpHeader(Context, Channel, Key, ReceivedLine, EolFound);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnHttpRequestor.DoLineError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           ErrorCode: Cardinal);
begin
  try
    if Assigned(FHttpError) then
      FHttpError(Context, Channel, Key, ErrorCode);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnHttpRequestor.DoLineClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  try
    if Assigned(FHttpClose) then
      FHttpClose(Context, Channel, Key);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnHttpRequestor.ReadHttpHeader(Channel: TDnTcpChannel; Key: Pointer; MaxSize: Cardinal);
var Request: TDnReadHttpHeader;
begin
  CheckAvail;
  Request := TDnReadHttpHeader.Create(Channel, Key, Self, MaxSize);
  Channel.RunRequest(Request);
end;

procedure Register;
begin
  {$IFDEF ROOTISCOMPONENT}
  RegisterComponents('DNet', [TDnHttpRequestor]);
  {$ENDIF}
end;

end.
