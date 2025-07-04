# RCS: @(#) $Id: Play.tcl,v 1.9 2004/06/18 09:15:28 barras Exp $

# Copyright (C) 1998-2000, DGA - part of the Transcriber program
# distributed under the GNU General Public License (see COPYING file)


#################################################################

# Play current video or audio file
#   begin/end : segment to play (in seconds); defaults to all signal
#   script :    callback after non-interrupted playback

proc PlayRange {{begin 0} {end 0} {script {}}} {
   global v

   PauseAudio

   if {$v(videoFile) != ""} {
      set scale [lindex [$v(qtvideo) gettime] 5]
      $v(qtvideo) time [expr int($begin*$scale)]
      $v(qtvideo) callback [expr int($end*$scale)] StopVideo
      $v(qtvideo) play
      CursorStart $begin $end
      IsPlaying 1
      # Callback after playback
      set v(play,after) $script
      return
   }

   set wavename $v(sig,name)
   if {$wavename == ""} return

   if {$v(playbackRemote)} {
     if {[info commands rplayer] != "" && [rplayer cget -file] != $wavename} {
       rplayer destroy
     }
     if {[info commands rplayer] == ""} {
       OpenSound $wavename 1
     }
   } elseif {[info commands player] == ""} {
     snack::sound player
     if {[info commands snack::filter] != "" && ![info exists v(sig,filter)]} {
       set v(sig,filter) [snack::filter map]
     }
   }
   if {$v(playbackRemote)} {
     set rate [$v(sig,cmd) cget -frequency]
     rplayer play -start [expr int($begin*$rate)] -end [expr int($end*$rate)]
   } elseif {$v(sig,remote)} {
      set snd [OpenSound $wavename]
      set rate [$snd cget -frequency]
      set chan [$snd dump -start [expr int($begin*$rate)] -end [expr int($end*$rate)] -byteorder $::tcl_platform(byteOrder)]
      player conf -channel $chan
      player play -command [list close $chan]
   } else {
      # if possible, keep previously open sound file
      if {[player cget -file] != $wavename} {
	 player conf -file $wavename -channels $v(sig,channels) -frequency $v(sig,rate) -skiphead $v(sig,header) -guessproperties 1
      }
      # Apply multiplying factor to frequency - does not work with current
      # snack version.
      #player conf -frequency [expr int([$v(sig,cmd) cget -frequency]*$v(playbackSpeed))]
      set rate [$v(sig,cmd) cget -frequency]
      if {[$v(sig,cmd) cget -channels] == 2 && [info exists v(sig,filter)]} {
	eval $v(sig,filter) configure $v(sig,map)
	player play -start [expr int($begin*$rate)] -end [expr int($end*$rate)] -filter $v(sig,filter)
      } else {
	player play -start [expr int($begin*$rate)] -end [expr int($end*$rate)]
      }
   }
   
   # Callback after playback
   set v(play,after) $script

   IsPlaying 1
   CursorStart $begin $end
}

# Stop current play and freeze cursor
proc PauseAudio {} {
   global v
   if {$v(videoFile) != ""} {
     $v(qtvideo) stop
     foreach cb [$v(qtvideo) callback info] {
        $v(qtvideo) callback cancel $cb
     }
   }
   if {[info commands player] != ""} {
      catch {close [player conf -channel]}
      player stop
   }
   if {[info commands rplayer] != ""} {
     if {[catch {rplayer stop}]} {
       catch {rplayer destroy}
     }
   }
   catch {beeper stop}
   CursorStop
   IsPlaying 0
   after cancel Play
}

#################################################################
# Automatic cursor management

# called from: PlayRange
proc CursorStart {pos max} {
   global v

   set v(curs,pos) $pos
   set v(curs,start) $pos
   set v(curs,max) $max
   # Ask for cursor events every 20 ms
   CursorEvent 20
   # Permit fast forward/backward
   catch {unset v(play,no-fast)}
}

# called from: PauseAudio
proc CursorStop {} {
   global v

   if {[info exists v(curs,event)]} {
      after cancel $v(curs,event)
      unset v(curs,event)
   }
}

