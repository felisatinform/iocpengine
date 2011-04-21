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
unit DnCoders;

interface
uses  SysUtils,
      DnConst, DnRtl;
type
  TDnEscapeCoder = class(TObject)
  public
    class function Encode(const S: String): String;
    class function Decode(const S: String): String;
  end;

  TDnBase64Encoder = class(TObject)
  protected
    FSource:        Pointer;
    FSourceSize:    Integer;
    FFinishSwitch:  Boolean;
    FProcessed:     Integer;
    FCharPos:       Integer;
    FNeededInput:   Boolean;
    FNeededOutput:  Boolean;

    procedure Three2Four(a1, a2, a3: byte; var b1, b2, b3, b4: byte);
  public
    constructor Create;
    destructor  Destroy; override;
    procedure   Reset;
    procedure   SetSource(var Source; Size: Integer);
    function    RemainingInputData: Integer;
    function    Encode(var Dest; Size: Integer): Integer;
    function    IsNeededInput: Boolean;
    function    IsNeededOutput: Boolean;
    procedure   Finish;
  end;

  TDnBase64Decoder = class(TObject)
  protected
    FSource:        Pointer;
    FSourceSize:    Integer;
    FFinishSwitch:  Boolean;
    FProcessed:     Integer;
    FCharPos:       Integer;
    FNeededInput:   Boolean;
    FNeededOutput:  Boolean;
    procedure Four2Three(a1, a2, a3, a4: Byte; var b1, b2, b3: Byte);
  public
    constructor Create;
    destructor  Destroy; override;
    procedure   Reset;
    procedure   SetSource(var Source; Size: Integer);
    function    RemainingInputData: Integer;
    function    Decode(var Dest; Size: Integer): Integer;
    function    IsNeededInput: Boolean;
    function    IsNeededOutput: Boolean;
    procedure   Finish;
  end;

implementation

const
  Base64Alphabet: String = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-';

class function TDnEscapeCoder.Decode(const S: String): String;
var i, j, Len, Start: Integer;
begin
  Len := Length(S); Start := 1;
  SetLength(Result, Len);
  i := Start; j := 1;
  while i < Start+Len do
  begin
    if S[i] = '%' then
    begin
      if i >= Start+Len - 2 then
        Result[j] := Char(Byte(StrToInt('$' + Copy(S, i+1, 2))))
      else
        raise EDnException.Create(ErrCannotParseUrlencodedString, 0, S);
      inc(i, 2);
    end else
    if S[i] = '+' then
      Result[j] := ' '
    else
      Result[j] := S[i];
    inc(j); inc(i);
  end;
  Result := Copy(Result, 1, j-1);
end;

class function TDnEscapeCoder.Encode(const S: String): String;
var i, j, SLen: Integer;
    hex: String;
begin
  SLen := Length(S);
  SetLength(Result, SLen*3);
  j := 1;
  for i:=1 to SLen do
  begin
    if S[i] in ['a'..'z', 'A'..'Z', '0'..'9', '.', '-', '*', '_'] then
      Result[j] := S[i]
    else if S[i] = ' ' then
      Result[j] := '+'
    else
    begin
      hex := IntToHex(Byte(S[i]), 2);
      Result[j] := '%'; Result[j+1] := hex[1]; Result[j+2] := hex[2];
      inc(j,2);
    end;
    inc(j);
  end;
  SetLength(Result, j-1);
end;
//---------------------------------------------------------------------------
//---------------------------------------------------------------------------

constructor TDnBase64Encoder.Create;
begin
  inherited Create;
  Reset;
end;

destructor TDnBase64Encoder.Destroy;
begin
  inherited Destroy;
end;

procedure TDnBase64Encoder.Three2Four(a1, a2, a3: byte; var b1, b2, b3, b4: byte);
begin
  b1 := a1 shr 2;
  b2 := ((a1 shl 4) and $30) + ((a2 shr 4) and $F);
  b3 := ((a2 shl 2) and $3C) + ((a3 shr 6) and $3);
  b4 := a3 and $3F;
  if b1 = 0 then
    b1 := 64 + 32
  else
    b1 := b1 + 32;

  if b2 = 0 then
    b2 := 64 + 32
  else
    b2 := b2 + 32;

  if b3 = 0 then
    b3 := 64 + 32
  else
    b3 := b3 + 32;

  if b4 = 0 then
    b4 := 64 + 32
  else
    b4 := b4 + 32;

  b1 := byte(Base64Alphabet[(b1 - 32) mod 64]);
  b2 := byte(Base64Alphabet[(b2 - 32) mod 64]);
  b3 := byte(Base64Alphabet[(b3 - 32) mod 64]);
  b4 := byte(Base64Alphabet[(b4 - 32) mod 64]);
