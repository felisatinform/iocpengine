{$I DnConfig.inc}
{$ifdef USE_3RD_PARTY_LOGGING}
unit DnLogger;

interface

uses
  Classes, SysUtils, DnAbstractLogger
  ,Logging, LogSupport
  ;

type

  TDnLogger = class(TDnAbstractLogger)
  protected
    FLog: TabsLog;

    function  TurnOn: Boolean; override;
    function  TurnOff: Boolean; override;

  public
    constructor Create(AOwner: TComponent; aLog : TabsLog); virtual; reintroduce;
    destructor Destroy; override;
    procedure     LogMsg(Level: TDnLogLevel; const Msg: String); override;
  end;

implementation

constructor TDnLogger.Create(AOwner: TComponent; aLog : TabsLog);
begin
  inherited Create(AOwner);
  FLog := Alog;  // uses, but does not own log
  FActive := True;
end;

destructor TDnLogger.Destroy;
begin
  inherited Destroy;
end;

function  TDnLogger.TurnOn: Boolean;
begin
  Result := assigned(FLog) and FLog.Active;
end;

function  TDnLogger.TurnOff: Boolean;
begin
  Result := False;
end;

procedure  TDnLogger.LogMsg(Level: TDnLogLevel; const Msg: String);
begin
  if not  Active then
    Exit;
  try
    case level of
      llMandatory :
        begin
          FLog.LogError(Msg);
          FLog.LogStackTrace(lvError, Msg);
        end;
      llCritical :
        begin
          FLog.LogError(Msg);
          FLog.LogStackTrace(lvError, Msg);
        end;
      llSerious :
        begin
          FLog.LogWarning(Msg);
          //FLog.LogStackTrace(lvWarning, Msg);
        end;
      llImportant :
        begin
          FLog.LogWarning(Msg);
          //FLog.LogStackTrace(lvWarning, Msg);
        end;
      llPriority :
        begin
          FLog.LogMessage(Msg);
          //FLog.LogStackTrace(lvMessage, Msg);
        end;
      llInformation :
        begin
          FLog.LogVerbose(Msg);
         // FLog.LogStackTrace(lvVerbose, Msg);
        end;
      llLowLevel :
        begin
          FLog.LogDebug(Msg);
          //FLog.LogStackTrace(lvDebug, Msg);
        end;
    end;

  except
  end;

end;
end.
{$else}
unit DnLogger;
interface
implementation
end.
{$endif}
