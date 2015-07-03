unit UnitCommon;

interface

uses System.Classes;

const MbMemLimit                = 1;
const MemLimit                  = Cardinal( MbMemLimit ) * 1024 * 1024;
const CoreMemSize               = MemLimit div 4;
const PartSortHeaderSize        = 2 * sizeof( UInt64 );               //  размер последовательности + к-во строк в п-ти
const PartSortStringHeaderSize  = sizeof( UInt64 ) + sizeof( Word );  //  размер строки + смещение строки

type

  PString = ^TString;
  TString = packed record
    Offset  : Int64;                            //  смещение строки в исходном файле
    Length  : Word;                             //  длина строки (не более 500 по условию задачи)
    function Size: Cardinal; inline;            //  размер структуры
    function Ptr: PAnsiChar; inline;            //  указатель на строку
    function Next: PString; inline;             //  следующая структура
    function Less( const r: TString ): Boolean; //  предикат сравнения
    function Comp( const r: TString ): Integer; //  функция сравнения
  end;

  TCommonThread = class(TThread)
  private
    m_Progress        : Single;   //  процент исполнения работы потока
  protected
    m_pBuffer         : Pointer;  //  рабочий буфер
    m_pLastOutputTime : PInteger; //  время последней операции обновления статуса программы
    m_hWakeup         : THandle;  //  событие пробуждения потока
    m_fAbort          : Boolean;  //  флаг для завершения потока
    procedure UpdateProgress( Value: Single );
    procedure Init( pBuffer: Pointer; pLastOutputTime: PInteger );
  public
    constructor Create;
    destructor Destroy; override;
    procedure Abort;
    procedure Wakeup;
    property Progress: Single read m_Progress;
  end;

//  используемые inline-версии (для генерации inline-методов)
function Min( a, b: Word ): Word; inline; overload;
function Min( a, b: Cardinal ): Cardinal; inline; overload;

implementation

uses Winapi.Windows, System.AnsiStrings, SDIMAIN;

function Min( a, b: Word ): Word;
begin
  if a < b then
    Result  := a
  else
    Result  := b;
end;

function Min( a, b: Cardinal ): Cardinal;
begin
  if a < b then
    Result  := a
  else
    Result  := b;
end;

{ TString }

function TString.Comp(const r: TString): Integer;
begin
  if Length < r.Length then
    Result  := -1
  else if Length > r.Length then
    Result  := +1
  else
    Result  := System.AnsiStrings.AnsiStrLComp( Ptr, r.Ptr, Min( Length, 50 ) );
end;

function TString.Less( const r: TString ): Boolean;
begin
  Result  := 0 > Comp( r );
end;

function TString.Next: PString;
begin
  Result  := PString( Ptr + Min( Length, 50 ) );
end;

function TString.Ptr: PAnsiChar;
begin
  Result  := @Length;
  Inc( PWord( Result ) );
end;

function TString.Size: Cardinal;
begin
  Result  := Min( Length, 50 ) + PartSortStringHeaderSize;
end;

{ TCommonThread }

procedure TCommonThread.Abort;
begin
  m_fAbort  := True;
  Wakeup;
end;

constructor TCommonThread.Create;
begin
  m_fAbort  := False;
  m_hWakeup := CreateEvent( nil, False, False, nil );
  inherited Create( False );
end;

destructor TCommonThread.Destroy;
begin
  CloseHandle( m_hWakeup );
  inherited;
end;

procedure TCommonThread.Init( pBuffer: Pointer; pLastOutputTime: PInteger );
begin
  m_pBuffer          := pBuffer;
  m_pLastOutputTime  := pLastOutputTime;
end;

procedure TCommonThread.UpdateProgress(Value: Single);
var Now, Old: Integer;
begin
  m_Progress  := Value;
  Now         := GetTickCount;
  Old         := m_pLastOutputTime^;
  if ( Now - Old ) > 800 then
    if ( InterlockedCompareExchange( m_pLastOutputTime^, Now, Old ) = Old ) and not m_fAbort then
      Synchronize( SDIAppForm.UpdateStatus );
end;

procedure TCommonThread.Wakeup;
begin
  SetEvent( m_hWakeup );
end;

end.
