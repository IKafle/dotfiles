# Git alias ⬇️
#[alias]
    #nah = "!f(){ git reset --hard; git clean -df; if [ -d ".git/rebase-apply" ] || [ -d ".git/rebase-merge" ]; then git rebase --abort; fi; }; f"


# git nah! https://laravel-news.com/the-ultimate-git-nah-alias?ref=dailydev
nah () {
    git reset --hard
    git clean -df
    if [ -d ".git/rebase-apply" ] || [ -d ".git/rebase-merge" ]; then
        git rebase --abort
    fi
}



# bash functions that are frequently used.

function prod (){

echo 'Mt$3rD&'
return 0
}





 #          ruler that stretches across the terminal                #
#######################################################################

  function ruler() { for s in '....^....|' '1234567890'; do w=${#s}; str=$( for (( i=1; $i<=$(( ($COLUMNS + $w) / $w )) ; i=$i+1 )); do echo -n $s; done ); str=$(echo $str | cut -c -$COLUMNS) ; echo $str; done; }


#                   Ask			        #
##################################################
    function ask()
{
    echo -n "$@" '[y/n] ' ; read ans
    case "$ans" in
        y*|Y*) return 0 ;;
        *) return 1 ;;
    esac
}




#          Analyze your bash usage	        #
##################################################

function check_()
{
cut -f1 -d" " .bash_history | sort | uniq -c | sort -nr | head -n 30
}


 #      find the IP addresses that are currently online in your network       #
##################################################################################

function localIps()
{
for i in {1..254}; do
	x=`ping -c1 -w1 192.168.1.$i | grep "%" | cut -d"," -f3 | cut -d"%" -f1 | tr '\n' ' ' | sed 's/ //g'`
	if [ "$x" == "0" ]; then
		echo "192.168.1.$i"
	fi
done
}


#      myip - finds your current IP if your connected to the internet          #
###################################################################################
function myip()
{
lynx -dump -hiddenlinks=ignore -nolist http://checkip.dyndns.org:8245/ | awk '{ print $4 }' | sed '/^$/d; s/^[ ]*//g; s/[ ]*$//g'
}


#            netinfo - shows network information for your system                        #
#########################################################################################

function netinfo()
{
echo "--------------- Network Information ---------------"
/sbin/ifconfig | awk /'inet addr/ {print $2}'
/sbin/ifconfig | awk /'Bcast/ {print $3}'
/sbin/ifconfig | awk /'inet addr/ {print $4}'
/sbin/ifconfig | awk /'HWaddr/ {print $4,$5}'
myip=`lynx -dump -hiddenlinks=ignore -nolist http://checkip.dyndns.org:8245/ | sed '/^$/d; s/^[ ]*//g; s/[ ]*$//g' `
echo "${myip}"
echo "---------------------------------------------------"
}



# Find all videos under current directory using	             #
# MIME a.k.a not using extension		             #
##############################################################

function allVideos() { find ./ -type f -print0 | xargs -0 file -iNf - | grep ": video/" | cut -d: -f1 ; }



#                   fake error string                        #
#####################################################################
function error()
{
while true; do awk '{ print ; system("let R=$RANDOM%10; sleep $R") }' compiler.log; done
}


#     pretend to be busy in office to enjoy a cup of coffee      #
########################################################################
function grepcolor()
{
cat /dev/urandom | hexdump -C | grep --color=auto "ca fe"
}




#                     bored ? read some one liners                           #
##############################################################################
function oneliners()
{
w3m -dump_source http://www.onelinerz.net/random-one-liners/1/ | awk ' /.*<div id=\"oneliner_[0-9].*/ {while (! /\/div/ ) { gsub("\n", ""); getline; }; gsub (/<[^>][^>]*>/, "", $0); print $0}'
}



#                  simple calculator to 4 decimals                         #
############################################################################
function calc() {
echo "scale=4; $1" | bc
}


  # Get the headlines of an atom feed		 #
##################################################

function atomtitles()
{
curl --silent $1 | xmlstarlet sel -N atom="http://www.w3.org/2005/Atom" -t -m /atom:feed/atom:entry -v atom:title -n
}



#                         record audio and use sox to eliminate silence                #
########################################################################################
# outputs an ogg file that only contains the audio signal exceeding -45dB
# useful for recording radio scanner

function audiorecord-45dB()
{
rec -r 44100 -p | sox -p "audio_name-$(date '+%Y-%m-%d').ogg" silence -l 1 00:00:00.5 -45d -1 00:00:00.5 -45d
}


  # Backup .bash* files				 #
##################################################

function backup_bashfiles()
{
  ARCHIVE="$HOME/bash_dotfiles_$(date +%Y%m%d_%H%M%S).tar.gz";
  cd ~
  tar -czvf $ARCHIVE .bash_profile .bashrc .bash_functions .bash_aliases .bash_prompt
  echo "All backed up in $ARCHIVE";
}



