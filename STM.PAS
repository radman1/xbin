{$A+,B-,D+,E+,F-,G-,I+,L+,N-,O-,P-,Q-,R-,S-,T-,V-,X+,Y+}
UNIT STM;
{=============================================================================

  Unit STreaMs

  Provides buffered input/output for untyped files.

  Purpose :
    Accessing files with small records can slow down a program dramatically
    due to overhead when chaining to the DOS INT 21h handler.  By buffering
    all reads and writes, thereby reducing the number of calls to the INT 21h
    handler, we can gain a significant amount of speed increase at an
    acceptable cost of increased memory use.

    Files are split up into blocks of STM_BufSize bytes, these blocks are
    called 'pages'.  As needs predict, the stream will read the appropriate
    page in memory, and copy the required data out of the buffer.

  The STM unit strongly resembles the C 'FILE' type.  STM is however
  somewhat simpler since it provides no way for altering the buffer size
  (other than changing the STM_BufSize constant and recompiling), and always
  works by reading data on STM_BufSize boundaries.

=============================================================================}

{ﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂ}
                                INTERFACE
{‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹}

USES DOS;

CONST  STM_BufSize = 4096;                   { Multiples of 2 are best       }

TYPE   OpenFlag    = (NOCREATE, CREATE, CREATENEW);