# Update cursor position in waveform widget
proc CursorEvent {inc} {
   global v

   if {$v(videoFile) != ""} {
     set scale [lindex [$v(qtvideo) gettime] 5]
     set pos [expr [lindex [$v(qtvideo) gettime] 1]/double($scale)]
     set active [expr {[$v(qtvideo) rate] != 0}]
   } else {		
     if {$v(playbackRemote) && [info commands rplayer] != ""} {
       set audio rplayer
     } else {
       set audio audio
     }
     set pos [expr $v(curs,start)+[$audio elapsedTime]*$v(playbackSpeed)]
     set active [$audio active]
   } 
   if {$pos>$v(curs,max) || !$active} {
      PauseAudio
      # Command to be launched after signal playback (rewind by default)
      eval $v(play,after)
      return
   }
   foreach win $v(wavfm,list) {
      set margin [expr 0.05 * $v($win,size)]
      if {($pos<$v($win,left))||
	  ($pos>$v($win,right)-$margin && $v(curs,max)>$v($win,right))} {
	 set v($win,left) [expr $pos-$margin]
	 SynchroWidgets $win
      }
   }
   SetCursor $pos
   if {[info exists v(socket,client)]} {
     TransClient SetCursor $pos
   }
   set v(curs,event) [after $inc [list CursorEvent $inc]]
}

#################################################################

# Stop playing and reset cursor to beginning of selection or file
proc StopAndRewind {} {
   global v

   catch {unset v(playbackSegmt)}
   PauseAudio
   if [GetSelection beg end] {
      SetCursor $beg hide
   } else {
      SetCursor $v(sig,min) hide
   }
}

# Start new play at cursor pos in current playback mode
proc Play {} {
   global v

   # Default behaviour: start from current position ($pos) up to
   # end of selection or end of signal ($end), then rewind to
   # start of selection or elso to current position ($script)
   set pos [GetCursor]
   set sel [GetSelection beg end]
   if {($pos<$beg) || ($pos>=$end)} {
      set pos $beg
   }
   if {$sel} {
      set script "SetCursor $beg"
   } else {
      DisplayMessage ""
      set script "SetCursor $pos"
   }
   # Detect current playback mode: continuous/pause/beep/stop/loop/segmt
   set mode $v(playbackMode)
   if {[info exists v(playbackSegmt)]} {
      set mode "segmt"
   }
   set scriptPause "IsPlaying 1; after [expr int(1000*$v(playbackPause))] Play"
   if {$mode != "continuous" && [info exists v(segmt,curr)]} {
      set n $v(segmt,curr)
      set begSeg [GetSegmtField seg0 $n -begin]
      set endSeg [GetSegmtField seg0 $n -end]
      incr n
      if {$mode == "segmt"} {
	 set pos $begSeg
	 set end $endSeg
	 SetSelection $pos $pos
	 set script "SetCursor $pos"
      } elseif {$mode == "loop" && !$sel} {
	 set end $endSeg
	 set script "SetCursor $begSeg"
      } elseif {$endSeg < $end && $n < [GetSegmtNb seg0]} {
	 set scriptStop "SetCursor $endSeg; SetCurrentSegment $n"
	 if {$mode=="beep" && [file readable $v(playbackBeep)]} {
	    set end $endSeg
	    set script "$scriptStop; PlayBeep"
	 } elseif {$mode=="pause" && $v(playbackPause)>0} {
	    set end $endSeg
	    set script "$scriptStop; $scriptPause"
	 } elseif {$mode=="stop"} {
	    set end $endSeg
	    set script $scriptStop
	 } elseif {$mode=="next"} {
 	    set end [expr $endSeg-0.001]
	    while {$end <= $pos + 0.1 && $n < [GetSegmtNb seg0]} {
	      set end [expr [GetSegmtField seg0 $n -end]-0.001]
	      incr n
	    }
	    set script "SetCursor $end"
	 }
      }
   }
   # loop on current selection or segment after a pause
   if {$mode == "loop"} {
      append script "; $scriptPause"
   } else {
      append script "; catch {unset v(playbackSegmt)}"
   }
   PlayRange $pos $end $script
}

proc PlayBeep {} {
   global v

   catch {snack::sound beeper}
   beeper conf -file $v(playbackBeep)
   beeper play -command "IsPlaying 0; after 0 Play"
   IsPlaying 1
}

proc IsPlaying {{state {}}} {
   global v

   if {$state != ""} {
      if {$state} {
	 $v(tk,play) config -state disabled
	 $v(tk,stop) config -state normal
      } else {
         $v(tk,play) config -state normal
	 $v(tk,stop) config -state disabled
      }
      #update
      set v(play,state) $state
   } else {
      if ![info exists v(play,state)] {
	 set v(play,state) 0
      }
      return $v(play,state)
   }
}

#################################################################

