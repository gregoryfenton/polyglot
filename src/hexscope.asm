; ============================================================================
; HEXSCOPE 1.1
; DOS 6.22 COM / Linux x86-64 ELF polyglot
;
; Build:
;   nasm -f bin dosandlx.asm -o runme.com
;
; Run:
;   DOS:   RUNME filename
;   Linux: ./runme.com filename
;
; Keys:
;   Left/Right     Previous/next byte
;   Up/Down        Previous/next row
;   Home/End       First/last byte of file
;   PgUp/PgDn      Previous/next 256-byte page
;   Q/Esc          Quit
; ============================================================================

BITS 16
ORG 0x400000

ehdr:
    db 0x7F,"ELF",2,1,1,0
    times 8 db 0
    dw 2
    dw 0x3E
    dd 1
    dq linux_start
    dq phdr-$$
    dq 0
    dd 0
    dw 64,56,1
    dw 0,0,0

times 0x47-($-$$) db 0
    jmp dos_start

times 0x68-($-$$) db 0

BITS 64
phdr:
    dd 1,7
    dq 0
    dq 0x400000
    dq 0x400000
    dq filesize
    dq filesize
    dq 0x1000

; ============================================================================
; LINUX
; ============================================================================

linux_start:
    mov rax,[rsp]
    cmp rax,2
    jb linux_usage

    mov rdi,-100
    mov rsi,[rsp+16]
    xor edx,edx
    xor r10d,r10d
    mov eax,257
    syscall
    test rax,rax
    js linux_error
    mov [rel linux_fd],eax

    mov edi,eax
    xor esi,esi
    mov edx,2
    mov eax,8
    syscall
    test rax,rax
    js linux_error
    mov [rel linux_file_size],rax

    mov edi,[rel linux_fd]
    xor esi,esi
    xor edx,edx
    mov eax,8
    syscall

    mov eax,16
    xor edi,edi
    mov esi,0x5401
    lea rdx,[rel old_termios]
    syscall
    test rax,rax
    js linux_error

    lea rsi,[rel old_termios]
    lea rdi,[rel new_termios]
    mov ecx,36
    rep movsb

    and dword [rel new_termios+12],~10
    mov byte [rel new_termios+22],1
    mov byte [rel new_termios+23],0

    mov eax,16
    xor edi,edi
    mov esi,0x5402
    lea rdx,[rel new_termios]
    syscall

    mov byte [rel terminal_active],1
    mov dword [rel selected_offset],0
    mov dword [rel page_offset],0
    
    call linux_clear_screen

    call linux_load_page
    call linux_heading
    mov dword [rel last_selected_index],0xffffffff
    call linux_render_page
    call linux_info
    call linux_update_selection

.linux_keys:
    call linux_getkey

    cmp eax,27
    je .linux_quit
    cmp eax,'q'
    je .linux_quit
    cmp eax,'Q'
    je .linux_quit

    cmp eax,1
    je .linux_left
    cmp eax,2
    je .linux_right
    cmp eax,3
    je .linux_up
    cmp eax,4
    je .linux_down
    cmp eax,5
    je .linux_home
    cmp eax,6
    je .linux_end
    cmp eax,7
    je .linux_pgup
    cmp eax,8
    je .linux_pgdn
    jmp .linux_keys

.linux_left:
    cmp dword [rel selected_offset],0
    je .linux_keys
    dec dword [rel selected_offset]
    jmp .linux_move

.linux_right:
    mov eax,[rel selected_offset]
    inc eax
    cmp rax,[rel linux_file_size]
    jae .linux_keys
    mov [rel selected_offset],eax
    jmp .linux_move

.linux_up:
    mov eax,[rel selected_offset]
    cmp eax,16
    jb .linux_keys
    sub eax,16
    mov [rel selected_offset],eax
    jmp .linux_move

