#TEMPLATE(MyImportExport,'MyImportExport - import / export any dictionary table - v1.0'),FAMILY('ABC','CW20')
#!============================================================================
#! MyImportExport - generic import / export for any dictionary table
#!   Formats : CSV, TSV, JSON, XML, XLS, XLSX  (via MIEConvert.exe)
#!   Class   : libsrc\win\MyImportExport.inc / .clw   (MyImportExportClass)
#!   Repo    : https://github.com/robertorenz/myimportexport
#!
#!   Templates in this set
#!     MyImportExportGlobal   APPLICATION extension. Add it ONCE to every app
#!                            of the suite. Includes the class, sets the
#!                            _MIEDllMode_ / _MIELinkMode_ project defines,
#!                            and (where requested) generates the global
#!                            procedure MIE_ImportExport(STRING,BYTE=0),BYTE
#!                            and MIE_ExportTables(<STRING>),BYTE (several
#!                            tables into one file) in their own module
#!                            <program>_MIE.clw, sharing one dictionary-bound
#!                            class MIE_DictClass (SetupTable + ABC hooks).
#!     MyImportExportButtons  WINDOW control template: Import... / Export...
#!                            buttons (or one button that asks).
#!     MyImportExportCall     CODE template: call MIE_ImportExport anywhere.
#!
#!   Field selection rules (per dictionary table, see MyImportExport.tpw)
#!     - skipped: GROUP / END markers, MEMO, BLOB, fields declared OVER(),
#!       and every field inside a GROUP that is OVER() or DIM()'d
#!     - skipped: any field (or GROUP) whose dictionary User Options
#!       contain MIEEXCLUDE; a table whose User Options contain MIEEXCLUDE
#!       is skipped entirely
#!     - DIM arrays: one AddField per element (Label[1], Label[2] ...)
#!     - ALIAS tables are skipped (they share the physical file of the
#!       aliased table, which is offered instead); so are VIEWs and tables
#!       that end up with no usable field
#!============================================================================
#!
#!
#!============================================================================
#! GLOBAL EXTENSION
#!============================================================================
#EXTENSION(MyImportExportGlobal,'MyImportExport - global support (add once to every app)'),APPLICATION,DESCRIPTION('MyImportExport - import / export any dictionary table')
#SHEET,HSCROLL
  #TAB('&General')
    #DISPLAY('MyImportExport template build 2026-10-09b')
    #PROMPT('&Disable MyImportExport in this application',CHECK),%MIEDisable,DEFAULT(0),AT(10)
    #BOXED('The MIE_ImportExport procedure')
      #PROMPT('&Generate MIE_ImportExport in this application',CHECK),%MIEGenerate,DEFAULT(%GlobalExternal=0),AT(10)
      #DISPLAY('Tick it in ONE application of a multi-DLL suite - normally the')
      #DISPLAY('data DLL (where the tables live) - or in a single EXE. The other')
      #DISPLAY('apps leave it unticked: they import the procedure from that DLL')
      #DISPLAY('(its .LIB must be in their project, as for any DLL procedure).')
    #ENDBOXED
    #BOXED('Defaults used by the import / export window')
      #PROMPT('Default &format:',DROP('XLSX|XLS|CSV|TSV|JSON|XML')),%MIEFormat,DEFAULT('XLSX')
      #PROMPT('&Use dictionary pictures for dates, times and numbers',CHECK),%MIEUsePictures,DEFAULT(0),AT(10)
    #ENDBOXED
  #ENDTAB
  #TAB('&Helper && INI')
    #BOXED('MIEConvert.exe')
      #PROMPT('&Helper program:',@s255),%MIEHelper,DEFAULT('MIEConvert.exe')
      #DISPLAY('A name without a folder is looked up beside the program (.exe)')
      #DISPLAY('at run time. Start the entry with ! to use a variable / expression.')
      #PROMPT('&Copy the helper to the output folder on build',CHECK),%MIECopyHelper,DEFAULT(0),AT(10)
    #ENDBOXED
    #BOXED('Saved column mappings')
      #PROMPT('&INI file:',@s255),%MIEIniFile,DEFAULT('')
      #DISPLAY('Blank = the application INI file (ABC: INIMgr.FileName).')
      #DISPLAY('Start the entry with ! to use a variable / expression.')
    #ENDBOXED
  #ENDTAB
  #TAB('&Tables')
    #BOXED('Tables that are NOT offered')
      #PROMPT('&Exclude tables:',FROM(%File)),%MIEExcludeTables,MULTI('Tables to exclude'),INLINE,UNIQUE,SELECTION('Tables to exclude')
      #DISPLAY('Also excluded: ALIAS tables, and any table or field whose dictionary')
      #DISPLAY('User Options contain MIEEXCLUDE. MEMO and BLOB fields are never offered.')
      #PROMPT('Skip &in-memory tables (MEMORY driver, declared as QUEUE / GROUP)',CHECK),%MIESkipMemory,DEFAULT(1),AT(10)
      #PROMPT('&Only tables this application already uses',CHECK),%MIEUsedOnly,DEFAULT(0),AT(10)
      #DISPLAY('Unticked, tables no procedure uses are declared in the app so they')
      #DISPLAY('can be exported too - except a table whose file name is a variable')
      #DISPLAY('(!Name): that variable may not exist in this app, so such a table is')
      #DISPLAY('offered only when a procedure of this app already uses it.')
    #ENDBOXED
    #BOXED('ABC: "Replace all" import mode deletes records through')
      #PROMPT('&Delete with:',DROP('FileManager (no cascade)|RelationManager (enforce RI)')),%MIEDeleteVia,DEFAULT('FileManager (no cascade)')
      #DISPLAY('RelationManager honours the dictionary RI: Cascade rules DELETE the')
      #DISPLAY('child records of every replaced row, Restrict rules stop the delete.')
    #ENDBOXED
  #ENDTAB
  #TAB('&Multi-DLL')
    #BOXED('Where the MyImportExportClass code lives')
      #PROMPT('&Class code:',DROP('Default|Compile into this application|Import from a DLL')),%MIEClassLocation,DEFAULT('Default')
      #DISPLAY('Default follows Global Properties > External, like the ABC classes:')
      #DISPLAY('  None external (single EXE, data DLL) - compiled in (and exported')
      #DISPLAY('  from a DLL); All external from a DLL - imported from that DLL.')
      #PROMPT('&Export the class from this DLL:',DROP('Default|Yes|No')),%MIEExportClass,DEFAULT('Default')
      #DISPLAY('Default = yes for a DLL whose class code is compiled in and whose')
      #DISPLAY('globals are not external (the data DLL).')
    #ENDBOXED
  #ENDTAB
