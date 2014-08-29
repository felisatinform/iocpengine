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
unit DnTimerEngine;

interface
uses
  Classes, SysUtils, Windows, contnrs,
  DnRtl, DnConst, DnTcpChannel, DnInterfaces,
  DnTcpRequest;
type

  TDnTimerThread = class;

  TDnTimerEngine = class(TComponent)
  protected
    FGuard:           TDnMutex;
    FChannelList:     TObjectList;
    FNewChannelList:  TObjectList;
    FOldChannelList:  TObjectList;
    FTimerSink:       IDnTimerSupport;
    
    FCurrentTact:     Cardinal;
    FThread:          TDnTimerThread;
    FStartTime:       TDateTime;
    FActive:          Boolean;
    
    function  TurnOn: Boolean;
    function  TurnOff: Boolean; 
    procedure SetActive(Value: Boolean);

    procedure UpdateCurrentTact;

  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
    procedure   RequestTimerNotify(Channel: TDnTcpChannel; Tacts: Cardinal;
                                    Key: Pointer);
    procedure   CancelNotify(Channel: TDnTcpChannel);

    property Active: Boolean read FActive write SetActive;
    property TimerSink: IDnTimerSupport read FTimerSink write FTimerSink;
    property CurrentTact: Cardinal read FCurrentTact;
  end;

  TDnTimerThread = class (TDnThread)
  protected
    FTimer: TDnTimerEngine;
    FTerminateSignal: TDnEvent;

    procedure CreateContext; override;
    procedure DestroyContext; override;
    procedure ThreadRoutine; override;
  public
    constructor Create(Timer: TDnTimerEngine);
    destructor  Destroy; override;

    property    TerminateSignal: TDnEvent read FTerminateSignal;
  end;


procedure Register;

implementation


constructor TDnTimerEngine.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCurrentTact := 0;
  FGuard := Nil;
  FChannelList := TObjectList.Create(False);
  FNewChannelList := TObjectList.Create(False);
  FOldChannelList := TObjectList.Create(False);

  FCurrentTact := 0;
  FGuard := TDnMutex.Create;
  FStartTime := Now;

end;

destructor TDnTimerEngine.Destroy;
begin
  SetActive(False);
  FreeAndNil(FChannelList);
  FreeAndNil(FNewChannelList);
  FreeAndNil(FOldChannelList);
  FreeAndNil(FGuard);
  inherited Destroy;
end;
procedure TDnTimerEngine.SetActive(Value: Boolean);
begin
  FGuard.Acquire;
  try
    if not FActive and Value then
      FActive := TurnOn
    else
    if FActive and not Value then
      FActive := TurnOff;
  finally
    FGuard.Release;
  end;
end;

function TDnTimerEngine.TurnOn;
begin
  //create the list
  FThread := TDnTimerThread.Create(Self);
  FThread.Priority := tpNormal;
  FThread.Resume;
  UpdateCurrentTact();
  Result := True;
end;

function TDnTimerEngine.TurnOff;
begin
  //inherited TurnOff;
  if FThread <> Nil then
  begin
    FThread.Terminate;
    FThread.TerminateSignal.SetEvent;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;

  ClearChannelList(FChannelList);   
  ClearChannelList(FNewChannelList);
  ClearChannelList(FOldChannelList);

  Result := False;
end;

procedure TDnTimerEngine.RequestTimerNotify(Channel: TDnTcpChannel; Tacts: Cardinal; Key: Pointer);
begin
  if Tacts = 0 then
  begin
    CancelNotify(Channel);
    Exit;
  end;
  
  //grab the channel
  Channel.AddRef(rtTimerEngine);

  //set the timeout ticks
  Channel.TimeoutTact := FCurrentTact + Tacts;

  //add the channel to list
  try
    FGuard.Acquire;

    try
      FNewChannelList.Add(Channel);
    except
      Channel.Release(rtTimerEngine);
    end;

  finally
    FGuard.Release;
  end;
end;

procedure TDnTimerEngine.CancelNotify(Channel: TDnTcpChannel);
begin
  try
    FGuard.Acquire;

    if (FChannelList.IndexOf(Channel) <> -1) and (FNewChannelList.IndexOf(Channel) <> -1) then
      FOldChannelList.Add(Channel);
  finally
    FGuard.Release;
  end;
end;

procedure TDnTimerEngine.UpdateCurrentTact;
var
  DiffTime: TDateTime;
begin
  DiffTime := Now - FStartTime;
  FCurrentTact := Trunc(DiffTime * 86400 + 0.5);
end;

procedure Register;
begin
  RegisterComponents('DNet', [TDnTimerEngine]);
end;

//----------------------------------------------------------------------
constructor TDnTimerThread.Create(Timer: TDnTimerEngine);
begin
  inherited Create;
  FTimer := Timer;
  FTerminateSignal := TDnEvent.Create;
end;

destructor TDnTimerThread.Destroy;
begin
  FTimer := Nil;
  FreeAndNil(FTerminateSignal);
  inherited Destroy;
end;

procedure TDnTimerThread.CreateContext;
begin
end;

procedure TDnTimerThread.DestroyContext;
begin
end;


procedure TDnTimerThread.ThreadRoutine;
var Channel: TDnTcpChannel;
    NewSize, i: Integer;
begin
  with FTimer do
  begin
    while not Terminated and (FTerminateSignal.WaitFor(0) = dwrTimeOut) do
    begin
      UpdateCurrentTact();

      //iterate the list
      i := 0;
      while i<FChannelList.Count do
      begin
        //extract channel pointer
        Channel := TDnTcpChannel(FChannelList[i]);

        //check if the time for timer message
        if Channel.TimeoutTact <= FCurrentTact then
        begin //signal channel
          //send user-defined IOCP signal
          Channel.TimeoutTact := FCurrentTact + Channel.Timeout;

          //post timer message
          FTimerSink.PostTimerMessage(Channel);

          //remove from timer list
          FChannelList.Extract(Channel);

          //dereference channel - NOT HERE! It will be done on timer message receiving
          //Channel.Release(rtTimerEngine);
        end
        else
          Inc(i);
          
      end;

      FGuard.Acquire;
      try
        NewSize := FChannelList.Capacity + FNewChannelList.Count + FOldChannelList.Count;
        if NewSize < FChannelList.Capacity then
          FChannelList.Capacity := NewSize * 2;

        //process newly added channels
        for i:=0 to FNewChannelList.Count-1 do
          FChannelList.Add(FNewChannelList[i]);

        //process cancelled channels
        for i:=0 to FOldChannelList.Count-1 do
          (TDnTcpChannel(FChannelList.Extract(FOldChannelList[i]))).Release(rtTimerEngine);

        FNewChannelList.Clear; FOldChannelList.Clear;
      finally
        FGuard.Release;
      end;

      Windows.Sleep(1);
    end;
  end;
end;

end.
