;=========================================================
; ATmega328P
; TWO TRAFFIC LIGHT MODULES
; PUSH BUTTON
; 5 LEDs
; LDR LIGHT / DARK CONTROL
;
; CLOCK = 16 MHz
;
; PIN CHANGES IN THIS VERSION:
;   Button     : PD0 (D0)  -> PD7 (D7)
;   M1 RED LED : PD1 (D1)  -> PB5 (D13)
;=========================================================


;=========================================================
; PORT B
;=========================================================

; PB0 = LED 1
; PB1 = LED 2
; PB2 = LED 3
; PB3 = LED 4
; PB4 = LED 5
; PB5 = MODULE 1 RED   (D13)   <-- moved here (shares PORTB with the 5 LEDs)


;=========================================================
; PORT D
;=========================================================

; PD7 = PUSH BUTTON (D7)       <-- moved here

; MODULE 1:
; PB5 = RED   (see PORT B)
; PD2 = YELLOW
; PD3 = GREEN

; MODULE 2:
; PD4 = RED
; PD5 = YELLOW
; PD6 = GREEN

; PD0 / PD1 = unused (UART RX/TX, left as inputs)


;=========================================================
; ADC
;=========================================================

; PC0 / ADC0 / A0 = LDR

; LDR CONNECTION:
;
;       +5V
;        |
;       LDR
;        |
;        +-------- A0 / PC0
;        |
;       4.7K
;        |
;       GND

; BRIGHT = HIGH ADC VALUE
; DARK   = LOW ADC VALUE


;=========================================================
; NORMAL TRAFFIC:
;=========================================================

; M1 GREEN  / M2 RED      10 sec
; M1 YELLOW / M2 RED      3 sec   (M1 stops)
; M1 RED    / M2 YELLOW   3 sec   (M2 gets ready)
; M1 RED    / M2 GREEN    10 sec
; M1 RED    / M2 YELLOW   3 sec   (M2 stops)
; M1 YELLOW / M2 RED      3 sec   (M1 gets ready)
; repeat


;=========================================================
; DARK MODE:
;=========================================================

; M1 YELLOW / M2 YELLOW
; Yellow LEDs blink.
;
; The push button is IGNORED during dark mode.
; Any press made in the dark is discarded when light returns.


;=========================================================
; INCLUDE
;=========================================================

.include "m328pdef.inc"


;=========================================================
; LIGHT THRESHOLD
;=========================================================

; Arduino Serial Monitor gives 10-bit ADC value:
;
; 0   - 499  = DARK
; 500 - 1023 = LIGHT
;
; Since ADLAR = 1, we read ADCH (upper 8 bits).
;
; 500 / 4 = 125
;
; Therefore:
;
; 0   - 124 = DARK
; 125 - 255 = LIGHT
;
;=========================================================

.equ LIGHT_THRESHOLD = 125


;=========================================================
; MACROS FOR MODULE 1 RED (now on PB5)
;
; PB5 lives on PORTB together with the 5 sequence LEDs,
; so it must NEVER be changed with a whole-port write.
; These macros touch only the PB5 bit.
;=========================================================

.macro M1_RED_ON
    sbi PORTB, PB5
.endmacro

.macro M1_RED_OFF
    cbi PORTB, PB5
.endmacro


;=========================================================
; RESET VECTOR
;=========================================================

.org 0x0000

    rjmp RESET


;---------------------------------------------------------
; Pin-change interrupt vector (PCINT16-23 = PORT D)
;---------------------------------------------------------

.org PCI2addr

    rjmp PCINT2_ISR


; Main program starts after the vector table

.org INT_VECTORS_SIZE


;=========================================================
; REGISTER USE
;=========================================================

; r16 = general purpose
; r17 = traffic timer
; r18 = LED timer/counter
; r19 = button request flag (latched by the PD7 interrupt)
; r20 = delay counter
; r21 = delay counter
; r22 = delay counter
; r23 = button source
; r24 = ADC value
; r25 = light status
; r26 = scratch for LED_WRITE (new)

