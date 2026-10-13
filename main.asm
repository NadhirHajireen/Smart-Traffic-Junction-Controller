; ATmega328P - two traffic light modules, push button, LDR
; 16 MHz
;
; PB0-PB4 countdown LEDs     PD2 M1 yellow    PD4 M2 red
; PB5     M1 red             PD3 M1 green     PD5 M2 yellow
; PD7     button             PC0 LDR (ADC0)   PD6 M2 green
;
; Normal: M1 green 10s -> M1 yellow 3s -> M2 yellow 3s -> M2 green 10s
;         -> M2 yellow 3s -> M1 yellow 3s -> repeat
; Button: finish current green, yellow, both red with 5s LED countdown,
;         then the other module goes
; Dark:   both yellows blink, button ignored

.include "m328pdef.inc"

; ADCH threshold (500 / 4)
.equ LIGHT_THRESHOLD = 125

; PB5 shares PORTB with the LEDs, so only touch that bit
.macro M1_RED_ON
    sbi PORTB, PB5
.endmacro

.macro M1_RED_OFF
    cbi PORTB, PB5
.endmacro


.org 0x0000

    rjmp RESET

.org PCI2addr

    rjmp PCINT2_ISR

.org INT_VECTORS_SIZE


; r17 = phase timer (100 ms ticks)
; r18 = 1 sec counter
; r19 = button request flag
; r20-r22 = delay counters
; r23 = who was green when button pressed (1 = M1, 2 = M2)
; r24 = ADC value
; r25 = 0 dark, 1 light
; r26 = scratch for LED_WRITE


RESET:

    ldi r16, high(RAMEND)
    out SPH, r16

    ldi r16, low(RAMEND)
    out SPL, r16

    ; PB0-PB5 outputs
    ldi r16, 0b00111111
    out DDRB, r16

    ldi r16, 0
    out PORTB, r16

    ; PD2-PD6 outputs, PD7 input
    ldi r16, 0b01111100
    out DDRD, r16

    ldi r16, 0
    out PORTD, r16

    ; button pull-up
    sbi PORTD, PD7

    ; pin change interrupt on PD7
    ldi r16, (1<<PCINT23)
    sts PCMSK2, r16

    ldi r16, (1<<PCIE2)
    sts PCICR, r16

    ldi r16, (1<<PCIF2)
    out PCIFR, r16

    cbi DDRC, PC0

    ; AVCC ref, left adjusted, ADC0
    ldi r16, (1<<REFS0) | (1<<ADLAR)
    sts ADMUX, r16

    ; enable ADC, clock /128
    ldi r16, (1<<ADEN) | (1<<ADPS2) | (1<<ADPS1) | (1<<ADPS0)
    sts ADCSRA, r16

    ldi r19, 0
    ldi r23, 0
    ldi r25, 1

    sei

    rcall CHECK_LIGHT

    rjmp CHECK_LIGHT_MODE


CHECK_LIGHT_MODE:

    rcall CHECK_LIGHT

    tst r25
    brne LIGHT_START

    rjmp DARK_MODE


LIGHT_START:

    rjmp M1_GREEN_M2_RED


;---------------- dark mode ----------------

DARK_MODE:

    M1_RED_OFF
    sbi PORTD, PD2
    cbi PORTD, PD3

    cbi PORTD, PD4
    sbi PORTD, PD5
    cbi PORTD, PD6

    rcall LEDS_OFF

    ; yellow on 500 ms
    ldi r17, 5


DARK_YELLOW_ON_LOOP:

    rcall DELAY_100MS

    dec r17
    brne DARK_YELLOW_ON_LOOP

    rcall CHECK_LIGHT

    tst r25
    brne DARK_LIGHT_RETURNED_1

    cbi PORTD, PD2
    cbi PORTD, PD5

    ; yellow off 500 ms
    ldi r17, 5


DARK_YELLOW_OFF_LOOP:

    rcall DELAY_100MS

    dec r17
    brne DARK_YELLOW_OFF_LOOP

    rcall CHECK_LIGHT

    tst r25
    brne DARK_LIGHT_RETURNED_2

    rjmp DARK_MODE


