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
unit DnTcpRequests;
interface
uses
  Classes, SysUtils, Windows, Winsock, Winsock2, Math,
  DnTcpReactor, DnConst, DnRtl, DnTcpRequest, DnTcpChannel, DnDataQueue;

const
  TempStorageSize = 8192;
   
type

  TDnTcpRequestInfo = class
  public
    constructor Create(_Type: TDnIORequestType; Ptr: Pointer);
    destructor Destroy; override;
  protected
    FType: TDnIORequestType;
    FRequest: Pointer;
  end;
  
  IDnTcpCloseHandler = interface
  ['{AB1279A1-BBC9-11d5-BDB9-0000212296FE}']
    procedure DoClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
    procedure DoCloseError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);
  end;

  TDnTcpCloseRequest = class (TDnTcpRequest)
  protected
    FWSABuf:      WSABUF;
    FTempBuffer:  RawByteString;
    FRead:        Cardinal;
    FFlags:       Cardinal;
    FHandler:     IDnTcpCloseHandler;
    FBrutal:      Boolean;

  public
    constructor Create(Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTcpCloseHandler;
                        Brutal: Boolean = False);
    destructor  Destroy; override;

    procedure     SetTransferred(Transferred: Cardinal); override;
    procedure     Execute; override;
    function      IsComplete: Boolean; override;
    procedure     ReExecute; override;
    function      RequestType: TDnIORequestType; override;
    procedure     CallHandler(Context: TDnThreadContext); override;

  end;

  IDnTcpReadHandler = interface
  ['{AB1279A2-BBC9-11d5-BDB9-0000212296FE}']
    procedure DoRead(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  Buf: PAnsiChar; BufSize: Cardinal);
    procedure DoReadError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                  ErrorCode: Cardinal);
    procedure DoReadClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
  end;

  TDnTcpReadRequest = class (TDnTcpRequest)
  protected
    FWSABuf:  WSABUF;
    FRead:    Cardinal;
    FToRead:  Cardinal;
    FFlags:   Cardinal;
    FHandler: IDnTcpReadHandler;
    FMustAll: Boolean;
    FStrBuf:  RawByteString;

  public
    constructor Create( Channel: TDnTcpChannel; Key: Pointer;
                        Handler: IDnTcpReadHandler; Buf: PAnsiChar;
                        BufSize: Cardinal; MustAll:  Boolean = True);// overload;
    constructor CreateString( Channel:  TDnTcpChannel; Key: Pointer;
                        Handler: IDnTcpReadHandler; BufSize: Integer;
                        MustAll:  Boolean = True);
    destructor Destroy; override;
    procedure     Init( Channel: TDnTcpChannel; Key: Pointer;
                    Handler: IDnTcpReadHandler; Buf: PAnsiChar;
                    BufSize: Cardinal; MustAll: Boolean = True);

    procedure     SetTransferred(Transferred: Cardinal); override;
    procedure     Execute; override;
    function      IsComplete: Boolean; override;
    procedure     ReExecute; override;
    function      RequestType: TDnIORequestType; override;
    procedure     CallHandler(Context: TDnThreadContext); override;

  end;

  IDnTcpLineHandler = interface
  ['{AB1279A4-BBC9-11d5-BDB9-0000212296FE}']
    procedure DoLine( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                      ReceivedLine: RawByteString; EolFound: Boolean );
    procedure DoLineError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          ErrorCode: Cardinal);
    procedure DoLineClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
  end;

  TDnTcpLineRequest = class (TDnTcpRequest)
  protected
    FWSABuf:    WSABUF;
    FRead:      Cardinal;
    FToRead:    Integer;
    FWasRead:   Integer;
    FTotalWasRead:
                Integer;
    FFlags:     Cardinal;
    FHandler:   IDnTcpLineHandler;
    FMaxSize:   Integer;
    FRecv:      RawByteString;
    FEolFound:  Boolean;
    FEolSign:   PAnsiChar;

    FBufInitialSize: Integer;
    FBufGranularity: Integer;
    
    function  CheckForEol(Line: PAnsiChar; Len: Integer): Integer;
    function  IssueWSARecv( s : TSocket; lpBuffers : LPWSABUF; dwBufferCount : DWORD; var lpNumberOfBytesRecvd : DWORD; var lpFlags : DWORD;
              lpOverlapped : LPWSAOVERLAPPED; lpCompletionRoutine : LPWSAOVERLAPPED_COMPLETION_ROUTINE ): Integer; stdcall;
    procedure Reset(Channel: TDnTcpChannel; Key: Pointer;
                        Handler: IDnTcpLineHandler; MaxSize: Cardinal);
  public
    constructor Create( Channel: TDnTcpChannel; Key: Pointer;
                        Handler: IDnTcpLineHandler; MaxSize: Cardinal );
    destructor Destroy; override;

    procedure     SetTransferred(Transferred: Cardinal); override;
    procedure     Execute; override;
    function      IsComplete: Boolean; override;
    procedure     ReExecute; override;
    function      RequestType: TDnIORequestType; override;
    procedure     CallHandler(Context: TDnThreadContext); override;

  end;

  IDnTcpWriteHandler = interface
  ['{AB1279A5-BBC9-11d5-BDB9-0000212296FE}']
    procedure DoWrite(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                      Buf: PAnsiChar; BufSize: Cardinal);
    procedure DoWriteError( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                            ErrorCode: Cardinal );
    procedure DoWriteStream(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                      Stream: TStream);
  end;


  TDnTcpWriteRequest = class (TDnTcpRequest)
  protected
    FWSABuf:            WSABUF;
    FWritten:           Cardinal;
    FToWrite:           Cardinal;
    FFlags:             Cardinal;
    FHandler:           IDnTcpWriteHandler;
    FTempStorage:       RawByteString;
    FStream:            TStream;
    FDataQueue:         TDnDataQueue;
    FDecoratedStream:   TStream;
    
    procedure ReadStream;
    procedure ReadQueue;
  public
    constructor Create( Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTcpWriteHandler;
                        Buf: PAnsiChar; BufSize: Cardinal);
    constructor CreateString( Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTcpWriteHandler;
                        Buf: RawByteString);
    constructor CreateStream( Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTcpWriteHandler;
                        Stream: TStream);
    constructor CreateQueue(Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTcpWriteHandler;
                        Queue: TDnDataQueue);

    destructor Destroy; override;

    procedure       SetTransferred(Transferred: Cardinal); override;
    procedure       Execute; override;
    procedure       ReExecute; override;
    procedure       CallHandler(Context: TDnThreadContext); override;

    function        IsComplete:   Boolean; override;
    function        RequestType:  TDnIORequestType; override;

    property        DecoratedStream: TStream read FDecoratedStream write FDecoratedStream;
  end;

