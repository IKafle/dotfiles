# Shell config — holiday greetings and session settings

# Use %-d to avoid space-padding on single-digit days (fixes "January 1" vs "January1")
day=$(date +"%B%-d")
year=$(date +"%Y")
hol=1

if   [ "$day" = "January1"    ]; then holgreet="Happy New Year! Have a great $year."
elif [ "$day" = "January28"   ]; then holgreet="Tomorrow is your Wife's Birthday — better plan something special!"
elif [ "$day" = "January29"   ]; then holgreet="Happy Birthday Wifey! 🎂"
elif [ "$day" = "February2"   ]; then holgreet="Spring season is here."
elif [ "$day" = "February14"  ]; then holgreet="Happy Valentine's Day ❤️"
elif [ "$day" = "February28"  ]; then holgreet="Happy Birthday $USER! Have a wonderful day 🎉"
elif [ "$day" = "April1"      ]; then holgreet="April Fool's Day — watch your back!"
elif [ "$day" = "October31"   ]; then holgreet="Happy Halloween 🎃"
elif [ "$day" = "December24"  ]; then holgreet="Merry Christmas Eve!"
elif [ "$day" = "December25"  ]; then holgreet="Merry Christmas! 🎄"
elif [ "$day" = "December31"  ]; then holgreet="Happy New Year's Eve — almost there!"
else hol=0
fi

if [ "$hol" = "1" ]; then
    if command -v cowsay &>/dev/null; then
        echo "$holgreet" | cowsay
    else
        echo "  🎉 $holgreet"
    fi
fi

unset day year hol holgreet
