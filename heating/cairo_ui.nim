import strutils, system
import cairo
import fbsurface

type
  Point* = tuple [ x, y: int ]

  Renderer* = ref object of RootObj

  cairo_ui* = tuple [
    context: PContext,
    s: Psurface,
    fb: fb_surface
  ]

method name*(this: Renderer): string {.base.} =
  return "Renderer"

method draw*(this: Renderer, ui: cairo_ui) {.base.} =
  quit "draw: $1: to override" % this.name()

method pos*(this: Renderer): Point {.base.} =
  quit "pos: $1: to override" % this.name()

proc create_cairo_ui*(devname: string) : cairo_ui =
  ## Create a cairo context matching the framebuffer

  let fb = create_fb_surface(devname)
  result.fb = fb
  result.s = image_surface_create(cast[Tformat](4), fb.width(), fb.height())
  result.context = create(result.s)
  select_font_face(result.context, "Sans", FONT_SLANT_NORMAL, FONT_WEIGHT_NORMAL)

proc size*(ui: cairo_ui): Point =
  result.x = ui.fb.width
  result.y = ui.fb.height

proc destroy*(ui: cairo_ui) =
  destroy(ui.s)
  destroy(ui.context)
  destroy(ui.fb)

proc clear*(ui: cairo_ui) =
  let cr = ui.context
  cr.set_source_rgb(1, 1, 1)
  paint(cr)

proc draw*(ui: cairo_ui, r: Renderer) =
  let cr = ui.context

  cr.save()
  let p = r.pos()
  cr.translate(float(p.x), float(p.y))
  r.draw(ui)
  cr.restore()

proc blit*(ui: cairo_ui) =
  blit(ui.fb, ui.s.get_data())

proc cr*(ui: cairo_ui) : PContext =
  return ui.context

