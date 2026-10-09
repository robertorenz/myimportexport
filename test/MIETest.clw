!============================================================================
! MIETest - headless round-trip test for MyImportExportClass
!   Exports a table to every format, imports it into a copy, compares.
!   Results go to mietest.log; exit code (HALT) = number of failures.
!============================================================================
  PROGRAM

  INCLUDE('MyImportExport.inc'),ONCE

  MAP
    WriteLog(STRING pText)
    FillCustomers()
    SetupFields(BYTE pCopy)
    RoundTrip(STRING pFormat,STRING pExt,<STRING pSheet>)
    CompareTables(STRING pWhat),LONG
    UpsertTest()
    MultiTest()
    PicturesTest()
    FavTest()
    RunFavTest()
    Check(BYTE pOk,STRING pWhat)
    MultiOne(STRING pFormat,STRING pExt)
  END

Customer             FILE,DRIVER('TOPSPEED'),NAME('customer.tps'),PRE(CUS),CREATE,THREAD
KeyId                  KEY(CUS:Id),PRIMARY,NOCASE
Record                 RECORD
Id                       LONG
Name                     STRING(40)
City                     CSTRING(31)
Born                     LONG
Since                    DATE
Alarm                    LONG
Balance                  DECIMAL(11,2)
Rate                     REAL
Phone                    STRING(15),DIM(2)
                       END
                     END

CustCopy             FILE,DRIVER('TOPSPEED'),NAME('custcopy.tps'),PRE(CPY),CREATE,THREAD
KeyId                  KEY(CPY:Id),PRIMARY,NOCASE
Record                 RECORD
Id                       LONG
Name                     STRING(40)
City                     CSTRING(31)
Born                     LONG
Since                    DATE
Alarm                    LONG
Balance                  DECIMAL(11,2)
Rate                     REAL
Phone                    STRING(15),DIM(2)
                       END
                     END

LogFile              FILE,DRIVER('ASCII'),NAME('mietest.log'),CREATE,PRE(LOG)
Record                 RECORD
Line                     STRING(1000)
                       END
                     END

Failures             LONG
CurMie               &MyImportExportClass
TestMie              CLASS(MyImportExportClass)
SetupTable             PROCEDURE(STRING pName),BYTE,DERIVED
                     END

  CODE
  IF COMMAND('/win')                    ! manual look at the Export tables window
    TestMie.Init()
    TestMie.IniFile = LONGPATH() & '<92>miefav.ini'
    TestMie.AddTable('Customer','Customers')
    TestMie.AddTable('CustCopy','Copy of customers')
    TestMie.AddTable('Product','Products')
    GET(TestMie.Tables,1); TestMie.Tables.Selected = 1; PUT(TestMie.Tables)
    TestMie.Format = 'XLSX'; TestMie.FileName = 'c:<92>temp<92>month.xlsx'
    TestMie.SaveFavorite('Month end')
    TestMie.LoadTablesMap()
    TestMie.AskTables()
    TestMie.Kill()
    RETURN
  END
  CREATE(LogFile)
  WriteLog('start')
  REMOVE(Customer)
  REMOVE(CustCopy)
  CREATE(Customer)
  CREATE(CustCopy)
  FillCustomers()
  RoundTrip('CSV','csv')
  RoundTrip('TSV','tsv')
  RoundTrip('JSON','json')
  RoundTrip('XML','xml')
  RoundTrip('XLSX','xlsx','Customers')
  RoundTrip('XLS','xls','Customers')
  UpsertTest()
  MultiTest()
  PicturesTest()
  FavTest()
  RunFavTest()
  WriteLog('FAILURES: ' & Failures)
  HALT(Failures)

WriteLog             PROCEDURE(STRING pText)
  CODE
  OPEN(LogFile)
  LOG:Line = pText
  ADD(LogFile)
  CLOSE(LogFile)

