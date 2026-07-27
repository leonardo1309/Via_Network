#ifndef CONFIG_H
#define CONFIG_H

// ==========================================
// 1. CONFIGURACIÓN DE RED (WI-FI)
// ==========================================
const char* WIFI_SSID = "YOUR_WIFI_SSID";
const char* WIFI_PASS = "YOUR_WIFI_PASSWORD";

// ==========================================
// 2. CONFIGURACIÓN BLOCKCHAIN
// ==========================================
const bool RPC_USE_TLS = false;
const char* RPC_HOST = "192.168.1.100"; // IP local de tu PC corriendo Anvil (verifica con ipconfig)
const uint16_t RPC_PORT = 8545;
const char* RPC_PATH = "";
const uint32_t CHAIN_ID = 31337;

const char* CONTRACT_ADDRESS = "0x0000000000000000000000000000000000000000"; // VIA_Operator desplegado
const char* PRIVATE_KEY = "0xYOUR_PRIVATE_KEY";

// ==========================================
// 3. PARÁMETROS TÉCNICOS DE TRANSACCIÓN
// ==========================================
const unsigned long long GAS_PRICE = 20000000000ULL; // 20 Gwei
const uint32_t GAS_LIMIT = 210000;

// ==========================================
// 4. IDENTIDAD DEL VALIDADOR (bus/zona de prueba)
// ==========================================
const uint32_t BUS_ID = 101;
const uint32_t ZONE_ID = 1;

#endif
