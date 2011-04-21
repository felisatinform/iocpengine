object HttpEngine: THttpEngine
  OldCreateOrder = False
  Height = 399
  Width = 284
  object TcpListener: TDnTcpListener
    Active = False
    Port = 7080
    Address = '0.0.0.0'
    UseNagle = True
    BackLog = 5
    Reactor = TcpReactor
    Executor = SimpleExecutor
    Logger = FileLogger
    LogLevel = llMandatory
    KeepAlive = False
    OnIncoming = TcpListenerIncoming
    Left = 32
    Top = 24
  end
  object TcpReactor: TDnTcpReactor
    Active = False
    Executor = SimpleExecutor
    Logger = FileLogger
    LogLevel = llMandatory
    ThreadSize = 8
    Left = 32
    Top = 88
  end
  object HttpRequestor: TDnHttpRequestor
    Reactor = TcpReactor
    LogLevel = llMandatory
    Logger = FileLogger
    Executor = SimpleExecutor
    Active = False
    OnHttpHeader = HttpRequestorHttpHeader
    OnTcpError = HttpRequestorTcpError
    OnTcpClientClose = HttpRequestorTcpClientClose
    Left = 32
    Top = 152
  end
  object SimpleExecutor: TDnSimpleExecutor
    Logger = FileLogger
    LogLevel = llMandatory
    Active = False
    Left = 128
    Top = 24
  end
  object WinSockMgr: TDnWinSockMgr
    Active = False
    Left = 120
    Top = 152
  end
  object TcpRequestor: TDnTcpRequestor
    Reactor = TcpReactor
    LogLevel = llMandatory
    Logger = FileLogger
    Executor = SimpleExecutor
    Active = False
    OnWrite = TcpRequestorWrite
    OnClose = TcpRequestorClose
    Left = 32
    Top = 208
  end
  object FileSender: TDnTcpFileWriter
    Reactor = TcpReactor
    LogLevel = llMandatory
    Logger = FileLogger
    Executor = SimpleExecutor
    Active = False
    OnFileWritten = FileSenderFileWritten
    Left = 120
    Top = 208
  end
  object FileLogger: TDnFileCachedLogger
    ShowProcessId = False
    ProcessIdWidth = 5
    ShowThreadId = False
    ThreadIdWidth = 5
    ShowDateTime = True
    DateTimeFormat = 'ss.nn.hh mm.dd.yyyy'
    MinLevel = llMandatory
    Active = False
    FileName = 'Log.txt'
    RewriteLog = True
    FlushInterval = 5000
    FlushSize = 102400
    Left = 32
    Top = 264
  end
end
