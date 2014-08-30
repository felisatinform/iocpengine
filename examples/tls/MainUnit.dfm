object FrmMain: TFrmMain
  Left = 0
  Top = 0
  Caption = 'TLS demo'
  ClientHeight = 431
  ClientWidth = 472
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 120
  TextHeight = 16
  object Label1: TLabel
    Left = 8
    Top = 16
    Width = 45
    Height = 16
    Caption = 'Host IP:'
  end
  object EdHostIp: TEdit
    Left = 127
    Top = 13
    Width = 234
    Height = 24
    TabOrder = 0
    Text = '37.139.30.183:5061'
  end
  object BtConnect: TButton
    Left = 367
    Top = 13
    Width = 98
    Height = 25
    Caption = 'Connect'
    TabOrder = 1
    OnClick = BtConnectClick
  end
  object MmLog: TMemo
    Left = 8
    Top = 44
    Width = 457
    Height = 379
    TabOrder = 2
  end
end
