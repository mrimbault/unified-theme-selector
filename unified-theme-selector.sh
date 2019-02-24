#!/usr/bin/env bash
#------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2019 Mael Rimbault
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#------------------------------------------------------------------------------
#
# Use rofi to display installed themes, preview the selected theme on the rofi
# window, and then apply the theme configuration to other applications, reload
# their configuration if they are already running.
# FIXME adapted from rofi-theme-selector script
#
# Put bash on "strict mode".
# See: http://redsymbol.net/articles/unofficial-bash-strict-mode/
# And: https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
# Immediately exit on any error.
set -o errexit
# Raise an error when using an undefined variable, instead of silently using
# the empty string.
set -o nounset
# Raise an error when any command involved in a pipe fails, not just the last
# one.
set -o pipefail
# Remove whitespace from default word split characters.
IFS=$'\n\t'

# Declare "die" function, used to exit with an error when preliminary checks
# fail on a script.
die() {
    echo "ERROR: $*"
    exit 1
}

self="$(basename -s ".sh" "$0")"
version="0.1-dev"

# FIXME local config dir
# Default configuration.
APPLIST=("i3" "vim" "termite" "tmux")
DATADIR="${HOME}/.local/share/${self}"
THEMEDIR="${DATADIR}/themes"
CONFIGFILE="${HOME}/.local/config/${self}"
SELECTED_THEME=""
SELECTED=""

# Source local configuration file if present to overwrite defaults.
if [ -r "${CONFIGFILE}" ]; then
    # Silence shellcheck about "SC1090: Can't follow non-constant source".
    # shellcheck source=/dev/null
    source "$CONFIGFILE"
fi

TMP_CONFIG_FILE="$(mktemp)"

# Array with parts to the found themes, and array with the printable name.
declare -a themes
declare -a theme_names
# Indicates what entry is selected.
declare -i SELECTED

# Print usage, formatted to generate man page using help2man.
print_usage() {

    printf '
Use rofi to display installed themes, preview the selected theme on the rofi
window, and then apply the theme configuration to other applications, reload
their configuration if they are already running.

Usage: %s [OPTION]

Without argument, it opens a rofi dmenu window showing installed themes.

Supported options:
  -T <theme_name>   Directly select a theme from command line, no menu.
  -h                Prints this help and exits.
  -v                Prints version and exits.

Report bugs to <mael.rimbault@gmail.com>.
' "$self"

}

# Print version and copyright, formatted to generate man page using help2man.
print_version() {

    printf '%s %s

Copyright (C) 2019 Mael Rimbault.

License MIT: <https://opensource.org/licenses/MIT>.

Written by Mael Rimbault.
' "$self" "$version"

}


# This function use sed commands to replace every lines between two markers on
# a configuration file with the content from another file.  This is a ugly hack
# used as a substitute for a proper "include" configuration feature.
replace_file_section() {

    # FIXME test files
    configfile="$1"
    includefile="$2"

    # FIXME default to string "INCLUDE"
    # FIXME allow to specify full include strings, begin and end.
    includestring="$3"
    INCBEG="## #INCLUDE# #${includestring}# #BEGIN# ##"
    INCEND="## #INCLUDE# #${includestring}# #END# ##"

    # Backup old configuration file in case something went wrong.
    cp -p "$configfile" "${configfile}.before_replaced"
    # The sed command works like this:
    # - print all lines until the include section begin string $INCBEG;
    # - read the file to be included and print it after $INCBEG;
    # - print all lines from section end $INCEND to the end of the file.
    # Note that this won't work if the same include string is present more than
    # once.
    sed -n \
        -e "1,/${INCBEG}/p" \
        -e "/${INCBEG}/r ${includefile}" \
        -e "/${INCEND}/,\$p" \
        "${configfile}.before_replaced" > "$configfile"

}

