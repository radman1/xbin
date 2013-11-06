{$A+,B-,D-,E-,F-,G-,I-,L-,N-,O-,P-,Q-,R-,S-,T-,V-,X+,Y+}
UNIT VGA;
{=============================================================================

  Unit VGA

  Provides VGA specific functions.
     - VGA detection
     - Setting palette
     - Setting fonts & loading
     ...

=============================================================================}

{ßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßß}
                                INTERFACE
{ÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜ}

CONST  VGA_CRTC         = $03D4;       { Port address CRTC                   }
       VGA_STATUS       = $03DA;       { Port address for Status register    }
       VGA_AC           = $03C0;       { Port address Attribute controller   }
       VGA_AC_READ      = $03C1;       { Read address Attribute controller   }
       VGA_SR           = $03C4;       { Port address Sequencer register     }
       VGA_GC           = $03CE;       { Port address Graphics controller    }
       VGA_PEL_WRITE    = $03C8;       { Port address PEL Address Write      }
       VGA_PEL_READ     = $03C7;       { Port address PEL Address Read       }
       VGA_PEL_DATA     = $03C9;       { Port address PEL Data register      }

FUNCTION  VGA_IsPresent     : BOOLEAN;
PROCEDURE VGA_Mode          (Mode : Byte);
PROCEDURE VGA_SetPalette    (StartColor, NumColors:Byte; VAR Palette);
PROCEDURE VGA_SetFlatTextPal;
PROCEDURE VGA_SetBlink      (BlinkMode : BOOLEAN);
PROCEDURE VGA_SetActiveFont (Font0, Font1 : Byte);
PROCEDURE VGA_SetFontSize   (FontSize:Byte);
PROCEDURE VGA_SetFont       (StartChar,NumChars, FontSize, VideoOffset : Word; VAR Font);
PROCEDURE VGA_Set8PixelFont;

{ßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßßß}
                              IMPLEMENTATION
{ÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜÜ}

