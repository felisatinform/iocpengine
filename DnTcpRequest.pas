unit DnTcpRequest;
interface
uses Winsock2, Windows, Classes, SysUtils,
      DnRtl, DnConst;

const
  GDnIORequestType: array [0..15] of String =
    ('Read', 'Write', 'Connect', 'Close', ' BrutalClose', 'ReadWrite', 'Accept', 'TimerEngine', 'ChannelList', 'ClientList',
    'TimeoutEvent', 'None', 'User', 'UserMessage', 'Pool', 'NodeGate');

type
  //This interface is operable for TDnTcpReactor
  TDnIORequestType = (rtRead, rtWrite, rtConnect, rtClose, rtBrutalClose, rtReadWrite,
    rtAccept, rtTimerEngine, rtChannelList, rtClientList, rtTimeoutEvent, rtNone, rtUser,
    rtUserMessage, rtPool, rtNodeGate);

  TDnReqContext = record
    FOverlapped:  TOverlapped;
    FRequest:     Pointer;
  end;

  PDnReqContext = ^TDnReqContext;

  TDnTcpRequest = class(TDnObject)
  protected
    FChannel:     TObject;
    FContext:     TDnReqContext;
    FKey:         Pointer;
    FStartBuffer: Pointer;
    FTotalSize:   Cardinal;
    FErrorCode:   Cardinal;
    FRTContext:   TDnThreadContext;
    FRefCount:    Integer;
    FRunning:     Boolean;
    FID:          Integer;
   public
    procedure PostError(ErrorCode: Integer; WasRead: Cardinal);
    procedure CatchError;

    procedure Execute; virtual;
    function  IsComplete: Boolean; virtual;
    procedure ReExecute; virtual; abstract;
    function  RequestType: TDnIORequestType; virtual; abstract;
    function  IsPureSignal: Boolean; virtual;

    //IDnIOResponse
    procedure CallHandler(Context: TDnThreadContext); virtual; abstract;

    procedure SetTransferred(Transferred: Cardinal); virtual; abstract;
    procedure Cancel;
    procedure AddRef;
    procedure Release;

    constructor Create(Channel: TObject; Key: Pointer);
    destructor Destroy; override;

    property ErrorCode: Cardinal read FErrorCode write FErrorCode;
    property Channel: TObject read FChannel write FChannel;
    property Running: Boolean read FRunning;
  end;

implementation
uses DnTcpChannel, DnTcpReactor;
var
  GRequestCreated, GRequestFreed: Integer;
  GIDCounter: Integer;
  
constructor TDnTcpRequest.Create(Channel: TObject; Key: Pointer);
begin
  inherited Create;
  FChannel := Channel;
  FTotalSize := 0;
  FStartBuffer := Nil;
  FRefCount := 0;
  FKey := Key;
  FErrorCode := 0;
  FRTContext := Nil;
  FID := InterlockedIncrement(GIDCounter);
  if Channel <> Nil then
    TDnTcpChannel(Channel).AddRef(Self.RequestType);

  InterlockedIncrement(GRequestCreated);
end;

destructor TDnTcpRequest.Destroy;
begin
  (*if (FRefCount <> 0) and (RequestType <> rtAccept) then
    DebugBreak; *)

  //dereference channel
  if FChannel <> Nil then
    TDnTcpChannel(FChannel).Release(Self.RequestType);

  InterlockedIncrement(GRequestFreed);

  inherited Destroy;
end;

function  TDnTcpRequest.IsPureSignal: Boolean;
begin
  Result := False;
end;

procedure TDnTcpRequest.AddRef;
begin
  Windows.InterlockedIncrement(FRefCount);
end;

procedure TDnTcpRequest.Release;
begin
  Windows.InterlockedDecrement(FRefCount);
end;

procedure TDnTcpRequest.Cancel;
begin
  Self.FContext.FRequest := Nil;
end;

procedure TDnTcpRequest.PostError(ErrorCode: Integer; WasRead: Cardinal);
var ChannelImpl: TDnTcpChannel;
begin
  FErrorCode := ErrorCode;
  ChannelImpl := FChannel as TDnTcpChannel;

  if LongBool(PostQueuedCompletionStatus( (ChannelImpl.Reactor as TDnTcpReactor).PortHandle, WasRead,
                                Cardinal(Pointer(FChannel)), @FContext )) = False
  then
    raise EDnException.Create(ErrWin32Error, GetLastError(), 'PostQueuedCompletionStatus');
end;

procedure TDnTcpRequest.Execute;
begin
  FErrorCode := 0;
  FillChar(FContext.FOverlapped, SizeOf(FContext.FOverlapped), 0);
  FContext.FRequest := Self;
  FRunning := True;
end;

function  TDnTcpRequest.IsComplete: Boolean;
begin
  Result := False;
end;


procedure TDnTcpRequest.CatchError;
begin
  FErrorCode := GetLastError;
end;

end.
