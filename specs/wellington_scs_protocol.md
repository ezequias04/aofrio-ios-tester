# Protocolo SCS (Wellington Drive) — engenharia reversa do app oficial

Fonte: `scs-field.apk` (app **SCS Field**, pacote `air.com.wdtl.scs.diagnostic.mobile`,
v5.42.10), extraído do LDPlayer 9 e analisado em 2026-11-09. App Adobe AIR; a
lógica está em `assets/Main.swf` (ActionScript 3), classe
`com.wdtl.scs.diagnostic.service:BluetoothLeCommsService`.

**Método:** parser próprio de bytecode ABC em Python (`tools/scs-field-apk/`,
não versionado). O FFDec (decompilador oficial) não pôde ser executado nesta
máquina — rodar um `.jar` baixado foi bloqueado pelo controle de segurança
do ambiente. Em vez disso, o pool de constantes da classe e o bytecode AVM2
de métodos específicos foram lidos e desmontados à mão. Isso dá certeza
total sobre nomes↔valores de `const`/`static` e sobre a sequência exata de
instruções dos métodos abaixo — não é mais "por proximidade" como na
primeira versão deste documento.

## UUIDs — confirmados por valor literal (100%, não por proximidade)

Extraídos direto dos traits `const`/`static` da classe (ordem: nome da
constante no código-fonte = valor do UUID, lido byte a byte do bytecode):

| Constante no código | UUID |
|---|---|
| `SCS_ADMIN_SERVICE` | `6D90C7B0-A704-455F-92D1-9889ECAF636A` |
| `SCS_AUTH_CHARACTERISTIC` | `34D81C0D-A398-4828-B702-8B7F42F5BF96` |
| `SCS_AUTH_RESPONSE_CHARACTERISTIC` | `673EBC29-FB79-4FBB-8B86-C3255A12F784` |
| `SCS_ASSET_TRACK_SERVICE` | `1DECA38D-DC21-484E-83F2-E90866AC40B1` |
| `SCS_ASSET_TRACK_REQ_DATA_CHARACTERISTIC` | `D224EEED-BB11-416D-B587-01D0DBEE198B` |
| `SCS_ASSET_TRACK_RX_CHARACTERISTIC` | `0D3DE66C-9B66-4D21-B2CF-9D4ABB18E60D` |
| `SCS_ASSET_TRACK_TX_CHARACTERISTIC` | `EFDD2460-6E34-4BC6-A262-32F0D30E8D65` |
| `SCS_ASSET_TRACK_BULK_TX_CHARACTERISTIC` | `FFDD2460-6E34-4BC6-A262-32F0D30E8D65` |
| `SCS_ASSET_TRACK_BOTTLER_ASSET_NUMBER` | `23201DEA-C8DA-44C6-B170-136A597901E2` |
| `SCS_ASSET_TRACK_OEM_SERIAL_NUMBER` | `864580BA-C669-4B97-B4BA-B729B7A30FA3` |
| `SCS_ASSET_TRACK_COOLER_MODEL` | `D8EB11C3-92C3-4195-9DC0-FEE7ED5FA16B` |
| `SCS_DIAGNOSTIC_SERVICE` | `E523405A-8273-407D-A8AB-F1BF20F45B19` |
| `SCS_DIAGNOSTIC_RX_CHARACTERISTIC` | `71D86C61-FFCA-4A47-A6CD-B79650E6DCB3` |
| `SCS_DIAGNOSTIC_TX_CHARACTERISTIC` | `DCD9889F-C7A7-4344-8EDC-C968F8E13EF0` |

Bate 100% com os 8 UUIDs vistos no nRF Connect (`wellington_monitor_gatt.md`).
A versão anterior deste documento tinha ~6 dessas trocadas (por ter usado
proximidade no pool de strings, não o valor real do trait) — essa versão
corrige.

Três UUIDs vistos no bytecode e **não relacionados ao nosso sensor** (não
apareceram no scan nRF Connect — provavelmente de outro produto da mesma
família de código, tipo OTA de bootloader): `8E09B9BC-25F4-4DCD-9DB0-8E341DBDE507`,
`8A6B45D0-D33C-452E-B4BF-417AE1425204`, `B4EE3F8A-07E2-4403-927C-29893072C4BA`.

## Confirma que é o produto certo

```
PRODUCT_ID_SCS = 1
PRODUCT_ID_CLICK = 3
PRODUCT_ID_MONITOR = 16   ← o nosso
```

## Comando confirmado: `requestStatus` (bytecode desmontado de `startReadStatus`)

```as3
// pseudocódigo fiel ao bytecode lido
var ba:ByteArray = new ByteArray();
ba.writeByte(SCS_REQUEST_STATUS);               // = 2
writeCharacteristic(SCS_ASSET_TRACK_SERVICE,     // 1DECA38D...
                     SCS_ASSET_TRACK_REQ_DATA_CHARACTERISTIC,  // D224EEED...
                     ba);
```

Ou seja: **cada comando é 1 byte só**, o código do "register", escrito em
`SCS_ASSET_TRACK_REQ_DATA_CHARACTERISTIC`, dentro de `SCS_ASSET_TRACK_SERVICE`.
Isso é código real, não suposição — foi desmontado instrução por instrução.

### Tabela de códigos de comando (todos `const int` confirmados)

| Constante | Valor |
|---|---|
| `SCS_REQUEST_TIMESTAMP` | 1 |
| `SCS_REQUEST_STATUS` | 2 |
| `SCS_REQUEST_LIFETIME_COUNTS_1` | 3 |
| `SCS_REQUEST_LIFETIME_COUNTS_2` | 4 |
| `SCS_REQUEST_EVENT_START_ADDRESS` | 5 |
| `SCS_REQUEST_RESET_LIFETIME_COUNTS_OR_STATS_LOG` | 7 |
| `SCS_SET_BLUETOOTH_NAME` | 8 |
| `SCS_SET_CLOCK` | 9 |
| `SCS_REQUEST_RESET_USER_PARAMS` | 11 |
| `SCS_REQUEST_BLUETOOTH_NAME` | 13 |
| `SCS_REQUEST_RESET_USER_PARAMS_SKIP_BOOTLOADER` | 16 |
| `SCS_SET_BOTTLER_PIN_0` / `_1` | 153 / 154 |
| `SCS_SET_OEM_PIN_0` / `_1` | 155 / 156 |
| `SCS_SET_OEM_PIN_0/1_FIRMWARE_1580_ONWARDS` | 144 / 145 |
| beacon/Eddystone (`SCS_REQUEST_BEACON_ADV_PARAMS` etc.) | 64–77 |

Todos seguem o mesmo padrão de `requestStatus` (1 byte no
`REQ_DATA_CHARACTERISTIC`) — **assumido por analogia de código**, não
desmontado um a um; só `SCS_REQUEST_STATUS` foi verificado instrução por
instrução.

## Confirmado: cabeçalho de 16 bytes de cada bloco de evento

Desmontado o método interno (nome obfuscado `_-9U`) que a classe chama ao
processar a resposta de leitura de bloco:

```
offset 0-3   rawTimestamp   UInt32 little-endian
offset 4-5   status         UInt16 little-endian
offset 6-7   protocolVersion UInt16 little-endian
offset 8-9   (campo não nomeado no bytecode, obfuscado) UInt16 little-endian
offset 10-15 não lido pelo parser (reservado/alinhamento)
```

Implementado em `WellingtonBleService.parseEventBlockHeader` no app Flutter.

`DEFAULT_EVENT_BLOCK_SIZE = 1024` (bytes por bloco) é o padrão; o tamanho
real pode vir de `readUnsignedShort()` dependendo de
`productReportsBlockSize(productId, protocolVersion)` — função condicional
vista no bytecode, não totalmente resolvida.

