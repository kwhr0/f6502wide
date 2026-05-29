	RELAXED ON

gray	equ	0x2104

r_reset		equ	6
r_adr		equ	7
r_x		equ	8
r_y		equ	9
r_black		equ	10
r_white		equ	11
r_active	equ	12
r_ptr	equ	13
r_spi		equ	14
r_init		equ	15

; LCD definitions
; converted from https://github.com/cpldcpu/uTFT-ST7735

INITR_GREENTAB equ	0x0
INITR_REDTAB   equ	0x1

ST7735_TFTWIDTH equ	128
ST7735_TFTHEIGHT equ	160

ST7735_NOP     equ	0x00
ST7735_SWRESET equ	0x01
ST7735_RDDID   equ	0x04
ST7735_RDDST   equ	0x09

ST7735_SLPIN   equ	0x10
ST7735_SLPOUT  equ	0x11
ST7735_PTLON   equ	0x12
ST7735_NORON   equ	0x13

ST7735_INVOFF  equ	0x20
ST7735_INVON   equ	0x21
ST7735_DISPOFF equ	0x28
ST7735_DISPON  equ	0x29
ST7735_CASET   equ	0x2A
ST7735_RASET   equ	0x2B
ST7735_RAMWR   equ	0x2C
ST7735_RAMRD   equ	0x2E

ST7735_PTLAR   equ	0x30
ST7735_COLMOD  equ	0x3A
ST7735_MADCTL  equ	0x36

ST7735_FRMCTR1 equ	0xB1
ST7735_FRMCTR2 equ	0xB2
ST7735_FRMCTR3 equ	0xB3
ST7735_INVCTR  equ	0xB4
ST7735_DISSET5 equ	0xB6

ST7735_PWCTR1  equ	0xC0
ST7735_PWCTR2  equ	0xC1
ST7735_PWCTR3  equ	0xC2
ST7735_PWCTR4  equ	0xC3
ST7735_PWCTR5  equ	0xC4
ST7735_VMCTR1  equ	0xC5

ST7735_RDID1   equ	0xDA
ST7735_RDID2   equ	0xDB
ST7735_RDID3   equ	0xDC
ST7735_RDID4   equ	0xDD

ST7735_PWCTR6  equ	0xFC

ST7735_GMCTRP1 equ	0xE0
ST7735_GMCTRN1 equ	0xE1

; End of LCD definitions

l	function	v,v&0xff
h	function	v,v>>8

lea	macro	reg,ptr
	ldi	l(ptr)
	plo	reg
	ldi	h(ptr)
	phi	reg
	endm

delay_d:	macro	;/5 mS
	sex	r_spi
$$delay2:
	out	3
	dec	r_spi
$$delay1:
	b2	$$delay1
	smi	1
	bnz	$$delay2
	endm

delay100:	macro
	ldi	100/5
	delay_d
	endm

spi_d:	macro
	str	r_spi
	sex	r_spi
	align	2,0xee;X=14
$$spi1:
	b1	$$spi1
	out	1
	dec	r_spi
	endm

spi:	macro	value
	ldi	value
	spi_d
	endm

trans_dot:	macro	mask
	sex	r_spi
	inp	1
	ani	mask
	bnz	$$trans_dot1
	sex	r_black
$$trans_dot2:
	b1	$$trans_dot2
	out	1
	dec	r_black
$$trans_dot3:
	b1	$$trans_dot3
	out	1
	dec	r_black
	br	$$trans_dot4
$$trans_dot1:
	sex	r_white
$$trans_dot5:
	b1	$$trans_dot5
	out	1
	dec	r_white
$$trans_dot6:
	b1	$$trans_dot6
	out	1
	dec	r_white
$$trans_dot4:
	endm

; start
; init pointers
	lea	r_init,p_init
	lea	r_reset,p_reset
	lea	r_active,p_active
	lea	r_adr,p_adr
	lea	r_x,p_x
	lea	r_y,p_y
	lea	r_black,p_black
	lea	r_white,r_white
	lea	r_spi,p_spi
	;
	sex	r_init
	out	2
	dec	r_init
	delay100
	sex	r_reset
	out	2
	dec	r_reset
	delay100
	sex	r_init
	out	2
	dec	r_init
	delay100
	sex	r_active
	out	2
	dec	r_active
