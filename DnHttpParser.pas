// The contents of this file are used with permission, subject t
// the Mozilla Public License Version 1.1 (the "License"); you may
// not use this file except in compliance with the License. You may
// obtain a copy of the License at
// http://www.mozilla.org/MPL/MPL-1.1.html
//
// Software distributed under the License is distributed on an
// "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
// implied. See the License for the specific language governing
// rights and limitations under the License.
unit DnHttpParser;

interface

uses SysUtils, Windows, shlwapi, Classes, contnrs, Math,
  DnRtl, DnConst, DnStringList
{$IF DEFINED(VER200) OR DEFINED(VER210)}
  , AnsiStrings
{$IFEND}
  ;

type
  TDnHttpString = record
    FStart: Cardinal;
    FLength: Cardinal;
  end;

  TDnHttpHeader = record
    FName: TDnHttpString;
    FValue: TDnHttpString;
  end;

  PDnHttpHeader = ^TDnHttpHeader;

  TDnHttpParam = record
    FName: TDnHttpString;
    FValue: TDnHttpString;
  end;

  PDnHttpParam = ^TDnHttpParam;

const
  // Maximal number of lines in HTTP request
  MAX_HTTP_HEADER_COUNT = 1024;

  // Maximal size of single HTTP header
  MAX_HTTP_HEADER_SIZE = 1024;

  // Maximal size of HTTP request line
  MAX_HTTP_REQUEST_SIZE = 1024;

  // Maximal length of HTTP method name
  MAX_METHOD_SIZE = 32;

  // Maximal length of URL in request
  MAX_URL_SIZE = 2048;

  // Maximal pair parameter size (name=value)
  MAX_PARAM_SIZE = 1024;

  // Maximal length of parameters
  MAX_PARAM_TOTALSIZE = 16384;

  // Maximal number of lines in HTTP request
  MAX_HTTP_PARAM_COUNT = 1024;

  // Initial writer buffer size
  INITIAL_WRITER_BUFFER_SIZE = 16384;

  // Initial form data cache size
  FORMDATA_CACHE_SIZE = $FFFF;

  // Maximal form data size - about 10 MB
  MAX_FORMDATA_SIZE = 10000000;

  // Maximal size of boundary string for form data
  MAX_BOUNDARY_SIZE = 128;

  // Maximal size of single headers part in form data
  MAX_FORMDATA_HEADERS_SIZE = 512;

  // Initial formdata buffer size
  INITIAL_FORMDATA_SIZE = 128000;

  // Maximal formdata parameter's name size
  MAX_PARAMNAME_SIZE = 128;

  // Maximal formdata parameter's filename size
  MAX_FILENAME_SIZE = 256;

  // Maximal number of parameters in formdata
  MAX_FORMDATAPARAM_COUNT = 64;

