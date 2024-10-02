#!/usr/bin/env bash
# Algoritmika DBMS "Lessons/Payment"
# Prerequisites: sqlite3, batcat
#
# Author: Sergey Samoylov


function main() {
    # print centered heading
    heading="=== WELCOME TO ALGORITMIKA LESSONS/PAYMENT DATABASE ==="
    width_terminal=$(tput cols)
    padding=$(( (width_terminal - ${#heading}) / 2 ))
    printf "%*s\n\n" $((padding + ${#heading})) "$heading"

    setup # Exports variables, no need to make lots of globals
    add_tables # Old and new payments are added to DB as needed

    # Main interface:
    case "$choice" in
        -a ) add;;
        -c ) export_to_csv;;
        -h ) help_algo;;
        -v ) view && total;;
        * ) total;;
    esac

    # ~ do not PWD after CD -
    cd ~-
}

function setup() {
    req_progs=(sqlite3 batcat)
    for p in ${req_progs[@]}
        do
            hash "$p" 2>&- || \
	    { echo >&2 " Required program \"$p\" not installed."; exit 1; }
        done

    db_dir="$HOME/.bin/databases"
    db="algoritmika.db"
    tl="lessons" # tl == table_lessons
    tp="payment" # tp == table_payment before 2024-10-01

    # Payments increase after September, 30 (2024)
    today=$(date +%s)
    September_30=$(date -d "2024-09-30" +%s)
    [ $today -gt $September_30 ] && tp="payment_2024_10_01"

    mkdir -p $db_dir
    cd $db_dir
}

function add_tables() {
      # Have to move this block left for EOF to work. Don't like "\".
sqlite3 "$db" <<EOF
CREATE TABLE IF NOT EXISTS $tl(
"date" text, "time" text, "course" text, "subject" text, "students" integer);
CREATE TABLE IF NOT EXISTS $tp (
  'students' integer,
  'offline' integer,
  'online' integer,
  'comment' text
);
EOF
    # Check if there is data in payment* table
    data_in_payments=$(sqlite3 "$db" "SELECT COUNT(*) FROM $tp;")
    [ $data_in_payments -lt 1 ] && payments_insert_data
}

function payments_insert_data() {
    # Populate old payment with data, if it is not there
    offline_payments=($(for i in {650..2450..150}; do echo $i; done))
    online_payments=($(for i in {500..1700..100}; do echo $i; done))
    # Populate payment_2024_10_01 with data, if it is not there
    if [[ $today -gt $September_30 ]]; then
        offline_payments=($(for i in {750..2550..150}; do echo $i; done))
        online_payments=($(for i in {600..1800..100}; do echo $i; done))
    fi
    # Loop to insert values for 13 students
    for i in {1..13}
    do
      offline=${offline_payments[$i-1]}
      online=${online_payments[$i-1]}
sqlite3 "$db" <<EOF
INSERT INTO $tp (students, offline, online)
VALUES ($i, $offline, $online);
EOF
    done
}

function add() {
    while [ 1 ]
        do
            echo -e "Please Enter Your Lesson Info\n"
            current_date=$(date +%Y-%m-%d)
            current_time=$(date +%H:%M)

            # As there's little chance that year will be in time format
            # let's check date and time in one go
            is_valid_data() {
                if [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
                   [[ "$1" =~ ^[0-9]{2}:[0-9]{2}$ ]] ||
                   [[ "$1" =~ ^$ ]]
                then
                    return 0
                else
                    return 1
                fi  
            }   
            
            # This works in reverse way - look first at Usage -> below
            validate_input() {
                local prompt="$1"
                local default_value="$2"
                local input

                while true; do
                    read -p "$prompt [$default_value]: " input
                    [ "$input" = "" ] && input=$default_value
                    if is_valid_data "$input"; then
                        echo "$input"
                        break
                    else
                        echo "Correct format: [$default_value]" >&2
                        echo "Invalid input, please try again." >&2
                    fi
                done
            }

            # Usage is calling validate_input
            # validate_input is calling is_valid_data
            day=$(validate_input "Date" "$current_date")
            start_time=$(validate_input "Time" "$current_time")

            echo "Final day value: $day"

            check="check"
            while [ "$check" = "check" ]
                do
                    read -p "Course [Python Pro 2nd year - offline]: " course
                    if echo "$course" | grep -qE "online|offline"; then
                        check="don't check"
                    else
                        echo "You must chose 'offline' or 'online' here."
                    fi
                done
            read -p "Subject [Kivy basics]: " subject
            [ "$subject" = "" ] && echo "Value needed" && exit 1
            read -p "Number of students: " students
            [ "$students" = "" ] && echo "Value needed" && exit 1

sqlite3 "$db" <<EOF
INSERT INTO $tl
VALUES ('$day', '$start_time', '$course', '$subject', '$students');
EOF
            clear
            echo "Row added to your table $tl in database $db:"

sqlite3 "$db" <<EOF
.mode box
SELECT *
FROM $tl
WHERE date = '$day' and time = '$start_time';
EOF

            echo
            read -p "Would you like to enter another lesson? [y/n]: " answer

            [ "$answer" = "n" ] && echo "Goodbye..." && exit 1 || clear
        done
}

function view() {
    [ "$width_terminal" -le 96 ] && q="course," || q="course, subject, $tl.students,"
    # View current month only, as it is the one for payment
sqlite3 "$db" <<EOF
.mode box
SELECT date, time, $q
    (
        CASE
            WHEN $tl.course LIKE '%offline%' THEN $tp.offline
            WHEN $tl.course LIKE '%online%' THEN $tp.online
        END
    ) AS money
FROM $tl
JOIN $tp ON $tl.students = $tp.students
WHERE strftime('%Y-%m', date) = strftime('%Y-%m', 'now');
EOF
}

function total() {
sqlite3 "$db" <<EOF
.mode box
SELECT
    SUM(
        CASE
            WHEN $tp.course LIKE '%offline%' THEN $tp.offline
            WHEN $tp.course LIKE '%online%' THEN $tp.online
        END
    ) AS money_total
FROM $tl
JOIN $tp ON $tl.students = $tp.students
WHERE strftime('%Y-%m', date) = strftime('%Y-%m', 'now');
EOF
}

function help_algo() {
    echo " ${0##*/} <no args> - show total sum earned"
    echo " ${0##*/} -a - add lesson to '$tl' table in the $db"
    echo -e "\t-> add - 'offline' or 'online' in the 'course' column!"
    echo " ${0##*/} -c - export data as .csv file"
    echo " ${0##*/} -v - view $db"
    echo -e " ${0##*/} -h - print this help message\n"
}

function export_to_csv() {
    csv_file="$HOME/tmp/algo.csv"
sqlite3 "$db" <<EOF
.mode csv
.output $csv_file
SELECT date, time, course, subject, $tl.students,
    (
        CASE
            WHEN lessons.course LIKE '%offline%' THEN payment.offline
            WHEN lessons.course LIKE '%online%' THEN payment.online
        END
    ) AS money_total
FROM $tl
JOIN $tp ON $tl.students = $tp.students
WHERE strftime('%Y-%m', date) = strftime('%Y-%m', 'now');
EOF
    batcat $csv_file
}

choice=$1
clear
main
