{$I DnConfig.inc}
unit DnHttpServer;

interface
uses  WinSock2, Classes, SysUtils, SyncObjs, Windows, contnrs,
      DnRtl, DnTcpReactor, DnTcpListener, DnTcpRequestor,
      DnAbstractExecutor, DnSimpleExecutor, DnAbstractLogger,
      DnFileLogger, DnWinsockMgr, DnTcpChannel, DnFileCachedLogger,
      DnMsgClientInfo, DnTcpRequest, DnStringList, DnHttpParser,
      DnTcpFileWriter, DnCallbackLogger;

const
  HTTP_BUFFER_SIZE = 16384;

type
  // Class describes HTTP specialized TCP connection.
  TDnHttpChannel = class(TDnTcpChannel)
  protected
    // Temporary buffer to hold
    FTempBuffer: array [0..HTTP_BUFFER_SIZE] of AnsiChar;

    // Buffer to hold unparsed HTTP data
    FHttpBuffer: array [0..HTTP_BUFFER_SIZE] of AnsiChar;

    // Amount of used buffer.
    FBufferUsed: Cardinal;

    // Parser for HTTP requests.
    FRequest: TDnHttpRequest;

    // Marks if this channel is keep-alive
    FKeepAlive: Boolean;

    // Assembler to build HTTP response data
    FResponse: TDnHttpWriter;

    // Amount of sent bytes
    FSentBytes: Int64;

    // Form data parser
    FFormData: TDnFormDataParser;

    FCloseAfterSend:  Boolean;
    function GetTempBufferPtr: PAnsiChar;
    function GetTempBufferSize: Integer;

    function GetBufferPtr: PByte;
    function GetBufferUsed: Cardinal;
    function GetBufferFree: Cardinal;

    procedure EnqueueData(Buf: Pointer; BufSize: Integer);
    procedure DeleteData(BufSize: Integer);

  public
    constructor   Create(Reactor: TObject; Sock: TSocket; RemoteAddr: TSockAddrIn);
    destructor    Destroy; override;

    property BufferPtr:       PByte             read GetBufferPtr;
    property BufferUsed:      Cardinal          read FBufferUsed write FBufferUsed;
    property BufferFree:      Cardinal          read GetBufferFree;
    property Request:         TDnHttpRequest    read FRequest write FRequest;
    property Response:        TDnHttpWriter     read FResponse write FResponse;
    property FormData:        TDnFormDataParser read FFormData;
    property KeepAlive:       Boolean           read FKeepAlive write FKeepAlive;
    property SentBytes:       Int64             read FSentBytes write FSentBytes;
    property CloseAfterSend:  Boolean           read FCloseAfterSend write FCloseAfterSend;

    property TempBufferPtr:   PAnsiChar        read GetTempBufferPtr;
    property TempBufferSize:  Integer          read GetTempBufferSize;
  end;