; r19:
;   0 = no button request
;   1 = button request

; r23:
;   1 = M1 was GREEN
;   2 = M2 was GREEN

; r25:
;   0 = DARK
;   1 = LIGHT


;=========================================================
; RESET
;=========================================================

RESET:

    ;-----------------------------------------------------
    ; Initialize Stack
    ;-----------------------------------------------------

    ldi r16, high(RAMEND)
    out SPH, r16

    ldi r16, low(RAMEND)
    out SPL, r16


    ;=====================================================
    ; PORT B
    ;=====================================================

    ; PB0-PB4 = 5 LEDs (OUTPUT)
    ; PB5     = M1 RED (OUTPUT)

    ldi r16, 0b00111111
    out DDRB, r16

    ; All outputs OFF

    ldi r16, 0
    out PORTB, r16


    ;=====================================================
    ; PORT D
    ;=====================================================

    ; PD0, PD1 = unused (input)
    ; PD2-PD6  = OUTPUT (M1 yellow/green, M2 R/Y/G)
    ; PD7      = INPUT  (push button)

    ldi r16, 0b01111100
    out DDRD, r16

    ; Outputs OFF, PD7 pull-up ON (set below)

    ldi r16, 0
    out PORTD, r16


    ;-----------------------------------------------------
    ; Enable internal pull-up on push button (PD7)
    ;
    ; Wiring: button between D7 and GND
    ;-----------------------------------------------------

    sbi PORTD, PD7


    ;-----------------------------------------------------
    ; Pin-change interrupt on PD7 (PCINT23)
    ;
    ; A button press is LATCHED by the interrupt, so it is
    ; never missed while the program sits in a delay, and
    ; the program never has to wait for the release.
    ;-----------------------------------------------------

    ldi r16, (1<<PCINT23)
    sts PCMSK2, r16

    ldi r16, (1<<PCIE2)
    sts PCICR, r16

    ; Clear any pending flag

    ldi r16, (1<<PCIF2)
    out PCIFR, r16


    ;=====================================================
    ; ADC0 / PC0
    ;=====================================================

    ; PC0 = INPUT

    cbi DDRC, PC0


    ;=====================================================
    ; ADC INITIALIZATION
    ;=====================================================

    ;-----------------------------------------------------
    ; ADMUX
    ;
    ; REFS0 = 1
    ; AVCC reference
    ;
    ; ADLAR = 1
    ; Left adjusted
    ;
    ; MUX = 0000
    ; ADC0 selected
    ;-----------------------------------------------------

    ldi r16, (1<<REFS0) | (1<<ADLAR)
    sts ADMUX, r16


    ;-----------------------------------------------------
    ; ADCSRA
    ;
    ; ADEN = 1
    ; ADC enabled
    ;
    ; ADPS2:0 = 111
    ; ADC clock = 16MHz / 128
    ;            = 125kHz
    ;-----------------------------------------------------

    ldi r16, (1<<ADEN) | (1<<ADPS2) | (1<<ADPS1) | (1<<ADPS0)
    sts ADCSRA, r16


    ;=====================================================
    ; VARIABLES
    ;=====================================================

    ldi r19, 0
    ldi r23, 0
    ldi r25, 1

    ; Enable interrupts

    sei


    ;=====================================================
    ; INITIAL LIGHT CHECK
    ;=====================================================

    rcall CHECK_LIGHT


    ;=====================================================
    ; START
    ;=====================================================

    rjmp CHECK_LIGHT_MODE


;=========================================================
;=========================================================
; MAIN LIGHT MODE CHECK
;=========================================================

; r25 = 0 -> DARK
; r25 = 1 -> LIGHT


CHECK_LIGHT_MODE:

    rcall CHECK_LIGHT

    tst r25

    ; If LIGHT, branch only a few instructions forward.
    brne LIGHT_START

    ; Long jump is done with RJMP.

    rjmp DARK_MODE


