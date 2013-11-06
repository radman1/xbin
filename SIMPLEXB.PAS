{$A+,B-,D+,E+,F-,G-,I+,L+,N-,O-,P-,Q+,R+,S+,T-,V-,X+,Y+}
{$M 4096,0,655360}

PROGRAM Simple_XB_Viewer;

USES  CRT,   { Standard CRT unit }
      STM,   { Streams }
      VGA;   { VGA functions }

TYPE  Char4        = ARRAY [0..3] OF Char;

Const XB_ID        : Char4 = 'XBIN';
      XBIN_PALETTE = $01;
      XBIN_FONT    = $02;
      XBIN_COMPRESS= $04;
      XBIN_NONBLINK= $08;
      XBIN_512     = $10;
      XBIN_RESERVED= $E0;

TYPE  XB_Header    = RECORD
                       ID      : Char4;
                       EofChar : Byte;
                       Width   : Word;
                       Height  : Word;
                       Fontsize: Byte;
                       Flags   : Byte;
                     END;
      LineStart    = ARRAY[0..1023] OF LongInt;
      LineStartPtr = ^LineStart;

VAR   XBIN         : Stream;
      XBHdr        : XB_Header;
      Lines        : ARRAY[0..63] OF LineStartPtr; { Offset in File of line start }
      Font         : ARRAY[0..(512*32)-1] OF Byte; { Font Table                   }
      Palette      : ARRAY[0..15,1..3] OF Byte;    { Palette                      }
      FontDepth    : Word;                         { 256 or 512 characters        }
      Count        : Word;
      X, Y         : Word;
      CountByte    : Byte;
      RunLength    : Byte;
      Choice       : Char;
      LineBuf      : ARRAY[1..128] OF BYTE;

PROCEDURE Abort (Str: String);
BEGIN
   WriteLn;
   WriteLn('SimpleXB V1.00.  Execution aborted.');
   WriteLn;
   WriteLn(Str);
   WriteLn;
   Halt(1);
END;

FUNCTION Strf(Val:Word):String;
VAR Temp : STRING;
BEGIN
   Str(Val,Temp);
   Strf:=Temp;
END;

{€ Show palette : Quick & Dirty method €€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€}
PROCEDURE ShowPalette;
Const BW_Pal : Array[1..6] of Byte = (0,0,0,63,63,63);
VAR Count : Word;
    X, Y  : Word;
    Col   : Word;
    Row   : Word;
    WMode : Boolean;
