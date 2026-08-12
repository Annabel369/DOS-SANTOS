#include <stdio.h>
#include <dos.h>
#include <string.h>
#include <conio.h>

#ifdef __386__
#define FAR
#else
#define FAR far
#endif

// Estrutura PXENV+ (cabecalho minimo para diagnostico)
struct pxenv_t {
    char signature[6];      // "PXENV+"
    unsigned short version; // Versao (MSB=major, LSB=minor)
    unsigned char length;   // Tamanho da estrutura
    unsigned char checksum; // Checksum para validacao
    void far *rm_entry;     // Entry point do Real Mode
};

// Estrutura !PXE (cabecalho minimo para diagnostico)
struct pxe_t {
    char signature[4];      // "!PXE"
    unsigned char length;   // Tamanho da estrutura
    unsigned char checksum; // Checksum para validacao
    unsigned char revision; // Revisao
    unsigned char reserved;
    void far *rm_entry;     // Entry point do Real Mode
};

int main() {
    clrscr();
    printf("==================================================\n");
    printf("     DIAGNOSTICO PXE / UNDI - BORLAND C++ 3.1\n");
    printf("==================================================\n\n");

    // 1. Testar chamada de instalacao via INT 1A, AX = 5650h
    printf("1. Testando chamada INT 1Ah AX=5650h (PXE Installation Check)...\n");
    union REGS regs;
    struct SREGS sregs;
    regs.x.ax = 0x5650;
    regs.x.bx = 0;
    sregs.es = 0;
    
    int86x(0x1A, &regs, &regs, &sregs);
    
    // Sucesso: AX = 564Eh ('VN'), CF = 0
    if (regs.x.cflag == 0 && regs.x.ax == 0x564E) {
        printf("[+] SUCESSO: PXE detectado via INT 1Ah!\n");
        printf("    Endereco de PXENV+: %04X:%04X\n", sregs.es, regs.x.bx);
        
        struct pxenv_t far *pxenv = (struct pxenv_t far *)MK_FP(sregs.es, regs.x.bx);
        char sig[7];
        memcpy(sig, pxenv->signature, 6);
        sig[6] = '\0';
        printf("    Assinatura na estrutura: %s\n", sig);
        printf("    Versao da API PXE: %d.%d\n", pxenv->version >> 8, pxenv->version & 0xFF);
        printf("    Entry Point da API UNDI: %p\n", pxenv->rm_entry);
    } else {
        printf("[-] FALHOU: INT 1Ah AX=5650h nao retornou 'VN' (AX=0x%04X, CF=%d)\n", regs.x.ax, regs.x.cflag);
    }
    printf("\n");

    // 2. Varrer a memoria convencional e UMA atras de "PXENV+" e "!PXE"
    printf("2. Varrendo a memoria convencional e UMA por assinaturas...\n");
    printf("   (Escaneando de 0000:0000 a FFFF:0000 em passos de 16 bytes)\n");
    
    int pxenv_count = 0;
    int pxe_count = 0;
    
    // Faremos um scan de 0000h a FFFFh
    // No DOS real, podemos ler toda a memoria
    for (unsigned int seg = 0x0000; seg < 0xFFFF; seg++) {
        // Exibe progresso a cada 4096 segmentos para nao desacelerar muito
        if ((seg % 0x1000) == 0) {
            printf("   Escaneando segmento %04Xh...\n", seg);
        }
        
        char far *ptr = (char far *)MK_FP(seg, 0);
        
        // Verifica assinatura "!PXE"
        if (ptr[0] == '!' && ptr[1] == 'P' && ptr[2] == 'X' && ptr[3] == 'E') {
            printf("[+] Encontrado '!PXE' em %04X:0000\n", seg);
            pxe_count++;
            
            struct pxe_t far *pxe = (struct pxe_t far *)ptr;
            printf("    Entry Point: %p, Checksum: 0x%02X, Revisao: %d\n", 
                   pxe->rm_entry, pxe->checksum, pxe->revision);
        }
        
        // Verifica assinatura "PXENV+"
        if (ptr[0] == 'P' && ptr[1] == 'X' && ptr[2] == 'E' && ptr[3] == 'N' && ptr[4] == 'V' && ptr[5] == '+') {
            printf("[+] Encontrado 'PXENV+' em %04X:0000\n", seg);
            pxenv_count++;
            
            struct pxenv_t far *pxenv = (struct pxenv_t far *)ptr;
            printf("    Entry Point: %p, Checksum: 0x%02X, Versao: %d.%d\n", 
                   pxenv->rm_entry, pxenv->checksum, pxenv->version >> 8, pxenv->version & 0xFF);
        }
    }
    
    printf("\nVarredura concluida.\n");
    printf("Total de estruturas '!PXE' encontradas: %d\n", pxe_count);
    printf("Total de estruturas 'PXENV+' encontradas: %d\n", pxenv_count);
    
    if (pxenv_count == 0 && pxe_count == 0) {
        printf("\n[-] AVISO: Nenhuma assinatura PXE foi encontrada na memoria.\n");
        printf("    Isso significa que a interface PXE/UNDI nao esta ativa.\n");
        printf("    Para usar o driver UNDI, certifique-se de:\n");
        printf("    1. Ativar a ROM do Mellanox FlexBoot (Legacy boot) na BIOS.\n");
        printf("    2. Configurar o bootloader (ex: GRUB4DOS com 'pxe keep'\n");
        printf("       ou PXELINUX/MEMDISK com 'keeppxe') para nao descarregar o PXE.\n");
    }
    
    printf("\nPressione qualquer tecla para sair...");
    getch();
    return 0;
}
