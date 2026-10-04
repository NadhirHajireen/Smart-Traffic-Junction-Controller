;=========================================================
; ATmega328P
; TWO TRAFFIC LIGHT MODULES
; PUSH BUTTON
; 5 LEDs
; LDR LIGHT / DARK CONTROL
;
; CLOCK = 16 MHz
;=========================================================


;=========================================================
; PORT B
;=========================================================

; PB0 = LED 1
; PB1 = LED 2
; PB2 = LED 3
; PB3 = LED 4
; PB4 = LED 5


;=========================================================
; PORT D
;=========================================================

; PD0 = PUSH BUTTON

; MODULE 1:
; PD1 = RED
; PD2 = YELLOW
; PD3 = GREEN

; MODULE 2:
; PD4 = RED
; PD5 = YELLOW
; PD6 = GREEN


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

; M1 GREEN / M2 RED       10 sec
; M1 YELLOW / M2 YELLOW   3 sec
; M1 RED / M2 GREEN       10 sec
; M1 YELLOW / M2 YELLOW   3 sec
; repeat


;=========================================================
; DARK MODE:
;=========================================================

; M1 YELLOW / M2 YELLOW
; Yellow LEDs blink.
;
; If button pressed during dark mode:
;
; M1 RED / M2 RED
; LED sequence = 5 seconds
; then return to dark mode.


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
; RESET VECTOR
;=========================================================

.org 0x0000

    rjmp RESET


;=========================================================
; REGISTER USE
;=========================================================

; r16 = general purpose
; r17 = traffic timer
; r18 = LED timer/counter
; r19 = button request flag
; r20 = delay counter
; r21 = delay counter
; r22 = delay counter
; r23 = button source
; r24 = ADC value
; r25 = light status

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

    ; PB0-PB4 OUTPUT

    ldi r16, 0b00011111
    out DDRB, r16

    ; LEDs OFF

    ldi r16, 0
    out PORTB, r16


    ;=====================================================
    ; PORT D
    ;=====================================================

    ; PD0 = INPUT
    ; PD1-PD6 = OUTPUT

    ldi r16, 0b01111110
    out DDRD, r16


    ;-----------------------------------------------------
    ; Enable internal pull-up on push button
    ;-----------------------------------------------------

    sbi PORTD, PD0


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

    cbi PORTD, PD1
    sbi PORTD, PD2
    cbi PORTD, PD3


    ;-----------------------------------------------------
    ; M2 YELLOW
    ;-----------------------------------------------------

    cbi PORTD, PD4
    sbi PORTD, PD5
    cbi PORTD, PD6


    ;-----------------------------------------------------
    ; LEDs OFF
    ;-----------------------------------------------------

    ldi r16, 0
    out PORTB, r16


    ;-----------------------------------------------------
    ; YELLOW ON = 500 ms
    ;-----------------------------------------------------

    ldi r17, 5


DARK_YELLOW_ON_LOOP:

    rcall CHECK_BUTTON_DARK

    tst r19

    ; If no button, continue.
    breq DARK_NO_BUTTON_ON

    ; Button pressed.
    rjmp DARK_BUTTON


DARK_NO_BUTTON_ON:

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

    rcall CHECK_BUTTON_DARK

    tst r19

    breq DARK_NO_BUTTON_OFF

    rjmp DARK_BUTTON


DARK_NO_BUTTON_OFF:

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
; BUTTON DURING DARK MODE
;=========================================================

DARK_BUTTON:

    ldi r19, 0

    rjmp BOTH_RED_DARK


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
    ; LEDs OFF
    ;-----------------------------------------------------

    ldi r16, 0
    out PORTB, r16


    ;-----------------------------------------------------
    ; M1 GREEN
    ;-----------------------------------------------------

    cbi PORTD, PD1
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

    rcall CHECK_BUTTON

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

    rjmp BOTH_YELLOW_FROM_M1


;=========================================================
; BUTTON DURING M1 GREEN
;=========================================================

M1_GREEN_BUTTON:

    rjmp M1_YELLOW_M2_RED_REQUEST


;=========================================================
;=========================================================
; BOTH YELLOW AFTER M1 GREEN
;=========================================================
;=========================================================

BOTH_YELLOW_FROM_M1:

    rcall CHECK_LIGHT

    tst r25
    brne BOTH_YELLOW_M1_LIGHT

    rjmp DARK_MODE


