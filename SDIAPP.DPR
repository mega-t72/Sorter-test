program Sdiapp;

uses
  Forms,
  SDIMAIN in 'SDIMAIN.PAS' {SDIAppForm},
  ABOUT in 'ABOUT.PAS' {AboutBox},
  UnitPartSortThread in 'UnitPartSortThread.pas',
  UnitMergeThread in 'UnitMergeThread.pas',
  UnitCommon in 'UnitCommon.pas',
  UnitTranslateThread in 'UnitTranslateThread.pas';

{$R *.RES}

begin
  Application.Initialize;
  Application.CreateForm(TSDIAppForm, SDIAppForm);
  Application.CreateForm(TAboutBox, AboutBox);
  Application.Run;
end.
 