{$ifdef Debug_IOCP}
procedure Setup;

procedure Teardown;
{$endif}



implementation
{$ifdef Debug_IOCP}
uses
   logging
  ,logSupport
  ;

var
 log : TabsLog;

{$endif}


var
  CRLFZero:PAnsiChar = #13#10#0;


constructor TDnTcpRequestInfo.Create(_Type: TDnIORequestType; Ptr: Pointer);
begin
  inherited Create;
  FType := _Type;
  FRequest := Ptr;
end;

destructor TDnTcpRequestInfo.Destroy;
begin
  inherited Destroy;
end;

//----------------------------------------------------------------------------
//----------------------------------------------------------------------------

constructor TDnTcpCloseRequest.Create(Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTcpCloseHandler; Brutal: Boolean);
begin
  FBrutal := Brutal;
  
  inherited Create(Channel, Key);
  FHandler := Handler;
  SetLength(FTempBuffer, 1024);
  FWSABuf.len := 1024;
  FWSABuf.buf := @FTempBuffer[1];

end;

function TDnTcpCloseRequest.RequestType: TDnIORequestType;
begin
  if FBrutal then
    Result := rtBrutalClose
  else
    Result := rtClose;
end;

procedure TDnTcpCloseRequest.SetTransferred(Transferred: Cardinal);
begin
  FRead := Transferred;
  FWSABuf.buf := @FTempBuffer[1];
  FWSABuf.len := 1024;
end;

