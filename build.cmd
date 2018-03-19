@ECHO OFF

REM You can enable these variables on your local machine to aid local development, once 
REM you have added your keys etc do NOT push back to git. To stop git from detecting a
REM change you can stop tracking this file in SourceTree or via bash with this command:
REM     git update-index --assume-unchanged build.cmd
REM and if you want to start tracking again use
REM     git update-index --no-assume-unchanged build.cmd

REM SET Octopus_Server=http://octopusdeploy.bfl.local
REM Octopus_API_Key=
REM nuget_deployments_server=http://nugetdeployments.bfl.local
REM nuget_deployments_api_key=
REM nuget_server=http://nuget.bfl.local
REM nuget_api_key=

REM Setup the whole environment after initial clone of the repo, only needs to be run ONCE
IF /I "%1" == "FIRST" ( GOTO install_prerequisites )

REM Initialsation that prepares the build environment ready for rake (or other tools) to operate
IF /I "%1" == "INIT" ( GOTO initialise )

REM All other calls go to the standard runner
GOTO standard_command


:install_prerequisites

    ECHO Preparing for first run - Setting up all prerequisites (this only needs to be run once)...
    ECHO.
    ECHO Setting Build.cmd as git assume unchanged
    CALL git update-index --assume-unchanged build.cmd
    ECHO Setting CommonAssemblyInfo.cs as git assume unchanged
    CALL git update-index --assume-unchanged CommonAssemblyInfo.cs
    ECHO.
    ECHO Installing Bundler...
    CALL gem install bundler --no-ri --no-rdoc
    ECHO.
    CALL :initialise
    CALL bundle exec rake setup_dev_experience
    ECHO.
    ECHO Development setup completed, environment ready for developement!
    ECHO.
    GOTO finished

:initialise

    ECHO Initialising build environment, please wait...
    ECHO.
    ECHO Preparing build tools...
    IF EXIST "BuildTools" RD "BuildTools" /S /Q
    MKDIR "BuildTools"
    COPY \\alddevap21\Software\Nuget\.net4.5\Nuget.exe BuildTools\Nuget.exe
    CALL BuildTools\Nuget.exe install "BuildTools" -Source http://nuget.bfl.local/api/v2 -ExcludeVersion
    ECHO.
    ECHO Bundler is now installing required gems...
    CALL bundle install
    ECHO.
    ECHO Build initialisation completed, environment ready for build instructions!
    ECHO.
    GOTO :eof
:standard_command
    CALL bundle exec rake %*
:finished