type
  // Class intended to parse HTTP requests/response
  // It performs basic parsing of HTTP traffic - it separates HTTP headers from HTTP body data.
  // Class parses HTTP headers in lazy way - it scans HTTP headers, finds header names/values range.

  TDnHttpReader = class
  protected
    // Pointer to last parsed content
    FContent: PAnsiChar;

    // Size of last parsed content
    FContentSize: Integer;

    // Array of header boundaries
    FHeaderArray: array [0 .. MAX_HTTP_HEADER_COUNT - 1] of TDnHttpHeader;

    // Number of used items in FHeaderArray
    FHeaderCount: Integer;

    // Header copy (without terminating CRLFCRLF)
    FHeaderData: array [0 .. MAX_HTTP_REQUEST_SIZE] of AnsiChar;

    // Header's size (in bytes)
    FHeaderSize: Integer;

    // Function copies DestSize of URL'encoded ANSI string to SrcBuffer by decoding them
    function CopyURLEncoded(DestBuffer: PAnsiChar; DestSize: Integer;
      SrcBuffer: PAnsiChar; SrcSize: Integer): Integer;

    // Decodes 2 digit hex number to AnsiChar
    function DecodeHex(Code1, Code2: AnsiChar): AnsiChar;

    function GetRawHeaderData: PAnsiChar;
    function GetRawHeaderSize: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear; virtual;

    // Parses incoming content
    function Parse(SkipFirstLine: Boolean = True): Boolean;

    // Looks for specified header name. Returns pointer to found header record.
    // Can return Nil if header name does not exist.
    function FindHeader(HeaderName: PAnsiChar): PDnHttpHeader;

    // Compares header's value from HTTP message and specified value.
    function IsHdrEqual(Hdr: PDnHttpHeader; Value: PAnsiChar): Boolean;

    // Copies header's value to specified buffer
    procedure CopyHeaderValue(Hdr: PDnHttpHeader; OutputBuffer: PAnsiChar; OutputSize: Integer);

    // Helper function for TDnHttpServer
    procedure CopyToHeaderData(BufferPtr: PAnsiChar; BufferSize: Integer);

    property RawHeaderData: PAnsiChar read GetRawHeaderData;
    property RawHeaderSize: Integer read GetRawHeaderSize;
  end;

  // Supported HTTP version list.
  TDnHttpVersion = (http09, http10, http11);

  // Request stages
  TDnHttpRequestStage = (hrsHeader, hrsFormUrlEncoded, hrsFormData);

  // Class intended to parse HTTP requests. It inherits from TDnHttpReader and
  // adds functionality to work with HTTP request's fields - path, http version and method name.
  TDnHttpRequest = class(TDnHttpReader)
  protected
    // Method name
    FMethod: array [0 .. MAX_METHOD_SIZE - 1] of AnsiChar;

    // Path (decoded from urlencoded form to normal ansistring)
    FPath: array [0 .. MAX_URL_SIZE - 1] of AnsiChar;

    // HTTP request's version
    FVersion: TDnHttpVersion;

    // Received parameters. It is used for POST requests.
    FParamData: array [0 .. MAX_PARAM_TOTALSIZE] of AnsiChar;
    FParamSize: Integer;

    // Specifies param array. By default it is not generated - call ParseParams to fill it.
    FParamArray: array [0 .. MAX_HTTP_PARAM_COUNT - 1] of TDnHttpParam;

    // Number of parsed parameters
    FParamCount: Integer;

    // Current HTTP request reading stage
    FStage: TDnHttpRequestStage;

    // POST request body length
    FContentLength: Integer;

    // Optional boundary signature
    FBoundary: Array [0 .. MAX_PARAM_SIZE] of AnsiChar;

    // Optional form data pointer
    FFormData: PAnsiChar;
    FFormDataUsed: Integer;
    FFormDataCapacity: Integer;

    function GetMethod: PAnsiChar;
    function GetPath: PAnsiChar;

    procedure ProcessPOSTRequest;

    function GetBoundary: PAnsiChar;
    function GetRawParamData: PAnsiChar;
    function GetRawParamSize: Integer;

  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear; override;
    function  Parse(Content: PAnsiChar; ContentSize: Integer): Boolean;

    // Looks for specified param name. Returns pointer to found param record.
    // Can return Nil if param name does not exist.
    function  FindParam(ParamName: PAnsiChar): PDnHttpParam;

    // Compares param value from HTTP message and specified value.
    function  IsParamEqual(Param: PDnHttpParam; Value: PAnsiChar): Boolean;

    // Returns parameters count
    function  ParamCount: Integer;

    // Get parameter record by index
    function  GetParamAt(Index: Integer): PDnHttpParam;

    // Get parameter name
    procedure GetParamName(Param: PDnHttpParam; BufferPtr: PAnsiChar; BufferSize: Integer = -1);

    // Get parameter value
    procedure GetParamValue(Param: PDnHttpParam; BufferPtr: PAnsiChar; BufferSize: Integer = -1);

    // Helper function to save raw parameters data. Returns false if not enough memory
    function  SaveParametersData(BufferPtr: PAnsiChar; BufferSize: Integer): Boolean;

    // Helper function to parse raw urlencoded parameters data
    procedure ParseParameters(Buffer: PAnsiChar);


    // HTTP method name
    property Method:          PAnsiChar read GetMethod;

    // Path - HTTP query up to '?' symbol
    property Path:            PAnsiChar read GetPath;

    // Used HTTP version
    property Version:         TDnHttpVersion read FVersion;

    // State of parser
    property Stage:           TDnHttpRequestStage read FStage write FStage;

    // Found content length
    property ContentLength:   Integer read FContentLength;

    // Found boundary signature
    property Boundary:        PAnsiChar read GetBoundary;

    // Pointer to raw parameter data
    property RawParamData:    PAnsiChar read GetRawParamData;

    // Size of raw parameter data
    property RawParamSize:    Integer read GetRawParamSize;
  end;

  // TDnHttpWriter is class designed to ease content sending from HTTP server.
  // It has strict requiements to its using.
  // The first step is to AddVersion of response. It can be http09/http10/http11.
  // The second step is to add response code - call AddResponseCode.
  // After response msg is required - call AddResponseMsg.
  // TODO: finish the description

  TDnHttpWriter = class
  protected
    FContent: PAnsiChar;
    FContentCapacity, FContentSize: Integer;
    FHeaderSize: Integer;
    FIsLastChunk: Boolean;

    // HTTP behaviour and content length
    FHTTPChunkedEncoding: Boolean;
    FHTTPContentLength: Integer;
    FHTTPKeepAlive: Boolean;

    procedure QueueBuffer(const Buffer: PByte; BufferSize: Integer);
      overload;
    procedure QueueBuffer(const Buffer: PByte); overload;

    function GetContent: PByte;
    function GetContentSize: Integer;

    function GetHeaderSize: Integer;
    function GetBodySize: Integer;

  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure AddVersion(Version: TDnHttpVersion);
    procedure AddResponseCode(Code: Integer);
    procedure AddResponseMsg(Msg: PAnsiChar);
    procedure AddHeader(const HeaderName: PAnsiChar;
      const HeaderValue: PAnsiChar); overload;
    procedure AddHeader(const HeaderName: PAnsiChar; HeaderValue: Integer);
      overload;
    procedure FinishHeader;

    procedure AddContent(const Buffer: PAnsiChar; BufferSize: Integer);
    procedure Build;

    property ChunkedEncoding: Boolean read FHTTPChunkedEncoding write
      FHTTPChunkedEncoding;
    property ContentLength: Integer read FHTTPContentLength write
      FHTTPContentLength;
    property KeepAlive: Boolean read FHTTPKeepAlive write FHTTPKeepAlive;

    property BufferPtr: PByte read GetContent;
    property BufferSize: Integer read GetContentSize;

    property HeaderSize: Integer read GetHeaderSize;
    property BodySize: Integer read GetBodySize;

    property IsLastChunk: Boolean read FIsLastChunk;
  end;

  TDnFormDataParserStage = (dpsBoundary, dpsHeaders, dpsData);

  TDnFormDataParam = record
    FName:        array [0..MAX_PARAMNAME_SIZE] of AnsiChar;
    FFilename:    array [0..MAX_FILENAME_SIZE] of AnsiChar;
    FDataPtr:     PAnsiChar;
    FDataSize:    Integer;
  end;
  PDnFormDataParam = ^TDnFormDataParam;

  TDnFormDataParser = class(TObject)
  protected
    // Marks if new data / EOM flag is set
    FIsDataReady:   Boolean;
    FIsFinished:    Boolean;

    // Parser state - boundary, headers, data
    FStage:         TDnFormDataParserStage;

    // Amount of processed data
    FProcessed:     Integer;

    // Cached boundary string
    FBoundary:      array[0..MAX_BOUNDARY_SIZE] of AnsiChar;
    FBoundarySize:  Integer;

    // Boundary signature - it is boundary string prefixed by \r\n--
    FBoundarySign:  PAnsiChar;

    // Cached headers
    FHeaders:       array[0..MAX_FORMDATA_HEADERS_SIZE] of AnsiChar;
    FHeadersSize:   Integer;

    // Cached data
    FData:          PAnsiChar;

    // Cached data size
    FDataSize:      Integer;

    // Cached data buffer capacity
    FDataCapacity:  Integer;

    // Counter of sequentinal CRLF. Used to detect header end.
    FCRLFCounter:   Integer;

    // HTTP headers parser
    FHttpReader:    TDnHttpReader;

    // Array of extracted parameters
    FParamArray:    array[0..MAX_FORMDATAPARAM_COUNT] of TDnFormDataParam;

    // Number of used slots in FParamArray
    FParamCount:    Integer;

    function    InternalGetName(NamePrefix: PAnsiChar; BufferOut: PAnsiChar; BufferSize: Integer): Boolean;

  public
    constructor Create;
    destructor  Destroy; override;
    procedure   Clear;
    procedure   SetBoundary(Boundary: PAnsiChar);

    // Parses data. Returns True if processing was success, and False if failed.
    // Method affects properties Processed and IsDataReady.
    function    Parse(Buffer: PAnsiChar; BufferSize: Integer): Boolean;

    // Copies name of current parameter to specified buffer. BufferSize should be size of buffer (including terminating zero byte).
    function    GetName(BufferOut: PAnsiChar; BufferSize: Integer): Boolean;

    // Copies filename of current parameter to specified buffer. BufferSize should be size of buffer (including terminating zero byte).
    function    GetFileName(BufferOut: PAnsiChar; BufferSize: Integer): Boolean;

    // Returns pointer to current parameter data. Returns Nil if end of message is detected.
    function    GetDataPtr: PAnsiChar;

    // Returns size of current parameter data.
    function    GetDataSize: Integer;

    // Collects current parameter data to FParamArray. Returns number of collected parameters
    function    SaveParamData: Integer;

    function    GetParamCount: Integer;
    function    GetParamAt(Index: Integer): PDnFormDataParam;
    function    FindParamByName(ParamName: PAnsiChar): PDnFormDataParam;

    // Returns number of processed bytes during last Parse() call
    property    Processed:    Integer read FProcessed;

    // Returns True if new parameter is available or end of message is detected
    property    IsDataReady:  Boolean read FIsDataReady;
    property    IsFinished:   Boolean read FIsFinished;

    property    ParamCount:   Integer read GetParamCount;
  end;
  (*
    TDnHttpParser = class(TObject)
    protected
    FHttpData:                  RawByteString;
    FHttpVersion:               RawByteString;
    FMethodName:                RawByteString;
    FMethodURL:                 RawByteString;
    FHttpResponseCode:          Integer;
    FHttpResponseReason:        RawByteString;
    FNames: TDnStringList;
    FValues: TDnStringList;

    class function  ExtractLine(var Data: RawByteString): RawByteString;
    class procedure ExtractPair(var Data: RawByteString; var LeftPart, RightPart: RawByteString);
    class procedure StripSpaces(var Data: RawByteString);
    class function  Skip1Space(const S: RawByteString; StartWith: Integer): Integer;
    class function  Skip1Colon(const S: RawByteString; StartWith: Integer): Integer;
    class function  GetWord(const S: RawByteString; StartWith: Integer; var Lexem: RawByteString): Integer;
    class function  GetIntLexem(const S: RawByteString; StartWith: Integer; var Lexem: RawByteString): Integer;
    procedure ParseHttpHeaders(S: RawByteString);
    function  AssembleHttpHeaders: RawByteString;

    function  GetHttpHeader(const Name: RawByteString): RawByteString;
    procedure SetHttpHeader(const Name, Value: RawByteString);

    public
    constructor Create;
    destructor  Destroy; override;
    procedure   Clear;
    procedure   ParseResponse(const HttpData: RawByteString);
    procedure   ParseRequest(const HttpData: RawByteString);
    function    AssembleResponse: RawByteString;
    function    AssembleRequest: RawByteString;

    class function  IsAbsoluteUrl(const Url: RawByteString): Boolean;

    class procedure ParseAbsoluteUrl(const Url: RawByteString;
    var Protocol, User, Password, Host, Port, Path,
    Query: RawByteString; var UserExists, PasswordExists: Boolean); overload;

    class procedure ParseRelativeUrl(const Url: RawByteString; var Path, Query: RawByteString);
    class procedure ParseHttpTime(const S: RawByteString; StartWith: Integer;
    var FinishWith: Integer;
    var Year, Month, Day, DayOfWeek, Hour, Minute, Second: Integer;
    var TimeZone: RawByteString);
    class function  FormatHttpTime(Year, Month, Day, DayOfWeek, Hour,
    Minute, Second: Integer;
    TimeZone: RawByteString): RawByteString;
    class procedure ParseResponseContentType(const S: RawByteString; var ContentType: RawByteString;
    var CharSet: RawByteString);
    class function  ParseAcceptList(const S: RawByteString): TStringList;
    class function  AdjustSlash(const S: RawByteString): RawByteString;
    property  HttpMethodName: RawByteString read FMethodName write FMethodName;
    property  HttpMethodURL: RawByteString read FMethodURL write FMethodURL;
    property  HttpVersion: RawByteString read FHttpVersion write FHttpVersion;
    property  HttpHeader[const Name: RawByteString]: RawByteString read GetHttpHeader write SetHttpHeader;
    property  HttpCode: Integer read FHttpResponseCode write FHttpResponseCode;
    property  HttpReason: RawByteString read FHttpResponseReason write FHttpResponseReason;
    end;
    *)

implementation