.linux_down:
    mov eax,[rel selected_offset]
    add eax,16
    cmp rax,[rel linux_file_size]
    jae .linux_keys
    mov [rel selected_offset],eax
    jmp .linux_move

.linux_home:
    xor eax, eax
    mov [rel selected_offset],eax
    jmp .linux_move

.linux_end:
    mov rax,[rel linux_file_size]
    test rax,rax
    jz .linux_keys
    dec eax
    mov [rel selected_offset],eax
    jmp .linux_page_check

.linux_pgup:
    mov eax,[rel selected_offset]
    cmp eax,256
    jb .linux_keys
    sub eax,256
    mov [rel selected_offset],eax
    jmp .linux_page_check

.linux_pgdn:
    mov eax,[rel selected_offset]
    add eax,256
    cmp rax,[rel linux_file_size]
    jae .linux_keys
    mov [rel selected_offset],eax
    jmp .linux_page_check

.linux_page_check:
    mov eax,[rel selected_offset]
    and eax,0xffffff00
    cmp eax,[rel page_offset]
    je .linux_update_only

    mov [rel page_offset],eax
    call linux_load_page
    call linux_render_page
    mov dword [rel last_selected_index],0xffffffff
    call linux_info
    call linux_update_selection
    jmp .linux_keys

.linux_move:
    jmp .linux_page_check

.linux_update_only:
    call linux_info
    call linux_update_selection
    jmp .linux_keys

.linux_quit:
    call linux_restore
    mov edi,[rel linux_fd]
    mov eax,3
    syscall
    xor edi,edi
    mov eax,60
    syscall

linux_getkey:
    lea rsi,[rel keybuf]
    mov edx,1
    xor edi,edi
    xor eax,eax
    syscall
    test rax,rax
    jle .none

    movzx eax,byte [rel keybuf]
    cmp al,27
    jne .return

    lea rsi,[rel keybuf]
    mov edx,1
    xor edi,edi
    xor eax,eax
    syscall
    cmp byte [rel keybuf],'['
    jne .escape

    lea rsi,[rel keybuf]
    mov edx,1
    xor edi,edi
    xor eax,eax
    syscall

    mov al,[rel keybuf]
    cmp al,'A'
    je .up
    cmp al,'B'
    je .down
    cmp al,'C'
    je .right
    cmp al,'D'
    je .left
    cmp al,'H'
    je .home
    cmp al,'F'
    je .end
    cmp al,'5'
    je .pageup
    cmp al,'6'
    je .pagedown
    jmp .none

.up:       mov eax,3
           ret
.down:     mov eax,4
           ret
.right:    mov eax,2
           ret
.left:     mov eax,1
           ret
.home:     mov eax,5
           ret
.end:      mov eax,6
           ret
.pageup:   mov eax,7
           ret
.pagedown: mov eax,8
           ret
.escape:   mov eax,27
           ret
.return:
    ret
.none:
    xor eax,eax
    ret

linux_load_page:
    ; Clear the 256-byte file buffer first to prevent stale data
    push rdi
    push rcx
    lea rdi,[rel filebuf]
    xor eax,eax
    mov ecx,64          ; 64 dwords = 256 bytes
    rep stosd
    pop rcx
    pop rdi

    mov edi,[rel linux_fd]
    mov esi,[rel page_offset]
    xor edx,edx
    mov eax,8
    syscall

    lea rsi,[rel filebuf]
    mov edi,[rel linux_fd]
    mov edx,256
    xor eax,eax
    syscall
    test rax,rax
    js .bad
    mov [rel linux_count],eax
    ret
.bad:
    mov dword [rel linux_count],0
    ret
    
linux_heading:
    lea rsi,[rel heading_text]
    mov edx,heading_len
    jmp linux_write

linux_render_page:
    mov eax,4
    call linux_goto_row

    xor ebx,ebx
.row:
    cmp ebx,16
    jae .done

    mov eax,[rel page_offset]
    mov ecx,ebx
    shl ecx,4
    add eax,ecx
    call linux_hex32

    mov al,' '
    call linux_char

    xor r12d,r12d
