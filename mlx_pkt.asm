; ===========================================================================
;  ESQUELETO DO PACKET DRIVER DOS PARA MELLANOX CONNECTX-3 (VIA UNDI/PXE)
; ===========================================================================
; Compilar com: nasm -f bin mlx_pkt.asm -o mlx_pkt.com
; Executar com: mlx_pkt.com [vector] (ex: mlx_pkt.com 0x60)
; ===========================================================================

org 100h

section .text

start:
    jmp init_driver

; --- DADOS E VARIAVEIS DO RESIDENTE ---
driver_sig      db 'PKT DRVR', 0    ; Assinatura obrigatória do Crynwr
int_num         db 60h              ; Vetor de interrupção padrão
pxe_found       db 0
pxe_seg         dw 0
pxe_off         dw 0
undi_entry_seg  dw 0
undi_entry_off  dw 0
mac_address     db 0,0,0,0,0,0

original_int_off    dw 0
original_int_seg    dw 0

orig_int1c_off      dw 0
orig_int1c_seg      dw 0

client_active       db 0
client_class        db 0
client_type         dw 0
client_callback_off dw 0
client_callback_seg dw 0
client_handle       dw 1234h        ; Um ID de handle fixo

driver_name_str     db 'Mellanox ConnectX-3 UNDI Packet Driver', 0

; Blocos de parâmetros residentes para chamadas da ISR e Transmissão
align 4
undi_isr_block:
    .Status:             dw 0
    .FuncFlag:           dw 0
    .BufferLength:       dw 0
    .FrameLength:        dw 0
    .FrameHeaderLength:  dw 0
    .Frame_off:          dw 0
    .Frame_seg:          dw 0
    .ProtType:           db 0
    .PktType:            db 0

align 4
undi_tbd_block:
    .ImmedLength:        dw 0
    .Xmit_off:           dw 0
    .Xmit_seg:           dw 0
    .DataBlkCount:       dw 0

align 4
undi_xmit_block:
    .Status:             dw 0
    .Protocol:           db 0
    .XmitFlag:           db 0
    .DestAddr_off:       dw 0
    .DestAddr_seg:       dw 0
    .TBD_off:            dw 0
    .TBD_seg:            dw 0
    .Reserved:           dd 0

; --- HANDLER DA INTERRUPCAO (PARTE RESIDENTE) ---
align 4
packet_driver_handler:
    jmp .handle_int
    db 'PKT DRVR'

.handle_int:
    cmp ah, 01h         ; driver_info?
    je .driver_info
    cmp ah, 02h         ; access_type?
    je .access_type
    cmp ah, 03h         ; release_type?
    je .release_type
    cmp ah, 04h         ; send_pkt?
    je .send_pkt
    cmp ah, 05h         ; terminate?
    je .terminate
    cmp ah, 06h         ; get_address?
    je .get_address
    
    mov dh, 1           ; Erro: BAD_COMMAND
    stc
    iret

.driver_info:
    mov ah, 1           ; Spec version 1
    mov al, 1           ; Class 1 (Ethernet)
    mov bx, 100         ; Driver version 1.00
    mov cx, 0           ; Driver type 0
    xor dx, dx          ; Basic functionalities
    push cs
    pop ds
    mov si, driver_name_str
    clc
    iret

.access_type:
    cmp byte [cs:client_active], 0
    jne .access_error_busy
    
    mov [cs:client_class], al
    mov [cs:client_type], bx
    mov [cs:client_callback_off], di
    mov [cs:client_callback_seg], es
    mov byte [cs:client_active], 1
    
    mov ax, [cs:client_handle]
    clc
    iret

.access_error_busy:
    mov dh, 9           ; NO_SPACE/NO_RESOURCES
    stc
    iret

.release_type:
    cmp bx, [cs:client_handle]
    jne .release_error_handle
    cmp byte [cs:client_active], 0
    je .release_error_handle
    
    mov byte [cs:client_active], 0
    clc
    iret

