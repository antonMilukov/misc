#!/bin/bash

# исходная директория скрипта - вычисляется автоматически
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/";

# ветка в репозитории
branch=production;

# алиас для ссылки репозитория
hub=origin;

# директория для фронт
frontDir='front/';

# куда формируется билд при gulp build в папке front/source/deploy/
distPath='dist/';

# директория для АПИ
apiDir='api/';

# Исходный код
sourcePath='source/';

# Папка с релизами
releasePath='releases/';

# Активный релиз
serverPath='current';

# папка сервера
deployPath='deploy/';

# папка upload для АПИ
uploadPath='upload';

# Кол-во активных релизов
countReleases=3;

# Файл лога при деплое
log=${DIR}'/log.txt';

# Настройки для почтовых уведомлений
# Для работы уведомлений требуется установленный агент писем: heirloom-mailx:

# Удаленный smtp сервер
mailSmtpServer=smtp.yandex.ru:587;

# Отправитель для ошибок деплоя
mailErrorFrom="deploy@example.com";

# Пользователь для авторизации на Smtp сервере
mailSmtpUser=deploy@example.com;

# Пароль для авторизации на Smtp сервере
mailSmtpPass=passForAuthOnSmpt;

#Список получателей уведомлений об ошибке деплоя, пример переменной для нескольких получателей: "1@mail.ru, 2@mail.ru"
mailErrorRecipients="user@example.com, user1@example.com";

apiRepo="repo for api";
frontRepo="repo for front";

export curDate=`date +%Y-%m-%d_%H-%M-%S`;

yellow='\033[0;32m';
green='\033[0;36m';
red='\033[0;31m';
nc='\033[0m';
set -o pipefail
shopt -s expand_aliases
declare -ig __oo__insideTryCatch=0

# if try-catch is nested, then set +e before so the parent handler doesn't catch us
alias try="[[ \$__oo__insideTryCatch -gt 0 ]] && set +e;
           __oo__insideTryCatch+=1; ( set -e;
           trap \"Exception.Capture \${LINENO}; \" ERR;"
alias catch=" ); Exception.Extract \$? || "

Exception.Capture() {
    local script="${BASH_SOURCE[1]#./}"

    if [[ ! -f /tmp/stored_exception_source ]]; then
        echo "$script" > /tmp/stored_exception_source
    fi
    if [[ ! -f /tmp/stored_exception_line ]]; then
        echo "$1" > /tmp/stored_exception_line
    fi
    return 0
}

Exception.Extract() {
    if [[ $__oo__insideTryCatch -gt 1 ]]
    then
        set -e
    fi

    __oo__insideTryCatch+=-1

    __EXCEPTION_CATCH__=( $(Exception.GetLastException) )

    local retVal=$1
    if [[ $retVal -gt 0 ]]
    then
        # BACKWARDS COMPATIBILE WAY:
        # export __EXCEPTION_SOURCE__="${__EXCEPTION_CATCH__[(${#__EXCEPTION_CATCH__[@]}-1)]}"
        # export __EXCEPTION_LINE__="${__EXCEPTION_CATCH__[(${#__EXCEPTION_CATCH__[@]}-2)]}"
        export __EXCEPTION_SOURCE__="${__EXCEPTION_CATCH__[-1]}"
        export __EXCEPTION_LINE__="${__EXCEPTION_CATCH__[-2]}"
        export __EXCEPTION__="${__EXCEPTION_CATCH__[@]:0:(${#__EXCEPTION_CATCH__[@]} - 2)}"
        return 1 # so that we may continue with a "catch"
    fi
}

Exception.GetLastException() {
    if [[ -f /tmp/stored_exception ]] && [[ -f /tmp/stored_exception_line ]] && [[ -f /tmp/stored_exception_source ]]
    then
        cat /tmp/stored_exception
        cat /tmp/stored_exception_line
        cat /tmp/stored_exception_source
    else
        echo -e " \n${BASH_LINENO[1]}\n${BASH_SOURCE[2]#./}"
    fi

    rm -f /tmp/stored_exception /tmp/stored_exception_line /tmp/stored_exception_source
    return 0
}

# Формирование релиза с минимизцей кода и т.п.
function buildFront(){
    deployDir=${DIR}${frontDir}${sourcePath}${deployPath};
    printf "${yellow}Start to install npm packages:\n";
    printf "Start to install npm packages:\n"  >> ${log}
        cd ${deployDir};
        npm install >/dev/null 2>&1;
        cd ${DIR};
    printf "${green}Success\n";
    printf "Success\n" >> ${log}

    printf "${yellow}Start building app from sources:\n";
    printf "Start building app from sources:\n" >> ${log}
        cd ${deployDir};
        gulp build >/dev/null 2>&1;
        cd ${DIR};
    printf "${green}Success\n";
    printf "Success\n" >> ${log}
}

# Деплой релиза на сервер
function deploy(){
    printf "${yellow}Copy build to releases path:\n";
    printf "Copy build to releases path:\n" >> ${log}
        curReleasePath=${DIR}$1${releasePath}${curDate}/;
        if [ -z "$2" ]; then
            pullDir=${DIR}$1${sourcePath};
        else
            pullDir=$2
        fi;

        mkdir -p ${curReleasePath};
        cp -r ${pullDir}. ${curReleasePath};
    printf "${green}Success\n";
    printf "Success\n" >> ${log}

    printf "${yellow}Link release to server path:\n";
    printf "Link release to server path:\n" >> ${log}
        serverDir=${DIR}$1${serverPath};
        linkRelease ${curReleasePath} ${serverDir}
    printf "${green}Success\n";
    printf "Success\n" >> ${log}
}

function pull(){
    printf "${yellow}Pull sources from branch ${hub}:${branch}:\n";
    printf "Pull sources from branch ${hub}:${branch}:\n" >> ${log}
        pullDir=${DIR}$1${sourcePath};
        mkdir -p ${pullDir};
        pullFrom ${pullDir}
    printf "${green}Success\n";
    printf "Success\n" >> ${log}
}

function pullFrom(){
    git -C $1 pull ${hub} ${branch}
}

#Очистка старых релизов
function clearOldReleases(){
    printf "${yellow}Clear old releases:\n";
    printf "Clear old releases:\n" >> ${log}
        releaseDir=${DIR}$1${releasePath}
        cd ${releaseDir};
        find . -mindepth 1 -maxdepth 1 -type d | sort -n | head -n -${countReleases} | xargs rm -rf;
        cd ${DIR}
    printf "${green}Success\n";
    printf "Success\n" >> ${log}
}

#Email Уведомление об ошибке при деплое
function sendError(){
     cat ${log} | mailx \
        -s "Deploy error" \
        -S smtp-use-starttls \
        -S ssl-verify=ignore \
        -S smtp-auth=login \
        -S smtp=${mailSmtpServer} \
        -S from=${mailErrorFrom} \
        -S smtp-auth-user=${mailSmtpUser} \
        -S smtp-auth-password=${mailSmtpPass} \
        -S ssl-verify=ignore \
        ${mailErrorRecipients}
}

function deployApi(){
    printf "${yellow}API: Start deploing with release folder name: ${curDate}\n";
    printf "API: Start deploing with release folder name: ${curDate}\n" >> ${log}

    try {
        pull ${apiDir};
    } catch {
        printf "${red}Error when pulling from repository\n";
        printf "Error when pulling from repository\n" >> ${log}
        false;
    }

    try {
        deploy ${apiDir};
    } catch {
        printf "${red}Error when deploing\n";
        printf "Error when deploing\n" >> ${log}
        false;
    }

    deployLinkUpload

    try {
        clearOldReleases ${apiDir};
    } catch {
        printf "${red}Error when clear old releases\n";
        printf "Error when clear old releases\n" >> ${log}
        false;
    }
}

function deployFront(){
    printf "${yellow}FRONT: Start deploing with release folder name: ${curDate}\n";
    printf "FRONT: Start deploing with release folder name: ${curDate}\n" >> ${log}

    try {
        pull ${frontDir};
    } catch {
        printf "${red}Error when pulling from repository\n";
        printf "Error when pulling from repository\n" >> ${log}
        false;
    }

    try {
        buildFront;
    } catch {
        printf "${red}Error when building release\n";
        printf "Error when building release\n" >> ${log}
        false;
    }

    try {
        buildDir=${DIR}${frontDir}${sourcePath}${deployPath}${distPath};
        deploy ${frontDir} ${buildDir};
    } catch {
        printf "${red}Error when deploing\n";
        printf "Error when deploing\n" >> ${log}
        false;
    }

    try {
        clearOldReleases ${frontDir};
    } catch {
        printf "${red}Error when clear old releases\n";
        printf "Error when clear old releases\n" >> ${log}
        false;
    }
}

# Откат для фронты
function rollbackFront(){
    printf "${yellow}FRONT: start rollback\n";
    printf "FRONT: start rollback\n" >> ${log}
        rollback 'front/'
    printf "${green}Success\n";
    printf "Success\n" >> ${log}
}

# Откат для апи
function rollbackApi(){
    printf "${yellow}API: start rollback\n";
    printf "API: start rollback\n" >> ${log}
        rollback 'api/'
    printf "${green}Success\n";
    printf "Success\n" >> ${log}
}

# применить релиз
function linkRelease(){
    ln -nfs ${1} ${2};
}

# Откат изменений
function rollback()
{
    try {
        path=$1
        currentReleasePath=( $(ls -l ${DIR}${path}${serverPath} | awk '{print $11}'| awk 'FNR == 2 {print}' | awk -F'/' '{print $(NF-1)}') )
        if [ -z ${currentReleasePath} ]; then
            printf "${red}Link to current/ doesn't exist!\n";
            printf "Link to current/ doesn't exist!\n" >> ${log};
            exit 1;
        fi;

        releaseDir=${DIR}${path}${releasePath};
        cd ${releaseDir};
        arrDirs=( $(find . -mindepth 1 -maxdepth 1 -type d -printf '%P\n' | sort -nr ) );

        for ((index=0; index <= ${#arrDirs[@]}; index++)); do
          if [ "${arrDirs[index]}" == "$currentReleasePath" ]; then
            rollbackReleasePath=${arrDirs[index+1]};
          fi
        done

        if [ -z ${rollbackReleasePath} ]; then
            printf "${red}No more releases for rollback!\n";
            printf "No more releases for rollback!\n" >> ${log};
            exit 1;
        fi;
        cd ${DIR};

        rollbackReleasePath=$rollbackReleasePath/
        serverDir=${DIR}${path}${serverPath};
        linkRelease ${releaseDir}${rollbackReleasePath} ${serverDir}
        printf "${yellow}Rollback from ${releaseDir}${currentReleasePath}/ to ${releaseDir}${rollbackReleasePath}\n";
        printf "Rollback from ${releaseDir}${currentReleasePath}/ to ${releaseDir}${rollbackReleasePath}\n" >> ${log}
    } catch {
        printf "${red}Error to rollback\n";
        printf "Error to rollback\n" >> ${log}
        false;
    }
    cd ${DIR}
}

# Откат изменений для всех частей
function mainRollback(){
    rollbackFront
    printf "\n";
    rollbackApi
}

# Деплой всех частей проекта
function mainDeploy(){
    deployApi;
    printf "\n";
    printf "\n" >> ${log}
    deployFront;
}

function wrongUse(){
    printf "${red}Wrong use!\n";
    printf "Wrong use!\n" >> ${log}
    false;
}

# Инициализация окружения для деплоя
function deployInit(){
    printf "${yellow}Init deploy environment\n";
        _deployInit ${apiDir} ${apiRepo};
        _deployInit ${frontDir} ${frontRepo};
    printf "${green}Success\n";
}

function _deployInit(){
    srcDir=${DIR}${1}${sourcePath};
    releaseDir=${DIR}${1}${releasePath};
    mkdir -p ${srcDir};
    mkdir -p ${releaseDir};
    cd ${srcDir}
        git init;
        git remote add ${hub} ${2}
        git config credential.helper store
        pullFrom ${srcDir}
    cd ${DIR}
}

# симлинк папки upload в api/current/upload
function deployLinkUpload(){
    try {
        printf "${yellow}API: start symlink upload folder\n";
        printf "API: start symlink upload folder\n" >> ${log}

        if [ ! -d "$DIR$uploadPath" ]; then
          mkdir ${DIR}${uploadPath};
        fi

        if [ -d "$DIR$uploadPath" ]; then
          linkRelease ${DIR}${uploadPath} ${DIR}${apiDir}${serverPath}"/"${uploadPath}
        else
            printf "${red}Folder $DIR$uploadPath doesn't exists!\n";
            printf "Folder $DIR$uploadPath doesn't exists!\n" >> ${log}
            false;
        fi

        printf "${green}Success\n";
        printf "Success\n" >> ${log}

    } catch {
        printf "${red}Error when symlink upload folder\n";
        printf "Error when symlink upload folder\n" >> ${log}
        false;
    }
}

try {
    > ${log}
    if [ ! -z "$1" ]; then
        case "$1" in
           "rollback")
                if [ ! -z "$2" ]; then
                    try {
                        rollback${2^}
                    } catch {
                        wrongUse
                    }
                else
                    mainRollback
                fi;
           ;;

           *)
                try {
                    deploy${1^}
                } catch {
                    wrongUse
                }
           ;;
        esac
    else
        mainDeploy
    fi;
} catch {
    sendError
}
