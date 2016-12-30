import cairo
import cairo_ui
import heating_db
import strutils
import widget
import heating_config

let font_height = 40.0
let margin = 5.0

type TemperatureWidget = ref object of Widget
  dba: HeatingDb not nil
  cfg: ConfigData

proc create_temperature_widget*(
  dba: HeatingDb not nil,
  cfg: ConfigData) : TemperatureWidget =
  result = TemperatureWidget(dba:dba, cfg:cfg)
  result.init()

method name(this: TemperatureWidget): string = "Temperature"

method size(this: TemperatureWidget): Point =
  result = (70, int(font_height + margin))  # fixme: use font metrics

method draw(this: TemperatureWidget, ui: cairo_ui) =
  assert(this.dba != nil)

  let cr = ui.cr

  select_font_face(cr, "Sans", FONT_SLANT_NORMAL, FONT_WEIGHT_NORMAL)
  set_font_size(cr, font_height)
  move_to(cr, 10.0, font_height + margin)

  let (low_threshold, high_threshold) = this.dba.thresholds()
  let r = this.dba.current_temperature()
  if r.ok:
    let s = r.temperature.format_biggest_float(ffDecimal, precision=1) & " C"
    if r.temperature <= low_threshold:
      cr.set_source_rgb(0.5, 0.5, 1)
    else:
      cr.set_source_rgb(0, 0, 0)

    cr.show_text(s)
  else:
    cr.set_source_rgb(1, 0, 0)
    cr.show_text("sensor failure")
