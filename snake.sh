#!/bin/bash

IFS=''

# Terminal dimensions for the game area
declare -i height=$(($(tput lines)-5)) width=$(($(tput cols)-2))

# Snake state
declare -i head_r head_c tail_r tail_c
declare -i alive
declare -i length
declare body
declare -i direction delta_dir
declare -i score

# Colors
border_color="\e[30;43m"
snake_color="\e[32;42m"
food_color="\e[34;44m"
text_color="\e[31;43m"
no_color="\e[0m"

# Direction arrays: 0=up, 1=right, 2=down, 3=left
move_r=([0]=-1 [1]=0 [2]=1 [3]=0)
move_c=([0]=0 [1]=1 [2]=0 [3]=-1)

# Signals (for process communication)
SIG_UP=USR1
SIG_RIGHT=USR2
SIG_DOWN=URG
SIG_LEFT=IO
SIG_QUIT=WINCH
SIG_DEAD=HUP

init_game() {
    clear
    echo -ne "\e[?25l"
    stty -echo
    for ((i=0; i<height; i++)); do
        for ((j=0; j<width; j++)); do
            eval "arr$i[$j]=' '"
        done
    done
}

move_and_draw() {
    echo -ne "\e[${1};${2}H$3"
}

draw_board() {
    move_and_draw 1 1 "$border_color+$no_color"
    for ((i=2; i<=width+1; i++)); do
        move_and_draw 1 $i "$border_color-$no_color"
    done
    move_and_draw 1 $((width + 2)) "$border_color+$no_color"
    echo

    for ((i=0; i<height; i++)); do
        move_and_draw $((i+2)) 1 "$border_color|$no_color"
        eval echo -en "\"\${arr$i[*]}\""
        echo -e "$border_color|$no_color"
    done

    move_and_draw $((height+2)) 1 "$border_color+$no_color"
    for ((i=2; i<=width+1; i++)); do
        move_and_draw $((height+2)) $i "$border_color-$no_color"
    done
    move_and_draw $((height+2)) $((width + 2)) "$border_color+$no_color"
    echo
}

