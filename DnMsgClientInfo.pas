unit DnMsgClientInfo;
interface
uses
  Classes, SysUtils, Math, DnRtl;

type
  TMsgClientInfo = class
  protected
    FID,                        //Id (uniqe, set by client user)
    FAddress,                   //socket's IP address visible from the server
    FUser,                      //(set by client user)
    FPassword,                  //(set by client user)
    FVersion: RawByteString;    //(set by client user)

  public
    function SerializeTo: RawByteString;
    function SerializeSize: Integer;
    procedure SerializeFrom(var S: RawByteString);

    property ID:        RawByteString read FID write FID;
    property Address:   RawByteString read FAddress write FAddress;
    property User:      RawByteString read FUser write FUser;
    property Password:  RawByteString read FPassword write FPassword;
    property Version:   RawByteString read FVersion write FVersion;
  end;

  TExternalMemoryStream = class(TStream)
  private
    FMemory: PAnsiChar;
    FSize, FPosition: Integer;
  public
    constructor Create(Buffer: PAnsiChar; BufSize: Integer);
    destructor Destroy; override;

    function Write(const Buffer; Count: Longint): Longint; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Seek(Offset: Longint; Origin: Word): Longint; override;

    property Memory: PAnsiChar read FMemory;
  end;


implementation

function TMsgClientInfo.SerializeTo: RawByteString;
begin
  Result := ID + #0 + User + #0 + Password + #0 + Version + #0;
end;

function TMsgClientInfo.SerializeSize: Integer;
begin
  Result := Length(ID) + Length(User) + Length(Password) + Length(Version) +
    4;
end;

procedure TMsgClientInfo.SerializeFrom(var S: RawByteString);
var P1: Integer;
    VersionStr: RawByteString;
    ZeroStr: RawByteString;
begin
  ZeroStr := '';

  P1 := AnsiStrScan(PAnsiChar(S), #0) - PAnsiChar(S);
  if P1 < 0 then
    raise Exception.Create('Wrong parameter.');
  SetString(FID, PAnsiChar(S), P1);
  Delete(S, 1, P1 + 1);

  //User
  P1 := AnsiStrScan(PAnsiChar(S), #0) - PAnsiChar(S);
  if P1 < 0 then
    raise Exception.Create('Wrong parameter.');
  SetString(FUser, PAnsiChar(S), P1);
  Delete(S, 1, P1 + 1);

  //Password
  P1 := AnsiStrScan(PAnsiChar(S), #0) - PAnsiChar(S);
  if P1 < 0 then
    raise Exception.Create('Wrong parameter.');
  SetString(FPassword, PAnsiChar(S), P1);
  Delete(S, 1, P1 + 1);

  //Version
  P1 := AnsiStrScan(PAnsiChar(S), #0) - PAnsiChar(S);
  if P1 < 0 then
    raise Exception.Create('Wrong parameter.');
  SetString(VersionStr, PAnsiChar(S), P1);
  Delete(S, 1, P1+1);
  FVersion := VersionStr;
end;


constructor TExternalMemoryStream.Create(Buffer: PAnsiChar; BufSize: Integer);
begin
  inherited Create;
  FMemory := Buffer;
  FSize := BufSize;
  FPosition := 0;
end;

destructor TExternalMemoryStream.Destroy;
begin
  inherited Destroy;
end;

function TExternalMemoryStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result := 0;
end;

function TExternalMemoryStream.Read(var Buffer; Count: Longint): Longint;
var ToCopy: Integer;
begin
  ToCopy := Math.Min(Count, FSize - FPosition);
  Move((FMemory + FPosition)^, Buffer, ToCopy);
  Inc(FPosition, ToCopy); 
  Result := ToCopy;
end;

function TExternalMemoryStream.Seek(Offset: Longint; Origin: Word): Longint;
begin
  case Origin of
    soFromBeginning: begin
      if Offset > FSize then
        FPosition := FSize
      else
        FPosition := Offset;
    end;

    soFromCurrent: begin
      if Offset + FPosition > FSize then
        FPosition := FSize
      else
      if Offset + FPosition < 0 then
        FPosition := 0
      else
        FPosition := FPosition + Offset;
    end;

    soFromEnd: begin
      if FSize - Offset  < 0 then
        FPosition := 0
      else
      if FSize - Offset > FSize then
        FPosition := FSize
      else
        FPosition := FSize - Offset;
    end;
  end;

  Result := FPosition;
end;


end.