.release_error_handle:
    mov dh, 1           ; BAD_HANDLE
    stc
    iret

.send_pkt:
    push ds
    push es
    push si
    push di
    push cx
    
    push cs
    pop es
    
    mov [cs:undi_tbd_block.ImmedLength], cx
    mov [cs:undi_tbd_block.Xmit_off], si
    mov [cs:undi_tbd_block.Xmit_seg], ds
    mov word [cs:undi_tbd_block.DataBlkCount], 0
    
    mov word [cs:undi_xmit_block.Status], 0
    mov byte [cs:undi_xmit_block.Protocol], 0        ; P_UNKNOWN (0)
    mov byte [cs:undi_xmit_block.XmitFlag], 1        ; XMT_BROADCAST (1)
    mov word [cs:undi_xmit_block.DestAddr_off], 0
    mov word [cs:undi_xmit_block.DestAddr_seg], 0
    mov word [cs:undi_xmit_block.TBD_off], undi_tbd_block
    mov word [cs:undi_xmit_block.TBD_seg], cs
    mov dword [cs:undi_xmit_block.Reserved], 0
    
    push cs
    push undi_xmit_block
    push word 0008h     ; Opcode: PXENV_UNDI_TRANSMIT
    call far [cs:undi_entry_off]
    add sp, 6
    
    cmp ax, 0
    jne .send_error
    cmp word [cs:undi_xmit_block.Status], 0
    jne .send_error
    
    pop cx
    pop di
    pop si
    pop es
    pop ds
    clc
    iret
    
.send_error:
    pop cx
    pop di
    pop si
    pop es
    pop ds
    mov dh, 7           ; CANT_TRANSCEIVE
    stc
    iret

.terminate:
    cmp bx, [cs:client_handle]
    jne .term_bad_handle
    
    push ds
    push bx
    
    ; Restaurar o vetor de interrupção original do Packet Driver
    xor ax, ax
    mov ds, ax
    mov bl, [cs:int_num]
    xor bh, bh
    shl bx, 2
    
    cli
    mov ax, [cs:original_int_off]
    mov [ds:bx], ax
    mov ax, [cs:original_int_seg]
    mov [ds:bx+2], ax
    sti
    
    ; Restaurar INT 1Ch
    mov dx, [cs:orig_int1c_off]
    mov ax, [cs:orig_int1c_seg]
    mov ds, ax
    mov ax, 251Ch       ; Set Interrupt Vector 1Ch
    int 21h
    
    pop bx
    pop ds
    
    mov byte [cs:client_active], 0
    clc
    iret

.term_bad_handle:
    mov dh, 1           ; BAD_HANDLE
    stc
    iret

.get_address:
    cmp bx, [cs:client_handle]
    jne .get_addr_bad_handle
    cmp cx, 6
    jb .get_addr_no_space
    
    push ds
    push si
    push di
    push cx
    
    push cs
    pop ds
    mov si, mac_address
    mov cx, 6
    cld
    rep movsb
    
    pop cx
    pop di
    pop si
    pop ds
    
    mov cx, 6
    clc
    iret

.get_addr_bad_handle:
    mov dh, 1           ; BAD_HANDLE
    stc
    iret

.get_addr_no_space:
    mov dh, 9           ; NO_SPACE
    stc
    iret

align 4
timer_handler:
    pusha
    push ds
    push es
    
    push cs
    pop ds
    
    cmp byte [client_active], 0
    je .chain
    
    call poll_packets
    
.chain:
    pop es
    pop ds
    popa
    
    jmp far [cs:orig_int1c_off]

