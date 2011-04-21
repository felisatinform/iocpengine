object FrmGUI: TFrmGUI
  Left = 415
  Top = 200
  BorderStyle = bsDialog
  Caption = 'HTTP server'
  ClientHeight = 68
  ClientWidth = 371
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object Label1: TLabel
    Left = 8
    Top = 16
    Width = 66
    Height = 13
    Caption = 'Listening port:'
  end
  object Label2: TLabel
    Left = 8
    Top = 48
    Width = 60
    Height = 13
    Caption = 'Documents :'
  end
  object EdPort: TEdit
    Left = 80
    Top = 10
    Width = 89
    Height = 21
    TabOrder = 0
    Text = '8082'
  end
  object UDPort: TUpDown
    Left = 169
    Top = 10
    Width = 16
    Height = 21
    Associate = EdPort
    Max = 32767
    Position = 8082
    TabOrder = 1
    Thousands = False
  end
  object EdDocFolder: TEdit
    Left = 80
    Top = 42
    Width = 225
    Height = 21
    TabOrder = 2
    Text = 'Documents'
  end
  object BtStart: TButton
    Left = 200
    Top = 10
    Width = 65
    Height = 25
    Caption = 'Start'
    TabOrder = 3
    OnClick = BtStartClick
  end
  object BtStop: TButton
    Left = 272
    Top = 10
    Width = 65
    Height = 25
    Caption = 'Stop'
    TabOrder = 4
    OnClick = BtStopClick
  end
end
