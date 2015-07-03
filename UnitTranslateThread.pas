unit UnitTranslateThread;

interface

uses
  System.Classes, Winapi.Windows, UnitCommon;

type
  TTranslateThread = class(TCommonThread)
  private
    m_ReduceOffset  : UInt64;   //  смещение транслируемой последовательности
    m_hFile         : THandle;  //  дескриптор исходного файла
    m_hDstFile      : THandle;  //  дескриптор целевого файла
  protected
    procedure Execute; override;
  public
    procedure Init(
      ReduceOffset: UInt64;
      pBuffer: Pointer;
      pLastOutputTime: PInteger;
      hFile, hDstFile: THandle
    );
  end;

implementation

uses System.SysUtils, SDIMAIN;

{ TTranslateThread }

procedure TTranslateThread.Execute;
var
  ToRead, Readed, ToWrite, Written, MemSize, Unprocessed: Cardinal;
  SrcSize, Size, Offset: UInt64;
  pStr: PString;
  p: Pointer;
begin
  while ( WAIT_OBJECT_0 = WaitForSingleObject( m_hWakeup, INFINITE ) ) and not m_fAbort do
    begin
      Offset  := 0;
      //
      SetFilePointer(
        m_hDstFile, Int64Rec( m_ReduceOffset ).Lo, @Int64Rec( m_ReduceOffset ).Hi,
        FILE_BEGIN
      );
      //  определяем размер последовательности
      ToRead  := sizeof( UInt64 );
      if False = ReadFile( m_hDstFile, SrcSize, ToRead, Readed, nil ) then
        begin
          DebugBreak;
          Exit;
        end;
      if ToRead <> Readed then
        begin
          DebugBreak;
          Exit;
        end;
      //
      Inc( m_ReduceOffset, PartSortHeaderSize );
      Dec( SrcSize, PartSortHeaderSize );
      //
      p           := m_pBuffer;
      MemSize     := MemLimit - 502;
      Size        := SrcSize;
      Inc( PAnsiChar( p ), MemSize );
      //
      while Size > 0 do
        begin
          //  читаем буфер
          SetFilePointer(
            m_hDstFile, Int64Rec( m_ReduceOffset ).Lo, @Int64Rec( m_ReduceOffset ).Hi,
            FILE_BEGIN
          );
          ToRead  := Min( Size, MemSize );
          if False = ReadFile( m_hDstFile, m_pBuffer^, ToRead, Readed, nil ) then
            begin
              DebugBreak;
              Exit;
            end;
          if ToRead <> Readed then
            begin
              DebugBreak;
              Exit;
            end;
          Inc( m_ReduceOffset, Readed );
          Dec( Size, Readed );
          //  записываем в файл строки
          Unprocessed := Readed;
          pStr        := m_pBuffer;
          while
            ( Unprocessed >= PartSortStringHeaderSize ) and
            ( pStr^.Size <= Unprocessed )
          do
            begin
              //  читаем
              SetFilePointer(
                m_hFile, Int64Rec( pStr^.Offset ).Lo, @Int64Rec( pStr^.Offset ).Hi,
                FILE_BEGIN
              );
              Assert( pStr^.Length <= 500 );
              ToRead  := pStr^.Length;
              if False = ReadFile( m_hFile, p^, ToRead, Readed, nil ) then
                begin
                  DebugBreak;
                  Exit;
                end;
              if ToRead <> Readed then
                begin
                  DebugBreak;
                  Exit;
                end;
              //
              ( PAnsiChar( p ) + pStr^.Length + 0 )^  := #13;
              ( PAnsiChar( p ) + pStr^.Length + 1 )^  := #10;
              //  пишем
              SetFilePointer(
                m_hDstFile, Int64Rec( Offset ).Lo, @Int64Rec( Offset ).Hi,
                FILE_BEGIN
              );
              ToWrite := Readed + 2;
              if False = WriteFile( m_hDstFile, p^, ToWrite, Written, nil ) then
                begin
                  DebugBreak;
                  Exit;
                end;
              if ToWrite <> Written then
                begin
                  DebugBreak;
                  Exit;
                end;
              //
              Inc( Offset, pStr^.Length + 2 );
              Dec( Unprocessed, pStr^.Size );
              pStr  := pStr^.Next;
            end;
          Inc( Size, Unprocessed );
          Dec( m_ReduceOffset, Unprocessed );
          //  обновляем статус
          UpdateProgress( 100 - 100 * Size / SrcSize );
        end;
      //
      SetFilePointer(
        m_hDstFile, Int64Rec( Offset ).Lo, @Int64Rec( Offset ).Hi, FILE_BEGIN
      );
      //
      if not m_fAbort then
        Synchronize( SDIAppForm.NextState );
    end;
end;

procedure TTranslateThread.Init(
  ReduceOffset: UInt64;
  pBuffer: Pointer;
  pLastOutputTime: PInteger;
  hFile, hDstFile: THandle
);
begin
  m_ReduceOffset    := ReduceOffset;
  m_hFile           := hFile;
  m_hDstFile        := hDstFile;
  inherited Init( pBuffer, pLastOutputTime );
end;

end.
