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
unit DnCookieParser;
interface
uses  SysUtils, Windows, Classes, contnrs,
      DnRtl, DnConst, DnHttpParser, DnCoders;

type
  TDnSetCookie = class;


  TDnSetCookieList = class (TObject)
  protected
    FCookieList: TObjectList;

    function GetCookieItem(Ind: Integer): TDnSetCookie;
    function GetCookieCount: Integer;
  public
    constructor Create;
    destructor  Destroy; override;
    procedure   Parse(const RawData: String);
    function    Assemble: String;
    procedure   Add(Cookie: TDnSetCookie);
    procedure   Clear;

    property    Cookie[Ind: Integer]: TDnSetCookie read GetCookieItem;
    property    Count: Integer read GetCookieCount;
  end;

  TDnSetCookie = class (TObject)
  protected
    FName:      String;
    FValue:     String;
    FMaxAge:    Cardinal;
    FComment:   String;
    FPath:      String;
    FDomain:    String;
    FSecure:    Boolean;
    FVersion:   String;
  public
    constructor Create; overload;
    constructor Create(const RawData: String); overload;
    constructor Create(const Name, Value: String; MaxAge: Cardinal;
        const Comment, Path, Domain: String; Secure: Boolean;
        Version: String); overload;
    destructor Destroy; override;
    class function Assemble(const Name, Value: String; MaxAge: Cardinal;
        const Comment, Path, Domain: String; Secure: Boolean;
        Version: String): String; overload;

    function Parse(const RawData: String): String;
    function Assemble: String; overload;

    property Name:    String read FName write FName;
    property Value:   String read FValue write FValue;
    property MaxAge:  Cardinal read FMaxAge write FMaxAge;
    property Comment: String read FComment write FComment;
    property Path:    String read FPath write FPath;
    property Domain:  String read FDomain write FDomain;
    property Secure:  Boolean read FSecure write FSecure;
    property Version: String read FVersion write FVersion;
  end;

  TDnClientCookies = class (TObject)
  protected
    FCookieNames: TStringList;
    FCookieValues: TStringList;
    FPath: String;
    FDomain: String;
    FVersion: String;
  public
    constructor Create; 
    destructor Destroy; override;
    procedure Parse(const RawData: String);
    function  Assemble: String;
    procedure Add(const Name, Value: String);
    procedure Clear;

    property Path: String read FPath write FPath;
    property Domain: String read FDomain write FDomain;
    property Version: String read FVersion write FVersion;
  end;

implementation

constructor TDnSetCookieList.Create;
begin
  inherited Create;
  FCookieList := TObjectList.Create;
end;

destructor TDnSetCookieList.Destroy;
begin
  FreeAndNil(FCookieList);
  inherited Destroy;
end;

procedure TDnSetCookieList.Add(Cookie: TDnSetCookie);
begin
  FCookieList.Add(Cookie);
end;

procedure TDnSetCookieList.Parse(const RawData: String);
var toParse: String;
    cookie: TDnSetCookie;
begin
  toParse := Trim(RawData);
  while Length(toParse) <> 0 do
  begin
    cookie := TDnSetCookie.Create;
    FCookieList.Add(cookie);
    toParse := cookie.Parse(toParse);
  end;
end;

procedure TDnSetCookieList.Clear;
begin
  FCookieList.Clear;
end;

function TDnSetCookieList.GetCookieItem(Ind: Integer): TDnSetCookie;
begin
  Result := TDnSetCookie(FCookieList[Ind]);
end;

function TDnSetCookieList.GetCookieCount: Integer;
begin
  Result := FCookieList.Count;
end;

function TDnSetCookieList.Assemble: String;
var i: Integer;
begin
  Result := '';
  for i:=0 to FCookieList.Count-2 do
    Result := Result + TDnSetCookie(FCookieList).Assemble + ',';
  if FCookieList.Count > 0 then
    Result := Result + TDnSetCookie(FCookieList).Assemble;
end;


constructor TDnSetCookie.Create;
begin
  FName := '';
  FValue := '';
  FMaxAge := 0;
  FComment := '';
  FPath := '';
  FDomain := '';
  FSecure := False;
  FVersion := '0';
end;

constructor TDnSetCookie.Create(const RawData: String);
begin
  Self.Parse(RawData);
end;

constructor TDnSetCookie.Create( const Name, Value: String; MaxAge: Cardinal;
    const Comment, Path, Domain: String; Secure: Boolean;
    Version: String);
begin
  FName := Name;
  FValue := Value;
  FMaxAge := MaxAge;
  FComment := Comment;
  FPath := Path;
  FDomain := Domain;
  FSecure := Secure;
  FVersion := Version;
end;

destructor TDnSetCookie.Destroy;
begin
end;

class function TDnSetCookie.Assemble(const Name, Value: String; MaxAge: Cardinal;
        const Comment, Path, Domain: String; Secure: Boolean;
        Version: String): String;
begin
  Result := '';
  Result := Result + TDnEscapeCoder.Encode(Name) + '=' +
            TDnEscapeCoder.Encode(Value) + '; Max-Age=' +
            IntToStr(MaxAge) + '; Comment=' + TDnEscapeCoder.Encode(Comment) +
            '; Path=' + TDnEscapeCoder.Encode(Path) + '; Domain=' +
            TDnEscapeCoder.Encode(Domain);
  if Secure then
    Result := Result + '; Secure; ';
  Result := Result + '; Version=' + TDnEscapeCoder.Encode(Version);
end;

