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
unit DnTcpWriteFile;
interface
uses  Windows, WS2,
      DnRtl, DnConst,
      DnTcpReactor, DnTcpChannel, DnTcpRequest;

const
  DnFileReadBlock = 65536;
  
type
  IDnTcpWriteFileHandler = interface
  ['{9C7B392E-5B24-4aa6-A81C-2043948196AB}']
    procedure DoWriteFile(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          const FileName: String; Written: Int64);
    procedure DoWriteFileError( Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                ErrorCode: Cardinal );
  end;

  TDnTcpWriteFileRequest = class (TDnTcpRequest)
  protected
    FFileHandle:    THandle;
    FStartPos:      Int64;
    FFinishPos:     Int64;
    FFileName:      String;
    FHandler:       IDnTcpWriteFileHandler;
    FWSABUF:        WSABUF;
    FBuffer:        RawByteString;
    FWritten:       Cardinal;
    FToWrite:       Cardinal;
    FFlags:         Cardinal;
    FEOR:           Boolean;
    FTotalWritten:  Int64;
    
    function  ReadBlock: Boolean;

  public
    constructor Create( Channel: TDnTcpChannel; Key: Pointer; Handler: IDnTcpWriteFileHandler;
                        const FileName: String; StartPos, FinishPos: Int64);
    destructor  Destroy; override;

    procedure SetTransferred (Value: Cardinal); override;

    //IDnIORequest
    procedure Execute; override;
    function  IsComplete: Boolean; override;
    procedure ReExecute; override;
    function  RequestType: TDnIORequestType; override;
    procedure CallHandler(Context: TDnThreadContext); override;
  end;

implementation

constructor TDnTcpWriteFileRequest.Create( Channel: TDnTcpChannel; Key: Pointer;
                                        Handler: IDnTcpWriteFileHandler;
                                        const FileName: String;
                                        StartPos, FinishPos: Int64);
begin
  inherited Create(Channel, Key);
  FFileName := FileName;
  FFileHandle := INVALID_HANDLE_VALUE;
  if FStartPos > FFinishPos then
    raise EDnException.Create(ErrInvalidParameter, 0);
  FStartPos := StartPos;
  FFinishPos := FinishPos;

  if GetFileSize64(FileName) <= FinishPos then
    raise EDnException.Create(ErrInvalidParameter, 0);

  FFileHandle := Windows.CreateFile(PChar(FFileName), GENERIC_READ, FILE_SHARE_READ,
    Nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL + FILE_FLAG_SEQUENTIAL_SCAN, 0);
  if FFileHandle = INVALID_HANDLE_VALUE then
    raise EDnException.Create(ErrWin32Error, GetLastError(), 'CreateFile');
  SetFilePointer(FFileHandle, FStartPos, Nil, FILE_BEGIN);

  FWSABuf.Len := 0;
  FWSABuf.Buf := Nil;
  SetLength(FBuffer, DnFileReadBlock);
  FWritten := 0;
  FToWrite := 0;
  FFlags := 0;
  FTotalSize := FFinishPos - FStartPos + 1;
  FStartBuffer := Nil;
  FHandler := Handler;
  FEOR := False;
  FTotalWritten := 0;
  if ReadBlock = False then
    raise EDnException.Create(ErrWin32Error, GetLastError(), 'ReadFile');
end;


destructor TDnTcpWriteFileRequest.Destroy;
begin
  if FFileHandle <> INVALID_HANDLE_VALUE then
    CloseHandle(FFileHandle);
  inherited Destroy;
end;

procedure TDnTcpWriteFileRequest.SetTransferred(Value: Cardinal);
begin
  FWritten := Value;
  Inc(FWSABuf.buf, FWritten);
  Dec(FWSABuf.len, FWritten);
  Inc(FTotalWritten, FWritten);
end;

function TDnTcpWriteFileRequest.ReadBlock: Boolean;
var WasRead: Cardinal;
    ToRead: Int64;
begin
  //take a portion from file
  Result := True;
  if not FEOR then
  begin
    WasRead := 0;
    ToRead := FFinishPos - FStartPos + 1 - FTotalWritten;
    if ToRead > Length(FBuffer) then
      ToRead := Length(FBuffer);
    if ReadFile(FFileHandle, FBuffer[1], Cardinal(ToRead),
                WasRead, Nil) = LongBool(True) then
    begin
      FToWrite := WasRead;
      FEOR := WasRead < Cardinal(Length(FBuffer));
      if FEOR and (FTotalWritten + FToWrite < FFinishPos - FStartPos + 1) then
        Result := False
      else
      begin
        FWSABuf.buf := @FBuffer[1];
        FWSABuf.len := FToWrite;
        FWritten := 0;
      end;
    end else
      Result := False;
  end;
end;

function TDnTcpWriteFileRequest.IsComplete: Boolean;
var ChannelImpl: TDnTcpChannel;
begin
  Result := (FTotalWritten = FFinishPos - FStartPos + 1) or (FErrorCode <> 0);
  if FErrorCode <> 0 then
  begin
    ChannelImpl := FChannel as TDnTcpChannel;
    ChannelImpl.StopTimeOutTracking;
  end;
end;

procedure TDnTcpWriteFileRequest.ReExecute;
begin
  //ReadBlock;
  Execute;
end;

procedure TDnTcpWriteFileRequest.Execute;
var ResCode: Integer;
    ChannelImpl: TDnTcpChannel;
begin
  inherited Execute;
  ChannelImpl := FChannel as TDnTcpChannel;
  ResCode := WS2.WSASend(ChannelImpl.SocketHandle, @FWSABuf , 1, FWritten, 0, @FContext, Nil);
  //ResCode := Integer(WriteFileEx(ChannelImpl.SocketHandle, @FWSABuf , FWritten, FContext.FOverlapped, Nil));
  if ResCode = 0 then
  begin //WSASend completed immediately
    //Dec(FWSABuf.len, FWritten);
    //Inc(FWSABuf.buf, FWritten);
    //PostQueuedCompletionStatus(FChannel.Reactor.PortHandle, FWritten, Cardinal(Pointer(FChannel)), @FContext);
  end else
  begin
    ResCode := WSAGetLastError;
    if (ResCode <> WSA_IO_PENDING)  then
      Self.PostError(ResCode, 0);
  end;
end;

function  TDnTcpWriteFileRequest.RequestType: TDnIORequestType;
begin
  Result := rtWrite;  
end;

procedure TDnTcpWriteFileRequest.CallHandler(Context: TDnThreadContext);
begin
  begin
    if FErrorCode = 0 then
      FHandler.DoWriteFile(Context, FChannel as TDnTcpChannel, FKey, FFileName, FTotalWritten)
    else
      FHandler.DoWriteFileError(Context, FChannel as TDnTcpChannel, FKey, FErrorCode);
    FBuffer := '';
  end;
end;

end.