; light is back, drop any button press from the dark
DARK_LIGHT_RETURNED_1:

    ldi r19, 0
    ldi r23, 0

    rjmp M1_GREEN_M2_RED


DARK_LIGHT_RETURNED_2:

    ldi r19, 0
    ldi r23, 0

    rjmp M1_GREEN_M2_RED


;---------------- M1 green / M2 red ----------------

M1_GREEN_M2_RED:

    rcall CHECK_LIGHT

    tst r25
    brne M1_GREEN_LIGHT_OK

    rjmp DARK_MODE


M1_GREEN_LIGHT_OK:

    rcall LEDS_OFF

    M1_RED_OFF
    cbi PORTD, PD2
    sbi PORTD, PD3

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6

    ; 10 sec
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

    tst r19
    breq M1_GREEN_NO_REQUEST

    rjmp M1_GREEN_BUTTON


M1_GREEN_NO_REQUEST:

    rjmp STOP_M1


M1_GREEN_BUTTON:

    rjmp M1_YELLOW_M2_RED_REQUEST


;---------------- M1 stops ----------------

STOP_M1:

    rcall CHECK_LIGHT

    tst r25
    brne STOP_M1_LIGHT

    rjmp DARK_MODE


STOP_M1_LIGHT:

    ; M1 yellow, M2 red
    M1_RED_OFF
    sbi PORTD, PD2
    cbi PORTD, PD3

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6

    ; 3 sec
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

    ; M1 red, M2 yellow
    M1_RED_ON
    cbi PORTD, PD2
    cbi PORTD, PD3

    cbi PORTD, PD4
    sbi PORTD, PD5
    cbi PORTD, PD6

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


;---------------- button pressed in M1 green: M1 yellow ----------------

M1_YELLOW_M2_RED_REQUEST:

    rcall CHECK_LIGHT

    tst r25
    brne M1_YELLOW_REQUEST_LIGHT

    rjmp DARK_MODE


M1_YELLOW_REQUEST_LIGHT:

    rcall LEDS_OFF

    M1_RED_OFF
    sbi PORTD, PD2
    cbi PORTD, PD3

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6

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


;---------------- M1 red / M2 green ----------------

M1_RED_M2_GREEN:

    rcall CHECK_LIGHT

    tst r25
    brne M2_GREEN_LIGHT_OK

    rjmp DARK_MODE


M2_GREEN_LIGHT_OK:

    rcall LEDS_OFF

    M1_RED_ON
    cbi PORTD, PD2
    cbi PORTD, PD3

    cbi PORTD, PD4
    cbi PORTD, PD5
    sbi PORTD, PD6

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


M2_GREEN_BUTTON:

    rjmp M1_RED_M2_YELLOW_REQUEST


;---------------- M2 stops ----------------

STOP_M2:

    rcall CHECK_LIGHT

    tst r25
    brne STOP_M2_LIGHT

    rjmp DARK_MODE


STOP_M2_LIGHT:

    ; M1 red, M2 yellow
    M1_RED_ON
    cbi PORTD, PD2
    cbi PORTD, PD3

    cbi PORTD, PD4
    sbi PORTD, PD5
    cbi PORTD, PD6

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

    ; M1 yellow, M2 red
    M1_RED_OFF
    sbi PORTD, PD2
    cbi PORTD, PD3

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6

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


;---------------- button pressed in M2 green: M2 yellow ----------------

M1_RED_M2_YELLOW_REQUEST:

    rcall CHECK_LIGHT

    tst r25
    brne M2_YELLOW_REQUEST_LIGHT

    rjmp DARK_MODE


M2_YELLOW_REQUEST_LIGHT:

    rcall LEDS_OFF

    M1_RED_ON
    cbi PORTD, PD2
    cbi PORTD, PD3

    cbi PORTD, PD4
    sbi PORTD, PD5
    cbi PORTD, PD6

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


