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
unit DnTcpRequestor;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  Winsock2,
  DnConst, DnRtl, DnTcpReactor, DnTcpAbstractRequestor,
  DnTcpRequests, DnTcpChannel, DnTcpRequest, DnDataQueue
{$IFDEF ENABLE_DECORATOR}
  ,DnDataDecorator
{$ENDIF}
  ;

type
  TDnTcpRead =          procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          Buf: PByte; BufSize: Cardinal) of object;
  TDnTcpWrite =         procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           Buf: PByte; BufSize: Cardinal) of object;
  TDnTcpWriteStream =   procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           Stream: TStream) of object;
  TDnTcpError =         procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           ErrorCode: Cardinal) of object;
  TDnTcpClose =         procedure (Context: TDnThreadContext; Channel: TDnTcpChannel;
                            Key: Pointer) of object;
  TDnTcpClientClose =   procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer) of object;
  TDnTcpLine =          procedure (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          ReceivedLine: RawByteString; EolFound: Boolean) of object;
  TDnTcpConnect =       procedure (Context: TDnThreadContext; Channel: TDnTcpChannel;
                          Key: Pointer) of object;
  TDnTcpConnectError =  procedure (Context: TDnThreadContext; Channel: TDnTcpChannel;
                          Key: Pointer; ErrorCode: Cardinal) of object;

  TDnTcpMsg =           procedure (Context: TDnThreadContext; Channel: TDnTcpChannel;
                          Key: Pointer; ReceivedMsg: TStream) of object;

  TDnTcpRequestor = class(TDnTcpAbstractRequestor,
                          IDnTcpReadHandler, IDnTcpWriteHandler,
                          IDnTcpCloseHandler, IDnTcpLineHandler,
                          IUnknown)
  protected
    FTcpRead:         TDnTcpRead;
    FTcpWrite:        TDnTcpWrite;
    FTcpError:        TDnTcpError;
    FTcpClose:        TDnTcpClose;
    FTcpClientClose:  TDnTcpClientClose;
    FTcpLine:         TDnTcpLine;
    FTcpWriteStream:  TDnTcpWriteStream;

    //IDnTcpReadHandler
    procedure DoRead(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          Buf: PByte; BufSize: Cardinal);
    procedure DoReadError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           ErrorCode: Cardinal);
    procedure DoReadClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);

    //it is a helper routine that wraps original DoRead
    procedure DoReadString(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          Buf: RawByteString);

    //IDnTcpWriteHandler
    procedure DoWrite(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           Buf: PByte; BufSize: Cardinal);
    procedure DoWriteError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           ErrorCode: Cardinal);
    procedure DoWriteStream(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                            Stream: TStream);

    //IDnTcpCloseHandler
    procedure DoCloseError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           ErrorCode: Cardinal);
    procedure DoClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);

    //IDnTcpLineHandler
    procedure DoLine( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                      ReceivedLine: RawByteString; EolFound: Boolean );
    procedure DoLineError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           ErrorCode: Cardinal);
    procedure DoLineClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);


    procedure DoClientClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
    procedure DoError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                      ErrorCode: Cardinal);


  public
    constructor Create(AOwner: TComponent);override;
    destructor Destroy; override;
    procedure Read(Channel: TDnTcpChannel; Key: Pointer; Buf: PAnsiChar; BufSize: Cardinal);
    procedure ReadString(Channel: TDnTcpChannel; Key: Pointer; Size: Integer);
    procedure RawRead(Channel: TDnTcpChannel; Key: Pointer; Buf: PAnsiChar; MaxSize: Cardinal);
    procedure Write(Channel: TDnTcpChannel; Key: Pointer; Buf: PAnsiChar;  BufSize: Cardinal);
    procedure WriteString(Channel: TDnTcpChannel; Key: Pointer; Buf: RawByteString);
    procedure WriteStream(Channel: TDnTcpChannel; Key: Pointer; Stream: TStream);
    //procedure WriteQueue(Channel: TDnTcpChannel; Key: Pointer; Queue: TDnDataQueue);
    procedure Close(Channel: TDnTcpChannel; Key: Pointer; Brutal: Boolean = False);
    procedure ReadLine(Channel: TDnTcpChannel; Key: Pointer; MaxSize: Cardinal);

  published
    property OnRead:          TDnTcpRead read FTcpRead write FTcpRead;
    property OnWrite:         TDnTcpWrite read FTcpWrite write FTcpWrite;
    property OnWriteStream:   TDnTcpWriteStream read FTcpWriteStream write FTcpWriteStream;
    property OnClose:         TDnTcpClose read FTcpClose write FTcpClose;
    property OnError:         TDnTcpError read FTcpError write FTcpError;
    property OnLineRead:      TDnTcpLine read FTcpLine write FTcpLine;
    property OnClientClose:   TDnTcpClientClose read FTcpClientClose write FTcpClientClose;
  end;


procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('DNet', [TDnTcpRequestor]);
end;

//----------------------------------------------------------------------------

constructor TDnTcpRequestor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTcpRead := Nil;
  FTcpWrite := Nil;
  FTcpError := Nil;
  FTcpClose := Nil;
  FTcpLine := Nil;
  FTcpClientClose := Nil;
end;

destructor TDnTcpRequestor.Destroy;
begin
  inherited Destroy;
end;

procedure TDnTcpRequestor.Read(Channel: TDnTcpChannel; Key: Pointer; Buf: PAnsiChar; BufSize: Cardinal);
var Request: TDnTcpRequest;
begin
  if not CheckAvail then
    Exit;

  Request := TDnTcpReadRequest.Create(Channel, Key, Self, Buf, BufSize);

  if Assigned(Request) then
    Channel.RunRequest(Request);
end;

procedure TDnTcpRequestor.ReadString(Channel: TDnTcpChannel; Key: Pointer; Size: Integer);
var Request: TDnTcpRequest;

begin
  if not CheckAvail then
    Exit;
  Request := TDnTcpReadRequest.CreateString(Channel, Key, Self, Size);

  if Assigned(Request) then
    Channel.RunRequest(Request);
end;

procedure TDnTcpRequestor.RawRead(Channel: TDnTcpChannel; Key: Pointer; Buf: PAnsiChar; MaxSize: Cardinal);
var Request: TDnTcpRequest;
begin
  if not CheckAvail then
    Exit;

  Request := TDnTcpReadRequest.Create(Channel, Key, Self, Buf, MaxSize, False);

  if Assigned(Request) then
    Channel.RunRequest(Request);
end;

procedure TDnTcpRequestor.Write(Channel: TDnTcpChannel; Key: Pointer; Buf: PAnsiChar; BufSize: Cardinal);
var Request: TDnTcpRequest;

begin
  if not CheckAvail then
    Exit;


  Request := TDnTcpWriteRequest.Create(Channel, Key, Self, Buf, BufSize);

  if Assigned(Request) then
    Channel.RunRequest(Request);
end;

procedure TDnTcpRequestor.WriteString(Channel: TDnTcpChannel; Key: Pointer; Buf: RawByteString);
var Request: TDnTcpRequest;

begin
  if not CheckAvail then
    Exit;

  Request := TDnTcpWriteRequest.CreateString(Channel, Key, Self, Buf);

  if Assigned(Request) then
    Channel.RunRequest(Request);
end;

procedure TDnTcpRequestor.WriteStream(Channel: TDnTcpChannel; Key: Pointer; Stream: TStream);
var Request: TDnTcpRequest;

begin
  if not CheckAvail then
    Exit;

  Request := TDnTcpWriteRequest.CreateStream(Channel,Key, Self, Stream);

  if Assigned(Request) then
    Channel.RunRequest(Request);
end;

(*
procedure TDnTcpRequestor.WriteQueue(Channel: TDnTcpChannel; Key: Pointer; Queue: TDnDataQueue);
var Request: TDnTcpRequest;
begin
  if not CheckAvail then
    Exit;

  Request := TDnTcpWriteRequest.CreateQueue(Channel, Key, Self, Queue);
  Channel.RunRequest(Request);
end;
*)

procedure TDnTcpRequestor.Close(Channel: TDnTcpChannel; Key: Pointer; Brutal: Boolean);
var Request: TDnTcpRequest;
begin
  if not CheckAvail then
    Exit;

  Request := TDnTcpCloseRequest.Create(Channel, Key, Self, Brutal);

  if Assigned(Request) then
    Channel.RunRequest(Request);
end;

procedure TDnTcpRequestor.ReadLine(Channel: TDnTcpChannel; Key: Pointer; MaxSize: Cardinal);
var Request: TDnTcpRequest;
begin
  if not CheckAvail then
    Exit;
  Request := TDnTcpLineRequest.Create(Channel, Key, Self, MaxSize);
  Channel.RunRequest(Request);
end;

procedure TDnTcpRequestor.DoRead( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  Buf: PByte; BufSize: Cardinal);
begin
  try
    if Assigned(FTcpRead) then
      FTcpRead(Context, Channel, Key, Buf, BufSize);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTcpRequestor.DoReadString(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                        Buf: RawByteString);
begin
  DoRead(Context, Channel, Key, @Buf[1], Length(Buf));
end;

procedure TDnTcpRequestor.DoReadError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                      ErrorCode: Cardinal);
begin
  Self.DoError(Context, Channel, Key, ErrorCode);
end;

procedure TDnTcpRequestor.DoReadClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  Self.DoClientClose(Context, Channel, Key);
end;

procedure TDnTcpRequestor.DoWrite(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  Buf: PByte; BufSize: Cardinal);
begin
  try
    if Assigned(FTcpWrite) then
      FTcpWrite(Context, Channel, Key, Buf, BufSize);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTcpRequestor.DoWriteStream(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  Stream: TStream);
begin
  try
    if Assigned(FTcpWriteStream) then
      FTcpWriteStream(Context, Channel, Key, Stream);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTcpRequestor.DoWriteError( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                        ErrorCode: Cardinal );
begin
  Self.DoError(Context, Channel, Key, ErrorCode);
end;

procedure TDnTcpRequestor.DoError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);
begin
  try
    if Assigned(FTcpError) then
      FTcpError(Context, Channel, Key, ErrorCode);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTcpRequestor.DoClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  Channel.CloseSocketHandle;
  
  try
    if Assigned(FTcpClose) then
      FTcpClose(Context, Channel, Key);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTcpRequestor.DoCloseError( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                        ErrorCode: Cardinal );
begin
  Self.DoError(Context, Channel, Key, ErrorCode);
end;

procedure TDnTcpRequestor.DoClientClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  try
    if Assigned(FTcpClientClose) then
      FTcpClientClose(Context, Channel, Key);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTcpRequestor.DoLine( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ReceivedLine: RawByteString; EolFound: Boolean );
begin
  try
    if Assigned(FTcpLine) then
      FTcpLine(Context, Channel, Key, ReceivedLine, EolFound);
  except
    on E: Exception do
      Self.PostLogMessage(E.Message);
  end;
end;

procedure TDnTcpRequestor.DoLineClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  Self.DoClientClose(Context, Channel, Key);
end;

procedure TDnTcpRequestor.DoLineError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                      ErrorCode: Cardinal );
begin
  Self.DoError(Context, Channel, Key, ErrorCode);
end;

end.