{ RETURN TRUE if VGA card is present }
FUNCTION  VGA_IsPresent : BOOLEAN; ASSEMBLER;
ASM
              MOV    AX,01A00h         { Â> Display Combination Code         }
              INT    10h               { Ù                                   }
              CMP    AL,01Ah           { Is AL=01Ah then it's a VGA          }
              MOV    AL,TRUE           { Assume it'll be true                }
              JE     @Return           { We were right, quit now             }
              MOV    AL,FALSE          { We were wrong, return false         }
@Return:
END;


PROCEDURE VGA_Mode       (Mode : Byte); ASSEMBLER;
ASM
              MOV    AH,0
              MOV    AL,Mode
              INT    10h
END;


PROCEDURE VGA_SetPalette (StartColor, NumColors:Byte; VAR Palette); ASSEMBLER;
ASM
              PUSH   DS                { Save DS                          }

              MOV    DX,VGA_PEL_WRITE  { DX = Palette address register    }
              MOV    AL,[StartColor]   { AL = First Color to set          }
              OUT    DX,AL             { Activate StartColor              }
              MOV    AH,[NumColors]    { Get number of colors to modify   }
              CMP    AH,0              { Is it Zero ?                     }
              JE     @SetDone          { Yes, we don't need to do anything}
              LDS    SI,Palette        { DS:SI points to palette data     }
              CLD                      { Increment SI on LODSB            }
              MOV    DX,VGA_PEL_DATA   { DX = Pallette data register      }
@SetColor:    LODSB                    { Load RED                         }
              OUT    DX,AL             { Set RED                          }
              LODSB                    { Load GREEN                       }
              OUT    DX,AL             { Set Green                        }
              LODSB                    { LOAD BLUE                        }
              OUT    DX,AL             { Set BLUE                         }
              DEC    AH                { One color done                   }
              JNZ    @SetColor         { Need to do more ?                }
@SetDone:
              POP    DS                { Restore DS                       }
END;


PROCEDURE VGA_SetFlatTextPal; ASSEMBLER;
ASM
              MOV    DX,VGA_STATUS     { CRTC Status register             }
              IN     AL,DX             { Read CRTC Status. (This'll reset }
                                       { Attribute controller flip-flop)  }
            { Set EGA palette to color 0-15                               }
              MOV    DX,VGA_AC         { Attribute controller             }
              MOV    AL,0              { Color 0. (and Clears PAS field)  }
@NxtPalEGA:   OUT    DX,AL             { Set paletteregister to change    }
              OUT    DX,AL             { Set value for palette register   }
              INC    AL                { Next color                       }
              CMP    AL,0Fh            { All colors done ?                }
              JBE    @NxtPalEGA        { Nope.                            }
              MOV    AL,20h
              OUT    DX,AL             { Set PAS field (Video has access  }
                                       { to palette)                      }
END;


PROCEDURE VGA_SetBlink      (BlinkMode : BOOLEAN); ASSEMBLER;
ASM
              MOV    DX,VGA_STATUS     { CRTC Status register             }
              IN     AL,DX             { Read CRTC Status. (This'll reset }
                                       { Attribute controller flip-flop)  }
            { Set blink bit }
              MOV    DX,VGA_AC         { Attribute controller (Write port)}
              MOV    AL,10h+20h        { Register 10h (Mode control)      }
                                       { leave PAS field enabled.         }
              OUT    DX,AL             { Activate register 10h            }
              MOV    DX,VGA_AC_READ    { DX=003C1h (Attribute READ port)  }
              IN     AL,DX             { Read Mode control register       }
              MOV    DX,VGA_AC         { DX=003C0h (Attribute Write port) }
              CMP    [BlinkMode],TRUE  { BlinkMode = TRUE ?               }
              JE     @SetBlinkBit      {  Yes jump to SetBlinkBit         }
@BlinkOff:    AND    AL,NOT 008h       { Clear the Blink bit              }
              JMP    @SetBlinkBit      { And go tell the VGA card         }
@BlinkOn:     OR     AL,008h           { Clear the Blink bit              }
@SetBlinkBit:
              OUT    DX,AL             { Rewrite Mode control register    }
END;


PROCEDURE VGA_SetActiveFont (Font0, Font1 : Byte); ASSEMBLER;
ASM
              MOV    DX,VGA_SR         { Sequencer register               }
              MOV    AL,03             { Character Map Select             }

              MOV    BL,[Font0]        { Prepare 'Font0' for Character    }
              MOV    BH,BL             { Generator B                      }
              AND    BL,003h
              AND    BH,004h
              SHL    BH,1
              SHL    BH,1
              OR     BL,BH

              MOV    CL,[Font1]        { Prepare 'Font1' for Character    }
              MOV    CH,CL             { Generator A                      }
              AND    CL,003h
              AND    CH,004h
              SHL    CH,1
              OR     CL,CH
              SHL    CX,1
              SHL    CX,1

              MOV    AH,BL             { Combine bits for Char Gen A and B }
              OR     AH,CL             { Ù                                 }
              OUT    DX,AX             { And activate the requested Char   }
                                       { maps                              }
END;


PROCEDURE VGA_SetFontSize (FontSize:Byte); ASSEMBLER;
ASM
              MOV    DX,VGA_CRTC       { CRTC address register             }
              MOV    AL,9              { Index for Max Scanline Register   }
              OUT    DX,AL             { set MSL as active register        }
              INC    DX                { Set DX to CRTC Data register      }
              IN     AL,DX             { read current MSL                  }
              AND    AL,011100000b     { set MSL to 0, preserve others bits}
              MOV    AH,[FontSize]     { get required size                 }
              DEC    AH                { minus one.                        }
              OR     AL,AH             { set size in MSL field             }
              OUT    DX,AL             { Writeback modified value          }
END;


PROCEDURE VGA_SetFont(StartChar, NumChars, FontSize, VideoOffset : Word; VAR Font); ASSEMBLER;
ASM
{ === Switch VGA into linear/planar more, ready for receiving font data === }
              CLI                      { No interrupts allowed             }
              MOV    DX,VGA_SR         { Sequencer register                }
              MOV    AX,0100h          { Â> Synchronous reset              }
              OUT    DX,AX             { Ù                                 }
              MOV    AX,0402h          { Â> Select Plane 2 for WRITE       }
              OUT    DX,AX             { Ù                                 }
              MOV    AX,0704h          { Â> Sequential Addressing mode     }
              OUT    DX,AX             { Ù                                 }
              MOV    AX,0300h          { Â> Release Synchronous reset      }
              OUT    DX,AX             { Ù                                 }

              MOV    DX,VGA_GC         { Graphics controller register      }
              MOV    AX,0204h          { Â> Select Plane 2 for READ        }
              OUT    DX,AX             { Ù                                 }
              MOV    AX,0005h          { Â> Disable odd addressing mode    }
              OUT    DX,AX             { Ù                                 }
              MOV    AX,0006h          { Â> Memory range is A000:0000      }
              OUT    DX,AX             { Ù                                 }
              STI                      { Interrupts enabled                }
{ === LOAD the font ======================================================= }

              MOV    DI,[SegA000]      { ¿                                 }
              MOV    ES,DI             { Ã> ES:DI -> Video Address where   }
              MOV    DI,[StartChar]    { ³           to load font          }
              SHL    DI,1              { ³                                 }
              SHL    DI,1              { ³  DS=VideoOffset + Offset for    }
              SHL    DI,1              { ³     starting at <StartChar>     }
              SHL    DI,1              { ³                                 }
              SHL    DI,1              { ³                                 }
              ADD    DI,[VideoOffset]  { Ù                                 }

              PUSH   DS                { Save DS                           }
              LDS    SI,[Font]         { DS:SI -> Font                     }

              MOV    BX,[NumChars]     { Number of characters to load      }
              CMP    BX,0
              JE     @DoneLoad         { No characters to load, we're done }

              MOV    AX,[FontSize]
              CLD                      { Increment pointers on MOVSB       }
              MOV    DX,32             { Â> DX= 32-FontSize (Size of gap in}
              SUB    DX,AX             { ³  between two videomemory        }
                                       { Ù  characters                     }

@NextChar:    MOV    CX,AX             { Copy FontSize in CX               }
              REP    MOVSB             { Copy current character            }
              ADD    DI,DX             { Skip gap in videomemory           }
              DEC    BX                { One character done                }
              JNZ    @NextChar         { Still more to do ?                }

@DoneLoad:    POP    DS

{ === Switch VGA back into normal textmode operation ====================== }
              CLI                      { No interrupts allowed.            }
              MOV    DX,VGA_SR         { Sequence controller register      }
              MOV    AX,0100h          { Â> Synchronous reset              }
              OUT    DX,AX             { Ù                                 }
              MOV    AX,0302h          { Â> Select Plane 0 & 1 for WRITE   }
              OUT    DX,AX             { Ù                                 }
              MOV    AX,0304h          { Â> Odd/Even Addressing mode       }
              OUT    DX,AX             { Ù                                 }
              MOV    AX,0300h          { Â> Release Synchronous reset      }
              OUT    DX,AX             { Ù                                 }

              MOV    DX,VGA_GC         { Graphics controller register      }
              MOV    AX,0004h          { Â> Select Plane 0 for READ        }
              OUT    DX,AX             { Ù                                 }
              MOV    AX,1005h          { Â> Enable odd addressing mode     }
              OUT    DX,AX             { Ù                                 }
              MOV    AX,0E06h          { Â> Memory range is B800:0000      }
              OUT    DX,AX             { Ù                                 }
              STI                      { Interrupts enabled                }

END;


PROCEDURE VGA_Set8PixelFont; ASSEMBLER;
ASM
              MOV    DX,003CCh         { Misc output register READ port    }
              IN     AL,DX             { Read value.                       }
              AND    AL,0F3h           { Bits 2 & 3 off (Clock select 0).  }
              MOV    DX,003C2h         { Misc Output Write port            }
              OUT    DX,AL             { Writeback modified value          }

              CLI                      { NO interrupts for a while         }
              MOV    DX,03C4h          { Sequencer register                }
              MOV    AX,100h           { \ Generate and hold Synchronous   }
              OUT    DX,AX             { / reset                           }

              MOV    AL,001h           { Clocking mode register            }
              OUT    DX,AL             { Activate Clocking mode register   }
              INC    DX                { Data register                     }
              IN     AL,DX             { Read value                        }
              OR     AL,1              { Set Bit 0 (8/9)                   }
              OUT    DX,AL             { Writeback.                        }
              DEC    DX                { Back to Address register          }

              MOV    AX,300h           { \ Release Reset state. (normal)   }
              OUT    DX,AX             { /                                 }

              MOV    DX,VGA_STATUS     { CRTC Status register              }
              IN     AL,DX             { Read CRTC Status. (This'll reset  }
                                       { Attribute controller flip-flop)   }
              MOV    DX,VGA_AC         { Attribute controller              }
              MOV    AL,13h            { Horizontal Pixel Pan              }
              OUT    DX,AL             { Activate HPP                      }
              MOV    AL,0              { \ Set HPP to 0                    }
              OUT    DX,AL             { /                                 }
              MOV    AL,20h
              OUT    DX,AL             { Set PAS field (Video has access   }
                                       { to palette)                       }

              STI                      { Interrupts allowed again          }
END;


END.