.first:
    cmp r12d,8
    jae .middle
    mov eax,ebx
    shl eax,4
    add eax,r12d
    call linux_emit_byte
    mov al,' '
    call linux_char
    inc r12d
    jmp .first

.middle:
    mov al,'-'
    call linux_char
    mov al,' '
    call linux_char
    mov r12d,8

.second:
    cmp r12d,16
    jae .ascii_start
    mov eax,ebx
    shl eax,4
    add eax,r12d
    call linux_emit_byte
    cmp r12d,15
    je .second_next
    mov al,' '
    call linux_char
.second_next:
    inc r12d
    jmp .second

.ascii_start:
    mov al,' '
    call linux_char
    mov al,'|'
    call linux_char
    xor r12d,r12d

.ascii_loop:
    cmp r12d,16
    jae .ascii_end
    mov eax,ebx
    shl eax,4
    add eax,r12d
    cmp eax,[rel linux_count]
    jae .blank
    lea rdx,[rel filebuf]
    movzx eax,byte [rdx+rax]
    cmp al,32
    jb .dot
    cmp al,126
    ja .dot
    call linux_char
    jmp .ascii_next
.dot:
    mov al,'.'
    call linux_char
    jmp .ascii_next
.blank:
    mov al,' '
    call linux_char
.ascii_next:
    inc r12d
    jmp .ascii_loop

.ascii_end:
    mov al,'|'
    call linux_char
    ; Clear from cursor to end of line to wipe any lingering artifacts
    mov al,27
    call linux_char
    mov al,'['
    call linux_char
    mov al,'K'
    call linux_char
    mov al,10
    call linux_char
    inc ebx
    jmp .row
.done:
    ret

linux_info:
    mov eax,21
    call linux_goto_row

    lea rsi,[rel selected_label]
    mov edx,selected_len
    call linux_write

    mov eax,[rel selected_offset]
    call linux_hex32

    mov al,':'
    call linux_char
    mov al,' '
    call linux_char

    mov eax,[rel selected_offset]
    sub eax,[rel page_offset]
    cmp eax,[rel linux_count]
    jae .empty

    lea rdx,[rel filebuf]
    movzx eax,byte [rdx+rax]
    mov [rel selected_value],al

    call linux_byte
    mov al,' '
    call linux_char

    movzx eax,byte [rel selected_value]
    call linux_decimal8
    mov al,' '
    call linux_char

    movzx eax,byte [rel selected_value]
    call linux_binary8
    
    mov al,' '
    call linux_char
    mov al,' '
    call linux_char
    lea rsi,[rel filesize_label]
    mov edx,filesize_label_len
    call linux_write
    mov eax,filesize
    call linux_hex32
    
    jmp .finish
.empty:
    mov al,'X'
    call linux_char
    mov al,'x'
    call linux_char
.finish:
    ; Clear remainder of info line and reset attributes
    mov al,27
    call linux_char
    mov al,'['
    call linux_char
    mov al,'K'
    call linux_char
    mov al,27
    call linux_char
    mov al,'['
    call linux_char
    mov al,'0'
    call linux_char
    mov al,'m'
    call linux_char
    ret
    
linux_update_selection:
    push rbx
    push r12
    mov eax,[rel last_selected_index]
    cmp eax,0xffffffff
    je .draw_new
    call linux_selection_coords
    mov ecx,' '
    call linux_put_at
    add ebx,3
    mov ecx,' '
    call linux_put_at
.draw_new:
    mov eax,[rel selected_offset]
    sub eax,[rel page_offset]
    cmp eax,[rel linux_count]
    jae .none
    mov [rel last_selected_index],eax
    call linux_selection_coords
    mov ecx,'['
    call linux_put_at
    add ebx,3
    mov ecx,']'
    call linux_put_at
    jmp .done
.none:
    mov dword [rel last_selected_index],0xffffffff