type
  TDnHttpRequestEvent = procedure (Sender: TObject; Channel: TDnHttpChannel; Stage: TDnHttpRequestStage) of object;
  TDnHttpTimeToSendEvent = procedure (Sender: TObject; Channel: TDnHttpChannel) of object;
  TDnHttpLogEvent = procedure (Sender: TObject; Level: TDnLogLevel; const Msg: String) of object;
  TDnHttpConnectedEvent = procedure (Sender: TObject; Channel: TDnHttpChannel) of object;
  TDnHttpDisconnectedEvent = procedure (Sender: TObject; Channel: TDnHttpChannel) of object;

  TDnHttpServer = class(TComponent)
  protected
    FWinsock:         TDnWinsockMgr;
    FListener:        TDnTcpListener;
    FReactor:         TDnTcpReactor;
    FLogger:          TDnAbstractLogger;
    FExecutor:        TDnSimpleExecutor;
    FRequestor:       TDnTcpRequestor;
    FActive:          Boolean;
    FFileWriter:      TDnTcpFileWriter;
    FKeepAliveTime:   Integer;


    FOnRequest:       TDnHttpRequestEvent;
    FOnTimeToSend:    TDnHttpTimeToSendEvent;
    FOnLog:           TDnHttpLogEvent;
    FOnConnected:     TDnHttpConnectedEvent;
    FOnDisconnected:  TDnHttpDisconnectedEvent;

    procedure     AllocChain;
    procedure     FreeChain;
    procedure     Start;
    procedure     Stop;

    procedure     SetPort(Value: Word);
    function      GetPort: Word;
    procedure     SetIP(Value: AnsiString);
    function      GetIP: AnsiString;
    procedure     SetActive(Value: Boolean);
    function      GetActive: Boolean;
    procedure     SetThreadNum(Value: Integer);
    function      GetThreadNum: Integer;

    procedure     ChannelConnected(Context: TDnThreadContext; Channel: TDnTcpChannel);
    procedure     ChannelCreate(Context: TDnThreadContext; Socket: TSocket; Addr: TSockAddrIn;
                    Reactor: TDnTcpReactor; var ChannelImpl: TDnTcpChannel);
    procedure     TcpRead(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          Buf: PByte; BufSize: Cardinal);
    procedure     TcpWrite(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           Buf: PByte; BufSize: Cardinal);
    procedure     TcpWriteStream (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           Stream: TStream);
    procedure     TcpError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           ErrorCode: Cardinal);
    procedure     TcpClose(Context: TDnThreadContext; Channel: TDnTcpChannel;
                            Key: Pointer);
    procedure     TcpClientClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);

    procedure     TcpFileWritten(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                FileName: String; Written: Int64);
    procedure     TcpFileError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                ErrorCode: Cardinal );
    procedure     LogMessage(Level: TDnLogLevel; const Msg: String);
    procedure     ChannelTimeout(Context: TDnThreadContext; Channel: TDnTcpChannel);
    procedure     UserMessage(Context: TDnThreadContext; Channel: TDnTcpChannel; SignalType: Integer; UserData: Pointer);

    function      ProcessHeader (HttpChannel: TDnHttpChannel): Integer;
    function      ProcessFormURLEncoded (HttpChannel: TDnHttpChannel): Integer;
    function      ProcessFormData (HttpChannel: TDnHttpChannel): Integer;
    procedure     SendBadRequest (HttpChannel: TDnHttpChannel);
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;

    procedure   SendFile(Channel: TDnHttpChannel; FileName: String);
    procedure   SendData(Channel: TDnHttpChannel; Buf: Pointer; BufSize: Integer);
    procedure   SendResponse(Channel: TDnHttpChannel);

    // Helper function to get file size
    function    GetFileSize(const FileName: String): Integer;

  published
    property Port:            Word                read GetPort write SetPort;
    property IP:              AnsiString          read GetIP write SetIP;
    property Active:          Boolean             read GetActive write SetActive;
    property Threads:         Integer             read GetThreadNum write SetThreadNum;
    property KeepAliveTime:   Integer             read FKeepAliveTime write FKeepAliveTime;

    property OnRequest:       TDnHttpRequestEvent read FOnRequest write FOnRequest;
    property OnTimeToSend:    TDnHttpTimeToSendEvent read FOnTimeToSend write FOnTimeToSend;
    property OnLog:           TDnHttpLogEvent read FOnLog write FOnLog;
    property OnConnected:     TDnHttpConnectedEvent read FOnConnected write FOnConnected;
    property OnDisconnected:  TDnHttpDisconnectedEvent read FOnDisconnected write FOnDisconnected;
  end;

implementation

constructor TDnHttpChannel.Create(Reactor: TObject; Sock: TSocket; RemoteAddr: TSockAddrIn);
begin
  inherited Create(Reactor, Sock, RemoteAddr);
  FRequest := TDnHttpRequest.Create;
  FResponse := TDnHttpWriter.Create;
  FFormData := TDnFormDataParser.Create;

end;

destructor TDnHttpChannel.Destroy;
begin
  FRequest.Free;
  FResponse.Free;
  FFormData.Free;
  inherited Destroy;
end;

function TDnHttpChannel.GetTempBufferPtr: PAnsiChar;
begin
  Result := @FTempBuffer;
end;

function TDnHttpChannel.GetTempBufferSize: Integer;
begin
  Result := Sizeof(FTempBuffer);
end;

function TDnHttpChannel.GetBufferPtr: PByte;
begin
  Result := @FHttpBuffer;
end;

function TDnHttpChannel.GetBufferUsed: Cardinal;
begin
  Result := FBufferUsed;
end;

function TDnHttpChannel.GetBufferFree: Cardinal;
begin
  Result := Sizeof(FHttpBuffer) - FBufferUsed;
end;

