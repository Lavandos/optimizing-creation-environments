#Основные настройки

#Путь размещения среды
$PathEnviroument = "C:\inetpub\wwwroot"

#Название папки с проектом
$NameEnvironment = "NTL"

#Массив имён серверов (MSSQL, PostgreSQL, Oracle)
$NameServers = @(
    'DESKTOP-C8A1CHF\SQLEXPRESS'
)

#Двумерный массив с конфигурацией среды.
#!ВАЖНО! Должно быть указано минимум 2 среды для корректной работы!
#Хранит: 
# 0 аргумент: Текст приписки среды.
# 1 аргумент: Необходимость копирования.
# 2 аргумент: Необходимость изменения файла web.config
# 3 аргумент: Название сайта в IIS. Для значения по умолчанию необходимо указать defaultNameIIS
# 4 аргумент: Номер порта в IIS. Для значения по умолчанию необходимо указать defaultPortIIS.
# 5 аргумент: Имя базы данных. Для значения по умолчанию необходимо указать defaultNameDB.
# 6 аргумент: Имя пользователя. Для значения по умолчанию необходимо указать defaultLoginUSERDB.
# 7 аргумент: Пароль пользователя. Для значения по умолчанию необходимо указать defaultPasswordUSERDB.
# 8 аргумент: Номер базы Redis.

$Envirouments = @(
    @('_MyDevScript11111111',   $true,   $true,  'defaultNameIIS', 'defaultPortIIS', 'defaultNameDB', 'defaultLoginUSERDB', 'defaultPasswordUSERDB', 5),
    @('_TestScript',  $false,  $false,  'defaultNameIIS', 'defaultPortIIS', 'defaultNameDB', 'defaultLoginUSERDB', 'defaultPasswordUSERDB', 6)
    #@('_Test2Script', $true,  $false,  'defaultNameIIS', 'defaultPortIIS', 'defaultNameDB', 'defaultLoginUSERDB', 'defaultPasswordUSERDB', 7)
)

#Дополнительные настройки

#Двумерный массив с типами СУБД
#Хранит: 
# 1 аргумент: Название СУБД.
# 2 аргумент: Название расширения файла бэкапа СУБД. Находится в папке db.
# 3 аргумент: Какую СУБД необходимо использовать. Автоматически определяется. 
$DataBaseTypes = @(
    @('MSSQL',      '.bak',    $false),
    @('PostgreSQL', '.enviroument', $false),
    @('Oracle',     '.DMP',    $false)
)

#Функции с реализованной логикой

function Create-IIS (){
    Write-Host "<---------------------------Начало настройки сайта IIS--------------------------->$([System.Environment]::NewLine)"
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
        if ($enviroument[4] -ne 'defaultPortIIS'){
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
            if ($Envirouments[$i][3] -like 'defaultNameIIS'){
                $Envirouments[$i][3] = "$NameEnvironment$($Envirouments[$i][0])"
            }

            if ($Envirouments[$i][4] -like 'defaultPortIIS'){
                $maxPort += 1
                $Envirouments[$i][4] = $maxPort  
            }

            $nameWebSite = $Envirouments[$i][3]
            $portWebSite = [int]$Envirouments[$i][4]
            $physicalPathWebSite = "$PathEnviroument\$($NameEnvironment)$($Envirouments[$i][0])"

            if (Get-Website -Name "$nameWebSite"){
                Write-Warning "Сайт с именем [$($nameWebSite)] уже существует!"
                $maxPort -= 1
            }
            else{
                [void](New-WebAppPool -Name "$nameWebSite")
                [void](New-WebSite -Name "$nameWebSite" -Port "$portWebSite" -PhysicalPath "$physicalPathWebSite" -ApplicationPool "$nameWebSite")
                [void](New-WebApplication -Name "0" -Site "$nameWebSite" -PhysicalPath "$physicalPathWebSite\Terrasoft.WebApp" -ApplicationPool "$nameWebSite")
                Write-Host "Создан сайт IIS [$($nameWebSite):$($portWebSite)]$([System.Environment]::NewLine)"
            }
        }
    }
    Write-Host "<---------------------------Конец настройки сайта IIS--------------------------->$([System.Environment]::NewLine)"
}

