;======================================================================================================================================
;
; ModernUI Control - ModernUI_ProgressDots v1.0.0.0
;
; Copyright (c) 2018 by fearless
;
; All Rights Reserved
;
; http://www.LetTheLight.in
;
; http://github.com/mrfearless/ModernUI
;
;======================================================================================================================================
.686
.MMX
.XMM
.model flat,stdcall
option casemap:none
include \masm32\macros\macros.asm

;DEBUG32 EQU 1
;
;IFDEF DEBUG32
;    PRESERVEXMMREGS equ 1
;    includelib M:\Masm32\lib\Debug32.lib
;    DBG32LIB equ 1
;    DEBUGEXE textequ <'M:\Masm32\DbgWin.exe'>
;    include M:\Masm32\include\debug32.inc
;ENDIF

include windows.inc
include user32.inc
include kernel32.inc
include gdi32.inc
include comctl32.inc
includelib kernel32.lib
includelib user32.lib
includelib gdi32.lib
includelib comctl32.lib

include ModernUI.inc
includelib ModernUI.lib

include ModernUI_ProgressDots.inc

;--------------------------------------------------------------------------------------------------------------------------------------
; Prototypes for internal use
;--------------------------------------------------------------------------------------------------------------------------------------
_MUI_ProgressDotsWndProc            PROTO :DWORD, :DWORD, :DWORD, :DWORD
_MUI_ProgressDotsParentSubClassProc PROTO :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
_MUI_ProgressDotsInit               PROTO :DWORD
_MUI_ProgressDotsResize             PROTO :DWORD
_MUI_ProgressDotsPaint              PROTO :DWORD

_MUI_ProgressDotsPaintBackground    PROTO :DWORD, :DWORD, :DWORD 
_MUI_ProgressDotsPaintDots          PROTO :DWORD, :DWORD, :DWORD, :DWORD
_MUI_ProgressDotsCalcPositions      PROTO :DWORD
_MUI_ProgressDotsInitDots           PROTO :DWORD
_MUI_ProgressBarTimerProc           PROTO :DWORD, :DWORD

;--------------------------------------------------------------------------------------------------------------------------------------
; Structures for internal use
;--------------------------------------------------------------------------------------------------------------------------------------
; External public properties
MUI_PROGRESSDOTS_PROPERTIES             STRUCT
    dwBackColor                         DD ?
    dwDotColor                          DD ?
    dwDotsShowInterval                  DD ?
    dwDotsTimeInterval                  DD ?
    dwDotsSpeed                         DD ?
MUI_PROGRESSDOTS_PROPERTIES             ENDS

DOTS_USE_TIMERQUEUE                     EQU 1 ; comment out to use WM_SETIMER instead of TimerQueue

; Internal properties
_MUI_PROGRESSDOTS_PROPERTIES            STRUCT
    dwAnimateState                      DD ?
    dwMarkerStart                       DD ?
    dwMarkerFinish                      DD ?
    pDotsArray                          DD ?
    IFDEF DOTS_USE_TIMERQUEUE
    bUseTimerQueue                      DD ?
    hQueue                              DD ?
    hTimer                              DD ?
    ENDIF    
_MUI_PROGRESSDOTS_PROPERTIES            ENDS


DOTINFO                                 STRUCT
    bVisible                            DD 0
    xPos                                DD 0
    ;dwSpeed                             DD 0
    ;dwMoveCountdown                     DD 0
    dwShowCountdown                     DD 0
DOTINFO                                 ENDS



.CONST
MAX_DOTS                                EQU 5  ; No of dots to show - 5 or so looks ok
DOTS_SHOW_INTERVAL                      EQU 16 ; countdown til dot starts showing in animation
DOTS_TIME_INTERVAL                      EQU 10 ; Milliseconds for timer firing, 10 seems fine, increasing this will slow down animations
DOTS_SPEED                              EQU 2  ; Speed of the fastest dots before and after middle section
DOTS_DEFAULT_SIZE                       EQU 4  ; Default height and width of control and also dots



; Internal properties
@ProgressDotsAnimateState               EQU 0
@ProgressDotsMarkerStart                EQU 4
@ProgressDotsMarkerFinish               EQU 8
@ProgressDotsDotsArray                  EQU 12
IFDEF DOTS_USE_TIMERQUEUE
@ProgressDotsUseTimerQueue              EQU 16
@ProgressDotsQueue                      EQU 20
@ProgressDotsTimer                      EQU 24
ENDIF
; External public properties


.DATA
szMUIProgressDotsClass                  DB 'ModernUI_ProgressDots',0    ; Class name for creating our ProgressDots control


.CODE

align 4

