unit DnStringList;

interface
uses
  contnrs, DnRtl;

type

  TDnStringList = class
  protected
    FData: TObjectList;
    procedure SetString(Index: Integer; Value: RawByteString);
    function  GetString(Index: Integer): RawByteString;
    function  GetCount: Integer;

  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure Add(const S: RawByteString);
    function  IndexOf(const S: RawByteString): Integer;

    property  Strings[Index: Integer]: RawByteString read GetString write SetString; default;
    property  Count: Integer read GetCount;
  end;


implementation

type
  TStringValue = class
  public
    FValue: RawByteString;

  end;


constructor TDnStringList.Create;
begin
  inherited Create;
  FData := TObjectList.Create(True);
end;

destructor TDnStringList.Destroy;
begin
  FData.Free;
  inherited Destroy;
end;

procedure TDnStringList.Add(const S: RawByteString);
var ValueObject: TStringValue;
begin
  ValueObject := TStringValue.Create();
  ValueObject.FValue := S;
  FData.Add(ValueObject);
end;

function  TDnStringList.IndexOf(const S: RawByteString): Integer;
var
  I: Integer;
begin
  for I := 0 to FData.Count - 1 do
  begin
    if TStringValue(FData[i]).FValue = S then
    begin
      Result := I;
      Exit;
    end;
  end;

  Result := -1;
end;

procedure TDnStringList.SetString(Index: Integer; Value: RawByteString);
begin
  TStringValue(FData[Index]).FValue := Value;
end;

function  TDnStringList.GetString(Index: Integer): RawByteString;
begin
  Result := TStringValue(FData[Index]).FValue;
end;

function  TDnStringList.GetCount: Integer;
begin
  Result := FData.Count;
end;

procedure TDnStringList.Clear;
begin
  FData.Clear;
end;
end.