procedure TDnTcpCloseRequest.Execute;
var ResCode: Integer;
    ChannelImpl: TDnTcpChannel;
begin
  inherited Execute;

  //extract the TDnTcpChannel pointer
  ChannelImpl := TDnTcpChannel(FChannel);

  //close the socket handler
  ChannelImpl.CloseSocketHandle;

  //increase the counter of pending requests
  InterlockedIncrement(PendingRequests);

  //increase ref.count to avoid freeing request object.
  AddRef;

  //send 'close completed' packet.
  PostQueuedCompletionStatus((TDnTcpReactor(ChannelImpl.Reactor)).PortHandle, 0,
                                Cardinal(Pointer(ChannelImpl)), @FContext);
end;

procedure TDnTcpCloseRequest.ReExecute;
begin
  Execute;
end;

function TDnTcpCloseRequest.IsComplete: Boolean;
var ChannelImpl: TDnTcpChannel;
begin
  inherited IsComplete;

  Result := True;
end;


procedure TDnTcpCloseRequest.CallHandler(Context: TDnThreadContext);
var ChannelImpl: TDnTcpChannel;
begin
  try
    ChannelImpl := TDnTcpChannel(FChannel);// as TDnTcpChannel;

    //call handler
    if FErrorCode <> 0 then
      FHandler.DoCloseError(Context, ChannelImpl, FKey, FErrorCode)
    else
      FHandler.DoClose(Context, ChannelImpl, FKey);

    //remove requests that do not run yet
    ChannelImpl.DeleteNonActiveRequests;

    //dereference channel from reactor
    TDnTcpReactor(ChannelImpl.Reactor).RemoveChannel(ChannelImpl);
    
  finally
    //InterlockedDecrement(PendingRequests);
  end;
end;


destructor  TDnTcpCloseRequest.Destroy;
begin
  FHandler := Nil;
  inherited Destroy;
end;
//-------------------------------------------------------------------------------------------------

constructor TDnTcpReadRequest.Create( Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTcpReadHandler; Buf: PAnsiChar;
                                      BufSize: Cardinal; MustAll: Boolean = True );
begin
  inherited Create(Channel, Key);
  SetLength(FStrBuf, 0);
  Init(Channel, Key, Handler, Buf, BufSize, MustAll);
end;

constructor TDnTcpReadRequest.CreateString( Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTcpReadHandler; BufSize: Integer;
                                      MustAll: Boolean = True );
begin
  inherited Create(Channel, Key);
  SetLength(FStrBuf, BufSize);
  Init(Channel, Key, Handler, @FStrBuf[1], Length(FStrBuf), MustAll);
end;

procedure TDnTcpReadRequest.Init(Channel: TDnTcpChannel; Key: Pointer;
                                  Handler: IDnTcpReadHandler; Buf: PAnsiChar;
                                  BufSize: Cardinal; MustAll: Boolean = True);
begin
  FWSABuf.Len := BufSize;
  FWSABuf.Buf := PByte(Buf);
  FRead := 0;
  FToRead := BufSize;
  FFlags := 0;
  //FTotalSize := BufSize;
  FStartBuffer := Buf;
  FHandler := Handler;
  FMustAll := MustAll;
end;

destructor TDnTcpReadRequest.Destroy;
begin
  FHandler := Nil;
  inherited Destroy;
end;

function  TDnTcpReadRequest.RequestType: TDnIORequestType;
begin
  Result := rtRead;
end;

procedure TDnTcpReadRequest.SetTransferred(Transferred: Cardinal);
begin
  FRead := Transferred;
  Inc(FWSABuf.buf, FRead);
  Dec(FWSABuf.len, FRead);
end;

procedure TDnTcpReadRequest.Execute;
var ChannelImpl:  TDnTcpChannel;
    ResCode:      Integer;
begin
  inherited Execute;

  ChannelImpl := TDnTcpChannel(FChannel);

  //check the channel read cache
  FRead := ChannelImpl.ExtractFromCache(PAnsiChar(FWSABuf.buf), FToRead);
  //inc pending requests count
  InterlockedIncrement(PendingRequests);
  if FRead = FToRead then
  begin
    AddRef;
    PostQueuedCompletionStatus((ChannelImpl.Reactor as TDnTcpReactor).PortHandle, FRead,
                                Cardinal(Pointer(ChannelImpl)), @FContext)
  end
  else
  begin //not read yet...
    Inc(FWSABuf.buf, FRead);
    Dec(FWSABuf.len, FRead);
    AddRef;
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

