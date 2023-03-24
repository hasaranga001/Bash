#!/usr/bin/env bash
echo "Please enter a number"
read number

if [ $number -gt 0 ]; then
  echo "$number is Positive"
elif [ $number -lt 0 ]; then
  echo "$number is Negative"
else
  echo "$number is zero"
fi 
