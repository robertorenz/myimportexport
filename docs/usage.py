# One sentence and one worked piece of Clarion for every property and method
# of MyImportExportClass.  The signatures come out of libsrc\win\MyImportExport.inc
# when the manual is built; this file only says what each member is for and
# shows it in use.  A member missing from here fails the build.
#
#   name: (what it is, worked code)

PROPS = {
 'Fields': ("The fields that can be imported or exported, one row per AddField call, in export column order.",
            "LOOP I = 1 TO RECORDS(MIE.Fields)\n"
            "  GET(MIE.Fields, I)\n"
            "  IF MIE.Fields.IsKey THEN MIE.Fields.Selected = 1; PUT(MIE.Fields).\n"
            "END"),
 'Columns': ("The columns found in the source file. LoadColumns and Import fill it; each row has the column name and a sample value from the first data row.",
             "MIE.LoadColumns()\n"
             "LOOP I = 1 TO RECORDS(MIE.Columns)\n"
             "  GET(MIE.Columns, I)\n"
             "  Log('column ' & CLIP(MIE.Columns.Name) & ' e.g. ' & MIE.Columns.Sample)\n"
             "END"),
 'Sheets': ("The worksheet names of an .xls or .xlsx file, filled by LoadSheets.",
            "MIE.LoadSheets()\n"
            "GET(MIE.Sheets, 1)\n"
            "MIE.SheetName = MIE.Sheets.Name             ! import from the first sheet"),
 'Values': ("The values of the row being imported. Read them with GetValue rather than directly.",
            "!  inside ValidateRecord: the raw text of source column 3\n"
            "IF SELF.GetValue(3) = 'X' THEN RETURN 1."),
 'TableFile': ("The FILE being imported into or exported from, set by SetTable.",
               "IF ~MIE.TableFile &= NULL THEN Total = RECORDS(MIE.TableFile)."),
 'TableKey': ("The primary key given to SetTable. Add-or-update and Update-only imports find existing records through it; export walks the table in its order.",
              "IF MIE.TableKey &= NULL THEN MIE.ImportMode = MIE:Import:Add."),
 'TableName': ("The table's name as given to SetTable. It names the INI section of the saved mapping and appears in the window title.",
               "CASE UPPER(SELF.TableName)\n"
               "OF 'CUSTOMER' ; RETURN CHOOSE(CUS:Name = '', 1, 0)\n"
               "END"),
 'WeOpened': ("PROTECTED. Set by the default OpenTable when it opened the table itself, so CloseTable only closes what it opened.",
              "!  a derived OpenTable that opens the file itself sets it too\n"
              "SHARE(SELF.TableFile)\n"
              "SELF.WeOpened = CHOOSE(ERRORCODE() = 0, 1, 0)"),
 'KeyMapped': ("Set by ResolveMap: 1 when at least one primary key field is selected and mapped to a source column. When it is 0, new records are primed (auto-increment).",
               "IF ~SELF.KeyMapped THEN SELF.PrimeRecord()."),
 'Mode': ("Export or import: MIE:Mode:Export or MIE:Mode:Import. Ask opens on this mode unless it is passed one.",
          "MIE.Mode = MIE:Mode:Import"),
 'Format': ("The file format: CSV, TSV, JSON, XML, XLS or XLSX. Blank means it is taken from the file extension.",
            "MIE.Format = 'XLSX'"),
 'FileName': ("The file to read or write, with its full path.",
              "MIE.FileName = LONGPATH() & '\\customers.xlsx'"),
 'SheetName': ("Excel: the sheet to read from or write to. Blank means the first sheet on import and Sheet1 on export.",
               "MIE.SheetName = 'Customers'"),
 'HasHeader': ("1 when the first row holds the column names (CSV, TSV, XLS, XLSX). With 0, the columns are called Column1, Column2 ... and Auto Map matches by position.",
               "MIE.HasHeader = 0                          ! the file starts with data"),
 'Delimiter': ("CSV only: the separator. One of , ; | or the word tab.",
               "MIE.Delimiter = ';'                        ! European Excel CSV"),
 'Encoding': ("Text formats: the character set. Import accepts auto, utf8, ansi or a code page number; export accepts utf8, utf8bom, ansi or a code page. Blank is auto on import and utf8bom on export.",
              "MIE.Encoding = 'ansi'"),
 'XmlRoot': ("XML export: the root element name (default Data).",
             "MIE.XmlRoot = 'Customers'"),
 'XmlRow': ("XML: the element name of one row. On export the default is Row; on import, blank means the repeating element is found automatically.",
            "MIE.XmlRow = 'Customer'"),
 'JsonRoot': ("JSON: on export, wraps the array in an object with this property name. On import, names the property that holds the array (blank finds the first array).",
              "MIE.JsonRoot = 'items'                     ! {\"items\":[ ... ]}"),
 'ImportMode': ("How rows are written: MIE:Import:Add, MIE:Import:Upsert, MIE:Import:Update or MIE:Import:Replace.",
                "MIE.ImportMode = MIE:Import:Upsert"),
 'ReplaceSheet': ("XLSX export: 1 keeps the other sheets of an existing workbook and only adds or replaces SheetName.",
                  "MIE.SheetName    = 'Customers'\n"
                  "MIE.ReplaceSheet = 1"),
 'UsePictures': ("Export: 1 formats dates, times and numbers with each field's dictionary picture instead of yyyy-mm-dd, hh:mm:ss and plain numbers. Those columns are then written as text.",
                 "MIE.UsePictures = 1                        ! 15/03/1970 instead of 1970-03-15"),
 'HelperPath': ("The full path of MIEConvert.exe. The constructor sets it to the program's own folder.",
                "MIE.HelperPath = ExeDir & '\\tools\\MIEConvert.exe'"),
 'IniFile': ("Where SaveMap and LoadMap keep the settings. Blank turns saved mappings off.",
             "MIE.IniFile = INIMgr.FileName"),
 'Silent': ("1 suppresses every message box, for batch jobs and tests.",
            "MIE.Silent = 1\n"
            "IF MIE.Export() THEN Log(MIE.ErrorText)."),
 'ErrorText': ("Why the last Export, Import, LoadColumns or LoadSheets failed, including the helper's own message.",
               "IF MIE.Import()\n"
               "  MESSAGE(MIE.ErrorText, 'Import failed', ICON:Exclamation)\n"
               "END"),
 'Processed': ("Records exported, or data rows read on import.",
               "Log(MIE.Processed & ' rows read')"),
 'Added': ("Import: records inserted.", "IF MIE.Added = 0 THEN MESSAGE('Nothing new.')."),
 'Updated': ("Import: existing records written back (Add or update, Update only).",
             "Log(MIE.Updated & ' customers updated')"),
 'Skipped': ("Rows that ValidateRecord refused, Update-only rows with no matching record, and records ExportFilter left out.",
             "IF MIE.Skipped THEN Log(MIE.Skipped & ' rows skipped by the rules').") ,
 'Failed': ("Import: rows whose insert or update returned an error. LastFailure tells which.",
            "IF MIE.Failed THEN MESSAGE(MIE.LastFailure)."),
 'LastFailure': ("The row number and error of the last failed insert or update.",
                 "IF MIE.Failed > 0\n"
                 "  Log('last problem: ' & MIE.LastFailure)       ! Row 12: Creates Duplicate Key\n"
                 "END"),
 'ProgressControl': ("The PROGRESS control TakeProgress moves. Ask sets it to its own bar; set it yourself to use a bar on your window.",
                     "MIE.ProgressControl = ?MyProgress\n"
                     "MIE.Export()"),
 'StatusControl': ("A STRING control TakeProgress writes the record count into.",
                   "MIE.StatusControl = ?MyStatus"),
 'LineBuf': ("PROTECTED. The line just read from the intermediate file; grows as needed.",
             "!  inside a derived method, after ReadLine\n"
             "IF SELF.LineLen THEN Txt = SELF.LineBuf[1 : SELF.LineLen]."),
 'LineLen': ("The length of the line in LineBuf.", "IF SELF.LineLen = 0 THEN CYCLE.          ! blank line"),
 'LineCap': ("PROTECTED. The allocated size of LineBuf.", "!  internal: AppendLine doubles it when a line is longer"),
 'InPos': ("PROTECTED. Read position in the current 32 KB block.", "!  internal: ReadLine moves it past each line feed"),
 'InLen': ("PROTECTED. Bytes in the current block.", "!  internal: BYTES() of the last NEXT on the DOS file"),
 'InEOF': ("PROTECTED. 1 once the intermediate file is exhausted.", "!  internal: ReadLine returns 0 once it is set and the block is used up"),
 'OutPos': ("PROTECTED. Bytes waiting in the write buffer.", "!  internal: FlushOut writes them with ADD(file, OutPos)"),
 'IOOpen': ("PROTECTED. 1 while the intermediate file is open.", "!  internal: CloseIO does nothing when it is 0"),
 'Writing': ("PROTECTED. 1 when the intermediate file is open for writing.", "!  internal: CloseIO flushes first when it is 1"),
 'Scratch': ("PROTECTED. Work buffer that Escape returns its result from.", "!  internal: grown by EnsureScratch, freed by Destruct"),
 'ScratchCap': ("PROTECTED. The size of Scratch.", "!  internal"),
 'TempSeq': ("PROTECTED. Counter that keeps temporary file names unique within one object.", "!  internal: MIE<thread>_<clock>_<TempSeq>.tsv in %TEMP%"),
}