procedure TDnHttpChannel.EnqueueData(Buf: Pointer; BufSize: Integer);
begin
  if BufSize > Self.BufferFree then
    raise EDnException.Create(0,0);

  Move(PAnsiChar(Buf)^, FHttpBuffer[FBufferUsed], BufSize);
  FBufferUsed := FBufferUsed + BufSize;
end;

procedure TDnHttpChannel.DeleteData(BufSize: Integer);
begin
  if BufSize = FBufferUsed then
    FBufferUsed := 0
  else
  begin
    Move(FHttpBuffer[BufSize], FHttpBuffer[0], FBufferUsed - BufSize);
    Dec(FBufferUsed, BufSize);
  end;
end;

constructor TDnHttpServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  AllocChain;
  FActive := False;
end;

destructor TDnHttpServer.Destroy;
begin
  FreeChain;

  inherited Destroy;
end;

procedure TDnHttpServer.AllocChain;
begin
  FKeepAliveTime := 5;

  FWinsock := TDnWinsockMgr.Create(Nil);
  FWinsock.Active := True;

  FLogger :=    TDnCallbackLogger.Create(Nil);
  FLogger.ShowProcessId := False;
  FLogger.ShowThreadId := True;
  FLogger.ShowDateTime := True;

  TDnCallbackLogger(FLogger).OnLogMessage := LogMessage;

  FReactor :=   TDnTcpReactor.Create(Nil);
  FRequestor := TDnTcpRequestor.Create(Nil);
  FListener :=  TDnTcpListener.Create(Nil);
  FExecutor :=  TDnSimpleExecutor.Create(Nil);
  FFileWriter := TDnTcpFileWriter.Create(Nil);

  FListener.OnCreateChannel := Self.ChannelCreate;
  FListener.OnIncoming := Self.ChannelConnected;

  FReactor.Logger := FLogger;
  FReactor.Executor := FExecutor;
  FReactor.OnTimeout := ChannelTimeout;
  FReactor.OnUserMessage := UserMessage;

  FRequestor.Logger := FLogger;
  FRequestor.Executor := FExecutor;
  FRequestor.Reactor := FReactor;

  FRequestor.OnRead := Self.TcpRead;
  FRequestor.OnWrite := Self.TcpWrite;
  FRequestor.OnWriteStream := Self.TcpWriteStream;
  FRequestor.OnClose := Self.TcpClose;
  FRequestor.OnClientClose := Self.TcpClientClose;

  FFileWriter.Logger := FLogger;
  FFileWriter.Executor := FExecutor;
  FFileWriter.Reactor := FReactor;
  FFileWriter.OnFileWritten := Self.TcpFileWritten;
  FFileWriter.OnFileWriteError := Self.TcpFileError;

  FListener.Logger := FLogger;
  FListener.Executor := FExecutor;
  FListener.Reactor := FReactor;

end;

procedure TDnHttpServer.FreeChain;
begin
  Stop;

  FreeAndNil(FReactor);
  FreeAndNil(FListener);
  FreeAndNil(FExecutor);
  FreeAndNil(FRequestor);
  FreeAndNil(FFileWriter);
  FWinsock.Active := False;
  FreeAndNil(FWinsock);
  FreeAndNil(FLogger);
end;

procedure TDnHttpServer.Start;
begin
  if FActive then
    Exit;

  FLogger.Active := True;
  FReactor.Active := True;
  FExecutor.Active := True;
  FRequestor.Active := True;
  FListener.Active := True;

  FActive := True;
end;

procedure TDnHttpServer.Stop;
begin
  if not FActive then
    Exit;

  FListener.Active := False;
  FListener.WaitForShutdown;

  //Close all channels
  FReactor.CloseChannels;

  while FReactor.GetChannelCount > 0 do
    Windows.Sleep(1);

  FReactor.Active := False;
  FRequestor.Active := False;
  FExecutor.Active := False;
  FLogger.Active := False;
  FActive := False;
end;

procedure TDnHttpServer.SetPort(Value: Word);
begin
  FListener.Port := Value;
end;

function  TDnHttpServer.GetPort: Word;
begin
  Result := FListener.Port;
end;

procedure TDnHttpServer.SetIP(Value: AnsiString);
begin
  FListener.Address := Value;
end;

function  TDnHttpServer.GetIP: AnsiString;
begin
  Result := FListener.Address;
end;