LIGHT_START:

    rjmp M1_GREEN_M2_RED


;=========================================================
;=========================================================
; DARK MODE
;
; BOTH MODULES YELLOW BLINK
;=========================================================
;=========================================================

DARK_MODE:

    ;-----------------------------------------------------
    ; M1 YELLOW
    ;-----------------------------------------------------

    M1_RED_OFF
    sbi PORTD, PD2
    cbi PORTD, PD3


    ;-----------------------------------------------------
    ; M2 YELLOW
    ;-----------------------------------------------------

    cbi PORTD, PD4
    sbi PORTD, PD5
    cbi PORTD, PD6


    ;-----------------------------------------------------
    ; 5 LEDs OFF (M1 RED on PB5 is preserved)
    ;-----------------------------------------------------

    rcall LEDS_OFF


    ;-----------------------------------------------------
    ; YELLOW ON = 500 ms
    ;-----------------------------------------------------

    ldi r17, 5


DARK_YELLOW_ON_LOOP:

    ; Push button is IGNORED in dark mode.

    rcall DELAY_100MS

    dec r17
    brne DARK_YELLOW_ON_LOOP


    ;-----------------------------------------------------
    ; Check light
    ;-----------------------------------------------------

    rcall CHECK_LIGHT

    tst r25

    ; If LIGHT, continue at LIGHT_RETURNED.
    brne DARK_LIGHT_RETURNED_1

    ; Still dark.


    ;-----------------------------------------------------
    ; Turn yellow OFF
    ;-----------------------------------------------------

    cbi PORTD, PD2
    cbi PORTD, PD5


    ;-----------------------------------------------------
    ; YELLOW OFF = 500 ms
    ;-----------------------------------------------------

    ldi r17, 5


DARK_YELLOW_OFF_LOOP:

    ; Push button is IGNORED in dark mode.

    rcall DELAY_100MS

    dec r17
    brne DARK_YELLOW_OFF_LOOP


    ;-----------------------------------------------------
    ; Check light again
    ;-----------------------------------------------------

    rcall CHECK_LIGHT

    tst r25

    brne DARK_LIGHT_RETURNED_2

    ; Still dark.

    rjmp DARK_MODE


;---------------------------------------------------------
; Light returned while yellow was ON
;---------------------------------------------------------

DARK_LIGHT_RETURNED_1:

    ldi r19, 0
    ldi r23, 0

    rjmp M1_GREEN_M2_RED


;---------------------------------------------------------
; Light returned while yellow was OFF
;---------------------------------------------------------

DARK_LIGHT_RETURNED_2:

    ldi r19, 0
    ldi r23, 0

    rjmp M1_GREEN_M2_RED


;=========================================================
;=========================================================
; NORMAL TRAFFIC
;
; M1 GREEN
; M2 RED
;=========================================================
;=========================================================

M1_GREEN_M2_RED:

    ;-----------------------------------------------------
    ; Check light
    ;-----------------------------------------------------

    rcall CHECK_LIGHT

    tst r25
    brne M1_GREEN_LIGHT_OK

    rjmp DARK_MODE


M1_GREEN_LIGHT_OK:

    ;-----------------------------------------------------
    ; 5 LEDs OFF
    ;-----------------------------------------------------

    rcall LEDS_OFF


    ;-----------------------------------------------------
    ; M1 GREEN
    ;-----------------------------------------------------

    M1_RED_OFF
    cbi PORTD, PD2
    sbi PORTD, PD3


    ;-----------------------------------------------------
    ; M2 RED
    ;-----------------------------------------------------

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6


    ;-----------------------------------------------------
    ; M1 GREEN = 10 seconds
    ;-----------------------------------------------------

    ldi r17, 100