#ENDSHEET
#!
#ATSTART
  #DECLARE(%MIEIsABC)
  #DECLARE(%MIEDllMode)
  #DECLARE(%MIELinkMode)
  #DECLARE(%MIEDoExportClass)
  #DECLARE(%MIEModuleBase)
  #DECLARE(%MIEModuleFile)
  #DECLARE(%MIETables),UNIQUE
  #DECLARE(%MIEKeepTables),UNIQUE
  #DECLARE(%MIESkippedTables),MULTI
  #DECLARE(%MIEKeyFields),UNIQUE
  #DECLARE(%MIEIncFile)
  #DECLARE(%MIEIncFound)
  #DECLARE(%MIEIncDefinesLink)
  #DECLARE(%MIEIncMethods),MULTI
  #DECLARE(%MIEFieldCount)
  #IF(UPPER(%AppTemplateFamily)='CLARION')
    #SET(%MIEIsABC,0)
  #ELSE
    #SET(%MIEIsABC,1)
  #ENDIF
  #! --- class location: same rule ABC uses for its own classes (ABOOP.tpw %SetCategoryLocation)
  #CASE(%MIEClassLocation)
  #OF('Compile into this application')
    #SET(%MIEDllMode,0)
  #OF('Import from a DLL')
    #SET(%MIEDllMode,1)
  #ELSE
    #IF(%GlobalExternal AND %ExternalSource='Dynamic Link Library (DLL)')
      #SET(%MIEDllMode,1)
    #ELSE
      #SET(%MIEDllMode,0)
    #ENDIF
  #ENDCASE
  #SET(%MIELinkMode,1-%MIEDllMode)
  #CASE(%MIEExportClass)
  #OF('Yes')
    #SET(%MIEDoExportClass,%MIELinkMode)
  #OF('No')
    #SET(%MIEDoExportClass,0)
  #ELSE
    #IF(%MIELinkMode AND NOT %GlobalExternal)
      #SET(%MIEDoExportClass,1)
    #ELSE
      #SET(%MIEDoExportClass,0)
    #ENDIF
  #ENDCASE
  #IF(UPPER(%ProgramExtension)<>'DLL')
    #SET(%MIEDoExportClass,0)
  #ENDIF
  #SET(%MIEModuleBase,SLICE(%Program,1,INSTRING('.',%Program,1,1)-1))
  #SET(%MIEModuleFile,%MIEModuleBase & '_MIE.clw')
  #! --- read the class header (found through the redirection file)
  #CALL(%MIEReadInc)
  #! --- the tables that get a CASE branch
  #IF(%MIEDisable=0 AND %MIEGenerate)
    #FOR(%File),WHERE(%FileType='FILE' AND NOT %AliasFile)
      #IF(INLIST(%File,%MIEExcludeTables))
        #CYCLE
      #ENDIF
      #IF(INSTRING('MIEEXCLUDE',UPPER(%FileUserOptions),1,1))
        #CYCLE
      #ENDIF
      #IF(%MIESkipMemory)
        #! #CALL, not %MIEIsMemoryTable() in the #IF: a no-parameter group
        #! called inside an expression here skips the rest of the loop body
        #CALL(%MIEIsMemoryTable),%MIEFieldCount
        #IF(%MIEFieldCount)
          #CYCLE
        #ENDIF
      #ENDIF
      #SET(%MIEFieldCount,%MIEFieldLoop(0))
      #IF(%MIEFieldCount > 0)
        #ADD(%MIETables,%File)
      #ENDIF
    #ENDFOR
  #ENDIF