procedure TDnHttpServer.SetActive(Value: Boolean);
begin
  if FActive and not Value then
    Stop
  else
  if not FActive and Value then
    Start;
end;

function  TDnHttpServer.GetActive: Boolean;
begin
  Result := FActive;
end;

procedure     TDnHttpServer.SetThreadNum(Value: Integer);
begin
  FReactor.ThreadSize := Value;
end;

function      TDnHttpServer.GetThreadNum: Integer;
begin
  Result := FReactor.ThreadSize;
end;

procedure TDnHttpServer.ChannelConnected(Context: TDnThreadContext; Channel: TDnTcpChannel);
begin
  // Notify about new connection
  if Assigned(FOnConnected) then
    FOnConnected(Self, TDnHttpChannel(Channel));

  // Start pump data
  FRequestor.RawRead(Channel, Nil, TDnHttpChannel(Channel).TempBufferPtr, TDnHttpChannel(Channel).TempBufferSize);
end;

procedure TDnHttpServer.ChannelCreate(Context: TDnThreadContext; Socket: TSocket; Addr: TSockAddrIn;
                    Reactor: TDnTcpReactor; var ChannelImpl: TDnTcpChannel);
begin
  // Create HTTP channel instance
  ChannelImpl := TDnHttpChannel.Create(Reactor, Socket, Addr);
  ChannelImpl.TimeOut := FKeepAliveTime;
end;

function FindCRLFCRLF(Buf: PAnsiChar; BufSize: Integer): Integer;
var
    RP: PAnsiChar;
    CRLF2: PAnsiChar;
begin
  Buf[BufSize] := #0;
  CRLF2 := #13#10#13#10;
  RP := AnsiStrPos(Buf, CRLF2);
  if RP = Nil then
    Result := -1
  else
    Result := RP - Buf;
end;

function FindCRLF(Buf: PAnsiChar; BufSize: Integer): Integer;
var
    RP: PAnsiChar;
    CRLF2: PAnsiChar;
begin
  Buf[BufSize] := #0;
  CRLF2 := #13#10;
  RP := AnsiStrPos(Buf, CRLF2);
  if RP = Nil then
    Result := -1
  else
    Result := RP - Buf;
end;

procedure TDnHttpServer.TcpRead(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          Buf: PByte; BufSize: Cardinal);
var HttpChannel: TDnHttpChannel;
    Processed: Integer;
begin
  // Cast channel object to HTTP channel
  HttpChannel := TDnHttpChannel(Channel);

  // Save read buffer size
  HttpChannel.EnqueueData(Buf, BufSize);

  // Run next read request
  FRequestor.RawRead(Channel, Nil, HttpChannel.TempBufferPtr, HttpChannel.TempBufferSize);

  FLogger.LogMsg(llMandatory, 'Data is read');

  // Check the request parser state
  Processed := 0;
  repeat
    case HttpChannel.Request.Stage of
      hrsHeader:            Processed := ProcessHeader(HttpChannel);
      hrsFormUrlEncoded:    Processed := ProcessFormURLEncoded(HttpChannel);
      hrsFormData:          Processed := ProcessFormData(HttpChannel);
    end;
  until Processed = 0;

end;

procedure TDnHttpServer.TcpWrite(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                          Buf: PByte; BufSize: Cardinal);
var HttpChannel: TDnHttpChannel;
begin
  HttpChannel := TDnHttpChannel(Channel);

  FLogger.LogMsg(llMandatory, 'Data is written.');

  // Increase counter of sent bytes
  HttpChannel.SentBytes := HttpChannel.SentBytes + BufSize;

  // Ask about new data for ChunkedEncoding case
  if HttpChannel.Response.ChunkedEncoding and not HttpChannel.Response.IsLastChunk and not HttpChannel.CloseAfterSend then
  begin
    FLogger.LogMsg(llMandatory, 'Sending OnTimeToSend event.');

    if Assigned(FOnTimeToSend) then
      FOnTimeToSend(Self, HttpChannel);
  end
  else
  begin
    // Check if all response is sent ok
    //if HttpChannel.SentBytes = HttpChannel.Response.HeaderSize + HttpChannel.Response.BodySize then
    begin
      // Check if we deal with Keep-Alive connection
      if not HttpChannel.KeepAlive or HttpChannel.CloseAfterSend then
        FRequestor.Close(Channel, Nil, True);
      (*
      else
        FRequestor.RawRead(Channel, Nil, HttpChannel.BufferPtr + HttpChannel.BufferUsed, HttpChannel.BufferFree); *)
    end;
  end;

end;

procedure TDnHttpServer.TcpWriteStream (Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           Stream: TStream);
begin
  ;
end;

procedure TDnHttpServer.TcpError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                           ErrorCode: Cardinal);
begin
  FRequestor.Close(Channel, Nil, True);
end;

procedure  TDnHttpServer.TcpClose(Context: TDnThreadContext; Channel: TDnTcpChannel;
                            Key: Pointer);
begin
  if Assigned(FOnDisconnected) then
    FOnDisconnected(Self, TDnHttpChannel(Channel));

  FLogger.LogMsg(llMandatory, 'Connection is closed.');
end;

procedure  TDnHttpServer.TcpClientClose(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  FLogger.LogMsg(llMandatory, 'Client closed connection.');

  FRequestor.Close(Channel, Nil, True);
end;

procedure  TDnHttpServer.TcpFileWritten(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                FileName: String; Written: Int64);
var HttpChannel: TDnHttpChannel;
begin
  HttpChannel := TDnHttpChannel(Channel);

  // Increase counter of sent bytes
  HttpChannel.SentBytes := HttpChannel.SentBytes + Written;

  // Ask about new data for ChunkedEncoding case
  if HttpChannel.Response.ChunkedEncoding then
  begin
    if Assigned(FOnTimeToSend) then
      FOnTimeToSend(Self, HttpChannel);
  end
  else
  begin
    // Check if all FContentSize is sent already
    //if HttpChannel.Response.HeaderSize + HttpChannel.Response.ContentLength  = HttpChannel.SentBytes then
    begin
      // Check if we deal with Keep-Alive connection
      if not HttpChannel.KeepAlive then
        FRequestor.Close(Channel, Nil, True);
    end;
  end;
end;

procedure  TDnHttpServer.TcpFileError(Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer;
                                ErrorCode: Cardinal );
begin
  FRequestor.Close(Channel, Nil, True);
end;


procedure  TDnHttpServer.SendFile(Channel: TDnHttpChannel; FileName: String);
var HttpChannel: TDnHttpChannel;
begin
  HttpChannel := TDnHttpChannel(Channel);

  FFileWriter.RequestFileWrite(Channel, Pointer(LongBool(HttpChannel.KeepAlive)), FileName);
end;

procedure  TDnHttpServer.SendData(Channel: TDnHttpChannel; Buf: Pointer; BufSize: Integer);
begin
  FRequestor.Write(Channel, Nil, PAnsiChar(Buf), BufSize);
end;

procedure  TDnHttpServer.SendResponse(Channel: TDnHttpChannel);
begin
  // Ensure response headers are built
  Channel.Response.Build;

  Channel.SentBytes := 0;

  // Send response headers
  FRequestor.Write(Channel, Nil, Channel.Response.BufferPtr, Channel.Response.BufferSize);
end;

function    TDnHttpServer.GetFileSize(const FileName: String): Integer;
var FS: TFileStream;
begin
  try
    FS := TFileStream.Create(FileName, fmOpenRead + fmShareDenyNone);
    Result := FS.Size;
    FS.Free;
  except
    Result := 0;
  end;
end;

procedure     TDnHttpServer.LogMessage(Level: TDnLogLevel; const Msg: String);
begin
  if Assigned(FOnLog) then
    FOnLog(Self, Level, Msg);
end;

procedure     TDnHttpServer.ChannelTimeout(Context: TDnThreadContext; Channel: TDnTcpChannel);
begin
  FRequestor.Close(Channel, Nil, True);
end;

procedure     TDnHttpServer.UserMessage(Context: TDnThreadContext; Channel: TDnTcpChannel; SignalType: Integer; UserData: Pointer);
begin

end;

function     TDnHttpServer.ProcessHeader(HttpChannel: TDnHttpChannel): Integer;
var ConnCloseHdr: PDnHttpHeader;
    CRLFIndex:    Integer;
begin
  // Clear request object to parse new request
  HttpChannel.Request.Clear;

  Result := 0;

  // Check if HTTP header is here already
  CRLFIndex := FindCRLFCRLF(PAnsiChar(HttpChannel.BufferPtr), HttpChannel.BufferUsed);

  if CRLFIndex = -1 then
    Exit;

  // Save header data
  HttpChannel.Request.CopyToHeaderData(HttpChannel.FHttpBuffer, CRLFIndex+2);

  // Log about found header
  FLogger.LogMsg(llMandatory, 'Request header is found.');


  if not HttpChannel.Request.Parse(PAnsiChar(HttpChannel.BufferPtr), CRLFIndex + 2) then
  begin
    SendBadRequest(HttpChannel);
    Exit;
  end;

  // Check for Connection-Close header
  ConnCloseHdr := HttpChannel.Request.FindHeader('Connection');
  if Assigned(ConnCloseHdr) then
    HttpChannel.KeepAlive := HttpChannel.Request.IsHdrEqual(ConnCloseHdr, 'Keep-Alive')
  else
    HttpChannel.KeepAlive := HttpChannel.Request.Version = http11;

  // Check if content length is ok
  if (HttpChannel.Request.Stage in [hrsFormData, hrsFormUrlEncoded]) and
     (HttpChannel.Request.FindHeader('Content-Length') = Nil) then
  begin
    SendBadRequest(HttpChannel);
    Exit;
  end;

  if HttpChannel.Request.Stage = hrsFormData then
  begin
    HttpChannel.FormData.Clear;
    HttpChannel.FormData.SetBoundary(HttpChannel.Request.Boundary);
  end;

  if Assigned(FOnRequest) then
    FOnRequest(Self, HttpChannel, hrsHeader);


  // Remove processed portion of data
  HttpChannel.DeleteData(CRLFIndex + 4);

  Result := CRLFIndex + 4;
end;

function      TDnHttpServer.ProcessFormURLEncoded(HttpChannel: TDnHttpChannel): Integer;
begin
  Result := 0;
  // Check for CRLF
  if HttpChannel.BufferUsed < HttpChannel.Request.ContentLength then
    Exit;

  HttpChannel.Request.SaveParametersData(PAnsiChar(HttpChannel.BufferPtr), HttpChannel.Request.ContentLength);
  HttpChannel.Request.ParseParameters(HttpChannel.Request.RawParamData);

  // Save result
  Result := HttpChannel.Request.ContentLength;

  // Remove processed data
  HttpChannel.DeleteData(HttpChannel.Request.ContentLength);

  // Switch request parser stage back to header
  HttpChannel.Request.Stage := hrsHeader;

  if Assigned(FOnRequest) then
    FOnRequest(Self, HttpChannel, hrsFormUrlEncoded);
end;

function     TDnHttpServer.ProcessFormData(HttpChannel: TDnHttpChannel): Integer;
var ParseResult: Boolean;
    TotalProcessed: Integer;
begin
  Result := 0;

  // Check if all data is read
  if HttpChannel.BufferUsed < HttpChannel.Request.ContentLength then
    Exit;

  TotalProcessed := 0;
  repeat
    ParseResult := HttpChannel.FormData.Parse(PAnsiChar(HttpChannel.BufferPtr) + TotalProcessed, HttpChannel.Request.ContentLength - TotalProcessed);

    if not ParseResult then
    begin
      SendBadRequest(HttpChannel);
      Exit;
    end;

    // Increase counter of processed bytes
    Inc(TotalProcessed, HttpChannel.FormData.Processed);

    // Check for parameter
    if HttpChannel.FormData.IsDataReady or HttpChannel.FormData.IsFinished then
    begin
      // Got new parameter or EOM!
      if not HttpChannel.FormData.IsFinished then
        HttpChannel.FormData.SaveParamData
      else
        break; // Exit from loop
    end;

  until not ParseResult;

  HttpChannel.DeleteData(TotalProcessed);

  // Switch request parser stage back to header
  HttpChannel.Request.Stage := hrsHeader;

  if Assigned(FOnRequest) then
    FOnRequest(Self, HttpChannel, hrsFormData);

  Result := 0;
end;

procedure  TDnHttpServer.SendBadRequest (HttpChannel: TDnHttpChannel);
begin
  HttpChannel.Response.Clear;
  HttpChannel.Response.AddVersion(HttpChannel.Request.Version);
  HttpChannel.Response.AddResponseCode(400);
  HttpChannel.Response.AddResponseMsg(PByte(PAnsiChar('Bad Request')));
  HttpChannel.Response.FinishHeader;
  HttpChannel.CloseAfterSend := True;

  Self.SendResponse(HttpChannel);
end;

end.
