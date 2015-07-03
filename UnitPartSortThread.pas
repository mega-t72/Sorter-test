unit UnitPartSortThread;

interface

uses
  System.Classes, Winapi.Windows, UnitCommon;

type
  TPartSortThread = class(TCommonThread)
  private
    m_Offset      : UInt64;   //  смещение набора в исходном файле
    m_Size        : UInt64;   //  размер набора в исходном файле
    m_pIDs        : Pointer;  //  базовые указатели внутри буфера
    m_pPtrs       : Pointer;  //  указатель на массив строк (быстрый доступ)
    m_pTail       : Pointer;  //  указатель на конец рабочего буфера (начало реверсированного массива длин строк)
    m_ItemsCount  : Word;     //  число записей в буфере
    m_PackedSize  : Cardinal; //  упакованный размер блока данных (строк)
    m_Results     : Integer;  //  число частичных результатов сортировки текущего потока
    m_ResultsSize : UInt64;   //  объем частичных результатов сортировки текущего потока
    m_hFile       : THandle;  //  дескриптор исходного файла
    m_hDstFile    : THandle;  //  дескриптор целевого файла
    m_hSrcLock    : THandle;  //  мьютекс, защищающий доступ к исходному файлу
    m_hDstLock    : THandle;  //  мьютекс, защищающий доступ к целевому файлу
    m_FileSize    : UInt64;   //  размер исходного файла
    m_Last        : Boolean;  //  признак хвостового потока (учет последней строки без CRLF)
    m_pRunning    : PInteger; //  общее число выполн€ющихс€ потоков
    function Comp( a, b: Word ): Integer;
    procedure BuildList;
    procedure QuickSort( l, r: Word );
  protected
    procedure Execute; override;
    function GetID( Index: Word ): PWord; inline;
    function GetItem( Index: Word ): PAnsiChar; inline;
    function GetItemLength( Index: Word ): Word; inline;
    function GetItemOffset( Index: Word ): Cardinal; inline;
    procedure SortStrings;
    function WriteStrings( const FileOffset, FileSize: UInt64 ): Boolean;
  public
    procedure Init(
      hFile, hDstFile, hSrcLock, hDstLock: THandle;
      Offset, Size, FileSize: UInt64;
      pBuffer: Pointer;
      pRunning, pLastOutputTime: PInteger;
      Last: Boolean
    );
    procedure AddSize( Chunk: IntPtr );
    function AdjustOffset( hFile: THandle ): Word;
    property Results: Integer read m_Results;
    property ResultsSize: UInt64 read m_ResultsSize;
  end;

implementation

uses System.AnsiStrings, System.SysUtils, SDIMAIN;

