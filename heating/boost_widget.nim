import cairo
import cairo_ui
import strutils
import widget
import heating_db
import times, math

let width = 50.0
let height = 50.0
let radius = width/2.0 - 5.0

type BoostWidget = ref object of Widget
  dba: HeatingDb

proc create_boost_widget*(dba: HeatingDb not nil) : BoostWidget =
  result = BoostWidget(dba:dba)
  result.init()

method size(this: BoostWidget): Point =
  return (int(width), int(height))

method name(this: BoostWidget): string =
  return "Boost"

method draw(this: BoostWidget, ui: cairo_ui) =
  let cr = ui.cr

  let boosted = this.dba.is_boosted()
  let status = this.dba.controller_status()

  if status.heating:
    cr.set_source_rgb(1.0, 0, 0)
  else:
    cr.set_source_rgb(0.6, 0, 0.4)

  cr.move_to(width/2.0, height/2.0)
  cr.arc(width/2.0, height/2.0, radius, 0.0, 2.0*PI)
  cr.fill()
  cr.stroke()

method onRelease*(w: BoostWidget, pos: Point) =
  if not w.dba.is_boosted():
    w.dba.boost_heating()
    echo "Boosted"