# Stop current play, keeping current pos
# or restart play at previous pos
proc PlayOrPause {} {
   global v

   catch {unset v(playbackSegmt)}
   if {[IsPlaying]} {
      PauseAudio
   } else {
      # Start back playback from requested duration
      SetCursor [expr [GetCursor] - $v(playbackBefore)]
      Play
   } 
}

proc PlayBut {} {
  global v

  if {[info exists v(play,state)]} {
    if {$v(play,state) == 0} {
      if {[info exists v(curs,event)]} {
	PauseAudio
      } else {
	Play
      }
    }
    update
  }
}

proc PauseBut {} {
  global v
  
  if {[info exists v(play,state)]} {
    if {$v(play,state) == 1} {
      if {[info exists v(curs,event)]} {
	PauseAudio
      } else {
	Play
      }
    }
  }
}

proc PlayFromBegin {} {
   global v

   StopAndRewind
   Play
}

proc PlayCurrentSegmt {} {
   global v

   set v(playbackSegmt) 1
   Play
}

proc PlayNextSegmt {} {
   global v

   TextNextSync +1
   set v(playbackSegmt) 1
   Play
}

#################################################################
# Play a little part of signal before and after cursor position

proc PlayAround {{len 1.0}} {
   global v

   set pos [GetCursor]
   SetCursor [expr $pos-$len]; set left [GetCursor]
   SetSelection $left $pos
   PlayRange $left $pos "after [expr int(1000*$v(playbackPause))] PlayAround2 $len $pos"
}

proc PlayAround2 {len pos} {
   global v

   SetCursor [expr $pos+$len]; set right [GetCursor]
   SetSelection $pos $right
   PlayRange $pos $right "SetSelection $pos $pos"
}

#################################################################
# Fast forward/backward (depending on direction)
# move with 1/2s step and restart playing
proc PlayForward {dir} {
   global v

   set play [IsPlaying]
   if $play {
      if [info exists v(play,no-fast)] return
      set v(play,no-fast) 1
   }

   set pos [expr [GetCursor]+$dir*0.5]
   SetCursor $pos
   #ViewSelection $pos $pos
   if $play Play
}

# Fwd/bwd from button press with auto-repeat
proc BeginPlayForward {dir} {
   global v

   catch {after cancel $v(curs,fast)}
   set v(curs,fast) [after 200 [list BeginPlayForward $dir]]
   PlayForward $dir
}

# button release : unregister event
proc EndPlayForward {} {
   global v

   catch {after cancel $v(curs,fast)}
}

#################################################################
# Video management using QuickTimeTcl
proc OpenVideoFile {{file ""}} {
   global v

   if {[info commands movie] == ""} {
     tk_messageBox -type ok -icon error -message [Local "Sorry, QuickTime Video support not available in this configuration (currently available for Mac OS X)"]
     return
   }
   if {$file == ""} {
      set file [tk_getOpenFile -filetypes {{"Video files" {".mov" ".mpg" ".avi"}} {"All files"   {*}}} -title "Open video file"]
      #set file [tk_getOpenFilePreview]
   }
   if {$file != ""} {
      if {![quicktimetcl::canopen $file -type movie]} {
	tk_messageBox -type ok -icon error -message [format [Local "File %s does not seem to be supported by QuickTime"] $file]
	return
      }
      set v(videoFile) $file
      if {![info exists v(qtvideo)]} {
         set v(qtvideo) [movie .snd.qt -file $v(videoFile) -controller 0]
	 pack .snd.qt -side left
	 pack .snd.1 -side right -expand true
      }
      if {[$v(qtvideo) cget -file] != $v(videoFile)} {
	 $v(qtvideo) configure -file $v(videoFile)
      }
      foreach {w h} [$v(qtvideo) size] break
      if {$h > 400} {
	 $v(qtvideo) configure -width [expr int($w/2)] -height [expr int($h/2)]
      } else {
	 $v(qtvideo) configure -width 0 -height 0
      }
   }
}

proc EmptyVideo {} {
    global v
    
    if {[info exists v(qtvideo)]} {
	destroy $v(qtvideo)
	unset v(qtvideo)
    }
    set v(videoFile) ""
}
    
proc ViewVideo {time} {
   global v
   if {$v(videoFile) != "" && [$v(qtvideo) rate] == 0.0} {
      set scale [lindex [$v(qtvideo) gettime] 5]
      $v(qtvideo) time [expr int($time*$scale)]
   }
}

proc StopVideo {name video time} {
  $video stop
}