function SearchCRLF( p: Pointer; Length: Cardinal ): Cardinal;
begin
  Result  := 0;
  while Length > 0 do
    begin
      if PAnsiChar( p )^ = #13 then
        begin
          Inc( PAnsiChar( p ) );
          Dec( Length );
          if ( Length > 0 ) and ( PAnsiChar( p )^ = #10 ) then
            Exit
          else
            Inc( Result );
          if Length = 0 then Break;
        end;
      Inc( PAnsiChar( p ) );
      Dec( Length );
      Inc( Result );
    end;
end;

{ TPartSortThread }

procedure TPartSortThread.AddSize( Chunk: IntPtr );
begin
  Inc( m_Size, Chunk );
end;

function TPartSortThread.AdjustOffset( hFile: THandle ): Word;
var Offset: UInt64; ToRead, Readed: Cardinal; CRLF: Word;
begin
  //  захватываем последние 2 символа предыдущего буфера
  //  (учет ситуации, когда граница буферов перерезает строку )
  Offset  := Self.m_Offset - 2;
  //  читаем буфер
  SetFilePointer(
    hFile, Int64Rec( Offset ).Lo, @Int64Rec( Offset ).Hi, FILE_BEGIN
  );
  ToRead  := Min( CoreMemSize, m_Size + 2 );
  if False = ReadFile( hFile, m_pBuffer^, ToRead, Readed, nil ) then
    begin
      DebugBreak;
      Result  := 0;
      Exit;
    end;
  if ToRead <> Readed then
    begin
      DebugBreak;
      Result  := 0;
      Exit;
    end;
  //
  CRLF    := SearchCRLF( m_pBuffer, Readed );
  Result  := CRLF;
  if CRLF < Readed then
    Inc( Result, 2 );
  Dec( Result, 2 );
  //  корректировка смещений
  Inc( Self.m_Offset, Result );
  Dec( Self.m_Size, Result );
end;

procedure TPartSortThread.BuildList;
var
  ps: Cardinal;
  i, Length: Word;
  pString: PAnsiChar;
  pSize, pID: PWord;
  pPtr: PPointer;
begin
  m_pIDs    := m_pBuffer;
  m_pPtrs   := m_pBuffer;
  m_pTail   := m_pBuffer;
  //
  Inc( PAnsiChar( m_pPtrs ), m_PackedSize );
  Inc( PWord( m_pPtrs ), m_ItemsCount );
  Inc( PAnsiChar( m_pIDs ), m_PackedSize );
  Inc( PAnsiChar( m_pTail ), CoreMemSize );
  //
  pPtr    := m_pPtrs;
  pID     := m_pIDs;
  pSize   := m_pTail;
  pString := m_pBuffer;
  ps      := 0;
  for i := 0 to m_ItemsCount - 1 do
    begin
      Dec( pSize );
      //
      pPtr^   := pString;
      pID^    := i;
      Length  := Min( pSize^, 50 );
      //
      Inc( pString, Length );
      Inc( pPtr );
      Inc( pID );
      Inc( ps, Length );
    end;
  Assert( ps = m_PackedSize );
end;

function TPartSortThread.Comp(a, b: Word): Integer;
var al, bl: Word;
begin
  al      := GetItemLength( a );
  bl      := GetItemLength( b );
  if al < bl then
    Result  := -1
  else if al > bl then
    Result  := +1
  else
    Result  := System.AnsiStrings.AnsiStrLComp(
      GetItem( a ), GetItem( b ), Min( 50, al )
    );
end;

procedure TPartSortThread.Execute;
var
  BufferOffset, RelOffset, Unreaded: UInt64;
  ToRead, Readed, CRLF, _CRLF, RecSize, UnpackedSize, SysSize: Cardinal;
  p, pSizes: Pointer;
  Done: Boolean;
label loop;
begin
  while ( WAIT_OBJECT_0 = WaitForSingleObject( m_hWakeup, INFINITE ) ) and not m_fAbort do
    begin
      BufferOffset  := m_Offset;
      RelOffset     := m_Offset;
      Unreaded      := m_Size;
      UnpackedSize  := 0;
      m_Results     := 0;
      m_ResultsSize := 0;
      while Unreaded > 0 do
        begin
          p           := m_pBuffer;
          pSizes      := m_pBuffer;
          Done        := False;
          m_PackedSize  := 0;
          m_ItemsCount  := 0;
          Inc( PAnsiChar( pSizes ), CoreMemSize );
          while not Done and ( Unreaded > 0 ) do
            begin
              RelOffset := BufferOffset;
              //  читаем буфер
              WaitForSingleObject( m_hSrcLock, INFINITE );
              SetFilePointer(
                m_hFile, Int64Rec( BufferOffset ).Lo, @Int64Rec( BufferOffset ).Hi,
                FILE_BEGIN
              );
              ToRead    := Min(
                CoreMemSize - m_PackedSize - m_ItemsCount * sizeof( Word ), Unreaded
              );
              Assert( IntPtr(p) < ( IntPtr( m_pBuffer ) + CoreMemSize ) );
              Assert( ( UIntPtr(p) + ToRead ) <= ( UIntPtr( m_pBuffer ) + CoreMemSize ) );
              if False = ReadFile( m_hFile, p^, ToRead, Readed, nil ) then
                begin
                  DebugBreak;
                  ReleaseMutex( m_hSrcLock );
                  Exit;
                end;
              if ToRead <> Readed then
                begin
                  DebugBreak;
                  ReleaseMutex( m_hSrcLock );
                  Exit;
                end;
              ReleaseMutex( m_hSrcLock );
              //  учитываем остаток с предыдущей итерации
              Dec( PAnsiChar( p ), UnpackedSize );
              Inc( ToRead, UnpackedSize );
              //  упаковываем строки
              UnpackedSize  := ToRead;
loop:
              CRLF  := SearchCRLF( p, UnpackedSize );
              _CRLF := CRLF;
              if CRLF < UnpackedSize then
                Inc( _CRLF, 2 );
              if ( CRLF < UnpackedSize ) or ( m_Last and ( UnpackedSize > 0 ) and ( UnpackedSize = Unreaded ) ) then
                begin
                  Assert( CRLF <= 500 );
                  RecSize := Min( CRLF, 50 );
                  //  остаток буфера должен вмещать все индексы и указатели дл€ упакованных строк
                  SysSize  := 2 * ( m_ItemsCount + 1 ) * ( 2 * sizeof( Word ) + sizeof( Pointer ) );
                  if ( CoreMemSize - m_PackedSize - RecSize ) >= SysSize then
                    begin
                      Inc( m_PackedSize, RecSize );
                      Dec( UnpackedSize, _CRLF );
                      Inc( BufferOffset, _CRLF );
                      Dec( Unreaded, _CRLF );
                      MoveMemory(
                        PAnsiChar( p ) + RecSize, PAnsiChar( p ) + _CRLF, UnpackedSize
                      );
                      Inc( m_ItemsCount );
                      //  пишем фактический размер строки в конец буфера
                      Assert( CRLF <= $0000FFFF );
                      Dec( PWord( pSizes ) );
                      PWord( pSizes )^  := Word( CRLF );
                      //
                      Inc( PAnsiChar( p ), RecSize );
                      goto loop;
                    end
                  else
                    begin
                      UnpackedSize  := 0;
                      Done          := True;
                    end;
                end;
              //  в UnpackedSize остаток, который нужно перенести на след. итерацию
              Inc( PAnsiChar( p ), UnpackedSize );
            end;
          //  заполн€ем массив индексов
          BuildList;
          //  сортируем индексы строк
          SortStrings;
          //  записываем частичные результаты в файл
          WaitForSingleObject( m_hDstLock, INFINITE );
          if not WriteStrings( RelOffset, m_FileSize ) then
            begin
              DebugBreak;
              ReleaseMutex( m_hDstLock );
              Exit;
            end;
          ReleaseMutex( m_hDstLock );
          //
          Inc( m_Results );
          //  размер данных
          Inc( m_ResultsSize, m_PackedSize );
          //  размер длин и смещений строк
          Inc( m_ResultsSize, m_ItemsCount * PartSortStringHeaderSize );
          //  размер заголовка (размер и число строк)
          Inc( m_ResultsSize, PartSortHeaderSize );
          //  обновл€ем статус
          UpdateProgress( 100 - ( Unreaded * 100 ) / m_Size );
        end;
      if ( InterlockedDecrement( m_pRunning^ ) = 0 ) and not m_fAbort then
        Synchronize( SDIAppForm.NextState );
    end;
end;

function TPartSortThread.GetID(Index: Word): PWord;
begin
  Result  := m_pIDs;
  Inc( Result, Index );
end;

function TPartSortThread.GetItem(Index: Word): PAnsiChar;
begin
  Result  := PPointer( IntPtr( m_pPtrs ) + Index * sizeof( IntPtr ) )^;
end;

function TPartSortThread.GetItemLength(Index: Word): Word;
begin
  Result  := PWord( IntPtr( m_pTail ) - ( Index + 1 ) * sizeof( Word ) )^;
end;

function TPartSortThread.GetItemOffset(Index: Word): Cardinal;
var pSize: PWord;
begin
  Result  := 0;
  pSize   := m_pTail;
  while Index > 0 do
    begin
      Dec( pSize );
      Dec( Index );
      Inc( Result, 2 + pSize^ );
    end;
end;

procedure TPartSortThread.Init(
  hFile, hDstFile, hSrcLock, hDstLock: THandle;
  Offset, Size, FileSize: UInt64;
  pBuffer: Pointer;
  pRunning, pLastOutputTime: PInteger;
  Last: Boolean
);
begin
  m_hFile            := hFile;
  m_hDstFile         := hDstFile;
  m_hSrcLock         := hSrcLock;
  m_hDstLock         := hDstLock;
  m_hWakeup          := m_hWakeup;
  m_FileSize         := FileSize;
  m_Offset           := Offset;
  m_Size             := Size;
  m_pRunning         := pRunning;
  m_Last             := Last;
  m_ItemsCount       := 0;
  inherited Init( pBuffer, pLastOutputTime);
end;

procedure TPartSortThread.QuickSort(l, r: Word);
var i, j, q, sw: Integer;
begin
  if ( r - l ) < 1 then Exit;
  repeat
    i := l;
    j := r;
    q := GetID( l + ( r - l ) shr 1 )^;
    repeat
      while Comp( GetID( i )^, q ) < 0 do Inc(I);
      while Comp( GetID( j )^, q ) > 0 do Dec(J);
      if I <= J then
        begin
          if i <> j then
            begin
              sw          := GetID( i )^;
              GetID( i )^ := GetID( j )^;
              GetID( j )^ := sw;
            end;
          Inc( i );
          Dec( j );
        end;
    until i > j;
    if l < j then
      QuickSort( l, j );
    l := i;
  until i >= r;
end;

procedure TPartSortThread.SortStrings;
begin
  if m_ItemsCount > 0 then
    QuickSort( 0, m_ItemsCount - 1 );
end;

function TPartSortThread.WriteStrings( const FileOffset, FileSize: UInt64): Boolean;
var i, ID, Size, Length: Word; Written: Cardinal; ui64: UInt64;
begin
  Result  := False;
  //  размер последовательности
  ui64  := PartSortHeaderSize + m_ItemsCount * PartSortStringHeaderSize + m_PackedSize;
  if False = WriteFile( m_hDstFile, ui64, sizeof( ui64 ), Written, nil ) then
    begin
      DebugBreak;
      Exit;
    end;
  if Written <> sizeof( ui64 ) then
    begin
      DebugBreak;
      Exit;
    end;
  //  число строк
  ui64  := m_ItemsCount;
  if False = WriteFile( m_hDstFile, ui64, sizeof( ui64 ), Written, nil ) then
    begin
      DebugBreak;
      Exit;
    end;
  if Written <> sizeof( ui64 ) then
    begin
      DebugBreak;
      Exit;
    end;
  //  строки
  for i := 0 to m_ItemsCount - 1 do
    begin
      ID    := GetID( i )^;
      Size  := GetItemLength( ID );
      //  смещение строки
      ui64  := FileOffset + GetItemOffset( ID );
      if ( ui64 + Size ) > FileSize then
        begin
          //Assert( ( ui64 + Size ) <= FileSize );
          DebugBreak;
        end;
      if False = WriteFile( m_hDstFile, ui64, sizeof( UInt64 ), Written, nil ) then
        begin
          DebugBreak;
          Exit;
        end;
      if Written <> sizeof( UInt64 ) then
        begin
          DebugBreak;
          Exit;
        end;
      //  длина строки
      if False = WriteFile( m_hDstFile, Size, sizeof( Word ), Written, nil ) then
        begin
          DebugBreak;
          Exit;
        end;
      if Written <> sizeof( Word ) then
        begin
          DebugBreak;
          Exit;
        end;
      //  строка
      Length  := Min( Size, 50 );
      if False = WriteFile( m_hDstFile, GetItem( ID )^, Length, Written, nil ) then
        begin
          DebugBreak;
          Exit;
        end;
      if Written <> Length then
        begin
          DebugBreak;
          Exit;
        end;
    end;
  //
  Result  := True;
end;

end.
