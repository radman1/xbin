{$A+,B-,D+,E+,F-,G-,I+,L+,N-,O-,P-,Q+,R+,S+,T-,V-,X+,Y+}
{$M 4096,0,655360}
PROGRAM BIN_TO_XBIN_Converter;
(*****************************************************************************

 BIN to XBIN conversion program.

 BIN2XBIN will take a set of BIN files, load them as one big BIN, and then
 write an XBIN file.  When the conditional compilation directive XBIN_RAW
 is {$DEFINE}-ed the XBIN is written as an uncompressed file, when XBIN_RAW
 has not been defined, compression is used.

 Most of the code is pretty obvious, the names of the functions/variables and
 the comments should pretty much give you a clue on how things work.

 The actual compression routine is what's most important here.  It stands out
 pretty clear using a thick line to indicate it's start and end.

 The only other part here worth noting is the way the memory is managed...
 some more about that now.

 With Turbo Pascal in real-mode (DOS), you are limited to having datastructures
 (arrays) of maximum 64Kb in size.  Since BIN2XBIN was intended to handle
 pretty big XBIN's (500Kb or so unpacked size) it's obvious some workaround
 was needed...

 The BIN is stored as follows

     ⁄ƒ BIN, an Array of pointers to BIN-Lines
     
   ⁄ƒƒƒƒƒƒƒƒƒø   ⁄ƒƒƒƒƒƒƒƒƒƒ¬ƒƒƒƒƒƒƒƒƒƒ¬ƒƒƒƒƒƒƒƒƒƒ¬    ¬ƒƒƒƒƒƒƒƒƒƒø
   ≥ Line  1 ≥-> ≥ Column 1 ≥ Column 2 ≥ Column 3 ≥ ...≥ Column X ≥
   √ƒƒƒƒƒƒƒƒƒ¥   ¿ƒƒƒƒƒƒƒƒƒƒ¡ƒƒƒƒƒƒƒƒƒƒ¡ƒƒƒƒƒƒƒƒƒƒ¡    ¡ƒƒƒƒƒƒƒƒƒƒŸ
   ≥ Line  2 ≥->
   √ƒƒƒƒƒƒƒƒƒ¥
   ≥ Line  3 ≥->
   √ƒƒƒƒƒƒƒƒƒ¥
   ≥ Line  4 ≥->
   √ƒƒƒƒƒƒƒƒƒ¥
   ...
   √ƒƒƒƒƒƒƒƒƒ¥
   ≥ Line  Y ≥->
   ¿ƒƒƒƒƒƒƒƒƒŸ

 Since we only allocate as much memory as is needed for the entire BIN, there
 is very little overhead, and we are thus able to load quite big BINs.

 Some facts...
   In a pretty normal setup, with say.. 580Mb free, there is about 550Kb free
   for loading the BIN.
   A Normal 80*25 screen takes 4000 Bytes, thus, BIN2XBIN is perfectly capable
   of handling BINs consisting out of 125 80*25 screens.

 I don't think the 10*10 screens limit (effectively a bin of 800*250) is really
   a 'limit'. I've not yet seen any ANSi come even close to that.

*****************************************************************************)

USES  CRT,
      DOS,
      STM;

{ $DEFINE XBIN_RAW}  { Enable compression or not ? }

TYPE  Char4     = ARRAY [0..3] OF Char;

Const XB_ID     : Char4 = 'XBIN';
Const MaxBINLine= 2048;                { Max number of lines in the combined BIN }

TYPE  XB_Header = RECORD
                    ID      : Char4;
                    EofChar : Byte;
                    Width   : Word;
                    Height  : Word;
                    FontSize: Byte;
                    Flags   : Byte;
                  END;
      BINChr    = RECORD               { BIN Character/Attribute pair. }
                    CASE Boolean OF
                    TRUE  : (
                             CharAttr : Word;
                            );
                    FALSE : (
                             Character : Byte;
                             Attribute : Byte;
                            );
                  END;

      BINChrAry = ARRAY[0..32000] OF BINChr;
      BINChrPtr = ^BINChrAry;