.done:
    pop r12
    pop rbx
    ret

linux_selection_coords:
    mov ebx,eax
    shr eax,4
    add eax,4
    and ebx,15
    mov ecx,ebx
    lea ebx,[rbx+rbx*2]
    add ebx,9
    cmp ecx,8
    jb .done
    add ebx,2
.done:
    ret

linux_put_at:
    push rax
    push rbx
    push rcx
    call linux_cursor_at
    pop rcx
    mov eax,ecx
    call linux_char
    pop rbx
    pop rax
    ret
    
linux_cursor_at:
    push rbx
    push r8
    mov r8d,ebx
    mov r9d,eax
    mov al,27
    call linux_char
    mov al,'['
    call linux_char
    mov eax,r9d
    call linux_two_digits
    mov al,';'
    call linux_char
    mov eax,r8d
    call linux_two_digits
    mov al,'H'
    call linux_char
    pop r8
    pop rbx
    ret

linux_two_digits:
    xor edx,edx
    mov ecx,10
    div ecx
    push rdx
    add al,'0'
    call linux_char
    pop rax
    add al,'0'
    call linux_char
    ret

linux_goto_row:
    push rax
    mov al,27
    call linux_char
    mov al,'['
    call linux_char
    pop rax
    call linux_two_digits
    mov al,';'
    call linux_char
    mov al,'1'
    call linux_char
    mov al,'H'
    call linux_char
    ret

linux_decimal:
    add al,'0'
    jmp linux_char

linux_write:
    mov eax,1
    mov edi,1
    syscall
    ret

linux_char:
    mov [rel charbuf],al
    lea rsi,[rel charbuf]
    mov edx,1
    mov eax,1
    mov edi,1
    syscall
    ret

linux_hex32:
    push rbx
    mov ebx,eax
    mov r8d,8
.loop:
    rol ebx,4
    mov eax,ebx
    and eax,15
    lea rdx,[rel hex_digits]
    mov al,[rdx+rax]
    call linux_char
    dec r8d
    jnz .loop
    pop rbx
    ret
    
linux_byte:
    push rax
    movzx eax,al
    shr eax,4
    lea rdx,[rel hex_digits]
    mov al,[rdx+rax]
    call linux_char
    pop rax
    and eax,15
    lea rdx,[rel hex_digits]
    mov al,[rdx+rax]
    call linux_char
    ret

linux_decimal8:
    xor edx,edx
    mov ebx,100
    div ebx
    add al,'0'
    call linux_char
    mov eax,edx
    xor edx,edx
    mov ebx,10
    div ebx
    push rdx
    add al,'0'
    call linux_char
    pop rax
    add al,'0'
    call linux_char
    ret

linux_binary8:
    mov r8d,8
.loop:
    shl al,1
    mov dl,'0'
    jnc .emit
    mov dl,'1'
.emit:
    push rax
    mov al,dl
    call linux_char
    pop rax
    dec r8d
    jnz .loop
    ret

linux_emit_byte:
    cmp eax,[rel linux_count]
    jae .empty
    lea rdx,[rel filebuf]
    movzx eax,byte [rdx+rax]
    jmp linux_byte
.empty:
    mov al,' '
    call linux_char
    mov al,' '
    call linux_char
    ret

linux_restore:
    cmp byte [rel terminal_active],0
    je .done
    mov eax,16
    xor edi,edi
    mov esi,0x5402
    lea rdx,[rel old_termios]
    syscall
    mov byte [rel terminal_active],0
.done:
    ret

linux_usage:
    lea rsi,[rel usage_text]
    mov edx,usage_len
    call linux_write
    mov edi,1
    jmp linux_exit

linux_error:
    call linux_restore
    lea rsi,[rel error_text]
    mov edx,error_len
    call linux_write
    mov edi,1
linux_exit:
    mov eax,60
    syscall

