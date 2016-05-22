import
  os, parsecfg, strutils, streams, sequtils, utils, parseopt2

type
  output_template* = enum
    intro,  introIndex,  item,  example,  chapterDescr,  chapterItemized, nodes,  indexes

type
  output_config* = object
    ignoredPath*: seq[string]
    otemplate*: array[output_template, string]


proc parseConfig*(file:string):output_config=
  var f = newFileStream(file, fmRead)
  for i in output_template:
    result.otemplate[i] = nil
  if f != nil:
    var p: CfgParser
    open(p, f, paramStr(1))
    while true:
      var e = next(p)
      case e.kind
      of cfgEof:
        #echo("EOF!")
        break

      of cfgSectionStart:   ## a ``[section]`` has been parsed
        case e.section:
          of "General":
            discard
            #echo "General section!"
          of "Template":
            discard
            #echo "theme secton"
          else:
            discard
            #echo "Ignoring section: " & e.section

      of cfgKeyValuePair:
        case e.key:
          of "IgnoredPaths":
            result.ignoredPath = e.value.split(",").map(stripString).filter(isSomeString)
          of "intro":
            result.otemplate[intro] = e.value
          of "introIndex":
            result.otemplate[introIndex] = e.value
          of "item":
            result.otemplate[item] = e.value
          of "example":
            result.otemplate[example] = e.value
          of "chapterDescr":
            result.otemplate[chapterDescr] = e.value
          of "nodes":
            result.otemplate[nodes] = e.value
          of "chapterItemized":
            result.otemplate[chapterItemized] = e.value
          of "indexes":
            result.otemplate[indexes] = e.value
          else:
            echo "Ignoring Key: " & e.key
      of cfgOption:
        echo("Ignoring command: " & e.key & ": " & e.value)
      of cfgError:
        echo(e.msg)

    for i in output_template:
      if result.otemplate[i].isNil:
        echo "Error in config file! Missing key: " & $i
        quit 1

    close(p)

  else:
    echo("cannot open: " & paramStr(1))

proc parseCmd*():tuple[libd:string, conff:string]=
  var
    config_filename = "config/nimtexi.cfg"
    lib_dir : string = ""
  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      lib_dir = key
    of cmdLongOption, cmdShortOption:
      case key:
        of "config", "c":
          config_filename=val
        else :
          discard
    of cmdEnd: assert(false) # cannot happen
  if lib_dir == "":
    # no config_filename has been given, so we show the help:
    echo "Need nim's library directory!"
  else:
    result = (lib_dir, config_filename)


when isMainModule:
  let c = parseConfig(paramStr(1))
  echo c.ignoredPath
  echo c.otemplate[intro]
  echo "---"
  echo $indexes
  echo output_template.low
  echo c.otemplate[chapterItemized]
  echo "---"
  echo c.otemplate[chapterItemized] % ["this is first", "item1"]
  echo "---"
  echo c.otemplate[chapterItemized].format(["this is first", "item1"])
