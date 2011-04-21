{$I DnConfig.inc}
unit DnDnsRequestor;
interface
uses
  Classes, SysUtils, Types, Contnrs, Winsock2, Windows,
  DnRtl, DnTcpAbstractRequestor;

type
  //This event occurs when resolving result is known
  TDnDnsResolveEvent = procedure (const HostName: String; const IPAddress: String; ErrorCode: Integer; UserData: Pointer) of object;

  //This helper class wraps DNS resolve request information and callback to get the result
  TDnDnsResolveRequest = class (TObject)
  protected
    FHostName:    String;
    FUserData:    Pointer;
    FHandler:     TDnDnsResolveEvent;
    FErrorCode:   Integer;
    FIP:          String;

  public
    constructor   Create(const HostName: String; UserData: Pointer; Handler: TDnDnsResolveEvent);
    destructor    Destroy; override;
    procedure     RunHandler;

    property HostName:  String read FHostName write FHostName;
    property UserData:  Pointer read FUserData write FUserData;
    property Handler:   TDnDnsResolveEvent read FHandler write FHandler;
    property ErrorCode: Integer read FErrorCode write FErrorCode;
    property IP: String read FIP write FIP;
  end;

  TDnDnsThread = class(TThread)
  protected
    FSuperNode:     TObject;
    FGuard:         TDnMutex;
    FRequestList:   TObjectList;
    FRequestSem:    TDnSemaphore;
    FExitEvent:     TDnEvent;

    procedure Execute; override;
    procedure Finalize;
  public
    constructor Create(SuperNode: TObject);
    destructor  Destroy; override;

    procedure   Stop;
    procedure   StartResolve(const HostName: AnsiString; UserData: Pointer; CompleteHandler: TDnDnsResolveEvent);
  end;

  TDnDnsRequestor = class(TDnTcpAbstractRequestor)
  protected
    FOnResolved:  TDnDNSResolveEvent;
    FThread:      TDnDNSThread;
    
    function TurnOn: Boolean; override;
    function TurnOff: Boolean; override;

  public
    constructor Create{$IFDEF ROOT_IS_COMPONENT}(AOwner: TComponent); override {$ENDIF};
    destructor  Destroy; override;

    //This method STARTS the resolving of host name
    procedure   Resolve(const HostName: String; UserData: Pointer; Handler: TDnDNSResolveEvent = Nil);

    class function
                IsIPAddress(const S: AnsiString): Boolean;
                
    property    OnResolved: TDnDNSResolveEvent read FOnResolved write FOnResolved;
  end;
  

implementation

//------------- TDNSThreadRequest ---------
constructor TDnDnsResolveRequest.Create(const HostName: String; UserData: Pointer; Handler: TDnDnsResolveEvent);
begin
  inherited Create;
  FHostName := HostName;
  FUserData := UserData;
  FHandler := Handler;
end;

destructor TDnDnsResolveRequest.Destroy;
begin
  inherited Destroy;
end;

procedure TDnDnsResolveRequest.RunHandler;
begin
  try
    FHandler(FHostName, FIP, FErrorCode, FUserData);
  except
  end;
end;

//------------- TDNSThread ----------------
constructor TDnDnsThread.Create(SuperNode: TObject);
begin
  inherited Create(True);
  FGuard := TDnMutex.Create;
  FSuperNode := SuperNode;
  FRequestList := TObjectList.Create;
  FRequestSem := TDnSemaphore.Create(0, $7FFFFFFF);
  FExitEvent := TDnEvent.Create;
  FreeOnTerminate := False;
end;

destructor TDnDnsThread.Destroy;
begin
  if Assigned(FRequestList) then
    FRequestList.Free;
  if Assigned(FRequestSem) then
    FRequestSem.Free;
  if Assigned(FExitEvent) then
    FExitEvent.Free;
  if Assigned(FGuard) then
    FGuard.Free;

  inherited Destroy;
end;

procedure  TDnDnsThread.Stop;
begin
  Self.Terminate;
  FExitEvent.SetEvent;
end;

