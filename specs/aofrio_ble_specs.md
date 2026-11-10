# Guia Técnico de Integração e Engenharia Reversa: AoFrio Monitor BLE

Este documento detalha o funcionamento de rádio do hardware **AoFrio Monitor** (antigo Wellington Drive Connect Monitor) para permitir a integração do driver Bluetooth no App Móvel.

---

## 1. Características de Rádio do Hardware
* **Frequência:** 2.4 GHz Bluetooth Low Energy (BLE 4.2 / 5.0).
* **Potência / Alcance:** Transmissão ajustada para atravessar paredes de gabinetes refrigerados comerciais.
* **Memória Flash do Sensor:** Armazena até 60 dias de registros com intervalos configuráveis (geralmente 1 leitura a cada 1 a 15 minutos).
* **Outros Sensores Embutidos:**
  * Sensor de temperatura interna calibrado em fábrica.
  * Acelerômetro de 3 eixos (detecta vibração contínua do compressor e movimentação da porta).
  * Sensor óptico/magnético de porta.
  * Beacon iBeacon e Eddystone (Google).

---

## 2. Passo a Passo para Mapear o Dispositivo Real com nRF Connect

Assim que você ou o técnico receber o sensor físico em mãos:

1. **Baixar o nRF Connect:**
   * Disponível gratuitamente na Google Play Store (Android) e Apple App Store (iOS).
2. **Escanear:**
   * Ligue o Bluetooth do celular e aproxime-se do sensor.
   * Procure por nomes como: `AoFrio`, `WDRIVE`, `Connect Monitor` ou prefixos com código MAC.
3. **Inspecionar Anúncio (Advertising):**
   * Verifique o campo **Manufacturer Data**. A AoFrio costuma colocar nos primeiros 4 a 8 bytes a temperatura instantânea em formato hexadecimal ($T \times 10$ ou $T \times 100$ em complemento de 2).
4. **Conectar (GATT Services):**
   * Clique em **Connect** no nRF Connect.
   * Observe a lista de UUIDs de 128-bits.
   * Localize a característica que possui propriedades de **READ**, **WRITE** e **NOTIFY**.
   * Geralmente, a transferência do histórico de 60 dias é iniciada escrevendo um comando de handshake (ex.: `0x01` ou uma estampa de tempo unix) na característica de comando; o sensor então responde disparando centenas de pacotes de notificação com blocos compactados de bytes.

---

## 3. Estrutura Abstrata do Driver BLE (Arquitetura de Código)

Para que o aplicativo funcione antes e depois da chegada do hardware, o código do App Móvel utiliza uma interface (`IBleService`):

```dart
abstract class IBleService {
  Stream<BleScanResult> scanForDevices();
  Future<void> connect(String deviceId);
  Future<List<SensorReading>> downloadStoredHistory();
  Future<void> disconnect();
}
```

* **`MockBleService` (Atual):** Simula perfeitamente a entrega dos bytes históricos de um ensaio pull-down.
* **`AoFrioBleService` (Final):** Implementa o protocolo GATT real usando o pacote `flutter_blue_plus`.