function TDnTcpReadRequest.IsComplete: Boolean;
var ChannelImpl:  TDnTcpChannel;
    ChannelName:  String;
begin
  inherited IsComplete;
  ChannelImpl := TDnTcpChannel(FChannel);
  if ChannelImpl.IsClient then
    ChannelName := 'Client'
  else
    ChannelName := 'Server';

{$ifdef Debug_IOCP}
  Log.LogDebug('Read %s is finished', [ChannelName]);
{$endif}
  Result := (FWSABuf.len = 0) or    //everything is read
            (FRead = 0) or          //client close
            (FErrorCode <> 0) or    //network error
            not FMustAll;           //raw read
  if (FRead = 0) or (FErrorCode <> 0) then
    ChannelImpl.StopTimeOutTracking;
end;


procedure TDnTcpReadRequest.ReExecute;
begin
//  Dec(FWSABuf.len, FRead);
//  Inc(FWSABuf.buf, FRead);
  FRead := 0;
  Execute;
end;

procedure TDnTcpReadRequest.CallHandler(Context: TDnThreadContext);
begin
  try
    if (FErrorCode = 0) and (FRead <> 0) then
      FHandler.DoRead(Context, FChannel as TDnTcpChannel, FKey, FStartBuffer, FToRead - FWSABuf.len)
    else
    if FRead = 0 then
      FHandler.DoReadClose(Context, FChannel as TDnTcpChannel, FKey)
    else
      FHandler.DoReadError(Context, FChannel as TDnTcpChannel, FKey, FErrorCode);
  finally
    //InterlockedDecrement(RequestsPending);
  end;
end;
//-----------------------------------------------------------------------------

constructor TDnTcpLineRequest.Create( Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTcpLineHandler; MaxSize: Cardinal );
begin
  inherited Create(Channel, Key);
  if MaxSize > 1024 then
    FBufInitialSize := 1024
  else
    FBufInitialSize := MaxSize;
  
  Reset(Channel, Key, Handler, MaxSize);
  FContext.FRequest := Pointer(Self);
  SetLength(FRecv, MaxSize);
  FWSABuf.Len := MaxSize;
  FWSABuf.Buf := @FRecv[1];
  FRead := 0;
  FToRead := MaxSize;
  FFlags := 0;
  //FTotalSize := MaxSize;
  FStartBuffer := PAnsiChar(FRecv);
  
  FHandler := Handler;
  FMaxSize := MaxSize;
  FEolFound := False;
  FWasRead := 0;
  FEolSign := CRLFZero; //CRLF - zero terminated string
end;

const MaxSizePerRecv: Cardinal = 65536;

procedure TDnTcpLineRequest.Reset(Channel: TDnTcpChannel; Key: Pointer;
                                  Handler: IDnTcpLineHandler; MaxSize: Cardinal);
begin
  //bind POverlapped to this object
  FContext.FRequest := Pointer(Self);
  //allocate memory for recv'ed data
  SetLength(FRecv, FBufInitialSize);//SetLength(FRecv, MaxSize);
  FWSABuf.Len := FBufInitialSize; //FWSABuf.Len := MaxSize;
  FToRead := FBufInitialSize; //FToRead := MaxSize;
  FWSABuf.Buf := @FRecv[1];
  FRead := 0;
  FFlags := 0;
  FStartBuffer := @FRecv[1];
  FHandler := Handler;
  FMaxSize := MaxSize;
  FEolFound := False;
  FWasRead := 0;
  FEolSign := CRLFZero; //CRLF - zero terminated string
  FTotalWasRead := 0;
end;

destructor TDnTcpLineRequest.Destroy;
begin
  FHandler := Nil;
  inherited Destroy;
end;

function  TDnTcpLineRequest.RequestType: TDnIORequestType;
begin
  Result := rtRead;
