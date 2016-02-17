
# usage: coffee --nodejs --expose-gc src/process.coffee inputfiles/*.png

async = require 'async'
fs = require 'fs'
path = require 'path'
sharp = require 'sharp'
spiral = require 'spiral-rectangle'

sharp.cache 0

imageSize = 11000
splitPos = 0.473

cloudSteps = 10
cloudTresh = 0.6

spiralSteps = do ->
  s = Math.pow cloudSteps, 2
  f = spiral s, s, 1
  return (f() for _ in [0...cloudSteps])

filenamePattern = /hima8(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})fd.png/

hr2sec = (delta) -> delta[0] + (delta[1] / 1e9)

parseFilename = (filename) ->
  basename = path.basename filename
  if match = filenamePattern.exec basename
    [year, month, day, hour, minute, second] = match[1..].map Number
  return {filename, basename, year, month, day, hour, minute, second}

inputImages = process.argv[2...].map parseFilename

outputImage = new Buffer imageSize * imageSize * 3
outputImage.fill 255

lumaLookup = new Float32Array imageSize * imageSize
lumaLookup.fill 1.0

getLuma = (r, g, b) ->
  # 0.2126*r + 0.7152*g + 0.0722*b
  Math.sqrt 0.299 * Math.pow(r / 255, 2) + 0.587 * Math.pow(g / 255, 2) + 0.114 * Math.pow(b / 255, 2)

processImage = (image, callback) ->
  process.stdout.write "#{ image.basename }... "
  start = process.hrtime()

  x1 = 0
  x2 = imageSize

  # sample multiple exposures, tried with photos taken at 11 and 13, made the resulting earth look egg-shaped
  # x1 = 0
  # x2 = Math.floor imageSize * splitPos
  # if image.hour < 12
  #   x1 = x2
  #   x2 = imageSize

  sharp(image.filename).sequentialRead().raw().toBuffer (error, buffer, info) ->
    if error?
      process.stdout.write "ERROR: #{ error.message }\n"
      callback error
      return
    process.stdout.write "(#{ info.channels }) #{ (hr2sec process.hrtime start).toFixed 2 } -- "
    start = process.hrtime()
    w = info.width
    h = info.height
    d = buffer # d is a buffer of [r,g,b,r,g,b,r,g,b...]
    max = w * h
    for y in [0...h] by 1
      for x in [x1...x2] by 1
        i = w * y + x
        pi = i * 3

        lum = getLuma d[pi], d[pi+1], d[pi+2]

        copy = false
        if lum < lumaLookup[i]
          copy = true
          # some lookaround in an effort to eliminate the shadows left by clouds
          for step in spiralSteps
            ci = w * (y + step[1]) + (x + step[0])
            continue if ci < 0 or ci >= max
            cip = ci * 3
            clum = getLuma d[cip], d[cip+1], d[cip+2]
            if clum > 0.6
              copy = false
              break

        if copy
          outputImage[pi] = d[pi]
          outputImage[pi + 1] = d[pi + 1]
          outputImage[pi + 2] = d[pi + 2]
          lumaLookup[i] = lum

    # had some problems with memory usage growing out of control... run with --expose-gc
    global.gc()

    process.stdout.write "#{ (hr2sec process.hrtime start).toFixed 2 }\n"
    process.nextTick callback
    return
  return

async.forEachSeries inputImages, processImage, (error) ->
  throw error if error?
  console.log "Processed #{ inputImages.length } images."
  console.log "Writing output..."

  opts =
    raw:
      width: imageSize
      height: imageSize
      channels: 3

  sharp outputImage, opts
    .png()
    .toFile 'output.png', (error) ->
      throw error if error?
      console.log 'Done!'