poll_packets:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    
    push cs
    pop ds
    
    mov word [undi_isr_block.FuncFlag], 1   ; PXENV_UNDI_ISR_IN_START
    
    push cs
    push undi_isr_block
    push word 0014h     ; Opcode: PXENV_UNDI_ISR
    call far [cs:undi_entry_off]
    add sp, 6
    
    cmp ax, 0
    jne .done
    cmp word [undi_isr_block.Status], 0
    jne .done
    
    cmp word [undi_isr_block.FuncFlag], 0   ; PXENV_UNDI_ISR_OUT_OURS
    jne .done
    
    mov word [undi_isr_block.FuncFlag], 2   ; PXENV_UNDI_ISR_IN_PROCESS
    
.process_loop:
    push cs
    push undi_isr_block
    push word 0014h     ; Opcode: PXENV_UNDI_ISR
    call far [cs:undi_entry_off]
    add sp, 6
    
    cmp ax, 0
    jne .done
    cmp word [undi_isr_block.Status], 0
    jne .done
    
    mov bx, [undi_isr_block.FuncFlag]
    cmp bx, 3           ; PXENV_UNDI_ISR_OUT_RECEIVE
    je .received_packet
    
    cmp bx, 6           ; PXENV_UNDI_ISR_OUT_DONE
    je .done
    
    jmp .get_next
    
.received_packet:
    cmp byte [client_active], 0
    je .get_next
    
    mov cx, [undi_isr_block.FrameLength]
    mov ds, [undi_isr_block.Frame_seg]
    mov si, [undi_isr_block.Frame_off]
    
    push bp
    push ds
    push es
    
    xor ax, ax          ; AX = 0 (Request Buffer)
    call far [cs:client_callback_off]
    
    mov bx, es
    mov dx, di
    
    pop es
    pop ds
    pop bp
    
    push cs
    pop ds
    
    mov ax, bx
    or ax, dx
    jz .get_next
    
    push es
    push ds
    
    mov es, bx
    mov di, dx
    
    mov ds, [undi_isr_block.Frame_seg]
    mov si, [undi_isr_block.Frame_off]
    
    mov cx, [cs:undi_isr_block.BufferLength]
    cld
    rep movsb
    
    pop ds
    pop es
    
    push bp
    push ds
    push es
    
    mov es, bx
    mov di, dx
    mov cx, [cs:undi_isr_block.FrameLength]
    mov ax, 1           ; AX = 1 (Complete)
    
    call far [cs:client_callback_off]
    
    pop es
    pop ds
    pop bp
    
    push cs
    pop ds
    
.get_next:
    mov word [undi_isr_block.FuncFlag], 3   ; PXENV_UNDI_ISR_IN_GET_NEXT
    jmp .process_loop
    
.done:
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

align 16
resident_end:           ; Fim do código residente


; --- CÓDIGO DE INICIALIZAÇÃO (DESCARTADO APÓS CARREGAR) ---
init_driver:
    mov dx, msg_hello
    call print_string

    ; Parse do argumento da linha de comando (vetor)
    mov si, 81h
.find_arg_loop:
    lodsb
    cmp al, 0Dh
    je .no_arg
    cmp al, ' '
    je .find_arg_loop
    cmp al, 9
    je .find_arg_loop
    
    dec si
    call parse_hex_byte
    jc .no_arg
    mov [int_num], al
    jmp .arg_parsed
.no_arg:
.arg_parsed:

    call find_pxe_struct
    cmp byte [pxe_found], 1
    je .pxe_ok
    
    mov dx, msg_no_pxe
    call print_string
    mov ax, 4C01h
    int 21h

.pxe_ok:
    mov dx, msg_pxe_found
    call print_string
    
    mov ax, [undi_entry_seg]
    call print_hex_word
    mov dl, ':'
    mov ah, 02h
    int 21h
    mov ax, [undi_entry_off]
    call print_hex_word
    mov dx, msg_newline
    call print_string

    ; Ler o MAC via UNDI
    mov bx, 000Ch       ; Opcode: PXENV_UNDI_GET_INFORMATION
    mov dx, undi_info_block
    call call_pxe
    jc .mac_error
    
    cmp word [undi_info_block.Status], 0
    jne .mac_error
    
    push ds
    push es
    push cs
    pop ds
    push cs
    pop es
    mov si, undi_info_block.CurrentNodeAddress
    mov di, mac_address
    mov cx, 6
    cld
    rep movsb
    pop es
    pop ds
    
    mov dx, msg_mac_ok
    call print_string
    mov si, mac_address
    call print_mac
    jmp .install
    