# We cannot force running Vim instances to reload their configuration using a
# signal or anything.  So we use a somewhat clever (read: ugly and unecessary
# complex) trick to directly send key strokes to these Vim instances using
# tmux.
# See: https://blog.damonkelley.me/2016/09/07/tmux-send-keys/
reload_vim_tmux() {
    local panes
    local pane
    # Get list of pane ids running Vim (based on last 6 characters from pane
    # title), in all Tmux sessions and windows.
    panes=$(tmux list-panes -a -F "#{=-6:pane_title}#{pane_id}" |
                sed -n '/^ - VIM/ s/^.\{6\}//p')
    # Send reload keys to Vim instances (and escape to ensure we are in normal
    # mode).
    # FIXME use "jk" ? what about command mode, or other modes ?
    # FIXME add a map in vimrc (like C-[) that works like ESC in all modes
    if [ -n "$panes" ]; then
        for pane in $panes; do
            tmux send-keys -t "$pane" "jk:so ${HOME}/.vim_current_theme" Enter
            tmux send-keys -t "$pane" ":redraw" Enter
            tmux send-keys -t "$pane" ":AirlineRefresh" Enter
            # FIXME send "syn off" then "syn on" if syntax was on?
        done
    fi
    # FIXME if the previous fails, maybe use "-l" option, and then send only "Enter"
}


vim_change_theme() {

    # Check if dependencies are installed.
    if ! command -v vim >/dev/null; then
        die '"vim" command is missing.'
    fi

    # Create symlink to the theme file that will be sourced from vimrc.
    if [ -f "${HOME}/.vim_current_theme" ]; then
        rm "${HOME}/.vim_current_theme"
    fi
    ln -s "${THEMEDIR}/vim_theme_${SELECTED_THEME}.vim" "${HOME}/.vim_current_theme"

    # Only reload Vim instances running through tmux, if it is installed.
    if command -v tmux >/dev/null; then
        reload_vim_tmux
    fi

}

tmux_change_theme() {

    # Check if dependencies are installed.
    if ! command -v tmux >/dev/null; then
        die '"tmux" command is missing.'
    fi

    # Create symlink to the theme file that will be sourced from vimrc.
    if [ -f "${HOME}/.tmux_current_theme" ]; then
        rm "${HOME}/.tmux_current_theme"
    fi
    ln -s "${THEMEDIR}/tmux_theme_${SELECTED_THEME}.conf" "${HOME}/.tmux_current_theme"

    # Reload tmux theme configuration.
    tmux source-file "${HOME}/.tmux_current_theme"

}

termite_change_theme() {

    # Check if dependencies are installed.
    if ! command -v termite >/dev/null; then
        die '"termite" command is missing.'
    fi

    replace_file_section "${HOME}/.config/termite/config" \
        "${THEMEDIR}/termite_theme_${SELECTED_THEME}" \
        "TERMITE"

    # Reload configuration for all termite instances.
    pkill -SIGUSR1 termite

}

i3_change_theme() {

    # Check if dependencies are installed.
    if ! command -v i3-msg >/dev/null; then
        die '"i3-msg" command is missing.'
    fi

    replace_file_section "${HOME}/.config/i3/config" \
        "${THEMEDIR}/i3_theme_${SELECTED_THEME}" \
        "I3WM"

    replace_file_section "${HOME}/.config/i3/config" \
        "${THEMEDIR}/i3bar_theme_${SELECTED_THEME}" \
        "I3BAR"

    # Reload i3 configuration.
    i3-msg reload

}

