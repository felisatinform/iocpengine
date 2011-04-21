object FrmTest: TFrmTest
  Left = 0
  Top = 0
  Caption = 'Msg test'
  ClientHeight = 208
  ClientWidth = 273
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
    Left = 32
    Top = 32
    Width = 75
    Height = 25
    Caption = 'Start server'
    TabOrder = 0
    OnClick = BtServerClick
  end
  object BtClient: TButton
    Left = 152
    Top = 32
    Width = 75
    Height = 25
    Caption = 'Start client'
    TabOrder = 1
    OnClick = BtClientClick
  end
  object BtConnect: TButton
    Left = 152
    Top = 72
    Width = 75
    Height = 25
    Caption = 'Connect'
    TabOrder = 2
    OnClick = BtConnectClick
  end
  object BtDisconnect: TButton
    Left = 152
    Top = 112
    Width = 75
    Height = 25
    Caption = 'Disconnect'
    TabOrder = 3
    OnClick = BtDisconnectClick
  end
  object TmrClient: TTimer
    Interval = 20
    OnTimer = TmrClientTimer
    Left = 32
    Top = 112
  end
end