;---------------- both red + LED countdown ----------------

BOTH_RED:

    M1_RED_ON
    cbi PORTD, PD2
    cbi PORTD, PD3

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6

    rcall LEDS_OFF

    rcall LED_SEQUENCE

    rcall LEDS_OFF

    ; next turn goes to the module that was NOT green
    cpi r23, 1
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


;---------------- after button from M1: M2 goes ----------------

BUTTON_FROM_M1:

    ldi r19, 0
    ldi r23, 0

    rcall LEDS_OFF

    M1_RED_ON
    cbi PORTD, PD2
    cbi PORTD, PD3

    cbi PORTD, PD4
    sbi PORTD, PD5
    cbi PORTD, PD6

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


BUTTON_M2_GREEN:

    rcall CHECK_LIGHT

    tst r25
    brne BUTTON_M2_GREEN_LIGHT

    rjmp DARK_MODE


BUTTON_M2_GREEN_LIGHT:

    rcall LEDS_OFF

    M1_RED_ON
    cbi PORTD, PD2
    cbi PORTD, PD3

    cbi PORTD, PD4
    cbi PORTD, PD5
    sbi PORTD, PD6

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


;---------------- after button from M2: M1 goes ----------------

BUTTON_FROM_M2:

    ldi r19, 0
    ldi r23, 0

    rcall LEDS_OFF

    M1_RED_OFF
    sbi PORTD, PD2
    cbi PORTD, PD3

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6

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


BUTTON_M1_GREEN:

    rcall CHECK_LIGHT

    tst r25
    brne BUTTON_M1_GREEN_LIGHT

    rjmp DARK_MODE


BUTTON_M1_GREEN_LIGHT:

    rcall LEDS_OFF

    M1_RED_OFF
    cbi PORTD, PD2
    sbi PORTD, PD3

    sbi PORTD, PD4
    cbi PORTD, PD5
    cbi PORTD, PD6

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


;---------------- button interrupt ----------------
; latches a press into r19, ignores release

PCINT2_ISR:

    sbic PIND, PD7
    rjmp PCINT2_EXIT

    ldi r19, 1


PCINT2_EXIT:

    reti


;---------------- read LDR ----------------
; r25 = 0 dark, 1 light

CHECK_LIGHT:

    lds r16, ADCSRA

    ori r16, (1<<ADSC)

    sts ADCSRA, r16


ADC_WAIT:

    lds r16, ADCSRA

    sbrc r16, ADSC
    rjmp ADC_WAIT

    lds r24, ADCH

    cpi r24, LIGHT_THRESHOLD

    brlo ADC_DARK

    ldi r25, 1

    ret


ADC_DARK:

    ldi r25, 0

    ret


;---------------- LEDs on PB0-PB4 (leaves PB5 alone) ----------------

LED_WRITE:

    andi r16, 0b00011111
    in   r26, PORTB
    andi r26, 0b11100000
    or   r26, r16
    out  PORTB, r26

    ret


LEDS_OFF:

    ldi r16, 0
    rjmp LED_WRITE


; 5 LEDs -> 1 LED, 1 sec each

LED_SEQUENCE:

    ldi r16, 0b00011111
    rcall LED_WRITE
    rcall DELAY_1SEC

    ldi r16, 0b00001111
    rcall LED_WRITE
    rcall DELAY_1SEC

    ldi r16, 0b00000111
    rcall LED_WRITE
    rcall DELAY_1SEC

    ldi r16, 0b00000011
    rcall LED_WRITE
    rcall DELAY_1SEC

    ldi r16, 0b00000001
    rcall LED_WRITE
    rcall DELAY_1SEC

    rcall LEDS_OFF
    ret


;---------------- delays ----------------

DELAY_1SEC:

    ldi r18, 10


DELAY_1SEC_LOOP:

    rcall DELAY_100MS

    dec r18
    brne DELAY_1SEC_LOOP

    ret


; ~100 ms at 16 MHz
DELAY_100MS:

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