# Find locally installed themes.  This fills in #themes array and formats a
# displayable string #theme_names.
get_themes() {
    # FIXME create themes based on: https://github.com/DaveDavenport/rofi-themes/tree/master/Official%20Themes
    # Add user dir.
    if [ -d "${THEMEDIR}" ]
    then
        echo "Checking themes in: ${THEMEDIR}"
        # FIXME should use find instead of for loop using * jocker
        for file in "${THEMEDIR}"/*.rasi
        do
            if [ -f "${file}" ]
            then
                themes+=("${file}")
                # Extract only the theme names by removing full path, beginning
                # of the file name, and file extension.
                theme_names+=("$(basename -s ".rasi" "${file}" | sed 's/rofi_theme_//')")
            fi
        done
    fi
}

# Create a copy of current rofi configuration.
create_config_copy() {
    "rofi" -dump-xresources > "${TMP_CONFIG_FILE}"
}

# Print the list out so it can be displayed by rofi.
create_theme_list() {
    OLDIFS=${IFS}
    IFS='|'
    for themen in "${theme_names[@]}"
    do
        echo "${themen}"
    done
    IFS=${OLDIFS}
}

select_theme () {
    local MORE_FLAGS
    MORE_FLAGS=(-dmenu -format i -no-custom -p "Theme" -markup)
    MORE_FLAGS+=(-config "${TMP_CONFIG_FILE}" -i)
    MORE_FLAGS+=(-kb-custom-1 "Alt-a")
    MORE_FLAGS+=(-u 2,3 -a 4,5 )
    local CUR
    CUR="default"
    while true; do
        declare -i RTR
        declare -i RES
        local MESG
        MESG="You can preview themes by hitting <b>Enter</b>.
<b>Alt-a</b> to accept the new theme.
<b>Escape</b> to cancel
Current theme: <b>${CUR}</b>"
        # FIXME why not local?
        THEME_FLAG=
        if [ -n "${SELECTED}" ]; then
            THEME_FLAG=("-theme" "${themes[${SELECTED}]}")
        fi
        RES="$(create_theme_list | "rofi" "${THEME_FLAG[@]}" \
                "${MORE_FLAGS[@]}" -cycle -selected-row "${SELECTED}" \
                -mesg "${MESG}")"
        RTR=$?
        if [ ${RTR} = 10 ]; then
            return 0
        elif [ ${RTR} = 1 ]; then
            return 1
        fi
        CUR=${theme_names[${RES}]}
        SELECTED=${RES}
    done
}

# Create if not exists, then removes #include of .theme file (if present) and
# add the selected theme to the end.  Repeated calls should leave the config
# clean-ish
set_theme() {
    CDIR="${HOME}/.config/rofi/"
    if [ ! -d "${CDIR}" ]; then
        mkdir -p "${CDIR}"
    fi
    if [ -f "${CDIR}/config.rasi" ]; then
        sed -i "/@import.*/d" "${CDIR}/config.rasi"
        echo "@import \"${1}\"" >> "${CDIR}/config.rasi"
    else
        if [ -f "${CDIR}/config" ]; then
            sed -i "/rofi\.theme: .*\.rasi$/d" "${CDIR}/config"
        fi
        echo "rofi.theme: ${1}" >> "${CDIR}/config"
    fi
}

# Get script arguments.
while getopts 'hvT:' flag; do
  case "${flag}" in
    h) print_usage; exit 0 ;;
    v) print_version; exit 0 ;;
    T) SELECTED_THEME="${OPTARG}" ;;
    *) print_usage
       die "Unknown option \"$flag\"." ;;
  esac
done

# Check if dependencies are installed.
if ! command -v rofi >/dev/null; then
    die '"rofi" utility must be installed.'
fi
# Get installed themes.
get_themes
# Check if there are installed themes.
if [ ${#themes[@]} = 0 ]; then
    rofi -e "No themes found."
    exit 0
fi
# If theme is not already selected using "-T" option, then launch rofi.
if [ -z "$SELECTED_THEME" ]; then
    # Create copy of rofi configuration to preview the selected theme.
    create_config_copy
    # Show the themes to user.
    if select_theme && [ -n "${SELECTED}" ]; then
        selected_full_path="${themes[${SELECTED}]}"
        # Set rofi theme.
        set_theme "${selected_full_path}"
        # Specify selected global theme name.
        SELECTED_THEME="${theme_names[${SELECTED}]}"
    fi
    # Remove temporary rofi configuration used for preview.
    rm "${TMP_CONFIG_FILE}"
    if [ -z "$SELECTED_THEME" ]; then
        # No theme selected, no change necessary.
        exit 0
    fi
else
    # Set rofi theme without lauching rofi menu.
    for i in "${!theme_names[@]}"; do
       if [[ "${theme_names[$i]}" = "${SELECTED_THEME}" ]]; then
           selected_full_path="${themes[${i}]}"
           set_theme "${selected_full_path}"
       fi
    done
fi

# FIXME backup current theme so we can rollback
# FIXME function?
current_theme_file="${DATADIR}/current_global_theme"
previous_theme_file="${DATADIR}/previous_global_theme"
# FIXME write theme name into one file: ~/.themes/current_theme
# Backup previous theme name if exists, so we can rollback in case of failure.
if [ -r "$current_theme_file" ]; then
    mv "$current_theme_file" "$previous_theme_file"
fi
# Write the new theme name.
echo "${SELECTED_THEME}" > "$current_theme_file"

# Change the actual global theme.  For every application supporting dynamic
# theme changing, launch its specific script.
for app in "${APPLIST[@]}"; do
    case "$app" in
      "vim") vim_change_theme ;;
      "i3") i3_change_theme ;;
      "termite") termite_change_theme ;;
      "tmux") tmux_change_theme ;;
      "*") die "Unsupported application: \"$app\"." ;;
    esac
done

unset HOMEDIR
unset THEMEDIR
unset APPLIST
unset SELECTED_THEME