FillCustomers        PROCEDURE
  CODE
  SHARE(Customer)
  CLEAR(CUS:Record)
  CUS:Id = 1
  CUS:Name = 'Smith, John'
  CUS:City = 'Zürich'
  CUS:Born = DATE(3,15,1970)
  CUS:Since = DATE(1,2,2020)
  CUS:Alarm = 8*360000 + 30*6000 + 15*100 + 1
  CUS:Balance = 1234.56
  CUS:Rate = 0.125
  CUS:Phone[1] = '555-0101'
  CUS:Phone[2] = '555-0102'
  ADD(Customer)
  CLEAR(CUS:Record)
  CUS:Id = 2
  CUS:Name = 'Say "Hi" <9>tab\back'
  CUS:City = 'São Paulo'
  CUS:Born = DATE(12,31,1999)
  CUS:Since = 0
  CUS:Alarm = 0
  CUS:Balance = -42.5
  CUS:Rate = 3
  ADD(Customer)
  CLEAR(CUS:Record)
  CUS:Id = 3
  CUS:Name = 'Line1<13,10>Line2; semi|pipe'
  CUS:City = ''
  CUS:Born = 0
  CUS:Since = DATE(2,29,2024)
  CUS:Alarm = 23*360000 + 59*6000 + 59*100 + 1
  CUS:Balance = 0
  CUS:Rate = 0
  CUS:Phone[2] = 'ñandú'
  ADD(Customer)
  CLOSE(Customer)

SetupFields          PROCEDURE(BYTE pCopy)
  CODE
  IF pCopy
    CurMie.SetTable(CustCopy,'CustCopy',CPY:KeyId)
    CurMie.AddField('CPY:Id','Id','LONG','@n_10',CPY:Id,1)
    CurMie.AddField('CPY:Name','Name','STRING','@s40',CPY:Name)
    CurMie.AddField('CPY:City','City','CSTRING','@s30',CPY:City)
    CurMie.AddField('CPY:Born','Born','LONG','@d6',CPY:Born)
    CurMie.AddField('CPY:Since','Since','DATE','@d17',CPY:Since)
    CurMie.AddField('CPY:Alarm','Alarm','LONG','@t4',CPY:Alarm)
    CurMie.AddField('CPY:Balance','Balance','DECIMAL','@n-14.2',CPY:Balance)
    CurMie.AddField('CPY:Rate','Rate','REAL','@n-15.4',CPY:Rate)
    CurMie.AddField('CPY:Phone[1]','Phone1','STRING','@s15',CPY:Phone[1])
    CurMie.AddField('CPY:Phone[2]','Phone2','STRING','@s15',CPY:Phone[2])
  ELSE
    CurMie.SetTable(Customer,'Customer',CUS:KeyId)
    CurMie.AddField('CUS:Id','Id','LONG','@n_10',CUS:Id,1)
    CurMie.AddField('CUS:Name','Name','STRING','@s40',CUS:Name)
    CurMie.AddField('CUS:City','City','CSTRING','@s30',CUS:City)
    CurMie.AddField('CUS:Born','Born','LONG','@d6',CUS:Born)
    CurMie.AddField('CUS:Since','Since','DATE','@d17',CUS:Since)
    CurMie.AddField('CUS:Alarm','Alarm','LONG','@t4',CUS:Alarm)
    CurMie.AddField('CUS:Balance','Balance','DECIMAL','@n-14.2',CUS:Balance)
    CurMie.AddField('CUS:Rate','Rate','REAL','@n-15.4',CUS:Rate)
    CurMie.AddField('CUS:Phone[1]','Phone1','STRING','@s15',CUS:Phone[1])
    CurMie.AddField('CUS:Phone[2]','Phone2','STRING','@s15',CUS:Phone[2])
  END

RoundTrip            PROCEDURE(STRING pFormat,STRING pExt,<STRING pSheet>)
Exp                  MyImportExportClass
Imp                  MyImportExportClass
  CODE
  Exp.Init()
  Exp.Silent   = 1
  Exp.IniFile  = ''
  CurMie &= Exp
  SetupFields(0)
  Exp.Format   = pFormat
  Exp.FileName = LONGPATH() & '\out_test.' & pExt
  IF NOT OMITTED(pSheet) THEN Exp.SheetName = pSheet.
  REMOVE(Exp.FileName)
  IF Exp.Export()
    Failures += 1
    WriteLog(pFormat & ' EXPORT FAILED: ' & Exp.ErrorText)
    RETURN
  END
  WriteLog(pFormat & ' export: ' & Exp.Processed & ' records')

  Imp.Init()
  Imp.Silent     = 1
  Imp.IniFile    = ''
  CurMie &= Imp
  SetupFields(1)
  Imp.Format     = pFormat
  Imp.FileName   = Exp.FileName
  Imp.ImportMode = MIE:Import:Replace
  IF NOT OMITTED(pSheet) THEN Imp.SheetName = pSheet.
  IF Imp.LoadColumns()
    Failures += 1
    WriteLog(pFormat & ' LOADCOLUMNS FAILED: ' & Imp.ErrorText)
    RETURN
  END
  Imp.AutoMap()
  IF Imp.Import()
    Failures += 1
    WriteLog(pFormat & ' IMPORT FAILED: ' & Imp.ErrorText)
    RETURN
  END
  WriteLog(pFormat & ' import: read ' & Imp.Processed & ' added ' & Imp.Added & ' failed ' & Imp.Failed & ' ' & Imp.LastFailure)
  IF Imp.Added <> 3 THEN Failures += 1.
  Failures += CompareTables(pFormat)
  Exp.Kill()
  Imp.Kill()

