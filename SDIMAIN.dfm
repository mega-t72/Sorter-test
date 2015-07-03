object SDIAppForm: TSDIAppForm
  Left = 197
  Top = 111
  Caption = #1055#1088#1086#1075#1088#1072#1084#1084#1072' '#1076#1083#1103' '#1089#1086#1088#1090#1080#1088#1086#1074#1082#1080' '#1089#1090#1088#1086#1082
  ClientHeight = 108
  ClientWidth = 437
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'System'
  Font.Style = []
  Menu = MainMenu1
  OldCreateOrder = False
  Position = poScreenCenter
  OnClose = FormClose
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 16
  object Label2: TLabel
    Left = 14
    Top = 4
    Width = 113
    Height = 16
    Caption = #1048#1089#1093#1086#1076#1085#1099#1081' '#1092#1072#1081#1083':'
  end
  object Label3: TLabel
    Left = 14
    Top = 29
    Width = 111
    Height = 16
    Caption = #1050#1086#1085#1077#1095#1085#1099#1081' '#1092#1072#1081#1083':'
  end
  object StatusBar: TStatusBar
    Left = 0
    Top = 89
    Width = 437
    Height = 19
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    AutoHint = True
    Panels = <
      item
        Width = 200
      end
      item
        Alignment = taRightJustify
        Width = 50
      end>
    SizeGrip = False
    ExplicitTop = 176
    ExplicitWidth = 326
  end
  object Button2: TButton
    Left = 409
    Top = 0
    Width = 25
    Height = 26
    Action = ActionOpen
    Caption = '...'
    TabOrder = 1
  end
  object EditSrc: TEdit
    Left = 128
    Top = 1
    Width = 281
    Height = 24
    Color = clBtnFace
    ReadOnly = True
    TabOrder = 4
  end
  object EditDst: TEdit
    Left = 128
    Top = 26
    Width = 281
    Height = 24
    Color = clBtnFace
    ReadOnly = True
    TabOrder = 5
  end
  object Button3: TButton
    Left = 8
    Top = 56
    Width = 121
    Height = 25
    Action = ActionSort
    TabOrder = 3
  end
  object Button4: TButton
    Left = 409
    Top = 25
    Width = 25
    Height = 26
    Action = ActionSave
    Caption = '...'
    TabOrder = 2
  end
  object MainMenu1: TMainMenu
    Left = 176
    Top = 56
    object File1: TMenuItem
      Caption = '&'#1060#1072#1081#1083
      object FileOpenItem: TMenuItem
        Action = ActionOpen
        Hint = #1054#1090#1082#1088#1099#1090#1100'|'#1059#1082#1072#1079#1072#1090#1100' '#1080#1089#1093#1086#1076#1085#1099#1081' '#1092#1072#1081#1083
      end
      object N2: TMenuItem
        Action = ActionSave
        Hint = #1057#1086#1093#1088#1072#1085#1080#1090#1100'|'#1059#1082#1072#1079#1072#1090#1100' '#1082#1086#1085#1077#1095#1085#1099#1081' '#1092#1072#1081#1083
      end
      object N3: TMenuItem
        Caption = '-'
      end
      object N4: TMenuItem
        Action = ActionGenerate
        Hint = #1043#1077#1085#1077#1088#1072#1094#1080#1103' '#1092#1072#1081#1083#1072'|'#1057#1075#1077#1085#1077#1088#1080#1088#1086#1074#1072#1090#1100' '#1090#1077#1082#1089#1090#1086#1074#1099#1081' '#1092#1072#1081#1083
      end
      object N5: TMenuItem
        Action = ActionSort
        Hint = #1057#1086#1088#1090#1080#1088#1086#1074#1082#1072'|'#1054#1090#1089#1086#1088#1090#1080#1088#1086#1074#1072#1090#1100' '#1080#1089#1093#1086#1076#1085#1099#1081' '#1092#1072#1081#1083
      end
      object N1: TMenuItem
        Caption = '-'
      end
      object FileExitItem: TMenuItem
        Caption = #1042'&'#1099#1093#1086#1076
        Hint = #1042#1099#1093#1086#1076'|'#1042#1099#1093#1086#1076' '#1080#1079' '#1087#1088#1086#1075#1088#1072#1084#1084#1099
        OnClick = FileExit1Execute
      end
    end
    object Help1: TMenuItem
      Caption = '&'#1057#1087#1088#1072#1074#1082#1072
      object HelpAboutItem: TMenuItem
        Action = ActionAbout
        Hint = #1054' '#1087#1088#1086#1075#1088#1072#1084#1084#1077
      end
    end
  end
  object ActionList1: TActionList
    Left = 208
    Top = 56
    object ActionOpen: TAction
      Caption = #1054#1090#1082#1088#1099#1090#1100'...'
      OnExecute = ActionOpenExecute
    end
    object ActionSave: TAction
      Caption = #1057#1086#1093#1088#1072#1085#1080#1090#1100'...'
      OnExecute = ActionSaveExecute
    end
    object ActionSort: TAction
      Caption = #1057#1086#1088#1090#1080#1088#1086#1074#1072#1090#1100
      Enabled = False
      OnExecute = ActionSortExecute
    end
    object ActionGenerate: TAction
      Caption = #1043#1077#1085#1077#1088#1080#1088#1086#1074#1072#1090#1100
      Enabled = False
      OnExecute = ActionGenerateExecute
    end
    object ActionAbout: TAction
      Caption = #1054' '#1087#1088#1086#1075#1088#1072#1084#1084#1077'...'
      OnExecute = ActionAboutExecute
    end
  end
  object OpenDialog: TOpenDialog
    DefaultExt = 'txt'
    Filter = '*.txt|*.txt|All Files (*.*)|*.*'
    Left = 240
    Top = 56
  end
  object SaveDialog: TSaveDialog
    DefaultExt = 'txt'
    Filter = '*.txt|*.txt|All Files (*.*)|*.*'
    Left = 272
    Top = 56
  end
end
