
import os
import lists
import system
import times
import parseopt
import heating
import heating_db
import logging
import parsecfg
import strutils
import logging
import net

var current_heating_status = (notified:false, status:RelayState.Unknown)

proc heating_sysfs_file(relay: int) : string =
    assert(relay != 0)
    return "/sys/class/gpio/gpio$1/value" % $relay

proc report_heating_status(db: HeatingDb, status: RelayState) =
    ## Report changes in relay state to the database

    if db.isNil:
      return

    # If we haven't told the database, or the status has changed, then
    # report it
    var notify = false
    if not current_heating_status.notified:
      notify = true
    else:
      if status != current_heating_status.status:
        notify = true

    current_heating_status = (true, status)
    if notify:
      db.update_heating_status(status)
      info($status)

proc relay_on(relay: int, db: HeatingDb) =
    # turn on the C/H relay
    writeFile(heating_sysfs_file(relay), "1")
    report_heating_status(db, On)
    
proc relay_off(relay: int, db: HeatingDb) =
    writeFile(heating_sysfs_file(relay), "0")
    report_heating_status(db, Off)

# Turn off all the relays if we quit
var cleanup_relays = newSeq[int](2)
proc cleanup() {.noconv.} =
    # can't update the database here - we're probably exiting because
    # of a network error
    for i in cleanup_relays:
        if i != 0:
            relay_off(i, nil)

proc on_relay_command(line: string, heating_relay: int, db: HeatingDb) =
    if line == "":
        error "closed connection from far end"
        quit()

    if line == "heating On":
        relay_on(heating_relay, db)
    elif line == "heating Off":
        relay_off(heating_relay, db)
    else:
        info("invalid command: " & substr(line, 0, 32))

proc onoff_controller(heating_relay: int) =
    discard """ Open a socket and wait for commands from the heating
        controller.

        If anything goes wrong, exit and allow init to restart
        the process.
    """

    info("starting")
    let db = heatingdb_open("heating")
    relay_off(heating_relay, db)
    cleanup_relays.add(heating_relay)
    addQuitProc(cleanup)
    let verbose = false

    # FIXME: use SSL
    var notify_socket = newSocket()
    try:
        notify_socket.connect("heating", Port(8001))
    except:
        error("could not connect to heating server: $1" % getCurrentExceptionMsg(), delay=5000)

    while true:
        try:
            var line: TaintedString = ""
            notify_socket.send("notify\r\n")

            # get initial status
            notify_socket.readLine(line, timeout=1000, maxLength=80)
            on_relay_command(line, heating_relay, db)

            # wait for an update
            notify_socket.readLine(line, timeout=60*1000, maxLength=80)
            on_relay_command(line, heating_relay, db)

        except TimeoutError:
            info("controller: relay status: " & $current_heating_status.status)

        except:
            # shut down and wait to be restarted
            relay_off(heating_relay, nil)
            error("network error: $1" % getCurrentExceptionMsg(), delay=5000)

proc parseCmdLine() =

    let Usage = """
        -h | --help             Give this help
    """

    var p = initOptParser()
    while true:
        next(p)
        var kind = p.kind
        var key = p.key

        case kind
        of cmdArgument:
            stdout.write("unexpected option\n")
            quit(Usage)

        of cmdLongoption, cmdShortOption:
            case key.string
            of "help", "h":
                stdout.write(Usage)
                quit(0)
            else:
                quit(Usage)

        of cmdEnd:
            break

proc parseHeatingRelay() : int =
    var dict = loadConfig("/opt/heating/heating.cfg")
    let v = dict.getSectionValue("Controller", "boiler-relay")
    if v == "":
        error("heating.cfg: Controller.boiler-relay not found")

    try:
        result = parseInt(v)
    except:
        echo "error parsing Controller.boiler-relay: " & getCurrentExceptionMsg()

    if result <= 1 or result >= 27:
        error("C/H relay GPIO number $1 invalid: giving up" % $result)

parseCmdLine()
let heating_relay = parseHeatingRelay()

assert(heating_relay != 0)

onoff_controller(heating_relay=heating_relay)
