;
; main.asm
; Author : Diane Marquette, Luc Reveyron
;

.include "macros.asm"					; include macros definition
.include "definitions.asm"				; include register/constant definition

;====INTERRUPT TABLE====
.org	0
		jmp reset
		jmp ext_int0
		jmp ext_int1

.org	0x24
		rjmp uart_rcx					; UART RX Complete handler


.org	OVF0addr
		rjmp ovf0

;====OTHER INCLUDES====
.org	0x30
.include "uart.asm"						; include UART routine
.include "printf.asm"					; include formatted printing routines
.include "wire1.asm"	      

;====INTERRUPT SERVICE ROUTINES====

ext_int0:
		rjmp reset

ext_int1:

		ldi r21,200
 
		counter: 
			sbi	PORTA,SPEAKER
			WAIT_US	200	

			cbi	PORTA,SPEAKER
			WAIT_US	200	
		
			dec r21
			cpi r21,0
			brne counter
		cpi r28,0
		brne skip1
		rcall temperature
		ldi r25,1						; The message comes from INT0
		ldi r28,1								; Set T = 1
		rcall display
		skip1:							; No message is displayed if T was already set
		reti
uart_rcx:
		rcall UART0_getc
		PRINTF UART0
.db LF,CR,"a0=",FBIN,a,0
		cpi a0,0b11110101				; Compare register to binary value associated to character "u"
		brne not_update
		rcall temperature
		rcall display
		not_update:
		cpi a0,0b11100100				; Compare register to binary value associated to character "d"
		brne not_day
		TIMERLIMIT 0,0,0
		not_day:
		cpi a0,0b11110100				; Compare register to binary value associated to character "t"
		brne not_twelve
		TIMERLIMIT 0,0,12
		not_twelve:
		cpi a0,0b11100110				; Compare register to binary value associated to character "f"
		brne not_five
		TIMERLIMIT 0,55,23
		not_five:
		cpi a0,0b11110011				; Compare register to binary value associated to character "s"
		brne not_second
		TIMERLIMIT 55,59,23
		not_second:



		ldi a0,0
		reti
		

		
ovf0: 

	inc r22								; Increment seconds
	cpi r22,60							; Verify if the counter reached one minute
	brne back			
	ldi r22,0							; Reset second
	inc r23							; Increment minute
	cpi r23,60							; Verify if the counter reached one hour
	brne back
	ldi r23,0							; Reset minutes
	inc r24							; Increment hours
	cpi r24,24							; Verify if the counter reached one day
	brne back
	ldi r24,0							; Reset hours
	rcall temperature
	ldi r25,0							; Message comes from TIMER0
	rcall display
	sbi PORTC,7
	back:
	reti


;====RESET====

reset:
	LDSP	RAMEND						; load stack pointer SP
	OUTI DDRC,$ff						; set LED 
	OUTI DDRD,$00
	sbi	DDRA,SPEAKER					; make pin SPEAKER an output
	OUTI EIMSK,0b00000011				; enable INT0 
	rcall	wire1_init					; initialize 1-wire(R) interface
	rcall	UART0_init					; initialize UART
	OUTI TIMSK,1<<TOIE0
	OUTI ASSR,(1<<AS0)
	OUTI TCCR0,5
	ldi r22,0							; reset r22
	ldi r25,0							; reset r25
	ldi r28,0							; reset r28
	sei									; set global interrupt 

	rjmp main	


;====MAIN====

main:
	nop
	rjmp	main					
	
;====SUB-ROUTINES DEFINITIONS====		

;====display================================================
;purpose: This sub-routine displays a message on the UART terminal and includes the current values stored in some registers (temperature,pump's status)
;in:		a0,a1,a2 (temperature)
;			T (pump's status: 1 OFF, 0 ON)
;			r21	 (message's origin: 1 INT0, 0 TIMER0)
;out:			 (a message is displayed on the UART terminal)
;mod:		none
;===========================================================
display:
		sbrs r25,0				; Skip if bit 0 of r25 is set
		rjmp jump1
		PRINTF UART0
.db LF,CR,	"/!\ WARNING /!\",0
		jump1:
		PRINTF UART0
.db LF,CR,	"Report:",0
		PRINTF UART0
.db LF,CR,	"temperature=",FFRAC2+FSIGN,a,4,$42,"C ",CR,0
		PRINTF UART0
.db LF,CR,	"pump's status:",0

		cpi r28,1			
		breq skip2				; Branch to skip2 if r28 = 1
		PRINTF UART0
.db "ON",0
		rjmp jump2
		skip2:					
		PRINTF UART0
.db "OFF",0
		jump2:
		ret 

;====temperature============================================
;purpose: This sub-routine ask for the current temperature measured by the probe
;in:		none
;out:		a0,a1,a2 
;mod:		a0,a1,a2,c0
;===========================================================
temperature:
			
			rcall	wire1_reset			; send a reset pulse
			CA	wire1_write, skipROM	; skip ROM identification
			CA	wire1_write, convertT	; initiate temp conversion
			WAIT_MS	750					; wait 750 msec
	
			rcall	wire1_reset			; send a reset pulse
			CA	wire1_write, skipROM
			CA	wire1_write, readScratchpad	
			rcall	wire1_read			; read temperature LSB
			mov	c0,a0
			rcall	wire1_read			; read temperature MSB
			mov	a1,a0
			mov	a0,c0

			ret

