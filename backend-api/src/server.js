const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Arquivo local de persistência para não perder dados ao reiniciar
const DB_FILE = path.join(__dirname, 'database.json');

// Função para ler o banco
function readDatabase() {
  if (!fs.existsSync(DB_FILE)) {
    fs.writeFileSync(DB_FILE, JSON.stringify([], null, 2));
    return [];
  }
  try {
    const content = fs.readFileSync(DB_FILE, 'utf-8');
    return JSON.parse(content || '[]');
  } catch (e) {
    return [];
  }
}

// Função para salvar no banco
function saveDatabase(data) {
  fs.writeFileSync(DB_FILE, JSON.stringify(data, null, 2));
}

// Servir os arquivos do Web Dashboard e do App Mobile
const dashboardDir = path.join(__dirname, '../../web-dashboard');
app.use(express.static(dashboardDir));

// App Flutter rodando no navegador do PC (gerado por: flutter build web --base-href /app/)
app.use('/app', express.static(path.join(__dirname, '../../mobile-app/build/web')));

// Rota direta para o App Mobile no iPhone
app.get('/mobile', (req, res) => {
  res.sendFile(path.join(dashboardDir, 'app-screens-preview.html'));
});

// 1. Receber laudo do App Móvel
app.post('/api/tests', (req, res) => {
  const payload = req.body;
  if (!payload.serialNumber) {
    return res.status(400).json({ error: 'Nº de patrimônio/série obrigatório.' });
  }

  const tests = readDatabase();

  const newTest = {
    id: payload.testId || `TEST-${Date.now()}`,
    serialNumber: payload.serialNumber,
    modelName: payload.modelName || 'Equipamento Comercial',
    technicianName: payload.technicianName || 'Técnico de Campo',
    profileName: payload.profile?.name || payload.profileName || 'Perfil Padrão',
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

  tests.unshift(newTest);
  saveDatabase(tests);

  console.log(`[NOVO LAUDO GRAVADO] Geladeira: ${newTest.serialNumber} -> Status: ${newTest.status}`);
  res.status(201).json({ success: true, testId: newTest.id, status: newTest.status });
});

// 2. Listar testes para o Portal Web
app.get('/api/tests', (req, res) => {
  const { serialNumber, status } = req.query;
  let results = readDatabase();

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
  const tests = readDatabase();
  const test = tests.find(t => t.id === req.params.id);
  if (!test) return res.status(404).json({ error: 'Teste não encontrado.' });
  res.json(test);
});

// 4. Estatísticas gerenciais da frota
app.get('/api/stats', (req, res) => {
  const tests = readDatabase();
  const total = tests.length;
  const approved = tests.filter(t => t.status === 'APROVADA').length;
  const rejected = total - approved;
  const rate = total > 0 ? ((approved / total) * 100).toFixed(1) : 0;
  res.json({ total, approved, rejected, approvalRate: `${rate}%` });
});

// 5. Rota para resetar/limpar tudo a qualquer momento
app.post('/api/reset', (req, res) => {
  saveDatabase([]);
  console.log('[BANCO RESETADO] Todos os testes foram apagados.');
  res.json({ success: true, message: 'Banco de dados zerado com sucesso.' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`====================================================`);
  console.log(`  AoFrio System Ativo (${readDatabase().length} laudos em database.json)`);
  console.log(`  Portal Web:    http://localhost:${PORT}`);
  console.log(`  App no iPhone: http://192.168.0.68:${PORT}/mobile`);
  console.log(`====================================================`);
});
