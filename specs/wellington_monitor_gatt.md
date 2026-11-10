# Wellington Monitor (MON1-001) — mapa GATT

Fonte 1: macro exportada do nRF Connect (`Meu.xml`) + vídeo, 2026-11-09.
Unidade: serial `B152E02371`, MAC `E4:B2:DC:3F:4F:3E`.
Nome BLE anunciado e Device Name (0x2A00, Read/Write): `B152E02371079226226`
(serial da etiqueta + `079226226`).

Fonte 2 (nomes das colunas "Papel"/"Valor decodificado"): engenharia reversa
do app oficial — ver [`wellington_scs_protocol.md`](wellington_scs_protocol.md).
Os nomes de serviço/característica abaixo são os nomes reais usados no
código da Wellington, confirmados por leitura do bytecode do app, não mais
hipótese.

## Serviços e características

| Serviço | Característica | Papel (confirmado) | Props | Valor lido |
|---|---|---|---|---|
| 0x1800 Generic Access | 0x2A00 Device Name | — | R, W | ASCII `B152E02371079226226` |
| | 0x2A01 Appearance | — | R | `0002` |
| | 0x2A04 PPCP | — | R | `0900 1800 0000 9001` (11,25–30 ms, latência 0, timeout 4 s) |
| | 0x2AA6 Central Addr Resolution | — | R | `01` |
| 0x1801 Generic Attribute | — | — | — | vazio |
| Nordic UART `6e400001-…` | RX `6e400002-…` | genérico (não-SCS) | W, WNR | — |
| | TX `6e400003-…` | genérico (não-SCS) | N | — |
| **SCS_ADMIN_SERVICE** `6d90c7b0-…` | `34d81c0d-…` = **SCS_AUTH_CHARACTERISTIC** | auth (escreve chave AES) | R, W | `02D90548C809000A00` |
| | `673ebc29-…` = **SCS_AUTH_RESPONSE_CHARACTERISTIC** | auth (resposta) | N, R | `02070000004100070000000000011006000100` |
| **SCS_ASSET_TRACK_SERVICE** `1deca38d-…` | `d224eeed-…` = **SCS_ASSET_TRACK_REQ_DATA_CHARACTERISTIC** | **grava comandos aqui** (1 byte, código do pedido) | W | — |
| | `0d3de66c-…` = **SCS_ASSET_TRACK_RX_CHARACTERISTIC** | escrita diversa | W | — |
| | `efdd2460-…` = **SCS_ASSET_TRACK_TX_CHARACTERISTIC** | notifica status/registro | N | — |
| | `23201dea-…` = **SCS_ASSET_TRACK_BOTTLER_ASSET_NUMBER** | nº do ativo do engarrafador/cliente | N, R, W | ASCII `GEUB031229` |
| | `864580ba-…` = **SCS_ASSET_TRACK_OEM_SERIAL_NUMBER** | nº de série OEM | N, R, W | ASCII `8261004922014076634` |
| | `d8eb11c3-…` = **SCS_ASSET_TRACK_COOLER_MODEL** | código do modelo do equipamento | N, R, W | ASCII `VB43` |
| | `ffdd2460-…` = **SCS_ASSET_TRACK_BULK_TX_CHARACTERISTIC** | **notifica os blocos de histórico** (até 1024 bytes/bloco) | N | — |
| **SCS_DIAGNOSTIC_SERVICE** `e523405a-…` | `dcd9889f-…` = **SCS_DIAGNOSTIC_TX_CHARACTERISTIC** | notifica diagnóstico | N | — |
| | `71d86c61-…` = **SCS_DIAGNOSTIC_RX_CHARACTERISTIC** | escreve diagnóstico | W | — |

(UUIDs completos, código de comandos e formato do cabeçalho de bloco:
[`wellington_scs_protocol.md`](wellington_scs_protocol.md).)

## Interpretação dos valores lidos — CONFIRMADO pelo usuário (2026-11-09)
- `VB43`: modelo da geladeira onde o sensor estava instalado
  (`SCS_ASSET_TRACK_COOLER_MODEL`).
- `GEUB031229` / `8261004922014076634`: também identificam esse mesmo
  equipamento/instalação (`BOTTLER_ASSET_NUMBER` / `OEM_SERIAL_NUMBER`),
  não são IDs de fábrica do sensor em si — são dados do cadastro do
  cliente/integrador pra esse cooler específico.
- `34d81c0d` / `673ebc29`: binários de 9 e 19 bytes ligados à **autenticação**
  (handshake AES), não "status/config" genérico como hipótese anterior.
- Ainda não vimos nenhum dado de temperatura/histórico — ele só sai depois
  do handshake de autenticação + comando `SCS_REQUEST_EVENT_START_ADDRESS`
  em `SCS_ASSET_TRACK_REQ_DATA_CHARACTERISTIC`, notificado em
  `SCS_ASSET_TRACK_BULK_TX_CHARACTERISTIC`.

## Pendências
- Confirmar byte a byte o handshake de autenticação AES (qual chave L1/L2/L3,
  qual IV) — não dá para deduzir só do nome da constante.
- Confirmar o layout de cada registro de temperatura dentro do bloco de
  1024 bytes (depois do cabeçalho de 16 bytes já decodificado).
- Capturar HCI snoop do app oficial conversando com o sensor real é o jeito
  mais direto de fechar os dois pontos acima.
- **NÃO escrever às cegas** em características R/W (Device Name e as de
  Asset Track podem alterar configuração do sensor).