end;

procedure TDnBase64Encoder.Reset;
begin
  FSource := Nil;
  FSourceSize := 0;
  FFinishSwitch := False;
  FProcessed := 0;
  FCharPos := 0;
  FNeededInput := False;
  FNeededOutput := False;
end;


procedure   TDnBase64Encoder.SetSource(var Source; Size: Integer);
begin
  FSource := PChar(@Source);
  FSourceSize := Size;
end;

function  TDnBase64Encoder.RemainingInputData: Integer;
begin
  Result := FSourceSize - FProcessed;
end;

function    TDnBase64Encoder.Encode(var Dest; Size: Integer): Integer;
var Filled, i: Integer;
    outByte, inByte: PChar;
    a1, a2, a3, b1, b2, b3, b4: Byte;
begin
  outByte := PChar(Dest); inByte := PChar(FSource);
  FNeededInput := False; FNeededOutput := False;
  FProcessed := 0;
  Filled := 0;
  //Result := 0;
  //need to finish the line?
  if FCharPos > 76-1 then
  begin //append CRLF
    if Size-Filled < 2 then
    begin //not enough output space
      Result := Filled;
      FNeededOutput := True;
      Exit;
    end else
    begin
      outByte^ := #13; inc(outByte); inc(filled);
      outByte^ := #10; inc(outByte); inc(filled);
      FCharPos := 0;
    end;
  end;

  for i:=0 to FSourceSize-1 do
  begin
    //check the required output space
    if Size-Filled < 4 then
    begin //not enough output space
      Result := Filled;
      FNeededOutput := True;
      FProcessed := i;
      Exit;
    end;

    if (i > FSourceSize - 3) and not FFinishSwitch then
    begin
      FNeededInput := True;
      Result := filled;
      FProcessed := i;
      Exit;
    end;

    a1 := Byte(inByte^); inc(inByte); a2 := 0; a3 := 0;
    if i < FSourceSize - 1 then
    begin
      a2 := Byte(inByte^);
      inc(inByte);
    end;

    if i < FSourceSize - 2 then
    begin
      a3 := Byte(inByte^);
      inc(inByte);
    end;
    FProcessed := i;
    Three2Four(a1, a2, a3, b1, b2, b3, b4);
    Byte(outByte^) := b1; inc(outByte); inc(filled); inc(FCharPos);
    Byte(outByte^) := b2; inc(outByte); inc(filled); inc(FCharPos);
    Byte(outByte^) := b3; inc(outByte); inc(filled); inc(FCharPos);
    Byte(outByte^) := b4; inc(outByte); inc(filled); inc(FCharPos);

    //need to finish the line?
    if FCharPos = 76 then
    begin //append CRLF
      if Size-Filled < 2 then
      begin //not enough output space
        Result := filled;
        FNeededOutput := True;
        FProcessed := i;
        Exit;
      end else
      begin
        outByte^ := #13; inc(outByte); inc(filled);
        outByte^ := #10; inc(outByte); inc(filled);
        FCharPos := 0;
      end;
    end;
  end;
  Result := Filled;
end;

function TDnBase64Encoder.IsNeededInput: Boolean;
begin
  Result := FNeededInput;
end;

function TDnBase64Encoder.IsNeededOutput: Boolean;
begin
  Result := FNeededOutput;
end;

procedure TDnBase64Encoder.Finish;
begin
  FFinishSwitch := True;
end;
//------------------------------------------------------------------------
//------------------------------------------------------------------------

constructor TDnBase64Decoder.Create;
begin
  inherited Create;
  Reset;
end;

destructor TDnBase64Decoder.Destroy;
begin
  inherited Destroy;
end;

procedure TDnBase64Decoder.Reset;
begin
  FSource := Nil;
  FSourceSize := 0;
  FFinishSwitch := False;
  FProcessed := 0;
  FCharPos := 0;
  FNeededInput := False;
  FNeededOutput := False;
end;

procedure TDnBase64Decoder.SetSource(var Source; Size: Integer);
begin
  FSource := PChar(@Source);
  FSourceSize := Size;
end;

function TDnBase64Decoder.RemainingInputData: Integer;
begin
  Result := FSourceSize - FProcessed;