VAR   XBHdr     : XB_Header;
      BIN       : ARRAY[1..MaxBINLine] OF BINChrPtr;
      BINWidth  : Word;
      BINHeight : Word;
      ErrCode   : Integer;
      XB        : STREAM;              { File stream, see STM unit }
      Lines     : Word;


{ ABORT Execution and display error message }
PROCEDURE Abort (Str: String);
BEGIN
   WriteLn;
   WriteLn('BIN2XBIN V1.00.  Execution aborted.');
   WriteLn;
   WriteLn(Str);
   WriteLn;
   Halt(2);
END;


{ Display command syntax and abort }
PROCEDURE HelpText;
BEGIN
   WriteLn('BIN2XBIN will combine a set of BIN files and will create a compressed XBIN.');
   WriteLn('BIN2XBIN 1.00 does not have support for alternative palettes or fonts.');
   WriteLn;
   WriteLn('Correct Syntax:  BIN2XBIN <BaseName> [Width (defaults to 80)]');
   WriteLn;
   WriteLn('BIN2XBIN expects to find a set of files called BBBBBBxy.BIN');
   WriteLn('  BBBBBB  names the set.');
   WriteLn('  x  is the X-coordinate of the position of the BIN in the total picture');
   WriteLn('  y  is the Y-coordinate of the position of the BIN in the total picture');
   WriteLn;
   WriteLn('Example.  If you wanted to create an XBIN of 160*50 out of 4 80*25 BINs, then');
   WriteLn('they would be named in following way.');
   WriteLn('                  ⁄ƒƒƒƒƒƒƒƒƒƒƒƒ¬ƒƒƒƒƒƒƒƒƒƒƒƒø');
   WriteLn('                  ≥ NNNN00.BIN ≥ NNNN10.BIN ≥');
   WriteLn('                  √ƒƒƒƒƒƒƒƒƒƒƒƒ≈ƒƒƒƒƒƒƒƒƒƒƒƒ¥');
   WriteLn('                  ≥ NNNN01.BIN ≥ NNNN11.BIN ≥');
   WriteLn('                  ¿ƒƒƒƒƒƒƒƒƒƒƒƒ¡ƒƒƒƒƒƒƒƒƒƒƒƒŸ');
   WriteLn('All BINs must be of identical size and must not contain SAUCE information');
   WriteLn;
   WriteLn('Unless an error occurs, BIN2XBIN will have created a file named BBBBBB.XB');
   Writeln;
   Halt(1);
END;


