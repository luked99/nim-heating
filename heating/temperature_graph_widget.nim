import cairo
import cairo_ui
import heating_db
import strutils
import widget
import heating_config
import times

let width = 200
let height = 150
let MaxValidTemp = 40.0

type ColourTemperature = tuple [temp, r, g, b: float]
type ColourTemperatures = array[7, ColourTemperature]
let colour_temps: ColourTemperatures = [
  (0.0, 0.0, 0.0, 1.0),
  (15.0, 0.3, 0.0, 1.0),
  (18.0, 0.5, 0.0, 1.0),
  (20.0, 0.9, 0.3, 0.7),
  (21.0, 0.9, 0.3, 0.6),
  (22.0, 0.9, 0.5, 0.5),
  (25.0, 1.0, 0.5, 0.3)
]

proc pick_colour(temperature: float) : ColourTemperature =
  result = colour_temps[0]
  for ct in colour_temps:
    if temperature >= ct.temp:
      result = ct

type TemperatureGraphWidget = ref object of Widget
  dba: HeatingDb
  cfg: ConfigData

proc create_temperature_graph_widget*(dba: HeatingDb, cfg: ConfigData) : TemperatureGraphWidget =
  result = TemperatureGraphWidget(dba:dba, cfg:cfg)
  result.init()

method size(this: TemperatureGraphWidget): Point =
  result = (width, height)

method name(this: TemperatureGraphWidget): string =
  return "TemperatureGraph"

method draw(this: TemperatureGraphWidget, ui: cairo_ui) =
  let cr = ui.cr
  select_font_face(cr, "Sans", FONT_SLANT_NORMAL, FONT_WEIGHT_NORMAL)
  set_font_size(cr, 20.0)
  set_line_width(cr, 1)

  let period = 24*3600

  let now = getLocalTime(getTime())
  let p = initInterval(days=int(period/(3600*24)))
  let start = now - p

  const y_margin = 2    # degrees C
  let temperatures = temperatures(this.dba, period)
  var hourlies = newSeq[tuple[count:int, total:float, hour:int]](24)  # average temperature per hour

  let (low_threshold, high_threshold) = this.dba.thresholds()
  var min = low_threshold
  var max = -1000.0
  var count = 0

  for t in temperatures:
    if t.time < toTime(start):
      continue

    inc(count)
    let temp = t.temperature
    if temp > MaxValidTemp:
      continue

    if temp < min:
      min = temp
    if temp > max:
      max = temp

    let time_info = getGMTime(t.time)

    # hour relative to now (so now-24 = 0, now-23 = 1, etc
    let h = int(int(time_info.toTime() - start.toTime())/3600)

    if h >= 24:
      # we started looping just before the hour ticked over (?)
      continue

    inc(hourlies[h].count)
    hourlies[h].total = hourlies[h].total + temp
    hourlies[h].hour = time_info.hour

  let delta = max - min
  
  let xbase = 20
  let ybase = 10

  translate(cr, float(xbase), float(ybase))

  cr.save()

  let columns = hourlies.len
  let yrange = float(height)/float(delta+y_margin)
  cr.scale(1.0, -1.0)
  cr.translate(0.0, float(-height))
  cr.set_source_rgb(0.0,0.0,1.0)
  cr.rectangle(0.0,0.0,float(width),float(height))
  cr.stroke()

  cr.scale(float(width)/float(columns), yrange)

  cr.set_source_rgb(0.8, 0.8, 0.8)
  cr.rectangle(0.0, 0.0, float(columns), delta+y_margin)
  cr.fill()
  cr.stroke()

  var index = -1
  set_line_width(cr, 1.0)
  for h in hourlies:
    inc(index)
    if h.count == 0:
      continue

    let mean_temp = h.total / float(h.count)
    let ct = pick_colour(mean_temp)
    cr.set_source_rgb(ct.r, ct.g, ct.b)

    cr.move_to(float(index)+0.5, 0.0)
    cr.line_to(float(index)+0.5, mean_temp-min)
    cr.stroke()

  # grid

  cr.set_source_rgb(0.3, 0.3, 0.3)
  cr.set_line_width(yrange/float(3*height))

  cr.move_to(0.0, low_threshold-min)
  cr.line_to(float(columns), low_threshold - min)
  cr.stroke()

  cr.move_to(0.0, high_threshold-min)
  cr.line_to(float(columns), high_threshold-min)
  cr.stroke()

  cr.restore()

  # labels

  cr.set_font_size(10)
  cr.set_source_rgb(0, 0, 0)

  # x-axis
  cr.move_to(0.0, float(height+20))
  cr.show_text($start.hour)

  cr.move_to(float(width), float(height+20))
  cr.show_text($now.hour)

  cr.move_to(float(width/2), float(height+20))
  let mid_hour = start + initInterval(hours=int(period/(2*3600)))
  cr.show_text($mid_hour.hour)

  # y-axis
  cr.move_to(-20.0, float(height))
  cr.show_text($int(min))

  cr.move_to(-20.0, 0.0)
  let top = int(max)+y_margin
  cr.show_text($top)
