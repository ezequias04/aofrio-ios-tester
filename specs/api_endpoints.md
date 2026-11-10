# Especificação dos Endpoints REST (Backend API)

API leve e de alto desempenho que faz a ponte entre o **App Móvel (Coletor de Ensaios)** e o **Portal Web (Consulta de Relatórios)**.

---

## 1. POST /api/tests
Envia um laudo de teste concluído com as séries temporais de temperatura baixadas do AoFrio.

### Corpo da Requisição (JSON):
```json
{
  "serialNumber": "GEL-METAFRIO-8821",
  "model": "Refrigerador Vertical 450L",
  "technician": "Carlos Pereira",
  "notes": "Bancada 03 - Troca de compressor",
  "targetTemperature": 3.0,
  "maxAllowedMinutes": 90,
  "readings": [
    {
      "timestamp": "2026-11-09T08:00:00Z",
      "temperature": 27.5,
      "doorOpen": false,
      "compressorActive": true
    },
    {
      "timestamp": "2026-11-09T08:15:00Z",
      "temperature": 23.2,
      "doorOpen": false,
      "compressorActive": true
    }
  ]
}
```

### Resposta de Sucesso (`201 Created`):
```json
{
  "success": true,
  "testId": "TEST-20261109-1",
  "status": "APROVADA",
  "message": "Ensaio processado e registrado com sucesso."
}
```

---

## 2. GET /api/tests
Lista os testes registrados para o portal web, com filtros de busca.

### Parâmetros de Consulta (Query Params):
* `serialNumber` (opcional): Filtro por texto parcial.
* `status` (opcional): `APROVADA` ou `REPROVADA`.
* `limit` (opcional, padrão 50).

### Resposta:
```json
[
  {
    "id": "TEST-20261109-1",
    "serialNumber": "GEL-METAFRIO-8821",
    "model": "Refrigerador Vertical 450L",
    "technician": "Carlos Pereira",
    "status": "APROVADA",
    "createdAt": "2026-11-09T09:10:00Z",
    "metrics": {
      "initialTemp": 27.5,
      "finalTemp": 2.8,
      "durationMinutes": 58,
      "doorOpenCount": 0
    }
  }
]
```

---

## 3. GET /api/tests/:id
Obtém o laudo completo com todos os pontos da série temporal para renderizar o gráfico no navegador.