linux_clear_screen:
    lea rsi,[rel clear_screen_text]
    mov edx,clear_screen_len
    jmp linux_write

heading_text:
    db "HexScope 1.1 *READ ONLY* By Gregory Fenton, polyglot DOS and Linux version",10
    db "Offset   00 01 02 03 04 05 06 07 - 08 09 0A 0B 0C 0D 0E 0F  Character",10
    db "-------- ----------------------- - ----------------------- ------------------",10
heading_len equ $-heading_text

selected_label:
    db "Selected byte "
selected_len equ $-selected_label

filesize_label:
	db "File size: "
filesize_label_len equ $ - filesize_label

usage_text:
    db "Usage: runme.com filename",10
usage_len equ $-usage_text

error_text:
    db "HEXSCOPE: unable to open or read file",10
error_len equ $-error_text

hex_digits:
    db "0123456789ABCDEF"

clear_screen_text:
    db 27,"[2J",27,"[H"
clear_screen_len equ $-clear_screen_text

linux_fd:          dd 0
linux_count:       dd 0
linux_file_size:         dq 0
selected_offset:   dd 0
page_offset:       dd 0
selected_value:    db 0
last_selected_index: dd 0xffffffff
charbuf:           db 0
keybuf:            db 0
terminal_active:   db 0
old_termios:       times 36 db 0
new_termios:       times 36 db 0
align 16
filebuf:           times 256 db 0

; ============================================================================
; DOS
; ============================================================================

BITS 16
%define D(x) (x-$$+0x100)

dos_start:
    push cs
    pop ds
    push cs
    pop es

    mov ax,3
    int 10h

    mov ax,0B800h
    mov es,ax
    mov word [D(screen_pos)],0

    mov si,81h
    xor cx,cx
    mov cl,[80h]
.skip:
    or cx,cx
    jnz .have_char
    jmp dos_usage
.have_char:
    lodsb
    dec cx
    cmp al,' '
    je .skip
    cmp al,13
    je dos_usage

    mov di,D(filename)
.copy:
    cmp al,' '
    je .name_done
    cmp al,13
    je .name_done
    mov [di],al
    inc di
    jcxz .name_done
    lodsb
    dec cx
    jmp .copy
.name_done:
    mov byte [di],0

    mov dx,D(filename)
    mov ax,3D00h
    int 21h
    jc dos_error
    mov [D(file_handle)],ax

    mov bx,ax
    mov ax,4202h
    xor cx,cx
    xor dx,dx
    int 21h
    jc dos_error
    mov [D(dos_file_size)],ax
    mov [D(dos_file_size+2)],dx

    mov bx,[D(file_handle)]
    mov ax,4200h
    xor cx,cx
    xor dx,dx
    int 21h

    mov dword [D(selected_offset)],0
    mov dword [D(page_offset)],0

    call dos_load_page
    call dos_heading
    mov word [D(last_selected_index)],0xffff
    call dos_render_page
    call dos_info
    call dos_update_selection

.dos_keys:
    xor ah,ah
    int 16h

    cmp al,27
    je dos_quit
    cmp al,'q'
    je dos_quit
    cmp al,'Q'
    je dos_quit

    cmp ah,4Bh
    je .dos_left
    cmp ah,4Dh
    je .dos_right
    cmp ah,48h
    je .dos_up
    cmp ah,50h
    je .dos_down
    cmp ah,47h
    je .dos_home
    cmp ah,4Fh
    je .dos_end
    cmp ah,49h
    je .dos_pgup
    cmp ah,51h
    je .dos_pgdn
    jmp .dos_keys

.dos_left:
    mov ax,[D(selected_offset)]
    mov dx,[D(selected_offset+2)]
    or ax,dx
    jz .again
    sub word [D(selected_offset)],1
    sbb word [D(selected_offset+2)],0
    jmp .page_check