;-------------------------------------------------------------------------------------
; Set property for ProgressDots control
;-------------------------------------------------------------------------------------
MUIProgressDotsSetProperty PROC PUBLIC hControl:DWORD, dwProperty:DWORD, dwPropertyValue:DWORD
    Invoke SendMessage, hControl, MUI_SETPROPERTY, dwProperty, dwPropertyValue
    ret
MUIProgressDotsSetProperty ENDP


;-------------------------------------------------------------------------------------
; Get property for ProgressDots control
;-------------------------------------------------------------------------------------
MUIProgressDotsGetProperty PROC PUBLIC hControl:DWORD, dwProperty:DWORD
    Invoke SendMessage, hControl, MUI_GETPROPERTY, dwProperty, NULL
    ret
MUIProgressDotsGetProperty ENDP


;-------------------------------------------------------------------------------------
; MUIProgressDotsRegister - Registers the ProgressDots control
; can be used at start of program for use with RadASM custom control
; Custom control class must be set as ProgressDots
;-------------------------------------------------------------------------------------
MUIProgressDotsRegister PROC PUBLIC
    LOCAL wc:WNDCLASSEX
    LOCAL hinstance:DWORD
    
    Invoke GetModuleHandle, NULL
    mov hinstance, eax

    invoke GetClassInfoEx,hinstance,addr szMUIProgressDotsClass, Addr wc 
    .IF eax == 0 ; if class not already registered do so
        mov wc.cbSize,sizeof WNDCLASSEX
        lea eax, szMUIProgressDotsClass
        mov wc.lpszClassName, eax
        mov eax, hinstance
        mov wc.hInstance, eax
        mov wc.lpfnWndProc, OFFSET _MUI_ProgressDotsWndProc
        Invoke LoadCursor, NULL, IDC_ARROW
        mov wc.hCursor, eax
        mov wc.hIcon, 0
        mov wc.hIconSm, 0
        mov wc.lpszMenuName, NULL
        mov wc.hbrBackground, NULL
        mov wc.style, NULL
        mov wc.cbClsExtra, 0
        mov wc.cbWndExtra, 8 ; cbWndExtra +0 = dword ptr to internal properties memory block, cbWndExtra +4 = dword ptr to external properties memory block
        Invoke RegisterClassEx, addr wc
    .ENDIF  
    ret

MUIProgressDotsRegister ENDP


;-------------------------------------------------------------------------------------
; MUIProgressDotsCreate - Returns handle in eax of newly created control
; Note: dwStyle should be 0 as nothing extra added to control so far.
;-------------------------------------------------------------------------------------
MUIProgressDotsCreate PROC PUBLIC hWndParent:DWORD, ypos:DWORD, controlheight:DWORD, dwResourceID:DWORD, dwStyle:DWORD
    LOCAL hinstance:DWORD
    LOCAL hControl:DWORD
    LOCAL rect:RECT
    LOCAL dwHeight:DWORD
    LOCAL dwWidth:DWORD
    
    Invoke GetModuleHandle, NULL
    mov hinstance, eax

    Invoke MUIProgressDotsRegister
    
    Invoke GetWindowRect, hWndParent, Addr rect
    mov eax, rect.right
    sub eax, rect.left
    dec eax
    dec eax
    mov dwWidth, eax
    
    mov eax, controlheight
    .IF eax == 0
        mov eax, DOTS_DEFAULT_SIZE
    .ENDIF
    mov dwHeight, eax

    Invoke CreateWindowEx, NULL, Addr szMUIProgressDotsClass, NULL, WS_CHILD or WS_VISIBLE or WS_CLIPSIBLINGS, 1, ypos, dwWidth, dwHeight, hWndParent, dwResourceID, hinstance, NULL
    mov hControl, eax
    .IF eax != NULL
        
    .ENDIF
    mov eax, hControl
    ret
MUIProgressDotsCreate ENDP