METHODS = {
 'Construct': ("Creates the queues, sets the defaults (CSV, header row, comma, Add mode) and points HelperPath and IniFile at the program's folder. Runs automatically.",
               "MIE  MyImportExportClass                    ! constructed here"),
 'Destruct': ("Frees every queue and buffer. Runs automatically when the object goes out of scope.",
              "!  nothing to call; DISPOSE a NEWed object to run it\n"
              "DISPOSE(MIERef)"),
 'Init': ("Resets the counters and the error text. Call it before setting the table.",
          "MIE.Init()"),
 'Kill': ("Releases the field references and empties the queues. Call it when you are done.",
          "MIE.Kill()"),
 'SetTable': ("Names the table to work on and, optionally, its primary key. Clears any fields from a previous table.",
              "MIE.SetTable(Customer, 'Customer', CUS:KeyCustNumber)"),
 'AddField': ("Offers one field of the record for import and export: its label, its column name, its dictionary type and picture, the field itself, and whether it is part of the primary key.",
              "MIE.AddField('CUS:CustNumber', 'CustNumber', 'LONG', '@n_10', CUS:CustNumber, 1)\n"
              "MIE.AddField('CUS:Since', 'Since', 'DATE', '@d17', CUS:Since)"),
 'ClearFields': ("Removes every field. SetTable calls it.",
                 "MIE.ClearFields()"),
 'SelectAll': ("Ticks (1) or unticks (0) every field.",
               "MIE.SelectAll(0)                           ! then tick just the ones you want"),
 'AutoMap': ("Matches source columns to fields by name, ignoring case, prefixes, spaces, underscores, dashes and dots. Without a header row it matches by position. Fields with no match are unticked.",
             "MIE.LoadColumns()\n"
             "MIE.AutoMap()"),
 'MapField': ("Maps one field to a named source column by hand. Returns 1 if the field exists. An empty column name unmaps it.",
              "MIE.MapField('CUS:Name', 'Customer name')"),
 'FormatFromFileName': ("Returns the format for a file extension (.txt counts as TSV), or blank.",
                        "MIE.Format = MIE.FormatFromFileName(MIE.FileName)"),
 'LoadSheets': ("Reads the sheet names of the Excel file in FileName into Sheets. Returns 0 when it worked.",
                "IF MIE.LoadSheets() = 0 AND RECORDS(MIE.Sheets)\n"
                "  GET(MIE.Sheets, 1) ; MIE.SheetName = MIE.Sheets.Name\n"
                "END"),
 'LoadColumns': ("Reads the column names and one sample row of FileName into Columns. Returns 0 when it worked.",
                 "IF MIE.LoadColumns() THEN MESSAGE(MIE.ErrorText)."),
 'Export': ("Writes the selected fields of every record to FileName in Format. Returns 0 when it worked; the counters say how many records went out.",
            "MIE.Format   = 'CSV'\n"
            "MIE.FileName = 'c:\\out\\customers.csv'\n"
            "IF MIE.Export() THEN MESSAGE(MIE.ErrorText).") ,
 'Import': ("Reads FileName and writes its rows into the table according to ImportMode and the mapping. Returns 0 when it ran; Failed counts rows that were refused.",
            "MIE.LoadColumns() ; MIE.AutoMap()\n"
            "MIE.ImportMode = MIE:Import:Upsert\n"
            "IF MIE.Import() = 0 THEN MESSAGE(MIE.ResultText()).") ,
 'Ask': ("Opens the import / export window. Pass a mode to open on it. Returns 1 when something was imported or exported.",
         "IF MIE.Ask(MIE:Mode:Import) THEN BRW1.ResetSort(1)."),
 'SaveMap': ("Saves the settings and the field mapping for this table to IniFile. Ask does it after every successful run.",
             "MIE.SaveMap()"),
 'LoadMap': ("Restores what SaveMap stored for this table. Call it after the fields are added.",
             "MIE.LoadMap()\n"
             "MIE.Ask()"),
 'ResultText': ("A summary of the last run, ready for a message box.",
                "MESSAGE(MIE.ResultText(), 'Import complete')"),
 'ResolveMap': ("Re-links each field's SourceName to a column number in Columns and sets KeyMapped. Returns how many selected fields are mapped. Import calls it.",
                "IF MIE.ResolveMap() = 0 THEN MIE.AutoMap()."),
 'GetValue': ("The text of a source column in the row being imported, after unescaping.",
              "!  in ValidateRecord\n"
              "IF UPPER(SELF.GetValue(5)) = 'DELETED' THEN RETURN 1."),
 'ExeFolder': ("The folder of the running program, ending in a backslash.",
               "MIE.HelperPath = MIE.ExeFolder() & 'bin\\MIEConvert.exe'"),
 'ResetCounters': ("Zeroes Processed, Added, Updated, Skipped and Failed and clears the error texts. Export and Import call it.",
                   "MIE.ResetCounters()"),
 'OpenTable': ("Hook. Opens the table before a run; returns 0 when it is open. The default leaves an open file alone, otherwise SHAREs it (CREATEs it first on import if it does not exist).",
               "ThisMIE.OpenTable PROCEDURE()\n"
               "  CODE\n"
               "  IF Access:Customer.Open() THEN RETURN 1.\n"
               "  Access:Customer.UseFile()\n"
               "  RETURN 0"),
 'CloseTable': ("Hook. Closes the table after a run. The default only closes what OpenTable opened.",
                "ThisMIE.CloseTable PROCEDURE()\n"
                "  CODE\n"
                "  Access:Customer.Close()"),
 'PrimeRecord': ("Hook. Called before the fields of a new record are filled, only when no key field is mapped. The ABC template primes auto-increment here.",
                 "ThisMIE.PrimeRecord PROCEDURE()\n"
                 "  CODE\n"
                 "  SELF.FM.PrimeRecord()"),
 'CancelPrime': ("Hook. Called when a primed record is not inserted after all.",
                 "ThisMIE.CancelPrime PROCEDURE()\n"
                 "  CODE\n"
                 "  SELF.FM.CancelAutoInc()"),
 'InsertRecord': ("Hook. Adds the record; returns 0 when it worked. The default is ADD.",
                  "ThisMIE.InsertRecord PROCEDURE()\n"
                  "  CODE\n"
                  "  CUS:ImportedOn = TODAY()\n"
                  "  RETURN PARENT.InsertRecord()"),
 'UpdateRecord': ("Hook. Writes an existing record back; returns 0 when it worked. The default is PUT.",
                  "ThisMIE.UpdateRecord PROCEDURE()\n"
                  "  CODE\n"
                  "  RETURN SELF.FM.TryUpdate()"),
 'FetchRecord': ("Hook. Reads the record whose primary key is in the buffer; returns 0 when found. The default is GET on TableKey.",
                 "ThisMIE.FetchRecord PROCEDURE()\n"
                 "  CODE\n"
                 "  RETURN SELF.FM.TryFetch(SELF.TableKey)"),
 'DeleteRecord': ("Hook. Deletes the current record for the Replace all mode; returns 0 when it worked. The default is DELETE.",
                  "ThisMIE.DeleteRecord PROCEDURE()\n"
                  "  CODE\n"
                  "  RETURN SELF.RM.Delete(0)                ! with the dictionary's RI"),
 'ValidateRecord': ("Hook. Called on import after the row is in the record buffer, before it is written. Return non-zero to skip the row.",
                    "ThisMIE.ValidateRecord PROCEDURE()\n"
                    "  CODE\n"
                    "  IF CUS:Email = '' THEN RETURN 1.            ! skip rows without an e-mail\n"
                    "  RETURN 0"),
 'ExportFilter': ("Hook. Called on export for every record. Return 0 to leave the record out.",
                  "ThisMIE.ExportFilter PROCEDURE()\n"
                  "  CODE\n"
                  "  RETURN CHOOSE(CUS:Active = 1, 1, 0)"),
 'TakeProgress': ("Hook. Called for every record; the default moves ProgressControl and writes StatusControl every 50 records.",
                  "ThisMIE.TakeProgress PROCEDURE(LONG pDone,LONG pTotal=0)\n"
                  "  CODE\n"
                  "  IF pDone % 1000 = 0 THEN Log(pDone & ' rows').\n"
                  "  PARENT.TakeProgress(pDone, pTotal)"),
 'ShowMessage': ("Hook. Shows a message unless Silent is set. Derive it to route messages to your own window or log.",
                 "ThisMIE.ShowMessage PROCEDURE(STRING pText,STRING pCaption,<STRING pIcon>)\n"
                 "  CODE\n"
                 "  Log(pCaption & ': ' & pText)"),
 'RunHelper': ("PROTECTED. Runs MIEConvert.exe with the arguments, waits, and copies its error message into ErrorText. Returns 0 on success.",
               "IF SELF.RunHelper('sheets ' & SELF.Quote(SELF.FileName) & ' ' & SELF.Quote(Tmp)) THEN RETURN 1."),
 'TempName': ("PROTECTED. A unique file name in the Windows temp folder.",
              "Tmp = SELF.TempName('tsv')"),
 'Quote': ("PROTECTED. Puts double quotes around a path for the command line.",
           "Args = 'export ' & SELF.Quote(Tmp) & ' ' & SELF.Quote(SELF.FileName)"),
 'Escape': ("PROTECTED. Escapes backslash, tab, CR and LF for the intermediate file.",
            "SELF.WriteText(SELF.Escape(SELF.FieldToText()))"),
 'UnescapeTo': ("PROTECTED. Undoes Escape into a buffer and returns the length.",
                "Len = SELF.UnescapeTo(Raw, Buffer)"),
 'SplitLine': ("PROTECTED. Splits a tab-separated line into Values. The caller passes one byte more than the line.",
               "SELF.SplitLine(SELF.LineBuf[1 : SELF.LineLen + 1])"),
 'FreeValues': ("PROTECTED. Disposes the strings in Values and empties it.",
                "SELF.FreeValues()"),
 'FieldToText': ("PROTECTED. The current field's value as export text (ISO dates, hh:mm:ss times, plain numbers, or the picture).",
                 "GET(SELF.Fields, I) ; Txt = SELF.FieldToText()"),
 'TypeCode': ("PROTECTED. The column type sent to the helper: S, N, D or T.",
              "SELF.WriteText(SELF.TypeCode())"),
 'TextToField': ("PROTECTED. Converts imported text and stores it in the current field.",
                 "GET(SELF.Fields, I) ; SELF.TextToField('2026-10-09')"),
 'ApplyRow': ("PROTECTED. Copies every mapped column of the current row into the record buffer.",
              "CLEAR(SELF.TableFile) ; SELF.ApplyRow()"),
 'NormalName': ("PROTECTED. The name Auto Map compares: upper case, no prefix, no spaces or punctuation.",
                "IF SELF.NormalName('Cust Number') = SELF.NormalName('CUS:CustNumber') THEN Same = 1."),
 'CommonArgs': ("PROTECTED. The helper options that follow from the settings (format, sheet, delimiter ...).",
                "Args = 'import ' & SELF.Quote(SELF.FileName) & ' ' & SELF.Quote(Tmp) & SELF.CommonArgs()"),
 'IsDate': ("PROTECTED. 1 when the current field holds a date: type DATE, or a number with an @D picture.",
            "IF SELF.IsDate() THEN Txt = FORMAT(SELF.Fields.Ref, @D10-)."),
 'IsTime': ("PROTECTED. 1 when the current field holds a time: type TIME, or a number with an @T picture.",
            "IF SELF.IsTime() THEN Txt = FORMAT(SELF.Fields.Ref, @T04)."),
 'IsNumber': ("PROTECTED. 1 for the numeric types (BYTE ... DECIMAL, REAL).",
              "IF SELF.IsNumber() THEN SELF.Fields.Ref = DEFORMAT(Txt)."),
 'OpenRead': ("PROTECTED. Opens a file for ReadLine. Returns 0 when it is open.",
              "IF SELF.OpenRead(Tmp) = 0\n"
              "  LOOP WHILE SELF.ReadLine() ; DO TakeLine ; END\n"
              "  SELF.CloseIO()\n"
              "END"),
 'OpenWrite': ("PROTECTED. Creates a file for WriteText. Returns 0 when it is open.",
               "IF SELF.OpenWrite(Tmp) THEN RETURN 1."),
 'CloseIO': ("PROTECTED. Flushes and closes the intermediate file.",
             "SELF.CloseIO()"),
 'ReadLine': ("PROTECTED. Reads the next line into LineBuf / LineLen. Returns 0 at the end of the file.",
              "LOOP WHILE SELF.ReadLine()\n"
              "  IF SELF.LineLen = 0 THEN CYCLE.\n"
              "END"),
 'AppendLine': ("PROTECTED. Appends text to LineBuf, growing it.",
                "SELF.AppendLine(Chunk)"),
 'WriteText': ("PROTECTED. Appends text to the write buffer.",
               "SELF.WriteText('<13,10>')"),
 'FlushOut': ("PROTECTED. Writes the buffer to disk.",
              "SELF.FlushOut()"),
 'EnsureScratch': ("PROTECTED. Makes Scratch at least this big.",
                   "SELF.EnsureScratch(LEN(Txt) * 2)"),
}

