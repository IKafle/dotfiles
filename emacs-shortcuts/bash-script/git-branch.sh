# checks if branch has something pending
function parse_git_dirty() {
    git diff --quiet --ignore-submodules HEAD 2>/dev/null; [ $? -eq 1 ] && echo "*"
}

# gets the current git branch
function parse_git_branch() {
    git branch --no-color 2> /dev/null | sed -e '/^[^*]/d' -e "s/* \(.*\)/\1$(parse_git_dirty)/"
}

# get last commit hash prepended with @ (i.e. @8a323d0)
function parse_git_hash() {
    git rev-parse --short HEAD 2> /dev/null | sed "s/\(.*\)/@\1/"
}


# get last commit hash 
function parse_commit_message() {
    git log --format=%B -n 1 $1 
}


#DEMO

# echo -e "[auto] running auto git update ... \n"
# git update
# GIT_COMMIT_HASH=$(parse_git_hash)| cut -d '@' -f 2

 echo "$COMMIT_HASH"
 GIT_BRANCH="$(parse_git_branch)$(parse_git_hash)@$(parse_commit_message "$GIT_COMMIT_HASH")"
 echo ${GIT_BRANCH}