.dos_right:
    mov ax,[D(selected_offset)]
    mov dx,[D(selected_offset+2)]
    add ax,1
    adc dx,0
    mov [D(temp_offset)],ax
    mov [D(temp_offset+2)],dx
    call dos_check_eof
    jc .again
    mov ax,[D(temp_offset)]
    mov dx,[D(temp_offset+2)]
    mov [D(selected_offset)],ax
    mov [D(selected_offset+2)],dx
    jmp .page_check

.dos_up:
    mov ax,[D(selected_offset)]
    mov dx,[D(selected_offset+2)]
    cmp dx,0
    jne .dos_up_ok
    cmp ax,16
    jb .again
.dos_up_ok:
    sub ax,16
    sbb dx,0
    mov [D(selected_offset)],ax
    mov [D(selected_offset+2)],dx
    jmp .page_check

.dos_down:
    mov ax,[D(selected_offset)]
    mov dx,[D(selected_offset+2)]
    add ax,16
    adc dx,0
    mov [D(temp_offset)],ax
    mov [D(temp_offset+2)],dx
    call dos_check_eof
    jc .again
    mov ax,[D(temp_offset)]
    mov dx,[D(temp_offset+2)]
    mov [D(selected_offset)],ax
    mov [D(selected_offset+2)],dx
    jmp .page_check

.dos_home:
    mov word [D(selected_offset)],0
    mov word [D(selected_offset+2)],0
    jmp .page_check

.dos_end:
    mov ax,[D(dos_file_size)]
    mov dx,[D(dos_file_size+2)]
    or ax,dx
    jz .again
    sub ax,1
    sbb dx,0
    mov [D(selected_offset)],ax
    mov [D(selected_offset+2)],dx
    jmp .page_check

.dos_pgup:
    mov ax,[D(selected_offset)]
    mov dx,[D(selected_offset+2)]
    cmp dx,0
    jne .dos_pgup_ok
    cmp ax,256
    jb .again
.dos_pgup_ok:
    sub ax,256
    sbb dx,0
    mov [D(selected_offset)],ax
    mov [D(selected_offset+2)],dx
    jmp .page_check

.dos_pgdn:
    mov ax,[D(selected_offset)]
    mov dx,[D(selected_offset+2)]
    add ax,256
    adc dx,0
    mov [D(temp_offset)],ax
    mov [D(temp_offset+2)],dx
    call dos_check_eof
    jc .again
    mov ax,[D(temp_offset)]
    mov dx,[D(temp_offset+2)]
    mov [D(selected_offset)],ax
    mov [D(selected_offset+2)],dx

.page_check:
    mov ax,[D(selected_offset)]
    mov dx,[D(selected_offset+2)]
    and al,0
    mov [D(new_page)],ax
    mov [D(new_page+2)],dx
    mov ax,[D(new_page)]
    mov dx,[D(new_page+2)]
    cmp ax,[D(page_offset)]
    jne .new_page
    cmp dx,[D(page_offset+2)]
    je .update_only

.new_page:
    mov ax,[D(new_page)]
    mov dx,[D(new_page+2)]
    mov [D(page_offset)],ax
    mov [D(page_offset+2)],dx
    call dos_load_page
    call dos_render_page
    mov word [D(last_selected_index)],0xffff
    call dos_info
    call dos_update_selection
    jmp .again

.update_only:
    call dos_info
    call dos_update_selection

.again:
    jmp .dos_keys

dos_check_eof:
    mov ax,[D(temp_offset)]
    mov dx,[D(temp_offset+2)]
    cmp dx,[D(dos_file_size+2)]
    ja .past
    jb .valid
    cmp ax,[D(dos_file_size)]
    jae .past
.valid:
    clc
    ret
.past:
    stc
    ret

dos_load_page:
    mov bx,[D(file_handle)]
    mov ax,[D(page_offset)]
    mov dx,[D(page_offset+2)]
    mov cx,dx
    mov dx,ax
    mov ax,4200h
    int 21h

    mov bx,[D(file_handle)]
    mov dx,D(filebuf)
    mov cx,256
    mov ah,3Fh
    int 21h
    jc .bad
    mov [D(file_count)],ax
    ret
