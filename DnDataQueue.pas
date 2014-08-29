unit DnDataQueue;
interface
uses
  Classes, SysUtils, Windows, SyncObjs, Math, DnRtl;

type
  TDnDataQueue = class
  protected
    FSize,
    FCapacity,
    FIncrement:   Integer;
    FData:        PByte;
    FGuard:       TCriticalSection;

    procedure SetSize(NewSize: Integer);
    
  public
    constructor Create(InitialCapacity: Integer = 8192; Increment: Integer = 8192);
    destructor  Destroy; override;

    procedure   Lock;
    procedure   Unlock;
    procedure   Append(Buf: Pointer; Size: Integer);
    procedure   AppendString(const S: RawByteString);
    procedure   AppendFromStream(Stream: TStream; Size: Integer);
    function    Extract(Buf: Pointer; Size: Integer): Integer;
    function    Delete(Size: Integer): Integer;
    procedure   Clear;

    function    IsInteger: Boolean;
    function    IsInt64: Boolean;
    function    IsByte: Boolean;
    function    IsAnsiChar: Boolean;

    function    ReadInteger: Integer;
    function    ReadCardinal: Cardinal;
    function    ReadInt64: Int64;
    function    ReadByte: Byte;
    function    ReadWord: Word;
    function    ReadAnsiChar: AnsiChar;
    function    ReadBlock(BlockSize: Integer): AnsiString;

    procedure   EnsureCapacity(NewSize: Integer);

    property    Size:  Integer read FSize write SetSize;
    property    Capacity: Integer read FCapacity write FCapacity;
    property    Memory: PByte read FData;
  end;

implementation

//---------------------- TDataQueue ---------------------
constructor TDnDataQueue.Create(InitialCapacity: Integer = 8192; Increment: Integer = 8192);
begin
  inherited Create;
  FGuard := TCriticalSection.Create;

  GetMem(FData, InitialCapacity);
  if FData = Nil then
    raise EOutOfMemory.Create('TDataQueue.Create');
  FCapacity := InitialCapacity;
  FIncrement := Increment;
  FSize := 0;
end;

destructor TDnDataQueue.Destroy;
begin
  FreeMem(FData); FData := Nil;
  FreeAndNil(FGuard);
  inherited Destroy;
end;

procedure TDnDataQueue.SetSize(NewSize: Integer);
begin
  Assert(NewSize <= FCapacity);
  FSize := NewSize;
end;

procedure TDnDataQueue.EnsureCapacity(NewSize: Integer);
var NewCapacity: Integer;
begin
  if NewSize > FCapacity then
  begin
    if NewSize mod FIncrement = 0 then
      NewCapacity := NewSize
    else
      NewCapacity := FIncrement * ((NewSize div FIncrement) + 1);

    Assert(NewCapacity >= NewSize);

    ReallocMem(FData, NewCapacity);

    FCapacity := NewCapacity;
  end;
end;

procedure TDnDataQueue.Append(Buf: Pointer; Size: Integer);
begin
  EnsureCapacity(FSize + Size);
  
  Move(PAnsiChar(Buf)^, (PAnsiChar(FData) + FSize)^, Size);

  Inc(FSize, Size);
end;

procedure TDnDataQueue.AppendString(const S: RawByteString);
begin
  Self.Append(@S[1], Length(S));
end;

procedure TDnDataQueue.AppendFromStream(Stream: TStream; Size: Integer);
begin
  EnsureCapacity(FSize + Size);
  Stream.Read((PAnsiChar(FData) + FSize)^, Size);
  Inc(FSize, Size);
end;

procedure TDnDataQueue.Lock;
begin
  FGuard.Enter;
end;

procedure TDnDataQueue.Unlock;
begin
  FGuard.Leave;
end;

function TDnDataQueue.Extract(Buf: Pointer; Size: Integer): Integer;
var ToCopy: Integer;
begin
  ToCopy := Min(Size, FSize);
  if Buf <> Nil then
    Move(PAnsiChar(FData)^, PAnsiChar(Buf)^, ToCopy);
  if FSize <> ToCopy then
    Move(PAnsiChar(Cardinal(FData) + Size)^, PAnsiChar(FData)^, FSize - Size);
  
  Dec(FSize, ToCopy);
  Result := ToCopy;
end;

function TDnDataQueue.Delete(Size: Integer): Integer;
begin
  Result := Extract(Nil, Size);
end;

procedure TDnDataQueue.Clear;
begin
  Extract(Nil, Size);
end;

function TDnDataQueue.IsInteger: Boolean;
begin
  Result := Size >= Sizeof(Integer);
end;

function TDnDataQueue.IsInt64: Boolean;
begin
  Result := Size >= Sizeof(Int64);
end;

function TDnDataQueue.IsByte: Boolean;
begin
  Result := Size >= Sizeof(Byte);
end;

function TDnDataQueue.IsAnsiChar: Boolean;
begin
  Result := Size >= Sizeof(AnsiChar);
end;

function TDnDataQueue.ReadInteger: Integer;
begin
  Extract(@Result, Sizeof(Integer));
end;

function TDnDataQueue.ReadInt64: Int64;
begin
  Extract(@Result, Sizeof(Int64));
end;

function TDnDataQueue.ReadByte: Byte;
begin
  Extract(@Result, Sizeof(Result));
end;

function TDnDataQueue.ReadCardinal: Cardinal;
begin
  Extract(@Result, Sizeof(Result));
end;

function TDnDataQueue.ReadWord: Word;
begin
  Extract(@Result, Sizeof(Result));
end;

function TDnDataQueue.ReadAnsiChar: AnsiChar;
begin
  Extract(@Result, Sizeof(@Result));
end;

function TDnDataQueue.ReadBlock(BlockSize: Integer): AnsiString;
var Avail: Integer;
begin
  if BlockSize > Size then
    raise Exception.Create('!!!');

  Avail := Min(Size, BlockSize);
  SetString(Result, PAnsiChar(Memory), Avail);
  Delete(Avail);
end;

end.

