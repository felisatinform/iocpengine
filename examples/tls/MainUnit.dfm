object FrmMain: TFrmMain
  Left = 0
  Top = 0
  BorderStyle = bsSingle
  Caption = 'TLS demo'
  ClientHeight = 437
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
    Left = 7
    Top = 42
    Width = 99
    Height = 16
    Caption = 'TLS client target:'
  end
  object Label2: TLabel
    Left = 8
    Top = 8
    Width = 142
    Height = 16
    Caption = 'TLS server port number:'
  end
  object EdHostIp: TEdit
    Left = 156
    Top = 39
    Width = 173
    Height = 24
    TabOrder = 0
    Text = '192.168.12.134:10273'
  end
  object BtStartClient: TButton
    Left = 335
    Top = 39
    Width = 129
    Height = 25
    Caption = 'Start client'
    TabOrder = 1
    OnClick = BtStartClientClick
  end
  object MmLog: TMemo
    Left = 0
    Top = 70
    Width = 472
    Height = 367
    Align = alBottom
    Anchors = [akLeft, akTop, akRight, akBottom]
    ScrollBars = ssBoth
    TabOrder = 2
  end
  object EdServerPortNumber: TEdit
    Left = 156
    Top = 8
    Width = 173
    Height = 24
    TabOrder = 3
    Text = '10273'
  end
  object BtStartServer: TButton
    Left = 335
    Top = 8
    Width = 129
    Height = 25
    Caption = 'Start server'
    TabOrder = 4
    OnClick = BtStartServerClick
  end
end