function ChangeStatusDataBaseTypes([System.IO.FileInfo]$fileBackupDB){
    foreach ($dataBaseType in $DataBaseTypes){
        if ($dataBaseType[1] -like $fileBackupDB.Extension){
            $dataBaseType[2] = $true
        }
    }
}

function Copy-Enviroument (){
    Write-Host "$([System.Environment]::NewLine) <---------------------------Начало настройки папки проекта---------------------------> $([System.Environment]::NewLine)"
    foreach ($enviroument in $Envirouments){
        $folderPath = "$pathEnviroument\$NameEnvironment$($enviroument[0])"
        if ($enviroument[1]){
            try{
                if (-not (Test-Path -Path $PSScriptRoot\$NameEnvironment)){
                    Write-Error "Невозможно найти папку чистой среды [$($NameEnvironment)] в директории [$($PSScriptRoot)]"
                    Exit
                }
                if (Test-Path -Path "$folderPath"){
                    Write-Warning "По пути [$($folderPath)] уже существует такая папка!"
                    continue;
                }
                else {
                    Write-Host "Идёт копирование среды [$($nameEnvironment)$($enviroument[0])]..."
                    Copy-Item -Path "$PSScriptRoot\$NameEnvironment" -Destination "$($folderPath)" -Recurse

                    Write-Host "Среда успешно скопирована! Расположение: [$($folderPath)]"
                
                    #Определение необходимой базы данных
                    $fileBackupDB = Get-Childitem -Path "$folderPath\db"
                    ChangeStatusDataBaseTypes $fileBackupDB
                }
                Write-Host $([System.Environment]::NewLine)
            }
            catch{
                Write-Error "Ошибка при копировании среды [$($NameEnvironment)$($enviroument[0])]!"
                Exit
            }
        }
    }
    Write-Host "<---------------------------Конец настройки папки проекта--------------------------->$([System.Environment]::NewLine) "
}

function Update-WebConfig([string[]] $Enviroument){
    $path = "$PathEnviroument\$NameEnvironment$($Enviroument[0])\Web.config"

    $file = Get-Content -Path $path
    $ChangedFile = $file -replace '<add key="UseStaticFileContent" value="true" />', '<add key="UseStaticFileContent" value="false" />'
    $ChangedFile | Set-Content -Path $path

    $file = Get-Content -Path $path
    $ChangedFile = $file -replace '<fileDesignMode enabled="false" />', '<fileDesignMode enabled="true" />'
    $ChangedFile | Set-Content -Path $path

    Write-Host "Для среды разработки [$($NameEnvironment)$($Enviroument[0])] изменён файл [Web.config]!"
}

function Init-Variables-DBs(){
    foreach($enviroument in $Envirouments){
        if ($enviroument[5] -eq 'defaultNameDB'){
            $enviroument[5] = "$NameEnvironment$($enviroument[0])"
        }
        if ($enviroument[6] -eq 'defaultLoginUSERDB'){
            $enviroument[6] = "User_$NameEnvironment$($enviroument[0])"
        }
        if ($enviroument[7] -eq 'defaultPasswordUSERDB'){
            $enviroument[7] = "$NameEnvironment$($enviroument[0])"
        }
    }
}

