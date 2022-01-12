#Основные настройки

#Путь размещения среды
$PathEnviroument = "C:\inetpub\wwwroot"

#Название папки с проектом
$NameEnvironment = "NTL"

#Двумерный массив с конфигурацией среды.
#!ВАЖНО! Должно быть указано минимум 2 среды для корректной работы!
#Хранит: 
# 1 аргумент: Приписка типа среды. Например, приписка "_dev" и $NameEnvironment = "NTL" (см. выше) значит, что папка среды будет называться NTL_dev 
# 2 аргумент: Необходимость копирования.
# 3 аргумент: Необходимость изменения файла web.config
# 4 аргумент: Название сайта в IIS. Для значения по умолчанию необходимо указать defaultName
# 5 аргумент: Номер порта в IIS. Для значения по умолчанию необходимо указать defaultPort.

$Envirouments = @(
    @('_dev',   $true,  $true,  'defaultName', 'defaultPort'),
    @('_test',  $true,  $false,  'defaultName', 'defaultPort')
    #@('_test4',  $true,  $false, '_test4', '3475'),
    #@('_test41', $true,  $false, 'defaultName', 'defaultPort'),
    #@('_test5',  $false, $true,  'defaultName', 'defaultPort')
)

#Дополнительные настройки

#Двумерный массив с типами СУБД
#Хранит: 
# 1 аргумент: Название СУБД.
# 2 аргумент: Название расширения файла бэкапа СУБД. Находится в папке db.
# 3 аргумент: Какую СУБД необходимо использовать. Автоматически определяется. 
# 4 аргумент: Название базы данных. Для значения по умолчанию необходимо указать defaultNameDB
$DataBaseTypes = @(
    @('MSSQL',      '.bak',    $false),
    @('PostgreSQL', '.enviroument', $false),
    @('Oracle',     '.DMP',    $false)
)

function Print-Error ([string]$textError){

    Write-Error '$textError'
    Write-Host 'Операция прервана!' 
}

function Create-IIS (){

    #Конфигурация сайта IIS

    $maxPort = -1
    $listWebSites = Get-Website *
    foreach ($webSite in $listWebSites){
        if ($webSite.id -eq 1){
            continue
        }
        $port = $webSite.Bindings.Collection.bindingInformation -match "\d+"|%{$matches[0]}

        #Прохожусь по всем существующим сайтам в IIS и получаю максимальный порт
        if ($port -gt $maxPort){
            $maxPort = $port
        }
        $maxPort = [int]$maxPort
    }
    #Прохожусь по заданным средам, которые указаны в массиве Envirouments
    foreach ($enviroument in $Envirouments){
        if ($enviroument[4] -ne 'defaultPort'){
            if ([int]$enviroument[4] -gt $maxPort){
                $maxPort = [int]$enviroument[4]
            }
        }
    }

    #Делаю номер порта по умолчанию = 4000
    if($maxPort -eq -1){
        $maxPort = 4000
    }

    for ($i=0; $i -lt $Envirouments.Count; $i++){
        if ($Envirouments[$i][1] -like $true){
            if ($Envirouments[$i][3] -like 'defaultName'){
                $Envirouments[$i][3] = "$NameEnvironment$($Envirouments[$i][0])"
            }

            if ($Envirouments[$i][4] -like 'defaultPort'){
                $maxPort += 1
                $Envirouments[$i][4] = $maxPort  
            }

            $nameWebSite = $Envirouments[$i][3]
            $portWebSite = [int]$Envirouments[$i][4]
            $physicalPathWebSite = "$PathEnviroument\$($NameEnvironment)$($Envirouments[$i][0])"

            if (Get-Website -Name "$nameWebSite"){
                Write-Host "!--> Сайт с именем $nameWebSite уже существует!"
            }
            else{
                New-WebAppPool -Name "$nameWebSite"
                New-WebSite -Name "$nameWebSite" -Port "$portWebSite" -PhysicalPath "$physicalPathWebSite" -ApplicationPool "$nameWebSite"
                New-WebApplication -Name "0" -Site "$nameWebSite" -PhysicalPath "$physicalPathWebSite\Terrasoft.WebApp" -ApplicationPool "$nameWebSite"

                
            }
        }
    }
}

function ChangeStatusDataBaseTypes([System.IO.FileInfo]$fileBackupDB){
    foreach ($dataBaseType in $DataBaseTypes){
        if ($dataBaseType[1] -like $fileBackupDB.Extension){
            $dataBaseType[2] = $true
        }
    }
}

function Copy-Enviroument (){
    
    foreach ($enviroument in $Envirouments){
        $folderPath = "$pathEnviroument\$nameEnvironment$($enviroument[0])"
        if ($enviroument[1]){
            try{
                if (Test-Path -Path "$folderPath"){
                    Write-Host "!--> По пути $folderPath уже существует такая папка!"
                    continue;
                }
                else {
                    Write-Host "Идёт копирование среды $nameEnvironment$($enviroument[0])..."
                    Copy-Item -Path "$PSScriptRoot\$NameEnvironment" -Destination "$($folderPath)" -Recurse

                    Write-Host "Среда успешно скопирована! Расположение: $($folderPath)"
                
                    #Определение необходимой базы данных
                    $fileBackupDB = Get-Childitem -Path "$folderPath\db"
                    ChangeStatusDataBaseTypes $fileBackupDB

                    if ($enviroument[2]){
                        Update-WebConfig $enviroument
                    }
                }
            }
            catch{
                Print-Error "Ошибка при копировании среды $($NameEnvironment)$($enviroument[0])!"
                Exit
            }
        }
    }
}

function Update-WebConfig([string[]] $Enviroument){
    $path = "$PathEnviroument\$NameEnvironment$($Enviroument[0])\Web.config"

    $file = Get-Content -Path $path
    $ChangedFile = $file -replace '<add key="UseStaticFileContent" value="true" />', '<add key="UseStaticFileContent" value="false" />'
    $ChangedFile | Set-Content -Path $path

    $file = Get-Content -Path $path
    $ChangedFile = $file -replace '<fileDesignMode enabled="false" />', '<fileDesignMode enabled="true" />'
    $ChangedFile | Set-Content -Path $path
}

function Create-Datebase-MSSQL(){
    [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
    $server = new-object ("Microsoft.SqlServer.Management.Smo.Server")

    $dbExists = $false
    foreach ($db in $server.databases) {
      if ($db.name -eq "Db") {
        Write-Host "!--> Такая база данных уже существует!"
        $dbExists = $true
      }
    }

    if ($dbExists -eq $false) {
      $db = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database -argumentlist $server, "Db"
      $db.Create()

      $user = "NT AUTHORITY\NETWORK SERVICE"
      $usr = New-Object -TypeName Microsoft.SqlServer.Management.Smo.User -argumentlist $db, $user
      $usr.Login = $user
      $usr.Create()

      $role = $db.Roles["db_datareader"]
      $role.AddMember($user)
    }
}

function Create-Datebase-MSSQL2(){
    $SourceServer = '.\LOCAL'
    $DestServer = '.\LOCAL2'
    $RestoreDb = 'test1'
    $DataFolder='C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA'
    $LogFolder='C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA'

    $dbBackupPath = "\\servername\Backup\$RestoreDb"

    Restore-DbaDatabase -SqlServer $DestServer -Path $dbBackupPath -DestinationDataDirectory $DataFolder -DestinationLogDirectory $LogFolder
}

#Стартовая информация
Write-Host "<--------------------------------------------------->"
Write-Host "Расположите в одной директории этот файл с бэкапом."
Write-Host ""

Copy-Enviroument

Create-IIS




