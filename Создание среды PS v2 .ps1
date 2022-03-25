# Таймер.
$watch = [System.Diagnostics.Stopwatch]::StartNew()

# Второй аргумент определяет какая база используется. После автоопределения становится = true
$TypeDB = @(
    @('MSSQL', $false),
    @('PostgreSQL', $false),
    @('Oracle', $false)
)

# Парсинг config.json
$pathConfig = "$PSScriptRoot\config.json"
$json = Get-Content $pathConfig | ConvertFrom-Json
$json.PathEnviroument = $json.PathEnviroument -replace '/', "\"

function DefineDatabase ([string] $extension) {
    if ($extension -like ".bak") {
        $TypeDB[0][1] = $true
    }
    if ($extension -like ".enviroument") {
        $TypeDB[1][1] = $true
    }
    if ($extension -like ".DMP") {
        $TypeDB[2][1] = $true
    }
}

function Create-IIS () {
    $watch.Restart()
    Write-Host "`n<---------------------------Начало настройки сайта IIS--------------------------->`n"
    #Конфигурация сайта IIS

    $maxPort = -1
    $listWebSites = Get-Website *
    foreach ($webSite in $listWebSites) {
        #Прохожусь по всем существующим сайтам в IIS и получаю максимальный порт
        $port = $webSite.Bindings.Collection.bindingInformation -match "\d+" | % { $matches[0] }        
        if ($port -gt $maxPort) {
            $maxPort = $port
        }
        $maxPort = [int]$maxPort
    }

    foreach ($env in $json.Envirouments) {
        if ($env.IIS.Port -ne 'default') {
            if ([int]$env.IIS.Port -gt $maxPort) {
                $maxPort = [int]$env.IIS.Port
            }
        }
    }

    #Делаю номер порта по умолчанию = 4000
    if ($maxPort -eq -1) {
        $maxPort = 4000
    }

    foreach ($env in $json.Envirouments) {
        $titleWebSite = $env.IIS.Title
        $portWebSite = $env.IIS.Port
        $physicalPathWebSite = $json.PathEnviroument + "\" + $json.TitleEnvironment + $env.Postscript

        #Проверка на значения по умолчанию
        if ($env.IIS.Title -like 'default') {
            $titleWebSite = $json.TitleEnvironment + $env.Postscript
            $env.IIS.Title = $titleWebSite
        }
        if ($env.IIS.Port -like 'default') {
            $portWebSite = $maxPort + 1
            $env.IIS.Port = $portWebSite
        }

        if (Get-Website -Name "$titleWebSite") {
            Write-Warning "Сайт с именем [$titleWebSite] уже существует!"
            continue;
        }
        if (Test-Path -Path $physicalPathWebSite) {
            try {
                if (-not (Test-Path -Path "IIS:\AppPools\$titleWebSite")) {
                    [void](New-WebAppPool -Name $titleWebSite)
                    Write-Host "Добавлен пул приложений [$titleWebSite]" 
                }
                if (-not (Test-Path -Path "IIS:\Sites\$titleWebSite")) {
                    [void](New-WebSite -Name $titleWebSite -Port $portWebSite -PhysicalPath $physicalPathWebSite -ApplicationPool $titleWebSite)
                    Write-Host "Добавлен сайт [$titleWebSite]"
                }
                if (-not (Get-WebApplication -Site $titleWebSite)) {
                    [void](New-WebApplication -Name "0" -Site $titleWebSite -PhysicalPath "$physicalPathWebSite\Terrasoft.WebApp" -ApplicationPool $titleWebSite)
                    Write-Host "Добавлено приложение для сайта [$titleWebSite]" 
                }
                Write-Host "Сайт [$($titleWebSite):$($portWebSite)] успешно создан!`n" -ForegroundColor Green
                $maxPort += 1
            }
            catch {
                Write-Warning "Что-то пошло не так при создании сайта [$titleWebSite]"
                Write-Error $Error
            }
        }
    }
    $watch.Stop()
    Write-Host "Время работы: " + $watch.Elapsed -ForegroundColor Cyan
    Write-Host "`n<---------------------------Конец настройки сайта IIS--------------------------->`n"
}

