object FrmTest: TFrmTest
  Left = 390
  Top = 282
  Width = 511
  Height = 470
  Caption = 'Msg test'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -14
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 120
  TextHeight = 17
  object BtServer: TButton
    Left = 10
    Top = 10
    Width = 99
    Height = 33
    Caption = 'Start server'
    TabOrder = 0
    OnClick = BtServerClick
  end
  object BtClient: TButton
    Left = 328
    Top = 10
    Width = 98
    Height = 33
    Caption = 'Start client'
    TabOrder = 1
    OnClick = BtClientClick
  end
  object MmLog: TMemo
    Left = 10
    Top = 51
    Width = 416
    Height = 377
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
