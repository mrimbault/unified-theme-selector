
# Unified theme selector

Use [rofi](https://github.com/DaveDavenport/rofi) to display installed themes,
preview the selected theme on the rofi window, then apply the theme
configuration to other applications, and reload their configuration if they are
already running.  Adapted from
[rofi-theme-selector](https://github.com/DaveDavenport/rofi/blob/next/script/rofi-theme-selector)
script.

Supports:
- termite
- tmux
- vim
- rofi
- i3wm
- i3bar

Note about Vim theme change support: reloading running Vim instances only works
if they are run through tmux.

## Installation

Installation:
```
sudo make install
```

Installs by default under `/usr/local` (`/usr/local/bin`, `/usr/local/share`,
etc.).

To change the installation prefix:
```
make prefix=/customdir install
```
This will install files directly under the new prefix (`/customdir/bin`,
`/customdir/share`, etc.).

To change the installation root, but keep the prefix:
```
make DESTDIR=/customdir install
```
With default prefix, this will install files under `/customdir/usr/local/`
(`/customdir/usr/local/bin`, `/customdir/usr/local/share`, etc.).

## Create theme files

Theme files should be installed into the fillowing directory:
`~/.local/share/unified-theme-selector/themes`

See [examples of theme
files](https://github.com/mrimbault/mr_systemconf/tree/master/themes).

## Change configuration

To change defaults variables into the script, one can create the following
configuration file: `~/.local/config/unified-theme-selector"`.  For example:
~~~
APPLIST="i3 vim termite tmux"
THEMEDIR="/usr/local/share/themes"
~~~