#ENDAT
#!
#!----------------------------------------------------------------------------
#AT(%AfterGlobalIncludes),WHERE(%MIEDisable=0)
   INCLUDE('MyImportExport.inc'),ONCE
#ENDAT
#!
#!----------------------------------------------------------------------------
#AT(%GlobalMap),WHERE(%MIEDisable=0)
  #IF(%MIEGenerate)
     MODULE('%MIEModuleFile')
       MIE_ImportExport(STRING,BYTE=0),BYTE,PROC
       MIE_ExportTables(<STRING>),BYTE,PROC
     END
  #ELSE
     MODULE('MIE_ImportExport_DLL')
       MIE_ImportExport(STRING,BYTE=0),BYTE,PROC,DLL
       MIE_ExportTables(<STRING>),BYTE,PROC,DLL
     END
  #ENDIF
#ENDAT
#!
#!----------------------------------------------------------------------------
#! Project defines, used files, the generated module, the helper copy.
#! %CustomGlobalDeclarations runs before the program module is generated and
#! before ABC builds its file list from %UsedFile (ABCHAIN.TPL / CW.TPL).
#AT(%CustomGlobalDeclarations),WHERE(%MIEDisable=0),PRIORITY(9500)
  #! the family is only known for sure once the chain body has run (CW.TPL sets it late)
  #IF(UPPER(%AppTemplateFamily)='CLARION')
    #SET(%MIEIsABC,0)
  #ELSE
    #SET(%MIEIsABC,1)
  #ENDIF
  #PDEFINE('_MIEDllMode_',%MIEDllMode)
  #IF(NOT %MIEIncDefinesLink)
  #PDEFINE('_MIELinkMode_',%MIELinkMode)
  #ENDIF
  #IF(%MIELinkMode)
    #! MyImportExport.clw reads / writes the MIE-TSV file through the DOS driver
    #FIX(%Driver,'DOS')
    #IF(%Driver='DOS')
  #PROJECT(%DriverLIB)
      #IF(VAREXISTS(%UsedDriverDLLs))
        #ADD(%UsedDriverDLLs,%DriverDLL)
      #ENDIF
    #ELSE
      #ERROR('MyImportExport: the DOS file driver must be registered (MyImportExport.clw uses it)')
    #ENDIF
  #ENDIF
  #IF(%MIECopyHelper AND SUB(%MIEHelper,1,1)<>'!' AND %MIEHelper<>'')
  #PROJECT('None(' & %MIEHelper & '),CopyToOutputDirectory=Always')
  #ENDIF
  #IF(%MIEGenerate)
    #! %UsedFile now holds every table the procedures use (they generate first).
    #! A table nobody uses is declared because of us - unless that can't compile.
    #FREE(%MIEKeepTables)
    #FREE(%MIESkippedTables)
    #FOR(%MIETables)
      #FIX(%File,%MIETables)
      #IF(INLIST(%MIETables,%UsedFile))
        #ADD(%MIEKeepTables,%MIETables)
      #ELSIF(%MIEUsedOnly)
        #ADD(%MIESkippedTables,%MIETables & ' - not used by this application')
      #ELSIF(%FileName<>'' AND SUB(%FileName,1,1)<>'''')
        #! NAME(variable): the variable may not be declared in this app
        #ADD(%MIESkippedTables,%MIETables & ' - not used by this application, file name is the variable ' & %FileName)
      #ELSE
        #ADD(%MIEKeepTables,%MIETables)
      #ENDIF
    #ENDFOR
    #FREE(%MIETables)
    #FOR(%MIEKeepTables)
      #ADD(%MIETables,%MIEKeepTables)
      #ADD(%UsedFile,%MIEKeepTables)
    #ENDFOR
    #MESSAGE('Generating Module:    ' & %MIEModuleFile,1)
    #CREATE('MIEMOD.$$$')