.bad:
    mov word [D(file_count)],0
    ret

dos_heading:
    mov si,D(heading_text)
.loop:
    lodsb
    or al,al
    jz .done
    cmp al,10
    je .nl
    call dos_putc
    jmp .loop
.nl:
    call dos_newline
    jmp .loop
.done:
    ret

dos_render_page:
    mov word [D(screen_pos)],480
    xor bp,bp
.row:
    cmp bp,16
    jae .done

    ; Load 32-bit page_offset into DX:AX
    mov ax,[D(page_offset)]
    mov dx,[D(page_offset+2)]

    ; Add row offset (bp * 16)
    mov cx,bp
    shl cx,4
    add ax,cx
    adc dx,0            ; Propagate carry to high word

    call dos_hex32      ; Prints correct 32-bit row offset

    mov al,' '
    call dos_putc
    
    xor di,di
.first:
    cmp di,8
    jae .middle
    mov ax,bp
    shl ax,4
    add ax,di
    call dos_emit_byte
    mov al,' '
    call dos_putc
    inc di
    jmp .first
.middle:
    mov al,'-'
    call dos_putc
    mov al,' '
    call dos_putc
    mov di,8
.second:
    cmp di,16
    jae .ascii_start
    mov ax,bp
    shl ax,4
    add ax,di
    call dos_emit_byte
    cmp di,15
    je .second_next
    mov al,' '
    call dos_putc
.second_next:
    inc di
    jmp .second
.ascii_start:
    mov al,' '
    call dos_putc
    mov al,'|'
    call dos_putc
    xor di,di
.ascii:
    cmp di,16
    jae .ascii_end
    mov ax,bp
    shl ax,4
    add ax,di
    cmp ax,[D(file_count)]
    jae .blank
    mov si,D(filebuf)
    add si,ax
    mov al,[si]
    call dos_putc
    jmp .ascii_next
.blank:
    mov al,' '
    call dos_putc
.ascii_next:
    inc di
    jmp .ascii
.ascii_end:
    mov al,'|'
    call dos_putc
    call dos_newline
    inc bp
    jmp .row
.done:
    ret

dos_update_selection:
    push ax
    push bx
    push cx
    push dx
    push di
    mov ax,[D(last_selected_index)]
    cmp ax,0xffff
    je .dos_draw_new
    call dos_bracket_offset
    mov word [es:di],0720h
    mov word [es:di+6],0720h
.dos_draw_new:
    mov ax,[D(selected_offset)]
    sub ax,[D(page_offset)]
    cmp ax,[D(file_count)]
    jae .none
    mov [D(last_selected_index)],ax
    call dos_bracket_offset
    mov word [es:di],075bh
    mov word [es:di+6],075dh
    jmp .done
.none:
    mov word [D(last_selected_index)],0xffff
.done:
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

dos_bracket_offset:
    push bx
    push cx
    push dx

    mov bx,ax

    mov dx,ax
    and dx,0fff0h
    shr dx,4
    mov ax,dx
    shl ax,7
    mov cx,dx
    shl cx,5
    add ax,cx
    add ax,480

    and bx,15
    mov dx,bx
    shl dx,1
    add dx,bx
    add dx,8

    cmp bx,8
    jb .column
    add dx,2

.column:
    shl dx,1
    add ax,dx
    mov di,ax

    pop dx
    pop cx
    pop bx
    ret

dos_info:
    mov word [D(screen_pos)],3200
    mov si,D(selected_label)
    mov cx, selected_len
