#include <stdio.h>
#include <dos.h>
#include <string.h>

#ifdef __386__
// 32-bit compiler
#define FAR
#else
// Borland C++ 16-bit
#define FAR far
#endif

int main() {
    clrscr();
    printf("==================================================\n");
    printf("     DOS PACKET DRIVER SCANNER - BORLAND C++ 3.1\n");
    printf("==================================================\n\n");
    printf("Procurando drivers de rede carregados (0x60-0x80)...\n\n");

    int found = 0;
    for (int intr = 0x60; intr <= 0x80; intr++) {
        // Obter o vetor de interrupcao
        void (interrupt FAR *handler)() = getvect(intr);
        if (handler == NULL) continue;

        // Converter o ponteiro FAR para ler a assinatura "PKT DRVR" no offset + 3
        char FAR *ptr = (char FAR *)handler;

        char sig[9];
        for (int i = 0; i < 8; i++) {
            sig[i] = ptr[3 + i];
        }
        sig[8] = '\0';

        // O padrao Crynwr/Packet Driver define "PKT DRVR" no offset 3 da interrupcao
        if (strcmp(sig, "PKT DRVR") == 0) {
            printf("[+] PACKET DRIVER ENCONTRADO na Interrupcao [0x%02X]\n", intr);
            printf("    Endereco do Handler: %p\n", (void FAR *)handler);
            
            // Consultar informacoes do driver usando AX = 0x01FF (driver_info)
            union REGS regs;
            struct SREGS sregs;
            regs.h.ah = 1;
            regs.h.al = 0xff;
            
            int86x(intr, &regs, &regs, &sregs);
            
            // Se o Carry Flag nao estiver setado, a chamada teve sucesso
            if (regs.x.cflag == 0) {
                printf("    Classe do Driver: %d (1=Ethernet, 2=IEEE 802.5, etc.)\n", regs.h.ch);
                printf("    Tipo de Hardware: %d\n", regs.x.dx);
                printf("    Versao do Driver: %d.%d\n", regs.x.bx / 100, regs.x.bx % 100);
                
                // Vamos tentar pegar o endereco MAC da placa
                // Chamada: AH = 6 (get_address), CX = buffer len, ES:DI = buffer
                unsigned char mac[6];
                regs.h.ah = 6;
                sregs.es = FP_SEG(mac);
                regs.x.di = FP_OFF(mac);
                regs.x.cx = 6;
                
                int86x(intr, &regs, &regs, &sregs);
                if (regs.x.cflag == 0) {
                    printf("    Endereco MAC: %02X:%02X:%02X:%02X:%02X:%02X\n",
                           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
                } else {
                    printf("    [-] Nao foi possivel obter o endereco MAC.\n");
                }
            } else {
                printf("    [-] Nao foi possivel obter detalhes da interrupcao.\n");
            }
            found = 1;
            printf("\n");
        }
    }

    if (!found) {
        printf("[-] Nenhum Packet Driver de Rede foi detectado.\n");
        printf("    Para utilizar TCP/IP no DOS nativo, voce precisa rodar o driver\n");
        printf("    da sua placa de rede (ex: RTSPKT.COM para placas Realtek)\n");
        printf("    que associa a placa a uma interrupcao de software (ex: 0x60).\n");
    }

    printf("\nPressione qualquer tecla para sair...");
    getch();
    return 0;
}