CompareTables        PROCEDURE(STRING pWhat)
Bad                  LONG
Rows                 LONG
I                    LONG
  CODE
  SHARE(Customer)
  SHARE(CustCopy)
  SET(CUS:KeyId)
  LOOP
    NEXT(Customer)
    IF ERRORCODE() THEN BREAK.
    Rows += 1
    CPY:Id = CUS:Id
    GET(CustCopy,CPY:KeyId)
    IF ERRORCODE()
      WriteLog('  ' & pWhat & ' missing id ' & CUS:Id)
      Bad += 1
      CYCLE
    END
    IF CPY:Name <> CUS:Name THEN Bad += 1; WriteLog('  ' & pWhat & ' Name [' & CLIP(CPY:Name) & '] vs [' & CLIP(CUS:Name) & ']').
    IF CPY:City <> CUS:City THEN Bad += 1; WriteLog('  ' & pWhat & ' City [' & CPY:City & '] vs [' & CUS:City & ']').
    IF CPY:Born <> CUS:Born THEN Bad += 1; WriteLog('  ' & pWhat & ' Born ' & CPY:Born & ' vs ' & CUS:Born).
    IF CPY:Since <> CUS:Since THEN Bad += 1; WriteLog('  ' & pWhat & ' Since ' & CPY:Since & ' vs ' & CUS:Since).
    IF CPY:Alarm <> CUS:Alarm THEN Bad += 1; WriteLog('  ' & pWhat & ' Alarm ' & CPY:Alarm & ' vs ' & CUS:Alarm).
    IF CPY:Balance <> CUS:Balance THEN Bad += 1; WriteLog('  ' & pWhat & ' Balance ' & CPY:Balance & ' vs ' & CUS:Balance).
    IF CPY:Rate <> CUS:Rate THEN Bad += 1; WriteLog('  ' & pWhat & ' Rate ' & CPY:Rate & ' vs ' & CUS:Rate).
    LOOP I = 1 TO 2
      IF CPY:Phone[I] <> CUS:Phone[I] THEN Bad += 1; WriteLog('  ' & pWhat & ' Phone' & I & ' [' & CLIP(CPY:Phone[I]) & '] vs [' & CLIP(CUS:Phone[I]) & ']').
    END
  END
  CLOSE(Customer)
  CLOSE(CustCopy)
  WriteLog('  ' & pWhat & ' compared ' & Rows & ' rows, ' & Bad & ' differences')
  RETURN CHOOSE(Bad > 0,1,0)

UpsertTest           PROCEDURE
Exp                  MyImportExportClass
Imp                  MyImportExportClass
  CODE
  ! change one record + add one in the source, export only Id/Name, upsert into copy
  SHARE(Customer)
  CUS:Id = 2
  GET(Customer,CUS:KeyId)
  CUS:Name = 'Changed name'
  PUT(Customer)
  CLEAR(CUS:Record)
  CUS:Id = 9
  CUS:Name = 'New one'
  ADD(Customer)
  CLOSE(Customer)
  Exp.Init()
  Exp.Silent  = 1
  Exp.IniFile = ''
  CurMie &= Exp
  SetupFields(0)
  Exp.SelectAll(0)
  GET(Exp.Fields,1)
  Exp.Fields.Selected = 1
  PUT(Exp.Fields)
  GET(Exp.Fields,2)
  Exp.Fields.Selected = 1
  PUT(Exp.Fields)
  Exp.Format   = 'CSV'
  Exp.FileName = LONGPATH() & '\out_upsert.csv'
  IF Exp.Export() THEN Failures += 1; WriteLog('UPSERT export failed: ' & Exp.ErrorText); RETURN.
  Imp.Init()
  Imp.Silent     = 1
  Imp.IniFile    = ''
  CurMie &= Imp
  SetupFields(1)
  Imp.FileName   = Exp.FileName
  Imp.Format     = 'CSV'
  Imp.ImportMode = MIE:Import:Upsert
  Imp.LoadColumns()
  Imp.AutoMap()
  IF Imp.Import() THEN Failures += 1; WriteLog('UPSERT import failed: ' & Imp.ErrorText); RETURN.
  WriteLog('UPSERT: read ' & Imp.Processed & ' added ' & Imp.Added & ' updated ' & Imp.Updated & ' failed ' & Imp.Failed)
  IF Imp.Added <> 1 OR Imp.Updated <> 3 THEN Failures += 1.
  SHARE(CustCopy)
  CPY:Id = 2
  GET(CustCopy,CPY:KeyId)
  IF CPY:Name <> 'Changed name' OR CPY:City <> 'São Paulo'
    Failures += 1
    WriteLog('UPSERT: record 2 wrong: ' & CLIP(CPY:Name) & ' / ' & CPY:City)
  END
  CLOSE(CustCopy)