.label:
    lodsb
    call dos_putc
    dec cx
    jnz .label

    mov dx,[D(selected_offset+2)]
    mov ax,[D(selected_offset)]
    call dos_hex32
    mov al,':'
    call dos_putc
    mov al,' '
    call dos_putc

    mov ax,[D(selected_offset)]
    sub ax,[D(page_offset)]
    cmp ax,[D(file_count)]
    jae .empty
    mov si,D(filebuf)
    add si,ax
    mov al,[si]
    mov [D(selected_value)],al
    call dos_hex8
    mov al,' '
    call dos_putc
    mov al,[D(selected_value)]
    call dos_decimal8
    mov al,' '
    call dos_putc
    mov al,[D(selected_value)]
    call dos_binary8
    
    ; File size output
    mov al,' '
    call dos_putc
    mov al,' '
    call dos_putc
    mov si,D(filesize_label)
    mov cx, filesize_label_len
.filesizelabel:
    lodsb
    call dos_putc
    dec cx
    jnz .filesizelabel

    mov dx,[D(dos_file_size+2)]
    mov ax,[D(dos_file_size)]
    call dos_hex32
    ret
.empty:
    mov al,'-'
    call dos_putc
    call dos_putc
    ret
    
dos_putc:
    push ax
    push di
    mov di,[D(screen_pos)]
    mov ah,07h
    mov [es:di],ax
    add di,2
    mov [D(screen_pos)],di
    pop di
    pop ax
    ret

dos_newline:
    push ax
    push bx
    push dx
    mov ax,[D(screen_pos)]
    xor dx,dx
    mov bx,160
    div bx
    inc ax
    mul bx
    mov [D(screen_pos)],ax
    pop dx
    pop bx
    pop ax
    ret

dos_hex32:
    push ax
    mov ax, dx
    call dos_hex16
    pop ax
    call dos_hex16
    ret
    
dos_hex16:
    push ax
    mov al,ah
    call dos_hex8
    pop ax
    jmp dos_hex8

dos_hex8:
    push ax
    mov ah,al
    shr al,4
    call dos_nibble
    mov al,ah
    and al,15
    call dos_nibble
    pop ax
    ret

dos_nibble:
    push bx
    xor bh,bh
    mov bl,al
    mov al,[D(hex_digits)+bx]
    call dos_putc
    pop bx
    ret

dos_decimal8:
    push ax
    push bx
    push dx
    xor ah,ah
    xor dx,dx
    mov bx,100
    div bx
    add al,'0'
    call dos_putc
    mov ax,dx
    xor dx,dx
    mov bx,10
    div bx
    push dx
    add al,'0'
    call dos_putc
    pop dx
    mov al,dl
    add al,'0'
    call dos_putc
    pop dx
    pop bx
    pop ax
    ret

dos_binary8:
    push ax
    push cx
    push dx
    mov cx,8
.loop:
    shl al,1
    mov dl,'0'
    jnc .emit
    mov dl,'1'
.emit:
    push ax
    mov al,dl
    call dos_putc
    pop ax
    loop .loop
    pop dx
    pop cx
    pop ax
    ret

dos_emit_byte:
    cmp ax,[D(file_count)]
    jae .empty
    push ax
    mov si,D(filebuf)
    add si,ax
    mov al,[si]
    call dos_hex8
    pop ax
    ret
.empty:
    mov al,'-'
    call dos_putc
    call dos_putc
    ret

dos_error:
    mov si,D(error_text)
    call dos_print
    mov ax,4C01h
    int 21h

dos_usage:
    mov si,D(usage_text)
    call dos_print
    mov ax,4C01h
    int 21h

dos_print:
    lodsb
    or al,al
    jz .done
    cmp al,10
    je .nl
    call dos_putc
    jmp dos_print
.nl:
    call dos_newline
    jmp dos_print
.done:
    ret

dos_quit:
    mov bx,[D(file_handle)]
    mov ah,3Eh
    int 21h
    mov ax,4C00h
    int 21h

filename:          times 128 db 0
file_handle:       dw 0
file_count:        dw 0
dos_file_size:         dd 0
new_page:          dd 0
temp_offset:       dd 0
screen_pos:        dw 0

filesize equ $-$$