M1_GREEN_LOOP:

    rcall CHECK_LIGHT

    tst r25
    brne M1_GREEN_STILL_LIGHT

    rjmp DARK_MODE


M1_GREEN_STILL_LIGHT:

    tst r19
    breq M1_GREEN_NO_BUTTON

    ldi r23, 1


M1_GREEN_NO_BUTTON:

    rcall DELAY_100MS

    dec r17
    brne M1_GREEN_LOOP


    ;-----------------------------------------------------
    ; Green finished
    ;-----------------------------------------------------

    tst r19
    breq M1_GREEN_NO_REQUEST

    rjmp M1_GREEN_BUTTON


M1_GREEN_NO_REQUEST:

    rjmp STOP_M1


;=========================================================
; BUTTON DURING M1 GREEN
;=========================================================

M1_GREEN_BUTTON:

    rjmp M1_YELLOW_M2_RED_REQUEST


;=========================================================
;=========================================================
; M1 STOPPING SEQUENCE (after M1 green)
; 
; M1 YELLOW / M2 RED  -> M1 RED / M2 YELLOW -> M2 green
;=========================================================
;=========================================================

STOP_M1:

    rcall CHECK_LIGHT

    tst r25
    brne STOP_M1_LIGHT

    rjmp DARK_MODE


STOP_M1_LIGHT:

    ; M1 YELLOW

    M1_RED_OFF
    sbi PORTD, PD2
    cbi PORTD, PD3


    ; M2 RED

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6


    ;-----------------------------------------------------
    ; 3 seconds
    ;-----------------------------------------------------

    ldi r17, 30


STOP_M1_LOOP:

    rcall CHECK_LIGHT

    tst r25
    brne STOP_M1_CONT

    rjmp DARK_MODE


STOP_M1_CONT:

    rcall DELAY_100MS

    dec r17
    brne STOP_M1_LOOP


    rjmp PREP_M2


PREP_M2:

    rcall CHECK_LIGHT

    tst r25
    brne PREP_M2_LIGHT

    rjmp DARK_MODE


PREP_M2_LIGHT:

    ; M1 RED

    M1_RED_ON
    cbi PORTD, PD2
    cbi PORTD, PD3


    ; M2 YELLOW

    cbi PORTD, PD4
    sbi PORTD, PD5
    cbi PORTD, PD6


    ;-----------------------------------------------------
    ; 3 seconds
    ;-----------------------------------------------------

    ldi r17, 30


PREP_M2_LOOP:

    rcall CHECK_LIGHT

    tst r25
    brne PREP_M2_CONT

    rjmp DARK_MODE


PREP_M2_CONT:

    rcall DELAY_100MS

    dec r17
    brne PREP_M2_LOOP


    rjmp M1_RED_M2_GREEN


;=========================================================
; BUTTON REQUEST:
;
; M1 YELLOW
; M2 RED
;=========================================================

M1_YELLOW_M2_RED_REQUEST:

    rcall CHECK_LIGHT

    tst r25
    brne M1_YELLOW_REQUEST_LIGHT

    rjmp DARK_MODE


M1_YELLOW_REQUEST_LIGHT:

    ; 5 LEDs OFF

    rcall LEDS_OFF


    ; M1 YELLOW

    M1_RED_OFF
    sbi PORTD, PD2
    cbi PORTD, PD3


    ; M2 RED

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6


    ;-----------------------------------------------------
    ; 3 seconds
    ;-----------------------------------------------------

    ldi r17, 30


M1_YELLOW_REQUEST_LOOP:

    rcall CHECK_LIGHT

    tst r25
    brne M1_YELLOW_REQUEST_CONTINUE

    rjmp DARK_MODE


M1_YELLOW_REQUEST_CONTINUE:

    rcall DELAY_100MS

    dec r17
    brne M1_YELLOW_REQUEST_LOOP


    rjmp BOTH_RED


;=========================================================
;=========================================================
; M1 RED / M2 GREEN
;=========================================================
;=========================================================

