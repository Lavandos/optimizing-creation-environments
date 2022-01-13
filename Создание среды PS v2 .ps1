#Основные настройки

#Путь размещения среды
$PathEnviroument = "C:\inetpub\wwwroot"

#Название папки с проектом
$NameEnvironment = "NTL"

#Двумерный массив с конфигурацией среды.
#!ВАЖНО! Должно быть указано минимум 2 среды для корректной работы!
#Хранит: 
# 0 аргумент: Текст приписки среды.
# 1 аргумент: Необходимость копирования.
# 2 аргумент: Необходимость изменения файла web.config
# 3 аргумент: Название сайта в IIS. Для значения по умолчанию необходимо указать defaultNameIIS
# 4 аргумент: Номер порта в IIS. Для значения по умолчанию необходимо указать defaultPortIIS.
# 5 аргумент: Имя базы данных. Для значения по умолчанию необходимо указать defaultNameDB.

$Envirouments = @(
    @('_dev1',   $true,   $true,  'defaultNameIIS', 'defaultPortIIS', 'defaultNameDB', 'defaultLoginUSERDB', 'defaultPasswordUSERDB'),
    @('_test1',  $true,  $false,  'defaultNameIIS', 'defaultPortIIS', 'defaultNameDB', 'defaultLoginUSERDB', 'defaultPasswordUSERDB')
    #@('_test4',$true,  $false,  'defaultNameIIS', 'defaultPortIIS', 'defaultNameDB', 'defaultLoginUSERDB', 'defaultPasswordUSERDB')
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
        if ($enviroument[4] -ne 'IISdefaultPort'){
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
            if ($Envirouments[$i][3] -like 'IISdefaultName'){
                $Envirouments[$i][3] = "$NameEnvironment$($Envirouments[$i][0])"
            }

            if ($Envirouments[$i][4] -like 'IISdefaultPort'){
                $maxPort += 1
                $Envirouments[$i][4] = $maxPort  
            }

            $nameWebSite = $Envirouments[$i][3]
            $portWebSite = [int]$Envirouments[$i][4]
            $physicalPathWebSite = "$PathEnviroument\$($NameEnvironment)$($Envirouments[$i][0])"

            if (Get-Website -Name "$nameWebSite"){
                Write-Host "!--> Сайт с именем $nameWebSite уже существует!"
                $maxPort -= 1
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
        $folderPath = "$pathEnviroument\$NameEnvironment$($enviroument[0])"
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

    Import-Module SQLPS -DisableNameChecking
    [void][reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
    $server = New-Object("Microsoft.SqlServer.Management.Smo.Server")

    #Инициализация переменных для базы данных
    Init-Variables-DBs
    
    foreach($enviroument in $Envirouments){
        $databasename = "$($enviroument[5])"
        $dbUserName = "$($enviroument[6])"
        $loginName = "$($enviroument[6])"
        $password = "$($enviroument[7])"
        $roleOwnerName = "db_owner"

        $dbExists = $false
        foreach ($db in $server.databases) {
          if ($db.name -eq "$databasename") {
            Write-Host "!--> Такая база данных уже существует!"
            $dbExists = $true
          }
        }

        if (-not $dbExists) {
            $db = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database -argumentlist $server, "$databasename"
            $db.Create()
            Write-Host "Создана база данных $($databasename)!"

            $loginExists = $false
            foreach ($login in $server.logins) {
              if ($login.name -eq "$loginName") {
                Write-Host "!--> Такой пользователь уже существует!"
                $loginExists = $true
              }
            }

            if (-not $loginExists){
                $dbUser = New-Object `
	            -TypeName Microsoft.SqlServer.Management.Smo.User `
	            -ArgumentList $db, $dbUserName
$dbUser
	            $dbUser.Login = $loginName
	            $dbUser.Create()
	            Write-Host("User $dbUser created successfully.")

	            #assign database role for a new user
	            $dbrole = $db.Roles[$roleOwnerName]
	            $dbrole.AddMember($dbUserName)
	            $dbrole.Alter()
	            Write-Host("User $dbUser successfully added to $roleName role.")

                <#
                $login = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Login -ArgumentList $server, $loginName
                $login.LoginType = [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin
                $login.PasswordExpirationEnabled = $false
                $login.Create($password)
                Write-Host "Добавлен пользователь $($loginName)!"

                $dbrole = $db.Roles[$roleOwnerName]
                $dbrole
	            $dbrole.AddMember($roleOwnerName)
	            $dbrole.Alter()
	            Write-Host("Пользователю $($loginName) добавлена роль $($dbrole)")
                #>
            }
        }
    }
}

function create-users(){
    

    $loginName = "testUser"
    $dbUserName = "testUser"
    $password = "test123"
    $databasenames = "Db", "Dbgg"

    $server = New-Object("Microsoft.SqlServer.Management.Smo.Server")

    # drop login if it exists
    if ($server.Logins.Contains($loginName)) 
    {   
	    Write-Host("Deleting the existing login $loginName.")
   	    $server.Logins[$loginName].Drop() 
    }

    $login = New-Object `
    -TypeName Microsoft.SqlServer.Management.Smo.Login `
    -ArgumentList $server, $loginName
    $login.LoginType = [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin
    $login.PasswordExpirationEnabled = $false
    $login.Create($password)
    Write-Host("Login $loginName created successfully.")

    foreach($databaseToMap in $databasenames)
    {
	    $database = $server.Databases[$databaseToMap]
	    if ($database.Users[$dbUserName])
	    {
		    Write-Host("Dropping user $dbUserName on $database.")
	        $database.Users[$dbUserName].Drop()
	    }

	    $dbUser = New-Object `
	    -TypeName Microsoft.SqlServer.Management.Smo.User `
	    -ArgumentList $database, $dbUserName
	    $dbUser.Login = $loginName
	    $dbUser.Create()
	    Write-Host("User $dbUser created successfully.")

	    #assign database role for a new user
	    $dbrole = $database.Roles[$roleName]
	    $dbrole.AddMember($dbUserName)
	    $dbrole.Alter()
	    Write-Host("User $dbUser successfully added to $roleName role.")
    }
}

function Create-Datebase-MSSQL(){
    [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
    $server = New-Object("Microsoft.SqlServer.Management.Smo.Server")

    Init-Variables-DB

    $dbExists = $false
    foreach ($db in $server.databases) {
      if ($db.name -eq "Dbgg") {
        Write-Host "!--> Такая база данных уже существует!"
        $dbExists = $true
      }
    }

    if (!$dbExists) {
      $db = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database -argumentlist $server, "Dbgg"
      $db.Create()

      $user = "user1"
      $usr = New-Object -TypeName Microsoft.SqlServer.Management.Smo.User -argumentlist $db, $user
      $usr.Login = $user
      $usr.Create()

      $role = $db.Roles["db_owner"]
      $role.AddMember($user)
    }
}
#Начало работы программы 

Write-Host "<--------------------------------------------------->"
Write-Host "Расположите в одной директории этот файл с бэкапом."
Write-Host ""

#Copy-Enviroument

#Create-IIS

#Create-Datebase-MSSQL

Recover-MSSQL