.mac_error:
    mov dx, msg_mac_err
    call print_string
    mov byte [mac_address+0], 00h
    mov byte [mac_address+1], 15h
    mov byte [mac_address+2], 5Dh
    mov byte [mac_address+3], 03h
    mov byte [mac_address+4], 14h
    mov byte [mac_address+5], 0Ah
    mov si, mac_address
    call print_mac

.install:
    xor ax, ax
    mov es, ax
    mov bl, [int_num]
    xor bh, bh
    shl bx, 2
    
    cli
    mov ax, [es:bx]
    mov [original_int_off], ax
    mov ax, [es:bx+2]
    mov [original_int_seg], ax
    
    mov word [es:bx], packet_driver_handler
    mov word [es:bx+2], cs
    sti

    mov ax, 351Ch       ; Get Interrupt Vector 1Ch
    int 21h
    mov [orig_int1c_off], bx
    mov [orig_int1c_seg], es
    
    mov dx, timer_handler
    mov ax, 251Ch       ; Set Interrupt Vector 1Ch
    int 21h

    mov dx, msg_installed
    call print_string
    mov al, [int_num]
    call print_hex_byte
    mov dx, msg_newline
    call print_string

    mov ax, resident_end
    sub ax, 100h
    add ax, 15
    shr ax, 4
    add ax, 11h
    
    mov dx, ax
    mov ax, 3100h       ; TSR
    int 21h

; --- IMPRESSÃO AUXILIAR (DOS) ---
print_string:
    mov ah, 09h
    int 21h
    ret

print_hex_byte:
    push ax
    push dx
    push ax
    shr al, 4
    call print_nibble
    pop ax
    and al, 0Fh
    call print_nibble
    pop dx
    pop ax
    ret

print_nibble:
    and al, 0Fh
    add al, '0'
    cmp al, '9'
    jbe .ok
    add al, 7
.ok:
    mov dl, al
    mov ah, 02h
    int 21h
    ret

print_hex_word:
    push ax
    mov al, ah
    call print_hex_byte
    pop ax
    call print_hex_byte
    ret

print_mac:
    mov cx, 5
.loop:
    lodsb
    call print_hex_byte
    mov dl, ':'
    mov ah, 02h
    int 21h
    loop .loop
    lodsb
    call print_hex_byte
    mov dx, msg_newline
    call print_string
    ret

; --- PARSER AUXILIAR ---
parse_hex_byte:
    push bx
    xor bx, bx
    
    lodsb
    call char_to_nibble
    jc .error
    shl al, 4
    mov bl, al
    
    lodsb
    call char_to_nibble
    jc .error
    or bl, al
    
    mov al, bl
    pop bx
    clc
    ret
.error:
    pop bx
    stc
    ret

char_to_nibble:
    cmp al, '0'
    jb .not_num
    cmp al, '9'
    jbe .num
    cmp al, 'a'
    jb .check_upper
    cmp al, 'f'
    jbe .lower
.check_upper:
    cmp al, 'A'
    jb .invalid
    cmp al, 'F'
    jbe .upper
.invalid:
    stc
    ret
.num:
    sub al, '0'
    clc
    ret
.lower:
    sub al, 'a'
    add al, 10
    clc
    ret
.upper:
    sub al, 'A'
    add al, 10
    clc
    ret
.not_num:
    stc
    ret

