#include <iostream>
#include <string>
#include <cstring>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <chrono>

int main(int argc, char* argv[]) {
    std::string ip = "192.168.100.49";
    int port = 80;
    std::string path = "/select?id=-2";

    if (argc > 1) {
        ip = argv[1];
    }
    if (argc > 2) {
        path = argv[2];
    }
    if (argc > 3) {
        try {
            port = std::stoi(argv[3]);
        } catch (...) {
            std::cerr << "Invalid port format! Using 80." << std::endl;
        }
    }

    std::cout << "==========================================================" << std::endl;
    std::cout << "    ESP32 HTTP COMMAND SENDER (LINUX C++)" << std::endl;
    std::cout << "==========================================================" << std::endl;
    std::cout << "Target: http://" << ip << ":" << port << path << std::endl;

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        std::cerr << "[-] Error creating socket!" << std::endl;
        return 1;
    }

    // Set timeout to 3 seconds for connection and transfer
    struct timeval timeout;      
    timeout.tv_sec = 3;
    timeout.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    sockaddr_in serv_addr;
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(port);

    if (inet_pton(AF_INET, ip.c_str(), &serv_addr.sin_addr) <= 0) {
        std::cerr << "[-] Invalid IP address: " << ip << std::endl;
        close(sock);
        return 1;
    }

    std::cout << "[+] Connecting..." << std::endl;
    auto start = std::chrono::high_resolution_clock::now();
    if (connect(sock, (struct sockaddr*)&serv_addr, sizeof(serv_addr)) < 0) {
        std::cerr << "[-] Connection failed! ESP32 might be offline." << std::endl;
        close(sock);
        return 1;
    }
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> conn_time = end - start;
    std::cout << "[+] Connected in " << conn_time.count() << " ms." << std::endl;

    // Build the HTTP request
    std::string request = "GET " + path + " HTTP/1.1\r\n" +
                          "Host: " + ip + "\r\n" +
                          "Connection: close\r\n\r\n";

    std::cout << "[+] Sending HTTP Request:\n" << request;

    if (send(sock, request.c_str(), request.length(), 0) < 0) {
        std::cerr << "[-] Failed to send data!" << std::endl;
        close(sock);
        return 1;
    }

    std::cout << "[+] Waiting for response..." << std::endl;
    std::cout << "--- RESPONSE START ---" << std::endl;

    char buffer[1024];
    int bytes_received = 0;
    while ((bytes_received = recv(sock, buffer, sizeof(buffer) - 1, 0)) > 0) {
        buffer[bytes_received] = '\0';
        std::cout << buffer;
    }
    std::cout << "\n--- RESPONSE END ---" << std::endl;

    close(sock);
    return 0;
}
