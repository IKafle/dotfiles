#!/bin/sh


GRAY='\033[1;90m'
BOLD='\033[1;92m'
NOCOLOR='\033[0m' # No Color
PS1_COLOR='\033[00;32m'

ACTION='\033[1;90m'
FINISHED='\033[1;96m'
READY='\033[1;92m'
NOCOLOR='\033[0m' # No Color
ERROR='\033[0;31m'


echo -e "${GRAY}====================================================="  >&2
echo -e "#Script	: Git Tag Automation \n"  >&2

echo -e "#Author : Ishwor Kafle <ishwor.kafle@lisnepal.com.np>"  >&2                                           
echo -e "=====================================================${PS1_COLOR}\n"  >&2


function TerminateWithMsg(){

    local readonly file_name=$(basename $0)    
    echo -e "\nTerminating script: $file_name ............... ${FINISHED}Goodbye!${PS1_COLOR}" >&2
    echo -e "\n" >&2
    
}

function BranchValidity(){
    
    if [ "$1" != "MASTER" ]; then
	
     	echo -e "Unable to create a TAG ${ERROR}[✕]${PS1_COLOR}" >&2
        echo -e "\n${ERROR}[error]${PS1_COLOR} Expected branch: ${BOLD}MASTER ${PS1_COLOR}, Found branch: ${BOLD}$1${PS1_COLOR}" >&2
	echo -e "\n${GRAY}[Do] ${BOLD}git checkout master ${PS1_COLOR}and re-run this script" >&2
     	TerminateWithMsg
	echo 1;
	
	exit;
    fi

    echo -e "\nOn a branch : ${BOLD}$1${PS1_COLOR} \n" >&2
    echo -e "${GRAY}[git]${PS1_COLOR}: Branch verification  ${BOLD}[✓]${PS1_COLOR}\n" >&2
    echo 0
}



function CompareBranch(){
    
    echo  >&2
    local readonly branch=$(git rev-parse --abbrev-ref HEAD | tr a-z A-Z)
    BranchValidity "$branch"
}



function ReconcileBranches(){
    git fetch
    HEADHASH=$(git rev-parse HEAD)
    UPSTREAMHASH=$(git rev-parse master@{upstream})

    if [ "$HEADHASH" != "$UPSTREAMHASH" ]
    then
	local readonly _local=$(git rev-parse --abbrev-ref HEAD)
	echo -e "Local branch ${ERROR}$_local not up to date ${PS1_COLOR}with origin.\n"  >&2
	echo -e "${ACTION}[git] :${READY} pulling remote changes to local ... \n" >&2
	git fetch origin master >&2
	git reset --hard FETCH_HEAD >&2 
	git clean -df  >&2
	echo -e "\n${GRAY}[git]${READY} : all the remote changes pulled to local  ${BOLD}[✓]${PS1_COLOR} \n" >&2
    else
	echo -e "${FINISHED}Current branch is up to date with origin/master.${NOCOLOR} \n" >&2
    fi

    echo 0;
}



result=$(CompareBranch)

if(( $result == 0))
then
    RECONCILLATION=$(ReconcileBranches "$branch")
fi


echo ${RECONCILLATION}
