unit HttpEnginePart;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  DnRtl, DnTcpReactor, DnTcpAbstractRequestor, DnHttpRequestor,
  DnAbstractLogger, DnFileLogger, DnAbstractExecutor, DnSimpleExecutor,
  DnWinSockMgr, DnTcpRequestor, DnInterfaces, DnHttpParser,
  DnTcpFileWriter, DnTcpListener, DnFileCachedLogger, DnTcpChannel;

type
  THttpEngine = class(TDataModule)
    TcpListener:      TDnTcpListener;
    TcpReactor:       TDnTcpReactor;
    HttpRequestor:    TDnHttpRequestor;
    SimpleExecutor:   TDnSimpleExecutor;
    WinSockMgr:       TDnWinSockMgr;
    TcpRequestor:     TDnTcpRequestor;
    FileSender: TDnTcpFileWriter;
    FileLogger: TDnFileCachedLogger;
    procedure TcpListenerIncoming(Context: TDnThreadContext; Channel: TDnTcpChannel);
{$IF NOT DEFINED(VER190) AND NOT DEFINED(VER200)}
    procedure HttpRequestorHttpHeader(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer; Received: String;
      EOMFound: Boolean);
{$ELSE}
    procedure HttpRequestorHttpHeader(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer; Received: RawByteString;
      EOMFound: Boolean);
{$IFEND}
    procedure HttpRequestorTcpClose(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer);
    procedure HttpRequestorTcpError(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer; ErrorCode: Cardinal);
    procedure TcpRequestorWrite(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer; Buf: PAnsiChar; BufSize: Cardinal);
    function ThreadExecutorCreateContext(
      Thread: TDnThread): TDnThreadContext;
    procedure ThreadExecutorDestroyContext(Context: TDnThreadContext);
    procedure TcpRequestorClose(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer);
    procedure HttpRequestorTcpClientClose(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer);
    procedure FileSenderFileWritten(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer; FileName: String; Written: Int64);
{    procedure FileSenderFileWritten(Context: TDnThreadContext;
      Channel: TDnTcpChannel; Key: Pointer; FileName: String;
      Written: Cardinal); }
  private
    { Private declarations }
    FDocRoot: String;
    function ProcessRequest(Parser: TDnHttpParser): String;
  public
    procedure Start(PortNum: Integer; const DocFolder: String);
    procedure Stop;
    procedure WriteToLog(const S: String);
  end;

var
  HttpEngine: THttpEngine;

implementation

{$R *.DFM}

{
  We should use the following sequence of turning on
  our HTTP engine:
  1) WinSockMgr and loggers
  2) Executors and reactors
  3) Timers
  4) Listeners (power is on!)
}
procedure THttpEngine.Start(PortNum: Integer; const DocFolder: String);
begin
  TcpListener.Port := SmallInt(PortNum);
  FDocRoot := DocFolder;
  WinSockMgr.Active :=      True;
  FileSender.Active :=      True;
  SimpleExecutor.Active :=  True;
  TcpReactor.Active :=      True;
  HttpRequestor.Active :=   True;
  FileLogger.Active :=      True;
  TcpRequestor.Active :=    True;
  TcpListener.Active :=     True;
end;

{
  A order of turning off steps:
  1) Listeners
  2) Requestors
  3) Reactors
  4) Timers
  5) Executors
  6) Loggers
  7) WinSock
}

var HtmlContent: AnsiString;

procedure THttpEngine.Stop;
begin
  TcpListener.Active :=     False; //no more new requests
  HttpRequestor.Active :=   False;
  TcpRequestor.Active :=    False;
  FileSender.Active :=      False;
  TcpReactor.Active :=      False;
  SimpleExecutor.Active :=  False;
  FileLogger.Active :=      False;
  WinSockMgr.Active :=      False;
end;

procedure THttpEngine.WriteToLog(const S: String);
begin
  FileLogger.LogMsg(llMandatory, S);
end;

function THttpEngine.ProcessRequest(Parser: TDnHttpParser): String;
var ResponseText: RawByteString;
begin
  //take a document
  Parser.Clear;
  Parser.HttpVersion := 'HTTP/1.0';
  Parser.HttpCode := 200;
  Parser.HttpReason := 'OK';
  ResponseText := '<HTML><HEAD><TITLE>Response page from DNet test server</TITLE></HEAD>' +
                  '<BODY>' + StringOfChar(' ', 1900) + '<BR>' + 'Test passed OK' +
                  '</BODY></HTML>';
  Parser.HttpHeader['Content-Length'] := IntToStr(Length(ResponseText));
  Result := Parser.AssembleResponse + ResponseText;
end;

procedure THttpEngine.TcpListenerIncoming(Context: TDnThreadContext; Channel: TDnTcpChannel);
begin
  //ThreadExecutor.BindChannelToContext(Channel as IDnIOTrackerHolder, Context);
  HttpRequestor.ReadHttpHeader(Channel, Nil, 2000000);
end;

function GetFileSize(FileName: String): Integer;
var
  FS: TFileStream;
begin
  try
    FS := TFileStream.Create(Filename, fmOpenRead);
  except
    Result := -1;
  end;
  if Result <> -1 then Result := FS.Size;
  FS.Free;
end;

procedure THttpEngine.HttpRequestorHttpHeader(Context: TDnThreadContext;
  Channel: TDnTcpChannel; Key: Pointer; Received: RawByteString;
  EOMFound: Boolean);
