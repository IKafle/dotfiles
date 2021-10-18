#!/bin/bash
# Bash Menu Script Example


trap "exit 1" TERM
export TOP_PID=$$

bold=$(tput bold)


function BranchValidity(){
    
    if [ "$1" != "MASTER" ]; then
	
     	echo -e "\nUnable to create a TAG [✕]\n\n[Error] Expected branch: ${bold}MASTER \033[00;32m, Found branch: ${bold}$1\033[00;32m" >&2
	
	echo -e "\n[Do] ${bold}git checkout master \033[00;32mand re-run this script" >&2
	
     	file_name=$(basename $0)
	
     	echo -e "\nTerminating script: $file_name" >&2
	
	echo -e "Goodbye!\n" >&2
	kill -s TERM $TOP_PID
    fi

    echo 0
}


function deploy(){

    #0 : new , 1: update , 2: hot

    echo -e "\n[Git]: Branch verification success [✓]"
    
    local deployment_type=$2

    local last_snapshot=$1;
    
    local project=$(basename `git rev-parse --show-toplevel | tr a-z A-Z`)
    
    local most_recent_tag=$(git tag --merged=HEAD --list "DUMMY-*" | sort -r -n -k2 | sort -rn -t $'V' -k2,2 | head -n 1)
    
    echo -e "\n[Git]: Snapshot: ${bold}$last_snapshot\033[00;32m \n"
    
    IFS='- ' read -r -a array <<< "$most_recent_tag"

    local version_pre=$(echo "${array[1]}" | awk -F'.' '{print $1}' | tr -dc '0-9')

    echo "PRE: ${array[1]}"
    
    local version_post=$(echo "${array[1]}" | awk -F'.' '{print $2}')

    local current_date=$(date +"%Y-%m-%d")

    if (( $deployment_type == 0)) ; then
	((version_pre++));
	version_post=0
    elif (( $deployment_type == 2 )) ; then
	((version_post++));
	
    fi

    
    local tag_label="$project-V$version_pre.$version_post-$current_date"
    
    local commit_message="V$version_pre.$version_post-$current_date release"
    
    if (( $deployment_type == 1 )) ; then
	git tag -a "$tag_label" "$last_snapshot" -m "$commit_message" 2> /dev/null
	if (( $? != 0 )); then
	    echo -e "[Warning] tag $tag_label already exists. Force updating ...\n"
	    git tag -af "$tag_label" "$last_snapshot" -m "$commit_message" 
	fi
    else
	git tag -a "$tag_label" "$last_snapshot" -m "$commit_message" 

    fi

    
    git tag -fa latest  "$last_snapshot" -m "$commit_message"
    
    git push --tags origin master --force
    
    echo -e "\n[new tag] success: ${bold}$tag_label\033[00;32m\n"

    echo  -e "[Before]: $most_recent_tag\n[After]: $tag_label\n"
    
}


function initScript(){

    echo -e "\n"
    
    local branch_snapshot=`sh ~/Documents/bash-script/git-branch.sh`

    local branch_name=`echo $branch_snapshot | cut -d '@' -f 1 | tr a-z A-Z`
    local commit_hash=`echo $branch_snapshot | cut -d '@' -f 2`
    
    local PS3='Please enter your choice: '

    local options=("New Deployment" "Update TAG from last commit" "Hot Fix" "Quit")
    select opt in "${options[@]}"
    do
	case $opt in
            "New Deployment")
		deploy "$commit_hash" 0 
		break
		;;
	    
            "Update TAG from last commit")
		deploy  "$commit_hash" 1
		break
		;;
	    
	    "Hot Fix")
		deploy "$commit_hash" 2
		break
		;;
	    
            "Quit")
		break
		;;
	    
            *) echo "invalid option $REPLY";;
	esac

    done
    
}


branch_snapshot=`sh ~/Documents/bash-script/git-branch.sh`

branch_name=`echo $branch_snapshot | cut -d '@' -f 1 | tr a-z A-Z`

is_valid_branch=$(BranchValidity "$branch_name")

if (( $is_valid_branch == 0 )); then
    initScript
fi