TYPE   STM_Buffer  = ARRAY [0..STM_BufSize-1] OF BYTE;
       STM_BufPtr  = ^STM_Buffer;
       STM_Error   = (STM_OK,                { No error                      }
                      STM_NOMEM,             { Insufficient memory for buffer}
                      STM_OPENERROR,         { Open/create did not succeed   }
                      STM_SEEKERROR,         { Error seeking to location     }
                      STM_READERROR,         { Error when reading            }
                      STM_WRITEERROR);       { Error when writing            }


       STREAM      = RECORD
                       F       : File;       { FILE associated with stream   }
                       BufPtr  : STM_BufPtr; { Pointer to buffer for stream  }
                       PageNr  : LONGINT;    { Page number we're working at  }
                       PageNdx : LONGINT;    { offset within page of current }
                                             { file pointer                  }
                       PageLen : LONGINT;    { Actual length of buffer read  }
                                             { from disk.  will be equal to  }
                                             { STM_BufSize except for the    }
                                             { last page                     }
                       LastErr : STM_Error;  { Last error reported on this   }
                                             { stream                        }
                       Modified: BOOLEAN;    { Has the page been written to? }
                     END;

PROCEDURE STM_Open   (VAR S : STREAM; CONST FName : NameStr; CONST Flag : OpenFlag);
PROCEDURE STM_Create (VAR S : STREAM; CONST FName : NameStr);
PROCEDURE STM_Close  (VAR S : STREAM);
PROCEDURE STM_Write  (VAR S : STREAM; VAR DataBuf; DataLen : Word);
PROCEDURE STM_Read   (VAR S : STREAM; VAR DataBuf; DataLen : Word);
PROCEDURE STM_Flush  (VAR S : STREAM);
PROCEDURE STM_Goto   (VAR S : STREAM; Location : Longint);
FUNCTION  STM_GetPos (VAR S : STREAM) : LongInt;
FUNCTION  STM_GetSize(VAR S : STREAM) : LongInt;

{ﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂﬂ}
                              IMPLEMENTATION
{‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹}

{ Open a stream.
{  Flag:  NOCREATE : Open a stream but do not create a new file              }
{         CREATE   : Open a stream if possible, create a new file if opening }
{                    did not succeed.                                        }
{         CREATENEW: Create a new file                                       }
PROCEDURE STM_Open   (VAR S : STREAM; CONST FName : NameStr; CONST Flag : OpenFlag);
VAR  IsOpen : BOOLEAN;
BEGIN
  IsOpen:=FALSE;
  FILLCHAR(S,sizeof(S),#0);            { Initialize the stream record        }

  IF (MaxAvail<STM_BufSize) THEN BEGIN { Enough memory is available ?        }
     S.LastErr:=STM_NOMEM;
     Exit;
  END;

  ASSIGN (S.F,FName);                  { Assign filename to file             }

  IF (Flag = NOCREATE) OR (Flag = CREATE) THEN BEGIN
     {$i-}
     Reset(S.F,1);
     {$i+}
     IsOpen:=IOResult=0;
  END;
  IF (NOT IsOpen) AND ((Flag = CREATE) OR (Flag = CREATENEW)) THEN BEGIN
     {$i-}
     Rewrite(S.F,1);
     {$i+}
     IsOpen:=IOResult=0;
  END;

  IF NOT IsOpen THEN BEGIN
     S.LastErr:=STM_OPENERROR;
  END
  ELSE BEGIN
     New(S.BufPtr);
     S.PageNr:=-1;                     { Make sure we'll be actually reading }
                                       { a new page                          }
     STM_Goto(S,0);                    { and position at start of file       }
  END;
END;


{ Create a stream }
PROCEDURE STM_Create (VAR S : STREAM; CONST FName : NameStr);
BEGIN
  STM_Open(S,FName,CREATENEW);
END;


{ Close a stream }
PROCEDURE STM_Close  (VAR S : STREAM);
BEGIN
  STM_Flush(S);                        { Force any modified data to disk     }
  Close(S.F);                          { Close the file                      }
  Dispose(S.BufPtr);                   { Free the memory                     }
END;


{ Write the buffered data to disk }
PROCEDURE STM_Flush  (VAR S : STREAM);
VAR BytesWritten : Word;
BEGIN
  IF (S.Modified) THEN BEGIN           { Is there any modified data ?        }
     {$I-}
     Seek(S.F, S.PageNr*STM_BufSize);  { Seek to start of current page       }
     {$I+}
     IF (IOResult<>0) THEN BEGIN
        S.LastErr:=STM_SEEKERROR;
        Exit;
     END;

                                       { Write page                          }
     BlockWrite(S.F, S.BufPtr^, S.PageLen, BytesWritten);
     IF (BytesWritten<>S.PageLen) THEN BEGIN
        S.LastErr:=STM_WRITEERROR;
        Exit;
     END;

     S.Modified:=FALSE;
  END;

  S.LastErr:=STM_OK;
END;


{ Alter the current file pointer (similar to Pascal's Seek) }
PROCEDURE STM_Goto   (VAR S : STREAM; Location : LONGINT);
VAR BytesRead     : Word;
    WantedPageNr  : LongInt;
    WantedPageNdx : LongInt;
BEGIN
  WantedPageNr :=Location DIV STM_BufSize;
  WantedPageNdx:=Location MOD STM_BufSize;

  IF (WantedPageNr<>S.PageNr) THEN BEGIN
     STM_Flush(S);                     { Force any modified data to disk     }
     IF (S.LastErr<>STM_OK) THEN Exit;

     {$I-}                             { Seek to start of current page       }
     Seek(S.F, WantedPageNr*STM_BufSize);
     {$I+}
     IF (IOResult<>0) THEN BEGIN
        S.LastErr:=STM_SEEKERROR;
        Exit;
     END;

                                       { Read page                           }
     BlockRead(S.F, S.BufPtr^, STM_BufSize, BytesRead);
     S.PageLen:=BytesRead;
     IF (WantedPageNdx>S.PageLen) THEN BEGIN
        S.LastErr:=STM_SEEKERROR;
        Exit;
     END;
     S.PageNdx:=WantedPageNdx;
     S.PageNr :=WantedPageNr;
  END
  ELSE
     S.PageNdx:=WantedPageNdx;

  S.LastErr:=STM_OK;
END;


{ Write some data to the stream, not necessarily writing to disk }
PROCEDURE STM_Write  (VAR S : STREAM; VAR DataBuf; DataLen : Word);
VAR BytePtr : ^Byte;
    Len     : Word;
BEGIN
  IF (S.LastErr<>STM_OK) THEN RunError(5);

  BytePtr:=@DataBuf;
  WHILE (DataLen>0) AND (S.LastErr=STM_OK) DO BEGIN
     IF (S.PageNdx+DataLen>STM_BufSize) THEN
        Len:=STM_BufSize-S.PageNdx
     ELSE
        Len:=DataLen;

     Move(BytePtr^,S.BufPtr^[S.PageNdx],Len);
     S.Modified:=TRUE;

     Dec(DataLen,Len);
     Inc(BytePtr,Len);
     Inc(S.PageNdx,Len);

     IF (S.PageLen<S.PageNdx) THEN
        S.PageLen:=S.PageNdx;

     IF (DataLen>0) OR (S.PageNdx=STM_BufSize) THEN
        STM_Goto(S,(S.PageNr+1)*STM_BufSize);
  END;
END;


{ Read some data from the stream }
PROCEDURE STM_Read   (VAR S : STREAM; VAR DataBuf; DataLen : Word);
VAR BytePtr : ^Byte;
    Len     : Word;
BEGIN
  IF (S.LastErr<>STM_OK) THEN RunError(5);

  BytePtr:=@DataBuf;
  WHILE (DataLen>0) AND (S.LastErr=STM_OK) DO BEGIN
     IF (S.PageNdx+DataLen>STM_BufSize) THEN
        Len:=STM_BufSize-S.PageNdx
     ELSE
        Len:=DataLen;

     Move(S.BufPtr^[S.PageNdx],BytePtr^,Len);

     Dec(DataLen,Len);
     Inc(BytePtr,Len);
     Inc(S.PageNdx,Len);

     IF (DataLen>0) OR (S.PageNdx=STM_BufSize) THEN
        STM_Goto(S,(S.PageNr+1)*STM_BufSize);
  END;
END;


{ Return the current file pointer (similar to Pascal's GetPos) }
FUNCTION  STM_GetPos (VAR S : STREAM) : LongInt;
BEGIN
  STM_GetPos := S.PageNr*STM_BufSize + S.PageNdx;
END;


{ Return the current size of the file }
FUNCTION  STM_GetSize(VAR S : STREAM) : LongInt;
BEGIN
  STM_Flush(S);                        { Force data to disk first }
  STM_GetSize:= FileSize(S.F);
END;


END.

