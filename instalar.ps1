<#
  QRWAP Atendimento - instalador e atualizador (Windows 10/11)

  Instalar OU atualizar (o mesmo comando; é seguro repetir):
      irm https://raw.githubusercontent.com/jefersonrte/qrwap-instalador/main/instalar.ps1 | iex

  O que ele faz, nesta ordem:
    1. confere o computador (Windows, virtualização, espaço em disco, memória);
    2. instala o Docker Desktop se não houver (com o seu OK, por causa da licença da Docker);
    3. baixa a última versão do QRWAP no GitHub (release) e a coloca em C:\QRWAP\app;
    4. guarda uma cópia do banco antes de atualizar;
    5. sobe o sistema (banco + OpenWA + painel) e espera ele responder;
    6. cria o atalho na área de trabalho e abre o painel.

  Ajustes (variáveis de ambiente, definidas ANTES do irm):
      $env:QRWAP_PASTA  = 'D:\QRWAP'   pasta de instalação (padrão C:\QRWAP)
      $env:QRWAP_PORTA  = '8080'       porta do painel neste computador (padrão 8080)
      $env:QRWAP_REPO   = 'dono/repo'  repositório do GitHub com as versões (padrão jefersonrte/qrwap-instalador)
      $env:QRWAP_TOKEN  = '...'        chave do GitHub (só se o repositório for privado)
      $env:QRWAP_ACEITO = '1'          aceita sem perguntar a licença do Docker Desktop
      $env:QRWAP_ORIGEM = 'caminho ou URL de um .zip'   instala deste pacote (testes) em vez do GitHub
      $env:QRWAP_PROJETO = 'nome'      nome do projeto no Docker (para ter duas instalações lado a lado; padrão qrwap)
      $env:QRWAP_AUTOATUALIZAR = '1'   cria uma tarefa que procura versão nova toda semana
      $env:QRWAP_SEMPRE_LIGADO = '1'   (ou '0') não deixa o computador dormir na tomada; sem isto o instalador pergunta
#>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------------------------- ajustes
$Repo      = if ($env:QRWAP_REPO)  { $env:QRWAP_REPO }  else { 'jefersonrte/qrwap-instalador' }
$Pasta     = if ($env:QRWAP_PASTA) { $env:QRWAP_PASTA.TrimEnd('\') } else { 'C:\QRWAP' }
$PortaPedida = if ($env:QRWAP_PORTA) { [int]$env:QRWAP_PORTA } else { 0 }
$UrlScript = "https://raw.githubusercontent.com/$Repo/main/instalar.ps1"
$SenhaInicial = 'Qrwap@2026'                       # senha genérica do primeiro acesso: o sistema obriga a trocar ao entrar
$App       = Join-Path $Pasta 'app'
$Backups   = Join-Path $Pasta 'backups'
$Log       = Join-Path $Pasta 'instalacao.log'

function Linha($texto, $cor = 'Gray') { Write-Host $texto -ForegroundColor $cor }
function Titulo($texto) { Write-Host ''; Write-Host "==> $texto" -ForegroundColor Cyan }
function Ok($texto) { Write-Host "    ok  $texto" -ForegroundColor Green }
function Aviso($texto) { Write-Host "    !   $texto" -ForegroundColor Yellow }
function Falhar($texto) { Write-Host ''; Write-Host "ERRO: $texto" -ForegroundColor Red; throw $texto }

# comandos nativos (docker) escrevem avisos em stderr: no Windows PowerShell 5.1 isso viraria erro fatal com 'Stop'
function Nativo([scriptblock]$bloco) { $antes = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { & $bloco } finally { $ErrorActionPreference = $antes } }

function Cabecalhos {
    $h = @{ 'User-Agent' = 'QRWAP-instalador'; 'Accept' = 'application/vnd.github+json' }
    if ($env:QRWAP_TOKEN) { $h['Authorization'] = 'Bearer ' + $env:QRWAP_TOKEN }
    return $h
}

# ------------------------------------------------------------------------ 0. precisa ser administrador
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Linha 'O instalador precisa de permissão de administrador (para instalar o Docker). Vou pedir a autorização do Windows...' Yellow
    $temp = Join-Path $env:TEMP 'qrwap-instalar.ps1'
    # as opções vão no começo do arquivo: o processo elevado não herda as variáveis desta janela
    $prelude = ''
    foreach ($n in 'QRWAP_PASTA', 'QRWAP_PORTA', 'QRWAP_REPO', 'QRWAP_TOKEN', 'QRWAP_ACEITO', 'QRWAP_ORIGEM', 'QRWAP_AUTOATUALIZAR', 'QRWAP_PROJETO', 'QRWAP_SEMPRE_LIGADO') {
        $v = [Environment]::GetEnvironmentVariable($n)
        if ($v) { $prelude += "`$env:$n = '" + $v.Replace("'", "''") + "'`r`n" }
    }
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        $corpo = Get-Content $PSCommandPath -Raw
    } else {
        $corpo = (Invoke-WebRequest -UseBasicParsing -Headers (Cabecalhos) -Uri $UrlScript).Content
    }
    Set-Content -Path $temp -Value ($prelude + $corpo) -Encoding UTF8
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$temp`""
    return
}

New-Item -ItemType Directory -Force -Path $Pasta, $Backups | Out-Null
try { Start-Transcript -Path $Log -Append | Out-Null } catch { }

try {
    Linha ''
    Linha '  QRWAP Atendimento - instalação e atualização' White
    Linha "  Pasta: $Pasta" DarkGray

    # --------------------------------------------------------------------------------- 1. o computador
    Titulo 'Conferindo o computador'
    $so = Get-CimInstance Win32_OperatingSystem
    if ([int]$so.BuildNumber -lt 19041) { Falhar "Precisa do Windows 10 (versão 2004 ou mais nova) ou do Windows 11. Este é: $($so.Caption) ($($so.BuildNumber))." }
    Ok $so.Caption
    $virt = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent -or ((Get-CimInstance Win32_Processor | Select-Object -First 1).VirtualizationFirmwareEnabled)
    if (-not $virt) { Falhar 'A virtualização está desligada. Entre na BIOS/UEFI do computador e ligue "Intel VT-x / Virtualization Technology" (ou "SVM Mode" nos AMD), depois rode este comando de novo.' }
    Ok 'virtualização ligada'
    $livre = [math]::Round((Get-PSDrive -Name ($Pasta.Substring(0, 1))).Free / 1GB, 1)
    if ($livre -lt 8) { Falhar "Pouco espaço em disco: $livre GB livres em $($Pasta.Substring(0,2)). O sistema usa cerca de 5 GB; deixe pelo menos 8 GB." }
    Ok "$livre GB livres em disco"
    $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    if ($ram -lt 6) { Aviso "Só $ram GB de memória: funciona, mas pode ficar lento. O ideal é 8 GB ou mais." } else { Ok "$ram GB de memória" }

    # --------------------------------------------------------------------------------- 2. Docker Desktop
    Titulo 'Docker Desktop'
    $dockerBin = 'C:\Program Files\Docker\Docker\resources\bin'
    if ((Test-Path $dockerBin) -and ($env:Path -notlike "*$dockerBin*")) { $env:Path += ";$dockerBin" }
    $temDocker = [bool](Get-Command docker -ErrorAction SilentlyContinue)
    if (-not $temDocker) {
        Linha '    O Docker Desktop não está instalado. Ele é o programa que roda o sistema.' White
        Linha '    Licença da Docker: o Docker Desktop é grátis para uso pessoal, ensino e empresas pequenas' DarkGray
        Linha '    (menos de 250 funcionários e menos de US$ 10 milhões por ano); acima disso é pago.' DarkGray
        Linha '    Termos: https://www.docker.com/legal/docker-subscription-service-agreement/' DarkGray
        if ($env:QRWAP_ACEITO -ne '1') {
            $r = Read-Host '    Digite S para aceitar a licença e instalar o Docker Desktop (qualquer outra tecla cancela)'
            if ($r -notmatch '^[sSyY]') { Falhar 'Instalação cancelada: sem o Docker Desktop o sistema não roda.' }
        }
        $arq = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
        $instalador = Join-Path $env:TEMP 'DockerDesktopInstaller.exe'
        Linha "    Baixando o instalador (cerca de 600 MB, pode demorar)..." DarkGray
        Invoke-WebRequest -UseBasicParsing -Uri "https://desktop.docker.com/win/main/$arq/Docker%20Desktop%20Installer.exe" -OutFile $instalador
        $assinatura = Get-AuthenticodeSignature $instalador
        if ($assinatura.Status -ne 'Valid' -or $assinatura.SignerCertificate.Subject -notmatch 'Docker Inc') {
            Remove-Item $instalador -Force -ErrorAction SilentlyContinue
            Falhar 'O instalador baixado não tem a assinatura da Docker Inc. Por segurança, parei aqui.'
        }
        Ok 'instalador assinado pela Docker Inc'
        Linha '    Instalando (alguns minutos)...' DarkGray
        $p = Start-Process -FilePath $instalador -ArgumentList 'install', '--quiet', '--accept-license', '--backend=wsl-2' -Wait -PassThru
        Remove-Item $instalador -Force -ErrorAction SilentlyContinue
        if ($p.ExitCode -notin 0, 3010) { Falhar "O instalador do Docker terminou com o código $($p.ExitCode)." }
        if (Test-Path $dockerBin) { $env:Path += ";$dockerBin" }
        $reiniciar = ($p.ExitCode -eq 3010) -or -not (Get-Command wsl -ErrorAction SilentlyContinue)
        Ok 'Docker Desktop instalado'
        if ($reiniciar) {
            Write-Host ''
            Linha '  O Windows precisa REINICIAR para terminar de preparar o Docker (WSL2).' Yellow
            Linha '  Reinicie o computador e rode o MESMO comando de novo: ele continua de onde parou.' Yellow
            return
        }
    } else {
        Ok 'Docker Desktop já instalado'
    }

    # o motor precisa estar de pé
    function MotorDocker { try { $v = Nativo { docker info --format '{{.ServerVersion}}' 2>$null }; return [bool]$v } catch { return $false } }
    if (-not (MotorDocker)) {
        Linha '    Iniciando o Docker Desktop (a primeira vez demora)...' DarkGray
        $exe = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
        if (-not (Test-Path $exe)) { Falhar 'Não encontrei o Docker Desktop instalado. Instale-o e rode este comando de novo.' }
        Start-Process $exe
        $limite = (Get-Date).AddMinutes(6)
        while (-not (MotorDocker)) {
            if ((Get-Date) -gt $limite) {
                Falhar 'O Docker Desktop não ficou pronto em 6 minutos. Abra o Docker Desktop, espere o ícone da baleia parar de se mexer (e aceite o que ele pedir), depois rode este comando de novo.'
            }
            Start-Sleep -Seconds 5
        }
    }
    Ok 'Docker pronto'

    # --------------------------------------------------------------------------------- 3. versão
    Titulo 'Procurando a versão'
    $instalada = $null
    $nucleo = Join-Path $App 'site\interno\nucleo.php'
    if (Test-Path $nucleo) {
        $m = [regex]::Match((Get-Content $nucleo -Raw), "WAP_VERSAO = '([^']+)'")
        if ($m.Success) { $instalada = $m.Groups[1].Value }
    }
    if ($instalada) { Linha "    Instalada agora: $instalada" DarkGray } else { Linha '    Nenhuma instalação anterior.' DarkGray }

    $zip = Join-Path $env:TEMP 'qrwap-pacote.zip'
    $nova = $null
    if ($env:QRWAP_ORIGEM) {
        if ($env:QRWAP_ORIGEM -match '^https?://') { Invoke-WebRequest -UseBasicParsing -Headers (Cabecalhos) -Uri $env:QRWAP_ORIGEM -OutFile $zip } else { Copy-Item $env:QRWAP_ORIGEM $zip -Force }
        $nova = 'do pacote informado'
    } else {
        try {
            $rel = Invoke-RestMethod -Headers (Cabecalhos) -Uri "https://api.github.com/repos/$Repo/releases/latest"
        } catch {
            Falhar "Não consegui ler a última versão em github.com/$Repo ($($_.Exception.Message)). Confira a internet; se o repositório for privado, defina `$env:QRWAP_TOKEN antes do comando."
        }
        $nova = ([string]$rel.tag_name).TrimStart('v')
        Linha "    Última versão: $nova" DarkGray
        if ($instalada -and ([version]$instalada -ge [version]$nova) -and (Test-Path (Join-Path $App 'docker-compose.yml'))) {
            Ok "Já está na versão mais nova ($instalada). Só confirmo que está rodando."
            $nova = $null
        } else {
            $asset = $rel.assets | Where-Object { $_.name -like 'qrwap-*.zip' } | Select-Object -First 1
            $h = Cabecalhos
            if ($asset) { $h['Accept'] = 'application/octet-stream'; $url = $asset.url } else { $url = $rel.zipball_url }
            Linha '    Baixando...' DarkGray
            Invoke-WebRequest -UseBasicParsing -Headers $h -Uri $url -OutFile $zip
        }
    }

    # --------------------------------------------------------------------------------- 4. arquivos (com cópia do banco antes)
    if ($nova) {
        Titulo $(if ($instalada) { "Atualizando $instalada -> $nova" } else { 'Instalando' })
        if ($instalada) {
            try {
                Push-Location $App
                $copia = Join-Path $Backups ("qrwap-banco-$instalada-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.sql')
                Nativo { docker compose exec -T db sh -c 'mariadb-dump -uqrwap -p"$MARIADB_PASSWORD" qrwap > /tmp/qrwap.sql' 2>$null }
                Nativo { docker compose cp db:/tmp/qrwap.sql $copia 2>$null }
                if ((Test-Path $copia) -and (Get-Item $copia).Length -gt 500) { Ok "cópia do banco em $copia" } else { Remove-Item $copia -Force -ErrorAction SilentlyContinue; Aviso 'não consegui copiar o banco (o sistema estava parado?); sigo mesmo assim' }
            } catch { Aviso 'não consegui copiar o banco; sigo mesmo assim' } finally { Pop-Location }
            Get-ChildItem $Backups -Filter 'qrwap-banco-*.sql' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 5 | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        $tmp = Join-Path $env:TEMP ('qrwap-extrair-' + [guid]::NewGuid().ToString('N'))
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        $raiz = Get-ChildItem $tmp | Where-Object { Test-Path (Join-Path $_.FullName 'docker-compose.yml') } | Select-Object -First 1
        if (-not $raiz) { $raiz = Get-Item $tmp }
        if (-not (Test-Path (Join-Path $raiz.FullName 'docker-compose.yml'))) { Falhar 'O pacote baixado não tem o docker-compose.yml: não é uma versão do QRWAP.' }
        New-Item -ItemType Directory -Force -Path $App | Out-Null
        # troca o código, preservando o que é desta instalação (senha do banco, porta, acesso)
        Get-ChildItem $App -Force | Where-Object { $_.Name -notin '.env', 'ACESSO' } | Remove-Item -Recurse -Force
        Copy-Item -Path (Join-Path $raiz.FullName '*') -Destination $App -Recurse -Force
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Ok 'arquivos no lugar'
    }

    # --------------------------------------------------------------------------------- 5. configuração desta instalação
    Titulo 'Configurando'
    $envArq = Join-Path $App '.env'
    $conf = @{}
    if (Test-Path $envArq) { foreach ($l in Get-Content $envArq) { if ($l -match '^([A-Z_]+)=(.*)$') { $conf[$Matches[1]] = $Matches[2] } } }
    if (-not $conf['DB_SENHA']) { $conf['DB_SENHA'] = -join ((48..57) + (97..122) | Get-Random -Count 28 | ForEach-Object { [char]$_ }) }
    function PortaLivre([int]$p) { -not (Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue) }
    $porta = if ($PortaPedida) { $PortaPedida } elseif ($conf['PORTA']) { [int]$conf['PORTA'] } else { 8080 }
    # só procura outra porta quando ela é nova (instalação nova ou porta diferente da guardada): a guardada é do próprio
    # QRWAP, que já está usando-a, e pareceria "ocupada" numa atualização
    if (-not $conf['PORTA'] -or $porta -ne [int]$conf['PORTA']) {
        while (-not (PortaLivre $porta)) { $porta++; if ($porta -gt 8099) { Falhar 'Nenhuma porta livre entre 8080 e 8099. Libere uma ou use $env:QRWAP_PORTA.' } }
    }
    $conf['PORTA'] = [string]$porta
    if ($env:QRWAP_PROJETO) { $conf['COMPOSE_PROJECT_NAME'] = $env:QRWAP_PROJETO }
    if (-not $conf['ADMIN_SENHA_INICIAL']) { $conf['ADMIN_SENHA_INICIAL'] = $SenhaInicial }
    ($conf.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "`r`n" | Set-Content -Path $envArq -Encoding ASCII
    Ok "painel em http://localhost:$porta"

    # --------------------------------------------------------------------------------- 6. subir
    Titulo 'Subindo o sistema (a primeira vez baixa as imagens, uns 2 GB)'
    Push-Location $App
    try {
        Nativo { docker compose up -d --build 2>&1 | ForEach-Object { Linha "    $_" DarkGray } }
        if ($LASTEXITCODE -ne 0) { Falhar 'O docker compose não conseguiu subir o sistema (veja as linhas acima).' }
    } finally { Pop-Location }
    $limite = (Get-Date).AddMinutes(6)
    $pronto = $false
    while (-not $pronto) {
        try { $s = Invoke-RestMethod "http://localhost:$porta/saude.php" -TimeoutSec 5; $pronto = [bool]$s.ok } catch { }
        if ($pronto) { break }
        if ((Get-Date) -gt $limite) { Falhar "O painel não respondeu em 6 minutos em http://localhost:$porta/. Abra o Docker Desktop, veja os logs do contêiner 'app' e rode este comando de novo." }
        Start-Sleep -Seconds 4
    }
    Ok "painel no ar, versão $($s.versao)"

    # --------------------------------------------------------------------------------- 7. atalhos e utilitários
    Titulo 'Atalhos'
    Set-Content -Path (Join-Path $Pasta 'ATUALIZAR.bat') -Encoding ASCII -Value @"
@echo off
title QRWAP - atualizar
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm $UrlScript | iex"
pause
"@
    Set-Content -Path (Join-Path $Pasta 'PARAR.bat') -Encoding ASCII -Value "@echo off`r`ncd /d `"$App`"`r`ndocker compose stop`r`necho Parado. Os dados ficam guardados. Para ligar: docker compose start (ou rode ATUALIZAR.bat).`r`npause"
    Set-Content -Path (Join-Path $Pasta 'DESINSTALAR.bat') -Encoding ASCII -Value @"
@echo off
echo Isto REMOVE o QRWAP deste computador, inclusive o banco de dados e a conexao do WhatsApp.
set /p ok=Digite APAGAR para confirmar:
if /i not "%ok%"=="APAGAR" (echo Cancelado. & pause & exit /b)
cd /d "$App"
docker compose down -v
schtasks /Delete /TN "QRWAP Iniciar" /F >nul 2>nul
schtasks /Delete /TN "QRWAP Atualizar" /F >nul 2>nul
cd /d "$Pasta\.."
echo Os arquivos em $Pasta podem ser apagados a mao (mantive a pasta backups).
pause
"@
    $atalho = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'QRWAP Atendimento.url'
    Set-Content -Path $atalho -Encoding ASCII -Value "[InternetShortcut]`r`nURL=http://localhost:$porta/"
    Ok ('atalho "QRWAP Atendimento" na área de trabalho; ATUALIZAR.bat, PARAR.bat e DESINSTALAR.bat em ' + $Pasta)
    if ($env:QRWAP_AUTOATUALIZAR -eq '1') {
        $acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"`$env:QRWAP_ACEITO='1'; irm $UrlScript | iex`""
        Register-ScheduledTask -TaskName 'QRWAP Atualizar' -Action $acao -Trigger (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am) -RunLevel Highest -Force | Out-Null
        Ok 'atualização automática: todo domingo às 3h'
    }

    # --------------------------------------------------------------------------------- 8. iniciar junto com o computador
    Titulo 'Iniciar junto com o computador'
    # (a) o Docker Desktop abre quando alguém entra no Windows (para todos os usuários da máquina)
    $dockerExe = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
    if (Test-Path $dockerExe) {
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'Docker Desktop' -Value ('"' + $dockerExe + '" -Autostart') -Type String
        # o Windows só roda a entrada se ela estiver "aprovada" em StartupApproved (uma entrada antiga desativada a esconde)
        foreach ($raiz in 'HKLM', 'HKCU') {
            $aprov = $raiz + ':\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
            if (-not (Test-Path $aprov)) { New-Item -Path $aprov -Force | Out-Null }
            New-ItemProperty -Path $aprov -Name 'Docker Desktop' -Value ([byte[]](2,0,0,0,0,0,0,0,0,0,0,0)) -PropertyType Binary -Force | Out-Null
        }
        $cfg = Join-Path $env:APPDATA 'Docker\settings-store.json'
        if (Test-Path $cfg) {
            try { $j = Get-Content $cfg -Raw | ConvertFrom-Json; $j | Add-Member -NotePropertyName AutoStart -NotePropertyValue $true -Force; $j | ConvertTo-Json -Depth 10 | Set-Content $cfg -Encoding utf8 } catch { }
        }
        Ok 'Docker Desktop abre junto com o Windows'
    }
    # (b) os contêineres já têm "reiniciar sempre" (voltam sozinhos com o Docker); esta tarefa, ao entrar no Windows, espera o
    #     Docker ficar pronto e garante que o QRWAP está de pé (cobre o caso de ele ter sido parado)
    $iniciar = Join-Path $Pasta 'iniciar.ps1'
    Set-Content -Path $iniciar -Encoding UTF8 -Value @"
`$ErrorActionPreference = 'Continue'
`$bin = 'C:\Program Files\Docker\Docker\resources\bin'
if (Test-Path `$bin) { `$env:Path += ";`$bin" }
`$limite = (Get-Date).AddMinutes(10)
`$exe = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
`$passou = 0
while ((Get-Date) -lt `$limite) {
  `$v = docker info --format '{{.ServerVersion}}' 2>`$null
  if (`$v) { break }
  Start-Sleep -Seconds 5; `$passou += 5
  # se o Docker Desktop não abriu sozinho em 90 s, abre aqui
  if (`$passou -eq 90 -and -not (Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue)) { Start-Process `$exe }
}
Set-Location '$App'
docker compose up -d *> '$Pasta\iniciar.log'
"@
    $acaoIni = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$iniciar`""
    $gatilho = New-ScheduledTaskTrigger -AtLogOn
    $gatilho.Delay = 'PT30S'
    $princ = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
    Register-ScheduledTask -TaskName 'QRWAP Iniciar' -Action $acaoIni -Trigger $gatilho -Principal $princ -Force | Out-Null
    Ok 'tarefa "QRWAP Iniciar": ao entrar no Windows, garante que o sistema está no ar'
    # (c) o computador não deve dormir com o sistema atendendo (só na tomada); pergunta, a menos que já esteja decidido
    $sempre = $env:QRWAP_SEMPRE_LIGADO
    if (-not $sempre -and $env:QRWAP_ACEITO -ne '1') {
        $r = Read-Host '    Deixar o computador SEM entrar em suspensão quando ligado na tomada, para o atendimento não parar? (S/n)'
        $sempre = if ($r -match '^[nN]') { '0' } else { '1' }
    }
    if ($sempre -eq '1') {
        powercfg /change standby-timeout-ac 0 | Out-Null
        powercfg /change hibernate-timeout-ac 0 | Out-Null
        Ok 'sem suspensão na tomada (a tela pode apagar normalmente)'
    }
    Linha '    Observação: o Windows só inicia os programas depois que alguém ENTRA na conta. Para o sistema subir sozinho' DarkGray
    Linha '    depois de uma queda de energia, deixe a entrada automática ligada (netplwiz) ou alguém precisa entrar.' DarkGray

    # --------------------------------------------------------------------------------- fim
    $acessoTxt = Join-Path $App 'ACESSO\ACESSO.txt'
    Write-Host ''
    Linha '  PRONTO!' Green
    Linha "  Painel:  http://localhost:$porta/" White
    Linha '  E-mail:  admin@qrwap.local' White
    Linha "  Senha inicial:  $($conf['ADMIN_SENHA_INICIAL'])   (o sistema pede para trocar no primeiro acesso)" White
    Linha '  Depois: Administração > WhatsApp > Conectar e gerar QR Code, e leia com o celular.' DarkGray
    Linha '  Para atualizar no futuro: rode o mesmo comando (ou ATUALIZAR.bat).' DarkGray
    if (Test-Path $acessoTxt) { Start-Process notepad.exe $acessoTxt }
    Start-Process "http://localhost:$porta/"
} catch {
    Write-Host ''
    Write-Host "A instalação parou: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "O registro completo está em $Log" -ForegroundColor DarkGray
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
