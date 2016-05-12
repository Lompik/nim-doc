import json
import strutils
import os
import osproc
import nre
import tables

type symbol_type = enum
  skConst=0, skIterator, skLet, skProc, skTemplate, skType, skVar, skMacro, skConverter
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


var  tmpname = getTempDir().joinPath("jjjjjiiii516516156161")
proc parse_symb_json(n_json:JsonNode, module:string)=
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


    if(n_json[i].haskey("description")):
      writeFile(tmpname,n_json[i]["description"].str)
      output &= execProcess( @["/usr/bin/pandoc","-f","html","-t","texinfo", tmpname].join(" "),
                        @[] ).replace("@node Top","").replace("@top Top","").replace(re"@ref{.*?,(.*?)}","\1")
      tmpname.removeFile()
      discard system.open(tmpname, fmWrite)

    #let id = (symbols[stype])[0]
    symbols[stype][2] = symbols[stype][2] & output

proc Main()=
  var chapters = ""
  var modules : seq[string] = @[]
  var modulei : seq[string] = @[]
  var json_dir = commandLineParams()[0]
  for file in walkDirRec(json_dir ):
    var (mpath, module, ext) = splitFile(file)
    if ext != ".json":
      continue
    var n_json = json.parseFile(file)
    if len(n_json) == 0:
      continue
    var mod1 = mpath.split(json_dir)
    module = mod1[mod1.len - 1] & "/" & module
    modulei.add(module)
    modules.add("* " & module & "::\n")
    chapters &= "\n@node $1\n" % module

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


  echo """@settitle The Nim Reference Manual
@ifnottex
@node Top
@top Nim info Manual
@end ifnottex
@defindex it

@menu
"""
  echo modules.join("")
  echo """

* Function Index:: Procedures, Macros and Templates
* Iterator Index:: Iterators
* Variable Index:: Variables
* Type Index:: Types
@end menu

hello!
"""
  echo chapters

  echo """
@node Function Index
@unnumbered Function index

@printindex fn

@node Iterator Index
@unnumbered Iterator index

@printindex it

@node Variable Index
@unnumbered Variable index

@printindex vr

@node Type Index
@unnumbered Type index

@printindex tp

"""
Main()

# Local Variables:
# firestarter: "nim c -d:release %f || notify-send -u low 'nim' 'compile error on %f'"
# End:
