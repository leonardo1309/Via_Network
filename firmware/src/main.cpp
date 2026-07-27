/**
 * @file main.cpp
 * @brief Firmware del validador fisico de Via Network (ESP32 + PN532).
 *
 * Lee tarjetas RFID/Mifare y cobra el pasaje llamando a `VIA_Operator.collectFare(address,uint256,uint256)`
 * on-chain. Usa la libreria Web3E unicamente para criptografia offline (codificacion ABI y firma de la
 * transaccion) — el transporte JSON-RPC es un cliente HTTP propio (`rpcCall`), porque los metodos
 * `Web3::Eth*()` de Web3E son inutilizables aqui: fuerzan TLS (Anvil habla HTTP plano) y resuelven el
 * host desde una tabla fija sin entrada para chain 31337 ni para Celo. Ver CLAUDE.md para el detalle.
 *
 * @note Llama collectFare() directamente (paga su propio gas en CELO nativo); todavia no firma el
 * mensaje EIP-712 para el flujo de relayer (`collectFareWithSig`) — ver "Known gap" en CLAUDE.md.
 */

// 1. Forzar la definición del byte de Arduino antes de cargar las librerías
#include <Arduino.h>
#define USBCON // Truco opcional para ciertos entornos, pero el de abajo es el vital
typedef uint8_t arduino_byte;
#define byte arduino_byte
#include <Adafruit_PN532.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <Web3.h>
#include <KeyID.h>
#include <HTTPClient.h>
#include <string>

#include <Wire.h>
#include "config.h"

using std::string;

#define I2C_SDA 21
#define I2C_SCL 22

#define LED_INTERNO 2

Adafruit_PN532 nfc(I2C_SDA, I2C_SCL);

/**
 * @brief Detecta si un valor de config.h quedo con el placeholder de config.example.h sin rellenar.
 * @param value Cadena a revisar.
 * @return true si contiene "YOUR_" (aun no fue configurada con un valor real).
 */
bool isPlaceholder(const char* value) {
  return strstr(value, "YOUR_") != nullptr;
}

/**
 * @brief Valida que config.h tenga todos los campos requeridos antes de arrancar.
 * @return true si la configuracion es valida; false si falta algo (y ya se imprimio el error por Serial).
 */
bool validateConfig() {
  bool ok = true;

  if (strlen(WIFI_SSID) == 0 || isPlaceholder(WIFI_SSID)) {
    Serial.println("[CONFIG ERROR] WIFI_SSID no configurado.");
    ok = false;
  }

  if (strlen(WIFI_PASS) == 0 || isPlaceholder(WIFI_PASS)) {
    Serial.println("[CONFIG ERROR] WIFI_PASS no configurado.");
    ok = false;
  }

  if (strlen(RPC_HOST) == 0 || isPlaceholder(RPC_HOST)) {
    Serial.println("[CONFIG ERROR] RPC_HOST no configurado.");
    ok = false;
  }

  if (strlen(RPC_PATH) > 0 && isPlaceholder(RPC_PATH)) {
    Serial.println("[CONFIG ERROR] RPC_PATH no configurado.");
    ok = false;
  }

  if (strlen(CONTRACT_ADDRESS) != 42 || strncmp(CONTRACT_ADDRESS, "0x", 2) != 0) {
    Serial.println("[CONFIG ERROR] CONTRACT_ADDRESS invalido (debe ser 0x + 40 hex).");
    ok = false;
  }

  if (strlen(PRIVATE_KEY) != 66 || strncmp(PRIVATE_KEY, "0x", 2) != 0) {
    Serial.println("[CONFIG ERROR] PRIVATE_KEY invalida (debe ser 0x + 64 hex).");
    ok = false;
  }

  if (CHAIN_ID == 0) {
    Serial.println("[CONFIG ERROR] CHAIN_ID no puede ser 0.");
    ok = false;
  }

  return ok;
}

/**
 * @brief Extrae el valor de un campo string de una respuesta JSON-RPC, sin parsear JSON completo.
 * @dev Suficiente para respuestas de nodo Ethereum (`{"result":"0x..."}`) que siempre traen el valor
 * entre comillas; no soporta objetos/arreglos anidados como valor.
 * @param json Cuerpo de la respuesta JSON-RPC completa.
 * @param field Nombre del campo a buscar (p.ej. "result").
 * @return El valor entre comillas, o "" si no se encontro.
 */
String extractQuotedJsonField(const String& json, const char* field) {
  String key = String("\"") + field + "\":";
  int keyPos = json.indexOf(key);
  if (keyPos < 0) {
    return "";
  }

  int firstQuote = json.indexOf('"', keyPos + key.length());
  if (firstQuote < 0) {
    return "";
  }

  int secondQuote = json.indexOf('"', firstQuote + 1);
  if (secondQuote < 0) {
    return "";
  }

  return json.substring(firstQuote + 1, secondQuote);
}

/**
 * @brief Arranque del validador: valida config.h, inicializa el lector PN532 y conecta al Wi-Fi.
 * @dev Si la configuracion es invalida o el PN532 no responde, se queda en un loop infinito
 * parpadeando el LED en vez de continuar — es intencional, no tiene sentido operar sin lector NFC.
 */
void setup(void) {

  Serial.begin(115200);

  // Configurar el pin del LED como salida
  pinMode(LED_INTERNO, OUTPUT);
  digitalWrite(LED_INTERNO, LOW); // Aseguramos que arranque apagado

  if (!validateConfig()) {
    Serial.println("[CONFIG ERROR] Corrige src/config.h y reinicia.");
    while (1) {
      digitalWrite(LED_INTERNO, HIGH);
      delay(500);
      digitalWrite(LED_INTERNO, LOW);
      delay(500);
    }
  }

  // 1. Inicializar el bus I2C para el PN532 usando los pines del ESP32-CAM
  Serial.println("Configurando pines I2C para el lector NFC...");
  Wire.begin(I2C_SDA, I2C_SCL);

  // 2. Arrancar el lector NFC
  nfc.begin();
  uint32_t versiondata = nfc.getFirmwareVersion();
  if (!versiondata) {
    Serial.println("Error crítico: No se encontró el lector PN532. Revisa conexiones.");
    while (1); // Detiene la ejecución si el hardware no responde
  }
  
  // Configurar el PN532 para leer tarjetas
  nfc.SAMConfig();
  Serial.println("Lector PN532 inicializado correctamente.");

  // 3. Conectar a la red Wi-Fi
  Serial.print("Conectando a Wi-Fi");
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  
  while (WiFi.status() != WL_CONNECTED) {
     digitalWrite(LED_INTERNO, HIGH); // Enciende el LED
    delay(100);
    digitalWrite(LED_INTERNO, LOW);  // Apaga el LED
    delay(100);
    Serial.print(".");
  }
  Serial.println("\n¡Conectado con éxito a la red!");
  Serial.print("Dirección IP del validador: ");
  Serial.println(WiFi.localIP());
  
  Serial.println("Validador listo y esperando tarjetas Mifare...");
  

  digitalWrite(LED_INTERNO, HIGH); 
  delay(4000);
  digitalWrite(LED_INTERNO, LOW);

  Serial.println("\nConectado con éxito!");
}


// Web3E se usa para ABI + firmado; el RPC se hace por HTTP directo al host configurado.
Web3 web3(CHAIN_ID);

/**
 * @brief Arma la URL base del endpoint JSON-RPC a partir de config.h (RPC_USE_TLS/RPC_HOST/RPC_PORT/RPC_PATH).
 * @return URL completa, p.ej. "http://192.168.2.6:8545".
 */
String getRpcUrl() {
  String url = String(RPC_USE_TLS ? "https://" : "http://") + RPC_HOST + ":" + String(RPC_PORT);

  if (strlen(RPC_PATH) > 0) {
    if (RPC_PATH[0] != '/') {
      url += "/";
    }
    url += RPC_PATH;
  }

  return url;
}

/**
 * @brief Cliente JSON-RPC minimo propio (reemplaza los metodos Eth*() de Web3E, ver nota del archivo).
 * @param method Metodo JSON-RPC, p.ej. "eth_sendRawTransaction".
 * @param params Parametros ya formateados como arreglo JSON, p.ej. "[\"0x...\"]".
 * @param resultOut [out] Campo "result" de la respuesta, si la llamada fue exitosa.
 * @return true si la request HTTP y la respuesta JSON-RPC fueron exitosas (sin campo "error").
 */
bool rpcCall(const String& method, const String& params, String& resultOut) {
  HTTPClient http;
  const String payload =
      String("{\"jsonrpc\":\"2.0\",\"method\":\"") + method +
      "\",\"params\":" + params + ",\"id\":1}";

  int status = -1;
  String response;
  const String url = getRpcUrl();

  if (RPC_USE_TLS) {
    WiFiClientSecure client;
    client.setInsecure();
    client.setTimeout(15000);

    if (!http.begin(client, url)) {
      Serial.println("[RPC ERROR] No se pudo inicializar la conexion HTTPS.");
      return false;
    }

    http.addHeader("Content-Type", "application/json");
    status = http.POST(payload);
    if (status > 0) {
      response = http.getString();
    }
    http.end();
  } else {
    if (!http.begin(url)) {
      Serial.println("[RPC ERROR] No se pudo inicializar la conexion HTTP.");
      return false;
    }

    http.addHeader("Content-Type", "application/json");
    status = http.POST(payload);
    if (status > 0) {
      response = http.getString();
    }
    http.end();
  }

  if (status <= 0) {
    Serial.printf("[RPC ERROR] POST falló con código %d\n", status);
    return false;
  }

  if (response.indexOf("\"error\"") >= 0 && response.indexOf("\"error\":null") < 0) {
    Serial.print("[RPC ERROR] Respuesta: ");
    Serial.println(response);
    return false;
  }

  resultOut = extractQuotedJsonField(response, "result");
  if (resultOut.length() == 0) {
    Serial.print("[RPC ERROR] No se encontro result en respuesta: ");
    Serial.println(response);
    return false;
  }

  return true;
}

/**
 * @brief Consulta el nonce "pending" de una direccion, para poder firmar la siguiente transaccion.
 * @param fromAddress Direccion (con 0x) cuyo nonce se quiere consultar.
 * @return El nonce como entero, o 0 si la consulta RPC fallo (ver log de [RPC ERROR] en Serial).
 */
uint32_t getPendingNonce(const String& fromAddress) {
  String result;
  const String params = String("[\"") + fromAddress + "\",\"pending\"]";
  if (!rpcCall("eth_getTransactionCount", params, result)) {
    return 0;
  }

  return strtoul(result.c_str(), nullptr, 16);
}

/**
 * @brief Cobra un pasaje llamando a VIA_Operator.collectFare(address,uint256,uint256) directamente.
 * @dev El propio ESP32 firma la transaccion (legacy, EIP-155) y paga su gas en CELO nativo — requiere
 * que su direccion (derivada de PRIVATE_KEY) tenga VALIDATOR_ROLE otorgado en el contrato.
 * @note Los prints "[DEBUG] data/signedTx" quedaron de instrumentacion para diagnosticar un bug de
 * codificacion RLP en Web3E (ver CLAUDE.md); se pueden quitar una vez se confirme que ya no hacen falta.
 * @param userAddress Direccion (con 0x) del pasajero a quien se le descuenta el pasaje.
 * @param busId Identificador del bus que realiza el cobro.
 * @param zoneId Zona tarifaria del viaje (debe existir en VIA_Operator.getZonePrice).
 */
void collectFare(const char* userAddress, uint256_t busId, uint256_t zoneId) {
    Serial.println("\n==========================================");
    Serial.println("COBRO DE PASAJE - VIA NETWORK");
    Serial.println("==========================================");

    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("[ERROR] Dispositivo sin conexión Wi-Fi.");
        return;
    }

    Contract contract(&web3, CONTRACT_ADDRESS);
    contract.SetPrivateKey(PRIVATE_KEY);

    const string privateKeyHex(PRIVATE_KEY);
    KeyID keyId(&web3, privateKeyHex);
    const string from = keyId.getAddress();

    uint32_t nonce = getPendingNonce(from.c_str());

    Serial.println("[Web3] Firmando transacción...");
    string user(userAddress);
    string data = contract.SetupContractData("collectFare(address,uint256,uint256)", &user, &busId, &zoneId);

    string to(CONTRACT_ADDRESS);
    uint256_t value = 0;
    string signedTx = contract.SignTransaction(nonce, GAS_PRICE, GAS_LIMIT, &to, &value, &data);

    if (signedTx.rfind("0x", 0) != 0) {
      signedTx = "0x" + signedTx;
    }

    Serial.print("[DEBUG] data: ");
    Serial.println(data.c_str());
    Serial.print("[DEBUG] signedTx: ");
    Serial.println(signedTx.c_str());

    Serial.println("[Web3] Enviando transacción raw al RPC...");
    String tx_hash;
    const String params = String("[\"") + signedTx.c_str() + "\"]";
    bool sent = rpcCall("eth_sendRawTransaction", params, tx_hash);

    // 5. Procesar el resultado devuelto por Anvil a través del túnel
    if (sent && tx_hash.length() > 0 && tx_hash != "0x0000000000000000000000000000000000000000000000000000000000000000") {
        Serial.print("[ÉXITO] Transacción procesada por el bloque. Tx Hash: ");
      Serial.println(tx_hash);

        // Simulación visual de éxito en el hardware
        digitalWrite(LED_INTERNO, HIGH);
        delay(1000);
        digitalWrite(LED_INTERNO, LOW);
    } else {
        Serial.println("[ERROR] La transacción fue rechazada por la EVM o falló el túnel.");
    }
    
    Serial.println("==========================================");
}



/**
 * @brief Bucle principal: escanea tarjetas Mifare y dispara un cobro cuando detecta una.
 * @dev El mapeo UID -> direccion de pasajero todavia es un valor fijo de prueba (ver comentario abajo);
 * falta implementar el mapeo real tarjeta -> wallet.
 */
void loop(void) {
  uint8_t success;
  uint8_t userId[] = { 0, 0, 0, 0, 0, 0, 0 }; 
  uint8_t userIdLength;

  // Buscar tarjetas NFC
  success = nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, userId, &userIdLength);

  if (success) {
    Serial.println("¡Pasajero detectado!");
    
    // En el futuro, mapearemos este UID a una dirección real del pasajero.
    // Usa una dirección de pasajero válida en la red objetivo.
    const char* direccionPasajero = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC";

    // Bus y zona de prueba (ver VIA_Operator.getZonePrice — zona 1 = Urbano).
    uint256_t busId = BUS_ID;
    uint256_t zoneId = ZONE_ID;

    // Disparar el cobro en la Blockchain
    collectFare(direccionPasajero, busId, zoneId);
    
    delay(3000); // Pausa para evitar cobros dobles accidentales
    Serial.println("\nEsperando siguiente pasajero...");
  }
}