M1_RED_M2_GREEN:

    rcall CHECK_LIGHT

    tst r25
    brne M2_GREEN_LIGHT_OK

    rjmp DARK_MODE


M2_GREEN_LIGHT_OK:

    ; 5 LEDs OFF

    rcall LEDS_OFF


    ; M1 RED

    M1_RED_ON
    cbi PORTD, PD2
    cbi PORTD, PD3


    ; M2 GREEN

    cbi PORTD, PD4
    cbi PORTD, PD5
    sbi PORTD, PD6


    ;-----------------------------------------------------
    ; M2 GREEN = 10 seconds
    ;-----------------------------------------------------

    ldi r17, 100


M2_GREEN_LOOP:

    rcall CHECK_LIGHT

    tst r25
    brne M2_GREEN_STILL_LIGHT

    rjmp DARK_MODE


M2_GREEN_STILL_LIGHT:

    tst r19
    breq M2_GREEN_NO_BUTTON

    ldi r23, 2


M2_GREEN_NO_BUTTON:

    rcall DELAY_100MS

    dec r17
    brne M2_GREEN_LOOP


    tst r19
    breq M2_GREEN_NO_REQUEST

    rjmp M2_GREEN_BUTTON


M2_GREEN_NO_REQUEST:

    rjmp STOP_M2


;=========================================================
; BUTTON DURING M2 GREEN
;=========================================================

M2_GREEN_BUTTON:

    rjmp M1_RED_M2_YELLOW_REQUEST


;=========================================================
;=========================================================
; M2 STOPPING SEQUENCE (after M2 green)
; 
; M2 YELLOW / M1 RED  -> M2 RED / M1 YELLOW -> M1 green
;=========================================================
;=========================================================

STOP_M2:

    rcall CHECK_LIGHT

    tst r25
    brne STOP_M2_LIGHT

    rjmp DARK_MODE


STOP_M2_LIGHT:

    ; M1 RED

    M1_RED_ON
    cbi PORTD, PD2
    cbi PORTD, PD3


    ; M2 YELLOW

    cbi PORTD, PD4
    sbi PORTD, PD5
    cbi PORTD, PD6


    ;-----------------------------------------------------
    ; 3 seconds
    ;-----------------------------------------------------

    ldi r17, 30


STOP_M2_LOOP:

    rcall CHECK_LIGHT

    tst r25
    brne STOP_M2_CONT

    rjmp DARK_MODE


STOP_M2_CONT:

    rcall DELAY_100MS

    dec r17
    brne STOP_M2_LOOP


    rjmp PREP_M1


PREP_M1:

    rcall CHECK_LIGHT

    tst r25
    brne PREP_M1_LIGHT

    rjmp DARK_MODE


PREP_M1_LIGHT:

    ; M1 YELLOW

    M1_RED_OFF
    sbi PORTD, PD2
    cbi PORTD, PD3


    ; M2 RED

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6


    ;-----------------------------------------------------
    ; 3 seconds
    ;-----------------------------------------------------

    ldi r17, 30


PREP_M1_LOOP:

    rcall CHECK_LIGHT

    tst r25
    brne PREP_M1_CONT

    rjmp DARK_MODE


PREP_M1_CONT:

    rcall DELAY_100MS

    dec r17
    brne PREP_M1_LOOP


    rjmp M1_GREEN_M2_RED


;=========================================================
; BUTTON REQUEST:
;
; M1 RED
; M2 YELLOW
;=========================================================

M1_RED_M2_YELLOW_REQUEST:

    rcall CHECK_LIGHT

    tst r25
    brne M2_YELLOW_REQUEST_LIGHT

    rjmp DARK_MODE