#INSERT(%MIEWriteModule)
    #CLOSE('MIEMOD.$$$')
    #REPLACE(%MIEModuleFile,'MIEMOD.$$$')
    #REMOVE('MIEMOD.$$$')
    #PROJECT(%MIEModuleFile)
  #ENDIF
#ENDAT
#!
#!----------------------------------------------------------------------------
#AT(%DLLExportList),WHERE(%MIEDisable=0 AND UPPER(%ProgramExtension)='DLL')
  #IF(%MIEGenerate)
; MyImportExport: the generated procedures
  %[55](LINKNAME('MIE_ImportExport(STRING,BYTE),BYTE')) @?
  %[55](LINKNAME('MIE_ExportTables(<<STRING>),BYTE')) @?
  #ENDIF
  #IF(%MIEDoExportClass)
    #IF(%MIEIncFound)
; MyImportExport: MyImportExportClass (read from %MIEIncFile)
  %[55]('VMT$MYIMPORTEXPORTCLASS') @?
  %[55]('TYPE$MYIMPORTEXPORTCLASS') @?
      #FOR(%MIEIncMethods)
  %[55](LINKNAME(%MIEIncMethods,'MyImportExportClass')) @?
      #ENDFOR
    #ELSE
; MyImportExport: MyImportExport.inc was not found on the redirection path - class NOT exported
    #ENDIF
  #ENDIF
#ENDAT
#!
#!
#!============================================================================
#! CONTROL TEMPLATE - Import / Export buttons
#!============================================================================
#CONTROL(MyImportExportButtons,'MyImportExport - Import / Export buttons'),WINDOW,MULTI,REQ(MyImportExportGlobal),DESCRIPTION('Import / Export buttons (' & %MIEBtnTableSource & CHOOSE(%MIEBtnTableSource='A specific table',': ' & %MIEBtnTable,'') & ')')
  CONTROLS
    BUTTON('&Import...'),AT(,,50,14),USE(?MIEImport)
    BUTTON('E&xport...'),AT(52,0,50,14),USE(?MIEExport)
    BUTTON('Export &tables...'),AT(104,0,64,14),USE(?MIEExportTables)
  END