init_snake() {
    alive=0
    length=10
    direction=0
    delta_dir=-1
    score=0
    head_r=$((height/2-2))
    head_c=$((width/2))
    body=''
    for ((i=0; i<length-1; i++)); do
        body="1$body"
    done
    local p=$((${move_r[1]} * (length-1)))
    local q=$((${move_c[1]} * (length-1)))
    tail_r=$((head_r+p))
    tail_c=$((head_c+q))
    eval "arr$head_r[$head_c]=\"${snake_color}o$no_color\""
    prev_r=$head_r
    prev_c=$head_c
    b=$body
    while [ -n "$b" ]; do
        local p=${move_r[$(echo $b | grep -o '^[0-3]')]}
        local q=${move_c[$(echo $b | grep -o '^[0-3]')]}
        new_r=$((prev_r+p))
        new_c=$((prev_c+q))
        eval "arr$new_r[$new_c]=\"${snake_color}o$no_color\""
        prev_r=$new_r
        prev_c=$new_c
        b=${b#[0-3]}
    done
}

is_dead() {
    if [ "$1" -lt 0 ] || [ "$1" -ge "$height" ] || \
       [ "$2" -lt 0 ] || [ "$2" -ge "$width" ]; then
        return 0
    fi
    eval "local pos=\${arr$1[$2]}"
    if [ "$pos" == "${snake_color}o$no_color" ]; then
        return 0
    fi
    return 1
}

give_food() {
    local food_r food_c pos
    while true; do
        food_r=$((RANDOM % height))
        food_c=$((RANDOM % width))
        eval "pos=\${arr$food_r[$food_c]}"
        if [ "$pos" = " " ]; then
            break
        fi
    done
    eval "arr$food_r[$food_c]=\"$food_color@$no_color\""
}

move_snake() {
    local newhead_r=$((head_r + move_r[direction]))
    local newhead_c=$((head_c + move_c[direction]))
    eval "local pos=\${arr$newhead_r[$newhead_c]}"
    if is_dead $newhead_r $newhead_c; then
        alive=1
        return
    fi
    if [ "$pos" == "$food_color@$no_color" ]; then
        length+=1
        eval "arr$newhead_r[$newhead_c]=\"${snake_color}o$no_color\""
        body="$(((direction+2)%4))$body"
        head_r=$newhead_r
        head_c=$newhead_c
        score+=1
        give_food
        return
    fi
    head_r=$newhead_r
    head_c=$newhead_c
    local d=$(echo $body | grep -o '[0-3]$')
    body="$(((direction+2)%4))${body%[0-3]}"
    eval "arr$tail_r[$tail_c]=' '"
    eval "arr$head_r[$head_c]=\"${snake_color}o$no_color\""
    local p=${move_r[(d+2)%4]}
    local q=${move_c[(d+2)%4]}
    tail_r=$((tail_r+p))
    tail_c=$((tail_c+q))
}

change_dir() {
    if [ $(((direction+2)%4)) -ne $1 ]; then
        direction=$1
    fi
    delta_dir=-1
}

getchar() {
    trap "" SIGINT SIGQUIT
    trap "return;" SIGTERM
    while true; do
        read -rsn1 key
        if [[ "$key" == $'\e' ]]; then
            read -rsn2 rest
            key+="$rest"
            case "$key" in
                $'\e[A') if kill -0 $game_pid 2>/dev/null; then kill -$SIG_UP $game_pid; fi ;;
                $'\e[B') if kill -0 $game_pid 2>/dev/null; then kill -$SIG_DOWN $game_pid; fi ;;
                $'\e[C') if kill -0 $game_pid 2>/dev/null; then kill -$SIG_RIGHT $game_pid; fi ;;
                $'\e[D') if kill -0 $game_pid 2>/dev/null; then kill -$SIG_LEFT $game_pid; fi ;;
            esac
        else
            case "$key" in
                [qQ]) if kill -0 $game_pid 2>/dev/null; then kill -$SIG_QUIT $game_pid; fi; return ;;
                [kK]) if kill -0 $game_pid 2>/dev/null; then kill -$SIG_UP $game_pid; fi ;;
                [lL]) if kill -0 $game_pid 2>/dev/null; then kill -$SIG_RIGHT $game_pid; fi ;;
                [jJ]) if kill -0 $game_pid 2>/dev/null; then kill -$SIG_DOWN $game_pid; fi ;;
                [hH]) if kill -0 $game_pid 2>/dev/null; then kill -$SIG_LEFT $game_pid; fi ;;
            esac
        fi
    done
}

game_loop() {
    trap "delta_dir=0;" $SIG_UP
    trap "delta_dir=1;" $SIG_RIGHT
    trap "delta_dir=2;" $SIG_DOWN
    trap "delta_dir=3;" $SIG_LEFT
    trap "alive=2;" $SIG_QUIT
    while [ "$alive" -eq 0 ]; do
        echo -e "\n${text_color}           Your score: $score $no_color"
        if [ "$delta_dir" -ne -1 ]; then
            change_dir $delta_dir
        fi
        move_snake
        draw_board
        sleep 0.03
    done
    # game over
    echo -e "${text_color}Oh, No! You 0xdead$no_color"
    kill -TERM $$
}

clear_game() {
    stty echo
    echo -e "\e[?25h"
}

main() {
    while true; do
        init_game
        init_snake
        give_food
        draw_board
        game_loop &
        game_pid=$!
        getchar
        clear_game
        # Retry/Exit prompt
        while true; do
            echo -ne "${text_color}Retry (R) or Exit (E)? $no_color"
            read -n1 key
            echo
            case "$key" in
                [Rr]) break ;; # Retry outer loop
                [Ee]) exit 0 ;; # Exit script
                *) echo "Please press R or E." ;;
            esac
        done
    done
}

main
exit 0
