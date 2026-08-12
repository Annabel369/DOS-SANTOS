org 100h            ; Programas .COM comecam no offset 0x100 no DOS

section .text

start:
    ; Imprime a mensagem de inicio
    mov dx, msg_start
    call print_string

    ; 1. Verificar se a BIOS PCI existe
    mov ax, 0B101h  ; PCI BIOS Present?
    int 1Ah
    jc no_pci_bios  ; Se Carry Flag setado, nao ha BIOS PCI
    cmp ah, 0       ; Se AH != 0, falhou
    jne no_pci_bios

    ; BIOS PCI encontrada!
    mov dx, msg_pci_ok
    call print_string

    ; Imprime o cabecalho da tabela
    mov dx, msg_header1
    call print_string
    mov dx, msg_header2
    call print_string

    ; Inicializa contadores
    mov word [total_devices], 0
    mov word [mellanox_count], 0
    mov byte [line_count], 0
    mov byte [cur_bus], 0

bus_loop:
    mov byte [cur_dev], 0

dev_loop:
    ; Verifica a Funcao 0 primeiro
    mov byte [cur_func], 0
    call check_device_func
    cmp ax, 0FFFFh          ; Se a Funcao 0 nao existe, pula o dispositivo
    je next_device

    ; Funcao 0 existe! Agora varre as funcoes 1 a 7
    mov byte [cur_func], 1
func_loop:
    call check_device_func
    inc byte [cur_func]
    cmp byte [cur_func], 8
    jb func_loop

next_device:
    inc byte [cur_dev]
    cmp byte [cur_dev], 32
    jb dev_loop

    inc byte [cur_bus]
    cmp byte [cur_bus], 0   ; Volta a zero apos 255 (pois eh um byte)
    jne bus_loop

    ; --- FIM DA VARREDURA ---
    ; Imprime o resumo
    mov dx, msg_summary_start
    call print_string

    mov ax, [total_devices]
    call print_dec_word

    mov dx, msg_summary_mid
    call print_string

    mov ax, [mellanox_count]
    call print_dec_word

    mov dx, msg_summary_end
    call print_string

    ; Se encontrou Mellanox, exibe sucesso, senao erro
    cmp word [mellanox_count], 0
    ja mellanox_found_success

    mov dx, msg_no_mellanox
    call print_string
    jmp exit

mellanox_found_success:
    mov dx, msg_mellanox_ok
    call print_string
    jmp exit

no_pci_bios:
    mov dx, msg_no_pci
    call print_string

exit:
    ; Encerrar programa e voltar ao DOS
    mov ax, 4C00h
    int 21h


; --- FUNCOES AUXILIARES ---

check_device_func:
    ; BH = Bus
    ; BL = (Device << 3) | Function
    ; DI = 0 (Register 0: Vendor ID)
    mov bh, [cur_bus]
    mov al, [cur_dev]
    shl al, 3
    or al, [cur_func]
    mov bl, al
    mov di, 0
    mov ax, 0B109h          ; Read Config Word
    int 1Ah
    
    jc .not_found
    cmp ah, 0
    jne .not_found
    cmp cx, 0FFFFh
    je .not_found

    mov [temp_vendor], cx

    ; Ler Device ID (Register 2)
    mov bh, [cur_bus]
    mov al, [cur_dev]
    shl al, 3
    or al, [cur_func]
    mov bl, al
    mov di, 2
    mov ax, 0B109h          ; Read Config Word
    int 1Ah
    jc .no_dev_id
    cmp ah, 0
    jne .no_dev_id
    mov [temp_device], cx
    jmp .read_class

.no_dev_id:
    mov word [temp_device], 0FFFFh

.read_class:
    ; Ler Class Code (Register 0Ah)
    mov bh, [cur_bus]
    mov al, [cur_dev]
    shl al, 3
    or al, [cur_func]
    mov bl, al
    mov di, 0Ah
    mov ax, 0B109h          ; Read Config Word
    int 1Ah
    jc .no_class
    cmp ah, 0
    jne .no_class
    mov [temp_class], cx
    jmp .process

.no_class:
    mov word [temp_class], 0000h

.process:
    inc word [total_devices]
    call print_device

    ; Verifica se eh Mellanox (Vendor ID = 15B3h)
    cmp word [temp_vendor], 15B3h
    jne .done
    inc word [mellanox_count]

.done:
    mov ax, [temp_vendor]
    ret

.not_found:
    mov ax, 0FFFFh
    ret


print_device:
    push ax
    push bx
    push cx
    push dx

    inc byte [line_count]

    ; Verifica se eh Mellanox
    cmp word [temp_vendor], 15B3h
    je .mellanox

    mov dx, msg_prefix_normal
    call print_string
    jmp .print_body

