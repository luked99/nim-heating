
import sequtils, system
import widget
import uievents
import widget, cairo_ui

type MainWindow* = ref object of Widget
  widgets: seq[Widget]

proc create_mainwindow*() : MainWindow =
  result = MainWindow()
  result.init()
  result.widgets = newSeq[Widget](0)

proc add*(this: MainWindow, w: Widget) =
  this.widgets.add(w)
  echo "added " & w.name()

method name(this: Widget): string = "MainWindow"

method onPress*(this: MainWindow, pos: Point) =
  for w in this.widgets:
    if w.contains(pos):
      w.onPress(pos)

method onRelease(this: MainWindow, pos: Point) =
  for w in this.widgets:
    if w.contains(pos):
      w.onRelease(pos)

method draw(this: MainWindow, ui: cairo_ui) =
  echo "begin draw"
  for w in this.widgets:
    ui.draw(w)
    echo w.name
  echo "done"

method pos(this: MAinWindow): Point =
  return (0,0)