M2_YELLOW_REQUEST_LIGHT:

    ; 5 LEDs OFF

    rcall LEDS_OFF


    ; M1 RED

    M1_RED_ON
    cbi PORTD, PD2
    cbi PORTD, PD3


    ; M2 YELLOW

    cbi PORTD, PD4
    sbi PORTD, PD5
    cbi PORTD, PD6


    ;-----------------------------------------------------
    ; 3 seconds
    ;-----------------------------------------------------

    ldi r17, 30


M2_YELLOW_REQUEST_LOOP:

    rcall CHECK_LIGHT

    tst r25
    brne M2_YELLOW_REQUEST_CONTINUE

    rjmp DARK_MODE


M2_YELLOW_REQUEST_CONTINUE:

    rcall DELAY_100MS

    dec r17
    brne M2_YELLOW_REQUEST_LOOP


    rjmp BOTH_RED


;=========================================================
;=========================================================
; BOTH RED
;
; NORMAL BUTTON OPERATION
;=========================================================
;=========================================================

BOTH_RED:

    ; M1 RED

    M1_RED_ON
    cbi PORTD, PD2
    cbi PORTD, PD3


    ; M2 RED

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6


    ; 5 LEDs OFF (M1 RED on PB5 stays ON)

    rcall LEDS_OFF


    ;-----------------------------------------------------
    ; 5-second LED sequence
    ;-----------------------------------------------------

    rcall LED_SEQUENCE


    ; 5 LEDs OFF

    rcall LEDS_OFF


    ;-----------------------------------------------------
    ; Determine button source
    ;-----------------------------------------------------

    cpi r23, 1

    ; Keep conditional branch local.

    brne CHECK_BUTTON_SOURCE_M2

    rjmp BUTTON_FROM_M1


CHECK_BUTTON_SOURCE_M2:

    cpi r23, 2
    brne BUTTON_SOURCE_ERROR

    rjmp BUTTON_FROM_M2


BUTTON_SOURCE_ERROR:

    ldi r19, 0
    ldi r23, 0

    rjmp M1_GREEN_M2_RED


;=========================================================
;=========================================================
; BUTTON FROM M1 GREEN
;=========================================================
;=========================================================

BUTTON_FROM_M1:

    ldi r19, 0
    ldi r23, 0


    ; 5 LEDs OFF

    rcall LEDS_OFF


    ; M1 RED

    M1_RED_ON
    cbi PORTD, PD2
    cbi PORTD, PD3


    ; M2 YELLOW

    cbi PORTD, PD4
    sbi PORTD, PD5
    cbi PORTD, PD6


    ;-----------------------------------------------------
    ; M2 YELLOW = 3 sec
    ;-----------------------------------------------------

    ldi r17, 30


BUTTON_FROM_M1_YELLOW_LOOP:

    rcall CHECK_LIGHT

    tst r25
    brne BUTTON_M1_YELLOW_CONTINUE

    rjmp DARK_MODE


BUTTON_M1_YELLOW_CONTINUE:

    rcall DELAY_100MS

    dec r17
    brne BUTTON_FROM_M1_YELLOW_LOOP


    rjmp BUTTON_M2_GREEN


;=========================================================
; M1 RED / M2 GREEN
;=========================================================

BUTTON_M2_GREEN:

    rcall CHECK_LIGHT

    tst r25
    brne BUTTON_M2_GREEN_LIGHT

    rjmp DARK_MODE


BUTTON_M2_GREEN_LIGHT:

    ; 5 LEDs OFF

    rcall LEDS_OFF


    ; M1 RED

    M1_RED_ON
    cbi PORTD, PD2
    cbi PORTD, PD3


    ; M2 GREEN

    cbi PORTD, PD4
    cbi PORTD, PD5
    sbi PORTD, PD6


    ;-----------------------------------------------------
    ; M2 GREEN = 10 sec
    ;-----------------------------------------------------

    ldi r17, 100


BUTTON_M2_GREEN_LOOP:

    rcall CHECK_LIGHT

    tst r25
    brne BUTTON_M2_GREEN_CONTINUE

    rjmp DARK_MODE


