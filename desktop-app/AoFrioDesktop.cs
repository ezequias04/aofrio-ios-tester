using System;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Threading;
using System.Windows.Forms;

namespace AoFrioTester
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            try
            {
                // Raiz = pasta acima do .exe (desktop-app/..); cai no caminho fixo se o exe foi movido.
                string projectRoot = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, ".."));
                if (!Directory.Exists(Path.Combine(projectRoot, "backend-api")))
                    projectRoot = @"C:\Users\PEREIRA\Desktop\AoFrio-Refrigeration-Testing-System";
                string backendPath = Path.Combine(projectRoot, "backend-api");
                string serverScript = Path.Combine(backendPath, "src", "server.js");

                // 1. Verifica se a porta 3000 já está ativa
                bool isPortOpen = false;
                try
                {
                    using (var client = new TcpClient())
                    {
                        var result = client.BeginConnect("127.0.0.1", 3000, null, null);
                        bool success = result.AsyncWaitHandle.WaitOne(600);
                        if (success && client.Connected)
                        {
                            isPortOpen = true;
                            client.EndConnect(result);
                        }
                    }
                }
                catch { }

                // 2. Se a porta não estiver aberta, inicia o Node.js em processo desacoplado
                if (!isPortOpen && File.Exists(serverScript))
                {
                    string protoNode = @"C:\Users\PEREIRA\.proto\shims\node.exe";
                    string nodeExe = File.Exists(protoNode) ? protoNode : "node";

                    ProcessStartInfo nodePsi = new ProcessStartInfo();
                    nodePsi.FileName = nodeExe;
                    nodePsi.Arguments = "src/server.js";
                    nodePsi.WorkingDirectory = backendPath;
                    nodePsi.WindowStyle = ProcessWindowStyle.Hidden;
                    nodePsi.CreateNoWindow = true;
                    nodePsi.UseShellExecute = true; // Mantém o processo vivo independentemente
                    try
                    {
                        Process.Start(nodePsi);
                    }
                    catch { }

                    // Aguarda até o servidor responder
                    for (int i = 0; i < 15; i++)
                    {
                        Thread.Sleep(300);
                        try
                        {
                            using (var client = new TcpClient())
                            {
                                var r = client.BeginConnect("127.0.0.1", 3000, null, null);
                                if (r.AsyncWaitHandle.WaitOne(400) && client.Connected)
                                {
                                    client.EndConnect(r);
                                    isPortOpen = true;
                                    break;
                                }
                            }
                        }
                        catch { }
                    }
                }

                // 3. Abre no modo Janela Desktop Standalone (Edge ou Chrome)
                string edgePath = @"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe";
                string chromePath = @"C:\Program Files\Google\Chrome\Application\chrome.exe";
                string browserExe = File.Exists(edgePath) ? edgePath : (File.Exists(chromePath) ? chromePath : null);

                string appUrl = "http://localhost:3000";
                string userDataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AoFrioTester", "Profile");
                Directory.CreateDirectory(userDataDir);

                if (browserExe != null)
                {
                    ProcessStartInfo appPsi = new ProcessStartInfo();
                    appPsi.FileName = browserExe;
                    appPsi.Arguments = string.Format("--app=\"{0}\" --user-data-dir=\"{1}\" --window-size=1360,880 --app-id=AoFrioRefrigerationTester", appUrl, userDataDir);
                    appPsi.UseShellExecute = true;
                    Process.Start(appPsi);
                }
                else
                {
                    Process.Start(appUrl);
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("Erro ao iniciar AoFrio Tester: " + ex.Message, "AoFrio Tester", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
