object FrmTest: TFrmTest
  Left = 0
  Top = 0
  Caption = 'Msg test'
  ClientHeight = 335
  ClientWidth = 335
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object BtServer: TButton
    Left = 8
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Start server'
    TabOrder = 0
    OnClick = BtServerClick
  end
  object BtClient: TButton
    Left = 251
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Start client'
    TabOrder = 1
    OnClick = BtClientClick
  end
  object MmLog: TMemo
    Left = 8
    Top = 39
    Width = 318
    Height = 288
    TabOrder = 2
  end
  object TmrClient: TTimer
    Interval = 20
    OnTimer = TmrClientTimer
    Left = 200
    Top = 80
  end
  object TmrSend: TTimer
    Interval = 20
    OnTimer = TmrSendTimer
    Left = 72
    Top = 104
  end
end
