import cairo
import cairo_ui
import strutils
import widget
import times

type TimeWidget = ref object of Widget

proc create_time_widget*() : TimeWidget =
  result = TimeWidget()
  result.init()

method size(this: TimeWidget): Point =
  return (50, 30)           # FIXME; use font metrics

method name(this: TimeWidget): string =
  return "Time"

method draw(this: TimeWidget, ui: cairo_ui) =
  let cr = ui.cr

  set_font_size(cr, 20.0)
  move_to(cr, 10.0, 25.0)   # internal margin, height-of-text

  let tstr = getClockStr()
  cr.set_source_rgb(0, 0, 0)
  cr.show_text(tstr)
