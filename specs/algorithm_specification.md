# Especificação Matemática do Algoritmo de Pull-Down (Ensaio Térmico)

O **Ensaio de Pull-Down** é o procedimento padrão da engenharia de refrigeração para qualificar a capacidade do sistema frigorífico de reduzir a temperatura de um gabinete carregado ou vazio a partir da temperatura ambiente até a faixa de conservação pretendida.

---

## 1. Variáveis de Entrada do Ensaio

| Símbolo | Nome | Descrição | Exemplo |
| :--- | :--- | :--- | :--- |
| $T_{\text{amb}}$ | Temperatura Ambiente | Temperatura externa do ar no início do teste. | $28.0^\circ\text{C}$ |
| $T_{\text{ini}}$ | Temperatura Inicial | Temperatura interna no instante do fechamento da porta. | $27.5^\circ\text{C}$ |
| $T_{\text{alvo}}$ | Temperatura Alvo (Set-point) | Limite máximo aceitável para considerar resfriada. | $3.0^\circ\text{C}$ (Bebidas) / $-18.0^\circ\text{C}$ (Freezer) |
| $t_{\text{max}}$ | Tempo Máximo Tolerado | Prazo limite estipulado no perfil de teste. | $90 \text{ minutos}$ |
| $S(t)$ | Série Temporal | Conjunto de amostras gravadas na memória do AoFrio: $\{t_i, T_i, P_i, C_i\}$ | Onde $P_i \in \{0, 1\}$ (porta) e $C_i \in \{0, 1\}$ (compressor). |

---

## 2. Detecção Automática do Ponto de Início ($t_0$)

Como o técnico não aciona um cronômetro ao vivo, o algoritmo varre os dados da memória interna do sensor:

1. **Condição de Início ($t_0$):**
   * Ponto em que a derivada da temperatura torna-se negativa de forma sustentada:
     $$\frac{dT}{dt} \le -0.15^\circ\text{C}/\text{min} \quad \text{durante pelo menos 5 minutos consecutivos}$$
   * E o sensor de porta registra fechamento contínuo ($P_i = 0$).
2. A temperatura nessa estampa de tempo $t_0$ é fixada como $T_{\text{ini}}$.

---

## 3. Detecção do Ponto de Conclusão ($t_f$)

1. O ensaio é considerado concluído com sucesso no menor instante $t_f > t_0$ em que:
   $$T(t_f) \le T_{\text{alvo}}$$
2. O tempo de pull-down realizado ($\Delta t_{\text{pd}}$) é:
   $$\Delta t_{\text{pd}} = t_f - t_0$$

---

## 4. Métricas Derivadas

### A. Taxa Média de Resfriamento ($R_{\text{méd}}$)
Mede a velocidade média de extração de calor do gabinete:
$$R_{\text{méd}} = \frac{T_{\text{ini}} - T(t_f)}{\Delta t_{\text{pd}}} \quad [^\circ\text{C}/\text{min}]$$

### B. Taxa Inicial de Resposta (Primeiros 15 minutos)
Avalia se o compressor deu partida imediata:
$$\Delta T_{15} = T_{\text{ini}} - T(t_0 + 15\text{min})$$
* **Critério de Falha:** Se $\Delta T_{15} < 1.5^\circ\text{C}$, indica falha no relé de partida, termostato desregulado ou vazamento catastrófico de gás.

### C. Auditoria de Interferências Externas
* **Contagem de Aberturas de Porta ($N_{\text{portas}}$):**
  $$N_{\text{portas}} = \sum_{t = t_0}^{t_f} (\text{transições de } 0 \to 1 \text{ no sensor de porta})$$
  * Se $N_{\text{portas}} > 0$: Alerta de teste comprometido por violação térmica.
* **Fator de Operação do Compressor ($F_{\text{comp}}$):**
  $$F_{\text{comp}} = \frac{\text{Tempo de Compressor Ativo entre } t_0 \text{ e } t_f}{\Delta t_{\text{pd}}}$$
  * Durante o pull-down, espera-se $F_{\text{comp}} \ge 0.95$ (compressor operando direto sem desarmar por térmico).

---

## 5. Matriz de Decisão do Veredito

```
                ┌──────────────────────────────────────┐
                │        Início da Avaliação           │
                └──────────────────┬───────────────────┘
                                   │
                     ¿Atingiu T_alvo em t <= t_max?
                                   │
                    ┌──────────────┴──────────────┐
                   SIM                           NÃO
                    │                             │
          ¿Houve Abertura de Porta?        REPROVADA
                    │                  (Tempo Excedido)
           ┌────────┴────────┐
          NÃO               SIM
           │                 │
       APROVADA           APROVADA COM ALERTA
                     (Interferência de Porta)
```

---

## 6. Exemplo de Saída JSON do Algoritmo

```json
{
  "testId": "TEST-20261109-001",
  "serialNumber": "GEL-METAFRIO-8821",
  "model": "Refrigerador Vertical 450L",
  "status": "APROVADA",
  "metrics": {
    "startTime": "2026-11-09T08:00:00Z",
    "endTime": "2026-11-09T08:58:00Z",
    "durationMinutes": 58,
    "maxAllowedMinutes": 90,
    "initialTemperature": 26.8,
    "finalTemperature": 2.8,
    "targetTemperature": 3.0,
    "coolingRateDegPerMin": 0.41,
    "doorOpenCount": 0,
    "compressorDutyCycle": 1.0
  },
  "verdictReason": "Atingiu a meta de 3.0°C em 58 minutos (limite era 90 min) sem aberturas de porta."
}
```