;-------------------------------------------------------------------------------------
; _MUI_ProgressDotsWndProc - Main processing window for our control
;-------------------------------------------------------------------------------------
_MUI_ProgressDotsWndProc PROC PRIVATE USES EBX hWin:HWND, uMsg:UINT, wParam:WPARAM, lParam:LPARAM

    mov eax,uMsg
    .IF eax == WM_NCCREATE
        mov eax, TRUE
        ret

    .ELSEIF eax == WM_CREATE
        Invoke MUIAllocMemProperties, hWin, 0, SIZEOF _MUI_PROGRESSDOTS_PROPERTIES ; internal properties
        Invoke MUIAllocMemProperties, hWin, 4, SIZEOF MUI_PROGRESSDOTS_PROPERTIES ; external properties
        Invoke _MUI_ProgressDotsInit, hWin

        ret    

    .ELSEIF eax == WM_NCDESTROY
        Invoke MUIFreeMemProperties, hWin, 0
        Invoke MUIFreeMemProperties, hWin, 4
        
    .ELSEIF eax == WM_ERASEBKGND
        mov eax, 1
        ret

    .ELSEIF eax == WM_PAINT
        Invoke _MUI_ProgressDotsPaint, hWin
        mov eax, 0
        ret

    .ELSEIF eax == WM_SIZE
        Invoke _MUI_ProgressDotsResize, hWin
        mov eax, 0
        ret        

    .ELSEIF eax == WM_TIMER
        mov eax, wParam
        .IF eax == hWin
            Invoke _MUI_ProgressDotsCalcPositions, hWin
            Invoke InvalidateRect, hWin, NULL, TRUE
            Invoke UpdateWindow, hWin
        .ENDIF

    ; custom messages start here
    
    .ELSEIF eax == MUIPDM_ANIMATESTART
        Invoke MUIProgressDotsAnimateStart, hWin
        ret

    .ELSEIF eax == MUIPDM_ANIMATESTOP
        Invoke MUIProgressDotsAnimateStop, hWin
        ret

    .ELSEIF eax == MUI_GETPROPERTY
        Invoke MUIGetExtProperty, hWin, wParam
        ret
        
    .ELSEIF eax == MUI_SETPROPERTY  
        Invoke MUISetExtProperty, hWin, wParam, lParam
        ret
        
    .ENDIF
    
    Invoke DefWindowProc, hWin, uMsg, wParam, lParam
    ret

_MUI_ProgressDotsWndProc ENDP


;-------------------------------------------------------------------------------------
; _MUI_ProgressDotsParentSubClassProc - Subclass for progressdots parent window 
; dwRefData is the handle to our progressdots control in this subclass proc
;-------------------------------------------------------------------------------------
_MUI_ProgressDotsParentSubClassProc PROC PRIVATE hWin:HWND, uMsg:UINT, wParam:WPARAM, lParam:LPARAM, uIdSubclass:UINT, dwRefData:DWORD

    mov eax, uMsg
    .IF eax == WM_NCDESTROY
        Invoke RemoveWindowSubclass, hWin, Addr _MUI_ProgressDotsParentSubClassProc, uIdSubclass ; remove subclass before control destroyed.
        Invoke DefSubclassProc, hWin, uMsg, wParam, lParam
        ret

    .ELSEIF eax == WM_SIZE
        Invoke SendMessage, dwRefData, WM_SIZE, 0, 0 ; force resize of progressdots

    .ENDIF
    
    Invoke DefSubclassProc, hWin, uMsg, wParam, lParam 
    ret        
_MUI_ProgressDotsParentSubClassProc ENDP


;-------------------------------------------------------------------------------------
; _MUI_ProgressDotsInit - set initial default values
;-------------------------------------------------------------------------------------
_MUI_ProgressDotsInit PROC PRIVATE USES EBX EDX hControl:DWORD
    LOCAL hParent:DWORD
    LOCAL dwStyle:DWORD
    LOCAL pDotsArray:DWORD
    LOCAL rect:RECT
    LOCAL dwWidth:DWORD
    LOCAL dwMarkerStart:DWORD
    LOCAL dwMarkerFinish:DWORD    
    
    Invoke GetParent, hControl
    mov hParent, eax
    
    ; get style and check it is our default at least
    Invoke GetWindowLong, hControl, GWL_STYLE
    mov dwStyle, eax
    and eax, WS_CHILD or WS_VISIBLE or WS_CLIPCHILDREN
    .IF eax != WS_CHILD or WS_VISIBLE or WS_CLIPCHILDREN
        mov eax, dwStyle
        or eax, WS_CHILD or WS_VISIBLE or WS_CLIPCHILDREN
        mov dwStyle, eax
        Invoke SetWindowLong, hControl, GWL_STYLE, dwStyle
    .ENDIF

    ; Set default initial internal property values
    Invoke MUISetIntProperty, hControl, @ProgressDotsAnimateState, FALSE
    IFDEF DOTS_USE_TIMERQUEUE
        Invoke MUISetIntProperty, hControl, @ProgressDotsUseTimerQueue, TRUE
        Invoke MUISetIntProperty, hControl, @ProgressDotsQueue, 0
        Invoke MUISetIntProperty, hControl, @ProgressDotsTimer, 0
    ENDIF

    ; Set default initial external property values
    Invoke MUIGetParentBackgroundColor, hControl
    .IF eax == -1 ; if background was NULL then try a color as default
        Invoke GetSysColor, COLOR_WINDOW
    .ENDIF
    Invoke MUISetExtProperty, hControl, @ProgressDotsBackColor, eax ;MUI_RGBCOLOR(48,48,48) ;eax    
    Invoke MUISetExtProperty, hControl, @ProgressDotsDotColor, MUI_RGBCOLOR(53,133,211)
    Invoke MUISetExtProperty, hControl, @ProgressDotsShowInterval, DOTS_SHOW_INTERVAL
    Invoke MUISetExtProperty, hControl, @ProgressDotsTimeInterval, DOTS_TIME_INTERVAL
    Invoke MUISetExtProperty, hControl, @ProgressDotsSpeed, DOTS_SPEED    

    ; Calc makers for middle section of control, where dots are slowest
    Invoke GetClientRect, hControl, Addr rect
    mov eax, rect.right
    sub eax, rect.left
    mov dwWidth, eax
    ; magic no by qword to div by 3
    mov ebx,dwWidth
    mov eax,055555556h
    imul ebx
    shr ebx,31
    add edx,ebx
    ; quotient now in edx
    mov dwMarkerStart, edx
    add edx, edx
    mov dwMarkerFinish, edx    
    Invoke MUISetIntProperty, hControl, @ProgressDotsMarkerStart, dwMarkerStart
    Invoke MUISetIntProperty, hControl, @ProgressDotsMarkerFinish, dwMarkerFinish

    ; Calc space for allocating no of dots to show
    mov ebx, MAX_DOTS
    mov eax, SIZEOF DOTINFO
    mul ebx
    Invoke GlobalAlloc, GMEM_FIXED or GMEM_ZEROINIT, eax
    .IF eax == NULL
        mov eax, 1
        ret
    .ENDIF
    mov pDotsArray, eax
    Invoke MUISetIntProperty, hControl, @ProgressDotsDotsArray, pDotsArray
    
    ; subclass parent to react to resize notifications, to reset our controls animation and internal markers etc
    Invoke SetWindowSubclass, hParent, Addr _MUI_ProgressDotsParentSubClassProc, hControl, hControl

    mov eax, 0
    ret

