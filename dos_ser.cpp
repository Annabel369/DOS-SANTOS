#include <stdio.h>
#include <conio.h>
#include <dos.h>
#include <stdlib.h>

#define COM1_BASE 0x3F8
#define COM2_BASE 0x2F8

// Initialise the serial port with a specific baud rate
void init_serial(int port_base, long baud) {
    // Disable interrupts on the UART
    outportb(port_base + 1, 0x00);
    
    // Set DLAB (Divisor Latch Access Bit) to 1 to load divisor
    outportb(port_base + 3, 0x80);
    
    // Calculate divisor (115200 is the base clock frequency divisor)
    int divisor = (int)(115200L / baud);
    
    // Set Baud Rate Divisor (low byte first, then high byte)
    outportb(port_base + 0, divisor & 0xFF);
    outportb(port_base + 1, (divisor >> 8) & 0xFF);
    
    // Set Line Control: 8 data bits, no parity, 1 stop bit (DLAB = 0)
    outportb(port_base + 3, 0x03);
    
    // Enable FIFO, clear RX/TX queues
    outportb(port_base + 2, 0xC7);
    
    // Set DTR & RTS high, enable Out2
    outportb(port_base + 4, 0x0B);
    
    printf("[+] Porta configurada: Baudrate=%ld, 8N1\n", baud);
}

// Send a single character
void write_serial(int port_base, char c) {
    // Wait until Transmit Holding Register is empty (bit 5 of LSR)
    while ((inportb(port_base + 5) & 0x20) == 0);
    outportb(port_base, c);
}

// Check if a character is ready to be read
int read_ready(int port_base) {
    // Bit 0 of LSR is Data Ready
    return inportb(port_base + 5) & 0x01;
}

// Read a single character
char read_serial(int port_base) {
    while (!read_ready(port_base));
    return inportb(port_base);
}

// Send a null-terminated string
void write_string(int port_base, const char* str) {
    while (*str) {
        write_serial(port_base, *str++);
    }
}

int main() {
    int port_base = COM1_BASE;
    long baud = 115200L;
    char opt;

    clrscr();
    printf("==================================================\n");
    printf("     DOS ESP32 SERIAL COMMANDER - BORLAND C++ 3.1\n");
    printf("==================================================\n\n");

    printf("Escolha a porta serial:\n");
    printf("1. COM1 (0x3F8)\n");
    printf("2. COM2 (0x2F8)\n");
    printf("Opcao: ");
    opt = getche();
    printf("\n");
    if (opt == '2') {
        port_base = COM2_BASE;
    }

    printf("Escolha o baud rate:\n");
    printf("1. 115200 (Padrao ESP32)\n");
    printf("2. 9600\n");
    printf("Opcao: ");
    opt = getche();
    printf("\n");
    if (opt == '2') {
        baud = 9600L;
    }

    init_serial(port_base, baud);

    printf("\nPressione ESC para sair.\n");
    printf("Digite o comando a enviar (ex: GET /select?id=-2 HTTP/1.1\\r\\n):\n");
    printf("--------------------------------------------------\n");

    // Loop to send commands
    char cmd[100];
    int idx = 0;
    
    while (1) {
        if (kbhit()) {
            char key = getch();
            if (key == 27) { // ESC key
                break;
            }
            if (key == 13) { // ENTER
                cmd[idx] = '\0';
                printf("\nEnviando: %s\\r\\n\n", cmd);
                
                // Send the command string followed by CR+LF
                write_string(port_base, cmd);
                write_serial(port_base, '\r');
                write_serial(port_base, '\n');
                
                idx = 0; // reset buffer
                
                // Read response for a short period
                printf("Resposta:\n");
                delay(200); // Wait 200ms
                while (read_ready(port_base)) {
                    char rx = inportb(port_base);
                    if (rx == '\n') printf("\r\n");
                    else if (rx != '\r') putchar(rx);
                }
                printf("\n--------------------------------------------------\n");
            } else if (key == 8) { // BACKSPACE
                if (idx > 0) {
                    idx--;
                    putchar(8);
                    putchar(' ');
                    putchar(8);
                }
            } else {
                if (idx < 99) {
                    cmd[idx++] = key;
                    putchar(key);
                }
            }
        }
        
        // Also print any unsolicited incoming bytes
        if (read_ready(port_base)) {
            char rx = inportb(port_base);
            if (rx == '\n') printf("\r\n");
            else if (rx != '\r') putchar(rx);
        }
    }

    printf("\nEncerrando o programa.\n");
    return 0;
}