end;

procedure TDnBase64Decoder.Four2Three(a1, a2, a3, a4: Byte; var b1, b2, b3: Byte);
begin
  case Char(a1) of
    'A'..'Z': a1 := a1 - Byte('A');
    'a'..'z': a1 := a1 + 26 - Byte('a');
    '0'..'9': a1 := a1 + 52 - Byte('0');
    '+':      a1 := 62;
    '-':      a1 := 63;
  end;

  case Char(a2) of
    'A'..'Z': a2 := a2 - Byte('A');
    'a'..'z': a2 := a2 + 26 - Byte('a');
    '0'..'9': a2 := a2 + 52 - Byte('0');
    '+':      a2 := 62;
    '-':      a2 := 63;
  end;

  case Char(a3) of
    'A'..'Z': a3 := a3 - Byte('A');
    'a'..'z': a3 := a3 + 26 - Byte('a');
    '0'..'9': a3 := a3 + 52 - Byte('0');
    '+':      a3 := 62;
    '-':      a3 := 63;
  end;

  case Char(a4) of
    'A'..'Z': a4 := a4 - Byte('A');
    'a'..'z': a4 := a4 + 26 - Byte('a');
    '0'..'9': a4 := a4 + 52 - Byte('0');
    '+':      a4 := 62;
    '-':      a4 := 63;
  end;

  b1 := (a1 shl 2) + ((a2 and $30) shr 4);
  b2 := ((a2 and $F) shl 4) + ((a3 and $3c) shr 2);
  b3 := ((a3 and $3) shl 6) + (a4 and $3F);
end;

function TDnBase64Decoder.Decode(var Dest; Size: Integer): Integer;
var filled, i, fetchedQuartet, startQuartet, endQuartet: Integer;
    inByte, outByte: PChar;
    quartet: array[0..4] of Byte;
    b1, b2, b3: byte;
begin
  inByte := PChar(FSource); outByte := PChar(Dest);
  FNeededOutput := False; FNeededInput := False;
  fetchedQuartet := 0; startQuartet := 0;
  quartet[0] := 0; quartet[1] := 0; quartet[2] := 0; quartet[3] := 0;
  filled := 0; endQuartet := 0;
  
  for i:=0 to FSourceSize-1 do
  begin
    if inByte^ in [#13, #10] then
    begin //skip them
      Inc(FProcessed);
      Continue;
    end;

    if fetchedQuartet < 4 then
    begin
      if fetchedQuartet = 0 then
        startQuartet := i;
      quartet[fetchedQuartet] := byte(inByte^);
      inc(fetchedQuartet);
      endQuartet := i;
    end;

    if fetchedQuartet = 4 then
    begin
      //check for required output space
      if Size - filled < 3 then
      begin
        FProcessed := startQuartet;
        FNeededOutput := True;
        Result := filled;
        Exit;
      end;

      Four2Three(quartet[0], quartet[1], quartet[2], quartet[3], b1, b2, b3);
      outByte^ := Char(b1); inc(outByte); inc(filled);
      outByte^ := Char(b2); inc(outByte); inc(filled);
      outByte^ := Char(b3); inc(outByte); inc(filled);
      quartet[0] := 0; quartet[1] := 0; quartet[2] := 0; quartet[3] := 0;
      FProcessed := i;
      fetchedQuartet := 0;
    end;
  end;
  if fetchedQuartet > 0 then
  begin
    if FFinishSwitch then
    begin
      if Size - filled < 3 then
      begin
        FNeededOutput := True;
        FProcessed := startQuartet;
        Result := filled;
        Exit;
      end;
      Four2Three(quartet[0], quartet[1], quartet[2], quartet[3], b1, b2, b3);
      outByte^ := Char(b1); inc(outByte); inc(filled);
      outByte^ := Char(b2); inc(outByte); inc(filled);
      outByte^ := Char(b3); {inc(outByte);} inc(filled);
      FProcessed := endQuartet;
      //Result := filled;
    end else
    begin
      FNeededInput := True;
      FProcessed := startQuartet;
      //Result := filled;
      //Exit;
    end;
  end;
  Result := filled;
end;

function TDnBase64Decoder.IsNeededInput: Boolean;
begin
  Result := FNeededInput;
end;

function TDnBase64Decoder.IsNeededOutput: Boolean;
begin
  Result := FNeededOutput;
end;

procedure TDnBase64Decoder.Finish;
begin
  FFinishSwitch := True;
end;

end.