TestMie.SetupTable   PROCEDURE(STRING pName)
  CODE
  CurMie &= SELF
  CASE UPPER(pName)
  OF 'CUSTOMER'
    SetupFields(0)
  OF 'CUSTCOPY'
    SetupFields(1)
  ELSE
    RETURN 1
  END
  RETURN 0

MultiTest            PROCEDURE
  CODE
  MultiOne('JSON','json')
  MultiOne('XML','xml')
  MultiOne('XLSX','xlsx')
  MultiOne('XLS','xls')
  MultiOne('CSV','csv')

MultiOne             PROCEDURE(STRING pFormat,STRING pExt)
I                    LONG
  CODE
  TestMie.Init()
  TestMie.Silent  = 1
  TestMie.IniFile = ''
  TestMie.AddTable('Customer','Customers')
  TestMie.AddTable('CustCopy','Copy of customers')
  TestMie.AddTable('Nothing','not selected')
  LOOP I = 1 TO 2
    GET(TestMie.Tables,I)
    TestMie.Tables.Selected = 1
    PUT(TestMie.Tables)
  END
  TestMie.Format   = pFormat
  TestMie.FileName = LONGPATH() & '\out_multi.' & pExt
  REMOVE(TestMie.FileName)
  IF TestMie.ExportTables()
    Failures += 1
    WriteLog('MULTI ' & pFormat & ' FAILED: ' & TestMie.ErrorText)
  ELSE
    WriteLog('MULTI ' & pFormat & ': ' & RECORDS(TestMie.Batch) & ' tables, ' & TestMie.Processed & ' records')
    IF RECORDS(TestMie.Batch) <> 2 THEN Failures += 1.
    IF TestMie.IsMultiFormat()
      IF NOT EXISTS(TestMie.FileName) THEN Failures += 1; WriteLog('  missing ' & TestMie.FileName).
    ELSE
      IF NOT EXISTS(TestMie.BatchFileName('Customer')) OR NOT EXISTS(TestMie.BatchFileName('CustCopy'))
        Failures += 1
        WriteLog('  missing per-table files')
      END
    END
  END
  TestMie.Kill()

PicturesTest         PROCEDURE
Exp                  MyImportExportClass
  CODE
  ! numbers must stay numbers in JSON even with "Format with dictionary pictures"
  Exp.Init()
  Exp.Silent      = 1
  Exp.IniFile     = ''
  CurMie &= Exp
  SetupFields(0)
  Exp.Format      = 'JSON'
  Exp.UsePictures = 1
  Exp.FileName    = LONGPATH() & '<92>out_pics.json'
  IF Exp.Export()
    Failures += 1
    WriteLog('PICTURES export failed: ' & Exp.ErrorText)
  ELSE
    WriteLog('PICTURES export: ' & Exp.Processed & ' records')
  END
  Exp.Kill()

Check                PROCEDURE(BYTE pOk,STRING pWhat)
  CODE
  IF pOk
    WriteLog('  ok: ' & pWhat)
  ELSE
    Failures += 1
    WriteLog('  FAILED: ' & pWhat)
  END