end;

//scans Line for CRLF sequence
function TDnTcpLineRequest.CheckForEol(Line: PAnsiChar; Len: Integer): Integer;
var Ptr: PAnsiChar;
begin
  Ptr := StrPos(Line, FEolSign);
  if Ptr <> Nil then
    Result := Ptr - Line + Length(FEolSign)
  else
    Result := -1;
end;

procedure TDnTcpLineRequest.SetTransferred(Transferred: Cardinal);
begin
  FRead := Transferred;
  Dec(FWSABuf.len, FRead);
  Inc(FWSABuf.buf, FRead);
  Inc(FTotalWasRead, FRead); 
end;

function  TDnTcpLineRequest.IssueWSARecv( s : TSocket; lpBuffers : LPWSABUF; dwBufferCount : DWORD; var lpNumberOfBytesRecvd : DWORD; var lpFlags : DWORD;
              lpOverlapped : LPWSAOVERLAPPED; lpCompletionRoutine : LPWSAOVERLAPPED_COMPLETION_ROUTINE ): Integer;
begin
  Result := Winsock2.WSARecv(s, lpBuffers, dwBufferCount, lpNumberOfBytesRecvd, lpFlags, lpOverlapped, lpCompletionRoutine);
end;


procedure TDnTcpLineRequest.Execute;
var ResCode: Integer;
    Len: Cardinal;
    ChannelImpl: TDnTcpChannel;
begin
  inherited Execute;
  FContext.FRequest := Self;
  //grab the channel read cache
  InterlockedIncrement(PendingRequests);
  ChannelImpl := FChannel as TDnTcpChannel;
  if ChannelImpl.CacheHasData then
  begin
    FRead := ChannelImpl.ExtractFromCache(PAnsiChar(FWSABuf.buf), FWSABuf.len);
    Len := Self.CheckForEol(PAnsiChar(FWSABuf.buf), FRead);
    if Len <> $FFFFFFFF then
    begin
      ChannelImpl.InsertToCache(PAnsiChar(FWSABuf.buf) + Len, FRead - Len);
      FRead := Len;
      AddRef;
      PostQueuedCompletionStatus((ChannelImpl.Reactor as TDnTcpReactor).PortHandle, FRead, Cardinal(Pointer(ChannelImpl)), @FContext);
      //OutputDebugString('PostQueuedCompletionStatus');
    end else
    if FRead <> 0 then
    begin
      AddRef;
      PostQueuedCompletionStatus((ChannelImpl.Reactor as TDnTcpReactor).PortHandle, FRead, Cardinal(Pointer(ChannelImpl)), @FContext);
      //OutputDebugString('PostQueuedCompletionStatus');
    end;
  end
  else
  begin //start reading from socket
    AddRef;
    ResCode := IssueWSARecv(ChannelImpl.SocketHandle, @FWSABuf, 1,  FRead, FFlags, @FContext, Nil);

    if ResCode <> 0 then
    begin
      ResCode := WSAGetLastError;
      if ResCode <> WSA_IO_PENDING then
        Self.PostError(ResCode, FRead);
    end;
  end;
end;

function TDnTcpLineRequest.IsComplete: Boolean;
var ChannelImpl: TDnTcpChannel;
    Found: Integer;
    Tail: Integer;
    NeedToRead: Cardinal;
    OldSize, NewSize: Integer;
