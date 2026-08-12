# DOS-SANTOS: Mellanox ConnectX-3 Pro DOS Driver 🚀

Um projeto experimental para desenvolvimento de ferramentas e um Packet Driver genérico (Modo Real de 16 bits) para placas de rede PCIe de altíssima performance **Mellanox ConnectX-3 Pro** (10GbE / 40GbE) para o sistema operacional **MS-DOS**.

## 📌 Sobre o Projeto
Placas Mellanox ConnectX-3 Pro utilizam mapeamentos complexos de memória de 64 bits (PCI BARs), Filas de Conclusão (CQs) e Pares de Filas (QPs). Como o MS-DOS roda em Modo Real e possui o limite de 1 MB de memória, desenvolver um driver nativo requer engenharia reversa do protocolo UNDI/PXE disponibilizado pelo FlexBoot da própria placa.

Este repositório contém:
1. **PCI Scanner (`pci_scan.asm`)**: Uma ferramenta em Assembly (compilada com `nasm`) para varrer o barramento PCI/PCIe e detectar o Vendor ID `15B3` (Mellanox), revelando o Bus/Dev/Func da sua placa diretamente no DOS.
2. **Packet Driver Skeleton (`mlx_pkt.asm`)**: O esqueleto (TSR - Terminate and Stay Resident) do nosso driver genérico. Ele varre a memória em busca da assinatura `!PXE` deixada pela ROM da Mellanox e prepara a interrupção `0x60` (Padrão Crynwr) para interagir com o stack TCP/IP do DOS (como o mTCP).
3. **DOS Serial & HTTP Test (`dos_ser.cpp` & `esp_send.cpp`)**: Programas em C++ (Borland C++ 3.1) para testar comunicações pela porta serial e envio de pacotes brutos.


<img width="1080" height="992" alt="Gemini_Generated_Image_9vi9h69vi9h69vi9" src="https://github.com/user-attachments/assets/04453432-3f23-41ea-ab95-eba978490c9f" />
 

## 🛠️ Como Compilar
Para compilar os arquivos em Assembly, utilize o **Netwide Assembler (NASM)** no Linux ou Windows:
```bash
nasm -f bin pci_scan.asm -o pci_scan.com
nasm -f bin mlx_pkt.asm -o mlx_pkt.com
```

Para compilar os utilitários em C++, utilize o **Borland C++ 3.1**.

## 🚀 Como Executar no DOS
Inicie sua máquina no MS-DOS e rode os utilitários:
- Para checar a placa: `PCI_SCAN.COM`
- Para iniciar o driver residente: `MLX_PKT.COM`

Consulte o arquivo `HELPDOS.txt` para um guia detalhado sobre a teoria, arquitetura do driver e dicas de diagnóstico de hardware.
