import strutils
import cairo
import cairo_ui

type

  Widget* = ref object of Renderer
    x: int
    y: int

method name(this: Widget): string = "widget"
method pos(this: Widget): Point =
  return (this.x, this.y)

method size*(this: Widget) : Point {.base.} =
  echo "size: to override: " & this.name()

method init*(this: Widget) {.base.} =
  this.x = 0
  this.y = 0

proc in_range(pos, lower, upper: int): bool =
  return pos >= lower and pos < upper

proc contains*(this: Widget, pos:Point): bool =
  let size = this.size()
  return inRange(pos.x, this.x, this.x + size.x) and
         inRange(pos.y, this.y, this.y + size.y)

method move*(this: Widget, x, y: int): Widget {.base.} =
  this.x = x
  this.y = y
  return this

method onPress*(w: Widget, pos: Point) {.base.} =
  discard

method onRelease*(w: Widget, pos: Point) {.base.} =
  discard


