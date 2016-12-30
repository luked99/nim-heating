#!/bin/sh

# FIXME: get the program to automatically restart with the new version
set -e
INSTALL=/opt/heating
OPTS="--cpu:arm --os:linux -d:useuClibc --threads:on"

TARGETS="heating/heating_monitor heating/heating_display heating/boiler_controller"
mkdir -p build/heating

push() {
	f=$1
	h=$2
	sum=$(sha1sum build/$f | awk '{print $1}')
	oldsum=
	if test -f build/.$f.sum; then
		oldsum=$(cat build/.$f.sum)
	fi
	if test -f build/$f.sum -a "$sum" = "$oldsum"; then
		echo $f is unchanged
		return
	fi
	ssh heating@$h "test -f $INSTALL/$f && mv -f $INSTALL/$f $INSTALL/$f.old || true"
	scp -C build/$f heating@$h:$INSTALL/$f
	ssh heating@$h chmod 0755 $INSTALL/$f
	echo $sum >build/.$f.sum
	echo "copied $f to $h"
}

mkdir -p build

for t in $TARGETS; do
	nim c $OPTS --out:build/$t $t.nim
done

push heating_monitor heating
push heating_display heating
push boiler_controller boiler
