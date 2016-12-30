import syslog
import heating_config
import os

syslog.openlog(ident="heating", facility=syslog.logDaemon)

proc info*(str: string) =
    echo "heating: " & str
    if config.syslog:
        syslog.info(str)

proc error*(str: string, delay=0) =
    echo "heating: " & str
    if config.syslog:
        syslog.error(str)

    sleep(delay)
    quit(1)

