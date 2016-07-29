import json
import strutils
import os
import osproc
import nre
import options
import tables
import posix

import nim_JsonWithTexi, config

type symbol_type = enum
  skConst=0, skIterator, skLet, skProc, skTemplate, skType, skVar, skMacro, skConverter, moduleDesc
const
  s_en=0
  s_index=1
  s_data=2
  s_printname=3

let indexv= @["Variable", "Type", "Procedures", "Iterator"]
let index_type = {"Variable": ("@vindex","vr"), "Procedures": ("@findex","fn"), "Iterator": ("@itindex","it"), "Type":("@tpindex", "tp")}.totable

var symbols, symbols_empty = {
  "moduleDesc": (moduleDesc,"","","Module Description"),
  "skConst": (skConst,"@vindex","","Constant variables"),
  "skIterator": (skIterator,"@itindex","","Iterators"),
  "skLet": (skLet,"@vindex","","Let variable"),
  "skProc": (skProc,"@findex","","Procedures"),
  "skTemplate": (skTemplate,"@findex","","Templates"),
  "skType": (skType,"@tindex","","Types"),
  "skMacro": (skMacro,"@findex","","Macros"),
  "skConverter": (skConverter,"@findex","","Converter"),
  "skMethod": (skConverter,"@findex","","Methods"),
  "skVar": (skVar,"@vindex","","Variables")}.totable

proc texize(txt:string):string=
  txt.replace("@", "@@").replace("}","@}").replace("{","@{")

proc check_posix(c:auto, fr:PFrame=nil)=
  if c == -1:
    if fr != nil:
      writestackTrace()
      echo "Error in Posix call at line: " & $fr.line
      quit 1
    else:
      echo "Error in Posix call at line: "
      quit 1

proc parse_symb_json(n_json:JsonNode, module:string, oconfig: output_config)=
  var  tmpname = getTempDir().joinPath("jjjjjiiii516516156161")
  var tmpfile = posix.open(tmpname, posix.O_RDWR or posix.O_CREAT, posix.S_IRWXU)
  check_posix(tmpfile)

  symbols=symbols_empty
  for i in countUp(0,n_json.len- 1):
    var output="\n\n"
    if n_json[i].haskey("moduledesc"):
      symbols["moduleDesc"][s_data] = n_json[i]["moduledesc"].str & "\n"
      continue
    var stype = n_json[i]["type"].str
    output &= oconfig.otemplate[item] % [n_json[i]["name"].str.texize]
    output &= "$1 $2\n" % [(symbols[stype])[1],n_json[i]["code"].str.texize, module]

    if(n_json[i].haskey("code")):
      output &= oconfig.otemplate[example] % n_json[i]["code"].str.texize


    if(n_json[i].haskey("description") and n_json[i]["description"].str.strip != ""):
      output &= n_json[i]["description"].str.strip
    #let id = (symbols[stype])[0]
    symbols[stype][s_data] = symbols[stype][s_data] & output
  discard tmpfile.close()
  tmpname.removeFile()

let anchor = ""
let anchorre = re" (?<index>\d+)"

proc set_include_dir*(dir:string):string=
  dir.replace(re"/lib/?$","")

var excluded_dir = @["private"]

proc isFileExcluded(file: tuple[dir, name, ext: string]):bool =
  result = false
  if file.ext != ".nim" :
    return true
  for excluded in excluded_dir:
    if file.dir.find(excluded) != -1:
      return true

proc Main()=
  let (lib_dir, config_file) = parseCmd()
  let oconfig: output_config = config.parseConfig(config_file)
  excluded_dir=oconfig.ignoredPath
  var chapters = ""
  var modules : seq[string] = @[]
  var modulei : seq[string] = @[]

  nim_JsonWithTexi.include_dir = set_include_dir(lib_dir)
  stderr.writeline nim_JsonWithTexi.include_dir
  var i = -1
  for file in walkDirRec(lib_dir ):
    var (mpath, module, ext) = splitFile(file)
    if (mpath, module, ext).isFileExcluded:
      stderr.writeLine "Ignored: "&  [mpath , module & ext].joinPath
      continue
    var n_json: JsonNode
    try:
      n_json = nim_JsonWithTexi.parseNim(file)
    except:
      continue
    if len(n_json) == 0:
      continue
    i+=1
    var mod1 = mpath.split(lib_dir)
    module = mod1[mod1.len - 1] & "/" & module
    modulei.add(module)
    modules.add("* " & module & "::\n")
    chapters &= oconfig.otemplate[nodes] % [module, anchor, $i]

    parse_symb_json(n_json, module, oconfig)

    for stype in symbols.keys:
      if symbols[stype][s_data] != "":
        if stype == "moduleDesc":
          chapters &= oconfig.otemplate[chapterDescr] % [symbols[stype][s_printname], symbols[stype][s_data]]

        else: symbols[stype][s_data] =oconfig.otemplate[chapterItemized] % [symbols[stype][3], symbols[stype][s_data]]

    chapters &= @[symbols["skConst"][s_data],
                  symbols["skLet"][s_data],
                  symbols["skVar"][s_data],
                  symbols["skType"][s_data],
                  symbols["skProc"][s_data],
                  symbols["skTemplate"][s_data],
                  symbols["skMacro"][s_data],
                  symbols["skConverter"][s_data],
                  symbols["skMethod"][s_data],
                  symbols["skIterator"][s_data]].join("\n")
  let max_files=i+1

  proc update_node(match: RegexMatch):string=
    let id = match.captures["index"].parseInt
    if max_files == 1:
      result = indexv[0] & " Index, " & "Top" & ", Top"
    elif id == 0 and max_files>1:
      result = modulei[id+1] & " , Top, Top"
    elif id == modulei.len-1:
      result = indexv[0] & " Index, " & modulei[id-1] & ", Top"
    else:
      result = modulei[id+1] & " , " & modulei[id-1] & ", Top"
  chapters=chapters.replace(anchorre,update_node)
  echo oconfig.otemplate[intro]
  echo modules.join("")
  echo oconfig.otemplate[introIndex]
  echo chapters

  for index, key in indexv.pairs:
    var prev =""
    var next =""
    if(index==0):
      prev=modulei[modulei.len-1]
      next=indexv[index+1]& " Index"
    elif(index == indexv.len - 1):
      prev=indexv[index-1]& " Index"
      next=""
    else:
      prev=indexv[index - 1]& " Index"
      next=indexv[index + 1]& " Index"
    echo oconfig.otemplate[indexes] % [key, index_type[key][1], next, prev]
Main()

# Local Variables:
# firestarter: "nim c -d:release %f || notify-send -u low 'nim' 'compile error on %f'"
# End:
