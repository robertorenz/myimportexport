!============================================================================
! MyImportExport - generic import / export for any dictionary table
!   Repo : https://github.com/robertorenz/myimportexport
!============================================================================
  MEMBER()

  MAP
    MODULE('Win32')
      MIE_GetModuleFileName(LONG hModule,*CSTRING lpFilename,LONG nSize),LONG,PASCAL,RAW,NAME('GetModuleFileNameA')
      MIE_GetTempPath(LONG nBufferLength,*CSTRING lpBuffer),LONG,PASCAL,RAW,NAME('GetTempPathA')
      MIE_WriteProfile(*CSTRING lpSection,LONG lpKey,LONG lpValue,*CSTRING lpFile),LONG,PASCAL,RAW,PROC,NAME('WritePrivateProfileStringA')
    END
  END

  INCLUDE('MyImportExport.inc'),ONCE
  INCLUDE('KEYCODES.CLW'),ONCE

MIE:IOName           CSTRING(261),THREAD
MIE:IOFile           FILE,DRIVER('DOS'),NAME(MIE:IOName),PRE(MIEIO),CREATE,THREAD
Record                 RECORD
Buf                      STRING(32768)
                       END
                     END

MIE:NumericTypes     EQUATE(',BYTE,SHORT,USHORT,LONG,ULONG,SIGNED,UNSIGNED,REAL,SREAL,DECIMAL,PDECIMAL,BFLOAT4,BFLOAT8,')
MIE:NotMapped        EQUATE('(not mapped)')

!============================================================================
MyImportExportClass.Construct PROCEDURE
  CODE
  SELF.Fields  &= NEW MIE_FieldQueue
  SELF.Columns &= NEW MIE_ColumnQueue
  SELF.Sheets  &= NEW MIE_SheetQueue
  SELF.Values  &= NEW MIE_ValueQueue
  SELF.Tables  &= NEW MIE_TableQueue
  SELF.Batch   &= NEW MIE_BatchQueue
  SELF.LineCap  = 4096
  SELF.LineBuf &= NEW STRING(SELF.LineCap)
  SELF.Mode       = MIE:Mode:Export
  SELF.Format     = 'CSV'
  SELF.HasHeader  = 1
  SELF.Delimiter  = ','
  SELF.ImportMode = MIE:Import:Add
  SELF.HelperPath = SELF.ExeFolder() & 'MIEConvert.exe'
  SELF.IniFile    = SELF.ExeFolder() & 'MyImportExport.ini'

MyImportExportClass.Destruct PROCEDURE
  CODE
  SELF.CloseIO()
  SELF.BatchCancel()
  SELF.ClearFields()
  SELF.FreeValues()
  DISPOSE(SELF.Fields)
  DISPOSE(SELF.Tables)
  DISPOSE(SELF.Batch)
  DISPOSE(SELF.Columns)
  DISPOSE(SELF.Sheets)
  DISPOSE(SELF.Values)
  IF NOT SELF.LineBuf &= NULL THEN DISPOSE(SELF.LineBuf).
  IF NOT SELF.Scratch &= NULL THEN DISPOSE(SELF.Scratch).

MyImportExportClass.Init PROCEDURE
  CODE
  SELF.ResetCounters()
  SELF.ErrorText = ''

MyImportExportClass.Kill PROCEDURE
  CODE
  SELF.CloseIO()
  SELF.ClearFields()
  SELF.FreeValues()
  FREE(SELF.Columns)
  FREE(SELF.Sheets)
  SELF.BatchCancel()
  FREE(SELF.Tables)

MyImportExportClass.ResetCounters PROCEDURE
  CODE
  SELF.Processed   = 0
  SELF.Added       = 0
  SELF.Updated     = 0
  SELF.Skipped     = 0
  SELF.Failed      = 0
  SELF.LastFailure = ''
  SELF.ErrorText   = ''

!----------------------------------------------------------------------------
! Table and field registration
!----------------------------------------------------------------------------
MyImportExportClass.SetTable PROCEDURE(*FILE pFile,STRING pName,<*KEY pPrimaryKey>)
  CODE
  SELF.ClearFields()
  SELF.TableFile &= pFile
  SELF.TableName = pName
  IF OMITTED(pPrimaryKey)
    SELF.TableKey &= NULL
  ELSE
    SELF.TableKey &= pPrimaryKey
  END

MyImportExportClass.AddField PROCEDURE(STRING pLabel,STRING pName,STRING pType,STRING pPicture,*? pField,BYTE pIsKey=0)
  CODE
  CLEAR(SELF.Fields)
  SELF.Fields.Label      = pLabel
  SELF.Fields.Name       = pName
  SELF.Fields.FieldType  = UPPER(pType)
  SELF.Fields.Picture    = pPicture
  SELF.Fields.Ref       &= pField
  SELF.Fields.IsKey      = pIsKey
  SELF.Fields.Selected   = 1
  SELF.Fields.Header     = pName
  SELF.Fields.Order      = RECORDS(SELF.Fields) + 1
  ADD(SELF.Fields)

MyImportExportClass.ClearFields PROCEDURE
I                      LONG
  CODE
  LOOP I = RECORDS(SELF.Fields) TO 1 BY -1
    GET(SELF.Fields,I)
    SELF.Fields.Ref &= NULL
    PUT(SELF.Fields)
  END
  FREE(SELF.Fields)

MyImportExportClass.SelectAll PROCEDURE(BYTE pOn=1)
I                      LONG
  CODE
  LOOP I = 1 TO RECORDS(SELF.Fields)
    GET(SELF.Fields,I)
    SELF.Fields.Selected = pOn
    PUT(SELF.Fields)
  END

!----------------------------------------------------------------------------
! Mapping
!----------------------------------------------------------------------------
MyImportExportClass.NormalName PROCEDURE(STRING pText)
S                      CSTRING(256)
R                      CSTRING(256)
I                      LONG
  CODE
  S = UPPER(CLIP(LEFT(pText)))
  LOOP I = LEN(S) TO 1 BY -1             ! drop a PRE: prefix
    IF S[I] = ':'
      S = SUB(S,I+1,LEN(S)-I)
      BREAK
    END
  END
  LOOP I = 1 TO LEN(S)
    IF INSTRING(S[I],' _-.:[]',1,1) THEN CYCLE.
    R = R & S[I]
  END
  RETURN R

MyImportExportClass.AutoMap PROCEDURE
I                      LONG
C                      LONG
N1                     CSTRING(256)
N2                     CSTRING(256)
N3                     CSTRING(256)
CN                     CSTRING(256)
  CODE
  IF RECORDS(SELF.Columns) = 0 THEN RETURN.
  SORT(SELF.Fields,SELF.Fields.Order)
  LOOP I = 1 TO RECORDS(SELF.Fields)
    GET(SELF.Fields,I)
    SELF.Fields.SourceCol  = 0
    SELF.Fields.SourceName = ''
    IF SELF.HasHeader
      N1 = SELF.NormalName(SELF.Fields.Name)
      N2 = SELF.NormalName(SELF.Fields.Label)
      N3 = SELF.NormalName(SELF.Fields.Header)
      LOOP C = 1 TO RECORDS(SELF.Columns)
        GET(SELF.Columns,C)
        CN = SELF.NormalName(SELF.Columns.Name)
        IF CN <> '' AND (CN = N1 OR CN = N2 OR CN = N3)
          SELF.Fields.SourceCol  = C
          SELF.Fields.SourceName = SELF.Columns.Name
          BREAK
        END
      END
    ELSIF I <= RECORDS(SELF.Columns)        ! no header: map by position
      GET(SELF.Columns,I)
      SELF.Fields.SourceCol  = I
      SELF.Fields.SourceName = SELF.Columns.Name
    END
    SELF.Fields.Selected = CHOOSE(SELF.Fields.SourceCol > 0,1,0)
    PUT(SELF.Fields)
  END

MyImportExportClass.MapField PROCEDURE(STRING pLabel,STRING pSourceColumn)
I                      LONG
C                      LONG
  CODE
  LOOP I = 1 TO RECORDS(SELF.Fields)
    GET(SELF.Fields,I)
    IF UPPER(CLIP(SELF.Fields.Label)) <> UPPER(CLIP(pLabel)) THEN CYCLE.
    SELF.Fields.SourceCol  = 0
    SELF.Fields.SourceName = pSourceColumn
    SELF.Fields.Selected   = CHOOSE(pSourceColumn <> '',1,0)
    LOOP C = 1 TO RECORDS(SELF.Columns)
      GET(SELF.Columns,C)
      IF UPPER(CLIP(SELF.Columns.Name)) = UPPER(CLIP(pSourceColumn))
        SELF.Fields.SourceCol = C
        BREAK
      END
    END
    PUT(SELF.Fields)
    RETURN 1
  END
  RETURN 0

MyImportExportClass.ResolveMap PROCEDURE
I                      LONG
C                      LONG
Mapped                 LONG
  CODE
  SELF.KeyMapped = 0
  LOOP I = 1 TO RECORDS(SELF.Fields)
    GET(SELF.Fields,I)
    SELF.Fields.SourceCol = 0
    IF SELF.Fields.SourceName <> ''
      LOOP C = 1 TO RECORDS(SELF.Columns)
        GET(SELF.Columns,C)
        IF UPPER(CLIP(SELF.Columns.Name)) = UPPER(CLIP(SELF.Fields.SourceName))
          SELF.Fields.SourceCol = C
          BREAK
        END
      END
    END
    IF SELF.Fields.SourceCol AND SELF.Fields.Selected
      Mapped += 1
      IF SELF.Fields.IsKey THEN SELF.KeyMapped = 1.
    END
    PUT(SELF.Fields)
  END
  RETURN Mapped

MyImportExportClass.FormatFromFileName PROCEDURE(STRING pFileName)
I                      LONG
E                      CSTRING(20)
  CODE
  LOOP I = LEN(CLIP(pFileName)) TO 1 BY -1
    CASE pFileName[I]
    OF '.'
      E = UPPER(SUB(pFileName,I+1,LEN(CLIP(pFileName))-I))
      BREAK
    OF '\'
    OROF '/'
      BREAK
    END
  END
  CASE E
  OF 'TXT'
    RETURN 'TSV'
  OF 'CSV' OROF 'TSV' OROF 'JSON' OROF 'XML' OROF 'XLS' OROF 'XLSX'
    RETURN E
  END
  RETURN ''

!----------------------------------------------------------------------------
! Source discovery (import)
!----------------------------------------------------------------------------
MyImportExportClass.LoadSheets PROCEDURE
Tmp                    CSTRING(261)
  CODE
  FREE(SELF.Sheets)
  IF NOT INLIST(UPPER(CLIP(SELF.Format)),'XLS','XLSX') THEN RETURN 0.
  IF SELF.FileName = '' OR NOT EXISTS(SELF.FileName) THEN RETURN 0.
  Tmp = SELF.TempName('txt')
  IF SELF.RunHelper('sheets ' & SELF.Quote(SELF.FileName) & ' ' & SELF.Quote(Tmp)) THEN RETURN 1.
  IF SELF.OpenRead(Tmp) = 0
    LOOP WHILE SELF.ReadLine()
      IF SELF.LineLen = 0 THEN CYCLE.
      SELF.Sheets.Name = SELF.LineBuf[1 : SELF.LineLen]
      ADD(SELF.Sheets)
    END
    SELF.CloseIO()
  END
  REMOVE(Tmp)
  RETURN 0

MyImportExportClass.LoadColumns PROCEDURE
Tmp                    CSTRING(261)
SaveMode               BYTE
RC                     BYTE
C                      LONG
  CODE
  FREE(SELF.Columns)
  IF SELF.FileName = '' OR NOT EXISTS(SELF.FileName)
    SELF.ErrorText = 'File not found: ' & SELF.FileName
    RETURN 1
  END
  IF SELF.Format = '' THEN SELF.Format = SELF.FormatFromFileName(SELF.FileName).
  Tmp = SELF.TempName('tsv')
  SaveMode  = SELF.Mode
  SELF.Mode = MIE:Mode:Import
  RC = SELF.RunHelper('import ' & SELF.Quote(SELF.FileName) & ' ' & SELF.Quote(Tmp) & SELF.CommonArgs() & ' --maxrows 5')
  SELF.Mode = SaveMode
  IF RC THEN RETURN 1.
  IF SELF.OpenRead(Tmp) = 0
    IF SELF.ReadLine()
      SELF.SplitLine(SELF.LineBuf[1 : SELF.LineLen + 1])     ! +1 keeps the slice valid when empty
      LOOP C = 1 TO RECORDS(SELF.Values)
        CLEAR(SELF.Columns)
        SELF.Columns.Name = SELF.GetValue(C)
        ADD(SELF.Columns)
      END
      LOOP WHILE SELF.ReadLine()                              ! first data row = sample values
        IF SELF.LineLen = 0 THEN CYCLE.
        SELF.SplitLine(SELF.LineBuf[1 : SELF.LineLen + 1])
        LOOP C = 1 TO RECORDS(SELF.Columns)
          GET(SELF.Columns,C)
          SELF.Columns.Sample = SELF.GetValue(C)
          PUT(SELF.Columns)
        END
        BREAK
      END
    END
    SELF.CloseIO()
  END
  REMOVE(Tmp)
  SELF.FreeValues()
  RETURN 0

!----------------------------------------------------------------------------
! Export
!----------------------------------------------------------------------------
MyImportExportClass.Export PROCEDURE
Tmp                    CSTRING(261)
RC                     BYTE
  CODE
  SELF.BatchCancel()
  SELF.ResetCounters()
  SELF.Mode = MIE:Mode:Export
  IF SELF.FileName = ''
    SELF.ErrorText = 'Please choose the file to export to.'
    RETURN 1
  END
  IF SELF.Format = '' THEN SELF.Format = SELF.FormatFromFileName(SELF.FileName).
  IF SELF.Format = '' THEN SELF.Format = 'CSV'.
  Tmp = SELF.TempName('tsv')
  IF SELF.ExportTsv(Tmp)
    REMOVE(Tmp)
    RETURN 1
  END
  RC = SELF.RunHelper('export ' & SELF.Quote(Tmp) & ' ' & SELF.Quote(SELF.FileName) & SELF.CommonArgs())
  REMOVE(Tmp)
  RETURN RC

!----------------------------------------------------------------------------
! ExportTsv - the current table's selected fields -> intermediate file.
! Adds to Processed / Skipped; does not reset them (a batch sums them).
!----------------------------------------------------------------------------
MyImportExportClass.ExportTsv PROCEDURE(STRING pTsvFile)
I                      LONG
Cnt                    LONG
Total                  LONG
First                  BYTE
Sel                    LONG
  CODE
  SELF.Mode = MIE:Mode:Export
  IF SELF.TableFile &= NULL
    SELF.ErrorText = 'No table was set.'
    RETURN 1
  END
  SORT(SELF.Fields,SELF.Fields.Order)
  LOOP I = 1 TO RECORDS(SELF.Fields)
    GET(SELF.Fields,I)
    IF SELF.Fields.Selected THEN Sel += 1.
  END
  IF Sel = 0
    SELF.ErrorText = 'Please select at least one field of ' & CLIP(SELF.TableName) & ' to export.'
    RETURN 1
  END
  IF SELF.OpenWrite(pTsvFile) THEN RETURN 1.
  First = 1                                  ! header line
  LOOP I = 1 TO RECORDS(SELF.Fields)
    GET(SELF.Fields,I)
    IF NOT SELF.Fields.Selected THEN CYCLE.
    IF NOT First THEN SELF.WriteText('<9>').
    First = 0
    SELF.WriteText(SELF.Escape(CHOOSE(SELF.Fields.Header <> '',SELF.Fields.Header,SELF.Fields.Name)))
  END
  SELF.WriteText('<13,10>')
  First = 1                                  ! type line
  LOOP I = 1 TO RECORDS(SELF.Fields)
    GET(SELF.Fields,I)
    IF NOT SELF.Fields.Selected THEN CYCLE.
    IF NOT First THEN SELF.WriteText('<9>').
    First = 0
    SELF.WriteText(SELF.TypeCode())
  END
  SELF.WriteText('<13,10>')
  IF SELF.OpenTable()
    SELF.CloseIO()
    RETURN 1
  END
  Total = RECORDS(SELF.TableFile)
  IF SELF.TableKey &= NULL
    SET(SELF.TableFile)
  ELSE
    SET(SELF.TableKey)
  END
  LOOP
    NEXT(SELF.TableFile)
    IF ERRORCODE() THEN BREAK.
    Cnt += 1
    IF NOT SELF.ExportFilter()
      SELF.Skipped += 1
      SELF.TakeProgress(Cnt,Total)
      CYCLE
    END
    First = 1
    LOOP I = 1 TO RECORDS(SELF.Fields)
      GET(SELF.Fields,I)
      IF NOT SELF.Fields.Selected THEN CYCLE.
      IF NOT First THEN SELF.WriteText('<9>').
      First = 0
      SELF.WriteText(SELF.Escape(SELF.FieldToText()))
    END
    SELF.WriteText('<13,10>')
    SELF.Processed += 1
    SELF.TakeProgress(Cnt,Total)
  END
  SELF.CloseTable()
  SELF.CloseIO()
  SELF.TakeProgress(Total,Total)
  RETURN 0

!----------------------------------------------------------------------------
! Import
!----------------------------------------------------------------------------
MyImportExportClass.Import PROCEDURE
Tmp                    CSTRING(261)
C                      LONG
Primed                 BYTE
  CODE
  SELF.ResetCounters()
  SELF.Mode = MIE:Mode:Import
  IF SELF.TableFile &= NULL
    SELF.ErrorText = 'No table was set.'
    RETURN 1
  END
  IF SELF.FileName = '' OR NOT EXISTS(SELF.FileName)
    SELF.ErrorText = 'File not found: ' & SELF.FileName
    RETURN 1
  END
  IF SELF.Format = '' THEN SELF.Format = SELF.FormatFromFileName(SELF.FileName).
  Tmp = SELF.TempName('tsv')
  IF SELF.RunHelper('import ' & SELF.Quote(SELF.FileName) & ' ' & SELF.Quote(Tmp) & SELF.CommonArgs()) THEN RETURN 1.
  IF SELF.OpenRead(Tmp) THEN RETURN 1.
  IF NOT SELF.ReadLine()
    SELF.ErrorText = 'The file contains no data.'
    DO Cleanup
    RETURN 1
  END
  FREE(SELF.Columns)                         ! header line = source columns
  SELF.SplitLine(SELF.LineBuf[1 : SELF.LineLen + 1])
  LOOP C = 1 TO RECORDS(SELF.Values)
    CLEAR(SELF.Columns)
    SELF.Columns.Name = SELF.GetValue(C)
    ADD(SELF.Columns)
  END
  IF SELF.ResolveMap() = 0
    SELF.ErrorText = 'No source columns are mapped to fields of ' & CLIP(SELF.TableName) & '.'
    DO Cleanup
    RETURN 1
  END
  IF INLIST(SELF.ImportMode,MIE:Import:Upsert,MIE:Import:Update) AND (SELF.TableKey &= NULL OR NOT SELF.KeyMapped)
    SELF.ErrorText = 'To update existing records the primary key field(s) must be mapped.'
    DO Cleanup
    RETURN 1
  END
  IF SELF.OpenTable()
    DO Cleanup
    RETURN 1
  END
  IF SELF.ImportMode = MIE:Import:Replace
    C = RECORDS(SELF.TableFile) + 1
    LOOP C TIMES                               ! bounded: never spin if a delete is ignored
      SET(SELF.TableFile)
      NEXT(SELF.TableFile)
      IF ERRORCODE() THEN BREAK.
      IF SELF.DeleteRecord()
        SELF.ErrorText = 'Could not delete the existing records: ' & ERROR()
        SELF.CloseTable()
        DO Cleanup
        RETURN 1
      END
    END
  END
  LOOP WHILE SELF.ReadLine()
    IF SELF.LineLen = 0 THEN CYCLE.
    SELF.SplitLine(SELF.LineBuf[1 : SELF.LineLen + 1])
    SELF.Processed += 1
    CASE SELF.ImportMode
    OF MIE:Import:Upsert
    OROF MIE:Import:Update
      CLEAR(SELF.TableFile)
      SELF.ApplyRow()
      IF SELF.FetchRecord() = 0
        SELF.ApplyRow()
        IF SELF.ValidateRecord()
          SELF.Skipped += 1
        ELSIF SELF.UpdateRecord() = 0
          SELF.Updated += 1
        ELSE
          SELF.Failed += 1
          DO NoteFailure
        END
      ELSIF SELF.ImportMode = MIE:Import:Upsert
        DO AddRow
      ELSE
        SELF.Skipped += 1
      END
    ELSE
      DO AddRow
    END
    SELF.TakeProgress(SELF.Processed)
  END
  SELF.CloseTable()
  DO Cleanup
  RETURN 0

AddRow ROUTINE
  CLEAR(SELF.TableFile)
  Primed = 0
  IF NOT SELF.KeyMapped
    SELF.PrimeRecord()
    Primed = 1
  END
  SELF.ApplyRow()
  IF SELF.ValidateRecord()
    SELF.Skipped += 1
    IF Primed THEN SELF.CancelPrime().
  ELSIF SELF.InsertRecord() = 0
    SELF.Added += 1
  ELSE
    SELF.Failed += 1
    DO NoteFailure
    IF Primed THEN SELF.CancelPrime().
  END

NoteFailure ROUTINE
  SELF.LastFailure = 'Row ' & SELF.Processed & ': ' & CLIP(ERROR())
  IF FILEERRORCODE() THEN SELF.LastFailure = SELF.LastFailure & ' (' & CLIP(FILEERROR()) & ')'.

Cleanup ROUTINE
  SELF.CloseIO()
  REMOVE(Tmp)
  SELF.FreeValues()

MyImportExportClass.ApplyRow PROCEDURE
I                      LONG
  CODE
  LOOP I = 1 TO RECORDS(SELF.Fields)
    GET(SELF.Fields,I)
    IF SELF.Fields.Selected AND SELF.Fields.SourceCol
      SELF.TextToField(SELF.GetValue(SELF.Fields.SourceCol))
    END
  END

MyImportExportClass.GetValue PROCEDURE(LONG pColumn)
  CODE
  IF pColumn < 1 OR pColumn > RECORDS(SELF.Values) THEN RETURN ''.
  GET(SELF.Values,pColumn)
  IF SELF.Values.Len = 0 THEN RETURN ''.
  RETURN SELF.Values.Value[1 : SELF.Values.Len]

!----------------------------------------------------------------------------
! Value conversion
!----------------------------------------------------------------------------
MyImportExportClass.IsNumber PROCEDURE
  CODE
  RETURN CHOOSE(INSTRING(',' & UPPER(CLIP(SELF.Fields.FieldType)) & ',',MIE:NumericTypes,1,1) > 0,1,0)

MyImportExportClass.IsDate PROCEDURE
  CODE
  IF UPPER(SELF.Fields.FieldType) = 'DATE' THEN RETURN 1.
  IF SELF.IsNumber() AND UPPER(SUB(LEFT(SELF.Fields.Picture),1,2)) = '@D' THEN RETURN 1.
  RETURN 0

MyImportExportClass.IsTime PROCEDURE
  CODE
  IF UPPER(SELF.Fields.FieldType) = 'TIME' THEN RETURN 1.
  IF SELF.IsNumber() AND UPPER(SUB(LEFT(SELF.Fields.Picture),1,2)) = '@T' THEN RETURN 1.
  RETURN 0

MyImportExportClass.TypeCode PROCEDURE
  CODE
  ! Pictures only apply to the text formats (see PicturesApply); JSON, XLSX
  ! and XLS always get typed numbers, dates and times.
  IF SELF.PicturesApply() AND SELF.Fields.Picture <> '' AND (SELF.IsDate() OR SELF.IsTime() OR SELF.IsNumber())
    RETURN 'S'
  END
  IF SELF.IsDate() THEN RETURN 'D'.
  IF SELF.IsTime() THEN RETURN 'T'.
  IF SELF.IsNumber() THEN RETURN 'N'.
  RETURN 'S'

MyImportExportClass.PicturesApply PROCEDURE
  CODE
  ! Display pictures make sense where everything is text anyway. JSON, XLSX and
  ! XLS have real number and date types: a picture such as @n-14.2 (1,234.56)
  ! would turn numbers into strings there, so they always get typed values.
  RETURN CHOOSE(SELF.UsePictures AND INLIST(UPPER(CLIP(SELF.Format)),'CSV','TSV','XML') > 0,1,0)

MyImportExportClass.FieldToText PROCEDURE
Pic                    CSTRING(41)
  CODE
  Pic = CLIP(LEFT(SELF.Fields.Picture))
  IF SELF.IsDate()
    IF SELF.Fields.Ref = 0 THEN RETURN ''.
    IF SELF.PicturesApply() AND Pic <> '' THEN RETURN CLIP(LEFT(FORMAT(SELF.Fields.Ref,Pic))).
    RETURN FORMAT(SELF.Fields.Ref,@D10-)
  ELSIF SELF.IsTime()
    IF SELF.Fields.Ref = 0 THEN RETURN ''.
    IF SELF.PicturesApply() AND Pic <> '' THEN RETURN CLIP(LEFT(FORMAT(SELF.Fields.Ref,Pic))).
    RETURN FORMAT(SELF.Fields.Ref,@T04)
  ELSIF SELF.IsNumber()
    IF SELF.PicturesApply() AND Pic <> '' THEN RETURN CLIP(LEFT(FORMAT(SELF.Fields.Ref,Pic))).
    RETURN CLIP(LEFT(SELF.Fields.Ref))
  END
  RETURN CLIP(SELF.Fields.Ref)

MyImportExportClass.TextToField PROCEDURE(STRING pText)
T                      CSTRING(256)
R                      CSTRING(256)
Pic                    CSTRING(41)
P                      LONG
H                      LONG
M                      LONG
S                      LONG
  CODE
  IF NOT SELF.IsDate() AND NOT SELF.IsTime() AND NOT SELF.IsNumber()
    SELF.Fields.Ref = pText
    RETURN
  END
  T   = CLIP(LEFT(pText))
  Pic = CLIP(LEFT(SELF.Fields.Picture))
  IF T = ''
    SELF.Fields.Ref = 0
  ELSIF SELF.IsDate()
    IF LEN(T) >= 10 AND INLIST(T[5],'-','/','.') AND T[8] = T[5] AND NUMERIC(T[1:4]) AND NUMERIC(T[6:7]) AND NUMERIC(T[9:10])
      SELF.Fields.Ref = DATE(T[6:7],T[9:10],T[1:4])       ! yyyy-mm-dd[ hh:mm:ss]
    ELSIF LEN(T) = 8 AND NUMERIC(T) AND T >= 18000101
      SELF.Fields.Ref = DATE(T[5:6],T[7:8],T[1:4])        ! yyyymmdd
    ELSIF NUMERIC(T)
      SELF.Fields.Ref = T                                 ! Clarion date number
    ELSE
      IF UPPER(SUB(Pic,1,2)) <> '@D' THEN Pic = '@D2'.
      SELF.Fields.Ref = DEFORMAT(T,Pic)
    END
  ELSIF SELF.IsTime()
    P = INSTRING(' ',T,1,1)                               ! date part in front?
    IF P = 0 AND LEN(T) > 10 AND UPPER(T[11]) = 'T' THEN P = 11.
    IF P AND INSTRING(':',T,1,P) THEN T = SUB(T,P+1,LEN(T)-P).
    P = INSTRING(':',T,1,1)
    IF P > 1 AND NUMERIC(SUB(T,1,P-1))
      H = SUB(T,1,P-1)
      R = SUB(T,P+1,LEN(T)-P)
      P = INSTRING(':',R,1,1)
      IF P
        M = SUB(R,1,P-1)
        S = INT(SUB(R,P+1,LEN(R)-P))
      ELSE
        M = R
        S = 0
      END
      SELF.Fields.Ref = H * 360000 + M * 6000 + S * 100 + 1
    ELSIF NUMERIC(T)
      SELF.Fields.Ref = T                                 ! Clarion time number
    ELSE
      IF UPPER(SUB(Pic,1,2)) <> '@T' THEN Pic = '@T4'.
      SELF.Fields.Ref = DEFORMAT(T,Pic)
    END
  ELSE                                                    ! numeric
    IF NUMERIC(T)
      SELF.Fields.Ref = T
    ELSIF INLIST(UPPER(T),'TRUE','YES','Y')
      SELF.Fields.Ref = 1
    ELSIF INLIST(UPPER(T),'FALSE','NO','N')
      SELF.Fields.Ref = 0
    ELSE
      SELF.Fields.Ref = DEFORMAT(T)
    END
  END

!----------------------------------------------------------------------------
! MIE-TSV escaping
!----------------------------------------------------------------------------
MyImportExportClass.EnsureScratch PROCEDURE(LONG pSize)
  CODE
  IF pSize <= SELF.ScratchCap THEN RETURN.
  IF NOT SELF.Scratch &= NULL THEN DISPOSE(SELF.Scratch).
  SELF.ScratchCap = pSize + 4096
  SELF.Scratch &= NEW STRING(SELF.ScratchCap)

MyImportExportClass.Escape PROCEDURE(STRING pText)
L                      LONG
N                      LONG
I                      LONG
  CODE
  L = LEN(CLIP(pText))
  IF L = 0 THEN RETURN ''.
  IF NOT INSTRING('\',pText[1 : L],1,1) AND NOT INSTRING('<9>',pText[1 : L],1,1) |
     AND NOT INSTRING('<10>',pText[1 : L],1,1) AND NOT INSTRING('<13>',pText[1 : L],1,1)
    RETURN pText[1 : L]
  END
  SELF.EnsureScratch(L * 2)
  LOOP I = 1 TO L
    CASE pText[I]
    OF '\'
      SELF.Scratch[N+1 : N+2] = '\\'
      N += 2
    OF '<9>'
      SELF.Scratch[N+1 : N+2] = '\t'
      N += 2
    OF '<10>'
      SELF.Scratch[N+1 : N+2] = '\n'
      N += 2
    OF '<13>'
      SELF.Scratch[N+1 : N+2] = '\r'
      N += 2
    ELSE
      N += 1
      SELF.Scratch[N] = pText[I]
    END
  END
  RETURN SELF.Scratch[1 : N]

MyImportExportClass.UnescapeTo PROCEDURE(STRING pText,*STRING pOut)
L                      LONG
N                      LONG
I                      LONG
Ch                     STRING(1)
  CODE
  L = LEN(pText)
  I = 1
  LOOP WHILE I <= L
    Ch = pText[I]
    IF Ch = '\' AND I < L
      I += 1
      CASE pText[I]
      OF 't'
        Ch = '<9>'
      OF 'n'
        Ch = '<10>'
      OF 'r'
        Ch = '<13>'
      OF '\'
        Ch = '\'
      ELSE
        N += 1
        pOut[N] = '\'
        Ch = pText[I]
      END
    END
    N += 1
    pOut[N] = Ch
    I += 1
  END
  RETURN N

MyImportExportClass.SplitLine PROCEDURE(STRING pLine)
L                      LONG
Start                  LONG
P                      LONG
Seg                    LONG
  CODE
  SELF.FreeValues()
  L = LEN(pLine) - 1                         ! callers pass one extra byte
  Start = 1
  LOOP
    IF Start > L
      P = L + 1
    ELSE
      P = INSTRING('<9>',pLine[1 : L],1,Start)
      IF P = 0 THEN P = L + 1.
    END
    Seg = P - Start
    CLEAR(SELF.Values)
    SELF.Values.Value &= NULL
    IF Seg > 0
      SELF.Values.Value &= NEW STRING(Seg)
      IF INSTRING('\',pLine[Start : P-1],1,1)
        SELF.Values.Len = SELF.UnescapeTo(pLine[Start : P-1],SELF.Values.Value)
      ELSE
        SELF.Values.Value = pLine[Start : P-1]
        SELF.Values.Len   = Seg
      END
    END
    ADD(SELF.Values)
    IF P > L THEN BREAK.
    Start = P + 1
  END

MyImportExportClass.FreeValues PROCEDURE
I                      LONG
  CODE
  LOOP I = 1 TO RECORDS(SELF.Values)
    GET(SELF.Values,I)
    IF NOT SELF.Values.Value &= NULL THEN DISPOSE(SELF.Values.Value).
  END
  FREE(SELF.Values)

!----------------------------------------------------------------------------
! Intermediate file I/O (DOS driver, buffered)
!----------------------------------------------------------------------------
MyImportExportClass.OpenRead PROCEDURE(STRING pName)
  CODE
  SELF.CloseIO()
  MIE:IOName = CLIP(pName)
  OPEN(MIE:IOFile,40h)                        ! read only, deny none
  IF ERRORCODE()
    SELF.ErrorText = 'Cannot open ' & CLIP(pName) & ': ' & ERROR()
    RETURN 1
  END
  SET(MIE:IOFile)
  SELF.InPos   = 1
  SELF.InLen   = 0
  SELF.InEOF   = 0
  SELF.IOOpen  = 1
  SELF.Writing = 0
  RETURN 0

MyImportExportClass.OpenWrite PROCEDURE(STRING pName)
  CODE
  SELF.CloseIO()
  MIE:IOName = CLIP(pName)
  CREATE(MIE:IOFile)
  IF NOT ERRORCODE() THEN OPEN(MIE:IOFile,12h).   ! read/write, deny all
  IF ERRORCODE()
    SELF.ErrorText = 'Cannot create ' & CLIP(pName) & ': ' & ERROR()
    RETURN 1
  END
  SELF.OutPos  = 0
  SELF.IOOpen  = 1
  SELF.Writing = 1
  RETURN 0

MyImportExportClass.CloseIO PROCEDURE
  CODE
  IF NOT SELF.IOOpen THEN RETURN.
  IF SELF.Writing THEN SELF.FlushOut().
  CLOSE(MIE:IOFile)
  SELF.IOOpen  = 0
  SELF.Writing = 0

MyImportExportClass.ReadLine PROCEDURE
P                      LONG
  CODE
  SELF.LineLen = 0
  IF SELF.InEOF AND SELF.InPos > SELF.InLen THEN RETURN 0.
  LOOP
    IF SELF.InPos > SELF.InLen
      IF SELF.InEOF THEN BREAK.
      NEXT(MIE:IOFile)
      IF ERRORCODE()
        SELF.InEOF = 1
        BREAK
      END
      SELF.InLen = BYTES(MIE:IOFile)
      SELF.InPos = 1
      IF SELF.InLen = 0
        SELF.InEOF = 1
        BREAK
      END
    END
    P = INSTRING('<10>',MIEIO:Buf[1 : SELF.InLen],1,SELF.InPos)
    IF P
      IF P > SELF.InPos THEN SELF.AppendLine(MIEIO:Buf[SELF.InPos : P-1]).
      SELF.InPos = P + 1
      DO StripCR
      RETURN 1
    END
    SELF.AppendLine(MIEIO:Buf[SELF.InPos : SELF.InLen])
    SELF.InPos = SELF.InLen + 1
  END
  DO StripCR
  RETURN CHOOSE(SELF.LineLen > 0,1,0)

StripCR ROUTINE
  IF SELF.LineLen > 0
    IF SELF.LineBuf[SELF.LineLen] = '<13>' THEN SELF.LineLen -= 1.
  END

MyImportExportClass.AppendLine PROCEDURE(STRING pText)
L                      LONG
NewCap                 LONG
NewBuf                 &STRING
  CODE
  L = LEN(pText)
  IF L = 0 THEN RETURN.
  IF SELF.LineLen + L + 1 > SELF.LineCap      ! +1: callers may slice one byte past the end
    NewCap = SELF.LineCap * 2
    IF NewCap < SELF.LineLen + L + 4096 THEN NewCap = SELF.LineLen + L + 4096.
    NewBuf &= NEW STRING(NewCap)
    IF SELF.LineLen > 0 THEN NewBuf[1 : SELF.LineLen] = SELF.LineBuf[1 : SELF.LineLen].
    IF NOT SELF.LineBuf &= NULL THEN DISPOSE(SELF.LineBuf).
    SELF.LineBuf &= NewBuf
    SELF.LineCap  = NewCap
  END
  SELF.LineBuf[SELF.LineLen + 1 : SELF.LineLen + L] = pText
  SELF.LineLen += L

MyImportExportClass.WriteText PROCEDURE(STRING pText)
L                      LONG
Pos                    LONG
N                      LONG
  CODE
  L = LEN(pText)
  Pos = 1
  LOOP WHILE Pos <= L
    N = L - Pos + 1
    IF N > SIZE(MIEIO:Buf) - SELF.OutPos THEN N = SIZE(MIEIO:Buf) - SELF.OutPos.
    MIEIO:Buf[SELF.OutPos + 1 : SELF.OutPos + N] = pText[Pos : Pos + N - 1]
    SELF.OutPos += N
    Pos += N
    IF SELF.OutPos >= SIZE(MIEIO:Buf) THEN SELF.FlushOut().
  END

MyImportExportClass.FlushOut PROCEDURE
  CODE
  IF SELF.OutPos > 0
    ADD(MIE:IOFile,SELF.OutPos)
    IF ERRORCODE() THEN SELF.ErrorText = 'Write error: ' & ERROR().
    SELF.OutPos = 0
  END

!----------------------------------------------------------------------------
! Helper process
!----------------------------------------------------------------------------
MyImportExportClass.RunHelper PROCEDURE(STRING pArgs)
ErrName                CSTRING(261)
Cmd                    CSTRING(4096)
RC                     LONG
  CODE
  IF NOT EXISTS(SELF.HelperPath)
    SELF.ErrorText = 'The helper program was not found: ' & SELF.HelperPath
    RETURN 1
  END
  ErrName = SELF.TempName('err')
  Cmd = SELF.Quote(SELF.HelperPath) & ' ' & CLIP(pArgs) & ' --errfile ' & SELF.Quote(ErrName)
  RUN(Cmd,1)
  IF ERRORCODE()
    SELF.ErrorText = 'Could not run ' & SELF.HelperPath & ': ' & ERROR()
    RETURN 1
  END
  RC = RUNCODE()
  IF RC <> 0
    SELF.ErrorText = 'MIEConvert failed (exit code ' & RC & ').'
    IF EXISTS(ErrName)
      IF SELF.OpenRead(ErrName) = 0
        SELF.ErrorText = ''
        LOOP WHILE SELF.ReadLine()
          IF SELF.LineLen = 0 THEN CYCLE.
          IF LEN(SELF.ErrorText) + SELF.LineLen + 2 > SIZE(SELF.ErrorText) - 1 THEN BREAK.
          IF SELF.ErrorText <> '' THEN SELF.ErrorText = SELF.ErrorText & '<13,10>'.
          SELF.ErrorText = SELF.ErrorText & SELF.LineBuf[1 : SELF.LineLen]
        END
        SELF.CloseIO()
      END
      REMOVE(ErrName)
    END
    RETURN 1
  END
  IF EXISTS(ErrName) THEN REMOVE(ErrName).
  RETURN 0

MyImportExportClass.CommonArgs PROCEDURE
A                      CSTRING(1024)
F                      CSTRING(9)
  CODE
  F = LOWER(CLIP(SELF.Format))
  A = ' --format ' & F
  IF INLIST(F,'xls','xlsx') AND SELF.SheetName <> '' THEN A = A & ' --sheet ' & SELF.Quote(SELF.SheetName).
  IF INLIST(F,'csv','tsv','xls','xlsx') AND NOT SELF.HasHeader THEN A = A & ' --noheader'.
  IF F = 'csv' AND SELF.Delimiter <> '' THEN A = A & ' --delimiter ' & SELF.Quote(SELF.Delimiter).
  IF INLIST(F,'csv','tsv','json','xml') AND SELF.Encoding <> '' THEN A = A & ' --encoding ' & SELF.Encoding.
  IF SELF.Mode = MIE:Mode:Import
    IF F = 'xml' AND SELF.XmlRow <> '' THEN A = A & ' --rowpath ' & SELF.Quote(SELF.XmlRow).
    IF F = 'json' AND SELF.JsonRoot <> '' THEN A = A & ' --rowpath ' & SELF.Quote(SELF.JsonRoot).
  ELSE
    IF F = 'xml' AND SELF.XmlRoot <> '' THEN A = A & ' --root ' & SELF.Quote(SELF.XmlRoot).
    IF F = 'xml' AND SELF.XmlRow <> '' THEN A = A & ' --row ' & SELF.Quote(SELF.XmlRow).
    IF F = 'json' AND SELF.JsonRoot <> '' THEN A = A & ' --root ' & SELF.Quote(SELF.JsonRoot).
    IF F = 'xlsx' AND SELF.ReplaceSheet THEN A = A & ' --replacesheet'.
  END
  RETURN A

MyImportExportClass.Quote PROCEDURE(STRING pText)
  CODE
  RETURN '"' & CLIP(pText) & '"'

MyImportExportClass.TempName PROCEDURE(STRING pExt)
P                      CSTRING(261)
  CODE
  IF MIE_GetTempPath(SIZE(P) - 1,P) = 0 THEN P = '.\'.
  IF LEN(P) = 0 THEN P = '.\'.
  IF P[LEN(P)] <> '\' THEN P = P & '\'.
  SELF.TempSeq += 1
  RETURN P & 'MIE' & THREAD() & '_' & CLOCK() & '_' & SELF.TempSeq & '.' & CLIP(pExt)

MyImportExportClass.ExeFolder PROCEDURE
P                      CSTRING(261)
I                      LONG
  CODE
  IF MIE_GetModuleFileName(0,P,SIZE(P) - 1) = 0 THEN RETURN ''.
  LOOP I = LEN(P) TO 1 BY -1
    IF P[I] = '\' THEN RETURN P[1 : I].
  END
  RETURN ''

!----------------------------------------------------------------------------
! Saved mappings (INI)
!----------------------------------------------------------------------------
MyImportExportClass.SaveMap PROCEDURE
Sec                    CSTRING(120)
I                      LONG
  CODE
  IF SELF.TableName = '' OR SELF.IniFile = '' THEN RETURN.
  Sec = 'MIE_' & CLIP(SELF.TableName)
  PUTINI(Sec,'Mode',SELF.Mode,SELF.IniFile)
  PUTINI(Sec,'Format',SELF.Format,SELF.IniFile)
  PUTINI(Sec,'FileName',SELF.FileName,SELF.IniFile)
  PUTINI(Sec,'SheetName',SELF.SheetName,SELF.IniFile)
  PUTINI(Sec,'HasHeader',SELF.HasHeader,SELF.IniFile)
  PUTINI(Sec,'Delimiter',SELF.Delimiter,SELF.IniFile)
  PUTINI(Sec,'Encoding',SELF.Encoding,SELF.IniFile)
  PUTINI(Sec,'XmlRoot',SELF.XmlRoot,SELF.IniFile)
  PUTINI(Sec,'XmlRow',SELF.XmlRow,SELF.IniFile)
  PUTINI(Sec,'JsonRoot',SELF.JsonRoot,SELF.IniFile)
  PUTINI(Sec,'ImportMode',SELF.ImportMode,SELF.IniFile)
  PUTINI(Sec,'ReplaceSheet',SELF.ReplaceSheet,SELF.IniFile)
  PUTINI(Sec,'UsePictures',SELF.UsePictures,SELF.IniFile)
  LOOP I = 1 TO RECORDS(SELF.Fields)
    GET(SELF.Fields,I)
    PUTINI(Sec,'F_' & CLIP(SELF.Fields.Label),SELF.Fields.Selected & '|' & SELF.Fields.Order & '|' & |
           CLIP(SELF.Fields.Header) & '|' & CLIP(SELF.Fields.SourceName),SELF.IniFile)
  END

MyImportExportClass.LoadMap PROCEDURE
Sec                    CSTRING(120)
V                      CSTRING(400)
I                      LONG
P1                     LONG
P2                     LONG
P3                     LONG
  CODE
  IF SELF.TableName = '' OR SELF.IniFile = '' THEN RETURN.
  Sec = 'MIE_' & CLIP(SELF.TableName)
  IF GETINI(Sec,'Format','',SELF.IniFile) = '' THEN RETURN.
  SELF.Mode         = GETINI(Sec,'Mode',SELF.Mode,SELF.IniFile)
  SELF.Format       = GETINI(Sec,'Format',SELF.Format,SELF.IniFile)
  SELF.FileName     = GETINI(Sec,'FileName',SELF.FileName,SELF.IniFile)
  SELF.SheetName    = GETINI(Sec,'SheetName',SELF.SheetName,SELF.IniFile)
  SELF.HasHeader    = GETINI(Sec,'HasHeader',SELF.HasHeader,SELF.IniFile)
  SELF.Delimiter    = GETINI(Sec,'Delimiter',SELF.Delimiter,SELF.IniFile)
  SELF.Encoding     = GETINI(Sec,'Encoding',SELF.Encoding,SELF.IniFile)
  SELF.XmlRoot      = GETINI(Sec,'XmlRoot',SELF.XmlRoot,SELF.IniFile)
  SELF.XmlRow       = GETINI(Sec,'XmlRow',SELF.XmlRow,SELF.IniFile)
  SELF.JsonRoot     = GETINI(Sec,'JsonRoot',SELF.JsonRoot,SELF.IniFile)
  SELF.ImportMode   = GETINI(Sec,'ImportMode',SELF.ImportMode,SELF.IniFile)
  SELF.ReplaceSheet = GETINI(Sec,'ReplaceSheet',SELF.ReplaceSheet,SELF.IniFile)
  SELF.UsePictures  = GETINI(Sec,'UsePictures',SELF.UsePictures,SELF.IniFile)
  IF SELF.Mode < MIE:Mode:Export OR SELF.Mode > MIE:Mode:Import THEN SELF.Mode = MIE:Mode:Export.
  IF SELF.ImportMode < MIE:Import:Add OR SELF.ImportMode > MIE:Import:Replace THEN SELF.ImportMode = MIE:Import:Add.
  LOOP I = 1 TO RECORDS(SELF.Fields)
    GET(SELF.Fields,I)
    V = GETINI(Sec,'F_' & CLIP(SELF.Fields.Label),'',SELF.IniFile)
    P1 = INSTRING('|',V,1,1)
    IF P1 = 0 THEN CYCLE.
    P2 = INSTRING('|',V,1,P1 + 1)
    IF P2 = 0 THEN CYCLE.
    P3 = INSTRING('|',V,1,P2 + 1)
    IF P3 = 0 THEN CYCLE.
    SELF.Fields.Selected   = SUB(V,1,P1 - 1)
    SELF.Fields.Order      = SUB(V,P1 + 1,P2 - P1 - 1)
    SELF.Fields.Header     = SUB(V,P2 + 1,P3 - P2 - 1)
    SELF.Fields.SourceName = SUB(V,P3 + 1,LEN(V) - P3)
    IF SELF.Fields.Header = '' THEN SELF.Fields.Header = SELF.Fields.Name.
    PUT(SELF.Fields)
  END
  SORT(SELF.Fields,SELF.Fields.Order)
  LOOP I = 1 TO RECORDS(SELF.Fields)          ! renumber 1..n
    GET(SELF.Fields,I)
    SELF.Fields.Order = I
    PUT(SELF.Fields)
  END

MyImportExportClass.ResultText PROCEDURE
T                      CSTRING(4096)
I                      LONG
  CODE
  IF SELF.Mode = MIE:Mode:Export AND RECORDS(SELF.Batch)
    IF SELF.IsMultiFormat()
      T = 'Exported ' & RECORDS(SELF.Batch) & ' table(s) to<13,10>' & SELF.FileName & '<13,10>'
    ELSE
      T = 'Exported ' & RECORDS(SELF.Batch) & ' table(s), one file each, next to<13,10>' & SELF.FileName & '<13,10>'
    END
    LOOP I = 1 TO RECORDS(SELF.Batch)
      GET(SELF.Batch,I)
      IF I > 25
        T = T & '<13,10>... and ' & RECORDS(SELF.Batch) - 25 & ' more'
        BREAK
      END
      T = T & '<13,10>' & CLIP(SELF.Batch.Name) & ': ' & SELF.Batch.Records & ' record(s)'
    END
    IF SELF.Skipped THEN T = T & '<13,10><13,10>Filtered out: ' & SELF.Skipped.
  ELSIF SELF.Mode = MIE:Mode:Export
    T = 'Exported ' & SELF.Processed & ' record(s) from ' & CLIP(SELF.TableName) & ' to<13,10>' & SELF.FileName
    IF SELF.Skipped THEN T = T & '<13,10><13,10>Filtered out: ' & SELF.Skipped.
  ELSE
    T = 'Rows read: ' & SELF.Processed & |
        '<13,10>Added: '   & SELF.Added   & |
        '<13,10>Updated: ' & SELF.Updated & |
        '<13,10>Skipped: ' & SELF.Skipped & |
        '<13,10>Failed: '  & SELF.Failed
    IF SELF.LastFailure <> '' THEN T = T & '<13,10><13,10>Last error: ' & SELF.LastFailure.
  END
  RETURN T

!----------------------------------------------------------------------------
! Several tables in one file
!   JSON  one collection per table   {"Customer":[...],"Product":[...]}
!   XML   one element per table      <Data><Customer><Row>..</Row></Customer>..</Data>
!   XLSX / XLS  one sheet per table, named after the table
!   CSV / TSV   one file per table:  <name>_<Table>.csv
!----------------------------------------------------------------------------
MyImportExportClass.AddTable PROCEDURE(STRING pName,<STRING pDescription>)
  CODE
  CLEAR(SELF.Tables)
  SELF.Tables.Name = pName
  IF NOT OMITTED(pDescription) THEN SELF.Tables.Description = pDescription.
  SELF.Tables.Selected = 0
  ADD(SELF.Tables)

MyImportExportClass.IsMultiFormat PROCEDURE(<STRING pFormat>)
F                      CSTRING(9)
  CODE
  IF OMITTED(pFormat)
    F = UPPER(CLIP(SELF.Format))
  ELSE
    F = UPPER(CLIP(pFormat))
  END
  RETURN CHOOSE(INLIST(F,'JSON','XML','XLSX','XLS') > 0,1,0)

MyImportExportClass.BatchFileName PROCEDURE(STRING pName)
F                      CSTRING(261)
I                      LONG
  CODE
  F = CLIP(SELF.FileName)
  LOOP I = LEN(F) TO 1 BY -1
    CASE F[I]
    OF '.'
      RETURN SUB(F,1,I-1) & '_' & CLIP(pName) & SUB(F,I,LEN(F)-I+1)
    OF '\'
    OROF '/'
      BREAK
    END
  END
  RETURN F & '_' & CLIP(pName) & '.' & LOWER(CLIP(SELF.Format))

MyImportExportClass.BatchBegin PROCEDURE
  CODE
  SELF.BatchCancel()
  SELF.ResetCounters()
  SELF.Mode = MIE:Mode:Export

MyImportExportClass.BatchCancel PROCEDURE
I                      LONG
  CODE
  LOOP I = 1 TO RECORDS(SELF.Batch)
    GET(SELF.Batch,I)
    IF SELF.Batch.TsvFile <> '' THEN REMOVE(SELF.Batch.TsvFile).
  END
  FREE(SELF.Batch)

MyImportExportClass.BatchAdd PROCEDURE(STRING pName)
Tmp                    CSTRING(261)
Before                 LONG
  CODE
  Tmp = SELF.TempName('tsv')
  Before = SELF.Processed
  IF SELF.ExportTsv(Tmp)
    REMOVE(Tmp)
    RETURN 1
  END
  CLEAR(SELF.Batch)
  SELF.Batch.Name    = pName
  SELF.Batch.TsvFile = Tmp
  SELF.Batch.Records = SELF.Processed - Before
  ADD(SELF.Batch)
  RETURN 0

MyImportExportClass.BatchFinish PROCEDURE
ListName               CSTRING(261)
Args                   CSTRING(1024)
F                      CSTRING(9)
I                      LONG
RC                     BYTE
  CODE
  IF RECORDS(SELF.Batch) = 0
    SELF.ErrorText = 'No tables were exported.'
    RETURN 1
  END
  IF SELF.FileName = ''
    SELF.ErrorText = 'Please choose the file to export to.'
    SELF.BatchCancel()
    RETURN 1
  END
  IF SELF.Format = '' THEN SELF.Format = SELF.FormatFromFileName(SELF.FileName).
  IF SELF.Format = '' THEN SELF.Format = 'XLSX'.
  F = LOWER(CLIP(SELF.Format))
  IF SELF.IsMultiFormat()
    ListName = SELF.TempName('txt')
    IF SELF.OpenWrite(ListName)
      SELF.BatchCancel()
      RETURN 1
    END
    LOOP I = 1 TO RECORDS(SELF.Batch)
      GET(SELF.Batch,I)
      SELF.WriteText(CLIP(SELF.Batch.Name) & '<9>' & SELF.Batch.TsvFile & '<13,10>')
    END
    SELF.CloseIO()
    Args = ' --format ' & F
    IF F = 'xml' AND SELF.XmlRoot <> '' THEN Args = Args & ' --root ' & SELF.Quote(SELF.XmlRoot).
    IF F = 'xml' AND SELF.XmlRow <> '' THEN Args = Args & ' --row ' & SELF.Quote(SELF.XmlRow).
    IF INLIST(F,'json','xml') AND SELF.Encoding <> '' THEN Args = Args & ' --encoding ' & SELF.Encoding.
    IF INLIST(F,'xls','xlsx') AND NOT SELF.HasHeader THEN Args = Args & ' --noheader'.
    RC = SELF.RunHelper('exportmulti ' & SELF.Quote(ListName) & ' ' & SELF.Quote(SELF.FileName) & Args)
    REMOVE(ListName)
  ELSE                                          ! CSV / TSV: one file per table
    LOOP I = 1 TO RECORDS(SELF.Batch)
      GET(SELF.Batch,I)
      RC = SELF.RunHelper('export ' & SELF.Quote(SELF.Batch.TsvFile) & ' ' & |
                          SELF.Quote(SELF.BatchFileName(SELF.Batch.Name)) & SELF.CommonArgs())
      IF RC
        SELF.ErrorText = CLIP(SELF.Batch.Name) & ': ' & SELF.ErrorText
        BREAK
      END
    END
  END
  LOOP I = 1 TO RECORDS(SELF.Batch)            ! keep names and counts for ResultText
    GET(SELF.Batch,I)
    REMOVE(SELF.Batch.TsvFile)
    SELF.Batch.TsvFile = ''
    PUT(SELF.Batch)
  END
  RETURN RC

MyImportExportClass.ExportTables PROCEDURE
SaveFormat             STRING(8)
SaveFile               CSTRING(261)
SavePictures           BYTE
SaveHeader             BYTE
SaveDelimiter          CSTRING(6)
SaveEncoding           CSTRING(16)
SaveRoot               CSTRING(65)
SaveRow                CSTRING(65)
TName                  STRING(100)
I                      LONG
Sel                    LONG
RC                     BYTE
  CODE
  IF SELF.FileName = ''
    SELF.ErrorText = 'Please choose the file to export to.'
    RETURN 1
  END
  IF SELF.Format = '' THEN SELF.Format = SELF.FormatFromFileName(SELF.FileName).
  IF SELF.Format = '' THEN SELF.Format = 'XLSX'.
  LOOP I = 1 TO RECORDS(SELF.Tables)
    GET(SELF.Tables,I)
    IF SELF.Tables.Selected THEN Sel += 1.
  END
  IF Sel = 0
    SELF.ErrorText = 'Please select at least one table to export.'
    RETURN 1
  END
  SaveFormat    = SELF.Format                ! LoadMap restores each table's own settings,
  SaveFile      = SELF.FileName              ! so the batch settings are put back after it
  SavePictures  = SELF.UsePictures
  SaveHeader    = SELF.HasHeader
  SaveDelimiter = SELF.Delimiter
  SaveEncoding  = SELF.Encoding
  SaveRoot      = SELF.XmlRoot
  SaveRow       = SELF.XmlRow
  SELF.BatchBegin()
  LOOP I = 1 TO RECORDS(SELF.Tables)
    GET(SELF.Tables,I)
    IF NOT SELF.Tables.Selected THEN CYCLE.
    TName = SELF.Tables.Name
    IF SELF.StatusControl THEN SELF.StatusControl{PROP:Text} = 'Exporting ' & CLIP(TName) & ' ...'.
    IF SELF.SetupTable(TName)
      SELF.ErrorText = 'The table ' & CLIP(TName) & ' is not available for export.'
      RC = 1
      BREAK
    END
    SELF.LoadMap()
    DO RestoreSettings
    IF SELF.BatchAdd(TName)
      SELF.ErrorText = CLIP(TName) & ': ' & SELF.ErrorText
      RC = 1
      BREAK
    END
  END
  IF RC
    SELF.BatchCancel()
  ELSE
    IF SELF.StatusControl THEN SELF.StatusControl{PROP:Text} = 'Writing ' & SELF.FileName & ' ...'.
    RC = SELF.BatchFinish()
  END
  DO RestoreSettings
  RETURN RC

RestoreSettings ROUTINE
  SELF.Mode        = MIE:Mode:Export
  SELF.Format      = SaveFormat
  SELF.FileName    = SaveFile
  SELF.UsePictures = SavePictures
  SELF.HasHeader   = SaveHeader
  SELF.Delimiter   = SaveDelimiter
  SELF.Encoding    = SaveEncoding
  SELF.XmlRoot     = SaveRoot
  SELF.XmlRow      = SaveRow

MyImportExportClass.SaveTablesMap PROCEDURE
  CODE
  IF SELF.IniFile = '' THEN RETURN.
  SELF.WriteTableSet('MIE__Tables')
  PUTINI('MIE__Tables','Favorite',SELF.Favorite,SELF.IniFile)

MyImportExportClass.LoadTablesMap PROCEDURE
  CODE
  IF SELF.IniFile = '' THEN RETURN.
  IF SELF.ReadTableSet('MIE__Tables') THEN RETURN.
  SELF.Favorite = GETINI('MIE__Tables','Favorite','',SELF.IniFile)
  IF SELF.FavoriteIndex(SELF.Favorite) = 0 THEN SELF.Favorite = ''.

! the ticked tables, format, file and pictures flag -> one INI section
MyImportExportClass.WriteTableSet PROCEDURE(STRING pSection)
L                      CSTRING(8192)
I                      LONG
  CODE
  PUTINI(pSection,'Format',SELF.Format,SELF.IniFile)
  PUTINI(pSection,'FileName',SELF.FileName,SELF.IniFile)
  PUTINI(pSection,'UsePictures',SELF.UsePictures,SELF.IniFile)
  LOOP I = 1 TO RECORDS(SELF.Tables)
    GET(SELF.Tables,I)
    IF NOT SELF.Tables.Selected THEN CYCLE.
    IF LEN(L) + LEN(CLIP(SELF.Tables.Name)) + 2 > SIZE(L) - 1 THEN BREAK.
    L = L & CHOOSE(L = '','',',') & CLIP(SELF.Tables.Name)
  END
  PUTINI(pSection,'Selected',L,SELF.IniFile)

! 1 = the section is not there (nothing changed)
MyImportExportClass.ReadTableSet PROCEDURE(STRING pSection)
L                      CSTRING(8192)
I                      LONG
  CODE
  IF GETINI(pSection,'Format','',SELF.IniFile) = '' THEN RETURN 1.
  SELF.Format      = GETINI(pSection,'Format',SELF.Format,SELF.IniFile)
  SELF.FileName    = GETINI(pSection,'FileName',SELF.FileName,SELF.IniFile)
  SELF.UsePictures = GETINI(pSection,'UsePictures',SELF.UsePictures,SELF.IniFile)
  L = ',' & UPPER(GETINI(pSection,'Selected','',SELF.IniFile)) & ','
  LOOP I = 1 TO RECORDS(SELF.Tables)
    GET(SELF.Tables,I)
    SELF.Tables.Selected = CHOOSE(INSTRING(',' & UPPER(CLIP(SELF.Tables.Name)) & ',',L,1,1) > 0,1,0)
    PUT(SELF.Tables)
  END
  RETURN 0

!----------------------------------------------------------------------------
! Favorites: [MIE__Tables] Favorites=Month end|Price list
!            [MIE__Favorite Month end] Format=, FileName=, UsePictures=, Selected=
!----------------------------------------------------------------------------
MyImportExportClass.FavoriteNames PROCEDURE
  CODE
  IF SELF.IniFile = '' THEN RETURN ''.
  RETURN GETINI('MIE__Tables','Favorites','',SELF.IniFile)

MyImportExportClass.FavoriteClean PROCEDURE(STRING pName)
R                      CSTRING(41)
I                      LONG
  CODE
  LOOP I = 1 TO LEN(CLIP(pName))
    IF INSTRING(pName[I],'|[]=;,',1,1) THEN CYCLE.
    IF R = '' AND pName[I] = ' ' THEN CYCLE.
    IF LEN(R) >= 40 THEN BREAK.
    R = R & pName[I]
  END
  RETURN CLIP(R)

! position (1..n) of the favorite in FavoriteNames, 0 = none (case-insensitive)
MyImportExportClass.FavoriteIndex PROCEDURE(STRING pName)
L                      CSTRING(4096)
N                      CSTRING(41)
P                      LONG
Q                      LONG
K                      LONG
  CODE
  N = UPPER(SELF.FavoriteClean(pName))
  IF N = '' THEN RETURN 0.
  L = UPPER(SELF.FavoriteNames()) & '|'
  P = 1
  LOOP
    Q = INSTRING('|',L,1,P)
    IF Q = 0 THEN BREAK.
    K += 1
    IF Q > P AND L[P : Q-1] = N THEN RETURN K.
    P = Q + 1
  END
  RETURN 0

! the name at position pIndex, as it was saved
MyImportExportClass.FavoriteName PROCEDURE(LONG pIndex)
L                      CSTRING(4096)
P                      LONG
Q                      LONG
K                      LONG
  CODE
  L = SELF.FavoriteNames() & '|'
  P = 1
  LOOP
    Q = INSTRING('|',L,1,P)
    IF Q = 0 THEN BREAK.
    K += 1
    IF K = pIndex AND Q > P THEN RETURN L[P : Q-1].
    P = Q + 1
  END
  RETURN ''

MyImportExportClass.SaveFavorite PROCEDURE(STRING pName)
N                      CSTRING(41)
L                      CSTRING(4096)
  CODE
  N = SELF.FavoriteClean(pName)
  IF N = '' OR SELF.IniFile = '' THEN RETURN 1.
  IF SELF.FavoriteIndex(N)
    N = SELF.FavoriteName(SELF.FavoriteIndex(N))          ! keep the saved spelling
  ELSE
    L = SELF.FavoriteNames()
    IF LEN(L) + LEN(N) + 2 > SIZE(L) - 1 THEN RETURN 1.
    L = L & CHOOSE(L = '','','|') & N
    PUTINI('MIE__Tables','Favorites',L,SELF.IniFile)
  END
  SELF.WriteTableSet('MIE__Favorite ' & N)
  SELF.Favorite = N
  PUTINI('MIE__Tables','Favorite',N,SELF.IniFile)
  RETURN 0

MyImportExportClass.LoadFavorite PROCEDURE(STRING pName)
N                      CSTRING(41)
  CODE
  N = SELF.FavoriteClean(pName)
  IF SELF.IniFile = '' OR SELF.FavoriteIndex(N) = 0 THEN RETURN 1.
  N = SELF.FavoriteName(SELF.FavoriteIndex(N))
  IF SELF.ReadTableSet('MIE__Favorite ' & N) THEN RETURN 1.
  SELF.Favorite = N
  RETURN 0

! Export a favorite without the window: load it, export, show the result.
! pName = '' pops a menu of the saved favorites.
MyImportExportClass.RunFavorite PROCEDURE(STRING pName)
N                      CSTRING(41)
M                      CSTRING(8192)
Item                   CSTRING(90)
K                      LONG
I                      LONG
RC                     BYTE
  CODE
  N = SELF.FavoriteClean(pName)
  IF N = ''
    IF SELF.FavoriteNames() = ''
      SELF.ShowMessage('There are no saved favorites yet.<13,10>Tick the tables in the Export tables window and click Save as... to make one.','Export favorite',ICON:Exclamation)
      RETURN 0
    END
    K = 1
    LOOP
      Item = SELF.FavoriteName(K)
      IF Item = '' THEN BREAK.
      IF LEN(M) + LEN(Item) * 2 + 2 > SIZE(M) - 1 THEN BREAK.
      IF M <> '' THEN M = M & '|'.
      LOOP I = 1 TO LEN(Item)                   ! & is the hot-key marker in a menu
        M = M & CHOOSE(Item[I] = '&','&&',Item[I])
      END
      K += 1
    END
    K = POPUP(M)
    IF K = 0 THEN RETURN 0.
    N = SELF.FavoriteName(K)
  END
  IF SELF.LoadFavorite(N)
    SELF.ShowMessage('The favorite "' & N & '" was not found.<13,10>It may have been deleted or saved in another INI file.','Export favorite',ICON:Exclamation)
    RETURN 0
  END
  IF SELF.FileName = ''
    SELF.ShowMessage('The favorite "' & N & '" has no file. Open Export tables, choose a file and save it again.','Export favorite',ICON:Exclamation)
    RETURN 0
  END
  SETCURSOR(CURSOR:Wait)
  RC = SELF.ExportTables()
  SETCURSOR()
  IF RC
    SELF.ShowMessage(SELF.ErrorText,'Export favorite',ICON:Exclamation)
    RETURN 0
  END
  SELF.ShowMessage(SELF.ResultText(),'Export complete: ' & N)
  RETURN 1

MyImportExportClass.DeleteFavorite PROCEDURE(STRING pName)
N                      CSTRING(41)
Sec                    CSTRING(64)
L                      CSTRING(4096)
R                      CSTRING(4096)
P                      LONG
Q                      LONG
  CODE
  N = SELF.FavoriteClean(pName)
  IF SELF.IniFile = '' OR SELF.FavoriteIndex(N) = 0 THEN RETURN.
  L = SELF.FavoriteNames() & '|'
  P = 1
  LOOP
    Q = INSTRING('|',L,1,P)
    IF Q = 0 THEN BREAK.
    IF Q > P AND UPPER(L[P : Q-1]) <> UPPER(N)
      R = R & CHOOSE(R = '','','|') & L[P : Q-1]
    END
    P = Q + 1
  END
  PUTINI('MIE__Tables','Favorites',R,SELF.IniFile)
  Sec = 'MIE__Favorite ' & N
  MIE_WriteProfile(Sec,0,0,SELF.IniFile)              ! drop the whole section
  IF UPPER(SELF.Favorite) = UPPER(N)
    SELF.Favorite = ''
    PUTINI('MIE__Tables','Favorite','',SELF.IniFile)
  END

!============================================================================
! AskTables - the multi-table export window
!============================================================================
MyImportExportClass.AskTables PROCEDURE
LocFormat              STRING(8)
LocFile                STRING(260)
LocPictures            BYTE
Result                 BYTE
I                      LONG
C                      LONG
J                      LONG
Picked                 STRING(260)
FileMask               CSTRING(300)
Ext                    CSTRING(10)
TabQ                   QUEUE
UseText                  STRING(1)
UseIcon                  LONG
Name                     STRING(100)
Description              STRING(128)
                       END
LocFav                 STRING(40)
FavName                STRING(40)
FavOk                  BYTE
P                      LONG
Q                      LONG
FavList                CSTRING(4096)
FavQ                   QUEUE
Name                     STRING(40)
                       END
Window WINDOW('Export tables'),AT(,,424,300),FONT('Segoe UI',9,,FONT:regular),CENTER,GRAY,SYSTEM,DOUBLE
       BOX,AT(0,0,424,30),USE(?Band),COLOR(05F3A1FH),FILL(05F3A1FH)
       STRING('Export tables'),AT(10,3),USE(?Title),TRN,FONT(,13,COLOR:White,FONT:bold)
       STRING('Several tables into one file'),AT(10,18,400,10),USE(?SubTitle),TRN,FONT(,9,0E8D8C8H)
       PROMPT('Fa&vorite:'),AT(8,38),USE(?FavPrompt)
       LIST,AT(52,36,190,12),USE(LocFav),DROP(12),FROM(FavQ),FORMAT('160L(2)@s40@'), |
           TIP('Pick a saved set of tables: ticks them and restores the format and file')
       BUTTON('&Save as...'),AT(248,35,50,14),USE(?FavSave),TIP('Save the ticked tables, format and file as a favorite')
       BUTTON('&Delete'),AT(302,35,36,14),USE(?FavDelete),TIP('Delete the chosen favorite')
       PROMPT('Tables:'),AT(8,56),USE(?TablesPrompt)
       LIST,AT(8,68,330,132),USE(?TableList),VSCROLL,FROM(TabQ),ALRT(MouseLeft2),ALRT(SpaceKey), |
           FORMAT('20C|I~Use~@s1@100L(2)|~Table~@s100@200L(2)~Description~@s128@')
       BUTTON('Select &All'),AT(344,68,72,14),USE(?SelectAll)
       BUTTON('Select &None'),AT(344,86,72,14),USE(?SelectNone)
       STRING(''),AT(344,108,72,10),USE(?Count),FONT(,8,COLOR:Gray)
       PROMPT('Format:'),AT(8,212),USE(?FormatPrompt)
       LIST,AT(52,210,64,12),USE(LocFormat),DROP(6),FROM('XLSX|XLS|JSON|XML|CSV|TSV')
       STRING(''),AT(124,212,292,10),USE(?FormatNote)
       PROMPT('File:'),AT(8,230),USE(?FilePrompt)
       ENTRY(@s255),AT(52,228,342,12),USE(LocFile)
       BUTTON('...'),AT(398,227,18,14),USE(?BrowseFile),TIP('Choose the file')
       CHECK('Format with dictionary pictures'),AT(52,246),USE(LocPictures),TIP('CSV, TSV and XML: write dates, times and numbers as the program shows them')
       STRING('Each table uses the columns saved for it in Import / Export.'),AT(8,262,408,10),USE(?Hint),FONT(,8,COLOR:Gray)
       PROGRESS,AT(8,280,200,8),USE(?Progress),RANGE(0,100)
       STRING(''),AT(8,290,290,10),USE(?Status)
       BUTTON('&Export'),AT(306,278,54,16),USE(?Run),DEFAULT
       BUTTON('&Close'),AT(364,278,52,16),USE(?Close)
     END
NameWin WINDOW('Save favorite'),AT(,,240,74),FONT('Segoe UI',9,,FONT:regular),CENTER,GRAY,SYSTEM,DOUBLE
       BOX,AT(0,0,240,4),USE(?NameBand),COLOR(05F3A1FH),FILL(05F3A1FH)
       PROMPT('Name of the favorite:'),AT(8,12),USE(?NamePrompt)
       ENTRY(@s40),AT(8,24,224,12),USE(FavName)
       STRING('Saves the ticked tables, the format and the file.'),AT(8,40,224,10),USE(?NameHint),FONT(,8,COLOR:Gray)
       BUTTON('&Save'),AT(124,54,52,16),USE(?NameOk),DEFAULT
       BUTTON('Cancel'),AT(180,54,52,16),USE(?NameCancel)
     END
  CODE
  LocFormat   = CHOOSE(SELF.Format = '','XLSX',UPPER(SELF.Format))
  LocFile     = SELF.FileName
  LocPictures = SELF.UsePictures
  OPEN(Window)
  ?TableList{PROP:IconList,1} = ICON:Tick
  SELF.ProgressControl = ?Progress
  SELF.StatusControl   = ?Status
  LocFav = SELF.Favorite
  DO LoadFavList
  DO RefreshList
  DO ShowNote
  ACCEPT
    CASE EVENT()
    OF EVENT:AlertKey
      IF FIELD() = ?TableList AND INLIST(KEYCODE(),MouseLeft2,SpaceKey)
        DO ToggleCurrent
      END
    OF EVENT:NewSelection
      IF FIELD() = ?TableList AND KEYCODE() = MouseLeft AND ?TableList{PROPLIST:MouseDownField} = 1
        DO ToggleCurrent
      END
    OF EVENT:Accepted
      CASE FIELD()
      OF ?LocFav
        IF LocFav <> '' AND SELF.LoadFavorite(LocFav) = 0
          LocFormat   = CHOOSE(SELF.Format = '','XLSX',UPPER(SELF.Format))
          LocFile     = SELF.FileName
          LocPictures = SELF.UsePictures
          ENABLE(?FavDelete)
          DO RefreshList
          DO ShowNote
          ?Status{PROP:Text} = 'Favorite "' & CLIP(LocFav) & '" loaded'
        END
      OF ?FavSave
        DO SaveFav
      OF ?FavDelete
        DO DeleteFav
      OF ?SelectAll
        LOOP I = 1 TO RECORDS(SELF.Tables)
          GET(SELF.Tables,I)
          SELF.Tables.Selected = 1
          PUT(SELF.Tables)
        END
        DO RefreshList
      OF ?SelectNone
        LOOP I = 1 TO RECORDS(SELF.Tables)
          GET(SELF.Tables,I)
          SELF.Tables.Selected = 0
          PUT(SELF.Tables)
        END
        DO RefreshList
      OF ?LocFormat
        DO FixExtension
        DO ShowNote
      OF ?LocFile
        Ext = SELF.FormatFromFileName(LocFile)
        IF Ext <> ''
          LocFormat = Ext
        ELSE
          DO FixExtension
        END
        DO ShowNote
      OF ?BrowseFile
        DO PickFile
      OF ?Run
        DO RunIt
      OF ?Close
        POST(EVENT:CloseWindow)
      END
    END
  END
  SELF.ProgressControl = 0
  SELF.StatusControl   = 0
  CLOSE(Window)
  RETURN Result

LoadFavList ROUTINE
  FREE(FavQ)
  FavList = SELF.FavoriteNames() & '|'
  P = 1
  LOOP
    Q = INSTRING('|',FavList,1,P)
    IF Q = 0 THEN BREAK.
    IF Q > P
      FavQ.Name = FavList[P : Q-1]
      ADD(FavQ,+FavQ.Name)
    END
    P = Q + 1
  END
  IF RECORDS(FavQ) = 0
    LocFav = ''
    DISABLE(?LocFav)
    DISABLE(?FavDelete)
  ELSE
    ENABLE(?LocFav)
    IF LocFav = '' THEN DISABLE(?FavDelete) ELSE ENABLE(?FavDelete).
  END
  DISPLAY

SaveFav ROUTINE
  I = 0
  LOOP J = 1 TO RECORDS(SELF.Tables)
    GET(SELF.Tables,J)
    IF SELF.Tables.Selected THEN I += 1.
  END
  IF I = 0
    SELF.ShowMessage('Tick the tables to save in the favorite first.','Save favorite',ICON:Exclamation)
    EXIT
  END
  IF SELF.IniFile = ''
    SELF.ShowMessage('Favorites need an INI file (MIE.IniFile).','Save favorite',ICON:Exclamation)
    EXIT
  END
  FavName = LocFav
  FavOk   = 0
  OPEN(NameWin)
  ACCEPT
    CASE EVENT()
    OF EVENT:Accepted
      CASE FIELD()
      OF ?NameOk
        FavName = SELF.FavoriteClean(FavName)
        IF FavName = ''
          SELF.ShowMessage('Please type a name.','Save favorite',ICON:Exclamation)
          SELECT(?FavName)
          CYCLE
        END
        IF SELF.FavoriteIndex(FavName) AND UPPER(FavName) <> UPPER(LocFav)
          IF MESSAGE('A favorite called "' & CLIP(FavName) & '" already exists.<13,10>Do you want to replace it?', |
                     'Save favorite',ICON:Question,BUTTON:Yes + BUTTON:No,BUTTON:No) <> BUTTON:Yes
            SELECT(?FavName)
            CYCLE
          END
        END
        FavOk = 1
        POST(EVENT:CloseWindow)
      OF ?NameCancel
        POST(EVENT:CloseWindow)
      END
    END
  END
  CLOSE(NameWin)
  IF NOT FavOk THEN EXIT.
  SELF.Format      = LocFormat
  SELF.FileName    = CLIP(LocFile)
  SELF.UsePictures = LocPictures
  IF SELF.SaveFavorite(FavName)
    SELF.ShowMessage('The favorite could not be saved.','Save favorite',ICON:Exclamation)
    EXIT
  END
  LocFav = SELF.Favorite
  DO LoadFavList
  ?Status{PROP:Text} = 'Favorite "' & CLIP(LocFav) & '" saved'

DeleteFav ROUTINE
  IF LocFav = '' THEN EXIT.
  IF MESSAGE('Delete the favorite "' & CLIP(LocFav) & '"?<13,10>The tables themselves are not touched.', |
             'Delete favorite',ICON:Question,BUTTON:Yes + BUTTON:No,BUTTON:No) <> BUTTON:Yes THEN EXIT.
  SELF.DeleteFavorite(LocFav)
  ?Status{PROP:Text} = 'Favorite "' & CLIP(LocFav) & '" deleted'
  LocFav = ''
  DO LoadFavList

RefreshList ROUTINE
  C = CHOICE(?TableList)
  FREE(TabQ)
  I = 0
  LOOP J = 1 TO RECORDS(SELF.Tables)
    GET(SELF.Tables,J)
    CLEAR(TabQ)
    TabQ.UseIcon     = CHOOSE(SELF.Tables.Selected = 1,1,0)
    TabQ.Name        = SELF.Tables.Name
    TabQ.Description = SELF.Tables.Description
    ADD(TabQ)
    IF SELF.Tables.Selected THEN I += 1.
  END
  IF C < 1 THEN C = 1.
  IF C > RECORDS(TabQ) THEN C = RECORDS(TabQ).
  IF C THEN ?TableList{PROP:Selected} = C.
  ?Count{PROP:Text} = I & ' of ' & RECORDS(SELF.Tables) & ' selected'
  DISPLAY

ToggleCurrent ROUTINE
  I = CHOICE(?TableList)
  IF I < 1 OR I > RECORDS(SELF.Tables) THEN EXIT.
  GET(SELF.Tables,I)
  SELF.Tables.Selected = CHOOSE(SELF.Tables.Selected = 1,0,1)
  PUT(SELF.Tables)
  DO RefreshList

ShowNote ROUTINE
  IF INLIST(LocFormat,'CSV','TSV','XML') THEN UNHIDE(?LocPictures) ELSE HIDE(?LocPictures).
  CASE LocFormat
  OF 'XLSX'
  OROF 'XLS'
    ?FormatNote{PROP:Text} = 'One sheet per table, named after the table.'
  OF 'JSON'
    ?FormatNote{PROP:Text} = 'One collection per table, named after the table.'
  OF 'XML'
    ?FormatNote{PROP:Text} = 'One element per table inside the root element.'
  ELSE
    ?FormatNote{PROP:Text} = 'One file per table: the table name is added to the file name.'
  END

FixExtension ROUTINE
  IF LocFile = '' THEN EXIT.
  Ext = LOWER(CLIP(LocFormat))
  LOOP I = LEN(CLIP(LocFile)) TO 1 BY -1
    IF INLIST(LocFile[I],'\','/') THEN BREAK.
    IF LocFile[I] = '.'
      LocFile = SUB(LocFile,1,I) & Ext
      DISPLAY(?LocFile)
      EXIT
    END
  END
  LocFile = CLIP(LocFile) & '.' & Ext
  DISPLAY(?LocFile)

PickFile ROUTINE
  FileMask = 'Excel workbook (*.xlsx)|*.xlsx|Excel 97-2003 (*.xls)|*.xls|JSON files (*.json)|*.json' & |
             '|XML files (*.xml)|*.xml|CSV files (*.csv)|*.csv|Tab separated (*.tsv)|*.tsv|All files (*.*)|*.*'
  Picked = LocFile
  IF NOT FILEDIALOG('Export tables to',Picked,FileMask,FILE:Save + FILE:KeepDir + FILE:LongName) THEN EXIT.
  LocFile = Picked
  Ext = SELF.FormatFromFileName(LocFile)
  IF Ext <> ''
    LocFormat = Ext
  ELSE
    DO FixExtension
  END
  DO ShowNote
  DISPLAY

RunIt ROUTINE
  SELF.Format      = LocFormat
  SELF.FileName    = CLIP(LocFile)
  SELF.UsePictures = LocPictures
  IF SELF.FileName = ''
    SELF.ShowMessage('Please choose a file first.','Export tables',ICON:Exclamation)
    SELECT(?LocFile)
    EXIT
  END
  IF SELF.IsMultiFormat() AND EXISTS(SELF.FileName)
    IF MESSAGE('The file ' & SELF.FileName & ' already exists.<13,10>Do you want to replace it?', |
               'Export tables',ICON:Question,BUTTON:Yes + BUTTON:No,BUTTON:No) <> BUTTON:Yes THEN EXIT.
  END
  DISABLE(?Run)
  SETCURSOR(CURSOR:Wait)
  I = SELF.ExportTables()
  SETCURSOR()
  ENABLE(?Run)
  IF I
    ?Status{PROP:Text} = 'Failed'
    SELF.ShowMessage(SELF.ErrorText,'Export tables',ICON:Exclamation)
  ELSE
    Result = 1
    SELF.SaveTablesMap()
    ?Progress{PROP:Progress} = 100
    ?Status{PROP:Text} = 'Done'
    SELF.ShowMessage(SELF.ResultText(),'Export complete')
    POST(EVENT:CloseWindow)
  END

!----------------------------------------------------------------------------
! Virtual hooks - raw driver defaults
!----------------------------------------------------------------------------
MyImportExportClass.OpenTable PROCEDURE
  CODE
  SELF.WeOpened = 0
  IF STATUS(SELF.TableFile) THEN RETURN 0.      ! already open
  SHARE(SELF.TableFile)
  IF ERRORCODE() = 2 AND SELF.Mode = MIE:Mode:Import
    CREATE(SELF.TableFile)
    IF NOT ERRORCODE() THEN SHARE(SELF.TableFile).
  END
  IF ERRORCODE()
    SELF.ErrorText = 'Cannot open ' & CLIP(SELF.TableName) & ': ' & ERROR()
    RETURN 1
  END
  SELF.WeOpened = 1
  RETURN 0

MyImportExportClass.CloseTable PROCEDURE
  CODE
  IF SELF.WeOpened
    CLOSE(SELF.TableFile)
    SELF.WeOpened = 0
  END

MyImportExportClass.PrimeRecord PROCEDURE
  CODE

MyImportExportClass.CancelPrime PROCEDURE
  CODE

MyImportExportClass.InsertRecord PROCEDURE
  CODE
  ADD(SELF.TableFile)
  RETURN CHOOSE(ERRORCODE() = 0,0,1)

MyImportExportClass.UpdateRecord PROCEDURE
  CODE
  PUT(SELF.TableFile)
  RETURN CHOOSE(ERRORCODE() = 0,0,1)

MyImportExportClass.FetchRecord PROCEDURE
  CODE
  IF SELF.TableKey &= NULL THEN RETURN 1.
  GET(SELF.TableFile,SELF.TableKey)
  RETURN CHOOSE(ERRORCODE() = 0,0,1)

MyImportExportClass.DeleteRecord PROCEDURE
  CODE
  DELETE(SELF.TableFile)
  RETURN CHOOSE(ERRORCODE() = 0,0,1)

MyImportExportClass.ValidateRecord PROCEDURE
  CODE
  RETURN 0

MyImportExportClass.ExportFilter PROCEDURE
  CODE
  RETURN 1

MyImportExportClass.TakeProgress PROCEDURE(LONG pDone,LONG pTotal=0)
  CODE
  IF SELF.ProgressControl = 0 THEN RETURN.
  IF pDone % 50 <> 0 AND pDone <> pTotal THEN RETURN.
  IF pTotal > 0
    SELF.ProgressControl{PROP:Progress} = INT(pDone * 100 / pTotal)
  ELSE
    SELF.ProgressControl{PROP:Progress} = (pDone / 50) % 101
  END
  IF SELF.StatusControl
    IF pTotal > 0
      SELF.StatusControl{PROP:Text} = pDone & ' of ' & pTotal & ' records'
    ELSE
      SELF.StatusControl{PROP:Text} = pDone & ' rows'
    END
  END
  DISPLAY()

MyImportExportClass.ShowMessage PROCEDURE(STRING pText,STRING pCaption,<STRING pIcon>)
  CODE
  IF SELF.Silent THEN RETURN.
  IF OMITTED(pIcon)
    MESSAGE(pText,pCaption,ICON:Asterisk)
  ELSE
    MESSAGE(pText,pCaption,pIcon)
  END

MyImportExportClass.SetupTable PROCEDURE(STRING pName)
  CODE
  SELF.ErrorText = 'No table setup for ' & CLIP(pName) & ' (derive SetupTable).'
  RETURN 1

!============================================================================
! Ask - the import / export window
!============================================================================
MyImportExportClass.Ask PROCEDURE(BYTE pMode=0)
LocMode                BYTE
LocFormat              STRING(8)
PrevFormat             STRING(8)
LocFile                STRING(260)
LocSheet               STRING(128)
LocHeader              BYTE
LocDelim               STRING(20)
LocRoot                STRING(64)
LocRow                 STRING(64)
LocImportMode          STRING(60)
LocReplace             BYTE
LocPictures            BYTE
LocSource              STRING(160)
LocHeaderName          STRING(128)
LocTitle               STRING(200)
Result                 BYTE
I                      LONG
C                      LONG
MoveDir                SIGNED
FileMask               CSTRING(400)
Picked                 STRING(260)
Ext                    CSTRING(10)
DispQ                  QUEUE
UseText                  STRING(1)
UseIcon                  LONG
Label                    STRING(100)
FType                    STRING(40)
ColumnName               STRING(128)
Extra                    STRING(128)
                       END
ColQ                   QUEUE
Name                     STRING(160)
                       END
SheetQ                 QUEUE
Name                     STRING(128)
                       END
Window WINDOW('Import / Export'),AT(,,480,344),FONT('Segoe UI',9,,FONT:regular),CENTER,GRAY,SYSTEM,DOUBLE
       BOX,AT(0,0,480,30),USE(?Band),COLOR(05F3A1FH),FILL(05F3A1FH)
       STRING('Import / Export'),AT(10,3),USE(?Title),TRN,FONT(,13,COLOR:White,FONT:bold)
       STRING(@s200),AT(10,18,460,10),USE(LocTitle),TRN,FONT(,9,0E8D8C8H)
       OPTION('Action'),AT(8,34,128,26),USE(LocMode),BOXED
         RADIO('Export'),AT(18,45),USE(?ModeExport),VALUE('1')
         RADIO('Import'),AT(74,45),USE(?ModeImport),VALUE('2')
       END
       PROMPT('Format:'),AT(148,46),USE(?FormatPrompt)
       LIST,AT(180,44,64,12),USE(LocFormat),DROP(6),FROM('CSV|TSV|JSON|XML|XLSX|XLS')
       PROMPT('File:'),AT(8,68),USE(?FilePrompt)
       ENTRY(@s255),AT(52,66,398,12),USE(LocFile)
       BUTTON('...'),AT(454,65,18,14),USE(?BrowseFile),TIP('Choose the file')
       PROMPT('Sheet:'),AT(8,86),USE(?SheetPrompt)
       COMBO(@s128),AT(52,84,150,12),USE(LocSheet),VSCROLL,DROP(12),FROM(SheetQ)
       CHECK('First row contains column names'),AT(212,85),USE(LocHeader)
       PROMPT('Delimiter:'),AT(344,86),USE(?DelimPrompt)
       LIST,AT(382,84,90,12),USE(LocDelim),DROP(4),FROM('Comma|Semicolon|Tab|Pipe')
       PROMPT('Root:'),AT(8,104),USE(?RootPrompt)
       ENTRY(@s64),AT(52,102,80,12),USE(LocRoot)
       PROMPT('Row:'),AT(140,104),USE(?RowPrompt)
       ENTRY(@s64),AT(162,102,80,12),USE(LocRow)
       PROMPT('Import mode:'),AT(252,104),USE(?ImportModePrompt)
       LIST,AT(300,102,172,12),USE(LocImportMode),DROP(4),FROM('Add new records|Add or update (match primary key)|Update existing records only|Replace all records')
       CHECK('Format with dictionary pictures'),AT(252,103),USE(LocPictures),TIP('CSV, TSV and XML: write dates, times and numbers as the program shows them')
       CHECK('Keep other sheets'),AT(390,103),USE(LocReplace),TIP('Add or replace only this sheet in an existing workbook')
       LIST,AT(8,122,394,168),USE(?MapList),VSCROLL,FROM(DispQ),ALRT(MouseLeft2),ALRT(SpaceKey), |
           FORMAT('20C|I~Use~@s1@110L(2)|~Field~@s100@64L(2)|~Type~@s40@120L(2)|~Column~@s128@80L(2)~Sample~@s128@')
       BUTTON('Select &All'),AT(408,122,64,14),USE(?SelectAll)
       BUTTON('Select &None'),AT(408,140,64,14),USE(?SelectNone)
       BUTTON('Auto &Map'),AT(408,158,64,14),USE(?AutoMap),TIP('Match source columns to fields by name')
       BUTTON('Move &Up'),AT(408,182,64,14),USE(?MoveUp),TIP('Move the field one column to the left')
       BUTTON('Move &Down'),AT(408,200,64,14),USE(?MoveDown),TIP('Move the field one column to the right')
       BUTTON('&Reload'),AT(408,224,64,14),USE(?Reload),TIP('Read the sheets and columns of the file again')
       PROMPT('Source column:'),AT(8,296),USE(?SourcePrompt)
       LIST,AT(66,294,200,12),USE(LocSource),VSCROLL,DROP(15),FROM(ColQ)
       PROMPT('Column header:'),AT(8,296),USE(?HeaderPrompt)
       ENTRY(@s128),AT(66,294,200,12),USE(LocHeaderName)
       STRING('Double-click or press Space to include / exclude a field'),AT(272,296,200,10),USE(?Hint),FONT(,8,COLOR:Gray)
       PROGRESS,AT(8,316,280,8),USE(?Progress),RANGE(0,100)
       STRING(''),AT(8,328,288,10),USE(?Status)
       BUTTON('&Save Mapping'),AT(298,318,60,16),USE(?SaveMap),TIP('Remember these settings for this table')
       BUTTON('&Run'),AT(362,318,54,16),USE(?Run),DEFAULT
       BUTTON('&Close'),AT(420,318,52,16),USE(?Close)
     END
  CODE
  IF pMode THEN SELF.Mode = pMode.
  DO PushSettings
  OPEN(Window)
  Window{PROP:Text} = 'Import / Export - ' & CLIP(SELF.TableName)
  LocTitle = 'Table: ' & CLIP(SELF.TableName) & '   (' & RECORDS(SELF.Fields) & ' fields)'
  ?MapList{PROP:IconList,1} = ICON:Tick
  ?LocImportMode{PROP:Selected} = SELF.ImportMode
  SELF.ProgressControl = ?Progress
  SELF.StatusControl   = ?Status
  SORT(SELF.Fields,SELF.Fields.Order)
  IF LocFile <> '' AND EXISTS(LocFile)
    DO LoadSource
  END
  DO RefreshAll
  ACCEPT
    CASE EVENT()
    OF EVENT:AlertKey
      IF FIELD() = ?MapList AND INLIST(KEYCODE(),MouseLeft2,SpaceKey)
        DO ToggleCurrent
      END
    OF EVENT:NewSelection
      IF FIELD() = ?MapList
        IF KEYCODE() = MouseLeft AND ?MapList{PROPLIST:MouseDownField} = 1
          DO ToggleCurrent
        END
        DO ShowCurrent
      END
    OF EVENT:Accepted
      CASE FIELD()
      OF ?LocMode
        DO PullSettings
        IF LocMode = MIE:Mode:Import AND LocFile <> '' AND EXISTS(LocFile)
          DO LoadSource
        END
        DO RefreshAll
      OF ?LocFormat
        DO SwitchFormat
        DO FixExtension
        DO PullSettings
        IF LocMode = MIE:Mode:Import AND LocFile <> '' AND EXISTS(LocFile)
          DO LoadSource
        END
        DO RefreshAll
      OF ?BrowseFile
        DO PickFile
      OF ?LocFile
        DO FileChanged
      OF ?LocSheet
      OROF ?LocHeader
      OROF ?LocDelim
      OROF ?LocRoot
      OROF ?LocRow
        DO PullSettings
        IF LocMode = MIE:Mode:Import
          DO LoadSource
          DO RefreshAll
        END
      OF ?LocSource
        DO SetSource
      OF ?LocHeaderName
        DO SetHeaderName
      OF ?SelectAll
        SELF.SelectAll(1)
        DO RefreshList
      OF ?SelectNone
        SELF.SelectAll(0)
        DO RefreshList
      OF ?AutoMap
        DO PullSettings
        SELF.AutoMap()
        DO RefreshList
      OF ?MoveUp
        MoveDir = -1
        DO MoveRow
      OF ?MoveDown
        MoveDir = 1
        DO MoveRow
      OF ?Reload
        DO PullSettings
        DO LoadSource
        DO RefreshAll
      OF ?SaveMap
        DO PullSettings
        SELF.SaveMap()
        ?Status{PROP:Text} = 'Settings saved for ' & CLIP(SELF.TableName)
      OF ?Run
        DO RunIt
      OF ?Close
        POST(EVENT:CloseWindow)
      END
    END
  END
  SELF.ProgressControl = 0
  SELF.StatusControl   = 0
  CLOSE(Window)
  RETURN Result

!--- settings <-> window ----------------------------------------------------
PushSettings ROUTINE
  LocMode     = CHOOSE(SELF.Mode = MIE:Mode:Import,MIE:Mode:Import,MIE:Mode:Export)
  LocFormat   = CHOOSE(SELF.Format = '','CSV',SELF.Format)
  PrevFormat  = LocFormat
  LocFile     = SELF.FileName
  LocSheet    = SELF.SheetName
  LocHeader   = SELF.HasHeader
  LocReplace  = SELF.ReplaceSheet
  LocPictures = SELF.UsePictures
  CASE SELF.Delimiter
  OF ';'
    LocDelim = 'Semicolon'
  OF 'tab'
    LocDelim = 'Tab'
  OF '|'
    LocDelim = 'Pipe'
  ELSE
    LocDelim = 'Comma'
  END
  DO LoadRoots

LoadRoots ROUTINE
  IF LocFormat = 'JSON'
    LocRoot = SELF.JsonRoot
    LocRow  = ''
  ELSE
    LocRoot = SELF.XmlRoot
    LocRow  = SELF.XmlRow
  END

PullSettings ROUTINE
  SELF.Mode         = LocMode
  SELF.Format       = LocFormat
  SELF.FileName     = CLIP(LocFile)
  SELF.SheetName    = CLIP(LocSheet)
  SELF.HasHeader    = LocHeader
  SELF.ReplaceSheet = LocReplace
  SELF.UsePictures  = LocPictures
  SELF.ImportMode   = CHOICE(?LocImportMode)
  IF SELF.ImportMode = 0 THEN SELF.ImportMode = MIE:Import:Add.
  CASE LocDelim
  OF 'Semicolon'
    SELF.Delimiter = ';'
  OF 'Tab'
    SELF.Delimiter = 'tab'
  OF 'Pipe'
    SELF.Delimiter = '|'
  ELSE
    SELF.Delimiter = ','
  END
  IF LocFormat = 'JSON'
    SELF.JsonRoot = CLIP(LocRoot)
  ELSIF LocFormat = 'XML'
    SELF.XmlRoot = CLIP(LocRoot)
    SELF.XmlRow  = CLIP(LocRow)
  END

SwitchFormat ROUTINE
  IF PrevFormat = 'JSON'                    ! keep what was typed for the old format
    SELF.JsonRoot = CLIP(LocRoot)
  ELSIF PrevFormat = 'XML'
    SELF.XmlRoot = CLIP(LocRoot)
    SELF.XmlRow  = CLIP(LocRow)
  END
  PrevFormat = LocFormat
  DO LoadRoots
  DISPLAY

FixExtension ROUTINE
  IF LocMode <> MIE:Mode:Export OR LocFile = '' THEN EXIT.
  Ext = LOWER(CLIP(LocFormat))
  LOOP I = LEN(CLIP(LocFile)) TO 1 BY -1
    IF INLIST(LocFile[I],'\','/') THEN BREAK.
    IF LocFile[I] = '.'
      LocFile = SUB(LocFile,1,I) & Ext
      DISPLAY(?LocFile)
      EXIT
    END
  END
  LocFile = CLIP(LocFile) & '.' & Ext
  DISPLAY(?LocFile)

!--- file selection ---------------------------------------------------------
PickFile ROUTINE
  FileMask = 'All supported files|*.csv;*.tsv;*.txt;*.json;*.xml;*.xlsx;*.xls' & |
             '|CSV files (*.csv)|*.csv|Tab separated (*.tsv;*.txt)|*.tsv;*.txt|JSON files (*.json)|*.json' & |
             '|XML files (*.xml)|*.xml|Excel workbook (*.xlsx)|*.xlsx|Excel 97-2003 (*.xls)|*.xls|All files (*.*)|*.*'
  Picked = LocFile
  IF LocMode = MIE:Mode:Export
    IF NOT FILEDIALOG('Export ' & CLIP(SELF.TableName) & ' to',Picked,FileMask,FILE:Save + FILE:KeepDir + FILE:LongName) THEN EXIT.
  ELSE
    IF NOT FILEDIALOG('Import into ' & CLIP(SELF.TableName) & ' from',Picked,FileMask,FILE:KeepDir + FILE:LongName) THEN EXIT.
  END
  LocFile = Picked
  DISPLAY(?LocFile)
  DO FileChanged

FileChanged ROUTINE
  Ext = SELF.FormatFromFileName(LocFile)
  IF Ext <> '' AND Ext <> LocFormat
    LocFormat = Ext
    DO SwitchFormat
  ELSIF Ext = ''
    DO FixExtension
  END
  DO PullSettings
  IF LocFile <> '' AND EXISTS(LocFile)
    DO LoadSource
  END
  DO RefreshAll

LoadSource ROUTINE
  DO PullSettings
  FREE(SheetQ)
  FREE(ColQ)
  ColQ.Name = MIE:NotMapped
  ADD(ColQ)
  IF SELF.FileName = '' OR NOT EXISTS(SELF.FileName)
    ?Status{PROP:Text} = CHOOSE(SELF.Mode = MIE:Mode:Import,'File not found','')
    EXIT
  END
  SETCURSOR(CURSOR:Wait)
  IF INLIST(LocFormat,'XLS','XLSX')
    IF SELF.LoadSheets() = 0
      LOOP I = 1 TO RECORDS(SELF.Sheets)
        GET(SELF.Sheets,I)
        SheetQ.Name = SELF.Sheets.Name
        ADD(SheetQ)
      END
      IF SELF.Mode = MIE:Mode:Import AND RECORDS(SheetQ)
        SheetQ.Name = LocSheet
        GET(SheetQ,SheetQ.Name)
        IF ERRORCODE() OR LocSheet = ''
          GET(SheetQ,1)
          LocSheet = SheetQ.Name
          SELF.SheetName = CLIP(LocSheet)
        END
      END
    END
  END
  IF SELF.Mode = MIE:Mode:Import
    IF SELF.LoadColumns()
      SETCURSOR()
      ?Status{PROP:Text} = 'Could not read the file'
      SELF.ShowMessage(SELF.ErrorText,'Import',ICON:Exclamation)
      EXIT
    END
    LOOP I = 1 TO RECORDS(SELF.Columns)
      GET(SELF.Columns,I)
      ColQ.Name = SELF.Columns.Name
      ADD(ColQ)
    END
    IF SELF.ResolveMap() = 0 THEN SELF.AutoMap().
    ?Status{PROP:Text} = RECORDS(SELF.Columns) & ' column(s) found in the file'
  END
  SETCURSOR()

!--- list -------------------------------------------------------------------
RefreshAll ROUTINE
  DO SyncControls
  DO RefreshList

SyncControls ROUTINE
  IF INLIST(LocFormat,'XLS','XLSX')
    UNHIDE(?SheetPrompt,?LocSheet)
  ELSE
    HIDE(?SheetPrompt,?LocSheet)
  END
  IF INLIST(LocFormat,'CSV','TSV','XLS','XLSX') THEN UNHIDE(?LocHeader) ELSE HIDE(?LocHeader).
  IF LocFormat = 'CSV' THEN UNHIDE(?DelimPrompt,?LocDelim) ELSE HIDE(?DelimPrompt,?LocDelim).
  CASE LocFormat
  OF 'XML'
    ?RootPrompt{PROP:Text} = 'Root:'
    UNHIDE(?RootPrompt,?LocRow)
  OF 'JSON'
    ?RootPrompt{PROP:Text} = 'Array:'
    UNHIDE(?RootPrompt,?LocRoot)
    HIDE(?RowPrompt,?LocRow)
  ELSE
    HIDE(?RootPrompt,?LocRow)
  END
  IF LocMode = MIE:Mode:Import
    UNHIDE(?ImportModePrompt,?LocImportMode)
    HIDE(?LocPictures)
    HIDE(?LocReplace)
    UNHIDE(?SourcePrompt,?LocSource)
    HIDE(?HeaderPrompt,?LocHeaderName)
    UNHIDE(?AutoMap)
    UNHIDE(?Reload)
    ?Run{PROP:Text} = '&Import'
    ?MapList{PROPLIST:Header,4} = 'Source column'
    ?MapList{PROPLIST:Header,5} = 'Sample'
    ?LocRoot{PROP:Tip} = CHOOSE(LocFormat = 'JSON','Property holding the array (blank = auto)','')
    ?LocRow{PROP:Tip}  = 'Element name of one row (blank = auto)'
  ELSE
    HIDE(?ImportModePrompt,?LocImportMode)
    IF INLIST(LocFormat,'CSV','TSV','XML') THEN UNHIDE(?LocPictures) ELSE HIDE(?LocPictures).
    IF LocFormat = 'XLSX' THEN UNHIDE(?LocReplace) ELSE HIDE(?LocReplace).
    HIDE(?SourcePrompt,?LocSource)
    UNHIDE(?HeaderPrompt,?LocHeaderName)
    HIDE(?AutoMap)
    HIDE(?Reload)
    ?Run{PROP:Text} = '&Export'
    ?MapList{PROPLIST:Header,4} = 'Column header'
    ?MapList{PROPLIST:Header,5} = 'Picture'
    ?LocRoot{PROP:Tip} = CHOOSE(LocFormat = 'JSON','Wrap the array in an object with this name (optional)','Root element (default Data)')
    ?LocRow{PROP:Tip}  = 'Row element (default Row)'
  END
  DISPLAY

RefreshList ROUTINE
  C = CHOICE(?MapList)
  FREE(DispQ)
  LOOP I = 1 TO RECORDS(SELF.Fields)
    GET(SELF.Fields,I)
    CLEAR(DispQ)
    DispQ.UseIcon = CHOOSE(SELF.Fields.Selected = 1,1,0)
    DispQ.Label   = SELF.Fields.Label
    DispQ.FType   = CLIP(SELF.Fields.FieldType) & CHOOSE(SELF.Fields.IsKey = 1,'  (key)','')
    IF LocMode = MIE:Mode:Import
      IF SELF.Fields.SourceCol
        DispQ.ColumnName = SELF.Fields.SourceName
        GET(SELF.Columns,SELF.Fields.SourceCol)
        IF NOT ERRORCODE() THEN DispQ.Extra = SELF.Columns.Sample.
      END
    ELSE
      DispQ.ColumnName = SELF.Fields.Header
      DispQ.Extra      = SELF.Fields.Picture
    END
    ADD(DispQ)
  END
  IF C < 1 THEN C = 1.
  IF C > RECORDS(DispQ) THEN C = RECORDS(DispQ).
  IF C THEN ?MapList{PROP:Selected} = C.
  DO ShowCurrent
  DISPLAY

ShowCurrent ROUTINE
  I = CHOICE(?MapList)
  IF I < 1 OR I > RECORDS(SELF.Fields) THEN EXIT.
  GET(SELF.Fields,I)
  LocHeaderName = SELF.Fields.Header
  IF SELF.Fields.SourceCol
    LocSource = SELF.Fields.SourceName
  ELSE
    LocSource = MIE:NotMapped
  END
  DISPLAY(?LocSource)
  DISPLAY(?LocHeaderName)

ToggleCurrent ROUTINE
  I = CHOICE(?MapList)
  IF I < 1 OR I > RECORDS(SELF.Fields) THEN EXIT.
  GET(SELF.Fields,I)
  SELF.Fields.Selected = CHOOSE(SELF.Fields.Selected = 1,0,1)
  PUT(SELF.Fields)
  DO RefreshList

SetSource ROUTINE
  I = CHOICE(?MapList)
  IF I < 1 OR I > RECORDS(SELF.Fields) THEN EXIT.
  GET(SELF.Fields,I)
  C = CHOICE(?LocSource) - 1
  IF C > 0 AND C <= RECORDS(SELF.Columns)
    GET(SELF.Columns,C)
    SELF.Fields.SourceCol  = C
    SELF.Fields.SourceName = SELF.Columns.Name
    SELF.Fields.Selected   = 1
  ELSE
    SELF.Fields.SourceCol  = 0
    SELF.Fields.SourceName = ''
    SELF.Fields.Selected   = 0
  END
  PUT(SELF.Fields)
  DO RefreshList

SetHeaderName ROUTINE
  I = CHOICE(?MapList)
  IF I < 1 OR I > RECORDS(SELF.Fields) THEN EXIT.
  GET(SELF.Fields,I)
  SELF.Fields.Header = LocHeaderName
  PUT(SELF.Fields)
  DO RefreshList

MoveRow ROUTINE
  I = CHOICE(?MapList)
  C = I + MoveDir
  IF I < 1 OR C < 1 OR C > RECORDS(SELF.Fields) THEN EXIT.
  GET(SELF.Fields,I)
  SELF.Fields.Order = C
  PUT(SELF.Fields)
  GET(SELF.Fields,C)
  SELF.Fields.Order = I
  PUT(SELF.Fields)
  SORT(SELF.Fields,SELF.Fields.Order)
  ?MapList{PROP:Selected} = C
  DO RefreshList

!--- run --------------------------------------------------------------------
RunIt ROUTINE
  DO PullSettings
  IF SELF.FileName = ''
    SELF.ShowMessage('Please choose a file first.','Import / Export',ICON:Exclamation)
    SELECT(?LocFile)
    EXIT
  END
  IF LocMode = MIE:Mode:Export
    IF EXISTS(SELF.FileName) AND NOT (LocFormat = 'XLSX' AND LocReplace)
      IF MESSAGE('The file ' & SELF.FileName & ' already exists.<13,10>Do you want to replace it?', |
                 'Export',ICON:Question,BUTTON:Yes + BUTTON:No,BUTTON:No) <> BUTTON:Yes THEN EXIT.
    END
  ELSE
    IF SELF.ImportMode = MIE:Import:Replace
      IF MESSAGE('All existing records in ' & CLIP(SELF.TableName) & ' will be deleted before importing.' & |
                 '<13,10><13,10>Do you want to continue?','Replace all records',ICON:Exclamation, |
                 BUTTON:Yes + BUTTON:No,BUTTON:No) <> BUTTON:Yes THEN EXIT.
    END
  END
  DISABLE(?Run)
  SETCURSOR(CURSOR:Wait)
  IF LocMode = MIE:Mode:Export
    I = SELF.Export()
  ELSE
    I = SELF.Import()
  END
  SETCURSOR()
  ENABLE(?Run)
  IF I
    ?Status{PROP:Text} = 'Failed'
    SELF.ShowMessage(SELF.ErrorText,CHOOSE(LocMode = MIE:Mode:Export,'Export','Import'),ICON:Exclamation)
  ELSE
    Result = 1
    SELF.SaveMap()
    ?Progress{PROP:Progress} = 100
    ?Status{PROP:Text} = 'Done'
    SELF.ShowMessage(SELF.ResultText(),CHOOSE(LocMode = MIE:Mode:Export,'Export complete','Import complete'), |
                     CHOOSE(SELF.Failed > 0,ICON:Exclamation,ICON:Asterisk))
    POST(EVENT:CloseWindow)
  END