function TDnSetCookie.Parse(const RawData: String): String;
var semicolon, comma, asgn: Integer;
    pair, cookie, rvalue, lvalue: String;
begin

  comma := Pos(',', RawData);
  if comma <> 0 then
  begin
    cookie := Copy(RawData, 1, comma-1);
    Result := Copy(RawData, comma+1, Length(RawData) - comma);
  end
  else
  begin
    cookie := RawData;
    Result := '';
  end;

  semicolon := Pos(';', cookie);
  try
    if semicolon <> 0 then
    begin
    //Extract 'name=value' pair
      pair := Trim(Copy(cookie, 1, semicolon-1));
      asgn := Pos('=', pair);
      if asgn <> 0 then
      begin
        FName := TDnEscapeCoder.Decode(Trim(Copy(pair, 1, asgn-1)));
        FValue := TDnEscapeCoder.Decode(Trim(Copy(pair, asgn+1, Length(pair) - asgn)));
      end else
        raise EDnException.Create(ErrCannotParseCookie, 0, RawData);
      Delete(cookie, 1, semicolon);
    end
    else
      raise EDnException.Create(ErrCannotParseCookie, 0, RawData);

    Delete(cookie, 1, semicolon);
    Cookie := Trim(Cookie);
    repeat
      semicolon := Pos(';', cookie);
      if semicolon <> 0 then
      begin
        pair := Copy(cookie, 1, semicolon-1);
        Delete(cookie, 1, semicolon);
      end else
      begin
        pair := cookie;
        cookie := '';
      end;
      //extract pair's data
      asgn := Pos('=', pair);
      if asgn <> 0 then
      begin
        lvalue := Trim(Copy(pair, 1, asgn-1));
        rvalue := TDnEscapeCoder.Decode(Trim(Copy(pair, asgn+1, Length(pair)-asgn)));
        if rvalue = 'Max-Age' then
          FMaxAge := StrToInt(rvalue)
        else if lvalue = 'Comment' then
          FComment := rvalue
        else if lvalue = 'Path' then
          FPath := rvalue
        else if lvalue = 'Domain' then
          FDomain := rvalue
        else if lvalue = 'Version' then
          FVersion := rvalue
        else raise EDnException.Create(ErrCannotParseCookie, 0, RawData);
      end else
      begin
        lvalue := Trim(pair);
        if lvalue = 'Secure' then
          FSecure := True
        else
          raise EDnException.Create(ErrCannotParseCookie, 0, RawData);
      end;
    until Length(cookie) = 0;
  except
    on E: Exception do
      raise EDnException.Create(ErrCannotParseCookie, 0, RawData);
  end;
end;

function TDnSetCookie.Assemble: String;
begin
  Result := TDnSetCookie.Assemble(FName, FValue, FMaxAge, FComment, FPath,
    FDomain, FSecure, FVersion);
end;

//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------

constructor TDnClientCookies.Create;
begin
  inherited Create;
  FCookieNames := TStringList.Create;
  FCookieValues := TStringList.Create;
  FPath := '';
  FDomain := '';
  FVersion := '';
end;

destructor TDnClientCookies.Destroy;
begin
  FreeAndNil(FCookieNames);
  FreeAndNil(FCookieValues);
  inherited Destroy;  
end;

procedure TDnClientCookies.Parse(const RawData: String);
var buf, lvalue, rvalue: String;
    i, lvalueStart, rvalueStart: Integer;
begin
  buf := RawData;
  i := 1; lvalueStart := 1; rvalueStart := -1;
  while i < Length(RawData) do
  begin
    if RawData[i] in [',', ';'] then
    begin
      if rvalueStart = -1 then
        raise EDnException.Create(ErrCannotParseCookie, 0, RawData);
      rvalue := TDnEscapeCoder.Decode(Trim(Copy(RawData, rvalueStart, i-rvalueStart)));
      if lvalue = 'Path' then
        FPath := rvalue
      else if lvalue = 'Version' then
        FVersion := rvalue
      else if lvalue = 'Domain' then
        FDomain := rvalue
      else
      begin
        FCookieNames.Add(lvalue);
        FCookieValues.Add(rvalue);
      end;
      lvalueStart := i+1;
    end else
    if RawData[i] in ['='] then
    begin
      rvalueStart := i + 1;
      lvalue := TDnEscapeCoder.Decode((Copy(RawData, lvalueStart, i-lvalueStart)));
    end else
      ;
    Inc(i);
  end;
end;

function  TDnClientCookies.Assemble: String;
var i: Integer;
begin
  for i:=0 to FCookieNames.Count-2 do
    Result := Result + TDnEscapeCoder.Encode(FCookieNames[i]) +
      '=' + TDnEscapeCoder.Encode(FCookieValues[i]) + ';';

  i := FCookieNames.Count-1;
  if FCookieNames.Count > 0 then
    Result := Result + TDnEscapeCoder.Encode(FCookieNames[i]) +
      '=' + TDnEscapeCoder.Encode(FCookieValues[i]);
  if FPath <> '' then
    Result := Result + '; Path=' + TDnEscapeCoder.Encode(FPath);
  if FDomain <> '' then
    Result := Result + '; Domain=' + TDnEscapeCoder.Encode(FDomain);
  Result := Result +' ; Version=' + TDnEscapeCoder.Encode(FVersion);
end;

procedure TDnClientCookies.Add(const Name, Value: String);
begin
  FCookieNames.Add(Name);
  FCookieValues.Add(Value);
end;

procedure TDnClientCookies.Clear;
begin
  FCookieNames.Clear;
  FCookieValues.Clear;
end;

end.