begin
  inherited IsComplete;
  ChannelImpl := FChannel as TDnTcpChannel;
  if (FErrorCode <> 0) or (FRead = 0)then
  begin
    ChannelImpl.StopTimeOutTracking;
    Result := True;
    Exit;
  end;
  FEolFound := False;
  Dec(FToRead, FRead);

  Inc(FWasRead, FRead);
  //Inc(FTotalWasRead, FRead);
  if FWasRead <> 0 then
    Found := Self.CheckForEol(PAnsiChar(FRecv), FWasRead)
  else
    Found := -1;

  if (Found = -1) and (FToRead <> 0) then
    Result := False
  else
  if (Found = -1) and (FToRead = 0) then
  begin //ok, here we read all FToRead's bytes but EOL is not found
    //ok, do we need to read smth else?
    if Length(FRecv) < FMaxSize then
    begin
      OldSize := Length(FRecv);
      NewSize := Trunc(Length(FRecv) * 1.25 + 0.5);
      if NewSize > FMaxSize then
        NewSize := FMaxSize;
      SetLength(FRecv, NewSize);
      NeedToRead := NewSize - OldSize;
      FWSABuf.buf := @FRecv[OldSize+1];
      FWSABuf.len := NeedToRead;
      FToRead := NeedToRead;
      FRead := 0; FWasRead := 0;
      Execute;
      Result := False;
    end else
      Result := True
  end
  else
  if (Found <> -1) then
  begin
    Tail := FWasRead - Found;
    ChannelImpl.Add2Cache(PAnsiChar(FRecv) + Found, Tail);
    Inc(FToRead, Tail); Dec(FWasRead, Tail);
    Dec(FTotalWasRead, Tail);
    SetLength(FRecv, Found);
    FEolFound := True;
    Result := True;
  end else
    Result := True;
end;


procedure TDnTcpLineRequest.ReExecute;
begin
  Execute;
end;

procedure TDnTcpLineRequest.CallHandler(Context: TDnThreadContext);
//var ChannelImpl: TDnTcpChannel;
begin
  try
    if FErrorCode = 0 then
    begin
      if FRead = 0 then
        FHandler.DoLineClose(Context, TDnTcpChannel(FChannel), FKey)
      else
        FHandler.DoLine(Context, TDnTcpChannel(FChannel), FKey, FRecv, FEolFound);
    end else
      FHandler.DoLineError(Context, FChannel as TDnTcpChannel, FKey, FErrorCode);
  finally
    //InterlockedDecrement(RequestsPending);
  end;
end;
//-----------------------------------------------------------------------------

constructor TDnTcpWriteRequest.Create(Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTcpWriteHandler; Buf: PAnsiChar;
                                      BufSize: Cardinal);
begin
  inherited Create(Channel, Key);

  FWSABuf.Len := BufSize;
  FWSABuf.Buf := PByte(Buf);
  FWritten := 0;
  FToWrite := BufSize;
  FFlags := 0;
  //FTotalSize := BufSize;
  FStartBuffer := @Buf;
  FHandler := Handler;
  FTempStorage := '';
end;

constructor TDnTcpWriteRequest.CreateString(Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTcpWriteHandler; Buf: RawByteString);
begin
  inherited Create(Channel, Key);

  FWSABuf.Len := Length(Buf);
  FWSABuf.Buf := @Buf[1];
  FWritten := 0;
  FToWrite := Length(Buf);
  FFlags := 0;
  FTotalSize := Length(Buf);
  FStartBuffer := PAnsiChar(Buf);
  FHandler := Handler;
  FTempStorage := Buf;
end;

constructor TDnTcpWriteRequest.CreateStream(Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTcpWriteHandler; Stream: TStream);

begin
  inherited Create(Channel, Key);

  //initialize temporary buffer
  SetLength(FTempStorage, TempStorageSize);

  //early save stream object to allow ReadStream method to work
  FStream := Stream;

  //read stream to temporary storage
  ReadStream;

  //zero flags
  FFlags := 0;

  //save total size of stream
  FTotalSize := FStream.Size;

  //save handler interface
  FHandler := Handler;

end;

constructor TDnTcpWriteRequest.CreateQueue(Channel: TDnTcpChannel; Key: Pointer;
                                      Handler: IDnTcpWriteHandler; Queue: TDnDataQueue);

begin
  inherited Create(Channel, Key);

  //initialize temporary buffer
  SetLength(FTempStorage, TempStorageSize);

  //early save stream object to allow ReadStream method to work
  FDataQueue := Queue;

  //zero flags
  FFlags := 0;

  //save handler interface
  FHandler := Handler;

  ReadQueue;
end;


destructor TDnTcpWriteRequest.Destroy;
begin
  FHandler := Nil;
  if not FRunning and (FStream <> Nil) then
    FStream.Free;
  inherited Destroy;
end;

function TDnTcpWriteRequest.RequestType: TDnIORequestType;
begin
  Result := rtWrite;