_MUI_ProgressDotsInit ENDP


;-------------------------------------------------------------------------------------
; _MUI_ProgressDotsResize
;-------------------------------------------------------------------------------------
_MUI_ProgressDotsResize PROC PRIVATE hControl:DWORD
    LOCAL hParent:DWORD
    LOCAL rect:RECT
    LOCAL parentrect:RECT
    LOCAL dwWidth:DWORD
    LOCAL dwHeight:DWORD
    LOCAL dwMarkerStart:DWORD
    LOCAL dwMarkerFinish:DWORD
    LOCAL hDefer:DWORD

    Invoke GetClientRect, hControl, Addr rect
    mov eax, rect.bottom
    sub eax, rect.top
    mov dwHeight, eax

    Invoke GetParent, hControl
    mov hParent, eax
    
    Invoke GetWindowRect, hParent, Addr parentrect
    mov eax, parentrect.right
    sub eax, parentrect.left
    dec eax
    dec eax
    mov dwWidth, eax
    
    Invoke BeginDeferWindowPos, 1
    mov hDefer, eax
    .IF hDefer == NULL
        Invoke SetWindowPos, hControl, NULL, 0, 0, dwWidth, dwHeight, SWP_NOZORDER or SWP_NOOWNERZORDER  or SWP_NOACTIVATE or SWP_NOMOVE ;or SWP_NOSENDCHANGING ;or SWP_NOCOPYBITS
    .ELSE
        Invoke DeferWindowPos, hDefer, hControl, NULL, 0, 0, dwWidth, dwHeight, SWP_NOZORDER or SWP_NOOWNERZORDER or SWP_NOACTIVATE or SWP_NOMOVE ;or SWP_NOSENDCHANGING
        mov hDefer, eax
    .ENDIF
    .IF hDefer != NULL
        Invoke EndDeferWindowPos, hDefer
    .ENDIF    

    ;Invoke InvalidateRect, hControl, NULL, TRUE
    Invoke GetClientRect, hControl, Addr rect
    mov eax, rect.right
    sub eax, rect.left
    mov dwWidth, eax
    ; div by 3
    mov ebx,dwWidth
    mov eax,055555556h
    imul ebx
    shr ebx,31
    add edx,ebx
    ; quotient now in edx
    mov dwMarkerStart, edx
    add edx, edx
    mov dwMarkerFinish, edx    
    Invoke MUISetIntProperty, hControl, @ProgressDotsMarkerStart, dwMarkerStart
    Invoke MUISetIntProperty, hControl, @ProgressDotsMarkerFinish, dwMarkerFinish    
    
    ; reset everything otherwise graphically it looks odd
    Invoke _MUI_ProgressDotsInitDots, hControl
    
    ret

_MUI_ProgressDotsResize ENDP