.mellanox:
    mov dx, msg_prefix_mellanox
    call print_string

.print_body:
    ; Print Bus
    mov al, [cur_bus]
    call print_hex_byte

    mov dx, msg_space_bus_dev
    call print_string

    ; Print Dev
    mov al, [cur_dev]
    call print_hex_byte

    mov dx, msg_space_dev_func
    call print_string

    ; Print Func
    mov al, [cur_func]
    add al, '0'
    mov dl, al
    mov ah, 02h
    int 21h

    mov dx, msg_divider_func
    call print_string

    ; Print Vendor ID
    mov ax, [temp_vendor]
    call print_hex_word

    mov dx, msg_space_ven_dev
    call print_string

    ; Print Device ID
    mov ax, [temp_device]
    call print_hex_word

    mov dx, msg_divider_class
    call print_string

    ; Print Class Code
    mov ax, [temp_class]
    call print_hex_word

    ; Se Mellanox, imprime o sufixo
    cmp word [temp_vendor], 15B3h
    jne .end_line

    mov dx, msg_mellanox_suffix
    call print_string

.end_line:
    mov dx, msg_newline
    call print_string

    ; Verifica se precisa pausar (22 linhas para aproveitar melhor a tela de 25)
    cmp byte [line_count], 22
    jb .done

    mov dx, msg_pause
    call print_string
    
    mov ah, 00h
    int 16h

    mov dx, msg_clear_pause
    call print_string

    mov byte [line_count], 0

.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret


print_string:
    mov ah, 09h
    int 21h
    ret


print_hex_byte:
    push ax
    push dx
    
    ; Imprime o nibble alto (shift right 4 bits)
    push ax
    shr al, 4
    call print_nibble
    pop ax
    
    ; Imprime o nibble baixo
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


print_dec_word:
    push ax
    push bx
    push cx
    push dx
    mov bx, 10
    xor cx, cx
.div_loop:
    xor dx, dx
    div bx
    push dx
    inc cx
    or ax, ax
    jnz .div_loop
.print_loop:
    pop dx
    add dl, '0'
    mov ah, 02h
    int 21h
    loop .print_loop
    pop dx
    pop cx
    pop bx
    pop ax
    ret


section .data
    msg_start           db '=== ANALISADOR DE BARRAMENTO PCI DOS (NASM) ===', 0Dh, 0Ah, '$'
    msg_pci_ok          db '[+] BIOS PCI detectada no sistema.', 0Dh, 0Ah, '$'
    msg_no_pci          db '[-] ERRO: BIOS PCI nao encontrada ou nao suportada.', 0Dh, 0Ah, '$'
    
    msg_header1         db '  Bus Dev Fnc  | Vendor Device | Class', 0Dh, 0Ah, '$'
    msg_header2         db '  -------------+---------------+------', 0Dh, 0Ah, '$'
    
    msg_prefix_normal   db '  ', '$'
    msg_prefix_mellanox db '* ', '$'
    msg_space_bus_dev   db '  ', '$'
    msg_space_dev_func  db '  ', '$'
    msg_divider_func    db '    | ', '$'
    msg_space_ven_dev   db '     ', '$'
    msg_divider_class   db ' | ', '$'
    msg_mellanox_suffix db '  [MELLANOX]', '$'
    msg_newline         db 0Dh, 0Ah, '$'
    
    msg_pause           db 0Dh, '-- Pressione qualquer tecla para continuar --', '$'
    msg_clear_pause     db 0Dh, '                                             ', 0Dh, '$'

    msg_summary_start   db 0Dh, 0Ah, '=== RESUMO DA VARREDURA ===', 0Dh, 0Ah
                        db 'Total de dispositivos PCI encontrados: ', '$'
    msg_summary_mid     db 0Dh, 0Ah, 'Dispositivos Mellanox encontrados:     ', '$'
    msg_summary_end     db 0Dh, 0Ah, '$'
    msg_mellanox_ok     db '[+] SUCESSO: Placa Mellanox detectada e listada acima!', 0Dh, 0Ah, '$'
    msg_no_mellanox     db '[-] ERRO: Nenhuma placa Mellanox (Vendor ID 15B3) foi encontrada.', 0Dh, 0Ah, '$'

    cur_bus             db 0
    cur_dev             db 0
    cur_func            db 0
    line_count          db 0

    total_devices       dw 0
    mellanox_count      dw 0
    temp_vendor         dw 0
    temp_device         dw 0
    temp_class          dw 0
