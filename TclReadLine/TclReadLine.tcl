#
# You can find the base source for this script at /Users/bsw/test/trysomething/civilizer
#
# Read README.md included in the package for detail
#

package provide TclReadLine 1.2

namespace eval TclReadLine {

    namespace export interact

    # Initialise our own env variables:
    variable PROMPT {\033\[36m> \033\[0m}
    variable COMPLETION_MATCH ""
    
    # Support extensions to the completion handling
    # which will be called in list order.
    # Initialize with the "open sourced" TCL base handler
    # taken from the wiki page
    variable COMPLETION_HANDLERS [list TclReadLine::handleCompletionBase]

    #
    #  This value was determined by measuring 
    #  a cygwin over ssh. 
    #
    variable READLINE_LATENCY 10 ;# in ms
    
    variable CMDLINE ""
    variable CMDLINE_CURSOR 0
    variable CMDLINE_LINES 0
    variable CMDLINE_PARTIAL

    variable ALIASES
    array set ALIASES {}

    # Context data for the history search
    variable HSEARCH_STATE OFF
    variable HSEARCH_LIST [list]
    variable HSEARCH_INDICES [list]
    variable HSEARCH_WORD {}
    
    variable forever 0
    
    # Resource and history files:
    variable HISTORY_SIZE 100
    variable HISTORY_LEVEL 0
    variable HISTFILE $::env(HOME)/.tclline_history
    #variable  RCFILE $::env(HOME)/.tcllinerc
}

proc TclReadLine::ESC {} {
    return "\033"
}

proc TclReadLine::shift {ls} {
    upvar 1 $ls LIST
    set ret [lindex $LIST 0]
    set LIST [lrange $LIST 1 end]
    return $ret
}

proc TclReadLine::readbuf {txt} {
    upvar 1 $txt STRING
    
    set ret [string index $STRING 0]
    set STRING [string range $STRING 1 end]
    return $ret
}

proc TclReadLine::goto {row {col 1}} {
    switch -- $row {
        "home" {set row 1}
    }
    print "[ESC]\[${row};${col}H" nowait
}

proc TclReadLine::gotocol {col} {
    print "\r" nowait
    if {$col > 0} {
        print "[ESC]\[${col}C" nowait
    }
}

proc TclReadLine::clear {} {
    print "[ESC]\[2J" nowait
    goto home
}

proc TclReadLine::clearline {} {
    print "[ESC]\[2K\r" nowait
}

proc TclReadLine::getColumns {} {
    variable COLUMNS
    set cols 0
    if {![catch {exec stty size} size]} {
        lassign $size rows cols
    } elseif {![catch {exec stty -a} err]} {
        # check for Linux stlye stty output
        if {[regexp {rows (= )?(\d+); columns (= )?(\d+)} $err - i1 rows i2 cols]} {
            return [set COLUMNS $cols]
        }
        # check for BSD style stty output
        if {[regexp { (\d+) rows; (\d+) columns;} $err - rows cols]} {
            return [set COLUMNS $cols]
        }
    }
    set COLUMNS $cols
}

proc TclReadLine::localInfo {args} {
    set v [uplevel _info $args]
    if { [string equal "script" [lindex $args 0]] } {
        if { [string equal $v $TclReadLine::ThisScript] } {
            return ""
        }
    }
    return $v
}

proc TclReadLine::localPuts {args} {
    
    set l [llength $args]
    if { 3 < $l } {
        return -code error "Error: wrong \# args"
    }
    
    if { 1 < $l } {
        if { [string equal "-nonewline" [lindex $args 0]] } {
            if { 2 < $l } {
                # we don't send to channel...
                eval _origPuts $args
            } else {
                set str [lindex $args 1]
                append TclReadLine::putsString $str ;# no newline...
            }
        } else {
            # must be a channel
            eval _origPuts $args
        }
    } else {
        append TclReadLine::putsString [lindex $args 0] "\n"
    }
}

proc TclReadLine::prompt {{txt ""}} {
    
    if { "" != [info var ::tcl_prompt1] } {
        rename ::puts ::_origPuts
        rename TclReadLine::localPuts ::puts
        variable putsString
        set putsString ""
        eval [set ::tcl_prompt1]
        set prompt $putsString
        rename ::puts TclReadLine::localPuts
        rename ::_origPuts ::puts
    } else {
        variable PROMPT
        set prompt [subst $PROMPT]
    }
    set txt "$prompt$txt"
    variable CMDLINE_LINES
    variable CMDLINE_CURSOR
    variable COLUMNS
    foreach {end mid} $CMDLINE_LINES break
    
    # Calculate how many extra lines we need to display.
    # Also calculate cursor position:
    set n -1
    set totalLen 0
    set visprompt [regsub -all {\x1b\[[0-9;]*[a-zA-Z]} $prompt {}]  ;# strip colour codes
    set cursorLen [expr {$CMDLINE_CURSOR+[string length $visprompt]}]
    set row 0
    set col 0
    
    # Render output line-by-line to $out then copy back to $txt:
    set found 0
    set out [list]
    foreach line [split $txt "\n"] {
        set len [expr {[string length $line]+1}]
        incr totalLen $len
        if {$found == 0 && $totalLen >= $cursorLen} {
            set cursorLen [expr {$cursorLen - ($totalLen - $len)}]
            set col [expr {$cursorLen % $COLUMNS}]
            set row [expr {$n + ($cursorLen / $COLUMNS) + 1}]
            
            if {$cursorLen >= $len} {
                set col 0
                incr row
            }
            set found 1
        }
        incr n [expr {int(ceil(double($len)/$COLUMNS))}]
        while {$len > 0} {
            lappend out [string range $line 0 [expr {$COLUMNS-1}]]
            set line [string range $line $COLUMNS end]
            set len [expr {$len-$COLUMNS}]
        }
    }
    set txt [join $out "\n"]
    set row [expr {$n-$row}]
    
    # Reserve spaces for display:
    if {$end} {
        if {$mid} {
            print "[ESC]\[${mid}B" nowait
        }
        for {set x 0} {$x < $end} {incr x} {
            clearline
            print "[ESC]\[1A" nowait
        }
    }
    clearline
    set CMDLINE_LINES $n
    
    # Output line(s):
    print "\r$txt"
    
    if {$row} {
        print "[ESC]\[${row}A" nowait
    }
    gotocol $col
    lappend CMDLINE_LINES $row
}

proc TclReadLine::print {txt {wait wait}} {
    # Sends output to stdout chunks at a time.
    # This is to prevent the terminal from
    # hanging if we output too much:
    while {[string length $txt]} {
        puts -nonewline [string range $txt 0 2047]
        set txt [string range $txt 2048 end]
        if {$wait == "wait"} {
            after 1
        }
    }
}

proc TclReadLine::unknown {args} {
    
    set name [lindex $args 0]
    set cmdline $TclReadLine::CMDLINE
    set cmd [string trim [regexp -inline {^\s*[^\s]+} $cmdline]]
    if {[info exists TclReadLine::ALIASES($cmd)]} {
        set cmd [regexp -inline {^\s*[^\s]+} $TclReadLine::ALIASES($cmd)]
    }
    
    set new [auto_execok $name]
    if {$new != ""} {
        set redir ""
        if {$name == $cmd && [info command $cmd] == ""} {
            set redir ">&@ stdout <@ stdin"
        }
        if {[catch {
            uplevel 1 exec $redir $new [lrange $args 1 end]} ret]
        } {
            return
        }
        return $ret
    }
    
    uplevel _unknown $args
}

proc TclReadLine::alias {word command} {
    variable ALIASES
    set ALIASES($word) $command
}

proc TclReadLine::unalias {word} {
    variable ALIASES
    array unset ALIASES $word
}

proc TclReadLine::getCmdlineToCursor {{trim 0}} {
    variable CMDLINE
    variable CMDLINE_CURSOR
    set str [string range $CMDLINE 0 [expr $CMDLINE_CURSOR - 1]]
    if {$trim} {
        set str [string trimright $str]
    }
    return $str
}

proc TclReadLine::setHistorySearchState {state} {
    variable HSEARCH_STATE
    set HSEARCH_STATE $state
}

proc TclReadLine::processHistorySearch {searchWord {direction 1}} {
    variable HSEARCH_STATE
    variable HSEARCH_LIST
    variable HSEARCH_INDICES
    variable HSEARCH_WORD
    switch -- $HSEARCH_STATE {
        OFF {
        }
        SWITCH_ON {
            # The list for the command history in reverse order
            set HSEARCH_LIST [lreverse [getHistory]]
            # The list for the index of the matched command
            set HSEARCH_INDICES [list -1]
            # The current search word
            set HSEARCH_WORD $searchWord

            setHistorySearchState ON
            tailcall processHistorySearch $searchWord 1
        }
        ON {
            if {$direction == 1} { ;# Cursor up
                if {$searchWord == {}} {
                    set searchWord $HSEARCH_WORD
                }

                # When the search starts, this variable is assigned 0
                # Otherwise, it is assigned [the index of the last retrieved command] + 1
                set startIdx [expr [lindex $HSEARCH_INDICES end] + 1]

                set idx [lsearch -start $startIdx -nocase $HSEARCH_LIST "*$searchWord*"]
                if {$idx == -1} { ;# No match found
                    if {[llength $HSEARCH_INDICES] == 1} {
                        # It was a first time try,
                        # which means there is no match for the entire history records
                        setHistorySearchState SWITCH_OFF
                        tailcall processHistorySearch $searchWord 1
                    }
                    # Returns the last command found
                    return [lindex $HSEARCH_LIST [lindex $HSEARCH_INDICES end]]
                } else {
                    set lastCmd [lindex $HSEARCH_LIST [lindex $HSEARCH_INDICES end]]
                    if {$lastCmd == [lindex $HSEARCH_LIST $idx]} {
                        # The new match is identical with the last match.
                        # Retry search until we find a different command
                        set HSEARCH_INDICES [lreplace $HSEARCH_INDICES end end $idx]
                        tailcall processHistorySearch $searchWord 1
                    }
                }
                # Append the index of the new match to the match list
                set HSEARCH_INDICES [lappend HSEARCH_INDICES $idx]
            } else { ;# Cursor down
                if {[llength $HSEARCH_INDICES] > 1} {
                    # Remove the index at the top of the match list
                    set HSEARCH_INDICES [lreplace $HSEARCH_INDICES end end]
                }
                set idx [lindex $HSEARCH_INDICES end]
            }
            return [lindex $HSEARCH_LIST $idx]
        }
        SWITCH_OFF {
            set HSEARCH_LIST [list]
            set HSEARCH_INDICES [list]
            set HSEARCH_WORD {}
            setHistorySearchState OFF
        }
    }
    return {}
}

# Key bindings
proc TclReadLine::handleEscapes {} {
    
    variable CMDLINE
    variable CMDLINE_CURSOR
    
    upvar 1 keybuffer keybuffer
    set seq ""
    set found 0
    while {[set ch [readbuf keybuffer]] != ""} {
        append seq $ch

        switch -exact -- $seq {
            "b" { ;# Move to the previous word
                set CMDLINE_CURSOR [tcl_startOfPreviousWord $CMDLINE $CMDLINE_CURSOR]
            }
            "e" { ;# Move to the end of the current word
                set dstCursor [tcl_endOfWord $CMDLINE $CMDLINE_CURSOR]
                if {$dstCursor < 0} {
                    set dstCursor [string length $CMDLINE]
                }
                set CMDLINE_CURSOR $dstCursor
            }
            "f" -
            "w" { ;# Move to the next word
                set dstCursor [tcl_startOfNextWord $CMDLINE $CMDLINE_CURSOR]
                if {$dstCursor < 0} {
                    set dstCursor [string length $CMDLINE]
                }
                set CMDLINE_CURSOR $dstCursor
            }
            "d" { ;# Delete the next word
                set dstCursor [tcl_endOfWord $CMDLINE $CMDLINE_CURSOR]
                if {$dstCursor < 0} {
                    set dstCursor [string length $CMDLINE]
                }
                set CMDLINE [string replace $CMDLINE $CMDLINE_CURSOR $dstCursor]
            }
            "/" {
                set CMDLINE {/}
                set CMDLINE_CURSOR 1
            }
            "0" {
                set CMDLINE_CURSOR 0
            }
            "k" -
            "\[A" { ;# Cursor Up (cuu1,up)
                handleHistory 1
                set found 1; break
            }
            "j" -
            "\[B" { ;# Cursor Down
                handleHistory -1
                set found 1; break
            }
            "l" -
            "\[C" { ;# Cursor Right (cuf1,nd)
                if {$CMDLINE_CURSOR < [string length $CMDLINE]} {
                    incr CMDLINE_CURSOR
                }
                set found 1; break
            }
            "h" -
            "\[D" { ;# Cursor Left
                if {$CMDLINE_CURSOR > 0} {
                    incr CMDLINE_CURSOR -1
                }
                set found 1; break
            }
            "\[1;2C" { ;# Shift + Right ( Move to the next blank ) 
                regexp -start $CMDLINE_CURSOR -indices {\S} $CMDLINE matchedRange
                if {[info exists matchedRange] && [llength $matchedRange]} {
                    regexp -start [lindex $matchedRange 0] -indices {\s} $CMDLINE matchedRange2
                    if {[info exists matchedRange2] && [llength $matchedRange2]} {
                        set CMDLINE_CURSOR [lindex $matchedRange2 0]
                    } else {
                        set CMDLINE_CURSOR [string length $CMDLINE]
                    }
                }
            }
            "\[1;2D" { ;# Shift + Left ( Move to the previous blank )
                set dstCursor [string last " " [string trimright [getCmdlineToCursor]]]
                if { $dstCursor == -1 } {
                    set dstCursor 0
                }
                set CMDLINE_CURSOR $dstCursor
            }
            "\[H" -
            "\[7~" -
            "\[1~" { ;# home
                set CMDLINE_CURSOR 0
                set found 1; break
            }
            "x" -
            "\[3~" { ;# delete
                if {$CMDLINE_CURSOR < [string length $CMDLINE]} {
                    set CMDLINE [string replace $CMDLINE \
                                     $CMDLINE_CURSOR $CMDLINE_CURSOR]
                }
                set found 1; break
            }
            "\[F" -
            "\[K" -
            "\[8~" -
            "\[4~" { ;# end
                set CMDLINE_CURSOR [string length $CMDLINE]
                set found 1; break
            }
            "\[5~" { ;# Page Up
            }
            "\[6~" { ;# Page Down
            }
        }
    }
    return $found
}

proc TclReadLine::handleControls {} {
    
    variable CMDLINE
    variable CMDLINE_CURSOR
    
    upvar 1 char char
    upvar 1 keybuffer keybuffer
    
    # Control chars start at a == \u0001 and count up.
    switch -exact -- $char {
        \u0001 { ;# ^a
            set CMDLINE_CURSOR 0
        }
        \u0002 { ;# ^b
            if { $CMDLINE_CURSOR > 0 } {
                incr CMDLINE_CURSOR -1
            }
        }
        \u0004 { ;# ^d
            print "\n" nowait
            doExit
        }
        \u0005 { ;# ^e
            set CMDLINE_CURSOR [string length $CMDLINE]
        }
        \u0006 { ;# ^f
            if {$CMDLINE_CURSOR < [string length $CMDLINE]} {
                incr CMDLINE_CURSOR
            }
        }
        \u0007 { ;# ^g
            set CMDLINE ""
            set CMDLINE_CURSOR 0
        }
        \u000b { ;# ^k
            variable YANK
            set YANK  [string range $CMDLINE [expr {$CMDLINE_CURSOR  } ] end ]
            set CMDLINE [string range $CMDLINE 0 [expr {$CMDLINE_CURSOR - 1 } ]]
        }
        \u0019 { ;# ^y
            variable YANK
            if { [ info exists YANK ] } {
                set CMDLINE \
                    "[string range $CMDLINE 0 [expr {$CMDLINE_CURSOR - 1 }]]$YANK[string range $CMDLINE $CMDLINE_CURSOR end]"
            }
        }
        \u000e { ;# ^n
            handleHistory -1
        }
        \u0010 { ;# ^p
            handleHistory 1
        }
        \u0015 { ;# ^u
            variable YANK
            set YANK [string range $CMDLINE 0 [expr $CMDLINE_CURSOR-1]] 
            set CMDLINE [string range $CMDLINE [expr $CMDLINE_CURSOR] end]
            set CMDLINE_CURSOR 0
        }
        \u0017 { ;# ^w
            # delete the previous word
            set dstCursor [tcl_startOfPreviousWord $CMDLINE $CMDLINE_CURSOR]
            if {$dstCursor < 0} {
                set dstCursor 0
            }
            set CMDLINE [string replace $CMDLINE $dstCursor $CMDLINE_CURSOR]
            set CMDLINE_CURSOR $dstCursor
        }
        \u0008 -
        \u007f { ;# ^h && backspace ?
            if {$CMDLINE_CURSOR > 0} {
                incr CMDLINE_CURSOR -1
                set CMDLINE [string replace $CMDLINE \
                                 $CMDLINE_CURSOR $CMDLINE_CURSOR]
            }
        }
        \u001b { ;# ESC - handle escape sequences
            handleEscapes
        }
    }
    # Rate limiter:
    set keybuffer ""
}

proc TclReadLine::shortMatch {maybe} {
    # Find the shortest matching substring:
    set maybe [lsort $maybe]
    set shortest [lindex $maybe 0]
    foreach x $maybe {
        while {![string match $shortest* $x]} {
            set shortest [string range $shortest 0 end-1]
        }
    }
    return $shortest
}

proc TclReadLine::addCompletionHandler {completion_extension} {
    variable COMPLETION_HANDLERS
    set COMPLETION_HANDLERS [concat $completion_extension $COMPLETION_HANDLERS]
}

proc TclReadLine::delCompletionHandler {completion_extension} {
    variable COMPLETION_HANDLERS
    set COMPLETION_HANDLERS [lsearch -all -not -inline $COMPLETION_HANDLERS $completion_extension] 
}

proc TclReadLine::getCompletionHandler {} {
    variable COMPLETION_HANDLERS
    return "$COMPLETION_HANDLERS"
}

proc TclReadLine::handleCompletion {} {
    variable COMPLETION_HANDLERS
    foreach handler $COMPLETION_HANDLERS {
        if {[eval $handler] == 1} {
            break
        } 
    }
    return 
}

proc TclReadLine::handleCompletionBase {} {
    variable CMDLINE
    variable CMDLINE_CURSOR
    
    set vars ""
    set cmds ""
    set execs ""
    set files ""
    
    # First find out what kind of word we need to complete:
    set wordstart [string last " " $CMDLINE [expr {$CMDLINE_CURSOR-1}]]
    incr wordstart
    set wordend [string first " " $CMDLINE $wordstart]
    if {$wordend == -1} {
        set wordend end
    } else {
        incr wordend -1
    }
    set word [string range $CMDLINE $wordstart $wordend]
    
    if {[string trim $word] == ""} return
    
    set firstchar [string index $word 0]
    
    # Check if word is a variable:
    if {$firstchar == "\$"} {
        set word [string range $word 1 end]
        incr wordstart
        
        # Check if it is an array key:proc
        
        set x [string first "(" $word]
        if {$x != -1} {
            set v [string range $word 0 [expr {$x-1}]]
            incr x
            set word [string range $word $x end]
            incr wordstart $x
            if {[uplevel \#0 "array exists $v"]} {
                set vars [uplevel \#0 "array names $v $word*"]
            }
        } else {
            foreach x [uplevel \#0 {info vars}] {
                if {[string match $word* $x]} {
                    lappend vars $x
                }
            }
        }
    } else {
        # Check if word is possibly a path:
        if {$firstchar == "/" || $firstchar == "." || $wordstart != 0} {
            set files [glob -nocomplain -- $word*]
        }
        if {$files == ""} {
            # Not a path then get all possibilities:
            if {$firstchar == "\[" || $wordstart == 0} {
                if {$firstchar == "\["} {
                    set word [string range $word 1 end]
                    incr wordstart
                }
                # Check executables:
                foreach dir [split $::env(PATH) :] {
                    foreach f [glob -nocomplain -directory $dir -- $word*] {
                        set exe [string trimleft [string range $f \
                                                      [string length $dir] end] "/"]
                        
                        if {[lsearch -exact $execs $exe] == -1} {
                            lappend execs $exe
                        }
                    }
                }
                # Check commands:
                foreach x [info commands] {
                    if {[string match $word* $x]} {
                        lappend cmds $x
                    }
                }
            } else {
                # Check commands anyway:
                foreach x [info commands] {
                    if {[string match $word* $x]} {
                        lappend cmds $x
                    }
                }
            }
        }
        if {$wordstart != 0} {
            # Check variables anyway:
            set x [string first "(" $word]
            if {$x != -1} {
                set v [string range $word 0 [expr {$x-1}]]
                incr x
                set word [string range $word $x end]
                incr wordstart $x
                if {[uplevel \#0 "array exists $v"]} {
                    set vars [uplevel \#0 "array names $v $word*"]
                }
            } else {
                foreach x [uplevel \#0 {info vars}] {
                    if {[string match $word* $x]} {
                        lappend vars $x
                    }
                }
            }
        }
    }
    
    variable COMPLETION_MATCH
    set maybe [concat $vars $cmds $execs $files]
    set shortest [shortMatch $maybe]
    if {"$word" == "$shortest"} {
        if {[llength $maybe] > 1 && $COMPLETION_MATCH != $maybe} {
            set COMPLETION_MATCH $maybe
            clearline
            set temp ""
            foreach {match format} {
                vars  "35"
                cmds  "1;32"
                execs "32"
                files "0"
            } {
                if {[llength [set $match]]} {
                    append temp "[ESC]\[${format}m"
                    foreach x [set $match] {
                        append temp "[file tail $x] "
                    }
                    append temp "[ESC]\[0m"
                }
            }
            print "\n$temp\n"
        }
    } else {
        if {[file isdirectory $shortest] &&
            [string index $shortest end] != "/"} {
            append shortest "/"
        }
        if {$shortest != ""} {
            set CMDLINE \
                [string replace $CMDLINE $wordstart $wordend $shortest]
            set CMDLINE_CURSOR \
                [expr {$wordstart+[string length $shortest]}]
        } elseif { $COMPLETION_MATCH != " not found "} {
            set COMPLETION_MATCH " not found "
            print "\nNo match found.\n"
        }
    }
}

proc TclReadLine::handleHistory {x} {
    variable HISTORY_LEVEL
    variable HISTORY_SIZE
    variable CMDLINE
    variable CMDLINE_CURSOR
    variable CMDLINE_PARTIAL

    set hsMatch [string trim [processHistorySearch {} $x]]
    if {$hsMatch != {}} {
        set CMDLINE $hsMatch
        set CMDLINE_CURSOR [string length $hsMatch]
        return
    }

    set maxid [expr {[history nextid] - 1}]
    if {$maxid > 0} {
        #
        #  Check for a top level command line and history event
        #  Store this command line locally (i.e. don't use the history stack)
        #
        if {$HISTORY_LEVEL == 0} {
            set CMDLINE_PARTIAL $CMDLINE
        } 
        incr HISTORY_LEVEL $x
        #
        #  Note:  HISTORY_LEVEL is used to offset into
        #  the history events.  It will be reset to zero 
        #  when a command is executed by tclline.
        #  
        #  Check the three bounds of
        #  1) HISTORY_LEVEL <= 0 - Restore the top level cmd line (not in history stack)
        #  2) HISTORY_LEVEL > HISTORY_SIZE
        #  3) HISTORY_LEVEL > maxid
        #
        if {$HISTORY_LEVEL <= 0} {
            set HISTORY_LEVEL 0 
            if {[info exists CMDLINE_PARTIAL]} {
                set CMDLINE $CMDLINE_PARTIAL
                set CMDLINE_CURSOR [string length $CMDLINE]
            }
            return
        } elseif {$HISTORY_LEVEL > $maxid} {
            set HISTORY_LEVEL $maxid
        } elseif {$HISTORY_LEVEL > $HISTORY_SIZE} {
            set HISTORY_LEVEL $HISTORY_SIZE
        } 
        set id [expr {($maxid + 1) - $HISTORY_LEVEL}]
        set cmd [expr {$id > $maxid ? "" : [history event $id]}]
        set CMDLINE $cmd
        set CMDLINE_CURSOR [string length $cmd]
    }
}

# History handling functions

proc TclReadLine::getHistory {} {
    variable HISTORY_SIZE
    
    set l [list]
    set e [history nextid]
    set i [expr {$e - $HISTORY_SIZE}]
    if {$i <= 0} {
        set i 1
    }
    for { set i } {$i < $e} {incr i} {
        lappend l [history event $i]
    }
    return $l
}

proc TclReadLine::setHistory {hlist} {
    foreach event $hlist {
        history add $event
    }
}

# main()

proc TclReadLine::rawInput {} {
    fconfigure stdin -buffering none -blocking 0
    fconfigure stdout -buffering none -translation crlf
    exec stty raw -echo
}

proc TclReadLine::lineInput {} {
    fconfigure stdin -buffering line -blocking 1
    fconfigure stdout -buffering line
    exec stty -raw echo
}

proc TclReadLine::doExit {{code 0}} {
    variable HISTFILE
    variable HISTORY_SIZE 

    # Reset terminal:
    #print "[ESC]c[ESC]\[2J" nowait
    
    restore ;# restore "info' command -
    lineInput
    
    set hlist [getHistory]
    #
    # Get rid of the TclReadLine::doExit, shouldn't be more than one
    #
    set hlist [lsearch -all -not -inline $hlist "TclReadLine::doExit"]
    set hlistlen [llength $hlist]
    if {$hlistlen > 0} {
        set f [open $HISTFILE w]
        if {$hlistlen > $HISTORY_SIZE} {
            set hlist [lrange $hlist [expr {($hlistlen - $HISTORY_SIZE - 1)}] end]
        }
        foreach x $hlist {
            # Escape newlines:
            puts $f [string map {
                \n "\\n"
                "\\" "\\b"
            } $x]
        }
        close $f
    }
    
    exit $code
}

proc TclReadLine::restore {} {
    lineInput
    rename ::unknown TclReadLine::unknown
    rename ::_unknown ::unknown
}

proc TclReadLine::interact {} {

    rename ::unknown ::_unknown
    rename TclReadLine::unknown ::unknown
    
    #variable RCFILE
    #if {[file exists $RCFILE]} {
        #source $RCFILE
    #}

    # Load history if available:
    # variable HISTORY
    variable HISTFILE
    variable HISTORY_SIZE
    history keep $HISTORY_SIZE
    
    if {[file exists $HISTFILE]} {
        set f [open $HISTFILE r]
        set hlist [list]
        foreach x [split [read $f] "\n"] {
            if {$x != ""} {
                # Undo newline escapes:
                lappend hlist [string map {
                    "\\n" \n
                    "\\\\" "\\"
                    "\\b" "\\"
                } $x]
            }
        }
        setHistory $hlist
        unset hlist
        close $f
    }
    
    rawInput
    
    # This is to restore the environment on exit:
    # Do not unalias this!
    alias exit TclReadLine::doExit
    
    variable ThisScript [info script]
    
    tclline ;# emit the first prompt
    
    fileevent stdin readable TclReadLine::tclline
    variable forever
    vwait TclReadLine::forever
    
    restore
}


proc TclReadLine::check_partial_keyseq {buffer} {
    variable READLINE_LATENCY
    upvar $buffer keybuffer

    #
    # check for a partial esc sequence as tclline expects the whole sequence
    #
    if {[string index $keybuffer 0] == [ESC]} {
        #
        # Give extra time to read partial key sequences
        # 
        set timer  [expr {[clock clicks -milliseconds] + $READLINE_LATENCY}]
        while {[clock clicks -milliseconds] < $timer } {
            append keybuffer [read stdin]
        }
    }
}

proc TclReadLine::addCmdToHistory {cmdline} {
    if { $cmdline == {exit}
        || $cmdline == [history event 0]
        || [string first {history} $cmdline] == 0 } {
        return
    }
    history add $cmdline
}

proc TclReadLine::tclline {} {
    variable COLUMNS
    variable CMDLINE_CURSOR
    variable CMDLINE
    
    set char ""
    set keybuffer [read stdin]
    set COLUMNS [getColumns]
    
    check_partial_keyseq keybuffer
    
    while {$keybuffer != ""} {
        if {[eof stdin]} return
        set char [readbuf keybuffer]
        if {$char == ""} {
            # Sleep for a bit to reduce CPU overhead:
            after 40
            continue
        }
        
        if {[string is print $char]} {
            set x $CMDLINE_CURSOR
            
            if {$x < 1 && [string trim $char] == ""} continue
            
            set trailing [string range $CMDLINE $x end]
            set CMDLINE [string replace $CMDLINE $x end]
            append CMDLINE $char
            append CMDLINE $trailing
            incr CMDLINE_CURSOR
        } elseif {$char == "\t"} {
            handleCompletion
        } elseif {$char == "\n" || $char == "\r"} {
            if {[string index $CMDLINE 0] == {/}} {
                # Search command with given words from the command history
                set searchWord [string range $CMDLINE 1 end]
                if {$searchWord == {}} {
                    setHistorySearchState SWITCH_OFF
                    processHistorySearch {}
                    set CMDLINE {}
                    set CMDLINE_CURSOR 0
                } else {
                    setHistorySearchState SWITCH_ON
                    set CMDLINE [processHistorySearch $searchWord]
                    set CMDLINE_CURSOR [string length $CMDLINE]
                }
            } elseif {$CMDLINE == {}} {
                setHistorySearchState SWITCH_OFF
                processHistorySearch {}
                print "\n" nowait
            } elseif {[info complete $CMDLINE] &&
                [string index $CMDLINE end] != "\\"} {
                lineInput
                print "\n" nowait
                uplevel \#0 {
                    
                    # Handle aliases:
                    set cmdline $TclReadLine::CMDLINE
                    #
                    # Add the cmd line to history before doing any substitutions
                    # 
                    TclReadLine::addCmdToHistory $cmdline
                    set cmd [string trim [regexp -inline {^\s*[^\s]+} $cmdline]]
                    
                    rename ::info ::_info
                    rename TclReadLine::localInfo ::info

                    # Reset HISTORY_LEVEL before next command
                    set TclReadLine::HISTORY_LEVEL 0
                    if {[info exists TclReadLine::CMDLINE_PARTIAL]} {
                        unset TclReadLine::CMDLINE_PARTIAL
                    }

                    # Run the command:
                    set code [catch $cmdline res]
                    rename ::info TclReadLine::localInfo
                    rename ::_info ::info
                    if {$code == 1} {
                        TclReadLine::print "$::errorInfo\n"
                    } else {
                        TclReadLine::print "$res\n"
                    }
                    
                    set TclReadLine::CMDLINE ""
                    set TclReadLine::CMDLINE_CURSOR 0
                    set TclReadLine::CMDLINE_LINES {0 0}
                } ;# end uplevel
                rawInput
            } else {
                set x $CMDLINE_CURSOR
                
                if {$x < 1 && [string trim $char] == ""} continue
                
                set trailing [string range $CMDLINE $x end]
                set CMDLINE [string replace $CMDLINE $x end]
                append CMDLINE $char
                append CMDLINE $trailing
                incr CMDLINE_CURSOR
            }
        } else {
            handleControls
        }
    }
    prompt $CMDLINE
}

# start immediately if invoked as a script:
if {!$::tcl_interactive && [info script] eq $::argv0} {
    TclReadLine::interact
}

# Put the following in your .tclshrc
#if {$::tcl_interactive} {
    ##package require TclReadLine
    #TclReadLine::interact
#}