BEGIN
  WMode:=DirectVideo;                  { Save DirectVideo status }
  DirectVideo:=FALSE;                  { Set it to false         }
  VGA_Mode($13);                       { Set mode 320*200 256 colors }
  { Color setup for showing the palette          }
  {   0 : remains black                          }
  {   1 : white                                  }
  {   2-17 : Palette from XBIN                   }
  VGA_SetPalette(0,2,BW_Pal);
  VGA_SetPalette(2,16,Palette);

  TextColor(1);
  TextBackGround(0);
  WriteLn; WriteLn;
  WriteLn('              XBIN PALETTE');
  WriteLn('             --------------');
  WriteLn;
  WriteLn('  0    1    2    3    4    5    6    7');
  WriteLn; WriteLn; WriteLn; WriteLn; WriteLn; WriteLn;
  WriteLn('  8    9    10   11   12   13   14   15');

  FOR Count:=0 TO 15 DO BEGIN
     Col:=Count MOD 8;
     Row:=Count DIV 8;
     { Draw box }
     FOR X:=0 TO 31 DO BEGIN
        MEM[SegA000:(49+Row*56)*320+(X+Col*40)+4] := 1;
        MEM[SegA000:(80+Row*56)*320+(X+Col*40)+4] := 1;
     END;
     FOR Y:=0 TO 31 DO BEGIN
        MEM[SegA000:(49+Y+Row*56)*320+(Col*40)+ 4] := 1;
        MEM[SegA000:(49+Y+Row*56)*320+(Col*40)+35] := 1;
     END;
     FOR X:=1 TO 30 DO BEGIN
        FOR Y:=1 to 30 DO BEGIN
           MEM[SegA000:(49+Y+Row*56)*320+(X+Col*40)+4] := Count+2;
           MEM[SegA000:(49+Y+Row*56)*320+(X+Col*40)+4] := Count+2;
        END;
     END;
  END;

  IF (ReadKey=#0) THEN
     ReadKey;

  TextMode(Co80);
  DirectVideo:=WMode;                  { Restore orriginal DirectVideo }
END;


{€ Show font : Quick & Dirty method €€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€}
PROCEDURE ShowFont;
VAR Count : Word;
    Y     : Word;
    Block : Word;
    Col   : Word;
    Row   : Word;
    WMode : Boolean;
    Part  : Word;
BEGIN
  WMode:=DirectVideo;                  { Save DirectVideo status }
  DirectVideo:=FALSE;                  { Set it to false         }
  VGA_Mode($12);                       { Set mode 640*480 16 colors }

  Part:=0;

  REPEAT
     WriteLn('                               XBIN Font (Part ',Part+1,')');
     WriteLn('                              --------------------');
     WriteLn;
     WriteLn('    x> 0 1 2 3 4 5 6 7 8 9 A B C D E F    x> 0 1 2 3 4 5 6 7 8 9 A B C D E F');
     WriteLn('    0x','8x':38); WriteLn;
     WriteLn('    1x','9x':38); WriteLn;
     WriteLn('    2x','Ax':38); WriteLn;
     WriteLn('    3x','Bx':38); WriteLn;
     WriteLn('    4x','Cx':38); WriteLn;
     WriteLn('    5x','Dx':38); WriteLn;
     WriteLn('    6x','Ex':38); WriteLn;
     WriteLn('    7x','Fx':38); WriteLn;

     For Count:=0 to 255 DO BEGIN
        Row  :=(Count MOD 128) DIV 16;
        Col  :=(Count MOD 128) MOD 16;
        Block:=Count DIV 128;
        FOR Y:=0 TO XBHdr.FontSize-1 DO
          MEM[SegA000:((Row*32)+64+Y)*80+Col*2+38*Block+7]:=
          Font[(Part*256+Count)*XBHdr.FontSize+Y];
     END;

     Inc(Part);
     IF (XBHdr.Flags AND XBIN_512) = 0 THEN Inc(Part); { Set Part to 2 if 256 characters }
  UNTIL Part=2;

  IF (ReadKey=#0) THEN
     ReadKey;

  TextMode(Co80);
  DirectVideo:=WMode;                  { Restore original DirectVideo }
END;

{€ Show Image €€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€€}
PROCEDURE ShowImage(DispHeight : WORD);
TYPE VideoWord = RECORD
                   Case Boolean of
                   True : (Character:Byte; Attribute:Byte);
                   False: (CharAttr :Word);
                 END;
VAR  TopX : WORD;
     TopY : WORD;
     X,Y  : WORD;
     Len  : WORD;
     CH   : Char;
     VidW : VideoWord;
     Count: BYTE;
BEGIN
  GotoXY(1,1);

  TopX:=0;
  TopY:=0;

  IF (XBHdr.Width<80) THEN
     Len:=XBHdr.Width
  ELSE
     Len:=80;

  IF XBHdr.Height<DispHeight THEN
     DispHeight:=XBHdr.Height;
  REPEAT
     FOR Y:=0 TO DispHeight-1 DO BEGIN
        IF (XBHdr.Flags AND XBIN_COMPRESS) <> 0 THEN BEGIN
           STM_Goto(XBIN,Lines[(Y+TopY) DIV 1024]^[(Y+TopY) MOD 1024]);
           IF (XBIN.LastErr<>STM_OK) THEN BEGIN
              TextMode(Co80);
              Abort('Error reading XBIN.');
           END;

           X:=0;
           WHILE X<TopX+Len DO BEGIN
              STM_Read(XBIN,Countbyte,1);
              IF (XBIN.LastErr<>STM_OK) THEN BEGIN
                 TextMode(Co80);
                 Abort('Invalid XBIN.  Out of data.');
              END;

              RunLength := (CountByte AND $3F) + 1;
              CASE (CountByte AND $C0) OF
                 $00 : STM_Read(XBIN,LineBuf,RunLength*2);
                 $40 : STM_Read(XBIN,LineBuf,1+RunLength);
                 $80 : STM_Read(XBIN,LineBuf,1+RunLength);
                 $C0 : STM_Read(XBIN,LineBuf,2);
              END;
              IF (XBin.lastErr<>STM_OK) THEN BEGIN
                 TextMode(Co80);
                 Abort('Invalid XBIN.  Out of data.');
              END;

              FOR Count:=1 TO RunLength DO BEGIN
                 CASE (CountByte AND $C0) OF
                    $00 : BEGIN
                            VidW.Character:=LineBuf[Count*2-1];
                            VidW.Attribute:=LineBuf[Count*2];
                          END;
                    $40 : BEGIN
                            VidW.Character:=LineBuf[1];
                            VidW.Attribute:=LineBuf[Count+1];
                          END;
                    $80 : BEGIN
                            VidW.Character:=LineBuf[Count+1];
                            VidW.Attribute:=LineBuf[1];
                          END;
                    $C0 : BEGIN
                            VidW.Character:=LineBuf[1];
                            VidW.Attribute:=LineBuf[2];
                          END;
                 END;
                 IF (X>=TopX) AND (X<TopX+Len) THEN
                    MemW[SegB800:Y*160+(X-TopX)*2]:=VidW.CharAttr;

                 Inc(X);
                 Dec(RunLength);
              END;
           END;
        END
        ELSE BEGIN  { ==== DISPLAY UNCOMPRESSED XBIN DATA ===== }
           STM_Goto(XBIN,Lines[(Y+TopY) DIV 1024]^[(Y+TopY) MOD 1024]+(TopX*2));
           IF (XBIN.LastErr<>STM_OK) THEN BEGIN
              TextMode(Co80);
              Abort('Error reading XBIN.');
           END;
           STM_Read(XBIN,MEM[SegB800:Y*160],Len*2);
           IF (XBIN.LastErr<>STM_OK) THEN BEGIN
              TextMode(Co80);
              Abort('Error reading XBIN.');
           END;
        END;
     END;

     CH:=ReadKey;
     IF CH=#0 THEN BEGIN
        CH:=ReadKey;
        CASE Ch OF
           #72 : IF TopY>0 THEN Dec(TopY);  { Up key }
           #80 : IF TopY<XBHdr.Height-DispHeight THEN Inc(TopY);  { Down key }
           #75 : IF TopX>0 THEN Dec(TopX); { Left key }
           #77 : IF TopX<XBHdr.Width-80 THEN Inc(TopX); { Right key }
        END;
     END;
  UNTIL CH=#27;
END;


BEGIN
  CheckBreak:=True;
  DirectVideo:=False;
  TextMode(Co80);

  WriteLn ('SimpleXB V1.00.  Simple eXtended BIN format viewer');
  WriteLn ('Coded by Tasmaniac / ACiD.');
  WriteLn ('Sourcecode placed into the public domain, use freely');
  WriteLn;

  { --- Check for presence of a VGA card --- }
  IF (NOT VGA_IsPresent) THEN
     Abort('VGA required');

  { --- Check if sufficient memory is available and allocate Lines --- }
  WriteLn('Allocating memory...');
  FOR Count:=Low(Lines) TO High(Lines) DO BEGIN
     IF MaxAvail<Sizeof(Lines[Count]^) THEN
       Abort('Insuficient memory');
     New(Lines[Count]);
  END;

  { --- Check passed parameter and open XB file -------------------------- }
  IF (ParamCount<>1) THEN Abort('SimpleXB Filename');

  WriteLn('Opening XBIN ('+ParamStr(1)+')...');
  STM_Open(XBIN,ParamStr(1),NOCREATE);
  IF (XBIN.LastErr<>STM_OK) THEN Abort('Error opening XBIN file '+ParamStr(1));

  { --- Read XBIN Header ------------------------------------------------- }
  WriteLn('Reading XBIN Header...');
  STM_Read(XBIN,XBHdr,Sizeof(XBHdr));
  IF (XBIN.LastErr<>STM_OK) THEN Abort('Error reading XBIN Header.');

  { --- ID bytes check out ? --------------------------------------------- }
  IF (XBHdr.ID<>XB_ID) OR
     (XBHdr.EofChar<>26) THEN Abort('File is not an eXtended BIN');
  WriteLn('   Image width  : ',XBHdr.Width);
  WriteLn('   Image height : ',XBHdr.Height);
  { IF Width=0 then Height must be 0 too. and vice versa }
  IF ((XBHdr.Width =0) AND (XBHdr.Height<>0) OR
      (XBHdr.Width<>0) AND (XBHdr.Height =0)) THEN
     Abort('Invalid XBIN.  <Width> and <Height> must both be equal or different from 0');

  Write  ('   Palette      : ');
  IF (XBHdr.Flags AND XBIN_PALETTE) <> 0 THEN
     WriteLn('Alternate palette present')
  ELSE
     WriteLn('Default palette');

  IF XBHdr.Flags AND XBIN_512 <> 0 THEN
     FontDepth:=512
  ELSE
     FontDepth:=256;

  Write  ('   Font set     : ');
  IF (XBHdr.Flags AND XBIN_FONT) <> 0 THEN BEGIN
     WriteLn('Alternate font, ',FontDepth,' characters.');
     WriteLn('   Fontsize     : ',XBHdr.Fontsize);
  END
  ELSE BEGIN
     WriteLn('Default font, ',FontDepth,' characters');
     WriteLn('   Fontsize     : ',XBHdr.FontSize,' (Default font)');

     IF XBHdr.Fontsize<>16 THEN Abort('Invalid XBIN.  Default <Fontsize> should be 16.');
     IF FontDepth<>256 THEN Abort('Invalid XBIN.  Default font must have 256 characters.');
  END;
  IF (XBHdr.FontSize=0) OR (XBHdr.FontSize>32) THEN
     Abort('Invalid XBIN.  <Fontsize> must be between 1 and 32.');

  Write  ('   Compression  : ');
  IF (XBHdr.Flags AND XBIN_COMPRESS) <> 0 THEN
     WriteLn('XBIN Compressed')
  ELSE
     WriteLn('Uncompressed BIN');

  Write  ('   Blinking     : ');
  IF (XBHdr.Flags AND XBIN_NONBLINK) <> 0 THEN
     WriteLn('Disabled')
  ELSE
     WriteLn('Enabled');

  IF (XBHdr.Flags AND XBIN_RESERVED) <> 0 THEN
     WriteLn('Invalid XBIN.  Reserved <Flags> must be zero.');

  { --- IF a Palette is present, read it --------------------------------- }
  IF (XBHdr.Flags AND XBIN_PALETTE <> 0) THEN BEGIN
     WriteLn('Reading palette...');
     STM_Read(XBIN,Palette,Sizeof(Palette));
     IF (XBIN.LastErr<>STM_OK) THEN
        Abort('Error reading XBIN palette.');
     FOR Count:=Low(Palette) TO High(Palette) DO BEGIN
        IF Palette[Count][1]>63 THEN
           Abort('Invalid palette value for color '+Strf(Count)+' RED');
        IF Palette[Count][2]>63 THEN
           Abort('Invalid palette value for color '+Strf(Count)+' GREEN');
        IF Palette[Count][3]>63 THEN
           Abort('Invalid palette value for color '+Strf(Count)+' BLUE');
     END;
  END;

  { --- IF a font is present, read it ------------------------------------ }
  IF (XBHdr.Flags AND XBIN_FONT <> 0) THEN BEGIN
     WriteLn('Reading font...');
     STM_Read(XBIN,Font,FontDepth*XBHdr.Fontsize);
     IF (XBIN.LastErr<>STM_OK) THEN
        Abort('Error reading XBIN font.');
  END;

  { --- Check Image data & mode ------------------------------------------ }
  IF (XBHdr.Width>0) THEN BEGIN
     IF (XBHdr.Flags AND XBIN_COMPRESS) <> 0 THEN BEGIN
        WriteLn('Checking and preparing XBIN compressed image data...');

        Y:=0;
        WHILE Y<XBHdr.Height DO BEGIN
           Write(#13,' Checking line ',Y+1);
           Lines[Y DIV 1024]^[Y MOD 1024]:=STM_GetPos(XBin);
           X:=0;
           WHILE X<XBHdr.Width DO BEGIN
              STM_Read(XBIN,Countbyte,1);
              IF (XBIN.LastErr<>STM_OK) THEN
                 Abort('Invalid XBIN.  Out of data.');

              RunLength := (CountByte AND $3F) + 1;
              Inc(X,RunLength);
              CASE (CountByte AND $C0) OF
                 $00 : STM_Read(XBIN,LineBuf,RunLength*2);
                 $40 : STM_Read(XBIN,LineBuf,1+RunLength);
                 $80 : STM_Read(XBIN,LineBuf,1+RunLength);
                 $C0 : STM_Read(XBIN,LineBuf,2);
              END;
              IF (XBin.lastErr<>STM_OK) THEN
                 Abort('Invalid XBIN.  Out of data.');
           END;

           IF (X>XBHdr.Width) THEN
              Abort('Invalid XBIN.  Compressed across line boundary.');

           Inc(Y);
        END;
        Write(#13,'':79,#13);

     END
     ELSE BEGIN
        WriteLn('Checking and preparing uncompressed image data...');
        IF STM_GetSize(XBIN)<STM_GetPos(XBIN)+(XBHdr.Width*XBHdr.Height*2) THEN
           Abort('Invalid XBIN.  Insufficient image data');
        FOR Count:=0 to XBHdr.Height-1 DO
           Lines[Count DIV 1024]^[Count MOD 1024]:=STM_GetPos(XBIN)+(Count*XBHdr.Width*2);
     END;
  END;
  WriteLn('ƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒ');
  WriteLn('XBIN checks out ok...');
  WriteLn('ƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒƒ');
  WriteLn;

  { --- Ask user what to do next ----------------------------------------- }
  REPEAT
     Write('Display: <P>alette, <F>ont, <I>magedata, <X>BIN, All other keys quit : ');
     Choice:=Upcase(Readkey);
     WriteLn(Choice);
     IF Choice=#0 THEN BEGIN  { Function key was pressed }
        Choice:=Readkey;      { Process the next scancode }
        Choice:=#27;          { All others keys quit... }
     END;

     CASE (Choice) OF
        'P' : BEGIN
                 IF (XBHdr.Flags AND XBIN_PALETTE) <> 0 THEN
                    ShowPalette
                 ELSE
                    WriteLn('Default palette applies');
              END;
        'F' : BEGIN 
                 IF (XBHdr.Flags AND XBIN_FONT) <> 0 THEN
                    ShowFont
                 ELSE
                    WriteLn('Default palette applies');
              END;
        'I' : BEGIN
                 ShowImage(25);
                 TextMode(Co80);
              END;
        'X' : BEGIN
                VGA_Set8PixelFont; { This'll look better }

                IF (XBHdr.Flags AND XBIN_PALETTE) <> 0 THEN BEGIN
                   VGA_SetFlatTextPal;
                   VGA_SetPalette(0,16,Palette);
                END;

                IF (XBHdr.Flags AND XBIN_NONBLINK) <> 0 THEN
                   VGA_SetBlink(FALSE);

                IF (XBHdr.Flags AND XBIN_512) <> 0 THEN
                   VGA_SetActiveFont(0,4); { Activate Character map 0 and 4 }
                                           { 0 and 4 are adjacent Character }
                                           { maps                           }

                VGA_SetFontSize(XBHdr.FontSize);
                IF (XBHDR.Flags AND XBIN_FONT) <> 0 THEN
                   VGA_SetFont(0,FontDepth,XBHdr.FontSize,0,Font);

                ShowImage(400 DIV XBHdr.FontSize); { 400 Scanlines are on screen }
                TextMode(Co80);
              END;
        ELSE Choice:=#27;
     END;
  UNTIL (Choice=#27);


  { --- Free allocated memory -------------------------------------------- }
  WriteLn('Closing XBIN...');
  STM_Close (XBIN);

  { --- Free allocated memory -------------------------------------------- }
  WriteLn('Freeing memory...');
  FOR Count:=Low(Lines) TO High(Lines) DO BEGIN
     Dispose(Lines[Count]);
  END;
END.

