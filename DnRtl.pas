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
unit DnRtl;

interface
uses
  SysUtils, Windows, Contnrs, Classes, DnConst, WS2;

type

{$if CompilerVersion < 20}
  RawByteString = AnsiString;
{$ifend}

{$if CompilerVersion <= 18.5}
  NativeUInt = Cardinal;
{$ifend}

  EDnException = class(Exception)
  protected
    FErrorCode: Integer;
    FErrorSubCode: Integer;
    FErrorMessage: String;
    function GetErrorMessage: String;
  public
    constructor Create(Code: Integer; SubCode: Integer); overload;
    constructor Create(Code: Integer; SubCode: Integer; const Details: String); overload;
    destructor  Destroy; override;
    property    ErrorMessage: String read GetErrorMessage;
    property    ErrorCode: Integer read FErrorCode;
    property    ErrorSubCode: Integer read FErrorSubCode;
  end;

  TDnLogEvent = procedure (Msg: String) of object;

  TDnMutex = class
  protected
    FCriticalSection: TRTLCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Acquire;
    procedure Release;
  end;

  TDnWaitResult = (dwrTimeOut, dwrSignaled, dwrFailed);

  TDnEvent = class
  protected
    FEvent: THandle;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Pulse;
    procedure SetEvent;
    function WaitFor(TimeOut: Cardinal): TDnWaitResult; overload;
    function WaitFor: TDnWaitResult; overload;

    property Handle: THandle read FEvent;
  end;

  TDnCondition = class
  protected
    FSema:      THandle;
    FWaiters:   Cardinal;
    FLock:      TDnMutex;
  public
    constructor Create;
    destructor Destroy; override;
    procedure  Signal;
    function   WaitFor(Mutex: TDnMutex; TimeOut: Cardinal): TDnWaitResult; overload;
    function   WaitFor(Mutex: TDnMutex): TDnWaitResult; overload;
  end;
      
  TDnSemaphore = class
  protected
    FSemaphore: THandle;
  public
    constructor Create(InitialCount, MaxCount: Integer);
    destructor Destroy; override;
    function  Wait(TimeOut: Cardinal): TDnWaitResult; overload;
    function  Wait: TDnWaitResult; overload;
    procedure Release;

    property Handle: THandle read FSemaphore;
  end;
  
  TDnThread = class;
  TDnThreadContext = class(TObject)
  protected
    FOwnerThread: TDnThread;
  public
    constructor Create(Thread: TDnThread);
    destructor  Destroy; override;
    procedure   Grab;
    procedure   Release;
    property    OwnerThread: TDnThread read FOwnerThread;
  end;

  TDnThread = class (TThread)
  protected
    FContext: TDnThreadContext;
    FRefCount: Integer;
    
    procedure Execute; override;
    procedure CreateContext; virtual; abstract;
    procedure DestroyContext; virtual; abstract;
    procedure ThreadRoutine; virtual; abstract;
    procedure Grab;
    procedure Release;

  public
    constructor Create;
    destructor  Destroy; override;
    procedure   Run;
  end;

  TDnObject = class (TObject, IUnknown)
  protected
    FRefCount: Integer;
  public
    function QueryInterface(const IID: System.TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;

    constructor Create;
    destructor Destroy; override;
  end;

  //just a same layout as Windows'es TSystemTime
  TDnDateRec = record
    Year:         Word;
    Month:        Word;
    DayOfWeek:    Word;
    Day:          Word;
    Hour:         Word;
    Minute:       Word;
    Second:       Word;
    Milliseconds: Word;
  end;

  PSockAddrIn = ^TSockAddrIn;
  
procedure DateTimeToDateRec(DT: TDateTime; var DRec: TDnDateRec);
function  DateRecToDateTime(var DRec: TDnDateRec): TDateTime;


function  GetCurrentContext: TDnThreadContext;
procedure SetCurrentContext(Context: TDnThreadContext);

function  CheckRunningNT4: Boolean;
function  CheckRunning2K: Boolean;
function  CurrentTimeFromLaunch: Cardinal;

function  GetFileSize64(const FileName: String): Int64;

function  IsIPAddress(const S: AnsiString): Boolean;
function  PosExAnsi(SubStr, Str: AnsiString; StartOffset: Integer): Integer;
function  TrimAnsi(Str: AnsiString): AnsiString;
function  PosAnsi(SubStr, Str: AnsiString): Integer;

var PendingRequests: Integer;

implementation
  
var LaunchTime: TDateTime;

threadvar CurrentThread: TDnThread;

function GetCurrentContext: TDnThreadContext;
begin
  if CurrentThread <> Nil then
    Result := CurrentThread.FContext
  else
    Result := Nil;
end;

procedure SetCurrentContext(Context: TDnThreadContext);
begin
  if Context <> Nil then
    CurrentThread := Context.OwnerThread
  else
    CurrentThread := Nil;
end;

function CheckRunningNT4: Boolean;
var ver: Cardinal;
begin
  ver := GetVersion;
  Result := ((ver and $80000000) = 0) and ((ver and $FF) >= 4);
end;

function CheckRunning2K: Boolean;
var ver: Cardinal;
begin
  ver := GetVersion;
  Result := ((ver and $80000000) = 0) and ((ver and $FF) >= 4);
end;

procedure DateTimeToDateRec(DT: TDateTime; var DRec: TDnDateRec);
var PTime: PSystemTime; 
begin
  PTime := PSystemTime(@DRec);
  DateTimeToSystemTime(DT, PTime^);
end;

function  DateRecToDateTime(var DRec: TDnDateRec): TDateTime;
var PTime: PSystemTime;
begin
  PTime := PSystemTime(@DRec);
  Result := SystemTimeToDateTime(PTime^);
end;
//-----------------------------------------------------------------------

constructor EDnException.Create(Code: Integer; SubCode: Integer);
begin
  inherited Create('');
  FErrorCode := Code;
  FErrorSubCode := SubCode;
  FErrorMessage := '';
end;

constructor EDnException.Create(Code: Integer; SubCode: Integer; const Details: String);
begin
  inherited Create('');
  FErrorCode := Code;
  FErrorSubCode := SubCode;
  FErrorMessage := Details;
  Message := 'Error code is ' + IntToStr(Code) + '. Error subcode is ' +
    IntToStr(FErrorSubCode) + '. Details are ' + Details;
end;

destructor  EDnException.Destroy;
begin
  inherited Destroy;
end;

function   EDnException.GetErrorMessage: String;
begin
  Result := DnConst.ExceptionMessages[FErrorCode];
  if FErrorMessage <> '' then
    Result := Result + ' Details are: ' + FErrorMessage;
end;
//-----------------------------------------------------------------------


constructor TDnMutex.Create;
begin
  inherited Create;
  InitializeCriticalSection(FCriticalSection);
end;

destructor TDnMutex.Destroy;
begin
  DeleteCriticalSection(FCriticalSection);
  inherited Destroy;
end;

procedure TDnMutex.Acquire;
begin
  EnterCriticalSection(FCriticalSection);
end;

procedure TDnMutex.Release;
begin
  LeaveCriticalSection(FCriticalSection);
end;

constructor TDnEvent.Create;
begin
  FEvent := CreateEvent(Nil, False, False, Nil);
  if FEvent = 0 then
    raise EDnException.Create(ErrWin32Error, GetLastError(), 'CreateEvent');
end;

destructor TDnEvent.Destroy;
begin
  if FEvent<>0 then
    CloseHandle(FEvent);
  inherited Destroy;
end;

procedure TDnEvent.Pulse;
begin
  PulseEvent(FEvent);
end;

procedure TDnEvent.SetEvent;
begin
  Windows.SetEvent(FEvent);
end;

function TDnEvent.WaitFor(TimeOut: Cardinal): TDnWaitResult;
var ResCode: Cardinal;
begin
  ResCode := WaitForSingleObject(FEvent, TimeOut);
  if ResCode = WAIT_ABANDONED then
    Result := dwrFailed
  else if ResCode = WAIT_OBJECT_0 then
    Result := dwrSignaled
  else if ResCode = WAIT_TIMEOUT then
    Result := dwrTimeOut
  else raise EDnException.Create(ErrWin32Error, GetLastError(), 'WaitForSingleObject');
end;

function TDnEvent.WaitFor: TDnWaitResult;
var ResCode: Cardinal;
begin
  ResCode := WaitForSingleObject(FEvent, INFINITE);
  if ResCode = WAIT_ABANDONED then
    Result := dwrFailed
  else if ResCode = WAIT_OBJECT_0 then
    Result := dwrSignaled
  else if ResCode = WAIT_TIMEOUT then
    Result := dwrTimeOut
  else raise EDnException.Create(ErrWin32Error, GetLastError(), 'WaitForSingleObject');
end;
//--------------------------------------------------------------------------

constructor TDnCondition.Create;
begin
  inherited Create;
  FLock := TDnMutex.Create;
  FSema := CreateSemaphore(Nil, 0, $7FFFFFFF, Nil);
  FWaiters := 0;
end;

destructor TDnCondition.Destroy;
begin
  CloseHandle(FSema); FSema := 0;
  FreeAndNil(FLock);
  inherited Destroy;
end;

procedure  TDnCondition.Signal;
var IsWaiters: Boolean;
begin
  FLock.Acquire;
  IsWaiters := FWaiters > 0;
  FLock.Release;
  if IsWaiters then
    ReleaseSemaphore(FSema, 1, Nil);   
end;

function TDnCondition.WaitFor(Mutex: TDnMutex; TimeOut: Cardinal): TDnWaitResult;
begin
  FLock.Acquire;
  Mutex.Release;
  Inc(FWaiters);

  FLock.Release;
  case WaitForSingleObject(FSema, TimeOut) of
    WAIT_OBJECT_0:
      Result := dwrSignaled;
    WAIT_TIMEOUT:
      Result := dwrTimeout;
    WAIT_ABANDONED:
      Result := dwrFailed;
    else
      Result := dwrFailed;
  end;
  FLock.Acquire;
  Dec(FWaiters);
  FLock.Release;
  Mutex.Acquire;
end;

function TDnCondition.WaitFor(Mutex: TDnMutex): TDnWaitResult;
begin
  Result := Self.WaitFor(Mutex, INFINITE);
end;

//--------------------------------------------------------------------------
constructor TDnSemaphore.Create(InitialCount, MaxCount: Integer);
begin
  inherited Create;
  FSemaphore := CreateSemaphore(Nil, InitialCount, MaxCount, Nil);
  if FSemaphore = 0 then
    raise EDnException.Create(ErrWin32Error, GetLastError(), 'CreateSemaphore');
end;

destructor TDnSemaphore.Destroy;
begin
  if FSemaphore <> 0 then
    CloseHandle(FSemaphore);
  inherited Destroy;
end;

function  TDnSemaphore.Wait(TimeOut: Cardinal): TDnWaitResult;
begin
  case WaitForSingleObject(FSemaphore, TimeOut) of
    WAIT_OBJECT_0:
      Result := dwrSignaled;
    WAIT_ABANDONED:
      Result := dwrFailed;
    WAIT_TIMEOUT:
      Result := dwrTimeOut;
    else
      Result := dwrFailed;
  end;
end;

function  TDnSemaphore.Wait: TDnWaitResult;
begin
  Result := Self.Wait(INFINITE);
end;

procedure TDnSemaphore.Release;
begin
  ReleaseSemaphore(FSemaphore, 1, Nil);
end;
//--------------------------------------------------------------------------

constructor TDnThreadContext.Create(Thread: TDnThread);
begin
  inherited Create;
  FOwnerThread := Thread;
end;

destructor TDnThreadContext.Destroy;
begin
  inherited Destroy;
end;

procedure TDnThreadContext.Grab;
begin
  if FOwnerThread <> Nil then
    FOwnerThread.Grab;
end;

procedure TDnThreadContext.Release;
begin
  if FOwnerThread <> Nil then
    FOwnerThread.Release;
end;
//--------------------------------------------------------------------------

constructor TDnThread.Create;
begin
  inherited Create(True);
  FRefCount := 0;
end;

destructor TDnThread.Destroy;
begin
  inherited Destroy;
end;

procedure TDnThread.Run;
begin
  Self.Resume;
end;

procedure TDnThread.Grab;
begin
  InterlockedIncrement(FRefCount);
end;

procedure TDnThread.Release;
begin
  InterlockedDecrement(FRefCount);
end;

procedure TDnThread.Execute;
begin
  DnRtl.CurrentThread := Nil;
  Self.CreateContext;
  //if FContext <> Nil then
  try
    DnRtl.CurrentThread := Self;
    Self.ThreadRoutine;
  except
    on E: Exception
      do MessageBox(0, PChar(E.Message), Nil, MB_OK);
  end;
  DnRtl.CurrentThread := Nil;
  Self.DestroyContext;
end;
//---------------------------------------------------------------------------

constructor TDnObject.Create;
begin
  inherited Create;
  FRefCount := 1;
end;

destructor TDnObject.Destroy;
begin
  inherited Destroy;
end;

function TDnObject.QueryInterface(const IID: System.TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := E_NOINTERFACE;
end;

function TDnObject._AddRef: Integer;
begin
  Result := InterlockedIncrement(FRefCount);
end;

function TDnObject._Release: Integer;
begin
  Result := InterlockedDecrement(FRefCount);
  if Result = 0 then
    Destroy; //he-he :)
end;

//---------------------------------------------------------------------------
function CurrentTimeFromLaunch: Cardinal;
begin
  Result := Cardinal(trunc((Now - LaunchTime) * 86400 + 0.5));
end;

function GetFileSize64(const FileName: String): Int64;
var FileHandle: THandle;
    ResLo, ResHi: Cardinal;
begin
  FileHandle := CreateFile(PChar(FileName), GENERIC_READ, FILE_SHARE_READ, Nil,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if FileHandle = INVALID_HANDLE_VALUE then
    raise EDnException.Create(ErrWin32Error, GetLastError(), 'CreateFile');
  ResLo := GetFileSize(FileHandle, @ResHi);
  CloseHandle(FileHandle);
  Result := ResLo + (ResHi shl 32);
end;


function  IsIPAddress(const S: AnsiString): Boolean;
begin
  Result := False;
end;

function  PosExAnsi(SubStr, Str: AnsiString; StartOffset: Integer): Integer;
var P, P2: PAnsiChar;
begin
  P := PAnsiChar(Str);
  P := P + StartOffset;

  P2 := AnsiStrPos(P, PAnsiChar(SubStr));
  if P2 <> Nil then
    Result := P2 - P + 1
  else
    Result := 0;
end;

function  TrimAnsi(Str: AnsiString): AnsiString;
var
  I, ResultIndex: Integer;
begin
  SetLength(Result, Length(Str));
  ResultIndex := 1;

  for I := 1 to Length(Str) do
  begin
    if Str[i] <> ' ' then
    begin
      Result[i] := Str[ResultIndex];
      Inc(ResultIndex);
    end;
  end;
  SetLength(Result, ResultIndex-1);
end;

function PosAnsi(SubStr, Str: AnsiString): Integer;
var P: PAnsiChar;
begin
  P := AnsiStrPos(PAnsiChar(Str), PAnsiChar(SubStr));
  if P <> Nil then
    Result := P - PAnsiChar(Str) + 1
  else
    Result := -1;
end;
initialization
  CurrentThread := Nil;
  LaunchTime := Now;
  PendingRequests := 0;
end.