;-------------------------------------------------------------------------------------
; _MUI_ProgressDotsPaint
;-------------------------------------------------------------------------------------
_MUI_ProgressDotsPaint PROC PRIVATE hWin:DWORD
    LOCAL ps:PAINTSTRUCT 
    LOCAL rect:RECT
    LOCAL hdc:HDC
    LOCAL hdcMem:HDC
    LOCAL hbmMem:DWORD
    LOCAL hBitmap:DWORD
    LOCAL hOldBitmap:DWORD
    LOCAL AnimateState:DWORD

    Invoke BeginPaint, hWin, Addr ps
    mov hdc, eax
    
    Invoke IsWindowVisible, hWin
    .IF eax == 0
        Invoke EndPaint, hWin, Addr ps
        ret
    .ENDIF
    
    ;----------------------------------------------------------
    ; Get some property values
    ;---------------------------------------------------------- 
    Invoke MUIGetIntProperty, hWin, @ProgressDotsAnimateState
    mov AnimateState, eax    

    Invoke GetClientRect, hWin, Addr rect    

    ;----------------------------------------------------------
    ; Setup Double Buffering
    ;----------------------------------------------------------
    Invoke CreateCompatibleDC, hdc
    mov hdcMem, eax
    Invoke CreateCompatibleBitmap, hdc, rect.right, rect.bottom
    mov hbmMem, eax
    Invoke SelectObject, hdcMem, hbmMem
    mov hOldBitmap, eax

    ;----------------------------------------------------------
    ; Background
    ;----------------------------------------------------------
    Invoke _MUI_ProgressDotsPaintBackground, hWin, hdcMem, Addr rect

    .IF AnimateState == TRUE

        ;----------------------------------------------------------
        ; Dots
        ;----------------------------------------------------------
        Invoke _MUI_ProgressDotsPaintDots, hWin, hdc, hdcMem, Addr rect
    
    .ENDIF

    ;----------------------------------------------------------
    ; BitBlt from hdcMem back to hdc
    ;----------------------------------------------------------
    Invoke BitBlt, hdc, 0, 0, rect.right, rect.bottom, hdcMem, 0, 0, SRCCOPY

    ;----------------------------------------------------------
    ; Cleanup
    ;----------------------------------------------------------
    Invoke SelectObject, hdcMem, hOldBitmap
    Invoke DeleteDC, hdcMem
    Invoke DeleteObject, hbmMem
    .IF hOldBitmap != 0
        Invoke DeleteObject, hOldBitmap
    .ENDIF      

    Invoke EndPaint, hWin, Addr ps

    ret
_MUI_ProgressDotsPaint ENDP


;-------------------------------------------------------------------------------------
; _MUI_ProgressDotsPaintBackground
;-------------------------------------------------------------------------------------
_MUI_ProgressDotsPaintBackground PROC PRIVATE hWin:DWORD, hdc:DWORD, lpRect:DWORD
    LOCAL BackColor:DWORD
    LOCAL hBrush:DWORD
    LOCAL hOldBrush:DWORD
    
    Invoke MUIGetExtProperty, hWin, @ProgressDotsBackColor
    mov BackColor, eax
    
    Invoke GetStockObject, DC_BRUSH
    mov hBrush, eax
    Invoke SelectObject, hdc, eax
    mov hOldBrush, eax
    Invoke SetDCBrushColor, hdc, BackColor
    Invoke FillRect, hdc, lpRect, hBrush
    
    .IF hOldBrush != 0
        Invoke SelectObject, hdc, hOldBrush
        Invoke DeleteObject, hOldBrush
    .ENDIF     
    .IF hBrush != 0
        Invoke DeleteObject, hBrush
    .ENDIF      
    ret

_MUI_ProgressDotsPaintBackground ENDP