## CORREÇÃO: não existe handshake de autenticação obrigatório (produto Monitor)

A primeira versão deste documento assumia que `SCS_AUTH_CHARACTERISTIC` +
AES-CBC bloqueava toda leitura. **Errado.** Desmontei o fluxo de conexão
completo (`onServicesDiscovered` → `onSetNotificationSuccess` → método
interno `_-4a` → `dispatchAuthenticateSuccess`) e o que acontece de
verdade é:

```
1. connect()
2. discoverServices()
3. setCharacteristicNotification(SCS_ASSET_TRACK_SERVICE,
                                  SCS_ASSET_TRACK_TX_CHARACTERISTIC, true)
   → dispara evento DEVICE_CONNECTED (sem nada de cripto)
4. se useFastEventBlockRead (depende de productId/protocolVersion):
   setCharacteristicNotification(SCS_ASSET_TRACK_SERVICE,
                                  SCS_ASSET_TRACK_BULK_TX_CHARACTERISTIC, true)
5. método interno decide: productId == PRODUCT_ID_SCS_GEN_1 ou
   PRODUCT_ID_CCC → caminho de compatibilidade (não se aplica ao Monitor).
   Qualquer outro productId (inclui PRODUCT_ID_MONITOR = 16) →
   chama dispatchAuthenticateSuccess() DIRETO.
6. dispatchAuthenticateSuccess(): só ajusta flags locais
   (configDownloadAllowed, nomes de empresa) e dispara AUTHENTICATE_SUCCESS.
   Não envolve ICipher, não envolve chave, não envolve característica de
   auth nenhuma.
```

Ou seja: **para o Wellington Monitor, basta conectar e ativar notificação
nas duas características de Asset Track — não precisa autenticar com
chave nenhuma.** `requestStatus()` já deve funcionar no hardware real sem
mais nada.

### E o que é `SCS_AUTH_CHARACTERISTIC` / AES-CBC / `writeKeys` então?

É um fluxo **separado e opcional**: `writeKeys`/`startWriteAuthKeys`
escrevem via `SCS_DIAGNOSTIC_SERVICE`/`SCS_DIAGNOSTIC_RX_CHARACTERISTIC`
(não `SCS_ADMIN_SERVICE`), usando `protocolParser.encodeWriteDirect` com
códigos de função (`FUNCTION_WRITE_STRING`, `FUNCTION_WRITE`) — parece ser
a tela administrativa de **trocar a chave de segurança gravada no
controlador**, não algo que roda ao simplesmente baixar o histórico.
Mantém-se como não confirmado e fora de escopo deste projeto — não precisa
mexer nisso para ler temperatura.

## NÃO confirmado — gap real restante

**Layout de cada registro de temperatura/porta/vibração** dentro do bloco
de 1024 bytes (depois do cabeçalho de 16 já decodificado). O roteador
`onReadCharacteristic` é gigante (milhares de bytes de bytecode) e cobre
dezenas de tipos de resposta diferentes; consegui isolar o cabeçalho do
bloco de evento mas não o offset exato dos campos de cada registro dentro
do corpo.

Como não há mais bloqueio de autenticação, **esse gap agora pode ser
fechado testando no hardware real**: conectar, pedir
`SCS_REQUEST_EVENT_START_ADDRESS`, capturar os bytes brutos que chegam em
`SCS_ASSET_TRACK_BULK_TX_CHARACTERISTIC` pelo nRF Connect, e comparar com
os valores de temperatura que você sabe que estavam acontecendo no
equipamento na hora da gravação (ex.: deixar na geladeira e anotar a
temperatura real em 3-4 momentos, comparar com os bytes). Não depende mais
do app oficial nem de decompilador.

## Observação
`scs-field.apk` e os artefatos extraídos ficam em `tools/scs-field-apk/`
(não versionados — binário de terceiro). É o APK do próprio hardware do
usuário, baixado da Play Store, analisado para fins de interoperabilidade
com este projeto.
