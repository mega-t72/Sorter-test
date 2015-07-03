unit UnitMergeThread;

interface

uses
  System.Classes, Winapi.Windows, UnitCommon;

type
  TMergeThread = class(TCommonThread)
  private
    m_pReduceOffset   : PUInt64;  //  �������� ��������� ������������������
    m_pResultsOffset  : PUInt64;  //  �������� ������ ������������������
    m_pResultsSize    : PUInt64;  //  ������ �������������������
    m_pResults        : PInteger; //  ����� ����� �������������������
    m_pRunning        : PInteger; //  ����� ����� ������������� �������
    m_Iterations      : Cardinal; //  ����� ��� ������������������� ������
    m_hDstFile        : THandle;  //  ���������� �������� �����
    m_hDstLock        : THandle;  //  �������, ���������� ������ � �������� �����
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
            //  ���������� ������ ������ ����� �����
            MoveMemory( pSwBuffer, pRBuffer, pRBuffer^.Size );
            MoveMemory(
              PAnsiChar( pLBuffer ) + pRBuffer^.Size, pLBuffer,
              IntPtr( pRBuffer ) - IntPtr( pLBuffer )
            );
            MoveMemory( pLBuffer, pSwBuffer, pSwBuffer^.Size );
            //  ������������ ������� ��������� �� ������� ��������� ������
            Inc( PAnsiChar( pRBuffer ), pSwBuffer^.Size );
            //
            pLBuffer  := pLBuffer^.Next;
            Dec( RRem, pSwBuffer^.Size );
            //
            Dec( RCount );
          end
        else
          begin
            //  ������� � ����. ����� ������
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
            //  spin-lock-�������� ���������� �����������
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
            //  ���������� �������� ��� ������ ������������������
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
            //  ���������� ����� ����� ����� ������������������
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
            //  ���������� �������� ��� ��������� ������������������
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
            //  ���������� ����� ����� ������ ������������������
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
            //  �������� ����� ��� ���������� �������
            DOffset         := m_pResultsOffset^ + m_pResultsSize^;
            m_pReduceOffset^  := DOffset;
            //  ���������
            Inc( m_pResultsSize^, PartSortHeaderSize );
            //  ������
            Inc( m_pResultsSize^, LSize + RSize - 2 * PartSortHeaderSize );
            //  ����� ��������� ���������� �������
            SetFilePointer(
              m_hDstFile, Int64Rec( DOffset ).Lo, @Int64Rec( DOffset ).Hi,
              FILE_BEGIN
            );
            DSize   := LSize + RSize - PartSortHeaderSize;
            DCount  := LCount + RCount;
            //  ������ �-��
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
            //  ����� �����
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
            //  ���������� ������� �������
            pLBuffer  := m_pBuffer;
            pRBuffer  := m_pBuffer;
            pSwBuffer := m_pBuffer;
            BSize     := ( CoreMemSize - 50 - PartSortStringHeaderSize ) div 2;
            Inc( PAnsiChar( pRBuffer ), BSize );
            Inc( PAnsiChar( pSwBuffer ), 2 * BSize );
            //  ���������� ���������
            Inc( LOffset, PartSortHeaderSize );
            Inc( ROffset, PartSortHeaderSize );
            Dec( LSize, PartSortHeaderSize );
            Dec( RSize, PartSortHeaderSize );
            //  �������� ������
            LRem      := 0;
            RRem      := 0;
            //  �������� �� ������� ���� �������������������
            while
              ( ( LSize > 0 ) or ( LRem > 0 ) ) and
              ( ( RSize > 0 ) or ( RRem > 0 ) )
            do
              begin
                //  ��������� ������� �����
                MoveMemory( m_pBuffer, pLBuffer, LRem );
                pLBuffer  := Pointer( PAnsiChar( m_pBuffer ) + LRem );
                //  ��������� ������� ������
                MoveMemory( PAnsiChar( m_pBuffer ) + BSize, pRBuffer, RRem );
                pRBuffer  := Pointer( PAnsiChar( m_pBuffer ) + BSize + RRem );
                //
                WaitForSingleObject( m_hDstLock, INFINITE );
                //  ��������� ����� �����
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
                //  ��������� ������ �����
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
                //  ������� ������������������
                Merge;
                //  ���������� � ���� ����� �-��
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
            //  �������
            if LSize > 0 then
              begin
                ROffset := LOffset;
                RSize   := LSize;
              end;
            while RSize > 0 do
              begin
                WaitForSingleObject( m_hDstLock, INFINITE );
                //  ������ �����
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
                //  ���������� � ���� �������
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
            //  ���������� �������������� ������������������
            InterlockedIncrement( m_pResults^ );
            //  ��������� ������
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
