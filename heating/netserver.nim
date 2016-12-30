import asyncnet, asyncdispatch
import strutils, sequtils

type HeatingClient = tuple [ socket: AsyncSocket, notify: bool, new_client: bool ]

type StatusReporter = proc(): string

type Handlers* = tuple [
  status_reporter: StatusReporter,                ## how to report current status
  relay_status: StatusReporter,                   ## current relay status
  boost_handler: StatusReporter,                  ## Boost the heating for an hour
]

var clients {.threadvar.}: seq[ref HeatingClient]

var helptext {.threadvar.} : string

helptext = """
help          - give this help
quit          - quit
status        - current status
wakeup <arg>  - wakeup all clients with <arg>
notify        - wait for wakeup
boost         - boost the heating
restart       - restart the server
"""

proc remove_client(socket: AsyncSocket) =
  clients = filter(clients, proc(c: ref HeatingClient): bool = c.socket != socket)

proc notify_clients*(msg: string) =
  for i in countup(0, clients.high):
    var ci = clients[i]
    if ci.notify:
      asyncCheck ci.socket.send(msg)
      ci.notify = false

proc notify_async(msg: string) {.async.} =
  for i in countup(0, clients.high):
    var ci = clients[i]
    if ci.notify:
      await ci.socket.send(msg)
      ci.notify = false

proc processClient(socket: AsyncSocket, handlers: Handlers) {.async.} =
  var c: ref HeatingClient
  var found = false
  for i in clients:
    if i.socket == socket:
      found = true
      c = i
      break

  if not found:
    return

  var socket = c.socket

  while true:
    let line = await socket.recvLine()
    if line.len == 0: break
    let words = line.splitWhitespace()
    if words.len == 0: break
    let command = words[0]
    case command
    of "help":
      await socket.send(helptext & "\r\n")

    of "notify":
      c.notify = true
      await socket.send(handlers.relay_status() & "\r\n")

    of "quit":
      await socket.send("bye\r\n")
      break

    of "status":
      let status: string = handlers.status_reporter()
      #let status: string = "foo"
      await socket.send(status & "\r\n")

    of "boost":
      let status: string = handlers.boost_handler()
      await socket.send(status & "\r\n")

    of "wakeup":
      echo "waking up clients"
      let msg = line[7 .. line.high] & "\r\n"
      asyncCheck notify_async(msg)

    of "restart":
      quit()

    else:
      await socket.send("unknown command\r\n")

  remove_client(socket)
  socket.close()
        
proc serve(handlers: Handlers) {.async.} =
  clients = @[]
  var server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(Port(8001))
  server.listen()
  
  while true:
    let socket = await server.accept()
    var client: ref HeatingClient
    new(client)
    client.socket = socket
    client.notify = false
    client.new_client = true
    clients.add(client)
    
    asyncCheck processClient(client.socket, handlers)

proc server_init*(handlers: Handlers) =
  asyncCheck serve(handlers)

proc server_serve*(timeout: int) =
  poll(timeout)