#SHEET
  #TAB('&General')
    #PROMPT('&Disable these buttons',CHECK),%MIEBtnDisable,DEFAULT(0),AT(10)
    #PROMPT('&Table:',DROP('Procedure''s primary table|A specific table|Ask the user at run time')),%MIEBtnTableSource,DEFAULT('Procedure''s primary table')
    #ENABLE(%MIEBtnTableSource='A specific table'),CLEAR
      #PROMPT('&Specific table:',FROM(%File)),%MIEBtnTable,DEFAULT('')
    #ENDENABLE
    #DISPLAY('Procedure''s primary table = the table of the first browse on the')
    #DISPLAY('window, else the form''s table; none found = the user picks one.')
    #PROMPT('&Buttons:',DROP('Two buttons (Import, Export)|One button (asks Import or Export)')),%MIEBtnStyle,DEFAULT('Two buttons (Import, Export)')
    #DISPLAY('One button: the Import button becomes "Import / Export..." and pops a')
    #DISPLAY('menu; the Export button is hidden (you may move it out of the way).')
    #PROMPT('&Refresh the window after a successful import',CHECK),%MIEBtnRefresh,DEFAULT(1),AT(10)
    #PROMPT('Show the "Export &tables..." button (several tables, one file)',CHECK),%MIEBtnTables,DEFAULT(0),AT(10)
    #DISPLAY('Unticked, that button is hidden at run time. The one-button style')
    #DISPLAY('always offers "Export several tables..." as a third menu item.')
  #ENDTAB
#ENDSHEET
#!
#ATSTART
  #DECLARE(%MIEImportCtl)
  #DECLARE(%MIEExportCtl)
  #DECLARE(%MIETablesCtl)
  #DECLARE(%MIEBtnCallTable)
  #FOR(%Control),WHERE(%ControlInstance = %ActiveTemplateInstance)
    #CASE(%ControlOriginal)
    #OF('?MIEImport')
      #SET(%MIEImportCtl,%Control)
    #OF('?MIEExport')
      #SET(%MIEExportCtl,%Control)
    #OF('?MIEExportTables')
      #SET(%MIETablesCtl,%Control)
    #ENDCASE
  #ENDFOR
  #CASE(%MIEBtnTableSource)
  #OF('A specific table')
    #SET(%MIEBtnCallTable,%MIEBtnTable)
  #OF('Ask the user at run time')
    #SET(%MIEBtnCallTable,'')
  #ELSE
    #SET(%MIEBtnCallTable,%MIEProcPrimary())
  #ENDCASE
#ENDAT
#!
#AT(%AfterWindowOpening),WHERE(%MIEBtnDisable=0)
  #IF(SUB(%MIEBtnStyle,1,3)='One')
    #IF(%MIEImportCtl)
%MIEImportCtl{PROP:Text} = 'Import / E&xport...'
    #ENDIF
    #IF(%MIEExportCtl)
%MIEExportCtl{PROP:Hide} = True
    #ENDIF
    #IF(%MIETablesCtl)
%MIETablesCtl{PROP:Hide} = True
    #ENDIF
  #ELSIF(NOT %MIEBtnTables AND %MIETablesCtl)
%MIETablesCtl{PROP:Hide} = True
  #ENDIF
#ENDAT
#!
#AT(%ControlEventHandling,%MIEImportCtl,'Accepted'),WHERE(%MIEBtnDisable=0)
  #IF(SUB(%MIEBtnStyle,1,3)='One')
CASE POPUP('&Import...|E&xport...|Export several &tables...')
OF 1
  #INSERT(%MIECallAndRefresh,%MIEBtnCallTable,'MIE:Mode:Import',%MIEBtnRefresh)
OF 2
  #INSERT(%MIECallAndRefresh,%MIEBtnCallTable,'MIE:Mode:Export',0)
OF 3
  MIE_ExportTables()
END
  #ELSE
#INSERT(%MIECallAndRefresh,%MIEBtnCallTable,'MIE:Mode:Import',%MIEBtnRefresh)
  #ENDIF