function Copy-Enviroument () {
    $watch.Start()
    Write-Host "`n<---------------------------Начало настройки папки проекта--------------------------->`n"
    $cleanEnvPath = "$PSScriptRoot\" + $json.TitleEnvironment
    foreach ($env in $json.Envirouments) {
        $titleEnv = $json.TitleEnvironment + $env.Postscript
        $needFolderPath = $json.PathEnviroument + "\" + $json.TitleEnvironment + $env.Postscript
        try {
            if (-not (Test-Path -Path $cleanEnvPath)) {
                Write-Error "Невозможно найти папку чистой среды [$($json.TitleEnvironment)] в директории [$PSScriptRoot]"
                Exit
            }
            if (Test-Path -Path $needFolderPath) {
                Write-Warning "По пути [$($needFolderPath)] уже существует такая папка!"
                continue;
            }
            Write-Host "Идёт копирование среды [$titleEnv]..."
            Copy-Item -Path $cleanEnvPath -Destination $needFolderPath -Recurse
            Write-Host "Среда успешно скопирована! Расположение: [$needFolderPath]`n" -ForegroundColor Green
        }
        catch {
            Write-Warning "Ошибка при копировании среды [$titleEnv]!"
            Write-Error $Error
            continue;
        }
    }
    #Определение необходимой базы данных
    $pathBackupDB = "$PSScriptRoot\" + $json.TitleEnvironment + "\db"
    $backupDB = Get-Childitem -Path $pathBackupDB
    DefineDatabase $backupDB.Extension
    $watch.Stop()
    Write-Host "Время работы: " + $watch.Elapsed -ForegroundColor Cyan
    Write-Host "`n<---------------------------Конец настройки папки проекта--------------------------->`n"
}

function Update-WebConfig([pscustomobject] $env) {
    $pathFile = $json.PathEnviroument + "\" + $json.TitleEnvironment + $env.Postscript + "\Web.config"
    $file = Get-Content -Path $pathFile
    $ChangedFile = $file -replace '<add key="UseStaticFileContent" value="true" />', '<add key="UseStaticFileContent" value="false" />'
    $ChangedFile | Set-Content -Path $pathFile

    $file = Get-Content -Path $pathFile
    $ChangedFile = $file -replace '<fileDesignMode enabled="false" />', '<fileDesignMode enabled="true" />'
    $ChangedFile | Set-Content -Path $pathFile

    Write-Host "Для среды разработки [$($json.TitleEnvironment)$($env.Postscript)] изменён файл [Web.config]!"
}

function Recover-MSSQL() {
    $watch.Restart()
    Write-Host "`n<---------------------------Начало настройки базы данных MS SQL--------------------------->`n"
    Import-Module SQLPS -DisableNameChecking
    [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
    $server = New-Object("Microsoft.SqlServer.Management.Smo.Server") "$($json.TitleServers.MSSQL)"
    
    foreach ($env in $json.Envirouments) {
        $titleDB = "$($env.DB.Title)"
        $loginUser = "$($env.DB.LoginUser)"
        $passwordUser = "$($env.DB.PasswordUser)"
        $roleOwnerName = "db_owner"

        if ($titleDB -like "default") {
            $titleDB = $json.TitleEnvironment + $env.Postscript
            $env.DB.Title = $titleDB
        }
        if ($loginUser -like "default") {
            $loginUser = "User_" + $json.TitleEnvironment + $env.Postscript
            $env.DB.LoginUser = $loginUser
        }
        if ($passwordUser -like "default") {
            $passwordUser = "Pass_" + $json.TitleEnvironment + $env.Postscript
            $env.DB.PasswordUser = $passwordUser
        }

        # Если есть БД с таким же именем, то мы пропускаем создание БД для текущей среды.
        $existsDB = $false
        foreach ($db in $server.databases) {
            if ($db.name -eq $titleDB) {
                Write-Warning "База данных [$titleDB] уже существует!"
                $existsDB = $true
            }
        }
        if ($existsDB) {
            continue;
        }

        # Создаём БД.
        try {
            $db = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database -argumentlist $server, "$titleDB"
            $db.Create()
            Write-Host "Создана база данных [$titleDB]!"

            # Восстановление базы данных.
            $pathBackupFile = $json.PathEnviroument + "\" + $json.TitleEnvironment + $env.Postscript + "\db"
            $backupFile = Get-Childitem -Path "$pathBackupFile"
            Restore-SqlDatabase -ServerInstance "$($json.TitleServers.MSSQL)" -Database "$titleDB" -BackupFile "$($pathBackupFile)\$($backupFile)" -ReplaceDatabase
            Write-Host "База данных [$titleDB] восстановлена из файла [$backupFile]!"

            # Если нет такого логина
            $loginExists = $false
            foreach ($login in $server.logins) {
                if ($login.name -eq $loginUser) {
                    Write-Warning "Пользователь [$loginUser] уже существует!"
                    $loginExists = $true
                }
            }
            if (-not $loginExists) {
                #Добавить пользователя
                $login = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Login -ArgumentList $server, "$loginUser"
                $login.LoginType = [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin
                $login.PasswordExpirationEnabled = $false
                $login.Create($passwordUser)
                Write-Host "Добавлен пользователь [$loginUser] с паролем [$passwordUser]!"
            }

            #Добавить этого пользователя в пользователи конкретной БД
            $dbUser = New-Object `
                -TypeName Microsoft.SqlServer.Management.Smo.User `
                -ArgumentList $db, $loginUser
            $dbUser.Login = $loginUser
            $dbUser.Create()

            #Добавить пользователю роль db_owner
            $dbrole = $db.Roles[$roleOwnerName]
            $dbrole.AddMember($loginUser)
            $dbrole.Alter()
            Write-Host("Пользователю [$loginUser] успешно добавлена роль [$roleOwnerName]")
            Write-Host("База данных [$titleDB] восстановлена и настроена!`n") -ForegroundColor Green
        }
        catch {
            Write-Warning "Что-то пошло не так при работе с БД [$titleDB]"
            Write-Error $Error
            continue;
        }
    }
    $watch.Stop()
    Write-Host "Время работы: " + $watch.Elapsed -ForegroundColor Cyan
    Write-Host "`n<---------------------------Конец настройки базы данных MS SQL--------------------------->`n"
}
function Update-ConnectionStrings-MSSQL([pscustomobject] $env) {
    $path = $json.PathEnviroument + "\" + $json.TitleEnvironment + $env.Postscript + "\ConnectionStrings.config"
    
    $numberDbRedis = $env.NumberDBRedis
    $stringCustomRedis = '  <add name="redis" connectionString="host=localhost;db=' + $numberDbRedis + ';port=6379" />'
    $searchWordRedis = 'name="redis"'
    
    $dataSource = $json.TitleServers.MSSQL
    $initialCatalog = $env.DB.Title
    $userId = $env.DB.LoginUser
    $password = $env.DB.PasswordUser
    $stringCustomDb = '  <add name="db" connectionString="Data Source=' + $dataSource + '; Initial Catalog=' + $initialCatalog + '; Persist Security Info=True; MultipleActiveResultSets=True; User ID=' + $userId + '; Password=' + $password + '; Pooling = true; Max Pool Size = 100; Async = true" />'
    $searchWordDb = 'name="db"'

    $file = Get-Content -Path $path
    $stringSearchRedis = ($file | Select-String "$searchWordRedis").Line
    $ChangedFile = $file -replace $stringSearchRedis, $stringCustomRedis
    $ChangedFile | Set-Content -Path $path

    $file = Get-Content -Path $path
    $stringSearchDb = ($file | Select-String "$searchWordDb").Line
    $ChangedFile = $file -replace $stringSearchDb, $stringCustomDb
    $ChangedFile | Set-Content -Path $path

    Write-Host "Для среды разработки [$($json.TitleEnvironment)$($env.Postscript)] изменён файл [ConnectionStrings.config]!"
}

function Update-Files() {
    Write-Host "`n<---------------------------Начало изменения файлов--------------------------->`n"
    $watch.Restart()
    foreach ($env in $json.Envirouments) {
        if ($env.EditFileWebConfig) {
            Update-WebConfig $env
        }
        if ($TypeDB[0]) {
            Update-ConnectionStrings-MSSQL $env
        }
        if ($TypeDB[1]) {
            #Update-ConnectionStrings-PostgreSQL
        }
        if ($TypeDB[2]) {
            #Update-ConnectionStrings-Oracle
        }        
    }
    $watch.Stop()
    Write-Host("Изменение файлов закончено!`n") -ForegroundColor Green
    Write-Host "Время работы: " + $watch.Elapsed -ForegroundColor Cyan
    Write-Host "`n<---------------------------Конец изменения файлов--------------------------->`n"
}

#Начало работы программы 

Copy-Enviroument

Create-IIS

Recover-MSSQL

Update-Files
