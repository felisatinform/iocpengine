object HttpProcessor: THttpProcessor
  OldCreateOrder = False
  OnDestroy = DataModuleDestroy
  Height = 150
  Width = 215
  object Server: TDnHttpServer
    Port = 7080
    IP = '0.0.0.0'
    Active = False
    Threads = 4
    KeepAliveTime = 5
    OnRequest = ServerRequest
    OnTimeToSend = ServerTimeToSend
    OnLog = ServerLog
    Left = 32
    Top = 48
  end
end
