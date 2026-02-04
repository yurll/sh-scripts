#!/usr/bin/env bash

### This script sets up a custom keyboard mapping for macOS users
### using the M4 european keyboard layout. It swaps the button left to "1" to work as "`"
### and while with "SHIFT" it works as "~" instead of "§".

SESSION_FLAG="/tmp/zsh_session_$(whoami)"

# Keyboard mapping for macOS M4 european keyboard layout
if [[ ! -f "$SESSION_FLAG" ]]; then
    hidutil property --set '{"UserKeyMapping":[
        {"HIDKeyboardModifierMappingSrc": 0x700000064, "HIDKeyboardModifierMappingDst": 0x700000035},
        {"HIDKeyboardModifierMappingSrc": 0x700000035, "HIDKeyboardModifierMappingDst": 0x7000000E1}
    ]}'
    touch "$SESSION_FLAG"
fi