{ Return size of File in Bytes or -1 if it does not exist or can't determine }
{ size                                                                       }
FUNCTION FileExist (FName:String) : LongInt;
VAR F      : FILE;
BEGIN
  {$i-}
  ASSIGN(F,FName);
  RESET(F,1);
  IF (IOResult=0) THEN BEGIN
     FileExist := FileSize(F);          { Return Size of file        }
     IF (IOResult<>0) THEN
        FileExist:=-1;                  { Return -1 : File not Found }
     Close(F);
  END
  ELSE
     FileExist:=-1;                     { Return -1 : File not Found }
  {$i+}
END;


{ Load multiple BIN files as one BIG BIN }
PROCEDURE LoadBIN (BaseName : String);
VAR B         : FILE;
    X, XMax   : Char;
    Y, YMax   : Char;
    FSize     : LongInt;
    Tel       : Word;
    BytesRead : Word;
    XPos      : Word;
    YPos      : Word;
BEGIN
  XMax:='0';
  YMax:='0';
  FSize:=FileExist(BaseName+'00.BIN');
  IF (FSize<=0) THEN
     Abort('Filename '+BaseName+'00.BIN not found or 0 size.');

  { Determine maximum valid value for 'X' parameter in BIN name }
  WHILE (FileExist(BaseName+XMax+'0.BIN')>=0) AND (XMax<='9') DO Inc(XMax);
  Dec(XMax);              { Last value we tried was NOT valid, so backup one }

  { Determine maximum valid value for 'Y' parameter in BIN name }
  WHILE (FileExist(BaseName+'0'+YMax+'.BIN')>=0) AND (YMax<='9') DO Inc(YMax);
  Dec(YMax);              { Last value we tried was NOT valid, so backup one }

  { --- Calculate number of lines in a single BIN --- }
  BINHeight := FSize DIV (BINWidth*2);
  { --- Calculate width of combined BINs --- }
  XBHdr.Width:=(Ord(XMax)-Ord('0')+1)*BINWidth;
  { --- Calculate height of combined BINs --- }
  XBHdr.Height:=(Ord(YMax)-Ord('0')+1)*BINHeight;

  { --- NOW We want to allocate XBHdr.Height lines of XBHdr.Width character/ }
  {     attribute pairs of memory for loading the entire combined BIN        }
  IF (XBHdr.Height>MaxBINLine) THEN
     Abort('Combined BINS contain more lines than currently possible.'+#10#13+
           'Raise the value of <MaxBINLine> in the source and recompile.');

  FOR Tel:=1 to XBHdr.Height DO BEGIN
     IF (MaxAvail<XBHdr.Height*XBHdr.Width*2) THEN
        Abort('Not enough memory to load all BINs of the set.');
     getmem(BIN[Tel],XBHdr.Width*2);
  END;

  { --- Load all BINs --- }
  WriteLn ('Loading ',XMax,' by ',YMax,' BINs of ',BINWidth,' by ',BINHeight,' Characters');

  FOR Y:='0' to YMax DO BEGIN            { Get all BINs on Y axis }
     FOR X:='0' to XMax DO BEGIN         { Get all BINs on X axis }
        Write(BaseName,X,Y,'.BIN',#13);
        {$i-}
        ASSIGN(B,BaseName+X+Y+'.BIN');
        RESET(B,1);
        IF (IOResult=0) THEN BEGIN
           FOR Tel:=1 TO XBHdr.Height DO BEGIN { Read All lines }
              Write(BaseName,X,Y,'.BIN Line:',Tel,'/',XBHdr.Height,#13);
              YPos:=(Ord(Y)-Ord('0'))*BINHeight+Tel;
              XPos:=(Ord(X)-Ord('0'))*BINWidth*2;
              BlockRead(B,BIN[YPos]^[XPos],BINWidth*2,BytesRead);
              IF (BytesRead<>BINWidth*2) THEN
                 Abort('Error reading file '+BaseName+X+Y+'.BIN');
           END;
           Close(B);
        END
        ELSE
           Abort('Error opening file '+BaseName+X+Y+'.BIN');
        {$i+}
     END;
  END;
  WriteLn('':79,#13,'Loading completed');
END;


{€€€ XBIN Compression START €€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€}

{
  Introductory note.

  The XBIN compression used here is a single step compression algorythm.
  What this means is that we will compress the data one character/attribute
  pair at a time letting that char/attr pass through all the necessary
  conditions until it has been decided what has to be done with it.
  While not being the fastest or most compact algorythm available, it does
  make the algorythm a lot easier to understand.

  This XBIN compression routine uses a temporary buffer (an array) to hold
  the current run-count and compressed data.  Since the maximum run-count is
  64, this buffer only needs to be 129 bytes in size (1 byte for the
  run-count, and 64 times a char/attr pair when no compression is taking
  place.

  The overall idea behind this routine is pretty simple..  here's the rough
  outline:

  WHILE (Still_characters_to_process)
     IF (A_run_is_busy)
        IF (Stop_this_run_for_whatever_reason)
           Write_run_to_disk;
        ENDIF
     ENDIF
     IF (Run_is_still_busy)
        add_current_char/attr_pair_to_run;
     ELSE
        start_a_new_run_with_char/attr_pair;
     ENDIF
  ENDWHILE
  IF (A_run_is_busy)
     Write_run_to_disk;
  ENDIF

  It looks simple, but implementing it effectively is tricky.  The most
  involving part will be the "Stop_this_run_for_whatever_reason" routine.
  There are several reasons for wishing to stop the run.
    1) The current run is 64 characters wide, thus, another char/attr pair
       can't be added.
    2) The current compression can no longer be maintained as the new
       char/attr pair does not match.
    3) Aborting the run prematurely offers a possibility to restart using a
       better compression method.
  Reasons 1 and 2, are easy enough to deal with, the third provides the path
  to optimal compression.  The better the conditions are made for aborting in
  favour of a better compression method, the better compression will be.

  Enough about theory, on to the actual code.
}

PROCEDURE XBIN_Compress (VAR BIN:BINChrAry; BIN_Width : WORD);

CONST NO_COMP       = $00;
      CHAR_COMP     = $40;
      ATTR_COMP     = $80;
      CHARATTR_COMP = $C0;

VAR   CompressBuf   : Array[0..2*64] of Byte;
      RunCount      : Word;
      RunMode       : Byte;
      RunChar       : BINChr;
      CB_Index      : Word;            { Index into CompressBuf               }
      BIN_Index     : Word;            { Index into BIN_Line                  }
      EndRun        : Boolean;

BEGIN
  RunCount := 0;                       { There's no run busy                  }
  BIN_Index:= 0;

  WHILE (BIN_Index<BIN_Width) DO BEGIN { Still characters to process ?        }
     IF (RunCount>0) THEN BEGIN        { A run is busy                        }
        EndRun := FALSE;               { Assume we won't need to end the run  }

        IF (RunCount=64) THEN BEGIN    { We reached the longest possible run? }
           EndRun:=TRUE;               { Yes, end the current run             }
        END
        ELSE BEGIN
           { A run is currently busy.  Check to see if we can/will continue...}
           CASE RunMode OF
              NO_COMP       : BEGIN
                { No compression can always continue, since it does not       }
                { require on the character and/or attribute to match its      }
                { predecessor                                                 }

                { === No compression run.  Aborting this will only have       }
                {     benefit if we can start a run of at least 3 character   }
                {     or attribute compression. OR a run of at least 2        }
                {     char/attr compression                                   }
                {     The required run of 3 (2) takes into account the fact   }
                {     that a run must be re-issued if no more than 3 (2)      }
                {     BIN pairs can be compressed                             }
                IF (BIN_Width-BIN_Index>=2) AND
                   (BIN[BIN_Index].CharAttr=BIN[BIN_Index+1].CharAttr) THEN BEGIN
                   EndRun:=TRUE;
                END
                ELSE IF (BIN_Width-BIN_Index>=3) AND
                        (BIN[BIN_Index].Character=BIN[BIN_Index+1].Character) AND
                        (BIN[BIN_Index].Character=BIN[BIN_Index+2].Character) THEN BEGIN
                   EndRun:=TRUE;
                END
                ELSE IF (BIN_Width-BIN_Index>=3) AND
                        (BIN[BIN_Index].Attribute=BIN[BIN_Index+1].Attribute) AND
                        (BIN[BIN_Index].Attribute=BIN[BIN_Index+2].Attribute) THEN BEGIN
                   EndRun:=TRUE;
                END
              END;

              CHAR_COMP     : BEGIN
                { Character compression needs to be ended when the new        }
                { character no longer matches the run-character               }
                IF (BIN[BIN_Index].Character<>RunChar.Character) THEN BEGIN
                   EndRun:=TRUE;
                END
                { === Aborting an character compression run will only have    }
                {     benefit if we can start a run of at least 3 char/attr   }
                {     pairs.                                                  }
                ELSE IF (BIN_Width-BIN_Index>=3) AND
                        (BIN[BIN_Index].CharAttr=BIN[BIN_Index+1].CharAttr) AND
                        (BIN[BIN_Index].CharAttr=BIN[BIN_Index+2].CharAttr) THEN BEGIN
                   EndRun:=TRUE;
                END
              END;

              ATTR_COMP     : BEGIN
                { Attribute compression needs to be ended when the new        }
                { attribute no longer matches the run-attribute               }
                IF (BIN[BIN_Index].Attribute<>RunChar.Attribute) THEN BEGIN
                   EndRun:=TRUE;
                END
                { === Aborting an attribute compression run will only have    }
                {     benefit if we can start a run of at least 3 char/attr   }
                {     pairs.                                                  }
                ELSE IF (BIN_Width-BIN_Index>=3) AND
                        (BIN[BIN_Index].CharAttr=BIN[BIN_Index+1].CharAttr) AND
                        (BIN[BIN_Index].CharAttr=BIN[BIN_Index+2].CharAttr) THEN BEGIN
                   EndRun:=TRUE;
                END
              END;

              CHARATTR_COMP : BEGIN
                { Character/Attribute compression needs to be ended when the  }
                { new char/attr no longer matches the run-char/attr           }
                IF (BIN[BIN_Index].CharAttr<>RunChar.CharAttr) THEN BEGIN
                   EndRun:=TRUE;
                END
                { === Aborting a char/attr compression will never yield any   }
                {     benefit                                                 }
              END;
           END; { CASE }
        END; { IF }

        IF EndRun THEN BEGIN
           CompressBuf[0] := RunMode + (RunCount-1);
           STM_Write(XB,CompressBuf,CB_Index);
           IF (XB.LastErr<>STM_OK) THEN Abort('Error Writing File');

           RunCount:=0;                { Run no longer busy                   }
        END; { IF }
     END; { IF }

     IF (RunCount>0) THEN BEGIN        { Run is still busy ?                  }
         { === Add new char/attr to current run as appropriate for compression}
         {     method in use                                                  }
         CASE RunMode OF
            NO_COMP       : BEGIN
               { Store Char/Attr pair                                         }
               CompressBuf[CB_Index]:=BIN[BIN_Index].Character;
               CompressBuf[CB_Index+1]:=BIN[BIN_Index].Attribute;
               Inc(CB_Index,2);
            END;

            CHAR_COMP     : BEGIN
               { Store Attribute                                              }
               CompressBuf[CB_Index]:=BIN[BIN_Index].Attribute;
               Inc(CB_Index);
            END;

            ATTR_COMP     : BEGIN
               { Store character                                              }
               CompressBuf[CB_Index]:=BIN[BIN_Index].Character;
               Inc(CB_Index);
            END;

            CHARATTR_COMP : BEGIN
               { Nothing to change, only RunCount ever changes                }
            END;
         END;
     END
     ELSE BEGIN                        { Run not busy, Start a new one        }
         CB_Index := 1;                { Skip index 0 (for run-count byte)    }

         IF (BIN_Width-BIN_Index>=2) THEN BEGIN { At least 2 more to do       }
            IF (BIN[BIN_Index].CharAttr=BIN[BIN_Index+1].CharAttr) THEN
               { === We can use char/attr compression                         }
               RunMode:=CHARATTR_COMP
            ELSE IF (BIN[BIN_Index].Character=BIN[BIN_Index+1].Character) THEN
               { === We can use character compression                         }
               RunMode:=CHAR_COMP
            ELSE IF (BIN[BIN_Index].Attribute=BIN[BIN_Index+1].Attribute) THEN
               { === We can use attribute compression                         }
               RunMode:=ATTR_COMP
            ELSE
               { === We can't use any compression                             }
               RunMode:=NO_COMP;
         END
         ELSE                          { Last character, use no-compression   }
            RunMode:=NO_COMP;

         IF (RunMode=ATTR_COMP) THEN BEGIN
                                       { Attr compression has Attr first !!   }
            CompressBuf[CB_Index]:=BIN[BIN_Index].Attribute;
            CompressBuf[CB_Index+1]:=BIN[BIN_Index].Character;
         END
         ELSE BEGIN
            CompressBuf[CB_Index]:=BIN[BIN_Index].Character;
            CompressBuf[CB_Index+1]:=BIN[BIN_Index].Attribute;
         END;

         Inc(CB_Index,2);
         RunChar.CharAttr:=BIN[BIN_Index].CharAttr;
     END; { IF }

     Inc(RunCount);                    { RunCount is now one more             }
     Inc(BIN_Index);                   { One char/attr pair processed         }
  END;

  IF (RunCount>0) THEN BEGIN
     CompressBuf[0] := RunMode + (RunCount-1);
     STM_Write(XB,CompressBuf,CB_Index);
     IF (XB.LastErr<>STM_OK) THEN Abort('Error Writing File');
  END;
END;

{€€€ XBIN Compression END €€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€}


BEGIN { *** MAIN *** }
  WriteLn ('BIN TO XBIN Converter V1.00.');
  WriteLn ('Coded by Tasmaniac / ACiD.');
  WriteLn ('Sourcecode placed into the public domain, use and modify freely');
  WriteLn;

  { --- Check passed parameter ------------------------------------------- }
  IF (ParamCount<>1) AND (ParamCount<>2) THEN HelpText;

  { --- Complete XBIN Header --------------------------------------------- }
  IF (ParamCount=2) THEN BEGIN
     Val(ParamStr(2),BINWidth,ErrCode);
     IF ErrCode<>0 THEN Abort('Invalid width specified');
  END
  ELSE
     BINWidth:=80;

  { --- Load BIN's ------------------------------------------------------- }
  LoadBIN(ParamStr(1));

  { ===========================  CREATE XBIN  ============================ }
  STM_Create(XB,Paramstr(1)+'.XB');
  IF (XB.LastErr<>STM_OK) THEN Abort('Error creating XBIN file '+ParamStr(1)+'.XB');

  XBHdr.ID      := XB_ID; { 'XBIN' ID                       }
  XBHdr.EofChar := 26;    { Mark EOF when TYPEing XBIN      }
{ XBHDr.Width   :=          Already filled in by LoadBIN()  }
{ XBHdr.Height  :=          Already filled in by LoadBIN()  }
  XBHdr.FontSize:= 16;    { Default font is 16 pixels high  }
  {$IFDEF XBIN_RAW}
     XBHdr.Flags   := $00;{ Compression disabled. no special features are enabled }

     { --- Write Header ----------------------------------------------------- }
     WriteLn('Writing XBIN Header');
     STM_Write(XB,XBHdr,Sizeof(XBHdr));
     IF (XB.LastErr<>STM_OK) THEN Abort('Error Writing XBIN File');

     { --- Write image data ------------------------------------------------- }
     WriteLn('Writing uncompressed image data');
     FOR Lines:=1 to XBHdr.Height DO BEGIN
        Write(Lines,'/',XBHdr.Height,#13);
        STM_Write(XB,BIN[Lines]^,XBHdr.Width*2);
        IF (XB.LastErr<>STM_OK) THEN Abort('Error Writing File');
     END;
     Write('':79,#13);

  {$ELSE}
     XBHdr.Flags   := $04;{ Compression enabled. no special features are enabled }

     { --- Write Header ----------------------------------------------------- }
     WriteLn('Writing XBIN Header');
     STM_Write(XB,XBHdr,Sizeof(XBHdr));
     IF (XB.LastErr<>STM_OK) THEN Abort('Error Writing XBIN File');

     { --- Write image data ------------------------------------------------- }
     WriteLn('Writing compressed image data');
     FOR Lines:=1 to XBHdr.Height DO BEGIN
        Write(Lines,'/',XBHdr.Height,#13);
        XBIN_Compress(BIN[Lines]^,XBHdr.Width);
     END;
     Write('':79,#13);

  {$ENDIF}

  STM_Close(XB);

  WriteLn ('Conversion complete.');
END.






