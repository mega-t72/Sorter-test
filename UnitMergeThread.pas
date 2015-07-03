unit UnitMergeThread;

interface

uses
  System.Classes, Winapi.Windows, UnitCommon;

type
  TMergeThread = class(TCommonThread)
  private
    m_pReduceOffset   : PUInt64;  //  смещение последней последовательности
    m_pResultsOffset  : PUInt64;  //  смещение первой последовательности
    m_pResultsSize    : PUInt64;  //  размер последовательностей
    m_pResults        : PInteger; //  общее число последовательностей
    m_pRunning        : PInteger; //  общее число выполняющихся потоков
    m_Iterations      : Cardinal; //  число пар последовательностей потока
    m_hDstFile        : THandle;  //  дескриптор целевого файла
    m_hDstLock        : THandle;  //  мьютекс, защищающий доступ к целевому файлу
  protected
    procedure Execute; override;
  public
    procedure Init(
      pReduceOffset, pResultsOffset, pResultsSize: PUInt64;
      pBuffer: Pointer;
      pResults, pRunning, pLastOutputTime: PInteger;
      Iterations: Cardinal;
      hDstFile, hDstLock: THandle
    );
    procedure AddIterations( Count: Cardinal );
  end;

implementation

uses System.SysUtils, SDIMAIN;

{ TMergeThread }

procedure TMergeThread.AddIterations(Count: Cardinal);
begin
  Inc( m_Iterations, Count );
end;

procedure TMergeThread.Execute;
var
  LSize, RSize, DSize, LOffset, ROffset, LCount, RCount, DCount, DOffset: UInt64;
  it, ToRead, Readed, BSize, LRem, RRem, ToWrite, Written: Cardinal;
  pLBuffer, pRBuffer, pSwBuffer: PString;
  //
  procedure Merge;
  begin
    while
      ( LRem >= PartSortStringHeaderSize ) and
      ( RRem >= PartSortStringHeaderSize ) and
      ( pLBuffer^.Size <= LRem ) and ( pRBuffer^.Size <= RRem )
    do
      begin
        if pRBuffer^.Less( pLBuffer^ ) then
          begin
            //  перемещаем правую строку перед левой
            MoveMemory( pSwBuffer, pRBuffer, pRBuffer^.Size );
            MoveMemory(
              PAnsiChar( pLBuffer ) + pRBuffer^.Size, pLBuffer,
              IntPtr( pRBuffer ) - IntPtr( pLBuffer )
            );
            MoveMemory( pLBuffer, pSwBuffer, pSwBuffer^.Size );
            //  выравнивание правого указателя на границу следующей строки
            Inc( PAnsiChar( pRBuffer ), pSwBuffer^.Size );
            //
            pLBuffer  := pLBuffer^.Next;
            Dec( RRem, pSwBuffer^.Size );
            //
            Dec( RCount );
          end
        else
          begin
            //  переход к след. левой строке
            Dec( LCount );
            Dec( LRem, pLBuffer^.Size );
            pLBuffer  := pLBuffer^.Next;
          end;
      end;
  end;
begin
  while ( WAIT_OBJECT_0 = WaitForSingleObject( m_hWakeup, INFINITE ) ) and not m_fAbort do
    begin
      if m_Iterations > 0 then
        for it := m_Iterations - 1 downto 0 do
          begin
            //  spin-lock-ожидание готовности результатов
            while InterlockedExchangeAdd( m_pResults^, -2 ) < 2 do
              begin
                InterlockedExchangeAdd( m_pResults^, 2 );
                SwitchToThread;
              end;
            //
            WaitForSingleObject( m_hDstLock, INFINITE );
            //
            LOffset := m_pResultsOffset^;
            SetFilePointer(
              m_hDstFile, Int64Rec( m_pResultsOffset^ ).Lo,
              @Int64Rec( m_pResultsOffset^ ).Hi, FILE_BEGIN
            );
            //  определяем смещение для правой последовательности
            ToRead  := sizeof( UInt64 );
            if False = ReadFile( m_hDstFile, LSize, ToRead, Readed, nil ) then
              begin
                DebugBreak;
                ReleaseMutex( m_hDstLock );
                Exit;
              end;
            if ToRead <> Readed then
              begin
                DebugBreak;
                ReleaseMutex( m_hDstLock );
                Exit;
              end;
            ROffset := LOffset + LSize;
            //  определяем число строк левой последовательности
            ToRead  := sizeof( UInt64 );
            if False = ReadFile( m_hDstFile, LCount, ToRead, Readed, nil ) then
              begin
                DebugBreak;
                ReleaseMutex( m_hDstLock );
                Exit;
              end;
            if ToRead <> Readed then
              begin
                DebugBreak;
                ReleaseMutex( m_hDstLock );
                Exit;
              end;
            //  определяем смещение для следующей последовательности
            SetFilePointer(
              m_hDstFile, Int64Rec( ROffset ).Lo, @Int64Rec( ROffset ).Hi,
              FILE_BEGIN
            );
            ToRead  := sizeof( UInt64 );
            if False = ReadFile( m_hDstFile, RSize, ToRead, Readed, nil ) then
              begin
                DebugBreak;
                ReleaseMutex( m_hDstLock );
                Exit;
              end;
            if ToRead <> Readed then
              begin
                DebugBreak;
                ReleaseMutex( m_hDstLock );
                Exit;
              end;
            m_pResultsOffset^  := ROffset + RSize;
            Dec( m_pResultsSize^, LSize + RSize );
            //  определяем число строк правой последовательности
            ToRead  := sizeof( UInt64 );
            if False = ReadFile( m_hDstFile, RCount, ToRead, Readed, nil ) then
              begin
                DebugBreak;
                ReleaseMutex( m_hDstLock );
                Exit;
              end;
            if ToRead <> Readed then
              begin
                DebugBreak;
                ReleaseMutex( m_hDstLock );
                Exit;
              end;
            //  выделяем место для результата слияния
            DOffset         := m_pResultsOffset^ + m_pResultsSize^;
            m_pReduceOffset^  := DOffset;
            //  заголовок
            Inc( m_pResultsSize^, PartSortHeaderSize );
            //  строки
            Inc( m_pResultsSize^, LSize + RSize - 2 * PartSortHeaderSize );
            //  пишем заголовок результата слияния
            SetFilePointer(
              m_hDstFile, Int64Rec( DOffset ).Lo, @Int64Rec( DOffset ).Hi,
              FILE_BEGIN
            );
            DSize   := LSize + RSize - PartSortHeaderSize;
            DCount  := LCount + RCount;
            //  размер п-ти
            ToWrite := sizeof( DSize );
            if False = WriteFile( m_hDstFile, DSize, ToWrite, Written, nil ) then
              begin
                DebugBreak;
                ReleaseMutex( m_hDstLock );
                Exit;
              end;
            if ToWrite <> Written then
              begin
                DebugBreak;
                ReleaseMutex( m_hDstLock );
                Exit;
              end;
            //  число строк
            ToWrite := sizeof( DCount );
            if False = WriteFile( m_hDstFile, DCount, ToWrite, Written, nil ) then
              begin
                DebugBreak;
                ReleaseMutex( m_hDstLock );
                Exit;
              end;
            if ToWrite <> Written then
              begin
                DebugBreak;
                ReleaseMutex( m_hDstLock );
                Exit;
              end;
            Inc( DOffset, PartSortHeaderSize );
            //
            ReleaseMutex( m_hDstLock );
            //  обозначаем границы буферов
            pLBuffer  := m_pBuffer;
            pRBuffer  := m_pBuffer;
            pSwBuffer := m_pBuffer;
            BSize     := ( CoreMemSize - 50 - PartSortStringHeaderSize ) div 2;
            Inc( PAnsiChar( pRBuffer ), BSize );
            Inc( PAnsiChar( pSwBuffer ), 2 * BSize );
            //  пропускаем заголовки
            Inc( LOffset, PartSortHeaderSize );
            Inc( ROffset, PartSortHeaderSize );
            Dec( LSize, PartSortHeaderSize );
            Dec( RSize, PartSortHeaderSize );
            //  обнуляем буферы
            LRem      := 0;
            RRem      := 0;
            //  итерации по слиянию двух последовательностей
            while
              ( ( LSize > 0 ) or ( LRem > 0 ) ) and
              ( ( RSize > 0 ) or ( RRem > 0 ) )
            do
              begin
                //  учитываем остаток слева
                MoveMemory( m_pBuffer, pLBuffer, LRem );
                pLBuffer  := Pointer( PAnsiChar( m_pBuffer ) + LRem );
                //  учитываем остаток справа
                MoveMemory( PAnsiChar( m_pBuffer ) + BSize, pRBuffer, RRem );
                pRBuffer  := Pointer( PAnsiChar( m_pBuffer ) + BSize + RRem );
                //
                WaitForSingleObject( m_hDstLock, INFINITE );
                //  заполняем левый буфер
                SetFilePointer(
                  m_hDstFile, Int64Rec( LOffset ).Lo, @Int64Rec( LOffset ).Hi,
                  FILE_BEGIN
                );
                ToRead  := Min( LSize, BSize - LRem );
                if False = ReadFile( m_hDstFile, pLBuffer^, ToRead, Readed, nil ) then
                  begin
                    DebugBreak;
                    ReleaseMutex( m_hDstLock );
                    Exit;
                  end;
                if ToRead <> Readed then
                  begin
                    DebugBreak;
                    ReleaseMutex( m_hDstLock );
                    Exit;
                  end;
                //
                Dec( PAnsiChar( pLBuffer ), LRem );
                Inc( LRem, ToRead );
                //
                Dec( LSize, ToRead );
                Inc( LOffset, ToRead );
                //  заполняем правый буфер
                SetFilePointer(
                  m_hDstFile, Int64Rec( ROffset ).Lo, @Int64Rec( ROffset ).Hi,
                  FILE_BEGIN
                );
                ToRead  := Min( RSize, BSize - RRem );
                if False = ReadFile( m_hDstFile, pRBuffer^, ToRead, Readed, nil ) then
                  begin
                    DebugBreak;
                    ReleaseMutex( m_hDstLock );
                    Exit;
                  end;
                if ToRead <> Readed then
                  begin
                    DebugBreak;
                    ReleaseMutex( m_hDstLock );
                    Exit;
                  end;
                ReleaseMutex( m_hDstLock );
                //
                Dec( PAnsiChar( pRBuffer ), RRem );
                Inc( RRem, ToRead );
                //
                Dec( RSize, ToRead );
                Inc( ROffset, ToRead );
                //  сливаем последовательности
                Merge;
                //  записываем в файл левую п-ть
                WaitForSingleObject( m_hDstLock, INFINITE );
                SetFilePointer(
                  m_hDstFile, Int64Rec( DOffset ).Lo, @Int64Rec( DOffset ).Hi,
                  FILE_BEGIN
                );
                ToWrite := IntPtr( pLBuffer ) - IntPtr( m_pBuffer );
                if False = WriteFile( m_hDstFile, m_pBuffer^, ToWrite, Written, nil ) then
                  begin
                    DebugBreak;
                    ReleaseMutex( m_hDstLock );
                    Exit;
                  end;
                if ToWrite <> Written then
                  begin
                    DebugBreak;
                    ReleaseMutex( m_hDstLock );
                    Exit;
                  end;
                ReleaseMutex( m_hDstLock );
                Inc( DOffset, ToWrite );
              end;
            //
            Inc( LSize, LRem );
            Dec( LOffset, LRem );
            Inc( RSize, RRem );
            Dec( ROffset, RRem );
            Assert( ( LSize = 0 ) or ( RSize = 0 ) );
            //  остаток
            if LSize > 0 then
              begin
                ROffset := LOffset;
                RSize   := LSize;
              end;
            while RSize > 0 do
              begin
                WaitForSingleObject( m_hDstLock, INFINITE );
                //  читаем буфер
                SetFilePointer(
                  m_hDstFile, Int64Rec( ROffset ).Lo, @Int64Rec( ROffset ).Hi,
                  FILE_BEGIN
                );
                ToRead  := Min( RSize, MemLimit );
                if False = ReadFile( m_hDstFile, m_pBuffer^, ToRead, Readed, nil ) then
                  begin
                    DebugBreak;
                    ReleaseMutex( m_hDstLock );
                    Exit;
                  end;
                if ToRead <> Readed then
                  begin
                    DebugBreak;
                    ReleaseMutex( m_hDstLock );
                    Exit;
                  end;
                Inc( ROffset, Readed );
                Dec( RSize, Readed );
                //  записываем в файл остаток
                SetFilePointer(
                  m_hDstFile, Int64Rec( DOffset ).Lo, @Int64Rec( DOffset ).Hi,
                  FILE_BEGIN
                );
                ToWrite := Readed;
                if False = WriteFile( m_hDstFile, m_pBuffer^, ToWrite, Written, nil ) then
                  begin
                    DebugBreak;
                    ReleaseMutex( m_hDstLock );
                    Exit;
                  end;
                if ToWrite <> Written then
                  begin
                    DebugBreak;
                    ReleaseMutex( m_hDstLock );
                    Exit;
                  end;
                Inc( DOffset, ToWrite );
                //
                ReleaseMutex( m_hDstLock );
              end;
            //  показываем результирующую последовательность
            InterlockedIncrement( m_pResults^ );
            //  обновляем статус
            UpdateProgress( 100 - 100 * it / m_Iterations );
          end;
        if ( InterlockedDecrement( m_pRunning^ ) = 0 ) and not m_fAbort then
          Synchronize( SDIAppForm.NextState );
      end;
end;

procedure TMergeThread.Init(
    pReduceOffset, pResultsOffset, pResultsSize: PUInt64;
    pBuffer: Pointer;
    pResults, pRunning, pLastOutputTime: PInteger;
    Iterations: Cardinal;
    hDstFile, hDstLock: THandle
);
begin
  m_pReduceOffset    := pReduceOffset;
  m_pResultsOffset   := pResultsOffset;
  m_pResultsSize     := pResultsSize;
  m_pResults         := pResults;
  m_pRunning         := pRunning;
  m_Iterations       := Iterations;
  m_hDstFile         := hDstFile;
  m_hDstLock         := hDstLock;
  inherited Init( pBuffer, pLastOutputTime );
end;

end.