; --- BUSCA DA ESTRUTURA PXE ---
find_pxe_struct:
    ; Tenta primeiro via chamada oficial do BIOS (INT 1Ah AX=5650h)
    mov ax, 5650h
    xor bx, bx
    int 1Ah
    jc .scan_pxe          ; Se carry flag setado, nao suportado -> scan manual
    cmp ax, 564Eh         ; AX deve ser 'VN' (0x564E)
    jne .scan_pxe
    
    ; Validar assinatura da estrutura apontada por ES:BX
    cmp dword [es:bx], 4E455850h    ; 'PXEN'
    jne .scan_pxe
    cmp word [es:bx+4], 2B56h       ; 'V+'
    jne .scan_pxe
    
    ; Encontrou via BIOS!
    mov byte [pxe_found], 1
    mov [pxe_seg], es
    mov ax, [es:bx+0Ah]
    mov [undi_entry_off], ax
    mov ax, [es:bx+0Ch]
    mov [undi_entry_seg], ax
    ret

.scan_pxe:
    mov ax, 1000h
.loop_pxe:
    mov es, ax
    xor di, di
    cmp dword [es:di], 45585021h    ; '!PXE'
    je .found_pxe
    inc ax
    cmp ax, 0FFFFh
    jb .loop_pxe

    mov ax, 1000h
.loop_pxenv:
    mov es, ax
    xor di, di
    cmp dword [es:di], 4E455850h    ; 'PXEN'
    jne .next_pxenv
    cmp word [es:di+4], 2B56h       ; 'V+'
    je .found_pxenv
.next_pxenv:
    inc ax
    cmp ax, 0FFFFh
    jb .loop_pxenv
    ret

.found_pxe:
    mov byte [pxe_found], 1
    mov [pxe_seg], ax
    mov bx, [es:di+10h]
    mov [undi_entry_off], bx
    mov bx, [es:di+12h]
    mov [undi_entry_seg], bx
    ret

.found_pxenv:
    mov byte [pxe_found], 1
    mov [pxe_seg], ax
    mov bx, [es:di+0Ah]
    mov [undi_entry_off], bx
    mov bx, [es:di+0Ch]
    mov [undi_entry_seg], bx
    ret

call_pxe:
    push bp
    mov bp, sp
    push ds
    push es
    
    push cs
    push dx
    push bx
    call far [cs:undi_entry_off]
    add sp, 6
    
    pop es
    pop ds
    
    cmp ax, 0
    je .success
    stc
    jmp .done
.success:
    clc
.done:
    pop bp
    ret

; --- DADOS DA INICIALIZACAO ---
align 4
undi_info_block:
    .Status:             dw 0
    .BaseIo:             dw 0
    .IntNumber:          dw 0
    .MaxTranUnit:        dw 0
    .HwType:             dw 0
    .HwAddrLen:          dw 0
    .CurrentNodeAddress: times 6 db 0
    .PermNodeAddress:    times 6 db 0
    .ROMAddress:         dw 0
    .RxBufCt:            dw 0
    .TxBufCt:            dw 0

    msg_hello       db '=== INSTALADOR DO MLX_PKT DRIVER (MELLANOX DOS) ===', 0Dh, 0Ah, '$'
    msg_no_pxe      db '[-] ERRO: Interface PXE/UNDI nao encontrada na memoria.', 0Dh, 0Ah
                    db '    Certifique-se de que o FlexBoot da Mellanox rodou no boot.', 0Dh, 0Ah, '$'
    msg_pxe_found   db '[+] Interface PXE/UNDI detectada com sucesso em: ', '$'
    msg_installed   db '[+] Driver instalado com sucesso no vetor de interrupcao: 0x', '$'
    msg_newline     db 0Dh, 0Ah, '$'
    msg_mac_ok      db '[+] Endereco MAC obtido via UNDI: ', '$'
    msg_mac_err     db '[-] Nao foi possivel obter o MAC via UNDI. Usando MAC ficticio: ', '$'
