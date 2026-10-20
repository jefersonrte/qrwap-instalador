# QRWAP Atendimento — instalador

Painel de atendimento por WhatsApp (conexão por QR Code) que roda no seu computador Windows. Este repositório só distribui o **instalador** e os
**pacotes** de cada versão.

## Instalar (ou atualizar)

Abra o **PowerShell como administrador** (menu Iniciar → digite *PowerShell* → botão direito → *Executar como administrador*) e cole:

```powershell
irm https://raw.githubusercontent.com/jefersonrte/qrwap-instalador/main/instalar.ps1 | iex
```

O instalador:
1. confere o computador (Windows 10/11, virtualização ligada, espaço em disco, memória);
2. **instala o Docker Desktop** se não houver (pede o seu OK por causa da licença da Docker);
3. baixa a **última versão** daqui (aba *Releases*) e instala em `C:\QRWAP`;
4. sobe o sistema, cria o atalho **QRWAP Atendimento** na área de trabalho e abre o painel;
5. deixa tudo para **iniciar junto com o computador**.

Para **atualizar**, rode o mesmo comando (ou `C:\QRWAP\ATUALIZAR.bat`): ele guarda uma cópia do banco, troca o código e mantém seus dados.

## Primeiro acesso

- Endereço: `http://localhost:8080` (o painel só atende este computador)
- E-mail: `admin@qrwap.local` — senha inicial: `Qrwap@2026`
- O sistema **obriga a trocar a senha** no primeiro acesso, antes de abrir qualquer tela.
- Depois: *Administração → WhatsApp → Conectar e gerar QR Code* e leia com o celular (WhatsApp → Aparelhos conectados).

## Requisitos e avisos

- Windows 10 (2004 ou mais novo) ou 11, com a virtualização (VT-x/SVM) ligada na BIOS; 8 GB de memória ou mais é o ideal; ~8 GB livres em disco.
- Se o Windows pedir para **reiniciar** (WSL2 do Docker), reinicie e rode o mesmo comando: ele continua.
- O Windows só inicia programas depois que alguém entra na conta; para subir sozinho depois de uma queda de energia, deixe a entrada automática ligada.
- A conexão por QR Code **não é a API oficial** do WhatsApp: use um número dedicado ao atendimento (números usados para disparo em massa podem ser bloqueados).
- Docker Desktop: grátis para uso pessoal e empresas pequenas (menos de 250 funcionários e US$ 10 milhões/ano); acima disso é pago.
- Desinstalar: `C:\QRWAP\DESINSTALAR.bat` (remove também o banco e a conexão do WhatsApp).

Repositório com chave (se você mantiver uma cópia privada): antes do comando, `$env:QRWAP_TOKEN = '<chave do GitHub>'` e `$env:QRWAP_REPO = 'dono/repo'`.