BUTTON_M2_GREEN_CONTINUE:

    rcall DELAY_100MS

    dec r17
    brne BUTTON_M2_GREEN_LOOP


    rjmp STOP_M2


;=========================================================
;=========================================================
; BUTTON FROM M2 GREEN
;=========================================================
;=========================================================

BUTTON_FROM_M2:

    ldi r19, 0
    ldi r23, 0


    ; 5 LEDs OFF

    rcall LEDS_OFF


    ; M1 YELLOW

    M1_RED_OFF
    sbi PORTD, PD2
    cbi PORTD, PD3


    ; M2 RED

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6


    ;-----------------------------------------------------
    ; M1 YELLOW = 3 sec
    ;-----------------------------------------------------

    ldi r17, 30


BUTTON_FROM_M2_YELLOW_LOOP:

    rcall CHECK_LIGHT

    tst r25
    brne BUTTON_M2_YELLOW_CONTINUE

    rjmp DARK_MODE


BUTTON_M2_YELLOW_CONTINUE:

    rcall DELAY_100MS

    dec r17
    brne BUTTON_FROM_M2_YELLOW_LOOP


    rjmp BUTTON_M1_GREEN


;=========================================================
; M1 GREEN / M2 RED
;=========================================================

BUTTON_M1_GREEN:

    rcall CHECK_LIGHT

    tst r25
    brne BUTTON_M1_GREEN_LIGHT

    rjmp DARK_MODE


BUTTON_M1_GREEN_LIGHT:

    ; 5 LEDs OFF

    rcall LEDS_OFF


    ; M1 GREEN

    M1_RED_OFF
    cbi PORTD, PD2
    sbi PORTD, PD3


    ; M2 RED

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6


    ;-----------------------------------------------------
    ; M1 GREEN = 10 sec
    ;-----------------------------------------------------

    ldi r17, 100


BUTTON_M1_GREEN_LOOP:

    rcall CHECK_LIGHT

    tst r25
    brne BUTTON_M1_GREEN_CONTINUE

    rjmp DARK_MODE


BUTTON_M1_GREEN_CONTINUE:

    rcall DELAY_100MS

    dec r17
    brne BUTTON_M1_GREEN_LOOP


    rjmp STOP_M1


;=========================================================
;=========================================================
; BUTTON INTERRUPT  (PD7 pin change)
;
; Runs on every change of PD7.
;   pin LOW  (pressed)  -> latch r19 = 1
;   pin HIGH (released) -> ignored
;
; r19 stays 1 until the main program clears it.
; Contact bounce only re-latches the same flag.
;
; Only SBIC / RJMP / LDI are used. None of them change
; SREG, so nothing has to be saved.
;=========================================================
;=========================================================

PCINT2_ISR:

    sbic PIND, PD7        ; skip next line if pin is LOW (pressed)
    rjmp PCINT2_EXIT      ; pin HIGH -> ignore

    ldi r19, 1            ; latch button request


PCINT2_EXIT:

    reti


;=========================================================
;=========================================================
; CHECK LIGHT
;
; ADC0 / A0
;
; r25:
;
; 0 = DARK
; 1 = LIGHT
;
;=========================================================
;=========================================================

CHECK_LIGHT:

    ;-----------------------------------------------------
    ; Start ADC conversion
    ;-----------------------------------------------------

    lds r16, ADCSRA

    ori r16, (1<<ADSC)

    sts ADCSRA, r16


    ;-----------------------------------------------------
    ; Wait for ADC
    ;-----------------------------------------------------

ADC_WAIT:

    lds r16, ADCSRA

    sbrc r16, ADSC
    rjmp ADC_WAIT


    ;-----------------------------------------------------
    ; Read upper 8 bits
    ;-----------------------------------------------------

    lds r24, ADCH


    ;-----------------------------------------------------
    ; Compare ADC value with threshold
    ;
    ; LIGHT_THRESHOLD = 125
    ;
    ; ADCH < 125  -> DARK
    ; ADCH >= 125 -> LIGHT
    ;-----------------------------------------------------

    cpi r24, LIGHT_THRESHOLD

    ; BRLO only jumps to nearby ADC_DARK label.

    brlo ADC_DARK


    ;-----------------------------------------------------
    ; LIGHT
    ;-----------------------------------------------------

    ldi r25, 1

    ret