function Recover-MSSQL(){
    Write-Host "<---------------------------Начало настройки базы данных MS SQL--------------------------->$([System.Environment]::NewLine)"
    Import-Module SQLPS -DisableNameChecking
    [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
    $server = New-Object("Microsoft.SqlServer.Management.Smo.Server") "$($NameServers[0])"

    #Инициализация переменных для базы данных
    Init-Variables-DBs
    
    foreach($enviroument in $Envirouments){
        $databaseName = "$($enviroument[5])"
        $dbUserName = "$($enviroument[6])"
        $loginName = "$($enviroument[6])"
        $password = "$($enviroument[7])"
        $roleOwnerName = "db_owner"
        if ($enviroument[1]){
            #Проверяю, есть ли такая бд
            $dbExists = $false
            foreach ($db in $server.databases) {
              if ($db.name -eq "$databaseName") {
                Write-Warning "База данных [$($databaseName)] уже существует!"
                $dbExists = $true
              }
            }
            # Если нет такой бд
            if (-not $dbExists) {
                $db = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database -argumentlist $server, "$databasename"
                $db.Create()
                Write-Host "Создана база данных [$($databaseName)]!"

                #Восстановление базы данных
                $nameRelocateDataFile = "$($databaseName)_Data"
                $nameRelocateLogFile = "$($databaseName)_Log"
                $pathBackupFile = "$($PathEnviroument)\$($NameEnvironment)$($enviroument[0])\db"
                $backupFile = Get-Childitem -Path "$pathBackupFile"    
                Restore-SqlDatabase -ServerInstance "$($NameServers[0])" -Database "$($databaseName)" -BackupFile "$($pathBackupFile)\$($backupFile)" -ReplaceDatabase
            
                Write-Host "База данных [$($databaseName)] восстановлена из файла [$($backupFile)]!"

                # Если нет такого логина
                $loginExists = $false
                foreach ($login in $server.logins) {
                  if ($login.name -eq "$loginName") {
                    Write-Warning "Пользователь [$($loginName)] уже существует!"
                    $loginExists = $true
                  }
                }

                if (-not $loginExists){
                
                    #Добавить пользователя
                    $login = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Login -ArgumentList $server, $loginName
                    $login.LoginType = [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin
                    $login.PasswordExpirationEnabled = $false
                    $login.Create($password)
                    Write-Host "Добавлен пользователь [$($loginName)] с паролем [$($password)]!"        
                }

                #Добавить этого пользователя в пользователи конкретной БД
                $dbUser = New-Object `
                -TypeName Microsoft.SqlServer.Management.Smo.User `
                -ArgumentList $db, $dbUserName
                $dbUser.Login = $loginName
                $dbUser.Create()

                #Добавить пользователю роль db_owner
                $dbrole = $db.Roles[$roleOwnerName]
                $dbrole.AddMember($dbUserName)
                $dbrole.Alter()
                Write-Host("Пользователю [$($dbUserName)] успешно добавлена роль [$($roleOwnerName)]")
                [System.Environment]::NewLine
            }
        }
    }
    Write-Host "<---------------------------Конец настройки базы данных MS SQL--------------------------->$([System.Environment]::NewLine)"
}

function Update-ConnectionStrings-MSSQL([string[]] $enviroument){
    
    $path = "$PathEnviroument\$NameEnvironment$($Enviroument[0])\ConnectionStrings.config"
    
    $numberDbRedis = $enviroument[8]
    $stringCustomRedis = '  <add name="redis" connectionString="host=localhost;db=' + $numberDbRedis + ';port=6379" />'
    $searchWordRedis = 'name="redis"'
    
    $dataSource = $NameServers[0]
    $initialCatalog = $enviroument[5]
    $userId = $enviroument[6]
    $password = $enviroument[7]
    $stringCustomDb = '  <add name="db" connectionString="Data Source='+ $dataSource +'; Initial Catalog='+ $initialCatalog +'; Persist Security Info=True; MultipleActiveResultSets=True; User ID='+ $userId +'; Password='+ $password +'; Pooling = true; Max Pool Size = 100; Async = true" />'
    $searchWordDb = 'name="db"'

    $file = Get-Content -Path $path
    $stringSearchRedis = ($file|Select-String "$searchWordRedis").Line
    $ChangedFile = $file -replace $stringSearchRedis, $stringCustomRedis
    $ChangedFile | Set-Content -Path $path

    $file = Get-Content -Path $path
    $stringSearchDb = ($file|Select-String "$searchWordDb").Line
    $ChangedFile = $file -replace $stringSearchDb, $stringCustomDb
    $ChangedFile | Set-Content -Path $path

    Write-Host "Для среды разработки [$($NameEnvironment)$($Enviroument[0])] изменён файл [ConnectionStrings.config]!"
}

function Update-Files(){
    Write-Host "<---------------------------Начало изменения файлов--------------------------->$([System.Environment]::NewLine)"
    foreach($enviroument in $Envirouments){
        if ($enviroument[1]){

            if ($enviroument[2]){
                Update-WebConfig $enviroument
            }
            if ($DataBaseTypes[0][2]){
                Update-ConnectionStrings-MSSQL $enviroument
            }
            else{
                Write-Warning "Простите, но пока работает только для MS SQL! Скоро будет и для Postgre :)"
            }
            
        }
        
    }
     Write-Host "$([System.Environment]::NewLine)<---------------------------Конец изменения файлов--------------------------->$([System.Environment]::NewLine)"
}
#Начало работы программы 

Copy-Enviroument

Create-IIS

Recover-MSSQL

Update-Files

