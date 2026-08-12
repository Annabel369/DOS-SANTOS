#include <stdlib.h>
#include <stdio.h>
#include <time.h>

int main() {
    // Inicializa a semente aleatoria usando o relogio do sistema
    srand((unsigned)time(NULL));
    
    // Gera um ID aleatorio entre -1 e -5
    // rand() % 5 gera 0 a 4. Somando 1, gera 1 a 5. Negativo fica -1 a -5.
    int id = -(rand() % 5 + 1);
    
    char cmd[128];
    sprintf(cmd, "HTGET.EXE -output NUL http://192.168.100.49/select?id=%d", id);
    
    printf("\n[+] Enviando requesicao HTTP via HTGET...\n");
    printf("[+] Comando: %s\n", cmd);
    
    // Executa o comando no shell do DOS
    int ret = system(cmd);
    
    if (ret == 0) {
        printf("[+] Sucesso ao executar o HTGET (ID = %d)!\n", id);
    } else {
        printf("[-] Erro ao executar o HTGET. Codigo de retorno: %d\n", ret);
        printf("    Certifique-se de que o HTGET.EXE do mTCP esta no PATH ou na mesma pasta.\n");
    }
    
    return ret;
}
