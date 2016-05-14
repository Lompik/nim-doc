import json
import strutils
import os
import osproc
import nre
import options
import tables
import posix

import nim_JsonWithTexi

type symbol_type = enum
  skConst=0, skIterator, skLet, skProc, skTemplate, skType, skVar, skMacro, skConverter

let indexv= @["Variable", "Type", "Procedures", "Iterator"]
let index_type = {"Variable": ("@vindex","vr"), "Procedures": ("@findex","fn"), "Iterator": ("@itindex","it"), "Type":("@tpindex", "tp")}.totable

var symbols, symbols_empty = {
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

let htmlcodes : seq[tuple[utf8:string, code:string]]=
  @[("<", "&lt;"),
    (">", "&gt;"),
    ("&", "&amp;"),
    ("\"", "&quot;"),
    ("\'", "&#x27;"),
    ("/", "&#x2F;")]


proc texize(txt:string):string=
  result=txt
  if txt[0] in @[ '`' , '\''] or txt.find("&") != -1:
    for htmlcode in htmlcodes:
     result = result.replace(htmlcode.code,htmlcode.utf8)
  result=result.replace("@", "@@").replace("}","@}").replace("{","@{")

proc check_posix(c:auto, fr:PFrame=nil)=
  if c == -1:
    if fr != nil:
      writestackTrace()
      echo "Error in Posix call at line: " & $fr.line
      quit 1
    else:
      echo "Error in Posix call at line: "
      quit 1

proc parse_symb_json(n_json:JsonNode, module:string)=
  var  tmpname = getTempDir().joinPath("jjjjjiiii516516156161")
  var tmpfile = posix.open(tmpname, posix.O_RDWR or posix.O_CREAT, posix.S_IRWXU)
  check_posix(tmpfile)

  symbols=symbols_empty
  for i in countUp(0,n_json.len- 1):
    var output="\n\n"
    var stype = n_json[i]["type"].str
    output &= """
@item $1
  """ % [n_json[i]["name"].str.texize]
    output &= "$1 $2\n" % [(symbols[stype])[1],n_json[i]["code"].str.texize, module]

    if(n_json[i].haskey("code")):
      output &= """
@example
$1
@end example
  """ % n_json[i]["code"].str.texize


    if(n_json[i].haskey("description") and n_json[i]["description"].str.strip != ""):
      if(defined(usePandoc)):
        check_posix(tmpfile.ftruncate(0))
        check_posix(posix.write(tmpfile,addr n_json[i]["description"].str[0], n_json[i]["description"].str.len))
        output &= execProcess( @["/usr/bin/pandoc","-f","html","-t","texinfo", tmpname].join(" "),
                          @[] ).replace("@node Top","").replace("@top Top","").replace(re"@ref{.*?,(.*?)}","\1")
      else:
        output &= n_json[i]["description"].str.strip
    #let id = (symbols[stype])[0]
    symbols[stype][2] = symbols[stype][2] & output
  discard tmpfile.close()
  tmpname.removeFile()

let anchor = ""
let anchorre = re" (?<index>\d+)"

proc Main()=
  var chapters = ""
  var modules : seq[string] = @[]
  var modulei : seq[string] = @[]
  var json_dir = commandLineParams()[0]
  var i = -1
  for file in walkDirRec(json_dir ):
    var (mpath, module, ext) = splitFile(file)
    if ext != ".nim":
      continue

    var n_json: JsonNode
    try:
      n_json = nim_JsonWithTexi.parseNim(file)
    except:
      continue
    if len(n_json) == 0:
      continue
    i+=1
    var mod1 = mpath.split(json_dir)
    module = mod1[mod1.len - 1] & "/" & module
    modulei.add(module)
    modules.add("* " & module & "::\n")
    chapters &= "\n@node $1, $2 $3\n" % [module, anchor, $i]

    parse_symb_json(n_json, module)

    for stype in symbols.keys:
      if symbols[stype][2] != "":
         symbols[stype][2] ="""
@chapter $1

@itemize
$2
@end itemize
""" % [symbols[stype][3], symbols[stype][2]]

    chapters &= @[symbols["skConst"][2],
                  symbols["skLet"][2],
                  symbols["skVar"][2],
                  symbols["skType"][2],
                  symbols["skProc"][2],
                  symbols["skTemplate"][2],
                  symbols["skMacro"][2],
                  symbols["skConverter"][2],
                  symbols["skMethod"][2],
                  symbols["skIterator"][2]].join("\n")
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
  echo """@documentencoding UTF-8
@settitle The Nim Reference Manual
@ifnottex
@node Top
@top Nim info Manual
@end ifnottex
@defindex it

@menu
"""
  echo modules.join("")
  echo """

* Variable Index:: Variables
* Type Index:: Types
* Procedures Index:: Procedures, Macros and Templates
* Iterator Index:: Iterators
@end menu

hello!
"""
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
    echo """
@node $1 Index, $3, $4, Top
@unnumbered $1 Index

@printindex $2

""" % [key, index_type[key][1], next, prev]
Main()

# Local Variables:
# firestarter: "nim c -d:release %f || notify-send -u low 'nim' 'compile error on %f'"
# End:
