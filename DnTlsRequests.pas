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
unit DnTlsRequests;
interface
uses
  Classes, SysUtils, Windows, Winsock, Winsock2,
  DnTcpReactor, DnConst, DnInterfaces, DnRtl, DnTcpRequests, DnTcpRequest,
  DnTcpChannel,
  StreamSecII, TlsClass, MpX509,
  TlsInternalServer, SecComp;

type
  IDnTlsCRequestHandler = interface
  ['{8c23ed7b-563d-4bc3-b2b6-449aa97ec7d3}']
    procedure DoTlsCRequestFinished(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
    procedure DoTlsCRequestError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);
  end;

  IDnTlsSResponseHandler = interface
  ['{242a8776-de9f-4cda-842e-8ccd42ae91bf}']
    procedure DoTlsSResponseFinished(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
    procedure DoTlsSResponseError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);
  end;

  IDnTlsCloseNotifyHandler = interface
    ['{62348456-b668-4355-8e4c-10cea3a9f49a}']
    procedure DoTlsCloseNotifyFinished(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
    procedure DoTlsCloseNotifyError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                    ErrorCode: Cardinal);
  end;

  IDnTlsReadHandler = interface
  ['{09cfa4fd-7117-49dc-8a2c-4d86039c72f6}']
    procedure DoHandshake(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                            Handshake: RawByteString);
    procedure DoRead(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  Buf: PAnsiChar; BufSize: Cardinal);
    procedure DoReadError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);
    procedure DoReadClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
  end;

  IDnTlsLineHandler = interface
  ['{AB1279A4-BBC9-11d5-BDB9-0000212296FE}']
    procedure DoLineHandshake(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                            Handshake: RawByteString);
    procedure DoLine( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                      ReceivedLine: RawByteString; EolFound: Boolean );
    procedure DoLineError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          ErrorCode: Cardinal);
    procedure DoLineClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
  end;
  TDnTlsHandshakeState = (tlsNone, tlsCreateRequest, tlsCreateResponse, tlsSendRequest, tlsReadResponse, tlsReadRequest, tlsSendResponse);

  (* This class represents client TLS handshake request *)
  TDnTlsCRequest = class (TDnTcpRequest)
  protected
    FWSABuf:        WSABUF;
    FFlags:         Cardinal;
    FHandler:       IDnTlsCRequestHandler;
    FTlsServer:     TSimpleTLSInternalServer;
    FRequestStream: TMemoryStream;
    FWritten:       Cardinal;
    FState:         TDnTlsHandshakeState;
    FTlsErrorCode:  Integer;
    
    procedure     SetTransferred(Transferred: Cardinal); override;
    procedure     SendRequestStream(ChannelImpl: TDnTcpChannel);

    //IDnIORequest
    procedure Execute; override;
    function  IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;

    //IDnIOResponse
    procedure CallHandler(Context: TDnThreadContext); override;

  public
    constructor Create(Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTlsCRequestHandler;
      TlsServer: TSimpleTLSInternalServer);
    destructor  Destroy; override;
  end;

  (* This class represents server handshake response - it just writes the next raw data to channel *)
  TDnTlsSResponse = class (TDnTcpRequest)
  protected
    FWSABuf:              WSABUF;
    FFlags:               Cardinal;
    FTLSServer:           TSimpleTLSInternalServer;
    FHandler:             IDnTlsSResponseHandler;
    FWritten:             Cardinal;
    FRequestStream,
    FResponseStream:      TMemoryStream;
    FTlsErrorCode:        Integer;
    
    procedure     SetTransferred(Transferred: Cardinal); override;
    procedure     SendResponseStream(ChannelImpl: TDnTcpChannel);

    //IDnIORequest
    procedure Execute; override;
    function  IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;

    //IDnIOResponse
    procedure CallHandler(Context: TDnThreadContext); override;

  public
    constructor CreateFromString(Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTlsSResponseHandler;
      TLSServer: TSimpleTLSInternalServer; Response: RawByteString);

    destructor Destroy; override;
  end;

  TFRState = (tlsReadHeader,  tlsReadData);
  //This request reads the TLS record
  TDnTlsFragmentRequest = class (TDnTcpRequest)
  protected
    FWSABuf:  WSABUF;
    FRead:    Cardinal;
    FFlags:   Cardinal;
    FRecvStream: TMemoryStream;
    FBuffer:  RawByteString;
    FState:   TFRState;
    FRecordSize: Word;
    FClosed:  Boolean;
    procedure SetTransferred(Transferred: Cardinal); override;

    //IDnIORequest
    procedure Execute; override;
    function IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;

    //IDnIOResponse
    procedure CallHandler(Context: TDnThreadContext); override;
    procedure Reset;
  public
    constructor Create( Channel: TDnTcpChannel; Key: Pointer);
    destructor Destroy; override;
    
  end;


  TDnTlsCloseNotifyRequest = class (TDnTcpRequest)
  protected
    FWSABuf:              WSABUF;
    FFlags:               Cardinal;
    FTLSServer:           TSimpleTLSInternalServer;
    FHandler:             IDnTlsCloseNotifyHandler;
    FWritten:             Cardinal;
    FRequestStream,
    FResponseStream:      TMemoryStream;
    FTlsErrorCode:        Integer;
    FState:               TDnTlsHandshakeState;
    procedure     SetTransferred(Transferred: Cardinal); override;
    procedure     SendResponseStream(ChannelImpl: TDnTcpChannel);

    //IDnIORequest
    procedure Execute; override;
    function  IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;

    //IDnIOResponse
    procedure CallHandler(Context: TDnThreadContext); override;

  public
    constructor Create(Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTlsCloseNotifyHandler;
      TLSServer: TSimpleTLSInternalServer);

    destructor Destroy; override;
  end;

  TDnTlsCloseRequest = class (TDnTcpRequest)
  protected
    FWSABuf:      WSABUF;
    FTempBuffer:  RawByteString;
    FRead:        Cardinal;
    FFlags:       Cardinal;
    FHandler:     IDnTcpCloseHandler;
    FBrutal:      Boolean;
    procedure     SetTransferred(Transferred: Cardinal); override;

    //IDnIORequest
    procedure Execute; override;
    function  IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;

    //IDnIOResponse
    procedure CallHandler(Context: TDnThreadContext); override;

  public
    constructor Create(Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTcpCloseHandler;
                        Brutal: Boolean = False);
    destructor  Destroy; override;
  end;

  TDnTlsReadRequest = class (TDnTcpRequest)
  protected
    FWSABuf:  WSABUF;
    FRead:    Cardinal;
    FToRead:  Cardinal;
    FFlags:   Cardinal;
    FHandler: IDnTlsReadHandler;
    FMustAll: Boolean;
    FStrBuf:  RawByteString;
    FTlsServer: TSimpleTLSInternalServer;

    FResponseStream,
    FDataStream,
    FRecvStream: TMemoryStream;

    //TLS error code
    FTlsErrorCode: Integer;

    //number of read application octets (after TLSDecode)
    FTlsRead: Integer;

    //marks if IOCP is simulated due to read from cache
    FCacheRead: Boolean;

    procedure SetTransferred(Transferred: Cardinal); override;

    //IDnIORequest
    procedure Execute; override;
    function IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;
    //IDnIOResponse
    procedure CallHandler(Context: TDnThreadContext); override;
  public
    constructor Create( Channel: TDnTcpChannel; Key: Pointer;
                        Handler: IDnTlsReadHandler; Buf: PAnsiChar;
                        BufSize: Cardinal; MustAll:  Boolean;
                        TlsServer: TSimpleTLSInternalServer);

    constructor CreateString( Channel:  TDnTcpChannel; Key: Pointer;
                        Handler: IDnTlsReadHandler; BufSize: Integer;
                        MustAll:  Boolean; TlsServer: TSimpleTLSInternalServer);
    destructor Destroy; override;
    procedure Init( Channel: TDnTcpChannel; Key: Pointer;
                    Handler: IDnTlsReadHandler; Buf: PAnsiChar;
                    BufSize: Cardinal; MustAll: Boolean;
                    TlsServer: TSimpleTLSInternalServer);

  end;

  TDnTlsLineRequest = class (TDnTlsFragmentRequest)
  protected
    FEolFound:        Boolean;
    FEolSign:         PAnsiChar;
    FDataStream:      TMemoryStream;
    FResponseStream:  TMemoryStream;
    FCacheRead:       Boolean;
    FTlsErrorCode:    Integer;
    FHandler:         IDnTlsLineHandler;
    FTlsServer:       TSimpleTLSInternalServer;
    FMaxSize:         Cardinal;

  public
    constructor Create( Channel: TDnTcpChannel; Key: Pointer;
                        Handler: IDnTlsLineHandler; MaxSize: Cardinal;
                        TlsServer: TSimpleTLSInternalServer );
    destructor Destroy; override;

    function  CheckForEol(Line: PAnsiChar; Len: Integer): Integer;
    procedure SetTransferred(Transferred: Cardinal); override;
    function  IssueWSARecv( s : TSocket; lpBuffers : LPWSABUF; dwBufferCount : DWORD; var lpNumberOfBytesRecvd : DWORD; var lpFlags : DWORD;
              lpOverlapped : LPWSAOVERLAPPED; lpCompletionRoutine : LPWSAOVERLAPPED_COMPLETION_ROUTINE ): Integer; stdcall;
    //IDnIORequest
    procedure Execute; override;
    function  IsComplete: Boolean; override;
    procedure ReExecute; override;

    //IDnIOResponse
    procedure CallHandler(Context: TDnThreadContext); override;
  public
  end;

  TDnTlsWriteRequest = class (TDnTcpRequest)
  protected
    FWSABuf:        WSABUF;
    FFlags:         Cardinal;
    FHandler:       IDnTcpWriteHandler;
    FTlsServer:     TSimpleTLSInternalServer;
    FWriteStream,
    FDataStream:    TMemoryStream;
    FTlsErrorCode:  Integer;
    FWritten:       Cardinal;

    procedure SetTransferred(Transferred: Cardinal); override;
    procedure Execute; override;
    function  IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;

    procedure CallHandler(Context: TDnThreadContext); override;
  public
(*    constructor Create( Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTcpWriteHandler;
                        Buf: PChar; BufSize: Cardinal;
                        TlsServer: TSimpleTLSInternalServer); overload; *)
    constructor CreateString( Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTcpWriteHandler;
                        Buf: RawByteString; TlsServer: TSimpleTLSInternalServer); overload;
    destructor Destroy; override;
  end;



implementation
var
  CRLFZero:PAnsiChar = #13#10#0;


//----------------------------------------------------------------------------

constructor TDnTlsCRequest.Create(Channel: TDnTcpChannel; Key: Pointer;
                                          Handler: IDnTlsCRequestHandler;
                                          TlsServer: TSimpleTLSInternalServer);
begin
  inherited Create(Channel, Key);

  //save handler reference
  FHandler := Handler;

  //save pointer to StreamSec
  FTlsServer := TlsServer;

  //create handshake request memory stream 
  FRequestStream := TMemoryStream.Create;

  //set state as 'None'
  FState := tlsNone;
end;

destructor TDnTlsCRequest.Destroy;
begin
  inherited Destroy;
end;

function TDnTlsCRequest.RequestType: TDnIORequestType;
begin
  Result := rtWrite;
end;

procedure TDnTlsCRequest.SetTransferred(Transferred: Cardinal);
begin
  FRequestStream.Position := Transferred;
end;

procedure TDnTlsCRequest.SendRequestStream(ChannelImpl: TDnTcpChannel);
var ResCode: Integer;
begin
  FWritten := 0;

  //send handshake request
  FWSABuf.len := FRequestStream.Size - FRequestStream.Position;
  FWSABuf.buf := PAnsiChar(FRequestStream.Memory) + FRequestStream.Position;

  //increase counter of requests
  InterlockedIncrement(PendingRequests);

  //start sending
  ResCode := Winsock2.WSASend(ChannelImpl.SocketHandle, @FWSABuf , 1, FWritten, 0, @FContext, Nil);
  if ResCode <> 0 then
  begin
    ResCode := WSAGetLastError;
    if (ResCode <> WSA_IO_PENDING)  then
      Self.PostError(ResCode, 0);
  end;
end;

procedure TDnTlsCRequest.Execute;
var
  ChannelImpl: TDnTcpChannel;
begin
  inherited Execute;
  ChannelImpl := TDnTcpChannel(FChannel);
  AddRef;
  case FState of
    tlsNone: begin
      //transition to state 'creating handshake request'
      FState := tlsCreateRequest;

      //create handshake request - TLS client is identified
      FTlsServer.TLSConnect(ChannelImpl, FRequestStream, @FTlsErrorCode);
      ChannelImpl.State := 1; //to prevent further TLSAccept

      //transition to state 'sending handshake request'
      FState := tlsSendRequest;

      //move to first octet
      FRequestStream.Position := 0;

      //send stream async
      SendRequestStream(ChannelImpl);
    end; //tlsNone

    tlsSendRequest: begin
      //send the stream further
      SendRequestStream(ChannelImpl);
    end;
  end;

end;

function TDnTlsCRequest.IsComplete: Boolean;
var ChannelImpl: TDnTcpChannel;
begin
  //perform TDnTcpRequest.IsComplete
  inherited IsComplete;

  //extract TDnTcpChannel pointer
  ChannelImpl := TDnTcpChannel(FChannel);

  //preliminary result is "no" - request is not finished
  Result := False;

  //do we get non zero error code?
  if FErrorCode <> 0 then
    Result := True //TCP error occured - the request is finished
  else
  if FRequestStream.Position = FRequestStream.Size then
  begin
    //find the TLS client pointer
    //FStreamSec.FindTLSSession(ChannelImpl, FTlsClient);
    Result := True;
  end;
end;

procedure TDnTlsCRequest.ReExecute;
begin
  Execute;
end;

procedure TDnTlsCRequest.CallHandler(Context: TDnThreadContext);
begin
  try
    if FErrorCode = 0 then
      Self.FHandler.DoTlsCRequestFinished(Context, TDnTcpChannel(FChannel), FKey)
    else
      Self.FHandler.DoTlsCRequestError(Context, TDnTcpChannel(FChannel), FKey, FErrorCode);
  except
  end;
end;


//----------------------------------------------------------------------------

constructor TDnTlsSResponse.CreateFromString(Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTlsSResponseHandler;
      TLSServer: TSimpleTLSInternalServer; Response: RawByteString);
begin
  inherited Create(Channel, Key);

  //save handler
  FHandler := Handler;

  //create response stream
  FResponseStream := TMemoryStream.Create;
  FResponseStream.Write(PAnsiChar(Response)^, Length(Response));
  FResponseStream.Position := 0;

  FRequestStream := TMemoryStream.Create;

  //no sent octets
  FWritten := 0;

  //save TLS server pointer
  FTlsServer := TLSServer;
end;

destructor TDnTlsSResponse.Destroy;
begin

  FreeAndNil(FResponseStream);
  FreeAndNil(FRequestStream);
  
  inherited Destroy;
end;

procedure TDnTlsSResponse.Execute;
var ChannelImpl: TDnTcpChannel;
begin
  inherited Execute;
  AddRef;
  
  //extract ChannelImpl
  ChannelImpl := TDnTcpChannel(FChannel);

  SendResponseStream(ChannelImpl);
end;

function TDnTlsSResponse.RequestType: TDnIORequestType;
begin
  Result := rtWrite;
end;

procedure TDnTlsSResponse.SetTransferred(Transferred: Cardinal);
begin
  FResponseStream.Position := Transferred;
end;

function  TDnTlsSResponse.IsComplete: Boolean;
begin
  if FErrorCode <> 0 then
    Result := True
  else
  Result := FResponseStream.Position = FResponseStream.Size;
end;

procedure TDnTlsSResponse.ReExecute;
begin
  Execute;
end;

procedure TDnTlsSResponse.SendResponseStream(ChannelImpl: TDnTcpChannel);
var ResCode: Integer;
begin
  FWritten := 0;

  //send handshake request
  FWSABuf.len := FResponseStream.Size - FResponseStream.Position;
  FWSABuf.buf := PAnsiChar(FResponseStream.Memory) + FResponseStream.Position;

  //increase counter of requests
  InterlockedIncrement(PendingRequests);

  //start sending
  ResCode := Winsock2.WSASend(ChannelImpl.SocketHandle, @FWSABuf , 1, FWritten, 0, @FContext, Nil);
  if ResCode <> 0 then
  begin
    ResCode := WSAGetLastError;
    if (ResCode <> WSA_IO_PENDING)  then
      Self.PostError(ResCode, 0);
  end;
end;

procedure TDnTlsSResponse.CallHandler(Context: TDnThreadContext);
begin
  try
    if FErrorCode = 0 then
      Self.FHandler.DoTlsSResponseFinished(Context, TDnTcpChannel(FChannel), FKey)
    else
      Self.FHandler.DoTlsSResponseError(Context, TDnTcpChannel(FChannel), FKey, FErrorCode);
  except
  end;
end;

//----------------------------------------------------------------------------

constructor TDnTlsCloseNotifyRequest.Create(Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTlsCloseNotifyHandler;
      TLSServer: TSimpleTLSInternalServer);
begin
  inherited Create(Channel, Key);

  //save handler
  FHandler := Handler;

  //create response stream
  FResponseStream := TMemoryStream.Create;

  //no sent octets
  FWritten := 0;

  //save TLS server pointer
  FTlsServer := TLSServer;

  //initial state
  FState := tlsNone;
end;

destructor TDnTlsCloseNotifyRequest.Destroy;
begin
  inherited Destroy;
end;

procedure TDnTlsCloseNotifyRequest.Execute;
var ChannelImpl: TDnTcpChannel;
begin
  inherited Execute;
  AddRef;
  //extract ChannelImpl
  ChannelImpl := TDnTcpChannel(FChannel);

  case FState of
    tlsNone: begin
      //accept connection
      FTlsServer.TLSClose(ChannelImpl, FResponseStream, @FTlsErrorCode);
      FResponseStream.Position := 0;
      //transition to tlsSendResponse
      FState := tlsSendResponse;

      //send the response
      SendResponseStream(ChannelImpl);
    end;

    tlsSendResponse:
      SendResponseStream(ChannelImpl);
  end;

end;

function TDnTlsCloseNotifyRequest.RequestType: TDnIORequestType;
begin
  Result := rtWrite;
end;

procedure TDnTlsCloseNotifyRequest.SetTransferred(Transferred: Cardinal);
begin
  FResponseStream.Position := Transferred;
end;

function  TDnTlsCloseNotifyRequest.IsComplete: Boolean;
begin
  if FErrorCode <> 0 then
    Result := True
  else
  Result := FResponseStream.Position = FResponseStream.Size;
end;

procedure TDnTlsCloseNotifyRequest.ReExecute;
begin
  Execute;
end;

procedure TDnTlsCloseNotifyRequest.SendResponseStream(ChannelImpl: TDnTcpChannel);
var ResCode: Integer;
begin
  FWritten := 0;

  //send handshake request
  FWSABuf.len := FResponseStream.Size - FResponseStream.Position;
  FWSABuf.buf := PAnsiChar(FResponseStream.Memory) + FResponseStream.Position;

  //increase counter of requests
  InterlockedIncrement(PendingRequests);

  //start sending
  ResCode := Winsock2.WSASend(ChannelImpl.SocketHandle, @FWSABuf , 1, FWritten, 0, @FContext, Nil);
  if ResCode <> 0 then
  begin
    ResCode := WSAGetLastError;
    if (ResCode <> WSA_IO_PENDING)  then
      Self.PostError(ResCode, 0);
  end;
end;

procedure TDnTlsCloseNotifyRequest.CallHandler(Context: TDnThreadContext);
begin
  try
    if FErrorCode = 0 then
      Self.FHandler.DoTlsCloseNotifyFinished(Context, TDnTcpChannel(FChannel), FKey)
    else
      Self.FHandler.DoTlsCloseNotifyError(Context, TDnTcpChannel(FChannel), FKey, FErrorCode);
  except
  end;
end;

//----------------------------------------------------------------------------

constructor TDnTlsCloseRequest.Create(Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTcpCloseHandler; Brutal: Boolean);
begin
  inherited Create(Channel, Key);
  FHandler := Handler;
  SetLength(FTempBuffer, 1024);
  FWSABuf.len := 1024;
  FWSABuf.buf := @FTempBuffer[1];
  FBrutal := Brutal;
end;

function TDnTlsCloseRequest.RequestType: TDnIORequestType;
begin
  if FBrutal then
    Result := rtBrutalClose
  else
    Result := rtClose;
end;

procedure TDnTlsCloseRequest.SetTransferred(Transferred: Cardinal);
begin
  FRead := Transferred;
  FWSABuf.buf := PAnsiChar(FTempBuffer);
  FWSABuf.len := 1024;
end;

procedure TDnTlsCloseRequest.Execute;
var ResCode: Integer;
    ChannelImpl: TDnTcpChannel;
begin
  inherited Execute;
  ChannelImpl := TDnTcpChannel(FChannel);
  Winsock2.shutdown(ChannelImpl.SocketHandle, SD_SEND); //disable sending
  InterlockedIncrement(PendingRequests);
  if not FBrutal then
  begin
    FRead := 0;
    ResCode := Winsock2.WSARecv(ChannelImpl.SocketHandle, @FWSABuf, 1,  FRead, FFlags, @FContext, Nil);
    if ResCode <> 0 then
    begin
      ResCode := WSAGetLastError;
      if ResCode <> WSA_IO_PENDING then
        Self.PostError(ResCode, 0);
    end;
  end else
    PostQueuedCompletionStatus(TDnTcpReactor(ChannelImpl.Reactor).PortHandle, 0,
                                Cardinal(Pointer(ChannelImpl)), @FContext);
end;

procedure TDnTlsCloseRequest.ReExecute;
begin
  Execute;
end;

function TDnTlsCloseRequest.IsComplete: Boolean;
var ChannelImpl: TDnTcpChannel;
begin
  inherited IsComplete;
  ChannelImpl := TDnTcpChannel(FChannel);
  Result := (FRead = 0) or (FErrorCode <> 0);
  if Result then
  begin
    ChannelImpl.CloseSocketHandle;
  end;
end;

procedure TDnTlsCloseRequest.CallHandler(Context: TDnThreadContext);
var ChannelImpl: TDnTcpChannel;
begin
  try
    ChannelImpl := TDnTcpChannel(FChannel);
    if FErrorCode <> 0 then
      FHandler.DoCloseError(Context, TDnTcpChannel(FChannel), FKey, FErrorCode)
    else
      FHandler.DoClose(Context, TDnTcpChannel(FChannel), FKey);
    ChannelImpl.CloseSocketHandle;
    //drop channel
    TDnTcpReactor(ChannelImpl.Reactor).RemoveChannel(TDnTcpChannel(FChannel));
  finally
    //InterlockedDecrement(PendingRequests);
  end;
end;


destructor  TDnTlsCloseRequest.Destroy;
begin
  FHandler := Nil;
  inherited Destroy;
end;
//-------------------------------------------------------------------------------------------------

constructor TDnTlsReadRequest.Create( Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTlsReadHandler; Buf: PAnsiChar;
                                      BufSize: Cardinal; MustAll: Boolean;
                                      TlsServer: TSimpleTLSInternalServer);
begin
  inherited Create(Channel, Key);
  SetLength(FStrBuf, 0);
  Init(Channel, Key, Handler, Buf, BufSize, MustAll, TlsServer);
end;

constructor TDnTlsReadRequest.CreateString( Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTlsReadHandler; BufSize: Integer;
                                      MustAll: Boolean;
                                      TlsServer: TSimpleTLSInternalServer);
begin
  inherited Create(Channel, Key);
  SetLength(FStrBuf, BufSize);
  Init(Channel, Key, Handler, @FStrBuf[1], Length(FStrBuf), MustAll, TlsServer);
end;

procedure TDnTlsReadRequest.Init(Channel: TDnTcpChannel; Key: Pointer;
                                  Handler: IDnTlsReadHandler; Buf: PAnsiChar;
                                  BufSize: Cardinal; MustAll: Boolean;
                                  TlsServer: TSimpleTLSInternalServer);
begin
  //prepare WSABuf record to receive data
  FWSABuf.Len := BufSize;
  FWSABuf.Buf := Buf;

  //set read octets counter to zero
  FRead := 0;

  //save the maximum number of octets to read
  FToRead := BufSize;

  //WSARecv flags
  FFlags := 0;

  //save the pointer to buffer start
  FStartBuffer := @Buf;

  //save the handler
  FHandler := Handler;

  //save the mark if all specified data must be read 
  FMustAll := MustAll;

  //save pointer to TLS server 
  FTlsServer := TlsServer;

  //create TLS streams
  FResponseStream := TMemoryStream.Create;
  FDataStream := TMemoryStream.Create;
  FRecvStream := TMemoryStream.Create;
end;

destructor TDnTlsReadRequest.Destroy;
begin
  FHandler := Nil;
  FreeAndNil(FRecvStream);
  FreeAndNil(FDataStream);
  FreeAndNil(FResponseStream);
  inherited Destroy;
end;

function  TDnTlsReadRequest.RequestType: TDnIORequestType;
begin
  Result := rtRead;
end;

procedure TDnTlsReadRequest.SetTransferred(Transferred: Cardinal);
var S: RawByteString;
    L: Integer;
begin
  L := 0;
  
  if Transferred <> 0 then
  begin
    //copy data to FRecvStream
    FRecvStream.Clear;
    FRecvStream.Write(FWSABuf.buf^, Transferred);
    FRecvStream.Position := 0;

    //save the length of FDataStream
    L := FDataStream.Size;

    //call TLSDecode
    FTlsServer.TLSDecodeData(TDnTcpChannel(FChannel), FRecvStream, FDataStream, FResponseStream, @FTlsErrorCode);

    //check if we response to send
    if FResponseStream.Size > 0 then
    begin
      //move to the begin of response stream
      FResponseStream.Position := 0;

      //extract the data to string buffer
      SetString(S, PAnsiChar(FResponseStream.Memory), FResponseStream.Size);

      //clear response stream
      FResponseStream.Clear;

      //call handler
      FHandler.DoHandshake(Nil, TDnTcpChannel(FChannel), FKey, S);
    end;
  end;

  FRead := Transferred;
  FTlsRead := FDataStream.Size - L;
end;

procedure TDnTlsReadRequest.Execute;
var ChannelImpl: TDnTcpChannel;
    ResCode: Integer;
begin
  inherited Execute;
  ChannelImpl := TDnTcpChannel(FChannel);
  AddRef;

  //check the channel read cache
  FRead := ChannelImpl.ExtractFromCache(FWSABuf.buf, FToRead);

  //inc pending requests count
  InterlockedIncrement(PendingRequests);

  if FRead = FToRead then //if all data are read?
  begin
    PostQueuedCompletionStatus(TDnTcpReactor(ChannelImpl.Reactor).PortHandle, FRead,
                                Cardinal(Pointer(ChannelImpl)), @FContext);
    FCacheRead := True;
  end
  else
  begin //not read yet...
    Inc(FWSABuf.buf, FRead);
    Dec(FWSABuf.len, FRead);
    ResCode := Winsock2.WSARecv(ChannelImpl.SocketHandle, @FWSABuf, 1,  FRead, FFlags, @FContext, Nil);
    //ResCode := Integer(ReadFileEx(ChannelImpl.SocketHandle, @FWSABuf, FRead, @FContext, Nil));
    if ResCode <> 0 then
    begin
      ResCode := WSAGetLastError;
      if ResCode <> WSA_IO_PENDING then
        Self.PostError(ResCode, FRead)
      else
        ;
    end;
  end;
end;

function TDnTlsReadRequest.IsComplete: Boolean;
begin
  inherited IsComplete;

  //is error occur?
  if (FErrorCode <> 0) or (FTlsErrorCode <> 0) then
    Result := True
  else
  if FCacheRead then //if all data were fetched from decoded data cache
  begin
    Result := True; //then read operation is finished
  end
  else              //well, we check the result of true WSARecv - not simulated
  if FMustAll then
  begin
    //is we read&decode enough data?
    Result := FDataStream.Size >= FToRead;

    //can we put the extra data to cache?
    if FToRead < FDataStream.Size then
      TDnTcpChannel(FChannel).Add2Cache(PAnsiChar(FDataStream.Memory) + FToRead, FDataStream.Size - FToRead);

    //copy data to result buffer
    Move(PAnsiChar(FDataStream.Memory)^, FWSABuf.buf^, FToRead);
  end
  else
  if FRead > 0 then
  begin
    Result := True;
  end
  else
    Result := True; //close notification got

  if (FRead = 0) or (FErrorCode <> 0) or (FTlsErrorCode <> 0) then
    TDnTcpChannel(FChannel).StopTimeOutTracking;
end;

procedure TDnTlsReadRequest.ReExecute;
begin
//  Dec(FWSABuf.len, FRead);
//  Inc(FWSABuf.buf, FRead);
  FRead := 0;
  Execute;
end;

procedure TDnTlsReadRequest.CallHandler(Context: TDnThreadContext);
begin
  try
    if (FErrorCode = 0) and (FTlsErrorCode = 0) and (FRead <> 0) then
      FHandler.DoRead(Context, TDnTcpChannel(FChannel), FKey, FStartBuffer, FToRead - FWSABuf.len)
    else
    if FRead = 0 then
      FHandler.DoReadClose(Context, TDnTcpChannel(FChannel), FKey)
    else
      FHandler.DoReadError(Context, TDnTcpChannel(FChannel), FKey, FErrorCode);
  finally
    //InterlockedDecrement(RequestsPending);
  end;
end;
//-----------------------------------------------------------------------------


constructor TDnTlsLineRequest.Create( Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTlsLineHandler; MaxSize: Cardinal;
                                      TlsServer: TSimpleTLSInternalServer );
begin
  //call inherited TDnTcpRequest constructor
  inherited Create(Channel, Key);

  //create TLS streams
  (* FRecvStream := TMemoryStream.Create; *)
  FDataStream := TMemoryStream.Create;
  FResponseStream := TMemoryStream.Create;
  FTlsServer := TlsServer;

  (* Reset(Channel, Key, Handler, MaxSize); *)

  //save handler reference
  FHandler := Handler;

  //save max size of received length
  FMaxSize := MaxSize;

  //the end-of-line sequence
  FEolSign := CRLFZero; //CRLF - zero terminated string
end;

const MaxSizePerRecv: Cardinal = 65536;

(*
procedure TDnTlsLineRequest.Reset(Channel: TDnTcpChannel; Key: Pointer;
                                  Handler: IDnTlsLineHandler; MaxSize: Cardinal);
begin
  //bind POverlapped to this object
  FContext.FRequest := Pointer(Self);

  //allocate memory for recv'ed data - allocate 8192 bytes
  SetLength(FRecv, 8192);
  FToRead := 8192;

  FWSABuf.Len := 8192; //FWSABuf.Len := MaxSize;
  FWSABuf.Buf := PChar(FRecv);

  //max size to read
  FToRead := 8192;

  FRead := 0;
  FFlags := 0;

  //pointer to buffer
  FStartBuffer := PChar(FRecv);

  //the end-of-line is not found yet
  FEolFound := False;

  //none read in the last WSARecv
  FWasRead := 0;

  //number of read bytes totally
  FTotalWasRead := 0;
end;
*)
destructor TDnTlsLineRequest.Destroy;
begin
  FreeAndNil(FDataStream);
  FreeAndNil(FResponseStream);
  FHandler := Nil;
  inherited Destroy;
end;


(*function  TDnTlsLineRequest.RequestType: TDnIORequestType;
begin
  Result := rtRead;
end;*)

//scans Line for CRLF sequence
function TDnTlsLineRequest.CheckForEol(Line: PAnsiChar; Len: Integer): Integer;
var Ptr: PAnsiChar;
begin
  Ptr := StrPos(Line, FEolSign);
  if Ptr <> Nil then
    Result := Ptr - Line + 2
  else
    Result := -1;
end;

procedure TDnTlsLineRequest.SetTransferred(Transferred: Cardinal);
var S: String;
    L: Integer;
    ChannelImpl: TDnTcpChannel;
begin
  if not FCacheRead then
    inherited SetTransferred(Transferred);
end;

function  TDnTlsLineRequest.IssueWSARecv( s : TSocket; lpBuffers : LPWSABUF; dwBufferCount : DWORD; var lpNumberOfBytesRecvd : DWORD; var lpFlags : DWORD;
              lpOverlapped : LPWSAOVERLAPPED; lpCompletionRoutine : LPWSAOVERLAPPED_COMPLETION_ROUTINE ): Integer;
begin
  Result := Winsock2.WSARecv(s, lpBuffers, dwBufferCount, lpNumberOfBytesRecvd, lpFlags, lpOverlapped, lpCompletionRoutine);
end;


procedure TDnTlsLineRequest.Execute;
var ResCode: Integer;
    Len: Cardinal;
    ChannelImpl: TDnTcpChannel;
begin
  //get the pointer to TDnTcpChannel
  ChannelImpl := TDnTcpChannel(FChannel);

  //check if there is data in cache
  if ChannelImpl.CacheHasData then
  begin
    //read from cache to temporary buffer
    FRead := ChannelImpl.ExtractFromCache(FWSABuf.buf, FWSABuf.len);

    //check if there is EOL
    Len := Self.CheckForEol(FWSABuf.buf, FRead);

    if Len <> $FFFFFFFF then
    begin //EOL is found
      //give back to cache tail of data
      ChannelImpl.InsertToCache(FWSABuf.buf + Len, FRead - Len);

      FRead := Len;

      FCacheRead := True;

      //simulate successful read request
      PostQueuedCompletionStatus(TDnTcpReactor(ChannelImpl.Reactor).PortHandle, FRead, Cardinal(Pointer(ChannelImpl)), @FContext);
    end else
    if FRead <> 0 then
      PostQueuedCompletionStatus(TDnTcpReactor(ChannelImpl.Reactor).PortHandle, FRead, Cardinal(Pointer(ChannelImpl)), @FContext)
  end
  else
    inherited Execute;
end;

function TDnTlsLineRequest.IsComplete: Boolean;
var ChannelImpl: TDnTcpChannel;
    Found: Integer;
    Tail: Integer;
    NeedToRead: Cardinal;
    OldSize, NewSize: Integer;
    S: String;
    R: Boolean;
begin
  R := inherited IsComplete;
  if not R then
  begin
    Result := R;
    Exit;
  end;
  
  ChannelImpl := TDnTcpChannel(FChannel);

  //if we got error code or got signal about connection close
  if (FErrorCode <> 0) or (FRead = 0)then
  begin
    ChannelImpl.StopTimeOutTracking;
    Result := True;
    Exit;
  end;

  //if all data was fetched from cache
  if FCacheRead then
  begin
    Result := True;
    Exit;
  end;

  //set EOL marker as not found
  FEolFound := False;

  //check if TLSAccept was called
  if R and (ChannelImpl.State = 0) then
  begin
    FRecvStream.Position := 0;
    FTlsServer.TLSAccept(ChannelImpl, FRecvStream, FResponseStream, @FTlsErrorCode);
    FRecvStream.Clear;
    ChannelImpl.State := 1;
  end
  else
  begin
    FRecvStream.Position := 0;
    FTlsServer.TLSDecodeData(ChannelImpl, FRecvStream, FDataStream, FResponseStream, @FTlsErrorCode); //decode from TLS
  end;

  //check if there is response data
  if FResponseStream.Size > 0 then
  begin
    //extract stream to string
    SetString(S, PAnsiChar(FResponseStream.Memory), FResponseStream.Size);
    try
      //call handler
      FHandler.DoLineHandshake(Nil, TDnTcpChannel(FChannel), FKey, S);
    except
    end;
    //clear the response stream
    FResponseStream.Size := 0;
  end;



  if FDataStream.Size <> 0 then
    Found := Self.CheckForEol(PAnsiChar(FDataStream.Memory), FDataStream.Size)
  else
    Found := -1;

  //if EOL is not found and the length of line less than FMaxSize
  if (Found = -1) then
  begin
    if FDataStream.Size < FMaxSize then
      Result := False
    else
    begin
      //extract tail to cache
      ChannelImpl.Add2Cache(PAnsiChar(FDataStream.Memory) + FMaxSize, FDataStream.Size - FMaxSize);

      //cut the stream to required FMaxSize
      FDataStream.Size := FMaxSize;

      //signal about success
      Result := True;
    end;
  end
  else
  begin //all line is read
    FEolFound := True;
    //extract tail to cache
    ChannelImpl.Add2Cache(PAnsiChar(FDataStream.Memory) + Found, FDataStream.Size - Found);

    //cut the stream to required FMaxSize
    FDataStream.Size := Found;

    //signal about success
    Result := True;
  end;

  if not Result then
    Reset; //reset the TLS reading routine 
end;

procedure TDnTlsLineRequest.ReExecute;
begin
  Execute;
end;

procedure TDnTlsLineRequest.CallHandler(Context: TDnThreadContext);
var Temp: String;
begin
  try
    if FErrorCode = 0 then
    begin
      if FRead = 0 then
        FHandler.DoLineClose(Context, TDnTcpChannel(FChannel), FKey)
      else
      begin
        SetString(Temp, PAnsiChar(FDataStream.Memory), FDataStream.Size);
        FHandler.DoLine(Context, TDnTcpChannel(FChannel), FKey, Temp, FEolFound);
      end
    end else
      FHandler.DoLineError(Context, TDnTcpChannel(FChannel), FKey, FErrorCode);
  finally
    //InterlockedDecrement(RequestsPending);
  end;
end;


//-----------------------------------------------------------------------------

(*constructor TDnTlsWriteRequest.Create(Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTcpWriteHandler; Buf: PChar;
                                      BufSize: Cardinal;
                                      TlsServer: TSimpleTLSInternalServer);
begin
  inherited Create(Channel, Key);

  FWSABuf.Len := BufSize;
  FWSABuf.Buf := Buf;
  FFlags := 0;

  FStartBuffer := @Buf;
  FHandler := Handler;
  FTlsServer := TlsServer;

  FWriteStream := TMemoryStream.Create;
  FDataStream := TMemoryStream.Create;
end; *)

constructor TDnTlsWriteRequest.CreateString(Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTcpWriteHandler; Buf: String;
                                      TlsServer: TSimpleTLSInternalServer);
begin
  inherited Create(Channel, Key);

  FDataStream := TMemoryStream.Create;
  FDataStream.Write(Buf[1], Length(Buf));
  FDataStream.Position := 0;
  FWriteStream := TMemoryStream.Create;
  TlsServer.TLSEncodeData(TDnTcpChannel(FChannel), FDataStream, FWriteStream, @FErrorCode);
  FWriteStream.Position := 0;
  
  FWSABuf.Len := FWriteStream.Size;
  FWSABuf.Buf := FWriteStream.Memory;
  FFlags := 0;
  FHandler := Handler;
  FTlsServer := TlsServer;
end;

destructor TDnTlsWriteRequest.Destroy;
begin
  FreeAndNil(FDataStream);
  FreeAndNil(FWriteStream);

  FHandler := Nil;
  inherited Destroy;
end;

function TDnTlsWriteRequest.RequestType: TDnIORequestType;
begin
  Result := rtWrite;
end;

procedure TDnTlsWriteRequest.SetTransferred(Transferred: Cardinal);
begin
  FWriteStream.Position := FWriteStream.Position + Transferred;
  FWSABuf.buf := PAnsiChar(FWriteStream.Memory) + Transferred;
  FWSABuf.len := FWriteStream.Size - FWriteStream.Position;
end;

procedure TDnTlsWriteRequest.Execute;
var ResCode: Integer;
    ChannelImpl: TDnTcpChannel;
    P: Integer;
begin
  inherited Execute;

  //find channel implementation
  ChannelImpl := TDnTcpChannel(FChannel);

  //increase the number of pending requests
  InterlockedIncrement(PendingRequests);

  ResCode := Winsock2.WSASend(ChannelImpl.SocketHandle, @FWSABuf , 1, FWritten, 0, @FContext, Nil);
  if ResCode = 0 then
  begin //WSASend completed immediately
    ;
  end else
  begin
    ResCode := WSAGetLastError;
    if (ResCode <> WSA_IO_PENDING)  then
      Self.PostError(ResCode, 0);
  end;
end;

function TDnTlsWriteRequest.IsComplete: Boolean;
begin
  inherited IsComplete;
  Result := (FWriteStream.Position = FWriteStream.Size) or (FErrorCode <> 0) or (FTlsErrorCode <> 0);
end;

procedure TDnTlsWriteRequest.ReExecute;
begin
  Execute;
end;

procedure TDnTlsWriteRequest.CallHandler(Context: TDnThreadContext);
begin
  if FErrorCode = 0 then
    FHandler.DoWrite(Context, TDnTcpChannel(FChannel), FKey, FStartBuffer, FWritten)
  else
    FHandler.DoWriteError(Context, TDnTcpChannel(FChannel), FKey, FErrorCode);
end;
//----------------------------------------------------------------------------

constructor TDnTlsFragmentRequest.Create(Channel: TDnTcpChannel; Key: Pointer);
begin
  inherited Create(Channel, Key);

  SetLength(FBuffer, 8192);

  FWSABuf.Buf := @FBuffer[1];
  FWSABuf.Len := Length(FBuffer);
  FRead := 0;
  FFlags := 0;
  FRecvStream := TMemoryStream.Create;
  FState := tlsReadHeader;
end;

destructor TDnTlsFragmentRequest.Destroy;
begin
  FreeAndNil(FRecvStream);
  inherited Destroy;
end;

procedure TDnTlsFragmentRequest.Reset;
begin
  FState := tlsReadHeader;
  FRecvStream.Clear;
  //FResponseStream.Clear;
  //FDataStream.Clear;
end;

function  TDnTlsFragmentRequest.RequestType: TDnIORequestType;
begin
  Result := rtRead;
end;


procedure TDnTlsFragmentRequest.Execute;
var ChannelImpl: TDnTcpChannel;
    ResCode: Integer;
begin
  inherited Execute;

  //get the channel object
  ChannelImpl := TDnTcpChannel(FChannel);

  //inc pending requests count
  InterlockedIncrement(PendingRequests);

  //setup the receiving buffer to get the remaining part of header
  FWSABuf.buf := @FBuffer[1];
  if FState = tlsReadHeader then
    FWSABuf.len := 5 - FRecvStream.Size
  else
    FWSABuf.len := FRecordSize - (FRecvStream.Size - 5);

  FRead := 0;
  ResCode := Winsock2.WSARecv(ChannelImpl.SocketHandle, @FWSABuf, 1,  FRead, FFlags, @FContext, Nil);

  if ResCode <> 0 then
  begin
    ResCode := WSAGetLastError;
    if ResCode <> WSA_IO_PENDING then
      Self.PostError(ResCode, FRead)
    else
      ;
  end;

end;

procedure TDnTlsFragmentRequest.SetTransferred(Transferred: Cardinal);
var RecordSize: Word;
begin
  FClosed := Transferred = 0;
  if Transferred > 0 then
  begin
    //save the received data to FRecvStream
    FRecvStream.Write(FBuffer[1], Transferred);

    if FState = tlsReadHeader then
    begin
      if FRecvStream.Size = 5 then
      begin
        //transition to state "receive TLS data"
        FState := tlsReadData;

        //read the TLS data size
        FRecvStream.Position := 3;
        FRecvStream.Read(FRecordSize, sizeof(FRecordSize));
        FRecordSize := ntohs(FRecordSize);
      end;
    end;
  end;


end;

function TDnTlsFragmentRequest.IsComplete;
begin
  Result := ((FState = tlsReadData) and (FRecordSize = FRecvStream.Size-5)) or (FErrorCode <> 0) or FClosed;
end;

procedure TDnTlsFragmentRequest.ReExecute;
begin
  Execute;
end;

//IDnIOResponse
procedure TDnTlsFragmentRequest.CallHandler(Context: TDnThreadContext);
begin
end;


//----------------------------------------------------------------------------
end.