;-------------------------------------------------------------------------------------
; _MUI_ProgressDotsCalcPositions - calculate x, y positions of images, text etc
;-------------------------------------------------------------------------------------
_MUI_ProgressDotsCalcPositions PROC PRIVATE USES EBX hWin:DWORD
    LOCAL rect:RECT
    LOCAL dwWidth:DWORD
    LOCAL dwMarkerStart:DWORD
    LOCAL dwMarkerFinish:DWORD
    LOCAL pDotsArray:DWORD
    LOCAL pCurrentDot:DWORD
    LOCAL xPos:DWORD
    LOCAL bVisible:DWORD
    LOCAL dwSpeed:DWORD
    LOCAL nDot:DWORD
    LOCAL dwShowCountdown:DWORD
    LOCAL dwDefaultShowInterval:DWORD

    Invoke GetClientRect, hWin, Addr rect
    mov eax, rect.right
    sub eax, rect.left
    mov dwWidth, eax

    Invoke MUIGetExtProperty, hWin, @ProgressDotsSpeed
    mov dwSpeed, eax
    Invoke MUIGetExtProperty, hWin, @ProgressDotsShowInterval
    mov dwDefaultShowInterval, eax
    Invoke MUIGetIntProperty, hWin, @ProgressDotsMarkerStart
    mov dwMarkerStart, eax
    Invoke MUIGetIntProperty, hWin, @ProgressDotsMarkerFinish
    mov dwMarkerFinish, eax
    Invoke MUIGetIntProperty, hWin, @ProgressDotsDotsArray
    mov pDotsArray, eax
    mov pCurrentDot, eax

    mov nDot, 0
    mov eax, 0
    .WHILE eax < MAX_DOTS
        mov ebx, pCurrentDot
        mov eax, [ebx].DOTINFO.bVisible
        mov bVisible, eax
        mov eax, [ebx].DOTINFO.xPos
        mov xPos, eax
        mov eax, [ebx].DOTINFO.dwShowCountdown
        mov dwShowCountdown, eax

        .IF bVisible == FALSE
            .IF dwShowCountdown == 0 ; time to show dot and start it moving
                mov ebx, pCurrentDot
                mov [ebx].DOTINFO.bVisible, TRUE
                mov [ebx].DOTINFO.xPos, 0
            .ELSE ; otherwise continue countdown till it shows
                mov eax, dwShowCountdown
                dec eax
                mov ebx, pCurrentDot
                mov [ebx].DOTINFO.dwShowCountdown, eax
            .ENDIF
        
        .ELSE ; VISIBLE
            
            mov eax, xPos
            .IF eax >= dwMarkerStart && eax < dwMarkerFinish ; between markers - slowest

                mov eax, xPos
                inc eax
                mov ebx, pCurrentDot
                mov [ebx].DOTINFO.xPos, eax

            .ELSEIF eax >= 0 && eax < dwMarkerStart ; before first marker
                
                mov eax, dwSpeed
                shl eax, 1 ; times 2 to make it faster
                add eax, xPos
                mov ebx, pCurrentDot
                mov [ebx].DOTINFO.xPos, eax

            .ELSEIF eax >= dwMarkerFinish && eax <= dwWidth ; between last marker and end of control

                mov eax, dwSpeed
                shl eax, 1 ; times 2 to make it faster
                add eax, xPos
                mov ebx, pCurrentDot
                mov [ebx].DOTINFO.xPos, eax

            .ELSEIF eax > dwWidth ; reached end, so reset dot to continue for next cycle of dots

                mov ebx, pCurrentDot
                mov [ebx].DOTINFO.bVisible, FALSE
                mov [ebx].DOTINFO.xPos, 0
                mov eax, dwDefaultShowInterval;DOTS_SHOW_INTERVAL
                shl eax, 2
                mov [ebx].DOTINFO.dwShowCountdown, eax

            .ENDIF

        .ENDIF

        add pCurrentDot, SIZEOF DOTINFO
        inc nDot
        mov eax, nDot
    .ENDW    

    ret
_MUI_ProgressDotsCalcPositions ENDP


;-------------------------------------------------------------------------------------
; _MUI_ProgressDotsPaintDots
;-------------------------------------------------------------------------------------
_MUI_ProgressDotsPaintDots PROC PRIVATE USES EBX hWin:DWORD, hdcMain:DWORD, hdcDest:DWORD, lpRect:DWORD
    LOCAL pDotsArray:DWORD
    LOCAL pCurrentDot:DWORD
    LOCAL xPos:DWORD
    LOCAL bVisible:DWORD
    LOCAL nDot:DWORD
    LOCAL hBrush:DWORD
    LOCAL hOldBrush:DWORD
    LOCAL rect:RECT
    LOCAL dwDotColor:DWORD
    LOCAL dwSize:DWORD
    
    Invoke MUIGetExtProperty, hWin, @ProgressDotsDotColor
    mov dwDotColor, eax
    
    Invoke MUIGetIntProperty, hWin, @ProgressDotsDotsArray
    mov pDotsArray, eax
    mov pCurrentDot, eax
    
    Invoke CopyRect, Addr rect, lpRect

    mov eax, rect.bottom
    sub eax, rect.top
    mov dwSize, eax

    Invoke GetStockObject, DC_BRUSH
    mov hBrush, eax
    Invoke SelectObject, hdcDest, eax
    mov hOldBrush, eax
    Invoke SetDCBrushColor, hdcDest, dwDotColor

    mov nDot, 0
    mov eax, 0
    .WHILE eax < MAX_DOTS
        mov ebx, pCurrentDot
        mov eax, [ebx].DOTINFO.bVisible
        mov bVisible, eax

        ; Paint dot
        .IF bVisible == TRUE

            mov eax, [ebx].DOTINFO.xPos
            mov xPos, eax
            mov rect.left, eax
            mov rect.right, eax
            mov eax, dwSize
            add rect.right, eax
            Invoke FillRect, hdcDest, Addr rect, hBrush
            ;Invoke FrameRect, hdcDest, Addr dotrect, hBrush            

        .ENDIF
        
        add pCurrentDot, SIZEOF DOTINFO
        inc nDot
        mov eax, nDot
    .ENDW

    .IF hOldBrush != 0
        Invoke SelectObject, hdcDest, hOldBrush
        Invoke DeleteObject, hOldBrush
    .ENDIF     
    .IF hBrush != 0
        Invoke DeleteObject, hBrush
    .ENDIF  

    ret