;
	lea	r_ptr,initdata
initloop:
	req
	lda	r_ptr
	spi_d
	ldx	;delay
	ldx	;delay
	ldx	;delay
	ldn	r_ptr
	ani	0x80
	bnz	do_delay
	seq
	lda	r_ptr
	str	r_x	; arg count
	bz	init2
init1:
	lda	r_ptr
	spi_d
	ldn	r_x
	smi	1
	str	r_x
	bnz	init1
	br	init2
do_delay:
	inc	r_ptr
	lda	r_ptr
	delay_d
init2:
	glo	r_ptr
	smi	l(initdata_end)
	bnz	initloop
; fill gray
	req
	spi	ST7735_RAMWR
	;
	ldi	0
	str	r_adr
	inc	r_adr
	ldi	0xb0	;-160*128>>8
	str	r_adr
	dec	r_adr
	seq
fill1:
	spi	h(gray)
	spi	l(gray)
	ldn	r_adr
	adi	1
	str	r_adr
	bnz	fill1
	inc	r_adr
	ldn	r_adr
	adi	1
	str	r_adr
	dec	r_adr
	bnz	fill1
;
	req
	spi	ST7735_CASET
	; output address and delay
	ldx	;delay
	ldx	;delay
	ldx	;delay
	ldx	;delay
	ldx	;delay
	ldx	;delay
	seq
	spi	0
	spi	16
	spi	0
	spi	16+95
; main loop
loop:
	sex	r_spi
	ldi	20	;100mS
waitstart2:
	out	3
	dec	r_spi
waitstart1:
	b3	start
	b2	waitstart1
	smi	1
	bnz	waitstart2
	; generate dummy VSync
	sex	r_active
	out	2	;CS_N=0
	dec	r_active
	sex	r_init
	out	2	;CS_N=1
	dec	r_init
	br	loop
start:
	sex	r_adr
	ldi	0
	str	r_adr
	inc	r_adr
	inp	2	;start address (upper)
	dec	r_adr
	sex	r_active
	out	2
	dec	r_active
	ldi	0
	str	r_y
loop_y:
	req
	spi	ST7735_RASET
	ldx	;delay
	ldx	;delay
	ldx	;delay
	ldx	;delay
	ldx	;delay
	ldx	;delay
	seq
	spi	0
	ldn	r_y
	spi_d
	spi	0
	ldn	r_y
	spi_d
	ldx	;delay
	ldx	;delay
	ldx	;delay
	ldx	;delay
	ldx	;delay
	ldx	;delay
;
	req
	spi	ST7735_RAMWR
	ldx	;delay
	ldx	;delay
	ldx	;delay
	ldx	;delay
	ldx	;delay
	ldx	;delay
	seq
;
	ldi		16
	str	r_x
loop_x:
; set address
	sex	r_adr
	out	4
	out	5
	dec	r_adr
	dec	r_adr
; increment address
	ldn	r_adr
	adi	1
	str	r_adr
	inc	r_adr
	ldn	r_adr
	adci	0
	str	r_adr
	dec	r_adr
	lbr	transfer1
	align	0x100
transfer1:
	trans_dot	0x80
	trans_dot	0x40
	trans_dot	0x20
	trans_dot	0x10
	trans_dot	0x08
	trans_dot	0x04
	trans_dot	0x02
	trans_dot	0x01
;;	ldx	;delay
next:
	ldn	r_x
	adi	8
	str	r_x
	smi	16+96
	lbnz	loop_x
	ldi	1
	sex	r_y
	add
	str	r_y
	ldi	160
	sm
	lbnz	loop_y
	sex	r_init
	out	2	;CS_N=1 as VSync
	dec	r_init
	lbr	loop

RESET_N	equ	2
CS_N	equ	1

p_init:	db	CS_N|RESET_N
p_reset:	db	CS_N
p_active:	db	RESET_N
p_black:	db	0
p_white:	db	0xff
p_spi:	ds	1
p_x:	ds	1
p_y:	ds	1
p_adr:	ds	2

; LCD init data
; converted from https://github.com/cpldcpu/uTFT-ST7735