FavTest              PROCEDURE
Fav                  MyImportExportClass
Ini                  CSTRING(260)
  CODE
  WriteLog('FAVORITES')
  Ini = LONGPATH() & '<92>miefav.ini'
  REMOVE(Ini)
  Fav.Init()
  Fav.Silent  = 1
  Fav.IniFile = Ini
  Fav.AddTable('Customer','Customers')
  Fav.AddTable('CustCopy','Copy')
  Fav.AddTable('Product','Products')
  GET(Fav.Tables,1); Fav.Tables.Selected = 1; PUT(Fav.Tables)
  GET(Fav.Tables,3); Fav.Tables.Selected = 1; PUT(Fav.Tables)
  Fav.Format = 'XLSX'; Fav.FileName = 'c:<92>temp<92>month.xlsx'
  Check(CHOOSE(Fav.SaveFavorite('Month end') = 0),'save Month end')
  GET(Fav.Tables,1); Fav.Tables.Selected = 0; PUT(Fav.Tables)
  GET(Fav.Tables,3); Fav.Tables.Selected = 0; PUT(Fav.Tables)
  GET(Fav.Tables,2); Fav.Tables.Selected = 1; PUT(Fav.Tables)
  Fav.Format = 'JSON'; Fav.FileName = 'c:<92>temp<92>prices.json'
  Check(CHOOSE(Fav.SaveFavorite(' Price, list') = 0),'save Price list (name cleaned)')
  Check(CHOOSE(Fav.FavoriteNames() = 'Month end|Price list'),'names = ' & Fav.FavoriteNames())
  Check(CHOOSE(Fav.SaveFavorite('') = 1),'empty name refused')
  Check(CHOOSE(Fav.LoadFavorite('MONTH END') = 0),'load, any case')
  GET(Fav.Tables,1); Check(Fav.Tables.Selected,'Customer ticked')
  GET(Fav.Tables,2); Check(CHOOSE(Fav.Tables.Selected = 0),'CustCopy not ticked')
  GET(Fav.Tables,3); Check(Fav.Tables.Selected,'Product ticked')
  Check(CHOOSE(UPPER(Fav.Format) = 'XLSX' AND Fav.FileName = 'c:<92>temp<92>month.xlsx'),'format + file restored')
  Check(CHOOSE(Fav.Favorite = 'Month end'),'Favorite property')
  Fav.SaveTablesMap()
  Fav.DeleteFavorite('month end')
  Check(CHOOSE(Fav.FavoriteNames() = 'Price list'),'deleted from list: ' & Fav.FavoriteNames())
  Check(CHOOSE(Fav.LoadFavorite('Month end') = 1),'deleted favorite does not load')
  Check(CHOOSE(GETINI('MIE__Favorite Month end','Format','gone',Ini) = 'gone'),'section removed')
  Check(CHOOSE(Fav.Favorite = ''),'Favorite cleared')
  Check(CHOOSE(Fav.LoadFavorite('Price list') = 0),'other favorite still loads')
  GET(Fav.Tables,2); Check(Fav.Tables.Selected,'CustCopy ticked')
  Fav.Kill()

RunFavTest           PROCEDURE
Ini                  CSTRING(260)
Out                  CSTRING(260)
  CODE
  WriteLog('RUN FAVORITE')
  Ini = LONGPATH() & '<92>mierun.ini'
  Out = LONGPATH() & '<92>out_fav.json'
  REMOVE(Ini)
  REMOVE(Out)
  TestMie.Init()
  TestMie.Silent  = 1
  TestMie.IniFile = Ini
  TestMie.AddTable('Customer','Customers')
  TestMie.AddTable('CustCopy','Copy of customers')
  GET(TestMie.Tables,1); TestMie.Tables.Selected = 1; PUT(TestMie.Tables)
  GET(TestMie.Tables,2); TestMie.Tables.Selected = 1; PUT(TestMie.Tables)
  TestMie.Format = 'JSON'; TestMie.FileName = Out
  TestMie.SaveFavorite('Nightly')
  TestMie.Kill()
  TestMie.Init()                                    ! a fresh object, as a button click would have
  TestMie.Silent  = 1
  TestMie.IniFile = Ini
  TestMie.AddTable('Customer','Customers')
  TestMie.AddTable('CustCopy','Copy of customers')
  Check(CHOOSE(TestMie.RunFavorite('nightly') = 1),'RunFavorite exported')
  Check(EXISTS(Out),'favorite file written')
  Check(CHOOSE(RECORDS(TestMie.Batch) = 2),'both tables in it')
  Check(CHOOSE(TestMie.RunFavorite('No such') = 0),'unknown favorite refused')
  TestMie.Kill()
