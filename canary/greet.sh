#!/bin/bash
greet() { echo "Hi there, $1! Welcome."; }
farewell() { echo "Goodbye, $1!"; }
"$@"