end;

procedure TDnTcpWriteRequest.SetTransferred(Transferred: Cardinal);
begin
  FWritten := Transferred;
  Dec(FWSABuf.len, FWritten);
  Inc(FWSABuf.buf, FWritten);

  if Assigned(FDataQueue) then
    FDataQueue.Delete(Transferred);
end;

procedure TDnTcpWriteRequest.Execute;
var ResCode:      Integer;
    ChannelImpl:  TDnTcpChannel;
    ChannelName:  String;
begin
  inherited Execute;

  //get the TDnTcpChannel object pointer
  ChannelImpl := TDnTcpChannel(FChannel);

  //optional log

  if ChannelImpl.IsClient then
    ChannelName := 'Client'
  else
    ChannelName := 'Server';

  {$ifdef Debug_IOCP}
  Log.LogDebug('Write %s is running', [ChannelName]);
{$endif}


  //increase the global number of pending requests (as we start new one)
  InterlockedIncrement(PendingRequests);

  //increment the usage counter
  AddRef;

  //start I/O
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

function TDnTcpWriteRequest.IsComplete: Boolean;
var ChannelName: String;
    ChannelImpl: TDnTcpChannel;
begin
  Result := inherited IsComplete;

  //optional log
  ChannelImpl := TDnTcpChannel(FChannel);

  if ChannelImpl.IsClient then
    ChannelName := 'Client'
  else
    ChannelName := 'Server';


{$ifdef Debug_IOCP}
  Log.LogDebug('Write %s is finished', [ChannelName]);
{$endif}

  if not Assigned(FStream) then
    Result := (FWSABuf.len = 0) or (FErrorCode <> 0)
  else
  begin
    //Is there is network error ?
    if FErrorCode <> 0 then
      Result := True
    else
    begin
      //Is temporary buffer is written fully?
      if FWSABuf.len = 0 then
      begin
        if Assigned(FStream) then
        begin
          if FStream.Position < FStream.Size then
          begin
            ReadStream;
            Result := False;
          end
          else
            Result := True;
        end
        else
        if Assigned(FDataQueue) then
        begin
          if FDataQueue.Size > 0 then
          begin
            ReadQueue;
            Result := False
          end
          else
            Result := True;
        end;
      end
      else
        Result := False;
    end;
  end;
end;


procedure TDnTcpWriteRequest.ReExecute;
begin
  Execute;
end;

procedure TDnTcpWriteRequest.CallHandler(Context: TDnThreadContext);
begin
  if FErrorCode = 0 then
  begin
    if FStream <> Nil then
      FHandler.DoWriteStream(Context, FChannel as TDnTcpChannel, FKey, FStream)
    else
      FHandler.DoWrite(Context, FChannel as TDnTcpChannel, FKey, FStartBuffer, FWritten)
  end
  else
    FHandler.DoWriteError(Context, FChannel as TDnTcpChannel, FKey, FErrorCode);

  if FStream <> Nil then
    FreeAndNil(FStream);
  FTempStorage := '';
end;

procedure TDnTcpWriteRequest.ReadStream;
begin
  //read from stream to temporary buffer
  FToWrite := FStream.Read(FTempStorage[1], TempStorageSize);
  
  //setup WSABuf
  FWSABuf.Len := FToWrite;
  FWSABuf.Buf := @FTempStorage[1];

  //zero FWritten
  FWritten := 0;
end;

procedure TDnTcpWriteRequest.ReadQueue;
begin
  //read from stream to temporary buffer
  SetString(FTempStorage, PAnsiChar(FDataQueue.Memory), Min(FDataQueue.Size, TempStorageSize));
  
  FToWrite := Min(FDataQueue.Size, TempStorageSize);

  //setup WSABuf
  FWSABuf.Len := FToWrite;
  FWSABuf.Buf := @FTempStorage[1];

  //zero FWritten
  FWritten := 0;
end;

//----------------------------------------------------------------------------

{$ifdef Debug_IOCP}

procedure Setup;
begin
  RegisterLogArea(Log,'IOCP.TCPRequests');
end;

procedure Teardown;
begin
  Log := nil
end;
{$endif}

end.
