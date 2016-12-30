import cairo
import cairo_ui
import heating_db
import strutils
import widget
import heating_config
import times

let rows = 4
let font_height = 15.0

type StatusWidget = ref object of Widget
  dba: HeatingDb
  cfg: ConfigData
  period: int

proc create_status_widget*(dba: HeatingDb, cfg: ConfigData) : StatusWidget =
  result = StatusWidget(dba:dba, cfg:cfg)
  result.init()
  result.period = 24*3600

proc draw_label(cr: PContext, y: float, label: string) : float =
  cr.move_to(0.0, y)
  cr.show_text(label)
  return y + font_height

proc draw_value(cr: PContext, y: float, label: string, value: string, unit: string) : float =
  cr.move_to(0.0, y)
  cr.show_text(label&":")
  cr.move_to(40.0, y)
  cr.show_text(value & unit)

  return y + font_height

method size(this: StatusWidget): Point =
  return (80, int(font_height) * rows)

proc draw_value(cr: PContext, y: float, label: string, value: float, unit: string) : float =
  return draw_value(cr, y, label, formatBiggestFloat(value, ffDecimal, 1), unit)

method name(this: StatusWidget): string =
  return "Status"

proc boolToToggle(b: bool) : string =
  if b: return "On"
  else: return "Off"

method draw(this: StatusWidget, ui: cairo_ui) =
  let cr = ui.cr
  select_font_face(cr, "Sans", FONT_SLANT_NORMAL, FONT_WEIGHT_NORMAL)
  cr.set_source_rgb(0.0,0.0,0.0)
  set_font_size(cr, font_height)
  var y = font_height

  # time of day
  y = cr.draw_label(y, getClockStr())

  # min/max
  let max = this.dba.max(this.period)
  let min = this.dba.min(this.period)

  y = cr.draw_value(y, "Max", max, "C")
  y = cr.draw_value(y, "Min", min, "C")

  # status
  let status = this.dba.controller_status()

  let show_heat = false
  if show_heat:
    var str = "Off"
    if status.heating:
      cr.set_source_rgb(1.0,0.0,0.0)
      str = "On"
    y = cr.draw_value(y, "Heat", str, "")
  
  let localtime = getLocalTime(getTime())
  let scheduled = this.dba.is_heating_scheduled(localtime)

  cr.set_source_rgb(0.0,0.0,0.0)
  y = cr.draw_label(y, "Sched: $1" % boolToToggle(scheduled))

  let boosted = this.dba.is_boosted()
  y = cr.draw_label(y, "Boost: $1" % boolToToggle(boosted))

  let auto_boosted = this.dba.is_auto_boosted()
  y = cr.draw_label(y, "Auto: $1" % boolToToggle(auto_boosted))

