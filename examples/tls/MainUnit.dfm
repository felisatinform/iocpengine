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
    Text = '37.139.30.183:443'
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
    Left = 0
    Top = 40
    Width = 472
    Height = 391
    Align = alBottom
    Anchors = [akLeft, akTop, akRight, akBottom]
    ScrollBars = ssBoth
    TabOrder = 2
    ExplicitLeft = 8
    ExplicitTop = 49
    ExplicitWidth = 473
  end
end
