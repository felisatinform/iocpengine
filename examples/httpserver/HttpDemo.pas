unit HttpDemo;

interface

uses
  SysUtils, Classes, Windows,
  DnRtl, DnTcpReactor, DnTcpAbstractRequestor, DnHttpRequestor,
  DnAbstractLogger, DnFileLogger, DnAbstractExecutor, DnSimpleExecutor,
  DnWinSockMgr, DnTcpRequestor, DnInterfaces, DnHttpParser,
  DnTcpFileWriter, DnTcpListener, DnFileCachedLogger, DnTcpChannel,
  DnHttpServer;


type
  THttpProcessor = class(TDataModule)
    Server: TDnHttpServer;

    procedure ServerRequest(Sender: TObject; Channel: TDnHttpChannel; Stage: TDnHttpRequestStage);
    procedure ServerTimeToSend(Sender: TObject; Channel: TDnHttpChannel);
    procedure ServerLog(Sender: TObject; Level: TDnLogLevel; const Msg: string);
    procedure DataModuleDestroy(Sender: TObject);
  private
    FDocumentPath: String;
  public

    property DocumentPath: String read FDocumentPath write FDocumentPath;
  end;

var
  HttpProcessor: THttpProcessor;

implementation

{$R *.dfm}
var HtmlContent: AnsiString;

procedure THttpProcessor.DataModuleDestroy(Sender: TObject);
begin
  ;
end;

procedure THttpProcessor.ServerLog(Sender: TObject; Level: TDnLogLevel;
  const Msg: string);
begin
  //OutputDebugString(PWideChar(Msg));
end;

procedure THttpProcessor.ServerRequest(Sender: TObject; Channel: TDnHttpChannel; Stage: TDnHttpRequestStage);
var i:              Integer;
    Param:          PDnHttpParam;
    FormDataParam:  PDnFormDataParam;
    TestName,
    TestValue:      array[0..MAX_PARAM_SIZE] of AnsiChar;
begin
  if (Stage = hrsHeader) and (Channel.Request.Method = 'POST') then
    Exit;

  Channel.Response.Clear;
  Channel.Response.AddVersion(Channel.Request.Version);
  Channel.Response.KeepAlive := Channel.KeepAlive;

  if (Channel.Request.Method = 'GET') or (Channel.Request.Method = 'POST')then
  begin
    // Look on URL components

    if Channel.Request.Path = '/test1.html' then
    begin
      // Dump input parameters
      if Channel.Request.Method = 'GET' then
      begin
        for i := 0 to Channel.Request.ParamCount-1 do
        begin
          Param := Channel.Request.GetParamAt(i);
          Channel.Request.GetParamName(Param, @TestName, MAX_PARAM_SIZE);
          Channel.Request.GetParamValue(Param, @TestValue, MAX_PARAM_SIZE);
        end;
      end
      else
      begin
        if Stage = hrsFormData then
        begin
          for i := 0 to Channel.FormData.ParamCount-1 do
          begin
            FormDataParam := Channel.FormData.GetParamAt(i);
          end;
        end
        else
        if Stage = hrsFormUrlEncoded then
        begin
          Param := Channel.Request.GetParamAt(i);
          Channel.Request.GetParamName(Param, @TestName, MAX_PARAM_SIZE);
          Channel.Request.GetParamValue(Param, @TestValue, MAX_PARAM_SIZE);
        end;
      end;

      // Source code to test pure I/O capability with Content-Length specified value (no chunked encoding)
      Channel.Response.AddResponseCode(200);
      Channel.Response.AddResponseMsg('OK');
      Channel.Response.ChunkedEncoding := False;
      Channel.Response.ContentLength := StrLen(PAnsiChar(HtmlContent));
      Channel.Response.FinishHeader;
      Channel.Response.AddContent(PAnsiChar(HtmlContent), Channel.Response.ContentLength);
      Server.SendResponse(Channel);
    end
    else
    if Channel.Request.Path = '/test2.html' then
    begin
      Channel.Response.AddResponseCode(200);
      Channel.Response.AddResponseMsg('OK');
      Channel.Response.ChunkedEncoding := True;
      Channel.Response.FinishHeader;
      // Add first chunk
      Channel.Response.AddContent(PAnsiChar(HtmlContent), Length(HtmlContent));

      // Add finish chunk
      Channel.Response.AddContent(Nil, 0);

      Server.SendResponse(Channel);
    end
    else
    if Channel.Request.Path = '/' then
    begin
      if FileExists(DocumentPath + '/index.html') then
      begin
        Channel.Response.AddResponseCode(200);
        Channel.Response.AddResponseMsg('OK');
        Channel.Response.ChunkedEncoding := False;
        Channel.Response.ContentLength := Server.GetFileSize(DocumentPath + '/index.html');
        Channel.Response.FinishHeader;

        Server.SendResponse(Channel);
        Server.SendFile(Channel, DocumentPath + '/index.html');
      end
      else
      begin
        Channel.Response.AddResponseCode(404);
        Channel.Response.AddResponseMsg('Not found');
        Channel.Response.ChunkedEncoding := False;
        Channel.Response.ContentLength := 0;
        Channel.Response.FinishHeader;

        Server.SendResponse(Channel);
      end;
    end
    else
    if FileExists(DocumentPath + Channel.Request.Path) then
    begin
      Channel.Response.AddResponseCode(200);
      Channel.Response.AddResponseMsg('OK');
      Channel.Response.ChunkedEncoding := False;
      Channel.Response.ContentLength := Server.GetFileSize(DocumentPath + Channel.Request.Path);
      Channel.Response.FinishHeader;

      Server.SendResponse(Channel);
      Server.SendFile(Channel, DocumentPath + Channel.Request.Path);
    end
    else
    begin
      Channel.Response.AddResponseCode(404);
      Channel.Response.AddResponseMsg('Not found');
      Channel.Response.ChunkedEncoding := False;
      Channel.Response.ContentLength := 0;
      //Channel.Response.KeepAlive := True;
      Channel.Response.FinishHeader;

      //Channel.KeepAlive := False;
      Server.SendResponse(Channel);
    end;
  end;
end;

procedure THttpProcessor.ServerTimeToSend(Sender: TObject;
  Channel: TDnHttpChannel);
begin
  // Time to generate new data
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