DELAY	equ	0x80
initdata:
	db	ST7735_SWRESET,   DELAY  ;  1: Software reset, 0 args, w/delay
	db	150/5                    ;     150 ms delay
	db	ST7735_SLPOUT ,   DELAY  ;  2: Out of sleep mode, 0 args, w/delay
	db	500/5                    ;     500 ms delay
	db	ST7735_FRMCTR1, 3        ;  3: Frame rate ctrl - normal mode, 3 args:
	db	0x00, 0x00, 0x00       ;     Rate = fosc/(1x2+40) * (LINE+2C+2D)
;	db	0x01, 0x2C, 0x2D       ;     Rate = fosc/(1x2+40) * (LINE+2C+2D)
	db	ST7735_FRMCTR2, 3        ;  4: Frame rate control - idle mode, 3 args:
	db	0x01, 0x2C, 0x2D       ;     Rate = fosc/(1x2+40) * (LINE+2C+2D)
	db	ST7735_FRMCTR3, 6        ;  5: Frame rate ctrl - partial mode, 6 args:
	db	0x01, 0x2C, 0x2D       ;     Dot inversion mode
	db	0x01, 0x2C, 0x2D       ;     Line inversion mode
	db	ST7735_INVCTR , 1        ;  6: Display inversion ctrl, 1 arg, no delay:
	db	0x07                   ;     No inversion
	db	ST7735_PWCTR1 , 3        ;  7: Power control, 3 args, no delay:
	db	0xA2
	db	0x02                   ;     -4.6V
	db	0x84                   ;     AUTO mode
	db	ST7735_PWCTR2 , 1        ;  8: Power control, 1 arg, no delay:
	db	0xC5                   ;     VGH25 = 2.4C VGSEL = -10 VGH = 3 * AVDD
	db	ST7735_PWCTR3 , 2        ;  9: Power control, 2 args, no delay:
	db	0x0A                   ;     Opamp current small
	db	0x00                   ;     Boost frequency
	db	ST7735_PWCTR4 , 2        ; 10: Power control, 2 args, no delay:
	db	0x8A                   ;     BCLK/2, Opamp current small & Medium low
	db	0x2A
	db	ST7735_PWCTR5 , 2        ; 11: Power control, 2 args, no delay:
	db	0x8A, 0xEE
	db	ST7735_VMCTR1 , 1        ; 12: Power control, 1 arg, no delay:
	db	0x0E
	db	ST7735_INVOFF , 0        ; 13: Don't invert display, no args, no delay
	db	ST7735_MADCTL , 1        ; 14: Memory access control (directions), 1 arg:
	db	0xC8                   ;     row addr/col addr, bottom to top refresh
	db	ST7735_COLMOD , 1        ; 15: set color mode, 1 arg, no delay:
	db	0x05
	db	ST7735_CASET  , 4        ;  1: Column addr set, 4 args, no delay:
	db	0x00, 0x00             ;     XSTART = 0
	db	0x00, 0x7F
;	db	0x00, 0x9F             ;
	db	ST7735_RASET  , 4        ;  2: Row addr set, 4 args, no delay:
	db	0x00, 0x00             ;     XSTART = 0
	db	0x00, 0x9F             ;
;	db	0x00, 0x7F
	db	ST7735_GMCTRP1, 16       ;  1: Magical unicorn dust, 16 args, no delay:
	db	0x02, 0x1c, 0x07, 0x12
	db	0x37, 0x32, 0x29, 0x2d
	db	0x29, 0x25, 0x2B, 0x39
	db	0x00, 0x01, 0x03, 0x10
	db	ST7735_GMCTRN1, 16       ;  2: Sparkles and rainbows, 16 args, no delay:
	db	0x03, 0x1d, 0x07, 0x06
	db	0x2E, 0x2C, 0x29, 0x2D
	db	0x2E, 0x2E, 0x37, 0x3F
	db	0x00, 0x00, 0x02, 0x10
	db	ST7735_NORON  ,    DELAY ;  3: Normal display on, no args, w/delay
	db	10/5                     ;     10 ms delay
	db	ST7735_DISPON ,    DELAY ;  4: Main screen turn on, no args w/delay
	db	100/5 ;     100 ms delay
initdata_end:

	end