_MUI_ProgressDotsPaintDots ENDP


;-------------------------------------------------------------------------------------
; _MUI_ProgressDotsInitDots
;-------------------------------------------------------------------------------------
_MUI_ProgressDotsInitDots PROC PRIVATE USES EBX hWin:DWORD
    LOCAL pDotsArray:DWORD
    LOCAL pCurrentDot:DWORD
    LOCAL nDot:DWORD
    LOCAL dwShowInterval:DWORD
    LOCAL dwDefaultShowInterval:DWORD
    LOCAL rect:RECT
    LOCAL dwSize:DWORD

    Invoke MUIGetExtProperty, hWin, @ProgressDotsShowInterval
    mov dwDefaultShowInterval, eax

    Invoke MUIGetIntProperty, hWin, @ProgressDotsDotsArray
    mov pDotsArray, eax
    mov pCurrentDot, eax
    
    Invoke GetClientRect, hWin, Addr rect 
    mov eax, rect.bottom
    sub eax, rect.top
    mov dwSize, eax

    mov dwShowInterval, 0

    mov nDot, 0
    mov eax, 0
    .WHILE eax < MAX_DOTS
        mov ebx, pCurrentDot
        
        mov [ebx].DOTINFO.bVisible, FALSE
        mov eax, 0
        sub eax, dwSize
        mov [ebx].DOTINFO.xPos, eax
        mov eax, dwShowInterval
        mov [ebx].DOTINFO.dwShowCountdown, eax

        ;mov [ebx].DOTINFO.dwSpeed, 0
        ;mov [ebx].DOTINFO.dwMoveCountdown, 0

        mov eax, dwShowInterval
        add eax, dwDefaultShowInterval
        mov dwShowInterval, eax
        
        add pCurrentDot, SIZEOF DOTINFO
        inc nDot
        mov eax, nDot
    .ENDW

    ret

_MUI_ProgressDotsInitDots ENDP


;-------------------------------------------------------------------------------------
; MUIProgressDotsAnimateStart
;-------------------------------------------------------------------------------------
MUIProgressDotsAnimateStart PROC PUBLIC hControl:DWORD
    LOCAL dwTimeInterval:DWORD
    IFDEF DOTS_USE_TIMERQUEUE
    LOCAL hQueue:DWORD
    LOCAL hTimer:DWORD
    ENDIF
    
    Invoke ShowWindow, hControl, SW_SHOWNA
    Invoke _MUI_ProgressDotsInitDots, hControl
    Invoke MUISetIntProperty, hControl, @ProgressDotsAnimateState, TRUE
    Invoke MUIGetExtProperty, hControl, @ProgressDotsTimeInterval
    .IF eax == 0
        Invoke MUISetIntProperty, hControl, @ProgressDotsTimeInterval, DOTS_TIME_INTERVAL
        mov eax, DOTS_TIME_INTERVAL
    .ENDIF
    mov dwTimeInterval, eax

    Invoke InvalidateRect, hControl, NULL, TRUE
    
    IFDEF DOTS_USE_TIMERQUEUE
    
        Invoke MUIGetIntProperty, hControl, @ProgressDotsUseTimerQueue
        .IF eax == TRUE
            Invoke MUIGetIntProperty, hControl, @ProgressDotsQueue
            mov hQueue, eax
            Invoke MUIGetIntProperty, hControl, @ProgressDotsTimer
            mov hTimer, eax
            .IF hQueue != NULL ; re-use existing hQueue
                Invoke ChangeTimerQueueTimer, hQueue, hTimer, dwTimeInterval, dwTimeInterval
                .IF eax == 0 ; failed 
                    Invoke DeleteTimerQueueEx, hQueue, FALSE
                    Invoke MUISetIntProperty, hControl, @ProgressDotsQueue, 0
                    Invoke MUISetIntProperty, hControl, @ProgressDotsTimer, 0
                    Invoke MUISetIntProperty, hControl, @ProgressDotsUseTimerQueue, FALSE
                    Invoke SetTimer, hControl, hControl, dwTimeInterval, NULL
                .ENDIF
            .ELSE ; Try to create TimerQueue 
                Invoke CreateTimerQueue
                .IF eax != NULL
                    mov hQueue, eax
                    Invoke CreateTimerQueueTimer, Addr hTimer, hQueue, Addr _MUI_ProgressBarTimerProc, hControl, dwTimeInterval, dwTimeInterval, 0
                    .IF eax == 0 ; failed, so fall back to WM_TIMER usage
                        Invoke DeleteTimerQueueEx, hQueue, FALSE
                        Invoke MUISetIntProperty, hControl, @ProgressDotsQueue, 0
                        Invoke MUISetIntProperty, hControl, @ProgressDotsTimer, 0
                        Invoke MUISetIntProperty, hControl, @ProgressDotsUseTimerQueue, FALSE
                        Invoke SetTimer, hControl, hControl, dwTimeInterval, NULL
                    .ELSE ; Success! - so save TimerQueue handles for re-use
                        IFDEF DEBUG32
                        PrintText 'Using QueueTimer'
                        ENDIF
                        Invoke MUISetIntProperty, hControl, @ProgressDotsQueue, hQueue
                        Invoke MUISetIntProperty, hControl, @ProgressDotsTimer, hTimer
                    .ENDIF
                .ELSE ; failed, so fall back to WM_TIMER usage
                    Invoke MUISetIntProperty, hControl, @ProgressDotsUseTimerQueue, FALSE
                    Invoke SetTimer, hControl, hControl, dwTimeInterval, NULL
                .ENDIF
            .ENDIF
        .ELSE  ; Not using TimerQueue, previous failure?, so fall back to WM_TIMER usage
            Invoke SetTimer, hControl, hControl, dwTimeInterval, NULL
        .ENDIF
    
    ELSE ; compiled define says to use WM_TIMER instead
    
        Invoke SetTimer, hControl, hControl, dwTimeInterval, NULL
        
    ENDIF
    ret