;=========================================================
; DARK
;=========================================================

ADC_DARK:

    ldi r25, 0

    ret


;=========================================================
;=========================================================
; LED_WRITE / LEDS_OFF   (NEW)
;
; The 5 sequence LEDs (PB0-PB4) share PORTB with
; M1 RED (PB5). A plain "out PORTB, x" would switch
; PB5 off, so these routines only change PB0-PB4.
;
; LED_WRITE : r16 bits 0-4 = new LED pattern
;             PB5-PB7 are left untouched
; LEDS_OFF  : turns PB0-PB4 off, PB5 untouched
;
; Uses r16 and r26.
;=========================================================
;=========================================================

LED_WRITE:

    andi r16, 0b00011111      ; keep only the LED bits
    in   r26, PORTB
    andi r26, 0b11100000      ; keep PB5-PB7 as they are
    or   r26, r16             ; merge new LED pattern
    out  PORTB, r26

    ret


LEDS_OFF:

    ldi r16, 0
    rjmp LED_WRITE            ; LED_WRITE returns to our caller


;=========================================================
;=========================================================
; LED SEQUENCE
;
; 1 sec = 5 LEDs
; 1 sec = 4 LEDs
; 1 sec = 3 LEDs
; 1 sec = 2 LEDs
; 1 sec = 1 LED
;
; Total = 5 seconds
;
; M1 RED (PB5) is not affected.
;
;=========================================================
;=========================================================

LED_SEQUENCE:

    ; Stage 1: LEDs 1-5 ON
    ldi r16, 0b00011111
    rcall LED_WRITE
    rcall DELAY_1SEC

    ; Stage 2: LEDs 1-4 ON
    ldi r16, 0b00001111
    rcall LED_WRITE
    rcall DELAY_1SEC

    ; Stage 3: LEDs 1-3 ON
    ldi r16, 0b00000111
    rcall LED_WRITE
    rcall DELAY_1SEC

    ; Stage 4: LEDs 1-2 ON
    ldi r16, 0b00000011
    rcall LED_WRITE
    rcall DELAY_1SEC

    ; Stage 5: LED 1 ON
    ldi r16, 0b00000001
    rcall LED_WRITE
    rcall DELAY_1SEC

    ; All 5 LEDs OFF
    rcall LEDS_OFF
    ret


;=========================================================
;=========================================================
; 1 SECOND DELAY
;
; 10 x 100ms
;
;=========================================================

DELAY_1SEC:

    ldi r18, 10


DELAY_1SEC_LOOP:

    rcall DELAY_100MS

    dec r18
    brne DELAY_1SEC_LOOP

    ret


;=========================================================
;=========================================================
; 100 ms DELAY
;
; CLOCK = 16 MHz
;
;=========================================================

DELAY_100MS:

    ; Cycle count (16 MHz, 1 cycle = 62.5 ns):
    ;   inner  loop (132) = 131*3 + 2   =     395 cycles
    ;   middle loop (250) = 249*399 + 398 = 99,749 cycles
    ;   outer  loop (16)  = ~1,596,047 cycles
    ;   total             = ~99.75 ms

    ldi r20, 16


DELAY100_OUTER:

    ldi r21, 250


DELAY100_MIDDLE:

    ldi r22, 132


DELAY100_INNER:

    dec r22
    brne DELAY100_INNER

    dec r21
    brne DELAY100_MIDDLE

    dec r20
    brne DELAY100_OUTER

    ret


;=========================================================
; END OF PROGRAM
;=========================================================