# Creates a backup of the file passed as	 #
# parameter with the date and time		 #
##################################################

function bak()
{
  cp $1 $1_`date +%H:%M:%S_%d-%m-%Y`

}



  
# Good bash tips for everyone			 #
##################################################

function bashtips() {
# copyright 2007 - 2010 Christopher Bratusek
cat <<EOF
DIRECTORIES
-----------
~-          Previous working directory
pushd tmp   Push tmp && cd tmp
popd        Pop && cd
GLOBBING AND OUTPUT SUBSTITUTION
--------------------------------
ls a[b-dx]e Globs abe, ace, ade, axe
ls a{c,bl}e Globs ace, able
\$(ls)      \`ls\` (but nestable!)
HISTORY MANIPULATION
--------------------
!!        Last command
!?foo     Last command containing \`foo'
^foo^bar^ Last command containing \`foo', but substitute \`bar'
!!:0      Last command word
!!:^      Last command's first argument
!\$       Last command's last argument
!!:*      Last command's arguments
!!:x-y    Arguments x to y of last command
C-s       search forwards in history
C-r       search backwards in history
LINE EDITING
------------
M-d     kill to end of word
C-w     kill to beginning of word
C-k     kill to end of line
C-u     kill to beginning of line
M-r     revert all modifications to current line
C-]     search forwards in line
M-C-]   search backwards in line
C-t     transpose characters
M-t     transpose words
M-u     uppercase word
M-l     lowercase word
M-c     capitalize word
COMPLETION
----------
M-/     complete filename
M-~     complete user name
M-@     complete host name
M-\$    complete variable name
M-!     complete command name
M-^     complete history
EOF
}




#                                binary clock   :     1                               #
#######################################################################################
function bclock()
{
watch -n 1 'echo "obase=2;`date +%s`" | bc'
}



#                                            binary clock       : 2                        #
#########################################################################################
function bclock2()
{
perl -e 'for(;;){@d=split("",`date +%H%M%S`);print"\r";for(0..5){printf"%.4b ",$d[$_]}sleep 1}'
}



function clock()
{
while true;do clear;echo "===========";date +"%r";echo "===========";sleep 1;done
}





#     Appends a '&' to a command so it will run in 	 #
#     the background				         #
###########################################################

###### useful for aliases
function bg_wrapper()
{
    "$@" &
}


 # Substitutes underscores for blanks in all the        #
# filenames in a directory			        #
#########################################################

function blank_rename()
{
ONE=1                     # For getting singular/plural right (see below).
number=0                  # Keeps track of how many files actually renamed.
FOUND=0                   # Successful return value.
for filename in *         #Traverse all files in directory.
do
     echo "$filename" | grep -q " "         #  Check whether filename
     if [ $? -eq $FOUND ]                   #+ contains space(s).
     then
       fname=$filename                      # Yes, this filename needs work.
       n=`echo $fname | sed -e "s/ /_/g"`   # Substitute underscore for blank.
       mv "$fname" "$n"                     # Do the actual renaming.
       let "number += 1"
     fi
done
if [ "$number" -eq "$ONE" ]                 # For correct grammar.
then
 echo "$number file renamed."
else
 echo "$number files renamed."
fi
}




  # Extract a file and cd into the new folder	 #
##################################################

function build()
{
   extract "$1" && cd
}


   # Commandlinefu.com and Shell-fu.org stuff	 #
##################################################

###### Search commandlinefu.com from the command line
# using the API
# Usage: cmdfu hello world
function cmdfu() { curl "http://www.commandlinefu.com/commands/matching/$@/$(echo -n $@ | openssl base64)/plaintext" --silent | sed "s/\(^#.*\)/\x1b[32m\1\x1b[0m/g" | less -R ; }



 function cmdfu() { curl "http://www.commandlinefu.com/commands/matching/$@/$(echo -n $@ | openssl base64)/plaintext"; }



#                automatically downloads all commands from http://www.commandlinefu.com into a single text file          #
########################################################################################################################## 

alias cmdfu_dl='mkdir /tmp/commandlinefu && cd /tmp/commandlinefu && curl -O http://www.commandlinefu.com/commands/browse/sort-by-votes/plaintext/[0-2400:25] && ls -1 | sort -n | while read mork ; do cat $mork >> commandlinefu.txt ; ls -ald $mork; done && mv commandlinefu.txt $HOME && rm -rf /tmp/commandlinefu'



#          find a CommandlineFu users average command rating           #
########################################################################
function cmdfu_rating()
{
wget -qO- www.commandlinefu.com/commands/by/PhillipNordwall | awk -F\> '/class="num-votes"/{S+=$2; I++}END{print S/I}'
}



function cmdfu_rating_()
{
curl -s www.commandlinefu.com/commands/by/PhillipNordwall | awk -F\> '/class="num-votes"/{S+=$2; I++}END{print S/I}'
}




#           command examples from shell-fu                              #
#########################################################################

function examples() { lynx -width=$COLUMNS -nonumbers -dump "http://www.shell-fu.org/lister.php?tag=$1" | \
sed -n '/^[a-zA-Z]/,$p' | egrep -v '^http|^javas|View Comm|HIDE|] \+|to Share|^ +\*|^ +[HV][a-z]* l|^ .*efu.*ep.*!$' | \
sed -e '/^  *__*/N;s/\n$//g' | less -r; }


   # What package does that command come from?	 #
##################################################

function cmdpkg() { PACKAGE=$(dpkg -S $(which $1) | cut -d':' -f1); echo "[${PACKAGE}]"; dpkg -s "${PACKAGE}" ;}



#              takes a name of a color and some text and then echoes out the text in the named color       #
############################################################################################################


# Usage:	colorize_text "color" "whatever text"
function colorize-text()
{
b='[0;30m'
# Implement command-line options
while getopts "nr" opt
 do
  case $opt in
   n  )  o='-n' ;;
   r  )  b=''   ;;
  esac
 done
shift $(($OPTIND - 1))
# Set variables
col=$1
shift
text="$*"
# Set a to console color code
case $col in
 'black'  ) a='[0;30m' ;;
 'blue'   ) a='[0;34m' ;;
 'green'  ) a='[0;32m' ;;
 'cyan'   ) a='[0;36m' ;;
 'red'    ) a='[0;31m' ;;
 'purple' ) a='[0;35m' ;;
 'brown'  ) a='[0;33m' ;;
 'ltgray' ) a='[0;37m' ;;
 'white'  ) a='[1;30m' ;;
 'ltblue' ) a='[1;34m' ;;
 'ltgreen') a='[1;32m' ;;
 'ltcyan' ) a='[1;36m' ;;
 'ltred'  ) a='[1;31m' ;;
 'pink'   ) a='[1;35m' ;;
 'yellow' ) a='[1;33m' ;;
 'gray'   ) a='[1;37m' ;;
esac
# Display text in designated color, no newline
echo -en "\033$a$text"
# If 'b' switch not on, restore color to black
if [ -n $b ]
 then
  echo -en "\033$b"
fi
# If 'n' switch on, do not display final newline
# otherwise output newline
echo $o
}



#       show numerical values for each of the 256 colors in bash           #
############################################################################

function colors2nums()
{
for code in {0..255}; do echo -e "\e[38;05;${code}m $code: Test"; done
}


 # Run command/program using a timer		 #
##################################################

###### Run a command until a specified time
# Example: command-timer 04:00
function command-timer() { echo "notify-send TimeToQuit" | at "$@" ; }



#                  Run a program on a timer                            #
########################################################################
# Example: program-timer 20 viewnior arg1
function program-timer() { perl -e 'alarm shift; exec @ARGV' "$@" & exit; }


#             Compress stuff	                 #
##################################################

function compress_() {
   # Credit goes to: Daenyth
   FILE=$1
   shift
   case $FILE in
      *.tar.bz2) tar cjf $FILE $*  ;;
      *.tar.gz)  tar czf $FILE $*  ;;
      *.tgz)     tar czf $FILE $*  ;;
      *.zip)     zip $FILE $*      ;;
      *.rar)     rar $FILE $*      ;;
      *)         echo "Filetype not recognized" ;;
   esac
}




  #      Count files in current directory        #
##################################################

function count_files()

{
	case $1 in
		*+h)
			echo $(($(ls --color=no -1 -la . | grep -v ^l | wc -l)-1))
		;;
		*-h)
			echo $(($(ls --color=no -1 -l . | grep -v ^l | wc -l)-1))
		;;
		*+d)
			echo $(($(ls --color=no -1 -la . | grep -v ^- | wc -l)-1))
		;;
		*-d)
			echo $(($(ls --color=no -1 -l . | grep -v ^- | wc -l)-1))
		;;
		*+f)
			echo $(($(ls --color=no -1 -la . | grep -v ^d | wc -l)-1))
		;;
		*-f)
			echo $(($(ls --color=no -1 -l . | grep -v ^d | wc -l)-1))
		;;
		*)
			echo -e "\n${ewhite}Usage:"
			echo -e "\n${eorange}count_files${ewhite} | ${egreen}+h ${eiceblue}[count files and folders - include hidden ones] \
			\n${eorange}count_files${ewhite} | ${egreen}-h ${eiceblue}[count files and folders - exclude hidden ones] \
			\n${eorange}count_files${ewhite} | ${egreen}+d ${eiceblue}[count folders - include hidden ones] \
			\n${eorange}count_files${ewhite} | ${egreen}-d ${eiceblue}[count folders - exclude hidden ones] \
			\n${eorange}count_files${ewhite} | ${egreen}+f ${eiceblue}[count files - include hidden ones] \
			\n${eorange}count_files${ewhite} | ${egreen}-f ${eiceblue}[count files - exclude hidden ones]\n"
			tput sgr0
		;;
	esac
}



 #        Count processes that are running       #
##################################################

function count_processes()
# copyright 2007 - 2010 Christopher Bratusek
{
	case $1 in
		*help )
			echo -e "\n${ewhite}Usage:"
			echo -e "\n${eorange}count_processes${ewhite} | ${egreen}! no options !\n"
			tput sgr0
		;;
		* )
			procs=$(ps ax | wc -l | awk '{print $1}')
			if [[ $procs -lt 10 ]]; then
				echo "000$procs"
			elif [[ $procs -lt 100 ]]; then
				echo "00$procs"
			elif [[ $procs -lt 1000 ]]; then
				echo "0$procs"
			fi
		;;
	esac
}



  #     Cp with progress bar (using pv)		 #
##################################################

function cp_p() {
	if [ `echo "$2" | grep ".*\/$"` ]
	then
		pv "$1" > "$2""$1"
	else
		pv "$1" > "$2"/"$1"
	fi
}




#        More advanced encryption / decryption                     #
####################################################################
# example: "encrypt filename" or "decrypt filename"
function encrypt()
{
# Author: Martin Langasek <cz4160@gmail.com>
case $LANG in
  cs* )
    err_title="Chyba"
    err_files="Neoznačen soubor"
    encrypt="Šifrovat"
    decrypt="Dešifrovat"
    file_msg="soubor:"
    pass_msg="Vložte heslo";;
  * )
    err_title="Error"
    err_files="No file selected"
    encrypt="Encrypt"
    decrypt="Decrypt"
    file_msg="file:"
    pass_msg="Enter passphrase";;
esac
if [ "$1" != "" ]
then
  i=1
  file=`echo "$1" | sed ''$i'!d'`
  while [ "$file" != "" ]
  do
    ext=`echo "$file" | grep [.]gpg$ 2>&1`
    if [ "$ext" != "" ]
    then
      pass_decrypt=`zenity --entry --entry-text "$pass_decrypt" --hide-text --title "$pass_msg" --text "$decrypt $file_msg ${file##*/}" "" 2>&1`
      if [ "$pass_decrypt" != "" ]
      then
        output=${file%.*}
        echo "$pass_decrypt" | gpg -o "$output" --batch --passphrase-fd 0 -d "$file"
      fi
    else
      pass_encrypt=`zenity --entry --hide-text --entry-text "$pass_encrypt" --title "$pass_msg" --text "$encrypt $file_msg ${file##*/}" "" 2>&1`
      if [ "$pass_encrypt" != "" ]
      then
        echo "$pass_encrypt" | gpg --batch --passphrase-fd 0 --cipher-algo aes256 -c "$file"
      fi
    fi
    i=$(($i+1))
    file=`echo "$1" | sed ''$i'!d'`
  done
else
  zenity --error --title "$err_title" --text "$err_files"
fi
}


    alias decrypt='encrypt'


  
#                         find a location's coordinates                                     #
#############################################################################################
# usage:	findlocation "Las Vegas, Nevada" = coordinates: [ -115.1728160, 36.1146460, 0 ]
function findlocation() { place=`echo $1 | sed 's/ /%20/g'` ; curl -s "http://maps.google.com/maps/geo?output=json&oe=utf-8&q=$place" | grep -e "address" -e "coordinates" | sed -e 's/^ *//' -e 's/"//g' -e 's/address/Full Address/';}





#                     your GeoIP location on Google Maps                             #
######################################################################################
function geoipme()
{
curl -s http://geoiplookup.wikimedia.org/|awk -F, '{print $3,$4}'|awk -F'"' '{print "http://maps.google.com/maps?q="$4 "," $8}'
}


#                   Google search (example: google dog)                               #
#######################################################################################
function google() {
firefox "http://www.google.com/search?&num=100&q=${@}" &
}



#                  Google text-to-speech in mp3/wav format                            #
######################################################################################
function say() { mplayer -user-agent Mozilla "http://translate.google.com/translate_tts?tl=en&q=$(echo $* | sed 's#\ #\+#g')" > /dev/null 2>&1 ; }



# Shows what processes need to be restarted after                               #
# system upgrade				                                #
#################################################################################

function deadlib() { lsof | grep 'DEL.*lib' | cut -f 1 -d ' ' | sort -u; }



# Download a web page and show info on what	 #
# took time					 #
##################################################

function debug_http() { /usr/bin/curl $@ -o /dev/null -w "dns: %{time_namelookup} connect: %{time_connect} pretransfer: %{time_pretransfer} starttransfer: %{time_starttransfer} total: %{time_total}\n" ; }


 # Lookup a word with dict.org			 #
##################################################

#define "whatever"
function dic() { curl dict://dict.org/d:"$@" ; }



 # Size of directories in MB			 #
##################################################

function ds()
{
    echo "size of directories in MB"
    if [ $# -lt 1 ] || [ $# -gt 2 ]; then
        echo "you did not specify a directy, using pwd"
        DIR=$(pwd)
        find $DIR -maxdepth 1 -type d -exec du -sm \{\} \; | sort -nr
    else
        find $1 -maxdepth 1 -type d -exec du -sm \{\} \; | sort -nr
    fi
}



  # Site down for everyone or just me?		 #
##################################################

function downforme() {
	RED='\e[1;31m'
	GREEN='\e[1;32m'
	YELLOW='\e[1;33m'
	NC='\e[0m'
	if [ $# = 0 ]
	then
		echo -e "${YELLOW}usage:${NC} downforme website_url"
	else
		JUSTYOUARRAY=(`lynx -dump http://downforeveryoneorjustme.com/$1 | grep -o "It's just you"`)
		if [ ${#JUSTYOUARRAY} != 0 ]
		then
			echo -e "${RED}It's just you. \n${NC}$1 is up."
		else
			echo -e "${GREEN}It's not just you! \n${NC}$1 looks down from here."
		fi
	fi
}



 # Edit your history file			 #
##################################################

function eh() { history -a ; vi ~/.bash_history ; history -r ; }


  # Determining the meaning of error codes	 #
##################################################

function err()
{
    grep --recursive --color=auto --recursive -- "$@" /usr/include/*/errno.h
    if [ "${?}" != 0 ]; then
        echo "Not found."
    fi
}


  


 # Festival - text-to-speech 			 #
##################################################

###### requires festival: sudo apt-get install festival
# Usage:	fest "text"
function fest() {
    echo $1 | festival --tts
}



 # Find out the pid of a specified process	 #
##################################################

######  note that the command name can be specified via a regex
#    E.g. findPid '/d$/' finds pids of all processes with names ending in 'd'
#    Without the 'sudo' it will only find processes of the current user
function findPid() { sudo /usr/sbin/lsof -t -c "$@" ; }


 
#        get sunrise and sunset times             #       
###################################################
function suntimes()
{
l=12765843;curl -s http://weather.yahooapis.com/forecastrss?w=$l|grep astronomy| awk -F\" '{print $2 "\n" $4;}'
}


  
 # Get FreeMusicCharts of the current month	 #
##################################################

function freemusiccharts()
{
wget -O - "http://www.darkerradio.com/news/free-music-charts-$(date "+%B-%Y")/" 2> /dev/null | grep -o "http://[^ \"']*\.mp3" |grep "freemusiccharts.songs" | sort | uniq | xargs -n1 wget -c
}



 # Cool History Summerizer			 #
##################################################

function historyawk() { history|awk '{a[$2]++}END{for(i in a){printf"%5d\t%s\n",a[i],i}}'|sort -nr|head; }


 #    Progress visuals				 #
##################################################

# display animated hourglass in the shell to indicate ongoing processing
function hourglass() { s=$(($SECONDS +${1:-10}));(tput civis;while [[ $SECONDS -lt $s ]];do for f in '|' ' ' '\-' /;do echo -n $f&&sleep .2s&&tput cub1;done;done);tput cnorm; }


# Convert number of bytes to human readable 	 #
# filesize					 #
##################################################

function human_filesize() { awk -v sum="$1" ' BEGIN {hum[1024^3]="Gb"; hum[1024^2]="Mb"; hum[1024]="Kb"; for (x=1024^3; x>=1024; x/=1024) { if (sum>=x) { printf "%.2f %s\n",sum/x,hum[x]; break; } } if (sum<1024) print "1kb"; } ' ; }


# Show computer information of all sorts	 #
# (requires 'gawk': sudo apt-get install gawk)	 #
##################################################

###### machine details
function ii()
{
    echo -e "\n${RED}You are logged onto:$NC " ; hostname
    echo -e "\n${RED}Additionnal information:$NC " ; uname -a
    echo -e "\n${RED}Users logged on:$NC " ; w -h
    echo -e "\n${RED}Current date:$NC " ; date
    echo -e "\n${RED}Machine stat:$NC " ; uptime
    echo -e "\n${RED}Disk space:$NC " ; df -h
    echo -e "\n${RED}Memory stats (in MB):$NC " ;
    if [ "$OS" = "Linux" ]; then
        free -m
    elif [ "$OS" = "Darwin" ]; then
        vm_stat
    fi
    echo -e "\n${RED}IPs:$NC " ; ips
}


# informatio about my computer #
#######################################

  function system_infos()

{
	case $1 in
		*cpu)
			echo -e "${ewhite}CPU:\n"
			echo -e "${eorange}Model:${eiceblue} $(grep "model name" /proc/cpuinfo | sed -e 's/.*: //g')"
			echo -e "${eorange}MHz  :${eiceblue} $(grep "cpu MHz" /proc/cpuinfo | sed -e 's/.*: //g')\n"
		;;
		*kernel)
			echo -e "${ewhite}Kernel:\n"
			echo -e "${eorange}Release:${eiceblue} $(uname -r)"
			echo -e "${eorange}Version:${eiceblue} $(uname -v)"
			echo -e "${eorange}Machine:${eiceblue} $(uname -m)\n"
		;;
		*mem | *ram)
			echo -e "${ewhite}RAM:\n"
			echo -e "${eorange}Total:${eiceblue} $(((`showmem --free`) + (`showmem --used`))) MB"
			echo -e "${eorange}Free :${eiceblue} $(showmem --free) MB"
			echo -e "${eorange}Used :${eiceblue} $(showmem --used) MB\n"
		;;
		*partitions)
			echo -e "${ewhite}Partitions:${eorange}\n"
			echo -e "major minor blocks device-node ${eiceblue}\
			\n$(cat /proc/partitions | sed -e '1,2d')" | column -t
			echo ""
		;;
		*pci)
			check_opt lspci systeminfos::pci
			if [[ $? != "1" ]]; then
				echo -e "${ewhite}PCI Devices:\n${eiceblue}"
				lspci -vkmm
				echo ""
			fi
		;;
		*usb)
			check_opt lsusb systeminfos::usb
			if [[ $? != "1" ]]; then
				echo -e "${ewhite}USB Devices:\n${eiceblue}"
				lsusb -v
				echo ""
			fi
		;;
		*mounts)
			echo -e "${ewhite}Mounts:\n${eorange}\
			\ndevice-node on mount-point type filesystem options\n" ${eiceblue} "\n\n$(mount)" | column -t
			echo ""
		;;
		*bios)
			check_opt dmidecode systeminfos::bios
			if [[ $? != "1" && $EUID == 0 ]]; then
				echo -e "${ewhite}SMBIOS/DMI Infos:${eiceblue}\n"
				dmidecode -q
			fi
		;;
		*all)
			system_infos_cpu
			system_infos_kernel
			system_infos_memory
			system_infos_partitions
			# system_infos_pci
			# system_infos_usb
			system_infos_mounts
			# system_infos_bios
		;;
		*)
			echo -e "\n${ewhite}Usage:\n"
			echo -e "${eorange}system_infos ${ewhite}|${egreen} --cpu\t\t${eiceblue}[Display CPU Model and Freq]\
			\n${eorange}system_infos ${ewhite}|${egreen} --kernel\t${eiceblue} 	[Display Kernel Version, Release and Machine]\
			\n${eorange}system_infos ${ewhite}|${egreen} --memory\t${eiceblue} 	[Display Total, Free and Used RAM]\
			\n${eorange}system_infos ${ewhite}|${egreen} --partitions\t${eiceblue}[Display Major, Minor, Blocks and Node for all Paritions]\
			\n${eorange}system_infos ${ewhite}|${egreen} --pci\t\t${eiceblue}[Display Infos about all PCI Devices (and their kernel-module)]\
			\n${eorange}system_infos ${ewhite}|${egreen} --usb\t\t${eiceblue}[Display Infos about all USB Devices (and their kernel-module)]\
			\n${eorange}system_infos ${ewhite}|${egreen} --bios\t${eiceblue} 	[Display SMBIOS DMI Infos]\
			\n${eorange}system_infos ${ewhite}|${egreen} --mounts\t${eiceblue} 	[Display all mounted devices]\n"
			tput sgr0
		;;
	esac
}




#            info about current open windows                   #
################################################################
# copyright 2007 - 2010 Christopher Bratusek
function wininfo() {
	xprop | grep -w "WM_NAME\|WM_CLASS\|WM_WINDOW_ROLE\|_NET_WM_STATE"
}


  # Kill a process by name			 #
##################################################

# example: killps firefox-bin
function killps()
{
    local pid pname sig="-TERM" # default signal
    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        echo "Usage: killps [-SIGNAL] pattern"
        return;
    fi
    if [ $# = 2 ]; then sig=$1 ; fi
    for pid in $(myps | nawk '!/nawk/ && $0~pat { print $2 }' pat=${!#}) ; do
        pname=$(myps | nawk '$2~var { print $6 }' var=$pid )
        if ask "Kill process $pid <$pname> with signal $sig ? "
            then kill $sig $pid
        fi
    done
}


 
  # Email yourself a quick message		 #
##################################################

function mailme()
{
	echo "$@" | mail -s "$1" $SERVERMAIL
}



 # What is the use of this switch?		 #
##################################################

function manswitch() { man $1 | less -p "^ +$2"; }



 # Makes directory then moves into it		 #
##################################################

function mkcdr() {
    mkdir -p -v $1
    cd $1
}



 # Creates an archive from directory		 #
##################################################

function mktar() { tar cvf  "${1%%/}.tar"     "${1%%/}/"; }



function mktbz() { tar cvjf "${1%%/}.tar.bz2" "${1%%/}/"; }



function mktgz() { tar cvzf "${1%%/}.tar.gz"  "${1%%/}/"; }


# stream YouTube videos directly to your media player            #
###################################################################

function mtube() {
  video_id=$(curl -s $1 | sed -n "/watch_fullscreen/s;.*\(video_id.\+\)&title.*;\1;p");
  mplayer -fs $(echo "http://youtube.com/get_video.php?$video_id");
}



alias mtube_='mplayer -fs $(echo "http://youtube.com/get_video.php?$(curl -s "$1" | sed -n "/watch_fullscreen/s;.*\(video_id.\+\)&title.*;\1;p")")'


 

  # For newbies with Linux			 #
##################################################

function newbies()
{
read -sn 1 -p "1/10. Welcome to Ubuntu. Relax. Take a breath. Just because it's not Windows doesn't mean it will be difficult to figure out. Especially with me at the wheel. ;)

"
read -sn 1 -p "﻿2/10. Ubuntu is an operating system, just like Windows (ie. XP, Vista, 7). It is a Linux distro, meaning it uses the Linux kernel, which is essentially the brains of the operating system. Ubuntu is highly customizable, and I have tweaked it to look similar to Windows, but it can look, feel, and run any way you'd like. Unlike Windows, Ubuntu is free, as well as nearly all of it's applications. Less than 1% of the world uses Linux; about half of that use Ubuntu (#1 ranked Linux distro)). And due to this, and the fact that it's structure is different than Windows, it is pretty much virus-free. Also, no Windows viruses can ever harm a Linux/Ubuntu computer. So download away.

"
read -sn 1 -p "3/10. Your computer's username is 'Me'. Your computer's password is 'password'. The password can easily be changed.

"
read -sn 1 -p "﻿4/10. To change the password, you must change both the User and the Default Keyring passwords. First, change the user password, by going to Menu (bottom left button) -> System -> Preferences -> About Me and click 'Change Password...'. Second, change the Default Keyring password by going to Menu (bottom left button) -> Accessories -> Passwords and Encryption Keys and find 'Passwords: default', click it with the right mouse button, and select 'Change Password'.

"
read -sn 1 -p "5/10. Ubuntu updates and upgrades are currently set up to install important security updates as well as to pop up a box prompting you to click install when anything else requires an upgrade. Very easy. Just need password. One thing about updates on Ubuntu is it updates everything, both the operating system and the installed applications through the repositories (official and unofficial servers that house a large number of various applications and games).

"
read -sn 1 -p "6/10. Your home folder (similar to a 'My Documents' folder in Windows) is 'me', and can be opened either by going to Menu (bottom left button) -> Places -> Home Folder, OR double-clicking the left mouse button on 'me's Home' on the Desktop. The 'Temp' folder inside is what is set for all downloads and is my ideal for using as the working folder for whatever you want. In the 'Pictures' folder, there is a 'Backgrounds' folder that includes all of your desktop backgrounds and is where you can add or remove backgrounds.

"
read -sn 1 -p "7/10. There are some application subsitutes to mention: [OpenOffice -> Microsoft Office], [(Totem) Movie Player -> Windows Media Player], [Evolution Mail -> Microsoft Outlook or Outlook Express], [Nautilus File Manager -> Windows Explorer].

"
read -sn 1 -p "8/10. If you'd like to add/remove software, Ubuntu has a very easy way to do so. Just go to the Ubuntu Software Center, by going to Menu (bottom left button) -> Ubuntu Software Center. It lists all the software found in the repositories.

"
read -sn 1 -p "9/10. If you wish to open this extremely helpful text again, it's as easy as: single-clicking the right mouse button anywhere on the Desktop (or in Nautilus File Manager) -> Scripts -> My_Scripts -> For-Newbies -> For-Newbies.sh.

"
read -sn 1 -p "10/10. To get rid of this damn script at startup because you are sick of seeing it every time you log into your computer, go to Menu (bottom left button) -> Other -> Startup Applications and uncheck 'For Newbies'.

"
}



   #     ThePirateBay.org torrent search         #
##################################################

function piratebay()
{
lynx -dump http://thepiratebay.org/search/$@|awk '/TPB.torrent$/ {print $2}'
}


  #     Pronounce an English word	         #
##################################################

###### usage:	pronounce "word1" "word2" "word3" "..."
function pronounce() { for a in $@; do wget -qO- $(wget -qO- "http://www.m-w.com/dictionary/$a" | grep 'return au' | sed -r "s|.*return au\('([^']*)', '([^'])[^']*'\).*|http://cougar.eb.com/soundc11/\2/\1|") | aplay -q; done }


  #   Reminder for whatever whenever		 #
##################################################

function remindme()
{
sleep $1 && zenity --info --text "$2" &
}



 #     Make a backup before editing a file	 #
##################################################

function safeedit() {
cp $1 ${1}.backup && vim $1
}



 # Screencasting with mplayer webcam window	 #
##################################################

function screencastw()
{
mplayer -cache 128 -tv driver=v4l2:width=176:height=177 -vo xv tv:// -noborder -geometry "95%:93%" -ontop | ffmpeg -y -f alsa -ac 2 -i pulse -f x11grab -r 30 -s `xdpyinfo | grep 'dimensions:'|awk '{print $2}'` -i :0.0 -acodec pcm_s16le output.wav -an -vcodec libx264 -vpre lossless_ultrafast -threads 0 output.mp4
}



 # Cut a part of a video 			 #
##################################################

# ("$1" for original file, "$2" for new file, "$3" is start time, & "$4" is length of video desired)
function splitvideo()
{
ffmpeg -vcodec copy -acodec copy -i "$1" -ss "$3" -t "$4" "$2"
}

 
 # Stopwatch and Countdown Timer	         #
##################################################

function stopwatch() {

BEGIN=$(date +%s)
while true; do
    NOW=$(date +%s)
    DIFF=$(($NOW - $BEGIN))
    MINS=$(($DIFF / 60))
    SECS=$(($DIFF % 60))
    echo -ne "Time elapsed: $MINS:`printf %02d $SECS`\r"
    sleep .1
done
}



###### stopwatch with log
function stop_watch()
{
START=$( date +%s ); while true; do CURRENT=$( date +%s ) ; echo $(( CURRENT-START )) ; sleep 1 ; echo -n ^[[A ; done
}



###### countdown clock
function countdown() { case "$1" in -s) shift;; *) set $(($1 * 60));; esac; local S=" "; for i in $(seq "$1" -1 1); do echo -ne "$S\r $i\r"; sleep 1; done; echo -e "$S\rBOOM!"; }



  # Set terminal title				 #
##################################################

function terminal_title {
    echo -en "\033]2;$@\007"
}



 
# Touchpad stuff				 #
##################################################

###### to get information on touchpad
alias touchpad_id='xinput list | grep -i touchpad'



###### to disable touchpad
# using 'touchpad_id', set the number for your touchpad (default is 12)
function off()
{
touchpad=12
xinput set-prop $touchpad "Device Enabled" 0
}



###### to enable touchpad
# using 'touchpad_id', set the number for your touchpad (default is 12)
function on()
{
touchpad=12
xinput set-prop $touchpad "Device Enabled" 1
}



 # Search for a show at TV.COM			 #
##################################################

function tvcom() {
firefox "http://www.tv.com/search.php?type=11&stype=all&tag=search%3Bfrontdoor&qs="${@}"&stype=program" &
}


 # Convert text file to pdf			 #
##################################################

# Requires:	sudo apt-get install txt2html python-pisa
function txt2pdf() { xhtml2pdf -b "${1%.*}" < <(txt2html "$1"); }



 # Text message on wallpaper			 #
##################################################

function wallpaperWarn() { BG="/desktop/gnome/background/picture_filename"; convert "`gconftool-2 -g $BG`" -pointsize 70 -draw "gravity center fill red  text 0,-360 'Warn' fill white  text 0,360 'Warn'" /tmp/w.jpg; gconftool-2 --set $BG -t string "/tmp/w.jpg" ; }


  

 # Crawl a webpage for links			 #
##################################################

function webcrawl()
{
lynx -dump $1 | grep -A999 "^References$" | tail -n +3 | awk '{print $2 }'
}


  # Download all files of a certain type with wget #
##################################################

###### usage: wgetall mp3 http://example.com/download/
function wgetall() { wget -r -l2 -nd -Nc -A.$@ $@ ; }



  # Which PATH variable should use for this script?#
######################################################

function whichpath() { local -A path; local c p; for c; do p=$(type -P "$c"); p=${p%/*}; path[${p:-/}]=1; done; local IFS=:; printf '%s\n' "${!path[*]}"; }



   # Adds some text in the terminal frame		 #
###########################################################

function xtitle()
{
    case "$TERM" in
        *term | rxvt)
            echo -n -e "\033]0;$*\007" ;;
        *)
            ;;
    esac
}


 
  # To create a ZIP archive of a file or folder	 #
##################################################

function zipf() { zip -r "$1".zip "$1" ; }

 