procedure TDnDnsThread.StartResolve(const HostName: String; UserData: Pointer; CompleteHandler: TDnDnsResolveEvent);
begin
  FGuard.Acquire;
  try
    FRequestList.Add(TDnDnsResolveRequest.Create(HostName, UserData, CompleteHandler));
    FRequestSem.Release;
  finally
    FGuard.Release;
  end;
end;

procedure TDnDnsThread.Execute;
var Handles:    array[0..1] of THandle;
    ResCode:    Integer;
    HostEnt:    PHostEnt;
    Request:    TDnDnsResolveRequest;
    PA:         PAnsiChar;
    SockAddr:   TSockAddrIn;
begin
  Handles[0] := FExitEvent.Handle;
  Handles[1] := FRequestSem.Handle;

  while not Terminated do
  begin
    //wait on semaphore&exit event
    ResCode := Windows.WaitForMultipleObjects(2, @Handles, False, INFINITE);

    //if there is signal to terminate - exit from thread
    if ResCode = Windows.WAIT_OBJECT_0 then
    begin
      Finalize;
      Exit;
    end;

    //if there is signal about new request - handle it
    if ResCode = Windows.WAIT_OBJECT_0 + 1 then
    begin
      FGuard.Acquire;

      //got new DNS request
      try
        Request := TDnDnsResolveRequest(FRequestList[0]);
        FRequestList.Delete(0);
      finally
        FGuard.Release;
      end;

      HostEnt := Winsock2.gethostbyname(PAnsiChar(AnsiString(Request.HostName)));
      if HostEnt = Nil then
        Request.ErrorCode := Winsock2.WSAGetLastError
      else
      begin
      //copy resulting IP address
        PA := PAnsiChar(HostEnt^.h_addr_list^);
        SockAddr.sin_addr.S_un_b.s_b1 := Ord(pa[0]);
        SockAddr.sin_addr.S_un_b.s_b2 := Ord(pa[1]);
        SockAddr.sin_addr.S_un_b.s_b3 := Ord(pa[2]);
        SockAddr.sin_addr.S_un_b.s_b4 := Ord(pa[3]);
        Request.FIP := Winsock2.inet_ntoa(SockAddr.sin_addr);
      end;

      //fire event
      Request.RunHandler;
      Request.Free;
    end; // WAIT_OBJECT_0 + 1
  end; //while not terminated
end;

procedure TDnDnsThread.Finalize;
var
    i: Integer;
begin
  FGuard.Acquire;
  try
    for i:=0 to FRequestList.Count-1 do
      TDnDnsResolveRequest(FRequestList[i]).RunHandler;


  finally
    FGuard.Release;
  end;
end;

//--------------------- TDnDnsRequestor -----------------------
constructor TDnDnsRequestor.Create{$IFDEF ROOT_IS_COMPONENT}(AOwner: TComponent){$ENDIF};
begin
  inherited Create{$IFDEF ROOT_IS_COMPONENT}(AOwner){$ENDIF};
end;

destructor TDnDnsRequestor.Destroy;
begin
  TurnOff;
  inherited Destroy;
end;

function TDnDnsRequestor.TurnOn: Boolean;
begin
  FThread := TDnDNSThread.Create(Nil);
  FThread.Resume;
  Result := True;
end;

function TDnDnsRequestor.TurnOff: Boolean;
begin
  Result := False;
  if Assigned(FThread) then
  begin
    FThread.Stop;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
end;

procedure  TDnDnsRequestor.Resolve(const HostName: String; UserData: Pointer; Handler: TDnDNSResolveEvent = Nil);
begin
  if not CheckAvail then
    Exit;
  if @Handler = Nil then
    Handler := FOnResolved;

  FThread.StartResolve(HostName, UserData, Handler);
end;

class function TDnDnsRequestor.IsIPAddress(const S: AnsiString): Boolean;
var Addr: Winsock2.TInAddr;
begin
  Addr.S_addr := Winsock2.inet_addr(PChar(S));
  Result :=  Addr.S_addr <> Winsock2.INADDR_NONE;
end;

end.
