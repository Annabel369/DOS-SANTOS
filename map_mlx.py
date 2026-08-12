import os
import struct
import mmap
import time

device_path = "/sys/bus/pci/devices/0000:06:00.0"
config_file = os.path.join(device_path, "config")
resource0_file = os.path.join(device_path, "resource0")
driver_symlink = os.path.join(device_path, "driver")
unbind_path = "/sys/bus/pci/drivers/mlx4_core/unbind"
bind_path = "/sys/bus/pci/drivers/mlx4_core/bind"

log_path = "/media/astral/5D0B-0163/esp_test/log.txt"

def main():
    if os.geteuid() != 0:
        print("Erro: Este script deve ser executado como root (sudo python3 map_mlx.py).")
        return

    output = []
    output.append("=======================================================")
    output.append("   MAPEA-MELLANOX - DETECTOR DE HARDWARE CONNECTX-3   ")
    output.append("=======================================================")
    output.append("")

    # 1. Ler o PCI Config Space
    try:
        with open(config_file, "rb") as f:
            config = f.read(256)
        
        vendor_id, device_id = struct.unpack("<HH", config[0:4])
        command, status = struct.unpack("<HH", config[4:8])
        class_code = struct.unpack("<I", config[8:12])[0] >> 8
        bar0 = struct.unpack("<I", config[16:20])[0]
        bar2 = struct.unpack("<I", config[24:28])[0]
        rom_bar = struct.unpack("<I", config[48:52])[0]
        
        output.append("--- PCI CONFIGURATION SPACE ---")
        output.append(f"Vendor ID:        0x{vendor_id:04X} (Mellanox)" if vendor_id == 0x15B3 else f"Vendor ID: 0x{vendor_id:04X}")
        output.append(f"Device ID:        0x{device_id:04X}")
        output.append(f"Command Register: 0x{command:04X}")
        output.append(f"Status Register:  0x{status:04X}")
        output.append(f"Class Code:       0x{class_code:06X}")
        output.append(f"BAR 0 (Base MMIO):0x{bar0 & 0xFFFFFFF0:08X} (Size 1MB)")
        output.append(f"BAR 2 (UAR/DB):   0x{bar2 & 0xFFFFFFF0:08X} (Size 8MB)")
        output.append(f"Expansion ROM:    0x{rom_bar & 0xFFFFFFFE:08X}")
        output.append("")
    except Exception as e:
        output.append(f"[-] Erro ao ler PCI Config: {e}")
        print("\n".join(output))
        return

    # Verificamos se o driver esta carregado e fazemos o unbind temporario
    was_bound = os.path.exists(driver_symlink)
    
    if was_bound:
        print("[+] Driver mlx4_core detectado. Fazendo unbind temporario...")
        try:
            with open(unbind_path, "w") as f_unbind:
                f_unbind.write("0000:06:00.0\n")
            time.sleep(0.5)  # tempo para o kernel desvincular
        except Exception as e:
            output.append(f"[-] Nao foi possivel desvincular o driver: {e}")

    # 2. Ler o HCR (Host Command Register) do BAR 0 usando mmap
    hcr_read_success = False
    try:
        with open(resource0_file, "r+b") as f:
            mm = mmap.mmap(f.fileno(), 1048576, mmap.MAP_SHARED, mmap.PROT_READ)
            try:
                hcr_data = mm[0x80680 : 0x80680 + 28]
                hcr_read_success = True
            finally:
                mm.close()
    except Exception as e:
        output.append(f"[-] Erro ao ler HCR do BAR 0 via mmap: {e}")

    # Restauramos o vinculo com o driver se ele estava ativo
    if was_bound:
        print("[+] Restaurando vinculo do driver mlx4_core (bind)...")
        try:
            with open(bind_path, "w") as f_bind:
                f_bind.write("0000:06:00.0\n")
        except Exception as e:
            print(f"[-] Erro ao re-vincular o driver: {e}")

    if hcr_read_success:
        dwords = struct.unpack("<IIIIIII", hcr_data)
        
        in_param_h = dwords[0]
        in_param_l = dwords[1]
        in_param = (in_param_h << 32) | in_param_l
        
        in_mod = dwords[2]
        
        out_param_h = dwords[3]
        out_param_l = dwords[4]
        out_param = (out_param_h << 32) | out_param_l
        
        token = (dwords[5] >> 16) & 0xFFFF
        
        ctrl = dwords[6]
        opcode = ctrl & 0xFFF
        op_mod = (ctrl >> 12) & 0xF
        t = (ctrl >> 21) & 1
        e = (ctrl >> 22) & 1
        go = (ctrl >> 23) & 1
        cmd_status = (ctrl >> 24) & 0xFF
        
        output.append("--- HCR (HOST COMMAND REGISTER) REGISTERS [Offset 0x80680] ---")
        output.append(f"Input Parameter:  0x{in_param:016X}")
        output.append(f"Input Modifier:   0x{in_mod:08X}")
        output.append(f"Output Parameter: 0x{out_param:016X}")
        output.append(f"Command Token:    0x{token:04X}")
        output.append(f"Opcode:           0x{opcode:03X}")
        output.append(f"Opcode Modifier:  0x{op_mod:X}")
        output.append(f"Toggle Bit (T):   {t}")
        output.append(f"Event Req (E):    {e}")
        output.append(f"Go Bit (GO):      {go} ({'Em execução' if go else 'Inativo/Software'})")
        output.append(f"Cmd Status:       0x{cmd_status:02X} ({'OK' if cmd_status == 0 else 'Erro'})")
        output.append("")

    # Escrever para o arquivo log.txt
    try:
        log_content = "\n".join(output)
        with open(log_path, "w") as f:
            f.write(log_content)
        print("\n" + log_content)
        print(f"\n[+] Log gerado com sucesso em: {log_path}")
    except Exception as e:
        print(f"[-] Erro ao gravar arquivo de log: {e}")

if __name__ == "__main__":
    main()
