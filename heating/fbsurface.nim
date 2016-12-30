##
## Framebuffer drawing surface
##
import linuxfb, posix, system, os
import strutils

type
  fb_surface* = tuple [
    fd: cint,             ## file descriptor for /dev/fd?
    fbmem: pointer,       ## base of mmaped frame buffer
    xres: uint32,           ## visible x width (pixels)
    yres: uint32,           ## visible height
    stride: uint32,          ## stride (pixels)
    bytes_per_pixel: uint32,
    size: uint32,            ## framebuffer size
    mapped_len: uint32
  ]

proc create_fb_surface*(devname: string) : fb_surface =
  ## Map the framebuffer device into memory

  let fd = open(devname, O_RDWR)
  if fd < 0:
    raiseOSError(OSErrorCode(errno), "could not open framebuffer " & devname)

  var fix_info: fb_fix_screeninfo
  var rc = ioctl(fd, FBIOGET_FSCREENINFO, addr fix_info)
  if rc < 0:
    raiseOSError(OSErrorCode(errno), "could not get fixed screeninfo for " & devname)

  var var_info: fb_var_screeninfo
  rc = ioctl(fd, FBIOGET_VSCREENINFO, addr var_info)
  if rc < 0:
    raiseOSError(OSErrorCode(errno), "could not get variable screeninfo for " & devname)

  result.mapped_len = fix_info.smem_len
  result.xres = var_info.xres
  result.yres = var_info.yres
  result.stride = var_info.xres
  result.bytes_per_pixel = var_info.bits_per_pixel div 8
  echo "$1 bits per pixel" % [$var_info.bits_per_pixel]
  result.size = result.stride * result.yres * result.bytes_per_pixel # ignore stride for now
  doAssert(result.size <= result.mapped_len)
  result.fd = fd

  let p = mmap(nil, int(result.mapped_len), PROT_READ or PROT_WRITE, MAP_SHARED, fd, cint(0))
  echo "mmap returned $1" % [toHex(cast[int](p))]
  if p == nil or p == cast[pointer](MAP_FAILED):
    raiseOSError(OSErrorCode(errno), "could not mmap " & $fix_info.smem_len)

  result.fbmem = cast[ptr uint8](p)

proc destroy*(fb: fb_surface) =
  discard munmap(fb.fbmem, int(fb.mapped_len))
  discard close(fb.fd)

proc blit*(fb: fb_surface, p: pointer) =
  doAssert(fb.fbmem != nil, "mapped fb is NULL")
  copyMem(fb.fbmem, p, csize(fb.size))

proc width*(this: fb_surface): int32 =
  return int32(this.xres)

proc height*(this: fb_surface): int32 =
  return int32(this.yres)