MUIProgressDotsAnimateStart ENDP


;-------------------------------------------------------------------------------------
; MUIProgressDotsAnimateStop
;-------------------------------------------------------------------------------------
MUIProgressDotsAnimateStop PROC PUBLIC hControl:DWORD
    IFDEF DOTS_USE_TIMERQUEUE
    LOCAL hQueue:DWORD
    LOCAL hTimer:DWORD
    ENDIF
    
    Invoke ShowWindow, hControl, SW_HIDE
    IFDEF DOTS_USE_TIMERQUEUE
    
        Invoke MUIGetIntProperty, hControl, @ProgressDotsUseTimerQueue
        .IF eax == TRUE
            Invoke MUIGetIntProperty, hControl, @ProgressDotsQueue
            mov hQueue, eax
            Invoke MUIGetIntProperty, hControl, @ProgressDotsTimer
            mov hTimer, eax
            .IF hQueue != NULL
                Invoke ChangeTimerQueueTimer, hQueue, hTimer, INFINITE, 0
                .IF eax == 0 ; failed, fall back to use KillTimer for WM_TIMER usage
                    Invoke DeleteTimerQueueEx, hQueue, FALSE
                    Invoke MUISetIntProperty, hControl, @ProgressDotsQueue, 0
                    Invoke MUISetIntProperty, hControl, @ProgressDotsTimer, 0
                    Invoke MUISetIntProperty, hControl, @ProgressDotsUseTimerQueue, FALSE
                    Invoke KillTimer, hControl, hControl
                .ENDIF
            .ELSE ; fall back to use KillTimer for WM_TIMER usage
                Invoke MUISetIntProperty, hControl, @ProgressDotsUseTimerQueue, FALSE
                Invoke KillTimer, hControl, hControl
            .ENDIF
        .ELSE ; Not using TimerQueue, previous failure? back to use KillTimer for WM_TIMER usage
            Invoke KillTimer, hControl, hControl
        .ENDIF
        
    ELSE ; compiled define says to use WM_TIMER instead
    
        Invoke KillTimer, hControl, hControl
        
    ENDIF
    
    Invoke MUISetIntProperty, hControl, @ProgressDotsAnimateState, FALSE
    Invoke InvalidateRect, hControl, NULL, TRUE
    ret
MUIProgressDotsAnimateStop ENDP


;-------------------------------------------------------------------------------------
; _MUI_ProgressBarTimerProc for TimerQueue
;-------------------------------------------------------------------------------------
IFDEF DOTS_USE_TIMERQUEUE
_MUI_ProgressBarTimerProc PROC USES EBX lpParam:DWORD, TimerOrWaitFired:DWORD
    ; lpParam is hControl
    Invoke _MUI_ProgressDotsCalcPositions, lpParam
    Invoke InvalidateRect, lpParam, NULL, TRUE
    Invoke UpdateWindow, lpParam
    ret
_MUI_ProgressBarTimerProc ENDP
ENDIF


END
