{$I DnConfig.inc}
unit DnDataDecorator;
interface
uses
  Classes, DnRTL;

{$IFDEF ENABLE_DECORATOR}
type
  TDnDecoratorState = (ddOk, ddFailed);

  TDnDataDecorator = class(TDnObject)
  protected
    function    GetState: TDnDecoratorState; virtual; abstract;
    function    GetErrorCode: Cardinal; virtual; abstract;
    function    GetErrorMsg: String; virtual; abstract;
    
  public
    constructor Create;
    destructor  Destroy; override;

    procedure   Connect; virtual; abstract;
    procedure   SendData(BufPtr: Pointer; BufSize: Integer); overload; virtual; abstract;
    procedure   SendData(Buffer: RawByteString); overload;
    procedure   ReceiveData(BufPtr: Pointer; BufSize: Integer); overload; virtual; abstract;
    procedure   ReceiveData(Buffer: RawByteString); overload;
    procedure   Close; virtual; abstract;

    function    ExtractRawData(MaxSize: Cardinal = $FFFFFFFF): AnsiString; virtual; abstract;
    function    ExtractAppData(MaxSize: Cardinal = $FFFFFFFF): AnsiString; virtual; abstract;
    function    AppDataSize: Cardinal; virtual; abstract;
    function    RawDataSize: Cardinal; virtual; abstract;

    function    ObjectSize: Integer; virtual; abstract;
    
    property    State:      TDnDecoratorState   read GetState;
    property    ErrorCode:  Cardinal            read GetErrorCode;
    property    ErrorMsg:   String              read GetErrorMsg;
  end;
{$ENDIF}

implementation

{$IFDEF ENABLE_DECORATOR}
constructor TDnDataDecorator.Create;
begin
  inherited Create;
end;

destructor TDnDataDecorator.Destroy;
begin
  inherited Destroy;
end;

procedure TDnDataDecorator.SendData(Buffer: RawByteString);
begin
  Self.SendData(@Buffer[1], Length(Buffer));
end;

procedure TDnDataDecorator.ReceiveData(Buffer: RawByteString);
begin
  Self.ReceiveData(@Buffer[1], Length(Buffer));
end;

{$ENDIF}
end.