# What each equate means (the value comes from the .inc)
EQUATES = {
 'MIE:Mode:Export':    "Export: Ask opens on export, Export() is the call.",
 'MIE:Mode:Import':    "Import: Ask opens on import, Import() is the call.",
 'MIE:Import:Add':     "Add every row as a new record.",
 'MIE:Import:Upsert':  "Update the record whose primary key matches; add the row when none does.",
 'MIE:Import:Update':  "Update matching records only; rows with no match are skipped.",
 'MIE:Import:Replace': "Delete every record of the table, then add the rows.",
}

# The helper's options: what each one does.  The list of options is read out
# of helper\MIEConvert\Program.cs.
OPTIONS = {
 'format':       ("import, export", "csv, tsv, json, xml, xls or xlsx. Default: the file extension (.txt reads as csv)."),
 'sheet':        ("import, export", "Excel sheet name. Import default: the first sheet; export default: Sheet1."),
 'noheader':     ("import, export", "Import: the first row is data and the columns are named Column1..N. Export: no header row."),
 'delimiter':    ("import, export", "CSV separator: , ; | or tab (also comma, semicolon, pipe, space)."),
 'encoding':     ("import, export", "Import: auto, utf8, ansi or a code page. Export: utf8, utf8bom (default), ansi or a code page."),
 'rowpath':      ("import", "XML: the element name of one row. JSON: the property (or dotted path) that holds the array."),
 'maxrows':      ("import", "Stop after this many data rows (used for the column preview)."),
 'errfile':      ("all", "On failure the error message is written to this file. The class always passes one."),
 'root':         ("export", "XML root element (default Data). JSON: wrap the array in {\"name\":[...]}."),
 'row':          ("export", "XML row element (default Row)."),
 'replacesheet': ("export", "xlsx: keep the other sheets of an existing workbook; add or replace only --sheet."),
 'codepage':     ("all", "Code page of the intermediate tab file (default: the Windows ANSI code page)."),
}