var Parser: TDnHttpParser;
    Reply, URL, Path, Query: RawByteString;
    FileSize: Integer;
    ContentToSend: RawByteString;
begin
  //read next request
  Self.HttpRequestor.ReadHttpHeader(Channel, nil, 8192);

  Parser := Nil;
  if EOMFound then
  begin
    Parser := TDnHttpParser.Create;
    Parser.ParseRequest(Received);
    if UpperCase(Parser.HttpMethodName) = 'GET' then
    begin
      URL := Parser.HttpMethodURL;
      TDnHttpParser.ParseRelativeUrl(URL, Path, Query);
      if Length(Path) > 0 then
      begin
        Path := FDocRoot + Path;
        Path := TDnHttpParser.AdjustSlash(Path);
        //check file for existing
        FileSize := 1;//GetFileSize(Path);
        if FileSize >= 0 then
        begin
          //FileSender.RequestFileWrite(Channel, Nil, Path, 0, FileSize(Path)-1);
          //send HTTP header
          Parser.Clear;
          Parser.HttpVersion := 'HTTP/1.1';
          Parser.HttpHeader['Connection'] := 'keep-alive';
          Parser.HttpHeader['Content-Type'] := 'text/html';
          Parser.HttpCode := 200;
          Parser.HttpReason := 'OK';
          Parser.HttpHeader['Content-Length'] := IntToStr(Length(HtmlContent));
          ContentToSend := Parser.AssembleResponse + HtmlContent;

          TcpRequestor.WriteString(Channel, Nil, ContentToSend);
          //TcpRequestor.WriteString(Channel, Nil, HtmlContent);
          //FileSender.RequestFileWrite(Channel, Nil, Path);

        end else
        begin
          Parser.Clear;
          Parser.HttpVersion := 'HTTP/1.1';
          Parser.HttpHeader['Connection'] := 'close';
          Parser.HttpHeader['Content-type'] := 'text/html';
          Parser.HttpCode := 404;
          Parser.HttpReason := 'Not found';
          Parser.HttpHeader['Content-Length'] := '0';
          TcpRequestor.WriteString(Channel, Nil, Parser.AssembleResponse);
        end;
      end else
      begin
          Parser.Clear;
          Parser.HttpVersion := 'HTTP/1.1';
          Parser.HttpHeader['Connection'] := 'close';
          Parser.HttpHeader['Content-type'] := 'text\html';
          Parser.HttpCode := 404;
          Parser.HttpReason := 'Not found';
          Parser.HttpHeader['Content-Length'] := '0';
          TcpRequestor.WriteString(Channel, Nil, Parser.AssembleResponse);
      end;

    end;
    FreeAndNil(Parser);
    //TcpRequestor.RequestWriteString(Channel, Key, Reply);
  end else
    TcpRequestor.Close(Channel, Key, True); //Yes, brutal force closing
end;

procedure THttpEngine.HttpRequestorTcpClose(Context: TDnThreadContext;
  Channel: TDnTcpChannel; Key: Pointer);
begin
  TcpRequestor.Close(Channel, Key);
end;

procedure THttpEngine.HttpRequestorTcpError(Context: TDnThreadContext;
  Channel: TDnTcpChannel; Key: Pointer; ErrorCode: Cardinal);
begin
  TcpRequestor.Close(Channel, Key, True);
end;

procedure THttpEngine.TcpRequestorWrite(Context: TDnThreadContext;
  Channel: TDnTcpChannel; Key: Pointer; Buf: PAnsiChar; BufSize: Cardinal);
begin
  //TcpRequestor.Close(Channel, Key);
end;

function THttpEngine.ThreadExecutorCreateContext(
  Thread: TDnThread): TDnThreadContext;
begin
  Result := TDnThreadContext.Create(Thread);
end;

procedure THttpEngine.ThreadExecutorDestroyContext(
  Context: TDnThreadContext);
begin
  FreeAndNil(Context);
end;

procedure THttpEngine.TcpRequestorClose(Context: TDnThreadContext;
  Channel: TDnTcpChannel; Key: Pointer);
begin
  //ThreadExecutor.UnbindChannelFromContext(Channel as IDnIOTrackerHolder, Context);
end;

procedure THttpEngine.HttpRequestorTcpClientClose(
  Context: TDnThreadContext; Channel: TDnTcpChannel; Key: Pointer);
begin
  TcpRequestor.Close(Channel, Key);
end;

{procedure THttpEngine.FileSenderFileWritten(Context: TDnThreadContext;
  Channel: TDnTcpChannel; Key: Pointer; FileName: String;
  Written: Cardinal);
begin
  TcpRequestor.Close(Channel, Nil);
end;}

procedure THttpEngine.FileSenderFileWritten(Context: TDnThreadContext;
  Channel: TDnTcpChannel; Key: Pointer; FileName: String; Written: Int64);
begin
  TcpRequestor.Close(Channel, Nil, True);
end;

initialization
  HtmlContent := '<html><body>012345678901234567890123456789012345678901234567890123456789012345678901';
  HtmlContent := HtmlContent + '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
  HtmlContent := HtmlContent + '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
  HtmlContent := HtmlContent + '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
  HtmlContent := HtmlContent + '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
  HtmlContent := HtmlContent + '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
  HtmlContent := HtmlContent + '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
  HtmlContent := HtmlContent + '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
  HtmlContent := HtmlContent + '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
  HtmlContent := HtmlContent + '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
  HtmlContent := HtmlContent + '  </body></html>';


end.
