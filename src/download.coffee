
async = require 'async'
fs = require 'fs'
needle = require 'needle'
time = require 'time'
flatten = require 'flatten'
printf = require 'printf'

TOKEN_URL = 'https://seg-web.nict.go.jp/wsdb_osndisk/shareDirDownload/bDw2maKV'
SEARCH_URL = 'https://seg-web.nict.go.jp/wsdb_osndisk/fileSearch/search'
DOWNLOAD_URL = 'https://seg-web.nict.go.jp/wsdb_osndisk/fileSearch/download'

getRequestCredentials = (callback) ->
  pattern = /\W+var FIXED_TOKEN = "(.*)";/g
  opts =
    follow_set_cookies: true
    follow_set_referer: true
    follow_max: 10
  cb = (error, result) ->
    callback? error, result
    callback = null
  needle.get TOKEN_URL, opts, (error, response) ->
    unless error?
      rv =
        'Cookie': response.req._headers.cookie
        'HashToken': 'bDw2maKV'
      if match = pattern.exec response.body
        rv['X-CSRFToken'] = match[1]
    callback error, rv

getFileList = (searchPath, searchStr, credentials, callback) ->
  data = {searchPath, searchStr, action: 'dir_download_dl'}
  opts = {headers: credentials}
  needle.post SEARCH_URL, data, opts, (error, response, result) ->
    if response? and response.statusCode isnt 200
      error ?= new Error "HTTP: #{ response.statusCode }"
    callback error, result

getFileStream = (path, credentials) ->
  data =
    '_method': 'POST'
    'data[FileSearch][is_compress]': 'false',
    'data[FileSearch][fixedToken]': credentials['X-CSRFToken']
    'data[FileSearch][hashUrl]': credentials['HashToken']
    'action': 'dir_download_dl'
    'dl_path': path
    'filelist[0]': path
  opts = {headers: credentials}
  return needle.post DOWNLOAD_URL, data, opts

class SearchResult

  constructor: (@name, @dir, @size, @date, @_credentials) ->

  getPath: -> "#{ @dir }/#{ @name }"

  getStream: -> getFileStream @getPath(), @_credentials

  inspect: -> {@name, @size, date: @date.toString()}


dayCount = (year, month) -> new Date(year, month, 0).getDate()

SearchResult.fromFileResponse = (response, credentials) ->
  [type, name, size, dateStr, dir] = response
  if type isnt 'file'
    throw new Error "Unable to handle response of type: #{ type }"
  date = new time.Date dateStr, 'Asia/Tokyo'
  return new SearchResult name, dir, size, date, credentials

getFullMonth = (year, month, hour, callback) ->
  numDays = dayCount year, month
  getRequestCredentials (error, credentials) ->
    unless error?
      rv = [1..numDays].map (day) ->
        name = printf 'hima8%d%02d%02d%02d0000fd.png', year, month, day, hour
        dir = '/osn-disk/webuser/wsdb/share_directory/bDw2maKV/png/Pifd'
        dir += printf '/%d/%02d-%02d/%02d/', year, month, day, hour
        date = new time.Date year, month - 1, day, 'Asia/Tokyo'
        return new SearchResult name, dir, 0, date, credentials
    callback error, rv

searchDay = (date, callback) ->
  tzDate = new time.Date date
  tzDate.setTimezone 'Asia/Tokyo'

  year = tzDate.getFullYear()
  month = tzDate.getMonth() + 1
  day = tzDate.getDate()

  listDay = (callback, shared) ->
    dir = printf 'png/Pifd/%d/%02d-%02d/', year, month, day
    getFileList dir, '*', shared.credentials, (error, result) ->
      unless error?
        rv = result.searchList
          .filter (item) -> item[0] is 'directory'
          .map (item) -> dir + item[1]
      callback error, rv

  listFiles = (callback, shared) ->
    listFile = (dir, callback) ->
      getFileList dir, '*.png', shared.credentials, callback
    async.map shared.dirs, listFile, callback

  async.auto
    credentials: getRequestCredentials
    dirs: ['credentials', listDay]
    files: ['credentials', 'dirs', listFiles]
  , (error, result) ->
    unless error?
      rv = flatten result.files.map (item) ->
        item.searchList.map (response) ->
          SearchResult.fromFileResponse response, result.credentials
    callback error, rv

# getFullMonth 2016, 1, 12, (error, results) ->
#   throw error if error?
#   saveResult = (result, callback) ->
#     fname = 'noon-jan/' + result.name
#     console.log "Starting #{ fname }"
#     cb = (error) ->
#       console.log "Finished #{ fname }"
#       if error?
#         console.log "ERROR #{ fname }: #{ error.message }"
#         fs.unlinkSync fname
#       callback?()
#       callback = null
#     dst = fs.createWriteStream fname
#     dst.on 'error', cb
#     dst.on 'close', cb
#     src = result.getStream()
#     src.on 'error', cb
#     src.pipe dst
#   async.mapLimit results, 4, saveResult, (error) ->
#     throw error if error?
#     console.log "Saved #{ results.length } files"
