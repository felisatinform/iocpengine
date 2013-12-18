object FrmTest: TFrmTest
  Left = 0
  Top = 0
  Caption = 'Msg test'
  ClientHeight = 438
  ClientWidth = 483
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -14
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  PixelsPerInch = 120
  TextHeight = 17
  object BtServer: TButton
    Left = 10
    Top = 10
    Width = 99
    Height = 33
    Margins.Left = 4
    Margins.Top = 4
    Margins.Right = 4
    Margins.Bottom = 4
    Caption = 'Start server'
    TabOrder = 0
    OnClick = BtServerClick
  end
  object BtClient: TButton
    Left = 328
    Top = 10
    Width = 98
    Height = 33
    Margins.Left = 4
    Margins.Top = 4
    Margins.Right = 4
    Margins.Bottom = 4
    Caption = 'Start client'
    TabOrder = 1
    OnClick = BtClientClick
  end
  object MmLog: TMemo
    Left = 10
    Top = 51
    Width = 416
    Height = 377
    Margins.Left = 4
    Margins.Top = 4
    Margins.Right = 4
    Margins.Bottom = 4
    ScrollBars = ssVertical
    TabOrder = 2
  end
  object TmrSend: TTimer
    Enabled = False
    Interval = 5000
    OnTimer = TmrSendTimer
    Left = 72
    Top = 104
  end
  object TmrLog: TTimer
    Interval = 20
    OnTimer = TmrLogTimer
    Left = 248
    Top = 216
  end
end