#ENDAT
#!
#AT(%ControlEventHandling,%MIEExportCtl,'Accepted'),WHERE(%MIEBtnDisable=0 AND SUB(%MIEBtnStyle,1,3)<>'One')
#INSERT(%MIECallAndRefresh,%MIEBtnCallTable,'MIE:Mode:Export',0)
#ENDAT
#!
#AT(%ControlEventHandling,%MIETablesCtl,'Accepted'),WHERE(%MIEBtnDisable=0 AND %MIEBtnTables AND SUB(%MIEBtnStyle,1,3)<>'One')
MIE_ExportTables()
#ENDAT
#!
#!
#!============================================================================
#! CODE TEMPLATE - call MIE_ImportExport
#!============================================================================
#CODE(MyImportExportCall,'MyImportExport - import / export a table'),REQ(MyImportExportGlobal),DESCRIPTION('MyImportExport: ' & %MIECallMode & ' - ' & CHOOSE(%MIECallTableSource='A specific table',%MIECallTable,%MIECallTableSource))
#PROMPT('&Table:',DROP('Ask the user at run time|A specific table|Procedure''s primary table')),%MIECallTableSource,DEFAULT('Ask the user at run time')
#ENABLE(%MIECallTableSource='A specific table'),CLEAR
  #PROMPT('&Specific table:',FROM(%File)),%MIECallTable,DEFAULT('')
#ENDENABLE
#PROMPT('&Mode:',DROP('Ask the user|Export|Import|Export several tables')),%MIECallMode,DEFAULT('Ask the user')
#DISPLAY('Export several tables: the user ticks the tables; the table prompt is ignored.')
#ENABLE(%MIECallMode='Export several tables'),CLEAR
  #PROMPT('Start with &favorite (optional):',@s40),%MIECallFavorite,DEFAULT('')
  #DISPLAY('A favorite saved in the Export tables window: its tables are ticked')
  #DISPLAY('and its format and file filled in when the window opens.')
#ENDENABLE
#PROMPT('Store the &result in (optional):',FIELD),%MIECallResult,DEFAULT('')
#DISPLAY('Result: 1 = something was imported / exported, 0 = cancelled / failed.')
#PROMPT('Re&fresh the window when the result is 1',CHECK),%MIECallRefresh,DEFAULT(0),AT(10)
#!
#DECLARE(%MIECallTableName)
#DECLARE(%MIECallModeEquate)
#DECLARE(%MIECallExpr)
#CASE(%MIECallTableSource)
#OF('A specific table')
  #SET(%MIECallTableName,%MIECallTable)
#OF('Procedure''s primary table')
  #SET(%MIECallTableName,%MIEProcPrimary())
#ELSE
  #SET(%MIECallTableName,'')
#ENDCASE
#CASE(%MIECallMode)
#OF('Export')
  #SET(%MIECallModeEquate,'MIE:Mode:Export')
#OF('Import')
  #SET(%MIECallModeEquate,'MIE:Mode:Import')
#ELSE
  #SET(%MIECallModeEquate,'0')
#ENDCASE
#IF(%MIECallMode='Export several tables')
  #IF(%MIECallFavorite)
    #SET(%MIECallExpr,'MIE_ExportTables(''@' & QUOTE(%MIECallFavorite) & ''')')
  #ELSE
    #SET(%MIECallExpr,'MIE_ExportTables()')
  #ENDIF
#ELSE
  #SET(%MIECallExpr,'MIE_ImportExport(''' & %MIECallTableName & ''',' & %MIECallModeEquate & ')')
#ENDIF
#IF(%MIECallResult)
%MIECallResult = %MIECallExpr
  #IF(%MIECallRefresh)
IF %MIECallResult
  #INSERT(%MIERefreshWindow)
END
  #ENDIF
#ELSIF(%MIECallRefresh)
IF %MIECallExpr
  #INSERT(%MIERefreshWindow)
END
#ELSE
%MIECallExpr
#ENDIF
#!
#!
#!============================================================================
#! Groups (must come after every #AT - a #GROUP swallows what follows it)
#!============================================================================
#INCLUDE('MyImportExport.tpw')
