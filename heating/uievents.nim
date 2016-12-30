import posix, strutils, os, selectors
import libevdev, linux/input
import cairo_ui

## Read and report mouse (touchscreen) events

type

  EventHandler* = tuple [
    onPress: proc(pos: Point): void,
    onRelease: proc(pos: Point): void
  ]

  UIEv* = ref object of RootObj
    dev: int
    selector: Selector
    evdev: ptr libevdev

    # x and y touch screen dimensions
    x_abs: ptr input_absinfo
    y_abs: ptr input_absinfo

    # display size (pixels)
    width, height: int

  UIError = object of Exception

  UIHardwareError = object of UIError

proc ui_init*(): UIEv =
  discard """Find the first input device which looks like a mouse, and return it
             and the associated file descriptor.
          """
  var fd: cint = -1
  var found = false
  var evdev: ptr libevdev
  for device in walkPattern("/dev/input/event*"):
    fd = open(device, O_RDONLY or O_NONBLOCK)
    if fd < 0:
      raiseOSError(OSErrorCode(errno), "could not open $1" % device)

    let ret = libevdev_new_from_fd(fd, addr evdev)
    if ret < 0:
      raiseOSError(OSErrorCode(errno), "could not create libevdev device for $1" % device)

    if libevdev_has_event_type(evdev, EV_ABS):
        # looks like a touchscreen
        found = true
        break
    discard close(fd)

  if not found:
    raise newException(UIHardwareError, "no mice found")

  var sel = newSelector()
  result = UIEv(dev: fd, selector: sel, evdev: evdev)
  result.selector.register(SocketHandle(fd), {EvRead, EvError}, result)

  # get touchscreen dimensions

  result.x_abs = libevdev_get_abs_info(evdev, ABS_X)
  result.y_abs = libevdev_get_abs_info(evdev, ABS_Y)

  echo "touchscreen: $1,$2 -> $3,$4" % [
    $result.x_abs.minimum, $result.y_abs.minimum,
    $result.x_abs.maximum, $result.y_abs.maximum
    ]

proc set_size*(ui: UIEv, rh: Point) =
  ## Set the LCD screen size, so that touchscreen events can be scaled to this
  ui.width = rh.x
  ui.height = rh.y
  echo "ui size is $1, $2" % [$rh.x, $rh.y]

proc scale(touchscreen_pos, display_size: int, touchscreen_size: ptr input_absinfo): int =
  let touchscreen_width = touchscreen_size.maximum - touchscreen_size.minimum
  let scaled = float(touchscreen_pos - touchscreen_size.minimum)/float(touchscreen_width)
  return int(scaled * float(display_size))

proc scale(ui: UIEv, pos: Point) : Point =
  ## scale a touchscreen co-ordinate to a screen co-ordiante

  # x and y are swapped
  let newpos : Point = (pos.y, pos.x)

  result.x = scale(newpos.x, ui.width, ui.x_abs)
  result.y = scale(newpos.y, ui.height, ui.y_abs)
  # y is flipped
  result.y = ui.height - result.y


proc wait_event*(ui: UIEv, timeout: int, event_handler: EventHandler) =
  let ready = ui.selector.select(timeout)
  for r in ready:
    if r.key.fd == SocketHandle(ui.dev):
      var pos: Point = (0,0)
      var lastpos: Point = (0,0)
      while true:
        var ev: input_event
        let rc = libevdev_next_event(ui.evdev, cuint(LIBEVDEV_READ_FLAG_NORMAL), addr ev)
        if rc == cint(LIBEVDEV_READ_STATUS_SUCCESS):
          # echo "type=$1, code=$2" % [$ev.ev_type, $ev.code]
          case ev.ev_type
          of EV_SYN:
            lastpos = pos
            pos.x = -1
            pos.y = -1
          of EV_KEY:
            discard
          of EV_ABS:
            case ev.code
            of ABS_X:
              pos.x = ev.value
            of ABS_Y:
              pos.y = ev.value
            of ABS_PRESSURE:
              let pressure = ev.value
              if int(pressure) != 0:
                event_handler.onPress(scale(ui, pos))
              else:
                event_handler.onRelease(scale(ui, lastpos))
            else:
              discard
          else:
            discard

        else:
          break

proc main() =
  let uiev = ui_init()
  proc tstPress(pos: Point) : void {.closure.} =
    echo "($1,$2)" % [$pos.x, $pos.y]

  proc tstRelease(pos: Point): void {.closure.} =
    echo "release: ($1,$2)" % [$pos.x, $pos.y]

  let eventHandlers: EventHandler = (onPress: tstPress, onRelease: tstRelease)
  while true:
    waitEvent(uiev, 1000, eventHandlers)
