!============================================================================
! MyImportExport - generic import / export for any dictionary table
!   Formats : CSV, TSV, JSON, XML, XLS, XLSX  (via MIEConvert.exe)
!   Repo    : https://github.com/robertorenz/myimportexport
!============================================================================
  OMIT('_EndOfInclude_',_MyImportExportPresent_)
_MyImportExportPresent_ EQUATE(1)

! Project defines (set by the MyImportExportGlobal template):
!   EXE, or the DLL that holds the class : _MIEDllMode_=>0;_MIELinkMode_=>1
!   DLL / EXE using it from another DLL  : _MIEDllMode_=>1;_MIELinkMode_=>0

MIE:Mode:Export      EQUATE(1)
MIE:Mode:Import      EQUATE(2)

MIE:Import:Add       EQUATE(1)    ! add new records only
MIE:Import:Upsert    EQUATE(2)    ! add, or update when the primary key exists
MIE:Import:Update    EQUATE(3)    ! update existing records only
MIE:Import:Replace   EQUATE(4)    ! delete all records, then add

! One row per table field that can be imported / exported
MIE_FieldQueue       QUEUE,TYPE
Label                  STRING(100)   ! CUS:Name
Name                   STRING(100)   ! Name (default column header)
FieldType              STRING(20)    ! STRING, LONG, DATE, TIME, DECIMAL ...
Picture                STRING(40)    ! dictionary display picture
Ref                    ANY           ! reference to the record field
IsKey                  BYTE          ! part of the primary key
Selected               BYTE          ! include in import / export
Header                 STRING(128)   ! export: column header written
SourceCol              LONG          ! import: column number in source (0 = not mapped)
SourceName             STRING(128)   ! import: source column name
Order                  LONG          ! export column order
                     END

! Columns found in the source file (import)
MIE_ColumnQueue      QUEUE,TYPE
Name                   STRING(128)
Sample                 STRING(128)
                     END

MIE_SheetQueue       QUEUE,TYPE
Name                   STRING(128)
                     END

! Values of one data row while importing
MIE_ValueQueue       QUEUE,TYPE
Value                  &STRING
Len                    LONG
                     END

! Tables offered by the multi-table export (AddTable)
MIE_TableQueue       QUEUE,TYPE
Name                   STRING(100)   ! table label, passed to SetupTable
Description            STRING(128)   ! dictionary description
Selected               BYTE          ! include in the multi-table export
                     END

! Tables exported so far in a batch (BatchAdd)
MIE_BatchQueue       QUEUE,TYPE
Name                   STRING(100)   ! collection / sheet / element name
TsvFile                CSTRING(261)  ! its intermediate file
Records                LONG          ! records written
                     END

MyImportExportClass  CLASS,TYPE,MODULE('MyImportExport.clw'),LINK('MyImportExport.clw',_MIELinkMode_),DLL(_MIEDllMode_)
Fields                 &MIE_FieldQueue
Columns                &MIE_ColumnQueue
Sheets                 &MIE_SheetQueue
Values                 &MIE_ValueQueue
Tables                 &MIE_TableQueue
Batch                  &MIE_BatchQueue
TableFile              &FILE
TableKey               &KEY
TableName              STRING(100)
WeOpened               BYTE,PROTECTED
KeyMapped              BYTE
! --- settings -------------------------------------------------------------
Mode                   BYTE          ! MIE:Mode:Export / MIE:Mode:Import
Format                 STRING(8)     ! CSV TSV JSON XML XLS XLSX
FileName               CSTRING(261)
SheetName              CSTRING(129)
HasHeader              BYTE
Delimiter              CSTRING(6)    ! , ; | tab
Encoding               CSTRING(16)   ! auto/utf8/utf8bom/ansi/<codepage>
XmlRoot                CSTRING(65)
XmlRow                 CSTRING(65)
JsonRoot               CSTRING(65)
ImportMode             BYTE
ReplaceSheet           BYTE          ! xlsx export: keep other sheets
UsePictures            BYTE          ! CSV/TSV/XML export: dates/times/numbers with dictionary pictures
HelperPath             CSTRING(261)  ! full path of MIEConvert.exe
IniFile                CSTRING(261)  ! where mappings are saved
Silent                 BYTE          ! no messages
! --- results --------------------------------------------------------------
ErrorText              CSTRING(1025)
Processed              LONG
Added                  LONG
Updated                LONG
Skipped                LONG
Failed                 LONG
LastFailure            CSTRING(513)
! --- UI -------------------------------------------------------------------
ProgressControl        SIGNED
StatusControl          SIGNED
! --- internal buffers -----------------------------------------------------
LineBuf                &STRING,PROTECTED
LineLen                LONG
LineCap                LONG,PROTECTED
InPos                  LONG,PROTECTED
InLen                  LONG,PROTECTED
InEOF                  BYTE,PROTECTED
OutPos                 LONG,PROTECTED
IOOpen                 BYTE,PROTECTED
Writing                BYTE,PROTECTED
Scratch                &STRING,PROTECTED
ScratchCap             LONG,PROTECTED
TempSeq                LONG,PROTECTED
! --- methods --------------------------------------------------------------
Construct              PROCEDURE
Destruct               PROCEDURE,VIRTUAL
Init                   PROCEDURE,VIRTUAL
Kill                   PROCEDURE,VIRTUAL
SetTable               PROCEDURE(*FILE pFile,STRING pName,<*KEY pPrimaryKey>)
AddField               PROCEDURE(STRING pLabel,STRING pName,STRING pType,STRING pPicture,*? pField,BYTE pIsKey=0)
ClearFields            PROCEDURE
SelectAll              PROCEDURE(BYTE pOn=1)
AutoMap                PROCEDURE
MapField               PROCEDURE(STRING pLabel,STRING pSourceColumn),BYTE,PROC
FormatFromFileName     PROCEDURE(STRING pFileName),STRING
LoadSheets             PROCEDURE,BYTE,PROC                ! fills SELF.Sheets
LoadColumns            PROCEDURE,BYTE,PROC                ! fills SELF.Columns
Export                 PROCEDURE,BYTE,PROC                ! 0 = ok
Import                 PROCEDURE,BYTE,PROC                ! 0 = ok
Ask                    PROCEDURE(BYTE pMode=0),BYTE,PROC  ! full UI. 1 = something was done
SaveMap                PROCEDURE
LoadMap                PROCEDURE
ResultText             PROCEDURE,STRING
ResolveMap             PROCEDURE,LONG,PROC                ! re-links SourceName -> SourceCol
GetValue               PROCEDURE(LONG pColumn),STRING     ! import: value of column in current row
ExeFolder              PROCEDURE,STRING                   ! folder of the running exe, with a trailing backslash
ResetCounters          PROCEDURE
! --- several tables in one file -------------------------------------------
AddTable               PROCEDURE(STRING pName,<STRING pDescription>)  ! offer a table to AskTables / ExportTables
ExportTsv              PROCEDURE(STRING pTsvFile),BYTE,PROC           ! current table -> intermediate file. 0 = ok
BatchBegin             PROCEDURE                                      ! start collecting tables
BatchAdd               PROCEDURE(STRING pName),BYTE,PROC              ! export the current table into the batch
BatchFinish            PROCEDURE,BYTE,PROC                            ! write FileName in Format with every table. 0 = ok
BatchCancel            PROCEDURE                                      ! drop the batch and its temp files
ExportTables           PROCEDURE,BYTE,PROC                            ! every Selected table of Tables -> FileName. 0 = ok
AskTables              PROCEDURE,BYTE,PROC                            ! window: pick tables, format, file. 1 = exported
SaveTablesMap          PROCEDURE
LoadTablesMap          PROCEDURE
IsMultiFormat          PROCEDURE(<STRING pFormat>),BYTE               ! 1 = JSON, XML, XLSX, XLS (one file holds every table)
BatchFileName          PROCEDURE(STRING pName),STRING                 ! CSV / TSV: the per-table file name
! --- virtual hooks ------------------------------------------------------
OpenTable              PROCEDURE,BYTE,VIRTUAL
CloseTable             PROCEDURE,VIRTUAL
PrimeRecord            PROCEDURE,VIRTUAL
CancelPrime            PROCEDURE,VIRTUAL
InsertRecord           PROCEDURE,BYTE,VIRTUAL
UpdateRecord           PROCEDURE,BYTE,VIRTUAL
FetchRecord            PROCEDURE,BYTE,VIRTUAL
DeleteRecord           PROCEDURE,BYTE,VIRTUAL
ValidateRecord         PROCEDURE,BYTE,VIRTUAL
ExportFilter           PROCEDURE,BYTE,VIRTUAL
TakeProgress           PROCEDURE(LONG pDone,LONG pTotal=0),VIRTUAL
ShowMessage            PROCEDURE(STRING pText,STRING pCaption,<STRING pIcon>),VIRTUAL
SetupTable             PROCEDURE(STRING pName),BYTE,VIRTUAL           ! SetTable + AddField for a table by name. 0 = ok
! --- internals ------------------------------------------------------------
RunHelper              PROCEDURE(STRING pArgs),BYTE,PROTECTED
TempName               PROCEDURE(STRING pExt),STRING,PROTECTED
Quote                  PROCEDURE(STRING pText),STRING,PROTECTED
Escape                 PROCEDURE(STRING pText),STRING,PROTECTED
UnescapeTo             PROCEDURE(STRING pText,*STRING pOut),LONG,PROTECTED
SplitLine              PROCEDURE(STRING pLine),PROTECTED
FreeValues             PROCEDURE,PROTECTED
FieldToText            PROCEDURE,STRING,PROTECTED
TypeCode               PROCEDURE,STRING,PROTECTED
PicturesApply          PROCEDURE,BYTE                     ! 1 = UsePictures and a text format (CSV, TSV, XML)
TextToField            PROCEDURE(STRING pText),PROTECTED
ApplyRow               PROCEDURE,PROTECTED
NormalName             PROCEDURE(STRING pText),STRING,PROTECTED
CommonArgs             PROCEDURE,STRING,PROTECTED
IsDate                 PROCEDURE,BYTE,PROTECTED
IsTime                 PROCEDURE,BYTE,PROTECTED
IsNumber               PROCEDURE,BYTE,PROTECTED
OpenRead               PROCEDURE(STRING pName),BYTE,PROTECTED
OpenWrite              PROCEDURE(STRING pName),BYTE,PROTECTED
CloseIO                PROCEDURE,PROTECTED
ReadLine               PROCEDURE,BYTE,PROTECTED
AppendLine             PROCEDURE(STRING pText),PROTECTED
WriteText              PROCEDURE(STRING pText),PROTECTED
FlushOut               PROCEDURE,PROTECTED
EnsureScratch          PROCEDURE(LONG pSize),PROTECTED
                     END

  _EndOfInclude_
