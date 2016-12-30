
import os, system, strutils, times
import cairo_ui
import heating_db
import fbsurface
import heating_config
import widget
import temperature_widget
import time_widget
import temperature_graph_widget
import status_widget
import boost_widget
import main_window
import uievents

proc main() =

  let uiev = uiInit()

  let cairo_ui = create_cairo_ui("/dev/fb1")
  uiev.setSize(cairo_ui.size())
  let db_access = heatingdb_open()
  assert(db_access != nil)

  let toplevel = create_mainwindow()

  toplevel.add create_temperature_widget(db_access, config)
  toplevel.add create_temperature_graph_widget(db_access, config).move(0, 50)
  toplevel.add create_status_widget(db_access, config).move(230, 0)
  toplevel.add create_boost_widget(db_access).move(230, 160)

  proc onHeatingPress(pos: Point) =
    toplevel.onPress(pos)

  proc onHeatingRelease(pos: Point) =
    toplevel.onRelease(pos)
  
  let eventHandlers: EventHandler = (onHeatingPress, onHeatingRelease)

  while true:
    
    cairo_ui.clear()
    cairo_ui.draw(toplevel)
    cairo_ui.blit()

    waitEvent(uiev, 1000, eventHandlers)

  destroy(cairo_ui)

main()