BOTH_YELLOW_M1_LIGHT:

    ; M1 YELLOW

    cbi PORTD, PD1
    sbi PORTD, PD2
    cbi PORTD, PD3


    ; M2 YELLOW

    cbi PORTD, PD4
    sbi PORTD, PD5
    cbi PORTD, PD6


    ;-----------------------------------------------------
    ; 3 seconds
    ;-----------------------------------------------------

    ldi r17, 30


BOTH_YELLOW_FROM_M1_LOOP:

    rcall CHECK_LIGHT

    tst r25
    brne BOTH_YELLOW_M1_CONTINUE

    rjmp DARK_MODE


BOTH_YELLOW_M1_CONTINUE:

    rcall DELAY_100MS

    dec r17
    brne BOTH_YELLOW_FROM_M1_LOOP


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

    ; LEDs OFF

    ldi r16, 0
    out PORTB, r16


    ; M1 YELLOW

    cbi PORTD, PD1
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

    ; LEDs OFF

    ldi r16, 0
    out PORTB, r16


    ; M1 RED

    sbi PORTD, PD1
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

    rcall CHECK_BUTTON

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

    rjmp BOTH_YELLOW_FROM_M2


;=========================================================
; BUTTON DURING M2 GREEN
;=========================================================

M2_GREEN_BUTTON:

    rjmp M1_RED_M2_YELLOW_REQUEST


;=========================================================
;=========================================================
; BOTH YELLOW AFTER M2 GREEN
;=========================================================
;=========================================================

BOTH_YELLOW_FROM_M2:

    rcall CHECK_LIGHT

    tst r25
    brne BOTH_YELLOW_M2_LIGHT

    rjmp DARK_MODE


BOTH_YELLOW_M2_LIGHT:

    ; M1 YELLOW

    cbi PORTD, PD1
    sbi PORTD, PD2
    cbi PORTD, PD3


    ; M2 YELLOW

    cbi PORTD, PD4
    sbi PORTD, PD5
    cbi PORTD, PD6


    ;-----------------------------------------------------
    ; 3 seconds
    ;-----------------------------------------------------

    ldi r17, 30


BOTH_YELLOW_FROM_M2_LOOP:

    rcall CHECK_LIGHT

    tst r25
    brne BOTH_YELLOW_M2_CONTINUE

    rjmp DARK_MODE


BOTH_YELLOW_M2_CONTINUE:

    rcall DELAY_100MS

    dec r17
    brne BOTH_YELLOW_FROM_M2_LOOP


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

    ; LEDs OFF

    ldi r16, 0
    out PORTB, r16


    ; M1 RED

    sbi PORTD, PD1
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

    sbi PORTD, PD1
    cbi PORTD, PD2
    cbi PORTD, PD3


    ; M2 RED

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6


    ; LEDs OFF

    ldi r16, 0
    out PORTB, r16


    ;-----------------------------------------------------
    ; 5-second LED sequence
    ;-----------------------------------------------------

    rcall LED_SEQUENCE


    ; LEDs OFF

    ldi r16, 0
    out PORTB, r16


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
; BOTH RED FROM DARK MODE
;=========================================================
;=========================================================

BOTH_RED_DARK:

    ;-----------------------------------------------------
    ; M1 RED
    ;-----------------------------------------------------

    sbi PORTD, PD1
    cbi PORTD, PD2
    cbi PORTD, PD3


    ;-----------------------------------------------------
    ; M2 RED
    ;-----------------------------------------------------

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6


    ; LEDs OFF

    ldi r16, 0
    out PORTB, r16


    ;-----------------------------------------------------
    ; 5-second LED sequence
    ;-----------------------------------------------------

    rcall LED_SEQUENCE


    ; LEDs OFF

    ldi r16, 0
    out PORTB, r16


    ; Clear button

    ldi r19, 0
    ldi r23, 0


    ;-----------------------------------------------------
    ; Check light
    ;-----------------------------------------------------

    rcall CHECK_LIGHT

    tst r25
    brne DARK_BUTTON_LIGHT_RETURNED

    rjmp DARK_MODE


DARK_BUTTON_LIGHT_RETURNED:

    rjmp M1_GREEN_M2_RED


;=========================================================
;=========================================================
; BUTTON FROM M1 GREEN
;=========================================================
;=========================================================

BUTTON_FROM_M1:

    ldi r19, 0
    ldi r23, 0


    ; LEDs OFF

    ldi r16, 0
    out PORTB, r16


    ; M1 RED

    sbi PORTD, PD1
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

    ; LEDs OFF

    ldi r16, 0
    out PORTB, r16


    ; M1 RED

    sbi PORTD, PD1
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


    rjmp BOTH_YELLOW_FROM_M2


