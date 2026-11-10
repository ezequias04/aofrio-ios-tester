const express = require('express');
const cors = require('cors');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Servir os arquivos do Web Dashboard e do App Mobile
const dashboardDir = path.join(__dirname, '../../web-dashboard');
app.use(express.static(dashboardDir));

// Rota direta para o App Mobile no iPhone
app.get('/mobile', (req, res) => {
  res.sendFile(path.join(dashboardDir, 'app-screens-preview.html'));
});

// Banco de dados em memória inicial com ensaios pré-carregados
let testsDatabase = [
  {
    id: "TEST-20261108-001",
    serialNumber: "GEL-METAFRIO-8821",
    modelName: "Refrigerador Vertical 450L",
    technicianName: "Carlos Pereira",
    profileName: "Expositor de Bebidas (0°C a 4°C)",
    status: "APROVADA",
    verdictReason: "Atingiu a meta de 3.0°C em 54 minutos (limite era 90 min) sem violações.",
    initialTemp: 26.8,
    finalTemp: 2.8,
    targetTemp: 3.0,
    maxAllowedMinutes: 90,
    durationMinutes: 54,
    coolingRate: 0.44,
    doorOpenEvents: 0,
    compressorDutyCycle: 1.0,
    createdAt: new Date(Date.now() - 86400000).toISOString(),
    readings: generateMockCurve(26.8, 2.8, 54, 0)
  },
  {
    id: "TEST-20261108-002",
    serialNumber: "CERV-GELOPAR-402",
    modelName: "Cervejeira Slim Porta de Vidro",
    technicianName: "Carlos Pereira",
    profileName: "Cervejeira (-4°C a -2°C)",
    status: "APROVADA",
    verdictReason: "Atingiu -2.2°C em 82 minutos com 100% de estabilidade.",
    initialTemp: 28.0,
    finalTemp: -2.2,
    targetTemp: -2.0,
    maxAllowedMinutes: 110,
    durationMinutes: 82,
    coolingRate: 0.37,
    doorOpenEvents: 0,
    compressorDutyCycle: 1.0,
    createdAt: new Date(Date.now() - 43200000).toISOString(),
    readings: generateMockCurve(28.0, -2.2, 82, 0)
  },
  {
    id: "TEST-20261109-003",
    serialNumber: "GEL-CONSUL-5510",
    modelName: "Expositor Comercial 300L",
    technicianName: "Marcos Inspetor",
    profileName: "Expositor de Bebidas (0°C a 4°C)",
    status: "REPROVADA",
    verdictReason: "Tempo limite excedido: estabilizou em 11.5°C sem vencer a carga térmica (suspeita de falta de fluido refrigerante).",
    initialTemp: 27.5,
    finalTemp: 11.5,
    targetTemp: 3.0,
    maxAllowedMinutes: 90,
    durationMinutes: 120,
    coolingRate: 0.13,
    doorOpenEvents: 0,
    compressorDutyCycle: 0.98,
    createdAt: new Date(Date.now() - 7200000).toISOString(),
    readings: generateMockCurve(27.5, 11.5, 120, 0)
  }
];

// Helper para gerar pontos de curva
function generateMockCurve(startTemp, endTemp, minutes, doorOpens) {
  const points = [];
  const startTime = new Date(Date.now() - minutes * 60000);
  for (let m = 0; m <= minutes; m += 2) {
    const progress = m / minutes;
    const currentTemp = startTemp - (startTemp - endTemp) * Math.pow(progress, 0.7);
    points.push({
      timestamp: new Date(startTime.getTime() + m * 60000).toISOString(),
      temperature: parseFloat(currentTemp.toFixed(1)),
      doorOpen: false,
      compressorActive: true
    });
  }
  return points;
}

// 1. Receber laudo do App Móvel
app.post('/api/tests', (req, res) => {
  const payload = req.body;
  if (!payload.serialNumber) {
    return res.status(400).json({ error: 'Nº de série obrigatório.' });
  }

  const newTest = {
    id: payload.testId || `TEST-${Date.now()}`,
    serialNumber: payload.serialNumber,
    modelName: payload.modelName || 'Equipamento Comercial',
    technicianName: payload.technicianName || 'Técnico de Campo',
    profileName: payload.profile?.name || 'Perfil Padrão',
    status: payload.status || 'APROVADA',
    verdictReason: payload.verdictReason || 'Ensaio finalizado.',
    initialTemp: payload.initialTemp,
    finalTemp: payload.finalTemp,
    targetTemp: payload.targetTemp,
    maxAllowedMinutes: payload.maxAllowedMinutes,
    durationMinutes: payload.durationMinutes,
    coolingRate: payload.coolingRate,
    doorOpenEvents: payload.doorOpenEvents || 0,
    compressorDutyCycle: payload.compressorDutyCycle || 1.0,
    createdAt: new Date().toISOString(),
    readings: payload.readings || []
  };

  testsDatabase.unshift(newTest);
  console.log(`[NOVO LAUDO] Recebido teste da geladeira: ${newTest.serialNumber} -> Status: ${newTest.status}`);
  res.status(201).json({ success: true, testId: newTest.id, status: newTest.status });
});

// 2. Listar testes para o Portal Web
app.get('/api/tests', (req, res) => {
  const { serialNumber, status } = req.query;
  let results = [...testsDatabase];

  if (serialNumber) {
    results = results.filter(t => t.serialNumber.toLowerCase().includes(serialNumber.toLowerCase()));
  }
  if (status) {
    results = results.filter(t => t.status.toUpperCase() === status.toUpperCase());
  }

  // Não envia a série temporal completa na listagem para economizar banda
  const summaries = results.map(({ readings, ...rest }) => rest);
  res.json(summaries);
});

// 3. Obter detalhes e gráfico de um teste específico
app.get('/api/tests/:id', (req, res) => {
  const test = testsDatabase.find(t => t.id === req.params.id);
  if (!test) return res.status(404).json({ error: 'Teste não encontrado.' });
  res.json(test);
});

// 4. Estatísticas gerenciais da frota
app.get('/api/stats', (req, res) => {
  const total = testsDatabase.length;
  const approved = testsDatabase.filter(t => t.status === 'APROVADA').length;
  const rejected = total - approved;
  const rate = total > 0 ? ((approved / total) * 100).toFixed(1) : 0;
  res.json({ total, approved, rejected, approvalRate: `${rate}%` });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`====================================================`);
  console.log(`  AoFrio System Ativo na Rede Local!`);
  console.log(`  Portal Web:    http://localhost:${PORT}`);
  console.log(`  App no iPhone: http://192.168.0.68:${PORT}/mobile`);
  console.log(`====================================================`);
});
