unit SDIMAIN;

interface

uses Winapi.Windows, System.Classes, Vcl.Graphics, Vcl.Forms, Vcl.Controls,
  Vcl.Menus, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Buttons, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.ImgList, Vcl.StdActns, Vcl.ActnList, Vcl.ToolWin, System.Actions,
  UnitPartSortThread, UnitMergeThread, UnitTranslateThread, UnitCommon;

type

  TState  = ( sNone, sSort, sMerge, sTranslate );

  TSDIAppForm = class(TForm)
    OpenDialog: TOpenDialog;
    SaveDialog: TSaveDialog;
    ActionList1: TActionList;
    StatusBar: TStatusBar;
    MainMenu1: TMainMenu;
    File1: TMenuItem;
    FileOpenItem: TMenuItem;
    N1: TMenuItem;
    FileExitItem: TMenuItem;
    Help1: TMenuItem;
    HelpAboutItem: TMenuItem;
    Button2: TButton;
    ActionAbout: TAction;
    ActionGenerate: TAction;
    ActionOpen: TAction;
    Label2: TLabel;
    EditSrc: TEdit;
    Label3: TLabel;
    EditDst: TEdit;
    ActionSave: TAction;
    Button3: TButton;
    ActionSort: TAction;
    Button4: TButton;
    N2: TMenuItem;
    N3: TMenuItem;
    N4: TMenuItem;
    N5: TMenuItem;
    procedure FileExit1Execute(Sender: TObject);
    procedure ActionAboutExecute(Sender: TObject);
    procedure ActionOpenExecute(Sender: TObject);
    procedure ActionSaveExecute(Sender: TObject);
    procedure ActionGenerateExecute(Sender: TObject);
    procedure ActionSortExecute(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    m_SortThreads     : array [0..3] of TPartSortThread;  //  потоки сортировки
    m_MergeThreads    : array [0..3] of TMergeThread;     //  потоки слияния
    m_TranslateThread : TTranslateThread;                 //  поток трансляции
    m_pBuffer         : Pointer;                          //  рабочий буфер
    m_Results         : Integer;                          //  число частично упорядоченных п-тей
    m_ResultsOffset   : UInt64;                           //  смещение частично упорядоченных п-тей в целевом файле
    m_ResultsSize     : UInt64;                           //  объем частично упорядоченных п-тей
    m_ReduceOffset    : UInt64;                           //  смещение упорядоченной последовательности для трансляции
    m_hDstLock        : THandle;                          //  мьютекс, защищающий доступ к целевому файлу
    m_hSrcLock        : THandle;                          //  мьютекс, защищающий доступ к исходному файлу
    m_hFile           : THandle;                          //  дескриптор исходного файла
    m_hDstFile        : THandle;                          //  дескриптор целевого файла
    m_Running         : Integer;                          //  общее число выполняющихся потоков
    m_State           : TState;                           //  состояние задачи
    m_StartTime       : Cardinal;                         //  время запуска задачи
    m_LastOutputTime  : Cardinal;                         //  время последней операции обновления статуса программы
  public
    function Sort( const Src, Dst: String ): Boolean;
    procedure Merge;
    procedure Translate;
    procedure NextState;
    procedure UpdateStatus;
    function Generate( const FileName: String; MbSize: Cardinal ):Boolean;
  end;

var
  SDIAppForm: TSDIAppForm;

implementation

uses System.SysUtils, System.UITypes, About;

{$R *.dfm}

procedure TSDIAppForm.ActionAboutExecute(Sender: TObject);
begin
  AboutBox.ShowModal;
end;

procedure TSDIAppForm.ActionGenerateExecute(Sender: TObject);
var Size: String;
begin
  if Length( EditDst.Text ) > 0 then
    begin
      Size  := InputBox(
        'Введите размер генерируемого файла (Мб)', 'Размер (Мб):', ''
      );
      if Size <> '' then
        if Generate( EditDst.Text, StrToInt( Size ) ) then
          MessageDlg( 'Файл успешно сгенерирован!', mtInformation, [mbOK], 0 )
        else
          MessageDlg(
            'Во время генерации файла произошла ошибка!', mtError, [mbOK], 0
          );
    end;
end;

procedure TSDIAppForm.ActionOpenExecute(Sender: TObject);
begin
  if OpenDialog.Execute then
    begin
      ActionSort.Enabled  := Length( EditDst.Text ) > 0;
      EditSrc.Text        := OpenDialog.FileName;
    end;
end;

procedure TSDIAppForm.ActionSaveExecute(Sender: TObject);
begin
  if SaveDialog.Execute then
    begin
      ActionGenerate.Enabled  := True;
      ActionSort.Enabled      := Length( EditSrc.Text ) > 0;
      EditDst.Text            := SaveDialog.FileName;
    end;
end;

procedure TSDIAppForm.ActionSortExecute(Sender: TObject);
begin
  if m_State = sNone then
    if ( Length( EditSrc.Text ) > 0 ) and ( Length( EditDst.Text ) > 0 ) then
      NextState;
end;

procedure TSDIAppForm.FileExit1Execute(Sender: TObject);
begin
  Close;
end;

procedure TSDIAppForm.FormClose(Sender: TObject; var Action: TCloseAction);
var i: Integer;
begin
  StatusBar.Panels[0].Text  := 'Завершение программы...';
  Application.ProcessMessages;
  //  завершение потоков
  for i := Low( m_SortThreads ) to High( m_SortThreads ) do m_SortThreads[i].Abort;
  for i := Low( m_SortThreads ) to High( m_SortThreads ) do m_SortThreads[i].WaitFor;
  for i := Low( m_SortThreads ) to High( m_SortThreads ) do m_SortThreads[i].Free;

  for i := Low( m_MergeThreads ) to High( m_MergeThreads ) do m_MergeThreads[i].Abort;
  for i := Low( m_MergeThreads ) to High( m_MergeThreads ) do m_MergeThreads[i].WaitFor;
  for i := Low( m_MergeThreads ) to High( m_MergeThreads ) do m_MergeThreads[i].Free;

  m_TranslateThread.Abort;
  m_TranslateThread.WaitFor;
  m_TranslateThread.Free;
  //  освобождение ресурсов
  SysFreeMem( m_pBuffer );
  CloseHandle( m_hDstLock );
  CloseHandle( m_hSrcLock );
end;

procedure TSDIAppForm.FormCreate(Sender: TObject);
var i: Integer;
begin
  m_pBuffer         := SysGetMem( MbMemLimit * 1024 * 1024 );
  m_hDstLock        := CreateMutex( nil, False, nil );
  m_hSrcLock        := CreateMutex( nil, False, nil );
  m_State           := sNone;
  m_LastOutputTime  := 0;
  Randomize;
  //
  for i := Low( m_SortThreads ) to High( m_SortThreads ) do
    m_SortThreads[i]  := TPartSortThread.Create;
  //
  for i := Low( m_MergeThreads ) to High( m_MergeThreads ) do
    m_MergeThreads[i]  := TMergeThread.Create;
  //
  m_TranslateThread  := TTranslateThread.Create;
end;

function TSDIAppForm.Generate( const FileName: String; MbSize: Cardinal ): Boolean;
var
  i, j, Range, ItCount  : Integer;
  Written, ToWrite, Rem : Cardinal;
  hFile                 : THandle;
  p                     : Pointer;
  SaveLF                : Boolean;
  //
  function Routine: Boolean;
  begin
    Result  := False;
    p       := m_pBuffer;
    j       := ToWrite - 1;
    if SaveLF then
      begin
        PAnsiChar( p )^ := #10;
        Inc( PAnsiChar( p ) );
        Dec( j );
      end;
    repeat
      if Random( 100 ) < 10 then
        begin
          PAnsiChar( p )^ := #13;
          SaveLF          := j < 1;
          if not SaveLF then
            begin
              Inc( PAnsiChar( p ) );
              Dec( j );
              PAnsiChar( p )^ := #10;
            end;
        end
      else
        PAnsiChar( p )^ := AnsiChar( Ord( ' ' ) + Random( Range - 1 ) );
      Inc( PAnsiChar( p ) );
      Dec( j );
    until j <= 0;
    if not WriteFile( hFile, m_pBuffer^, ToWrite, Written, nil ) then Exit;
    if Written <> ToWrite then Exit;
    Result  := True;
  end;
begin
  Result  := False;
  hFile   := CreateFile(
    PChar( FileName ), GENERIC_WRITE, 0, nil, CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL, 0
  );
  if hFile = INVALID_HANDLE_VALUE then Exit;
  Range   := Ord( 'z' ) - Ord( ' ' );
  ItCount := MbSize div MbMemLimit;
  Rem     := MbSize mod MbMemLimit;
  ToWrite := MbMemLimit * 1024 * 1024;
  SaveLF  := False;
  for i := ItCount - 1 downto 0 do
    if not Routine then
      begin
        CloseHandle( hFile );
        DeleteFile( PChar( FileName ) );
        Exit;
      end;
  if Rem <> 0 then
    begin
      ToWrite := Rem * 1024 * 1024;
      if not Routine then
        begin
          CloseHandle( hFile );
          DeleteFile( PChar( FileName ) );
          Exit;
        end;
    end;
  SetEndOfFile( hFile );
  CloseHandle( hFile );
  Result  := True;
end;

procedure TSDIAppForm.NextState;
begin
  case m_State of
    sNone:
      begin
        //  подготовка файлов и сортировка строк
        m_State                   := sSort;
        StatusBar.Panels[0].Text  := 'Сортировка...';
        ActionOpen.Enabled        := False;
        ActionSave.Enabled        := False;
        ActionSort.Enabled        := False;
        ActionGenerate.Enabled    := False;
        m_StartTime               := GetTickCount;
        Sort( EditSrc.Text, EditDst.Text );
      end;
    sSort:
      begin
        //  слияние частичных результатов
        m_State                   := sMerge;
        StatusBar.Panels[0].Text  := 'Слияние...';
        Merge;
      end;
    sMerge:
      begin
        //  трансляция редуцированной последовательности
        m_State                   := sTranslate;
        StatusBar.Panels[0].Text  := 'Трансляция...';
        Translate;
      end;
    sTranslate:
      begin
        //  завершение операций
        m_State                   := sNone;
        StatusBar.Panels[0].Text  := '';
        ActionOpen.Enabled        := True;
        ActionSave.Enabled        := True;
        ActionSort.Enabled        := True;
        ActionGenerate.Enabled    := True;
        SetEndOfFile( m_hDstFile );
        CloseHandle( m_hDstFile );
        CloseHandle( m_hFile );
        MessageDlg( 'Операция успешно завершена!', mtInformation, [mbOK], 0 )
      end;
  end;
end;

procedure TSDIAppForm.Merge;
var i, r, t, Iterations, IterationsPerCore: Cardinal; p: Pointer;
begin
  //  сбор данных с потоков
  m_Results     := 0;
  m_ResultsSize := 0;
  for i := Low( m_SortThreads ) to High( m_SortThreads ) do
    begin
      Inc( m_Results, m_SortThreads[i].Results );
      Inc( m_ResultsSize, m_SortThreads[i].ResultsSize );
    end;
  //  расчет числа итераций слияния
  r           := m_Results;
  Iterations  := 0;
  while r > 1 do
    begin
      t := r div 2;
      Dec( r, 2 * t );
      Inc( r, t );
      Inc( Iterations, t );
    end;
  //  деление итераций на 4 потока
  IterationsPerCore := Iterations div 4;
  m_Running           := 4;
  p                 := m_pBuffer;
  for i := 0 to 3 do
    begin
      m_MergeThreads[i].Init(
        @m_ReduceOffset, @m_ResultsOffset, @m_ResultsSize, p, @m_Results, @m_Running,
        @m_LastOutputTime, IterationsPerCore, m_hDstFile, m_hDstLock
      );
      Inc( PAnsiChar( p ), CoreMemSize );
    end;
  m_MergeThreads[3].AddIterations( Iterations - IterationsPerCore * 4 );
  //  параллельно сливаем частичные результаты в один
  for i := 0 to 3 do
    m_MergeThreads[i].Wakeup;
end;

procedure TSDIAppForm.Translate;
begin
  m_TranslateThread.Init( m_ReduceOffset, m_pBuffer, @m_LastOutputTime, m_hFile, m_hDstFile );
  m_TranslateThread.Wakeup;
end;

procedure TSDIAppForm.UpdateStatus;
var i: Integer; p: Single;
begin
  case m_State of
    sSort:
      begin
        p := 0;
        for i := Low( m_SortThreads ) to High( m_SortThreads ) do
          p := p + m_SortThreads[i].Progress;
        StatusBar.Panels[0].Text  := Format( 'Сортировка %.2f%%...', [p / 4] );
      end;
    sMerge:
      begin
        p := 0;
        for i := Low( m_MergeThreads ) to High( m_MergeThreads ) do
          p := p + m_MergeThreads[i].Progress;
        StatusBar.Panels[0].Text  := Format( 'Слияние %.2f%%...', [p / 4] );
      end;
    sTranslate:
      begin
        p := m_TranslateThread.Progress;
        StatusBar.Panels[0].Text  := Format( 'Трансляция %.2f%%...', [p] );
      end;
  end;
  StatusBar.Panels[1].Text  := Format(
    'Время работы: %f сек.', [( GetTickCount - m_StartTime ) / 1000]
  );
end;

function TSDIAppForm.Sort( const Src, Dst: String ): Boolean;
var Size, Offset, FileSize: UInt64; i: Cardinal; p: Pointer;
begin
  Result  := False;
  m_hFile   := CreateFile(
    PChar( Src ), GENERIC_READ, 0, nil, OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL, 0
  );
  m_hDstFile  := CreateFile(
    PChar( Dst ), GENERIC_READ or GENERIC_WRITE, 0, nil, CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL, 0
  );
  if m_hFile = INVALID_HANDLE_VALUE then Exit;
  if m_hDstFile = INVALID_HANDLE_VALUE then
    begin
      CloseHandle( m_hFile );
      Exit;
    end;
  Int64Rec( FileSize ).Lo := GetFileSize( m_hFile, @Int64Rec( FileSize ).Hi );
  m_ResultsOffset           := FileSize;
  SetFilePointer(
    m_hDstFile, Int64Rec( FileSize ).Lo, @Int64Rec( FileSize ).Hi, FILE_BEGIN
  );
  SetEndOfFile( m_hDstFile );
  //  делим файл на 4 потока
  Size    := FileSize div 4;
  Offset  := 0;
  p       := m_pBuffer;
  m_Running := 4;
  for i := 0 to 3 do
    begin
      m_SortThreads[i].Init(
        m_hFile, m_hDstFile, m_hSrcLock, m_hDstLock, Offset, Size, FileSize, p,
        @m_Running, @m_LastOutputTime, i = 3
      );
      Inc( PAnsiChar( p ), CoreMemSize );
      Inc( Offset, Size );
    end;
  m_SortThreads[3].AddSize( FileSize - Size * 4 );
  //  выравнивание границ буферов по границе строк
  for i := 1 to 3 do
    m_SortThreads[i - 1].AddSize( m_SortThreads[i].AdjustOffset( m_hFile ) );
  //  сортируем
  for i := 0 to 3 do
    m_SortThreads[i].Wakeup;
end;

end.