const
  CRLF: RawByteString = #13#10;
  ShortWeekDays: array [0 .. 6] of RawByteString = ('Sun', 'Mon', 'Tue', 'Wed',
    'Thu', 'Fri', 'Sat');
  LongWeekDays: array [0 .. 6] of RawByteString = ('Sunday', 'Monday',
    'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday');

  MonthNames: array [1 .. 12] of RawByteString = ('Jan', 'Feb', 'Mar', 'Apr',
    'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

  // -------------- TDnHttpReader --------------------------
constructor TDnHttpReader.Create;
begin
  inherited Create();
  FContentSize := 0;
  FContent := Nil;
  FHeaderSize := 0;
end;

destructor TDnHttpReader.Destroy;
begin
  inherited Destroy;
end;

procedure TDnHttpReader.Clear;
begin
  FContent := Nil;
  FContentSize := 0;

  FHeaderCount := 0;
  FHeaderSize := 0;
end;

function TDnHttpReader.Parse(SkipFirstLine: Boolean = True): Boolean;
var
  HeaderCounter: Integer;
  CRLF, EOL, SCDelimiter, TokenIter, StartLine: PAnsiChar;
  HeaderTokenStart, HeaderTokenLength: Integer;
begin
  Result := True;

  // Copy pointer and size to parsing buffer
  FContent := @FHeaderData[0];
  FContentSize := FHeaderSize;

  CRLF := #13#10;

  // Copy first line as is - it is request or response line
  if SkipFirstLine then
  begin
    EOL := AnsiStrPos(FContent, CRLF);
    if EOL = Nil then
    begin
      Result := False;
      Exit;
    end;

    FHeaderArray[0].FName.FStart := 0;
    FHeaderArray[0].FName.FLength := EOL - FContent;
    FHeaderArray[0].FValue.FStart := 0;
    FHeaderArray[0].FValue.FLength := 0;
    HeaderCounter := 1;
  end
  else
  begin
    HeaderCounter := 0;
    EOL := Nil;
  end;

  repeat
    if EOL <> Nil then
      StartLine := EOL + 2
    else
      StartLine := FContent;

    // Find end of the line
    EOL := AnsiStrPos(StartLine, CRLF);
    if EOL = Nil then
    begin
      Result := False;
      Exit;
    end;

    if StartLine = EOL then
      Break;

    // Replace #13 by #0 to make string zero terminated
    EOL^ := #0;

    // Find semicolon ':'
    SCDelimiter := AnsiStrPos(StartLine, ':');
    if SCDelimiter = Nil then
    begin
      Result := False;
      Exit;
    end;

    // Find indexes for header name and values
    HeaderTokenStart := StartLine - FContent;
    HeaderTokenLength := 0;

    // Iterate header name skipping spaces
    TokenIter := StartLine;
    while (TokenIter <> SCDelimiter) and (TokenIter^ <> #32) do
    begin
      Inc(TokenIter);
      Inc(HeaderTokenLength);
    end;

    FHeaderArray[HeaderCounter].FName.FStart := HeaderTokenStart;
    FHeaderArray[HeaderCounter].FName.FLength := HeaderTokenLength;

    // skip spaces
    TokenIter := SCDelimiter + 1;
    while (TokenIter^ = #32) and (TokenIter <> EOL) do
      Inc(TokenIter);

    // Iterate header name skipping spaces
    HeaderTokenStart := TokenIter - FContent;
    HeaderTokenLength := EOL - TokenIter;

    FHeaderArray[HeaderCounter].FValue.FStart := HeaderTokenStart;
    FHeaderArray[HeaderCounter].FValue.FLength := HeaderTokenLength;

    // Bring #13 back
    EOL^ := #13;

    Inc(HeaderCounter);

  until FContentSize = EOL - FContent + 2;

  FHeaderCount := HeaderCounter;
end;

function TDnHttpReader.CopyURLEncoded(DestBuffer: PAnsiChar; DestSize: Integer;
  SrcBuffer: PAnsiChar; SrcSize: Integer): Integer;
var
  SrcIter, DestIter: Integer;
  Code1, Code2: AnsiChar;
begin
  SrcIter := 0;
  DestIter := 0;
  while (SrcIter < SrcSize) and (DestIter < DestSize - 1) and
    (SrcBuffer[SrcIter] <> #0) do
  begin
    if SrcBuffer[SrcIter] = #32 then
    begin
      DestBuffer[DestSize] := ' ';
      Inc(DestSize);
    end
    else if SrcBuffer[SrcIter] = '%' then
    begin
      // Try to get next two characters to get hex symbol code
      if SrcIter < SrcSize - 2 then
      begin
        Code1 := SrcBuffer[SrcIter + 1];
        Code2 := SrcBuffer[SrcIter + 2];
        DestBuffer[DestIter] := DecodeHex(Code1, Code2);
        Inc(DestIter);
        Inc(SrcIter, 3);
      end;
    end
    else
    begin
      DestBuffer[DestIter] := SrcBuffer[SrcIter];
      Inc(DestIter);
      Inc(SrcIter);
    end;
  end;

  DestBuffer[DestIter] := #0;
  Result := DestIter + 1;
end;

function TDnHttpReader.DecodeHex(Code1, Code2: AnsiChar): AnsiChar;
var
  Value1, Value2: Integer;
begin
  Value1 := 0;
  Value2 := 0;
  if (Code1 >= '0') and (Code1 <= '9') then
    Value1 := Byte(Code1) - Byte('0')
  else if (Code1 >= 'a') and (Code1 <= 'f') then
    Value1 := Byte(Code1) - Byte('a') + 10
  else if (Code1 >= 'A') and (Code1 <= 'F') then
    Value1 := Byte(Code1) - Byte('A') + 10;

  if (Code2 >= '0') and (Code2 <= '9') then
    Value2 := Byte(Code2) - Byte('0')
  else if (Code2 >= 'a') and (Code2 <= 'f') then
    Value2 := Byte(Code2) - Byte('a') + 10
  else if (Code2 >= 'A') and (Code2 <= 'F') then
    Value2 := Byte(Code2) - Byte('A') + 10;

  Result := AnsiChar(Byte(Value1 * 16 + Value2));
end;

function TDnHttpReader.FindHeader(HeaderName: PAnsiChar): PDnHttpHeader;
var
  HeaderCounter: Integer;
  HeaderNameStart: PAnsiChar;
begin
  Result := nil;

  for HeaderCounter := 0 to FHeaderSize - 1 do
  begin
    if FHeaderArray[HeaderCounter].FName.FLength = 0 then
      continue;

    HeaderNameStart := PAnsiChar(@FHeaderData[0]) + FHeaderArray[HeaderCounter]
      .FName.FStart;

    if AnsiStrLIComp(HeaderName, HeaderNameStart,
      FHeaderArray[HeaderCounter].FName.FLength) = 0 then
    begin
      Result := @FHeaderArray[HeaderCounter];
      Exit;
    end;
  end;
end;

function TDnHttpReader.IsHdrEqual(Hdr: PDnHttpHeader;
  Value: PAnsiChar): Boolean;
begin
  if not Assigned(Hdr) then
    Result := False
  else
    Result := AnsiStrLIComp(Value, PAnsiChar(@FHeaderData[0]) + Hdr^.FValue.FStart, Hdr^.FValue.FLength) = 0;
end;

procedure TDnHttpReader.CopyHeaderValue(Hdr: PDnHttpHeader; OutputBuffer: PAnsiChar; OutputSize: Integer);
var ToCopy: Integer;
begin
  if not Assigned(Hdr) then
    Exit;

  ToCopy := Min(Hdr.FValue.FLength, OutputSize-1);
  Move(FHeaderData[Hdr.FValue.FStart], OutputBuffer^, ToCopy);
  OutputBuffer[ToCopy] := #0;
end;


function TDnHttpReader.GetRawHeaderData: PAnsiChar;
begin
  Result := @FHeaderData;
end;

function TDnHttpReader.GetRawHeaderSize: Integer;
begin
  Result := FHeaderSize;
end;

procedure TDnHttpReader.CopyToHeaderData(BufferPtr: PAnsiChar;
  BufferSize: Integer);
var
  ToCopy: Integer;
begin
  ToCopy := Min(MAX_HTTP_REQUEST_SIZE, BufferSize);
  Move(BufferPtr^, FHeaderData, ToCopy);
  FHeaderSize := ToCopy;
  FHeaderData[ToCopy] := #0;
end;

// ------------------ TDnHttpRequest ----------------
constructor TDnHttpRequest.Create;
begin
  inherited Create;
end;

destructor TDnHttpRequest.Destroy;
begin
  if Assigned(FFormData) then
    FreeMem(FFormData);

  inherited Destroy;
end;

function TDnHttpRequest.GetMethod: PAnsiChar;
begin
  Result := @FMethod[0];
end;

function TDnHttpRequest.GetPath: PAnsiChar;
begin
  Result := @FPath[0];
end;

procedure TDnHttpRequest.Clear;
begin
  inherited Clear;

  FMethod[0] := #0;
  FPath[0] := #0;
  FStage := hrsHeader;

  // No saved header
  FHeaderSize := 0;

  // No parsed parameters
  FParamCount := 0;

  // No saved parameter data
  FParamSize := 0;

  // No cached form data
  if Assigned(FFormData) then
  begin
    FreeMem(FFormData);
    FFormData := Nil;
    FFormDataUsed := 0;
    FFormDataCapacity := 0;
  end;
end;

function TDnHttpRequest.Parse(Content: PAnsiChar;
  ContentSize: Integer): Boolean;
var
  RequestLine: array [0 .. MAX_HTTP_REQUEST_SIZE] of AnsiChar;
  FirstSpace, SecondSpace: PAnsiChar;
  RequestSize: Integer;

  // Pointer to '?' symbol in query
  QPtr: PAnsiChar;
begin
  Result := True;

  if not inherited Parse() then
  begin
    Result := False;
    Exit;
  end;

  // check first header name - it must be request
  // split this name to 3 components - version command URL
  if FHeaderSize = 0 then
  begin
    Result := False;
    Exit;
  end;

  // Copy request line for further analyzing
  RequestSize := Math.Min(MAX_HTTP_REQUEST_SIZE, FHeaderArray[0].FName.FLength);
  Move(FContent[FHeaderArray[0].FName.FStart], RequestLine, RequestSize);
  RequestLine[RequestSize] := #0;

  // Parse request line
  FirstSpace := AnsiStrPos(@RequestLine, AnsiChar(' '));
  if FirstSpace = Nil then
  begin
    Result := False;
    Exit;
  end;

  SecondSpace := AnsiStrPos(FirstSpace + 1, ' ');
  if SecondSpace = Nil then
  begin
    Result := False;
    Exit;
  end;

  // Copy method name
  Move(RequestLine, Self.FMethod, FirstSpace - @RequestLine);
  FMethod[FirstSpace - @RequestLine] := #0;

  // Check for '?' symbol in query. Do SecondSpace #0 to let string functions work
  SecondSpace^ := #0;
  QPtr := AnsiStrPos(FirstSpace + 1, '?');
  if QPtr <> Nil then
    CopyURLEncoded(FPath, Sizeof(FPath), FirstSpace + 1, QPtr - FirstSpace - 1)
  else
    CopyURLEncoded(FPath, Sizeof(FPath), FirstSpace + 1,
      SecondSpace - FirstSpace - 1);

  // Parse parameters
  if QPtr <> Nil then
  begin
    SaveParametersData(QPtr + 1, SecondSpace - QPtr - 1);
    ParseParameters(FParamData);
  end;

  // Bring second space symbol back
  SecondSpace^ := #32;

  // Check HTTP version
  if AnsiStrIComp(SecondSpace + 1, 'HTTP/0.9') = 0 then
    FVersion := http09
  else if AnsiStrIComp(SecondSpace + 1, 'HTTP/1.0') = 0 then
    FVersion := http10
  else if AnsiStrIComp(SecondSpace + 1, 'HTTP/1.1') = 0 then
    FVersion := http11
  else
    Result := False;

  // Check if we deal with POST method and Content-Length is not a zero
  if StrComp(FMethod, 'POST') = 0 then
    ProcessPOSTRequest();
end;

procedure TDnHttpRequest.ProcessPOSTRequest;
var
  ContentType, ContentLength: Array [0 .. MAX_PARAM_SIZE] of AnsiChar;
  ContentTypeHdr, ContentLengthHdr: PDnHttpHeader;
  Boundary: PAnsiChar;
begin
  // Get Content-Type header value
  ContentTypeHdr := FindHeader('Content-Type');
  if not Assigned(ContentTypeHdr) then
    Exit;

  // Check if content type is form-urlencoded
  if Self.IsHdrEqual(ContentTypeHdr, 'application/x-www-form-urlencoded') then
  begin
    // Check Content-Length header
    ContentLengthHdr := FindHeader('Content-Length');
    if not Assigned(ContentLengthHdr) then
      Exit;

    // Copy Content-Length value
    Self.CopyHeaderValue(ContentLengthHdr, @ContentLength, Sizeof(ContentLength));

    // Get content length value
    FContentLength := shlwapi.StrToIntA(@ContentLength);

    FStage := (* TDnHttpRequestStage. *) hrsFormUrlEncoded;
  end
  else
  begin
    // Get content type copy
    Self.CopyHeaderValue(ContentTypeHdr, @ContentType, SizeOf(ContentType));

    // Check if it starts with multipart/form-data
    if AnsiStrPos(ContentType, 'multipart/form-data') = ContentType then
    begin
      // Switch request parser stage
      FStage := (* TDnHttpRequestStage. *) hrsFormData;

      // Allocate memory for form data
      GetMem(FFormData, FORMDATA_CACHE_SIZE);

      // Extract boundary signature
      Boundary := AnsiStrPos(PAnsiChar(@ContentType[0]), '=');
      if Boundary = Nil then
        Exit;

      // Save boundary value with prefix
      SysUtils.StrCopy(FBoundary, #13#10'--');
      SysUtils.StrCat(FBoundary, Boundary + 1);

      // Save content length value
      ContentLengthHdr := FindHeader('Content-Length');
      if not Assigned(ContentLengthHdr) then
        Exit;

      // Copy Content-Length value
      Self.CopyHeaderValue(ContentLengthHdr, @ContentLength, SizeOf(ContentLength));

      // Get content length value
      FContentLength := shlwapi.StrToIntA(@ContentLength);
    end;
  end;
end;

function TDnHttpRequest.GetBoundary: PAnsiChar;
begin
  Result := FBoundary;
end;

function TDnHttpRequest.GetRawParamData: PAnsiChar;
begin
  Result := @FParamData[0];
end;

function TDnHttpRequest.GetRawParamSize: Integer;
begin
  Result := FParamSize;
end;

// Looks for specified param name. Returns pointer to found param record.
// Can return Nil if param name does not exist.
function TDnHttpRequest.FindParam(ParamName: PAnsiChar): PDnHttpParam;
var
  i: Integer;
begin
  Result := Nil;
  for i := 0 to FParamCount - 1 do
  begin
    if AnsiStrLIComp(ParamName,
      PAnsiChar(@FParamData) + FParamArray[i].FName.FStart,
      FParamArray[i].FName.FLength) = 0 then
    begin
      Result := @FParamArray[i];
      Exit;
    end;
  end;
end;

// Compares param value from HTTP message and specified value.
function TDnHttpRequest.IsParamEqual(Param: PDnHttpParam;
  Value: PAnsiChar): Boolean;
var
  ValueTemp: array [0 .. MAX_PARAM_SIZE] of AnsiChar;
  Len: Integer;
begin
  Result := False;
  if not Assigned(Param) or not Assigned(Value) then
    Exit;

  // Copy parameter value to temporary storage
  Len := CopyURLEncoded(@ValueTemp, Sizeof(ValueTemp), Value, StrLen(Value));

  // Compare
  if Len <> StrLen(Value) then
    Result := False
  else
  begin
    Result := False;
  end;

end;

// Parses path to parameters
type
  TDnParseParameterStage = (ppsName, ppsValue);

procedure TDnHttpRequest.ParseParameters(Buffer: PAnsiChar);
var
  i: Integer;
  Stage: TDnParseParameterStage;
begin
  FParamArray[FParamCount].FName.FStart := 0;
  FParamArray[FParamCount].FName.FLength := 0;
  FParamArray[FParamCount].FValue.FLength := 0;
  Stage := ppsName;
  i := 0;
  while Buffer[i] <> #0 do
  begin
    case Buffer[i] of
      '=':
        begin
          Stage := ppsValue;
          FParamArray[FParamCount].FValue.FStart := i + 1;
          FParamArray[FParamCount].FValue.FLength := 0;
        end;

      '&':
        begin
          Stage := ppsName;
          Inc(FParamCount);
          FParamArray[FParamCount].FName.FStart := i + 1;
          FParamArray[FParamCount].FName.FLength := 0;
          FParamArray[FParamCount].FValue.FLength := 0;
        end;
    else
      begin
        if Stage = ppsName then
          Inc(FParamArray[FParamCount].FName.FLength)
        else
          Inc(FParamArray[FParamCount].FValue.FLength);
      end
    end;
    Inc(i);
  end;

  if Buffer[0] <> #0 then
    Inc(FParamCount);
end;

function FindSubstring(Str, Substr: PAnsiChar; StrSize: Integer): PAnsiChar;
var Iter: PAnsiChar;
    SubstrLen: Integer;
begin
  Result := Nil; Iter := Str; SubStrLen := StrLen(Substr);
  while (Iter < Str + StrSize) and (Result = Nil) do
  begin
    if AnsiStrLIComp(Iter, Substr, StrSize) = 0 then
      Result := Iter;
    Inc(Iter);
  end;
end;


constructor TDnFormDataParser.Create;
begin
  inherited Create;

  FStage := dpsBoundary;

  GetMem(FData, INITIAL_FORMDATA_SIZE);
  FDataCapacity := INITIAL_FORMDATA_SIZE;

  FHttpReader := TDnHttpReader.Create;
end;

destructor TDnFormDataParser.Destroy;
begin
  if FData <> Nil then
    FreeMem(FData);
  FreeAndNil(FHttpReader);

  inherited Destroy;
end;

procedure TDnFormDataParser.Clear;
var i: Integer;
begin
  FProcessed := 0;
  FIsDataReady := False;
  FIsFinished := False;
  for i:=0 to FParamCount-1 do
  begin
    if Assigned(FParamArray[i].FDataPtr) then
      FreeMem(FParamArray[i].FDataPtr);
  end;
  FParamCount := 0;
end;

procedure TDnFormDataParser.SetBoundary(Boundary: PAnsiChar);
begin
  FBoundarySign := Boundary;
end;

function TDnFormDataParser.Parse(Buffer: PAnsiChar; BufferSize: Integer): Boolean;
var
  BufferIter: Integer;
begin
  Result := False;

  FProcessed := 0;
  FIsDataReady := False;

  for BufferIter :=0 to BufferSize-1 do
  begin
    Inc(FProcessed);

    if FStage = dpsBoundary then
    begin
      // Cache boundary string
      if (Buffer[BufferIter] <> #13) and (Buffer[BufferIter] <> #10) then
      begin
        if FBoundarySize = MAX_BOUNDARY_SIZE then
          Exit; // Failed to parse

        FBoundary[FBoundarySize] := Buffer[BufferIter];
        Inc(FBoundarySize);
        FBoundary[FBoundarySize] := #0;
      end
      else
      if Buffer[BufferIter] = #10 then
      begin
        // Time to compare cached boundary with signature
        if AnsiStrComp(@FBoundary, FBoundarySign+2) <> 0 then
        begin
          if (FBoundarySize > 2) and (FBoundary[FBoundarySize-1] = '-') and (FBoundary[FBoundarySize-2] = '-') then
          begin
            FBoundary[FBoundarySize-2] := #0;
            if AnsiStrComp(@FBoundary, FBoundarySign+2) <> 0 then
              Exit;

            // Mark "End of message is found."
            FIsFinished := True;

            // Set number of processed bytes
            FProcessed := BufferIter + 1;

            // Result is positive - parsing was succesful
            Result := True;

            // Return from method
            Exit;
          end
          else
            Exit;
        end;

        // Move to next stage - headers
        FCRLFCounter := 0;
        FStage := dpsHeaders;
      end;
    end
    else
    if FStage = dpsHeaders then
    begin
      if (Buffer[BufferIter] <> #10) and (Buffer[BufferIter] <> #13) then
        FCRLFCounter := 0
      else
      if Buffer[BufferIter] = #10 then
        Inc(FCRLFCounter);

      // Cache headers
      if FHeadersSize = MAX_FORMDATA_HEADERS_SIZE then
        Exit; // Failed to parse

      FHeaders[FHeadersSize] := Buffer[BufferIter];
      Inc(FHeadersSize);
      FHeaders[FHeadersSize] := #0;

      if FCRLFCounter = 2 then
      begin
        // Try to parse read headers
        FHttpReader.Clear;
        FHttpReader.CopyToHeaderData(FHeaders, FHeadersSize-2);
        if not FHttpReader.Parse(False) then
          Exit;

        FStage := dpsData;
      end;
    end
    else
    if FStage = dpsData then
    begin
      // Ensure we have enough space to cache data
      if FDataSize = MAX_FORMDATA_SIZE then
        Exit;

      if FDataSize = FDataCapacity then
      begin
        ReallocMem(FData, FDataCapacity * 2);
        FDataCapacity := FDataCapacity * 2;
      end;

      // Cache data. Check for boundary here too.
      FData[FDataSize] := Buffer[BufferIter];
      Inc(FDataSize);

      // Append zero to make possible boundary string zero-terminated
      FData[FDataSize] := #0;

      // Check for boundary
      if FDataSize >= StrLen(FBoundarySign) then
      begin
        if AnsiStrComp(FData + FDataSize - StrLen(FBoundarySign), FBoundarySign) = 0 then
        begin
          // End of form data found
          FStage := dpsBoundary;

          // Adjust data size
          Dec(FDataSize, StrLen(FBoundarySign));

          // Reset length of detected boundary and headers
          FBoundarySize := 0;
          FHeadersSize := 0;

          // Report about ready data
          FIsDataReady := True;

          // Parse result is succesful
          Result := True;

          // Return number of processed bytes
          FProcessed := BufferIter - StrLen(FBoundarySign) + 3;

          // Exit from parse procedure
          Exit;
        end;
      end;
    end;
  end;

  FProcessed := BufferSize;
  Result := True;
end;

function TDnFormDataParser.InternalGetName(NamePrefix: PAnsiChar; BufferOut: PAnsiChar; BufferSize: Integer): Boolean;
var ContentDispositionHdr: PDnHttpHeader;
    CDS: array [0..MAX_PARAM_SIZE] of AnsiChar;
    NamePtr,
    QuotePtr: PAnsiChar;
    ToCopy: Integer;
begin
  ContentDispositionHdr := FHttpReader.FindHeader('Content-Disposition');
  if ContentDispositionHdr <> Nil then
  begin
    FHttpReader.CopyHeaderValue(ContentDispositionHdr, @CDS, Sizeof(CDS));

    // Find 'name='
    NamePtr := StrPos(CDS, NamePrefix);

    if NamePtr <> Nil then
    begin
      Inc(NamePtr, StrLen(NamePrefix));
      if NamePtr^ <> '"' then
        Result := False
      else
      begin
        QuotePtr := SysUtils.StrScan(NamePtr+1, '"');
        if QuotePtr <> Nil then
        begin
          // Find how much data we can copy
          ToCopy := Min (QuotePtr - NamePtr - 1, BufferSize-1);

          //Copy
          Move(NamePtr[1], BufferOut^, ToCopy);

          // Make string zeroterminated
          BufferOut[ToCopy] := #0;

          // Exit with True result
          Result := True;
          Exit;
        end;
      end;
    end;
  end;

  Result := False;
end;


function    TDnFormDataParser.GetName(BufferOut: PAnsiChar; BufferSize: Integer): Boolean;
begin
  Result := InternalGetName('name=', BufferOut, BufferSize);
end;

function    TDnFormDataParser.GetFileName(BufferOut: PAnsiChar; BufferSize: Integer): Boolean;
begin
  Result := InternalGetName('filename=', BufferOut, BufferSize);
end;


function    TDnFormDataParser.GetDataPtr: PAnsiChar;
begin
  Result := FData;
end;

function    TDnFormDataParser.GetDataSize: Integer;
begin
  Result := FDataSize;
end;

function TDnFormDataParser.SaveParamData: Integer;
begin
  if FParamCount < MAX_FORMDATAPARAM_COUNT then
  begin
    // Copy parameter name
    GetName(FParamArray[FParamCount].FName, Sizeof(FParamArray[FParamCount].FName));

    // Copy parameter filename
    GetFileName(FParamArray[FParamCount].FFileName, Sizeof(FParamArray[FParamCount].FFileName));

    // Copy pointer to data
    FParamArray[FParamCount].FDataPtr := Self.FData;

    // Save data size
    FParamArray[FParamCount].FDataSize := Self.FDataSize;

    // Reset data
    FDataSize := 0;
    FDataCapacity := 0;
    FData := Nil;
    GetMem(FData, INITIAL_FORMDATA_SIZE);
    FDataCapacity := INITIAL_FORMDATA_SIZE;
    Inc(FParamCount);
  end;

  Result := FParamCount;
end;

function TDnFormDataParser.GetParamCount: Integer;
begin
  Result := FParamCount;
end;

function  TDnFormDataParser.GetParamAt(Index: Integer): PDnFormDataParam;
begin
  Result := @FParamArray[Index];
end;

function  TDnFormDataParser.FindParamByName(ParamName: PAnsiChar): PDnFormDataParam;
var i: Integer;
begin
  for i:=0 to FParamCount-1 do
  begin
    if AnsiStrComp(ParamName, FParamArray[i].FName) = 0 then
    begin
      Result := @FParamArray[i];
      Exit;
    end;
  end;

  Result := Nil;
end;


// Returns parameters count
function TDnHttpRequest.ParamCount: Integer;
begin
  Result := FParamCount;
end;

// Get parameter record by index
function TDnHttpRequest.GetParamAt(Index: Integer): PDnHttpParam;
begin
  if Index >= FParamCount then
    Result := Nil
  else
    Result := @FParamArray[Index];
end;

// Get parameter name
procedure TDnHttpRequest.GetParamName(Param: PDnHttpParam;
  BufferPtr: PAnsiChar; BufferSize: Integer = -1);
var
  ToCopy: Integer;
begin
  if not Assigned(Param) then
    Exit;

  if Assigned(FFormData) then
  begin
    ;//TODO
  end
  else
  begin
    if BufferSize = -1 then
      ToCopy := Param.FName.FLength
    else
      ToCopy := Min(BufferSize - 1, Param.FName.FLength);

    CopyURLEncoded(BufferPtr, ToCopy + 1, @FParamData[Param.FName.FStart], Param.FName.FLength);
  end;
end;

// Get parameter value
procedure TDnHttpRequest.GetParamValue(Param: PDnHttpParam; BufferPtr: PAnsiChar; BufferSize: Integer = -1);
var
  ToCopy: Integer;
begin
  if not Assigned(Param) then
    Exit;

  if Assigned(FFormData) then
  begin
    // TODO
  end
  else
  begin
    if BufferSize = -1 then
      ToCopy := Param.FValue.FLength
    else
      ToCopy := Min(BufferSize - 1, Param.FValue.FLength);

    CopyURLEncoded(BufferPtr, ToCopy + 1, @FParamData[Param.FValue.FStart], Param.FValue.FLength);
  end;
end;

// Helper function to save raw parameters data
function TDnHttpRequest.SaveParametersData(BufferPtr: PAnsiChar; BufferSize: Integer): Boolean;
var
  ToCopy: Integer;
begin
  if FStage = hrsFormData then
  begin
    // Check if there is enough space in FFormData
    if FFormDataUsed + BufferSize > FFormDataCapacity then
    begin
      while (FFormDataCapacity < FFormDataUsed + BufferSize) and (FFormDataCapacity < MAX_FORMDATA_SIZE) do
        FFormDataCapacity := FFormDataCapacity * 2;

      // Check if amount of requested memory does not exceed limit
      if FFormDataCapacity < FFormDataUsed + BufferSize then
      begin
        Result := False;
        Exit;
      end;

      // Attempt to allocate memory
      try
        ReallocMem(FFormData, FFormDataCapacity);
      except
        on EOutOfMemory do
        begin
          Result := False;
          Exit;
        end;
      end;
    end;

    // Copy data
    Move(BufferPtr^, FFormData[FFormDataUsed], BufferSize);
    Inc(FFormDataUsed, BufferSize);
    Result := True;
  end
  else
  begin
    if BufferSize > MAX_PARAM_TOTALSIZE then
      Result := False
    else
    begin
      Move(BufferPtr^, FParamData, BufferSize);
      FParamData[BufferSize] := #0;
      FParamSize := BufferSize;
      Result := True;
    end;
  end;
end;

// ------------------------ TDnHttpWriter ------------------------
constructor TDnHttpWriter.Create;
begin
  inherited Create;

  GetMem(FContent, INITIAL_WRITER_BUFFER_SIZE);
  FContentCapacity := INITIAL_WRITER_BUFFER_SIZE;
  FContentSize := 0;
end;

destructor TDnHttpWriter.Destroy;
begin
  FreeMem(FContent);
  inherited Destroy;
end;

procedure TDnHttpWriter.Clear;
begin
  // The FContent is not realloced here - as I expect FContentCapacity to be around average value in any way
  FContentSize := 0;
  FHeaderSize := 0;
  FIsLastChunk := False;

end;

procedure TDnHttpWriter.AddVersion(Version: TDnHttpVersion);
begin
  case Version of
    http09:
      QueueBuffer(PByte(PAnsiChar('HTTP/0.9 ')));
    http10:
      QueueBuffer(PByte(PAnsiChar('HTTP/1.0 ')));
    http11:
      QueueBuffer(PByte(PAnsiChar('HTTP/1.1 ')));
  end;
end;

procedure TDnHttpWriter.AddResponseCode(Code: Integer);
var
  FormatString: PAnsiChar;
  FormatResult: array [0 .. 31] of AnsiChar;
begin
  FormatString := '%d ';
{$IF NOT DEFINED(VER200) AND NOT DEFINED(VER210)}
  FormatResult[FormatBuf(FormatResult, Sizeof(FormatResult), FormatString^,
    StrLen(FormatString), [Code])] := #0;
{$ELSE}
  FormatResult[AnsiFormatBuf(FormatResult, Sizeof(FormatResult), FormatString^,
    StrLen(FormatString), [Code])] := #0;
{$IFEND}
  QueueBuffer(@FormatResult);
end;

procedure TDnHttpWriter.AddResponseMsg(Msg: PAnsiChar);
var
  CRLF: PAnsiChar;
begin
  QueueBuffer(PByte(Msg));
  CRLF := #13#10;
  QueueBuffer(PByte(PAnsiChar(CRLF)));
end;

procedure TDnHttpWriter.AddHeader(const HeaderName: PAnsiChar;
  const HeaderValue: PAnsiChar);
var
  HeaderText: array [0 .. MAX_HTTP_HEADER_SIZE] of AnsiChar;
  FormatText: PAnsiChar;
begin
  FormatText := '%s: %s'#13#10;
{$IF NOT DEFINED(VER200) AND NOT DEFINED(VER210)}
  HeaderText[FormatBuf(HeaderText, Sizeof(HeaderText), FormatText^,
    StrLen(FormatText), [HeaderName, HeaderValue])] := #0;
{$ELSE}
  HeaderText[AnsiFormatBuf(HeaderText, Sizeof(HeaderText), FormatText^,
    StrLen(FormatText), [HeaderName, HeaderValue])] := #0;
{$IFEND}
  QueueBuffer(PByte(@HeaderText[0]));
end;

procedure TDnHttpWriter.AddHeader(const HeaderName: PAnsiChar;
  HeaderValue: Integer);
var
  HeaderText: array [0 .. MAX_HTTP_HEADER_SIZE] of AnsiChar;
  FormatText: PAnsiChar;
begin
  FormatText := '%s: %d'#13#10;
{$IF NOT DEFINED(VER200) AND NOT DEFINED(VER210)}
  HeaderText[FormatBuf(HeaderText, Sizeof(HeaderText), FormatText^,
    StrLen(FormatText), [HeaderName, HeaderValue])] := #0;
{$ELSE}
  HeaderText[AnsiFormatBuf(HeaderText, Sizeof(HeaderText), FormatText^,
    StrLen(FormatText), [HeaderName, HeaderValue])] := #0;
{$IFEND}
  QueueBuffer(PByte(@HeaderText[0]));
end;

procedure TDnHttpWriter.FinishHeader;
begin
  if FHTTPKeepAlive then
    AddHeader('Connection', 'Keep-Alive')
  else
    AddHeader('Connection', 'Close');

  if FHTTPChunkedEncoding then
    AddHeader('Transfer-Encoding', 'chunked')
  else
  begin
    AddHeader('Content-Length', FHTTPContentLength);
  end;

  QueueBuffer(PByte(PAnsiChar(#13#10#0)));

  FHeaderSize := FContentSize;
end;

procedure TDnHttpWriter.AddContent(const Buffer: PAnsiChar;
  BufferSize: Integer);
var
  ChunkLength: packed array [0 .. 32] of AnsiChar;
  FormatText: PAnsiChar;
begin
  if FIsLastChunk then
    Exit;

  // Prefix with buffer length for chunked encoding
  if FHTTPChunkedEncoding then
  begin
    FormatText := '%x'#13#10;
{$IF NOT DEFINED(VER200) AND NOT DEFINED(VER210)}
    ChunkLength[FormatBuf(ChunkLength, Sizeof(ChunkLength), FormatText^,
      StrLen(FormatText), [BufferSize])] := #0;
{$ELSE}
    ChunkLength[AnsiFormatBuf(ChunkLength[0], Sizeof(ChunkLength), FormatText^,
      StrLen(FormatText), [BufferSize])] := #0;
{$IFEND}
    QueueBuffer(PByte(@ChunkLength[0]), StrLen(PAnsiChar(@ChunkLength[0])));
  end;

  if BufferSize = 0 then
    FIsLastChunk := True
  else
    QueueBuffer(PByte(PAnsiChar(Buffer)), BufferSize);

  if FHTTPChunkedEncoding then
    QueueBuffer(PByte(PAnsiChar(#13#10)));
end;

procedure TDnHttpWriter.Build;
begin
  // No implementation here - currently all data are written ready-to-use
end;

procedure TDnHttpWriter.QueueBuffer(const Buffer: PByte;
  BufferSize: Integer);
begin
  if BufferSize = 0 then
    Exit;

  // Check if there is enough space to enqueue BufferSize
  while FContentCapacity - FContentSize < BufferSize do
  begin
    // Reallocate buffer
    ReallocMem(FContent, FContentCapacity * 2);
    FContentCapacity := FContentCapacity * 2;
  end;

  Move(Buffer^, FContent[FContentSize], BufferSize);
  Inc(FContentSize, BufferSize);
end;

procedure TDnHttpWriter.QueueBuffer(const Buffer: PByte);
begin
  Self.QueueBuffer(Buffer, StrLen(PAnsiChar(Buffer)));
end;

function TDnHttpWriter.GetContent: PByte;
begin
  Result := PByte(PAnsiChar(FContent));
end;

function TDnHttpWriter.GetContentSize: Integer;
begin
  Result := FContentSize;
end;

function TDnHttpWriter.GetHeaderSize: Integer;
begin
  Result := FHeaderSize;
end;

function TDnHttpWriter.GetBodySize: Integer;
begin
  Result := FHTTPContentLength;
end;

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
(*
  class function  TDnHttpParser.Skip1Space(const S: RawByteString; StartWith: Integer): Integer;
  var i: Integer;
  begin
  i := StartWith;
  if (i < Length(S)) and (S[i] = ' ') then
  Result := i + 1
  else
  raise EDnException.Create(ErrCannotParseHttpHeader, 0, S);
  end;

  class function  TDnHttpParser.Skip1Colon(const S: RawByteString; StartWith: Integer): Integer;
  var i: Integer;
  begin
  i := StartWith;
  if (i < Length(S)) and (S[i] = ':') then
  Result := i + 1
  else
  raise EDnException.Create(ErrCannotParseHttpTime, 0, S);
  end;

  class function  TDnHttpParser.GetWord(const S: RawByteString; StartWith: Integer; var Lexem: RawByteString): Integer;
  var i, len: Integer;
  begin
  i := StartWith; len := Length(S);
  while (i<=len) and (S[i] in ['A'..'Z','a'..'z']) do
  Inc(i);
  Lexem := Copy(S, StartWith, i-StartWith);
  Result := i;
  end;

  class function  TDnHttpParser.GetIntLexem(const S: RawByteString; StartWith: Integer; var Lexem: RawByteString): Integer;
  var i, len: Integer;
  begin
  i := StartWith; len := Length(S);
  while (i<=len) and ((S[i] in ['0'..'9']) or ((S[i] in ['-', '+']) and (i = StartWith))) do
  Inc(i);
  Lexem := Copy(S, StartWith, i-StartWith);
  Result := i;
  end;

  class procedure TDnHttpParser.ParseResponseContentType(const S: RawByteString; var ContentType: RawByteString;
  var CharSet: RawByteString);
  var semicolon: Integer;
  begin
  semicolon := Pos(';', S);
  if semicolon <> 0 then
  begin
  ContentType := Copy(S, 1, semicolon-1);
  CharSet := Copy(S, semicolon+1, Length(S) - semicolon);
  end else
  begin
  ContentType := Copy(S, 1, Length(S));
  CharSet := 'us-ascii';
  end;
  ContentType := Trim(ContentType); CharSet := Trim(CharSet);
  end;

  class function  TDnHttpParser.ParseAcceptList(const S: RawByteString): TStringList;
  begin
  Result := TStringList.Create;
  end;

  class function  TDnHttpParser.AdjustSlash(const S: RawByteString): RawByteString;
  var i: Integer;
  begin
  Result := S;
  for i:=1 to Length(S) do
  if Result[i] = '/' then
  Result[i] := '\';
  end;

  class procedure TDnHttpParser.ParseHttpTime(const S: RawByteString; StartWith: Integer;
  var FinishWith: Integer;
  var Year, Month, Day, DayOfWeek, Hour,
  Minute, Second: Integer;
  var TimeZone: RawByteString);
  var i, len, j, lexemLen, TimeKind: Integer;
  Lexem: RawByteString;
  begin
  i := StartWith; len := Length(S);
  i := GetWord(S, i, Lexem); lexemLen := i - StartWith;

  if lexemLen > 3 then
  TimeKind := 2 //RFC 850
  else if (i <= len) and (S[i] = ',') and (lexemLen = 3) then
  TimeKind := 1 //RFC 822
  else if (i <= len) and (S[i] = ' ') and (lexemLen = 3) then
  TimeKind := 3 //asctime
  else if lexemLen = 0 then
  TimeKind := 4 //number of seconds
  else
  raise EDnException.Create(ErrCannotParseHttpTime, 0, S);

  case TimeKind of
  1:  begin //RFC 822
  //find a number of week day
  j := 0;
  while (j < 7) and (ShortWeekDays[j] <> Lexem) do
  Inc(j);
  if j = 7 then
  raise EDnException.Create(ErrCannotParseHttpTime, 0, S);
  DayOfWeek := j;

  Inc(i); //skip a comma
  //find a number of day (in month)
  i := Skip1Space(S, i); i := GetIntLexem(S, i, Lexem);
  Day := StrToInt(Lexem);
  if Day > 31 then
  raise EDnException.Create(ErrCannotParseHttpTime, 0, S);

  i := Skip1Space(S, i);
  i := GetWord(S, i, Lexem);
  j := 1;
  while (j<13) and (MonthNames[j] <> Lexem) do
  Inc(j);
  if j = 13 then
  raise EDnException.Create(ErrCannotParseHttpTime, 0, S);
  Month := j;

  //find a year
  i := Skip1Space(S, i);
  i := GetIntLexem(S, i, Lexem);
  Year := StrToInt(Lexem);

  //find a hour
  i := Skip1Space(S, i); i := GetIntLexem(S, i, Lexem);
  Hour := StrToInt(Lexem);

  //find a minute
  i := Skip1Colon(S, i); i := GetIntLexem(S, i, Lexem);
  Minute := StrToInt(Lexem);

  //find a second
  i := Skip1Colon(S, i); i := GetIntLexem(S, i, Lexem);
  Second := StrToInt(Lexem);

  i := Skip1Space(S, i); i := GetWord(S, i, Lexem);
  TimeZone := Lexem;
  FinishWith := i-1;
  end;
  2:  begin //RFC 850
  //find a number of week day
  j := 0;
  while (j < 7) and (LongWeekDays[j] <> Lexem) do
  Inc(j);
  if j = 7 then
  raise EDnException.Create(ErrCannotParseHttpTime, 0, S);
  DayOfWeek := j;

  Inc(i); //skip a comma
  //find a number of day (in month)
  i := Skip1Space(S, i); i := GetIntLexem(S, i, Lexem);
  Day := StrToInt(Lexem);
  if Day > 31 then
  raise EDnException.Create(ErrCannotParseHttpTime, 0, S);

  Inc(i);//skip a '-'
  i := GetWord(S, i, Lexem);
  j := 1;
  while (j<13) and (MonthNames[j] <> Lexem) do
  Inc(j);
  if j = 13 then
  raise EDnException.Create(ErrCannotParseHttpTime, 0, S);
  Month := j;
  Inc(i);//skip a '-'
  i := GetIntLexem(S, i, Lexem);
  Year := StrToInt(Lexem);
  //Y2K problem
  if Year > 35 then
  Year := Year + 1900
  else
  Year := Year + 2000;

  //find a hour
  i := Skip1Space(S, i); i := GetIntLexem(S, i, Lexem);
  Hour := StrToInt(Lexem);

  //find a minute
  i := Skip1Colon(S, i); i := GetIntLexem(S, i, Lexem);
  Minute := StrToInt(Lexem);

  //find a second
  i := Skip1Colon(S, i); i := GetIntLexem(S, i, Lexem);
  Second := StrToInt(Lexem);

  i := Skip1Space(S, i); i := GetWord(S, i, Lexem);
  TimeZone := Lexem;
  FinishWith := i-1;
  end;
  3:  begin
  //find a number of week day
  j := 0;
  while (j < 7) and (ShortWeekDays[j] <> Lexem) do
  Inc(j);
  if j = 7 then
  raise EDnException.Create(ErrCannotParseHttpTime, 0, S);
  DayOfWeek := j;
  i := Skip1Space(S, i); i := GetWord(S, i, Lexem);
  j := 1;
  while (j<13) and (MonthNames[j] <> Lexem) do
  Inc(j);
  if j = 13 then
  raise EDnException.Create(ErrCannotParseHttpTime, 0, S);
  Month := j;
  i := Skip1Space(S, i);
  if i>Length(S) then
  raise EDnException.Create(ErrCannotParseHttpTime, 0, S);
  if S[i] = ' ' then
  i := Skip1Space(S, i);

  i := GetIntLexem(S, i, Lexem);
  day := StrToInt(Lexem);
  if Day > 31 then
  raise EDnException.Create(ErrCannotParseHttpTime, 0, S);

  //find a hour
  i := Skip1Space(S, i); i := GetIntLexem(S, i, Lexem);
  Hour := StrToInt(Lexem);

  //find a minute
  i := Skip1Colon(S, i); i := GetIntLexem(S, i, Lexem);
  Minute := StrToInt(Lexem);

  //find a second
  i := Skip1Colon(S, i); i := GetIntLexem(S, i, Lexem);
  Second := StrToInt(Lexem);

  i := Skip1Space(S, i); i := GetIntLexem(S, i, Lexem);
  Year := StrToInt(Lexem);
  TimeZone := 'GMT';
  FinishWith := i-1;
  end;
  4:  begin
  i := GetIntLexem(S, i, Lexem);
  Second := StrToInt(Lexem);
  FinishWith := i-1;
  end;
  end;

  end;

  class function  TDnHttpParser.FormatHttpTime( Year, Month, Day, DayOfWeek, Hour, Minute, Second: Integer;
  TimeZone: RawByteString): RawByteString;
  var HttpTime: RawByteString;
  begin
  if  (DayOfWeek > 6) or (DayOfWeek < 0) or (Month > 12) or (Month < 1) or
  (Day < 1) or (Day > 31) or (Hour > 24) or (Hour < 0) or
  (Minute < 0) or (Minute > 59) or (Second < 0) or (Second > 59) then
  raise EDnException.Create(ErrInvalidParameter, -1);

  HttpTime := '%s, %.2d %s %.4d %.2d:%.2:%.2 %s';
  Result := Format (HttpTime, [ShortWeekDays[DayOfWeek], Day,
  MonthNames[Month], Year, Hour,
  Minute, Second, TimeZone]);
  end;




  constructor TDnHttpParser.Create;
  begin
  inherited Create;
  FHttpData := '';
  FNames := TDnStringList.Create;
  FValues := TDnStringList.Create;
  end;

  procedure TDnHttpParser.Clear;
  begin
  FNames.Clear;
  FValues.Clear;
  FHttpVersion := '';
  FMethodName := '';
  FMethodURL := '';
  FHttpResponseCode := 0;
  FHttpResponseReason := '';
  end;


  destructor TDnHttpParser.Destroy;
  begin
  FreeAndNil(FNames);
  FreeAndNil(FValues);
  inherited Destroy;
  end;

  function  TDnHttpParser.GetHttpHeader(const Name: RawByteString): RawByteString;
  var i: Integer;
  begin
  i := FNames.IndexOf(Name);
  if i = -1 then
  Result := ''
  else
  Result := FValues[i];
  end;

  procedure TDnHttpParser.SetHttpHeader(const Name, Value: RawByteString);
  var i: Integer;
  begin
  i := FNames.IndexOf(Name);
  if i <> -1 then
  FValues[i] := Value
  else
  begin
  FNames.Add(Name);
  FValues.Add(Value);
  end;
  end;

  procedure TDnHttpParser.ParseHttpHeaders(S: RawByteString);
  var EOL, AssignPos: Integer;
  Line: RawByteString;
  begin
  EOL := Pos(CRLF, S);
  while EOL<>0 do
  begin
  Line := Copy(S, 1, EOL-1); Delete(S, 1, EOL+1);
  AssignPos := Pos('=', S);
  if AssignPos <> 0 then
  begin
  FNames.Add(Trim(Copy(Line, 1, AssignPos-1)));
  FValues.Add(Trim(Copy(Line, AssignPos+1, Length(Line) - AssignPos)));
  end;
  EOL := Pos(CRLF, S);
  end;
  end;

  procedure TDnHttpParser.ParseRequest(const HttpData: RawByteString);
  var S: RawByteString;
  Line, Lexem: RawByteString;
  EOL, i, j: Integer;
  begin
  FNames.Clear; FValues.Clear;
  //Normalize CRLF pairs
  S := AdjustLineBreaks(HttpData);
  EOL := Pos(CRLF, S);
  Line := Copy(S, 1, EOL-1);
  Delete(S, 1, EOL+1);

  //parse method name, URL, HTTP version
  i := GetWord(Line, 1, Lexem);
  FMethodName := UpperCase(Lexem);
  i := Skip1Space(Line, i);
  j := i;
  while (Line[j] <> ' ') and (j < Length(Line)) do
  Inc(j);
  FMethodURL := Copy(Line, i, j-i);
  i := j;
  FHttpVersion := UpperCase(Copy(Line, i, Length(Line) - i + 1));
  ParseHttpHeaders(S);
  end;

  procedure TDnHttpParser.ParseResponse(const HttpData: RawByteString);
  var S, Line: RawByteString;
  SpacePos, EOL: Integer;
  begin
  FNames.Clear; FValues.Clear;
  S := AdjustLineBreaks(HttpData);
  EOL := Pos (CRLF, S);
  if EOL = 0 then
  raise EDnException.Create(ErrCannotParseHttp, 0, S);
  Line := Copy(S, 1, EOL-1); Delete(S, 1, EOL+1);
  SpacePos := Pos(' ', S);
  if SpacePos = 0 then
  raise EDnException.Create(ErrCannotParseHttp, 0, Line);
  FHttpVersion := Copy(Line, 1, SpacePos-1); Delete(Line, 1, SpacePos);
  SpacePos := Pos(' ', Line);
  if SpacePos = 0 then
  raise EDnException.Create(ErrCannotParseHttp, 0, Line);
  FHttpResponseCode := StrToInt(Copy(Line, 1, SpacePos-1));
  Delete(Line, 1, SpacePos+1);
  FHttpResponseReason := Copy(Line, 1, Length(Line));
  ParseHttpHeaders(S);
  end;

  function TDnHttpParser.AssembleHttpHeaders: RawByteString;
  var i: Integer;
  begin
  Result := '';
  for i:=0 to FNames.Count-1 do
  Result:= Result + FNames[i] + ': ' + FValues[i] + CRLF;
  end;

  function TDnHttpParser.AssembleResponse: RawByteString;
  begin
  Result := FHttpVersion + ' ' + IntToStr(FHttpResponseCode) + ' ' + FHttpResponseReason + CRLF;
  Result := Result + AssembleHttpHeaders();
  Result := Result + CRLF;
  end;

  function TDnHttpParser.AssembleRequest: RawByteString;
  begin
  Result := FMethodName + ' ' + FMethodURL + ' ' + FHttpVersion + CRLF;
  Result := Result + AssembleHttpHeaders();
  Result := Result + CRLF;
  end;

  class function TDnHttpParser.ExtractLine(var Data: RawByteString): RawByteString;
  var CrLfPos: Integer;
  begin
  CrLfPos := Pos(CRLF, Data);
  if CrLfPos > 0 then
  begin
  Result := Copy(Data, 1, CrLfPos-1);
  Delete(Data, 1, CrLfPos+1);
  end else
  begin
  Result := Data;
  Data := '';
  end;
  end;


  class procedure TDnHttpParser.ExtractPair(var Data: RawByteString; var LeftPart, RightPart: RawByteString);
  var ScPos: Integer;
  begin
  ScPos := Pos(':', Data);
  if ScPos > 0 then
  begin
  LeftPart := Copy(Data, 1, ScPos-1);
  RightPart := Copy(Data, ScPos+1, Length(Data) - ScPos);
  end else
  LeftPart := Data;
  end;

  class procedure TDnHttpParser.StripSpaces(var Data: RawByteString);
  var I: Integer;
  begin
  //Detect first spaces
  for i := 1 to Length(Data) do
  if Data[i] <> '' then
  break;

  if I <= Length(Data) then
  begin
  if I <> 1 then
  Delete(Data, 1, I-1);
  end else
  Data := '';

  //Detect last spaces
  for  I:= Length(Data) downto 1 do
  if Data[i] <> '' then
  break;

  if I > 0 then
  begin
  if I <> Length(Data) then
  Delete(Data, I, Length(Data) - I);
  end else
  Data := '';
  end;

  procedure GetLexem( Data: RawByteString; StartWith: Integer; var Lexem: RawByteString;
  var FinishWith: Integer);
  var i, len: Integer;
  begin
  len := Length(Data);
  i := StartWith;
  while not (Data[i] in ['/', '\', ':', '?', '@']) and (i <= len) do
  begin
  Inc(i);
  end;
  Lexem := Copy(Data, StartWith, i-StartWith);
  FinishWith := i;
  end;

  procedure GetDelimiter( Data: RawByteString; StartWith: Integer; var Delimiter: RawByteString;
  var FinishWith: Integer);
  var i, len: Integer;
  begin
  len := Length(Data);
  i := StartWith;
  while (Data[i] in ['/', '\', ':', '?', '@']) and (i <= len) do
  begin
  if (Data[i] = '@') and (i = StartWith) then
  begin
  FinishWith := i + 1;
  Delimiter := '@';
  Exit;
  end else
  if (Data[i] = '@') and (i <> StartWith) then
  break;
  Inc(i);
  end;
  Delimiter := Copy(Data, StartWith, i-StartWith);
  FinishWith := i;
  end;

  class function TDnHttpParser.IsAbsoluteUrl(const Url: RawByteString): Boolean;
  begin
  Result := Pos('://', Url) <> 0;
  end;

  class procedure TDnHttpParser.ParseRelativeUrl(const Url: RawByteString; var Path, Query: RawByteString);
  var QueryPos : Integer;
  begin
  if Url = '*' then
  begin
  Path := '*';
  Query := '';
  Exit;
  end;

  QueryPos := Pos('?', Url);
  if QueryPos = 0 then
  begin
  Path := Url;
  Query := '';
  end else
  begin
  Path := Copy(Url, 1, QueryPos - 1);
  Query := Copy(Url, QueryPos, Length(Url) - QueryPos);
  end;
  end;



  class procedure TDnHttpParser.ParseAbsoluteUrl(const Url: RawByteString; var Protocol, User, Password,
  Host, Port, Path, Query: RawByteString;
  var UserExists, PasswordExists: Boolean);
  var LastDelimiterPos, Fp: Integer;
  Lexem: RawByteString;
  Delimiter: RawByteString;
  //PossiblePassword,
  //PossibleHost: RawByteString;
  //PossiblePasswordExists: Boolean;
  QueryStart, PathStart: PChar;
  //URLLen: Integer;
  begin
  Protocol := ''; User := ''; Password := '';
  Host := ''; Port := ''; Query := '';
  UserExists := False; PasswordExists := False;


  GetLexem(Url, 1, Lexem, Fp);
  LastDelimiterPos := Fp;
  GetDelimiter(Url, Fp, Delimiter, Fp);
  if Delimiter = '://' then
  begin
  Protocol := LowerCase(Lexem);
  GetLexem(Url, Fp, Lexem, Fp);
  LastDelimiterPos := Fp;
  GetDelimiter(Url, Fp, Delimiter, Fp);
  end else
  Protocol := LowerCase('http');
  if Delimiter = '@' then
  begin
  UserExists := True;
  User := Lexem;

  GetLexem(Url, Fp, Lexem, Fp);
  LastDelimiterPos := Fp;
  GetDelimiter(Url, Fp, Delimiter, Fp);
  if Delimiter = ':' then
  begin
  Password := Lexem; PasswordExists := True;
  GetLexem(Url, Fp, Lexem, Fp);
  LastDelimiterPos := Fp;
  GetDelimiter(Url, Fp, Delimiter, Fp);
  end;
  end else
  if Delimiter = ':' then
  begin
  PasswordExists := True; Password := Lexem;
  GetLexem(Url, Fp, Lexem, Fp);
  LastDelimiterPos := Fp;
  GetDelimiter(Url, Fp, Delimiter, Fp);
  end;

  while Delimiter = '.' do
  begin
  Host := Host + Lexem + Delimiter;
  GetLexem(Url, Fp, Lexem, Fp);
  GetDelimiter(Url, Fp, Delimiter, Fp);
  end;
  Host := Host + Lexem;

  if Delimiter = ':' then
  begin //port
  GetLexem(Url, Fp, Lexem, Fp);
  LastDelimiterPos := Fp;
  GetDelimiter(Url, Fp, Delimiter, Fp);
  Port := Lexem;
  end;
  //LastDelimiterPos := Fp;
  QueryStart := StrScan(PChar(Url) + LastDelimiterPos-1, '?');
  PathStart := StrScan(PChar(Url) + LastDelimiterPos-1, '/');
  if QueryStart = Nil then
  begin
  //QueryExists := False;
  Query := '';
  if PathStart = Nil then
  Path := ''
  else
  begin
  Path := Copy(Url, PathStart - PChar(Url) + 1, Length(Url) - (PathStart - PChar(Url)));
  end;
  end else
  begin
  //QueryExists := True
  Query := Copy(Url, QueryStart - PChar(Url) + 1, Length(Url) - (QueryStart - PChar(Url)));
  if PathStart = Nil then
  Path := ''
  else begin
  Path := Copy(Url, PathStart - PChar(Url) + 1, QueryStart - PathStart);
  end;
  end;
  end;

  //-----------------------------------------------------------------------------
*)

end.
