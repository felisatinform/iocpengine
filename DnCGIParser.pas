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
unit DnCGIParser;
interface
uses
  Classes, SysUtils, Contnrs,
  DnConst, DnHttpParser, DnCoders, DnRtl;


type
  TDnCGIValue = class (TObject)
  protected
    FValue: String;
    FNull: Boolean;
  public
    constructor Create(const S: String); overload;
    constructor CreateAsNull;
    constructor Create; overload;
    destructor Destroy; override;
    property  Value: String read FValue write FValue;
    property  IsNull: Boolean read FNull write FNull;
  end;

  TDnCGIParam = class (TObject)
  protected
    FName:    String;
    FValue:   TObjectList;
    function  GetValueCount: Integer;
    function  GetArrayValue(Ind: Integer): TDnCGIValue;
    function  GetValue: TDnCGIValue;
  public
    constructor Create;
    destructor  Destroy; override;
    procedure   AddValue(Value: String);
    procedure   AddNull;
    property    Name: String read FName write FName;
    property    Value: TDnCGIValue read GetValue;
    property    ValueCount: Integer read GetValueCount;
    property    ArrayValue[Ind: Integer]: TDnCGIValue read GetArrayValue;
  end;

  TDnCGIDecoder = class (TObject)
  protected
    FRawQuery: String;
    FParamList: TObjectList;
    constructor Create;
    procedure ParseGET(const Query: String);
    procedure ParsePOST(const Query: String);
  public
    class function ParseGETQuery(const Query: String): TDnCGIDecoder;
    class function ParsePOSTQuery(const Query: String): TDnCGIDecoder;
    destructor  Destroy; override;
    function  ParamCount: Integer;
    function  ParamByIndex(ind: Integer): TDnCGIParam;
    function  ParamByName(const ind: String): TDnCGIParam;
  end;

implementation

constructor TDnCGIValue.Create;
begin
  inherited Create;
  SetLength(FValue, 0);
  FNull := True;
end;

constructor TDnCGIValue.Create(const S: String);
begin
  inherited Create;
  FValue := S; FNull := False;
end;

constructor TDnCGIValue.CreateAsNull;
begin
  inherited Create;
  SetLength(FValue, 0); FNull := True;
end;

destructor TDnCGIValue.Destroy;
begin
  inherited Destroy;
end;
//-------------------------------------------------------------------------

constructor TDnCGIParam.Create;
begin
  FName := '';
  FValue := TObjectList.Create;
end;



destructor TDnCGIParam.Destroy;
begin
  FreeAndNil(FValue);
end;

procedure TDnCGIParam.AddValue(Value: String);
begin
  FValue.Add(TDnCGIValue.Create(Value));
end;

procedure   TDnCGIParam.AddNull;
begin
  FValue.Add(TDnCGIValue.CreateAsNull());
end;

function TDnCGIParam.GetValueCount: Integer;
begin
  Result := FValue.Count;
end;

function TDnCGIParam.GetArrayValue(Ind: Integer): TDnCGIValue;
begin
  if FValue.Count-1 < Ind then
    raise EDnException.Create(ErrCannotGetCGIParamValue, Ind);
  Result := TDnCGIValue(FValue[Ind]);
end;

function TDnCGIParam.GetValue: TDnCGIValue;
begin
  if FValue.Count = 0 then
    raise EDnException.Create(ErrCannotGetCGINullValue, 0);
  Result := TDnCGIValue(FValue[0]);
end;
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

class function TDnCGIDecoder.ParseGETQuery(const Query: String): TDnCGIDecoder;
begin
  Result := TDnCGIDecoder.Create;
  Result.ParseGET(Query);
end;

class function TDnCGIDecoder.ParsePOSTQuery(const Query: String): TDnCGIDecoder;
begin
  Result := TDnCGIDecoder.Create;
  Result.ParsePOST(Query);
end;

constructor TDnCGIDecoder.Create;
begin
  inherited Create;
  FParamList := TObjectList.Create;
  FRawQuery := '';
end;

destructor TDnCGIDecoder.Destroy;
begin
  FreeAndNil(FParamList);
  inherited Destroy;
end;

procedure TDnCGIDecoder.ParseGET(const Query: String);
var p, asgn, amp: Integer;
    param: TDnCGIParam;
    item, paramName: String;
begin
  FRawQuery := Query;
  p := 1;
  if FRawQuery[1] = '?' then
    inc(p);

  repeat
    amp := Pos('&', FRawQuery);
    
    if amp <> 0 then
      item := Copy(FRawQuery, P, amp-P)
    else
      item := Copy(FRawQuery, p, Length(FRawQuery) - p + 1);

    if Length(item) <> 0 then
    begin
      asgn := Pos('=', item);
      if asgn <> 0 then
      begin
        paramName := TDnEscapeCoder.Decode(Trim(Copy(item, 1, asgn-1)));
        param := ParamByName(paramName);
        if param = Nil then
        begin
          param := TDnCGIParam.Create;
          FParamList.Add(param);
        end;
        param.FName := paramName;
        param.AddValue(TDnEscapeCoder.Decode(Trim(Copy(item, asgn+1, Length(item)-asgn))));
      end
      else
      begin
        paramName := TDnEscapeCoder.Decode(Trim(item));
        param := ParamByName(paramName);
        if param = Nil then
        begin
          param := TDnCGIParam.Create;
          param.FName := paramName;
          FParamList.Add(param);
        end;
        param.AddNull();
      end;
    end;
  until amp = 0;
  FRawQuery := Query;
end;

procedure TDnCGIDecoder.ParsePOST(const Query: String);
var pline, pasgn: Integer;
    curLine, paramName: String;
    paramItem: TDnCGIParam;
begin
  FRawQuery := Query;
  while Length(FRawQuery) <> 0 do
  begin
    //take line
    pline := Pos(#13#10, FRawQuery);
    if pline = 0 then
    begin
      curLine := FRawQuery;
      FRawQuery := '';
    end else
    begin
      curLine := Copy(FRawQuery, 1, pline-1);
      Delete(FRawQuery, 1, pline+1);
    end;

    pasgn := Pos('=', curLine);
    if pasgn = 0 then
    begin
      paramName := TDnEscapeCoder.Decode(Trim(curLine));
      paramItem := Self.ParamByName(paramName);
      if paramItem = Nil then
      begin
        paramItem := TDnCGIParam.Create;
        FParamList.add(paramItem);
        paramItem.Name := paramName;
      end;
      paramItem.AddNull();
    end
    else
    begin
      paramName := TDnEscapeCoder.Decode(Copy(curLine, 1, pasgn-1));
      paramItem := Self.ParamByName(paramName);
      if paramItem = Nil then
      begin
        paramItem := TDnCGIParam.Create;
        FParamList.Add(paramItem);
        paramItem.Name := paramName;
      end;
      paramItem.AddValue(TDnEscapeCoder.Decode(Copy(curLine, pasgn+1, Length(curLine) - pasgn)));
    end;
  end;
end;

function TDnCGIDecoder.ParamCount: Integer;
begin
  Result := FParamList.Count;
end;

function TDnCGIDecoder.ParamByIndex(Ind: Integer): TDnCGIParam;
begin
  Result := TDnCGIParam(FParamList[Ind]);
end;

function TDnCGIDecoder.ParamByName(const Ind: String): TDnCGIParam;
var i: Integer;
begin
  i := 0;
  while (i<FParamList.Count) and (TDnCGIParam(FParamList[i]).Name <> Ind) do
    Inc(i);
  if i<FParamList.Count then
    Result := TDnCGIParam(FParamList[i])
  else
    Result := Nil;
end;

end.