;=========================================================
;=========================================================
; BUTTON FROM M2 GREEN
;=========================================================
;=========================================================

BUTTON_FROM_M2:

    ldi r19, 0
    ldi r23, 0


    ; LEDs OFF

    ldi r16, 0
    out PORTB, r16


    ; M1 YELLOW

    cbi PORTD, PD1
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

    ; LEDs OFF

    ldi r16, 0
    out PORTB, r16


    ; M1 GREEN

    cbi PORTD, PD1
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


    rjmp BOTH_YELLOW_FROM_M1


;=========================================================
;=========================================================
; CHECK BUTTON
;=========================================================

; PD0:
;
; HIGH = NOT PRESSED
; LOW  = PRESSED
;
;=========================================================

CHECK_BUTTON:

    ;-----------------------------------------------------
    ; Check button
    ;-----------------------------------------------------

    sbic PIND, PD0
    rjmp BUTTON_EXIT


    ;-----------------------------------------------------
    ; Debounce
    ;-----------------------------------------------------

    rcall DELAY_20MS


    ;-----------------------------------------------------
    ; Check again
    ;-----------------------------------------------------

    sbic PIND, PD0
    rjmp BUTTON_EXIT


    ;-----------------------------------------------------
    ; Button confirmed
    ;-----------------------------------------------------

    ldi r19, 1


    ;-----------------------------------------------------
    ; Wait for release
    ;-----------------------------------------------------

BUTTON_RELEASE:

    sbis PIND, PD0
    rjmp BUTTON_RELEASE


    ; Release debounce

    rcall DELAY_20MS


BUTTON_EXIT:

    ret


;=========================================================
;=========================================================
; CHECK BUTTON DURING DARK MODE
;=========================================================
;=========================================================

CHECK_BUTTON_DARK:

    sbic PIND, PD0
    rjmp DARK_BUTTON_EXIT


    ; Debounce

    rcall DELAY_20MS


    ; Check again

    sbic PIND, PD0
    rjmp DARK_BUTTON_EXIT


    ; Button confirmed

    ldi r19, 1


DARK_BUTTON_RELEASE:

    sbis PIND, PD0
    rjmp DARK_BUTTON_RELEASE


    rcall DELAY_20MS


DARK_BUTTON_EXIT:

    ret


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
;=========================================================
;=========================================================

LED_SEQUENCE:

    ;=====================================================
    ; 1 SECOND - 5 LEDs
    ;=====================================================

    ldi r16, 0b00011111
    out PORTB, r16

    rcall DELAY_1SEC


    ;=====================================================
    ; 2 SECOND - 4 LEDs
    ;=====================================================

    ldi r16, 0b00001111
    out PORTB, r16

    rcall DELAY_1SEC


    ;=====================================================
    ; 3 SECOND - 3 LEDs
    ;=====================================================

    ldi r16, 0b00000111
    out PORTB, r16

    rcall DELAY_1SEC


    ;=====================================================
    ; 4 SECOND - 2 LEDs
    ;=====================================================

    ldi r16, 0b00000011
    out PORTB, r16

    rcall DELAY_1SEC


    ;=====================================================
    ; 5 SECOND - 1 LED
    ;=====================================================

    ldi r16, 0b00000001
    out PORTB, r16

    rcall DELAY_1SEC


    ;-----------------------------------------------------
    ; LEDs OFF
    ;-----------------------------------------------------

    ldi r16, 0
    out PORTB, r16

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

    ldi r20, 8


DELAY100_OUTER:

    ldi r21, 200


DELAY100_MIDDLE:

    ldi r22, 250


DELAY100_INNER:

    dec r22
    brne DELAY100_INNER

    dec r21
    brne DELAY100_MIDDLE

    dec r20
    brne DELAY100_OUTER

    ret


;=========================================================
;=========================================================
; 20 ms DELAY
;
;=========================================================

DELAY_20MS:

    ldi r20, 2


DELAY20_OUTER:

    ldi r21, 200


DELAY20_MIDDLE:

    ldi r22, 250


DELAY20_INNER:

    dec r22
    brne DELAY20_INNER

    dec r21
    brne DELAY20_MIDDLE

    dec r20
    brne DELAY20_OUTER

    ret


;=========================================================
; END OF PROGRAM
;=========================================================